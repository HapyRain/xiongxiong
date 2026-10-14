## quality_settings.gd
## 画质分档：低/中/高 + 启动探测 + 持久化。注册为 autoload `QualitySettings`。
## 只动表现层（帧率/特效参数/特效层分辨率），不读写 scripts/rules/* 与对局状态。
## 对应 docs/arch/quality-performance-tiers.md §2 §4 §5
extends Node

signal tier_changed(tier: int)
signal settings_applied(tier: int)

enum Tier { LOW = 0, MID = 1, HIGH = 2 }

const SETTINGS_PATH := "user://settings.cfg"
const SECTION := "quality"
const TIER_NAMES: Array[String] = ["低", "中", "高"]

# 三档配置表（§5.1）。特效层 scale 供 SubViewport.size_2d_override 使用。
const CONFIG := {
	Tier.LOW: {
		"fps_target": 30,
		"vsync_mode": DisplayServer.VSYNC_ENABLED,
		"particle_scale": 0.3,
		"max_fx_instances": 2,
		"glow_enabled": false,
		"post_process_count": 0,
		"fx_viewport_scale": 0.5,
		"shader_complexity": 0,          # 0=modulate, 1=基础UV, 2=流光/扭曲
		"tween_duration_scale": 0.75,    # <1 缩短动效时长
		"fxaa": true,
		"light2d_shadows": false,
	},
	Tier.MID: {
		"fps_target": 60,
		"vsync_mode": DisplayServer.VSYNC_ENABLED,
		"particle_scale": 0.7,
		"max_fx_instances": 5,
		"glow_enabled": true,
		"post_process_count": 1,
		"fx_viewport_scale": 0.75,
		"shader_complexity": 1,
		"tween_duration_scale": 1.0,
		"fxaa": false,
		"light2d_shadows": false,
	},
	Tier.HIGH: {
		"fps_target": 120,               # 运行时用 FpsGuard.resolve_high_fps() 压到 90/120
		"vsync_mode": DisplayServer.VSYNC_ENABLED,
		"particle_scale": 1.0,
		"max_fx_instances": 12,
		"glow_enabled": true,
		"post_process_count": 3,
		"fx_viewport_scale": 1.0,
		"shader_complexity": 2,
		"tween_duration_scale": 1.0,
		"fxaa": false,
		"light2d_shadows": true,
	},
}

# ---- 当前状态 ----
var tier: int = Tier.MID
var auto_preset: bool = true          # true=启动自动预设；false=玩家手动
var fps_cap_override: int = 0         # 0=跟随档位；否则强制分段帧率
var device_probe: Dictionary = {}
var last_applied: Dictionary = {}

# 特效层降采样挂点（预留；主场景暂无特效 SubViewport 时为空）
var _fx_viewports: Array[SubViewport] = []


func _ready() -> void:
	load_settings()
	apply()
	_inject_settings_button()


## 主场景可不改逻辑：由 autoload 在角落挂一个齿轮入口。
func _inject_settings_button() -> void:
	if DisplayServer.get_name() == "headless":
		return
	# 对局场景由「菜单」入口打开同一设置面板，避免双按钮叠在右上角
	var scene_path := ""
	if get_tree() != null and get_tree().current_scene != null:
		scene_path = str(get_tree().current_scene.scene_file_path)
	if scene_path.ends_with("main.tscn") or scene_path.ends_with("net_battle.tscn"):
		return
	var layer := CanvasLayer.new()
	layer.name = "SettingsEntryLayer"
	layer.layer = 50
	add_child(layer)

	var btn := Button.new()
	btn.name = "SettingsButton"
	btn.text = "⚙"
	btn.tooltip_text = "画质 / 帧率设置"
	# 贴最右，给对局内「菜单」留出左侧位置，避免重叠
	btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	btn.offset_left = -44
	btn.offset_top = 8
	btn.offset_right = -8
	btn.offset_bottom = 40
	btn.add_theme_font_size_override("font_size", 16)
	btn.pressed.connect(_open_settings_panel)
	layer.add_child(btn)


func _open_settings_panel() -> void:
	var tree := get_tree()
	if tree == null:
		return
	# 避免重复打开
	var existing := tree.root.get_node_or_null("SettingsPanelOverlay")
	if existing != null:
		return
	var panel_scene: PackedScene = load("res://scenes/settings_panel.tscn")
	if panel_scene == null:
		return
	var overlay := panel_scene.instantiate()
	overlay.name = "SettingsPanelOverlay"
	tree.root.add_child(overlay)


# ---------- 对外 API ----------

func get_config(t: int = -1) -> Dictionary:
	if t < 0:
		t = tier
	return CONFIG.get(t, CONFIG[Tier.MID])


func tier_name(t: int = -1) -> String:
	if t < 0:
		t = tier
	if t >= 0 and t < TIER_NAMES.size():
		return TIER_NAMES[t]
	return "中"


## 目标帧率：高档自适配刷新率；可被 fps_cap_override 覆盖。
func get_target_fps() -> int:
	if fps_cap_override > 0:
		return FpsGuard.snap_to_segment(fps_cap_override)
	var c := get_config()
	var base := int(c["fps_target"])
	if tier == Tier.HIGH:
		base = FpsGuard.resolve_high_fps()
	return FpsGuard.snap_to_segment(base)


## 玩家手动切档并持久化。
func set_tier(t: int, manual: bool = true) -> void:
	t = clampi(t, Tier.LOW, Tier.HIGH)
	var changed := t != tier
	tier = t
	if manual:
		auto_preset = false
	if changed:
		tier_changed.emit(tier)
	apply()
	save_settings()


## 恢复自动预设（重跑探测）。
func restore_auto() -> void:
	device_probe = probe_device()
	tier = int(device_probe.get("auto_tier", Tier.MID))
	auto_preset = true
	fps_cap_override = 0
	tier_changed.emit(tier)
	apply()
	save_settings()


## 立即应用当前档位到引擎 / 特效层。
func apply() -> void:
	var c := get_config()
	var applied_fps := FpsGuard.apply(get_target_fps(), int(c["vsync_mode"]))

	# 特效层 SubViewport 降采样（UI 层不进 SubViewport，保持全分辨率）
	var fx_scale := float(c["fx_viewport_scale"])
	for vp in _fx_viewports:
		if not is_instance_valid(vp):
			continue
		_apply_fx_viewport(vp, fx_scale)

	last_applied = {
		"tier": tier,
		"fps": applied_fps,
		"fx_viewport_scale": fx_scale,
		"particle_scale": float(c["particle_scale"]),
		"max_fx_instances": int(c["max_fx_instances"]),
		"glow_enabled": bool(c["glow_enabled"]),
		"post_process_count": int(c["post_process_count"]),
		"shader_complexity": int(c["shader_complexity"]),
		"tween_duration_scale": float(c["tween_duration_scale"]),
		"auto_preset": auto_preset,
	}
	settings_applied.emit(tier)


# ---------- 特效层挂载（预留 SubViewport 降采样） ----------

func register_fx_viewport(vp: SubViewport) -> void:
	if vp == null or _fx_viewports.has(vp):
		return
	_fx_viewports.append(vp)
	_apply_fx_viewport(vp, float(get_config()["fx_viewport_scale"]))


func unregister_fx_viewport(vp: SubViewport) -> void:
	_fx_viewports.erase(vp)


func _apply_fx_viewport(vp: SubViewport, scale: float) -> void:
	# UI 不缩放：只缩特效渲染目标。scale≈0.5 → 填充约 1/4。
	var base := vp.size
	if base.x <= 0 or base.y <= 0:
		base = Vector2i(390, 820)
	var target := Vector2i(
		maxi(1, int(round(float(base.x) * scale))),
		maxi(1, int(round(float(base.y) * scale)))
	)
	vp.size_2d_override = target
	vp.size_2d_override_stretch = true


# ---------- 启动探测启发式（§4.2） ----------

func probe_device() -> Dictionary:
	var mem := OS.get_memory_info()
	var physical_mb := 0
	if typeof(mem) == TYPE_DICTIONARY and mem.has("physical"):
		physical_mb = int(mem["physical"]) / (1024 * 1024)
	var cores := OS.get_processor_count()
	var refresh := FpsGuard.get_refresh_rate()
	var gpu := ""
	if RenderingServer.get_video_adapter_name():
		gpu = RenderingServer.get_video_adapter_name()

	var score := 0
	# RAM 权重高
	if physical_mb > 0:
		if physical_mb < 3 * 1024:
			score += 1
		elif physical_mb <= 5 * 1024:
			score += 2
		else:
			score += 3
	else:
		score += 2  # 读不到就按中端

	# 刷新率
	if refresh >= 90.0:
		score += 2
	elif refresh >= 60.0:
		score += 1

	# CPU 核数
	if cores <= 4:
		score += 1
	elif cores <= 8:
		score += 2
	else:
		score += 3

	# GPU 黑名单一票否决 / 白名单抬升
	var gpu_l := gpu.to_lower()
	if gpu_l != "":
		for bad: String in ["mali-4", "mali-450", "adreno 5", "adreno 3", "powervr", "intel hd graphics"]:
			if gpu_l.contains(bad):
				score = mini(score, 2)
				break
		for good: String in ["adreno 7", "adreno 6", "mali-g7", "mali-g8", "xclipse", "apple gpu", "rtx", "radeon"]:
			if gpu_l.contains(good):
				score += 2
				break

	var auto_tier: int
	if score >= 8:
		auto_tier = Tier.HIGH
	elif score >= 5:
		auto_tier = Tier.MID
	else:
		auto_tier = Tier.LOW

	return {
		"physical_mb": physical_mb,
		"cpu_cores": cores,
		"refresh_rate": refresh,
		"gpu_name": gpu,
		"os_name": OS.get_name(),
		"score": score,
		"auto_tier": auto_tier,
	}


# ---------- 持久化 user://settings.cfg ----------

func save_settings() -> void:
	var cf := ConfigFile.new()
	cf.set_value(SECTION, "tier", tier)
	cf.set_value(SECTION, "auto_preset", auto_preset)
	cf.set_value(SECTION, "fps_cap", fps_cap_override)
	cf.set_value(SECTION, "updated_at", Time.get_datetime_string_from_system())
	var p := device_probe
	cf.set_value(SECTION, "probe_auto_tier", int(p.get("auto_tier", Tier.MID)))
	cf.set_value(SECTION, "probe_score", int(p.get("score", 0)))
	cf.set_value(SECTION, "probe_refresh", float(p.get("refresh_rate", 0.0)))
	cf.set_value(SECTION, "probe_ram_mb", int(p.get("physical_mb", 0)))
	cf.set_value(SECTION, "probe_cores", int(p.get("cpu_cores", 0)))
	cf.set_value(SECTION, "probe_gpu", str(p.get("gpu_name", "")))
	# 先写临时文件再替换，减半写损坏
	var tmp := SETTINGS_PATH + ".tmp"
	var err := cf.save(tmp)
	if err == OK:
		var dir := DirAccess.open("user://")
		if dir != null:
			if FileAccess.file_exists(SETTINGS_PATH):
				dir.remove(SETTINGS_PATH)
			dir.rename(tmp, SETTINGS_PATH)
	else:
		cf.save(SETTINGS_PATH)


func load_settings() -> void:
	device_probe = probe_device()
	var cf := ConfigFile.new()
	var err := cf.load(SETTINGS_PATH)
	if err != OK:
		# 首次启动：自动预设
		tier = int(device_probe.get("auto_tier", Tier.MID))
		auto_preset = true
		fps_cap_override = 0
		save_settings()
		return

	var saved_tier := int(cf.get_value(SECTION, "tier", Tier.MID))
	var saved_auto := bool(cf.get_value(SECTION, "auto_preset", true))
	tier = clampi(saved_tier, Tier.LOW, Tier.HIGH)
	auto_preset = saved_auto
	fps_cap_override = int(cf.get_value(SECTION, "fps_cap", 0))

	# 玩家手动档优先；无手动档则用本次探测结果
	if auto_preset:
		tier = int(device_probe.get("auto_tier", Tier.MID))

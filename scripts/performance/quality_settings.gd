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
		"shader_complexity": 0,
		"tween_duration_scale": 0.75,
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
		"fps_target": 120,
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
var auto_preset: bool = true
var fps_cap_override: int = 0
var device_probe: Dictionary = {}
var last_applied: Dictionary = {}

var _fx_viewports: Array[SubViewport] = []
var _entry_layer: CanvasLayer = null
var _last_scene: Node = null


func _ready() -> void:
	load_settings()
	apply()
	_inject_settings_button()


func _process(_delta: float) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var tree := get_tree()
	if tree == null:
		return
	if tree.current_scene != _last_scene:
		_last_scene = tree.current_scene
		_try_attach_settings_btn()


## 主场景可不改逻辑：由 autoload 在角落挂一个设置入口，但对局场景与主菜单（自带菜单/设置键）自动隐藏，杜绝右上角叠按钮 Bug。
func _inject_settings_button() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var tree := get_tree()
	if tree == null:
		return
	if not tree.node_added.is_connected(_on_node_added_for_settings):
		tree.node_added.connect(_on_node_added_for_settings)
	_try_attach_settings_btn()


func _on_node_added_for_settings(_n: Node) -> void:
	_try_attach_settings_btn.call_deferred()


func _try_attach_settings_btn() -> void:
	var tree := get_tree()
	if tree == null or tree.root == null:
		return
	var scene_path := ""
	var scene_name := ""
	if tree.current_scene != null:
		scene_path = str(tree.current_scene.scene_file_path)
		scene_name = str(tree.current_scene.name)
	# 对局场景（main / net_battle）与主菜单（menu）均自带「菜单/设置」按钮，隐藏常驻浮动设置键，彻底消除右上角重合
	var should_hide := (
		scene_path.ends_with("main.tscn")
		or scene_path.ends_with("net_battle.tscn")
		or scene_path.ends_with("menu.tscn")
		or scene_name in ["Main", "NetBattle", "Menu"]
		or tree.root.get_node_or_null("Main") != null
		or tree.root.get_node_or_null("NetBattle") != null
	)
	var existing := tree.get_first_node_in_group(UiNav.SETTINGS_ENTRY_GROUP) as Control
	if existing != null:
		existing.visible = not should_hide
		if _entry_layer != null and is_instance_valid(_entry_layer):
			_entry_layer.visible = not should_hide
		return
	if should_hide:
		return

	_entry_layer = CanvasLayer.new()
	_entry_layer.name = "SettingsEntryLayer"
	_entry_layer.layer = 50
	add_child(_entry_layer)

	var btn := Button.new()
	btn.name = "SettingsButton"
	btn.add_to_group(UiNav.SETTINGS_ENTRY_GROUP)
	btn.text = "设置"
	btn.tooltip_text = "画质 / 帧率设置"
	btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	btn.offset_left = -148
	btn.offset_top = 20
	btn.offset_right = -24
	btn.offset_bottom = 92
	btn.add_theme_font_size_override("font_size", 30)
	btn.pressed.connect(_open_settings_panel)
	_entry_layer.add_child(btn)


func _open_settings_panel() -> void:
	var tree := get_tree()
	if tree == null:
		return
	if UiNav.is_settings_open(tree):
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


func get_target_fps() -> int:
	if fps_cap_override > 0:
		return FpsGuard.snap_to_segment(fps_cap_override)
	var c := get_config()
	var base := int(c["fps_target"])
	if tier == Tier.HIGH:
		base = FpsGuard.resolve_high_fps()
	return FpsGuard.snap_to_segment(base)


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


func restore_auto() -> void:
	device_probe = probe_device()
	tier = int(device_probe.get("auto_tier", Tier.MID))
	auto_preset = true
	fps_cap_override = 0
	tier_changed.emit(tier)
	apply()
	save_settings()


func apply() -> void:
	var c := get_config()
	var applied_fps := FpsGuard.apply(get_target_fps(), int(c["vsync_mode"]))

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


# ---------- 特效层挂载 ----------

func register_fx_viewport(vp: SubViewport) -> void:
	if vp == null or _fx_viewports.has(vp):
		return
	_fx_viewports.append(vp)
	_apply_fx_viewport(vp, float(get_config()["fx_viewport_scale"]))


func unregister_fx_viewport(vp: SubViewport) -> void:
	_fx_viewports.erase(vp)


func _apply_fx_viewport(vp: SubViewport, scale: float) -> void:
	var base := vp.size
	if base.x <= 0 or base.y <= 0:
		base = Vector2i(1080, 1920)
	var target := Vector2i(
		maxi(1, int(round(float(base.x) * scale))),
		maxi(1, int(round(float(base.y) * scale)))
	)
	vp.size_2d_override = target
	vp.size_2d_override_stretch = true


# ---------- 启动探测启发式 ----------

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
	if physical_mb > 0:
		if physical_mb < 3 * 1024:
			score += 1
		elif physical_mb <= 5 * 1024:
			score += 2
		else:
			score += 3
	else:
		score += 2

	if refresh >= 90.0:
		score += 2
	elif refresh >= 60.0:
		score += 1

	if cores <= 4:
		score += 1
	elif cores <= 8:
		score += 2
	else:
		score += 3

	var gpu_l := gpu.to_lower()
	if gpu_l != "":
		if _match_any(gpu_l, ["adreno 7", "adreno (tm) 7", "immortalis", "mali-g7", "mali-g8", "apple a1", "apple m", "rtx", "radeon rx"]):
			score += 3
		elif _match_any(gpu_l, ["adreno 6", "adreno (tm) 6", "mali-g5", "mali-g6", "gtx", "iris", "uhd"]):
			score += 2
		elif _match_any(gpu_l, ["adreno 5", "mali-t", "mali-4", "powervr"]):
			score += 1
		else:
			score += 2
	else:
		score += 2

	var auto_t := Tier.MID
	if score <= 4:
		auto_t = Tier.LOW
	elif score >= 8:
		auto_t = Tier.HIGH

	return {
		"physical_mb": physical_mb,
		"cpu_cores": cores,
		"refresh_rate": refresh,
		"gpu_name": gpu,
		"os_name": OS.get_name(),
		"score": score,
		"auto_tier": auto_t,
	}


static func _match_any(hay: String, needles: Array) -> bool:
	for n in needles:
		if hay.find(str(n)) >= 0:
			return true
	return false


# ---------- 持久化 ----------

func load_settings() -> void:
	device_probe = probe_device()
	var default_tier := int(device_probe["auto_tier"])
	var cf := ConfigFile.new()
	if cf.load(SETTINGS_PATH) != OK:
		tier = default_tier
		auto_preset = true
		fps_cap_override = 0
		return
	auto_preset = bool(cf.get_value(SECTION, "auto_preset", true))
	fps_cap_override = int(cf.get_value(SECTION, "fps_cap", 0))
	if auto_preset:
		tier = default_tier
	else:
		tier = clampi(int(cf.get_value(SECTION, "tier", default_tier)), Tier.LOW, Tier.HIGH)


func save_settings() -> void:
	var cf := ConfigFile.new()
	cf.set_value(SECTION, "tier", tier)
	cf.set_value(SECTION, "auto_preset", auto_preset)
	cf.set_value(SECTION, "fps_cap", fps_cap_override)
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

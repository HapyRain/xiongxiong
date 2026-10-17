## run_quality_check.gd
## 无头自检：验证画质档 apply() 会改变 Engine.max_fps / 分段帧率 / 持久化。
extends SceneTree


func _init() -> void:
	var ok := true

	var fps_guard: RefCounted = load("res://scripts/performance/fps_guard.gd").new()
	var refresh := float(fps_guard.get_refresh_rate())
	ok = _exp(ok, "刷新率有效（>0）", refresh > 0.0)
	var high: int = int(fps_guard.resolve_high_fps())
	# 真断言：高档帧率必须是「刷新率 → 60/90/120」的正确映射（原来只断言 in [60,90,120]，恒真）
	var expect_high: int = 120 if refresh >= 120.0 else (90 if refresh >= 90.0 else 60)
	ok = _exp(ok, "高档帧率按刷新率映射 %d → %d" % [int(refresh), high], high == expect_high)
	ok = _exp(ok, "snap 35→30", int(fps_guard.snap_to_segment(35)) == 30)
	ok = _exp(ok, "snap 100→90", int(fps_guard.snap_to_segment(100)) == 90)
	ok = _exp(ok, "snap 130→120", int(fps_guard.snap_to_segment(130)) == 120)

	var qs: Node = load("res://scripts/performance/quality_settings.gd").new()
	# 手动构造探测（不进树，避免依赖 Display 窗口）
	qs.device_probe = {
		"physical_mb": 8192, "cpu_cores": 8, "refresh_rate": 60.0,
		"gpu_name": "Test GPU", "os_name": "headless", "score": 8, "auto_tier": 1,
	}

	qs.set_tier(0, true)  # 低
	ok = _exp(ok, "低档 max_fps==30", Engine.max_fps == 30)

	qs.set_tier(1, true)  # 中
	ok = _exp(ok, "中档 max_fps==60", Engine.max_fps == 60)

	qs.set_tier(2, true)  # 高
	var hi_fps: int = Engine.max_fps
	ok = _exp(ok, "高档 max_fps in 60/90/120", hi_fps in [60, 90, 120])

	# fps_cap 覆盖：取低于刷新率的分段，验证强制上限生效
	qs.fps_cap_override = 30
	qs.apply()
	ok = _exp(ok, "fps_cap=30 → max_fps==30", Engine.max_fps == 30)
	# VSync 开启时 max_fps 不得超过刷新率（设计 §3.2）。
	# 断言真实引擎不变量，而不是拿 FpsGuard.apply() 的返回值跟 Engine.max_fps 自比。
	qs.fps_cap_override = 120
	qs.apply()
	var refresh_seg := FpsGuard.snap_to_segment(int(ceil(FpsGuard.get_refresh_rate())))
	var vsync_on := DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED
	ok = _exp(ok, "VSync 下 Engine.max_fps 不超刷新率分段(%d)" % refresh_seg,
		(not vsync_on) or Engine.max_fps <= refresh_seg)
	qs.fps_cap_override = 0

	# 持久化往返
	qs.tier = 0
	qs.auto_preset = false
	qs.save_settings()
	var qs2: Node = load("res://scripts/performance/quality_settings.gd").new()
	qs2.device_probe = qs.device_probe.duplicate()
	qs2.load_settings()
	ok = _exp(ok, "持久化读回手动低档", int(qs2.tier) == 0 and bool(qs2.auto_preset) == false)

	# 配置表齐全
	var cfg: Dictionary = qs.get_config(1)
	for key: String in [
		"fps_target", "particle_scale", "max_fx_instances", "fx_viewport_scale",
		"shader_complexity", "tween_duration_scale", "fxaa", "glow_enabled",
	]:
		ok = _exp(ok, "配置项存在: %s" % key, cfg.has(key))

	# 粒子/特效层档位差异
	ok = _exp(ok, "低档粒子<=中档", float(qs.get_config(0)["particle_scale"]) <= float(qs.get_config(1)["particle_scale"]))
	ok = _exp(ok, "中档粒子<=高档", float(qs.get_config(1)["particle_scale"]) <= float(qs.get_config(2)["particle_scale"]))
	ok = _exp(ok, "低档特效层<=中档", float(qs.get_config(0)["fx_viewport_scale"]) <= float(qs.get_config(1)["fx_viewport_scale"]))
	# 红线：画质档只动帧率/特效，不得改字体渲染相关的 ProjectSettings（原来这里是字面 true）
	var font_keys := [
		"gui/theme/default_font_multichannel_signed_distance_field",
		"gui/theme/default_font_hinting",
	]
	var font_before: Array = []
	for k: String in font_keys:
		font_before.append(ProjectSettings.get_setting(k, null))
	qs.set_tier(2, true)
	for i in font_keys.size():
		ok = _exp(ok, "画质档不改字体渲染设置：%s" % font_keys[i],
			ProjectSettings.get_setting(font_keys[i], null) == font_before[i])

	qs.free()
	qs2.free()

	print("ALL PASS" if ok else "HAS FAILURES")
	quit(0 if ok else 1)


func _exp(ok: bool, name: String, cond: bool) -> bool:
	print(("PASS" if cond else "FAIL"), " - ", name)
	return ok and cond

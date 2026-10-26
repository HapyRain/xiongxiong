## run_nav_check.gd
## headless 导航自检：竖版配置 / 菜单无热座 / 终局回菜单 / 退出游戏 / 人机接管。
## 运行：
##   Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/run_nav_check.gd
extends SceneTree

var _ok: bool = true
var _finished: bool = false
var _phase: String = "init"
var _t: float = 0.0

# 人机接管联机双端
var _host_pm: PeerManager
var _client_pm: PeerManager
var _takeover_reason: String = ""
var _takeover_flag: bool = false
var _ai_step: String = "boot"
var _ai_t: float = 0.0
var _reveals_after: int = 0


func _initialize() -> void:
	print("NAVCHECK_START")
	_check_project_portrait()
	_check_ui_nav()
	_check_ai_opponent()
	# UI 场景的 _ready/_build_ui 要等进树后的首帧，放到 _process 里查
	_phase = "ui"


func _process(delta: float) -> bool:
	if _finished:
		return true
	_t += delta
	match _phase:
		"ui":
			_check_menu_scene()
			_check_settings_panel()
			_check_solo_select()
			_check_main_scene()
			_setup_ai_takeover()
			_phase = "ai"
			_ai_t = 0.0
		"ai":
			_tick_ai(delta)
		"done":
			_finish()
		_:
			_fail("unknown phase %s" % _phase)
			_finish()
	return _finished


# ================= 静态检查 =================

func _check_project_portrait() -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load("res://project.godot")
	_exp("project.godot loads", err == OK)
	if err != OK:
		return
	var w := int(cfg.get_value("display", "window/size/viewport_width", 0))
	var h := int(cfg.get_value("display", "window/size/viewport_height", 0))
	_exp("viewport portrait 390x820", w == 390 and h == 820 and h > w)
	var ori := int(cfg.get_value("display", "window/handheld/orientation", -1))
	_exp("handheld orientation portrait", ori == 1)
	var main_scene := str(cfg.get_value("application", "run/main_scene", ""))
	_exp("main scene is menu", main_scene.ends_with("menu.tscn"))
	var exp_cfg := ConfigFile.new()
	if exp_cfg.load("res://export_presets.cfg") == OK:
		var exp_ori := int(exp_cfg.get_value("preset.0.options", "screen/orientation", -1))
		_exp("export android portrait", exp_ori == 1)
	else:
		_exp("export_presets.cfg loads", false)


func _check_menu_scene() -> void:
	var packed: PackedScene = load("res://scenes/menu.tscn")
	_exp("menu.tscn loads", packed != null)
	if packed == null:
		return
	var menu: Control = packed.instantiate()
	root.add_child(menu)
	# --script 下进树可能不发 READY，补一刀再收集
	menu.notification(Node.NOTIFICATION_READY)
	var texts := _collect_button_texts(menu)
	if texts.is_empty():
		print("DEBUG menu child_count=", menu.get_child_count())
	_exp("menu has 单人", _has_button_prefix(menu, "单人") or texts.has("单机（人机）"))
	_exp("menu has 联机入口", _has_button_prefix(menu, "联机"))
	_exp("menu has 退出游戏", texts.has("退出游戏") or _has_button_prefix(menu, "退出"))
	_exp("menu no 热座按钮", not texts.has("热座（同屏双人）") and not texts.has("热座"))
	var flat := _collect_all_text(menu)
	_exp("menu body no 热座字样", not flat.contains("热座") and not flat.contains("同屏双人"))
	menu.free()


func _check_settings_panel() -> void:
	var packed: PackedScene = load("res://scenes/settings_panel.tscn")
	_exp("settings_panel.tscn loads", packed != null)
	if packed == null:
		return
	var panel: Control = packed.instantiate()
	root.add_child(panel)
	panel.notification(Node.NOTIFICATION_READY)
	var texts := _collect_button_texts(panel)
	if texts.is_empty():
		print("DEBUG settings child_count=", panel.get_child_count())
	_exp("settings has 返回菜单", texts.has("返回菜单") or _has_button_prefix(panel, "返回菜单"))
	if not texts.has("返回菜单") and not _has_button_prefix(panel, "返回菜单"):
		print("DEBUG settings texts=", texts.keys())
	_exp("settings has 退出游戏", texts.has("退出游戏"))
	_exp("settings has close", texts.has("关闭") or texts.has("✕") or _has_button_prefix(panel, "✕"))
	panel.free()


func _check_ui_nav() -> void:
	_exp("UiNav menu scene path", UiNav.MENU_SCENE.ends_with("menu.tscn"))
	var t: String = UiNav.leave_confirm_text()
	_exp("leave confirm mentions 人机接管或结束", t.contains("人机接管") or t.contains("结束"))
	_exp("peer left text 人机接管", UiNav.peer_left_text().contains("人机接管"))


func _check_ai_opponent() -> void:
	var s := BattleState.new()
	# 开局回合（round 1）规则层只放行攒气，AI 会直接短路成 ZAN —— 白名单断言将形同虚设。
	# 放到第 2 回合，才真正校验「AI 候选 ⊆ 攒气 / 包子×1 / 防御」这一覆盖点。
	s.round = 2
	s.qi = [3, 3]
	s.shield = [3, 3]
	var all_valid := true
	for i in 20:
		var a: int = AiOpponent.choose(s, 1)
		# v2：AI 候选表为 攒气 / 包子×1 / 防御（旧「波」= 单发 1 气攻击 → BAO1）
		if a != GameRules.Action.ZAN and a != GameRules.Action.BAO1 and a != GameRules.Action.FANG:
			all_valid = false
	_exp("ai action valid", all_valid)
	# 低气应偏攒（v2：0 气 0 盾 → 包子无气、防御无盾，规则层只放行攒气）
	s.qi = [0, 0]
	s.shield = [0, 0]
	var zan_count := 0
	for i in 30:
		if AiOpponent.choose(s, 1) == GameRules.Action.ZAN:
			zan_count += 1
	_exp("ai low-qi prefers zan", zan_count >= 20)


## W2：单人选择页可加载 + 竖版单屏不滚动（390×820 契约）。
func _check_solo_select() -> void:
	var packed: PackedScene = load("res://scenes/solo_select.tscn")
	_exp("solo_select.tscn loads", packed != null)
	if packed == null:
		return
	var solo: Control = packed.instantiate()
	root.add_child(solo)
	if not solo.is_node_ready():
		solo.notification(Node.NOTIFICATION_READY)
	var flat := _collect_all_text(solo)
	_exp("solo_select 模式卡 经典/课间", flat.contains("经典模式") and flat.contains("课间模式"))
	_exp("solo_select 难度 普通/困难", flat.contains("普通") and flat.contains("困难"))
	_exp("solo_select 开始/返回", flat.contains("开始") and flat.contains("返回"))
	_exp("solo_select back route → menu",
		str(UiNav.BACK_ROUTES.get("res://scenes/solo_select.tscn", "")) == UiNav.MENU_SCENE)
	var content := solo.get_node_or_null("Margin/Content") as Control
	_exp("solo_select 竖版单屏不滚动（内容最小高 ≤ 820）",
		content != null and content.get_combined_minimum_size().y <= 820.0)
	root.remove_child(solo)
	solo.free()


## W2：对战页按 cfg 渲染底部出招区（classic 3 按钮 / lesson 13 格）。
func _check_main_scene() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	_exp("main.tscn loads", packed != null)
	if packed == null:
		return
	BattleController.pending_cfg = {"mode": "classic", "mastery": false, "difficulty": "normal"}
	var classic: Control = packed.instantiate()
	root.add_child(classic)
	if not classic.is_node_ready():
		classic.notification(Node.NOTIFICATION_READY)
	_exp("main classic：三个出招按钮", _count_action_buttons(classic) == 3)
	root.remove_child(classic)
	classic.free()

	BattleController.pending_cfg = {"mode": "lesson", "mastery": false, "difficulty": "normal"}
	var lesson: Control = packed.instantiate()
	root.add_child(lesson)
	if not lesson.is_node_ready():
		lesson.notification(Node.NOTIFICATION_READY)
	_exp("main lesson：技能盘占位 13 格", _count_action_buttons(lesson) == 13)
	root.remove_child(lesson)
	lesson.free()
	BattleController.pending_cfg = {}


# ================= 人机接管联机 =================

func _setup_ai_takeover() -> void:
	var hp := LocalProvider.new()
	var cp := LocalProvider.new()
	hp.pair_with(cp)

	_host_pm = PeerManager.new()
	root.add_child(_host_pm)
	_host_pm.install_provider(hp, PeerManager.Mode.ENET)
	_host_pm.ai_takeover_started.connect(func(reason: String):
		_takeover_flag = true
		_takeover_reason = reason)
	_host_pm.actions_revealed.connect(func(_a, _r):
		if _takeover_flag:
			_reveals_after += 1)

	_client_pm = PeerManager.new()
	root.add_child(_client_pm)
	_client_pm.install_provider(cp, PeerManager.Mode.ENET)

	hp.open_as_host({})
	cp.open_as_client({})
	_host_pm._sync_fsm_identity()
	_client_pm._sync_fsm_identity()
	_host_pm._set_session(PeerManager.Session.IN_BATTLE)
	_client_pm._set_session(PeerManager.Session.IN_BATTLE)
	_host_pm.start_battle()
	_pump(0.05)
	# 开局点「攒」
	_host_pm.submit_action(GameRules.Action.ZAN, 0)
	_client_pm.submit_action(GameRules.Action.ZAN, 1)
	_pump(0.05)
	# 拍2 揭示：headless 下无控制器驱动节奏，手动触发（结算后才加气/盾）
	_host_pm.reveal_phase()
	_pump(0.05)
	_host_pm.debug_advance_round()
	_pump(0.02)

	_exp("ai host in battle", _host_pm.get_session() == PeerManager.Session.IN_BATTLE)
	_exp("ai not takeover yet", not _host_pm.ai_takeover)

	_ai_step = "drop"
	_ai_t = 0.0


func _tick_ai(delta: float) -> void:
	_ai_t += delta
	_pump(delta)
	match _ai_step:
		"drop":
			if _ai_t > 0.05:
				# 拆对：client 侧 close → host 收 disconnected → 人机接管
				if _client_pm != null and _client_pm.provider != null:
					_client_pm.provider.close()
				_pump(0.05)
				_exp("ai takeover fired", _takeover_flag)
				_exp("ai takeover flag on pm", _host_pm.ai_takeover)
				_exp("ai takeover reason", _takeover_reason != "")
				_exp("ai session still battle", _host_pm.get_session() == PeerManager.Session.IN_BATTLE)
				_exp("ai input open", _host_pm.is_input_open())
				_exp("ai is_host local", _host_pm.is_host())
				_ai_step = "play"
				_ai_t = 0.0
		"play":
			if _ai_t > 0.1:
				# 接管后仍可本地推进一回合
				if _host_pm.state.round >= 1 and not _host_pm.state.is_over():
					_host_pm.state.round = maxi(_host_pm.state.round, 2)
					_host_pm.state.pending = [-1, -1]
					_host_pm._pending_actions = [-1, -1]
					_host_pm._locks = [false, false]
					_host_pm._revealing = false
					var hp1 := int(_host_pm.state.hp[1])
					_host_pm.submit_action(GameRules.Action.ZAN, 0)
					_host_pm.submit_action(GameRules.Action.BAO1, 1)
					# 拍2 揭示：提交只锁定，结算由 reveal_phase 触发（3000d5e 后的节奏语义）
					_host_pm.reveal_phase()
					_pump(0.05)
					var resolved := _reveals_after >= 1 or int(_host_pm.state.hp[1]) != hp1
					_exp("ai takeover can resolve", resolved)
				_ai_step = "end"
				_ai_t = 0.0
		"end":
			if _host_pm != null:
				_host_pm.leave()
			_exp("ai leave resets takeover", not _host_pm.ai_takeover)
			_phase = "done"
		_:
			_fail("unknown ai step %s" % _ai_step)
			_phase = "done"


# ================= 通用 =================

func _pump(dt: float) -> void:
	if _host_pm != null and _host_pm.provider != null:
		_host_pm.provider.poll(dt)
		_host_pm._pump_session(dt)
	if _client_pm != null and _client_pm.provider != null:
		_client_pm.provider.poll(dt)
		_client_pm._pump_session(dt)


func _collect_button_texts(node: Node) -> Dictionary:
	var out := {}
	_walk(node, func(n: Node):
		if n is Button:
			out[str((n as Button).text)] = true)
	return out


func _has_button_prefix(node: Node, prefix: String) -> bool:
	for t in _collect_button_texts(node).keys():
		if str(t).begins_with(prefix):
			return true
	return false


func _collect_all_text(node: Node) -> String:
	var parts: PackedStringArray = []
	_walk(node, func(n: Node):
		if n is Label:
			parts.append(str((n as Label).text))
		elif n is Button:
			parts.append(str((n as Button).text)))
	return "\n".join(parts)


func _count_action_buttons(node: Node) -> int:
	var count := {"n": 0}
	_walk(node, func(n: Node):
		if n is Button and str(n.name).begins_with("Action"):
			count["n"] += 1)
	return int(count["n"])


func _walk(node: Node, cb: Callable) -> void:
	cb.call(node)
	for c in node.get_children():
		_walk(c, cb)


func _exp(name: String, cond: bool) -> void:
	print(("PASS" if cond else "FAIL"), " - ", name)
	_ok = _ok and cond


func _fail(msg: String) -> void:
	print("FAIL - ", msg)
	_ok = false


func _finish() -> void:
	if _finished:
		return
	_finished = true
	print("ALL PASS" if _ok else "HAS FAILURES")
	quit(0 if _ok else 1)

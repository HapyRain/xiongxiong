## net_battle_ui.gd
## 竖版联机对局 UI：对手在上 / 状态中段 / 我方在下。
## 热座入口已移除（底层 HOTSEAT 仅测试）；对方离开 → 人机接管提示并继续。
extends Control

var controller: NetworkedBattleController
var _status_label: Label
var _round_label: Label
var _log_label: Label
var _me_boxes: Array = []
var _you_boxes: Array = []
var _me_btns: Dictionary = {}
var _takeover_banner: Label
var _me_hp_row: HBoxContainer
var _me_qi_row: HBoxContainer
var _you_hp_row: HBoxContainer
var _you_qi_row: HBoxContainer
var _fx_layer: Control
var _reveal_layer: CanvasLayer
var _spot_layer: Control
var _sfx_clap: AudioStream
var _sfx_ding: AudioStream
var _sfx_hit: AudioStream
var _sfx_block: AudioStream
var _sfx_zan: AudioStream
var _sfx_players: Array = []

## 封存 / 同意 / 倒计时 / 终局遮罩
var _overlay: Control
var _overlay_title: Label
var _overlay_body: Label
var _btn_continue: Button
var _btn_decline: Button
var _btn_menu: Button
var _btn_rematch: Button
var _overlay_mode: String = ""


func _ready() -> void:
	UiTheme.apply_to_tree(get_tree())
	controller = NetworkedBattleController.new()
	controller.name = "NetworkedBattleController"
	add_child(controller)
	controller.attach(Net)
	_build_ui()
	_build_overlay()
	_setup_audio()
	controller.beat.connect(_on_beat)
	controller.preselect_changed.connect(_on_preselect)
	controller.phase_changed.connect(_on_phase)
	controller.round_resolved.connect(_on_resolved)
	controller.game_over.connect(_on_game_over)
	controller.status_text.connect(func(t: String):
		if _status_label != null:
			_status_label.text = t)
	Net.actions_revealed.connect(_on_reveal_actions)
	Net.peer_left.connect(_on_peer_left)
	Net.ai_takeover_started.connect(_on_ai_takeover)
	Net.net_state_changed.connect(_on_net_state)
	Net.consent_needed.connect(_on_consent_needed)
	Net.countdown_tick.connect(_on_countdown_tick)
	Net.session_failed.connect(_on_session_failed)
	Net.session_restored.connect(_on_session_restored)
	Net.battle_started.connect(func(_s): _on_battle_started_ui())
	controller.begin()
	_on_phase(controller.state.phase, controller.state.round)
	_refresh_all()


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = UiTheme.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	_fx_layer = Control.new()
	_fx_layer.name = "FxLayer"
	_fx_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fx_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fx_layer)

	# 右上角：设置/菜单（避开 QualitySettings 的 ⚙）
	var top_menu := Button.new()
	top_menu.text = "菜单"
	top_menu.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	top_menu.offset_left = -108
	top_menu.offset_top = 8
	top_menu.offset_right = -52
	top_menu.offset_bottom = 40
	top_menu.add_theme_font_size_override("font_size", 14)
	top_menu.add_theme_color_override("font_color", UiTheme.INK)
	top_menu.pressed.connect(_on_top_menu)
	BattleFx.bind_press(top_menu, "menu")
	add_child(top_menu)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	# 顶栏让出「菜单」按钮
	margin.add_theme_constant_override("margin_top", 52)
	margin.add_theme_constant_override("margin_bottom", 12)
	add_child(margin)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	margin.add_child(v)

	# 对手（上）
	var you_panel := PanelContainer.new()
	you_panel.add_theme_stylebox_override("panel", UiTheme.card_style())
	v.add_child(you_panel)
	var you_v := VBoxContainer.new()
	you_panel.add_child(you_v)
	var you_title := UiTheme.ink_label("对手", 16, UiTheme.INK)
	you_v.add_child(you_title)
	you_v.add_child(_make_stat_row("you", _you_boxes))
	var you_wait := UiTheme.ink_label("（等待对方选招…）", 12, UiTheme.INK_FAINT)
	you_wait.name = "YouWait"
	you_v.add_child(you_wait)

	# 中央
	var center := VBoxContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(center)

	_takeover_banner = Label.new()
	_takeover_banner.text = ""
	_takeover_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_takeover_banner.add_theme_font_size_override("font_size", 15)
	_takeover_banner.add_theme_color_override("font_color", UiTheme.DANGER)
	_takeover_banner.visible = false
	center.add_child(_takeover_banner)

	_round_label = UiTheme.ink_label("回合 -", 14, UiTheme.INK_SOFT)
	_round_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(_round_label)
	_status_label = UiTheme.ink_label("对局", 22, UiTheme.INK)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(_status_label)
	_log_label = UiTheme.ink_label("……", 13, UiTheme.INK_SOFT)
	_log_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	center.add_child(_log_label)

	# 我方（下）
	var me_panel := PanelContainer.new()
	me_panel.add_theme_stylebox_override("panel", UiTheme.card_style())
	v.add_child(me_panel)
	var me_v := VBoxContainer.new()
	me_panel.add_child(me_v)
	var me_title := UiTheme.ink_label("我", 16, UiTheme.INK)
	me_v.add_child(me_title)
	me_v.add_child(_make_stat_row("me", _me_boxes))
	me_v.add_child(_make_action_row(0, _me_btns))


func _make_stat_row(prefix: String, boxes: Array) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	var hp_row := BattleFx.make_hp_row(GameRules.MAX_HP, GameRules.MAX_HP)
	var qi_row := BattleFx.make_qi_row(GameRules.MAX_QI, 0)
	var sh_row := BattleFx.make_shield_row(GameRules.MAX_SHIELD, 0)
	if prefix == "me":
		_me_hp_row = hp_row
		_me_qi_row = qi_row
	else:
		_you_hp_row = hp_row
		_you_qi_row = qi_row
	var hp_lab := Label.new()
	hp_lab.name = prefix + "_hp"
	hp_lab.text = "%d/%d" % [GameRules.MAX_HP, GameRules.MAX_HP]
	var qi_lab := Label.new()
	qi_lab.name = prefix + "_qi"
	qi_lab.text = "0/%d" % GameRules.MAX_QI
	var sh_lab := Label.new()
	sh_lab.name = prefix + "_shield"
	sh_lab.text = "0/%d" % GameRules.MAX_SHIELD
	boxes.append(hp_lab)
	boxes.append(qi_lab)
	boxes.append(sh_lab)
	col.add_child(BattleFx.make_stat_line("血", hp_row, hp_lab))
	col.add_child(BattleFx.make_stat_line("气", qi_row, qi_lab))
	col.add_child(BattleFx.make_stat_line("盾", sh_row, sh_lab))
	# 图标行挂在列上，按 panel 取；勿用座位下标选 _me/_you
	col.set_meta("hp_row", hp_row)
	col.set_meta("qi_row", qi_row)
	col.set_meta("shield_row", sh_row)
	return col


func _make_action_row(who: int, btns: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var styles := {
		GameRules.Action.ZAN: UiTheme.ACCENT,
		GameRules.Action.BO: UiTheme.WAVE,
		GameRules.Action.FANG: UiTheme.SHIELD,
	}
	var names := {
		GameRules.Action.ZAN: "攒",
		GameRules.Action.BO: "波",
		GameRules.Action.FANG: "防",
	}
	for a in [GameRules.Action.ZAN, GameRules.Action.BO, GameRules.Action.FANG]:
		var b := Button.new()
		b.text = names[a]
		b.custom_minimum_size = Vector2(96, 72)
		b.add_theme_font_size_override("font_size", 22)
		# 亮底（攒）用深字，避免白字发虚
		var fg := UiTheme.INK if a == GameRules.Action.ZAN else Color.WHITE
		b.add_theme_color_override("font_color", fg)
		b.add_theme_color_override("font_hover_color", fg)
		b.add_theme_color_override("font_pressed_color", fg)
		var col: Color = styles[a]
		b.add_theme_stylebox_override("normal", UiTheme.button_style(col, 16))
		b.add_theme_stylebox_override("hover", UiTheme.button_style(col.lightened(0.08), 16))
		b.add_theme_stylebox_override("pressed", UiTheme.button_style(col.darkened(0.1), 16))
		var act: int = a
		var seat: int = who
		b.pressed.connect(func(): _on_pick(seat, act))
		var kind := "default"
		if a == GameRules.Action.ZAN:
			kind = "zan"
		elif a == GameRules.Action.BO:
			kind = "bo"
		else:
			kind = "fang"
		BattleFx.bind_press(b, kind)
		row.add_child(b)
		btns[a] = b
	return row


func _on_top_menu() -> void:
	var tree := get_tree()
	if tree == null:
		return
	var existing := tree.root.get_node_or_null("SettingsPanelOverlay")
	if existing != null:
		return
	var panel_scene: PackedScene = load("res://scenes/settings_panel.tscn")
	if panel_scene == null:
		return
	var overlay := panel_scene.instantiate()
	overlay.name = "SettingsPanelOverlay"
	tree.root.add_child(overlay)


# ---------- 封存 / 同意 / 倒计时 / 终局遮罩 ----------

func _build_overlay() -> void:
	_overlay = Control.new()
	_overlay.name = "NetOverlay"
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.visible = false
	add_child(_overlay)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.62)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(320, 0)
	center.add_child(panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	panel.add_child(v)

	_overlay_title = Label.new()
	_overlay_title.text = ""
	_overlay_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlay_title.add_theme_font_size_override("font_size", 24)
	_overlay_title.add_theme_color_override("font_color", UiTheme.INK)
	v.add_child(_overlay_title)

	_overlay_body = Label.new()
	_overlay_body.text = ""
	_overlay_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlay_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_overlay_body.custom_minimum_size = Vector2(280, 60)
	_overlay_body.add_theme_color_override("font_color", UiTheme.INK_SOFT)
	v.add_child(_overlay_body)

	var btn_col := VBoxContainer.new()
	btn_col.add_theme_constant_override("separation", 10)
	btn_col.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(btn_col)

	_btn_continue = Button.new()
	_btn_continue.text = "继续"
	_btn_continue.custom_minimum_size = Vector2(200, 48)
	_btn_continue.pressed.connect(func():
		Net.submit_resume_vote(true)
		_show_overlay("countdown", "已同意", "等待对方确认…", false, false, false))
	BattleFx.bind_press(_btn_continue, "menu")
	btn_col.add_child(_btn_continue)

	_btn_decline = Button.new()
	_btn_decline.text = "退出（判负）"
	_btn_decline.custom_minimum_size = Vector2(200, 48)
	_btn_decline.pressed.connect(func():
		Net.submit_resume_vote(false)
		_show_overlay("fail", "已拒绝继续", "你选择了退出，本局判负", false, false, true))
	BattleFx.bind_press(_btn_decline, "danger")
	btn_col.add_child(_btn_decline)

	_btn_menu = Button.new()
	_btn_menu.text = "返回菜单"
	_btn_menu.custom_minimum_size = Vector2(200, 48)
	_btn_menu.pressed.connect(func():
		if _overlay_mode == "rematch":
			_on_rematch_no()
		else:
			UiNav.return_to_menu(get_tree()))
	BattleFx.bind_press(_btn_menu, "menu")
	btn_col.add_child(_btn_menu)

	_btn_rematch = Button.new()
	_btn_rematch.text = "再来一局"
	_btn_rematch.custom_minimum_size = Vector2(200, 48)
	_btn_rematch.pressed.connect(_on_rematch_click)
	BattleFx.bind_press(_btn_rematch, "zan")
	btn_col.add_child(_btn_rematch)


func _show_overlay(mode: String, title: String, body: String, show_continue: bool, show_decline: bool, show_menu: bool = false) -> void:
	_overlay_mode = mode
	_overlay.visible = true
	_overlay_title.text = title
	_overlay_body.text = body
	_btn_continue.visible = show_continue
	_btn_decline.visible = show_decline
	_btn_menu.visible = show_menu
	if _btn_rematch != null:
		_btn_rematch.visible = (mode == "game_over" or mode == "rematch")
		_btn_rematch.disabled = false
		if mode == "game_over":
			_btn_rematch.text = "再来一局"
	_set_input_buttons_enabled(false)


func _hide_overlay() -> void:
	_overlay_mode = ""
	_overlay.visible = false
	_set_input_buttons_enabled(true)


func _set_input_buttons_enabled(on: bool) -> void:
	for b in _me_btns.values():
		b.disabled = not on


func _on_peer_left(_id: int, reason: String) -> void:
	_log("对手离开：%s" % reason)
	# 具体接管提示由 ai_takeover_started 统一给出


func _on_ai_takeover(reason: String) -> void:
	_takeover_banner.text = UiNav.peer_left_text()
	_takeover_banner.visible = true
	_log("对方已离开（%s），由人机接管" % reason)
	if _overlay_mode in ["sealed", "countdown", "resuming", "consent"]:
		_hide_overlay()
	# 短暂遮罩提示后自动继续
	_show_overlay("takeover", "对方已离开", "由人机接管，对局继续…", false, false, false)
	var t := get_tree()
	if t != null:
		t.create_timer(1.6).timeout.connect(func():
			if _overlay_mode == "takeover":
				_hide_overlay())


func _on_net_state(state_name: String, reason: String) -> void:
	match state_name:
		"Degraded":
			_log("网络不佳（%s）" % reason)
		"Sealed":
			_show_overlay("sealed", "连接中断", "已封存对局，等待链路恢复…\n（%s）" % reason, false, false, true)
		"AwaitingConsent":
			pass  # 由 consent_needed 弹出按钮
		"Countdown":
			_show_overlay("countdown", "即将恢复", "3…", false, false, false)
		"Resuming":
			_show_overlay("resuming", "恢复中…", "正在从快照恢复对局", false, false, false)
		"Connected":
			if _overlay_mode in ["sealed", "countdown", "resuming", "consent"]:
				_hide_overlay()
				_log("对局已恢复")
		"Fail":
			_show_overlay("fail", "对局结束", "因网络原因终局：%s\n可返回菜单。" % reason, false, false, true)


func _on_consent_needed(_snap: Dictionary, _need_from: Array) -> void:
	_show_overlay("consent", "是否继续？", "链路已恢复，双方都点「继续」才会以 3 秒倒计时恢复对局。\n一方退出或 30 秒未确认则判负。", true, true, true)


func _on_countdown_tick(remain_ms: int) -> void:
	if _overlay_mode != "countdown":
		_show_overlay("countdown", "即将恢复", "", false, false, false)
	var sec := int(ceil(remain_ms / 1000.0))
	_overlay_body.text = "%d" % maxi(sec, 1) if remain_ms > 0 else "恢复中…"
	_overlay_title.text = "即将恢复 · %d" % maxi(sec, 1)


func _on_session_failed(loser_role: int, reason: String) -> void:
	var mine: int = Net.get_local_role()
	var body: String
	if loser_role < 0:
		body = "双方均未确认，平局（%s）" % reason
	elif loser_role == mine:
		body = "未恢复方判负：你（%s）\n可返回菜单。" % reason
	else:
		body = "对方未恢复，你获胜（%s）\n可返回菜单。" % reason
	_show_overlay("fail", "对局结束", body, false, false, true)


func _on_session_restored(_snap: Dictionary) -> void:
	_hide_overlay()
	_refresh_all()
	_log("已从快照恢复")


func _on_beat(n: int) -> void:
	_play_sfx(_sfx_clap, 0.0)
	_status_label.text = "啪！（拍 %d）" % n


func _on_resolved(result: Dictionary) -> void:
	_hide_spotlight()
	var text := str(result.get("text", ""))
	_log(text)
	# 中场结算短面板
	if not bool(result.get("opening", false)) and text != "":
		_status_label.text = text
	_refresh_all()
	_play_reveal_cards(result)
	_play_impact_fx(result)
	_play_impact_sfx(result)


func _on_pick(who: int, action: int) -> void:
	if action == GameRules.Action.ZAN:
		_hide_spotlight()
	if controller.try_select(who, action):
		_play_sfx(_sfx_zan if action == GameRules.Action.ZAN else _sfx_ding, -6.0)
		_log("已选 %s" % GameRules.action_name(action))
		_refresh_all()
	else:
		_log("当前无法出招")


func _show_spotlight() -> void:
	if _spot_layer != null and is_instance_valid(_spot_layer):
		return
	var zan_btn: Button = _me_btns.get(GameRules.Action.ZAN) as Button
	if zan_btn == null:
		return
	_spot_layer = BattleFx.show_focus_spotlight(get_tree(), zan_btn, "点击「攒」开始对决")


func _hide_spotlight() -> void:
	if _spot_layer != null and is_instance_valid(_spot_layer):
		BattleFx.hide_focus_spotlight(_spot_layer)
	_spot_layer = null


func _exit_tree() -> void:
	_hide_spotlight()


func _on_preselect(who: int, action: int) -> void:
	var mine: int = Net.get_local_role()
	if who == mine:
		_log("我方已选 %s" % GameRules.action_name(action))
	else:
		_log("对方已选")  # 不泄露具体招式
	_refresh_all()


func _on_battle_started_ui() -> void:
	# 新局务必收掉上一局遮罩，否则特效在下面看不见
	_hide_overlay()


func _on_phase(phase: int, round_no: int) -> void:
	_round_label.text = "回合 %d / %d" % [round_no, GameRules.MAX_ROUND]
	var is_opening: bool = round_no == GameRules.OPENING_ROUND and controller != null \
		and controller.peer != null and not controller.peer._opening_done
	match phase:
		GameRules.Phase.SELECTING:
			if is_opening:
				_status_label.text = "点击「攒」开始对决"
				_show_spotlight()
			else:
				_status_label.text = "同步出招"
				_hide_spotlight()
			# 选招阶段应无遮罩
			if _overlay != null and _overlay.visible and _overlay_mode in ["game_over", "rematch", "takeover"]:
				_hide_overlay()
		GameRules.Phase.RESOLVING:
			_status_label.text = "结算…"
			_hide_spotlight()
		GameRules.Phase.PRESENTING:
			_status_label.text = "亮招"
			_hide_spotlight()
		GameRules.Phase.GAME_OVER:
			_status_label.text = "结束"
			_hide_spotlight()
	_refresh_all()


# ---------- 音效 / 亮招卡片 ----------

func _setup_audio() -> void:
	_sfx_clap = load("res://assets/audio/clap.wav")
	_sfx_ding = load("res://assets/audio/ding.wav")
	_sfx_hit = load("res://assets/audio/hit.wav")
	_sfx_block = load("res://assets/audio/block.wav")
	_sfx_zan = load("res://assets/audio/zan.wav")
	for i in 4:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_sfx_players.append(p)


func _play_sfx(stream: AudioStream, volume_db: float = 0.0) -> void:
	if stream == null:
		return
	for p: AudioStreamPlayer in _sfx_players:
		if not p.playing:
			p.stream = stream
			p.volume_db = volume_db
			p.play()
			return
	if _sfx_players.size() > 0:
		_sfx_players[0].stream = stream
		_sfx_players[0].volume_db = volume_db
		_sfx_players[0].play()


func _play_impact_sfx(result: Dictionary) -> void:
	if bool(result.get("opening", false)):
		_play_sfx(_sfx_zan, -2.0)
		return
	var hit: Array = result.get("hit", [false, false])
	var blocked: Array = result.get("blocked", [false, false])
	var any_hit := (hit.size() > 0 and (bool(hit[0]) or (hit.size() > 1 and bool(hit[1]))))
	var any_block := (blocked.size() > 0 and (bool(blocked[0]) or (blocked.size() > 1 and bool(blocked[1]))))
	if any_hit:
		_play_sfx(_sfx_hit, 0.0)
	elif any_block:
		_play_sfx(_sfx_block, 0.0)
	else:
		_play_sfx(_sfx_ding, -4.0)


func _play_reveal_cards(result: Dictionary) -> void:
	if get_tree() != null and get_tree().root.get_node_or_null("SettingsPanelOverlay") != null:
		return
	if _reveal_layer != null and is_instance_valid(_reveal_layer):
		_reveal_layer.queue_free()
	_reveal_layer = CanvasLayer.new()
	_reveal_layer.layer = 10
	add_child(_reveal_layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reveal_layer.add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0.12, 0.1, 0.08, 0.22)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dim)
	var box := HBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.add_theme_constant_override("separation", 24)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(box)
	var acts: Array = result.get("actions", [-1, -1])
	var mine: int = Net.get_local_role()
	var my_act: int = int(acts[mine]) if acts.size() > mine else -1
	var op_act: int = int(acts[1 - mine]) if acts.size() > (1 - mine) else -1
	var me_card := _make_action_card("我", GameRules.action_name(my_act), UiTheme.ACCENT)
	var you_card := _make_action_card("对手", GameRules.action_name(op_act), UiTheme.SHIELD)
	box.add_child(me_card)
	box.add_child(you_card)
	me_card.scale = Vector2(0.2, 0.2)
	you_card.scale = Vector2(0.2, 0.2)
	me_card.pivot_offset = me_card.size / 2.0
	you_card.pivot_offset = you_card.size / 2.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(me_card, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(you_card, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var t := get_tree()
	if t != null:
		t.create_timer(0.9).timeout.connect(func():
			if _reveal_layer != null and is_instance_valid(_reveal_layer):
				_reveal_layer.queue_free()
				_reveal_layer = null)


func _make_action_card(title: String, action: String, accent: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	var sb := UiTheme.button_style(Color(0.99, 0.97, 0.94, 0.96), 16, accent)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	panel.add_child(v)
	v.add_child(UiTheme.ink_label(title, 13, UiTheme.INK_SOFT))
	var act := UiTheme.ink_label(action, 32, accent)
	act.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(act)
	return panel


func _play_impact_fx(result: Dictionary) -> void:
	if _fx_layer == null or bool(result.get("opening", false)):
		return
	if get_tree() != null and get_tree().root.get_node_or_null("SettingsPanelOverlay") != null:
		return
	# 特效提到遮罩之上，避免被 game_over/rematch 盖住
	if _fx_layer.get_parent() != null:
		_fx_layer.get_parent().move_child(_fx_layer, _fx_layer.get_parent().get_child_count() - 1)
	var hit: Array = result.get("hit", [false, false])
	var blocked: Array = result.get("blocked", [false, false])
	var mine: int = Net.get_local_role()
	var me_target: Control = _me_hp_row.get_parent() as Control if _me_hp_row else self
	var you_target: Control = _you_hp_row.get_parent() as Control if _you_hp_row else self
	# hit[i]/blocked[i] 按座位 0/1；UI 上下是「我/对手」
	var my_hit: bool = bool(hit[mine]) if hit.size() > mine else false
	var other_hit: bool = bool(hit[1 - mine]) if hit.size() > (1 - mine) else false
	var my_block: bool = bool(blocked[mine]) if blocked.size() > mine else false
	var other_block: bool = bool(blocked[1 - mine]) if blocked.size() > (1 - mine) else false
	if my_hit:
		BattleFx.play_hurt(_fx_layer, me_target)
	if other_hit:
		BattleFx.play_hit(_fx_layer, you_target)
	if my_block:
		BattleFx.play_block(_fx_layer, me_target)
	if other_block:
		BattleFx.play_block(_fx_layer, you_target)


func _on_reveal_actions(actions: Array, _results: Dictionary) -> void:
	if actions.size() >= 2:
		var mine: int = Net.get_local_role()
		var other: int = 1 - mine
		_log("亮招：我 %s ｜ 对方 %s" % [
			GameRules.action_name(int(actions[mine])),
			GameRules.action_name(int(actions[other])),
		])


func _on_game_over(winner: int) -> void:
	var s: BattleState = controller.state
	var mine: int = Net.get_local_role()
	var body: String
	if winner == mine:
		_status_label.text = "我方胜利！"
		body = "你赢了！终局 HP %s" % str(s.hp)
	elif winner == 2 or winner < 0:
		_status_label.text = "平局"
		body = "平局。终局 HP %s" % str(s.hp)
	else:
		_status_label.text = "对方胜利"
		body = "对方获胜。终局 HP %s" % str(s.hp)
	for b in _me_btns.values():
		b.disabled = true
	# 胜负庆祝（0=左/房主，1=右/客户端；映射到本地观感）
	var view_win: int = winner if winner == 2 or winner < 0 else (0 if winner == mine else 1)
	if _fx_layer != null:
		BattleFx.play_result(_fx_layer, view_win, _status_label)
	_show_overlay("game_over", "对局结束", body + "\n再来一局，还是回菜单？", false, false, true)
	if _btn_rematch != null:
		_btn_rematch.visible = true
		_btn_rematch.disabled = false
		_btn_rematch.text = "再来一局"
		# 第二局终局时 handler 可能已被一次性替换，这里补回
		if _btn_rematch.pressed.is_connected(_on_rematch_yes):
			_btn_rematch.pressed.disconnect(_on_rematch_yes)
		if not _btn_rematch.pressed.is_connected(_on_rematch_click):
			_btn_rematch.pressed.connect(_on_rematch_click)
	Net.rematch_offer.connect(_on_rematch_offer, CONNECT_ONE_SHOT)
	Net.rematch_answered.connect(_on_rematch_answered, CONNECT_ONE_SHOT)


func _on_rematch_click() -> void:
	if _btn_rematch != null:
		_btn_rematch.disabled = true
		_btn_rematch.text = "等待对方…"
	Net.request_rematch()


func _on_rematch_offer() -> void:
	_overlay_mode = "rematch"
	_overlay.visible = true
	_overlay_title.text = "再来一局？"
	_overlay_body.text = "对方想再来一局，是否开始？"
	_btn_continue.visible = false
	_btn_decline.visible = false
	_btn_menu.visible = true
	_btn_menu.text = "回菜单"
	_btn_rematch.visible = true
	_btn_rematch.disabled = false
	_btn_rematch.text = "开始新局"
	_set_input_buttons_enabled(false)
	# 绑一次性：确认/取消
	if _btn_rematch.pressed.is_connected(_on_rematch_click):
		_btn_rematch.pressed.disconnect(_on_rematch_click)
	_btn_rematch.pressed.connect(_on_rematch_yes, CONNECT_ONE_SHOT)


func _on_rematch_yes() -> void:
	_hide_overlay()
	_btn_rematch.text = "再来一局"
	_btn_menu.text = "返回菜单"
	Net.answer_rematch(true)


func _on_rematch_no() -> void:
	_hide_overlay()
	Net.answer_rematch(false)
	UiNav.return_to_menu(get_tree())


func _on_rematch_answered(yes: bool) -> void:
	if yes:
		_hide_overlay()
		if _btn_rematch != null:
			_btn_rematch.text = "再来一局"
			_btn_rematch.disabled = false
		if _btn_menu != null:
			_btn_menu.text = "返回菜单"
		_refresh_all()
		_log("新对局开始")
	else:
		_show_overlay("game_over", "已结束", "对方不想再来一局，返回菜单。", false, false, true)
		var t := get_tree()
		if t != null:
			t.create_timer(1.2).timeout.connect(func():
				UiNav.return_to_menu(t))


func _log(t: String) -> void:
	if _log_label != null:
		_log_label.text = t


func _refresh_all() -> void:
	if controller == null:
		return
	var s: BattleState = controller.state
	# 座位：本地角色才是「我」，不能写死 0/1（客户端会看反）
	var mine: int = Net.get_local_role()
	if mine != 0 and mine != 1:
		mine = 0
	_set_row(_me_boxes, s, mine)
	_set_row(_you_boxes, s, 1 - mine)
	var input_ok: bool = Net != null and Net.is_input_open()
	var can_lock: bool = not s.is_over() and _overlay.visible == false and input_ok and controller._window_open
	# 本地已选（对齐单机：点完变灰）
	var picked: int = int(controller._local_preselect[mine]) if controller._local_preselect.size() > mine else -1
	if picked < 0:
		picked = int(s.pending[mine])
	var locked: bool = picked >= 0 or bool(Net != null and Net._locks != null and mine < Net._locks.size() and bool(Net._locks[mine]))
	for a in _me_btns.keys():
		var b: Button = _me_btns[a]
		var act := int(a)
		# 与单机一致：点完即灰，不再上色强调
		b.disabled = (not can_lock) or locked or (not s.can_use_action(mine, act))
	if locked and picked >= 0:
		_status_label.text = "已选：%s" % GameRules.action_name(picked)
	elif not input_ok and _overlay != null and not _overlay.visible and not s.is_over():
		if _log_label != null and _log_label.text == "……":
			_log_label.text = "网络同步中，请稍候…"


## 选中态：金边 + 稍暗，肉眼可辨「点成功了」
func _set_btn_selected(b: Button, on: bool) -> void:
	if b == null:
		return
	if on:
		b.add_theme_color_override("font_color", UiTheme.INK)
		b.add_theme_color_override("font_hover_color", UiTheme.INK)
		b.add_theme_stylebox_override("normal", UiTheme.button_style(Color(1.0, 0.85, 0.35), 16, UiTheme.ACCENT_DEEP))
		b.add_theme_stylebox_override("disabled", UiTheme.button_style(Color(1.0, 0.85, 0.35), 16, UiTheme.ACCENT_DEEP))
	else:
		# 恢复各招式默认色
		var col: Color = UiTheme.ACCENT
		if b.text == "波":
			col = UiTheme.WAVE
		elif b.text == "防":
			col = UiTheme.SHIELD
		var fg := UiTheme.INK if b.text == "攒" else Color.WHITE
		b.add_theme_color_override("font_color", fg)
		b.add_theme_color_override("font_hover_color", fg)
		b.add_theme_stylebox_override("normal", UiTheme.button_style(col, 16))
		b.add_theme_stylebox_override("disabled", UiTheme.button_style(col.darkened(0.25), 16))


func _set_row(boxes: Array, s: BattleState, i: int) -> void:
	if boxes.size() < 3:
		return
	if i < 0 or i > 1:
		i = 0
	var hp := clampi(int(s.hp[i]), 0, GameRules.MAX_HP)
	var qi := clampi(int(s.qi[i]), 0, GameRules.MAX_QI)
	var shield_n := clampi(int(s.shield[i]), 0, GameRules.MAX_SHIELD)
	boxes[0].text = "血 %d/%d" % [hp, GameRules.MAX_HP]
	boxes[1].text = "气 %d/%d" % [qi, GameRules.MAX_QI]
	boxes[2].text = "盾 %d/%d" % [shield_n, GameRules.MAX_SHIELD]
	# 从该 panel 的列 meta 取图标行（盾一直正确，血/气曾按座位 i 选错行）
	var src: Control = boxes[0].get_parent() as Control
	var col: Control = src
	if col != null and not col.has_meta("hp_row") and col.get_parent() != null:
		col = col.get_parent() as Control
	if col != null and col.has_meta("hp_row"):
		var hp_row: HBoxContainer = col.get_meta("hp_row")
		if hp_row != null:
			BattleFx.update_hp_row(hp_row, hp)
	if col != null and col.has_meta("qi_row"):
		var qi_row: HBoxContainer = col.get_meta("qi_row")
		if qi_row != null:
			BattleFx.update_qi_row(qi_row, qi)
	if col != null and col.has_meta("shield_row"):
		var sh: HBoxContainer = col.get_meta("shield_row")
		if sh != null:
			BattleFx.update_shield_row(sh, shield_n)

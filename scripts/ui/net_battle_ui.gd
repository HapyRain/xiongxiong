## net_battle_ui.gd
## 竖版联机对局 UI：对手在上 / 中央亮招对撞舞台 / 我方状态与双层拇指技能盘在下。
## 热座入口已移除（底层 HOTSEAT 仅测试）；对手离开 → 人机接管提示并继续。
extends Control

const SCENE := "res://scenes/net_battle.tscn"

var controller: NetworkedBattleController
var _status_label: Label
var _round_label: Label
var _log_label: Label
var _score_label: Label
var _arena_me_card: Label
var _arena_you_card: Label
var _tempo_root: Control
var _tempo_bg: ColorRect
var _tempo_fill: ColorRect
var _tempo_ticks: Array[ColorRect] = []
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
var _result_card: Control
## 返回菜单二次确认（返回键 / 遮罩「返回菜单」都走这里，确认前不切场景）
var _leave_dialog: Control


func _ready() -> void:
	UiTheme.apply_to_tree(get_tree())
	UiNav.register_back_target(SCENE, UiNav.MENU_SCENE)
	UiNav.register_back_guard(SCENE, _on_back_requested)
	add_child(UiBackRouter.new())
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
	controller.status_text.connect(_on_controller_status)
	# U1：Net 是 autoload，比场景命长；具名连接保证场景释放时自动断开
	Net.actions_revealed.connect(_on_reveal_actions)
	Net.peer_left.connect(_on_peer_left)
	Net.ai_takeover_started.connect(_on_ai_takeover)
	Net.net_state_changed.connect(_on_net_state)
	Net.consent_needed.connect(_on_consent_needed)
	Net.countdown_tick.connect(_on_countdown_tick)
	Net.session_failed.connect(_on_session_failed)
	Net.session_restored.connect(_on_session_restored)
	Net.battle_started.connect(_on_net_battle_started)
	controller.begin()
	_on_phase(controller.state.phase, controller.state.round)
	_refresh_all()


func _on_controller_status(t: String) -> void:
	if _status_label != null:
		_status_label.text = t


func _on_net_battle_started(_snap: Dictionary) -> void:
	_on_battle_started_ui()


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
	margin.add_theme_constant_override("margin_top", 44)
	margin.add_theme_constant_override("margin_bottom", 10)
	add_child(margin)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	margin.add_child(v)

	# 分数条（顶部）：我 = 本地角色座位
	_score_label = UiTheme.ink_label("", 14, UiTheme.INK_SOFT)
	_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_score_label)

	# 对手（上）
	var you_panel := PanelContainer.new()
	you_panel.add_theme_stylebox_override("panel", UiTheme.card_style(UiTheme.BG_CARD, 12, UiTheme.WAVE.lightened(0.35), 2))
	v.add_child(you_panel)
	var you_v := VBoxContainer.new()
	you_v.add_theme_constant_override("separation", 4)
	you_panel.add_child(you_v)
	var you_head := HBoxContainer.new()
	you_v.add_child(you_head)
	var you_title := UiTheme.ink_label("对手", 15, UiTheme.INK)
	you_head.add_child(you_title)
	var you_wait := UiTheme.ink_label("（等待对手选招…）", 12, UiTheme.INK_FAINT)
	you_wait.name = "YouWait"
	you_wait.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	you_wait.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	you_head.add_child(you_wait)
	you_v.add_child(_make_stat_row("you", _you_boxes))

	# 中央对撞舞台
	var center := VBoxContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_theme_constant_override("separation", 4)
	v.add_child(center)

	_takeover_banner = Label.new()
	_takeover_banner.text = ""
	_takeover_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_takeover_banner.add_theme_font_size_override("font_size", 14)
	_takeover_banner.add_theme_color_override("font_color", UiTheme.DANGER)
	_takeover_banner.visible = false
	center.add_child(_takeover_banner)

	_round_label = UiTheme.ink_label("回合 -", 13, UiTheme.INK_SOFT)
	_round_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(_round_label)
	_status_label = UiTheme.ink_label("对局", 19, UiTheme.INK)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(_status_label)

	var duel_row := HBoxContainer.new()
	duel_row.alignment = BoxContainer.ALIGNMENT_CENTER
	duel_row.add_theme_constant_override("separation", 14)
	center.add_child(duel_row)
	duel_row.add_child(_make_arena_slot("我", UiTheme.ACCENT, true))
	duel_row.add_child(UiTheme.ink_label("VS", 15, UiTheme.INK_FAINT))
	duel_row.add_child(_make_arena_slot("对手", UiTheme.WAVE, false))

	_tempo_root = _make_tempo_bar()
	center.add_child(_tempo_root)

	_log_label = UiTheme.ink_label("……", 12, UiTheme.INK_SOFT)
	_log_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	center.add_child(_log_label)

	# 我方（下）：状态卡 + 双层拇指技能盘
	var me_panel := PanelContainer.new()
	me_panel.add_theme_stylebox_override("panel", UiTheme.card_style(UiTheme.BG_CARD, 12, UiTheme.SHIELD.lightened(0.35), 2))
	v.add_child(me_panel)
	var me_v := VBoxContainer.new()
	me_v.add_theme_constant_override("separation", 6)
	me_panel.add_child(me_v)
	var me_title := UiTheme.ink_label("我", 15, UiTheme.INK)
	me_v.add_child(me_title)
	me_v.add_child(_make_stat_row("me", _me_boxes))
	me_v.add_child(_make_skill_deck(0, _me_btns))


func _make_arena_slot(title_str: String, accent: Color, is_me: bool) -> PanelContainer:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(120, 60)
	p.add_theme_stylebox_override("panel", UiTheme.card_style(UiTheme.BG_CARD, 12, accent, 2))
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 2)
	p.add_child(box)
	var t := UiTheme.ink_label(title_str, 11, UiTheme.INK_SOFT)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(t)
	var act_lab := UiTheme.ink_label("待命", 20, accent.darkened(0.1))
	act_lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(act_lab)
	if is_me:
		_arena_me_card = act_lab
	else:
		_arena_you_card = act_lab
	return p


func _make_tempo_bar() -> Control:
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 4)
	wrap.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var cap := UiTheme.ink_label("出招节奏", 11, UiTheme.INK_FAINT)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wrap.add_child(cap)

	_tempo_root = Control.new()
	_tempo_root.custom_minimum_size = Vector2(200, 12)
	_tempo_root.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_tempo_root.clip_contents = true
	_tempo_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(_tempo_root)

	_tempo_bg = ColorRect.new()
	_tempo_bg.color = UiTheme.DISABLED_BG
	_tempo_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tempo_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tempo_root.add_child(_tempo_bg)

	_tempo_fill = ColorRect.new()
	_tempo_fill.color = UiTheme.ACCENT
	_tempo_fill.size = Vector2(0, 12)
	_tempo_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tempo_root.add_child(_tempo_fill)

	_tempo_ticks.clear()
	for p in [0.0, 1.0]:
		var tick := ColorRect.new()
		tick.color = Color(0.06, 0.09, 0.16, 0.45)
		tick.size = Vector2(2, 12)
		tick.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_tempo_root.add_child(tick)
		_tempo_ticks.append(tick)
	return wrap


func _process(_delta: float) -> void:
	if _tempo_fill == null or controller == null:
		return
	var s: BattleState = controller.state
	if s == null:
		return
	var win := controller.window_seconds()
	var left: float = controller.select_left()
	var elapsed: float = win - left
	var t: float = clampf(elapsed / maxf(win, 0.01), 0.0, 1.0)
	var w: float = _tempo_root.size.x if _tempo_root.size.x > 0 else 200.0
	_tempo_fill.size = Vector2(w * t, 12)
	if t >= 0.82:
		_tempo_fill.color = UiTheme.DANGER
	elif t >= 0.55:
		_tempo_fill.color = UiTheme.ACCENT
	else:
		_tempo_fill.color = UiTheme.SHIELD
	if _tempo_ticks.size() >= 2 and win > 0.01:
		var clap := BattleTempo.clap2_at(s.round)
		_tempo_ticks[0].position = Vector2(1, 0)
		_tempo_ticks[1].position = Vector2(clampf(clap / win, 0.0, 1.0) * w - 1.0, 0)
	_tempo_root.visible = controller.window_open() and not s.is_over()
	_refresh_all()


func _make_stat_row(prefix: String, boxes: Array) -> VBoxContainer:
	var s: BattleState = controller.state
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	var hp_row := BattleFx.make_hp_row(s.max_hp(), s.max_hp())
	var qi_row := BattleFx.make_qi_row(s.max_qi(), 0)
	var sh_row := BattleFx.make_shield_row(s.max_shield(), 0)
	if prefix == "me":
		_me_hp_row = hp_row
		_me_qi_row = qi_row
	else:
		_you_hp_row = hp_row
		_you_qi_row = qi_row
	var hp_lab := Label.new()
	hp_lab.name = prefix + "_hp"
	hp_lab.text = "%d/%d" % [s.max_hp(), s.max_hp()]
	var qi_lab := Label.new()
	qi_lab.name = prefix + "_qi"
	qi_lab.text = "0/%d" % s.max_qi()
	var sh_lab := Label.new()
	sh_lab.name = prefix + "_shield"
	sh_lab.text = "0/%d" % s.max_shield()
	boxes.append(hp_lab)
	boxes.append(qi_lab)
	boxes.append(sh_lab)
	col.add_child(BattleFx.make_stat_line("血", hp_row, hp_lab))
	col.add_child(BattleFx.make_stat_line("气", qi_row, qi_lab))
	col.add_child(BattleFx.make_stat_line("盾", sh_row, sh_lab))
	col.set_meta("hp_row", hp_row)
	col.set_meta("qi_row", qi_row)
	col.set_meta("shield_row", sh_row)
	return col


## 双层拇指技能盘：上排 2×4 进阶技能槽（仅课间模式）+ 下排 3 大核心主键（防/攒/包连点）。
func _make_skill_deck(who: int, btns: Dictionary) -> VBoxContainer:
	var s: BattleState = controller.state
	var deck := VBoxContainer.new()
	deck.name = "SkillDeck"
	deck.add_theme_constant_override("separation", 6)

	if s.skills_enabled():
		var grid := GridContainer.new()
		grid.name = "SkillGrid"
		grid.columns = 4
		grid.add_theme_constant_override("h_separation", 6)
		grid.add_theme_constant_override("v_separation", 6)
		for a in GameRules.ADVANCED_SKILLS:
			var act := int(a)
			var b := UiTheme.make_skill_slot(act, false)
			var seat: int = who
			b.pressed.connect(func(): _on_pick(seat, act))
			BattleFx.bind_press(b, "fang" if GameRules.is_defense(act) else "bo")
			grid.add_child(b)
			btns[act] = b
		deck.add_child(grid)

	var primary_row := HBoxContainer.new()
	primary_row.name = "PrimaryRow"
	primary_row.add_theme_constant_override("separation", 8)
	for a in GameRules.PRIMARY_ACTIONS:
		var act := int(a)
		var b := UiTheme.make_skill_slot(act, true)
		var seat: int = who
		if act == GameRules.Action.BAO1:
			b.pressed.connect(func(): _on_bao_pick(seat))
			BattleFx.bind_press(b, "bo")
		elif act == GameRules.Action.ZAN:
			b.pressed.connect(func(): _on_pick(seat, GameRules.Action.ZAN))
			BattleFx.bind_press(b, "zan")
		else:
			b.pressed.connect(func(): _on_pick(seat, GameRules.Action.FANG))
			BattleFx.bind_press(b, "fang")
		primary_row.add_child(b)
		btns[act] = b

	deck.add_child(primary_row)
	return deck


func _on_bao_pick(who: int) -> void:
	if controller == null or controller.state == null:
		return
	var s: BattleState = controller.state
	var mine: int = Net.get_local_role()
	if mine != 0 and mine != 1:
		mine = who
	var pre := controller.local_preselect()
	var cur: int = int(pre[mine]) if pre.size() > mine else -1
	var target_act := UiTheme.next_bao_action(s, mine, cur)
	_on_pick(who, target_act)


func _on_top_menu() -> void:
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


# ---------- 封存 / 同意 / 倒计时 / 终局遮罩 ----------

func _build_overlay() -> void:
	_overlay = Control.new()
	_overlay.name = "NetOverlay"
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.visible = false
	add_child(_overlay)

	var dim := ColorRect.new()
	dim.color = Color(0.06, 0.09, 0.16, 0.62)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(320, 0)
	panel.add_theme_stylebox_override("panel", UiTheme.card_style(UiTheme.BG_CARD, 16, UiTheme.LINE, 2))
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

	_result_card = UiTheme.banner_card("本场战报", "感谢对决！", UiTheme.ACCENT, 84)
	_result_card.visible = false
	v.add_child(_result_card)

	var btn_col := VBoxContainer.new()
	btn_col.add_theme_constant_override("separation", 10)
	btn_col.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(btn_col)

	_btn_continue = UiTheme.make_btn("继续", UiTheme.OK, Color.WHITE, 17, 48)
	_btn_continue.custom_minimum_size = Vector2(200, 48)
	_btn_continue.pressed.connect(func():
		Net.submit_resume_vote(true)
		_show_overlay("countdown", "已同意", "等待对手确认…", false, false, false))
	BattleFx.bind_press(_btn_continue, "menu")
	btn_col.add_child(_btn_continue)

	_btn_decline = UiTheme.make_btn("退出（判负）", UiTheme.DANGER, Color.WHITE, 16, 48)
	_btn_decline.custom_minimum_size = Vector2(200, 48)
	_btn_decline.pressed.connect(func():
		Net.submit_resume_vote(false)
		_show_overlay("fail", "已拒绝继续", "你选择了退出，本局判负", false, false, true))
	BattleFx.bind_press(_btn_decline, "danger")
	btn_col.add_child(_btn_decline)

	_btn_menu = UiTheme.make_btn("返回菜单", UiTheme.LINE, UiTheme.INK, 16, 48)
	_btn_menu.custom_minimum_size = Vector2(200, 48)
	_btn_menu.pressed.connect(_request_leave)
	BattleFx.bind_press(_btn_menu, "menu")
	btn_col.add_child(_btn_menu)

	_btn_rematch = UiTheme.make_btn("再来一局", UiTheme.ACCENT, Color.WHITE, 17, 48)
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
	if _result_card != null:
		_result_card.visible = mode == "game_over" or mode == "rematch"


func _hide_overlay() -> void:
	_overlay_mode = ""
	_overlay.visible = false
	if _result_card != null:
		_result_card.visible = false
	_set_input_buttons_enabled(true)


func _set_input_buttons_enabled(on: bool) -> void:
	for b in _me_btns.values():
		b.disabled = not on


func _on_peer_left(_id: int, reason: String) -> void:
	_log("对手离开：%s" % reason)


func _on_ai_takeover(reason: String) -> void:
	_takeover_banner.text = UiNav.peer_left_text()
	_takeover_banner.visible = true
	_log("对手已离开（%s），由人机接管" % reason)
	if _overlay_mode in ["sealed", "countdown", "resuming", "consent"]:
		_hide_overlay()
	_show_overlay("takeover", "对手已离开", "由人机接管，对局继续…", false, false, false)
	var t := get_tree()
	if t != null:
		t.create_timer(1.6).timeout.connect(_hide_takeover_overlay)


func _hide_takeover_overlay() -> void:
	if _overlay_mode == "takeover":
		_hide_overlay()


func _on_net_state(state_name: String, reason: String) -> void:
	match state_name:
		"Degraded":
			_log("网络不佳（%s）" % reason)
		"Sealed":
			_show_overlay("sealed", "连接中断", "已封存对局，等待链路恢复…\n（%s）" % reason, false, false, true)
		"AwaitingConsent":
			pass
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
		body = "对手未恢复，你获胜（%s）\n可返回菜单。" % reason
	_show_overlay("fail", "对局结束", body, false, false, true)


func _on_session_restored(_snap: Dictionary) -> void:
	_hide_overlay()
	_refresh_all()
	_log("已从快照恢复")


func _on_beat(_n: int) -> void:
	var clap_pitch := 1.0
	if controller != null and controller.state != null:
		clap_pitch = BattleTempo.clap_pitch(controller.state.round)
	for p: AudioStreamPlayer in _sfx_players:
		if p.stream == _sfx_clap and p.playing:
			p.pitch_scale = clap_pitch
	_play_sfx(_sfx_clap, -2.0)
	for p: AudioStreamPlayer in _sfx_players:
		if p.stream == _sfx_clap and p.playing:
			p.pitch_scale = clap_pitch
	if _status_label != null and controller != null and controller.window_open():
		_status_label.text = "出招中"


func _on_resolved(result: Dictionary) -> void:
	_hide_spotlight()
	var mine: int = Net.get_local_role()
	var texts: Array = result.get("texts", [])
	var text := str(texts[mine]) if texts.size() > mine else str(result.get("text", ""))
	_log(text)
	if not bool(result.get("opening", false)) and text != "":
		_status_label.text = text
	var acts: Array = result.get("actions", [-1, -1])
	if acts.size() >= 2:
		if _arena_me_card != null:
			_arena_me_card.text = GameRules.action_short_name(int(acts[mine]))
		if _arena_you_card != null:
			_arena_you_card.text = GameRules.action_short_name(int(acts[1 - mine]))
	_refresh_all()
	_play_reveal_cards(result)
	_play_impact_fx(result)
	_play_impact_sfx(result)


func _on_pick(who: int, action: int) -> void:
	if action == GameRules.Action.ZAN:
		_hide_spotlight()
	if controller.try_select(who, action):
		_play_sfx(_sfx_zan if action == GameRules.Action.ZAN else _sfx_ding, -6.0)
		_log("已选 %s" % GameRules.action_short_name(action))
		_refresh_all()
	else:
		_log("当前无法出招")


func _show_spotlight() -> void:
	if _spot_layer != null and is_instance_valid(_spot_layer):
		return
	var zan_btn: Button = _me_btns.get(GameRules.Action.ZAN) as Button
	if zan_btn == null:
		return
	_spot_layer = BattleFx.show_focus_spotlight(get_tree(), zan_btn, "点击「攒气」开始对决")


func _hide_spotlight() -> void:
	if _spot_layer != null and is_instance_valid(_spot_layer):
		BattleFx.hide_focus_spotlight(_spot_layer)
	_spot_layer = null


func _exit_tree() -> void:
	_hide_spotlight()


func _on_preselect(who: int, action: int) -> void:
	var mine: int = Net.get_local_role()
	if who == mine:
		_log("我方已选 %s" % GameRules.action_short_name(action))
	else:
		_log("对手已选")
	_refresh_all()


func _on_battle_started_ui() -> void:
	_hide_overlay()


func _on_phase(phase: int, round_no: int) -> void:
	_round_label.text = "回合 %d / %d" % [round_no, controller.state.round_cap()]
	var is_opening: bool = round_no == GameRules.OPENING_ROUND and controller != null \
		and not controller.opening_done()
	match phase:
		GameRules.Phase.SELECTING:
			if is_opening:
				_status_label.text = "点击「攒气」开始对决"
				_show_spotlight()
			else:
				_status_label.text = "同步出招"
				_hide_spotlight()
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
	if UiNav.is_settings_open(get_tree()):
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
	dim.color = Color(0.06, 0.09, 0.16, 0.25)
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
	var timeouts: Array = result.get("timeout", [false, false])
	var mine: int = Net.get_local_role()
	var my_act: int = int(acts[mine]) if acts.size() > mine else -1
	var op_act: int = int(acts[1 - mine]) if acts.size() > (1 - mine) else -1
	var my_to: bool = bool(timeouts[mine]) if timeouts.size() > mine else false
	var op_to: bool = bool(timeouts[1 - mine]) if timeouts.size() > (1 - mine) else false
	var me_card := _make_action_card("我", GameRules.action_short_name(my_act), UiTheme.action_color(my_act), my_to)
	var you_card := _make_action_card("对手", GameRules.action_short_name(op_act), UiTheme.action_color(op_act), op_to)
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
		t.create_timer(BattleTempo.result_hold()).timeout.connect(_free_reveal_layer)


func _free_reveal_layer() -> void:
	if _reveal_layer != null and is_instance_valid(_reveal_layer):
		_reveal_layer.queue_free()
		_reveal_layer = null


func _make_action_card(title: String, action: String, accent: Color, is_timeout: bool = false) -> PanelContainer:
	var panel := PanelContainer.new()
	var sb := UiTheme.card_style(UiTheme.BG_CARD, 16, accent, 3)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	panel.add_child(v)
	v.add_child(UiTheme.ink_label(title, 13, UiTheme.INK_SOFT))
	var act := UiTheme.ink_label(action, 32, accent)
	act.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(act)
	if is_timeout:
		var badge := UiTheme.make_btn("超时", UiTheme.DANGER, Color.WHITE, 11, 22)
		badge.custom_minimum_size = Vector2(52, 22)
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(badge)
	return panel


func _play_impact_fx(result: Dictionary) -> void:
	if _fx_layer == null or bool(result.get("opening", false)):
		return
	if UiNav.is_settings_open(get_tree()):
		return
	if _fx_layer.get_parent() != null:
		_fx_layer.get_parent().move_child(_fx_layer, _fx_layer.get_parent().get_child_count() - 1)
	var hit: Array = result.get("hit", [false, false])
	var blocked: Array = result.get("blocked", [false, false])
	var mine: int = Net.get_local_role()
	var me_target: Control = _me_hp_row.get_parent() as Control if _me_hp_row else self
	var you_target: Control = _you_hp_row.get_parent() as Control if _you_hp_row else self
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
		_log("亮招：我 %s ｜ 对手 %s" % [
			GameRules.action_short_name(int(actions[mine])),
			GameRules.action_short_name(int(actions[other])),
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
		_status_label.text = "对手胜利"
		body = "对手获胜。终局 HP %s" % str(s.hp)
	for b in _me_btns.values():
		b.disabled = true
	var view_win: int = winner if winner == 2 or winner < 0 else (0 if winner == mine else 1)
	if _fx_layer != null:
		BattleFx.play_result(_fx_layer, view_win, _status_label)
	_show_overlay("game_over", "对局结束", body + "\n再来一局，还是回菜单？", false, false, true)
	if _btn_rematch != null:
		_btn_rematch.visible = true
		_btn_rematch.disabled = false
		_btn_rematch.text = "再来一局"
		if _btn_rematch.pressed.is_connected(_on_rematch_yes):
			_btn_rematch.pressed.disconnect(_on_rematch_yes)
		if not _btn_rematch.pressed.is_connected(_on_rematch_click):
			_btn_rematch.pressed.connect(_on_rematch_click)
	if not Net.rematch_offer.is_connected(_on_rematch_offer):
		Net.rematch_offer.connect(_on_rematch_offer, CONNECT_ONE_SHOT)
	if not Net.rematch_answered.is_connected(_on_rematch_answered):
		Net.rematch_answered.connect(_on_rematch_answered, CONNECT_ONE_SHOT)


func _on_rematch_click() -> void:
	if _btn_rematch != null:
		_btn_rematch.disabled = true
		_btn_rematch.text = "等待对手…"
	Net.request_rematch()


func _on_rematch_offer() -> void:
	_overlay_mode = "rematch"
	_overlay.visible = true
	_overlay_title.text = "再来一局？"
	_overlay_body.text = "对手想再来一局，是否开始？"
	_btn_continue.visible = false
	_btn_decline.visible = false
	_btn_menu.visible = true
	_btn_menu.text = "回菜单"
	_btn_rematch.visible = true
	_btn_rematch.disabled = false
	_btn_rematch.text = "开始新局"
	_set_input_buttons_enabled(false)
	if _btn_rematch.pressed.is_connected(_on_rematch_click):
		_btn_rematch.pressed.disconnect(_on_rematch_click)
	if not _btn_rematch.pressed.is_connected(_on_rematch_yes):
		_btn_rematch.pressed.connect(_on_rematch_yes, CONNECT_ONE_SHOT)


func _on_rematch_yes() -> void:
	_hide_overlay()
	_btn_rematch.text = "再来一局"
	_btn_menu.text = "返回菜单"
	Net.answer_rematch(true)


# ---------- 返回菜单：二次确认 ----------

func _on_back_requested() -> bool:
	if _leave_dialog != null and is_instance_valid(_leave_dialog):
		_close_leave_dialog()
		return true
	_request_leave()
	return true


func _request_leave() -> void:
	if _leave_dialog != null and is_instance_valid(_leave_dialog):
		return
	var layer := Control.new()
	layer.name = "LeaveConfirm"
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(layer)

	var dim := ColorRect.new()
	dim.color = Color(0.06, 0.09, 0.16, 0.5)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(300, 0)
	panel.add_theme_stylebox_override("panel", UiTheme.card_style())
	center.add_child(panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	panel.add_child(v)
	var title := UiTheme.ink_label("离开对局？", 20, UiTheme.INK)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var body := UiTheme.ink_label(UiNav.leave_confirm_text(), 13, UiTheme.INK_SOFT)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(260, 48)
	v.add_child(body)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	v.add_child(row)
	var yes := UiTheme.make_btn("确定", UiTheme.DANGER, Color.WHITE, 16, 44)
	yes.name = "LeaveConfirmYes"
	yes.custom_minimum_size.x = 120
	yes.pressed.connect(_confirm_leave)
	BattleFx.bind_press(yes, "danger")
	row.add_child(yes)
	var no := UiTheme.make_btn("取消", UiTheme.LINE, UiTheme.INK, 16, 44)
	no.name = "LeaveConfirmNo"
	no.custom_minimum_size.x = 120
	no.pressed.connect(_close_leave_dialog)
	BattleFx.bind_press(no, "menu")
	row.add_child(no)
	_leave_dialog = layer


func _confirm_leave() -> void:
	_close_leave_dialog()
	if _overlay_mode == "rematch":
		Net.answer_rematch(false)
	UiNav.return_to_menu(get_tree())


func _close_leave_dialog() -> void:
	if _leave_dialog != null and is_instance_valid(_leave_dialog):
		_leave_dialog.queue_free()
	_leave_dialog = null


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
		_show_overlay("game_over", "已结束", "对手不想再来一局，返回菜单。", false, false, true)
		var t := get_tree()
		if t != null:
			t.create_timer(1.2).timeout.connect(_leave_menu_after_decline)


func _leave_menu_after_decline() -> void:
	var t := get_tree()
	if t != null:
		UiNav.return_to_menu(t)


func _log(t: String) -> void:
	if _log_label != null:
		_log_label.text = t


func _refresh_all() -> void:
	if controller == null:
		return
	var s: BattleState = controller.state
	var mine: int = Net.get_local_role()
	if mine != 0 and mine != 1:
		mine = 0
	_set_row(_me_boxes, s, mine)
	_set_row(_you_boxes, s, 1 - mine)
	if _score_label != null:
		_score_label.text = "比分 我 %d : %d 对手 · 先到 %d 分" % [int(s.score[mine]), int(s.score[1 - mine]), s.score_to_win()]
	var input_ok: bool = controller.is_pick_open()
	var can_lock: bool = input_ok and _overlay.visible == false
	var preselect: Array = controller.local_preselect()
	var picked: int = int(preselect[mine]) if preselect.size() > mine else -1
	for a in _me_btns.keys():
		var b: Button = _me_btns[a]
		var act := int(a)
		UiTheme.update_skill_slot(b, s, mine, act, can_lock, picked, GameRules.PRIMARY_ACTIONS.has(act))
	if can_lock and _arena_me_card != null:
		_arena_me_card.text = GameRules.action_short_name(picked) if picked >= 0 else "待选"
	if not can_lock and _overlay != null and not _overlay.visible and not s.is_over():
		if _status_label != null and controller != null and (controller.resolving() or controller.did_settle()):
			_status_label.text = "结算中"
		elif _status_label != null and controller != null and controller.did_lock_fill():
			_status_label.text = "已封盘"
	elif picked >= 0 and can_lock:
		_status_label.text = "已选：%s（可改）" % GameRules.action_short_name(picked)
	elif not input_ok and _overlay != null and not _overlay.visible and not s.is_over():
		if _log_label != null and _log_label.text == "……":
			_log_label.text = "网络同步中，请稍候…"


func _set_row(boxes: Array, s: BattleState, i: int) -> void:
	if boxes.size() < 3:
		return
	if i < 0 or i > 1:
		i = 0
	var hp := clampi(int(s.hp[i]), 0, s.max_hp())
	var qi := clampi(int(s.qi[i]), 0, s.max_qi())
	var shield_n := clampi(int(s.shield[i]), 0, s.max_shield())
	boxes[0].text = "血 %d/%d" % [hp, s.max_hp()]
	boxes[1].text = "气 %d/%d" % [qi, s.max_qi()]
	boxes[2].text = "盾 %d/%d" % [shield_n, s.max_shield()]
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

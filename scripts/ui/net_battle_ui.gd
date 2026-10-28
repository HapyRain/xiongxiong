## net_battle_ui.gd
## 1080P (1080×1920) 竖版联机对局 UI（v3 全屏三渲二特效 · 炉石烧绳锚点 · 街机双层技能盘版）：
##   底层：1080P 三渲二夕阳天台对决舞台背景（stage_bg_cel.png）
##   顶部：比分条 + 右上角唯一「菜单」按钮 + 对手街机状态卡（带赤焰熊头像）
##   中部：正中偏上 MOBA 击杀感博弈横幅 + 双侧三渲二亮招对撞卡 + 右下贴边「5 轮打字机上推记招器」+ 炉石烧绳分界条
##   底部：我方街机状态卡（带金罡熊头像）+ 四态双层拇指技能盘 + 随回合推进紧绷感 BGM
extends Control

const SCENE := "res://scenes/net_battle.tscn"

var controller: NetworkedBattleController
var _status_label: Label
var _round_label: Label
var _log_label: Label
var _score_label: Label
var _you_wait_label: Label
var _moba_banner: PanelContainer
var _ticker: PanelContainer
var _me_duel_card: PanelContainer
var _you_duel_card: PanelContainer
var _rope_bar: PanelContainer
var _me_boxes: Array = []
var _you_boxes: Array = []
var _me_btns: Dictionary = {}
var _takeover_banner: Label
var _me_hp_row: HBoxContainer
var _me_qi_row: HBoxContainer
var _you_hp_row: HBoxContainer
var _you_qi_row: HBoxContainer
var _me_panel: PanelContainer
var _you_panel: PanelContainer
var _fx_layer: Control
var _spot_layer: Control
var _audio_bank: Dictionary = {}
var _active_round: int = 1

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
	_audio_bank = BattleFx.setup_audio_bank(self)
	_build_ui()
	_build_overlay()
	controller.beat.connect(_on_beat)
	controller.preselect_changed.connect(_on_preselect)
	controller.phase_changed.connect(_on_phase)
	controller.round_resolved.connect(_on_resolved)
	controller.game_over.connect(_on_game_over)
	controller.status_text.connect(_on_controller_status)
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
	BattleFx.start_bgm(_audio_bank)
	BattleFx.play_named_sfx(_audio_bank, "game_start", 0.0)
	_on_phase(controller.state.phase, controller.state.round)
	_refresh_all()


func _on_controller_status(t: String) -> void:
	if _status_label != null:
		_status_label.text = t


func _on_net_battle_started(_snap: Dictionary) -> void:
	_on_battle_started_ui()


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.name = "Bg"
	bg.color = UiTheme.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	UiTheme.add_stage_background(self, 0.10)

	# 右上角唯一「菜单」按钮（QualitySettings 已在对局场景自动隐藏常驻设置键，无重叠）
	var top_menu := UiTheme.make_btn("菜单", UiTheme.BG_DARK_CARD, Color.WHITE, 28, 68)
	top_menu.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	top_menu.offset_left = -164
	top_menu.offset_top = 18
	top_menu.offset_right = -26
	top_menu.offset_bottom = 86
	top_menu.pressed.connect(_on_top_menu)
	BattleFx.bind_press(top_menu, "menu")
	add_child(top_menu)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 26)
	margin.add_theme_constant_override("margin_right", 26)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_bottom", 20)
	add_child(margin)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	margin.add_child(v)

	# 顶部比分条
	var top_bar := HBoxContainer.new()
	top_bar.custom_minimum_size = Vector2(0, 64)
	top_bar.add_theme_constant_override("separation", 20)
	v.add_child(top_bar)

	_round_label = UiTheme.ink_label("回合 1/40", 30, Color(1.0, 0.96, 0.85), 6, UiTheme.INK)
	top_bar.add_child(_round_label)

	_score_label = UiTheme.ink_label("", 30, Color.WHITE, 6, UiTheme.INK)
	top_bar.add_child(_score_label)

	# 对手街机状态卡（上，带赤焰熊头像）
	_you_panel = PanelContainer.new()
	var you_sb := UiTheme.card_style(UiTheme.BG_DARK_CARD, 22, UiTheme.WAVE, 4)
	you_sb.content_margin_left = 18
	you_sb.content_margin_right = 18
	you_sb.content_margin_top = 10
	you_sb.content_margin_bottom = 10
	_you_panel.add_theme_stylebox_override("panel", you_sb)
	v.add_child(_you_panel)

	var you_main := HBoxContainer.new()
	you_main.add_theme_constant_override("separation", 18)
	_you_panel.add_child(you_main)

	var you_av := TextureRect.new()
	you_av.texture = UiTheme.load_ui_texture("avatar_bear_opp.png")
	you_av.custom_minimum_size = Vector2(156, 96)
	you_av.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	you_av.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	you_av.mouse_filter = Control.MOUSE_FILTER_IGNORE
	you_main.add_child(you_av)

	var you_v := VBoxContainer.new()
	you_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	you_v.add_theme_constant_override("separation", 4)
	you_main.add_child(you_v)

	var you_head := HBoxContainer.new()
	you_v.add_child(you_head)
	var you_title := UiTheme.ink_label("对手", 28, Color.WHITE, 6, UiTheme.INK)
	you_head.add_child(you_title)
	_you_wait_label = UiTheme.ink_label("（等待对手选招…）", 22, UiTheme.WAVE.lightened(0.35), 4, UiTheme.INK)
	_you_wait_label.name = "YouWait"
	_you_wait_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_you_wait_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	you_head.add_child(_you_wait_label)
	you_v.add_child(_make_stat_row("you", _you_boxes))

	# 中央全屏三渲二交锋舞台
	var center := VBoxContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.add_theme_constant_override("separation", 10)
	v.add_child(center)

	_takeover_banner = UiTheme.ink_label("", 26, UiTheme.DANGER, 5, UiTheme.INK)
	_takeover_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_takeover_banner.visible = false
	center.add_child(_takeover_banner)

	_moba_banner = BattleFx.make_moba_banner()
	center.add_child(_moba_banner)

	_status_label = UiTheme.ink_label("对局", 26, UiTheme.INK_SOFT)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.visible = false
	center.add_child(_status_label)

	var stage_mid := VBoxContainer.new()
	stage_mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage_mid.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(stage_mid)

	var duel_row := HBoxContainer.new()
	duel_row.alignment = BoxContainer.ALIGNMENT_CENTER
	duel_row.add_theme_constant_override("separation", 36)
	stage_mid.add_child(duel_row)
	_me_duel_card = BattleFx.make_duel_card("我", UiTheme.ACCENT)
	_you_duel_card = BattleFx.make_duel_card("对手", UiTheme.WAVE)
	duel_row.add_child(_me_duel_card)
	duel_row.add_child(UiTheme.ink_label("⚡VS⚡", 42, Color(1.0, 0.90, 0.35), 10, UiTheme.INK))
	duel_row.add_child(_you_duel_card)

	var ticker_row := HBoxContainer.new()
	ticker_row.alignment = BoxContainer.ALIGNMENT_END
	center.add_child(ticker_row)
	_ticker = BattleFx.make_battle_ticker()
	ticker_row.add_child(_ticker)

	_rope_bar = BattleFx.make_burning_rope_bar()
	center.add_child(_rope_bar)

	_log_label = UiTheme.ink_label("……", 22, UiTheme.INK_SOFT)
	_log_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_log_label.visible = false
	center.add_child(_log_label)

	# 我方（下）：街机状态栏（带金罡熊头像）+ 双层四态拇指技能盘
	_me_panel = PanelContainer.new()
	var me_sb := UiTheme.card_style(UiTheme.BG_DARK_CARD, 22, UiTheme.SHIELD, 4)
	me_sb.content_margin_left = 18
	me_sb.content_margin_right = 18
	me_sb.content_margin_top = 10
	me_sb.content_margin_bottom = 10
	_me_panel.add_theme_stylebox_override("panel", me_sb)
	v.add_child(_me_panel)

	var me_main := HBoxContainer.new()
	me_main.add_theme_constant_override("separation", 18)
	_me_panel.add_child(me_main)

	var me_av := TextureRect.new()
	me_av.texture = UiTheme.load_ui_texture("avatar_bear_me.png")
	me_av.custom_minimum_size = Vector2(156, 96)
	me_av.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	me_av.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	me_av.mouse_filter = Control.MOUSE_FILTER_IGNORE
	me_main.add_child(me_av)

	var me_v := VBoxContainer.new()
	me_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	me_v.add_theme_constant_override("separation", 4)
	me_main.add_child(me_v)
	var me_title := UiTheme.ink_label("我", 28, Color.WHITE, 6, UiTheme.INK)
	me_v.add_child(me_title)
	me_v.add_child(_make_stat_row("me", _me_boxes))

	v.add_child(_make_skill_deck(0, _me_btns))

	_fx_layer = Control.new()
	_fx_layer.name = "FxLayer"
	_fx_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fx_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fx_layer)
	BattleFx.ensure_cel_canvas(_fx_layer)


func _process(_delta: float) -> void:
	if _rope_bar == null or controller == null:
		return
	var s: BattleState = controller.state
	if s == null:
		return
	var win := controller.window_seconds()
	var left: float = controller.select_left()
	var open := controller.window_open() and not s.is_over()
	BattleFx.update_burning_rope_bar(_rope_bar, win, left, s.round, open)
	_refresh_all()


func _make_stat_row(prefix: String, boxes: Array) -> VBoxContainer:
	var s: BattleState = controller.state
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
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

	var vitals_row := HBoxContainer.new()
	vitals_row.add_theme_constant_override("separation", 18)
	vitals_row.add_child(BattleFx.make_stat_line("血", hp_row, hp_lab))
	vitals_row.add_child(BattleFx.make_stat_line("盾", sh_row, sh_lab))
	col.add_child(vitals_row)
	col.add_child(BattleFx.make_stat_line("气", qi_row, qi_lab))

	col.set_meta("hp_row", hp_row)
	col.set_meta("qi_row", qi_row)
	col.set_meta("shield_row", sh_row)
	return col


func _make_skill_deck(who: int, btns: Dictionary) -> VBoxContainer:
	var s: BattleState = controller.state
	var deck := VBoxContainer.new()
	deck.name = "SkillDeck"
	deck.add_theme_constant_override("separation", 12)

	if s.skills_enabled():
		var grid := GridContainer.new()
		grid.name = "SkillGrid"
		grid.columns = 4
		grid.add_theme_constant_override("h_separation", 12)
		grid.add_theme_constant_override("v_separation", 12)
		for a in GameRules.ADVANCED_SKILLS:
			var act := int(a)
			var b := UiTheme.make_skill_slot(act, false, _on_skill_rejected)
			var seat: int = who
			b.pressed.connect(func(): _on_pick(seat, act))
			BattleFx.bind_press(b, GameRules.action_category(act))
			grid.add_child(b)
			btns[act] = b
		deck.add_child(grid)

	var primary_row := HBoxContainer.new()
	primary_row.name = "PrimaryRow"
	primary_row.add_theme_constant_override("separation", 16)
	for a in GameRules.PRIMARY_ACTIONS:
		var act := int(a)
		var b := UiTheme.make_skill_slot(act, true, _on_skill_rejected)
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


func _on_skill_rejected(_act: int, reason: String) -> void:
	BattleFx.play_named_sfx(_audio_bank, "ui_deny", 0.5)
	BattleFx.show_moba_banner(_moba_banner, reason, "请改选其它可用招式", UiTheme.DANGER, true)


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
	dim.color = Color(0.04, 0.06, 0.12, 0.68)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(820, 0)
	panel.add_theme_stylebox_override("panel", UiTheme.card_style(UiTheme.BG_CARD, 28, UiTheme.INK, 5))
	center.add_child(panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 24)
	panel.add_child(v)

	_overlay_title = UiTheme.ink_label("", 48, UiTheme.INK)
	_overlay_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_overlay_title)

	_overlay_body = UiTheme.ink_label("", 28, UiTheme.INK_SOFT)
	_overlay_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlay_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_overlay_body.custom_minimum_size = Vector2(720, 110)
	v.add_child(_overlay_body)

	_result_card = UiTheme.banner_card("本场战报", "感谢对决！", UiTheme.ACCENT, 180)
	_result_card.visible = false
	v.add_child(_result_card)

	var btn_col := VBoxContainer.new()
	btn_col.add_theme_constant_override("separation", 20)
	btn_col.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(btn_col)

	_btn_continue = UiTheme.make_btn("继续", UiTheme.OK_GREEN, Color.WHITE, 34, 104)
	_btn_continue.custom_minimum_size = Vector2(520, 104)
	_btn_continue.pressed.connect(func():
		Net.submit_resume_vote(true)
		_show_overlay("countdown", "已同意", "等待对手确认…", false, false, false))
	BattleFx.bind_press(_btn_continue, "menu")
	btn_col.add_child(_btn_continue)

	_btn_decline = UiTheme.make_btn("退出（判负）", UiTheme.DANGER, Color.WHITE, 32, 104)
	_btn_decline.custom_minimum_size = Vector2(520, 104)
	_btn_decline.pressed.connect(func():
		Net.submit_resume_vote(false)
		_show_overlay("fail", "已拒绝继续", "你选择了退出，本局判负", false, false, true))
	BattleFx.bind_press(_btn_decline, "danger")
	btn_col.add_child(_btn_decline)

	_btn_menu = UiTheme.make_btn("返回菜单", UiTheme.BG_PANEL, UiTheme.INK, 32, 104)
	_btn_menu.custom_minimum_size = Vector2(520, 104)
	_btn_menu.pressed.connect(_request_leave)
	BattleFx.bind_press(_btn_menu, "menu")
	btn_col.add_child(_btn_menu)

	_btn_rematch = UiTheme.make_btn("再来一局", UiTheme.ACCENT, Color.WHITE, 34, 108)
	_btn_rematch.custom_minimum_size = Vector2(520, 108)
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


func _on_beat(n: int) -> void:
	var clap_pitch := 1.0
	if controller != null and controller.state != null:
		clap_pitch = BattleTempo.clap_pitch(controller.state.round)
	BattleFx.play_named_sfx(_audio_bank, "clap", 1.0, clap_pitch)
	BattleFx.play_beat_pulse(_fx_layer, n, _me_duel_card, _you_duel_card)
	if _status_label != null and controller != null and controller.window_open():
		_status_label.text = "出招中"


func _on_resolved(result: Dictionary) -> void:
	_hide_spotlight()
	var mine: int = Net.get_local_role()
	if mine != 0 and mine != 1:
		mine = 0
	var texts: Array = result.get("texts", [])
	var text := str(texts[mine]) if texts.size() > mine else str(result.get("text", ""))
	_log(text)
	if not bool(result.get("opening", false)) and text != "":
		_status_label.text = text
	_refresh_all()

	var r_copy := result.duplicate(true)
	if not r_copy.has("round"):
		r_copy["round"] = _active_round

	if _fx_layer != null and _overlay != null:
		move_child(_fx_layer, _overlay.get_index())
	BattleFx.play_clash_director(
		_fx_layer,
		controller.state if controller != null else null,
		r_copy,
		mine,
		_me_panel if _me_panel != null else self,
		_you_panel if _you_panel != null else self,
		_moba_banner,
		_ticker,
		_audio_bank,
		_me_duel_card,
		_you_duel_card
	)


func _on_pick(who: int, action: int) -> void:
	if action == GameRules.Action.ZAN:
		_hide_spotlight()
	if controller.try_select(who, action):
		if action == GameRules.Action.ZAN:
			BattleFx.play_named_sfx(_audio_bank, "zan", 0.0, 1.0)
		elif GameRules.is_bao(action):
			var cnt := GameRules.bao_count(action)
			BattleFx.play_named_sfx(_audio_bank, "ui_select", 0.5, 1.0 + float(cnt - 1) * 0.16)
		else:
			BattleFx.play_named_sfx(_audio_bank, "ui_select", 0.5, 1.05)
		BattleFx.show_moba_banner(
			_moba_banner,
			"✓ 已锁定：【%s】" % GameRules.action_short_name(action),
			UiTheme.action_hint(action) + " · 封盘前可随时改选",
			UiTheme.action_color(action),
			false
		)
		BattleFx.play_skill_select_vfx(_fx_layer, action, _me_duel_card)
		_log("已选 %s" % GameRules.action_short_name(action))
		_refresh_all()
	else:
		BattleFx.play_named_sfx(_audio_bank, "ui_deny", 0.5)
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
	BattleFx.stop_bgm(_audio_bank)
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
	BattleFx.clear_ticker(_ticker)
	BattleFx.start_bgm(_audio_bank)
	BattleFx.play_named_sfx(_audio_bank, "game_start", 0.0)


func _on_phase(phase: int, round_no: int) -> void:
	if phase == GameRules.Phase.SELECTING:
		_active_round = maxi(1, round_no)
	_round_label.text = "回合 %d / %d" % [round_no, controller.state.round_cap()]
	if controller != null and controller.state != null:
		BattleFx.update_bgm_tension(_audio_bank, controller.state)
	var s: BattleState = controller.state if controller != null else null
	var mine: int = Net.get_local_role()
	if mine != 0 and mine != 1:
		mine = 0
	var is_opening: bool = round_no == GameRules.OPENING_ROUND and controller != null \
		and not controller.opening_done()
	match phase:
		GameRules.Phase.SELECTING:
			if is_opening:
				_status_label.text = "点击「攒气」开始对决"
				BattleFx.show_moba_banner(_moba_banner, "⚡ 点击「攒气」开始对决 ⚡", "第 1 回合开局亮相 · 双方气 +1", UiTheme.ACCENT, false)
				_show_spotlight()
			elif s != null and s.quan_jiang_enabled() and int(s.qi[mine]) == s.max_qi() and int(s.hp[mine]) == s.max_hp() and int(s.hp[1 - mine]) == 1:
				_status_label.text = "劝降就绪"
				BattleFx.show_moba_banner(_moba_banner, "👑 劝降条件已达成！", "我方满气满血 vs 对手 1 血 · 本拍任意出招即刻获胜！", UiTheme.ACCENT, true)
				_hide_spotlight()
			else:
				_status_label.text = "同步出招"
				BattleFx.show_moba_banner(_moba_banner, "🎯 第 %d 回合 · 同步选招" % round_no, "烧绳结束前点选技能 · 预判对手招式", UiTheme.SHIELD, false)
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
		BattleFx.play_result(_fx_layer, view_win, _moba_banner)
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
	dim.color = Color(0.04, 0.06, 0.12, 0.65)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(760, 0)
	panel.add_theme_stylebox_override("panel", UiTheme.card_style())
	center.add_child(panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 24)
	panel.add_child(v)
	var title := UiTheme.ink_label("离开对局？", 44, UiTheme.INK)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var body := UiTheme.ink_label(UiNav.leave_confirm_text(), 28, UiTheme.INK_SOFT)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(680, 100)
	v.add_child(body)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 28)
	v.add_child(row)
	var yes := UiTheme.make_btn("确定", UiTheme.DANGER, Color.WHITE, 34, 96)
	yes.name = "LeaveConfirmYes"
	yes.custom_minimum_size.x = 280
	yes.pressed.connect(_confirm_leave)
	BattleFx.bind_press(yes, "danger")
	row.add_child(yes)
	var no := UiTheme.make_btn("取消", UiTheme.BG_PANEL, UiTheme.INK, 34, 96)
	no.name = "LeaveConfirmNo"
	no.custom_minimum_size.x = 280
	no.pressed.connect(_close_leave_dialog)
	BattleFx.bind_press(no, "menu")
	row.add_child(no)
	_leave_dialog = layer


func _confirm_leave() -> void:
	_close_leave_dialog()
	BattleFx.stop_bgm(_audio_bank)
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
		BattleFx.clear_ticker(_ticker)
		BattleFx.start_bgm(_audio_bank)
		BattleFx.play_named_sfx(_audio_bank, "game_start", 0.0)
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
		BattleFx.stop_bgm(_audio_bank)
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
	var op: int = 1 - mine
	_set_row(_me_boxes, s, mine)
	_set_row(_you_boxes, s, op)
	if _score_label != null:
		_score_label.text = "我 %d : %d 对手 · 先到 %d 分" % [int(s.score[mine]), int(s.score[op]), s.score_to_win()]
	var input_ok: bool = controller.is_pick_open()
	var can_lock: bool = input_ok and _overlay.visible == false
	var preselect: Array = controller.local_preselect()
	var picked: int = int(preselect[mine]) if preselect.size() > mine else -1
	for a in _me_btns.keys():
		var b: Button = _me_btns[a]
		var act := int(a)
		UiTheme.update_skill_slot(b, s, mine, act, can_lock, picked, GameRules.PRIMARY_ACTIONS.has(act))
	if _you_wait_label != null:
		var opp_seal := "[封盾] " if s.is_sealed(op) else ""
		var opp_wait := "（等待对手选招…）" if can_lock else "（已锁定）"
		_you_wait_label.text = opp_seal + opp_wait
	if can_lock and _me_duel_card != null:
		BattleFx.update_duel_card(_me_duel_card, picked, "待选", false)
	if can_lock and _you_duel_card != null:
		BattleFx.update_duel_card(_you_duel_card, -1, "…", false)
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
	boxes[0].text = "%d/%d" % [hp, s.max_hp()]
	boxes[1].text = "%d/%d" % [qi, s.max_qi()]
	boxes[2].text = "%d/%d" % [shield_n, s.max_shield()]
	var src: Control = boxes[1].get_parent() as Control
	var col: Control = src.get_parent() as Control if src != null else null
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

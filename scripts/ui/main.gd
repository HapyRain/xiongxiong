## main.gd
## 单人对战页（正式视觉）：
##   顶部：回合/比分条 + 对手血/气/盾状态卡（OppSlot）
##   中部：中央对撞舞台（双侧亮招卡 + 拍点倒计时条 + 战报）（RevealSlot）
##   底部：我方血/气/盾状态卡（MeSlot）+ 双层拇指操作盘（2×4 进阶技能槽 + 3 大核心主键）（BottomSlot）
extends Control

const SCENE := "res://scenes/main.tscn"
const SOLO_SCENE := "res://scenes/solo_select.tscn"
const DEFAULT_CFG := {"mode": "lesson", "mastery": false, "difficulty": "normal"}

@onready var controller: BattleController = $BattleController
@onready var info_label: Label = %InfoLabel
@onready var result_label: Label = %ResultLabel
## 对手资源槽（命名与内容一致；勿叫 YouSlot）
@onready var opp_slot: VBoxContainer = %OppSlot
@onready var reveal_slot: VBoxContainer = %RevealSlot
@onready var bottom_slot: VBoxContainer = %BottomSlot
@onready var overlay: Control = %Overlay
@onready var menu_btn: Button = %MenuBtn

var _cfg: Dictionary = {}
var _action_btns: Dictionary = {}
var _me_boxes: Array = []
var _opp_boxes: Array = []
var _me_hp_row: HBoxContainer
var _opp_hp_row: HBoxContainer
var _me_state_tag: Label
var _opp_state_tag: Label
var _arena_status: Label
var _arena_me_card: Label
var _arena_opp_card: Label
var _tempo_root: Control
var _tempo_fill: ColorRect
var _tempo_ticks: Array[ColorRect] = []
var _fx_layer: Control
var _spot_layer: Control

var _sfx_clap: AudioStream
var _sfx_ding: AudioStream
var _sfx_hit: AudioStream
var _sfx_block: AudioStream
var _sfx_zan: AudioStream
var _players: Array = []


func _ready() -> void:
	UiTheme.apply_to_tree(get_tree())
	_cfg = (BattleController.pending_cfg as Dictionary).duplicate()
	BattleController.pending_cfg = {}
	if _cfg.is_empty():
		_cfg = DEFAULT_CFG.duplicate()
	UiNav.register_back_target(SCENE, UiNav.MENU_SCENE)
	UiNav.register_back_guard(SCENE, _on_back_requested)
	add_child(UiBackRouter.new())
	menu_btn.pressed.connect(_leave_to_menu)
	BattleFx.bind_press(menu_btn, "menu")
	_setup_audio()

	_fx_layer = Control.new()
	_fx_layer.name = "FxLayer"
	_fx_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fx_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fx_layer)

	# U5：先连接信号再 start_match，保证开局首拍 phase_changed 不丢失
	controller.phase_changed.connect(_on_phase)
	controller.beat.connect(_on_beat)
	controller.round_resolved.connect(_on_resolved)
	controller.game_over.connect(_on_game_over)
	controller.start_match(_cfg)

	_build_hud_and_arena()
	_build_actions()
	overlay.visible = false
	_on_phase(controller.state.phase, controller.state.round)
	_refresh()


func _exit_tree() -> void:
	_hide_spotlight()


func _process(_delta: float) -> void:
	_update_tempo_bar()
	_refresh()


func _build_hud_and_arena() -> void:
	# 1. 对手状态卡
	var opp_card := _make_fighter_card("对手", "opp", _opp_boxes)
	opp_slot.add_child(opp_card)

	# 2. 中央对撞舞台 + 拍点进度条
	var arena := _make_arena_box()
	reveal_slot.add_child(arena)
	reveal_slot.move_child(arena, 0)

	# 3. 我方状态卡（插在底部出招区之前）
	var me_slot := VBoxContainer.new()
	me_slot.name = "MeSlot"
	var vbox := bottom_slot.get_parent() as VBoxContainer
	vbox.add_child(me_slot)
	vbox.move_child(me_slot, bottom_slot.get_index())
	var me_card := _make_fighter_card("我", "me", _me_boxes)
	me_slot.add_child(me_card)


func _make_fighter_card(title_text: String, prefix: String, boxes: Array) -> PanelContainer:
	var s: BattleState = controller.state
	var accent := UiTheme.SHIELD if prefix == "me" else UiTheme.WAVE
	var panel := PanelContainer.new()
	panel.name = prefix.capitalize() + "HudCard"
	panel.add_theme_stylebox_override("panel", UiTheme.card_style(UiTheme.BG_CARD, 12, accent.lightened(0.35), 2))

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	panel.add_child(col)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	col.add_child(head)

	var title := UiTheme.ink_label(title_text, 15, UiTheme.INK)
	head.add_child(title)

	var tag := UiTheme.ink_label("", 12, UiTheme.INK_SOFT)
	tag.name = prefix + "_tag"
	tag.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	head.add_child(tag)

	var hp_row := BattleFx.make_hp_row(s.max_hp(), s.max_hp())
	var qi_row := BattleFx.make_qi_row(s.max_qi(), 0)
	var sh_row := BattleFx.make_shield_row(s.max_shield(), s.max_shield())
	if prefix == "me":
		_me_hp_row = hp_row
		_me_state_tag = tag
	else:
		_opp_hp_row = hp_row
		_opp_state_tag = tag

	var hp_lab := Label.new()
	hp_lab.name = prefix + "_hp"
	var qi_lab := Label.new()
	qi_lab.name = prefix + "_qi"
	var sh_lab := Label.new()
	sh_lab.name = prefix + "_shield"
	boxes.append(hp_lab)
	boxes.append(qi_lab)
	boxes.append(sh_lab)

	col.add_child(BattleFx.make_stat_line("血", hp_row, hp_lab))
	col.add_child(BattleFx.make_stat_line("气", qi_row, qi_lab))
	col.add_child(BattleFx.make_stat_line("盾", sh_row, sh_lab))
	col.set_meta("hp_row", hp_row)
	col.set_meta("qi_row", qi_row)
	col.set_meta("shield_row", sh_row)
	return panel


func _make_arena_box() -> VBoxContainer:
	var wrap := VBoxContainer.new()
	wrap.name = "ArenaBox"
	wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	wrap.alignment = BoxContainer.ALIGNMENT_CENTER
	wrap.add_theme_constant_override("separation", 6)

	_arena_status = UiTheme.ink_label("点击「攒气」开始对决", 18, UiTheme.INK)
	_arena_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wrap.add_child(_arena_status)

	var duel_row := HBoxContainer.new()
	duel_row.alignment = BoxContainer.ALIGNMENT_CENTER
	duel_row.add_theme_constant_override("separation", 14)
	wrap.add_child(duel_row)

	var me_box := _make_duel_slot("我", UiTheme.ACCENT, true)
	var vs_lab := UiTheme.ink_label("VS", 16, UiTheme.INK_FAINT)
	var opp_box := _make_duel_slot("对手", UiTheme.WAVE, false)
	duel_row.add_child(me_box)
	duel_row.add_child(vs_lab)
	duel_row.add_child(opp_box)

	wrap.add_child(_make_tempo_bar())
	return wrap


func _make_duel_slot(who_title: String, border_col: Color, is_me: bool) -> PanelContainer:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(124, 68)
	p.add_theme_stylebox_override("panel", UiTheme.card_style(UiTheme.BG_CARD, 12, border_col, 2))
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 2)
	p.add_child(v)
	var t := UiTheme.ink_label(who_title, 11, UiTheme.INK_SOFT)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var act_lab := UiTheme.ink_label("待命", 22, border_col.darkened(0.1))
	act_lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(act_lab)
	if is_me:
		_arena_me_card = act_lab
	else:
		_arena_opp_card = act_lab
	return p


func _make_tempo_bar() -> Control:
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 4)
	wrap.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_tempo_root = Control.new()
	_tempo_root.custom_minimum_size = Vector2(220, 12)
	_tempo_root.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_tempo_root.clip_contents = true
	_tempo_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(_tempo_root)

	var bg := ColorRect.new()
	bg.color = UiTheme.DISABLED_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tempo_root.add_child(bg)

	_tempo_fill = ColorRect.new()
	_tempo_fill.color = UiTheme.ACCENT
	_tempo_fill.size = Vector2(0, 12)
	_tempo_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tempo_root.add_child(_tempo_fill)

	_tempo_ticks.clear()
	for _i in 2:
		var tick := ColorRect.new()
		tick.color = Color(0.06, 0.09, 0.16, 0.45)
		tick.size = Vector2(2, 12)
		tick.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_tempo_root.add_child(tick)
		_tempo_ticks.append(tick)
	return wrap


func _update_tempo_bar() -> void:
	if _tempo_fill == null or controller == null or controller.state == null:
		return
	var s: BattleState = controller.state
	var win := controller.window_seconds()
	var left := controller.select_left()
	var elapsed := win - left
	var t := clampf(elapsed / maxf(win, 0.01), 0.0, 1.0)
	var w := _tempo_root.size.x if _tempo_root.size.x > 0 else 220.0
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
	_tempo_root.visible = controller.is_pick_open() and not s.is_over()


## 底部双层拇指操作盘：
##   上层（课间模式）：2×4 进阶技能槽（8 个两字技能）
##   下层（常驻核心区）：3 大拇指主键【防御】【攒气】【包子】（包子支持连点 1→2→3 连）
func _build_actions() -> void:
	var s: BattleState = controller.state
	var deck := VBoxContainer.new()
	deck.name = "SkillDeck"
	deck.add_theme_constant_override("separation", 8)
	deck.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	if s.skills_enabled():
		var grid := GridContainer.new()
		grid.name = "SkillGrid"
		grid.columns = 4
		grid.add_theme_constant_override("h_separation", 6)
		grid.add_theme_constant_override("v_separation", 6)
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for a in GameRules.ADVANCED_SKILLS:
			var act := int(a)
			var b := UiTheme.make_skill_slot(act, false)
			b.pressed.connect(func(): _pick(act))
			BattleFx.bind_press(b, "fang" if GameRules.is_defense(act) else "bo")
			grid.add_child(b)
			_action_btns[act] = b
		deck.add_child(grid)

	var primary_row := HBoxContainer.new()
	primary_row.name = "PrimaryRow"
	primary_row.add_theme_constant_override("separation", 8)
	primary_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for a in GameRules.PRIMARY_ACTIONS:
		var act := int(a)
		var b := UiTheme.make_skill_slot(act, true)
		if act == GameRules.Action.BAO1:
			b.pressed.connect(_on_bao_pressed)
			BattleFx.bind_press(b, "bo")
		elif act == GameRules.Action.ZAN:
			b.pressed.connect(func(): _pick(GameRules.Action.ZAN))
			BattleFx.bind_press(b, "zan")
		else:
			b.pressed.connect(func(): _pick(GameRules.Action.FANG))
			BattleFx.bind_press(b, "fang")
		primary_row.add_child(b)
		_action_btns[act] = b

	deck.add_child(primary_row)
	bottom_slot.add_child(deck)


func _on_bao_pressed() -> void:
	if controller == null or controller.state == null:
		return
	var s: BattleState = controller.state
	var cur := int(s.pending[0])
	var target_act := UiTheme.next_bao_action(s, 0, cur)
	_pick(target_act)


func _pick(action: int) -> void:
	if action == GameRules.Action.ZAN:
		_hide_spotlight()
	if controller.try_select(0, action):
		_play_sfx(_sfx_zan if action == GameRules.Action.ZAN else _sfx_ding, -6.0)
		_refresh()


func _show_spotlight() -> void:
	if _spot_layer != null and is_instance_valid(_spot_layer):
		return
	var zan_btn: Button = _action_btns.get(GameRules.Action.ZAN) as Button
	if zan_btn == null:
		return
	_spot_layer = BattleFx.show_focus_spotlight(get_tree(), zan_btn, "点击「攒气」开始对决")


func _hide_spotlight() -> void:
	if _spot_layer != null and is_instance_valid(_spot_layer):
		BattleFx.hide_focus_spotlight(_spot_layer)
	_spot_layer = null


# ---------- 音效 ----------

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
		_players.append(p)


func _play_sfx(stream: AudioStream, volume_db: float = 0.0) -> void:
	if stream == null:
		return
	for p: AudioStreamPlayer in _players:
		if not p.playing:
			p.stream = stream
			p.volume_db = volume_db
			p.play()
			return
	if not _players.is_empty():
		_players[0].stream = stream
		_players[0].volume_db = volume_db
		_players[0].play()


func _on_beat(_beat_no: int) -> void:
	_play_sfx(_sfx_clap, 0.0)


func _refresh() -> void:
	if controller == null or controller.state == null:
		return
	var s: BattleState = controller.state
	info_label.text = "回合 %d/%d · 我 %d : %d 对手 · 先到 %d 分" % [
		int(s.round), s.round_cap(), int(s.score[0]), int(s.score[1]), s.score_to_win(),
	]
	_set_stat_row(_me_boxes, s, 0)
	_set_stat_row(_opp_boxes, s, 1)

	var open: bool = controller.is_pick_open()
	var picked: int = int(s.pending[0])
	for k in _action_btns.keys():
		var act := int(k)
		var b: Button = _action_btns[k]
		UiTheme.update_skill_slot(b, s, 0, act, open, picked, GameRules.PRIMARY_ACTIONS.has(act))

	if _me_state_tag != null:
		var seal_txt := "🚫封盾 " if s.is_sealed(0) else ""
		var pick_txt := ("已选:" + GameRules.action_short_name(picked)) if picked >= 0 else "请选招"
		_me_state_tag.text = seal_txt + pick_txt
	if _opp_state_tag != null:
		var opp_seal := "🚫封盾 " if s.is_sealed(1) else ""
		var opp_pick := "已就绪" if int(s.pending[1]) >= 0 else "思考中…"
		_opp_state_tag.text = opp_seal + opp_pick
	if open and _arena_me_card != null:
		_arena_me_card.text = GameRules.action_short_name(picked) if picked >= 0 else "待选"
	if open and _arena_opp_card != null:
		_arena_opp_card.text = "已锁" if int(s.pending[1]) >= 0 else "…"


func _set_stat_row(boxes: Array, s: BattleState, i: int) -> void:
	if boxes.size() < 3:
		return
	var hp := clampi(int(s.hp[i]), 0, s.max_hp())
	var qi := clampi(int(s.qi[i]), 0, s.max_qi())
	var shield_n := clampi(int(s.shield[i]), 0, s.max_shield())
	boxes[0].text = "血 %d/%d" % [hp, s.max_hp()]
	boxes[1].text = "气 %d/%d" % [qi, s.max_qi()]
	boxes[2].text = "盾 %d/%d" % [shield_n, s.max_shield()]
	var src: Control = boxes[0].get_parent() as Control
	var col: Control = src.get_parent() as Control if src != null else null
	if col == null:
		return
	if col.has_meta("hp_row"):
		BattleFx.update_hp_row(col.get_meta("hp_row") as HBoxContainer, hp)
	if col.has_meta("qi_row"):
		BattleFx.update_qi_row(col.get_meta("qi_row") as HBoxContainer, qi)
	if col.has_meta("shield_row"):
		BattleFx.update_shield_row(col.get_meta("shield_row") as HBoxContainer, shield_n)


func _on_phase(phase: int, round_no: int) -> void:
	if phase == GameRules.Phase.SELECTING and overlay.visible:
		overlay.visible = false
	var is_opening: bool = round_no == GameRules.OPENING_ROUND and controller != null and not controller.opening_done()
	if _arena_status != null:
		match phase:
			GameRules.Phase.SELECTING:
				if is_opening:
					_arena_status.text = "点击「攒气」开始对决"
					_show_spotlight()
				else:
					_arena_status.text = "拍点选招（可随时改选）"
					_hide_spotlight()
			GameRules.Phase.RESOLVING, GameRules.Phase.PRESENTING:
				_arena_status.text = "双方亮招！"
				_hide_spotlight()
			GameRules.Phase.GAME_OVER:
				_arena_status.text = "对局结束"
				_hide_spotlight()
	_refresh()


func _on_resolved(result: GameRules.RoundResult) -> void:
	_hide_spotlight()
	result_label.text = result.text
	if result.actions.size() >= 2:
		if _arena_me_card != null:
			_arena_me_card.text = GameRules.action_short_name(int(result.actions[0]))
		if _arena_opp_card != null:
			_arena_opp_card.text = GameRules.action_short_name(int(result.actions[1]))
	if result.opening:
		_play_sfx(_sfx_zan, -2.0)
	elif result.hit[0] or result.hit[1]:
		_play_sfx(_sfx_hit, 0.0)
	elif result.blocked[0] or result.blocked[1]:
		_play_sfx(_sfx_block, 0.0)
	elif int(result.qi_delta[0]) > 0 or int(result.qi_delta[1]) > 0:
		_play_sfx(_sfx_ding, -4.0)

	if not result.opening and _fx_layer != null:
		var me_t: Control = _me_hp_row.get_parent() as Control if _me_hp_row else self
		var opp_t: Control = _opp_hp_row.get_parent() as Control if _opp_hp_row else self
		if bool(result.hit[0]):
			BattleFx.play_hurt(_fx_layer, me_t)
		if bool(result.hit[1]):
			BattleFx.play_hit(_fx_layer, opp_t)
		if bool(result.blocked[0]):
			BattleFx.play_block(_fx_layer, me_t)
		if bool(result.blocked[1]):
			BattleFx.play_block(_fx_layer, opp_t)

	var s: BattleState = controller.state
	if s.is_over() and not s.is_match_over():
		var sub := "我 %d : %d 对手" % [int(s.score[0]), int(s.score[1])]
		if s.skills_enabled() and not s.mastery and s.winner == 0:
			var sc := int(s.score[0])
			for a in GameRules.ADVANCED_SKILLS:
				if GameRules.unlock_score(int(a)) == sc:
					sub += "\n解锁新技能：【%s】" % GameRules.action_short_name(int(a))
		_show_overlay("小局结算", sub, false)


func _on_game_over(winner: int) -> void:
	var s: BattleState = controller.state
	var title := "终场 · 平局"
	if winner == 0:
		title = "终场 · 我方胜利！"
	elif winner == 1:
		title = "终场 · 对手胜利"
	var sub := "最终比分 · 我 %d : %d 对手" % [int(s.score[0]), int(s.score[1])]
	if _fx_layer != null:
		BattleFx.play_result(_fx_layer, winner, _arena_status)
	_show_overlay(title, sub, true)


func _show_overlay(title_text: String, sub_text: String, with_buttons: bool) -> void:
	for c in overlay.get_children():
		overlay.remove_child(c)
		c.queue_free()
	overlay.visible = true
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP

	var dim := ColorRect.new()
	dim.color = Color(0.06, 0.09, 0.16, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)

	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(300, 0)
	v.add_theme_constant_override("separation", 12)
	center.add_child(v)
	v.add_child(UiTheme.banner_card(title_text, sub_text, UiTheme.ACCENT, 120))

	if with_buttons:
		var again := UiTheme.make_btn("再来一局", UiTheme.ACCENT, Color.WHITE, 17, 48)
		again.pressed.connect(_on_again)
		v.add_child(again)
		var back := UiTheme.make_btn("返回菜单", UiTheme.LINE, UiTheme.INK, 17, 48)
		back.pressed.connect(_leave_to_menu)
		v.add_child(back)


func _leave_to_menu() -> void:
	UiNav.return_to_menu(get_tree())


func _on_back_requested() -> bool:
	_leave_to_menu()
	return true


func _on_again() -> void:
	overlay.visible = false
	result_label.text = ""
	controller.start_match(_cfg)
	_on_phase(controller.state.phase, controller.state.round)
	_refresh()

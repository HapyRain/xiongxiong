## main.gd
## 1080P (1080×1920) 单人对战页（v3 全屏三渲二特效 · 炉石烧绳锚点 · 街机双层技能盘版）：
##   底层：1080P 三渲二夕阳天台对决舞台背景（stage_bg_cel.png）
##   顶部：回合/比分条 + 右上角唯一「菜单」入口 + 对手街机状态卡（含赤焰熊头像 + 血/气/盾槽，零重复文字）
##   中部（RevealSlot 全屏特效舞台区）：
##     - 上偏中：MOBA 级非对称博弈反馈横幅（MobaBanner）
##     - 中央：双侧三渲二亮招对撞卡（MeDuelCard vs OppDuelCard）+ 全舞台三渲二速度线/刀光/护盾/黑洞演出
##     - 右下角贴边：微缩半透明「5 轮打字机上推记招器」（BattleTicker）
##     - 舞台底部分界锚点：《炉石传说》式烧绳子倒计时导轨 + 三段拍点锚点（一拍 / 二拍 / 封盘）
##   底部：我方街机状态卡（含金罡熊头像）+ 高对比三渲二四态技能盘（左图标 + 居中黑边大字 + 零 Emoji）
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
var _me_card: PanelContainer
var _opp_card: PanelContainer
var _me_state_tag: Label
var _opp_state_tag: Label
var _moba_banner: PanelContainer
var _ticker: PanelContainer
var _me_duel_card: PanelContainer
var _opp_duel_card: PanelContainer
var _rope_bar: PanelContainer
var _fx_layer: Control
var _spot_layer: Control
var _audio_bank: Dictionary = {}
var _active_round: int = 1


func _ready() -> void:
	UiTheme.apply_to_tree(get_tree())
	_cfg = (BattleController.pending_cfg as Dictionary).duplicate()
	BattleController.pending_cfg = {}
	if _cfg.is_empty():
		_cfg = DEFAULT_CFG.duplicate()
	UiNav.register_back_target(SCENE, UiNav.MENU_SCENE)
	UiNav.register_back_guard(SCENE, _on_back_requested)
	add_child(UiBackRouter.new())

	# 铺设 1080P 三渲二天台对决背景（自动隐藏纯色 Bg 并置于 Margin 之前）
	UiTheme.add_stage_background(self, 0.10)

	menu_btn.add_theme_stylebox_override("normal", UiTheme.button_style(UiTheme.BG_DARK_CARD, 18, UiTheme.INK, 4, 6))
	menu_btn.add_theme_color_override("font_color", Color.WHITE)
	menu_btn.add_theme_constant_override("outline_size", 5)
	menu_btn.add_theme_color_override("font_outline_color", UiTheme.INK)
	menu_btn.pressed.connect(_on_top_menu)
	BattleFx.bind_press(menu_btn, "menu")
	_audio_bank = BattleFx.setup_audio_bank(self)

	_fx_layer = Control.new()
	_fx_layer.name = "FxLayer"
	_fx_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fx_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fx_layer)
	BattleFx.ensure_cel_canvas(_fx_layer)

	result_label.visible = false

	# U5：先连接信号再 start_match，保证开局首拍 phase_changed 不丢失
	controller.phase_changed.connect(_on_phase)
	controller.beat.connect(_on_beat)
	controller.round_resolved.connect(_on_resolved)
	controller.game_over.connect(_on_game_over)
	controller.start_match(_cfg)

	_build_hud_and_arena()
	_build_actions()
	# 确保全屏特效层位于舞台之上、Overlay 之下，且不拦截底部技能点击
	move_child(_fx_layer, overlay.get_index())
	overlay.visible = false
	BattleFx.start_bgm(_audio_bank)
	BattleFx.play_named_sfx(_audio_bank, "game_start", 0.0)
	_on_phase(controller.state.phase, controller.state.round)
	_refresh()


func _exit_tree() -> void:
	BattleFx.stop_bgm(_audio_bank)
	_hide_spotlight()


func _process(_delta: float) -> void:
	_update_tempo_bar()
	_refresh()


func _on_top_menu() -> void:
	var tree := get_tree()
	if tree == null:
		return
	if UiNav.is_settings_open(tree):
		return
	var panel_scene: PackedScene = load("res://scenes/settings_panel.tscn")
	if panel_scene == null:
		_leave_to_menu()
		return
	var s_overlay := panel_scene.instantiate()
	s_overlay.name = "SettingsPanelOverlay"
	tree.root.add_child(s_overlay)


func _build_hud_and_arena() -> void:
	# 1. 对手街机状态栏（带赤焰熊头像）
	_opp_card = _make_fighter_card("对手", "opp", _opp_boxes, "avatar_bear_opp.png")
	opp_slot.add_child(_opp_card)

	# 2. 中央全屏三渲二交锋舞台（MOBA 横幅 + 双侧亮招卡 + 右下贴边微缩记招器 + 炉石烧绳分界条）
	var arena := _make_arena_box()
	reveal_slot.add_child(arena)
	reveal_slot.move_child(arena, 0)

	# 3. 我方街机状态栏（带金罡熊头像，插在底部出招区之前）
	var me_slot := VBoxContainer.new()
	me_slot.name = "MeSlot"
	var vbox := bottom_slot.get_parent() as VBoxContainer
	vbox.add_child(me_slot)
	vbox.move_child(me_slot, bottom_slot.get_index())
	_me_card = _make_fighter_card("我", "me", _me_boxes, "avatar_bear_me.png")
	me_slot.add_child(_me_card)


func _make_fighter_card(title_text: String, prefix: String, boxes: Array, avatar_file: String) -> PanelContainer:
	var s: BattleState = controller.state
	var accent := UiTheme.SHIELD if prefix == "me" else UiTheme.WAVE
	var panel := PanelContainer.new()
	panel.name = prefix.capitalize() + "HudCard"
	var sb := UiTheme.card_style(UiTheme.BG_DARK_CARD, 22, accent, 4)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", sb)

	var main_row := HBoxContainer.new()
	main_row.add_theme_constant_override("separation", 18)
	panel.add_child(main_row)

	# 左侧：三渲二角色头像徽章
	var av := TextureRect.new()
	av.name = prefix + "_avatar"
	av.texture = UiTheme.load_ui_texture(avatar_file)
	av.custom_minimum_size = Vector2(156, 96)
	av.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	av.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	av.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main_row.add_child(av)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 4)
	main_row.add_child(col)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	col.add_child(head)

	var title := UiTheme.ink_label(title_text, 28, Color.WHITE, 6, UiTheme.INK)
	head.add_child(title)

	var tag := UiTheme.ink_label("", 22, accent.lightened(0.35), 4, UiTheme.INK)
	tag.name = prefix + "_tag"
	tag.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	head.add_child(tag)

	var hp_row := BattleFx.make_hp_row(s.max_hp(), s.max_hp())
	var qi_row := BattleFx.make_qi_row(s.max_qi(), 0)
	var sh_row := BattleFx.make_shield_row(s.max_shield(), s.max_shield())
	if prefix == "me":
		_me_state_tag = tag
	else:
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

	# 第一行：血槽 + 护盾槽同排紧凑呈现（告别繁琐三行堆叠）
	var vitals_row := HBoxContainer.new()
	vitals_row.add_theme_constant_override("separation", 18)
	var hp_line := BattleFx.make_stat_line("血", hp_row, hp_lab)
	var sh_line := BattleFx.make_stat_line("盾", sh_row, sh_lab)
	vitals_row.add_child(hp_line)
	vitals_row.add_child(sh_line)
	col.add_child(vitals_row)

	# 第二行：元气槽
	col.add_child(BattleFx.make_stat_line("气", qi_row, qi_lab))

	col.set_meta("hp_row", hp_row)
	col.set_meta("qi_row", qi_row)
	col.set_meta("shield_row", sh_row)
	return panel


func _make_arena_box() -> VBoxContainer:
	var wrap := VBoxContainer.new()
	wrap.name = "ArenaBox"
	wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	wrap.add_theme_constant_override("separation", 12)

	# 1. 正中间偏上：MOBA 击杀级反馈横幅
	_moba_banner = BattleFx.make_moba_banner()
	wrap.add_child(_moba_banner)

	# 2. 中央舞台留白+亮招对撞区（让背后的三渲二天台魔法阵与全屏特效充分绽放）
	var stage_mid := VBoxContainer.new()
	stage_mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage_mid.alignment = BoxContainer.ALIGNMENT_CENTER
	wrap.add_child(stage_mid)

	var duel_row := HBoxContainer.new()
	duel_row.alignment = BoxContainer.ALIGNMENT_CENTER
	duel_row.add_theme_constant_override("separation", 36)
	stage_mid.add_child(duel_row)

	_me_duel_card = BattleFx.make_duel_card("我", UiTheme.ACCENT)
	var vs_lab := UiTheme.ink_label("⚡VS⚡", 42, Color(1.0, 0.90, 0.35), 10, UiTheme.INK)
	_opp_duel_card = BattleFx.make_duel_card("对手", UiTheme.WAVE)
	duel_row.add_child(_me_duel_card)
	duel_row.add_child(vs_lab)
	duel_row.add_child(_opp_duel_card)

	# 3. 舞台右下角贴边：微缩半透明「5 轮打字机上推记招器」
	var ticker_row := HBoxContainer.new()
	ticker_row.alignment = BoxContainer.ALIGNMENT_END
	wrap.add_child(ticker_row)
	_ticker = BattleFx.make_battle_ticker()
	ticker_row.add_child(_ticker)

	# 4. 舞台底部分界锚点：《炉石传说》式烧绳子倒计时导轨（含一拍/二拍/封盘锚点）
	_rope_bar = BattleFx.make_burning_rope_bar()
	wrap.add_child(_rope_bar)

	return wrap


func _update_tempo_bar() -> void:
	if _rope_bar == null or controller == null or controller.state == null:
		return
	var s: BattleState = controller.state
	var win := controller.window_seconds()
	var left := controller.select_left()
	var open := controller.is_pick_open() and not s.is_over()
	BattleFx.update_burning_rope_bar(_rope_bar, win, left, s.round, open)


func _build_actions() -> void:
	var s: BattleState = controller.state
	var deck := VBoxContainer.new()
	deck.name = "SkillDeck"
	deck.add_theme_constant_override("separation", 12)
	deck.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	if s.skills_enabled():
		var grid := GridContainer.new()
		grid.name = "SkillGrid"
		grid.columns = 4
		grid.add_theme_constant_override("h_separation", 12)
		grid.add_theme_constant_override("v_separation", 12)
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for a in GameRules.ADVANCED_SKILLS:
			var act := int(a)
			var b := UiTheme.make_skill_slot(act, false, _on_skill_rejected)
			b.pressed.connect(func(): _pick(act))
			BattleFx.bind_press(b, GameRules.action_category(act))
			grid.add_child(b)
			_action_btns[act] = b
		deck.add_child(grid)

	var primary_row := HBoxContainer.new()
	primary_row.name = "PrimaryRow"
	primary_row.add_theme_constant_override("separation", 16)
	primary_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for a in GameRules.PRIMARY_ACTIONS:
		var act := int(a)
		var b := UiTheme.make_skill_slot(act, true, _on_skill_rejected)
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


func _on_skill_rejected(_act: int, reason: String) -> void:
	BattleFx.play_named_sfx(_audio_bank, "ui_deny", 0.5)
	BattleFx.show_moba_banner(_moba_banner, reason, "请改选其它可用招式", UiTheme.DANGER, true)


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


func _on_beat(beat_no: int) -> void:
	var clap_p := 1.0
	if controller != null and controller.state != null:
		clap_p = BattleTempo.clap_pitch(controller.state.round)
	BattleFx.play_named_sfx(_audio_bank, "clap", 1.0, clap_p)
	BattleFx.play_beat_pulse(_fx_layer, beat_no, _me_duel_card, _opp_duel_card)


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
		var seal_txt := "[封盾] " if s.is_sealed(0) else ""
		var pick_txt := ("已锁:" + GameRules.action_short_name(picked)) if picked >= 0 else "请出招"
		_me_state_tag.text = seal_txt + pick_txt
	if _opp_state_tag != null:
		var opp_seal := "[封盾] " if s.is_sealed(1) else ""
		var opp_pick := "已就绪" if int(s.pending[1]) >= 0 else "读招中"
		_opp_state_tag.text = opp_seal + opp_pick
	if open and _me_duel_card != null:
		BattleFx.update_duel_card(_me_duel_card, picked, "待选", false)
	if open and _opp_duel_card != null:
		BattleFx.update_duel_card(_opp_duel_card, -1, "已备" if int(s.pending[1]) >= 0 else "…", false)


func _set_stat_row(boxes: Array, s: BattleState, i: int) -> void:
	if boxes.size() < 3:
		return
	var hp := clampi(int(s.hp[i]), 0, s.max_hp())
	var qi := clampi(int(s.qi[i]), 0, s.max_qi())
	var shield_n := clampi(int(s.shield[i]), 0, s.max_shield())
	# 只显示纯数字比值（3/4），绝不再重复前置「血/气/盾」汉字
	boxes[0].text = "%d/%d" % [hp, s.max_hp()]
	boxes[1].text = "%d/%d" % [qi, s.max_qi()]
	boxes[2].text = "%d/%d" % [shield_n, s.max_shield()]
	var col: Control = _me_card if i == 0 else _opp_card
	if col != null:
		var vbox := boxes[1].get_parent().get_parent() as Control if boxes[1].get_parent() != null else null
		if vbox != null:
			if vbox.has_meta("hp_row"):
				BattleFx.update_hp_row(vbox.get_meta("hp_row") as HBoxContainer, hp)
			if vbox.has_meta("qi_row"):
				BattleFx.update_qi_row(vbox.get_meta("qi_row") as HBoxContainer, qi)
			if vbox.has_meta("shield_row"):
				BattleFx.update_shield_row(vbox.get_meta("shield_row") as HBoxContainer, shield_n)


func _on_phase(phase: int, round_no: int) -> void:
	if phase == GameRules.Phase.SELECTING:
		_active_round = maxi(1, round_no)
		if overlay.visible:
			overlay.visible = false
	if controller != null and controller.state != null:
		BattleFx.update_bgm_tension(_audio_bank, controller.state)
	var s: BattleState = controller.state if controller != null else null
	var is_opening: bool = round_no == GameRules.OPENING_ROUND and controller != null and not controller.opening_done()
	match phase:
		GameRules.Phase.SELECTING:
			if is_opening:
				BattleFx.show_moba_banner(_moba_banner, "⚡ 点击「攒气」开始对决 ⚡", "第 1 回合开局亮相 · 双方气 +1", UiTheme.ACCENT, false)
				_show_spotlight()
			elif s != null and s.quan_jiang_enabled() and int(s.qi[0]) == s.max_qi() and int(s.hp[0]) == s.max_hp() and int(s.hp[1]) == 1:
				BattleFx.show_moba_banner(_moba_banner, "👑 劝降条件已达成！", "我方满气满血 vs 对手 1 血 · 本拍任意出招即刻获胜！", UiTheme.ACCENT, true)
				_hide_spotlight()
			else:
				BattleFx.show_moba_banner(_moba_banner, "🎯 第 %d 回合 · 同步选招" % round_no, "烧绳结束前点选技能 · 预判对手招式", UiTheme.SHIELD, false)
				_hide_spotlight()
		GameRules.Phase.RESOLVING, GameRules.Phase.PRESENTING:
			_hide_spotlight()
		GameRules.Phase.GAME_OVER:
			_hide_spotlight()
	_refresh()


func _on_resolved(result: GameRules.RoundResult) -> void:
	_hide_spotlight()
	result_label.text = result.text

	var r_dict := {
		"opening": result.opening,
		"round": _active_round,
		"actions": result.actions,
		"hp_delta": result.hp_delta,
		"qi_delta": result.qi_delta,
		"shield_delta": result.shield_delta,
		"hit": result.hit,
		"blocked": result.blocked,
		"sealed": result.sealed,
		"quan_jiang": result.quan_jiang,
		"text": result.text,
	}
	BattleFx.play_clash_director(
		_fx_layer,
		controller.state,
		r_dict,
		0,
		_me_card if _me_card != null else self,
		_opp_card if _opp_card != null else self,
		_moba_banner,
		_ticker,
		_audio_bank,
		_me_duel_card,
		_opp_duel_card
	)

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
		BattleFx.play_result(_fx_layer, winner, _moba_banner)
	_show_overlay(title, sub, true)


func _show_overlay(title_text: String, sub_text: String, with_buttons: bool) -> void:
	for c in overlay.get_children():
		overlay.remove_child(c)
		c.queue_free()
	overlay.visible = true
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP

	var dim := ColorRect.new()
	dim.color = Color(0.04, 0.06, 0.12, 0.68)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)

	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(780, 0)
	v.add_theme_constant_override("separation", 28)
	center.add_child(v)
	v.add_child(UiTheme.banner_card(title_text, sub_text, UiTheme.ACCENT, 260))

	if with_buttons:
		var again := UiTheme.make_btn("再来一局", UiTheme.ACCENT, Color.WHITE, 36, 112)
		again.pressed.connect(_on_again)
		v.add_child(again)
		var back := UiTheme.make_btn("返回菜单", UiTheme.BG_CARD, UiTheme.INK, 34, 104)
		back.pressed.connect(_leave_to_menu)
		v.add_child(back)


func _leave_to_menu() -> void:
	BattleFx.stop_bgm(_audio_bank)
	UiNav.return_to_menu(get_tree())


func _on_back_requested() -> bool:
	_leave_to_menu()
	return true


func _on_again() -> void:
	overlay.visible = false
	result_label.text = ""
	BattleFx.clear_ticker(_ticker)
	controller.start_match(_cfg)
	BattleFx.start_bgm(_audio_bank)
	BattleFx.play_named_sfx(_audio_bank, "game_start", 0.0)
	_on_phase(controller.state.phase, controller.state.round)
	_refresh()

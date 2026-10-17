## main.gd
## 对战 UI：状态条 + 2 拍选招 + 亮招动画 + 音效。
extends Control

@onready var controller: BattleController = $BattleController

@onready var me_hp: ProgressBar = %MeHp
@onready var me_qi: ProgressBar = %MeQi
@onready var me_shield: HBoxContainer = %MeShield
@onready var me_hp_label: Label = %MeHpLabel
@onready var me_qi_label: Label = %MeQiLabel

@onready var you_hp: ProgressBar = %YouHp
@onready var you_qi: ProgressBar = %YouQi
@onready var you_shield: HBoxContainer = %YouShield
@onready var you_hp_label: Label = %YouHpLabel
@onready var you_qi_label: Label = %YouQiLabel

@onready var round_label: Label = %RoundLabel
@onready var center_label: Label = %CenterLabel
@onready var log_label: Label = %LogLabel

@onready var btn_zan: Button = %BtnZan
@onready var btn_bo: Button = %BtnBo
@onready var btn_fang: Button = %BtnFang

const COLOR_OK := Color(0.357, 0.722, 0.788, 1)
const COLOR_EMPTY := Color(0.78, 0.74, 0.68, 1)
const COLOR_WIN := Color(0.12, 0.45, 0.22, 1)
const COLOR_LOSE := Color(0.75, 0.18, 0.16, 1)
const COLOR_DRAW := Color(0.35, 0.33, 0.3, 1)

var _me_shield_pips: Array = []
var _you_shield_pips: Array = []
var _me_hp_row: HBoxContainer
var _me_qi_row: HBoxContainer
var _you_hp_row: HBoxContainer
var _you_qi_row: HBoxContainer
var _fx_layer: Control

var _sfx_clap: AudioStream
var _sfx_ding: AudioStream
var _sfx_hit: AudioStream
var _sfx_block: AudioStream
var _sfx_zan: AudioStream
var _players: Array = []

var _reveal_layer: CanvasLayer
var _spot_layer: Control
var _menu_btn: Button
var _top_menu_btn: Button
var _tempo_root: Control
var _tempo_bg: ColorRect
var _tempo_fill: ColorRect
var _tempo_ticks: Array[ColorRect] = []


func _ready() -> void:
	UiTheme.apply_to_tree(get_tree())
	_build_shield_pips()
	_build_resource_icons()
	_setup_audio()
	_build_nav()
	_build_tempo_bar()
	_tint_labels()
	btn_zan.pressed.connect(func(): _pick(GameRules.Action.ZAN))
	btn_bo.pressed.connect(func(): _pick(GameRules.Action.BO))
	btn_fang.pressed.connect(func(): _pick(GameRules.Action.FANG))
	BattleFx.bind_press(btn_zan, "zan")
	BattleFx.bind_press(btn_bo, "bo")
	BattleFx.bind_press(btn_fang, "fang")

	controller.phase_changed.connect(_on_phase)
	controller.beat.connect(_on_beat)
	controller.selected_changed.connect(_on_selected)
	controller.round_resolved.connect(_on_resolved)
	controller.game_over.connect(_on_game_over)
	# 子节点 BattleController 的 _ready 更早，首帧 phase_changed 可能已错过，这里回放一次
	_on_phase(controller.state.phase, controller.state.round)
	_refresh_all()


func _build_tempo_bar() -> void:
	# 进度条插到中央标签下方
	var parent: Node = center_label.get_parent() if center_label != null else self
	if parent is BoxContainer:
		var wrap := VBoxContainer.new()
		wrap.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		wrap.add_theme_constant_override("separation", 4)
		var cap := UiTheme.ink_label("出招节奏", 11, UiTheme.INK_FAINT)
		cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		wrap.add_child(cap)
		_tempo_root = Control.new()
		_tempo_root.custom_minimum_size = Vector2(160, 12)
		_tempo_root.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		_tempo_root.clip_contents = true
		_tempo_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
		wrap.add_child(_tempo_root)
		parent.add_child(wrap)
		parent.move_child(wrap, center_label.get_index() + 1)
	else:
		_tempo_root = Control.new()
		_tempo_root.set_anchors_preset(Control.PRESET_CENTER)
		_tempo_root.custom_minimum_size = Vector2(220, 12)
		add_child(_tempo_root)

	_tempo_bg = ColorRect.new()
	_tempo_bg.color = Color(0.88, 0.84, 0.78)
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
		tick.color = Color(0.35, 0.32, 0.28, 0.55)
		tick.size = Vector2(2, 12)
		tick.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_tempo_root.add_child(tick)
		_tempo_ticks.append(tick)


func _process(_delta: float) -> void:
	# 每帧同步按钮 ↔ is_pick_open
	if controller != null:
		_refresh_actions()
	if _tempo_fill == null or controller == null or controller.state == null:
		return
	var s: BattleState = controller.state
	var win: float = controller._window_total if controller._window_total > 0.01 else BattleTempo.total_window(s.round)
	var left: float = controller._select_left
	var elapsed: float = win - left
	var t: float = clampf(elapsed / maxf(win, 0.01), 0.0, 1.0)
	var w: float = _tempo_root.size.x if _tempo_root.size.x > 0 else 220.0
	_tempo_fill.size = Vector2(w * t, 12)
	if t >= 0.82:
		_tempo_fill.color = Color(0.85, 0.28, 0.22)
	elif t >= 0.55:
		_tempo_fill.color = Color(0.92, 0.62, 0.18)
	else:
		_tempo_fill.color = UiTheme.ACCENT
	if _tempo_ticks.size() >= 2:
		var clap := BattleTempo.clap2_at(s.round)
		_tempo_ticks[0].position = Vector2(1, 0)
		_tempo_ticks[1].position = Vector2(clampf(clap / win, 0.0, 1.0) * w - 1.0, 0)
	_tempo_root.visible = controller.is_pick_open() or (controller._window_total > 0 and not s.is_over())


func _build_nav() -> void:
	# 右上角：设置/菜单入口（避开 QualitySettings 的 ⚙）
	_top_menu_btn = Button.new()
	_top_menu_btn.text = "菜单"
	_top_menu_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_top_menu_btn.offset_left = -108
	_top_menu_btn.offset_top = 8
	_top_menu_btn.offset_right = -52
	_top_menu_btn.offset_bottom = 40
	_top_menu_btn.add_theme_font_size_override("font_size", 14)
	_top_menu_btn.pressed.connect(_on_top_menu)
	BattleFx.bind_press(_top_menu_btn, "menu")
	add_child(_top_menu_btn)

	# 终局：返回菜单（默认隐藏）
	_menu_btn = Button.new()
	_menu_btn.text = "返回菜单"
	_menu_btn.visible = false
	_menu_btn.custom_minimum_size = Vector2(0, 52)
	_menu_btn.add_theme_font_size_override("font_size", 20)
	_menu_btn.pressed.connect(_on_back_menu)
	BattleFx.bind_press(_menu_btn, "menu")
	var buttons: Node = get_node_or_null("Margin/VBox/Buttons")
	if buttons != null:
		buttons.add_child(_menu_btn)
	else:
		add_child(_menu_btn)


func _on_top_menu() -> void:
	# 打开设置/菜单面板（含返回菜单）
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


func _on_back_menu() -> void:
	UiNav.return_to_menu(get_tree())


func _setup_audio() -> void:
	_sfx_clap = load("res://assets/audio/clap.wav")
	_sfx_ding = load("res://assets/audio/ding.wav")
	_sfx_hit = load("res://assets/audio/hit.wav")
	_sfx_block = load("res://assets/audio/block.wav")
	_sfx_zan = load("res://assets/audio/zan.wav")
	for i: int in 4:
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
	# 全忙则抢第一个
	_players[0].stream = stream
	_players[0].volume_db = volume_db
	_players[0].play()


func _build_resource_icons() -> void:
	# 素条改成图标行（紧凑，不撑满）
	for bar: ProgressBar in [me_hp, me_qi, you_hp, you_qi]:
		if bar != null:
			bar.visible = false
	# 长文案标签只留数值，避免和图标挤在一起
	for lab: Label in [me_hp_label, me_qi_label, you_hp_label, you_qi_label]:
		if lab != null:
			lab.custom_minimum_size = Vector2(52, 0)
			lab.add_theme_font_size_override("font_size", 12)

	_fx_layer = Control.new()
	_fx_layer.name = "FxLayer"
	_fx_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fx_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fx_layer)

	_me_hp_row = BattleFx.make_hp_row(GameRules.MAX_HP, GameRules.MAX_HP)
	_me_qi_row = BattleFx.make_qi_row(GameRules.MAX_QI, 0)
	_you_hp_row = BattleFx.make_hp_row(GameRules.MAX_HP, GameRules.MAX_HP)
	_you_qi_row = BattleFx.make_qi_row(GameRules.MAX_QI, 0)

	_attach_icon_row(me_hp_label, _me_hp_row)
	_attach_icon_row(me_qi_label, _me_qi_row)
	_attach_icon_row(you_hp_label, _you_hp_row)
	_attach_icon_row(you_qi_label, _you_qi_row)


func _attach_icon_row(label: Label, row: HBoxContainer) -> void:
	if label == null:
		return
	var parent := label.get_parent()
	if parent is BoxContainer:
		var idx := label.get_index()
		parent.add_child(row)
		parent.move_child(row, idx)
		# 图标固定宽度，不横向撑满，避免和标签糊在一起
		row.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	else:
		parent.add_child(row)


func _tint_labels() -> void:
	# 场景里的 Label 默认色发虚，统一改成深色
	for lab: Label in [round_label, center_label, log_label, me_hp_label, me_qi_label, you_hp_label, you_qi_label]:
		if lab != null:
			lab.add_theme_color_override("font_color", UiTheme.INK if lab == center_label else UiTheme.INK_SOFT)
	var bg := get_node_or_null("Bg")
	if bg is ColorRect:
		(bg as ColorRect).color = UiTheme.BG
	UiTheme.tint_label(self, UiTheme.INK_SOFT)
	if center_label != null:
		center_label.add_theme_color_override("font_color", UiTheme.INK)


func _build_shield_pips() -> void:
	for i: int in GameRules.MAX_SHIELD:
		var a := ColorRect.new()
		a.custom_minimum_size = Vector2(30, 18)
		a.color = COLOR_OK
		me_shield.add_child(a)
		_me_shield_pips.append(a)
		var b := ColorRect.new()
		b.custom_minimum_size = Vector2(30, 18)
		b.color = COLOR_OK
		you_shield.add_child(b)
		_you_shield_pips.append(b)


func _pick(action: int) -> void:
	if action == GameRules.Action.ZAN:
		_hide_spotlight()
	controller.try_select(0, action)
	_play_sfx(_sfx_zan if action == GameRules.Action.ZAN else _sfx_ding, -6.0)
	_refresh_actions()


func _show_spotlight() -> void:
	if _spot_layer != null and is_instance_valid(_spot_layer):
		return
	_spot_layer = BattleFx.show_focus_spotlight(get_tree(), btn_zan, "点击「攒」开始对决")


func _hide_spotlight() -> void:
	if _spot_layer != null and is_instance_valid(_spot_layer):
		BattleFx.hide_focus_spotlight(_spot_layer)
	_spot_layer = null


func _exit_tree() -> void:
	_hide_spotlight()


func _on_phase(phase: int, round_no: int) -> void:
	round_label.text = "回合 %d / %d" % [round_no, GameRules.MAX_ROUND]
	if center_label.get_meta("game_over", false):
		return
	match phase:
		GameRules.Phase.OPENING:
			center_label.text = "开局亮相"
			_hide_spotlight()
		GameRules.Phase.SELECTING, GameRules.Phase.CLAP1:
			if round_no == GameRules.OPENING_ROUND and not controller._opening_done:
				center_label.text = "点击「攒」开始对决"
				_show_spotlight()
			else:
				center_label.text = "同步出招"
				_hide_spotlight()
		GameRules.Phase.RESOLVING:
			center_label.text = "结算"
		GameRules.Phase.PRESENTING:
			pass
		GameRules.Phase.GAME_OVER:
			pass
	_refresh_all()


func _on_beat(n: int) -> void:
	_play_sfx(_sfx_clap, 0.0)
	if center_label.get_meta("game_over", false):
		return
	center_label.text = "啪！（拍 %d）" % n
	_pulse(center_label, 1.12)


func _on_selected(who: int, action: int) -> void:
	if who == 0:
		log_label.text = "我方已选：%s" % GameRules.action_name(action)
	_refresh_all()


func _on_resolved(result: GameRules.RoundResult) -> void:
	_hide_spotlight()
	log_label.text = result.text
	if result.opening:
		center_label.text = "气 +1 · 盾 3"
		_play_sfx(_sfx_zan, -2.0)
		_pulse(center_label, 1.1)
	_refresh_all()
	_play_reveal(result)
	_play_impact_fx(result)


func _on_game_over(winner: int) -> void:
	center_label.set_meta("game_over", true)
	match winner:
		0:
			center_label.text = "我方胜利！"
			center_label.add_theme_color_override("font_color", COLOR_WIN)
		1:
			center_label.text = "对手胜利"
			center_label.add_theme_color_override("font_color", COLOR_LOSE)
		_:
			center_label.text = "平局"
			center_label.add_theme_color_override("font_color", COLOR_DRAW)
	_pulse(center_label, 1.2)
	btn_zan.disabled = true
	btn_bo.disabled = true
	btn_fang.disabled = true
	if _menu_btn != null:
		_menu_btn.visible = true
	if _fx_layer != null:
		BattleFx.play_result(_fx_layer, winner, center_label)


func _play_impact_fx(result: GameRules.RoundResult) -> void:
	if _fx_layer == null:
		return
	# result.hit[i] = 座位 i 被打中；blocked[i] = 座位 i 成功格挡
	var me_panel: Control = me_hp_label.get_parent() as Control if me_hp_label else null
	var you_panel: Control = you_hp_label.get_parent() as Control if you_hp_label else null
	if result.opening:
		return
	# 发波弹道
	if result.actions.size() >= 2:
		if int(result.actions[0]) == GameRules.Action.BO and me_panel != null and you_panel != null:
			BattleFx.play_projectile(_fx_layer, me_panel, you_panel, true)
		if int(result.actions[1]) == GameRules.Action.BO and me_panel != null and you_panel != null:
			BattleFx.play_projectile(_fx_layer, you_panel, me_panel, false)
	if result.hit[0]:
		BattleFx.play_hurt(_fx_layer, me_panel if me_panel else self)
	if result.hit[1]:
		BattleFx.play_hit(_fx_layer, you_panel if you_panel else self)
	if result.blocked[0]:
		BattleFx.play_block(_fx_layer, me_panel if me_panel else self)
	if result.blocked[1]:
		BattleFx.play_block(_fx_layer, you_panel if you_panel else self)


# ---------- 亮招动画 ----------

func _play_reveal(result: GameRules.RoundResult) -> void:
	# 设置面板打开时不播亮招，避免盖层/抢焦点
	if UiNav.is_settings_open(get_tree()):
		return
	# 清理上一次
	if _reveal_layer != null and is_instance_valid(_reveal_layer):
		_reveal_layer.queue_free()

	_reveal_layer = CanvasLayer.new()
	_reveal_layer.layer = 10
	add_child(_reveal_layer)

	var root := Control.new()
	root.name = "RevealRoot"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reveal_layer.add_child(root)
	_reveal_layer.set_meta("root", root)

	var dim := ColorRect.new()
	dim.color = Color(0.12, 0.1, 0.08, 0.28)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dim)

	var box := HBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.add_theme_constant_override("separation", 28)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(box)

	var me_card := _make_action_card("我", GameRules.action_name(result.actions[0]), Color(0.94, 0.71, 0.16))
	var you_card := _make_action_card("对手", GameRules.action_name(result.actions[1]), Color(0.36, 0.72, 0.79))
	box.add_child(me_card)
	box.add_child(you_card)

	me_card.scale = Vector2(0.2, 0.2)
	you_card.scale = Vector2(0.2, 0.2)
	me_card.pivot_offset = me_card.size / 2.0
	you_card.pivot_offset = you_card.size / 2.0

	var tw := create_tween().set_parallel(true)
	tw.tween_property(me_card, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(you_card, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# 结果音效：命中 / 格挡 / 互消
	tw.finished.connect(func():
		if result.hit[0] or result.hit[1]:
			_play_sfx(_sfx_hit, 0.0)
			_flash_color(me_card, Color(0.88, 0.29, 0.29) if result.hit[0] else Color(0.36, 0.72, 0.79))
			_flash_color(you_card, Color(0.88, 0.29, 0.29) if result.hit[1] else Color(0.36, 0.72, 0.79))
		elif result.blocked[0] or result.blocked[1]:
			_play_sfx(_sfx_block, 0.0)
		elif result.qi_delta[0] > 0 or result.qi_delta[1] > 0:
			_play_sfx(_sfx_ding, -4.0)
	)

	# 淡出含在 0.8s hold 内（勿在 await 里调 BattleTempo）
	await get_tree().create_timer(0.62).timeout
	if is_instance_valid(_reveal_layer):
		var fade_root: Control = _reveal_layer.get_meta("root")
		var fade := create_tween()
		fade.tween_property(fade_root, "modulate", Color(1, 1, 1, 0), 0.18)
		fade.finished.connect(func():
			if is_instance_valid(_reveal_layer):
				_reveal_layer.queue_free()
				_reveal_layer = null
		)


func _make_action_card(title: String, action: String, accent: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.99, 0.97, 0.94, 0.96)
	sb.border_color = accent
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(16)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", sb)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	panel.add_child(v)

	var lab := Label.new()
	lab.text = title
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lab.add_theme_font_size_override("font_size", 14)
	lab.add_theme_color_override("font_color", Color(0.35, 0.33, 0.3, 1))
	v.add_child(lab)

	var act := Label.new()
	act.text = action
	act.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	act.add_theme_font_size_override("font_size", 36)
	act.add_theme_color_override("font_color", accent.darkened(0.15))
	v.add_child(act)
	return panel


func _pulse(node: Control, to: float = 1.08) -> void:
	node.pivot_offset = node.size / 2.0
	var tw := create_tween()
	tw.tween_property(node, "scale", Vector2(to, to), 0.08)
	tw.tween_property(node, "scale", Vector2.ONE, 0.12)


func _flash_color(card: Control, color: Color) -> void:
	var panel := card as PanelContainer
	if panel == null:
		return
	var sb := panel.get_theme_stylebox("panel") as StyleBoxFlat
	if sb == null:
		return
	var base := sb.border_color
	var tw := create_tween()
	tw.tween_property(sb, "border_color", color, 0.06)
	tw.tween_property(sb, "border_color", base, 0.28)


# ---------- 数值刷新 ----------

func _refresh_all() -> void:
	var s: BattleState = controller.state
	me_hp.value = float(int(s.hp[0]))
	me_qi.value = float(int(s.qi[0]))
	you_hp.value = float(int(s.hp[1]))
	you_qi.value = float(int(s.qi[1]))
	me_hp_label.text = "%d/%d" % [int(s.hp[0]), GameRules.MAX_HP]
	me_qi_label.text = "%d/%d" % [int(s.qi[0]), GameRules.MAX_QI]
	you_hp_label.text = "%d/%d" % [int(s.hp[1]), GameRules.MAX_HP]
	you_qi_label.text = "%d/%d" % [int(s.qi[1]), GameRules.MAX_QI]
	if _me_hp_row != null:
		BattleFx.update_hp_row(_me_hp_row, int(s.hp[0]))
	if _me_qi_row != null:
		BattleFx.update_qi_row(_me_qi_row, int(s.qi[0]))
	if _you_hp_row != null:
		BattleFx.update_hp_row(_you_hp_row, int(s.hp[1]))
	if _you_qi_row != null:
		BattleFx.update_qi_row(_you_qi_row, int(s.qi[1]))
	for i: int in GameRules.MAX_SHIELD:
		_me_shield_pips[i].color = COLOR_OK if i < int(s.shield[0]) else COLOR_EMPTY
		_you_shield_pips[i].color = COLOR_OK if i < int(s.shield[1]) else COLOR_EMPTY
	_refresh_actions()


func _refresh_actions() -> void:
	var s: BattleState = controller.state
	# 与 controller.is_pick_open 同源，禁止“亮着点不动”
	var open: bool = controller != null and controller.is_pick_open()
	btn_zan.disabled = (not open) or not s.can_use_action(0, GameRules.Action.ZAN)
	btn_bo.disabled = (not open) or not s.can_use_action(0, GameRules.Action.BO)
	btn_fang.disabled = (not open) or not s.can_use_action(0, GameRules.Action.FANG)

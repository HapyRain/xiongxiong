## main.gd
## 单人对战页（占位视觉）：顶部对手资源 / 回合比分 / 中部揭示区 / 底部按模式出招。
## 后端真接线：按钮走 BattleController.try_select；小局结算与终场用占位面板。
## TODO(ui): 替换资源条/揭示区/技能盘为真实 UI（占位块见 UiPlaceholder）。
extends Control

const SCENE := "res://scenes/main.tscn"
const SOLO_SCENE := "res://scenes/solo_select.tscn"
const DEFAULT_CFG := {"mode": "lesson", "mastery": false, "difficulty": "normal"}

@onready var controller: BattleController = $BattleController
@onready var info_label: Label = %InfoLabel
@onready var result_label: Label = %ResultLabel
@onready var you_slot: VBoxContainer = %YouSlot
@onready var reveal_slot: VBoxContainer = %RevealSlot
@onready var bottom_slot: VBoxContainer = %BottomSlot
@onready var overlay: Control = %Overlay
@onready var menu_btn: Button = %MenuBtn

var _cfg: Dictionary = {}
var _action_btns: Dictionary = {}
var _sfx_clap: AudioStream
var _sfx_ding: AudioStream
var _sfx_hit: AudioStream
var _sfx_block: AudioStream
var _sfx_zan: AudioStream
var _players: Array = []


func _ready() -> void:
	UiTheme.apply_to_tree(get_tree())
	# 单人选择页传来的 cfg；直接进 main（主菜单旧入口）时按 lesson 默认开打
	_cfg = (BattleController.pending_cfg as Dictionary).duplicate()
	BattleController.pending_cfg = {}
	if _cfg.is_empty():
		_cfg = DEFAULT_CFG.duplicate()
	UiNav.register_back_target(SCENE, SOLO_SCENE)
	add_child(UiBackRouter.new())
	menu_btn.pressed.connect(func(): UiNav.return_to_menu(get_tree()))
	_setup_audio()

	var you_ph := UiPlaceholder.block("对手资源", Vector2(0, 96))
	you_ph.size_flags_vertical = Control.SIZE_FILL
	you_slot.add_child(you_ph)
	# 我方资源与对手同构，插在底部出招区之前
	var me_slot := VBoxContainer.new()
	me_slot.name = "MeSlot"
	me_slot.custom_minimum_size = Vector2(0, 96)
	var vbox := bottom_slot.get_parent() as VBoxContainer
	vbox.add_child(me_slot)
	vbox.move_child(me_slot, bottom_slot.get_index())
	var me_ph := UiPlaceholder.block("我方资源", Vector2(0, 96))
	me_ph.size_flags_vertical = Control.SIZE_FILL
	me_slot.add_child(me_ph)
	var reveal_ph := UiPlaceholder.block("揭示区", Vector2(0, 80))
	reveal_slot.add_child(reveal_ph)
	reveal_slot.move_child(reveal_ph, 0)

	controller.start_match(_cfg)
	_build_actions()
	overlay.visible = false
	controller.phase_changed.connect(_on_phase)
	controller.beat.connect(_on_beat)
	controller.round_resolved.connect(_on_resolved)
	controller.game_over.connect(_on_game_over)
	_refresh()


func _process(_delta: float) -> void:
	_refresh()


## 底部出招区：classic 三个按钮；lesson 技能盘占位 13 格（仍真实可选）。
func _build_actions() -> void:
	var s: BattleState = controller.state
	var acts: Array = GameRules.preset(s.mode)["actions"]
	var grid := GridContainer.new()
	grid.columns = 3 if acts.size() <= 3 else 4
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var placeholder: bool = acts.size() > 3
	for a in acts:
		var act := int(a)
		var col: Color = UiTheme.PLACEHOLDER_BG
		var fg: Color = UiTheme.INK
		if not placeholder:
			col = UiTheme.ACCENT
			if act == GameRules.Action.BAO1:
				col = UiTheme.WAVE
				fg = Color.WHITE
			elif act == GameRules.Action.FANG:
				col = UiTheme.SHIELD
				fg = Color.WHITE
		var b := Button.new()
		b.name = "Action%d" % act
		b.text = ("【占位】" if placeholder else "") + GameRules.action_name(act)
		b.clip_text = true
		b.custom_minimum_size = Vector2(0, 52)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 12 if placeholder else 18)
		b.add_theme_font_override("font", UiTheme.default_font())
		b.add_theme_color_override("font_color", fg)
		b.add_theme_color_override("font_hover_color", fg)
		b.add_theme_color_override("font_pressed_color", fg)
		b.add_theme_color_override("font_disabled_color", Color(0.35, 0.33, 0.3))
		b.add_theme_stylebox_override("normal", UiTheme.button_style(col, 12))
		b.add_theme_stylebox_override("hover", UiTheme.button_style(col.lightened(0.08), 12))
		b.add_theme_stylebox_override("pressed", UiTheme.button_style(col.darkened(0.08), 12))
		b.add_theme_stylebox_override("disabled", UiTheme.button_style(Color(0.80, 0.78, 0.74), 12))
		b.pressed.connect(func(): _pick(act))
		grid.add_child(b)
		_action_btns[act] = b
	bottom_slot.add_child(grid)


func _pick(action: int) -> void:
	if controller.try_select(0, action):
		_play_sfx(_sfx_zan if action == GameRules.Action.ZAN else _sfx_ding, -6.0)
		_refresh()


# ---------- 音效（从 HEAD 版 main.gd 恢复：拍点 / 选招 / 结算） ----------

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
	# 全忙则抢第一个
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
	var open: bool = controller.is_pick_open()
	for k in _action_btns.keys():
		var b: Button = _action_btns[k]
		b.disabled = not open or not s.can_use_action(0, int(k))


func _on_phase(phase: int, _round_no: int) -> void:
	# 小局结算面板只挡这一拍；新小局开局窗一到就收起
	if phase == GameRules.Phase.SELECTING and overlay.visible:
		overlay.visible = false
	_refresh()


func _on_resolved(result: GameRules.RoundResult) -> void:
	result_label.text = result.text
	if result.opening:
		_play_sfx(_sfx_zan, -2.0)
	elif result.hit[0] or result.hit[1]:
		_play_sfx(_sfx_hit, 0.0)
	elif result.blocked[0] or result.blocked[1]:
		_play_sfx(_sfx_block, 0.0)
	elif int(result.qi_delta[0]) > 0 or int(result.qi_delta[1]) > 0:
		_play_sfx(_sfx_ding, -4.0)
	var s: BattleState = controller.state
	if s.is_over() and not s.is_match_over():
		_show_overlay("小局结算 · 我 %d : %d 对手" % [int(s.score[0]), int(s.score[1])], false)


func _on_game_over(winner: int) -> void:
	var text := "终场 · 平局"
	if winner == 0:
		text = "终场 · 我方胜利"
	elif winner == 1:
		text = "终场 · 对手胜利"
	_show_overlay(text, true)


func _show_overlay(text: String, with_buttons: bool) -> void:
	for c in overlay.get_children():
		overlay.remove_child(c)
		c.queue_free()
	overlay.visible = true
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP

	var dim := ColorRect.new()
	dim.color = Color(0.12, 0.1, 0.08, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)

	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(300, 0)
	v.add_theme_constant_override("separation", 10)
	center.add_child(v)
	v.add_child(UiPlaceholder.block(text, Vector2(300, 160)))

	if with_buttons:
		var again := UiTheme.make_btn("再来一局", UiTheme.ACCENT, Color.WHITE, 17, 48)
		again.pressed.connect(_on_again)
		v.add_child(again)
		var back := UiTheme.make_btn("返回菜单", UiTheme.LINE, UiTheme.INK, 17, 48)
		back.pressed.connect(func(): UiNav.return_to_menu(get_tree()))
		v.add_child(back)


func _on_again() -> void:
	overlay.visible = false
	result_label.text = ""
	controller.start_match(_cfg)
	_refresh()

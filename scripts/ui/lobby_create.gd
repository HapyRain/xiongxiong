## lobby_create.gd
## 创建房间：模式 + 精通 → 房主建房 → 等待页。
extends Control

const CREATE_PATH := "res://scenes/lobby_create.tscn"
const WAIT_SCENE := "res://scenes/lobby_wait.tscn"
const GAME_PORT := 47001

var _mode: String = "lesson"
var _mastery: bool = false
var _classic_btn: Button
var _lesson_btn: Button
var _mastery_check: CheckButton
var _name_label: Label
var _status: Label


func _ready() -> void:
	UiTheme.apply_to_tree(get_tree())
	UiNav.cleanup_overlays(get_tree())
	UiNav.register_back_target(CREATE_PATH, UiNav.MENU_SCENE, true)
	add_child(UiBackRouter.new())
	_build_ui()
	_refresh()


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = UiTheme.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var title := UiTheme.ink_label("创建房间", 24, UiTheme.INK)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title.offset_top = 48
	title.grow_horizontal = Control.GROW_DIRECTION_BOTH
	add_child(title)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 96)
	margin.add_theme_constant_override("margin_bottom", 16)
	add_child(margin)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	margin.add_child(v)

	v.add_child(UiTheme.banner_card("🏠 局域网建房", "房主权威结算 · 同 Wi-Fi 或热点直连", UiTheme.ACCENT, 96))

	var mode_row := HBoxContainer.new()
	mode_row.add_theme_constant_override("separation", 12)
	v.add_child(mode_row)
	_classic_btn = _mode_btn("经典模式", "classic")
	_lesson_btn = _mode_btn("课间模式", "lesson")
	mode_row.add_child(_classic_btn)
	mode_row.add_child(_lesson_btn)

	_mastery_check = CheckButton.new()
	_mastery_check.text = "技能精通（课间专用）"
	_mastery_check.add_theme_font_override("font", UiTheme.default_font())
	_mastery_check.add_theme_font_size_override("font_size", 16)
	_mastery_check.toggled.connect(func(on: bool):
		_mastery = on
		_refresh())
	v.add_child(_mastery_check)

	_name_label = UiTheme.ink_label("", 14, UiTheme.INK_SOFT)
	_name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_name_label)

	var create := UiTheme.make_btn("创建房间", UiTheme.ACCENT, Color.WHITE, 18, 56)
	create.pressed.connect(_on_create)
	BattleFx.bind_press(create, "zan")
	v.add_child(create)

	_status = UiTheme.ink_label("选择模式后创建，等待对手加入", 13, UiTheme.INK_FAINT)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size.y = 40
	v.add_child(_status)

	var back := UiTheme.make_btn("返回", UiTheme.BG_CARD, UiTheme.INK, 15, 42)
	back.pressed.connect(_back)
	v.add_child(back)


func _mode_btn(text: String, mode: String) -> Button:
	var b := UiTheme.make_btn(text, UiTheme.BG_CARD, UiTheme.INK, 18, 64)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(func():
		_mode = mode
		_refresh())
	return b


func _refresh() -> void:
	if _classic_btn == null:
		return
	_paint(_classic_btn, "classic")
	_paint(_lesson_btn, "lesson")
	_mastery_check.disabled = _mode != "lesson"
	if _mastery_check.disabled and _mastery_check.button_pressed:
		_mastery_check.button_pressed = false
		_mastery = false
	if _name_label != null:
		_name_label.text = "房间名：%s" % PeerManager.default_room_name(_mode, _mastery)


func _paint(b: Button, mode: String) -> void:
	var on := _mode == mode
	var bg := UiTheme.ACCENT if on else UiTheme.BG_CARD
	var fg := Color.WHITE if on else UiTheme.INK
	var border_col := bg.darkened(0.22) if on else UiTheme.LINE
	b.add_theme_color_override("font_color", fg)
	b.add_theme_color_override("font_hover_color", fg)
	b.add_theme_color_override("font_pressed_color", fg)
	b.add_theme_stylebox_override("normal", UiTheme.button_style(bg, 12, border_col))
	b.add_theme_stylebox_override("hover", UiTheme.button_style(bg.lightened(0.08), 12, border_col))
	b.add_theme_stylebox_override("pressed", UiTheme.button_style(bg.darkened(0.08), 12, border_col))


func _on_create() -> void:
	var net := UiNav.net() as PeerManager
	if net == null:
		return
	if net.get_session() != PeerManager.Session.IDLE:
		net.leave()
	if net.provider == null or net.get_mode() != PeerManager.Mode.ENET:
		var err := net.set_backend(PeerManager.Mode.ENET)
		if err != OK:
			_status.text = "无法启动联机：%s" % error_string(err)
			return
	var err2 := net.host_game({
		"mode": PeerManager.Mode.ENET,
		"game_mode": _mode,
		"mastery": _mastery,
		"room_name": PeerManager.default_room_name(_mode, _mastery),
		"host_name": OS.get_model_name(),
		"port": GAME_PORT,
		"token": "",
		"max_players": 2,
		"use_discover": true,
	})
	if err2 != OK:
		_status.text = "创建失败：%s" % error_string(err2)
		return
	get_tree().change_scene_to_file(WAIT_SCENE)


func _back() -> void:
	Engine.set_meta("xiongxiong_net_entry", true)
	UiNav.cleanup_overlays(get_tree())
	get_tree().change_scene_to_file(UiNav.MENU_SCENE)

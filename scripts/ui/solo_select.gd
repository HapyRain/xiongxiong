## solo_select.gd
## 1080P (1080×1920) 单人模式选择：经典/课间 + 普通/困难 + 精通（仅课间）+ 开始/返回。
## 开始 → 把 cfg 放进 BattleController.pending_cfg → main.tscn。单屏 1080×1920，不滚动。
extends Control

const SCENE := "res://scenes/solo_select.tscn"
const MENU_SCENE := "res://scenes/menu.tscn"
const MAIN_SCENE := "res://scenes/main.tscn"

const MODE_TITLE := {"classic": "经典模式", "lesson": "课间模式"}
const MODE_DESC := {"classic": "一局定胜负 · 1 血 · 攒/包子/防御", "lesson": "先到 12 分 · 技能按分解锁"}

var _mode: String = "classic"
var _difficulty: String = "normal"
var _mastery: bool = false
var _mode_btns: Dictionary = {}
var _diff_btns: Dictionary = {}
var _mastery_btn: CheckButton


func _ready() -> void:
	UiTheme.apply_to_tree(get_tree())
	UiNav.register_back_target(SCENE, MENU_SCENE)
	add_child(UiBackRouter.new())
	_build()
	_refresh()


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = UiTheme.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	UiTheme.add_stage_background(self, 0.35)

	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 54)
	margin.add_theme_constant_override("margin_right", 54)
	margin.add_theme_constant_override("margin_top", 48)
	margin.add_theme_constant_override("margin_bottom", 48)
	add_child(margin)

	var v := VBoxContainer.new()
	v.name = "Content"
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 24)
	margin.add_child(v)

	var title := UiTheme.ink_label("单人对战", 68, Color(1.0, 0.94, 0.70), 12, UiTheme.INK)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var sub := UiTheme.ink_label("选择模式与难度", 28, Color(0.90, 0.95, 1.0), 5, UiTheme.INK)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)

	v.add_child(_section("模式"))
	for m in ["classic", "lesson"]:
		var b := Button.new()
		b.custom_minimum_size = Vector2(0, 176)
		b.add_theme_font_override("font", UiTheme.default_font())
		b.add_theme_font_size_override("font_size", 36)
		b.pressed.connect(func():
			_mode = str(m)
			_refresh())
		BattleFx.bind_press(b, "zan" if m == "lesson" else "fang")
		v.add_child(b)
		_mode_btns[str(m)] = b

	v.add_child(_section("难度"))
	var diff_row := HBoxContainer.new()
	diff_row.add_theme_constant_override("separation", 24)
	v.add_child(diff_row)
	for d in ["normal", "hard"]:
		var b := Button.new()
		b.text = "普通" if d == "normal" else "困难"
		b.custom_minimum_size = Vector2(0, 112)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_override("font", UiTheme.default_font())
		b.add_theme_font_size_override("font_size", 36)
		b.pressed.connect(func():
			_difficulty = str(d)
			_refresh())
		BattleFx.bind_press(b, "default")
		diff_row.add_child(b)
		_diff_btns[str(d)] = b

	_mastery_btn = CheckButton.new()
	_mastery_btn.text = "技能精通（仅课间）"
	_mastery_btn.custom_minimum_size = Vector2(0, 88)
	_mastery_btn.add_theme_font_override("font", UiTheme.default_font())
	_mastery_btn.add_theme_font_size_override("font_size", 32)
	_mastery_btn.add_theme_color_override("font_color", Color.WHITE)
	_mastery_btn.add_theme_constant_override("outline_size", 5)
	_mastery_btn.add_theme_color_override("font_outline_color", UiTheme.INK)
	_mastery_btn.toggled.connect(func(on: bool): _mastery = on)
	v.add_child(_mastery_btn)

	var start := UiTheme.make_btn("开始对战", UiTheme.ACCENT, Color.WHITE, 42, 124)
	start.pressed.connect(_on_start)
	BattleFx.bind_press(start, "zan")
	v.add_child(start)

	var back := UiTheme.make_btn("返回", UiTheme.BG_CARD, UiTheme.INK, 34, 102)
	back.pressed.connect(_on_back)
	BattleFx.bind_press(back, "menu")
	v.add_child(back)


func _section(text: String) -> Label:
	var lab := UiTheme.ink_label(text, 30, Color(0.92, 0.96, 1.0), 5, UiTheme.INK)
	lab.custom_minimum_size.y = 40
	return lab


func _paint(b: Button, bg: Color, fg: Color) -> void:
	b.add_theme_color_override("font_color", fg)
	b.add_theme_color_override("font_hover_color", fg)
	b.add_theme_color_override("font_pressed_color", fg)
	b.add_theme_color_override("font_disabled_color", UiTheme.INK_FAINT)
	b.add_theme_constant_override("outline_size", 6 if fg == Color.WHITE else 0)
	b.add_theme_color_override("font_outline_color", UiTheme.INK)
	b.add_theme_stylebox_override("normal", UiTheme.button_style(bg, 26, UiTheme.INK, 4, 8))
	b.add_theme_stylebox_override("hover", UiTheme.button_style(bg.lightened(0.08), 26, UiTheme.INK, 4, 8))
	b.add_theme_stylebox_override("pressed", UiTheme.button_style(bg.darkened(0.08), 26, UiTheme.INK, 4, 3))


func _refresh() -> void:
	for m in _mode_btns.keys():
		var on: bool = m == _mode
		var b: Button = _mode_btns[m]
		b.text = ("✓ " if on else "") + str(MODE_TITLE[m]) + "\n" + str(MODE_DESC[m])
		_paint(b, UiTheme.ACCENT if on else UiTheme.BG_CARD, Color.WHITE if on else UiTheme.INK)
	for d in _diff_btns.keys():
		var on: bool = d == _difficulty
		var b: Button = _diff_btns[d]
		_paint(b, UiTheme.SHIELD if on else UiTheme.BG_CARD, Color.WHITE if on else UiTheme.INK)
	_mastery_btn.disabled = _mode != "lesson"
	if _mode != "lesson" and _mastery:
		_mastery = false
		_mastery_btn.set_pressed_no_signal(false)


func _on_start() -> void:
	BattleController.pending_cfg = {
		"mode": _mode,
		"mastery": _mastery and _mode == "lesson",
		"difficulty": _difficulty,
	}
	get_tree().change_scene_to_file(MAIN_SCENE)


func _on_back() -> void:
	UiNav.return_to_menu(get_tree())

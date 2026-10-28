## settings_panel.gd
## 1080P (1080×1920) 竖版设置 + 菜单入口：画质档位 / 返回菜单 / 退出游戏。
extends Control

var _tier_btns: Array[Button] = []
var _fps_label: Label
var _info_label: Label
var _auto_btn: Button
var _close_btn: Button
var _menu_btn: Button
var _quit_btn: Button
var _confirm_layer: Control
var _confirm_title: Label
var _confirm_body: Label
var _confirm_yes: Button
var _confirm_no: Button
var _confirm_mode: String = ""


func _ready() -> void:
	name = "SettingsPanelOverlay"
	add_to_group(UiNav.SETTINGS_GROUP)
	UiTheme.apply_to_tree(get_tree())
	var parent := get_parent()
	if parent != null and not parent is CanvasLayer:
		var layer: CanvasLayer = null
		var existing_layer := parent.get_node_or_null("SettingsPanelLayer")
		if existing_layer is CanvasLayer:
			layer = existing_layer
		else:
			layer = CanvasLayer.new()
			layer.name = "SettingsPanelLayer"
			layer.layer = 100
			parent.add_child(layer)
		parent.remove_child(self)
		layer.add_child(self)
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_ui()
	_build_confirm()
	_bind_press_anims()
	_refresh()
	var timer := Timer.new()
	timer.wait_time = 0.5
	timer.autostart = true
	timer.timeout.connect(_refresh)
	add_child(timer)


func _bind_press_anims() -> void:
	BattleFx.bind_press(_auto_btn, "quiet")
	BattleFx.bind_press(_menu_btn, "menu")
	BattleFx.bind_press(_close_btn, "quiet")
	BattleFx.bind_press(_quit_btn, "danger")
	BattleFx.bind_press(_confirm_yes, "menu")
	BattleFx.bind_press(_confirm_no, "quiet")
	for i in _tier_btns.size():
		BattleFx.bind_press(_tier_btns[i], "default")


func _build_ui() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.04, 0.06, 0.12, 0.65)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			_close_panel()
		elif ev is InputEventScreenTouch and (ev as InputEventScreenTouch).pressed:
			_close_panel())
	add_child(dim)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(820, 0)
	var sb := UiTheme.card_style(UiTheme.BG_CARD, 28, UiTheme.INK, 5)
	sb.content_margin_left = 36
	sb.content_margin_right = 36
	sb.content_margin_top = 28
	sb.content_margin_bottom = 28
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)

	_close_btn = UiTheme.make_btn("✕", UiTheme.BG_PANEL, UiTheme.INK, 34, 80)
	_close_btn.custom_minimum_size = Vector2(88, 80)
	_close_btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	_close_btn.pressed.connect(_close_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 22)
	panel.add_child(box)

	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 16)
	box.add_child(title_row)

	var title := UiTheme.ink_label("设置 / 菜单", 46, UiTheme.INK)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	title_row.add_child(_close_btn)

	_fps_label = UiTheme.ink_label("", 32, UiTheme.INK_SOFT)
	_fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_fps_label)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(row)

	for i: int in 3:
		var b := UiTheme.make_btn(QualitySettings.TIER_NAMES[i], UiTheme.BG_PANEL, UiTheme.INK, 38, 96)
		b.custom_minimum_size = Vector2(180, 96)
		b.toggle_mode = true
		b.pressed.connect(_on_tier_pressed.bind(i))
		row.add_child(b)
		_tier_btns.append(b)

	_info_label = UiTheme.ink_label("", 26, UiTheme.INK_SOFT)
	_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_info_label)

	var btn_col := VBoxContainer.new()
	btn_col.add_theme_constant_override("separation", 18)
	box.add_child(btn_col)

	_auto_btn = UiTheme.make_btn("恢复自动", UiTheme.SHIELD, Color.WHITE, 34, 102)
	_auto_btn.pressed.connect(_on_auto_pressed)
	btn_col.add_child(_auto_btn)

	_menu_btn = UiTheme.make_btn("返回菜单", UiTheme.ACCENT, Color.WHITE, 36, 108)
	_menu_btn.pressed.connect(_on_menu_pressed)
	btn_col.add_child(_menu_btn)

	_quit_btn = UiTheme.make_btn("退出游戏", UiTheme.DANGER, Color.WHITE, 34, 102)
	_quit_btn.pressed.connect(_on_quit_pressed)
	btn_col.add_child(_quit_btn)


func _close_panel() -> void:
	var p := get_parent()
	if p is CanvasLayer:
		p.queue_free()
	else:
		queue_free()


func _build_confirm() -> void:
	_confirm_layer = Control.new()
	_confirm_layer.name = "ConfirmLayer"
	_confirm_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_confirm_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	_confirm_layer.visible = false
	add_child(_confirm_layer)

	var dim := ColorRect.new()
	dim.color = Color(0.04, 0.06, 0.12, 0.62)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_confirm_layer.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_confirm_layer.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(760, 0)
	var sb := UiTheme.card_style(UiTheme.BG_CARD, 26, UiTheme.INK, 5)
	sb.content_margin_left = 32
	sb.content_margin_right = 32
	sb.content_margin_top = 24
	sb.content_margin_bottom = 24
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 22)
	panel.add_child(v)

	_confirm_title = UiTheme.ink_label("", 42, UiTheme.INK)
	_confirm_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_confirm_title)

	_confirm_body = UiTheme.ink_label("", 30, UiTheme.INK_SOFT)
	_confirm_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_confirm_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_confirm_body.custom_minimum_size = Vector2(660, 100)
	_confirm_body.add_theme_constant_override("line_spacing", 8)
	v.add_child(_confirm_body)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 28)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(row)

	_confirm_yes = UiTheme.make_btn("确定", UiTheme.DANGER, Color.WHITE, 34, 96)
	_confirm_yes.custom_minimum_size = Vector2(260, 96)
	_confirm_yes.pressed.connect(_on_confirm_yes)
	row.add_child(_confirm_yes)

	_confirm_no = UiTheme.make_btn("取消", UiTheme.BG_PANEL, UiTheme.INK, 34, 96)
	_confirm_no.custom_minimum_size = Vector2(260, 96)
	_confirm_no.pressed.connect(_on_confirm_no)
	row.add_child(_confirm_no)


func _show_confirm(mode: String, title: String, body: String) -> void:
	_confirm_mode = mode
	_confirm_title.text = title
	_confirm_body.text = body
	_confirm_layer.visible = true


func _on_confirm_yes() -> void:
	var mode := _confirm_mode
	_confirm_layer.visible = false
	_confirm_mode = ""
	match mode:
		"menu":
			UiNav.return_to_menu(get_tree())
		"quit":
			UiNav.quit_game(get_tree())
		_:
			pass
	if is_instance_valid(self):
		_close_panel()


func _on_confirm_no() -> void:
	_confirm_layer.visible = false
	_confirm_mode = ""


func _on_menu_pressed() -> void:
	if not UiNav.is_in_battle_scene(get_tree()):
		_close_panel()
		return
	_show_confirm("menu", "返回菜单", UiNav.leave_confirm_text())


func _on_quit_pressed() -> void:
	_show_confirm("quit", "退出游戏", "确定退出拍拍熊熊？")


func _on_tier_pressed(t: int) -> void:
	QualitySettings.set_tier(t, true)
	_refresh()


func _on_auto_pressed() -> void:
	QualitySettings.restore_auto()
	_refresh()


func _refresh() -> void:
	var t: int = QualitySettings.tier
	for i: int in _tier_btns.size():
		var on := (i == t)
		_tier_btns[i].button_pressed = on
		var bg := UiTheme.SHIELD if on else UiTheme.BG_PANEL
		var fg := Color.WHITE if on else UiTheme.INK
		_tier_btns[i].add_theme_color_override("font_color", fg)
		_tier_btns[i].add_theme_color_override("font_hover_color", fg)
		_tier_btns[i].add_theme_color_override("font_pressed_color", fg)
		_tier_btns[i].add_theme_constant_override("outline_size", 6 if on else 0)
		_tier_btns[i].add_theme_color_override("font_outline_color", UiTheme.INK)
		_tier_btns[i].add_theme_stylebox_override("normal", UiTheme.button_style(bg, 20, UiTheme.INK, 4, 6))
		_tier_btns[i].add_theme_stylebox_override("pressed", UiTheme.button_style(bg, 20, UiTheme.INK, 4, 6))

	var snap := FpsGuard.snapshot()
	_fps_label.text = "实际 FPS %d / 上限 %d" % [int(snap["fps"]), int(snap["max_fps"])]

	var probe: Dictionary = QualitySettings.device_probe
	var mode_name := "自动" if QualitySettings.auto_preset else "手动"
	_info_label.text = "当前档位：%s（%s）\n屏幕刷新率：%.0f Hz · 高档可达 %d\n探测：%d 核 · %d MB RAM · %s" % [
		QualitySettings.tier_name(),
		mode_name,
		float(snap["refresh_rate"]),
		int(snap["high_capable"]),
		int(probe.get("cpu_cores", 0)),
		int(probe.get("physical_mb", 0)),
		str(probe.get("gpu_name", "未知 GPU")),
	]

	if _menu_btn != null:
		if UiNav.is_in_battle_scene(get_tree()):
			_menu_btn.text = "返回菜单"
		else:
			_menu_btn.text = "返回菜单（当前已在菜单）"

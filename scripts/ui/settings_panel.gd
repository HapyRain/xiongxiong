## settings_panel.gd
## 竖版设置 + 菜单入口：画质档位 / 返回菜单 / 退出游戏。
## 由 QualitySettings 注入的右上角齿轮打开；也可独立进场景。
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
	name = "SettingsPanel"
	UiTheme.apply_to_tree(get_tree())
	# 抬到亮招层(10)之上，避免每回合结算盖住设置
	var parent := get_parent()
	if parent != null and not parent is CanvasLayer:
		var layer := CanvasLayer.new()
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
	dim.color = Color(0.08, 0.07, 0.06, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(320, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.99, 0.97, 0.94, 0.98)
	sb.border_color = Color(0.16, 0.16, 0.16)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(14)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 14
	sb.content_margin_bottom = 14
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	var title := Label.new()
	title.text = "设置 / 菜单"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.16, 0.16, 0.16))
	box.add_child(title)

	_fps_label = Label.new()
	_fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_fps_label.add_theme_font_size_override("font_size", 15)
	_fps_label.add_theme_color_override("font_color", Color(0.35, 0.33, 0.3))
	box.add_child(_fps_label)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(row)

	for i: int in 3:
		var b := Button.new()
		b.text = QualitySettings.TIER_NAMES[i]
		b.custom_minimum_size = Vector2(72, 44)
		b.toggle_mode = true
		b.add_theme_font_size_override("font_size", 20)
		b.pressed.connect(_on_tier_pressed.bind(i))
		row.add_child(b)
		_tier_btns.append(b)
	# 注：动效在 _bind_press_anims 统一绑定

	_info_label = Label.new()
	_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_label.add_theme_font_size_override("font_size", 13)
	_info_label.add_theme_color_override("font_color", Color(0.35, 0.33, 0.3))
	box.add_child(_info_label)

	var btn_col := VBoxContainer.new()
	btn_col.add_theme_constant_override("separation", 8)
	box.add_child(btn_col)

	_auto_btn = Button.new()
	_auto_btn.text = "恢复自动"
	_auto_btn.custom_minimum_size = Vector2(0, 44)
	_auto_btn.add_theme_font_size_override("font_size", 15)
	_auto_btn.pressed.connect(_on_auto_pressed)
	btn_col.add_child(_auto_btn)

	_menu_btn = Button.new()
	_menu_btn.text = "返回菜单"
	_menu_btn.custom_minimum_size = Vector2(0, 48)
	_menu_btn.add_theme_font_size_override("font_size", 17)
	_menu_btn.pressed.connect(_on_menu_pressed)
	btn_col.add_child(_menu_btn)

	_close_btn = Button.new()
	_close_btn.text = "关闭"
	_close_btn.custom_minimum_size = Vector2(0, 44)
	_close_btn.add_theme_font_size_override("font_size", 15)
	_close_btn.pressed.connect(queue_free)
	btn_col.add_child(_close_btn)

	_quit_btn = Button.new()
	_quit_btn.text = "退出游戏"
	_quit_btn.custom_minimum_size = Vector2(0, 44)
	_quit_btn.add_theme_font_size_override("font_size", 15)
	_quit_btn.add_theme_color_override("font_color", Color(0.75, 0.18, 0.16))
	_quit_btn.pressed.connect(_on_quit_pressed)
	btn_col.add_child(_quit_btn)


func _build_confirm() -> void:
	_confirm_layer = Control.new()
	_confirm_layer.name = "ConfirmLayer"
	_confirm_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_confirm_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	_confirm_layer.visible = false
	add_child(_confirm_layer)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_confirm_layer.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_confirm_layer.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(300, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.99, 0.97, 0.94)
	sb.border_color = Color(0.16, 0.16, 0.16)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(12)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)

	_confirm_title = Label.new()
	_confirm_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_confirm_title.add_theme_font_size_override("font_size", 18)
	v.add_child(_confirm_title)

	_confirm_body = Label.new()
	_confirm_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_confirm_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_confirm_body.custom_minimum_size = Vector2(260, 48)
	v.add_child(_confirm_body)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(row)

	_confirm_yes = Button.new()
	_confirm_yes.text = "确定"
	_confirm_yes.custom_minimum_size = Vector2(110, 44)
	_confirm_yes.pressed.connect(_on_confirm_yes)
	row.add_child(_confirm_yes)

	_confirm_no = Button.new()
	_confirm_no.text = "取消"
	_confirm_no.custom_minimum_size = Vector2(110, 44)
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


func _on_confirm_no() -> void:
	_confirm_layer.visible = false
	_confirm_mode = ""


func _on_menu_pressed() -> void:
	if not UiNav.is_in_battle_scene(get_tree()):
		# 已在主菜单：直接关面板即可
		queue_free()
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
		_tier_btns[i].button_pressed = (i == t)

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

	# 对局中才需要「返回菜单」；主菜单里改成提示关闭
	if _menu_btn != null:
		if UiNav.is_in_battle_scene(get_tree()):
			_menu_btn.text = "返回菜单"
		else:
			_menu_btn.text = "返回菜单（当前已在菜单）"

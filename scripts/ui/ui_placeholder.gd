## ui_placeholder.gd
## W0：统一占位块。新页面未做完时先摆一块占位，视觉随前端重做一起换，不为占位加复杂度。
class_name UiPlaceholder
extends RefCounted


## 返回铺满 container 的占位块：ColorRect 打底 + 居中 Label "【占位】text"。
static func block(text: String, min_size: Vector2 = Vector2(200, 80)) -> Control:
	var root := Control.new()
	var safe := text.strip_edges().validate_node_name()
	if safe.is_empty():
		safe = "empty"
	root.name = "Placeholder_" + safe
	root.custom_minimum_size = min_size
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var bg := ColorRect.new()
	bg.color = UiTheme.PLACEHOLDER_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg)

	var label := UiTheme.ink_label("【占位】" + text, 16, UiTheme.PLACEHOLDER_FG)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(label)
	return root

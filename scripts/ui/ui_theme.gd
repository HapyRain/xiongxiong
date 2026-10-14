## ui_theme.gd
## 全局 UI 色板 + 文字对比度。奶油底 + 深棕字，避免白字发虚。
class_name UiTheme
extends RefCounted

const BG := Color(0.973, 0.945, 0.898)          # #F8F1E5 奶油
const BG_CARD := Color(1.0, 0.992, 0.969)       # #FFFDF7 卡片
const BG_PANEL := Color(0.988, 0.973, 0.941)
const INK := Color(0.145, 0.118, 0.075)         # #251E13 主文字
const INK_SOFT := Color(0.353, 0.310, 0.243)    # #5A4F3E 次要
const INK_FAINT := Color(0.478, 0.431, 0.353)   # #7A6E5A 弱化
const LINE := Color(0.851, 0.788, 0.690)        # #D9C9B0 分割
const ACCENT := Color(0.910, 0.640, 0.130)      # #E8A321 攒/主按钮
const ACCENT_DEEP := Color(0.780, 0.480, 0.100)
const WAVE := Color(0.910, 0.365, 0.165)        # #E85D2A 波
const SHIELD := Color(0.165, 0.615, 0.560)      # #2A9D8F 防
const DANGER := Color(0.760, 0.260, 0.210)      # #C24235
const OK := Color(0.180, 0.550, 0.320)
const SHADOW := Color(0, 0, 0, 0.08)


static func ink_label(text: String, size: int = 15, color: Color = INK) -> Label:
	var lab := Label.new()
	lab.text = text
	lab.add_theme_font_size_override("font_size", size)
	lab.add_theme_color_override("font_color", color)
	return lab


static func card_style(bg: Color = BG_CARD, radius: int = 14, border: Color = LINE) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.set_border_width_all(1)
	sb.border_color = border
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	return sb


static func button_style(bg: Color, radius: int = 12, border: Color = Color(0, 0, 0, 0.12)) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.set_border_width_all(1)
	sb.border_color = border
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	return sb


static func make_btn(text: String, bg: Color, fg: Color = Color.WHITE, size: int = 18, height: int = 52) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, height)
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_color", fg)
	b.add_theme_color_override("font_hover_color", fg)
	b.add_theme_color_override("font_pressed_color", fg)
	b.add_theme_stylebox_override("normal", button_style(bg))
	b.add_theme_stylebox_override("hover", button_style(bg.lightened(0.08)))
	b.add_theme_stylebox_override("pressed", button_style(bg.darkened(0.08)))
	return b


static func tint_label(node: Node, color: Color) -> void:
	if node is Label:
		(node as Label).add_theme_color_override("font_color", color)
	for c in node.get_children():
		tint_label(c, color)

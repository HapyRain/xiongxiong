## ui_theme.gd
## 全局 UI 色板 + 立体卡片/双层技能盘组件工厂。
## 采用高对比「元气潮玩对决风」：清爽云白底 + 纯白立体卡片 + 鲜明语义色 + 两字技能大名。
class_name UiTheme
extends RefCounted

const BG := Color(0.949, 0.961, 0.973)          # #F2F5F8 清爽云灰白
const BG_CARD := Color(1.0, 1.0, 1.0)           # #FFFFFF 纯白卡片
const BG_PANEL := Color(0.973, 0.980, 0.988)    # #F8FAFC 浅石板面板
const INK := Color(0.059, 0.090, 0.165)         # #0F172A 深邃岩黑（主文字）
const INK_SOFT := Color(0.278, 0.333, 0.412)    # #475569 冷石板灰（次要文字）
const INK_FAINT := Color(0.580, 0.639, 0.722)   # #94A3B8 弱化灰蓝
const LINE := Color(0.796, 0.835, 0.882)        # #CBD5E1 清晰描边
const ACCENT := Color(0.961, 0.620, 0.043)      # #F59E0B 元气琥珀金（攒气/主按钮）
const ACCENT_DEEP := Color(0.851, 0.467, 0.024) # #D97706 深琥珀
const WAVE := Color(0.937, 0.267, 0.267)        # #EF4444 烈焰珊瑚红（攻击/包子/破防）
const SHIELD := Color(0.055, 0.647, 0.914)      # #0EA5E9 澄澈天青蓝（防御/护盾）
const SPECIAL := Color(0.545, 0.361, 0.965)     # #8B5CF6 电光幻影紫（吸收/爆气/终极）
const GAIN := Color(0.063, 0.725, 0.506)        # #10B981 翡翠生机绿（集气/回复）
const DANGER := Color(0.863, 0.149, 0.149)      # #DC2626 警示红
const OK := Color(0.063, 0.725, 0.506)          # #10B981 成功绿
const DISABLED_BG := Color(0.886, 0.910, 0.941) # #E2E8F0 禁用浅冷灰
const DISABLED_FG := Color(0.580, 0.639, 0.722) # #94A3B8 禁用字色
const SHADOW := Color(0.059, 0.090, 0.165, 0.10)
## W0 占位块（UiPlaceholder 兼容保留）
const PLACEHOLDER_BG := Color(0.886, 0.910, 0.941, 0.75)
const PLACEHOLDER_FG := Color(0.278, 0.333, 0.412)

const FONT_PATH := "res://assets/fonts/NotoSansSC-Regular.otf"

static var _font: Font = null
static var _theme: Theme = null


## 中文/符号缺字时用打包字体；SystemFont 作兜底（安卓系统 CJK）。
static func default_font() -> Font:
	if _font != null:
		return _font
	if ResourceLoader.exists(FONT_PATH):
		_font = load(FONT_PATH)
	if _font == null:
		var sf := SystemFont.new()
		sf.font_names = PackedStringArray([
			"Noto Sans CJK SC", "Noto Sans SC", "Source Han Sans SC",
			"Microsoft YaHei", "PingFang SC", "Droid Sans Fallback", "sans-serif",
		])
		_font = sf
	return _font


static func default_theme() -> Theme:
	if _theme != null:
		return _theme
	_theme = Theme.new()
	_theme.default_font = default_font()
	_theme.default_font_size = 15
	_theme.set_color("font_color", "Label", INK)
	_theme.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0))
	return _theme


## 把主题挂到场景树根，所有控件继承，避免安卓缺字方块/乱码。
static func apply_to_tree(tree: SceneTree) -> void:
	if tree == null or tree.root == null:
		return
	tree.root.theme = default_theme()


static func ink_label(text: String, size: int = 15, color: Color = INK) -> Label:
	var lab := Label.new()
	lab.text = text
	lab.add_theme_font_size_override("font_size", size)
	lab.add_theme_color_override("font_color", color)
	lab.add_theme_font_override("font", default_font())
	return lab


static func card_style(bg: Color = BG_CARD, radius: int = 14, border: Color = LINE, border_w: int = 2) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.set_border_width_all(border_w)
	sb.border_color = border
	sb.shadow_color = SHADOW
	sb.shadow_size = 2
	sb.shadow_offset = Vector2(0, 2)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	return sb


static func button_style(bg: Color, radius: int = 12, border: Color = Color(0, 0, 0, 0.18), border_w: int = 2) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.set_border_width_all(border_w)
	sb.border_color = border
	sb.border_width_bottom = border_w + 2
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb


static func make_btn(text: String, bg: Color, fg: Color = Color.WHITE, size: int = 18, height: int = 52) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, height)
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_font_override("font", default_font())
	b.add_theme_color_override("font_color", fg)
	b.add_theme_color_override("font_hover_color", fg)
	b.add_theme_color_override("font_pressed_color", fg)
	b.add_theme_color_override("font_disabled_color", DISABLED_FG)
	var border_col := bg.darkened(0.22)
	b.add_theme_stylebox_override("normal", button_style(bg, 12, border_col))
	b.add_theme_stylebox_override("hover", button_style(bg.lightened(0.08), 12, border_col))
	b.add_theme_stylebox_override("pressed", button_style(bg.darkened(0.10), 12, border_col))
	b.add_theme_stylebox_override("disabled", button_style(DISABLED_BG, 12, LINE))
	return b


static func tint_label(node: Node, color: Color) -> void:
	if node is Label:
		(node as Label).add_theme_color_override("font_color", color)
	for c in node.get_children():
		tint_label(c, color)


## 按动作枚举返回对应的语义主色
static func action_color(act: int) -> Color:
	match GameRules.action_category(act):
		"zan":
			return ACCENT
		"attack":
			return WAVE
		"defense":
			return SHIELD
		"gain":
			return GAIN
		"special":
			return SPECIAL
	return ACCENT


## 动作简短效果提示（用于按钮底部微角标，不污染 Button.text）
static func action_hint(act: int) -> String:
	match act:
		GameRules.Action.ZAN: return "+1气+1盾"
		GameRules.Action.BAO1: return "×1 单发"
		GameRules.Action.BAO2: return "×2 二连"
		GameRules.Action.BAO3: return "×3 破防"
		GameRules.Action.FANG: return "耗1盾"
		GameRules.Action.STRONG_FANG: return "挡一切"
		GameRules.Action.XIAO_YANG: return "破防封盾"
		GameRules.Action.JI_QI: return "+3气"
		GameRules.Action.XI_SHOU: return "偷增益"
		GameRules.Action.DA_YANG: return "穿普防"
		GameRules.Action.BAO_QI: return "满盾挡1"
		GameRules.Action.HUI_FU: return "+1血"
		GameRules.Action.ZHONG_JI: return "2血大招"
		GameRules.Action.QUAN_JIANG: return "直接胜"
	return ""


## 顶部视觉横幅卡（替代旧的 UiPlaceholder.block，用于菜单/房间/等待页）
static func banner_card(title_text: String, sub_text: String, accent: Color = ACCENT, min_h: float = 92.0) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, min_h)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := card_style(BG_CARD, 16, accent, 2)
	sb.border_width_bottom = 4
	panel.add_theme_stylebox_override("panel", sb)

	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 4)
	panel.add_child(v)

	var t := ink_label(title_text, 20, accent.darkened(0.12))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)

	var sub := ink_label(sub_text, 13, INK_SOFT)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(sub)
	return panel


## 创建技能按钮：Button.text 严格保持 2 个汉字（action_short_name），耗气与 CD/解锁状态通过内部角标呈现。
static func make_skill_slot(act: int, is_primary: bool = false) -> Button:
	var col := action_color(act)
	var b := Button.new()
	b.name = "Action%d" % act
	b.text = GameRules.action_short_name(act)
	b.custom_minimum_size = Vector2(0, 68 if is_primary else 52)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.clip_text = false
	b.add_theme_font_override("font", default_font())
	b.add_theme_font_size_override("font_size", 20 if is_primary else 16)
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", DISABLED_FG)
	var border_col := col.darkened(0.25)
	var rad := 14 if is_primary else 10
	b.add_theme_stylebox_override("normal", button_style(col, rad, border_col, 2))
	b.add_theme_stylebox_override("hover", button_style(col.lightened(0.08), rad, border_col, 2))
	b.add_theme_stylebox_override("pressed", button_style(col.darkened(0.12), rad, border_col, 2))
	b.add_theme_stylebox_override("disabled", button_style(DISABLED_BG, rad, LINE, 1))

	# 右上角：耗气或耗盾角标
	var cost_lab := ink_label("", 10, Color(1, 1, 1, 0.92))
	cost_lab.name = "CostBadge"
	cost_lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cost_lab.set_anchors_preset(Control.PRESET_TOP_WIDE)
	cost_lab.offset_left = 6
	cost_lab.offset_right = -6
	cost_lab.offset_top = 3
	cost_lab.offset_bottom = 16
	cost_lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(cost_lab)

	# 底部居中：CD / 解锁分 / 简短提示 / 连击数
	var sub_lab := ink_label("", 10, Color(1, 1, 1, 0.90))
	sub_lab.name = "SubBadge"
	sub_lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub_lab.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	sub_lab.offset_left = 4
	sub_lab.offset_right = -4
	sub_lab.offset_top = -15
	sub_lab.offset_bottom = -2
	sub_lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(sub_lab)

	return b


## 包子主键连点升级逻辑：课间模式下连续点击包子键可在 单包(1) -> 双包(2) -> 三包(3) 之间循环切换。
static func next_bao_action(s: BattleState, who: int, current_picked: int) -> int:
	if s == null or s.bao_max() <= 1:
		return GameRules.Action.BAO1
	if current_picked == GameRules.Action.BAO1 and s.can_use_action(who, GameRules.Action.BAO2):
		return GameRules.Action.BAO2
	if current_picked == GameRules.Action.BAO2 and s.can_use_action(who, GameRules.Action.BAO3):
		return GameRules.Action.BAO3
	return GameRules.Action.BAO1


## 刷新单个技能按钮的启用状态、选中高亮框与角标文案（严格保持 Button.text 为 2 个汉字）
static func update_skill_slot(
	b: Button,
	s: BattleState,
	who: int,
	act: int,
	can_lock: bool,
	picked_act: int,
	is_primary: bool = false
) -> void:
	if b == null or s == null:
		return
	var display_act := act
	var is_selected := (picked_act == act)
	if act == GameRules.Action.BAO1 and GameRules.is_bao(picked_act):
		display_act = picked_act
		is_selected = true

	# 硬约束：按钮主文字永远是 2 个汉字
	b.text = GameRules.action_short_name(display_act)

	var usable := s.can_use_action(who, act)
	b.disabled = (not can_lock) or (not usable)

	var col := action_color(display_act)
	var rad := 14 if is_primary else 10
	if not b.disabled:
		var b_col := INK if is_selected else col.darkened(0.25)
		var b_w := 3 if is_selected else 2
		var fill := col.lightened(0.10) if is_selected else col
		b.add_theme_stylebox_override("normal", button_style(fill, rad, b_col, b_w))

	var cost_lab := b.get_node_or_null("CostBadge") as Label
	var sub_lab := b.get_node_or_null("SubBadge") as Label

	var cost := GameRules.qi_cost(display_act)
	var cost_str := ""
	if cost > 0:
		cost_str = "%d气" % cost
	elif display_act == GameRules.Action.FANG:
		cost_str = "1盾"
	elif display_act == GameRules.Action.ZAN:
		cost_str = "0气"

	var sub_str := action_hint(display_act)
	var unlocked := true
	if s.skills_enabled() and not s.mastery:
		var req := GameRules.unlock_score(act)
		if int(s.score[who]) < req:
			unlocked = false
			sub_str = "🔒%d分" % req

	if unlocked:
		var cd := GameRules.cooldown_of(act)
		var cd_left := maxi(0, int(s.cooldowns[who].get(act, 0)) + cd + 1 - s.round) if cd > 0 else 0
		if cd_left > 0:
			sub_str = "⏳CD%d" % cd_left
		elif s.is_sealed(who) and GameRules.is_sealable(act):
			sub_str = "🚫封盾"
		elif not usable and s.round > GameRules.OPENING_ROUND:
			if cost > int(s.qi[who]):
				sub_str = "缺气"
			elif act == GameRules.Action.FANG and int(s.shield[who]) < 1:
				sub_str = "无盾"
		elif act == GameRules.Action.BAO1 and s.bao_max() > 1:
			if is_selected:
				var cnt := GameRules.bao_count(display_act)
				sub_str = "✓×%d 再点升" % cnt if cnt < s.bao_max() and int(s.qi[who]) >= cnt + 1 else "✓×%d 已选" % cnt
			else:
				sub_str = "连点1-3连"
		elif is_selected:
			sub_str = "✓已选"

	var badge_color := DISABLED_FG if b.disabled else Color(1, 1, 1, 0.94)
	if cost_lab != null:
		cost_lab.text = cost_str
		cost_lab.add_theme_color_override("font_color", badge_color)
	if sub_lab != null:
		sub_lab.text = sub_str
		sub_lab.add_theme_color_override("font_color", badge_color)

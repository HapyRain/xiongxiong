## ui_theme.gd
## 全局 UI 色板 + 立体卡片/双层四态技能盘 + UI 贴图加载器。
## 采用高对比「元气潮玩对决风」：清爽云白底 + 纯白立体卡片 + 鲜明语义色 + 两字技能大名 + 专属图标与四态遮罩。
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
const OK_GREEN := Color(0.063, 0.725, 0.506)    # #10B981 成功绿（勿命名 OK，会遮蔽全局 Error.OK）
const DISABLED_BG := Color(0.886, 0.910, 0.941) # #E2E8F0 禁用浅冷灰
const DISABLED_FG := Color(0.580, 0.639, 0.722) # #94A3B8 禁用字色
const SHADOW := Color(0.059, 0.090, 0.165, 0.10)
## W0 占位块（UiPlaceholder 兼容保留）
const PLACEHOLDER_BG := Color(0.886, 0.910, 0.941, 0.75)
const PLACEHOLDER_FG := Color(0.278, 0.333, 0.412)

const FONT_PATH := "res://assets/fonts/NotoSansSC-Regular.otf"

static var _font: Font = null
static var _theme: Theme = null
static var _tex_cache: Dictionary = {}


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


static func apply_to_tree(tree: SceneTree) -> void:
	if tree == null or tree.root == null:
		return
	tree.root.theme = default_theme()


## 加载 assets/ui/ 下的 PNG 贴图（支持已 import 资源与未 import 裸 PNG 字节双路加载，即放即用）
static func load_ui_texture(file_name: String) -> Texture2D:
	if _tex_cache.has(file_name):
		return _tex_cache[file_name]
	var res_path := "res://assets/ui/" + file_name
	var tex: Texture2D = null
	if ResourceLoader.exists(res_path):
		var loaded := load(res_path)
		if loaded is Texture2D:
			tex = loaded
	if tex == null and FileAccess.file_exists(res_path):
		var bytes := FileAccess.get_file_as_bytes(res_path)
		if not bytes.is_empty():
			var img := Image.new()
			if img.load_png_from_buffer(bytes) == OK:
				tex = ImageTexture.create_from_image(img)
	_tex_cache[file_name] = tex
	return tex


static func action_icon_name(act: int) -> String:
	match act:
		GameRules.Action.ZAN: return "icon_zan.png"
		GameRules.Action.BAO1: return "icon_bao1.png"
		GameRules.Action.BAO2: return "icon_bao2.png"
		GameRules.Action.BAO3: return "icon_bao3.png"
		GameRules.Action.FANG: return "icon_fang.png"
		GameRules.Action.STRONG_FANG: return "icon_strong_fang.png"
		GameRules.Action.XIAO_YANG: return "icon_xiao_yang.png"
		GameRules.Action.JI_QI: return "icon_ji_qi.png"
		GameRules.Action.XI_SHOU: return "icon_xi_shou.png"
		GameRules.Action.DA_YANG: return "icon_da_yang.png"
		GameRules.Action.BAO_QI: return "icon_bao_qi.png"
		GameRules.Action.HUI_FU: return "icon_hui_fu.png"
		GameRules.Action.ZHONG_JI: return "icon_zhong_ji.png"
		GameRules.Action.QUAN_JIANG: return "icon_quan_jiang.png"
	return "icon_zan.png"


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
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb


static func button_style(bg: Color, radius: int = 12, border: Color = Color(0, 0, 0, 0.18), border_w: int = 2, bottom_lip: int = 4) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.set_border_width_all(border_w)
	sb.border_color = border
	sb.border_width_bottom = border_w + bottom_lip
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
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
	b.add_theme_stylebox_override("normal", button_style(bg, 12, border_col, 2, 4))
	b.add_theme_stylebox_override("hover", button_style(bg.lightened(0.08), 12, border_col, 2, 4))
	b.add_theme_stylebox_override("pressed", button_style(bg.darkened(0.10), 12, border_col, 2, 1))
	b.add_theme_stylebox_override("disabled", button_style(DISABLED_BG, 12, LINE, 1, 2))
	return b


static func tint_label(node: Node, color: Color) -> void:
	if node is Label:
		(node as Label).add_theme_color_override("font_color", color)
	for c in node.get_children():
		tint_label(c, color)


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


## 创建四态技能按钮：
##   1. Button.text 严格保持 2 个汉字（action_short_name）
##   2. 挂载专属图标 (IconTex) + 四态遮罩贴图 (StateTex: CD/未解锁/封盾/选中发光) + 右上耗气角标 + 底部状态角标
##   3. 支持禁用态点击拒绝反馈（on_reject_cb）：玩家误触 CD/未解锁/封盾/缺气按钮时触发抖动 + 拒绝音效 + 原因提示
static func make_skill_slot(act: int, is_primary: bool = false, on_reject_cb: Callable = Callable()) -> Button:
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
	b.add_theme_stylebox_override("normal", button_style(col, rad, border_col, 2, 4))
	b.add_theme_stylebox_override("hover", button_style(col.lightened(0.10), rad, border_col, 2, 4))
	b.add_theme_stylebox_override("pressed", button_style(col.darkened(0.12), rad, border_col, 2, 1))
	b.add_theme_stylebox_override("disabled", button_style(DISABLED_BG, rad, LINE, 1, 2))

	# 1. 状态纹理层（CD斜纹 / 未解锁暗框 / 封盾红链 / 选中金框）
	var state_tex := TextureRect.new()
	state_tex.name = "StateTex"
	state_tex.set_anchors_preset(Control.PRESET_FULL_RECT)
	state_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	state_tex.stretch_mode = TextureRect.STRETCH_SCALE
	state_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	state_tex.visible = false
	b.add_child(state_tex)

	# 2. 左上角技能小图标
	var icon_tex := TextureRect.new()
	icon_tex.name = "IconTex"
	icon_tex.texture = load_ui_texture(action_icon_name(act))
	var ic_sz := 20 if is_primary else 15
	icon_tex.custom_minimum_size = Vector2(ic_sz, ic_sz)
	icon_tex.size = Vector2(ic_sz, ic_sz)
	icon_tex.position = Vector2(6 if is_primary else 4, 5 if is_primary else 3)
	icon_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(icon_tex)

	# 3. 右上角：耗气或耗盾角标
	var cost_lab := ink_label("", 10, Color(1, 1, 1, 0.94))
	cost_lab.name = "CostBadge"
	cost_lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cost_lab.set_anchors_preset(Control.PRESET_TOP_WIDE)
	cost_lab.offset_left = 6
	cost_lab.offset_right = -6
	cost_lab.offset_top = 3
	cost_lab.offset_bottom = 16
	cost_lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(cost_lab)

	# 4. 底部居中：CD / 解锁分 / 简短提示 / 连击数
	var sub_lab := ink_label("", 10, Color(1, 1, 1, 0.92))
	sub_lab.name = "SubBadge"
	sub_lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub_lab.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	sub_lab.offset_left = 4
	sub_lab.offset_right = -4
	sub_lab.offset_top = -15
	sub_lab.offset_bottom = -2
	sub_lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(sub_lab)

	# 5. 禁用态点击拒绝反馈（当按钮处于 CD / 未解锁 / 封盾 / 缺气 时被点击，给抖动+音效+原因）
	b.gui_input.connect(func(ev: InputEvent):
		if not b.disabled:
			return
		var clicked := false
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			clicked = true
		elif ev is InputEventScreenTouch and (ev as InputEventScreenTouch).pressed:
			clicked = true
		if clicked:
			var reason := str(b.get_meta("reject_reason", "当前不可用"))
			BattleFx.play_reject_feedback(b)
			if on_reject_cb.is_valid():
				on_reject_cb.call(act, reason))

	return b


static func next_bao_action(s: BattleState, who: int, current_picked: int) -> int:
	if s == null or s.bao_max() <= 1:
		return GameRules.Action.BAO1
	if current_picked == GameRules.Action.BAO1 and s.can_use_action(who, GameRules.Action.BAO2):
		return GameRules.Action.BAO2
	if current_picked == GameRules.Action.BAO2 and s.can_use_action(who, GameRules.Action.BAO3):
		return GameRules.Action.BAO3
	return GameRules.Action.BAO1


## 刷新四态技能按钮（Normal / Hover-Selected / Pressed / Disabled-CD-Locked-Sealed）
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

	var icon_tex := b.get_node_or_null("IconTex") as TextureRect
	if icon_tex != null:
		icon_tex.texture = load_ui_texture(action_icon_name(display_act))
		icon_tex.modulate = Color(1, 1, 1, 0.40 if b.disabled else 1.0)

	var state_tex := b.get_node_or_null("StateTex") as TextureRect
	var col := action_color(display_act)
	var rad := 14 if is_primary else 10

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
	var reject_reason := "当前非出招时间"
	var overlay_png := ""

	var unlocked := true
	if s.skills_enabled() and not s.mastery:
		var req := GameRules.unlock_score(act)
		if int(s.score[who]) < req:
			unlocked = false
			sub_str = "🔒%d分" % req
			reject_reason = "🔒 需满 %d 分解锁【%s】" % [req, GameRules.action_short_name(act)]
			overlay_png = "state_locked_overlay.png"

	if unlocked:
		var cd := GameRules.cooldown_of(act)
		var cd_left := maxi(0, int(s.cooldowns[who].get(act, 0)) + cd + 1 - s.round) if cd > 0 else 0
		if cd_left > 0:
			sub_str = "⏳CD%d" % cd_left
			reject_reason = "⏳ 【%s】冷却中（还需 %d 回合）" % [GameRules.action_short_name(act), cd_left]
			overlay_png = "state_cd_overlay.png"
		elif s.is_sealed(who) and GameRules.is_sealable(act):
			sub_str = "🚫封盾"
			reject_reason = "🚫 护盾被封锁，本回合无法使用【%s】" % GameRules.action_short_name(act)
			overlay_png = "state_sealed_overlay.png"
		elif not usable and s.round == GameRules.OPENING_ROUND:
			reject_reason = "⚡ 首回合开局亮相请先点「攒气」"
		elif not usable and s.round > GameRules.OPENING_ROUND:
			if cost > int(s.qi[who]):
				sub_str = "缺气"
				reject_reason = "💧 气不足（【%s】需 %d 气）" % [GameRules.action_short_name(act), cost]
			elif act == GameRules.Action.FANG and int(s.shield[who]) < 1:
				sub_str = "无盾"
				reject_reason = "🛡️ 护盾为 0，无法使用普通防御"
		elif act == GameRules.Action.BAO1 and s.bao_max() > 1:
			if is_selected:
				var cnt := GameRules.bao_count(display_act)
				sub_str = "✓×%d 再点升" % cnt if cnt < s.bao_max() and int(s.qi[who]) >= cnt + 1 else "✓×%d 已选" % cnt
				overlay_png = "state_selected_glow.png"
			else:
				sub_str = "连点1-3连"
		elif is_selected:
			sub_str = "✓已选"
			overlay_png = "state_selected_glow.png"

	b.set_meta("reject_reason", reject_reason)

	if not b.disabled:
		var b_col := Color(1.0, 0.90, 0.30) if is_selected else col.darkened(0.25)
		var b_w := 3 if is_selected else 2
		var fill := col.lightened(0.12) if is_selected else col
		b.add_theme_stylebox_override("normal", button_style(fill, rad, b_col, b_w, 4))

	if state_tex != null:
		if overlay_png != "":
			state_tex.texture = load_ui_texture(overlay_png)
			state_tex.visible = state_tex.texture != null
		else:
			state_tex.visible = false

	var badge_color := DISABLED_FG if b.disabled else Color(1, 1, 1, 0.95)
	if cost_lab != null:
		cost_lab.text = cost_str
		cost_lab.add_theme_color_override("font_color", DANGER if (b.disabled and cost > int(s.qi[who]) and unlocked) else badge_color)
	if sub_lab != null:
		sub_lab.text = sub_str
		sub_lab.add_theme_color_override("font_color", badge_color)

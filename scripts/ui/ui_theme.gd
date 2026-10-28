## ui_theme.gd
## 1080P (1080×1920) 全局三渲二 (3D-to-2D Cel-Shaded) 街机漫画风 UI 主题与四态双层技能盘。
## 核心设计约束（严禁漂移）：
##   1. 彻底采用三渲二粗黑描边（#090D16 4~6px 漫画黑边 + 立体厚底沿 + 文字 6~10px 黑描边）
##   2. 技能按钮图文严格分区：左侧独立图标槽、居中大号黑边白字（严格 2 个汉字）、右上黑底耗气胶囊、底部黑底状态条
##   3. 严禁使用任何系统 Emoji（// 等），全部采用纯正中文角标与几何贴图
##   4. 区分「结算演出锁输入 (can_lock=false)」与「技能不可用 (usable=false)」：可用技能在结算期间保持鲜亮原色，绝不整盘闪烁变灰
class_name UiTheme
extends RefCounted

const BG := Color(0.071, 0.098, 0.165)           # #12192A 深邃天台夜幕底色（衬托三渲二舞台背景）
const BG_CARD := Color(0.976, 0.984, 0.996)      # #F9FBFE 高亮漫画卡片白
const BG_PANEL := Color(0.925, 0.945, 0.976)     # #ECF1F9 浅石板面板
const BG_DARK_CARD := Color(0.086, 0.122, 0.204, 0.90) # #161F34E6 街机深色半透明战术底板
const INK := Color(0.035, 0.051, 0.090)          # #090D17 纯正漫画粗黑墨线
const INK_SOFT := Color(0.216, 0.275, 0.369)     # #37465E 深石板灰
const INK_FAINT := Color(0.471, 0.545, 0.647)    # #788BA5 弱化灰蓝
const LINE := Color(0.059, 0.090, 0.165)         # #0F172A 三渲二硬朗黑框线
const ACCENT := Color(0.961, 0.620, 0.043)       # #F59E0B 元气琥珀金（攒气/主按钮）
const ACCENT_DEEP := Color(0.851, 0.467, 0.024)  # #D97706 深琥珀
const WAVE := Color(0.937, 0.267, 0.267)         # #EF4444 烈焰珊瑚红（攻击/包子/破防）
const SHIELD := Color(0.055, 0.647, 0.914)       # #0EA5E9 澄澈天青蓝（防御/护盾）
const SPECIAL := Color(0.545, 0.361, 0.965)      # #8B5CF6 电光幻影紫（吸收/爆气/终极）
const GAIN := Color(0.063, 0.725, 0.506)         # #10B981 翡翠生机绿（集气/回复）
const DANGER := Color(0.886, 0.149, 0.212)       # #E22636 警示猩红
const OK_GREEN := Color(0.063, 0.725, 0.506)     # #10B981 成功绿（勿命名 OK，会遮蔽全局 Error.OK）
const DISABLED_BG := Color(0.145, 0.192, 0.282)  # #253148 未解锁/冷却深岩灰（高对比衬托白字）
const DISABLED_FG := Color(0.780, 0.835, 0.910)  # #C7D5E8 禁用态清晰银白字
const SHADOW := Color(0.020, 0.031, 0.059, 0.42)
## W0 占位块（UiPlaceholder 兼容保留）
const PLACEHOLDER_BG := Color(0.886, 0.910, 0.941, 0.75)
const PLACEHOLDER_FG := Color(0.278, 0.333, 0.412)

const FONT_PATH := "res://assets/fonts/NotoSansSC-Regular.otf"

static var _font: Font = null
static var _theme: Theme = null
static var _tex_cache: Dictionary = {}


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
	_theme.default_font_size = 30
	_theme.set_color("font_color", "Label", INK)
	_theme.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0))
	return _theme


static func apply_to_tree(tree: SceneTree) -> void:
	if tree == null or tree.root == null:
		return
	tree.root.theme = default_theme()


## 加载 assets/ui/ 下的 PNG/JPG 贴图（支持裸字节流免 import 直读 + ResourceLoader 双路加载）
static func load_ui_texture(file_name: String) -> Texture2D:
	if _tex_cache.has(file_name):
		return _tex_cache[file_name]
	var res_path := "res://assets/ui/" + file_name
	var tex: Texture2D = null
	if FileAccess.file_exists(res_path):
		var bytes := FileAccess.get_file_as_bytes(res_path)
		if not bytes.is_empty():
			var img := Image.new()
			var err := img.load_png_from_buffer(bytes) if file_name.ends_with(".png") else img.load_jpg_from_buffer(bytes)
			if err == Error.OK:
				tex = ImageTexture.create_from_image(img)
	if tex == null and ResourceLoader.exists(res_path):
		var loaded := load(res_path)
		if loaded is Texture2D:
			tex = loaded
	_tex_cache[file_name] = tex
	return tex


## 为任意全屏场景底层铺设 1080P 三渲二夕阳天台对决舞台背景 + 氛围暗角
static func add_stage_background(host: Control, dim_alpha: float = 0.22) -> TextureRect:
	var bg_tex := TextureRect.new()
	bg_tex.name = "StageBgTex"
	bg_tex.texture = load_ui_texture("stage_bg_cel.png")
	bg_tex.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(bg_tex)
	if dim_alpha > 0.001:
		var tint := ColorRect.new()
		tint.name = "StageTint"
		tint.color = Color(0.04, 0.06, 0.12, dim_alpha)
		tint.set_anchors_preset(Control.PRESET_FULL_RECT)
		tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		host.add_child(tint)
	return bg_tex


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


static func ink_label(text: String, size: int = 28, color: Color = INK, outline_px: int = 0, outline_col: Color = INK) -> Label:
	var lab := Label.new()
	lab.text = text
	lab.add_theme_font_size_override("font_size", size)
	lab.add_theme_color_override("font_color", color)
	lab.add_theme_font_override("font", default_font())
	if outline_px > 0:
		lab.add_theme_constant_override("outline_size", outline_px)
		lab.add_theme_color_override("font_outline_color", outline_col)
	return lab


static func card_style(bg: Color = BG_CARD, radius: int = 24, border: Color = INK, border_w: int = 4) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.set_border_width_all(border_w)
	sb.border_width_bottom = border_w + 5
	sb.border_color = border
	sb.shadow_color = SHADOW
	sb.shadow_size = 6
	sb.shadow_offset = Vector2(0, 4)
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	sb.content_margin_top = 14
	sb.content_margin_bottom = 14
	return sb


static func button_style(bg: Color, radius: int = 22, border: Color = INK, border_w: int = 4, bottom_lip: int = 8) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.set_border_width_all(border_w)
	sb.border_color = border
	sb.border_width_bottom = border_w + bottom_lip
	sb.shadow_color = Color(0, 0, 0, 0.28)
	sb.shadow_size = 4
	sb.shadow_offset = Vector2(0, 3)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	return sb


static func make_btn(text: String, bg: Color, fg: Color = Color.WHITE, size: int = 34, height: int = 104) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, height)
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_font_override("font", default_font())
	b.add_theme_color_override("font_color", fg)
	b.add_theme_color_override("font_hover_color", fg)
	b.add_theme_color_override("font_pressed_color", fg)
	b.add_theme_color_override("font_disabled_color", DISABLED_FG)
	if fg == Color.WHITE:
		b.add_theme_constant_override("outline_size", 6)
		b.add_theme_color_override("font_outline_color", INK)
	b.add_theme_stylebox_override("normal", button_style(bg, 22, INK, 4, 8))
	b.add_theme_stylebox_override("hover", button_style(bg.lightened(0.10), 22, INK, 4, 8))
	b.add_theme_stylebox_override("pressed", button_style(bg.darkened(0.12), 22, INK, 4, 2))
	b.add_theme_stylebox_override("disabled", button_style(DISABLED_BG, 22, INK, 3, 4))
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
		GameRules.Action.ZAN: return "+1气 +1盾"
		GameRules.Action.BAO1: return "×1 单发"
		GameRules.Action.BAO2: return "×2 二连"
		GameRules.Action.BAO3: return "×3 破防"
		GameRules.Action.FANG: return "耗 1 盾"
		GameRules.Action.STRONG_FANG: return "挡一切"
		GameRules.Action.XIAO_YANG: return "破防封盾"
		GameRules.Action.JI_QI: return "直加 3 气"
		GameRules.Action.XI_SHOU: return "偷取增益"
		GameRules.Action.DA_YANG: return "穿普通防"
		GameRules.Action.BAO_QI: return "满盾挡1包"
		GameRules.Action.HUI_FU: return "恢复 1 血"
		GameRules.Action.ZHONG_JI: return "2 血必杀"
		GameRules.Action.QUAN_JIANG: return "满态秒杀"
	return ""


static func banner_card(title_text: String, sub_text: String, accent: Color = ACCENT, min_h: float = 180.0) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, min_h)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := card_style(BG_CARD, 28, INK, 5)
	sb.border_width_bottom = 12
	panel.add_theme_stylebox_override("panel", sb)

	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)

	var t := ink_label(title_text, 40, accent.darkened(0.08), 6, Color(1, 1, 1, 0.9))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)

	var sub := ink_label(sub_text, 26, INK_SOFT)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(sub)
	return panel


## 创建 1080P 三渲二街机风四态技能按钮：
##   1. Button.text 严格保持 2 个汉字（action_short_name），配 8~10px 纯黑漫画描边，任何底色下 100% 清晰
##   2. 左侧独立图标槽 IconTex（绝不垫在文字正下方！），右上黑底耗气胶囊 CostBadge，底部深色状态带 SubBadge（零 Emoji！）
##   3. 支持禁用态点击拒绝反馈（on_reject_cb）：误触不可用技能时触发抖动 + 拒绝音效 + 顶部原因横幅
static func make_skill_slot(act: int, is_primary: bool = false, on_reject_cb: Callable = Callable()) -> Button:
	var col := action_color(act)
	var b := Button.new()
	b.name = "Action%d" % act
	b.text = GameRules.action_short_name(act)
	b.custom_minimum_size = Vector2(0, 152 if is_primary else 112)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.clip_text = false
	b.add_theme_font_override("font", default_font())
	b.add_theme_font_size_override("font_size", 46 if is_primary else 34)
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", Color.WHITE)
	b.add_theme_constant_override("outline_size", 10 if is_primary else 8)
	b.add_theme_color_override("font_outline_color", INK)

	var rad := 26 if is_primary else 18
	var lip := 10 if is_primary else 7
	var norm_sb := button_style(col, rad, INK, 4, lip)
	norm_sb.content_margin_bottom = 32 if is_primary else 26
	norm_sb.content_margin_left = 54 if is_primary else 38
	b.add_theme_stylebox_override("normal", norm_sb)
	b.add_theme_stylebox_override("hover", button_style(col.lightened(0.12), rad, INK, 4, lip))
	b.add_theme_stylebox_override("pressed", button_style(col.darkened(0.14), rad, INK, 4, 2))
	b.add_theme_stylebox_override("disabled", norm_sb)

	# 1. 状态纹理层（冷却斜纹 / 未解锁暗纹 / 封盾红角 / 选中金框 —— 中心全透明，绝不挡字）
	var state_tex := TextureRect.new()
	state_tex.name = "StateTex"
	state_tex.set_anchors_preset(Control.PRESET_FULL_RECT)
	state_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	state_tex.stretch_mode = TextureRect.STRETCH_SCALE
	state_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	state_tex.visible = false
	b.add_child(state_tex)

	# 2. 左侧独立技能徽章（锚定在按钮左侧，与中央二字大名完全分开，绝不重叠！）
	var icon_tex := TextureRect.new()
	icon_tex.name = "IconTex"
	icon_tex.texture = load_ui_texture(action_icon_name(act))
	var ic_sz := 62 if is_primary else 42
	icon_tex.anchor_left = 0.0
	icon_tex.anchor_right = 0.0
	icon_tex.anchor_top = 0.5
	icon_tex.anchor_bottom = 0.5
	icon_tex.offset_left = 12 if is_primary else 8
	icon_tex.offset_right = (12 if is_primary else 8) + ic_sz
	icon_tex.offset_top = -ic_sz * 0.5 - 10
	icon_tex.offset_bottom = ic_sz * 0.5 - 10
	icon_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(icon_tex)

	# 3. 右上角：深色漫画描边耗气胶囊
	var cost_pill := PanelContainer.new()
	cost_pill.name = "CostPill"
	cost_pill.anchor_left = 1.0
	cost_pill.anchor_right = 1.0
	cost_pill.anchor_top = 0.0
	cost_pill.anchor_bottom = 0.0
	cost_pill.offset_left = -82 if is_primary else -68
	cost_pill.offset_right = -8
	cost_pill.offset_top = 6
	cost_pill.offset_bottom = 36 if is_primary else 32
	cost_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pill_sb := StyleBoxFlat.new()
	pill_sb.bg_color = Color(0.035, 0.051, 0.090, 0.86)
	pill_sb.set_corner_radius_all(10)
	pill_sb.content_margin_left = 6
	pill_sb.content_margin_right = 6
	pill_sb.content_margin_top = 1
	pill_sb.content_margin_bottom = 1
	cost_pill.add_theme_stylebox_override("panel", pill_sb)
	b.add_child(cost_pill)

	var cost_lab := ink_label("", 20 if is_primary else 17, Color(1.0, 0.92, 0.45), 4, INK)
	cost_lab.name = "CostBadge"
	cost_lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cost_lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cost_lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cost_pill.add_child(cost_lab)

	# 4. 底部高对比黑底状态彩带（彻底解决底部小字看不清的问题，且严禁使用 Emoji）
	var sub_bar := PanelContainer.new()
	sub_bar.name = "SubBar"
	sub_bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	sub_bar.offset_left = 4
	sub_bar.offset_right = -4
	sub_bar.offset_top = -36 if is_primary else -30
	sub_bar.offset_bottom = -6
	sub_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sub_sb := StyleBoxFlat.new()
	sub_sb.bg_color = Color(0.035, 0.051, 0.090, 0.82)
	sub_sb.set_corner_radius_all(10)
	sub_sb.content_margin_left = 4
	sub_sb.content_margin_right = 4
	sub_sb.content_margin_top = 1
	sub_sb.content_margin_bottom = 1
	sub_bar.add_theme_stylebox_override("panel", sub_sb)
	b.add_child(sub_bar)

	var sub_lab := ink_label("", 20 if is_primary else 17, Color.WHITE, 4, INK)
	sub_lab.name = "SubBadge"
	sub_lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub_lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sub_lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sub_bar.add_child(sub_lab)

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


## 刷新 1080P 三渲二四态技能按钮：
##   关键设计：当技能本身可用 (usable=true) 但当前处于结算演出阶段 (can_lock=false) 时，
##   按钮只锁定点击 (b.disabled = true) 但保持鲜亮原色样式，绝不每回合全盘变灰闪烁！
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
		icon_tex.modulate = Color(1, 1, 1, 1.0 if usable else 0.52)

	var state_tex := b.get_node_or_null("StateTex") as TextureRect
	var col := action_color(display_act)
	var rad := 26 if is_primary else 18
	var lip := 10 if is_primary else 7

	var cost_lab := b.find_child("CostBadge", true, false) as Label
	var sub_lab := b.find_child("SubBadge", true, false) as Label

	var cost := GameRules.qi_cost(display_act)
	var cost_str := "0气"
	if cost > 0:
		cost_str = "%d气" % cost
	elif display_act == GameRules.Action.FANG:
		cost_str = "1盾"

	var sub_str := action_hint(display_act)
	var sub_col := Color(0.95, 0.98, 1.0)
	var reject_reason := "正在结算本拍交锋，请稍候"
	var overlay_png := ""

	var unlocked := true
	if s.skills_enabled() and not s.mastery:
		var req := GameRules.unlock_score(act)
		if int(s.score[who]) < req:
			unlocked = false
			sub_str = "%d分解锁" % req
			sub_col = Color(0.75, 0.82, 0.92)
			reject_reason = "需得 %d 分解锁【%s】（当前 %d 分）" % [req, GameRules.action_short_name(act), int(s.score[who])]
			overlay_png = "state_locked_overlay.png"

	if unlocked:
		var cd := GameRules.cooldown_of(act)
		var cd_left := maxi(0, int(s.cooldowns[who].get(act, 0)) + cd + 1 - s.round) if cd > 0 else 0
		if cd_left > 0:
			sub_str = "冷却 %d" % cd_left
			sub_col = Color(0.45, 0.86, 1.0)
			reject_reason = "【%s】冷却中（还需 %d 回合）" % [GameRules.action_short_name(act), cd_left]
			overlay_png = "state_cd_overlay.png"
		elif s.is_sealed(who) and GameRules.is_sealable(act):
			sub_str = "护盾被封"
			sub_col = Color(1.0, 0.45, 0.55)
			reject_reason = "护盾被小羊封锁，本回合禁用【%s】" % GameRules.action_short_name(act)
			overlay_png = "state_sealed_overlay.png"
		elif not usable and s.round == GameRules.OPENING_ROUND:
			reject_reason = "第 1 回合开局亮相请先点「攒气」"
		elif not usable and s.round > GameRules.OPENING_ROUND:
			if cost > int(s.qi[who]):
				sub_str = "缺气(%d)" % cost
				sub_col = Color(1.0, 0.55, 0.55)
				reject_reason = "气量不足：【%s】需要 %d 气" % [GameRules.action_short_name(act), cost]
			elif act == GameRules.Action.FANG and int(s.shield[who]) < 1:
				sub_str = "无护盾"
				sub_col = Color(1.0, 0.55, 0.55)
				reject_reason = "当前护盾为 0，无法使用普通防御"
		elif act == GameRules.Action.BAO1 and s.bao_max() > 1:
			if is_selected:
				var cnt := GameRules.bao_count(display_act)
				sub_str = "已选×%d 再点升阶" % cnt if cnt < s.bao_max() and int(s.qi[who]) >= cnt + 1 else "已锁×%d连发" % cnt
				sub_col = Color(1.0, 0.92, 0.35)
				overlay_png = "state_selected_glow.png"
			else:
				sub_str = "连点1~3连"
		elif is_selected:
			sub_str = "已锁定"
			sub_col = Color(1.0, 0.92, 0.35)
			overlay_png = "state_selected_glow.png"

	b.set_meta("reject_reason", reject_reason)

	# 样式构建：可用技能即使在结算锁定期（can_lock=false）也保持鲜明彩色，彻底告别每回合闪灰
	var fill := (col.lightened(0.14) if is_selected else col) if usable else DISABLED_BG
	var b_col := Color(1.0, 0.90, 0.25) if is_selected else INK
	var b_w := 6 if is_selected else 4
	var active_sb := button_style(fill, rad, b_col, b_w, lip if usable else 4)
	active_sb.content_margin_bottom = 32 if is_primary else 26
	active_sb.content_margin_left = 54 if is_primary else 38
	b.add_theme_stylebox_override("normal", active_sb)
	b.add_theme_stylebox_override("disabled", active_sb)
	b.add_theme_color_override("font_color", Color.WHITE if usable else DISABLED_FG)
	b.add_theme_color_override("font_disabled_color", Color.WHITE if usable else DISABLED_FG)

	if state_tex != null:
		if overlay_png != "":
			state_tex.texture = load_ui_texture(overlay_png)
			state_tex.visible = state_tex.texture != null
		else:
			state_tex.visible = false

	if cost_lab != null:
		cost_lab.text = cost_str
		var lack_qi := (unlocked and cost > int(s.qi[who]) and s.round > GameRules.OPENING_ROUND)
		cost_lab.add_theme_color_override("font_color", Color(1.0, 0.42, 0.42) if lack_qi else Color(1.0, 0.92, 0.45))
	if sub_lab != null:
		sub_lab.text = sub_str
		sub_lab.add_theme_color_override("font_color", sub_col)

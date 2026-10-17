## battle_fx.gd
## 血/气图标与命中/格挡/受击/胜负特效。纯 UI 表现，不碰 rules。
class_name BattleFx
extends RefCounted

const COLOR_HP := Color(0.91, 0.28, 0.32)
const COLOR_HP_EMPTY := Color(0.88, 0.82, 0.78)
const COLOR_QI := Color(0.22, 0.55, 0.92)
const COLOR_QI_EMPTY := Color(0.82, 0.84, 0.88)
const COLOR_SHIELD := Color(0.36, 0.72, 0.79)
const COLOR_SHIELD_EMPTY := Color(0.78, 0.74, 0.68)
const COLOR_HIT := Color(0.92, 0.25, 0.22)
const COLOR_BLOCK := Color(0.35, 0.70, 0.95)
const COLOR_WIN := Color(0.18, 0.72, 0.38)
const COLOR_LOSE := Color(0.85, 0.25, 0.22)
const COLOR_DRAW := Color(0.55, 0.50, 0.42)


## 一排图标：filled 个实心 + (max-filled) 个空心。用圆角 Panel，禁止 FULL_RECT 撑满。
static func make_pip_row(max_n: int, filled: int, color: Color, empty_color: Color, pip_size: Vector2 = Vector2(14, 14), gap: int = 4) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", gap)
	row.name = "PipRow"
	row.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in max_n:
		row.add_child(_make_pip(i < filled, color, empty_color, pip_size))
	return row


static func _make_pip(on: bool, color: Color, empty_color: Color, pip_size: Vector2) -> Panel:
	var p := Panel.new()
	p.custom_minimum_size = pip_size
	p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.set_meta("on", on)
	p.add_theme_stylebox_override("panel", _pip_style(on, color, empty_color, pip_size))
	return p


static func _pip_style(on: bool, color: Color, empty_color: Color, pip_size: Vector2) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color if on else empty_color
	if on:
		sb.border_color = color.darkened(0.18)
	else:
		sb.border_color = empty_color.darkened(0.12)
	sb.set_border_width_all(1)
	var r := int(round(minf(pip_size.x, pip_size.y) * 0.32))
	sb.set_corner_radius_all(r)
	sb.anti_aliasing = true
	return sb


## 更新已有 pip 行的亮灭。
## 每帧都会被 net_battle_ui._process → _refresh_all 调到（26 个 pip），
## 若每次都重建 StyleBoxFlat 会连触发 NOTIFICATION_THEME_CHANGED + 重排；
## 这里按「亮灭 + 颜色 + 尺寸」缓存 key，未变直接跳过。
static func update_pips(row: HBoxContainer, filled: int, color: Color, empty_color: Color) -> void:
	if row == null:
		return
	for i in row.get_child_count():
		var holder: Control = row.get_child(i)
		if holder == null:
			continue
		var on: bool = i < filled
		holder.set_meta("on", on)
		var pip_size: Vector2 = holder.custom_minimum_size
		if pip_size.x <= 0:
			pip_size = Vector2(14, 14)
		var key := "%s|%s|%s|%s" % [
			str(on), color.to_html(), empty_color.to_html(), str(pip_size)]
		if str(holder.get_meta("pip_key", "")) == key:
			continue
		holder.set_meta("pip_key", key)
		holder.add_theme_stylebox_override("panel", _pip_style(on, color, empty_color, pip_size))


## 血：红心圆点行
static func make_hp_row(max_n: int, filled: int) -> HBoxContainer:
	return make_pip_row(max_n, filled, COLOR_HP, COLOR_HP_EMPTY, Vector2(16, 16), 4)


## 气：蓝色能量珠
static func make_qi_row(max_n: int, filled: int) -> HBoxContainer:
	return make_pip_row(max_n, filled, COLOR_QI, COLOR_QI_EMPTY, Vector2(12, 12), 4)


## 盾：竖条
static func make_shield_row(max_n: int, filled: int) -> HBoxContainer:
	return make_pip_row(max_n, filled, COLOR_SHIELD, COLOR_SHIELD_EMPTY, Vector2(10, 16), 3)


# ---------- 开局聚光灯：压暗全场，只亮出「攒」 ----------

## 返回 Control（挂在 current_scene 下）；不用时 queue_free()。
static func show_focus_spotlight(tree: SceneTree, target: Control, caption: String = "点击「攒」开始对决") -> Control:
	if tree == null or tree.current_scene == null or target == null:
		return null
	var host: Node = tree.current_scene
	var root := Control.new()
	root.name = "OpeningSpotlight"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(root)
	root.set_meta("spot_target", target)
	root.set_meta("spot_caption", caption)

	if not target.tree_exiting.is_connected(_on_spot_target_exit.bind(root.get_instance_id())):
		# 只绑 instance_id，别把 root 对象本身绑进回调：
		# 场景退出时 root 可能已被释放，把已释放 Object 作为参数传给带类型的参数会报
		# "Cannot convert argument 1 from Object to Object"。
		target.tree_exiting.connect(_on_spot_target_exit.bind(root.get_instance_id()), CONNECT_ONE_SHOT)
	# 布局变化自愈（Qwen：首帧 size 够大但 pos=0 会锁死）
	if not target.item_rect_changed.is_connected(_on_spot_target_rect.bind(root)):
		target.item_rect_changed.connect(_on_spot_target_rect.bind(root))

	# 等布局稳定：连续两帧 rect 一致且不为原点
	_wait_stable_rect(tree, target, root, caption)
	return root


static func _on_spot_target_exit(root_id: int) -> void:
	var root := instance_from_id(root_id) as Control
	if root != null and is_instance_valid(root):
		root.queue_free()


static func _on_spot_target_rect(root: Control) -> void:
	if root == null or not is_instance_valid(root):
		return
	var target: Control = root.get_meta("spot_target")
	var caption: String = str(root.get_meta("spot_caption", ""))
	if target == null or not is_instance_valid(target):
		return
	# 节流到下一帧再重建，避免布局风暴
	var tree := root.get_tree()
	if tree == null:
		return
	tree.create_timer(0.0).timeout.connect(func():
		if is_instance_valid(root) and is_instance_valid(target):
			_build_spot_geometry(root, target, caption, false))


static func _wait_stable_rect(tree: SceneTree, target: Control, root: Control, caption: String) -> void:
	var prev := Rect2(-1, -1, -1, -1)
	var tries := 0
	while tries < 12:
		tries += 1
		await tree.process_frame
		if not is_instance_valid(root) or not is_instance_valid(target):
			return
		var r := target.get_global_rect()
		# 布局未完成：pos=(0,0) 但按钮并非真在原点
		if r.position.length() < 1.0 and r.size.y < 200 and tries < 12:
			prev = r
			continue
		if r.size.x < 4 or r.size.y < 4:
			continue
		if prev == r:
			_build_spot_geometry(root, target, caption, true)
			return
		prev = r
	# 兜底：12 帧后按当前 rect 建
	if is_instance_valid(root) and is_instance_valid(target):
		_build_spot_geometry(root, target, caption, true)


static func _target_local_rect(root: Control, target: Control) -> Rect2:
	# root 为全屏 Control 时，global_rect 原点即 root 局部原点（DPI/stretch 下仍对）
	var gr := target.get_global_rect()
	var origin := root.get_global_rect().position
	return Rect2(gr.position - origin, gr.size)


static func _build_spot_geometry(root: Control, target: Control, caption: String, animate: bool = true) -> void:
	if root == null or not is_instance_valid(root) or target == null or not is_instance_valid(target):
		return
	# 重建前先杀掉上一轮的「循环呼吸」tween：它挂在即将被回收的边框上，
	# 目标全失效后仍无限循环 → 引擎会报 "Infinite loop detected"。
	var old_loop: Variant = root.get_meta("loop_tween", null)
	if old_loop is Tween and (old_loop as Tween).is_valid():
		(old_loop as Tween).kill()
	root.set_meta("loop_tween", null)
	for c in root.get_children():
		c.queue_free()
	var r := _target_local_rect(root, target)
	# 真·布局未完成才重试（不要再用 size>=100 当完成）
	if r.size.x < 8 or r.size.y < 8:
		root.get_tree().create_timer(0.03).timeout.connect(func():
			if is_instance_valid(root) and is_instance_valid(target):
				_build_spot_geometry(root, target, caption, animate))
		return
	var hole := r.grow(14)

	var vs := Vector2(390, 820)
	if root.get_viewport() != null and root.get_viewport().get_visible_rect().size.x > 0:
		vs = root.get_viewport().get_visible_rect().size
	var vw := maxf(root.size.x, vs.x)
	var vh := maxf(root.size.y, vs.y)

	# 渐入暗幕
	var dim_color := Color(0.04, 0.035, 0.03, 0.0 if animate else 0.68)
	var d0 := _add_dim(root, Rect2(0, 0, vw, maxf(0, hole.position.y)), dim_color)
	var d1 := _add_dim(root, Rect2(0, hole.end.y, vw, maxf(0, vh - hole.end.y)), dim_color)
	var d2 := _add_dim(root, Rect2(0, hole.position.y, maxf(0, hole.position.x), hole.size.y), dim_color)
	var d3 := _add_dim(root, Rect2(hole.end.x, hole.position.y, maxf(0, vw - hole.end.x), hole.size.y), dim_color)
	if animate:
		var tw_dim := root.create_tween().set_parallel(true)
		for d in [d0, d1, d2, d3]:
			if d != null:
				tw_dim.tween_property(d, "color", Color(0.04, 0.035, 0.03, 0.68), 0.22)

	# 空心金框 + 入场缩放聚焦
	var border := 3.0
	var gold := Color(1.0, 0.82, 0.25, 0.95)
	var edges: Array[ColorRect] = []
	edges.append(_edge_rect(hole.position - Vector2(border, border), Vector2(hole.size.x + border * 2, border), gold))
	edges.append(_edge_rect(Vector2(hole.position.x - border, hole.end.y), Vector2(hole.size.x + border * 2, border), gold))
	edges.append(_edge_rect(hole.position - Vector2(border, 0), Vector2(border, hole.size.y), gold))
	edges.append(_edge_rect(Vector2(hole.end.x, hole.position.y), Vector2(border, hole.size.y), gold))
	for e in edges:
		root.add_child(e)
		e.pivot_offset = e.size * 0.5
		if animate:
			e.scale = Vector2(1.35, 1.35)
			e.modulate = Color(1, 1, 1, 0)
	if animate:
		var tw_in := root.create_tween().set_parallel(true)
		for e in edges:
			tw_in.tween_property(e, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw_in.tween_property(e, "modulate", Color(1, 1, 1, 1), 0.20)
		tw_in.chain().tween_interval(0.05)
		tw_in.chain().tween_callback(func():
			if not is_instance_valid(root):
				return
			# 目标已被后续重建回收 → 跳过呼吸脉冲。
			# 否则 tween 里全是无效目标，配合 set_loops() 会报 "Infinite loop detected"。
			for e in edges:
				if not is_instance_valid(e):
					return
			var tw := root.create_tween().set_loops()
			root.set_meta("loop_tween", tw)
			tw.tween_property(edges[0], "modulate", Color(1, 1, 1, 0.35), 0.48)
			for i in range(1, edges.size()):
				tw.parallel().tween_property(edges[i], "modulate", Color(1, 1, 1, 0.35), 0.48)
			tw.tween_property(edges[0], "modulate", Color(1, 1, 1, 1.0), 0.48)
			for i in range(1, edges.size()):
				tw.parallel().tween_property(edges[i], "modulate", Color(1, 1, 1, 1.0), 0.48))
	else:
		# 同上：目标已回收就别建无限循环 tween
		for e in edges:
			if not is_instance_valid(e):
				return
		var tw := root.create_tween().set_loops()
		root.set_meta("loop_tween", tw)
		tw.tween_property(edges[0], "modulate", Color(1, 1, 1, 0.35), 0.48)
		for i in range(1, edges.size()):
			tw.parallel().tween_property(edges[i], "modulate", Color(1, 1, 1, 0.35), 0.48)
		tw.tween_property(edges[0], "modulate", Color(1, 1, 1, 1.0), 0.48)
		for i in range(1, edges.size()):
			tw.parallel().tween_property(edges[i], "modulate", Color(1, 1, 1, 1.0), 0.48)

	# 目标按钮轻脉冲（仅首建时播一次）
	if animate and target != null and is_instance_valid(target):
		target.pivot_offset = target.size * 0.5
		var tw_b := root.create_tween()
		tw_b.tween_property(target, "scale", Vector2(1.08, 1.08), 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw_b.tween_property(target, "scale", Vector2(1.0, 1.0), 0.18)

	if caption != "":
		var lab := Label.new()
		lab.text = caption
		lab.add_theme_font_size_override("font_size", 17)
		lab.add_theme_color_override("font_color", Color(1, 0.95, 0.85))
		lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lab.modulate = Color(1, 1, 1, 1 if not animate else 0)
		root.add_child(lab)
		lab.reset_size()
		lab.position = Vector2((vw - lab.size.x) * 0.5, hole.position.y - 56)
		if animate:
			var tw2 := root.create_tween()
			tw2.tween_property(lab, "modulate", Color(1, 1, 1, 1), 0.25)

static func _edge_rect(pos: Vector2, size: Vector2, color: Color) -> ColorRect:
	var d := ColorRect.new()
	d.color = color
	d.position = pos
	d.size = size
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return d


static func _add_dim(root: Control, rect: Rect2, color: Color) -> ColorRect:
	if rect.size.x <= 0.5 or rect.size.y <= 0.5:
		return null
	var d := ColorRect.new()
	d.color = color
	d.position = rect.position
	d.size = rect.size
	d.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(d)
	return d


static func hide_focus_spotlight(layer: Control) -> void:
	if layer != null and is_instance_valid(layer):
		layer.queue_free()


## 「血」标签 + 图标行 + 数值，排成一行，避免糊在一起。
static func make_stat_line(title: String, row: HBoxContainer, value_lab: Label) -> HBoxContainer:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 6)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var t := Label.new()
	t.text = title
	t.custom_minimum_size.x = 22
	t.add_theme_font_size_override("font_size", 13)
	t.add_theme_color_override("font_color", UiTheme.INK_SOFT)
	line.add_child(t)
	if row != null:
		line.add_child(row)
	if value_lab != null:
		value_lab.add_theme_font_size_override("font_size", 12)
		value_lab.add_theme_color_override("font_color", UiTheme.INK)
		value_lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		value_lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		line.add_child(value_lab)
	return line


static func update_hp_row(row: HBoxContainer, filled: int) -> void:
	update_pips(row, filled, COLOR_HP, COLOR_HP_EMPTY)


static func update_qi_row(row: HBoxContainer, filled: int) -> void:
	update_pips(row, filled, COLOR_QI, COLOR_QI_EMPTY)


static func update_shield_row(row: HBoxContainer, filled: int) -> void:
	update_pips(row, filled, COLOR_SHIELD, COLOR_SHIELD_EMPTY)


# ---------- 按钮点击动效（每类按钮单独手感） ----------

## kind: zan / bo / fang / menu / danger / quiet / default
static func press_feedback(btn: BaseButton, kind: String = "default") -> void:
	if btn == null or not is_instance_valid(btn):
		return
	btn.pivot_offset = btn.size * 0.5
	var tw := btn.create_tween()
	match kind:
		"zan":
			# 攒：暖色弹跳上顶
			_tint_flash(btn, Color(1.0, 0.78, 0.22), 0.18)
			tw.tween_property(btn, "scale", Vector2(1.12, 1.12), 0.08).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.tween_property(btn, "scale", Vector2(1.0, 1.0), 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		"bo":
			# 波：短促收缩再弹开 + 轻旋
			_tint_flash(btn, Color(1.0, 0.55, 0.2), 0.16)
			tw.tween_property(btn, "scale", Vector2(0.88, 0.88), 0.06).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			tw.tween_property(btn, "rotation", -0.12, 0.05)
			tw.tween_property(btn, "scale", Vector2(1.08, 1.08), 0.08).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.tween_property(btn, "rotation", 0.0, 0.08)
			tw.tween_property(btn, "scale", Vector2.ONE, 0.08)
		"fang":
			# 防：压扁再撑住（盾感）
			_tint_flash(btn, Color(0.35, 0.70, 0.95), 0.18)
			tw.tween_property(btn, "scale", Vector2(1.15, 0.82), 0.07).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tw.tween_property(btn, "scale", Vector2(0.95, 1.08), 0.08)
			tw.tween_property(btn, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		"menu":
			# 菜单：右移轻推
			var base := btn.position
			tw.tween_property(btn, "position", base + Vector2(4, 0), 0.06)
			tw.tween_property(btn, "position", base, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			_tint_flash(btn, Color(0.45, 0.45, 0.48), 0.14)
		"danger":
			# 危险（退出等）：红闪 + 微抖
			_tint_flash(btn, Color(0.9, 0.25, 0.22), 0.22)
			var bpos := btn.position
			tw.tween_property(btn, "position", bpos + Vector2(-3, 0), 0.04)
			tw.tween_property(btn, "position", bpos + Vector2(3, 0), 0.05)
			tw.tween_property(btn, "position", bpos, 0.06)
			tw.tween_property(btn, "scale", Vector2(0.96, 0.96), 0.05)
			tw.tween_property(btn, "scale", Vector2.ONE, 0.1)
		"quiet":
			# 安静型（关闭/取消）：仅轻缩放
			tw.tween_property(btn, "scale", Vector2(0.96, 0.96), 0.06)
			tw.tween_property(btn, "scale", Vector2.ONE, 0.1)
		_:
			tw.tween_property(btn, "scale", Vector2(1.06, 1.06), 0.07).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tw.tween_property(btn, "scale", Vector2.ONE, 0.12)


## 按下瞬间染色再回落
static func _tint_flash(btn: BaseButton, color: Color, dur: float) -> void:
	if btn == null or not is_instance_valid(btn):
		return
	var tw := btn.create_tween()
	tw.tween_property(btn, "self_modulate", Color(1, 1, 1, 1).lerp(color, 0.35), 0.05)
	tw.tween_property(btn, "self_modulate", Color(1, 1, 1, 1), dur)


## 给按钮接上按压动效（pressed 时触发）。
static func bind_press(btn: BaseButton, kind: String = "default") -> void:
	if btn == null:
		return
	if btn.pressed.is_connected(_on_pressed_feedback):
		return
	btn.pressed.connect(_on_pressed_feedback.bind(btn, kind))


static func _on_pressed_feedback(btn: BaseButton, kind: String) -> void:
	press_feedback(btn, kind)


# ---------- 特效 ----------

## 命中：目标闪红 + 轻微抖动 + 爆点
static func play_hit(host: Control, target: Control) -> void:
	if host == null or target == null:
		return
	_flash_rect(host, target, COLOR_HIT)
	_shake(target)
	_burst(host, target, COLOR_HIT, 10)


## 格挡：盾面蓝光 + 环波
static func play_block(host: Control, target: Control) -> void:
	if host == null or target == null:
		return
	_flash_rect(host, target, COLOR_BLOCK)
	_ring(host, target, COLOR_BLOCK)


## 受击：短红闪（被波打中）
static func play_hurt(host: Control, target: Control) -> void:
	if host == null or target == null:
		return
	_flash_rect(host, target, Color(1, 0.4, 0.35, 0.55))
	_shake(target)


## 胜负庆祝：中心弹字 + 彩色纸屑
static func play_result(host: Control, winner: int, center: Control = null) -> void:
	if host == null:
		return
	var anchor: Control = center if center != null else host
	var color := COLOR_WIN if winner == 0 else (COLOR_LOSE if winner == 1 else COLOR_DRAW)
	var text := "胜利！" if winner == 0 else ("失败" if winner == 1 else "平局")
	_pop_label(host, anchor, text, color)
	_confetti(host, 28 if winner == 0 else 12)


## 发波弹道：从 from 控件飞向 to
static func play_projectile(host: Control, from: Control, to: Control, friendly: bool) -> void:
	if host == null or from == null or to == null:
		return
	var ball := ColorRect.new()
	ball.color = COLOR_QI if friendly else Color(0.95, 0.55, 0.2)
	ball.size = Vector2(18, 18)
	ball.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(ball)
	var a := from.get_global_rect().get_center()
	var b := to.get_global_rect().get_center()
	ball.global_position = a - ball.size * 0.5
	var tw := host.create_tween()
	tw.tween_property(ball, "global_position", b - ball.size * 0.5, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(ball, "scale", Vector2(1.6, 1.6), 0.06)
	tw.tween_callback(func():
		if is_instance_valid(ball):
			ball.queue_free())


static func _flash_rect(host: Control, target: Control, color: Color) -> void:
	var flash := ColorRect.new()
	flash.color = color
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.size = target.size
	flash.position = Vector2.ZERO
	target.add_child(flash)
	var tw := host.create_tween()
	tw.tween_property(flash, "color", Color(color.r, color.g, color.b, 0.0), 0.32)
	tw.tween_callback(func():
		if is_instance_valid(flash):
			flash.queue_free())


static func _shake(target: Control) -> void:
	if not is_instance_valid(target):
		return
	var base := target.position
	var tw := target.create_tween()
	for i in 4:
		var off := Vector2(randf_range(-4, 4), randf_range(-3, 3))
		tw.tween_property(target, "position", base + off, 0.04)
	tw.tween_property(target, "position", base, 0.05)


static func _burst(host: Control, target: Control, color: Color, n: int) -> void:
	var c := target.get_global_rect().get_center()
	for i in n:
		var p := ColorRect.new()
		p.color = color
		p.size = Vector2(6, 6)
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		host.add_child(p)
		p.global_position = c - p.size * 0.5
		var ang := TAU * float(i) / float(n)
		var dist := randf_range(28, 56)
		var tw := host.create_tween()
		tw.set_parallel(true)
		tw.tween_property(p, "global_position", c + Vector2(cos(ang), sin(ang)) * dist - p.size * 0.5, 0.28)
		tw.tween_property(p, "modulate", Color(1, 1, 1, 0), 0.28)
		tw.chain().tween_callback(func():
			if is_instance_valid(p):
				p.queue_free())


static func _ring(host: Control, target: Control, color: Color) -> void:
	var c := target.get_global_rect().get_center()
	var ring := ColorRect.new()
	ring.color = Color(color.r, color.g, color.b, 0.45)
	ring.size = Vector2(8, 8)
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(ring)
	ring.global_position = c - ring.size * 0.5
	var tw := host.create_tween()
	tw.set_parallel(true)
	tw.tween_property(ring, "size", Vector2(72, 72), 0.32).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(ring, "global_position", c - Vector2(36, 36), 0.32)
	tw.tween_property(ring, "modulate", Color(1, 1, 1, 0), 0.32)
	tw.chain().tween_callback(func():
		if is_instance_valid(ring):
			ring.queue_free())


static func _pop_label(host: Control, anchor: Control, text: String, color: Color) -> void:
	var lab := Label.new()
	lab.text = text
	lab.add_theme_font_size_override("font_size", 48)
	lab.add_theme_color_override("font_color", color)
	lab.modulate = Color(1, 1, 1, 0)
	host.add_child(lab)
	lab.reset_size()
	var c := anchor.get_global_rect().get_center()
	lab.global_position = c - lab.size * 0.5
	var tw := host.create_tween()
	tw.set_parallel(true)
	tw.tween_property(lab, "modulate", Color(1, 1, 1, 1), 0.12)
	tw.tween_property(lab, "scale", Vector2(1.15, 1.15), 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.chain().tween_interval(0.55)
	tw.chain().tween_property(lab, "modulate", Color(1, 1, 1, 0), 0.28)
	tw.chain().tween_callback(func():
		if is_instance_valid(lab):
			lab.queue_free())


static func _confetti(host: Control, n: int) -> void:
	var colors := [COLOR_HP, COLOR_QI, Color(0.98, 0.78, 0.2), COLOR_WIN, Color(0.7, 0.4, 0.9)]
	for i in n:
		var p := ColorRect.new()
		p.color = colors[i % colors.size()]
		p.size = Vector2(randf_range(6, 12), randf_range(8, 16))
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		host.add_child(p)
		var x := randf_range(20, host.size.x - 40) if host.size.x > 80 else randf_range(20, 360)
		p.position = Vector2(x, -20 - randf_range(0, 80))
		var rot := randf_range(-2.5, 2.5)
		var fall := host.size.y + 60 if host.size.y > 80 else 900.0
		var tw := host.create_tween()
		tw.set_parallel(true)
		tw.tween_property(p, "position", Vector2(x + randf_range(-40, 40), fall), randf_range(1.0, 1.8)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_property(p, "rotation", rot, 1.4)
		tw.chain().tween_callback(func():
			if is_instance_valid(p):
				p.queue_free())

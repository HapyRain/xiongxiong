## battle_fx.gd
## 1080P (1080×1920) 全屏三渲二 (3D-to-2D Cel-Shaded) 特效导演系统、炉石式烧绳倒计时、右下微缩打字机记招器与双保险音频引擎。
## 纯 UI 表现层，不碰 rules/* 结算逻辑。
class_name BattleFx
extends RefCounted

const COLOR_HP := Color(0.937, 0.267, 0.267)       # #EF4444 鲜红血槽
const COLOR_HP_EMPTY := Color(0.145, 0.192, 0.282) # #253148 深灰空槽
const COLOR_QI := Color(0.961, 0.620, 0.043)       # #F59E0B 元气琥珀金
const COLOR_QI_EMPTY := Color(0.145, 0.192, 0.282)
const COLOR_SHIELD := Color(0.055, 0.647, 0.914)   # #0EA5E9 天青蓝护盾
const COLOR_SHIELD_EMPTY := Color(0.145, 0.192, 0.282)
const COLOR_HIT := Color(0.937, 0.267, 0.267)
const COLOR_BLOCK := Color(0.055, 0.647, 0.914)
const COLOR_WIN := Color(0.063, 0.725, 0.506)
const COLOR_LOSE := Color(0.863, 0.149, 0.149)
const COLOR_DRAW := Color(0.478, 0.525, 0.604)

static var _wav_cache: Dictionary = {}


# ══════════════════════ 0. 全屏三渲二不规则动态特效画布与屏幕后处理着色器 (CelStageCanvas) ══════════════════════

const POST_FX_SHADER_CODE := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform vec2 center_uv = vec2(0.5, 0.35);
uniform float radial_blur : hint_range(0.0, 0.08) = 0.0;
uniform float chroma_split : hint_range(0.0, 0.04) = 0.0;
uniform float shock_radius : hint_range(0.0, 1.5) = 0.0;
uniform float shock_amp : hint_range(0.0, 0.08) = 0.0;
uniform float impact_invert : hint_range(0.0, 1.0) = 0.0;
uniform vec4 tint_col : source_color = vec4(1.0, 0.85, 0.2, 1.0);

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 to_c = uv - center_uv;
	float dist = length(to_c);
	vec2 dir = dist > 0.0001 ? to_c / dist : vec2(0.0);

	if (shock_amp > 0.0005) {
		float band = abs(dist - shock_radius);
		if (band < 0.16) {
			float w = (1.0 - band / 0.16);
			uv += dir * sin(band * 42.0) * shock_amp * w * w;
		}
	}

	vec3 col = vec3(0.0);
	if (radial_blur > 0.0005 || chroma_split > 0.0005) {
		for (int i = 0; i < 8; i++) {
			float t = float(i) / 7.0;
			vec2 s_uv = uv - to_c * (t * radial_blur);
			float r = texture(screen_tex, s_uv + dir * chroma_split * t).r;
			float g = texture(screen_tex, s_uv).g;
			float b = texture(screen_tex, s_uv - dir * chroma_split * t).b;
			col += vec3(r, g, b);
		}
		col /= 8.0;
	} else {
		col = texture(screen_tex, uv).rgb;
	}

	if (impact_invert > 0.01) {
		float lum = dot(col, vec3(0.299, 0.587, 0.114));
		float bw = step(0.45, lum);
		vec3 inv_c = mix(vec3(0.03, 0.04, 0.08), tint_col.rgb, 1.0 - bw);
		col = mix(col, inv_c, impact_invert);
	}

	COLOR = vec4(col, 1.0);
}
"""


class CelStageCanvas extends Control:
	var ambient_time: float = 0.0
	var me_aura_col: Color = Color(0.961, 0.620, 0.043, 0.0)
	var opp_aura_col: Color = Color(0.937, 0.267, 0.267, 0.0)
	var speed_lines_alpha: float = 0.0
	var speed_lines_col: Color = Color(1.0, 0.85, 0.25)
	var impact_flash_alpha: float = 0.0
	var impact_flash_col: Color = Color.WHITE
	var rings: Array = []          # 不规则锯齿爆裂多边形 [{pos, r, max_r, col, width, alpha, hex, spikes}]
	var slashes: Array = []        # 不规则狂暴刀光 [{a, b, col, width, alpha}]
	var lightning_bolts: Array = [] # 中点位移不规则雷霆折线 [{pts, col, width, alpha}]
	var cracks: Array = []          # 屏幕裂痕树 [{pts, col, width, alpha}]
	var shards: Array = []          # 物理崩飞不规则碎片 [{pos, vel, rot, rvel, poly, col, alpha}]
	var vortex_alpha: float = 0.0
	var vortex_pos: Vector2 = Vector2(540, 620)
	var vortex_rot: float = 0.0
	var vortex_scale: float = 1.0
	var vortex_col: Color = Color(0.62, 0.32, 1.0)

	# 屏幕空间径向模糊 / 色差撕裂 / 空气冲击波 / 黑白顿帧参数
	var post_rect: ColorRect = null
	var post_mat: ShaderMaterial = null
	var blur_strength: float = 0.0
	var chroma_strength: float = 0.0
	var shock_radius: float = 0.0
	var shock_amp: float = 0.0
	var impact_invert: float = 0.0
	var post_center_uv: Vector2 = Vector2(0.5, 0.34)
	var post_tint_col: Color = Color(1.0, 0.85, 0.2)

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_FULL_RECT)

	func _process(delta: float) -> void:
		ambient_time += delta
		if speed_lines_alpha > 0.005:
			speed_lines_alpha = maxf(0.0, speed_lines_alpha - delta * 2.1)
		if impact_flash_alpha > 0.005:
			impact_flash_alpha = maxf(0.0, impact_flash_alpha - delta * 6.0)
		if vortex_alpha > 0.005:
			vortex_rot += delta * 10.5
			vortex_alpha = maxf(0.0, vortex_alpha - delta * 1.65)
		if blur_strength > 0.0005:
			blur_strength = maxf(0.0, blur_strength - delta * 0.085)
		if chroma_strength > 0.0005:
			chroma_strength = maxf(0.0, chroma_strength - delta * 0.045)
		if shock_amp > 0.0005:
			shock_radius += delta * 1.35
			shock_amp = maxf(0.0, shock_amp - delta * 0.075)
		if impact_invert > 0.01:
			impact_invert = maxf(0.0, impact_invert - delta * 9.5)

		if post_mat != null and post_rect != null:
			var active_post := (blur_strength > 0.001 or chroma_strength > 0.001 or shock_amp > 0.001 or impact_invert > 0.01)
			post_rect.visible = active_post
			if active_post:
				post_mat.set_shader_parameter("center_uv", post_center_uv)
				post_mat.set_shader_parameter("radial_blur", blur_strength)
				post_mat.set_shader_parameter("chroma_split", chroma_strength)
				post_mat.set_shader_parameter("shock_radius", shock_radius)
				post_mat.set_shader_parameter("shock_amp", shock_amp)
				post_mat.set_shader_parameter("impact_invert", impact_invert)
				post_mat.set_shader_parameter("tint_col", post_tint_col)

		for i in range(rings.size() - 1, -1, -1):
			var d: Dictionary = rings[i]
			d["r"] = float(d["r"]) + (float(d["max_r"]) - float(d["r"])) * minf(1.0, delta * 9.5)
			d["alpha"] = float(d["alpha"]) - delta * 2.2
			if float(d["alpha"]) <= 0.02:
				rings.remove_at(i)
			else:
				rings[i] = d
		for i in range(slashes.size() - 1, -1, -1):
			var s: Dictionary = slashes[i]
			s["alpha"] = float(s["alpha"]) - delta * 3.0
			if float(s["alpha"]) <= 0.02:
				slashes.remove_at(i)
			else:
				slashes[i] = s
		for i in range(lightning_bolts.size() - 1, -1, -1):
			var lb: Dictionary = lightning_bolts[i]
			lb["alpha"] = float(lb["alpha"]) - delta * 3.6
			if float(lb["alpha"]) <= 0.02:
				lightning_bolts.remove_at(i)
			else:
				lightning_bolts[i] = lb
		for i in range(cracks.size() - 1, -1, -1):
			var cr: Dictionary = cracks[i]
			cr["alpha"] = float(cr["alpha"]) - delta * 1.15
			if float(cr["alpha"]) <= 0.02:
				cracks.remove_at(i)
			else:
				cracks[i] = cr
		for i in range(shards.size() - 1, -1, -1):
			var sh: Dictionary = shards[i]
			var v: Vector2 = sh["vel"]
			v.y += 1100.0 * delta
			sh["vel"] = v
			sh["pos"] = (sh["pos"] as Vector2) + v * delta
			sh["rot"] = float(sh["rot"]) + float(sh["rvel"]) * delta
			sh["alpha"] = float(sh["alpha"]) - delta * 1.65
			if float(sh["alpha"]) <= 0.02:
				shards.remove_at(i)
			else:
				shards[i] = sh
		queue_redraw()

	func trigger_speed_lines(col: Color, intensity: float = 0.92) -> void:
		speed_lines_col = col
		speed_lines_alpha = clampf(intensity, 0.0, 1.0)
		queue_redraw()

	func trigger_impact_flash(col: Color, alpha: float = 0.55) -> void:
		impact_flash_col = col
		impact_flash_alpha = clampf(alpha, 0.0, 0.85)
		queue_redraw()

	## 触发屏幕空间径向动态模糊 + 色差撕裂 + 空气扭曲波（爆气/大羊/终极技核心反馈）
	func trigger_screen_distortion(world_pos: Vector2, blur: float = 0.052, chroma: float = 0.020, s_amp: float = 0.042, invert: float = 0.0, tint: Color = Color(1.0, 0.85, 0.2)) -> void:
		var sz := size if size.x > 100 else Vector2(1080, 1920)
		post_center_uv = Vector2(clampf(world_pos.x / sz.x, 0.1, 0.9), clampf(world_pos.y / sz.y, 0.1, 0.7))
		blur_strength = maxf(blur_strength, blur)
		chroma_strength = maxf(chroma_strength, chroma)
		shock_radius = 0.04
		shock_amp = maxf(shock_amp, s_amp)
		impact_invert = maxf(impact_invert, invert)
		post_tint_col = tint

	## 添加不规则锯齿多边形爆裂冲击（彻底废除规则圆环，每次爆裂均生成随机不对称尖刺）
	func add_cel_ring(pos: Vector2, start_r: float, max_r: float, col: Color, width: float = 14.0, is_hex: bool = false) -> void:
		var n_pts := 18 if is_hex else 24
		var spikes := PackedFloat32Array()
		for i in n_pts:
			if i % 2 == 0:
				spikes.append(randf_range(1.02, 1.42))
			else:
				spikes.append(randf_range(0.46, 0.78))
		rings.append({
			"pos": pos, "r": start_r, "max_r": max_r,
			"col": col, "width": width, "alpha": 1.0, "hex": is_hex,
			"spikes": spikes, "rot": randf_range(0.0, TAU),
		})
		queue_redraw()

	func add_cel_slash(a: Vector2, b: Vector2, col: Color, width: float = 22.0) -> void:
		slashes.append({"a": a, "b": b, "col": col, "width": width, "alpha": 1.0})
		queue_redraw()

	## 添加中点位移不规则狂暴雷电折线（含分叉支流）
	func add_jagged_lightning(a: Vector2, b: Vector2, col: Color, width: float = 16.0, jitter: float = 78.0) -> void:
		var pts := PackedVector2Array()
		var segs := 9
		var dir := (b - a)
		var nrm := Vector2(-dir.y, dir.x).normalized()
		pts.append(a)
		for i in range(1, segs):
			var t := float(i) / float(segs)
			var env := sin(t * PI)
			var off := randf_range(-jitter, jitter) * env
			pts.append(a + dir * t + nrm * off)
		pts.append(b)
		lightning_bolts.append({"pts": pts, "col": col, "width": width, "alpha": 1.0})
		# 随机生成 2 条分叉支流闪电
		for _k in 2:
			var idx := randi_range(2, segs - 2)
			var fork_start: Vector2 = pts[idx]
			var fork_end := fork_start + dir.normalized().rotated(randf_range(-0.85, 0.85)) * randf_range(110.0, 240.0)
			var f_pts := PackedVector2Array([
				fork_start,
				(fork_start + fork_end) * 0.5 + nrm * randf_range(-38.0, 38.0),
				fork_end,
			])
			lightning_bolts.append({"pts": f_pts, "col": col.lightened(0.25), "width": width * 0.6, "alpha": 0.92})
		queue_redraw()

	## 添加不规则屏幕碎裂纹（小羊：局部蛛网裂痕；大羊/终极：横贯全屏的巨型地壳大裂痕）
	func add_screen_crack(origin: Vector2, is_huge: bool, col: Color) -> void:
		var n_branches := 22 if is_huge else 11
		var max_len := 560.0 if is_huge else 250.0
		for i in n_branches:
			var base_ang := TAU * float(i) / float(n_branches) + randf_range(-0.18, 0.18)
			var cur := origin
			var pts := PackedVector2Array([cur])
			var steps := 6 if is_huge else 4
			for s in steps:
				var seg_len := (max_len / float(steps)) * randf_range(0.65, 1.35)
				var ang := base_ang + randf_range(-0.42, 0.42)
				cur += Vector2(cos(ang), sin(ang)) * seg_len
				cur.y = clampf(cur.y, 20.0, 1280.0)
				pts.append(cur)
			cracks.append({
				"pts": pts,
				"col": col,
				"width": (18.0 if is_huge else 11.0) * randf_range(0.75, 1.25),
				"alpha": 1.0,
			})
		spawn_shatter_shards(origin, 26 if is_huge else 14, col, 1.45 if is_huge else 1.0)
		queue_redraw()

	## 喷射不规则多边形碎晶/碎石块
	func spawn_shatter_shards(origin: Vector2, count: int, col: Color, speed_scale: float = 1.0) -> void:
		for i in count:
			var ang := randf_range(0.0, TAU)
			var spd := randf_range(240.0, 880.0) * speed_scale
			var v_cnt := randi_range(3, 5)
			var poly := PackedVector2Array()
			var base_r := randf_range(12.0, 32.0) * speed_scale
			for v_idx in v_cnt:
				var va := TAU * float(v_idx) / float(v_cnt) + randf_range(-0.25, 0.25)
				var vr := base_r * randf_range(0.55, 1.35)
				poly.append(Vector2(cos(va) * vr, sin(va) * vr))
			shards.append({
				"pos": origin + Vector2(cos(ang), sin(ang)) * randf_range(8.0, 36.0),
				"vel": Vector2(cos(ang) * spd, sin(ang) * spd - randf_range(120.0, 360.0)),
				"rot": randf_range(0.0, TAU),
				"rvel": randf_range(-14.0, 14.0),
				"poly": poly,
				"col": col.lightened(randf_range(0.0, 0.38)),
				"alpha": 1.0,
			})
		queue_redraw()

	func trigger_vortex(pos: Vector2, col: Color, sc: float = 1.0) -> void:
		vortex_pos = pos
		vortex_col = col
		vortex_scale = sc
		vortex_alpha = 1.0
		queue_redraw()

	func _draw() -> void:
		var sz := size if size.x > 100 else Vector2(1080, 1920)
		var stage_h := minf(sz.y, 1320.0)
		var center := Vector2(sz.x * 0.5, stage_h * 0.50)

		# 0. 彻底废除那 3 个丑陋的闪烁圆圈！改用 12 道不规则斜掠疾风火种流线点缀天台空气感
		for idx in 12:
			var seed_f := float(idx) * 2.17
			var cycle := fmod(ambient_time * (75.0 + float(idx % 4) * 22.0) + float(idx) * 90.0, 920.0)
			var prog := clampf(cycle / 920.0, 0.0, 1.0)
			var px := fmod(120.0 + float(idx) * 86.0 + cycle * 0.32, sz.x - 100.0) + 50.0
			var py := 1060.0 - cycle * 0.82 + sin(ambient_time * 2.5 + seed_f) * 18.0
			var ea := sin(prog * PI) * 0.58
			var streak_dir := Vector2(0.42, -0.91)
			var streak_nrm := Vector2(0.91, 0.42)
			var slen := 18.0 + float(idx % 3) * 9.0
			var sw := 3.5 + float(idx % 2) * 2.0
			var p_head := Vector2(px, py) + streak_dir * slen
			var p_tail := Vector2(px, py) - streak_dir * slen
			var s_poly := PackedVector2Array([
				p_head,
				Vector2(px, py) + streak_nrm * sw,
				p_tail,
				Vector2(px, py) - streak_nrm * sw,
			])
			var ecol := Color(1.0, 0.76, 0.22, ea) if (idx % 2 == 0) else Color(0.28, 0.86, 1.0, ea)
			draw_colored_polygon(s_poly, ecol)

		# 1. Impact Frame 瞬态高对比闪光（仅覆盖上方特效舞台区 y=0..stage_h）
		if impact_flash_alpha > 0.01:
			draw_rect(Rect2(0, 0, sz.x, stage_h), Color(impact_flash_col.r, impact_flash_col.g, impact_flash_col.b, impact_flash_alpha * 0.48), true)

		# 2. 全屏三渲二不规则放射漫画速度线（长短粗细随机错落，极具张力）
		if speed_lines_alpha > 0.01:
			var n_spikes := 52
			for i in n_spikes:
				var ang := TAU * float(i) / float(n_spikes) + sin(float(i) * 3.7) * 0.025
				var outer_r := 880.0
				var inner_r := 190.0 + float((i * 61) % 240)
				var half_w := 0.028 if (i % 3 == 0) else (0.016 if (i % 2 == 0) else 0.009)
				var p0 := center + Vector2(cos(ang - half_w), sin(ang - half_w)) * outer_r
				var p1 := center + Vector2(cos(ang + half_w), sin(ang + half_w)) * outer_r
				var tip := center + Vector2(cos(ang), sin(ang)) * inner_r
				p0.y = clampf(p0.y, 0.0, stage_h)
				p1.y = clampf(p1.y, 0.0, stage_h)
				tip.y = clampf(tip.y, 0.0, stage_h)
				var ink_c := Color(0.03, 0.05, 0.10, speed_lines_alpha * 0.84)
				var fill_c := Color(speed_lines_col.r, speed_lines_col.g, speed_lines_col.b, speed_lines_alpha * 0.90)
				draw_colored_polygon(PackedVector2Array([p0, p1, tip]), ink_c if (i % 3 == 0) else fill_c)

		# 3. 吸收黑洞不规则撕裂引力旋臂（无规则圆圈，纯锯齿黑洞裂隙与狂暴旋臂）
		if vortex_alpha > 0.01:
			var vr := 260.0 * vortex_scale
			var core_poly := PackedVector2Array()
			for k in 20:
				var ca := vortex_rot * -1.4 + float(k) * TAU / 20.0
				var cr := vr * (0.48 if k % 2 == 0 else 0.30)
				core_poly.append(vortex_pos + Vector2(cos(ca), sin(ca)) * cr)
			draw_colored_polygon(core_poly, Color(0.03, 0.01, 0.08, vortex_alpha * 0.94))
			for arm in 7:
				var base_a := vortex_rot + float(arm) * TAU / 7.0
				var pts := PackedVector2Array()
				for step in 12:
					var t := float(step) / 11.0
					var rr := lerpf(22.0, vr * 1.25, t) + sin(t * 18.0 + float(arm)) * 16.0
					var aa := base_a + t * 2.65
					pts.append(vortex_pos + Vector2(cos(aa), sin(aa)) * rr)
				draw_polyline(pts, Color(0.03, 0.05, 0.10, vortex_alpha * 0.95), 16.0)
				draw_polyline(pts, Color(vortex_col.lightened(0.35).r, vortex_col.lightened(0.35).g, vortex_col.lightened(0.35).b, vortex_alpha), 8.0)

		# 4. 不规则锯齿爆裂冲击多边形（替代原先单调的圆环！）
		for d: Dictionary in rings:
			var pos: Vector2 = d["pos"]
			var r: float = float(d["r"])
			var a: float = clampf(float(d["alpha"]), 0.0, 1.0)
			var col: Color = d["col"]
			var w: float = float(d["width"])
			var spikes: PackedFloat32Array = d.get("spikes", PackedFloat32Array())
			var base_rot: float = float(d.get("rot", 0.0))
			var n_s := spikes.size()
			if n_s >= 6:
				var poly_pts := PackedVector2Array()
				for k in range(n_s + 1):
					var idx_s := k % n_s
					var ang := base_rot + float(idx_s) * TAU / float(n_s)
					var sr := r * spikes[idx_s]
					var pt := pos + Vector2(cos(ang), sin(ang)) * sr
					pt.y = clampf(pt.y, 0.0, stage_h)
					poly_pts.append(pt)
				draw_polyline(poly_pts, Color(0.03, 0.05, 0.10, a * 0.95), w + 10.0)
				draw_polyline(poly_pts, Color(col.r, col.g, col.b, a), w)
				draw_polyline(poly_pts, Color(1.0, 1.0, 1.0, a * 0.78), maxf(2.0, w * 0.35))

		# 5. 屏幕裂痕树（小羊蛛网裂痕 / 大羊与终极技全屏地壳崩裂）
		for cr: Dictionary in cracks:
			var c_pts: PackedVector2Array = cr["pts"]
			var ca2: float = clampf(float(cr["alpha"]), 0.0, 1.0)
			var c_col: Color = cr["col"]
			var cw: float = float(cr["width"])
			if c_pts.size() >= 2:
				draw_polyline(c_pts, Color(0.02, 0.03, 0.07, ca2 * 0.96), cw + 8.0)
				draw_polyline(c_pts, Color(c_col.r, c_col.g, c_col.b, ca2 * 0.95), cw)
				draw_polyline(c_pts, Color(1.0, 0.98, 0.92, ca2 * 0.85), maxf(2.0, cw * 0.35))

		# 6. 中点位移不规则雷霆折线
		for lb: Dictionary in lightning_bolts:
			var l_pts: PackedVector2Array = lb["pts"]
			var la: float = clampf(float(lb["alpha"]), 0.0, 1.0)
			var l_col: Color = lb["col"]
			var lw: float = float(lb["width"])
			if l_pts.size() >= 2:
				draw_polyline(l_pts, Color(0.03, 0.05, 0.10, la * 0.95), lw + 10.0)
				draw_polyline(l_pts, Color(l_col.r, l_col.g, l_col.b, la), lw)
				draw_polyline(l_pts, Color(1.0, 1.0, 1.0, la * 0.92), maxf(2.5, lw * 0.38))

		# 7. 三渲二不规则狂暴刀光 / 撕裂斩击
		for s: Dictionary in slashes:
			var pa: Vector2 = s["a"]
			var pb: Vector2 = s["b"]
			var a2: float = clampf(float(s["alpha"]), 0.0, 1.0)
			var col2: Color = s["col"]
			var w2: float = float(s["width"]) * a2
			var dir := (pb - pa).normalized()
			var nrm := Vector2(-dir.y, dir.x) * w2
			var mid := (pa + pb) * 0.5 + nrm * 0.22
			var poly := PackedVector2Array([pa, mid + nrm, pb, mid - nrm * 0.85])
			draw_colored_polygon(poly, Color(0.03, 0.05, 0.10, a2))
			var poly_in := PackedVector2Array([pa, mid + nrm * 0.55, pb, mid - nrm * 0.45])
			draw_colored_polygon(poly_in, Color(col2.r, col2.g, col2.b, a2))

		# 8. 物理崩飞的不规则多边形碎晶与岩石残片
		for sh: Dictionary in shards:
			var spos: Vector2 = sh["pos"]
			if spos.y > stage_h:
				continue
			var srot: float = float(sh["rot"])
			var sa: float = clampf(float(sh["alpha"]), 0.0, 1.0)
			var scol: Color = sh["col"]
			var base_poly: PackedVector2Array = sh["poly"]
			var xform_poly := PackedVector2Array()
			var cs := cos(srot)
			var sn := sin(srot)
			for pt in base_poly:
				xform_poly.append(spos + Vector2(pt.x * cs - pt.y * sn, pt.x * sn + pt.y * cs))
			if xform_poly.size() >= 3:
				draw_colored_polygon(xform_poly, Color(scol.r, scol.g, scol.b, sa))
				xform_poly.append(xform_poly[0])
				draw_polyline(xform_poly, Color(0.03, 0.05, 0.10, sa * 0.95), 4.5)


# ══════════════════════ 1. 音频引擎（三层兜底：裸 WAV 字节 -> ResourceLoader -> 内存级 PCM 合成器） ══════════════════════

## 优先直接读取裸 WAV 的 16-bit PCM 字节（彻底绕开 Godot 4.7 默认 compress/mode=2 QOA 压缩导致的循环失效或杂音），
## 若无裸文件则走 ResourceLoader，若仍缺失则由 _synth_fallback_wav 在内存中实时合成 16-bit PCM，100% 保证全套音效与 BGM 必响！
static func load_wav_safe(file_name: String, loop: bool = false) -> AudioStream:
	var cache_key := file_name + ("|loop" if loop else "")
	if _wav_cache.has(cache_key):
		return _wav_cache[cache_key]
	var res_path := "res://assets/audio/" + file_name

	# 路径 1：直接读磁盘裸 WAV PCM 数据（不受 .import QOA 压缩影响，100% 还原峰值音量与无缝循环）
	if FileAccess.file_exists(res_path):
		var bytes := FileAccess.get_file_as_bytes(res_path)
		if bytes.size() > 44:
			var data_offset := 44
			for pos in range(12, mini(bytes.size() - 8, 128)):
				if bytes[pos] == 0x64 and bytes[pos + 1] == 0x61 and bytes[pos + 2] == 0x74 and bytes[pos + 3] == 0x61:
					data_offset = pos + 8
					break
			var pcm := bytes.slice(data_offset)
			var wav := AudioStreamWAV.new()
			wav.format = AudioStreamWAV.FORMAT_16_BITS
			wav.mix_rate = 44100
			wav.stereo = false
			wav.data = pcm
			if loop:
				wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
				wav.loop_begin = 0
				wav.loop_end = int(pcm.size() / 2)
			_wav_cache[cache_key] = wav
			return wav

	# 路径 2：导出包 (.pck/.apk) 内通过 ResourceLoader 加载
	if ResourceLoader.exists(res_path):
		var loaded := load(res_path)
		if loaded is AudioStreamWAV:
			var dup := (loaded as AudioStreamWAV).duplicate() as AudioStreamWAV
			if loop:
				dup.loop_mode = AudioStreamWAV.LOOP_FORWARD
				dup.loop_begin = 0
				if dup.format == AudioStreamWAV.FORMAT_16_BITS and dup.data.size() > 0:
					dup.loop_end = int(dup.data.size() / 2)
			_wav_cache[cache_key] = dup
			return dup
		elif loaded is AudioStream:
			_wav_cache[cache_key] = loaded
			return loaded

	# 路径 3：内存级 GDScript PCM 合成兜底（哪怕本地漏拷音频目录也必响！）
	var fallback := _synth_fallback_wav(file_name, loop)
	_wav_cache[cache_key] = fallback
	return fallback


static func _synth_fallback_wav(file_name: String, loop: bool) -> AudioStreamWAV:
	var sr := 22050
	var dur := 2.4 if loop else 0.24
	var n := int(sr * dur)
	var pcm := PackedByteArray()
	pcm.resize(n * 2)
	var base_f := 440.0
	if file_name.begins_with("clap"):
		base_f = 920.0
	elif file_name.begins_with("block_success") or file_name.begins_with("strong_fang"):
		base_f = 880.0
	elif file_name.begins_with("blocked"):
		base_f = 180.0
	elif file_name.begins_with("ui_deny") or file_name.begins_with("xi_shou_fail"):
		base_f = 150.0
	elif file_name.begins_with("zhong_ji") or file_name.begins_with("da_yang"):
		base_f = 130.0
	elif file_name.begins_with("zan") or file_name.begins_with("ji_qi") or file_name.begins_with("hui_fu"):
		base_f = 660.0
	for i in n:
		var t := float(i) / float(sr)
		var env := 1.0 if loop else exp(-t * 10.0)
		var f := base_f * (1.0 + 0.35 * sin(t * 14.0)) if not loop else (110.0 if int(t * 4.0) % 2 == 0 else 165.0)
		var v := sin(TAU * f * t) * 0.65 + sin(TAU * f * 2.0 * t) * 0.25
		var s16 := clampi(int(v * env * 26000.0), -32767, 32767)
		pcm.encode_s16(i * 2, s16)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = sr
	wav.stereo = false
	wav.data = pcm
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = n
	return wav


static func setup_audio_bank(host: Node) -> Dictionary:
	var sfx_players: Array[AudioStreamPlayer] = []
	for _i in 8:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		host.add_child(p)
		sfx_players.append(p)

	var bgm_player := AudioStreamPlayer.new()
	bgm_player.name = "BgmPlayer"
	bgm_player.bus = "Master"
	bgm_player.volume_db = -3.5
	bgm_player.set_meta("active", false)
	bgm_player.finished.connect(func():
		if is_instance_valid(bgm_player) and bool(bgm_player.get_meta("active", false)):
			bgm_player.play())
	host.add_child(bgm_player)

	var streams := {}
	for k in [
		"clap", "ding", "hit", "block", "zan",
		"game_start", "ui_select", "ui_deny",
		"block_success", "blocked_rebound", "seal",
		"bao1", "bao2", "bao3", "strong_fang",
		"xiao_yang", "da_yang", "ji_qi",
		"xi_shou_ok", "xi_shou_fail", "bao_qi",
		"hui_fu", "zhong_ji", "quan_jiang",
	]:
		streams[k] = load_wav_safe(k + ".wav", false)
	streams["bgm_battle"] = load_wav_safe("bgm_battle.wav", true)

	return {
		"players": sfx_players,
		"bgm": bgm_player,
		"streams": streams,
	}


static func play_named_sfx(bank: Dictionary, key: String, vol_db: float = 0.0, pitch: float = 1.0) -> void:
	if bank.is_empty():
		return
	var streams: Dictionary = bank.get("streams", {})
	var stream: AudioStream = streams.get(key, null)
	if stream == null:
		stream = load_wav_safe(key + ".wav", false)
		streams[key] = stream
	if stream == null:
		return
	var players: Array = bank.get("players", [])
	for p: AudioStreamPlayer in players:
		if not p.playing:
			p.stream = stream
			p.volume_db = clampf(vol_db + 2.0, -8.0, 6.0)
			p.pitch_scale = pitch
			p.play()
			return
	if not players.is_empty():
		var p0: AudioStreamPlayer = players[0]
		p0.stream = stream
		p0.volume_db = clampf(vol_db + 2.0, -8.0, 6.0)
		p0.pitch_scale = pitch
		p0.play()


static func start_bgm(bank: Dictionary) -> void:
	if bank.is_empty():
		return
	var bgm: AudioStreamPlayer = bank.get("bgm", null)
	var streams: Dictionary = bank.get("streams", {})
	var st: AudioStream = streams.get("bgm_battle", null)
	if bgm == null or st == null:
		return
	bgm.set_meta("active", true)
	bgm.stream = st
	bgm.pitch_scale = 1.0
	bgm.volume_db = -3.5
	if not bgm.playing:
		bgm.play()


static func stop_bgm(bank: Dictionary) -> void:
	if bank.is_empty():
		return
	var bgm: AudioStreamPlayer = bank.get("bgm", null)
	if bgm != null and is_instance_valid(bgm):
		bgm.set_meta("active", false)
		bgm.stop()


## 随回合推进与残血/赛点状态动态提升 BGM 速度与音量，营造「快上课了 / 决胜白热化」的紧绷感
static func update_bgm_tension(bank: Dictionary, s: BattleState) -> void:
	if bank.is_empty() or s == null:
		return
	var bgm: AudioStreamPlayer = bank.get("bgm", null)
	if bgm == null or not is_instance_valid(bgm):
		return
	var rno := maxi(1, int(s.round))
	var pitch := 1.0 + clampf(float(rno - 1) * 0.009, 0.0, 0.24)
	var vol := -3.5 + clampf(float(rno - 1) * 0.14, 0.0, 3.5)
	if int(s.hp[0]) == 1 or int(s.hp[1]) == 1:
		pitch += 0.06
		vol += 1.0
	if s.score_to_win() > 1 and (int(s.score[0]) >= s.score_to_win() - 2 or int(s.score[1]) >= s.score_to_win() - 2):
		pitch += 0.04
	bgm.pitch_scale = clampf(pitch, 1.0, 1.32)
	bgm.volume_db = clampf(vol, -3.5, 0.8)


# ══════════════════════ 2. 1080P 街机格斗血/气/盾组件（彻底砍掉重复文字） ══════════════════════

static func make_pip_row(max_n: int, filled: int, color: Color, empty_color: Color, pip_size: Vector2 = Vector2(36, 26), gap: int = 8) -> HBoxContainer:
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
	sb.border_color = UiTheme.INK
	sb.set_border_width_all(3)
	sb.border_width_bottom = 5 if on else 3
	var r := int(round(minf(pip_size.x, pip_size.y) * 0.32))
	sb.set_corner_radius_all(r)
	sb.anti_aliasing = true
	return sb


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
			pip_size = Vector2(36, 26)
		var key := "%s|%s|%s|%s" % [
			str(on), color.to_html(), empty_color.to_html(), str(pip_size)]
		if str(holder.get_meta("pip_key", "")) == key:
			continue
		holder.set_meta("pip_key", key)
		holder.add_theme_stylebox_override("panel", _pip_style(on, color, empty_color, pip_size))


static func make_hp_row(max_n: int, filled: int) -> HBoxContainer:
	return make_pip_row(max_n, filled, COLOR_HP, COLOR_HP_EMPTY, Vector2(54, 28), 8)


static func make_qi_row(max_n: int, filled: int) -> HBoxContainer:
	return make_pip_row(max_n, filled, COLOR_QI, COLOR_QI_EMPTY, Vector2(28, 22), 5)


static func make_shield_row(max_n: int, filled: int) -> HBoxContainer:
	return make_pip_row(max_n, filled, COLOR_SHIELD, COLOR_SHIELD_EMPTY, Vector2(36, 26), 6)


static func make_stat_line(title: String, row: HBoxContainer, value_lab: Label) -> HBoxContainer:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 10)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var t := UiTheme.ink_label(title, 22, Color(0.82, 0.88, 0.96), 4, UiTheme.INK)
	t.custom_minimum_size.x = 34
	line.add_child(t)
	if row != null:
		line.add_child(row)
	if value_lab != null:
		value_lab.add_theme_font_size_override("font_size", 22)
		value_lab.add_theme_color_override("font_color", Color.WHITE)
		value_lab.add_theme_constant_override("outline_size", 4)
		value_lab.add_theme_color_override("font_outline_color", UiTheme.INK)
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


# ══════════════════════ 3. MOBA 级中央偏上反馈横幅 + 炉石烧绳条 + 右下微缩 5 轮打字机战报 ══════════════════════

static func make_moba_banner() -> PanelContainer:
	var banner := PanelContainer.new()
	banner.name = "MobaBanner"
	banner.custom_minimum_size = Vector2(920, 112)
	banner.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.039, 0.059, 0.114, 0.94)
	sb.border_color = UiTheme.ACCENT
	sb.set_border_width_all(5)
	sb.border_width_left = 18
	sb.border_width_right = 18
	sb.set_corner_radius_all(26)
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = 10
	sb.shadow_offset = Vector2(0, 6)
	sb.content_margin_left = 28
	sb.content_margin_right = 28
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	banner.add_theme_stylebox_override("panel", sb)

	var bg_tex := TextureRect.new()
	bg_tex.name = "BannerTex"
	bg_tex.texture = UiTheme.load_ui_texture("moba_banner_bg.png")
	bg_tex.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg_tex.stretch_mode = TextureRect.STRETCH_SCALE
	bg_tex.modulate = Color(1, 1, 1, 0.35)
	bg_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.add_child(bg_tex)

	var v := VBoxContainer.new()
	v.name = "Box"
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 4)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.add_child(v)

	var title := UiTheme.ink_label("⚡ 点击「攒气」开始对决 ⚡", 36, Color(1.0, 0.94, 0.65), 8, UiTheme.INK)
	title.name = "BannerTitle"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)

	var sub := UiTheme.ink_label("两拍同步读招 · 预判对手行动", 23, Color(0.86, 0.92, 0.98), 4, UiTheme.INK)
	sub.name = "BannerSub"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)

	return banner


static func show_moba_banner(banner: PanelContainer, title_text: String, sub_text: String, accent: Color = UiTheme.ACCENT, pulse: bool = true) -> void:
	if banner == null or not is_instance_valid(banner):
		return
	var title := banner.find_child("BannerTitle", true, false) as Label
	var sub := banner.find_child("BannerSub", true, false) as Label
	if title != null:
		title.text = title_text
		title.add_theme_color_override("font_color", accent.lightened(0.42))
	if sub != null:
		sub.text = sub_text
		sub.visible = sub_text != ""

	var sb := banner.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	if sb != null:
		sb.border_color = accent
		banner.add_theme_stylebox_override("panel", sb)

	if pulse:
		banner.pivot_offset = banner.size * 0.5
		banner.scale = Vector2(1.28, 1.28)
		var tw := banner.create_tween()
		tw.tween_property(banner, "scale", Vector2(0.96, 0.96), 0.11).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(banner, "scale", Vector2.ONE, 0.09)


## 创建《炉石传说》式烧绳子 + 三段拍点锚点导轨（横贯舞台底部与我方 HUD 分界线，绝不悬空消失）
static func make_burning_rope_bar() -> PanelContainer:
	var bar := PanelContainer.new()
	bar.name = "BurningRopeBar"
	bar.custom_minimum_size = Vector2(1020, 62)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.047, 0.071, 0.133, 0.88)
	sb.border_color = UiTheme.INK
	sb.set_border_width_all(4)
	sb.set_corner_radius_all(20)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	bar.add_theme_stylebox_override("panel", sb)

	var track := Control.new()
	track.name = "RopeTrack"
	track.custom_minimum_size = Vector2(980, 44)
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(track)

	# 底层麻绳暗槽
	var groove := ColorRect.new()
	groove.name = "RopeGroove"
	groove.color = Color(0.14, 0.18, 0.26, 0.95)
	groove.position = Vector2(0, 14)
	groove.size = Vector2(980, 16)
	groove.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.add_child(groove)

	# 燃烧中的导火索本体（从右向左烧短，或随剩余比例收缩）
	var rope_fill := ColorRect.new()
	rope_fill.name = "RopeFill"
	rope_fill.color = Color(0.96, 0.65, 0.12)
	rope_fill.position = Vector2(0, 14)
	rope_fill.size = Vector2(980, 16)
	rope_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.add_child(rope_fill)

	# 三枚拍点锚点徽章（一拍 / 二拍 / 封盘）
	var anchors: Array[PanelContainer] = []
	var anchor_titles := ["一拍", "二拍", "封盘"]
	for i in 3:
		var anc := PanelContainer.new()
		anc.name = "BeatAnchor%d" % i
		anc.custom_minimum_size = Vector2(92, 38)
		anc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var asb := StyleBoxFlat.new()
		asb.bg_color = Color(0.12, 0.16, 0.25, 0.96)
		asb.border_color = UiTheme.INK
		asb.set_border_width_all(3)
		asb.set_corner_radius_all(14)
		asb.content_margin_left = 10
		asb.content_margin_right = 10
		asb.content_margin_top = 2
		asb.content_margin_bottom = 2
		anc.add_theme_stylebox_override("panel", asb)
		var alab := UiTheme.ink_label(anchor_titles[i], 20, Color.WHITE, 4, UiTheme.INK)
		alab.name = "AnchorLab"
		alab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		anc.add_child(alab)
		track.add_child(anc)
		anchors.append(anc)

	# 烧绳火花头（RopeSpark）
	var spark := TextureRect.new()
	spark.name = "RopeSpark"
	spark.texture = UiTheme.load_ui_texture("rope_spark.png")
	spark.custom_minimum_size = Vector2(64, 64)
	spark.size = Vector2(64, 64)
	spark.pivot_offset = Vector2(32, 32)
	spark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	spark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	spark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.add_child(spark)

	bar.set_meta("track", track)
	bar.set_meta("groove", groove)
	bar.set_meta("fill", rope_fill)
	bar.set_meta("anchors", anchors)
	bar.set_meta("spark", spark)
	return bar


static func update_burning_rope_bar(bar: PanelContainer, win: float, left: float, round_no: int, is_open: bool) -> void:
	if bar == null or not is_instance_valid(bar):
		return
	var track := bar.get_meta("track", null) as Control
	var groove := bar.get_meta("groove", null) as ColorRect
	var fill := bar.get_meta("fill", null) as ColorRect
	var anchors: Array = bar.get_meta("anchors", [])
	var spark := bar.get_meta("spark", null) as TextureRect
	if track == null or fill == null or groove == null:
		return

	var w := track.size.x if track.size.x > 100.0 else 980.0
	groove.size = Vector2(w, 16)
	var elapsed := clampf(win - left, 0.0, maxf(win, 0.01))
	var remain_ratio := clampf(left / maxf(win, 0.01), 0.0, 1.0) if is_open else 0.0
	var elapsed_ratio := 1.0 - remain_ratio

	# 炉石烧绳感：导火索从右往左烧短（或燃烧头在 remain_ratio * w 处剧烈闪烁旋转）
	var burn_x := w * remain_ratio
	fill.position = Vector2(0, 14)
	fill.size = Vector2(burn_x, 16)
	if remain_ratio <= 0.25:
		fill.color = UiTheme.DANGER
	elif remain_ratio <= 0.55:
		fill.color = UiTheme.ACCENT
	else:
		fill.color = UiTheme.SHIELD

	var clap2_ratio := clampf(BattleTempo.clap2_at(round_no) / maxf(win, 0.01), 0.25, 0.78)
	var anchor_xs := [10.0, w * (1.0 - clap2_ratio) - 46.0, w - 102.0]
	var anchor_active := [
		is_open and elapsed_ratio >= 0.01,
		is_open and elapsed_ratio >= clap2_ratio,
		not is_open or remain_ratio <= 0.08,
	]
	var anchor_cols := [UiTheme.SHIELD, UiTheme.ACCENT, UiTheme.DANGER]
	for i in mini(3, anchors.size()):
		var anc: PanelContainer = anchors[i]
		anc.position = Vector2(anchor_xs[i], 3)
		var asb := anc.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
		if asb != null:
			asb.bg_color = anchor_cols[i] if anchor_active[i] else Color(0.12, 0.16, 0.25, 0.96)
			anc.add_theme_stylebox_override("panel", asb)

	if spark != null:
		spark.visible = is_open and remain_ratio > 0.01
		spark.position = Vector2(clampf(burn_x - 32.0, -16.0, w - 32.0), -10.0)
		spark.rotation += 0.22
		var pulse_s := 1.25 if remain_ratio < 0.30 else 1.0
		spark.scale = Vector2(pulse_s, pulse_s)


## 创建位于舞台右下角的微缩半透明「5 轮打字机上推战报栏」（一屏最多记 5 次，低调不抢戏）
static func make_battle_ticker() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "BattleTicker"
	panel.custom_minimum_size = Vector2(400, 148)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_END
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.035, 0.051, 0.094, 0.62)
	sb.border_color = Color(0.28, 0.36, 0.48, 0.65)
	sb.set_border_width_all(2)
	sb.border_width_right = 6
	sb.set_corner_radius_all(16)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", sb)

	var box := VBoxContainer.new()
	box.name = "TickerLines"
	box.alignment = BoxContainer.ALIGNMENT_END
	box.add_theme_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(box)

	panel.set_meta("history", [])
	for i in 5:
		var lab := UiTheme.ink_label("", 20, Color(0.92, 0.95, 1.0), 4, UiTheme.INK)
		lab.name = "Line%d" % i
		lab.clip_text = true
		lab.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(lab)
	return panel


static func push_ticker_line(ticker: PanelContainer, line_text: String) -> void:
	if ticker == null or not is_instance_valid(ticker):
		return
	var hist: Array = ticker.get_meta("history", [])
	hist.append(line_text)
	while hist.size() > 5:
		hist.pop_front()
	ticker.set_meta("history", hist)

	var box := ticker.get_node_or_null("TickerLines") as VBoxContainer
	if box == null:
		return
	var n := hist.size()
	var alphas := [0.36, 0.50, 0.64, 0.78, 1.0]
	for i in 5:
		var lab := box.get_child(i) as Label
		if lab == null:
			continue
		var hist_idx := i - (5 - n)
		if hist_idx < 0 or hist_idx >= n:
			lab.text = ""
			lab.visible_ratio = 1.0
		else:
			lab.text = str(hist[hist_idx])
			var is_newest := (hist_idx == n - 1)
			var a: float = alphas[i]
			lab.modulate = Color(1.0, 0.94, 0.60, 1.0) if is_newest else Color(0.84, 0.90, 0.98, a)
			if is_newest:
				lab.visible_ratio = 0.0
				var tw := lab.create_tween()
				tw.tween_property(lab, "visible_ratio", 1.0, 0.28)

	box.position.y = 20.0
	var tw_push := ticker.create_tween()
	tw_push.tween_property(box, "position:y", 0.0, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


static func clear_ticker(ticker: PanelContainer) -> void:
	if ticker == null or not is_instance_valid(ticker):
		return
	ticker.set_meta("history", [])
	var box := ticker.get_node_or_null("TickerLines") as VBoxContainer
	if box == null:
		return
	for i in box.get_child_count():
		var lab := box.get_child(i) as Label
		if lab != null:
			lab.text = ""


## 创建 1080P 三渲二角色立绘中央对撞战卡（内置金罡熊/赤影熊三渲二立绘背景，彻底告别黑底空框）
static func make_duel_card(who_title: String, border_col: Color) -> PanelContainer:
	var is_me := (who_title == "我")
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(368, 224)
	var sb := UiTheme.card_style(Color(0.06, 0.09, 0.16, 0.90), 26, border_col, 5)
	sb.border_width_bottom = 12
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	p.add_theme_stylebox_override("panel", sb)

	var inner := Control.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(inner)

	# 底层：三渲二角色半身战姿立绘（fighter_*_stage.png 交付包缺失时回退同源头像原画）
	var art := TextureRect.new()
	art.name = "FighterArt"
	art.texture = UiTheme.load_ui_texture("fighter_me_stage.png" if is_me else "fighter_opp_stage.png")
	if art.texture == null:
		art.texture = UiTheme.load_ui_texture("avatar_bear_me.png" if is_me else "avatar_bear_opp.png")
	art.set_anchors_preset(Control.PRESET_FULL_RECT)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.modulate = Color(1.0, 1.0, 1.0, 0.86)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(art)

	# 底部深色漫画横幅遮罩（衬托招式图标与大字）
	var bot_shade := PanelContainer.new()
	bot_shade.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bot_shade.offset_top = -92
	bot_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh_sb := StyleBoxFlat.new()
	sh_sb.bg_color = Color(0.03, 0.05, 0.10, 0.84)
	sh_sb.set_corner_radius_all(18)
	sh_sb.content_margin_left = 10
	sh_sb.content_margin_right = 10
	sh_sb.content_margin_top = 4
	sh_sb.content_margin_bottom = 4
	bot_shade.add_theme_stylebox_override("panel", sh_sb)
	inner.add_child(bot_shade)

	# 顶部角色阵营角标
	var head := HBoxContainer.new()
	head.set_anchors_preset(Control.PRESET_TOP_WIDE)
	head.offset_left = 10
	head.offset_right = -10
	head.offset_top = 6
	head.offset_bottom = 40
	head.add_theme_constant_override("separation", 10)
	inner.add_child(head)

	var t := UiTheme.ink_label(who_title, 26, Color(1.0, 0.95, 0.78) if is_me else Color(1.0, 0.78, 0.80), 6, UiTheme.INK)
	head.add_child(t)

	var to_lab := UiTheme.ink_label("超时", 20, UiTheme.DANGER, 5, UiTheme.INK)
	to_lab.name = "TimeoutBadge"
	to_lab.visible = false
	head.add_child(to_lab)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	bot_shade.add_child(row)

	var icon := TextureRect.new()
	icon.name = "DuelIcon"
	icon.custom_minimum_size = Vector2(74, 74)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.visible = false
	row.add_child(icon)

	var act_lab := UiTheme.ink_label("待选", 48, Color.WHITE, 10, UiTheme.INK)
	act_lab.name = "DuelText"
	act_lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(act_lab)

	p.set_meta("duel_icon", icon)
	p.set_meta("duel_text", act_lab)
	p.set_meta("duel_timeout", to_lab)
	p.set_meta("fighter_art", art)
	p.set_meta("base_border", border_col)
	return p


static func update_duel_card(card: PanelContainer, act: int, placeholder_text: String = "待选", is_timeout: bool = false) -> void:
	if card == null or not is_instance_valid(card):
		return
	var icon := card.get_meta("duel_icon", null) as TextureRect
	var lab := card.get_meta("duel_text", null) as Label
	var to_lab := card.get_meta("duel_timeout", null) as Label
	var art := card.get_meta("fighter_art", null) as TextureRect
	var base_border: Color = card.get_meta("base_border", UiTheme.ACCENT)
	if to_lab != null:
		to_lab.visible = is_timeout
	if act >= 0:
		var col := UiTheme.action_color(act)
		var sb := UiTheme.card_style(Color(0.08, 0.11, 0.20, 0.95), 26, col.lightened(0.22), 6)
		sb.border_width_bottom = 14
		sb.content_margin_left = 10
		sb.content_margin_right = 10
		sb.content_margin_top = 10
		sb.content_margin_bottom = 10
		card.add_theme_stylebox_override("panel", sb)
		if art != null:
			art.modulate = Color(1.0, 1.0, 1.0, 1.0)
		if lab != null:
			lab.text = GameRules.action_short_name(act)
			lab.add_theme_color_override("font_color", Color(1.0, 0.96, 0.72))
		if icon != null:
			icon.texture = UiTheme.load_ui_texture(UiTheme.action_icon_name(act))
			icon.visible = icon.texture != null
	else:
		var sb2 := UiTheme.card_style(Color(0.06, 0.09, 0.16, 0.88), 26, base_border, 4)
		sb2.border_width_bottom = 11
		sb2.content_margin_left = 10
		sb2.content_margin_right = 10
		sb2.content_margin_top = 10
		sb2.content_margin_bottom = 10
		card.add_theme_stylebox_override("panel", sb2)
		if art != null:
			art.modulate = Color(0.88, 0.92, 1.0, 0.78)
		if lab != null:
			lab.text = placeholder_text
			lab.add_theme_color_override("font_color", Color(0.86, 0.92, 1.0))
		if icon != null:
			icon.visible = false


## 选招阶段点击任意技能按钮时的即时不规则舞台蓄力动效（零规则圆圈，点下即爆闪电/碎晶/龙卷！）
static func play_skill_select_vfx(fx_host: Control, act: int, me_duel_card: PanelContainer = null) -> void:
	if fx_host == null or not is_instance_valid(fx_host):
		return
	var cel := ensure_cel_canvas(fx_host)
	var col := UiTheme.action_color(act)
	var sz := fx_host.size if fx_host.size.x > 100 else Vector2(1080, 1920)
	var left_pos := Vector2(sz.x * 0.28, minf(sz.y, 1320.0) * 0.50)
	if me_duel_card != null and is_instance_valid(me_duel_card):
		left_pos = me_duel_card.get_global_rect().get_center()
		me_duel_card.pivot_offset = me_duel_card.size * 0.5
		me_duel_card.scale = Vector2(1.14, 1.14)
		var tw := me_duel_card.create_tween()
		tw.tween_property(me_duel_card, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	if cel == null:
		return
	cel.me_aura_col = Color(col.r, col.g, col.b, 0.95)
	var cat := GameRules.action_category(act)
	if cat == "defense":
		cel.add_cel_ring(left_pos, 48.0, 240.0, UiTheme.SHIELD, 12.0, true)
		cel.spawn_shatter_shards(left_pos, 8, UiTheme.SHIELD, 0.75)
	elif act == GameRules.Action.XI_SHOU:
		cel.trigger_vortex(left_pos, UiTheme.SPECIAL, 0.62)
		cel.add_jagged_lightning(left_pos + Vector2(-140, -90), left_pos + Vector2(140, 90), UiTheme.SPECIAL, 10.0, 48.0)
	elif act == GameRules.Action.BAO_QI:
		cel.trigger_screen_distortion(left_pos, 0.032, 0.012, 0.025, 0.0, UiTheme.SPECIAL)
		cel.add_jagged_lightning(left_pos + Vector2(0, 140), left_pos + Vector2(0, -160), UiTheme.ACCENT, 14.0, 56.0)
		cel.spawn_shatter_shards(left_pos, 10, UiTheme.ACCENT, 0.85)
	elif cat == "attack":
		cel.trigger_speed_lines(col, 0.42)
		cel.add_jagged_lightning(left_pos + Vector2(-150, 100), left_pos + Vector2(160, -110), col.lightened(0.20), 12.0, 52.0)
		cel.spawn_shatter_shards(left_pos, 9, col, 0.80)
	else:
		cel.add_jagged_lightning(left_pos + Vector2(-60, 130), left_pos + Vector2(60, -140), col, 11.0, 42.0)
		cel.spawn_shatter_shards(left_pos, 8, col, 0.70)


## 节拍器每拍同步舞台律动（仅让两张角色战卡弹性律动，绝不在画面中央画丑陋的圆圈！）
static func play_beat_pulse(_fx_host: Control, _beat_no: int, me_duel_card: PanelContainer = null, opp_duel_card: PanelContainer = null) -> void:
	for card in [me_duel_card, opp_duel_card]:
		if card != null and is_instance_valid(card):
			card.pivot_offset = card.size * 0.5
			card.scale = Vector2(1.045, 0.965)
			var tw: Tween = card.create_tween()
			tw.tween_property(card, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# ══════════════════════ 4. 1080P 全屏三渲二不规则动态交锋导演系统（一招一式一结果专属动画） ══════════════════════

static func ensure_cel_canvas(fx_host: Control) -> CelStageCanvas:
	if fx_host == null:
		return null
	var c := fx_host.get_node_or_null("CelStageCanvas") as CelStageCanvas
	if c == null:
		c = CelStageCanvas.new()
		c.name = "CelStageCanvas"
		fx_host.add_child(c)
		fx_host.move_child(c, 0)

		# 挂载屏幕空间后处理节点（BackBufferCopy + StagePostFxRect，严格限定在 y=0..1320 舞台区，绝不模糊底部技能栏）
		var bbc := BackBufferCopy.new()
		bbc.name = "StageBackBuffer"
		bbc.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
		fx_host.add_child(bbc)

		var post := ColorRect.new()
		post.name = "StagePostFxRect"
		post.mouse_filter = Control.MOUSE_FILTER_IGNORE
		post.position = Vector2.ZERO
		post.size = Vector2(1080, 1320)
		post.visible = false
		var sh := Shader.new()
		sh.code = POST_FX_SHADER_CODE
		var mat := ShaderMaterial.new()
		mat.shader = sh
		post.material = mat
		fx_host.add_child(post)

		c.post_rect = post
		c.post_mat = mat
	return c


static func play_clash_director(
	fx_host: Control,
	s: BattleState,
	result_dict: Dictionary,
	viewer: int,
	me_card: Control,
	opp_card: Control,
	moba_banner: PanelContainer,
	ticker: PanelContainer,
	audio_bank: Dictionary,
	me_duel_card: PanelContainer = null,
	opp_duel_card: PanelContainer = null
) -> void:
	var me := clampi(viewer, 0, 1)
	var op := 1 - me
	var opening := bool(result_dict.get("opening", false))
	var acts: Array = result_dict.get("actions", [0, 0])
	var timeouts: Array = result_dict.get("timeout", [false, false])
	var my_act: int = int(acts[me]) if acts.size() > me else 0
	var op_act: int = int(acts[op]) if acts.size() > op else 0
	var my_to: bool = bool(timeouts[me]) if timeouts.size() > me else false
	var op_to: bool = bool(timeouts[op]) if timeouts.size() > op else false

	if me_duel_card != null:
		update_duel_card(me_duel_card, my_act, "待选", my_to)
	if opp_duel_card != null:
		update_duel_card(opp_duel_card, op_act, "待选", op_to)

	var cel := ensure_cel_canvas(fx_host)
	var stage_center := Vector2(540, 620)

	if opening:
		play_named_sfx(audio_bank, "game_start", 0.0)
		show_moba_banner(moba_banner, "⚡ 对决开始 · 双方气 +1 ⚡", "第 1 回合开局亮相 · 准备第 2 回合交锋", UiTheme.ACCENT, true)
		push_ticker_line(ticker, "R01 开局亮相 ▸ 双方气+1")
		if cel != null:
			cel.trigger_speed_lines(UiTheme.ACCENT, 0.72)
			cel.add_jagged_lightning(Vector2(180, 620), Vector2(900, 620), UiTheme.ACCENT, 18.0, 85.0)
			cel.spawn_shatter_shards(stage_center, 16, UiTheme.ACCENT, 1.1)
		return

	var hit: Array = result_dict.get("hit", [false, false])
	var blocked: Array = result_dict.get("blocked", [false, false])
	var sealed: Array = result_dict.get("sealed", [false, false])
	var hp_d: Array = result_dict.get("hp_delta", [0, 0])
	var sh_d: Array = result_dict.get("shield_delta", [0, 0])
	var qj: int = int(result_dict.get("quan_jiang", -1))

	var my_hit := bool(hit[me]) if hit.size() > me else false
	var op_hit := bool(hit[op]) if hit.size() > op else false
	var my_blk := bool(blocked[me]) if blocked.size() > me else false
	var op_blk := bool(blocked[op]) if blocked.size() > op else false
	var my_seal := bool(sealed[me]) if sealed.size() > me else false
	var op_seal := bool(sealed[op]) if sealed.size() > op else false

	var my_name := GameRules.action_short_name(my_act)
	var op_name := GameRules.action_short_name(op_act)
	var rno := maxi(1, int(result_dict.get("round", s.round if s != null else 2)))

	_animate_duel_cards_clash(me_duel_card, opp_duel_card, my_blk, op_blk, my_hit, op_hit)

	# 1. 劝降终结演出（全屏黑白反色顿帧 + 径向模糊 + 霸主雷霆轰击）
	if qj >= 0:
		play_named_sfx(audio_bank, "quan_jiang", 2.0)
		var qj_win := (qj == me)
		show_moba_banner(
			moba_banner,
			"👑 劝降触发 · 我方不战而胜！" if qj_win else "👑 对手触发劝降 · 气势压倒！",
			"满气满血对阵 1 血，直接拿下本小局",
			UiTheme.ACCENT if qj_win else UiTheme.DANGER,
			true
		)
		push_ticker_line(ticker, "R%02d 劝降触发 ▸ %s直接获胜" % [rno, "我" if qj_win else "对手"])
		if cel != null:
			cel.trigger_screen_distortion(stage_center, 0.068, 0.032, 0.055, 0.92, UiTheme.ACCENT)
			cel.trigger_speed_lines(UiTheme.ACCENT, 1.0)
			cel.add_screen_crack(stage_center, true, UiTheme.ACCENT)
		if fx_host != null:
			_spawn_cutin_card(fx_host, "vfx_zhongji_ult.png", stage_center, UiTheme.ACCENT, Vector2(760, 440))
			_spawn_screen_crack_tex(fx_host, stage_center, true)
			_spawn_comic_callout(fx_host, stage_center, "👑 劝降秒杀！！", UiTheme.ACCENT, 82)
		return

	# 2. 全舞台技能施法音效与「一招一式一结果」专属不规则特效演出
	var from_me: Control = me_duel_card if me_duel_card != null else me_card
	var from_opp: Control = opp_duel_card if opp_duel_card != null else opp_card
	_play_skill_cast_vfx_and_sfx(
		fx_host, cel, my_act, op_act, from_me, from_opp, me_card, opp_card,
		op_blk, my_blk, op_hit, my_hit, op_seal, my_seal, audio_bank
	)

	# 3. 判定核心博弈结果（MOBA 横幅 + 舞台中央漫画拟声大字 + 右下微缩记招器）
	var banner_title := "⚔️ 【%s】 对决 【%s】" % [my_name, op_name]
	var banner_sub := "双方交锋完成"
	var banner_col := UiTheme.ACCENT
	var ticker_tag := "平分秋色"

	# 3A. 吸收博弈分支
	if my_act == GameRules.Action.XI_SHOU or op_act == GameRules.Action.XI_SHOU:
		if my_act == GameRules.Action.XI_SHOU and op_act == GameRules.Action.XI_SHOU:
			play_named_sfx(audio_bank, "ui_deny", 0.0)
			banner_title = "💨 双吸落空 · 徒耗元气"
			banner_sub = "双方同时使用吸收，各自白花 1 气"
			banner_col = UiTheme.SPECIAL
			ticker_tag = "双吸落空"
			if cel != null:
				cel.trigger_vortex(stage_center, UiTheme.INK_FAINT, 0.72)
		elif my_act == GameRules.Action.XI_SHOU:
			if GameRules.is_gain(op_act):
				play_named_sfx(audio_bank, "xi_shou_ok", 1.8)
				banner_title = "🌀 吸收成功 · 强夺对手【%s】！" % op_name
				banner_sub = "对手本轮增益作废，全数吸入我方黑洞！"
				banner_col = UiTheme.SPECIAL
				ticker_tag = "偷取[%s]" % op_name
				if cel != null:
					var my_c := from_me.get_global_rect().get_center() if from_me != null else Vector2(300, 620)
					cel.trigger_screen_distortion(my_c, 0.048, 0.022, 0.040, 0.0, UiTheme.SPECIAL)
					cel.trigger_speed_lines(UiTheme.SPECIAL, 0.96)
					cel.trigger_vortex(my_c, UiTheme.SPECIAL, 1.25)
				if fx_host != null:
					_spawn_cutin_card(fx_host, "vfx_vortex_cutin.png", stage_center + Vector2(-90, -20), UiTheme.SPECIAL, Vector2(540, 320))
					_siphon_orbs(fx_host, cel, from_opp, from_me, UiTheme.SPECIAL)
					_spawn_comic_callout(fx_host, stage_center + Vector2(0, -110), "🌀 黑洞虹吸！夺【%s】！" % op_name, UiTheme.SPECIAL, 64)
			elif GameRules.is_attack(op_act):
				play_named_sfx(audio_bank, "xi_shou_fail", 1.8)
				banner_title = "💔 吸收反噬 · 被【%s】轰碎黑洞！" % op_name
				banner_sub = "预判失误撞上对手攻击，黑洞坍缩掉 1 血"
				banner_col = UiTheme.DANGER
				ticker_tag = "吸收反噬-1血"
				if cel != null:
					var my_c2 := from_me.get_global_rect().get_center() if from_me != null else Vector2(300, 620)
					cel.trigger_screen_distortion(my_c2, 0.045, 0.025, 0.038, 0.0, UiTheme.DANGER)
					cel.trigger_speed_lines(UiTheme.DANGER, 0.96)
					cel.add_screen_crack(my_c2, false, UiTheme.DANGER)
				if fx_host != null:
					var my_c3 := from_me.get_global_rect().get_center() if from_me != null else Vector2(300, 620)
					_spawn_screen_crack_tex(fx_host, my_c3, false)
					play_hurt(fx_host, me_card)
					_spawn_comic_callout(fx_host, stage_center, "💥 黑洞坍缩反噬 -1血！！", UiTheme.DANGER, 64)
			else:
				play_named_sfx(audio_bank, "ui_deny", 0.0)
				banner_title = "💨 吸收落空 · 对手出【%s】" % op_name
				banner_sub = "对手未产生可偷增益，白花 1 气"
				banner_col = UiTheme.INK_FAINT
				ticker_tag = "吸收落空"
				if fx_host != null:
					_spawn_comic_callout(fx_host, stage_center, "吸收抓空…", UiTheme.INK_FAINT, 52)
		else:
			if GameRules.is_gain(my_act):
				play_named_sfx(audio_bank, "xi_shou_ok", 1.5)
				banner_title = "⚠️ 增益被偷 · 对手吸收了【%s】！" % my_name
				banner_sub = "我方本轮【%s】收益被对手黑洞强行夺走！" % my_name
				banner_col = UiTheme.DANGER
				ticker_tag = "被偷[%s]" % my_name
				if cel != null:
					var op_c := from_opp.get_global_rect().get_center() if from_opp != null else Vector2(780, 620)
					cel.trigger_screen_distortion(op_c, 0.048, 0.022, 0.040, 0.0, UiTheme.SPECIAL)
					cel.trigger_speed_lines(UiTheme.SPECIAL, 0.92)
					cel.trigger_vortex(op_c, UiTheme.SPECIAL, 1.20)
				if fx_host != null:
					_spawn_cutin_card(fx_host, "vfx_vortex_cutin.png", stage_center + Vector2(90, -20), UiTheme.SPECIAL, Vector2(540, 320))
					_siphon_orbs(fx_host, cel, from_me, from_opp, UiTheme.SPECIAL)
					_spawn_comic_callout(fx_host, stage_center, "⚠️【%s】被黑洞吸走！！" % my_name, UiTheme.DANGER, 62)
			elif GameRules.is_attack(my_act):
				play_named_sfx(audio_bank, "xi_shou_fail", 1.8)
				banner_title = "🎯 识破吸收 · 【%s】轰碎对手黑洞！" % my_name
				banner_sub = "对手妄图吸收被我方直接打断，对手 -1 血！"
				banner_col = UiTheme.OK_GREEN
				ticker_tag = "破对手吸收-1血"
				if cel != null:
					var op_c2 := from_opp.get_global_rect().get_center() if from_opp != null else Vector2(780, 620)
					cel.trigger_screen_distortion(op_c2, 0.045, 0.022, 0.038, 0.0, UiTheme.ACCENT)
					cel.trigger_speed_lines(UiTheme.ACCENT, 0.96)
					cel.add_screen_crack(op_c2, false, UiTheme.ACCENT)
				if fx_host != null:
					var op_c3 := from_opp.get_global_rect().get_center() if from_opp != null else Vector2(780, 620)
					_spawn_screen_crack_tex(fx_host, op_c3, false)
					play_hit(fx_host, opp_card)
					_spawn_comic_callout(fx_host, stage_center, "🔥 抓破吸收！对手-1血！", UiTheme.ACCENT, 64)
			else:
				banner_title = "🛡️ 稳健识破 · 对手吸收落空！"
				banner_sub = "对手白耗 1 气，未偷到任何收益"
				banner_col = UiTheme.SHIELD
				ticker_tag = "对手吸收落空"
				if fx_host != null:
					_spawn_comic_callout(fx_host, stage_center, "对手吸收抓空！", UiTheme.SHIELD, 54)

	# 3B. 小羊破防封盾分支（灵羊冲撞 + 局部蛛网裂痕 + 封盾锁链）
	elif my_seal or op_seal:
		play_named_sfx(audio_bank, "seal", 1.8)
		if op_seal:
			banner_title = "🐏 灵羊破盾 · 撞裂对手护盾！"
			banner_sub = "小羊冲撞破防成功！对手下回合禁用「防御」与「爆气」！"
			banner_col = UiTheme.ACCENT
			ticker_tag = "封对手护盾"
			if cel != null:
				var oc := from_opp.get_global_rect().get_center() if from_opp != null else Vector2(780, 620)
				cel.trigger_screen_distortion(oc, 0.036, 0.018, 0.032, 0.0, UiTheme.ACCENT)
				cel.trigger_speed_lines(UiTheme.ACCENT, 0.94)
				cel.add_screen_crack(oc, false, UiTheme.SHIELD)
			if fx_host != null:
				_play_seal_chains(fx_host, opp_card)
				_spawn_comic_callout(fx_host, stage_center, "🐏 灵羊裂盾！封锁护盾！！", UiTheme.ACCENT, 66)
		else:
			banner_title = "⚠️ 护盾被撞裂 · 小心下回合！"
			banner_sub = "我方被小羊冲撞破防，下回合禁用「防御」与「爆气」"
			banner_col = UiTheme.DANGER
			ticker_tag = "我被封盾"
			if cel != null:
				var mc := from_me.get_global_rect().get_center() if from_me != null else Vector2(300, 620)
				cel.trigger_screen_distortion(mc, 0.036, 0.018, 0.032, 0.0, UiTheme.DANGER)
				cel.trigger_speed_lines(UiTheme.DANGER, 0.94)
				cel.add_screen_crack(mc, false, UiTheme.DANGER)
			if fx_host != null:
				_play_seal_chains(fx_host, me_card)
				_spawn_comic_callout(fx_host, stage_center, "⛓️ 护盾碎裂被封 1 回合！！", UiTheme.DANGER, 64)

	# 3C. 格挡成功 vs 被格挡（全屏三渲二非对称强反馈）
	elif my_blk or op_blk:
		if my_blk:
			play_named_sfx(audio_bank, "block_success", 2.0)
			var is_sf := (my_act == GameRules.Action.STRONG_FANG)
			var is_bao_blk := GameRules.is_bao(my_act)
			if is_sf:
				banner_title = "⚡ 强防壁垒 · 完美弹飞【%s】！" % op_name
			elif is_bao_blk:
				banner_title = "🔥 火力格挡 · 【%s】硬接【%s】！" % [my_name, op_name]
			else:
				banner_title = "🛡️ 完美格挡 · 化解【%s】攻势！" % op_name
			banner_sub = "我方成功抵御对手进攻，稳住阵脚！"
			if is_sf and op_act == GameRules.Action.ZHONG_JI:
				banner_sub = "强防硬抗终极技！虽挡下必杀但护盾全碎！"
			banner_col = UiTheme.SHIELD
			ticker_tag = "格挡[%s]" % op_name
			if cel != null:
				var def_pos := from_me.get_global_rect().get_center() if from_me != null else Vector2(300, 620)
				cel.trigger_screen_distortion(def_pos, 0.038, 0.016, 0.036, 0.0, UiTheme.SHIELD)
				cel.trigger_speed_lines(UiTheme.SHIELD, 0.96)
				cel.add_cel_ring(def_pos, 50.0, 420.0, UiTheme.SHIELD, 20.0, true)
				cel.add_jagged_lightning(def_pos + Vector2(-180, -140), def_pos + Vector2(220, 140), UiTheme.ACCENT, 16.0, 64.0)
				if is_sf and op_act == GameRules.Action.ZHONG_JI:
					cel.add_screen_crack(def_pos, true, UiTheme.SHIELD)
			if fx_host != null:
				_spawn_cutin_card(fx_host, "vfx_shield_cutin.png", stage_center + Vector2(-90, -20), UiTheme.SHIELD, Vector2(520, 310))
				_play_block_positive(fx_host, me_card)
				_play_blocked_rebound(fx_host, opp_card)
				_spawn_comic_callout(fx_host, stage_center + Vector2(-80, -110), "⚡ 强防弹反！！" if is_sf else "🛡️ 完美格挡！！", UiTheme.SHIELD, 68)
				_spawn_comic_callout(fx_host, stage_center + Vector2(140, 120), "💥 攻势被弹飞！", Color(1.0, 0.55, 0.20), 46)
		if op_blk:
			play_named_sfx(audio_bank, "blocked_rebound", 2.0)
			var op_sf := (op_act == GameRules.Action.STRONG_FANG)
			banner_title = "💥 攻势受挫 · 【%s】被对手挡下！" % my_name
			banner_sub = ("对手开启【强防】弹飞了你的进攻" if op_sf else "对手提前预判格挡，未能造成伤害")
			banner_col = Color(0.96, 0.52, 0.18)
			ticker_tag = "[%s]被挡" % my_name
			if cel != null:
				var odef_pos := from_opp.get_global_rect().get_center() if from_opp != null else Vector2(780, 620)
				cel.trigger_screen_distortion(odef_pos, 0.032, 0.014, 0.030, 0.0, UiTheme.SHIELD)
				cel.trigger_speed_lines(UiTheme.SHIELD, 0.88)
				cel.add_cel_ring(odef_pos, 50.0, 380.0, UiTheme.SHIELD, 18.0, true)
			if fx_host != null:
				_spawn_cutin_card(fx_host, "vfx_shield_cutin.png", stage_center + Vector2(90, -20), UiTheme.SHIELD, Vector2(520, 310))
				_play_blocked_rebound(fx_host, me_card)
				_play_block_positive(fx_host, opp_card)
				_spawn_comic_callout(fx_host, stage_center + Vector2(-90, 100), "💥 攻击被弹回！！", Color(1.0, 0.50, 0.18), 64)
				_spawn_comic_callout(fx_host, stage_center + Vector2(120, -110), "🛡️ 对手格挡！", UiTheme.SHIELD, 48)

	# 3D. 命中扣血分支（终极 / 大羊 / 小羊 / 三包破防 / 包子）
	elif my_hit or op_hit:
		if op_hit and my_hit:
			play_named_sfx(audio_bank, "zhong_ji", 2.0)
			banner_title = "☄️ 双终极对轰 · 天崩地裂！"
			banner_sub = "双方同时命中终极技，全屏崩裂各掉 2 血！"
			banner_col = UiTheme.SPECIAL
			ticker_tag = "双终极互轰-2"
			if cel != null:
				cel.trigger_screen_distortion(stage_center, 0.072, 0.035, 0.060, 0.95, UiTheme.SPECIAL)
				cel.trigger_speed_lines(UiTheme.SPECIAL, 1.0)
				cel.add_screen_crack(stage_center, true, UiTheme.SPECIAL)
			if fx_host != null:
				_spawn_screen_crack_tex(fx_host, stage_center, true)
				play_hit(fx_host, me_card)
				play_hit(fx_host, opp_card)
				_spawn_comic_callout(fx_host, stage_center, "☄️ 双终极对轰 -2血！！", UiTheme.SPECIAL, 72)
		elif op_hit:
			var dmg: int = absi(int(hp_d[op]))
			play_named_sfx(audio_bank, "zhong_ji" if dmg >= 2 else "hit", 2.0)
			banner_title = ("☄️ 终极必杀 · 轰穿对手 -%d血！" if dmg >= 2 else "🔥 精准命中 · 【%s】打掉对手 1 血！") % (dmg if dmg >= 2 else my_name)
			banner_sub = "我方进攻直接奏效，压制对手血线！"
			banner_col = UiTheme.OK_GREEN if dmg == 1 else UiTheme.SPECIAL
			ticker_tag = "命中对手-%d血" % dmg
			if fx_host != null:
				play_hit(fx_host, opp_card)
				var callout_txt := "☄️ 终极必杀 -2血！！" if dmg >= 2 else (
					"🐏 巨羊踏碎 -1血！！" if my_act == GameRules.Action.DA_YANG else (
						"🐏 灵羊冲撞 -1血！！" if my_act == GameRules.Action.XIAO_YANG else (
							"🔥 三包破防 -1血！！" if my_act == GameRules.Action.BAO3 else "🔥 精准命中 -1血！！"
						)
					)
				)
				_spawn_comic_callout(fx_host, stage_center, callout_txt, UiTheme.SPECIAL if dmg >= 2 else UiTheme.ACCENT, 70)
		else:
			var my_dmg: int = absi(int(hp_d[me]))
			play_named_sfx(audio_bank, "zhong_ji" if my_dmg >= 2 else "hit", 2.0)
			banner_title = "⚠️ 遭受重击 · 被【%s】打掉 %d 血！" % [op_name, my_dmg]
			banner_sub = "注意对手气量与破防技冷却！"
			banner_col = UiTheme.DANGER
			ticker_tag = "我受击-%d血" % my_dmg
			if fx_host != null:
				play_hurt(fx_host, me_card)
				var hurt_txt := "☄️ 遭终极轰击 -2血！！" if my_dmg >= 2 else (
					"🐏 遭巨羊踏碎 -1血！！" if op_act == GameRules.Action.DA_YANG else "💥 遭受重击 -1血！！"
				)
				_spawn_comic_callout(fx_host, stage_center, hurt_txt, UiTheme.DANGER, 68)

	# 3E. 包子互拼削盾 / 招式互抵 / 双方攒气回血
	else:
		var my_sh_d := int(sh_d[me])
		var op_sh_d := int(sh_d[op])
		if op_sh_d < 0 and GameRules.is_bao(my_act):
			play_named_sfx(audio_bank, "hit", 0.8)
			banner_title = "💥 火力压制 · 震碎对手 %d 盾！" % absi(op_sh_d)
			banner_sub = "包子对拼占优，大幅削减对手护盾"
			banner_col = UiTheme.WAVE
			ticker_tag = "碎对手%d盾" % absi(op_sh_d)
			if cel != null:
				var oc4 := from_opp.get_global_rect().get_center() if from_opp != null else Vector2(780, 620)
				cel.trigger_speed_lines(UiTheme.WAVE, 0.82)
				cel.add_screen_crack(oc4, false, UiTheme.WAVE)
			if fx_host != null:
				_spawn_comic_callout(fx_host, stage_center, "💥 轰碎对手 %d 盾！！" % absi(op_sh_d), UiTheme.WAVE, 60)
		elif my_sh_d < 0 and GameRules.is_bao(op_act):
			play_named_sfx(audio_bank, "hit", 0.8)
			banner_title = "⚠️ 对拼劣势 · 我方损失 %d 盾" % absi(my_sh_d)
			banner_sub = "对手包子连数更高，注意补盾"
			banner_col = UiTheme.ACCENT
			ticker_tag = "我损%d盾" % absi(my_sh_d)
			if cel != null:
				var mc4 := from_me.get_global_rect().get_center() if from_me != null else Vector2(300, 620)
				cel.trigger_speed_lines(UiTheme.ACCENT, 0.78)
				cel.add_screen_crack(mc4, false, UiTheme.ACCENT)
			if fx_host != null:
				_spawn_comic_callout(fx_host, stage_center, "⚠️ 护盾受损 %d 盾！" % my_sh_d, UiTheme.ACCENT, 58)
		elif GameRules.is_attack(my_act) and my_act == op_act:
			play_named_sfx(audio_bank, "block", 1.5)
			banner_title = "⚔️ 招式互抵 · 【%s】正面相撞！" % my_name
			banner_sub = "双方同招对撞，在舞台中央炸裂抵消"
			banner_col = UiTheme.ACCENT
			ticker_tag = "同招[%s]互抵" % my_name
			if cel != null:
				cel.trigger_screen_distortion(stage_center, 0.035, 0.015, 0.032, 0.0, UiTheme.ACCENT)
				cel.trigger_speed_lines(UiTheme.ACCENT, 0.88)
				cel.add_jagged_lightning(stage_center + Vector2(-260, -180), stage_center + Vector2(260, 180), UiTheme.ACCENT, 18.0, 75.0)
				cel.add_jagged_lightning(stage_center + Vector2(260, -180), stage_center + Vector2(-260, 180), UiTheme.WAVE, 18.0, 75.0)
				cel.spawn_shatter_shards(stage_center, 18, UiTheme.ACCENT, 1.15)
			if fx_host != null:
				_spawn_comic_callout(fx_host, stage_center, "⚔️ 正面硬拼抵消！！", UiTheme.ACCENT, 62)
		else:
			banner_title = "✨ 蓄势博弈 · 我【%s】 vs 对手【%s】" % [my_name, op_name]
			banner_sub = "双方运转元气，准备下一拍交锋"
			banner_col = UiTheme.GAIN
			ticker_tag = "蓄力运营"

	show_moba_banner(moba_banner, banner_title, banner_sub, banner_col, true)
	push_ticker_line(ticker, "R%02d 我:%s 对手:%s ▸ %s" % [rno, my_name, op_name, ticker_tag])


## 中央两张亮招卡物理对撞与格挡反弹动效
static func _animate_duel_cards_clash(
	me_duel: Control,
	opp_duel: Control,
	my_blk: bool,
	op_blk: bool,
	my_hit: bool,
	op_hit: bool
) -> void:
	if me_duel != null and is_instance_valid(me_duel):
		me_duel.pivot_offset = me_duel.size * 0.5
		var tw_m := me_duel.create_tween()
		if op_blk:
			tw_m.tween_property(me_duel, "scale", Vector2(0.80, 0.80), 0.06)
			tw_m.parallel().tween_property(me_duel, "rotation", -0.22, 0.08)
			tw_m.tween_property(me_duel, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
			tw_m.parallel().tween_property(me_duel, "rotation", 0.0, 0.18)
		elif my_blk:
			tw_m.tween_property(me_duel, "scale", Vector2(1.28, 1.28), 0.10).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw_m.tween_property(me_duel, "scale", Vector2.ONE, 0.18)
		elif my_hit:
			tw_m.tween_property(me_duel, "scale", Vector2(0.76, 0.76), 0.08)
			tw_m.tween_property(me_duel, "scale", Vector2.ONE, 0.18)
		else:
			tw_m.tween_property(me_duel, "scale", Vector2(1.16, 1.16), 0.09).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw_m.tween_property(me_duel, "scale", Vector2.ONE, 0.14)

	if opp_duel != null and is_instance_valid(opp_duel):
		opp_duel.pivot_offset = opp_duel.size * 0.5
		var tw_o := opp_duel.create_tween()
		if my_blk:
			tw_o.tween_property(opp_duel, "scale", Vector2(0.80, 0.80), 0.06)
			tw_o.parallel().tween_property(opp_duel, "rotation", 0.22, 0.08)
			tw_o.tween_property(opp_duel, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
			tw_o.parallel().tween_property(opp_duel, "rotation", 0.0, 0.18)
		elif op_blk:
			tw_o.tween_property(opp_duel, "scale", Vector2(1.28, 1.28), 0.10).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw_o.tween_property(opp_duel, "scale", Vector2.ONE, 0.18)
		elif op_hit:
			tw_o.tween_property(opp_duel, "scale", Vector2(0.76, 0.76), 0.08)
			tw_o.tween_property(opp_duel, "scale", Vector2.ONE, 0.18)
		else:
			tw_o.tween_property(opp_duel, "scale", Vector2(1.16, 1.16), 0.09).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw_o.tween_property(opp_duel, "scale", Vector2.ONE, 0.14)


## 弹出不规则锯齿特写插画切入卡
static func _spawn_cutin_card(host: Control, tex_name: String, pos: Vector2, _col: Color, card_sz: Vector2 = Vector2(520, 310)) -> void:
	if host == null:
		return
	var tex := UiTheme.load_ui_texture(tex_name)
	if tex == null:
		return
	var tr := TextureRect.new()
	tr.texture = tex
	tr.size = card_sz
	tr.pivot_offset = card_sz * 0.5
	tr.global_position = pos - card_sz * 0.5
	tr.scale = Vector2(0.22, 0.22)
	tr.rotation = randf_range(-0.08, 0.08)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(tr)
	var tw := host.create_tween()
	tw.tween_property(tr, "scale", Vector2(1.15, 1.15), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(tr, "scale", Vector2(1.0, 1.0), 0.10)
	tw.tween_interval(0.26)
	tw.tween_property(tr, "modulate:a", 0.0, 0.22)
	tw.parallel().tween_property(tr, "scale", Vector2(1.38, 1.38), 0.22)
	tw.tween_callback(func():
		if is_instance_valid(tr):
			tr.queue_free())


## 弹出透明屏幕裂痕贴图（小羊：580×340 青白蛛网裂痕 vfx_crack_small.png；大羊/终极：960×540 巨型熔岩地壳裂痕 vfx_crack_huge.png）
static func _spawn_screen_crack_tex(host: Control, pos: Vector2, is_huge: bool) -> void:
	if host == null:
		return
	var tex_name := "vfx_crack_huge.png" if is_huge else "vfx_crack_small.png"
	var tex := UiTheme.load_ui_texture(tex_name)
	if tex == null:
		return
	var c_sz := Vector2(980, 560) if is_huge else Vector2(560, 330)
	var tr := TextureRect.new()
	tr.texture = tex
	tr.size = c_sz
	tr.pivot_offset = c_sz * 0.5
	var clamped_pos := Vector2(clampf(pos.x, 220.0, 860.0), clampf(pos.y, 260.0, 980.0))
	if is_huge:
		clamped_pos = Vector2(540.0, clampf(pos.y, 440.0, 760.0))
	tr.global_position = clamped_pos - c_sz * 0.5
	tr.scale = Vector2(0.35, 0.35)
	tr.rotation = randf_range(-0.12, 0.12)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(tr)
	var tw := host.create_tween()
	tw.tween_property(tr, "scale", Vector2(1.12, 1.12), 0.07).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(tr, "scale", Vector2(1.0, 1.0), 0.08)
	tw.tween_interval(0.42 if is_huge else 0.30)
	tw.tween_property(tr, "modulate:a", 0.0, 0.32)
	tw.tween_callback(func():
		if is_instance_valid(tr):
			tr.queue_free())


## 舞台中央三渲二漫画拟声大字
static func _spawn_comic_callout(host: Control, pos: Vector2, text: String, col: Color, fsize: int = 62) -> void:
	if host == null:
		return
	var lab := UiTheme.ink_label(text, fsize, col.lightened(0.25), 14, UiTheme.INK)
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(lab)
	lab.reset_size()
	lab.pivot_offset = lab.size * 0.5
	lab.global_position = pos - lab.size * 0.5
	lab.scale = Vector2(0.2, 0.2)
	lab.rotation = randf_range(-0.08, 0.08)
	var tw := host.create_tween()
	tw.tween_property(lab, "scale", Vector2(1.18, 1.18), 0.13).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(lab, "scale", Vector2(1.0, 1.0), 0.09)
	tw.tween_interval(0.32)
	tw.tween_property(lab, "global_position:y", lab.global_position.y - 60.0, 0.24)
	tw.parallel().tween_property(lab, "modulate:a", 0.0, 0.24)
	tw.tween_callback(func():
		if is_instance_valid(lab):
			lab.queue_free())


static func _play_skill_cast_vfx_and_sfx(
	fx_host: Control,
	cel: CelStageCanvas,
	my_act: int,
	op_act: int,
	me_duel: Control,
	opp_duel: Control,
	me_hud: Control,
	opp_hud: Control,
	op_blk: bool,
	my_blk: bool,
	op_hit: bool,
	my_hit: bool,
	op_seal: bool,
	my_seal: bool,
	audio_bank: Dictionary
) -> void:
	for act in [my_act, op_act]:
		match act:
			GameRules.Action.BAO3:
				play_named_sfx(audio_bank, "bao3", 1.8)
			GameRules.Action.BAO2:
				play_named_sfx(audio_bank, "bao2", 1.2)
			GameRules.Action.BAO1:
				play_named_sfx(audio_bank, "bao1", 0.8)
			GameRules.Action.STRONG_FANG:
				play_named_sfx(audio_bank, "strong_fang", 1.2)
			GameRules.Action.XIAO_YANG:
				play_named_sfx(audio_bank, "xiao_yang", 1.4)
			GameRules.Action.DA_YANG:
				play_named_sfx(audio_bank, "da_yang", 2.0)
			GameRules.Action.JI_QI:
				play_named_sfx(audio_bank, "ji_qi", 1.2)
			GameRules.Action.BAO_QI:
				play_named_sfx(audio_bank, "bao_qi", 1.6)
			GameRules.Action.HUI_FU:
				play_named_sfx(audio_bank, "hui_fu", 1.2)
			GameRules.Action.ZAN:
				play_named_sfx(audio_bank, "zan", 0.4)

	if fx_host == null:
		return

	var my_stolen := (op_act == GameRules.Action.XI_SHOU and GameRules.is_gain(my_act))
	var op_stolen := (my_act == GameRules.Action.XI_SHOU and GameRules.is_gain(op_act))
	var my_succeeded := op_hit or op_seal or (not op_blk and my_act != op_act)
	var op_succeeded := my_hit or my_seal or (not my_blk and op_act != my_act)

	_spawn_single_side_skill_vfx(fx_host, cel, my_act, me_duel, opp_duel, me_hud, opp_hud, true, op_blk, my_stolen, my_succeeded)
	_spawn_single_side_skill_vfx(fx_host, cel, op_act, opp_duel, me_duel, opp_hud, me_hud, false, my_blk, op_stolen, op_succeeded)


static func _spawn_single_side_skill_vfx(
	host: Control,
	cel: CelStageCanvas,
	act: int,
	from_card: Control,
	to_card: Control,
	_from_hud: Control,
	_to_hud: Control,
	friendly: bool,
	was_blocked: bool,
	was_stolen: bool = false,
	succeeded: bool = true
) -> void:
	if host == null or from_card == null or to_card == null:
		return
	var from_pos := from_card.get_global_rect().get_center()
	var to_pos := to_card.get_global_rect().get_center()
	match act:
		GameRules.Action.ZAN:
			if not was_stolen:
				_spawn_qi_tornado_eruption(host, cel, from_pos, UiTheme.ACCENT, 0.72)
		GameRules.Action.JI_QI:
			if not was_stolen:
				_spawn_qi_tornado_eruption(host, cel, from_pos, UiTheme.GAIN, 1.18)
		GameRules.Action.HUI_FU:
			if not was_stolen:
				_spawn_qi_tornado_eruption(host, cel, from_pos, UiTheme.OK_GREEN, 1.25)
		GameRules.Action.BAO_QI:
			_spawn_baoqi_spectacle(host, cel, from_pos, to_pos, was_stolen)
		GameRules.Action.BAO1, GameRules.Action.BAO2, GameRules.Action.BAO3:
			var n := GameRules.bao_count(act)
			for k in n:
				host.get_tree().create_timer(k * 0.065).timeout.connect(func():
					if is_instance_valid(host) and is_instance_valid(from_card) and is_instance_valid(to_card):
						_fire_bao_orb(host, from_card, to_card, friendly, was_blocked, n))
		GameRules.Action.XIAO_YANG:
			_fire_ram_stampede(host, cel, from_card, to_card, false, was_blocked or (not succeeded))
		GameRules.Action.DA_YANG:
			_fire_ram_stampede(host, cel, from_card, to_card, true, was_blocked or (not succeeded))
		GameRules.Action.ZHONG_JI:
			_play_ultimate_beam(host, cel, from_card, to_card, was_blocked)


## 【攒气 / 集气 / 回复】专属演出：不规则翠玉金风龙卷柱升腾 + 疾风闪电撕裂
static func _spawn_qi_tornado_eruption(host: Control, cel: CelStageCanvas, pos: Vector2, col: Color, sc: float = 1.0) -> void:
	if cel != null:
		cel.add_jagged_lightning(pos + Vector2(-80, 140), pos + Vector2(60, -180 * sc), col, 14.0 * sc, 56.0)
		cel.add_jagged_lightning(pos + Vector2(80, 130), pos + Vector2(-60, -170 * sc), col.lightened(0.28), 12.0 * sc, 48.0)
		cel.spawn_shatter_shards(pos, int(10 * sc), col, 0.85 * sc)
	var tex := UiTheme.load_ui_texture("vfx_qi_tornado.png")
	if tex == null:
		return
	var t_sz := Vector2(380, 260) * sc
	var tr := TextureRect.new()
	tr.texture = tex
	tr.size = t_sz
	tr.pivot_offset = Vector2(t_sz.x * 0.5, t_sz.y * 0.85)
	tr.global_position = pos - tr.pivot_offset + Vector2(0, 40)
	tr.scale = Vector2(0.35, 0.25)
	tr.modulate = col.lightened(0.35)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(tr)
	var tw := host.create_tween()
	tw.tween_property(tr, "scale", Vector2(1.18, 1.32), 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(tr, "global_position:y", tr.global_position.y - 48.0, 0.24)
	tw.tween_property(tr, "modulate:a", 0.0, 0.22)
	tw.parallel().tween_property(tr, "scale", Vector2(1.42, 1.55), 0.22)
	tw.tween_callback(func():
		if is_instance_valid(tr):
			tr.queue_free())


## 【爆气】专属演出：成功时触发全舞台径向动态模糊 + 空气扭曲波 + 金紫雷霆特写；被吸收偷走时能量中途崩解被扯入敌方黑洞
static func _spawn_baoqi_spectacle(host: Control, cel: CelStageCanvas, from_pos: Vector2, absorber_pos: Vector2, was_stolen: bool) -> void:
	if was_stolen:
		if cel != null:
			cel.add_jagged_lightning(from_pos, absorber_pos, UiTheme.SPECIAL, 18.0, 90.0)
		return
	if cel != null:
		cel.trigger_screen_distortion(from_pos, 0.062, 0.024, 0.052, 0.0, UiTheme.ACCENT)
		cel.trigger_speed_lines(UiTheme.ACCENT, 0.92)
		for k in 5:
			var ang := TAU * float(k) / 5.0 + randf_range(-0.2, 0.2)
			var tip := from_pos + Vector2(cos(ang), sin(ang)) * 340.0
			cel.add_jagged_lightning(from_pos, tip, UiTheme.ACCENT if k % 2 == 0 else UiTheme.SPECIAL, 16.0, 68.0)
		cel.spawn_shatter_shards(from_pos, 20, UiTheme.ACCENT, 1.25)
	_spawn_cutin_card(host, "vfx_baoqi_burst.png", from_pos, UiTheme.ACCENT, Vector2(560, 330))


## 【单包 / 双包 / 三包】专属演出：真实熔岩火陨连射（带不规则锯齿残影与破防碎裂）
static func _fire_bao_orb(host: Control, from_c: Control, to_c: Control, friendly: bool, bounce: bool, combo_n: int = 1) -> void:
	var cel := ensure_cel_canvas(host)
	var a := from_c.get_global_rect().get_center()
	var b := to_c.get_global_rect().get_center()
	var dir := (b - a).normalized()
	var sc := 0.72 + float(combo_n) * 0.22
	var m_sz := Vector2(340, 188) * sc

	var tr := TextureRect.new()
	tr.texture = UiTheme.load_ui_texture("vfx_bao_meteor.png")
	tr.size = m_sz
	tr.pivot_offset = m_sz * 0.5
	tr.global_position = a - m_sz * 0.5 + Vector2(0, randf_range(-28.0, 28.0) * float(combo_n - 1))
	tr.rotation = dir.angle()
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(tr)

	# 拖尾残影巧思：生成 2 个半透明错位火陨残影跟随冲刺
	for g_idx in 2:
		var ghost := TextureRect.new()
		ghost.texture = tr.texture
		ghost.size = m_sz * (0.86 - float(g_idx) * 0.14)
		ghost.pivot_offset = ghost.size * 0.5
		ghost.global_position = tr.global_position - dir * float((g_idx + 1) * 48)
		ghost.rotation = tr.rotation
		ghost.modulate = Color(1.0, 0.55, 0.15, 0.48 - float(g_idx) * 0.16)
		ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
		host.add_child(ghost)
		var g_tw := host.create_tween()
		g_tw.tween_property(ghost, "global_position", b - ghost.size * 0.5 - dir * float((g_idx + 1) * 32), 0.17)
		g_tw.parallel().tween_property(ghost, "modulate:a", 0.0, 0.17)
		g_tw.tween_callback(func():
			if is_instance_valid(ghost):
				ghost.queue_free())

	var tw := host.create_tween()
	var target_pt := (a + b) * 0.5 if bounce else b
	tw.tween_property(tr, "global_position", target_pt - m_sz * 0.5, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	if bounce:
		var deflect := target_pt + Vector2(-dir.x * 220.0, randf_range(-260.0, -140.0) if friendly else randf_range(140.0, 260.0))
		tw.tween_callback(func():
			if cel != null:
				cel.add_cel_slash(target_pt + Vector2(-90, -110), target_pt + Vector2(90, 110), UiTheme.SHIELD, 20.0)
				cel.spawn_shatter_shards(target_pt, 10, UiTheme.SHIELD, 0.9))
		tw.tween_property(tr, "global_position", deflect - m_sz * 0.5, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(tr, "rotation", tr.rotation + (1.8 if friendly else -1.8), 0.18)
		tw.parallel().tween_property(tr, "scale", Vector2(0.35, 0.35), 0.18)
		tw.parallel().tween_property(tr, "modulate:a", 0.0, 0.18)
	else:
		tw.tween_callback(func():
			if cel != null:
				cel.add_jagged_lightning(b + Vector2(-140 * sc, -100 * sc), b + Vector2(140 * sc, 100 * sc), UiTheme.WAVE, 14.0 * sc, 55.0)
				cel.spawn_shatter_shards(b, 8 + combo_n * 5, UiTheme.WAVE, 0.85 + float(combo_n) * 0.2)
				if combo_n >= 3:
					cel.trigger_screen_distortion(b, 0.042, 0.020, 0.036, 0.0, UiTheme.WAVE)
					cel.add_screen_crack(b, false, UiTheme.WAVE)
					_spawn_screen_crack_tex(host, b, false))
		tw.tween_property(tr, "scale", Vector2(1.65, 1.65), 0.09)
		tw.parallel().tween_property(tr, "modulate:a", 0.0, 0.09)
	tw.tween_callback(func():
		if is_instance_valid(tr):
			tr.queue_free())


## 【小羊 / 大羊】专属真羊冲撞演出：
##   - 小羊（heavy=false）：金焰灵羊 (vfx_xiaoyang_ram.png) 疾驰冲撞，命中炸开【小裂痕 (vfx_crack_small.png)】与玻璃碎晶
##   - 大羊（heavy=true）：赤金巨兽魔羊 (vfx_dayang_ram.png) 裹挟黑红雷霆狂暴冲撞，命中触发全舞台【巨型地壳大裂痕 (vfx_crack_huge.png)】+ 径向模糊与色差撕裂！
##   - 若被强防或三包挡下（bounce=true）：羊冲到舞台中央一头撞在护盾墙上向后翻滚弹飞！
static func _fire_ram_stampede(host: Control, cel: CelStageCanvas, from_c: Control, to_c: Control, heavy: bool, bounce: bool = false) -> void:
	var a := from_c.get_global_rect().get_center()
	var b := to_c.get_global_rect().get_center()
	var dir := (b - a).normalized()
	var tex_name := "vfx_dayang_ram.png" if heavy else "vfx_xiaoyang_ram.png"
	var r_sz := Vector2(600, 355) if heavy else Vector2(460, 272)

	var ram := TextureRect.new()
	ram.texture = UiTheme.load_ui_texture(tex_name)
	ram.size = r_sz
	ram.pivot_offset = r_sz * 0.5
	ram.global_position = a - r_sz * 0.5
	ram.flip_h = (dir.x < 0.0)
	ram.scale = Vector2(1.32, 0.76) # 起跑蓄力拉伸形变（Smear Frame 巧思）
	ram.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(ram)

	# 4 层高速冲锋残影
	var ghost_col := Color(1.0, 0.25, 0.20) if heavy else Color(1.0, 0.72, 0.18)
	for g in 4:
		var gh := TextureRect.new()
		gh.texture = ram.texture
		gh.size = r_sz * (0.92 - float(g) * 0.10)
		gh.pivot_offset = gh.size * 0.5
		gh.global_position = a - gh.size * 0.5 - dir * float((g + 1) * 55)
		gh.flip_h = ram.flip_h
		gh.modulate = Color(ghost_col.r, ghost_col.g, ghost_col.b, 0.52 - float(g) * 0.11)
		gh.mouse_filter = Control.MOUSE_FILTER_IGNORE
		host.add_child(gh)
		var gtw := host.create_tween()
		var g_end := ((a + b) * 0.5 if bounce else b) - gh.size * 0.5 - dir * float((g + 1) * 28)
		gtw.tween_property(gh, "global_position", g_end, 0.18 + float(g) * 0.02).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
		gtw.parallel().tween_property(gh, "modulate:a", 0.0, 0.20 + float(g) * 0.02)
		gtw.tween_callback(func():
			if is_instance_valid(gh):
				gh.queue_free())

	if cel != null:
		cel.add_jagged_lightning(a, (a + b) * 0.5 if bounce else b, UiTheme.WAVE if heavy else UiTheme.ACCENT, 22.0 if heavy else 14.0, 88.0 if heavy else 54.0)

	var tw := host.create_tween()
	var hit_pt := (a + b) * 0.5 if bounce else b
	tw.tween_property(ram, "global_position", hit_pt - r_sz * 0.5, 0.17).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(ram, "scale", Vector2(1.15, 1.15), 0.17)

	if bounce:
		var rebound_pt := a + Vector2(0, -140.0)
		tw.tween_callback(func():
			if cel != null:
				cel.add_cel_ring(hit_pt, 50.0, 380.0, UiTheme.SHIELD, 20.0, true)
				cel.spawn_shatter_shards(hit_pt, 16, UiTheme.SHIELD, 1.1))
		tw.tween_property(ram, "global_position", rebound_pt - r_sz * 0.5, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(ram, "rotation", -0.75 if dir.x > 0 else 0.75, 0.22)
		tw.parallel().tween_property(ram, "scale", Vector2(0.45, 0.45), 0.22)
		tw.parallel().tween_property(ram, "modulate:a", 0.0, 0.22)
	else:
		tw.tween_callback(func():
			# 撞击瞬间：小羊爆局部青白蛛网裂痕 (vfx_crack_small.png)，大羊爆全屏巨型地壳大裂痕 (vfx_crack_huge.png) + 剧烈震屏！
			_spawn_screen_crack_tex(host, b, heavy)
			if cel != null:
				if heavy:
					cel.trigger_screen_distortion(b, 0.056, 0.028, 0.048, 0.35, UiTheme.WAVE)
					cel.trigger_speed_lines(UiTheme.WAVE, 1.0)
					cel.add_screen_crack(Vector2(540, 620), true, UiTheme.WAVE)
					cel.add_jagged_lightning(Vector2(80, 260), Vector2(1000, 980), UiTheme.WAVE, 24.0, 110.0)
					cel.add_jagged_lightning(Vector2(980, 280), Vector2(100, 960), UiTheme.ACCENT, 20.0, 95.0)
				else:
					cel.trigger_screen_distortion(b, 0.034, 0.016, 0.030, 0.0, UiTheme.ACCENT)
					cel.trigger_speed_lines(UiTheme.ACCENT, 0.88)
					cel.add_screen_crack(b, false, UiTheme.SHIELD)
					cel.add_jagged_lightning(b + Vector2(-220, -140), b + Vector2(220, 140), UiTheme.ACCENT, 16.0, 64.0))
		tw.tween_property(ram, "scale", Vector2(1.42, 1.42), 0.09)
		tw.tween_interval(0.10)
		tw.tween_property(ram, "modulate:a", 0.0, 0.16)
		tw.parallel().tween_property(ram, "scale", Vector2(1.68, 1.68), 0.16)
	tw.tween_callback(func():
		if is_instance_valid(ram):
			ram.queue_free())


## 【终极技】全屏毁天灭地演出：
##   1. 0.11s 全舞台黑白反色漫画顿帧 (Impact Frame) + 径向动态模糊 + 色差撕裂
##   2. 760×440 紫金雷神巨熊特写 (vfx_zhongji_ult.png) 镇压全场
##   3. 全屏多道狂暴中点位移紫金雷霆 + 960×540 巨型空间崩裂大裂痕 (vfx_crack_huge.png)
static func _play_ultimate_beam(host: Control, cel: CelStageCanvas, from_c: Control, to_c: Control, was_blocked: bool = false) -> void:
	var a := from_c.get_global_rect().get_center()
	var b := to_c.get_global_rect().get_center()
	var stage_mid := Vector2(540, 600)

	if cel != null:
		cel.trigger_screen_distortion(b if not was_blocked else stage_mid, 0.072, 0.034, 0.060, 0.96, UiTheme.SPECIAL)
		cel.trigger_speed_lines(UiTheme.SPECIAL, 1.0)
		for k in 7:
			var top_pt := Vector2(140.0 + float(k) * 135.0 + randf_range(-40, 40), 60.0)
			var bot_pt := b + Vector2(randf_range(-180, 180), randf_range(-120, 160)) if not was_blocked else stage_mid + Vector2(randf_range(-160, 160), randf_range(-100, 100))
			cel.add_jagged_lightning(top_pt, bot_pt, UiTheme.SPECIAL if k % 2 == 0 else UiTheme.ACCENT, 26.0, 115.0)
		cel.add_jagged_lightning(a, b if not was_blocked else stage_mid, Color(1.0, 0.94, 0.45), 34.0, 95.0)
		cel.add_screen_crack(b if not was_blocked else stage_mid, true, UiTheme.SPECIAL)

	_spawn_cutin_card(host, "vfx_zhongji_ult.png", stage_mid + Vector2(0, -40), UiTheme.SPECIAL, Vector2(760, 440))
	_spawn_screen_crack_tex(host, b if not was_blocked else stage_mid, true)


## 【吸收成功】不规则暗物质闪电触手与碎晶虹吸
static func _siphon_orbs(host: Control, cel: CelStageCanvas, victim_c: Control, absorber_c: Control, col: Color) -> void:
	if host == null or victim_c == null or absorber_c == null:
		return
	var a := victim_c.get_global_rect().get_center()
	var b := absorber_c.get_global_rect().get_center()
	if cel != null:
		for k in 4:
			cel.add_jagged_lightning(a + Vector2(randf_range(-80, 80), randf_range(-60, 60)), b, col, 14.0, 72.0)
	var stage_mid := Vector2(540, 620)
	for i in 12:
		var shard := ColorRect.new()
		shard.size = Vector2(randf_range(22, 42), randf_range(14, 28))
		shard.pivot_offset = shard.size * 0.5
		shard.rotation = randf_range(0.0, TAU)
		shard.color = col.lightened(0.35) if i % 2 == 0 else UiTheme.ACCENT
		shard.mouse_filter = Control.MOUSE_FILTER_IGNORE
		host.add_child(shard)
		var off := Vector2(randf_range(-160, 160), randf_range(-90, 90))
		shard.global_position = a + off
		var tw := host.create_tween()
		tw.tween_interval(i * 0.025)
		tw.tween_property(shard, "global_position", stage_mid + off * 0.25, 0.13).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(shard, "rotation", shard.rotation + 3.2, 0.13)
		tw.tween_property(shard, "global_position", b - shard.size * 0.5, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(shard, "scale", Vector2(0.2, 0.2), 0.16)
		tw.tween_callback(func():
			if is_instance_valid(shard):
				shard.queue_free())


static func _play_seal_chains(host: Control, target: Control) -> void:
	if host == null or target == null:
		return
	_flash_rect(host, target, Color(0.55, 0.15, 0.75, 0.55))
	_shake(target)
	var cel := ensure_cel_canvas(host)
	var c := target.get_global_rect().get_center()
	if cel != null:
		cel.add_jagged_lightning(c + Vector2(-240, -90), c + Vector2(240, 90), Color(0.98, 0.22, 0.48), 18.0, 42.0)
		cel.add_jagged_lightning(c + Vector2(240, -90), c + Vector2(-240, 90), Color(0.98, 0.22, 0.48), 18.0, 42.0)
		cel.spawn_shatter_shards(c, 16, Color(0.98, 0.22, 0.48), 1.0)


static func _play_block_positive(host: Control, target: Control) -> void:
	if host == null or target == null:
		return
	_flash_rect(host, target, Color(0.10, 0.78, 0.98, 0.52))
	_ring(host, target, UiTheme.SHIELD)
	var cel := ensure_cel_canvas(host)
	if cel != null:
		cel.spawn_shatter_shards(target.get_global_rect().get_center(), 14, Color(1.0, 0.88, 0.25), 0.95)


static func _play_blocked_rebound(host: Control, target: Control) -> void:
	if host == null or target == null:
		return
	_flash_rect(host, target, Color(0.45, 0.48, 0.55, 0.50))
	var base := target.position
	var recoil_y := 32.0 if target.global_position.y > 700.0 else -32.0
	var tw := target.create_tween()
	tw.tween_property(target, "position", base + Vector2(0, recoil_y), 0.06).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(target, "position", base + Vector2(-16, 0), 0.05)
	tw.tween_property(target, "position", base + Vector2(16, 0), 0.05)
	tw.tween_property(target, "position", base, 0.08)


static func play_reject_feedback(btn: Control) -> void:
	if btn == null or not is_instance_valid(btn):
		return
	var base_x := btn.position.x
	var tw := btn.create_tween()
	tw.tween_property(btn, "position:x", base_x - 12.0, 0.04)
	tw.tween_property(btn, "position:x", base_x + 12.0, 0.04)
	tw.tween_property(btn, "position:x", base_x - 8.0, 0.04)
	tw.tween_property(btn, "position:x", base_x, 0.04)


# ══════════════════════ 5. 开局聚光灯与通用按钮/命中特效 ══════════════════════

static func show_focus_spotlight(tree: SceneTree, target: Control, caption: String = "点击「攒气」开始对决") -> Control:
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
		target.tree_exiting.connect(_on_spot_target_exit.bind(root.get_instance_id()), CONNECT_ONE_SHOT)
	if not target.item_rect_changed.is_connected(_on_spot_target_rect.bind(root)):
		target.item_rect_changed.connect(_on_spot_target_rect.bind(root))

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
		if r.position.length() < 1.0 and r.size.y < 300 and tries < 12:
			prev = r
			continue
		if r.size.x < 4 or r.size.y < 4:
			continue
		if prev == r:
			_build_spot_geometry(root, target, caption, true)
			return
		prev = r
	if is_instance_valid(root) and is_instance_valid(target):
		_build_spot_geometry(root, target, caption, true)


static func _target_local_rect(root: Control, target: Control) -> Rect2:
	var gr := target.get_global_rect()
	var origin := root.get_global_rect().position
	return Rect2(gr.position - origin, gr.size)


static func _build_spot_geometry(root: Control, target: Control, caption: String, animate: bool = true) -> void:
	if root == null or not is_instance_valid(root) or target == null or not is_instance_valid(target):
		return
	if root.has_meta("loop_tween"):
		var old_loop: Variant = root.get_meta("loop_tween")
		if old_loop is Tween and (old_loop as Tween).is_valid():
			(old_loop as Tween).kill()
		root.remove_meta("loop_tween")
	for c in root.get_children():
		c.queue_free()
	var r := _target_local_rect(root, target)
	if r.size.x < 8 or r.size.y < 8:
		root.get_tree().create_timer(0.03).timeout.connect(func():
			if is_instance_valid(root) and is_instance_valid(target):
				_build_spot_geometry(root, target, caption, animate))
		return
	var hole := r.grow(18)

	var vs := Vector2(1080, 1920)
	if root.get_viewport() != null and root.get_viewport().get_visible_rect().size.x > 0:
		vs = root.get_viewport().get_visible_rect().size
	var vw := maxf(root.size.x, vs.x)
	var vh := maxf(root.size.y, vs.y)

	var dim_color := Color(0.03, 0.05, 0.10, 0.0 if animate else 0.68)
	var d0 := _add_dim(root, Rect2(0, 0, vw, maxf(0, hole.position.y)), dim_color)
	var d1 := _add_dim(root, Rect2(0, hole.end.y, vw, maxf(0, vh - hole.end.y)), dim_color)
	var d2 := _add_dim(root, Rect2(0, hole.position.y, maxf(0, hole.position.x), hole.size.y), dim_color)
	var d3 := _add_dim(root, Rect2(hole.end.x, hole.position.y, maxf(0, vw - hole.end.x), hole.size.y), dim_color)
	if animate:
		var tw_dim := root.create_tween().set_parallel(true)
		for d in [d0, d1, d2, d3]:
			if d != null:
				tw_dim.tween_property(d, "color", Color(0.03, 0.05, 0.10, 0.68), 0.22)

	var border := 6.0
	var gold := Color(1.0, 0.82, 0.18, 0.98)
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

	if animate and target != null and is_instance_valid(target):
		target.pivot_offset = target.size * 0.5
		var tw_b := root.create_tween()
		tw_b.tween_property(target, "scale", Vector2(1.08, 1.08), 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw_b.tween_property(target, "scale", Vector2(1.0, 1.0), 0.18)

	if caption != "":
		var lab := UiTheme.ink_label(caption, 38, Color(1, 0.96, 0.82), 8, UiTheme.INK)
		lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lab.modulate = Color(1, 1, 1, 1 if not animate else 0)
		root.add_child(lab)
		lab.reset_size()
		lab.position = Vector2((vw - lab.size.x) * 0.5, hole.position.y - 96)
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
	if layer == null or not is_instance_valid(layer):
		return
	if layer.has_meta("spot_target"):
		var target := layer.get_meta("spot_target") as Control
		if target != null and is_instance_valid(target):
			var rect_cb := _on_spot_target_rect.bind(layer)
			if target.item_rect_changed.is_connected(rect_cb):
				target.item_rect_changed.disconnect(rect_cb)
			var exit_cb := _on_spot_target_exit.bind(layer.get_instance_id())
			if target.tree_exiting.is_connected(exit_cb):
				target.tree_exiting.disconnect(exit_cb)
	layer.queue_free()


## kind: zan / bo / fang / special / gain / menu / danger / quiet / default
static func press_feedback(btn: BaseButton, kind: String = "default") -> void:
	if btn == null or not is_instance_valid(btn):
		return
	btn.pivot_offset = btn.size * 0.5
	var tw := btn.create_tween()
	match kind:
		"zan":
			_tint_flash(btn, Color(1.0, 0.78, 0.22), 0.18)
			tw.tween_property(btn, "scale", Vector2(1.12, 1.12), 0.07).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.tween_property(btn, "scale", Vector2(1.0, 1.0), 0.13).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		"bo":
			_tint_flash(btn, Color(1.0, 0.45, 0.25), 0.16)
			tw.tween_property(btn, "scale", Vector2(0.88, 0.88), 0.05).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			tw.tween_property(btn, "scale", Vector2(1.10, 1.10), 0.08).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.tween_property(btn, "scale", Vector2.ONE, 0.08)
		"fang":
			_tint_flash(btn, Color(0.25, 0.75, 0.98), 0.18)
			tw.tween_property(btn, "scale", Vector2(1.14, 0.85), 0.06).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tw.tween_property(btn, "scale", Vector2(0.96, 1.06), 0.07)
			tw.tween_property(btn, "scale", Vector2.ONE, 0.10).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		"special":
			_tint_flash(btn, Color(0.75, 0.45, 1.0), 0.20)
			tw.tween_property(btn, "scale", Vector2(1.14, 1.14), 0.07).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.tween_property(btn, "scale", Vector2.ONE, 0.12)
		"gain":
			_tint_flash(btn, Color(0.25, 0.95, 0.65), 0.18)
			tw.tween_property(btn, "scale", Vector2(1.10, 1.10), 0.07)
			tw.tween_property(btn, "scale", Vector2.ONE, 0.11)
		"menu":
			var base := btn.position
			tw.tween_property(btn, "position", base + Vector2(8, 0), 0.06)
			tw.tween_property(btn, "position", base, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			_tint_flash(btn, Color(0.45, 0.45, 0.48), 0.14)
		"danger":
			_tint_flash(btn, Color(0.9, 0.25, 0.22), 0.22)
			var bpos := btn.position
			tw.tween_property(btn, "position", bpos + Vector2(-8, 0), 0.04)
			tw.tween_property(btn, "position", bpos + Vector2(8, 0), 0.05)
			tw.tween_property(btn, "position", bpos, 0.06)
			tw.tween_property(btn, "scale", Vector2(0.96, 0.96), 0.05)
			tw.tween_property(btn, "scale", Vector2.ONE, 0.1)
		"quiet":
			tw.tween_property(btn, "scale", Vector2(0.96, 0.96), 0.06)
			tw.tween_property(btn, "scale", Vector2.ONE, 0.1)
		_:
			tw.tween_property(btn, "scale", Vector2(1.06, 1.06), 0.07).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tw.tween_property(btn, "scale", Vector2.ONE, 0.12)


static func _tint_flash(btn: BaseButton, color: Color, dur: float) -> void:
	if btn == null or not is_instance_valid(btn):
		return
	var tw := btn.create_tween()
	tw.tween_property(btn, "self_modulate", Color(1, 1, 1, 1).lerp(color, 0.35), 0.05)
	tw.tween_property(btn, "self_modulate", Color(1, 1, 1, 1), dur)


static func bind_press(btn: BaseButton, kind: String = "default") -> void:
	if btn == null:
		return
	if btn.pressed.is_connected(_on_pressed_feedback):
		return
	btn.pressed.connect(_on_pressed_feedback.bind(btn, kind))


static func _on_pressed_feedback(btn: BaseButton, kind: String) -> void:
	press_feedback(btn, kind)


static func play_hit(host: Control, target: Control) -> void:
	if host == null or target == null:
		return
	_flash_rect(host, target, COLOR_HIT)
	_shake(target)
	_burst(host, target, COLOR_HIT, 16)


static func play_block(host: Control, target: Control) -> void:
	if host == null or target == null:
		return
	_flash_rect(host, target, COLOR_BLOCK)
	_ring(host, target, COLOR_BLOCK)


static func play_hurt(host: Control, target: Control) -> void:
	if host == null or target == null:
		return
	_flash_rect(host, target, Color(1, 0.25, 0.25, 0.58))
	_shake(target)


static func play_result(host: Control, winner: int, center: Control = null) -> void:
	if host == null:
		return
	var anchor: Control = center if center != null else host
	var color := COLOR_WIN if winner == 0 else (COLOR_LOSE if winner == 1 else COLOR_DRAW)
	var text := "胜利！！" if winner == 0 else ("惜败" if winner == 1 else "平局")
	_pop_label(host, anchor, text, color)
	_confetti(host, 42 if winner == 0 else 18)


static func play_projectile(host: Control, from: Control, to: Control, friendly: bool) -> void:
	if host == null or from == null or to == null:
		return
	_fire_bao_orb(host, from, to, friendly, false, 1)


static func _flash_rect(host: Control, target: Control, color: Color) -> void:
	var flash := ColorRect.new()
	flash.color = color
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.size = target.size
	flash.position = Vector2.ZERO
	target.add_child(flash)
	var tw := host.create_tween()
	tw.tween_property(flash, "color", Color(color.r, color.g, color.b, 0.0), 0.30)
	tw.tween_callback(func():
		if is_instance_valid(flash):
			flash.queue_free())


static func _shake(target: Control) -> void:
	if not is_instance_valid(target):
		return
	var base := target.position
	var tw := target.create_tween()
	for i in 6:
		var off := Vector2(randf_range(-16, 16), randf_range(-10, 10))
		tw.tween_property(target, "position", base + off, 0.032)
	tw.tween_property(target, "position", base, 0.05)


static func _burst(host: Control, target: Control, color: Color, n: int) -> void:
	var c := target.get_global_rect().get_center()
	for i in n:
		var p := ColorRect.new()
		p.color = color
		p.size = Vector2(16, 16)
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		host.add_child(p)
		p.global_position = c - p.size * 0.5
		var ang := TAU * float(i) / float(n)
		var dist := randf_range(90, 220)
		var tw := host.create_tween()
		tw.set_parallel(true)
		tw.tween_property(p, "global_position", c + Vector2(cos(ang), sin(ang)) * dist - p.size * 0.5, 0.28)
		tw.tween_property(p, "modulate", Color(1, 1, 1, 0), 0.28)
		tw.chain().tween_callback(func():
			if is_instance_valid(p):
				p.queue_free())


static func _ring(host: Control, target: Control, color: Color) -> void:
	var cel := ensure_cel_canvas(host)
	var c := target.get_global_rect().get_center()
	if cel != null:
		cel.add_cel_ring(c, 30.0, 260.0, color, 16.0, true)


static func _pop_label(host: Control, anchor: Control, text: String, color: Color) -> void:
	var lab := UiTheme.ink_label(text, 96, color, 16, UiTheme.INK)
	lab.modulate = Color(1, 1, 1, 0)
	host.add_child(lab)
	lab.reset_size()
	var c := anchor.get_global_rect().get_center()
	lab.global_position = c - lab.size * 0.5
	var tw := host.create_tween()
	tw.set_parallel(true)
	tw.tween_property(lab, "modulate", Color(1, 1, 1, 1), 0.12)
	tw.tween_property(lab, "scale", Vector2(1.18, 1.18), 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.chain().tween_interval(0.55)
	tw.chain().tween_property(lab, "modulate", Color(1, 1, 1, 0), 0.28)
	tw.chain().tween_callback(func():
		if is_instance_valid(lab):
			lab.queue_free())


static func _confetti(host: Control, n: int) -> void:
	var colors := [COLOR_HP, COLOR_QI, UiTheme.SHIELD, COLOR_WIN, UiTheme.SPECIAL]
	for i in n:
		var p := ColorRect.new()
		p.color = colors[i % colors.size()]
		p.size = Vector2(randf_range(16, 28), randf_range(20, 38))
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		host.add_child(p)
		var x := randf_range(40, host.size.x - 80) if host.size.x > 200 else randf_range(40, 1000)
		p.position = Vector2(x, -40 - randf_range(0, 160))
		var rot := randf_range(-3.0, 3.0)
		var fall := host.size.y + 120 if host.size.y > 200 else 2000.0
		var tw := host.create_tween()
		tw.set_parallel(true)
		tw.tween_property(p, "position", Vector2(x + randf_range(-90, 90), fall), randf_range(1.0, 1.8)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_property(p, "rotation", rot, 1.4)
		tw.chain().tween_callback(func():
			if is_instance_valid(p):
				p.queue_free())

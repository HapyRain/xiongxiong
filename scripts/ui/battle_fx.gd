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


# ══════════════════════ 0. 全屏三渲二特效画布 (CelStageCanvas) ══════════════════════

class CelStageCanvas extends Control:
	var ambient_time: float = 0.0
	var me_aura_col: Color = Color(0.961, 0.620, 0.043, 0.0)
	var opp_aura_col: Color = Color(0.937, 0.267, 0.267, 0.45)
	var speed_lines_alpha: float = 0.0
	var speed_lines_col: Color = Color(1.0, 0.85, 0.25)
	var impact_flash_alpha: float = 0.0
	var impact_flash_col: Color = Color.WHITE
	var rings: Array = []        # [{pos, r, max_r, col, width, alpha, hex}]
	var slashes: Array = []      # [{a, b, col, width, alpha}]
	var vortex_alpha: float = 0.0
	var vortex_pos: Vector2 = Vector2(540, 620)
	var vortex_rot: float = 0.0
	var vortex_scale: float = 1.0
	var vortex_col: Color = Color(0.62, 0.32, 1.0)

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_FULL_RECT)

	func _process(delta: float) -> void:
		ambient_time += delta
		var dirty := true
		if speed_lines_alpha > 0.005:
			speed_lines_alpha = maxf(0.0, speed_lines_alpha - delta * 2.2)
			dirty = true
		if impact_flash_alpha > 0.005:
			impact_flash_alpha = maxf(0.0, impact_flash_alpha - delta * 6.5)
			dirty = true
		if vortex_alpha > 0.005:
			vortex_rot += delta * 9.5
			vortex_alpha = maxf(0.0, vortex_alpha - delta * 1.65)
			dirty = true
		for i in range(rings.size() - 1, -1, -1):
			var d: Dictionary = rings[i]
			d["r"] = float(d["r"]) + (float(d["max_r"]) - float(d["r"])) * minf(1.0, delta * 9.0)
			d["alpha"] = float(d["alpha"]) - delta * 2.4
			if float(d["alpha"]) <= 0.02:
				rings.remove_at(i)
			else:
				rings[i] = d
			dirty = true
		for i in range(slashes.size() - 1, -1, -1):
			var s: Dictionary = slashes[i]
			s["alpha"] = float(s["alpha"]) - delta * 3.2
			if float(s["alpha"]) <= 0.02:
				slashes.remove_at(i)
			else:
				slashes[i] = s
			dirty = true
		if dirty:
			queue_redraw()

	func trigger_speed_lines(col: Color, intensity: float = 0.92) -> void:
		speed_lines_col = col
		speed_lines_alpha = clampf(intensity, 0.0, 1.0)
		queue_redraw()

	func trigger_impact_flash(col: Color, alpha: float = 0.55) -> void:
		impact_flash_col = col
		impact_flash_alpha = clampf(alpha, 0.0, 0.85)
		queue_redraw()

	func add_cel_ring(pos: Vector2, start_r: float, max_r: float, col: Color, width: float = 14.0, is_hex: bool = false) -> void:
		rings.append({
			"pos": pos, "r": start_r, "max_r": max_r,
			"col": col, "width": width, "alpha": 1.0, "hex": is_hex,
		})
		queue_redraw()

	func add_cel_slash(a: Vector2, b: Vector2, col: Color, width: float = 22.0) -> void:
		slashes.append({"a": a, "b": b, "col": col, "width": width, "alpha": 1.0})
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

		# 0. 常驻 60FPS 三渲二天台法阵呼吸光环、浮空能量火星与角色气场（告别选招期画面死寂）
		var pulse := 0.5 + 0.5 * sin(ambient_time * 3.4)
		var magic_r1 := 215.0 + pulse * 12.0
		var magic_r2 := 152.0 - pulse * 8.0
		draw_arc(center, magic_r1, 0.0, TAU, 48, Color(0.04, 0.06, 0.11, 0.38), 10.0)
		draw_arc(center, magic_r1, 0.0, TAU, 48, Color(0.06, 0.68, 0.96, 0.24 + pulse * 0.12), 4.0)
		draw_arc(center, magic_r2, 0.0, TAU, 36, Color(0.98, 0.68, 0.12, 0.22 + pulse * 0.12), 3.5)
		for k in 8:
			var ang_m := ambient_time * 0.45 + float(k) * TAU / 8.0
			var p_in := center + Vector2(cos(ang_m), sin(ang_m)) * magic_r2
			var p_out := center + Vector2(cos(ang_m), sin(ang_m)) * magic_r1
			draw_line(p_in, p_out, Color(1.0, 0.88, 0.38, 0.22), 3.0)

		# 角色双侧三渲二蓄力气场光晕
		var left_pos := Vector2(sz.x * 0.27, stage_h * 0.50)
		var right_pos := Vector2(sz.x * 0.73, stage_h * 0.50)
		if me_aura_col.a > 0.02:
			var mr := 148.0 + 10.0 * sin(ambient_time * 5.2)
			draw_arc(left_pos, mr, 0.0, TAU, 36, Color(0.04, 0.06, 0.11, me_aura_col.a * 0.65), 12.0)
			draw_arc(left_pos, mr, 0.0, TAU, 36, Color(me_aura_col.r, me_aura_col.g, me_aura_col.b, me_aura_col.a * 0.55), 6.0)
		if opp_aura_col.a > 0.02:
			var orad := 142.0 + 8.0 * cos(ambient_time * 4.6)
			draw_arc(right_pos, orad, 0.0, TAU, 36, Color(0.04, 0.06, 0.11, opp_aura_col.a * 0.50), 10.0)
			draw_arc(right_pos, orad, 0.0, TAU, 36, Color(opp_aura_col.r, opp_aura_col.g, opp_aura_col.b, opp_aura_col.a * 0.40), 5.0)

		# 18 颗上浮三渲二漫画描边能量火种
		for idx in 18:
			var seed_f := float(idx) * 1.73
			var px := fmod(80.0 + float(idx) * 56.0 + sin(ambient_time * 1.4 + seed_f) * 34.0, sz.x - 120.0) + 60.0
			var cycle := fmod(ambient_time * (48.0 + float(idx % 5) * 14.0) + float(idx) * 65.0, 760.0)
			var py := 1040.0 - cycle
			var ea := sin(clampf(cycle / 760.0, 0.0, 1.0) * PI) * 0.65
			var er := 5.0 + float(idx % 3) * 2.2
			var ecol := Color(1.0, 0.78, 0.22, ea) if (idx % 2 == 0) else Color(0.22, 0.82, 1.0, ea)
			draw_circle(Vector2(px, py), er + 2.5, Color(0.04, 0.06, 0.11, ea * 0.85))
			draw_circle(Vector2(px, py), er, ecol)

		# 1. Impact Frame 瞬态高对比闪光（仅覆盖上方特效舞台区 y=0..stage_h，绝不干扰底部技能盘）
		if impact_flash_alpha > 0.01:
			draw_rect(Rect2(0, 0, sz.x, stage_h), Color(impact_flash_col.r, impact_flash_col.g, impact_flash_col.b, impact_flash_alpha * 0.45), true)

		# 2. 全屏三渲二放射漫画速度线（围绕上方舞台四周向中心刺入）
		if speed_lines_alpha > 0.01:
			var n_spikes := 44
			for i in n_spikes:
				var ang := TAU * float(i) / float(n_spikes)
				var outer_r := 760.0
				var inner_r := 280.0 + float((i * 37) % 140)
				var half_w := 0.022 if (i % 2 == 0) else 0.012
				var p0 := center + Vector2(cos(ang - half_w), sin(ang - half_w)) * outer_r
				var p1 := center + Vector2(cos(ang + half_w), sin(ang + half_w)) * outer_r
				var tip := center + Vector2(cos(ang), sin(ang)) * inner_r
				p0.y = clampf(p0.y, 0.0, stage_h)
				p1.y = clampf(p1.y, 0.0, stage_h)
				tip.y = clampf(tip.y, 0.0, stage_h)
				var ink_c := Color(0.04, 0.06, 0.11, speed_lines_alpha * 0.78)
				var fill_c := Color(speed_lines_col.r, speed_lines_col.g, speed_lines_col.b, speed_lines_alpha * 0.85)
				draw_colored_polygon(PackedVector2Array([p0, p1, tip]), ink_c if (i % 3 == 0) else fill_c)

		# 3. 吸收黑洞三渲二螺旋引力场
		if vortex_alpha > 0.01:
			var vr := 220.0 * vortex_scale
			draw_circle(vortex_pos, vr * 0.85, Color(0.04, 0.02, 0.10, vortex_alpha * 0.88))
			draw_arc(vortex_pos, vr * 0.88, 0.0, TAU, 48, Color(0.04, 0.06, 0.11, vortex_alpha), 14.0)
			draw_arc(vortex_pos, vr * 0.82, 0.0, TAU, 48, Color(vortex_col.r, vortex_col.g, vortex_col.b, vortex_alpha), 8.0)
			for arm in 6:
				var base_a := vortex_rot + float(arm) * TAU / 6.0
				var pts := PackedVector2Array()
				for step in 12:
					var t := float(step) / 11.0
					var rr := lerpf(24.0, vr * 1.15, t)
					var aa := base_a + t * 2.4
					pts.append(vortex_pos + Vector2(cos(aa), sin(aa)) * rr)
				draw_polyline(pts, Color(0.04, 0.06, 0.11, vortex_alpha * 0.95), 14.0)
				draw_polyline(pts, Color(vortex_col.lightened(0.35).r, vortex_col.lightened(0.35).g, vortex_col.lightened(0.35).b, vortex_alpha), 7.0)

		# 4. 三渲二粗黑描边扩环与六边圣盾波
		for d: Dictionary in rings:
			var pos: Vector2 = d["pos"]
			var r: float = float(d["r"])
			var a: float = clampf(float(d["alpha"]), 0.0, 1.0)
			var col: Color = d["col"]
			var w: float = float(d["width"])
			var is_hex: bool = bool(d["hex"])
			var ink := Color(0.04, 0.06, 0.11, a * 0.95)
			var fg := Color(col.r, col.g, col.b, a)
			if is_hex:
				var hex_pts := PackedVector2Array()
				for k in 7:
					var ang := float(k) * TAU / 6.0 - PI / 6.0
					hex_pts.append(pos + Vector2(cos(ang), sin(ang)) * r)
				draw_polyline(hex_pts, ink, w + 10.0)
				draw_polyline(hex_pts, fg, w)
			else:
				draw_arc(pos, r, 0.0, TAU, 56, ink, w + 10.0)
				draw_arc(pos, r, 0.0, TAU, 56, fg, w)

		# 5. 三渲二漫画刀光 / 裂痕斩击线
		for s: Dictionary in slashes:
			var pa: Vector2 = s["a"]
			var pb: Vector2 = s["b"]
			var a2: float = clampf(float(s["alpha"]), 0.0, 1.0)
			var col2: Color = s["col"]
			var w2: float = float(s["width"]) * a2
			var dir := (pb - pa).normalized()
			var nrm := Vector2(-dir.y, dir.x) * w2
			var mid := (pa + pb) * 0.5
			var poly := PackedVector2Array([pa, mid + nrm, pb, mid - nrm])
			draw_colored_polygon(poly, Color(0.04, 0.06, 0.11, a2))
			var poly_in := PackedVector2Array([pa, mid + nrm * 0.55, pb, mid - nrm * 0.55])
			draw_colored_polygon(poly_in, Color(col2.r, col2.g, col2.b, a2))


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


## 选招阶段点击任意技能按钮时的即时三渲二舞台蓄力动效（无需等到回合结算，点下即爆气/开盾/旋涡！）
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
		me_duel_card.scale = Vector2(1.12, 1.12)
		var tw := me_duel_card.create_tween()
		tw.tween_property(me_duel_card, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	if cel == null:
		return
	cel.me_aura_col = Color(col.r, col.g, col.b, 0.95)
	var cat := GameRules.action_category(act)
	if cat == "defense":
		cel.add_cel_ring(left_pos, 40.0, 250.0, UiTheme.SHIELD, 14.0, true)
		cel.add_cel_ring(left_pos, 20.0, 180.0, UiTheme.ACCENT, 8.0, true)
	elif act == GameRules.Action.XI_SHOU:
		cel.trigger_vortex(left_pos, UiTheme.SPECIAL, 0.68)
		cel.add_cel_ring(left_pos, 180.0, 40.0, UiTheme.SPECIAL, 10.0, false)
	elif cat == "attack":
		cel.trigger_speed_lines(col, 0.48)
		cel.add_cel_ring(left_pos, 36.0, 260.0, col, 14.0, false)
		cel.add_cel_slash(left_pos + Vector2(-130, 90), left_pos + Vector2(130, -90), col.lightened(0.25), 18.0)
	else:
		cel.add_cel_ring(left_pos, 32.0, 230.0, col, 12.0, false)
		cel.add_cel_ring(left_pos, 60.0, 290.0, Color(1.0, 0.94, 0.55), 8.0, false)


## 节拍器每拍同步舞台脉冲（让两张角色立绘战卡与天台法阵随拍点呼吸律动）
static func play_beat_pulse(fx_host: Control, beat_no: int, me_duel_card: PanelContainer = null, opp_duel_card: PanelContainer = null) -> void:
	if fx_host != null and is_instance_valid(fx_host):
		var cel := ensure_cel_canvas(fx_host)
		if cel != null:
			var sz := fx_host.size if fx_host.size.x > 100 else Vector2(1080, 1920)
			var center := Vector2(sz.x * 0.5, minf(sz.y, 1320.0) * 0.50)
			var b_col := UiTheme.SHIELD if beat_no == 1 else UiTheme.ACCENT
			cel.add_cel_ring(center, 120.0, 320.0, b_col, 8.0, beat_no == 2)
	for card in [me_duel_card, opp_duel_card]:
		if card != null and is_instance_valid(card):
			card.pivot_offset = card.size * 0.5
			card.scale = Vector2(1.04, 1.04)
			var tw: Tween = card.create_tween()
			tw.tween_property(card, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


# ══════════════════════ 4. 1080P 全屏三渲二交锋导演系统（零冗余飘字，全舞台漫画冲击） ══════════════════════

static func ensure_cel_canvas(fx_host: Control) -> CelStageCanvas:
	if fx_host == null:
		return null
	var c := fx_host.get_node_or_null("CelStageCanvas") as CelStageCanvas
	if c == null:
		c = CelStageCanvas.new()
		c.name = "CelStageCanvas"
		fx_host.add_child(c)
		fx_host.move_child(c, 0)
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

	if opening:
		play_named_sfx(audio_bank, "game_start", 0.0)
		show_moba_banner(moba_banner, "⚡ 对决开始 · 双方气 +1 ⚡", "第 1 回合开局亮相 · 准备第 2 回合交锋", UiTheme.ACCENT, true)
		push_ticker_line(ticker, "R01 开局亮相 ▸ 双方气+1")
		if cel != null:
			cel.trigger_speed_lines(UiTheme.ACCENT, 0.72)
			cel.add_cel_ring(Vector2(540, 620), 60.0, 480.0, UiTheme.ACCENT, 16.0, false)
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

	# 1. 劝降终结演出
	if qj >= 0:
		play_named_sfx(audio_bank, "quan_jiang", 1.5)
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
			cel.trigger_impact_flash(UiTheme.ACCENT, 0.75)
			cel.trigger_speed_lines(UiTheme.ACCENT, 1.0)
			cel.add_cel_ring(Vector2(540, 620), 80.0, 620.0, UiTheme.ACCENT, 24.0, true)
		if fx_host != null:
			_spawn_comic_callout(fx_host, Vector2(540, 620), "劝降秒杀！！", UiTheme.ACCENT, 76)
		return

	# 2. 全舞台技能施法音效与三渲二弹道演出
	var from_me: Control = me_duel_card if me_duel_card != null else me_card
	var from_opp: Control = opp_duel_card if opp_duel_card != null else opp_card
	_play_skill_cast_vfx_and_sfx(fx_host, cel, my_act, op_act, from_me, from_opp, me_card, opp_card, op_blk, my_blk, audio_bank)

	# 3. 判定核心博弈结果（只保留正中偏上 MOBA 横幅 + 舞台中心三渲二漫画拟声大字 + 右下微缩记招器，彻底消灭上下重叠的胶囊飘字！）
	var banner_title := "⚔️ 【%s】 对决 【%s】" % [my_name, op_name]
	var banner_sub := "双方交锋完成"
	var banner_col := UiTheme.ACCENT
	var ticker_tag := "平分秋色"
	var stage_center := Vector2(540, 640)

	# 3A. 吸收博弈分支
	if my_act == GameRules.Action.XI_SHOU or op_act == GameRules.Action.XI_SHOU:
		if my_act == GameRules.Action.XI_SHOU and op_act == GameRules.Action.XI_SHOU:
			play_named_sfx(audio_bank, "ui_deny", 0.0)
			banner_title = "💨 双吸落空 · 徒耗元气"
			banner_sub = "双方同时使用吸收，各自白花 1 气"
			banner_col = UiTheme.SPECIAL
			ticker_tag = "双吸落空"
			if cel != null:
				cel.trigger_vortex(stage_center, UiTheme.INK_FAINT, 0.65)
		elif my_act == GameRules.Action.XI_SHOU:
			if GameRules.is_gain(op_act):
				play_named_sfx(audio_bank, "xi_shou_ok", 1.5)
				banner_title = "🌀 吸收成功 · 巧取对手【%s】！" % op_name
				banner_sub = "对手本轮增益作废，全数归入我方囊中！"
				banner_col = UiTheme.SPECIAL
				ticker_tag = "偷取[%s]" % op_name
				if cel != null:
					cel.trigger_impact_flash(UiTheme.SPECIAL, 0.55)
					cel.trigger_speed_lines(UiTheme.SPECIAL, 0.95)
					cel.trigger_vortex(stage_center, UiTheme.SPECIAL, 1.15)
				if fx_host != null:
					_spawn_cutin_card(fx_host, "vfx_vortex_cutin.png", stage_center, UiTheme.SPECIAL)
					_siphon_orbs(fx_host, opp_card, me_card, UiTheme.SPECIAL)
					_spawn_comic_callout(fx_host, stage_center + Vector2(0, -110), "吸收得手！偷【%s】！" % op_name, UiTheme.SPECIAL, 62)
			elif GameRules.is_attack(op_act):
				play_named_sfx(audio_bank, "xi_shou_fail", 1.5)
				banner_title = "💔 吸收反噬 · 被【%s】打断！" % op_name
				banner_sub = "预判失误撞上对手攻击，我方掉 1 血"
				banner_col = UiTheme.DANGER
				ticker_tag = "吸收反噬-1血"
				if cel != null:
					cel.trigger_impact_flash(UiTheme.DANGER, 0.65)
					cel.trigger_speed_lines(UiTheme.DANGER, 0.95)
					cel.trigger_vortex(stage_center, UiTheme.DANGER, 0.85)
					cel.add_cel_slash(stage_center + Vector2(-240, -180), stage_center + Vector2(240, 180), UiTheme.DANGER, 34.0)
					cel.add_cel_slash(stage_center + Vector2(240, -180), stage_center + Vector2(-240, 180), UiTheme.DANGER, 34.0)
				if fx_host != null:
					play_hurt(fx_host, me_card)
					_spawn_comic_callout(fx_host, stage_center, "吸收反噬 -1血！！", UiTheme.DANGER, 64)
			else:
				play_named_sfx(audio_bank, "ui_deny", 0.0)
				banner_title = "💨 吸收落空 · 对手出【%s】" % op_name
				banner_sub = "对手未产生可偷增益，白花 1 气"
				banner_col = UiTheme.INK_FAINT
				ticker_tag = "吸收落空"
				if fx_host != null:
					_spawn_comic_callout(fx_host, stage_center, "吸收落空…", UiTheme.INK_FAINT, 52)
		else:
			if GameRules.is_gain(my_act):
				play_named_sfx(audio_bank, "xi_shou_ok", 1.0)
				banner_title = "⚠️ 增益被偷 · 对手吸收了【%s】！" % my_name
				banner_sub = "我方本轮【%s】收益被对手夺走！" % my_name
				banner_col = UiTheme.DANGER
				ticker_tag = "被偷[%s]" % my_name
				if cel != null:
					cel.trigger_impact_flash(UiTheme.SPECIAL, 0.50)
					cel.trigger_speed_lines(UiTheme.SPECIAL, 0.90)
					cel.trigger_vortex(stage_center, UiTheme.SPECIAL, 1.10)
				if fx_host != null:
					_spawn_cutin_card(fx_host, "vfx_vortex_cutin.png", stage_center, UiTheme.SPECIAL)
					_siphon_orbs(fx_host, me_card, opp_card, UiTheme.SPECIAL)
					_spawn_comic_callout(fx_host, stage_center, "【%s】被吸走！！" % my_name, UiTheme.DANGER, 60)
			elif GameRules.is_attack(my_act):
				play_named_sfx(audio_bank, "xi_shou_fail", 1.5)
				banner_title = "🎯 识破吸收 · 【%s】重创对手！" % my_name
				banner_sub = "对手妄图吸收被我方直接打断，对手 -1 血！"
				banner_col = UiTheme.OK_GREEN
				ticker_tag = "破对手吸收-1血"
				if cel != null:
					cel.trigger_impact_flash(UiTheme.ACCENT, 0.65)
					cel.trigger_speed_lines(UiTheme.ACCENT, 0.95)
					cel.add_cel_slash(stage_center + Vector2(-260, 160), stage_center + Vector2(260, -160), UiTheme.ACCENT, 36.0)
				if fx_host != null:
					play_hit(fx_host, opp_card)
					_spawn_comic_callout(fx_host, stage_center, "抓破吸收！对手-1血！", UiTheme.ACCENT, 64)
			else:
				banner_title = "🛡️ 稳健识破 · 对手吸收落空！"
				banner_sub = "对手白耗 1 气，未偷到任何收益"
				banner_col = UiTheme.SHIELD
				ticker_tag = "对手吸收落空"
				if fx_host != null:
					_spawn_comic_callout(fx_host, stage_center, "对手吸收落空！", UiTheme.SHIELD, 54)

	# 3B. 小羊破防封盾分支
	elif my_seal or op_seal:
		play_named_sfx(audio_bank, "seal", 1.5)
		if op_seal:
			banner_title = "⛓️ 破防封盾 · 锁死对手护盾！"
			banner_sub = "对手下回合禁用「防御」与「爆气」！"
			banner_col = UiTheme.ACCENT
			ticker_tag = "封对手护盾"
			if cel != null:
				cel.trigger_impact_flash(UiTheme.ACCENT, 0.60)
				cel.trigger_speed_lines(UiTheme.ACCENT, 0.92)
				var oc := opp_card.get_global_rect().get_center() if opp_card != null else Vector2(540, 260)
				cel.add_cel_slash(oc + Vector2(-260, -80), oc + Vector2(260, 80), UiTheme.SPECIAL, 24.0)
				cel.add_cel_slash(oc + Vector2(260, -80), oc + Vector2(-260, 80), UiTheme.SPECIAL, 24.0)
			if fx_host != null:
				_play_seal_chains(fx_host, opp_card)
				_spawn_comic_callout(fx_host, stage_center, "破防！封锁护盾！！", UiTheme.ACCENT, 66)
		else:
			banner_title = "⚠️ 护盾被封 · 小心下回合！"
			banner_sub = "我方被小羊破防，下回合禁用「防御」与「爆气」"
			banner_col = UiTheme.DANGER
			ticker_tag = "我被封盾"
			if cel != null:
				cel.trigger_impact_flash(UiTheme.DANGER, 0.60)
				cel.trigger_speed_lines(UiTheme.DANGER, 0.92)
				var mc := me_card.get_global_rect().get_center() if me_card != null else Vector2(540, 1200)
				cel.add_cel_slash(mc + Vector2(-260, -80), mc + Vector2(260, 80), UiTheme.DANGER, 24.0)
				cel.add_cel_slash(mc + Vector2(260, -80), mc + Vector2(-260, 80), UiTheme.DANGER, 24.0)
			if fx_host != null:
				_play_seal_chains(fx_host, me_card)
				_spawn_comic_callout(fx_host, stage_center, "护盾被封 1 回合！！", UiTheme.DANGER, 64)

	# 3C. 格挡成功 vs 被格挡（全屏三渲二非对称强反馈）
	elif my_blk or op_blk:
		if my_blk:
			play_named_sfx(audio_bank, "block_success", 2.0)
			var is_sf := (my_act == GameRules.Action.STRONG_FANG)
			var is_bao_blk := GameRules.is_bao(my_act)
			if is_sf:
				banner_title = "⚡ 强防壁垒 · 完美弹反【%s】！" % op_name
			elif is_bao_blk:
				banner_title = "🔥 火力格挡 · 【%s】硬接【%s】！" % [my_name, op_name]
			else:
				banner_title = "🛡️ 完美格挡 · 化解【%s】攻势！" % op_name
			banner_sub = "我方成功抵御对手进攻，稳住阵脚！"
			if is_sf and op_act == GameRules.Action.ZHONG_JI:
				banner_sub = "强防挡下终极技，但我方护盾已全部震碎！"
			banner_col = UiTheme.SHIELD
			ticker_tag = "格挡[%s]" % op_name
			if cel != null:
				cel.trigger_impact_flash(UiTheme.SHIELD, 0.65)
				cel.trigger_speed_lines(UiTheme.SHIELD, 0.96)
				cel.add_cel_ring(stage_center + Vector2(-120, 40), 40.0, 380.0, UiTheme.SHIELD, 22.0, true)
				cel.add_cel_ring(stage_center + Vector2(-120, 40), 80.0, 480.0, UiTheme.ACCENT, 14.0, true)
			if fx_host != null:
				_spawn_cutin_card(fx_host, "vfx_shield_cutin.png", stage_center + Vector2(-90, -20), UiTheme.SHIELD)
				_play_block_positive(fx_host, me_card)
				_play_blocked_rebound(fx_host, opp_card)
				_spawn_comic_callout(fx_host, stage_center + Vector2(-80, -110), "⚡ 强防弹反！！" if is_sf else "🛡️ 完美格挡！！", UiTheme.SHIELD, 68)
				_spawn_comic_callout(fx_host, stage_center + Vector2(140, 120), "💥 攻势被挡！", Color(1.0, 0.55, 0.20), 46)
		if op_blk:
			play_named_sfx(audio_bank, "blocked_rebound", 2.0)
			var op_sf := (op_act == GameRules.Action.STRONG_FANG)
			banner_title = "💥 攻势受挫 · 【%s】被对手挡下！" % my_name
			banner_sub = ("对手开启【强防】弹开了你的进攻" if op_sf else "对手提前预判格挡，未能造成伤害")
			banner_col = Color(0.96, 0.52, 0.18)
			ticker_tag = "[%s]被挡" % my_name
			if cel != null:
				cel.trigger_impact_flash(Color(0.95, 0.45, 0.15), 0.55)
				cel.trigger_speed_lines(UiTheme.SHIELD, 0.88)
				cel.add_cel_ring(stage_center + Vector2(120, -40), 40.0, 360.0, UiTheme.SHIELD, 20.0, true)
			if fx_host != null:
				_spawn_cutin_card(fx_host, "vfx_shield_cutin.png", stage_center + Vector2(90, -20), UiTheme.SHIELD)
				_play_blocked_rebound(fx_host, me_card)
				_play_block_positive(fx_host, opp_card)
				_spawn_comic_callout(fx_host, stage_center + Vector2(-90, 100), "💥 攻击被挡！！", Color(1.0, 0.50, 0.18), 64)
				_spawn_comic_callout(fx_host, stage_center + Vector2(120, -110), "🛡️ 对手格挡！", UiTheme.SHIELD, 48)

	# 3D. 命中扣血分支（终极 / 大羊 / 包子 / 裸防受击）
	elif my_hit or op_hit:
		if op_hit and my_hit:
			play_named_sfx(audio_bank, "zhong_ji", 2.0)
			banner_title = "☄️ 双终极对轰 · 两败俱伤！"
			banner_sub = "双方同时命中终极技，各掉 2 血！"
			banner_col = UiTheme.SPECIAL
			ticker_tag = "双终极互轰-2"
			if cel != null:
				cel.trigger_impact_flash(UiTheme.SPECIAL, 0.80)
				cel.trigger_speed_lines(UiTheme.SPECIAL, 1.0)
				cel.add_cel_ring(stage_center, 60.0, 640.0, UiTheme.SPECIAL, 28.0, false)
			if fx_host != null:
				play_hit(fx_host, me_card)
				play_hit(fx_host, opp_card)
				_spawn_comic_callout(fx_host, stage_center, "双终极对轰 -2血！！", UiTheme.SPECIAL, 68)
		elif op_hit:
			var dmg: int = absi(int(hp_d[op]))
			play_named_sfx(audio_bank, "zhong_ji" if dmg >= 2 else "hit", 2.0)
			banner_title = ("☄️ 终极必杀 · 轰穿对手 -%d血！" if dmg >= 2 else "🔥 精准命中 · 【%s】打掉对手 1 血！") % (dmg if dmg >= 2 else my_name)
			banner_sub = "我方进攻直接奏效，压制对手血线！"
			banner_col = UiTheme.OK_GREEN if dmg == 1 else UiTheme.SPECIAL
			ticker_tag = "命中对手-%d血" % dmg
			if cel != null:
				cel.trigger_impact_flash(UiTheme.SPECIAL if dmg >= 2 else UiTheme.WAVE, 0.72)
				cel.trigger_speed_lines(UiTheme.SPECIAL if dmg >= 2 else UiTheme.ACCENT, 0.98)
				cel.add_cel_slash(stage_center + Vector2(-340, 220), stage_center + Vector2(340, -220), UiTheme.ACCENT, 42.0)
				cel.add_cel_ring(stage_center, 50.0, 520.0, UiTheme.WAVE, 22.0, false)
			if fx_host != null:
				play_hit(fx_host, opp_card)
				_spawn_comic_callout(fx_host, stage_center, ("雷霆必杀 -%d血！！" % dmg) if dmg >= 2 else "破防命中 -1血！！", UiTheme.ACCENT, 68)
		else:
			var my_dmg: int = absi(int(hp_d[me]))
			play_named_sfx(audio_bank, "zhong_ji" if my_dmg >= 2 else "hit", 2.0)
			banner_title = "⚠️ 遭受重击 · 被【%s】打掉 %d 血！" % [op_name, my_dmg]
			banner_sub = "注意对手气量与破防技冷却！"
			banner_col = UiTheme.DANGER
			ticker_tag = "我受击-%d血" % my_dmg
			if cel != null:
				cel.trigger_impact_flash(UiTheme.DANGER, 0.72)
				cel.trigger_speed_lines(UiTheme.DANGER, 0.96)
				cel.add_cel_slash(stage_center + Vector2(-320, -200), stage_center + Vector2(320, 200), UiTheme.DANGER, 40.0)
			if fx_host != null:
				play_hurt(fx_host, me_card)
				_spawn_comic_callout(fx_host, stage_center, "遭受重击 -%d血！！" % my_dmg, UiTheme.DANGER, 66)

	# 3E. 包子互拼削盾 / 招式互抵 / 双方攒气回血
	else:
		var my_sh_d := int(sh_d[me])
		var op_sh_d := int(sh_d[op])
		if op_sh_d < 0 and GameRules.is_bao(my_act):
			play_named_sfx(audio_bank, "hit", 0.5)
			banner_title = "💥 火力压制 · 震碎对手 %d 盾！" % absi(op_sh_d)
			banner_sub = "包子对拼占优，大幅削减对手护盾"
			banner_col = UiTheme.WAVE
			ticker_tag = "碎对手%d盾" % absi(op_sh_d)
			if cel != null:
				cel.trigger_speed_lines(UiTheme.WAVE, 0.80)
				cel.add_cel_ring(stage_center, 40.0, 420.0, UiTheme.WAVE, 18.0, true)
			if fx_host != null:
				_spawn_comic_callout(fx_host, stage_center, "轰碎对手 %d 盾！！" % absi(op_sh_d), UiTheme.WAVE, 58)
		elif my_sh_d < 0 and GameRules.is_bao(op_act):
			play_named_sfx(audio_bank, "hit", 0.5)
			banner_title = "⚠️ 对拼劣势 · 我方损失 %d 盾" % absi(my_sh_d)
			banner_sub = "对手包子连数更高，注意补盾"
			banner_col = UiTheme.ACCENT
			ticker_tag = "我损%d盾" % absi(my_sh_d)
			if cel != null:
				cel.trigger_speed_lines(UiTheme.ACCENT, 0.75)
			if fx_host != null:
				_spawn_comic_callout(fx_host, stage_center, "护盾受损 %d 盾！" % my_sh_d, UiTheme.ACCENT, 56)
		elif GameRules.is_attack(my_act) and my_act == op_act:
			play_named_sfx(audio_bank, "block", 1.5)
			banner_title = "⚔️ 招式互抵 · 【%s】正面相撞！" % my_name
			banner_sub = "双方同招对撞，攻势相互抵消"
			banner_col = UiTheme.ACCENT
			ticker_tag = "同招[%s]互抵" % my_name
			if cel != null:
				cel.trigger_impact_flash(UiTheme.ACCENT, 0.50)
				cel.trigger_speed_lines(UiTheme.ACCENT, 0.85)
				cel.add_cel_ring(stage_center, 40.0, 460.0, UiTheme.ACCENT, 20.0, false)
			if fx_host != null:
				_spawn_comic_callout(fx_host, stage_center, "⚔️ 正面拼招抵消！！", UiTheme.ACCENT, 58)
		else:
			banner_title = "✨ 蓄势运营 · 我【%s】 vs 对手【%s】" % [my_name, op_name]
			banner_sub = "双方调息蓄力，准备下一拍博弈"
			banner_col = UiTheme.GAIN
			ticker_tag = "蓄力运营"
			if cel != null:
				cel.add_cel_ring(stage_center, 50.0, 360.0, UiTheme.GAIN, 12.0, false)

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
			tw_m.tween_property(me_duel, "scale", Vector2(0.82, 0.82), 0.06)
			tw_m.parallel().tween_property(me_duel, "rotation", -0.20, 0.08)
			tw_m.tween_property(me_duel, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
			tw_m.parallel().tween_property(me_duel, "rotation", 0.0, 0.18)
		elif my_blk:
			tw_m.tween_property(me_duel, "scale", Vector2(1.26, 1.26), 0.10).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw_m.tween_property(me_duel, "scale", Vector2.ONE, 0.18)
		elif my_hit:
			tw_m.tween_property(me_duel, "scale", Vector2(0.80, 0.80), 0.08)
			tw_m.tween_property(me_duel, "scale", Vector2.ONE, 0.16)
		else:
			tw_m.tween_property(me_duel, "scale", Vector2(1.16, 1.16), 0.09).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw_m.tween_property(me_duel, "scale", Vector2.ONE, 0.14)

	if opp_duel != null and is_instance_valid(opp_duel):
		opp_duel.pivot_offset = opp_duel.size * 0.5
		var tw_o := opp_duel.create_tween()
		if my_blk:
			tw_o.tween_property(opp_duel, "scale", Vector2(0.82, 0.82), 0.06)
			tw_o.parallel().tween_property(opp_duel, "rotation", 0.20, 0.08)
			tw_o.tween_property(opp_duel, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
			tw_o.parallel().tween_property(opp_duel, "rotation", 0.0, 0.18)
		elif op_blk:
			tw_o.tween_property(opp_duel, "scale", Vector2(1.26, 1.26), 0.10).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw_o.tween_property(opp_duel, "scale", Vector2.ONE, 0.18)
		elif op_hit:
			tw_o.tween_property(opp_duel, "scale", Vector2(0.80, 0.80), 0.08)
			tw_o.tween_property(opp_duel, "scale", Vector2.ONE, 0.16)
		else:
			tw_o.tween_property(opp_duel, "scale", Vector2(1.16, 1.16), 0.09).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw_o.tween_property(opp_duel, "scale", Vector2.ONE, 0.14)


## 弹出三渲二特写插画切入卡（格挡六边圣盾特写 / 吸收黑洞特写）
static func _spawn_cutin_card(host: Control, tex_name: String, pos: Vector2, col: Color) -> void:
	if host == null:
		return
	var tex := UiTheme.load_ui_texture(tex_name)
	if tex == null:
		return
	var tr := TextureRect.new()
	tr.texture = tex
	tr.size = Vector2(420, 256)
	tr.pivot_offset = Vector2(210, 128)
	tr.global_position = pos - Vector2(210, 128)
	tr.scale = Vector2(0.25, 0.25)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(tr)
	var tw := host.create_tween()
	tw.tween_property(tr, "scale", Vector2(1.12, 1.12), 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(tr, "scale", Vector2(1.0, 1.0), 0.12)
	tw.tween_interval(0.22)
	tw.tween_property(tr, "modulate:a", 0.0, 0.22)
	tw.parallel().tween_property(tr, "scale", Vector2(1.35, 1.35), 0.22)
	tw.tween_callback(func():
		if is_instance_valid(tr):
			tr.queue_free())


## 舞台中央三渲二漫画拟声大字（粗黑描边 + 弹性冲击缩放，替代旧版琐碎黑胶囊）
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
	audio_bank: Dictionary
) -> void:
	for act in [my_act, op_act]:
		match act:
			GameRules.Action.BAO3:
				play_named_sfx(audio_bank, "bao3", 1.5)
			GameRules.Action.BAO2:
				play_named_sfx(audio_bank, "bao2", 1.0)
			GameRules.Action.BAO1:
				play_named_sfx(audio_bank, "bao1", 0.5)
			GameRules.Action.STRONG_FANG:
				play_named_sfx(audio_bank, "strong_fang", 1.0)
			GameRules.Action.XIAO_YANG:
				play_named_sfx(audio_bank, "xiao_yang", 1.0)
			GameRules.Action.DA_YANG:
				play_named_sfx(audio_bank, "da_yang", 1.5)
			GameRules.Action.JI_QI:
				play_named_sfx(audio_bank, "ji_qi", 1.0)
			GameRules.Action.BAO_QI:
				play_named_sfx(audio_bank, "bao_qi", 1.0)
			GameRules.Action.HUI_FU:
				play_named_sfx(audio_bank, "hui_fu", 1.0)
			GameRules.Action.ZAN:
				play_named_sfx(audio_bank, "zan", 0.0)

	if fx_host == null:
		return

	var my_stolen := (op_act == GameRules.Action.XI_SHOU and GameRules.is_gain(my_act))
	var op_stolen := (my_act == GameRules.Action.XI_SHOU and GameRules.is_gain(op_act))
	_spawn_single_side_skill_vfx(fx_host, cel, my_act, me_duel, opp_duel, me_hud, opp_hud, true, op_blk, my_stolen)
	_spawn_single_side_skill_vfx(fx_host, cel, op_act, opp_duel, me_duel, opp_hud, me_hud, false, my_blk, op_stolen)


static func _spawn_single_side_skill_vfx(
	host: Control,
	cel: CelStageCanvas,
	act: int,
	from_card: Control,
	to_card: Control,
	from_hud: Control,
	to_hud: Control,
	friendly: bool,
	was_blocked: bool,
	was_stolen: bool = false
) -> void:
	if host == null or from_card == null or to_card == null:
		return
	var gain_hud: Control = to_hud if was_stolen else from_hud
	var gain_center := gain_hud.get_global_rect().get_center() if gain_hud != null else from_card.get_global_rect().get_center()
	match act:
		GameRules.Action.ZAN:
			if cel != null:
				cel.add_cel_ring(gain_center, 30.0, 220.0, UiTheme.ACCENT, 12.0, false)
		GameRules.Action.JI_QI:
			if cel != null:
				cel.add_cel_ring(gain_center, 40.0, 320.0, UiTheme.GAIN, 16.0, false)
				cel.trigger_speed_lines(UiTheme.GAIN, 0.55)
		GameRules.Action.HUI_FU:
			if cel != null:
				cel.add_cel_ring(gain_center, 40.0, 340.0, UiTheme.OK_GREEN, 18.0, false)
		GameRules.Action.BAO_QI:
			if cel != null:
				cel.add_cel_ring(gain_center, 40.0, 360.0, UiTheme.SPECIAL, 20.0, true)
		GameRules.Action.BAO1, GameRules.Action.BAO2, GameRules.Action.BAO3:
			var n := GameRules.bao_count(act)
			for k in n:
				host.get_tree().create_timer(k * 0.065).timeout.connect(func():
					if is_instance_valid(host) and is_instance_valid(from_card) and is_instance_valid(to_card):
						_fire_bao_orb(host, from_card, to_card, friendly, was_blocked, n))
		GameRules.Action.XIAO_YANG:
			_fire_ram_wave(host, from_card, to_card, Color(1.0, 0.55, 0.15), false, was_blocked)
		GameRules.Action.DA_YANG:
			_fire_ram_wave(host, from_card, to_card, UiTheme.WAVE, true, was_blocked)
		GameRules.Action.ZHONG_JI:
			_play_ultimate_beam(host, from_card, to_card, was_blocked)


static func _fire_bao_orb(host: Control, from_c: Control, to_c: Control, friendly: bool, bounce: bool, combo_n: int = 1) -> void:
	var d_sz := 72 + combo_n * 22
	var orb := Panel.new()
	orb.size = Vector2(d_sz, d_sz)
	orb.pivot_offset = orb.size * 0.5
	orb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var col := UiTheme.WAVE if friendly else Color(1.0, 0.42, 0.15)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1.0, 0.92, 0.35)
	sb.border_color = UiTheme.INK
	sb.set_border_width_all(8)
	sb.set_corner_radius_all(d_sz / 2)
	sb.shadow_color = col
	sb.shadow_size = 18
	orb.add_theme_stylebox_override("panel", sb)
	host.add_child(orb)

	var a := from_c.get_global_rect().get_center()
	var b := to_c.get_global_rect().get_center()
	orb.global_position = a - orb.size * 0.5
	var tw := host.create_tween()
	tw.tween_property(orb, "global_position", b - orb.size * 0.5, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	if bounce:
		var deflect := b + Vector2(randf_range(-240, 240), 140 if friendly else -140)
		tw.tween_property(orb, "global_position", deflect, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(orb, "scale", Vector2(0.4, 0.4), 0.16)
		tw.parallel().tween_property(orb, "modulate", Color(0.7, 0.7, 0.7, 0.0), 0.16)
	else:
		tw.tween_property(orb, "scale", Vector2(2.2, 2.2), 0.08)
		tw.parallel().tween_property(orb, "modulate", Color(1, 1, 1, 0), 0.08)
	tw.tween_callback(func():
		if is_instance_valid(orb):
			orb.queue_free())


static func _fire_ram_wave(host: Control, from_c: Control, to_c: Control, col: Color, heavy: bool, bounce: bool = false) -> void:
	var wave := Panel.new()
	wave.size = Vector2(260 if heavy else 190, 68 if heavy else 48)
	wave.pivot_offset = wave.size * 0.5
	wave.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.border_color = UiTheme.INK
	sb.set_border_width_all(7)
	sb.set_corner_radius_all(24)
	wave.add_theme_stylebox_override("panel", sb)
	host.add_child(wave)

	var a := from_c.get_global_rect().get_center()
	var b := to_c.get_global_rect().get_center()
	wave.global_position = a - wave.size * 0.5
	var tw := host.create_tween()
	tw.tween_property(wave, "global_position", b - wave.size * 0.5, 0.19).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	if bounce:
		var deflect := b + Vector2(randf_range(-260, 260), 120)
		tw.tween_property(wave, "global_position", deflect, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(wave, "rotation", 0.75, 0.16)
		tw.parallel().tween_property(wave, "modulate", Color(0.65, 0.68, 0.75, 0.0), 0.16)
	else:
		tw.tween_property(wave, "scale", Vector2(2.1, 2.1), 0.09)
		tw.parallel().tween_property(wave, "modulate", Color(1, 1, 1, 0), 0.09)
	tw.tween_callback(func():
		if is_instance_valid(wave):
			wave.queue_free())


static func _play_ultimate_beam(host: Control, from_c: Control, to_c: Control, was_blocked: bool = false) -> void:
	var a := from_c.get_global_rect().get_center()
	var b := to_c.get_global_rect().get_center()
	var min_y := 80.0
	var h := 1160.0 if not was_blocked else 640.0
	var beam := Panel.new()
	beam.size = Vector2(220, h)
	beam.pivot_offset = beam.size * 0.5
	beam.global_position = Vector2(b.x - 110, min_y)
	beam.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.58, 0.28, 0.98, 0.92)
	sb.border_color = UiTheme.INK
	sb.set_border_width_all(8)
	beam.add_theme_stylebox_override("panel", sb)
	host.add_child(beam)

	var core := ColorRect.new()
	core.color = Color(1.0, 0.95, 0.42, 0.98)
	core.size = Vector2(92, h - 16)
	core.position = Vector2(64, 8)
	core.mouse_filter = Control.MOUSE_FILTER_IGNORE
	beam.add_child(core)

	var tw := host.create_tween()
	tw.tween_property(beam, "scale:x", 1.85, 0.10)
	tw.tween_property(beam, "scale:x", 0.08, 0.28)
	tw.parallel().tween_property(beam, "modulate", Color(1, 1, 1, 0), 0.28)
	tw.tween_callback(func():
		if is_instance_valid(beam):
			beam.queue_free())


static func _siphon_orbs(host: Control, victim_c: Control, absorber_c: Control, col: Color) -> void:
	if host == null or victim_c == null or absorber_c == null:
		return
	var a := victim_c.get_global_rect().get_center()
	var b := absorber_c.get_global_rect().get_center()
	var stage_mid := Vector2(540, 640)
	for i in 10:
		var orb := Panel.new()
		orb.size = Vector2(44, 44)
		orb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sb := StyleBoxFlat.new()
		sb.bg_color = col.lightened(0.32)
		sb.border_color = UiTheme.INK
		sb.set_border_width_all(5)
		sb.set_corner_radius_all(22)
		orb.add_theme_stylebox_override("panel", sb)
		host.add_child(orb)
		var off := Vector2(randf_range(-140, 140), randf_range(-60, 60))
		orb.global_position = a + off
		var tw := host.create_tween()
		tw.tween_interval(i * 0.03)
		tw.tween_property(orb, "global_position", stage_mid - orb.size * 0.5 + off * 0.3, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(orb, "global_position", b - orb.size * 0.5, 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		tw.tween_callback(func():
			if is_instance_valid(orb):
				orb.queue_free())


static func _play_seal_chains(host: Control, target: Control) -> void:
	if host == null or target == null:
		return
	_flash_rect(host, target, Color(0.55, 0.15, 0.75, 0.55))
	_shake(target)
	_burst(host, target, Color(0.95, 0.25, 0.50), 18)


static func _play_block_positive(host: Control, target: Control) -> void:
	if host == null or target == null:
		return
	_flash_rect(host, target, Color(0.10, 0.78, 0.98, 0.52))
	_ring(host, target, UiTheme.SHIELD)
	_burst(host, target, Color(1.0, 0.88, 0.25), 18)


static func _play_blocked_rebound(host: Control, target: Control) -> void:
	if host == null or target == null:
		return
	_flash_rect(host, target, Color(0.45, 0.48, 0.55, 0.50))
	var base := target.position
	var recoil_y := 28.0 if target.global_position.y > 700.0 else -28.0
	var tw := target.create_tween()
	tw.tween_property(target, "position", base + Vector2(0, recoil_y), 0.06).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(target, "position", base + Vector2(-12, 0), 0.05)
	tw.tween_property(target, "position", base + Vector2(12, 0), 0.05)
	tw.tween_property(target, "position", base, 0.08)
	_burst(host, target, Color(0.75, 0.78, 0.84), 14)


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

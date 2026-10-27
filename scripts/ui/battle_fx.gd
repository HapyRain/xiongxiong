## battle_fx.gd
## 血/气/盾图标、全技能专属粒子动效、中央出招卡对撞演出、MOBA 级非对称博弈横幅、右下 5 轮打字机上推战报、全套音效与渐进式紧绷感 BGM。
## 纯 UI 表现层，不碰 rules/* 结算逻辑。
class_name BattleFx
extends RefCounted

const COLOR_HP := Color(0.937, 0.267, 0.267)       # #EF4444 鲜红血点
const COLOR_HP_EMPTY := Color(0.886, 0.910, 0.941) # #E2E8F0
const COLOR_QI := Color(0.961, 0.620, 0.043)       # #F59E0B 元气琥珀金气珠
const COLOR_QI_EMPTY := Color(0.886, 0.910, 0.941) # #E2E8F0
const COLOR_SHIELD := Color(0.055, 0.647, 0.914)   # #0EA5E9 天青蓝护盾
const COLOR_SHIELD_EMPTY := Color(0.886, 0.910, 0.941)
const COLOR_HIT := Color(0.937, 0.267, 0.267)
const COLOR_BLOCK := Color(0.055, 0.647, 0.914)
const COLOR_WIN := Color(0.063, 0.725, 0.506)
const COLOR_LOSE := Color(0.863, 0.149, 0.149)
const COLOR_DRAW := Color(0.478, 0.525, 0.604)

static var _wav_cache: Dictionary = {}


# ══════════════════════ 1. 音频引擎（20 音效 + 随回合推进紧绷感 BGM） ══════════════════════

## 兼容已 import 的 AudioStream 与未 import 的裸 16-bit PCM WAV 文件（44100Hz 单声道）
static func load_wav_safe(file_name: String, loop: bool = false) -> AudioStream:
	var cache_key := file_name + ("|loop" if loop else "")
	if _wav_cache.has(cache_key):
		return _wav_cache[cache_key]
	var res_path := "res://assets/audio/" + file_name
	if ResourceLoader.exists(res_path):
		var loaded := load(res_path)
		if loaded is AudioStreamWAV:
			var dup := (loaded as AudioStreamWAV).duplicate() as AudioStreamWAV
			if loop:
				dup.loop_mode = AudioStreamWAV.LOOP_FORWARD
				dup.loop_begin = 0
				dup.loop_end = int(dup.data.size() / 2)
			_wav_cache[cache_key] = dup
			return dup
		elif loaded is AudioStream:
			_wav_cache[cache_key] = loaded
			return loaded
	if FileAccess.file_exists(res_path):
		var bytes := FileAccess.get_file_as_bytes(res_path)
		if bytes.size() > 44:
			var data_offset := 44
			# 标准 RIFF WAVE data chunk 查找，兼容扩展头
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
	return null


static func setup_audio_bank(host: Node) -> Dictionary:
	var sfx_players: Array[AudioStreamPlayer] = []
	for _i in 6:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		host.add_child(p)
		sfx_players.append(p)

	var bgm_player := AudioStreamPlayer.new()
	bgm_player.name = "BgmPlayer"
	bgm_player.bus = "Master"
	bgm_player.volume_db = -12.0
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
		return
	var players: Array = bank.get("players", [])
	for p: AudioStreamPlayer in players:
		if not p.playing:
			p.stream = stream
			p.volume_db = vol_db
			p.pitch_scale = pitch
			p.play()
			return
	if not players.is_empty():
		var p0: AudioStreamPlayer = players[0]
		p0.stream = stream
		p0.volume_db = vol_db
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
	bgm.volume_db = -12.0
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
	var pitch := 1.0 + clampf(float(rno - 1) * 0.008, 0.0, 0.22)
	var vol := -12.0 + clampf(float(rno - 1) * 0.16, 0.0, 4.0)
	if int(s.hp[0]) == 1 or int(s.hp[1]) == 1:
		pitch += 0.05
		vol += 1.2
	if s.score_to_win() > 1 and (int(s.score[0]) >= s.score_to_win() - 2 or int(s.score[1]) >= s.score_to_win() - 2):
		pitch += 0.04
	bgm.pitch_scale = clampf(pitch, 1.0, 1.30)
	bgm.volume_db = clampf(vol, -12.0, -6.5)


# ══════════════════════ 2. 血/气/盾图标行 ══════════════════════

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
		sb.border_color = color.darkened(0.22)
	else:
		sb.border_color = empty_color.darkened(0.14)
	sb.set_border_width_all(1)
	var r := int(round(minf(pip_size.x, pip_size.y) * 0.35))
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
			pip_size = Vector2(14, 14)
		var key := "%s|%s|%s|%s" % [
			str(on), color.to_html(), empty_color.to_html(), str(pip_size)]
		if str(holder.get_meta("pip_key", "")) == key:
			continue
		holder.set_meta("pip_key", key)
		holder.add_theme_stylebox_override("panel", _pip_style(on, color, empty_color, pip_size))


static func make_hp_row(max_n: int, filled: int) -> HBoxContainer:
	return make_pip_row(max_n, filled, COLOR_HP, COLOR_HP_EMPTY, Vector2(16, 14), 4)


static func make_qi_row(max_n: int, filled: int) -> HBoxContainer:
	return make_pip_row(max_n, filled, COLOR_QI, COLOR_QI_EMPTY, Vector2(12, 12), 3)


static func make_shield_row(max_n: int, filled: int) -> HBoxContainer:
	return make_pip_row(max_n, filled, COLOR_SHIELD, COLOR_SHIELD_EMPTY, Vector2(14, 14), 4)


static func make_stat_line(title: String, row: HBoxContainer, value_lab: Label) -> HBoxContainer:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 6)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var t := Label.new()
	t.text = title
	t.custom_minimum_size.x = 20
	t.add_theme_font_size_override("font_size", 12)
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


# ══════════════════════ 3. MOBA 级中央偏上反馈横幅 + 右下 5 轮打字机上推战报 ══════════════════════

static func make_moba_banner() -> PanelContainer:
	var banner := PanelContainer.new()
	banner.name = "MobaBanner"
	banner.custom_minimum_size = Vector2(336, 44)
	banner.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.059, 0.090, 0.165, 0.95)
	sb.border_color = UiTheme.ACCENT
	sb.set_border_width_all(2)
	sb.border_width_left = 6
	sb.border_width_right = 6
	sb.set_corner_radius_all(12)
	sb.shadow_color = Color(0, 0, 0, 0.18)
	sb.shadow_size = 3
	sb.shadow_offset = Vector2(0, 2)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
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
	v.add_theme_constant_override("separation", 1)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.add_child(v)

	var title := UiTheme.ink_label("⚡ 点击「攒气」开始对决 ⚡", 15, Color(1.0, 0.94, 0.70))
	title.name = "BannerTitle"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)

	var sub := UiTheme.ink_label("两拍同步读招 · 预判对手行动", 11, Color(0.82, 0.88, 0.95))
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
		title.add_theme_color_override("font_color", accent.lightened(0.45))
	if sub != null:
		sub.text = sub_text
		sub.visible = sub_text != ""

	var sb := banner.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	if sb != null:
		sb.border_color = accent
		banner.add_theme_stylebox_override("panel", sb)

	if pulse:
		banner.pivot_offset = banner.size * 0.5
		banner.scale = Vector2(1.34, 1.34)
		var tw := banner.create_tween()
		tw.tween_property(banner, "scale", Vector2(0.96, 0.96), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(banner, "scale", Vector2.ONE, 0.10)


## 创建位于右中下区域的「5 轮打字机上推战报栏」（一屏最多记 5 次，从下往上推）
static func make_battle_ticker() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "BattleTicker"
	panel.custom_minimum_size = Vector2(216, 84)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_END
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.059, 0.090, 0.165, 0.90)
	sb.border_color = UiTheme.SHIELD.lightened(0.15)
	sb.set_border_width_all(1)
	sb.border_width_left = 4
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	panel.add_theme_stylebox_override("panel", sb)

	var box := VBoxContainer.new()
	box.name = "TickerLines"
	box.alignment = BoxContainer.ALIGNMENT_END
	box.add_theme_constant_override("separation", 1)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(box)

	panel.set_meta("history", [])
	for i in 5:
		var lab := UiTheme.ink_label("", 10, Color(0.92, 0.95, 1.0))
		lab.name = "Line%d" % i
		lab.clip_text = true
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
	var alphas := [0.42, 0.54, 0.68, 0.82, 1.0]
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
			lab.modulate = Color(1.0, 0.94, 0.65, 1.0) if is_newest else Color(0.85, 0.90, 0.96, a)
			if is_newest:
				lab.visible_ratio = 0.0
				var tw := lab.create_tween()
				tw.tween_property(lab, "visible_ratio", 1.0, 0.30)

	box.position.y = 10.0
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


## 创建带实时技能图标与两字大名的中央对撞出招卡
static func make_duel_card(who_title: String, border_col: Color) -> PanelContainer:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(132, 64)
	p.add_theme_stylebox_override("panel", UiTheme.card_style(UiTheme.BG_CARD, 12, border_col, 2))
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 2)
	p.add_child(v)

	var t := UiTheme.ink_label(who_title, 11, UiTheme.INK_SOFT)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 6)
	v.add_child(row)

	var icon := TextureRect.new()
	icon.name = "DuelIcon"
	icon.custom_minimum_size = Vector2(24, 24)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.visible = false
	row.add_child(icon)

	var act_lab := UiTheme.ink_label("待命", 21, border_col.darkened(0.1))
	act_lab.name = "DuelText"
	act_lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(act_lab)

	p.set_meta("duel_icon", icon)
	p.set_meta("duel_text", act_lab)
	return p


static func update_duel_card(card: PanelContainer, act: int, placeholder_text: String = "待选") -> void:
	if card == null or not is_instance_valid(card):
		return
	var icon := card.get_meta("duel_icon", null) as TextureRect
	var lab := card.get_meta("duel_text", null) as Label
	if act >= 0:
		var col := UiTheme.action_color(act)
		card.add_theme_stylebox_override("panel", UiTheme.card_style(UiTheme.BG_CARD, 12, col, 2))
		if lab != null:
			lab.text = GameRules.action_short_name(act)
			lab.add_theme_color_override("font_color", col.darkened(0.12))
		if icon != null:
			icon.texture = UiTheme.load_ui_texture(UiTheme.action_icon_name(act))
			icon.visible = icon.texture != null
	else:
		if lab != null:
			lab.text = placeholder_text
			lab.add_theme_color_override("font_color", UiTheme.INK_FAINT)
		if icon != null:
			icon.visible = false


# ══════════════════════ 4. 全技能专属演出与非对称格挡/吸收导演系统 ══════════════════════

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
	var my_act: int = int(acts[me]) if acts.size() > me else 0
	var op_act: int = int(acts[op]) if acts.size() > op else 0

	if me_duel_card != null:
		update_duel_card(me_duel_card, my_act)
	if opp_duel_card != null:
		update_duel_card(opp_duel_card, op_act)

	if opening:
		play_named_sfx(audio_bank, "game_start", -1.0)
		show_moba_banner(moba_banner, "⚡ 对决开始 · 双方气 +1 ⚡", "第 1 回合开局亮相 · 准备第 2 回合交锋", UiTheme.ACCENT, true)
		push_ticker_line(ticker, "R01 开局亮相 ▸ 双方气+1")
		if fx_host != null:
			_aura_rise(fx_host, me_card, UiTheme.ACCENT, "+1 气 ⚡")
			_aura_rise(fx_host, opp_card, UiTheme.ACCENT, "+1 气 ⚡")
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
	var rno := maxi(1, int(s.round) if s != null else 2)

	# 中央双出招卡物理碰撞动效
	_animate_duel_cards_clash(me_duel_card, opp_duel_card, my_blk, op_blk, my_hit, op_hit)

	# 1. 劝降特例
	if qj >= 0:
		play_named_sfx(audio_bank, "quan_jiang", 0.0)
		var qj_win := (qj == me)
		show_moba_banner(
			moba_banner,
			"👑 劝降触发 · 我方不战而胜！" if qj_win else "👑 对手触发劝降 · 气势压倒！",
			"满气满血对阵 1 血，直接拿下本小局",
			UiTheme.ACCENT if qj_win else UiTheme.DANGER,
			true
		)
		push_ticker_line(ticker, "R%02d 【劝降】触发 ▸ %s直接获胜" % [rno, "我" if qj_win else "对手"])
		if fx_host != null:
			_float_banner(fx_host, me_card if qj_win else opp_card, "👑 劝降秒杀！", UiTheme.ACCENT, 26)
		return

	# 2. 施法音效与基础弹道/增益动效
	var from_me: Control = me_duel_card if me_duel_card != null else me_card
	var from_opp: Control = opp_duel_card if opp_duel_card != null else opp_card
	_play_skill_cast_vfx_and_sfx(fx_host, my_act, op_act, from_me, from_opp, op_blk, my_blk, audio_bank)

	# 3. 判定核心博弈结果（吸收 / 封盾 / 格挡非对称反馈 / 穿防重击 / 互抵）
	var banner_title := "⚔️ 【%s】 对决 【%s】" % [my_name, op_name]
	var banner_sub := "双方交锋完成"
	var banner_col := UiTheme.ACCENT
	var ticker_tag := "平分秋色"

	# 3A. 吸收博弈分支
	if my_act == GameRules.Action.XI_SHOU or op_act == GameRules.Action.XI_SHOU:
		if my_act == GameRules.Action.XI_SHOU and op_act == GameRules.Action.XI_SHOU:
			play_named_sfx(audio_bank, "ui_deny", -2.0)
			banner_title = "💨 双吸落空 · 徒耗元气"
			banner_sub = "双方同时使用吸收，各自白花 1 气"
			banner_col = UiTheme.SPECIAL
			ticker_tag = "双吸落空"
		elif my_act == GameRules.Action.XI_SHOU:
			if GameRules.is_gain(op_act):
				play_named_sfx(audio_bank, "xi_shou_ok", 0.0)
				banner_title = "🌀 吸收成功 · 巧取对手【%s】！" % op_name
				banner_sub = "对手本轮增益作废，全数归入我方囊中！"
				banner_col = UiTheme.SPECIAL
				ticker_tag = "我偷取[%s]" % op_name
				if fx_host != null:
					_play_center_vortex(fx_host, from_me, UiTheme.SPECIAL, false)
					_siphon_orbs(fx_host, opp_card, me_card, UiTheme.SPECIAL)
					_float_banner(fx_host, me_card, "✨ 吸收成功！偷取【%s】" % op_name, UiTheme.SPECIAL, 20)
					_float_banner(fx_host, opp_card, "💸 增益被偷空！", UiTheme.INK_SOFT, 17)
			elif GameRules.is_attack(op_act):
				play_named_sfx(audio_bank, "xi_shou_fail", 0.0)
				banner_title = "💔 吸收反噬 · 被【%s】打断！" % op_name
				banner_sub = "预判失误撞上对手攻击，我方掉 1 血"
				banner_col = UiTheme.DANGER
				ticker_tag = "我吸收受击-1血"
				if fx_host != null:
					_play_center_vortex(fx_host, from_me, UiTheme.DANGER, true)
					play_hurt(fx_host, me_card)
					_float_banner(fx_host, me_card, "💔 吸收受击 -1血！", UiTheme.DANGER, 20)
					_float_banner(fx_host, opp_card, "🎯 抓破吸收！", UiTheme.WAVE, 18)
			else:
				play_named_sfx(audio_bank, "ui_deny", -2.0)
				banner_title = "💨 吸收落空 · 对手出【%s】" % op_name
				banner_sub = "对手未产生可偷增益，白花 1 气"
				banner_col = UiTheme.INK_SOFT
				ticker_tag = "我吸收落空"
				if fx_host != null:
					_float_banner(fx_host, me_card, "💨 吸收落空", UiTheme.INK_SOFT, 16)
		else:
			if GameRules.is_gain(my_act):
				play_named_sfx(audio_bank, "xi_shou_ok", -1.0)
				banner_title = "⚠️ 增益被偷 · 对手吸收了【%s】！" % my_name
				banner_sub = "我方本轮【%s】收益被对手夺走！" % my_name
				banner_col = UiTheme.DANGER
				ticker_tag = "对手偷走[%s]" % my_name
				if fx_host != null:
					_play_center_vortex(fx_host, from_opp, UiTheme.SPECIAL, false)
					_siphon_orbs(fx_host, me_card, opp_card, UiTheme.SPECIAL)
					_float_banner(fx_host, opp_card, "🌀 吸收得手！", UiTheme.SPECIAL, 19)
					_float_banner(fx_host, me_card, "💸 【%s】被吸走！" % my_name, UiTheme.DANGER, 19)
			elif GameRules.is_attack(my_act):
				play_named_sfx(audio_bank, "xi_shou_fail", 0.0)
				banner_title = "🎯 识破吸收 · 【%s】重创对手！" % my_name
				banner_sub = "对手妄图吸收被我方直接打断，对手 -1 血！"
				banner_col = UiTheme.OK_GREEN
				ticker_tag = "打断吸收 敌-1血"
				if fx_host != null:
					_play_center_vortex(fx_host, from_opp, UiTheme.DANGER, true)
					play_hit(fx_host, opp_card)
					_float_banner(fx_host, me_card, "🎯 抓破吸收！", UiTheme.OK_GREEN, 20)
					_float_banner(fx_host, opp_card, "💔 吸收反噬 -1血！", UiTheme.DANGER, 19)
			else:
				banner_title = "🛡️ 稳健识破 · 对手吸收落空！"
				banner_sub = "对手白耗 1 气，未偷到任何收益"
				banner_col = UiTheme.SHIELD
				ticker_tag = "对手吸收落空"
				if fx_host != null:
					_float_banner(fx_host, opp_card, "💨 吸收落空", UiTheme.INK_SOFT, 16)

	# 3B. 小羊破防封盾分支
	elif my_seal or op_seal:
		play_named_sfx(audio_bank, "seal", 0.0)
		if op_seal:
			banner_title = "⛓️ 破防封盾 · 锁死对手护盾！"
			banner_sub = "对手下回合禁用「防御」与「爆气」！"
			banner_col = UiTheme.ACCENT
			ticker_tag = "对手被封盾"
			if fx_host != null:
				_play_seal_chains(fx_host, opp_card)
				_float_banner(fx_host, me_card, "🐏 小羊破防！", UiTheme.ACCENT, 20)
				_float_banner(fx_host, opp_card, "⛓️ 护盾被封 1 回合！", UiTheme.DANGER, 20)
		else:
			banner_title = "🚫 护盾被封 · 小心下回合！"
			banner_sub = "我方被小羊破防，下回合禁用「防御」与「爆气」"
			banner_col = UiTheme.DANGER
			ticker_tag = "我被封盾"
			if fx_host != null:
				_play_seal_chains(fx_host, me_card)
				_float_banner(fx_host, me_card, "⛓️ 护盾被封 1 回合！", UiTheme.DANGER, 20)
				_float_banner(fx_host, opp_card, "🐏 破防成功！", UiTheme.WAVE, 18)

	# 3C. 格挡成功 vs 被格挡（非对称强反馈）
	elif my_blk or op_blk:
		if my_blk:
			play_named_sfx(audio_bank, "block_success", 0.0)
			var is_sf := (my_act == GameRules.Action.STRONG_FANG)
			banner_title = ("⚡ 强防壁垒 · 挡下【%s】！" if is_sf else "🛡️ 完美格挡 · 化解【%s】攻势！") % op_name
			banner_sub = "我方成功抵御对手进攻，稳住阵脚！"
			if is_sf and op_act == GameRules.Action.ZHONG_JI:
				banner_sub = "强防挡下终极技，但我方护盾已全部震碎！"
			banner_col = UiTheme.SHIELD
			ticker_tag = "我格挡[%s]" % op_name
			if fx_host != null:
				_play_block_positive(fx_host, me_card, "⚡ 强防弹反！" if is_sf else "🛡️ 格挡成功！")
				_play_blocked_rebound(fx_host, opp_card, "💥 攻击被挡！")
				if me_duel_card != null:
					_float_banner(fx_host, me_duel_card, "🛡️ 格挡成功", UiTheme.SHIELD, 15)
				if opp_duel_card != null:
					_float_banner(fx_host, opp_duel_card, "💥 被格挡", Color(0.90, 0.40, 0.15), 15)
		if op_blk:
			play_named_sfx(audio_bank, "blocked_rebound", 0.0)
			var op_sf := (op_act == GameRules.Action.STRONG_FANG)
			banner_title = "💥 攻势受挫 · 【%s】被对手挡下！" % my_name
			banner_sub = ("对手开启【强防】弹开了你的进攻" if op_sf else "对手提前预判格挡，未能造成伤害")
			banner_col = Color(0.95, 0.52, 0.18)
			ticker_tag = "[%s]被对手格挡" % my_name
			if fx_host != null:
				_play_blocked_rebound(fx_host, me_card, "💥 攻击被挡！")
				_play_block_positive(fx_host, opp_card, "⚡ 强防弹反！" if op_sf else "🛡️ 格挡成功！")
				if me_duel_card != null:
					_float_banner(fx_host, me_duel_card, "💥 被格挡", Color(0.90, 0.40, 0.15), 15)
				if opp_duel_card != null:
					_float_banner(fx_host, opp_duel_card, "🛡️ 格挡成功", UiTheme.SHIELD, 15)

	# 3D. 命中扣血分支（终极 / 大羊 / 包子 / 裸防受击）
	elif my_hit or op_hit:
		if op_hit and my_hit:
			play_named_sfx(audio_bank, "zhong_ji", 0.0)
			banner_title = "☄️ 双终极对轰 · 两败俱伤！"
			banner_sub = "双方同时命中终极技，各掉 2 血！"
			banner_col = UiTheme.SPECIAL
			ticker_tag = "双终极互轰-2血"
			if fx_host != null:
				play_hit(fx_host, me_card)
				play_hit(fx_host, opp_card)
				_float_banner(fx_host, me_card, "🩸 重创 -2血！", UiTheme.DANGER, 22)
				_float_banner(fx_host, opp_card, "🩸 重创 -2血！", UiTheme.DANGER, 22)
		elif op_hit:
			var dmg: int = absi(int(hp_d[op]))
			play_named_sfx(audio_bank, "zhong_ji" if dmg >= 2 else "hit", 0.0)
			banner_title = ("☄️ 终极必杀 · 轰穿对手 -%d血！" if dmg >= 2 else "🔥 精准命中 · 【%s】打掉对手 1 血！") % (dmg if dmg >= 2 else my_name)
			banner_sub = "我方进攻直接奏效，压制对手血线！"
			banner_col = UiTheme.OK_GREEN if dmg == 1 else UiTheme.SPECIAL
			ticker_tag = "命中对手 -%d血" % dmg
			if fx_host != null:
				play_hit(fx_host, opp_card)
				_float_banner(fx_host, me_card, "🔥 破防命中！", UiTheme.ACCENT, 19)
				_float_banner(fx_host, opp_card, "🩸 受击 -%d血！" % dmg, UiTheme.DANGER, 22)
		else:
			var my_dmg: int = absi(int(hp_d[me]))
			play_named_sfx(audio_bank, "zhong_ji" if my_dmg >= 2 else "hit", 0.0)
			banner_title = "⚠️ 遭受重击 · 被【%s】打掉 %d 血！" % [op_name, my_dmg]
			banner_sub = "注意对手气量与破防技冷却！"
			banner_col = UiTheme.DANGER
			ticker_tag = "我受击 -%d血" % my_dmg
			if fx_host != null:
				play_hurt(fx_host, me_card)
				_float_banner(fx_host, me_card, "🩸 受击 -%d血！" % my_dmg, UiTheme.DANGER, 22)
				_float_banner(fx_host, opp_card, "💥 命中得手！", UiTheme.WAVE, 18)

	# 3E. 包子互拼削盾 / 招式互抵 / 双方攒气回血
	else:
		var my_sh_d := int(sh_d[me])
		var op_sh_d := int(sh_d[op])
		if op_sh_d < 0 and GameRules.is_bao(my_act):
			play_named_sfx(audio_bank, "hit", -2.0)
			banner_title = "💥 火力压制 · 削减对手 %d 盾！" % abs(op_sh_d)
			banner_sub = "包子对拼占优，击碎对手护盾"
			banner_col = UiTheme.WAVE
			ticker_tag = "破对手%d盾" % abs(op_sh_d)
			if fx_host != null:
				_float_banner(fx_host, opp_card, "🛡️ 护盾 %d" % op_sh_d, UiTheme.DANGER, 18)
		elif my_sh_d < 0 and GameRules.is_bao(op_act):
			play_named_sfx(audio_bank, "hit", -2.0)
			banner_title = "⚠️ 对拼劣势 · 我方损失 %d 盾" % abs(my_sh_d)
			banner_sub = "对手包子连数更高，注意补盾"
			banner_col = UiTheme.ACCENT
			ticker_tag = "我损%d盾" % abs(my_sh_d)
			if fx_host != null:
				_float_banner(fx_host, me_card, "🛡️ 护盾 %d" % my_sh_d, UiTheme.DANGER, 18)
		elif GameRules.is_attack(my_act) and my_act == op_act:
			play_named_sfx(audio_bank, "block", 0.0)
			banner_title = "⚔️ 招式互抵 · 【%s】正面相撞！" % my_name
			banner_sub = "双方同招对撞，攻势相互抵消"
			banner_col = UiTheme.ACCENT
			ticker_tag = "同招[%s]互抵" % my_name
			if fx_host != null:
				_float_banner(fx_host, me_card, "⚔️ 招式抵消", UiTheme.ACCENT, 18)
				_float_banner(fx_host, opp_card, "⚔️ 招式抵消", UiTheme.ACCENT, 18)
		else:
			banner_title = "✨ 蓄势运营 · 我【%s】 vs 对手【%s】" % [my_name, op_name]
			banner_sub = "双方调息蓄力，准备下一拍博弈"
			banner_col = UiTheme.GAIN
			ticker_tag = "双方蓄力运营"

	show_moba_banner(moba_banner, banner_title, banner_sub, banner_col, true)
	push_ticker_line(ticker, "R%02d 我[%s] 对[%s] ▸ %s" % [rno, my_name, op_name, ticker_tag])


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
			# 我方攻击被对手挡下：向中心冲撞后猛烈弹回并后仰
			tw_m.tween_property(me_duel, "scale", Vector2(0.86, 0.86), 0.06)
			tw_m.parallel().tween_property(me_duel, "rotation", -0.16, 0.08)
			tw_m.tween_property(me_duel, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
			tw_m.parallel().tween_property(me_duel, "rotation", 0.0, 0.16)
		elif my_blk:
			# 我方格挡成功：稳健撑开护盾放大
			tw_m.tween_property(me_duel, "scale", Vector2(1.20, 1.20), 0.10).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw_m.tween_property(me_duel, "scale", Vector2.ONE, 0.18)
		elif my_hit:
			tw_m.tween_property(me_duel, "scale", Vector2(0.84, 0.84), 0.08)
			tw_m.tween_property(me_duel, "scale", Vector2.ONE, 0.14)
		else:
			tw_m.tween_property(me_duel, "scale", Vector2(1.12, 1.12), 0.09).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw_m.tween_property(me_duel, "scale", Vector2.ONE, 0.14)

	if opp_duel != null and is_instance_valid(opp_duel):
		opp_duel.pivot_offset = opp_duel.size * 0.5
		var tw_o := opp_duel.create_tween()
		if my_blk:
			# 对手攻击被我方挡下：弹回后仰
			tw_o.tween_property(opp_duel, "scale", Vector2(0.86, 0.86), 0.06)
			tw_o.parallel().tween_property(opp_duel, "rotation", 0.16, 0.08)
			tw_o.tween_property(opp_duel, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
			tw_o.parallel().tween_property(opp_duel, "rotation", 0.0, 0.16)
		elif op_blk:
			tw_o.tween_property(opp_duel, "scale", Vector2(1.20, 1.20), 0.10).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw_o.tween_property(opp_duel, "scale", Vector2.ONE, 0.18)
		elif op_hit:
			tw_o.tween_property(opp_duel, "scale", Vector2(0.84, 0.84), 0.08)
			tw_o.tween_property(opp_duel, "scale", Vector2.ONE, 0.14)
		else:
			tw_o.tween_property(opp_duel, "scale", Vector2(1.12, 1.12), 0.09).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw_o.tween_property(opp_duel, "scale", Vector2.ONE, 0.14)


static func _play_center_vortex(host: Control, anchor: Control, col: Color, implode: bool) -> void:
	if host == null or anchor == null:
		return
	var tex := UiTheme.load_ui_texture("icon_xi_shou.png")
	var vtx := TextureRect.new()
	vtx.texture = tex
	vtx.size = Vector2(56, 56)
	vtx.pivot_offset = Vector2(28, 28)
	vtx.modulate = col.lightened(0.25)
	vtx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(vtx)
	var c := anchor.get_global_rect().get_center()
	vtx.global_position = c - Vector2(28, 28)
	var tw := host.create_tween().set_parallel(true)
	tw.tween_property(vtx, "rotation", TAU * (1.5 if not implode else -1.5), 0.36)
	if implode:
		vtx.scale = Vector2(1.5, 1.5)
		tw.tween_property(vtx, "scale", Vector2(0.1, 0.1), 0.34).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	else:
		vtx.scale = Vector2(0.3, 0.3)
		tw.tween_property(vtx, "scale", Vector2(1.4, 1.4), 0.34).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(vtx, "modulate:a", 0.0, 0.36)
	tw.chain().tween_callback(func():
		if is_instance_valid(vtx):
			vtx.queue_free())


static func _play_skill_cast_vfx_and_sfx(
	fx_host: Control,
	my_act: int,
	op_act: int,
	me_card: Control,
	opp_card: Control,
	op_blk: bool,
	my_blk: bool,
	audio_bank: Dictionary
) -> void:
	for act in [my_act, op_act]:
		match act:
			GameRules.Action.BAO3:
				play_named_sfx(audio_bank, "bao3", -2.0)
			GameRules.Action.BAO2:
				play_named_sfx(audio_bank, "bao2", -2.0)
			GameRules.Action.BAO1:
				play_named_sfx(audio_bank, "bao1", -3.0)
			GameRules.Action.STRONG_FANG:
				play_named_sfx(audio_bank, "strong_fang", -2.0)
			GameRules.Action.XIAO_YANG:
				play_named_sfx(audio_bank, "xiao_yang", -2.0)
			GameRules.Action.DA_YANG:
				play_named_sfx(audio_bank, "da_yang", -1.0)
			GameRules.Action.JI_QI:
				play_named_sfx(audio_bank, "ji_qi", -2.0)
			GameRules.Action.BAO_QI:
				play_named_sfx(audio_bank, "bao_qi", -2.0)
			GameRules.Action.HUI_FU:
				play_named_sfx(audio_bank, "hui_fu", -1.0)
			GameRules.Action.ZAN:
				play_named_sfx(audio_bank, "zan", -4.0)

	if fx_host == null:
		return

	_spawn_single_side_skill_vfx(fx_host, my_act, me_card, opp_card, true, op_blk)
	_spawn_single_side_skill_vfx(fx_host, op_act, opp_card, me_card, false, my_blk)


static func _spawn_single_side_skill_vfx(
	host: Control,
	act: int,
	from_card: Control,
	to_card: Control,
	friendly: bool,
	was_blocked: bool
) -> void:
	if host == null or from_card == null or to_card == null:
		return
	match act:
		GameRules.Action.ZAN:
			_aura_rise(host, from_card, UiTheme.ACCENT, "+1气 +1盾")
		GameRules.Action.JI_QI:
			_aura_rise(host, from_card, UiTheme.GAIN, "⚡ 集气 +3气！")
		GameRules.Action.HUI_FU:
			_aura_rise(host, from_card, UiTheme.OK_GREEN, "💚 回复 +1血！")
		GameRules.Action.BAO_QI:
			_ring(host, from_card, UiTheme.SPECIAL)
			_aura_rise(host, from_card, UiTheme.SPECIAL, "🛡️ 爆气满盾！")
		GameRules.Action.BAO1, GameRules.Action.BAO2, GameRules.Action.BAO3:
			var n := GameRules.bao_count(act)
			for k in n:
				host.get_tree().create_timer(k * 0.07).timeout.connect(func():
					if is_instance_valid(host) and is_instance_valid(from_card) and is_instance_valid(to_card):
						_fire_bao_orb(host, from_card, to_card, friendly, was_blocked))
		GameRules.Action.XIAO_YANG:
			_fire_ram_wave(host, from_card, to_card, Color(1.0, 0.55, 0.15), false)
		GameRules.Action.DA_YANG:
			_fire_ram_wave(host, from_card, to_card, UiTheme.WAVE, true)
		GameRules.Action.ZHONG_JI:
			_play_ultimate_beam(host, from_card, to_card)


static func _fire_bao_orb(host: Control, from_c: Control, to_c: Control, friendly: bool, bounce: bool) -> void:
	var orb := Panel.new()
	orb.size = Vector2(22, 22)
	orb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var col := UiTheme.WAVE if friendly else Color(1.0, 0.42, 0.18)
	orb.add_theme_stylebox_override("panel", _pip_style(true, col, col, Vector2(22, 22)))
	host.add_child(orb)
	var a := from_c.get_global_rect().get_center()
	var b := to_c.get_global_rect().get_center()
	orb.global_position = a - orb.size * 0.5
	var tw := host.create_tween()
	tw.tween_property(orb, "global_position", b - orb.size * 0.5, 0.20).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	if bounce:
		var deflect := b + Vector2(randf_range(-70, 70), 45 if friendly else -45)
		tw.tween_property(orb, "global_position", deflect, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(orb, "modulate", Color(0.7, 0.7, 0.7, 0.0), 0.16)
	else:
		tw.tween_property(orb, "scale", Vector2(1.7, 1.7), 0.06)
		tw.parallel().tween_property(orb, "modulate", Color(1, 1, 1, 0), 0.06)
	tw.tween_callback(func():
		if is_instance_valid(orb):
			orb.queue_free())


static func _fire_ram_wave(host: Control, from_c: Control, to_c: Control, col: Color, heavy: bool) -> void:
	var wave := ColorRect.new()
	wave.color = col
	wave.size = Vector2(56 if heavy else 38, 16 if heavy else 12)
	wave.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(wave)
	var a := from_c.get_global_rect().get_center()
	var b := to_c.get_global_rect().get_center()
	wave.global_position = a - wave.size * 0.5
	var tw := host.create_tween()
	tw.tween_property(wave, "global_position", b - wave.size * 0.5, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_property(wave, "scale", Vector2(1.8, 1.8), 0.08)
	tw.parallel().tween_property(wave, "modulate", Color(1, 1, 1, 0), 0.08)
	tw.tween_callback(func():
		if is_instance_valid(wave):
			wave.queue_free())


static func _play_ultimate_beam(host: Control, from_c: Control, to_c: Control) -> void:
	var a := from_c.get_global_rect().get_center()
	var b := to_c.get_global_rect().get_center()
	var min_y := minf(a.y, b.y)
	var h := maxf(80.0, absf(b.y - a.y))
	var beam := ColorRect.new()
	beam.color = Color(0.65, 0.35, 1.0, 0.88)
	beam.size = Vector2(36, h)
	beam.global_position = Vector2(b.x - 18, min_y)
	beam.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(beam)

	var core := ColorRect.new()
	core.color = Color(1.0, 0.95, 0.45, 0.96)
	core.size = Vector2(14, h)
	core.position = Vector2(11, 0)
	core.mouse_filter = Control.MOUSE_FILTER_IGNORE
	beam.add_child(core)

	var tw := host.create_tween()
	tw.tween_property(beam, "scale:x", 1.8, 0.10)
	tw.tween_property(beam, "scale:x", 0.1, 0.26)
	tw.parallel().tween_property(beam, "modulate", Color(1, 1, 1, 0), 0.26)
	tw.tween_callback(func():
		if is_instance_valid(beam):
			beam.queue_free())


static func _siphon_orbs(host: Control, victim_c: Control, absorber_c: Control, col: Color) -> void:
	if host == null or victim_c == null or absorber_c == null:
		return
	var a := victim_c.get_global_rect().get_center()
	var b := absorber_c.get_global_rect().get_center()
	for i in 6:
		var orb := ColorRect.new()
		orb.color = col.lightened(0.2)
		orb.size = Vector2(10, 10)
		orb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		host.add_child(orb)
		var off := Vector2(randf_range(-28, 28), randf_range(-16, 16))
		orb.global_position = a + off
		var tw := host.create_tween()
		tw.tween_interval(i * 0.035)
		tw.tween_property(orb, "global_position", b - orb.size * 0.5, 0.26).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		tw.tween_callback(func():
			if is_instance_valid(orb):
				orb.queue_free())


static func _play_seal_chains(host: Control, target: Control) -> void:
	if host == null or target == null:
		return
	_flash_rect(host, target, Color(0.55, 0.15, 0.75, 0.55))
	_shake(target)
	_burst(host, target, Color(0.85, 0.20, 0.45), 12)


static func _play_block_positive(host: Control, target: Control, text: String) -> void:
	if host == null or target == null:
		return
	_flash_rect(host, target, Color(0.10, 0.78, 0.98, 0.50))
	_ring(host, target, UiTheme.SHIELD)
	_burst(host, target, Color(0.98, 0.84, 0.25), 8)
	_float_banner(host, target, text, UiTheme.SHIELD.darkened(0.15), 21)


static func _play_blocked_rebound(host: Control, target: Control, text: String) -> void:
	if host == null or target == null:
		return
	_flash_rect(host, target, Color(0.45, 0.48, 0.55, 0.45))
	var base := target.position
	var recoil_y := 10.0 if target.global_position.y > 350.0 else -10.0
	var tw := target.create_tween()
	tw.tween_property(target, "position", base + Vector2(0, recoil_y), 0.06).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(target, "position", base + Vector2(-4, 0), 0.05)
	tw.tween_property(target, "position", base + Vector2(4, 0), 0.05)
	tw.tween_property(target, "position", base, 0.08)
	_burst(host, target, Color(0.65, 0.68, 0.74), 8)
	_float_banner(host, target, text, Color(0.88, 0.42, 0.15), 19)


static func _aura_rise(host: Control, target: Control, col: Color, label_txt: String) -> void:
	if host == null or target == null:
		return
	_flash_rect(host, target, Color(col.r, col.g, col.b, 0.32))
	_float_banner(host, target, label_txt, col.darkened(0.1), 16)


static func _float_banner(host: Control, target: Control, text: String, col: Color, fsize: int = 18) -> void:
	if host == null or target == null:
		return
	var pill := PanelContainer.new()
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.09, 0.16, 0.90)
	sb.border_color = col.lightened(0.25)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	pill.add_theme_stylebox_override("panel", sb)

	var lab := UiTheme.ink_label(text, fsize, Color.WHITE)
	lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.add_child(lab)
	host.add_child(pill)
	pill.reset_size()
	var c := target.get_global_rect().get_center()
	pill.global_position = c - pill.size * 0.5
	pill.scale = Vector2(0.5, 0.5)
	pill.pivot_offset = pill.size * 0.5

	var tw := host.create_tween()
	tw.set_parallel(true)
	tw.tween_property(pill, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(pill, "global_position:y", pill.global_position.y - 34.0, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.chain().tween_property(pill, "modulate", Color(1, 1, 1, 0), 0.22)
	tw.chain().tween_callback(func():
		if is_instance_valid(pill):
			pill.queue_free())


static func play_reject_feedback(btn: Control) -> void:
	if btn == null or not is_instance_valid(btn):
		return
	var base_x := btn.position.x
	var tw := btn.create_tween()
	tw.tween_property(btn, "position:x", base_x - 5.0, 0.04)
	tw.tween_property(btn, "position:x", base_x + 5.0, 0.04)
	tw.tween_property(btn, "position:x", base_x - 3.0, 0.04)
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
		if r.position.length() < 1.0 and r.size.y < 200 and tries < 12:
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
	var hole := r.grow(10)

	var vs := Vector2(390, 820)
	if root.get_viewport() != null and root.get_viewport().get_visible_rect().size.x > 0:
		vs = root.get_viewport().get_visible_rect().size
	var vw := maxf(root.size.x, vs.x)
	var vh := maxf(root.size.y, vs.y)

	var dim_color := Color(0.05, 0.07, 0.12, 0.0 if animate else 0.65)
	var d0 := _add_dim(root, Rect2(0, 0, vw, maxf(0, hole.position.y)), dim_color)
	var d1 := _add_dim(root, Rect2(0, hole.end.y, vw, maxf(0, vh - hole.end.y)), dim_color)
	var d2 := _add_dim(root, Rect2(0, hole.position.y, maxf(0, hole.position.x), hole.size.y), dim_color)
	var d3 := _add_dim(root, Rect2(hole.end.x, hole.position.y, maxf(0, vw - hole.end.x), hole.size.y), dim_color)
	if animate:
		var tw_dim := root.create_tween().set_parallel(true)
		for d in [d0, d1, d2, d3]:
			if d != null:
				tw_dim.tween_property(d, "color", Color(0.05, 0.07, 0.12, 0.65), 0.22)

	var border := 3.0
	var gold := Color(1.0, 0.78, 0.18, 0.98)
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
		var lab := Label.new()
		lab.text = caption
		lab.add_theme_font_size_override("font_size", 17)
		lab.add_theme_color_override("font_color", Color(1, 0.96, 0.86))
		lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lab.modulate = Color(1, 1, 1, 1 if not animate else 0)
		root.add_child(lab)
		lab.reset_size()
		lab.position = Vector2((vw - lab.size.x) * 0.5, hole.position.y - 48)
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
	# 显式解绑挂在目标按钮上的连接。
	# _on_spot_target_rect.bind(root) 每次都绑上一个新的 layer，`is_connected` 比较永不命中，
	# 不在这里 disconnect 就会随每个小局 / 每次「再来一局」在按钮上累积死连接。
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
			tw.tween_property(btn, "position", base + Vector2(4, 0), 0.06)
			tw.tween_property(btn, "position", base, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			_tint_flash(btn, Color(0.45, 0.45, 0.48), 0.14)
		"danger":
			_tint_flash(btn, Color(0.9, 0.25, 0.22), 0.22)
			var bpos := btn.position
			tw.tween_property(btn, "position", bpos + Vector2(-3, 0), 0.04)
			tw.tween_property(btn, "position", bpos + Vector2(3, 0), 0.05)
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
	_burst(host, target, COLOR_HIT, 12)


static func play_block(host: Control, target: Control) -> void:
	if host == null or target == null:
		return
	_flash_rect(host, target, COLOR_BLOCK)
	_ring(host, target, COLOR_BLOCK)


static func play_hurt(host: Control, target: Control) -> void:
	if host == null or target == null:
		return
	_flash_rect(host, target, Color(1, 0.35, 0.35, 0.55))
	_shake(target)


static func play_result(host: Control, winner: int, center: Control = null) -> void:
	if host == null:
		return
	var anchor: Control = center if center != null else host
	var color := COLOR_WIN if winner == 0 else (COLOR_LOSE if winner == 1 else COLOR_DRAW)
	var text := "胜利！" if winner == 0 else ("失败" if winner == 1 else "平局")
	_pop_label(host, anchor, text, color)
	_confetti(host, 28 if winner == 0 else 12)


static func play_projectile(host: Control, from: Control, to: Control, friendly: bool) -> void:
	if host == null or from == null or to == null:
		return
	_fire_bao_orb(host, from, to, friendly, false)


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
	for i in 5:
		var off := Vector2(randf_range(-6, 6), randf_range(-4, 4))
		tw.tween_property(target, "position", base + off, 0.035)
	tw.tween_property(target, "position", base, 0.05)


static func _burst(host: Control, target: Control, color: Color, n: int) -> void:
	var c := target.get_global_rect().get_center()
	for i in n:
		var p := ColorRect.new()
		p.color = color
		p.size = Vector2(7, 7)
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		host.add_child(p)
		p.global_position = c - p.size * 0.5
		var ang := TAU * float(i) / float(n)
		var dist := randf_range(32, 68)
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
	ring.color = Color(color.r, color.g, color.b, 0.48)
	ring.size = Vector2(10, 10)
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(ring)
	ring.global_position = c - ring.size * 0.5
	var tw := host.create_tween()
	tw.set_parallel(true)
	tw.tween_property(ring, "size", Vector2(88, 88), 0.30).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(ring, "global_position", c - Vector2(44, 44), 0.30)
	tw.tween_property(ring, "modulate", Color(1, 1, 1, 0), 0.30)
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
	var colors := [COLOR_HP, COLOR_QI, UiTheme.SHIELD, COLOR_WIN, UiTheme.SPECIAL]
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

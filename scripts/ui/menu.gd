## menu.gd
## 两页首页：主页（单人 / 联机入口）→ 联机页（建房 / 加入 / 搜索）。
## 已移除热座；文字用 UiTheme 深色系，避免奶油底上白字发虚。
extends Control

const GAME_PORT := 47001

var _page_home: Control
var _page_net: Control
var _status: Label
var _host_info: Label
var _ip_edit: LineEdit
var _token_edit: LineEdit
var _room_edit: LineEdit


func _ready() -> void:
	if Net != null and Net.get_session() != PeerManager.Session.IDLE:
		Net.leave()
	_build_ui()
	Net.mode_changed.connect(func(_m): _refresh_status())
	Net.session_changed.connect(func(_s): _refresh_status())
	Net.status_text.connect(func(t: String):
		if _status != null:
			_status.text = t)
	Net.peer_joined.connect(func(_id, _profile):
		if _status != null:
			_status.text = "对手已加入，进入对局…"
		_goto_battle())
	# 带参信号不能直接接无参方法；用 lambda 包一层，否则加入方永远进不了对局
	Net.battle_started.connect(func(_snap: Dictionary): _goto_battle(), CONNECT_ONE_SHOT)
	Net.room_found.connect(func(info: Dictionary):
		if _status != null:
			_status.text = "发现房间：%s @ %s:%s" % [info.get("room_name", "?"), info.get("address", "?"), info.get("port", "?")])
	_refresh_status()


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = UiTheme.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# 顶部品牌条
	var brand := Label.new()
	brand.text = "拍拍熊熊"
	brand.add_theme_font_size_override("font_size", 34)
	brand.add_theme_color_override("font_color", UiTheme.INK)
	brand.set_anchors_preset(Control.PRESET_CENTER_TOP)
	brand.offset_top = 36
	brand.offset_bottom = 80
	brand.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	brand.grow_horizontal = Control.GROW_DIRECTION_BOTH
	add_child(brand)

	var sub := Label.new()
	sub.text = "童年波波攒 · 1v1 指令对战"
	sub.add_theme_font_size_override("font_size", 14)
	sub.add_theme_color_override("font_color", UiTheme.INK_SOFT)
	sub.set_anchors_preset(Control.PRESET_CENTER_TOP)
	sub.offset_top = 82
	sub.offset_bottom = 108
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.grow_horizontal = Control.GROW_DIRECTION_BOTH
	add_child(sub)

	_page_home = _build_home_page()
	_page_net = _build_net_page()
	add_child(_page_home)
	add_child(_page_net)
	_page_net.visible = false


func _build_home_page() -> Control:
	var page := Control.new()
	page.name = "PageHome"
	page.set_anchors_preset(Control.PRESET_FULL_RECT)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.add_theme_constant_override("separation", 16)
	page.add_child(box)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 24)
	box.add_child(spacer)

	var solo := _mode_card("单人对战", UiTheme.ACCENT)
	solo.pressed.connect(_on_single)
	box.add_child(solo)

	var net := _mode_card("联机对战", UiTheme.SHIELD)
	net.pressed.connect(func(): _show_page(true))
	box.add_child(net)

	var quit := UiTheme.make_btn("退出游戏", UiTheme.DANGER, Color.WHITE, 15, 44)
	quit.pressed.connect(_on_quit)
	box.add_child(quit)

	return page


func _mode_card(title: String, accent: Color) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, 96)
	b.add_theme_font_size_override("font_size", 22)
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	var sb := UiTheme.button_style(accent, 18)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 14
	sb.content_margin_bottom = 14
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", UiTheme.button_style(accent.lightened(0.08), 18))
	b.add_theme_stylebox_override("pressed", UiTheme.button_style(accent.darkened(0.1), 18))
	b.text = title
	return b


func _build_net_page() -> Control:
	var page := Control.new()
	page.name = "PageNet"
	page.set_anchors_preset(Control.PRESET_FULL_RECT)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 130)
	margin.add_theme_constant_override("margin_bottom", 16)
	page.add_child(margin)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)

	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 12)
	scroll.add_child(v)

	var back := UiTheme.make_btn("← 返回", UiTheme.LINE, UiTheme.INK, 15, 42)
	back.pressed.connect(func(): _show_page(false))
	v.add_child(back)

	var info_card := PanelContainer.new()
	info_card.add_theme_stylebox_override("panel", UiTheme.card_style())
	v.add_child(info_card)
	var info_box := VBoxContainer.new()
	info_box.add_theme_constant_override("separation", 6)
	info_card.add_child(info_box)
	_host_info = UiTheme.ink_label("本机 IP：检测中…", 13, UiTheme.INK_SOFT)
	_host_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_box.add_child(_host_info)

	v.add_child(UiTheme.ink_label("创建房间", 18, UiTheme.INK))

	var room_row := HBoxContainer.new()
	room_row.add_theme_constant_override("separation", 8)
	v.add_child(room_row)
	room_row.add_child(UiTheme.ink_label("房间名", 13, UiTheme.INK_SOFT))
	_room_edit = LineEdit.new()
	_room_edit.text = "xiongxiong-room"
	_room_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_room_edit.custom_minimum_size.y = 42
	_room_edit.add_theme_font_size_override("font_size", 14)
	room_row.add_child(_room_edit)

	var token_row := HBoxContainer.new()
	token_row.add_theme_constant_override("separation", 8)
	v.add_child(token_row)
	token_row.add_child(UiTheme.ink_label("Token", 13, UiTheme.INK_SOFT))
	_token_edit = LineEdit.new()
	_token_edit.placeholder_text = "可选"
	_token_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_token_edit.custom_minimum_size.y = 42
	_token_edit.add_theme_font_size_override("font_size", 14)
	token_row.add_child(_token_edit)

	var host_btn := UiTheme.make_btn("创建房间（等待对手）", UiTheme.ACCENT, Color.WHITE, 17, 50)
	host_btn.pressed.connect(_on_host)
	v.add_child(host_btn)

	v.add_child(UiTheme.ink_label("加入对局", 18, UiTheme.INK))

	var ip_row := HBoxContainer.new()
	ip_row.add_theme_constant_override("separation", 8)
	v.add_child(ip_row)
	ip_row.add_child(UiTheme.ink_label("对方 IP", 13, UiTheme.INK_SOFT))
	_ip_edit = LineEdit.new()
	_ip_edit.placeholder_text = "例如 192.168.1.12"
	_ip_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ip_edit.custom_minimum_size.y = 42
	_ip_edit.add_theme_font_size_override("font_size", 14)
	ip_row.add_child(_ip_edit)

	var join_btns := HBoxContainer.new()
	join_btns.add_theme_constant_override("separation", 8)
	v.add_child(join_btns)
	var join := UiTheme.make_btn("加入(IP)", UiTheme.SHIELD, Color.WHITE, 16, 48)
	join.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join.pressed.connect(_on_join)
	join_btns.add_child(join)
	var disc := UiTheme.make_btn("搜索房间", UiTheme.WAVE, Color.WHITE, 16, 48)
	disc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	disc.pressed.connect(_on_discover)
	join_btns.add_child(disc)

	_status = UiTheme.ink_label("请选择操作", 14, UiTheme.INK)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_status)

	var leave := UiTheme.make_btn("断开 / 重置", UiTheme.LINE, UiTheme.INK, 14, 42)
	leave.pressed.connect(_on_leave)
	v.add_child(leave)

	return page


func _show_page(net: bool) -> void:
	if _page_home != null:
		_page_home.visible = not net
	if _page_net != null:
		_page_net.visible = net
	if net:
		_refresh_status()


func _refresh_status() -> void:
	if _host_info == null:
		return
	var eps := Net.get_provider_endpoints()
	# 避免开局就报「没连 Wi-Fi」：延迟文案，检测到真实 IP 再显示
	var ep_text := "检测中…"
	if not eps.is_empty() and eps[0] != "127.0.0.1":
		ep_text = "、".join(eps)
	elif not eps.is_empty():
		ep_text = "、".join(eps) + "（未检测到局域网 IP，请确认 Wi-Fi）"
	_host_info.text = "本机 IP：%s  ·  对局端口 %d" % [ep_text, GAME_PORT]
	if _ip_edit != null and _ip_edit.text.strip_edges() == "" and not eps.is_empty() and eps[0] != "127.0.0.1":
		_ip_edit.placeholder_text = "例如 %s" % eps[0]


func _on_single() -> void:
	if _status != null:
		_status.text = "进入单人对战…"
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _on_host() -> void:
	_request_net_perms()
	Net.set_backend(PeerManager.Mode.ENET)
	var opts := _opts()
	opts["max_players"] = 1
	var err := Net.host_game(opts)
	if err != OK:
		var detail := ""
		if Net.provider != null and Net.provider.has_method("get_last_host_err"):
			detail = str(Net.provider.call("get_last_host_err"))
			if detail.length() > 80:
				detail = detail.substr(0, 80) + "…"
		_status.text = "建房失败：%s%s" % [error_string(err), ("（" + detail + "）") if detail != "" else ""]
		return
	var eps := Net.get_provider_endpoints()
	var p := int(opts.get("port", GAME_PORT))
	if Net.provider != null:
		var room = Net.provider.get("_room_info")
		if typeof(room) == TYPE_DICTIONARY and room.has("port"):
			p = int(room["port"])
	_status.text = "已建房 · IP：%s · 端口 %d\n等待对手加入…" % ["、".join(eps), p]


func _on_join() -> void:
	_request_net_perms()
	Net.set_backend(PeerManager.Mode.ENET)
	var opts := _opts()
	opts["address"] = _ip_edit.text.strip_edges() if _ip_edit else ""
	if str(opts["address"]) == "":
		_status.text = "请先填写对方 IP"
		return
	var err := Net.join_game(opts)
	if err != OK:
		_status.text = "加入失败：%s" % error_string(err)
		return
	_status.text = "正在连接 %s:%d…" % [opts["address"], opts["port"]]


func _on_discover() -> void:
	_request_net_perms()
	Net.set_backend(PeerManager.Mode.ENET)
	_status.text = "搜索局域网房间 5s…"
	Net.start_discover(5.0)


func _on_leave() -> void:
	Net.leave()
	_status.text = "已断开"


func _on_quit() -> void:
	UiNav.quit_game(get_tree())


func _opts() -> Dictionary:
	return {
		"mode": PeerManager.Mode.ENET,
		"port": GAME_PORT,
		"token": _token_edit.text.strip_edges() if _token_edit else "",
		"room_name": _room_edit.text.strip_edges() if _room_edit else "xiongxiong-room",
		"use_discover": true,
	}


## 联机前申权限：Android 13+ NEARBY_WIFI_DEVICES；旧机型定位（Wi-Fi 发现）。
func _request_net_perms() -> void:
	if OS.get_name() != "Android":
		return
	for p in [
		"android.permission.NEARBY_WIFI_DEVICES",
		"android.permission.ACCESS_FINE_LOCATION",
		"android.permission.ACCESS_COARSE_LOCATION",
	]:
		if OS.get_granted_permissions().has(p):
			continue
		OS.request_permission(p)


func _goto_battle() -> void:
	get_tree().change_scene_to_file("res://scenes/net_battle.tscn")

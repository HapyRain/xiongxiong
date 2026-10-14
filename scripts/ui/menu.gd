## menu.gd
## 两页首页：主页（单人 / 联机）→ 联机页（建房 / 加入 / 搜索）。
## 统一 UiTheme 字体与色板；联机页暂不展示房间名 / Token。
extends Control

const GAME_PORT := 47001
const ROOM_NAME := "xiongxiong-room"

var _page_home: Control
var _page_net: Control
var _status: Label
var _host_info: Label
var _ip_edit: LineEdit
var _dialog_layer: Control


func _ready() -> void:
	UiTheme.apply_to_tree(get_tree())
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
			_status.text = "对方已连接，等待确认…")
	Net.join_requested.connect(func(_id, _profile): _show_accept_dialog())
	Net.battle_started.connect(func(_snap: Dictionary): _goto_battle(), CONNECT_ONE_SHOT)
	Net.room_found.connect(func(info: Dictionary): _show_join_room_dialog(info))
	_refresh_status()


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = UiTheme.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	_page_home = _build_home_page()
	_page_net = _build_net_page()
	add_child(_page_home)
	add_child(_page_net)
	_page_net.visible = false


# ---------- 通用 ----------

func _title(text: String, size: int, color: Color, top: float) -> Label:
	var lab := UiTheme.ink_label(text, size, color)
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lab.set_anchors_preset(Control.PRESET_CENTER_TOP)
	lab.offset_top = top
	lab.offset_bottom = top + size + 16
	lab.grow_horizontal = Control.GROW_DIRECTION_BOTH
	lab.add_theme_font_override("font", UiTheme.default_font())
	return lab


func _section(text: String) -> Label:
	return UiTheme.ink_label(text, 16, UiTheme.INK_SOFT)


func _field(label_text: String, edit: LineEdit) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var lab := UiTheme.ink_label(label_text, 13, UiTheme.INK_SOFT)
	lab.custom_minimum_size.x = 56
	row.add_child(lab)
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.custom_minimum_size.y = 44
	edit.add_theme_font_size_override("font_size", 15)
	edit.add_theme_font_override("font", UiTheme.default_font())
	row.add_child(edit)
	return row


# ---------- 主页 ----------

func _build_home_page() -> Control:
	var page := Control.new()
	page.name = "PageHome"
	page.set_anchors_preset(Control.PRESET_FULL_RECT)

	page.add_child(_title("拍拍熊熊", 36, UiTheme.INK, 72))
	page.add_child(_title("1v1 指令对战", 14, UiTheme.INK_SOFT, 124))

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.custom_minimum_size = Vector2(300, 0)
	box.add_theme_constant_override("separation", 18)
	page.add_child(box)

	box.add_child(_mode_card("单人对战", UiTheme.ACCENT, _on_single))
	box.add_child(_mode_card("联机对战", UiTheme.SHIELD, func(): _show_page(true)))

	var quit := UiTheme.make_btn("退出游戏", UiTheme.DANGER, Color.WHITE, 15, 46)
	quit.pressed.connect(_on_quit)
	box.add_child(quit)

	return page


func _mode_card(title: String, accent: Color, cb: Callable) -> Button:
	var b := Button.new()
	b.text = title
	b.custom_minimum_size = Vector2(0, 88)
	b.add_theme_font_override("font", UiTheme.default_font())
	b.add_theme_font_size_override("font_size", 22)
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_stylebox_override("normal", UiTheme.button_style(accent, 20))
	b.add_theme_stylebox_override("hover", UiTheme.button_style(accent.lightened(0.08), 20))
	b.add_theme_stylebox_override("pressed", UiTheme.button_style(accent.darkened(0.1), 20))
	b.pressed.connect(cb)
	BattleFx.bind_press(b, "zan" if accent == UiTheme.ACCENT else "fang")
	return b


# ---------- 联机页 ----------

func _build_net_page() -> Control:
	var page := Control.new()
	page.name = "PageNet"
	page.set_anchors_preset(Control.PRESET_FULL_RECT)

	page.add_child(_title("联机对战", 22, UiTheme.INK, 48))

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 96)
	margin.add_theme_constant_override("margin_bottom", 16)
	page.add_child(margin)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)

	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 14)
	scroll.add_child(v)

	var back := UiTheme.make_btn("返回", UiTheme.LINE, UiTheme.INK, 15, 42)
	back.pressed.connect(func(): _show_page(false))
	v.add_child(back)

	# 网络引导（不展示手机 IP，冗余且易抄成蜂窝地址）
	var info := PanelContainer.new()
	info.add_theme_stylebox_override("panel", UiTheme.card_style())
	v.add_child(info)
	_host_info = UiTheme.ink_label("请双方连接同一 Wi-Fi，或一人开热点另一人加入\n再创建 / 搜索房间", 13, UiTheme.INK_SOFT)
	_host_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(_host_info)

	# 创建
	v.add_child(_section("创建房间"))
	var host_btn := UiTheme.make_btn("创建房间", UiTheme.ACCENT, Color.WHITE, 17, 52)
	host_btn.pressed.connect(_on_host)
	v.add_child(host_btn)

	# 加入
	v.add_child(_section("加入对局"))
	_ip_edit = LineEdit.new()
	_ip_edit.placeholder_text = "对方 IP，例如 192.168.1.12"
	v.add_child(_field("对方 IP", _ip_edit))

	var join_btns := HBoxContainer.new()
	join_btns.add_theme_constant_override("separation", 10)
	join_btns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(join_btns)

	var join := UiTheme.make_btn("加入", UiTheme.SHIELD, Color.WHITE, 16, 48)
	join.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join.pressed.connect(_on_join)
	BattleFx.bind_press(join, "fang")
	join_btns.add_child(join)

	var disc := UiTheme.make_btn("搜索房间", UiTheme.WAVE, Color.WHITE, 16, 48)
	disc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	disc.pressed.connect(_on_discover)
	BattleFx.bind_press(disc, "bo")
	join_btns.add_child(disc)

	_status = UiTheme.ink_label("请选择操作", 13, UiTheme.INK_SOFT)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size.y = 40
	v.add_child(_status)

	var leave := UiTheme.make_btn("断开连接", UiTheme.LINE, UiTheme.INK_SOFT, 14, 42)
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
	# 不展示 IP：手机双网卡（蜂窝+Wi-Fi）容易抄错；引导共网即可
	var wifis := PackedStringArray()
	if Net != null and Net.provider != null and Net.provider.has_method("get_wifi_ipv4s"):
		wifis = Net.provider.call("get_wifi_ipv4s")
	if wifis.is_empty():
		_host_info.text = "未检测到 Wi-Fi 局域网\n请连接同一 Wi-Fi，或开热点后创建 / 搜索"
	else:
		_host_info.text = "已连接 Wi-Fi 局域网\n双方同一网络后即可创建 / 搜索"
	if _ip_edit != null:
		_ip_edit.placeholder_text = "对方 IP（连接后由搜索结果带出）"


func _on_single() -> void:
	if _status != null:
		_status.text = "进入单人对战…"
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _on_host() -> void:
	_request_net_perms()
	Net.set_backend(PeerManager.Mode.ENET)
	var err := Net.host_game(_opts())
	if err != OK:
		var detail := ""
		if Net.provider != null and Net.provider.has_method("get_last_host_err"):
			detail = str(Net.provider.call("get_last_host_err"))
			if detail.length() > 60:
				detail = detail.substr(0, 60) + "…"
		_status.text = "建房失败：%s%s" % [error_string(err), ("（" + detail + "）") if detail != "" else ""]
		return
	var eps := PackedStringArray()
	if Net.provider != null and Net.provider.has_method("get_wifi_ipv4s"):
		eps = Net.provider.call("get_wifi_ipv4s")
	var p := GAME_PORT
	if Net.provider != null:
		var room = Net.provider.get("_room_info")
		if typeof(room) == TYPE_DICTIONARY and room.has("port"):
			p = int(room["port"])
	if eps.is_empty():
		_status.text = "已建房（端口 %d）\n未检测到 Wi-Fi，请开热点或连同一 Wi-Fi\n等待对手加入…" % p
	else:
		_status.text = "已建房（端口 %d）\n对方在「搜索房间」里选本机即可加入\n等待对手…" % p


func _on_join(override_port: int = -1) -> void:
	_request_net_perms()
	Net.set_backend(PeerManager.Mode.ENET)
	var opts := _opts()
	if override_port > 0:
		opts["port"] = override_port
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
		"token": "",
		"room_name": ROOM_NAME,
		"use_discover": true,
	}


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


# ---------- 确认框：点选加入 / 房主接受 ----------

func _ask(title: String, body: String, yes_text: String, no_text: String, cb: Callable) -> void:
	if _dialog_layer != null and is_instance_valid(_dialog_layer):
		_dialog_layer.queue_free()
	_dialog_layer = Control.new()
	_dialog_layer.name = "AskDialog"
	_dialog_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dialog_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_dialog_layer)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dialog_layer.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dialog_layer.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(300, 0)
	panel.add_theme_stylebox_override("panel", UiTheme.card_style())
	center.add_child(panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	panel.add_child(v)

	v.add_child(UiTheme.ink_label(title, 18, UiTheme.INK))
	var lab := UiTheme.ink_label(body, 13, UiTheme.INK_SOFT)
	lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lab.custom_minimum_size = Vector2(260, 36)
	v.add_child(lab)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(row)

	var yes := UiTheme.make_btn(yes_text, UiTheme.ACCENT, Color.WHITE, 15, 42)
	yes.custom_minimum_size.x = 110
	yes.pressed.connect(func():
		_close_ask()
		cb.call(true))
	row.add_child(yes)

	var no := UiTheme.make_btn(no_text, UiTheme.LINE, UiTheme.INK, 15, 42)
	no.custom_minimum_size.x = 110
	no.pressed.connect(func():
		_close_ask()
		cb.call(false))
	row.add_child(no)


func _close_ask() -> void:
	if _dialog_layer != null and is_instance_valid(_dialog_layer):
		_dialog_layer.queue_free()
	_dialog_layer = null


func _show_join_room_dialog(info: Dictionary) -> void:
	var addr := str(info.get("address", "?"))
	var pname := str(info.get("room_name", "?"))
	var port := int(info.get("port", GAME_PORT))
	# 0.5s 重发会重复 announce，同房只弹一次
	if _dialog_layer != null and is_instance_valid(_dialog_layer):
		return
	if _status != null:
		_status.text = "发现房间：%s" % pname
	_ask("加入房间？", "是否加入「%s」？\n地址 %s" % [pname, addr], "加入", "取消", func(ok: bool):
		if not ok:
			return
		if _ip_edit != null:
			_ip_edit.text = addr
		_on_join(port))


func _show_accept_dialog() -> void:
	_ask("接受对战？", "对方已申请加入，是否接受并开启对战？", "接受开战", "拒绝", func(ok: bool):
		if ok:
			Net.accept_join()
		else:
			Net.reject_join())

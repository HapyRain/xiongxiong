## lobby_search.gd
## 搜索房间：搜索中 / 列表 / 空态 / 失败（未连热点、无房间、超时）+ 加入。
extends Control

const SEARCH_PATH := "res://scenes/lobby_search.tscn"
const WAIT_SCENE := "res://scenes/lobby_wait.tscn"
const NET_ENTRY_META := "xiongxiong_net_entry"
const DISCOVER_SEC := 5.0
const JOIN_TIMEOUT_SEC := 10.0
## 单屏不滚动：列表最多显示 3 个房间，其余只报数量
const MAX_ROWS := 3

var _net: PeerManager
var _rooms: Dictionary = {}
var _rows: Dictionary = {}
var _more_label: Label
var _state: String = "idle"
var _joining: bool = false
var _join_gen: int = 0
var _search_gen: int = 0
var _banner: Control
var _state_label: Label
var _list: VBoxContainer
var _status: Label


func _ready() -> void:
	UiTheme.apply_to_tree(get_tree())
	UiNav.cleanup_overlays(get_tree())
	UiNav.register_back_target(SEARCH_PATH, UiNav.MENU_SCENE, true)
	UiNav.register_back_guard(SEARCH_PATH, _on_back_requested)
	add_child(UiBackRouter.new())
	_net = UiNav.net() as PeerManager
	_build_ui()
	if _net != null:
		_net.room_found.connect(_on_room_found)
		_net.join_answered.connect(_on_join_answered)
		_net.lobby_left.connect(_on_lobby_left)
	_start_search()


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = UiTheme.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var title := UiTheme.ink_label("搜索房间", 24, UiTheme.INK)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title.offset_top = 44
	title.grow_horizontal = Control.GROW_DIRECTION_BOTH
	add_child(title)

	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 88)
	margin.add_theme_constant_override("margin_bottom", 16)
	add_child(margin)

	var v := VBoxContainer.new()
	v.name = "Content"
	v.add_theme_constant_override("separation", 12)
	margin.add_child(v)

	_banner = UiTheme.banner_card("📡 局域网雷达", "自动扫描同一 Wi-Fi / 热点下的对战房间", UiTheme.SHIELD, 88)
	v.add_child(_banner)

	_state_label = UiTheme.ink_label("正在搜索局域网房间…", 15, UiTheme.INK_SOFT)
	_state_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_state_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_state_label)

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 8)
	v.add_child(_list)

	_status = UiTheme.ink_label("", 13, UiTheme.INK_FAINT)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size.y = 36
	v.add_child(_status)

	var rescan := UiTheme.make_btn("重新搜索", UiTheme.WAVE, Color.WHITE, 16, 48)
	rescan.pressed.connect(_start_search)
	BattleFx.bind_press(rescan, "bo")
	v.add_child(rescan)

	var back := UiTheme.make_btn("返回", UiTheme.BG_CARD, UiTheme.INK, 15, 42)
	back.pressed.connect(_back)
	v.add_child(back)


func _start_search() -> void:
	if _net == null:
		return
	_joining = false
	if _net.get_session() != PeerManager.Session.IDLE:
		_net.leave()
	if _net.provider == null or _net.get_mode() != PeerManager.Mode.ENET:
		var err := _net.set_backend(PeerManager.Mode.ENET)
		if err != OK:
			_set_state("fail", "无法启动联机：%s" % error_string(err))
			return
	var wifis := PackedStringArray()
	if _net.provider != null and _net.provider.has_method("get_wifi_ipv4s"):
		wifis = _net.provider.call("get_wifi_ipv4s")
	if wifis.is_empty():
		_set_state("fail", "未检测到热点 / Wi-Fi，请先连同一网络")
		return
	var err2 := _net.start_discover(DISCOVER_SEC)
	if err2 != OK:
		_set_state("fail", "当前网络不支持搜索（%s）" % error_string(err2))
		return
	_rooms.clear()
	_clear_room_rows()
	_render_rooms()
	_set_state("searching", "正在搜索局域网房间…")
	_search_gen += 1
	var gen := _search_gen
	get_tree().create_timer(DISCOVER_SEC + 0.5).timeout.connect(_on_search_timeout.bind(gen))


func _on_room_found(info: Dictionary) -> void:
	var addr := str(info.get("address", "?"))
	var port := int(info.get("port", 47001))
	var key := "%s:%d" % [addr, port]
	var same_key := _rows.has(key)
	_rooms[key] = info
	if _state == "searching" or _state == "empty" or _state == "list":
		_set_state("list", "发现 %d 个房间" % _rooms.size())
		if same_key:
			_update_room_row(_rows[key], info)
		else:
			_render_rooms()


func _on_search_timeout(gen: int) -> void:
	if not is_inside_tree() or gen != _search_gen or _state != "searching" or _joining:
		return
	if _rooms.is_empty():
		_set_state("empty", "没有找到房间，确认对手已创建房间")
	else:
		_set_state("list", "发现 %d 个房间" % _rooms.size())
		_render_rooms()


func _set_state(state: String, text: String) -> void:
	_state = state
	if _state_label != null:
		_state_label.text = text


func _clear_room_rows() -> void:
	if _list == null:
		return
	for key in _rows.keys():
		var row: Control = _rows[key]
		if is_instance_valid(row):
			_list.remove_child(row)
			row.queue_free()
	_rows.clear()
	if _more_label != null and is_instance_valid(_more_label):
		_more_label.queue_free()
		_more_label = null


func _render_rooms() -> void:
	if _list == null:
		return
	var keys := _rooms.keys()
	var shown := mini(keys.size(), MAX_ROWS)
	for i in shown:
		var key := str(keys[i])
		if _rows.has(key):
			_update_room_row(_rows[key], _rooms[key])
		else:
			var panel := _room_row(key, _rooms[key])
			_list.add_child(panel)
			_rows[key] = panel
	if _more_label != null and is_instance_valid(_more_label):
		_more_label.queue_free()
		_more_label = null
	if keys.size() > MAX_ROWS:
		_more_label = UiTheme.ink_label("还有 %d 个房间" % (keys.size() - MAX_ROWS), 12, UiTheme.INK_FAINT)
		_more_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_list.add_child(_more_label)


func _room_text(info: Dictionary) -> String:
	var mode := str(info.get("mode", "lesson"))
	var tag := "经典" if mode == "classic" else "课间"
	if bool(info.get("mastery", false)):
		tag += " · 精通"
	return "%s\n%s · %d/%d 人" % [
		str(info.get("room_name", "未知房间")),
		tag,
		int(info.get("players", 1)),
		int(info.get("max_players", 2)),
	]


func _room_row(key: String, info: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.card_style())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)

	var text := UiTheme.ink_label(_room_text(info), 14, UiTheme.INK)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(text)
	panel.set_meta("text_label", text)

	var join := UiTheme.make_btn("加入", UiTheme.SHIELD, Color.WHITE, 15, 42)
	join.custom_minimum_size.x = 92
	join.pressed.connect(func(): _on_join(_rooms.get(key, info)))
	row.add_child(join)
	return panel


func _update_room_row(panel: Control, info: Dictionary) -> void:
	if not is_instance_valid(panel):
		return
	var label := panel.get_meta("text_label") as Label
	if label != null:
		label.text = _room_text(info)


func _on_join(info: Dictionary) -> void:
	if _joining or _net == null:
		return
	_joining = true
	_net.stop_discover()
	_status.text = "正在加入「%s」…" % str(info.get("room_name", "房间"))
	var err := _net.join_game({
		"mode": PeerManager.Mode.ENET,
		"address": str(info.get("address", "")),
		"port": int(info.get("port", 47001)),
		"token": str(info.get("token", "")),
	})
	if err != OK:
		_joining = false
		_status.text = "加入失败：%s" % error_string(err)
		return
	_join_gen += 1
	var gen := _join_gen
	get_tree().create_timer(JOIN_TIMEOUT_SEC).timeout.connect(_on_join_timeout.bind(gen))


func _on_join_timeout(gen: int) -> void:
	if not is_inside_tree() or gen != _join_gen or not _joining:
		return
	_joining = false
	_status.text = "加入超时，房主未回应，请重新选择房间"
	_set_state("list" if not _rooms.is_empty() else "empty",
		"发现 %d 个房间" % _rooms.size() if not _rooms.is_empty() else "没有找到房间")


func _on_join_answered(yes: bool) -> void:
	if not _joining:
		return
	if yes:
		get_tree().change_scene_to_file(WAIT_SCENE)
		return
	_joining = false
	_status.text = "房主未接受，请重新选择房间"
	_set_state("list" if not _rooms.is_empty() else "empty",
		"发现 %d 个房间" % _rooms.size() if not _rooms.is_empty() else "没有找到房间")


func _on_lobby_left(reason: String) -> void:
	_joining = false
	_status.text = reason


func _back() -> void:
	if _net != null:
		_net.stop_discover()
		if _net.get_session() != PeerManager.Session.IDLE:
			_net.leave()
	Engine.set_meta(NET_ENTRY_META, true)
	UiNav.cleanup_overlays(get_tree())
	get_tree().change_scene_to_file(UiNav.MENU_SCENE)


func _on_back_requested() -> bool:
	_back()
	return true

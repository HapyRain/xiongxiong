## lobby_wait.gd
## 1080P (1080×1920) 等待页：双座位 + 准备 + 5s 倒计时 + 离开；房主收到加入请求弹单确认框。
extends Control

const WAIT_PATH := "res://scenes/lobby_wait.tscn"
const NET_ENTRY_META := "xiongxiong_net_entry"

var _net: PeerManager
var _room_name: Label
var _seat_names: Array = []
var _seat_states: Array = []
var _ready_btn: Button
var _countdown: Label
var _status: Label
var _dialog: Control
var _notice: Control
var _started: bool = false


func _ready() -> void:
	UiTheme.apply_to_tree(get_tree())
	UiNav.cleanup_overlays(get_tree())
	UiNav.register_back_target(WAIT_PATH, UiNav.MENU_SCENE, true)
	UiNav.register_back_guard(WAIT_PATH, _on_back_requested)
	add_child(UiBackRouter.new())
	_net = UiNav.net() as PeerManager
	_build_ui()
	if _net != null:
		_net.room_updated.connect(_on_room_updated)
		_net.ready_changed.connect(_on_ready_changed)
		_net.lobby_countdown_tick.connect(_on_countdown)
		_net.lobby_left.connect(_on_lobby_left)
		_net.join_requested.connect(_on_join_requested)
		_net.battle_started.connect(_on_battle_started)
		_net.session_changed.connect(_on_session_changed)
	_refresh()


func _on_room_updated(_r: Dictionary) -> void:
	_refresh()


func _on_ready_changed(_h: bool, _c: bool) -> void:
	_refresh()


func _on_session_changed(_s: int) -> void:
	_refresh()


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = UiTheme.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	UiTheme.add_stage_background(self, 0.35)

	var title := UiTheme.ink_label("等待对局", 56, Color(1.0, 0.94, 0.70), 10, UiTheme.INK)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title.offset_top = 80
	title.grow_horizontal = Control.GROW_DIRECTION_BOTH
	add_child(title)

	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 44)
	margin.add_theme_constant_override("margin_right", 44)
	margin.add_theme_constant_override("margin_top", 180)
	margin.add_theme_constant_override("margin_bottom", 36)
	add_child(margin)

	var v := VBoxContainer.new()
	v.name = "Content"
	v.add_theme_constant_override("separation", 24)
	margin.add_child(v)

	_room_name = UiTheme.ink_label("", 28, Color.WHITE, 5, UiTheme.INK)
	_room_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_room_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_room_name)

	v.add_child(UiTheme.banner_card("1v1 对决台", "双方点击「准备」后 5 秒倒计时开局", UiTheme.SHIELD, 200))

	var seats := HBoxContainer.new()
	seats.add_theme_constant_override("separation", 24)
	seats.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(seats)
	for i in 2:
		var panel := PanelContainer.new()
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		panel.add_theme_stylebox_override("panel", UiTheme.card_style())
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 12)
		var name_lab := UiTheme.ink_label("", 36, UiTheme.INK)
		name_lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var state_lab := UiTheme.ink_label("", 26, UiTheme.INK_SOFT)
		box.add_child(name_lab)
		box.add_child(state_lab)
		panel.add_child(box)
		seats.add_child(panel)
		_seat_names.append(name_lab)
		_seat_states.append(state_lab)

	_countdown = UiTheme.ink_label("等待双方准备", 34, Color(1.0, 0.94, 0.70), 6, UiTheme.INK)
	_countdown.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_countdown)

	_ready_btn = UiTheme.make_btn("准备", UiTheme.SHIELD, Color.WHITE, 40, 124)
	_ready_btn.pressed.connect(_on_ready_pressed)
	BattleFx.bind_press(_ready_btn, "fang")
	v.add_child(_ready_btn)

	_status = UiTheme.ink_label("", 26, Color.WHITE, 4, UiTheme.INK)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size.y = 72
	v.add_child(_status)

	var leave := UiTheme.make_btn("离开房间", UiTheme.BG_CARD, UiTheme.INK, 34, 102)
	leave.pressed.connect(_on_leave)
	v.add_child(leave)


func _refresh() -> void:
	if _net == null or _seat_names.is_empty():
		return
	var r := _net.get_room()
	var flags := _net.get_ready_flags()
	var host_ready := bool(flags[0])
	var client_ready := bool(flags[1])
	var host_name := str(r.get("host_name", ""))
	var mode := str(r.get("mode", "lesson"))
	var tag := "经典" if mode == "classic" else "课间"
	if bool(r.get("mastery", false)):
		tag += " · 精通"
	_room_name.text = "%s\n%s" % [str(r.get("name", "房间")), tag]
	if host_name != "":
		_room_name.text += " · " + host_name

	var me_seat := 0 if _net.is_host() else 1
	_seat_names[me_seat].text = "我"
	_seat_names[1 - me_seat].text = "对手"
	_seat_states[0].text = "已入座" + (" · 已准备" if host_ready else "")
	var client_sitting := not _net.is_host() or _net.get_session() != PeerManager.Session.LOBBY
	if client_sitting:
		_seat_states[1].text = "已入座" + (" · 已准备" if client_ready else "")
	else:
		_seat_states[1].text = "空座"

	var counting := _net.get_session() == PeerManager.Session.COUNTDOWN
	if not counting and _countdown != null and _net.get_lobby_countdown_ms() <= 0:
		_countdown.text = "双方准备后 5 秒开局" if not (host_ready and client_ready) else "即将开局"
	if _ready_btn != null:
		_ready_btn.text = "取消准备" if _local_ready() else "准备"
		var sess := _net.get_session()
		_ready_btn.disabled = sess != PeerManager.Session.LOBBY \
			and sess != PeerManager.Session.READY_CHECK
	_ready_btn.add_theme_stylebox_override("normal",
		UiTheme.button_style(UiTheme.BG_CARD if _local_ready() else UiTheme.SHIELD, 24, UiTheme.INK, 4, 8))
	_ready_btn.add_theme_color_override("font_color",
		UiTheme.INK if _local_ready() else Color.WHITE)


func _local_ready() -> bool:
	var flags := _net.get_ready_flags()
	return bool(flags[0]) if _net.is_host() else bool(flags[1])


func _on_ready_pressed() -> void:
	if _net == null:
		return
	_net.set_ready(not _local_ready())
	_refresh()


func _on_countdown(remain_ms: int) -> void:
	if _countdown == null:
		return
	if remain_ms > 0:
		_countdown.text = "%d 秒后开局" % maxi(1, int(ceil(remain_ms / 1000.0)))
	else:
		_countdown.text = "开局中…"
	_refresh()


func _on_battle_started(_snap: Dictionary) -> void:
	if _started:
		return
	_started = true
	get_tree().change_scene_to_file("res://scenes/net_battle.tscn")


func _on_leave() -> void:
	if _net != null:
		_net.leave_room()
	_back_to_entry()


func _on_back_requested() -> bool:
	_on_leave()
	return true


func _on_join_requested(_id: int, _profile: Dictionary) -> void:
	if _dialog != null and is_instance_valid(_dialog):
		if _net != null:
			_net.reject_join()
		return
	_show_join_dialog()


func _show_join_dialog() -> void:
	if _dialog != null and is_instance_valid(_dialog):
		return
	_dialog = _modal("同意对战？", "有玩家申请加入房间，是否同意？", "同意", "拒绝", func(yes: bool):
		_close_dialog()
		if _net == null:
			return
		if yes:
			_net.accept_join()
		else:
			_net.reject_join()
		_refresh())


func _close_dialog() -> void:
	if _dialog != null and is_instance_valid(_dialog):
		_dialog.queue_free()
	_dialog = null


func _on_lobby_left(reason: String) -> void:
	if _notice != null and is_instance_valid(_notice):
		return
	_notice = _modal("房间已关闭", reason, "返回入口", "", func(_yes: bool):
		_back_to_entry())


func _modal(title: String, body: String, yes_text: String, no_text: String, cb: Callable) -> Control:
	var layer := Control.new()
	layer.name = "LobbyModal"
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(layer)

	var dim := ColorRect.new()
	dim.color = Color(0.04, 0.06, 0.12, 0.62)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(760, 0)
	panel.add_theme_stylebox_override("panel", UiTheme.card_style())
	center.add_child(panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 24)
	panel.add_child(v)

	v.add_child(UiTheme.ink_label(title, 40, UiTheme.INK))
	var body_label := UiTheme.ink_label(body, 28, UiTheme.INK_SOFT)
	body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body_label.custom_minimum_size = Vector2(680, 84)
	v.add_child(body_label)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 28)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(row)

	var yes := UiTheme.make_btn(yes_text, UiTheme.ACCENT, Color.WHITE, 34, 96)
	yes.custom_minimum_size.x = 280
	yes.pressed.connect(func(): cb.call(true))
	row.add_child(yes)

	if no_text != "":
		var no := UiTheme.make_btn(no_text, UiTheme.BG_CARD, UiTheme.INK, 34, 96)
		no.custom_minimum_size.x = 280
		no.pressed.connect(func(): cb.call(false))
		row.add_child(no)

	return layer


func _back_to_entry() -> void:
	Engine.set_meta(NET_ENTRY_META, true)
	UiNav.cleanup_overlays(get_tree())
	get_tree().change_scene_to_file(UiNav.MENU_SCENE)

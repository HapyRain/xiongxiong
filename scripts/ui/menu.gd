## menu.gd
## Splash overlay（占位加载）→ 主菜单（单人 / 联机 / 设置 / 退出）→ 联机入口（作为房主 / 搜索房间）。
## 房间/等待页在 lobby_*.tscn；本文件只做入口与跳转。
extends Control

const MENU_SCENE := "res://scenes/menu.tscn"
const SOLO_SCENE := "res://scenes/solo_select.tscn"
const CREATE_SCENE := "res://scenes/lobby_create.tscn"
const SEARCH_SCENE := "res://scenes/lobby_search.tscn"
const SETTINGS_SCENE := "res://scenes/settings_panel.tscn"
## 回入口：设置后 menu._ready 直接打开联机页（离开房间 → 回「作为房主/搜索」）。
const NET_ENTRY_META := "xiongxiong_net_entry"
## Splash 只在本次进程首次进菜单时显示；从对局/等待页回来不再弹。
const SPLASH_SEEN_META := "xiongxiong_splash_seen"

var _page_home: Control
var _page_net: Control
var _splash: Control
var _splash_enter: Button
var _splash_status: Label
var _status: Label
var _host_info: Label


func _ready() -> void:
	UiTheme.apply_to_tree(get_tree())
	# 从对局返回时清掉可能残留的聚光灯/设置层
	UiNav.cleanup_overlays(get_tree())
	if Net != null and Net.get_session() != PeerManager.Session.IDLE:
		Net.leave()
	_build_ui()
	Net.mode_changed.connect(func(_m): _refresh_status())
	Net.session_changed.connect(func(_s): _refresh_status())
	Net.status_text.connect(func(t: String):
		if _status != null:
			_status.text = t)
	_refresh_status()
	var entry := bool(Engine.get_meta(NET_ENTRY_META, false))
	Engine.set_meta(NET_ENTRY_META, false)
	_show_page(entry)


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
	_build_splash()


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


# ---------- Splash（占位加载） ----------

func _build_splash() -> void:
	if bool(Engine.get_meta(SPLASH_SEEN_META, false)):
		return
	Engine.set_meta(SPLASH_SEEN_META, true)
	_splash = Control.new()
	_splash.name = "SplashOverlay"
	_splash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_splash.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_splash)

	var bg := ColorRect.new()
	bg.color = UiTheme.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_splash.add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_splash.add_child(center)

	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(300, 0)
	v.add_theme_constant_override("separation", 16)
	center.add_child(v)

	var title := UiTheme.ink_label("拍拍熊熊", 34, UiTheme.INK)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	v.add_child(UiPlaceholder.block("加载动画", Vector2(280, 220)))

	_splash_status = UiTheme.ink_label("", 13, UiTheme.INK_SOFT)
	_splash_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_splash_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_splash_status)

	_splash_enter = UiTheme.make_btn("进入游戏", UiTheme.ACCENT, Color.WHITE, 20, 56)
	_splash_enter.pressed.connect(func():
		if _splash != null:
			_splash.visible = false)
	BattleFx.bind_press(_splash_enter, "zan")
	v.add_child(_splash_enter)

	# 没有异步加载管线：资源同步就绪即显示入口；以后接真加载再换成 await。
	# shortcut: 假设资源已同步就绪，接异步加载时改为进度回调再显示入口。
	var ready := _resources_ready()
	_splash_enter.visible = ready
	_splash_status.text = "资源已就绪" if ready else "【占位】资源未就绪"


func _resources_ready() -> bool:
	return ResourceLoader.exists(MENU_SCENE) \
		and ResourceLoader.exists("res://scenes/main.tscn") \
		and ResourceLoader.exists("res://scenes/net_battle.tscn")


# ---------- 主页 ----------

func _build_home_page() -> Control:
	var page := Control.new()
	page.name = "PageHome"
	page.set_anchors_preset(Control.PRESET_FULL_RECT)

	page.add_child(_title("拍拍熊熊", 36, UiTheme.INK, 72))
	page.add_child(_title("1v1 三分钟一局超爽超解压", 14, UiTheme.INK_SOFT, 124))

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.custom_minimum_size = Vector2(300, 0)
	box.add_theme_constant_override("separation", 16)
	page.add_child(box)

	box.add_child(_mode_card("单人模式", UiTheme.ACCENT, _on_single))
	box.add_child(_mode_card("联机对战", UiTheme.SHIELD, func(): _show_page(true)))

	var settings := UiTheme.make_btn("设置", UiTheme.LINE, UiTheme.INK, 16, 48)
	settings.pressed.connect(_on_settings)
	box.add_child(settings)

	var quit := UiTheme.make_btn("退出游戏", UiTheme.DANGER, Color.WHITE, 15, 46)
	quit.pressed.connect(_on_quit)
	box.add_child(quit)

	return page


# ---------- 联机入口 ----------

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

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	margin.add_child(v)

	var info := PanelContainer.new()
	info.add_theme_stylebox_override("panel", UiTheme.card_style())
	v.add_child(info)
	_host_info = UiTheme.ink_label("请双方连接同一 Wi-Fi，或一人开热点另一人加入\n再创建 / 搜索房间", 13, UiTheme.INK_SOFT)
	_host_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(_host_info)

	v.add_child(_section("创建房间"))
	var host_btn := UiTheme.make_btn("作为房主", UiTheme.ACCENT, Color.WHITE, 18, 56)
	host_btn.pressed.connect(_on_host_entry)
	BattleFx.bind_press(host_btn, "zan")
	v.add_child(host_btn)

	v.add_child(_section("加入房间"))
	var search_btn := UiTheme.make_btn("搜索房间", UiTheme.WAVE, Color.WHITE, 18, 56)
	search_btn.pressed.connect(_on_search_entry)
	BattleFx.bind_press(search_btn, "bo")
	v.add_child(search_btn)

	_status = UiTheme.ink_label("请选择操作", 13, UiTheme.INK_SOFT)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size.y = 40
	v.add_child(_status)

	var back := UiTheme.make_btn("返回", UiTheme.LINE, UiTheme.INK, 15, 42)
	back.pressed.connect(func(): _show_page(false))
	v.add_child(back)

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


# ---------- 动作 ----------

func _on_single() -> void:
	if not ResourceLoader.exists(SOLO_SCENE):
		if _status != null:
			_status.text = "单人模式页面未就绪"
		return
	get_tree().change_scene_to_file(SOLO_SCENE)


func _on_settings() -> void:
	var tree := get_tree()
	if tree == null or UiNav.is_settings_open(tree):
		return
	var packed: PackedScene = load(SETTINGS_SCENE)
	if packed == null:
		return
	var overlay := packed.instantiate()
	overlay.name = "SettingsPanelOverlay"
	tree.root.add_child(overlay)


func _on_host_entry() -> void:
	_request_net_perms()
	get_tree().change_scene_to_file(CREATE_SCENE)


func _on_search_entry() -> void:
	_request_net_perms()
	get_tree().change_scene_to_file(SEARCH_SCENE)


func _on_quit() -> void:
	UiNav.quit_game(get_tree())


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

## menu.gd
## 1080P (1080×1920) Splash overlay（开屏欢迎页）→ 主菜单（单人 / 联机 / 设置 / 退出）→ 联机入口（作为房主 / 搜索房间）。
extends Control

const MENU_SCENE := "res://scenes/menu.tscn"
const SOLO_SCENE := "res://scenes/solo_select.tscn"
const CREATE_SCENE := "res://scenes/lobby_create.tscn"
const SEARCH_SCENE := "res://scenes/lobby_search.tscn"
const SETTINGS_SCENE := "res://scenes/settings_panel.tscn"
const NET_ENTRY_META := "xiongxiong_net_entry"
const SPLASH_SEEN_META := "xiongxiong_splash_seen"

var _page_home: Control
var _page_net: Control
var _splash: Control
var _splash_enter: Button
var _splash_status: Label
var _status: Label
var _home_status: Label
var _host_info: Label


func _ready() -> void:
	UiTheme.apply_to_tree(get_tree())
	UiNav.cleanup_overlays(get_tree())
	if Net != null and Net.get_session() != PeerManager.Session.IDLE:
		Net.leave()
	_build_ui()
	Net.mode_changed.connect(_on_mode_changed)
	Net.session_changed.connect(_on_session_changed)
	Net.status_text.connect(_on_net_status_text)
	_refresh_status()
	var entry := bool(Engine.get_meta(NET_ENTRY_META, false))
	Engine.set_meta(NET_ENTRY_META, false)
	_show_page(entry)


func _on_mode_changed(_m: int) -> void:
	_refresh_status()


func _on_session_changed(_s: int) -> void:
	_refresh_status()


func _on_net_status_text(t: String) -> void:
	if _status != null:
		_status.text = t


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = UiTheme.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	UiTheme.add_stage_background(self, 0.35)

	_page_home = _build_home_page()
	_page_net = _build_net_page()
	add_child(_page_home)
	add_child(_page_net)
	_page_net.visible = false
	_build_splash()


func _title(text: String, size: int, color: Color, top: float) -> Label:
	var lab := UiTheme.ink_label(text, size, color, 10, UiTheme.INK)
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lab.set_anchors_preset(Control.PRESET_CENTER_TOP)
	lab.offset_top = top
	lab.offset_bottom = top + size + 32
	lab.grow_horizontal = Control.GROW_DIRECTION_BOTH
	return lab


func _section(text: String) -> Label:
	return UiTheme.ink_label(text, 32, Color(0.92, 0.96, 1.0), 6, UiTheme.INK)


func _mode_card(title: String, accent: Color, cb: Callable) -> Button:
	var b := Button.new()
	b.text = title
	b.custom_minimum_size = Vector2(0, 176)
	b.add_theme_font_override("font", UiTheme.default_font())
	b.add_theme_font_size_override("font_size", 48)
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_constant_override("outline_size", 10)
	b.add_theme_color_override("font_outline_color", UiTheme.INK)
	b.add_theme_stylebox_override("normal", UiTheme.button_style(accent, 32, UiTheme.INK, 5, 12))
	b.add_theme_stylebox_override("hover", UiTheme.button_style(accent.lightened(0.08), 32, UiTheme.INK, 5, 12))
	b.add_theme_stylebox_override("pressed", UiTheme.button_style(accent.darkened(0.10), 32, UiTheme.INK, 5, 4))
	b.pressed.connect(cb)
	BattleFx.bind_press(b, "zan" if accent == UiTheme.ACCENT else "fang")
	return b


# ---------- Splash（开屏欢迎层） ----------

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
	UiTheme.add_stage_background(_splash, 0.25)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_splash.add_child(center)

	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(820, 0)
	v.add_theme_constant_override("separation", 36)
	center.add_child(v)

	var title := UiTheme.ink_label("拍拍熊熊", 88, Color(1.0, 0.94, 0.70), 14, UiTheme.INK)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	v.add_child(UiTheme.banner_card("课间对决 · 致敬童年", "攒气 · 防御 · 包子 · 破防\n两拍定胜负，读招见真章", UiTheme.ACCENT, 300))

	_splash_status = UiTheme.ink_label("", 28, Color.WHITE, 5, UiTheme.INK)
	_splash_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_splash_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_splash_status)

	_splash_enter = UiTheme.make_btn("进入游戏", UiTheme.ACCENT, Color.WHITE, 44, 128)
	_splash_enter.pressed.connect(_on_splash_button)
	BattleFx.bind_press(_splash_enter, "zan")
	v.add_child(_splash_enter)

	_set_splash_state(_resources_ready())


func _set_splash_state(ready: bool) -> void:
	if _splash_enter == null:
		return
	_splash_enter.visible = true
	_splash_enter.text = "进入游戏" if ready else "重试"
	if _splash_status != null:
		_splash_status.text = "资源已就绪" if ready else "资源未就绪，点「重试」"


func _on_splash_button() -> void:
	if _resources_ready():
		if _splash != null:
			_splash.visible = false
	else:
		_set_splash_state(false)


func _resources_ready() -> bool:
	return ResourceLoader.exists(MENU_SCENE) \
		and ResourceLoader.exists("res://scenes/main.tscn") \
		and ResourceLoader.exists("res://scenes/net_battle.tscn")


# ---------- 主页 ----------

func _build_home_page() -> Control:
	var page := Control.new()
	page.name = "PageHome"
	page.set_anchors_preset(Control.PRESET_FULL_RECT)

	page.add_child(_title("拍拍熊熊", 86, Color(1.0, 0.94, 0.70), 160))
	page.add_child(_title("1080P 三渲二同步读招对决 · 致敬童年", 30, Color(0.90, 0.95, 1.0), 280))

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.custom_minimum_size = Vector2(780, 0)
	box.add_theme_constant_override("separation", 34)
	page.add_child(box)

	box.add_child(_mode_card("单人模式", UiTheme.ACCENT, _on_single))
	box.add_child(_mode_card("联机对战", UiTheme.SHIELD, func(): _show_page(true)))

	var settings := UiTheme.make_btn("设置", UiTheme.BG_CARD, UiTheme.INK, 36, 112)
	settings.pressed.connect(_on_settings)
	box.add_child(settings)

	var quit := UiTheme.make_btn("退出游戏", UiTheme.DANGER, Color.WHITE, 34, 106)
	quit.pressed.connect(_on_quit)
	box.add_child(quit)

	_home_status = UiTheme.ink_label("", 28, UiTheme.DANGER, 5, Color.WHITE)
	_home_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_home_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_home_status.custom_minimum_size.y = 72
	box.add_child(_home_status)

	return page


# ---------- 联机入口 ----------

func _build_net_page() -> Control:
	var page := Control.new()
	page.name = "PageNet"
	page.set_anchors_preset(Control.PRESET_FULL_RECT)

	page.add_child(_title("联机对战", 60, Color(1.0, 0.94, 0.70), 110))

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 56)
	margin.add_theme_constant_override("margin_right", 56)
	margin.add_theme_constant_override("margin_top", 230)
	margin.add_theme_constant_override("margin_bottom", 48)
	page.add_child(margin)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 28)
	margin.add_child(v)

	var info := PanelContainer.new()
	info.add_theme_stylebox_override("panel", UiTheme.card_style(UiTheme.BG_CARD, 26, UiTheme.INK, 4))
	v.add_child(info)
	_host_info = UiTheme.ink_label("请双方连接同一 Wi-Fi，或一人开热点另一人加入\n再创建 / 搜索房间", 28, UiTheme.INK_SOFT)
	_host_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(_host_info)

	v.add_child(_section("创建房间"))
	var host_btn := UiTheme.make_btn("作为房主", UiTheme.ACCENT, Color.WHITE, 40, 128)
	host_btn.pressed.connect(_on_host_entry)
	BattleFx.bind_press(host_btn, "zan")
	v.add_child(host_btn)

	v.add_child(_section("加入房间"))
	var search_btn := UiTheme.make_btn("搜索房间", UiTheme.WAVE, Color.WHITE, 40, 128)
	search_btn.pressed.connect(_on_search_entry)
	BattleFx.bind_press(search_btn, "bo")
	v.add_child(search_btn)

	_status = UiTheme.ink_label("请选择操作", 28, Color.WHITE, 5, UiTheme.INK)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size.y = 84
	v.add_child(_status)

	var back := UiTheme.make_btn("返回", UiTheme.BG_CARD, UiTheme.INK, 34, 104)
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
	var wifis := PackedStringArray()
	if Net != null and Net.provider != null and Net.provider.has_method("get_wifi_ipv4s"):
		wifis = Net.provider.call("get_wifi_ipv4s")
	if wifis.is_empty():
		_host_info.text = "未检测到 Wi-Fi 局域网\n请连接同一 Wi-Fi，或开热点后创建 / 搜索"
	else:
		_host_info.text = "已连接 Wi-Fi 局域网\n双方同一网络后即可创建 / 搜索"


func _on_single() -> void:
	if not ResourceLoader.exists(SOLO_SCENE):
		_report_error("单人模式页面未就绪")
		return
	get_tree().change_scene_to_file(SOLO_SCENE)


func _report_error(msg: String) -> void:
	if _home_status != null:
		_home_status.text = msg
	if _status != null:
		_status.text = msg


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

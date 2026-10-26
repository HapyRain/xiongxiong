## run_ui_check.gd
## 第 8 个 headless 自检：占位块 / 各屏 60 帧 / 返回路由真的切场景 / Splash 只首次显示。
## 联机屏用 LocalProvider 装入 Net，避免 headless 起真实 ENet。
## 运行：
##   Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/run_ui_check.gd
extends SceneTree

const FRAMES := 60
const BACK_WAIT := 3
const MENU_PATH := "res://scenes/menu.tscn"
const SETTINGS_PATH := "res://scenes/settings_panel.tscn"

## 依次加载的屏：parent = 返回路由父级（空 = 根屏，不测返回）。
const SCREENS := [
	{"path": "res://scenes/menu.tscn", "parent": ""},
	{"path": "res://scenes/solo_select.tscn", "parent": "res://scenes/menu.tscn"},
	{"path": "res://scenes/lobby_create.tscn", "parent": "res://scenes/menu.tscn", "net": "lobby"},
	{"path": "res://scenes/lobby_search.tscn", "parent": "res://scenes/menu.tscn", "net": "lobby"},
	{"path": "res://scenes/lobby_wait.tscn", "parent": "res://scenes/menu.tscn", "net": "wait"},
	{"path": "res://scenes/main.tscn", "parent": "res://scenes/solo_select.tscn"},
	{"path": "res://scenes/net_battle.tscn", "parent": "res://scenes/menu.tscn", "net": "battle"},
]

var _ok: bool = true
var _finished: bool = false
var _phase: String = "init"
var _idx: int = 0
var _frames: int = 0
var _before_path: String = ""


func _initialize() -> void:
	print("UICHECK_START")
	_check_placeholder()
	_exp("无 current_scene：go_back 安全返回 false", UiNav.go_back(self) == false)
	_phase = "boot"


func _process(_delta: float) -> bool:
	if _finished:
		return true
	match _phase:
		"boot":
			# _initialize 里 change_scene 可能早于 root 就绪，放到首帧再换
			_load_screen()
		"screen":
			_frames += 1
			if _frames >= FRAMES:
				_check_screen()
				_after_screen()
		"back":
			_frames += 1
			if _frames >= BACK_WAIT:
				_check_back()
		"leave":
			_frames += 1
			if _frames >= BACK_WAIT:
				_check_after_confirm()
		"settings":
			_frames += 1
			if _frames >= FRAMES:
				_check_settings()
				_finish()
		_:
			_fail("unknown phase %s" % _phase)
			_finish()
	return _finished


# ---------- 屏加载 ----------

func _load_screen() -> void:
	var cfg: Dictionary = SCREENS[_idx]
	var path := str(cfg["path"])
	_prepare_net(str(cfg.get("net", "")))
	if path.ends_with("main.tscn"):
		BattleController.pending_cfg = {"mode": "classic", "mastery": false, "difficulty": "normal"}
	_frames = 0
	_phase = "screen"
	var err := change_scene_to_file(path)
	_exp("%s: change_scene_to_file" % _short(path), err == OK)


func _next_screen() -> void:
	_idx += 1
	if _idx >= SCREENS.size():
		_load_settings()
		return
	_load_screen()


## 联机屏统一注入 LocalProvider（headless 不起真实 ENet）。
func _prepare_net(kind: String) -> void:
	if kind.is_empty():
		return
	var net := root.get_node_or_null("Net") as PeerManager
	_exp("Net autoload present", net != null)
	if net == null:
		return
	if net.provider == null or net.get_mode() != PeerManager.Mode.ENET:
		net.install_provider(LocalProvider.new(), PeerManager.Mode.ENET)
	if kind == "wait" or kind == "battle":
		net.room = {
			"room_id": "ui-test",
			"name": "测试房间",
			"mode": "classic",
			"mastery": false,
			"host_name": "我",
			"players": 2,
			"max": 2,
		}
		if kind == "battle":
			net._reset_rules_state()
			net._set_session(PeerManager.Session.IN_BATTLE)
		else:
			net._set_session(PeerManager.Session.READY_CHECK)


# ---------- 每屏断言 ----------

func _check_screen() -> void:
	var cfg: Dictionary = SCREENS[_idx]
	var path := str(cfg["path"])
	var parent := str(cfg.get("parent", ""))
	var cs := current_scene
	_exp("%s: current_scene 就位" % _short(path), cs != null and is_instance_valid(cs))
	if cs == null:
		return
	_exp("%s: 场景路径正确" % _short(path), str(cs.scene_file_path) == path)
	_exp("%s: 60 帧后仍在树中" % _short(path), cs.is_inside_tree())
	_exp("%s: _ready 完成" % _short(path), cs.is_node_ready())
	if not parent.is_empty():
		_exp("%s: 已注册返回父级" % _short(path), str(UiNav.BACK_ROUTES.get(path, "")) == parent)

	var flat := _flat(cs)
	match path:
		MENU_PATH:
			_exp("menu: 单人入口", _has_button_prefix(cs, "单人"))
			_exp("menu: 联机入口", _has_button_prefix(cs, "联机"))
			_exp("menu: 设置", _has_button_prefix(cs, "设置"))
			_exp("menu: 退出游戏", _has_button_prefix(cs, "退出"))
			var splash := _find_named(cs, "SplashOverlay")
			_exp("menu: 首次进菜单显示 Splash", splash != null)
			_exp("menu: Splash 有进入游戏", _has_button_prefix(cs, "进入游戏"))
			if splash != null:
				_exp("menu: Splash 占位加载动画", _flat(splash).contains("【占位】加载"))
		"res://scenes/solo_select.tscn":
			_exp("solo_select: 模式 经典/课间", flat.contains("经典模式") and flat.contains("课间模式"))
			_exp("solo_select: 难度 普通/困难", flat.contains("普通") and flat.contains("困难"))
			_exp("solo_select: 开始/返回", _has_button_prefix(cs, "开始") and _has_button_prefix(cs, "返回"))
		"res://scenes/lobby_create.tscn":
			_exp("lobby_create: 创建房间", _has_button_prefix(cs, "创建房间"))
			_exp("lobby_create: 模式 经典/课间", flat.contains("经典模式") and flat.contains("课间模式"))
		"res://scenes/lobby_search.tscn":
			_exp("lobby_search: 标题", flat.contains("搜索房间"))
			_exp("lobby_search: 重新搜索", _has_button_prefix(cs, "重新搜索"))
			_exp("lobby_search: 返回", _has_button_prefix(cs, "返回"))
			# announce 增量：同 room key 只更新文案，不 free 重建
			cs.call("_set_state", "list", "测试")
			var info := {
				"address": "10.0.0.2",
				"port": 47001,
				"room_name": "测试房",
				"mode": "classic",
				"players": 1,
				"max_players": 2,
			}
			cs.call("_on_room_found", info)
			var row: Node = (cs.get("_rows") as Dictionary).get("10.0.0.2:47001")
			_exp("lobby_search: announce 建行", row != null)
			var info2: Dictionary = info.duplicate(true)
			info2["players"] = 2
			cs.call("_on_room_found", info2)
			var row2: Node = (cs.get("_rows") as Dictionary).get("10.0.0.2:47001")
			_exp("lobby_search: 同 key announce 不重建行", row != null and row == row2)
			var txt: Label = null
			if row != null:
				txt = row.get_meta("text_label") as Label
			_exp("lobby_search: 同 key announce 更新文案", txt != null and txt.text.contains("2/2 人"))
		"res://scenes/lobby_wait.tscn":
			_exp("lobby_wait: 准备/取消准备",
				_has_button_prefix(cs, "准备") or _has_button_prefix(cs, "取消准备"))
			_exp("lobby_wait: 离开房间", _has_button_prefix(cs, "离开"))
		"res://scenes/main.tscn":
			_exp("main: classic 三个出招按钮", _count_action_buttons(cs) == 3)
			_exp("main: 对手资源占位", _find_named(cs, "Placeholder_对手资源") != null)
			_exp("main: 我方资源占位", _find_named(cs, "Placeholder_我方资源") != null)
		"res://scenes/net_battle.tscn":
			_exp("net_battle: classic 攒/包子/防御",
				_has_button_prefix(cs, "攒气") and _has_button_prefix(cs, "包子")
				and _has_button_prefix(cs, "防御"))


func _after_screen() -> void:
	var parent := str(SCREENS[_idx].get("parent", ""))
	if parent.is_empty():
		_next_screen()
		return
	_before_path = str(current_scene.scene_file_path)
	var handled := UiNav.go_back(self)
	_exp("%s: go_back 命中返回路由" % _short(str(SCREENS[_idx]["path"])), handled)
	_phase = "back"
	_frames = 0


func _check_back() -> void:
	var cfg: Dictionary = SCREENS[_idx]
	var path := str(cfg["path"])
	var parent := str(cfg["parent"])
	var cs := current_scene
	if path.ends_with("net_battle.tscn"):
		# 对局页返回必须先弹二次确认，不能一键切场景
		_exp("net_battle: 返回先确认，不直接切场景",
			cs != null and str(cs.scene_file_path) == path and path == _before_path)
		var dialog := _find_named(cs, "LeaveConfirm")
		_exp("net_battle: 二次确认框已弹出", dialog != null)
		var yes := _find_named(dialog, "LeaveConfirmYes") as Button
		_exp("net_battle: 二次确认有确定按钮", yes != null)
		if yes != null:
			yes.pressed.emit()
			_phase = "leave"
			_frames = 0
		else:
			_next_screen()
		return

	_exp("%s: 返回后 current_scene 真的换了" % _short(path),
		is_instance_valid(cs) and str(cs.scene_file_path) != _before_path)
	_exp("%s: 返回落点是父级" % _short(path),
		is_instance_valid(cs) and str(cs.scene_file_path) == parent)
	if path.begins_with("res://scenes/lobby_"):
		# lobby_* 父级 = menu 的联机入口页
		var page: Control = null
		if cs != null:
			page = cs.get("_page_net") as Control
		_exp("%s: 返回后打开联机入口页" % _short(path), page != null and page.visible)
	else:
		_exp("%s: 父级 _ready" % _short(path), is_instance_valid(cs) and cs.is_node_ready())
	if path.ends_with("solo_select.tscn"):
		_exp("menu: 回菜单不再弹 Splash", _find_named(cs, "SplashOverlay") == null)
	_next_screen()


func _check_after_confirm() -> void:
	var cs := current_scene
	_exp("net_battle: 确认后真的切场景",
		is_instance_valid(cs) and str(cs.scene_file_path) == MENU_PATH and _before_path != MENU_PATH)
	var page: Control = null
	if cs != null:
		page = cs.get("_page_net") as Control
	_exp("net_battle: 确认后回主菜单首页", page != null and not page.visible)
	_next_screen()


# ---------- 设置面板 ----------

func _load_settings() -> void:
	_phase = "settings"
	_frames = 0
	var packed: PackedScene = load(SETTINGS_PATH)
	_exp("settings_panel.tscn loads", packed != null)
	if packed == null:
		_finish()
		return
	root.add_child(packed.instantiate())


func _check_settings() -> void:
	var panel := get_first_node_in_group(UiNav.SETTINGS_GROUP)
	_exp("settings: 面板 60 帧后仍在树中", panel != null and panel.is_inside_tree())
	if panel == null:
		return
	_exp("settings: 返回菜单", _has_button_prefix(panel, "返回菜单"))
	_exp("settings: 退出游戏", _has_button_prefix(panel, "退出游戏"))
	_exp("settings: 关闭", _has_button_prefix(panel, "关闭") or _has_button_prefix(panel, "✕"))


# ---------- 占位块 ----------

func _check_placeholder() -> void:
	var ph := UiPlaceholder.block("测试屏")
	_exp("placeholder is Control", ph is Control)
	_exp("placeholder default min size", ph.custom_minimum_size == Vector2(200, 80))
	_exp("placeholder fills container", ph.size_flags_horizontal == Control.SIZE_EXPAND_FILL
		and ph.size_flags_vertical == Control.SIZE_EXPAND_FILL)
	_exp("placeholder node name", str(ph.name).begins_with("Placeholder_"))
	var bg := ph.get_child(0)
	_exp("placeholder has ColorRect", bg is ColorRect)
	var label := _find_label(ph)
	_exp("placeholder centered text", label != null and label.text == "【占位】测试屏"
		and label.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER)
	ph.free()


# ---------- 通用 ----------

func _short(path: String) -> String:
	return path.get_file().get_basename()


func _find_named(node: Node, target: String) -> Node:
	if node == null:
		return null
	if str(node.name) == target:
		return node
	for c in node.get_children():
		var hit := _find_named(c, target)
		if hit != null:
			return hit
	return null


func _find_label(node: Node) -> Label:
	for c in node.get_children():
		if c is Label:
			return c as Label
		var hit := _find_label(c)
		if hit != null:
			return hit
	return null


func _flat(node: Node) -> String:
	var parts := PackedStringArray()
	_walk(node, func(n: Node):
		if n is Label:
			parts.append(str((n as Label).text))
		elif n is Button:
			parts.append(str((n as Button).text)))
	return "\n".join(parts)


func _has_button_prefix(node: Node, prefix: String) -> bool:
	if node == null:
		return false
	if node is Button and str((node as Button).text).begins_with(prefix):
		return true
	for c in node.get_children():
		if _has_button_prefix(c, prefix):
			return true
	return false


func _count_action_buttons(node: Node) -> int:
	var count := {"n": 0}
	_walk(node, func(n: Node):
		if n is Button and str(n.name).begins_with("Action"):
			count["n"] += 1)
	return int(count["n"])


func _walk(node: Node, cb: Callable) -> void:
	cb.call(node)
	for c in node.get_children():
		_walk(c, cb)


func _exp(name: String, cond: bool) -> void:
	print(("PASS" if cond else "FAIL"), " - ", name)
	_ok = _ok and cond


func _fail(msg: String) -> void:
	print("FAIL - ", msg)
	_ok = false


func _finish() -> void:
	if _finished:
		return
	_finished = true
	print("ALL PASS" if _ok else "HAS FAILURES")
	quit(0 if _ok else 1)

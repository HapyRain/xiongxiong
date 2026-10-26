## ui_nav.gd
## 竖版导航公用：返回主菜单 / 退出游戏 / 离开对局确认文案。
## 不碰 rules/*；只服务菜单与对局 UI。
class_name UiNav
extends RefCounted

const MENU_SCENE := "res://scenes/menu.tscn"
## 设置面板一旦 _ready 会把自己搬进 SettingsPanelLayer/ 下，
## 所以「是否已打开」只能按 group 查，不能按 root 下的固定路径查。
const SETTINGS_GROUP := "settings_panel_overlay"
## 右上角「设置」齿轮（挂在 QualitySettings autoload 下的 SettingsEntryLayer 里）
const SETTINGS_ENTRY_GROUP := "settings_entry_button"

## 系统返回键路由：当前场景路径 → 回退场景路径。新屏必须自己注册。
static var BACK_ROUTES: Dictionary = {}
## 返回前守卫：当前场景路径 → Callable；返回 true 表示已接管（如弹二次确认），不再自动切场景。
static var BACK_GUARDS: Dictionary = {}
## 回退到 menu 时要打开「联机入口」页的场景路径（lobby_* 用）。
static var BACK_NET_ENTRY: Dictionary = {}
## menu.gd 读它决定 _ready 后打开主页还是联机入口页。
const NET_ENTRY_META := "xiongxiong_net_entry"


## 注册回退目标（screen = 当前场景 res:// 路径，parent = 回退场景 res:// 路径）。
## net_entry=true：回退到 menu 时直接打开联机入口页，而不是主菜单首页。
static func register_back_target(screen: String, parent: String, net_entry: bool = false) -> void:
	BACK_ROUTES[screen] = parent
	if net_entry:
		BACK_NET_ENTRY[screen] = true
	else:
		BACK_NET_ENTRY.erase(screen)


## 注册返回前守卫（如对局页二次确认）：guard 返回 true 表示已接管，go_back 不再切场景。
static func register_back_guard(screen: String, guard: Callable) -> void:
	BACK_GUARDS[screen] = guard


## 按当前场景路径查路由并切场景；未注册返回 false，交给调用方决定。
static func go_back(tree: SceneTree) -> bool:
	if tree == null or tree.current_scene == null:
		return false
	var screen := str(tree.current_scene.scene_file_path)
	var guard: Callable = BACK_GUARDS.get(screen, Callable())
	if guard.is_valid() and bool(guard.call()):
		return true
	var target := str(BACK_ROUTES.get(screen, ""))
	if target.is_empty():
		return false
	if bool(BACK_NET_ENTRY.get(screen, false)):
		Engine.set_meta(NET_ENTRY_META, true)
	cleanup_overlays(tree)
	tree.change_scene_to_file(target)
	return true


## 设置面板是否已打开（按 group 查，兼容面板被搬到 SettingsPanelLayer 之后）。
static func is_settings_open(tree: SceneTree) -> bool:
	if tree == null:
		return false
	return tree.get_first_node_in_group(SETTINGS_GROUP) != null


## 是否在联机对局会话中（ENet，且尚未结束）。
static func is_net_battle() -> bool:
	var n := net()
	if n == null:
		return false
	if bool(n.get("ai_takeover")):
		return true
	if int(n.call("get_mode")) != PeerManager.Mode.ENET:
		return false
	var s: int = int(n.call("get_session"))
	return s == PeerManager.Session.IN_BATTLE or s == PeerManager.Session.SEALED or s == PeerManager.Session.READY_CHECK


## 是否在任意对局场景（单机 main / 联机 net_battle）。
static func is_in_battle_scene(tree: SceneTree) -> bool:
	if tree == null or tree.current_scene == null:
		return false
	var path := str(tree.current_scene.scene_file_path)
	return path.ends_with("main.tscn") or path.ends_with("net_battle.tscn")


## 本地主动离开对局时的确认文案。
static func leave_confirm_text() -> String:
	if is_net_battle():
		return "返回菜单后，对方将由人机接管（或本局结束）。\n确定返回菜单？"
	return "返回菜单将结束当前对局。\n确定返回菜单？"


## 对方离开时的提示文案。
static func peer_left_text() -> String:
	return "对方已离开，由人机接管"


## 运行时拿 autoload Net（PeerManager）。
static func net() -> Node:
	var ml := Engine.get_main_loop()
	if ml is SceneTree:
		return (ml as SceneTree).root.get_node_or_null("Net")
	return null


## 清掉挂在 root / 场景上的临时层，避免切场景后聚光灯/设置面板残留卡死。
static func cleanup_overlays(tree: SceneTree) -> void:
	if tree == null or tree.root == null:
		return
	for n in [
		"OpeningSpotlight",
		"SettingsPanelOverlay",
		"SettingsPanelLayer",
		"NetOverlay",
	]:
		var node := tree.root.get_node_or_null(NodePath(n))
		if node != null:
			node.queue_free()
	# 面板实际挂在 SettingsPanelLayer/ 下，上面按名查不到 → 再按 group 兜一刀
	var panel := tree.get_first_node_in_group(SETTINGS_GROUP)
	if panel != null:
		panel.queue_free()
	# 当前场景内可能还有一份
	if tree.current_scene != null:
		for n in ["OpeningSpotlight", "SettingsPanelOverlay", "SettingsPanelLayer"]:
			var c := tree.current_scene.get_node_or_null(NodePath(n))
			if c != null:
				c.queue_free()


## 离开对局并回主菜单。
static func return_to_menu(tree: SceneTree) -> void:
	cleanup_overlays(tree)
	var n := net()
	if n != null and int(n.call("get_session")) != PeerManager.Session.IDLE:
		n.call("leave")
	if tree != null:
		tree.change_scene_to_file(MENU_SCENE)


## 退出游戏（Android 会 finish Activity）。
static func quit_game(tree: SceneTree) -> void:
	cleanup_overlays(tree)
	if tree != null:
		tree.quit()
	else:
		OS.kill(OS.get_process_id())

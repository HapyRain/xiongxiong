## ui_nav.gd
## 竖版导航公用：返回主菜单 / 退出游戏 / 离开对局确认文案。
## 不碰 rules/*；只服务菜单与对局 UI。
## 注意：static 方法里不直接写 autoload 名 Net（headless --script 编译期解析不到），改为运行时取。
class_name UiNav
extends RefCounted

const MENU_SCENE := "res://scenes/menu.tscn"


## 运行时拿 autoload Net（PeerManager）。
static func net() -> Node:
	var ml := Engine.get_main_loop()
	if ml is SceneTree:
		return (ml as SceneTree).root.get_node_or_null("Net")
	return null


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


## 离开对局并回主菜单。
static func return_to_menu(tree: SceneTree) -> void:
	var n := net()
	if n != null and int(n.call("get_session")) != PeerManager.Session.IDLE:
		n.call("leave")
	if tree != null:
		tree.change_scene_to_file(MENU_SCENE)


## 退出游戏（Android 会 finish Activity）。
static func quit_game(tree: SceneTree) -> void:
	if tree != null:
		tree.quit()
	else:
		OS.kill(OS.get_process_id())

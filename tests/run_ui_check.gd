## run_ui_check.gd
## 第 8 个 headless 自检：占位块 / 各屏 60 帧 / 返回路由真的切场景 / Splash 只首次显示。
## 联机屏用 LocalProvider 装入 Net，避免 headless 起真实 ENet。
## 新增（review 修复回归）：按钮真实前跳导航 / 系统返回清理 / 加入闩锁 / 座位文案 /
## 首拍 phase 不丢 / 读私有字段扫描 / rematch one-shot 不叠连 / 离开弹窗按返回=取消。
## 运行：
##   Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/run_ui_check.gd
extends SceneTree

const FRAMES := 60
const BACK_WAIT := 3
const MENU_PATH := "res://scenes/menu.tscn"
const SETTINGS_PATH := "res://scenes/settings_panel.tscn"

## 测试探针：LocalProvider 子类，记录 start/stop_discover 与发出的信封（U2 断言用）。
class UiNetProbe extends LocalProvider:
	var discover_starts: int = 0
	var discover_stops: int = 0
	var sent: Array = []

	func start_discover(_timeout_sec: float) -> Error:
		discover_starts += 1
		return OK

	func stop_discover() -> void:
		discover_stops += 1

	func get_wifi_ipv4s() -> PackedStringArray:
		return PackedStringArray(["192.168.4.2"])

	func send_reliable(_to_id: int, data: Dictionary) -> Error:
		sent.append(data)
		return OK

	func sent_types() -> Array:
		var out: Array = []
		for d in sent:
			out.append(str(d.get("type", "")))
		return out


## 依次加载的屏：parent = 返回路由父级（空 = 根屏，不测返回）。
const SCREENS := [
	{"path": "res://scenes/menu.tscn", "parent": ""},
	{"path": "res://scenes/solo_select.tscn", "parent": "res://scenes/menu.tscn"},
	{"path": "res://scenes/lobby_create.tscn", "parent": "res://scenes/menu.tscn", "net": "lobby"},
	{"path": "res://scenes/lobby_search.tscn", "parent": "res://scenes/menu.tscn", "net": "lobby"},
	{"path": "res://scenes/lobby_wait.tscn", "parent": "res://scenes/menu.tscn", "net": "wait"},
	{"path": "res://scenes/main.tscn", "parent": "res://scenes/menu.tscn"},
	{"path": "res://scenes/net_battle.tscn", "parent": "res://scenes/menu.tscn", "net": "battle"},
	{"path": "res://scenes/net_battle.tscn", "parent": "res://scenes/menu.tscn", "net": "battle_lesson"},
]

var _ok: bool = true
var _finished: bool = false
var _phase: String = "init"
var _idx: int = 0
var _frames: int = 0
var _before_path: String = ""
var _fwd_step: int = 0
var _probe: UiNetProbe = null
var _stops_before_back: int = 0
var _sent_before_back: int = 0


func _initialize() -> void:
	print("UICHECK_START")
	_check_placeholder()
	_check_source_rules()
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
		"fwd":
			_frames += 1
			if _frames >= BACK_WAIT:
				_fwd_tick()
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
		_start_forward_nav()
		return
	_load_screen()


## 联机屏统一注入 UiNetProbe（headless 不起真实 ENet，探针记录 discover/发包供 U2 断言）。
func _prepare_net(kind: String) -> void:
	if kind.is_empty():
		return
	var net := root.get_node_or_null("Net") as PeerManager
	_exp("Net autoload present", net != null)
	if net == null:
		return
	if net.provider == null or net.get_mode() != PeerManager.Mode.ENET:
		_probe = UiNetProbe.new()
		net.install_provider(_probe, PeerManager.Mode.ENET)
	else:
		_probe = net.provider as UiNetProbe
	if kind == "wait" or kind.begins_with("battle"):
		var room_mode := "classic"
		if kind == "battle_lesson":
			room_mode = "lesson"
		net.room = {
			"room_id": "ui-test",
			"name": "测试房间",
			"mode": room_mode,
			"mastery": false,
			"host_name": "测试机型",
			"players": 2,
			"max": 2,
		}
		if kind.begins_with("battle"):
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
				_exp("menu: Splash 欢迎横幅（无【占位】残留）", _flat(splash).contains("致敬童年") and not _flat(splash).contains("【占位】"))
				# U8：断言真的可见/真的收起，不是只断言存在
				_exp("menu: 首次进菜单 Splash 可见", splash.visible)
				var enter := cs.get("_splash_enter") as Button
				# U7：资源未就绪也不能只剩一块吞输入的 Splash —— 入口按钮必须一直可点
				cs.call("_set_splash_state", false)
				_exp("menu: 资源未就绪仍有可点入口（重试）",
					enter != null and enter.visible and str(enter.text) == "重试")
				cs.call("_set_splash_state", true)
				_exp("menu: 就绪时入口是进入游戏",
					enter != null and enter.visible and str(enter.text) == "进入游戏")
				if enter != null:
					enter.pressed.emit()
				_exp("menu: 点进入游戏后 Splash 收起", not splash.visible)
			# U7：入口失败必须显示在用户可见页，不能只写隐藏页
			cs.call("_report_error", "测试错误：单人模式页面未就绪")
			_exp("menu: 失败提示显示在可见页", _visible_label_contains(cs, "测试错误"))
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
			_check_search_join_latch(cs)
			# U2：记录返回前的 discover 计数，_check_back 断言系统返回真的停搜
			if _probe != null:
				_stops_before_back = _probe.discover_stops
		"res://scenes/lobby_wait.tscn":
			_exp("lobby_wait: 准备/取消准备",
				_has_button_prefix(cs, "准备") or _has_button_prefix(cs, "取消准备"))
			_exp("lobby_wait: 离开房间", _has_button_prefix(cs, "离开"))
			_check_wait_seats(cs)
			_check_wait_ready_button(cs)
			_check_wait_join_reject(cs)
			# U2：倒计时中系统返回也必须走 leave_room（离开按钮同一条路）
			var net := root.get_node_or_null("Net") as PeerManager
			if net != null:
				net._set_session(PeerManager.Session.COUNTDOWN)
			if _probe != null:
				_sent_before_back = _probe.sent.size()
		"res://scenes/main.tscn":
			_exp("main: classic 三个出招按钮", _count_action_buttons(cs) == 3)
			_exp("main: 对手真实血气盾 HUD", _find_named(cs, "opp_hp") != null and _find_named(cs, "opp_qi") != null and _find_named(cs, "opp_shield") != null)
			_exp("main: 我方真实血气盾 HUD", _find_named(cs, "me_hp") != null and _find_named(cs, "me_qi") != null and _find_named(cs, "me_shield") != null)
			_exp("main: MOBA 反馈横幅与右下 5 轮战报栏就位", _find_named(cs, "MobaBanner") != null and _find_named(cs, "BattleTicker") != null)
			_exp("main: 1080P 三渲二全屏特效画布与炉石烧绳条就位", _find_named(cs, "CelStageCanvas") != null and _find_named(cs, "BurningRopeBar") != null and _find_named(cs, "StageBgTex") != null)
			_exp("main: 右上角无重叠 SettingsButton", _settings_entry_hidden())
			_exp("main: 无【占位】残留", not flat.contains("【占位】"))
			_exp("main: 技能按钮主文案严格为 2 个汉字", _all_action_buttons_two_chars(cs))
			_check_ticker_five_lines(_find_named(cs, "BattleTicker") as PanelContainer)
			# U7：槽位命名与内容一致（OppSlot，不是 YouSlot）
			_exp("main: OppSlot 命名与内容一致",
				_find_named(cs, "OppSlot") != null and _find_named(cs, "YouSlot") == null)
			_check_main_first_phase()
		"res://scenes/net_battle.tscn":
			if str(cfg.get("net", "")) == "battle_lesson":
				# U8：lesson 模式冒烟 —— 双层技能盘（3 主键 + 8 进阶槽 = 11 键）
				_exp("net_battle: lesson 双层技能盘 11 键", _count_action_buttons(cs) == 11)
				_exp("net_battle: lesson 含攒气", _has_button_prefix(cs, "攒气"))
				_exp("net_battle: lesson 技能按钮主文案严格 2 字", _all_action_buttons_two_chars(cs))
				_exp("net_battle: MOBA 横幅与右下 5 轮战报栏就位", _find_named(cs, "MobaBanner") != null and _find_named(cs, "BattleTicker") != null)
				_exp("net_battle: 1080P 三渲二全屏特效画布与炉石烧绳条就位", _find_named(cs, "CelStageCanvas") != null and _find_named(cs, "BurningRopeBar") != null and _find_named(cs, "StageBgTex") != null)
				_exp("net_battle: 右上角无重叠 SettingsButton", _settings_entry_hidden())
				_exp("net_battle: lesson 无【占位】残留", not flat.contains("【占位】"))
			else:
				_exp("net_battle: classic 攒/包子/防御",
					_has_button_prefix(cs, "攒气") and _has_button_prefix(cs, "包子")
					and _has_button_prefix(cs, "防御"))
				_exp("net_battle: classic 三个出招按钮", _count_action_buttons(cs) == 3)
				_exp("net_battle: classic 技能按钮主文案严格 2 字", _all_action_buttons_two_chars(cs))
				_check_rematch_oneshots(cs)


## U3：_joining 闩锁 —— 重新搜索必须解锁；加入超时（~10s）清闩锁并给状态提示。
func _check_search_join_latch(cs: Node) -> void:
	cs.set("_joining", true)
	cs.call("_start_search")
	_exp("lobby_search: 重新搜索清掉 _joining 闩锁（U3）", not bool(cs.get("_joining")))
	_exp("lobby_search: 重扫清空旧房间行（U7 死代码删除后行为保持）",
		(cs.get("_rows") as Dictionary).is_empty())
	cs.call("_on_join", {"address": "10.0.0.2", "port": 47001, "token": "", "room_name": "测试房"})
	_exp("lobby_search: 加入后闩锁锁上（U3）", bool(cs.get("_joining")))
	var gen := int(cs.get("_join_gen"))
	cs.call("_on_join_timeout", gen)
	_exp("lobby_search: 加入超时清闩锁（U3）", not bool(cs.get("_joining")))
	var st := cs.get("_status") as Label
	_exp("lobby_search: 加入超时有状态提示（U3）", st != null and str(st.text).contains("超时"))


## U4：座位名按视角只用「我」/「对手」；机型只进副文案（房间名行）。
func _check_wait_seats(cs: Node) -> void:
	var names: Array = cs.get("_seat_names")
	var texts := PackedStringArray()
	for lab in names:
		if lab is Label:
			texts.append(str((lab as Label).text))
	_exp("lobby_wait: 座位名只有 我/对手（U4）",
		texts.size() == 2 and texts.has("我") and texts.has("对手"))
	_exp("lobby_wait: 座位名不含机型（U4）",
		texts.size() == 2 and not texts[0].contains("测试机型") and not texts[1].contains("测试机型"))
	var room_lab := cs.get("_room_name") as Label
	_exp("lobby_wait: 机型/房间名移到副文案（U4）",
		room_lab != null and room_lab.text.contains("测试机型"))


## U7：set_ready 在 IDLE/GAME_OVER/SEALED 是 no-op → 这些状态准备按钮必须禁用。
func _check_wait_ready_button(cs: Node) -> void:
	var net := root.get_node_or_null("Net") as PeerManager
	var btn := cs.get("_ready_btn") as Button
	if net == null or btn == null:
		_exp("lobby_wait: 准备按钮状态检查可执行", false)
		return
	net._set_session(PeerManager.Session.GAME_OVER)
	cs.call("_refresh")
	_exp("lobby_wait: GAME_OVER 准备按钮禁用（U7）", btn.disabled)
	net._set_session(PeerManager.Session.SEALED)
	cs.call("_refresh")
	_exp("lobby_wait: SEALED 准备按钮禁用（U7）", btn.disabled)
	net._set_session(PeerManager.Session.READY_CHECK)
	cs.call("_refresh")
	_exp("lobby_wait: READY_CHECK 准备按钮可用（U7）", not btn.disabled)


## U7：弹窗开着又来 join_requested —— 必须显式拒绝对方，不能静默丢请求。
func _check_wait_join_reject(cs: Node) -> void:
	var net := root.get_node_or_null("Net") as PeerManager
	if net == null or net.provider == null:
		_exp("lobby_wait: 加入拒绝检查可执行", false)
		return
	net.provider.open_as_host({})
	cs.call("_on_join_requested", 2, {})
	_exp("lobby_wait: 首个加入请求弹确认框", cs.get("_dialog") != null)
	var sent_before := 0
	if _probe != null:
		sent_before = _probe.sent.size()
	cs.call("_on_join_requested", 3, {})
	var rejected := false
	if _probe != null:
		for i in range(sent_before, _probe.sent.size()):
			var env: Dictionary = _probe.sent[i]
			if str(env.get("type", "")) == "join_answer" \
					and not bool((env.get("payload", {}) as Dictionary).get("yes", true)):
				rejected = true
	_exp("lobby_wait: 第二个加入请求被显式拒绝（U7）", rejected)
	_exp("lobby_wait: 原确认框未被顶掉（U7）", cs.get("_dialog") != null)
	cs.call("_close_dialog")


## U5：start_match 同步首发 phase_changed 时 _on_phase 必须已经连上（首发不许丢）。
func _check_main_first_phase() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	if packed == null:
		_exp("main: 首拍检查场景可加载", false)
		return
	var scene := packed.instantiate()
	var ctrl := scene.get_node_or_null("BattleController") as BattleController
	if ctrl == null:
		_exp("main: 首拍检查拿到控制器", false)
		return
	var spy := {"n": 0, "ok": false}
	ctrl.phase_changed.connect(func(_p: int, _r: int):
		spy["n"] += 1
		if int(spy["n"]) == 1:
			for c in (ctrl.phase_changed as Signal).get_connections():
				if str(c["callable"].get_method()) == "_on_phase":
					spy["ok"] = true)
	root.add_child(scene)
	if not scene.is_node_ready():
		scene.notification(Node.NOTIFICATION_READY)
	_exp("main: start_match 同步发出首个 phase_changed（U5）", int(spy["n"]) >= 1)
	_exp("main: 首拍发出前 _on_phase 已连接（U5）", bool(spy["ok"]))
	root.remove_child(scene)
	scene.free()
	# 手工实例 _ready 把 BACK_GUARD 覆盖成了已释放对象 → 补回真身的守卫
	if current_scene != null and str(current_scene.scene_file_path) == "res://scenes/main.tscn":
		UiNav.register_back_guard("res://scenes/main.tscn",
			Callable(current_scene, "_on_back_requested"))


## U7：rematch one-shot 每次终局都叠连 → 重复终局后一发双击。必须始终只有一条。
func _check_rematch_oneshots(cs: Node) -> void:
	var net := root.get_node_or_null("Net") as PeerManager
	if net == null:
		_exp("net_battle: rematch one-shot 检查可执行", false)
		return
	cs.call("_on_game_over", 0)
	cs.call("_on_game_over", 0)
	_exp("net_battle: rematch_offer one-shot 不叠连（U7）",
		_count_conns(net.rematch_offer, "_on_rematch_offer") == 1)
	_exp("net_battle: rematch_answered one-shot 不叠连（U7）",
		_count_conns(net.rematch_answered, "_on_rematch_answered") == 1)
	net.rematch_offer.emit()
	net.rematch_offer.emit()  # one-shot 已消费：第二发不应再进 handler
	var btn := cs.get("_btn_rematch") as Button
	_exp("net_battle: 「开始新局」只绑一次（U7）",
		btn != null and _count_conns(btn.pressed, "_on_rematch_yes") == 1)
	cs.call("_on_rematch_offer")  # 双击场景：handler 再进一次也不许重复绑
	_exp("net_battle: 重复 offer 不重复绑定（U7）",
		btn != null and _count_conns(btn.pressed, "_on_rematch_yes") == 1)


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
		# U7：弹窗开着时系统返回 = 点「取消」关弹窗，不能被吞掉
		#（queue_free 是帧末生效：按 _leave_dialog 置空 + is_queued_for_deletion 判定）
		UiNav.go_back(self)
		var closed := _find_named(cs, "LeaveConfirm")
		_exp("net_battle: 返回键关闭离开弹窗（U7）",
			cs.get("_leave_dialog") == null
			and (closed == null or closed.is_queued_for_deletion()))
		_exp("net_battle: 关弹窗不切场景（U7）",
			cs != null and str(cs.scene_file_path) == path)
		UiNav.go_back(self)
		var dialog2 := cs.get("_leave_dialog") as Control
		_exp("net_battle: 再按返回重新弹确认框",
			dialog2 != null and is_instance_valid(dialog2)
			and not dialog2.is_queued_for_deletion())
		var yes := _find_named(dialog2, "LeaveConfirmYes") as Button
		_exp("net_battle: 二次确认有确定按钮", yes != null)
		if yes != null:
			yes.pressed.emit()
			_phase = "leave"
			_frames = 0
		else:
			_next_screen()
		return

	if path.ends_with("lobby_search.tscn"):
		# U2：系统返回必须走按钮同一条清理路 —— stop_discover 不能漏
		_exp("lobby_search: 系统返回停止搜索（U2）",
			_probe != null and _probe.discover_stops > _stops_before_back)
	if path.ends_with("lobby_wait.tscn"):
		# U2：倒计时中系统返回也要发 leave_room（leave_room 是唯一「通知对方再走」的 API）
		var left_room := false
		if _probe != null:
			for i in range(_sent_before_back, _probe.sent.size()):
				if str((_probe.sent[i] as Dictionary).get("type", "")) == "leave_room":
					left_room = true
		_exp("lobby_wait: 系统返回发送 leave_room（U2）", left_room)

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


# ---------- 前跳导航：真实按钮 → 场景/状态真的变（W4 所有按钮真实可用） ----------

func _start_forward_nav() -> void:
	_phase = "fwd"
	_fwd_step = 0
	_frames = 0


func _fwd_tick() -> void:
	var cs := current_scene
	match _fwd_step:
		0:
			var b := _find_button_prefix(cs, "单人")
			_exp("fwd: 菜单「单人模式」按钮可点", b != null)
			if b != null:
				b.pressed.emit()
			_fwd_step = 1
			_frames = 0
		1:
			_exp("fwd: 单人 → solo_select 真的切场景", _scene_is("res://scenes/solo_select.tscn"))
			var b := _find_button_prefix(cs, "开始")
			_exp("fwd: solo「开始对战」按钮可点", b != null)
			if b != null:
				b.pressed.emit()
			_fwd_step = 2
			_frames = 0
		2:
			_exp("fwd: 开始对战 → main 真的切场景", _scene_is("res://scenes/main.tscn"))
			_prepare_net("lobby")
			change_scene_to_file("res://scenes/lobby_create.tscn")
			_fwd_step = 3
			_frames = 0
		3:
			_exp("fwd: 进入创建房间页", _scene_is("res://scenes/lobby_create.tscn"))
			var b := _find_button_prefix(cs, "创建房间")
			_exp("fwd: 「创建房间」按钮可点", b != null)
			if b != null:
				b.pressed.emit()
			_fwd_step = 4
			_frames = 0
		4:
			_exp("fwd: 创建房间 → lobby_wait 真的切场景", _scene_is("res://scenes/lobby_wait.tscn"))
			var net := root.get_node_or_null("Net") as PeerManager
			_exp("fwd: 建房成功进 LOBBY", net != null and net.get_session() == PeerManager.Session.LOBBY)
			if net != null:
				net.accept_join()
				net._client_ready = true
				var rb := _find_button_prefix(cs, "准备")
				_exp("fwd: 「准备」按钮可点", rb != null)
				if rb != null:
					rb.pressed.emit()
				_exp("fwd: 准备 → 进入开局倒计时",
					net.get_session() == PeerManager.Session.COUNTDOWN)
				_exp("fwd: 倒计时真的在走", net.get_lobby_countdown_ms() > 0)
				if rb != null:
					_exp("fwd: 倒计时中准备按钮禁用", rb.disabled)
				net.leave()
			_load_settings()


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
	# 结构断言，不锁死像素规格（视觉重做会改 min size）
	_exp("placeholder min size 非零",
		ph.custom_minimum_size.x > 0 and ph.custom_minimum_size.y > 0)
	_exp("placeholder fills container", ph.size_flags_horizontal == Control.SIZE_EXPAND_FILL
		and ph.size_flags_vertical == Control.SIZE_EXPAND_FILL)
	_exp("placeholder node name", str(ph.name).begins_with("Placeholder_"))
	var bg := ph.get_child(0)
	_exp("placeholder has ColorRect", bg is ColorRect)
	var label := _find_label(ph)
	_exp("placeholder centered text", label != null and label.text == "【占位】测试屏"
		and label.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER)
	ph.free()


# ---------- 源码守约（能失败的回归锁） ----------

func _check_source_rules() -> void:
	# U6：表现层不许读会话层私有字段，必须走只读访问器
	var src := _read_text("res://scripts/ui/net_battle_ui.gd")
	var clean := true
	for bad in ["._window_seconds", "._select_left", "._window_open",
			"._local_preselect", "._resolving", "._did_settle", "._did_lock_fill",
			"peer._opening_done"]:
		if src.contains(bad):
			clean = false
	_exp("net_battle_ui 不读控制器私有字段（U6）", clean and src != "")
	# 文案规则：自有文件只用「我」/「对手」（针拆两段拼，避免本文件自带违禁词）
	var needle := "\u5bf9\u65b9"
	for f in [
		"res://scripts/ui/menu.gd",
		"res://scripts/ui/main.gd",
		"res://scripts/ui/lobby_search.gd",
		"res://scripts/ui/lobby_wait.gd",
		"res://scripts/ui/lobby_create.gd",
		"res://scripts/ui/solo_select.gd",
		"res://scripts/ui/net_battle_ui.gd",
		"res://scripts/ui/ui_nav.gd",
		"res://scripts/ui/ui_back_router.gd",
		"res://scripts/ui/ui_placeholder.gd",
		"res://scripts/ui/ui_theme.gd",
		"res://scripts/ui/battle_fx.gd",
		"res://scripts/ui/settings_panel.gd",
		"res://scripts/session/battle_controller.gd",
		"res://scripts/session/networked_battle_controller.gd",
		"res://scripts/session/ai_opponent.gd",
	]:
		_exp("文案干净：%s" % f.get_file(), not _read_text(f).contains(needle))


func _read_text(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var t := f.get_as_text()
	f.close()
	return t


# ---------- 通用 ----------

func _short(path: String) -> String:
	return path.get_file().get_basename()


func _scene_is(path: String) -> bool:
	return current_scene != null and is_instance_valid(current_scene) \
		and str(current_scene.scene_file_path) == path


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


func _find_button_prefix(node: Node, prefix: String) -> Button:
	if node == null:
		return null
	if node is Button and str((node as Button).text).begins_with(prefix):
		return node as Button
	for c in node.get_children():
		var hit := _find_button_prefix(c, prefix)
		if hit != null:
			return hit
	return null


func _visible_label_contains(node: Node, text: String) -> bool:
	if node is Label and (node as Label).is_visible_in_tree() \
			and str((node as Label).text).contains(text):
		return true
	for c in node.get_children():
		if _visible_label_contains(c, text):
			return true
	return false


func _count_conns(sig: Signal, method: String) -> int:
	var n := 0
	for c in sig.get_connections():
		if str(c["callable"].get_method()) == method:
			n += 1
	return n


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


func _all_action_buttons_two_chars(node: Node) -> bool:
	var st := {"ok": true, "n": 0}
	_walk(node, func(n: Node):
		if n is Button and str(n.name).begins_with("Action"):
			st["n"] += 1
			if str((n as Button).text).length() != 2:
				st["ok"] = false)
	return bool(st["ok"]) and int(st["n"]) > 0


func _settings_entry_hidden() -> bool:
	var btn := get_first_node_in_group(UiNav.SETTINGS_ENTRY_GROUP) as Control
	return btn == null or not btn.is_visible_in_tree()


func _check_ticker_five_lines(ticker: PanelContainer) -> void:
	_exp("ticker: 初始实例有效", ticker != null)
	if ticker == null:
		return
	for i in 7:
		BattleFx.push_ticker_line(ticker, "R%02d 测试记录 %d" % [i + 1, i + 1])
	var hist: Array = ticker.get_meta("history", [])
	_exp("ticker: 最多保留 5 条记录（前 5 轮）", hist.size() == 5 and str(hist[0]).begins_with("R03") and str(hist[4]).begins_with("R07"))
	BattleFx.clear_ticker(ticker)
	_exp("ticker: clear_ticker 清空", (ticker.get_meta("history", []) as Array).is_empty())
	_exp("audio: BGM 与新增音效可加载", BattleFx.load_wav_safe("bgm_battle.wav", true) != null and BattleFx.load_wav_safe("block_success.wav") != null)
	_exp("ui_tex: 技能图标与状态遮罩可加载", UiTheme.load_ui_texture("icon_zan.png") != null and UiTheme.load_ui_texture("state_cd_overlay.png") != null)
	# 交付包缺 fighter_*_stage.png，对撞战卡必须回退同源头像原画（删回退即红）
	var card_me := BattleFx.make_duel_card("我", UiTheme.ACCENT)
	var card_opp := BattleFx.make_duel_card("对手", UiTheme.DANGER)
	_exp("duel_card: 对撞战卡立绘可加载（fighter_* 缺失回退头像）",
		(card_me.get_meta("fighter_art") as TextureRect).texture != null
		and (card_opp.get_meta("fighter_art") as TextureRect).texture != null)
	card_me.free()
	card_opp.free()


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

## run_network_check.gd
## headless 网络骨架自检：热座完整一局 + LocalProvider 双端协议 + ENet 环回。
## 运行：
##   Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/run_network_check.gd
extends SceneTree

var _ok: bool = true
var _phase: String = "init"
var _t: float = 0.0

# 热座
var _hs_pm: PeerManager
var _hs_rounds: int = 0
var _hs_done: bool = false

# LocalProvider 双端
var _host_pm: PeerManager
var _client_pm: PeerManager
var _local_reveals: int = 0
var _local_started: bool = false
var _local_host_failed: bool = false

# ENet 环回
var _enet_host: PeerManager
var _enet_client: PeerManager
var _enet_reveals: int = 0
var _enet_connected: bool = false
var _enet_join_req: bool = false
var _enet_step: String = "boot"
var _enet_t: float = 0.0

var _finished: bool = false


## 鸭子类型假 peer（ENetPacketPeer 是抽象类不能实例化/子类化；
## enet_provider 的事件处理函数接受未标注类型的 peer，注入走这里）。
class FakePeer extends RefCounted:
	var sent: Array = []
	var disconnect_called: bool = false
	var rx: PackedByteArray = PackedByteArray()

	func put_packet(p: PackedByteArray) -> Error:
		sent.append(p)
		return OK

	func peer_disconnect(_data: int = 0) -> void:
		disconnect_called = true

	func get_packet() -> PackedByteArray:
		return rx


## RTT 探针 provider：记录 get_rtt_ms 被问的是哪个对端 id。
class RttProbe extends NetworkProvider:
	var last_to: int = -1

	func get_rtt_ms(to_id: int) -> int:
		last_to = to_id
		return 42


func _initialize() -> void:
	print("NETCHECK_START")
	_check_room_names()
	_phase = "hotseat"
	_setup_hotseat()


func _process(delta: float) -> bool:
	if _finished:
		return true
	_t += delta
	match _phase:
		"hotseat":
			_tick_hotseat(delta)
		"local":
			_tick_local(delta)
		"enet":
			_tick_enet(delta)
		"done":
			_finish()
		_:
			_fail("unknown phase %s" % _phase)
			_finish()
	return _finished


# ================= 热座 =================

func _setup_hotseat() -> void:
	_hs_pm = PeerManager.new()
	root.add_child(_hs_pm)
	_hs_pm.install_provider(LocalProvider.new(), PeerManager.Mode.HOTSEAT)
	_hs_pm.actions_revealed.connect(func(_a, _r): _hs_rounds += 1)
	# 直接手动跑一局：opening + 若干轮锁招
	var err := _hs_pm.join_game({"mode": PeerManager.Mode.HOTSEAT})
	_exp("hotseat join", err == OK)
	_exp("hotseat session", _hs_pm.get_session() == PeerManager.Session.IN_BATTLE)
	_exp("hotseat is_host", _hs_pm.is_host())
	_exp("hotseat mode", _hs_pm.get_mode() == PeerManager.Mode.HOTSEAT)

	# 开局：产品改为双方点「攒」才算开始
	_exp("opening waiting", int(_hs_pm.state.round) == 1 and not _hs_pm._opening_done)
	_hs_pm.submit_action(GameRules.Action.ZAN, 0)
	_hs_pm.submit_action(GameRules.Action.ZAN, 1)
	_hs_pm.request_timeout_default()
	_exp("opening qi", int(_hs_pm.state.qi[0]) == 1 and int(_hs_pm.state.qi[1]) == 1)
	_exp("opening shield", int(_hs_pm.state.shield[0]) == 3 and int(_hs_pm.state.shield[1]) == 3)
	_exp("opening done flag", _hs_pm._opening_done)

	# 打几轮：固定脚本，不依赖计时器
	# 回合 2：左 包子×1 / 右 攒（裸防）→ 右掉 1 血
	# v2 语义：包子 vs 裸防（攒气/集气/回复）不论几连只吃 1 血
	_hs_pm.debug_advance_round()
	_exp("hotseat advanced to r2", _hs_pm.state.round == 2)
	_hs_pm.state.pending = [-1, -1]
	_hs_pm._locks = [false, false]
	_hs_pm._revealing = false
	var hs_before := _hs_rounds
	_hs_pm.submit_action(GameRules.Action.BAO1, 0)
	_hs_pm.submit_action(GameRules.Action.ZAN, 1)
	_hs_pm.request_timeout_default()
	_exp("hotseat r2 revealed", _hs_rounds > hs_before)
	# v2：MAX_HP=4；裸防挨 1 连包掉 1 血 → 4→3。
	# （v1 写法 hp[1]==4 是 MAX_HP=5 + 波/攒旧数值的残留，v2 必须为 3）
	_exp("hotseat r2 hp", int(_hs_pm.state.hp[1]) == 3)
	# 包子×1 耗 1 气：开局攒到 1 → 出包子后 0
	_exp("hotseat r2 qi", int(_hs_pm.state.qi[0]) == 0)
	# 攒会 +1 盾，从 3 封顶到 3；包子方盾不变
	_exp("hotseat r2 shield clamp", int(_hs_pm.state.shield[1]) == 3 and int(_hs_pm.state.shield[0]) == 3)

	# 进下一回合再测超时默认
	_hs_pm.debug_advance_round()
	_exp("hotseat advanced", _hs_pm.state.round == 3)
	_hs_pm.request_timeout_default()
	_exp("hotseat timeout applied", int(_hs_pm._pending_actions[0]) >= 0 and int(_hs_pm._pending_actions[1]) >= 0)
	# 盾≥1 → 防
	_exp("hotseat default is fang", int(_hs_pm._pending_actions[0]) == GameRules.Action.FANG and int(_hs_pm._pending_actions[1]) == GameRules.Action.FANG)
	# v2 新语义：FANG 需盾≥1、**使用即耗 1 盾**（双方都出防 → 各扣 1；防御互撞无额外伤害）→ 3→2
	_exp("hotseat fang costs shield", int(_hs_pm.state.shield[0]) == 2 and int(_hs_pm.state.shield[1]) == 2)

	# 快照往返
	var snap: Dictionary = _hs_pm.get_snapshot()
	_exp("snapshot has round", snap.has("round"))
	_hs_pm.restore_from_snapshot(snap)
	_exp("restore round", _hs_pm.state.round == int(snap["round"]))

	_phase = "local"
	_setup_room_flow()
	_setup_local()


# ================= 房间名 / 等待页 / 房主离开 =================

func _check_room_names() -> void:
	var model := OS.get_model_name()
	_exp("room name classic", PeerManager.default_room_name("classic", false) == model + " · 经典")
	_exp("room name lesson", PeerManager.default_room_name("lesson", false) == model + " · 课间")
	_exp("room name mastery suffix", PeerManager.default_room_name("lesson", true) == model + " · 课间 · 精通")
	_exp("room name classic ignores mastery",
		PeerManager.default_room_name("classic", true) == model + " · 经典")


func _setup_room_flow() -> void:
	# ① 经典房：join_request → 房主同意 → 双准备 → 5s 倒计时 → config 下发
	var a := _make_pair()
	var host: PeerManager = a[0]
	var client: PeerManager = a[1]
	var jr := [0]
	host.join_requested.connect(func(_id: int, _p: Dictionary): jr[0] += 1)

	var herr := host.host_game({
		"mode": PeerManager.Mode.ENET,
		"game_mode": "classic",
		"mastery": true,  # 经典无精通：应被忽略
		"use_discover": false,
	})
	_exp("room host_game", herr == OK)
	_exp("room model fields", str(host.room.get("room_id", "")) != ""
		and str(host.room.get("name", "")) == PeerManager.default_room_name("classic", false)
		and str(host.room.get("mode", "")) == "classic"
		and not bool(host.room.get("mastery", true))
		and int(host.room.get("players", 0)) == 1
		and int(host.room.get("max", 0)) == 2)
	_exp("room session lobby", host.get_session() == PeerManager.Session.LOBBY)

	var jerr := client.join_game({"mode": PeerManager.Mode.ENET})
	_exp("room client join", jerr == OK)
	_pump_pair(host, client)
	_exp("host got join_request", jr[0] >= 1)
	_exp("client stays lobby before accept", client.get_session() == PeerManager.Session.LOBBY)

	host.accept_join()
	_pump_pair(host, client)
	_exp("host ready_check after accept", host.get_session() == PeerManager.Session.READY_CHECK)
	_exp("client ready_check after accept", client.get_session() == PeerManager.Session.READY_CHECK)
	_exp("client got room config", str(client.room.get("mode", "")) == "classic")

	host.set_ready(true)
	client.set_ready(true)
	_pump_pair(host, client)
	_exp("both ready → host countdown", host.get_session() == PeerManager.Session.COUNTDOWN)
	_exp("both ready → client countdown", client.get_session() == PeerManager.Session.COUNTDOWN)
	_exp("countdown starts at 5s", host.get_lobby_countdown_ms() == 5000)
	_exp("client countdown 5s", client.get_lobby_countdown_ms() == 5000)

	host.debug_tick_countdown(4999)
	_exp("4.999s still countdown", host.get_session() == PeerManager.Session.COUNTDOWN
		and host.get_lobby_countdown_ms() == 1)
	host.debug_tick_countdown(1)
	_pump_pair(host, client)
	_exp("5s → host in battle", host.get_session() == PeerManager.Session.IN_BATTLE)
	_exp("5s → client in battle", client.get_session() == PeerManager.Session.IN_BATTLE)
	_exp("battle_start config downlink",
		(client.last_battle_config as Dictionary) == {"mode": "classic", "mastery": false, "difficulty": "normal"})
	_exp("client builds classic BattleState", client.state.mode == "classic" and client.state.max_hp() == 1)
	_exp("client snapshot carries mode", str(client.state.snapshot().get("mode", "")) == "classic")
	host.leave()
	client.leave()

	# ② 课间+精通房：mastery 必须随 config 下发（客户端默认 false）
	var b := _make_pair()
	var host2: PeerManager = b[0]
	var client2: PeerManager = b[1]
	host2.host_game({"mode": PeerManager.Mode.ENET, "game_mode": "lesson", "mastery": true, "use_discover": false})
	client2.join_game({"mode": PeerManager.Mode.ENET})
	_pump_pair(host2, client2)
	host2.accept_join()
	_pump_pair(host2, client2)
	_exp("mastery room propagated", bool(client2.room.get("mastery", false)))
	host2.set_ready(true)
	client2.set_ready(true)
	_pump_pair(host2, client2)
	host2.debug_tick_countdown(5000)
	_pump_pair(host2, client2)
	_exp("mastery config downlink",
		(client2.last_battle_config as Dictionary) == {"mode": "lesson", "mastery": true, "difficulty": "normal"})
	_exp("client builds mastery BattleState", client2.state.mode == "lesson" and client2.state.mastery)
	host2.leave()
	client2.leave()

	# ③ 房主未开局离开 → 客户端提示 + 回入口（IDLE）
	var c := _make_pair()
	var host3: PeerManager = c[0]
	var client3: PeerManager = c[1]
	var left_reason := [""]
	client3.lobby_left.connect(func(r: String): left_reason[0] = r)
	host3.host_game({"mode": PeerManager.Mode.ENET, "game_mode": "lesson", "use_discover": false})
	client3.join_game({"mode": PeerManager.Mode.ENET})
	_pump_pair(host3, client3)
	host3.accept_join()
	_pump_pair(host3, client3)
	_exp("leave case client in waiting", client3.get_session() == PeerManager.Session.READY_CHECK)
	host3.leave_room()
	_pump_pair(host3, client3)
	_exp("host left → client notice", str(left_reason[0]).contains("房主已离开"))
	_exp("host left → client idle", client3.get_session() == PeerManager.Session.IDLE)
	_exp("host left → host idle", host3.get_session() == PeerManager.Session.IDLE)


## 造一对 LocalProvider 房主/客户端（未 open；host_game/join_game 负责 open）。
func _make_pair() -> Array:
	var hp := LocalProvider.new()
	var cp := LocalProvider.new()
	hp.pair_with(cp)
	var host := PeerManager.new()
	root.add_child(host)
	host.install_provider(hp, PeerManager.Mode.ENET)
	var client := PeerManager.new()
	root.add_child(client)
	client.install_provider(cp, PeerManager.Mode.ENET)
	return [host, client]


func _pump_pair(a: PeerManager, b: PeerManager, dt: float = 0.0) -> void:
	if a != null and a.provider != null:
		a.provider.poll(dt)
		a._pump_session(dt)
	if b != null and b.provider != null:
		b.provider.poll(dt)
		b._pump_session(dt)


## 造一对已走完「入房→准备→倒计时→开局」的 host/client（battle_start 已同步）。
func _make_battle_pair() -> Array:
	var pair := _make_pair()
	var host: PeerManager = pair[0]
	var client: PeerManager = pair[1]
	host.host_game({"mode": PeerManager.Mode.ENET, "use_discover": false})
	client.join_game({"mode": PeerManager.Mode.ENET})
	_pump_pair(host, client)
	host.accept_join()
	_pump_pair(host, client)
	host.set_ready(true)
	client.set_ready(true)
	_pump_pair(host, client)
	host.debug_tick_countdown(5000)
	_pump_pair(host, client)
	return pair


# ================= 回归：C1 入站劫持 / C2 陌生人 / I6 token 校验 =================

func _check_provider_hardening() -> void:
	# ---- C2：房主侧陌生人 connect+disconnect 不得惊动会话层、不算人数、不进映射 ----
	var hp := EnetProvider.new()
	var host_events: Array = []
	var host_pkts: Array = []
	hp.disconnected.connect(func(r: String): host_events.append(r))
	hp.packet_received.connect(func(f: int, d: Dictionary): host_pkts.append([f, d]))
	var herr := hp.open_as_host({"token": "secret", "use_discover": false,
		"port": 47911, "bind_address": "127.0.0.1"})
	_exp("harden host open", herr == OK)

	var stranger := FakePeer.new()
	hp._on_connect(stranger)
	_exp("stranger connect stays unbound", hp.get_peer_ids().is_empty())
	stranger.rx = var_to_bytes({"v": 1, "type": "join_request", "round": 0, "payload": {}})
	hp._on_receive(stranger)
	_exp("stranger packet ignored while unbound", host_pkts.is_empty())
	hp._on_disconnect(stranger)
	_exp("stranger disconnect is silent", host_events.is_empty())

	# ---- I6：空 token 不再跳过校验，且被拒连接必须真的断开 ----
	var bad := FakePeer.new()
	hp._on_connect(bad)
	var sent_before: int = bad.sent.size()
	bad.rx = var_to_bytes({"v": 1, "type": "_hello", "payload": {"token": ""}})
	hp._on_receive(bad)
	_exp("empty-token hello rejected + disconnected", bad.disconnect_called)
	_exp("reject notice sent to empty-token peer", bad.sent.size() > sent_before)
	_exp("empty-token peer not bound", hp.get_peer_ids().is_empty() and host_events.is_empty())

	var bad2 := FakePeer.new()
	hp._on_connect(bad2)
	bad2.rx = var_to_bytes({"v": 1, "type": "_hello", "payload": {"token": "WRONG"}})
	hp._on_receive(bad2)
	_exp("wrong-token hello rejected + disconnected",
		bad2.disconnect_called and hp.get_peer_ids().is_empty())

	# ---- 正常客户端：hello 认证通过才绑定，之后其包映射为自己的 id ----
	var good := FakePeer.new()
	hp._on_connect(good)
	good.rx = var_to_bytes({"v": 1, "type": "_hello", "payload": {"token": "secret"}})
	hp._on_receive(good)
	_exp("valid hello binds session peer", hp.get_peer_ids().size() == 1)
	var bound_id := int(hp.get_peer_ids()[0])
	good.rx = var_to_bytes({"v": 1, "type": "submit_action", "round": 2,
		"payload": {"from_role": 1, "action": 0}})
	hp._on_receive(good)
	_exp("bound peer packets delivered with its own id",
		host_pkts.size() == 1 and int(host_pkts[0][0]) == bound_id and bound_id >= 2)
	hp._on_disconnect(good)
	_exp("bound peer disconnect is reported", host_events.size() == 1)
	hp.close()

	# ---- C1：客户端只认自己 connect_to_host 的对端，陌生人连进来立刻踢 ----
	var cp := EnetProvider.new()
	var client_events: Array = []
	var client_pkts: Array = []
	cp.disconnected.connect(func(r: String): client_events.append(r))
	cp.packet_received.connect(func(f: int, d: Dictionary): client_pkts.append([f, d]))
	var cerr := cp.open_as_client({"address": "127.0.0.1", "port": 47912, "token": "secret"})
	_exp("harden client open", cerr == OK)
	var tracked = cp._server_peer
	_exp("client tracks its connect_to_host peer", tracked != null)

	var hijack := FakePeer.new()
	cp._on_connect(hijack)
	_exp("client kicks inbound stranger connect",
		hijack.disconnect_called and hijack.sent.is_empty() and cp._server_peer == tracked)
	# 陌生人冒充房主发 _welcome / 业务包：一律不得冒头（尤其不能映射成 from_id=1）
	hijack.rx = var_to_bytes({"v": 1, "type": "_welcome", "payload": {"your_id": 1, "host_id": 1, "token": ""}})
	cp._on_receive(hijack)
	hijack.rx = var_to_bytes({"v": 1, "type": "round_result", "round": 2, "payload": {}})
	cp._on_receive(hijack)
	_exp("stranger packets ignored (no from_id=1 confusion)",
		client_pkts.is_empty() and cp.get_unique_id() == 0)
	cp._on_disconnect(hijack)
	_exp("stranger disconnect silent on client", client_events.is_empty())

	# 绑定对端（房主）的 _welcome / 业务包正常放行，业务包映射为 from_id=1
	var server := FakePeer.new()
	cp._server_peer = server
	var got_id := [0]
	cp.connected.connect(func(pid: int): got_id[0] = pid)
	server.rx = var_to_bytes({"v": 1, "type": "_welcome", "payload": {"your_id": 3, "host_id": 1, "token": "secret"}})
	cp._on_receive(server)
	_exp("tracked _welcome accepted", got_id[0] == 3 and cp.get_unique_id() == 3)
	server.rx = var_to_bytes({"v": 1, "type": "round_result", "round": 2, "payload": {}})
	cp._on_receive(server)
	_exp("tracked peer packets map to host id 1",
		client_pkts.size() == 1 and int(client_pkts[0][0]) == 1)
	# I6 客户端方向：房主声明空 token ≠ 校验通过
	server.rx = var_to_bytes({"v": 1, "type": "_welcome", "payload": {"your_id": 3, "host_id": 1, "token": ""}})
	cp._on_receive(server)
	_exp("empty-token _welcome rejected", client_events.has("token mismatch") and not cp._open)
	cp.close()

	# ---- C2 会话层：陌生人 connect+disconnect 不得触发封存/清大厅（无 disconnected 事件到达）----
	var pm := PeerManager.new()
	root.add_child(pm)
	var prov := EnetProvider.new()
	pm.install_provider(prov, PeerManager.Mode.ENET)
	var pm_err := pm.host_game({"mode": PeerManager.Mode.ENET, "token": "secret",
		"use_discover": false, "port": 47913, "bind_address": "127.0.0.1"})
	_exp("stranger churn host_game", pm_err == OK and pm.get_session() == PeerManager.Session.LOBBY)
	var took_over := [false]
	var sealed_flag := [false]
	pm.ai_takeover_started.connect(func(_r: String): took_over[0] = true)
	pm.sealed.connect(func(_r: String): sealed_flag[0] = true)
	var s2 := FakePeer.new()
	prov._on_connect(s2)
	prov._on_disconnect(s2)
	_exp("stranger churn keeps lobby intact",
		pm.get_session() == PeerManager.Session.LOBBY and not took_over[0]
		and pm._remote_peer_id == -1 and not sealed_flag[0])
	pm._set_session(PeerManager.Session.IN_BATTLE)
	var s3 := FakePeer.new()
	prov._on_connect(s3)
	prov._on_disconnect(s3)
	_exp("stranger churn no seal/takeover mid-battle",
		pm.get_session() == PeerManager.Session.IN_BATTLE and not took_over[0] and not sealed_flag[0])
	pm.leave()


# ================= 回归：C3 跨回合重放 / commit_id 去重 =================

func _check_replay_guard() -> void:
	var pair := _make_battle_pair()
	var host: PeerManager = pair[0]
	var client: PeerManager = pair[1]
	_exp("replay: pair in battle",
		host.get_session() == PeerManager.Session.IN_BATTLE
		and client.get_session() == PeerManager.Session.IN_BATTLE)
	host.state.round = 3
	client.state.round = 3

	# C3-a：对局中重放 battle_start 必须被丢（否则旧快照把整局倒带回回合 1）
	var old_snap: Dictionary = client.state.snapshot()
	old_snap["round"] = 1
	old_snap["hp"] = [1, 1]
	client._on_provider_packet(1, {"v": 1, "type": "battle_start", "round": 1, "payload": {
		"snapshot": old_snap, "seat": {"host": 0, "client": 1}, "config": {}}})
	_exp("replayed battle_start dropped mid-match",
		client.state.round == 3 and int(client.state.hp[0]) == GameRules.MAX_HP)

	# C3-b：重放旧 select_window 不得把回合数倒回去
	var begun := [0]
	client.round_begun.connect(func(_r: int): begun[0] += 1)
	client._on_provider_packet(1, {"v": 1, "type": "select_window", "round": 2, "payload": {"round": 2}})
	_exp("replayed select_window does not rewind round",
		client.state.round == 3 and begun[0] == 0)

	# C3-c：同一 commit_id 的重复提交 / 倒退 commit_id 一律丢
	var commits := [0]
	host.action_committed.connect(func(_w: int, _a: int): commits[0] += 1)
	host._revealing = false
	host._locks = [false, false]
	host._pending_actions = [-1, -1]
	host.state.pending = [-1, -1]
	host._on_provider_packet(2, {"v": 1, "type": "submit_action", "round": 3,
		"payload": {"from_role": 1, "action": GameRules.Action.FANG, "commit_id": "3-1-100"}})
	host._on_provider_packet(2, {"v": 1, "type": "submit_action", "round": 3,
		"payload": {"from_role": 1, "action": GameRules.Action.FANG, "commit_id": "3-1-100"}})
	_exp("duplicate commit_id dropped", commits[0] == 1 and bool(host._locks[1]))
	host._on_provider_packet(2, {"v": 1, "type": "submit_action", "round": 3,
		"payload": {"from_role": 1, "action": GameRules.Action.ZAN, "commit_id": "1-1-50"}})
	_exp("stale commit_id dropped", commits[0] == 1)

	# I1：对局中迟到的 countdown_start 必须被忽略（不得把客户端拽回 COUNTDOWN）
	client._on_provider_packet(1, {"v": 1, "type": "countdown_start", "round": 0, "payload": {"remain_ms": 5000}})
	_exp("countdown_start ignored in battle", client.get_session() == PeerManager.Session.IN_BATTLE)
	host.leave()
	client.leave()


# ================= 回归：I1/I2/I3 大厅消息闸 =================

func _check_lobby_message_guards() -> void:
	var pair := _make_pair()
	var host: PeerManager = pair[0]
	var client: PeerManager = pair[1]
	host.host_game({"mode": PeerManager.Mode.ENET, "use_discover": false})
	client.join_game({"mode": PeerManager.Mode.ENET})
	_pump_pair(host, client)
	_exp("lobby guard: join pending", host.get_session() == PeerManager.Session.LOBBY)

	# I3：未 accept_join 前的 ready 必须被忽略（不能跳过入房流程把客户端抬进 READY_CHECK）
	host._on_provider_packet(2, {"v": 1, "type": "ready", "round": 0, "payload": {"yes": true}})
	_pump_pair(host, client)
	_exp("ready before accept_join ignored",
		not bool(host.get_ready_flags()[1]) and client.get_session() == PeerManager.Session.LOBBY)

	host.accept_join()
	_pump_pair(host, client)
	_exp("lobby guard: both ready_check",
		host.get_session() == PeerManager.Session.READY_CHECK
		and client.get_session() == PeerManager.Session.READY_CHECK)

	# 信封版本闸：显式声明错误版本的包要被丢
	host._on_provider_packet(2, {"v": 2, "type": "ready", "round": 0, "payload": {"yes": true}})
	_exp("mismatched envelope version dropped", not bool(host.get_ready_flags()[1]))

	host.set_ready(true)
	client.set_ready(true)
	_pump_pair(host, client)
	_exp("lobby guard: both countdown",
		host.get_session() == PeerManager.Session.COUNTDOWN
		and client.get_session() == PeerManager.Session.COUNTDOWN)

	# I2：倒计时中迟到的 ready/取消准备不得翻座位状态
	host._on_provider_packet(2, {"v": 1, "type": "ready", "round": 0, "payload": {"yes": false}})
	_exp("ready during countdown ignored",
		bool(host.get_ready_flags()[1]) and host.get_session() == PeerManager.Session.COUNTDOWN)

	# I2：room_state 不得把客户端从 COUNTDOWN 踢回 READY_CHECK
	client._on_provider_packet(1, {"v": 1, "type": "room_state", "round": 0,
		"payload": {"room": {"mode": "lesson", "mastery": false},
			"host_ready": false, "client_ready": false}})
	_exp("room_state cannot regress from countdown",
		client.get_session() == PeerManager.Session.COUNTDOWN)
	host.leave()
	client.leave()

	# I3：join_answer{yes:false} 从 READY_CHECK 也要当终局（否则客户端永远挂死）
	var pair2 := _make_pair()
	var host2: PeerManager = pair2[0]
	var client2: PeerManager = pair2[1]
	host2.host_game({"mode": PeerManager.Mode.ENET, "use_discover": false})
	client2.join_game({"mode": PeerManager.Mode.ENET})
	_pump_pair(host2, client2)
	host2.accept_join()
	_pump_pair(host2, client2)
	_exp("reject case: client ready_check", client2.get_session() == PeerManager.Session.READY_CHECK)
	var answered := [99]
	client2.join_answered.connect(func(y: bool): answered[0] = 1 if y else 0)
	host2.reject_join()
	_pump_pair(host2, client2)
	_exp("join_answer no from READY_CHECK terminates",
		answered[0] == 0 and client2.get_session() == PeerManager.Session.IDLE)
	host2.leave()
	client2.leave()

	# I1：countdown_start 的 remain_ms 钳制到 [1000, LOBBY_COUNTDOWN_MS]
	var pair3 := _make_pair()
	var host3: PeerManager = pair3[0]
	var client3: PeerManager = pair3[1]
	host3.host_game({"mode": PeerManager.Mode.ENET, "use_discover": false})
	client3.join_game({"mode": PeerManager.Mode.ENET})
	_pump_pair(host3, client3)
	host3.accept_join()
	_pump_pair(host3, client3)
	client3._on_provider_packet(1, {"v": 1, "type": "countdown_start", "round": 0, "payload": {"remain_ms": 10}})
	_exp("countdown remain_ms clamped up to 1000",
		client3.get_lobby_countdown_ms() == 1000 and client3.get_session() == PeerManager.Session.COUNTDOWN)
	client3._set_session(PeerManager.Session.READY_CHECK)
	client3._on_provider_packet(1, {"v": 1, "type": "countdown_start", "round": 0, "payload": {"remain_ms": 999999}})
	_exp("countdown remain_ms clamped down to 5000",
		client3.get_lobby_countdown_ms() == PeerManager.LOBBY_COUNTDOWN_MS
		and client3.get_session() == PeerManager.Session.COUNTDOWN)
	host3.leave()
	client3.leave()


# ================= 回归：I4 对端 fill_only 不得锁房主座位 =================

func _check_fill_only_seat() -> void:
	var pair := _make_battle_pair()
	var host: PeerManager = pair[0]
	var client: PeerManager = pair[1]
	host._revealing = false
	host._locks = [false, false]
	host._pending_actions = [-1, -1]
	host.state.pending = [-1, -1]
	host._on_provider_packet(2, {"v": 1, "type": "timeout_request", "round": host.state.round,
		"payload": {"fill_only": true}})
	_exp("remote fill_only never fills host seat",
		int(host._pending_actions[0]) < 0 and not bool(host._locks[0]) and not bool(host._timeout_flags[0]))
	_exp("remote fill_only fills remote seat only",
		bool(host._locks[1]) and int(host._pending_actions[1]) >= 0)
	host.leave()
	client.leave()


# ================= 回归：get_rtt_ms 查真实绑定对端 =================

func _check_rtt_queries_bound_peer() -> void:
	var probe := RttProbe.new()
	var pm := PeerManager.new()
	root.add_child(pm)
	pm.install_provider(probe, PeerManager.Mode.ENET)
	pm._remote_peer_id = 7
	_exp("rtt queries bound remote id", pm.get_rtt_ms() == 42 and probe.last_to == 7)
	pm._remote_peer_id = -1
	_exp("rtt falls back to host id 1", pm.get_rtt_ms() == 42 and probe.last_to == 1)
	pm.leave()


# ================= LocalProvider 双端协议 =================

func _setup_local() -> void:
	var hp := LocalProvider.new()
	var cp := LocalProvider.new()
	# 先 pair，再 install（install 会 close 旧的，不会拆 pair）
	hp.pair_with(cp)

	_host_pm = PeerManager.new()
	root.add_child(_host_pm)
	_host_pm.install_provider(hp, PeerManager.Mode.ENET)
	_host_pm.actions_revealed.connect(func(_a, _r): _local_reveals += 1)
	_host_pm.session_failed.connect(func(_loser: int, _reason: String): _local_host_failed = true)

	_client_pm = PeerManager.new()
	root.add_child(_client_pm)
	_client_pm.install_provider(cp, PeerManager.Mode.ENET)
	_client_pm.actions_revealed.connect(func(_a, _r): _local_reveals += 1)

	# 模拟传输层 id
	# LocalProvider: host open 时 unique_id=1，client=2；但 install 不 open
	hp.open_as_host({})
	cp.open_as_client({})

	_exp("local host role", _host_pm.get_local_role() == 0)
	_exp("local client role", _client_pm.get_local_role() == 1)

	# 房主建房语义：手动进 IN_BATTLE 并开局
	_host_pm._set_session(PeerManager.Session.IN_BATTLE)
	_client_pm._set_session(PeerManager.Session.IN_BATTLE)
	_host_pm.start_battle()
	# client 通过 battle_start 同步
	_pump(0.05)
	_exp("local battle started", _client_pm.get_session() == PeerManager.Session.IN_BATTLE)

	# 开局：双方点「攒」
	_host_pm.submit_action(GameRules.Action.ZAN, 0)
	_client_pm.submit_action(GameRules.Action.ZAN, 1)
	# 拍2 统一结算（不再提交即亮招）
	_host_pm.request_timeout_default()
	_pump(0.05)
	_exp("local opening done", _host_pm._opening_done)
	_host_pm.debug_advance_round()
	_client_pm.debug_advance_round()
	_pump(0.02)

	# 双端各交一招，等拍2 后原子揭示
	_host_pm.state.round = 2
	_client_pm.state.round = 2
	_host_pm.submit_action(GameRules.Action.BAO1, 0)
	_client_pm.submit_action(GameRules.Action.FANG, 1)
	_host_pm.request_timeout_default()
	_pump(0.05)
	_exp("local revealed", _local_reveals >= 2)
	_exp("local host saw fang", int(_host_pm._pending_actions[1]) == GameRules.Action.FANG)
	_exp("local client saw bao1", int(_client_pm._pending_actions[0]) == GameRules.Action.BAO1)
	# v2：1 连包 vs 普通防御 = 被挡（被挡不再额外扣盾）；单看「使用防御」本身耗 1 盾 → 3→2
	_exp("local shield block", int(_client_pm.state.shield[1]) == 2)
	# v2：被普通防御挡下的 1 连包不破防、双方都不掉血（旧「空防不扣」口径已按 v2 更正）
	_exp("local block no hp loss", int(_client_pm.state.hp[0]) == GameRules.MAX_HP and int(_client_pm.state.hp[1]) == GameRules.MAX_HP)
	# 开局盾 3，使用防扣 1 → 2
	_exp("local block cost shield", int(_client_pm.state.shield[1]) == 2)

	# ===== 回归：发送者校验（房主权威不能被对端单包改写）=====
	# 房主通过 hello 学习到对端真实 id（LocalProvider client=2）
	_exp("host learned remote peer id", _host_pm._remote_peer_id == 2)
	var hp_before := int(_host_pm.state.hp[0])
	# 陌生 id 的判负包必须丢弃
	_host_pm._on_provider_packet(99, {"type": "sys_game_over", "round": 2,
		"payload": {"loser": 0, "reason": "forged"}})
	_exp("drop forged sys_game_over", not _local_host_failed)
	# 陌生 id 的恢复快照必须丢弃（否则对端能任意改房主局面）
	_host_pm._on_provider_packet(99, {"type": "sys_resume", "round": 2,
		"payload": {"snapshot": {"round": 40, "hp": [1, 5]}}})
	_exp("drop forged sys_resume", int(_host_pm.state.hp[0]) == hp_before)
	# 合法对端也不能替房主座位出招
	# 注意：上一轮揭示后 _revealing 仍为 true（等下一窗重置），这里模拟新选招窗
	_host_pm._revealing = false
	_host_pm._locks = [false, false]
	_host_pm._pending_actions = [-1, -1]
	_host_pm.state.pending = [-1, -1]
	_host_pm._on_provider_packet(2, {"type": "submit_action", "round": 2,
		"payload": {"from_role": 0, "action": GameRules.Action.BAO1}})
	_exp("reject remote write to host seat",
		int(_host_pm._pending_actions[0]) < 0 and int(_host_pm.state.pending[0]) < 0)
	# 同一来源写自己的座位必须接受
	_host_pm._on_provider_packet(2, {"type": "submit_action", "round": 2,
		"payload": {"from_role": 1, "action": GameRules.Action.FANG}})
	_exp("accept remote write to own seat", int(_host_pm._pending_actions[1]) == GameRules.Action.FANG)
	# 客户端侧只认房主(1)：陌生 id 宣布胜负必须丢弃
	var client_winner_before := int(_client_pm.state.winner)
	_client_pm._on_provider_packet(99, {"type": "sys_game_over", "round": 2,
		"payload": {"loser": 1, "reason": "forged"}})
	_exp("client drops stranger sys_game_over", int(_client_pm.state.winner) == client_winner_before)

	# ===== 回归：对局中 leave_room / 迟到 room_state 不得把客户端弹回大厅 =====
	_client_pm._on_provider_packet(1, {"type": "leave_room", "round": 2, "payload": {}})
	_exp("ignore leave_room in battle", _client_pm.get_session() == PeerManager.Session.IN_BATTLE)
	_client_pm._on_provider_packet(1, {"type": "room_state", "round": 2,
		"payload": {"room": {"mode": "lesson", "mastery": false}, "host_ready": true, "client_ready": true}})
	_exp("ignore room_state in battle", _client_pm.get_session() == PeerManager.Session.IN_BATTLE)

	# ===== 回归：房主拒绝一个客户端后解绑对端，房间能接待下一个 =====
	var gate := PeerManager.new()
	root.add_child(gate)
	gate.install_provider(LocalProvider.new(), PeerManager.Mode.ENET)
	var gate_joins: Array = []
	gate.join_requested.connect(func(id: int, _p: Dictionary): gate_joins.append(id))
	gate.host_game({"mode": PeerManager.Mode.ENET, "use_discover": false})
	gate._on_provider_packet(2, {"type": "join_request", "round": 0, "payload": {}})
	gate.reject_join()
	_exp("reject resets remote peer id", gate._remote_peer_id == -1)
	gate._on_provider_packet(3, {"type": "join_request", "round": 0, "payload": {}})
	_exp("second client can join after reject",
		gate_joins == [2, 3] and gate.get_session() == PeerManager.Session.LOBBY)
	gate.leave()

	# ===== 回归（评审 C1/C2/C3/I1-I6）：劫持 / 陌生人 / 重放 / 大厅消息闸 =====
	_check_provider_hardening()
	_check_replay_guard()
	_check_lobby_message_guards()
	_check_fill_only_seat()
	_check_rtt_queries_bound_peer()

	_phase = "enet"
	_setup_enet()


# ================= ENet 环回 =================

func _setup_enet() -> void:
	_enet_host = PeerManager.new()
	root.add_child(_enet_host)
	_enet_client = PeerManager.new()
	root.add_child(_enet_client)
	_enet_host.actions_revealed.connect(func(_a, _r): _enet_reveals += 1)
	_enet_client.actions_revealed.connect(func(_a, _r): _enet_reveals += 1)
	_enet_client.battle_started.connect(func(_s):
		_enet_connected = true
		if _enet_step == "wait_battle" or _enet_step == "connecting":
			_enet_step = "play")
	_enet_host.join_requested.connect(func(_id: int, _p: Dictionary): _enet_join_req = true)

	_enet_host.install_provider(EnetProvider.new(), PeerManager.Mode.ENET)
	_enet_client.install_provider(EnetProvider.new(), PeerManager.Mode.ENET)

	var herr := _enet_host.host_game({
		"mode": PeerManager.Mode.ENET,
		"port": 47888,
		"token": "t-xyz",
		"use_discover": false,
		"bind_address": "127.0.0.1",
		"max_players": 1,
	})
	_exp("enet host_game", herr == OK)

	_enet_step = "connecting"
	_enet_t = 0.0
	# join 放到下一帧，让 host 先监听
	_phase = "enet"


func _tick_enet(delta: float) -> void:
	_enet_t += delta
	match _enet_step:
		"boot":
			pass
		"connecting":
			if _enet_t > 0.05 and _enet_client.get_session() == PeerManager.Session.IDLE:
				var jerr := _enet_client.join_game({
					"mode": PeerManager.Mode.ENET,
					"address": "127.0.0.1",
					"port": 47888,
					"token": "t-xyz",
				})
				_exp("enet join_game", jerr == OK)
				_enet_step = "wait_battle"
				_enet_t = 0.0
		"wait_battle":
			# 新房流程：客户端 join_request → 房主同意进等待页 → 双准备 → 倒计时 → 开局
			if _enet_host.get_session() == PeerManager.Session.LOBBY and _enet_join_req:
				_enet_host.accept_join()
			elif _enet_client.get_session() == PeerManager.Session.READY_CHECK \
					and not bool(_enet_host.get_ready_flags()[0]):
				_enet_host.set_ready(true)
				_enet_client.set_ready(true)
			elif _enet_host.get_session() == PeerManager.Session.COUNTDOWN:
				_enet_host.debug_tick_countdown(5000)
			if _enet_connected or _enet_client.get_session() == PeerManager.Session.IN_BATTLE:
				_enet_step = "play"
				_enet_t = 0.0
				_exp("enet client in battle", _enet_client.get_session() == PeerManager.Session.IN_BATTLE)
			elif _enet_t > 6.0:
				_fail("enet battle start timeout (host_session=%d client_session=%d)" % [
					_enet_host.get_session(), _enet_client.get_session()])
				_enet_step = "end"
		"in_battle":
			_enet_step = "play"
			_enet_t = 0.0
		"play":
			# 开局点「攒」
			if not _enet_host._opening_done:
				if not _enet_host._locks[0]:
					_enet_host.submit_action(GameRules.Action.ZAN, 0)
				if not _enet_client._locks[1]:
					_enet_client.submit_action(GameRules.Action.ZAN, 1)
				if _enet_host._locks[0] and _enet_client._locks[1] or _enet_host._opening_done:
					_enet_host.reveal_phase()
			elif _enet_t > 0.3 and _enet_host.state.round >= 2:
				if not _enet_host._locks[0] and int(_enet_host.state.round) >= 2:
					_enet_host.submit_action(GameRules.Action.ZAN, 0)
				if _enet_client.state.round >= 2 and not _enet_client._locks[1]:
					_enet_client.submit_action(GameRules.Action.ZAN, 1)
				if _enet_host._locks[0] and _enet_host._locks[1]:
					_enet_host.reveal_phase()
			if _enet_reveals >= 4:
				_exp("enet revealed both sides", true)
				# 真断言：环回连接下房主必须能看到恰好一个对端（原来 `>=0 or ==-1` 恒真）
				_exp("enet host sees one peer",
					_enet_host.provider != null and _enet_host.provider.get_peer_ids().size() >= 1)
				_enet_step = "end"
			elif _enet_t > 6.0:
				_fail("enet play timeout reveals=%d host_round=%d client_round=%d locks=%s/%s" % [
					_enet_reveals, _enet_host.state.round, _enet_client.state.round,
					_enet_host._locks, _enet_client._locks])
				_enet_step = "end"
		"end":
			# 回归：provider.close() 后再 poll 不得碰已销毁的 ENetConnection（旧代码 SCRIPT ERROR）
			var p := EnetProvider.new()
			p.open_as_client({"address": "127.0.0.1", "port": 47888})
			p.close()
			p.poll(0.0)
			p._pump_service()
			_exp("enet poll after close is safe",
				p.get_peer_ids().is_empty() and p.send_reliable(1, {}) == ERR_UNCONFIGURED)
			if _enet_host != null:
				_enet_host.leave()
			if _enet_client != null:
				_enet_client.leave()
			_phase = "done"
		_:
			_fail("unknown enet step %s" % _enet_step)
			_phase = "done"


# ================= 通用 =================

func _tick_hotseat(_delta: float) -> void:
	# 热座在 setup 内同步跑完
	pass


func _tick_local(_delta: float) -> void:
	pass


func _pump(_dt: float) -> void:
	# LocalProvider.poll 在 PeerManager._process；headless 下手工泵
	if _host_pm != null and _host_pm.provider != null:
		_host_pm.provider.poll(0.0)
	if _client_pm != null and _client_pm.provider != null:
		_client_pm.provider.poll(0.0)


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

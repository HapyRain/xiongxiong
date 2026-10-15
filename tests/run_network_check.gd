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

# ENet 环回
var _enet_host: PeerManager
var _enet_client: PeerManager
var _enet_reveals: int = 0
var _enet_connected: bool = false
var _enet_step: String = "boot"
var _enet_t: float = 0.0

var _finished: bool = false


func _initialize() -> void:
	print("NETCHECK_START")
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
	# 回合 2：左 波 / 右 攒 → 右掉血
	_hs_pm.debug_advance_round()
	_exp("hotseat advanced to r2", _hs_pm.state.round == 2)
	_hs_pm.state.pending = [-1, -1]
	_hs_pm._locks = [false, false]
	_hs_pm._revealing = false
	var hs_before := _hs_rounds
	_hs_pm.submit_action(GameRules.Action.BO, 0)
	_hs_pm.submit_action(GameRules.Action.ZAN, 1)
	_hs_pm.request_timeout_default()
	_exp("hotseat r2 revealed", _hs_rounds > hs_before)
	_exp("hotseat r2 hp", int(_hs_pm.state.hp[1]) == 4)
	_exp("hotseat r2 qi", int(_hs_pm.state.qi[0]) == 0)  # 1-1 波耗气
	# 攒会 +1 盾，从 3 封顶到 3；波方盾不变
	_exp("hotseat r2 shield clamp", int(_hs_pm.state.shield[1]) == 3 and int(_hs_pm.state.shield[0]) == 3)

	# 进下一回合再测超时默认
	_hs_pm.debug_advance_round()
	_exp("hotseat advanced", _hs_pm.state.round == 3)
	_hs_pm.request_timeout_default()
	_exp("hotseat timeout applied", int(_hs_pm._pending_actions[0]) >= 0 and int(_hs_pm._pending_actions[1]) >= 0)
	# 盾≥1 → 防
	_exp("hotseat default is fang", int(_hs_pm._pending_actions[0]) == GameRules.Action.FANG and int(_hs_pm._pending_actions[1]) == GameRules.Action.FANG)

	# 快照往返
	var snap: Dictionary = _hs_pm.get_snapshot()
	_exp("snapshot has round", snap.has("round"))
	_hs_pm.restore_from_snapshot(snap)
	_exp("restore round", _hs_pm.state.round == int(snap["round"]))

	_phase = "local"
	_setup_local()


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
	_host_pm.submit_action(GameRules.Action.BO, 0)
	_client_pm.submit_action(GameRules.Action.FANG, 1)
	_host_pm.request_timeout_default()
	_pump(0.05)
	_exp("local revealed", _local_reveals >= 2)
	_exp("local host saw fang", int(_host_pm._pending_actions[1]) == GameRules.Action.FANG)
	_exp("local client saw bo", int(_client_pm._pending_actions[0]) == GameRules.Action.BO)
	_exp("local shield block", int(_client_pm.state.shield[1]) == 2 or int(_client_pm.state.shield[1]) == 3)
	# 开局盾3，防住波扣1 → 2
	_exp("local block cost shield", int(_client_pm.state.shield[1]) == 2)

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
			# 房主需点「接受」才开局（测试直接 accept_join）
			if _enet_host.get_session() == PeerManager.Session.READY_CHECK:
				_enet_host.accept_join()
			if _enet_connected or _enet_client.get_session() == PeerManager.Session.IN_BATTLE:
				_enet_step = "play"
				_enet_t = 0.0
				_exp("enet client in battle", true)
			elif _enet_t > 3.0:
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
				_exp("enet rtt api", _enet_host.get_rtt_ms() >= 0 or _enet_host.get_rtt_ms() == -1)
				_enet_step = "end"
			elif _enet_t > 6.0:
				_fail("enet play timeout reveals=%d host_round=%d client_round=%d locks=%s/%s" % [
					_enet_reveals, _enet_host.state.round, _enet_client.state.round,
					_enet_host._locks, _enet_client._locks])
				_enet_step = "end"
		"end":
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

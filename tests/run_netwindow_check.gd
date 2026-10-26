## run_netwindow_check.gd
## 回归：start_battle 在 attach/begin 之前发出 round_begun 时，控制器仍要开选招窗并能锁招结算。
extends SceneTree

var _ok := true
var _finished := false
var _host_pm: PeerManager
var _client_pm: PeerManager
var _ctrl: NetworkedBattleController
var _reveals := 0


func _initialize() -> void:
	print("NETWINDOW_START")
	var hp := LocalProvider.new()
	var cp := LocalProvider.new()
	hp.pair_with(cp)

	_host_pm = PeerManager.new()
	root.add_child(_host_pm)
	_host_pm.install_provider(hp, PeerManager.Mode.ENET)
	_host_pm.actions_revealed.connect(func(_a, _r): _reveals += 1)

	_client_pm = PeerManager.new()
	root.add_child(_client_pm)
	_client_pm.install_provider(cp, PeerManager.Mode.ENET)

	hp.open_as_host({})
	cp.open_as_client({})
	_host_pm._sync_fsm_identity()
	_client_pm._sync_fsm_identity()
	_host_pm._set_session(PeerManager.Session.IN_BATTLE)
	_client_pm._set_session(PeerManager.Session.IN_BATTLE)

	# 故意先 start_battle（会立刻 emit round_begun），再 attach 控制器
	_host_pm.start_battle()
	_pump()

	_ctrl = NetworkedBattleController.new()
	root.add_child(_ctrl)
	_ctrl.attach(_host_pm)
	_ctrl.begin()
	print("DBG session=", _host_pm.get_session(), " is_host=", _host_pm.is_host(), " window=", _ctrl._window_open, " input=", _host_pm.is_input_open(), " fsm=", _host_pm.get_net_state_name(), " opening_done=", _host_pm._opening_done)

	_exp("window opens after late attach", _ctrl._window_open)
	_exp("running", _ctrl._running)
	_exp("session in battle", _host_pm.get_session() == PeerManager.Session.IN_BATTLE)

	# 双方点攒 → 锁招 → 揭示
	_exp("select zan", _ctrl.try_select(0, GameRules.Action.ZAN))
	_exp("client zan", _client_pm.submit_action(GameRules.Action.ZAN, 1) == OK)
	_ctrl.lock_in()
	_pump()
	_pump()

	_exp("opening revealed", _host_pm._opening_done)
	_exp("qi after opening", int(_host_pm.state.qi[0]) == 1 and int(_host_pm.state.qi[1]) == 1)

	# 模拟下一回合开窗（跳过 await 延迟）
	_host_pm._begin_next_round()
	_pump()
	_ctrl._sync_window_from_peer()
	_exp("next round window", _ctrl._window_open)
	_exp("round is 2", _host_pm.state.round == 2)

	# 再锁一招，确认仍能揭示
	_ctrl.try_select(0, GameRules.Action.ZAN)
	_client_pm.submit_action(GameRules.Action.ZAN, 1)
	_ctrl.lock_in()
	_pump()
	_pump()
	_exp("round2 revealed", _reveals >= 2)

	_check_lobby_countdown()

	if _host_pm != null:
		_host_pm.leave()
	_finish()


## 等待页 5s 倒计时必须可注入（debug_tick_countdown），不依赖真实时钟。
func _check_lobby_countdown() -> void:
	var hp := LocalProvider.new()
	var cp := LocalProvider.new()
	hp.pair_with(cp)
	var host := PeerManager.new()
	root.add_child(host)
	host.install_provider(hp, PeerManager.Mode.ENET)
	var client := PeerManager.new()
	root.add_child(client)
	client.install_provider(cp, PeerManager.Mode.ENET)
	var ticks: Array = []
	host.lobby_countdown_tick.connect(func(ms: int): ticks.append(ms))

	host.host_game({"mode": PeerManager.Mode.ENET, "game_mode": "classic", "use_discover": false})
	client.join_game({"mode": PeerManager.Mode.ENET})
	_pump_pair(host, client)
	host.accept_join()
	_pump_pair(host, client)
	host.set_ready(true)
	client.set_ready(true)
	_pump_pair(host, client)

	_exp("lobby both ready → countdown", host.get_session() == PeerManager.Session.COUNTDOWN
		and client.get_session() == PeerManager.Session.COUNTDOWN)
	_exp("lobby countdown starts at 5000ms", host.get_lobby_countdown_ms() == 5000
		and client.get_lobby_countdown_ms() == 5000)
	host.debug_tick_countdown(5000)
	_pump_pair(host, client)
	_exp("lobby 5s tick → battle", host.get_session() == PeerManager.Session.IN_BATTLE
		and client.get_session() == PeerManager.Session.IN_BATTLE)
	_exp("lobby countdown tick reached 0", not ticks.is_empty() and int(ticks[ticks.size() - 1]) == 0)
	_exp("lobby config applied to client", client.state.mode == "classic")
	host.leave()
	client.leave()


func _pump_pair(a: PeerManager, b: PeerManager) -> void:
	if a != null and a.provider != null:
		a.provider.poll(0.0)
		a._pump_session(0.0)
	if b != null and b.provider != null:
		b.provider.poll(0.0)
		b._pump_session(0.0)


func _process(_d: float) -> bool:
	return _finished


func _pump() -> void:
	if _host_pm != null and _host_pm.provider != null:
		_host_pm.provider.poll(0.0)
		_host_pm._pump_session(0.0)
	if _client_pm != null and _client_pm.provider != null:
		_client_pm.provider.poll(0.0)
		_client_pm._pump_session(0.0)


func _exp(n: String, c: bool) -> void:
	print(("PASS" if c else "FAIL"), " - ", n)
	_ok = _ok and c


func _finish() -> void:
	if _finished:
		return
	_finished = true
	print("ALL PASS" if _ok else "HAS FAILURES")
	quit(0 if _ok else 1)

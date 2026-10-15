## run_roundloop_check.gd
## 联机闭环回归：点招 → 双方锁定 → 亮招 → 下一回合按钮回弹（含 rematch 后再开一局）。
## 复现：客户端第一回合点一次后 UI 永久灰（state.pending 未在新窗清空）。
extends SceneTree

var _ok := true
var _finished := false
var _host_pm: PeerManager
var _client_pm: PeerManager
var _host_ctrl: NetworkedBattleController
var _client_ctrl: NetworkedBattleController
var _reveals := 0


func _initialize() -> void:
	print("ROUNDLOOP_START")
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
	_host_pm.start_battle()
	_pump()

	_host_ctrl = NetworkedBattleController.new()
	root.add_child(_host_ctrl)
	_host_ctrl.attach(_host_pm)
	_host_ctrl.begin()

	_client_ctrl = NetworkedBattleController.new()
	root.add_child(_client_ctrl)
	_client_ctrl.attach(_client_pm)
	_client_ctrl.begin()
	_pump()

	_exp("host window open", _host_ctrl._window_open)
	_exp("client window open", _client_ctrl._window_open)

	# ---------- 开局：双方点「攒」 ----------
	_exp("host pick zan", _host_ctrl.try_select(0, GameRules.Action.ZAN))
	_exp("client pick zan", _client_ctrl.try_select(1, GameRules.Action.ZAN))
	_exp("host locked after pick", _host_pm._locks[0])
	_exp("client locked after pick", _client_pm._locks[1])
	# 点完即灰：本地已选
	_exp("host picked set", int(_host_ctrl._local_preselect[0]) == GameRules.Action.ZAN)
	_exp("client picked set", int(_client_ctrl._local_preselect[1]) == GameRules.Action.ZAN)

	_host_ctrl.lock_in()
	_client_ctrl.lock_in()
	_pump()
	_pump()

	_exp("opening done", _host_pm._opening_done and _client_pm._opening_done)
	_exp("opening qi 1", int(_host_pm.state.qi[0]) == 1 and int(_client_pm.state.qi[1]) == 1)
	_exp("reveals after opening", _reveals >= 1)

	# 房主推进到回合 2（等价于 OPENING_DELAY 后的 _begin_next_round）
	_host_pm._begin_next_round()
	_pump()
	_pump()

	_exp("round is 2 host", _host_pm.state.round == 2)
	_exp("round is 2 client", _client_pm.state.round == 2)

	# 关键：新窗必须回弹 —— pending / locks / preselect 全清，UI 才会解灰
	_exp("host pending cleared", int(_host_pm.state.pending[0]) < 0 and int(_host_pm.state.pending[1]) < 0)
	_exp("client pending cleared", int(_client_pm.state.pending[0]) < 0 and int(_client_pm.state.pending[1]) < 0)
	_exp("host locks cleared", not _host_pm._locks[0] and not _host_pm._locks[1])
	_exp("client locks cleared", not _client_pm._locks[0] and not _client_pm._locks[1])
	_exp("host preselect cleared", int(_host_ctrl._local_preselect[0]) < 0)
	_exp("client preselect cleared", int(_client_ctrl._local_preselect[1]) < 0)
	_exp("host window reopened", _host_ctrl._window_open)
	_exp("client window reopened", _client_ctrl._window_open)

	# UI 判灰等价式（net_battle_ui._refresh_all）
	_exp("host ui can pick", _ui_can_pick(_host_pm, _host_ctrl, 0))
	_exp("client ui can pick", _ui_can_pick(_client_pm, _client_ctrl, 1))

	# ---------- 回合 2：再点招并亮招 ----------
	_exp("host pick r2", _host_ctrl.try_select(0, GameRules.Action.ZAN))
	_exp("client pick r2", _client_ctrl.try_select(1, GameRules.Action.ZAN))
	_host_ctrl.lock_in()
	_client_ctrl.lock_in()
	_pump()
	_pump()

	var reveals_after_r2 := _reveals
	_exp("r2 revealed", reveals_after_r2 >= 2)

	_host_pm._begin_next_round()
	_pump()
	_pump()

	_exp("round is 3", _host_pm.state.round == 3 and _client_pm.state.round == 3)
	_exp("client pending cleared r3", int(_client_pm.state.pending[1]) < 0)
	_exp("client ui can pick r3", _ui_can_pick(_client_pm, _client_ctrl, 1))
	_exp("client try_select r3", _client_ctrl.try_select(1, GameRules.Action.ZAN))

	# ---------- rematch：强制终局后再来一局 ----------
	_host_pm.state.winner = 0
	_client_pm.state.winner = 0
	_host_pm._set_session(PeerManager.Session.GAME_OVER)
	_client_pm._set_session(PeerManager.Session.GAME_OVER)
	_host_ctrl.stop()
	_client_ctrl.stop()

	var host_rematch := false
	var client_rematch := false
	_host_pm.rematch_answered.connect(func(y): host_rematch = y)
	_client_pm.rematch_answered.connect(func(y): client_rematch = y)

	_host_pm.request_rematch()
	_pump()
	_client_pm.answer_rematch(true)
	_pump()
	_pump()

	_exp("host rematch started", host_rematch or _host_pm.get_session() == PeerManager.Session.IN_BATTLE)
	_exp("client rematch started", client_rematch or _client_pm.get_session() == PeerManager.Session.IN_BATTLE)
	_exp("rematch round reset", _host_pm.state.round == GameRules.OPENING_ROUND and _client_pm.state.round == GameRules.OPENING_ROUND)
	_exp("rematch hp reset", int(_host_pm.state.hp[0]) == GameRules.MAX_HP and int(_client_pm.state.hp[1]) == GameRules.MAX_HP)
	_exp("rematch pending clear", int(_client_pm.state.pending[1]) < 0)

	# rematch 后客户端必须还能点
	_client_ctrl.begin()
	_pump()
	_exp("client window after rematch", _client_ctrl._window_open)
	_exp("client ui can pick after rematch", _ui_can_pick(_client_pm, _client_ctrl, 1))
	_exp("client pick after rematch", _client_ctrl.try_select(1, GameRules.Action.ZAN))

	if _host_pm != null:
		_host_pm.leave()
	_finish()


func _ui_can_pick(pm: PeerManager, ctrl: NetworkedBattleController, seat: int) -> bool:
	# 与 net_battle_ui._refresh_all 同判据
	var s: BattleState = ctrl.state
	var picked: int = int(ctrl._local_preselect[seat]) if ctrl._local_preselect.size() > seat else -1
	if picked < 0:
		picked = int(s.pending[seat])
	var locked: bool = picked >= 0 or bool(pm._locks != null and seat < pm._locks.size() and bool(pm._locks[seat]))
	var can_lock: bool = not s.is_over() and pm.is_input_open() and ctrl._window_open
	return can_lock and not locked


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

## run_seal_check.gd
## headless 断线封存 / 双方同意 / 3s 倒计时恢复状态机自检。
## 运行：
##   Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/run_seal_check.gd
extends SceneTree

var _ok: bool = true
var _phase: String = "fsm"
var _t: float = 0.0
var _finished: bool = false

# FSM 纯状态机
var _fsm: NetworkSessionFSM

# PeerManager 集成（LocalProvider 双端）
var _host_pm: PeerManager
var _client_pm: PeerManager
var _pm_step: String = "boot"
var _pm_t: float = 0.0
var _host_failed: bool = false
var _client_failed: bool = false
var _host_fail_loser: int = -99
var _client_restored: bool = false
var _host_restored: bool = false
var _reject_mode: bool = false


func _initialize() -> void:
	print("SEALCHECK_START")
	_run_fsm_suite()
	_phase = "pm"
	_setup_pm()


func _process(delta: float) -> bool:
	if _finished:
		return true
	_t += delta
	match _phase:
		"pm":
			_tick_pm(delta)
		"pm_reject":
			_tick_pm_reject(delta)
		"done":
			_finish()
		_:
			_fail("unknown phase %s" % _phase)
			_finish()
	return _finished


# ================= 纯状态机 =================

func _run_fsm_suite() -> void:
	_fsm = NetworkSessionFSM.new()
	_fsm.is_host = true
	_fsm.host_peer_id = 1
	_fsm.local_peer_id = 1

	# 初始态
	_exp("fsm initial Connected", _fsm.state == NetworkSessionFSM.State.CONNECTED)
	_exp("fsm input open", _fsm.is_input_open())

	# --- 质量降级：RTT 超阈值 ---
	var t0 := 1000
	_fsm.on_heartbeat_sample(t0, 300)  # rtt 300 >= 250
	_exp("fsm quality_drop → Degraded", _fsm.state == NetworkSessionFSM.State.DEGRADED)
	_exp("fsm input closed in Degraded", not _fsm.is_input_open())

	# --- Degraded → Connected（连续 3 次达标）---
	_fsm.on_heartbeat_sample(t0 + 1000, 80)
	_fsm.on_heartbeat_sample(t0 + 2000, 80)
	_exp("fsm still Degraded after 2 ok", _fsm.state == NetworkSessionFSM.State.DEGRADED)
	_fsm.on_heartbeat_sample(t0 + 3000, 80)
	_exp("fsm recover → Connected", _fsm.state == NetworkSessionFSM.State.CONNECTED)

	# --- 连续丢心跳 2 → Degraded，5 → Sealed ---
	_fsm.on_heartbeat_miss(t0 + 4000)
	_fsm.on_heartbeat_miss(t0 + 5000)
	_exp("fsm 2 miss → Degraded", _fsm.state == NetworkSessionFSM.State.DEGRADED)
	_fsm.on_heartbeat_miss(t0 + 6000)
	_fsm.on_heartbeat_miss(t0 + 7000)
	_fsm.on_heartbeat_miss(t0 + 8000)
	_exp("fsm 5 miss → Sealed", _fsm.state == NetworkSessionFSM.State.SEALED)
	_exp("fsm sealed has snapshot", not _fsm.last_snapshot.is_empty())
	_exp("fsm snapshot seq", int(_fsm.last_snapshot.get("seq", 0)) >= 1)
	_exp("fsm snapshot has rules", _fsm.last_snapshot.has("rules"))
	_exp("fsm snapshot has checksum", str(_fsm.last_snapshot.get("checksum", "")).begins_with("sha256:"))
	_exp("fsm input closed in Sealed", not _fsm.is_input_open())

	# --- Sealed → AwaitingConsent（链路恢复）---
	_fsm.on_link_ok(t0 + 9000)
	_exp("fsm link_ok → AwaitingConsent", _fsm.state == NetworkSessionFSM.State.AWAITING_CONSENT)
	var need: Array = _fsm.get_consent_need()
	_exp("fsm consent need both", need.size() == 2)

	# --- 双方同意 → Countdown ---
	_fsm.submit_consent(1, true, t0 + 10000)
	_exp("fsm one vote still waiting", _fsm.state == NetworkSessionFSM.State.AWAITING_CONSENT)
	_fsm.submit_consent(2, true, t0 + 10100)
	_exp("fsm both yes → Countdown", _fsm.state == NetworkSessionFSM.State.COUNTDOWN)
	_exp("fsm resume_at set", _fsm.get_resume_at_host_ms() > 0)
	_exp("fsm countdown not input", not _fsm.is_input_open())

	# --- 对端 RESUME_ACK + 到点 → Resuming ---
	_fsm.on_resume_ack(2)
	_exp("fsm ack recorded", _fsm._resume_acks.has(2))
	var resume_at := _fsm.get_resume_at_host_ms()
	_fsm.tick(resume_at + NetworkSessionFSM.COUNTDOWN_ACK_GRACE_MS + 50)
	_exp("fsm countdown end → Resuming", _fsm.state == NetworkSessionFSM.State.RESUMING)

	# --- restore 校验 + confirm → Connected ---
	var snap: Dictionary = _fsm.last_snapshot.duplicate(true)
	_exp("fsm restore validate ok", _fsm.validate_snapshot(snap))
	_exp("fsm restore ok", _fsm.restore_from_snapshot(snap, resume_at + 4000))
	_fsm.confirm_restore(true, resume_at + 4100)
	_exp("fsm restore_ok → Connected", _fsm.state == NetworkSessionFSM.State.CONNECTED)
	_exp("fsm input open after restore", _fsm.is_input_open())

	# --- 快照 checksum / seq 闸门 ---
	var bad := snap.duplicate(true)
	bad["checksum"] = "sha256:deadbeef"
	_exp("fsm bad checksum rejected", not _fsm.validate_snapshot(bad))
	var old := snap.duplicate(true)
	old["seq"] = int(snap.get("seq", 1)) - 5
	old["checksum"] = NetworkSessionFSM.compute_checksum(old.get("rules", {}), old.get("session", {}))
	_exp("fsm old seq rejected", not _fsm.validate_snapshot(old))
	var good2 := snap.duplicate(true)
	good2["checksum"] = NetworkSessionFSM.compute_checksum(good2.get("rules", {}), good2.get("session", {}))
	_exp("fsm recomputed checksum ok", _fsm.validate_snapshot(good2))

	# --- 同意拒绝 → Fail（拒绝方判负）---
	_fsm2_reject()

	# --- Consent 超时 → 未同意方判负 ---
	_fsm2_timeout()

	# --- 一方拒绝对方同意的超时路径已覆盖；再测 peer_lost 封存 ---
	_fsm2_peer_lost()


func _fsm2_reject() -> void:
	var f := NetworkSessionFSM.new()
	f.is_host = true
	f.host_peer_id = 1
	f.local_peer_id = 1
	var t := 100
	f.request_seal(t, "test", {"round": 2, "hp": [4, 3], "qi": [1, 1], "shield": [2, 1], "pending": [-1, -1], "phase": 1, "winner": -1}, {})
	f.on_link_ok(t + 10)
	f.submit_consent(1, true, t + 20)
	f.submit_consent(2, false, t + 30)
	_exp("reject → Fail", f.state == NetworkSessionFSM.State.FAIL)
	_exp("reject loser is rejecter", f.get_fail_loser() == 2)
	_exp("reject winner is host", f.winner_on_fail() == 0)


func _fsm2_timeout() -> void:
	var f := NetworkSessionFSM.new()
	f.is_host = true
	f.host_peer_id = 1
	f.local_peer_id = 1
	var t := 200
	f.request_seal(t, "test", {"round": 2, "hp": [4, 3], "qi": [1, 1], "shield": [2, 1], "pending": [-1, -1], "phase": 1, "winner": -1}, {})
	f.on_link_ok(t + 10)
	f.submit_consent(1, true, t + 20)
	# peer 2 一直不点 → 30s 超时
	f.tick(t + 10 + NetworkSessionFSM.CONSENT_TIMEOUT_MS + 100)
	_exp("consent timeout → Fail", f.state == NetworkSessionFSM.State.FAIL)
	_exp("timeout loser is silent peer", f.get_fail_loser() == 2)
	_exp("timeout winner is host", f.winner_on_fail() == 0)

	# 双方都超时 → 平局
	var f2 := NetworkSessionFSM.new()
	f2.is_host = true
	f2.host_peer_id = 1
	f2.local_peer_id = 1
	f2.request_seal(300, "test", {"round": 3, "hp": [3, 3], "qi": [0, 0], "shield": [0, 0], "pending": [-1, -1], "phase": 1, "winner": -1}, {})
	f2.on_link_ok(310)
	f2.tick(310 + NetworkSessionFSM.CONSENT_TIMEOUT_MS + 100)
	_exp("both timeout → Fail draw", f2.state == NetworkSessionFSM.State.FAIL)
	_exp("draw loser -1", f2.get_fail_loser() == -1)
	_exp("draw winner 2", f2.winner_on_fail() == 2)


func _fsm2_peer_lost() -> void:
	var f := NetworkSessionFSM.new()
	f.is_host = true
	f.host_peer_id = 1
	f.local_peer_id = 1
	_exp("pre lost Connected", f.state == NetworkSessionFSM.State.CONNECTED)
	f.on_peer_lost(500, "peer_disconnected")
	_exp("peer_lost → Sealed", f.state == NetworkSessionFSM.State.SEALED)
	_exp("peer_lost snapshot", not f.last_snapshot.is_empty())
	# 封存后 60s 无链路 → Fail
	f.tick(500 + NetworkSessionFSM.SEAL_LINK_DEADLINE_MS + 10)
	_exp("seal link timeout → Fail", f.state == NetworkSessionFSM.State.FAIL)


# ================= PeerManager 集成 =================

func _setup_pm() -> void:
	var hp := LocalProvider.new()
	var cp := LocalProvider.new()
	hp.pair_with(cp)

	_host_pm = PeerManager.new()
	root.add_child(_host_pm)
	_host_pm.install_provider(hp, PeerManager.Mode.ENET)
	_host_pm.session_failed.connect(func(loser: int, reason: String):
		_host_failed = true
		_host_fail_loser = loser
		print("  host session_failed loser=%d reason=%s" % [loser, reason]))
	_host_pm.session_restored.connect(func(_s): _host_restored = true)

	_client_pm = PeerManager.new()
	root.add_child(_client_pm)
	_client_pm.install_provider(cp, PeerManager.Mode.ENET)
	_client_pm.session_failed.connect(func(loser: int, reason: String):
		_client_failed = true
		print("  client session_failed loser=%d reason=%s" % [loser, reason]))
	_client_pm.session_restored.connect(func(_s): _client_restored = true)

	hp.open_as_host({})
	cp.open_as_client({})

	_host_pm._sync_fsm_identity()
	_client_pm._sync_fsm_identity()
	_host_pm._set_session(PeerManager.Session.IN_BATTLE)
	_client_pm._set_session(PeerManager.Session.IN_BATTLE)
	_host_pm.start_battle()
	_pump_pair(0.05)

	_exp("pm host in battle", _host_pm.get_session() == PeerManager.Session.IN_BATTLE)
	_exp("pm client in battle", _client_pm.get_session() == PeerManager.Session.IN_BATTLE)

	# 打一点局面状态，验证快照字段
	_host_pm.state.round = 3
	_host_pm.state.hp = [4, 2]
	_host_pm.state.qi = [1, 0]
	_host_pm.state.shield = [2, 1]
	_host_pm.state.pending = [0, -1]
	_host_pm.state.phase = GameRules.Phase.SELECTING

	# 立即封存
	_host_pm.seal("test_seal")
	_pump_pair(0.05)
	_exp("pm host sealed session", _host_pm.get_session() == PeerManager.Session.SEALED)
	_exp("pm client sealed session", _client_pm.get_session() == PeerManager.Session.SEALED)
	_exp("pm host fsm sealed family", _host_pm.fsm.is_sealed_family())
	var snap: Dictionary = _host_pm.last_session_snap
	_exp("pm snap schema", int(snap.get("schema_version", 0)) == 1)
	_exp("pm snap rules hp", snap.has("rules") and (snap["rules"] as Dictionary).has("hp"))
	_exp("pm snap session beat", (snap.get("session", {}) as Dictionary).has("beat"))
	_exp("pm snap consent", (snap.get("consent", {}) as Dictionary).has("need_continue_from"))
	_exp("pm snap checksum", str(snap.get("checksum", "")).begins_with("sha256:"))
	_exp("pm client got snapshot", not _client_pm.last_session_snap.is_empty())

	# 快照字段：血/气/盾/回合/pending/phase
	var rules: Dictionary = snap.get("rules", {})
	_exp("pm snap hp values", int((rules.get("hp", []) as Array)[0]) == 4 and int((rules.get("hp", []) as Array)[1]) == 2)
	_exp("pm snap round", int(rules.get("round", 0)) == 3)
	_exp("pm snap pending", int((rules.get("pending", []) as Array)[0]) == 0)

	_pm_step = "consent"
	_pm_t = 0.0


func _tick_pm(delta: float) -> void:
	_pm_t += delta
	_pump_pair(delta)
	match _pm_step:
		"consent":
			if _pm_t > 0.05:
				# 双方点「继续」
				_host_pm.submit_resume_vote(true)
				_pump_pair(0.05)
				_client_pm.submit_resume_vote(true)
				# 多泵几轮，确保 COUNTDOWN / RESUME_ACK 送达
				for i in 4:
					_pump_pair(0.02)
				_exp("pm host fsm countdown or resuming",
					_host_pm.fsm.state == NetworkSessionFSM.State.COUNTDOWN
					or _host_pm.fsm.state == NetworkSessionFSM.State.RESUMING
					or _host_pm.fsm.state == NetworkSessionFSM.State.CONNECTED)
				_pm_step = "wait_resume"
				_pm_t = 0.0
		"wait_resume":
			# 手动推时钟：直接 tick fsm 到 resume_at 之后，再泵消息
			if _host_pm.fsm.state == NetworkSessionFSM.State.COUNTDOWN:
				var ra := _host_pm.fsm.get_resume_at_host_ms()
				# 快进：把 countdown_end 视作已到
				_host_pm.fsm.tick(ra + NetworkSessionFSM.COUNTDOWN_ACK_GRACE_MS + 20)
				_client_pm.fsm.tick(ra + NetworkSessionFSM.COUNTDOWN_ACK_GRACE_MS + 20)
				_host_pm._pump_session(0.0)
				_pump_pair(0.05)
			_pump_pair(0.02)
			if _host_pm.fsm.state == NetworkSessionFSM.State.CONNECTED and (_host_restored or _host_pm.is_input_open()):
				_exp("pm host restored", true)
				_exp("pm client restored", _client_restored or _client_pm.fsm.state == NetworkSessionFSM.State.CONNECTED)
				_exp("pm host input open", _host_pm.is_input_open())
				# 恢复后 rules 与快照一致
				_exp("pm restored hp", int(_host_pm.state.hp[0]) == 4 and int(_host_pm.state.hp[1]) == 2)
				_pm_step = "to_reject"
				_pm_t = 0.0
			elif _pm_t > 2.0:
				# 可能已直接 CONNECTED（restore 同步完成）
				if _host_pm.fsm.state == NetworkSessionFSM.State.CONNECTED:
					_exp("pm host restored", true)
					_exp("pm restored hp", int(_host_pm.state.hp[0]) == 4 and int(_host_pm.state.hp[1]) == 2)
					_pm_step = "to_reject"
					_pm_t = 0.0
				else:
					_fail("pm resume timeout state=%s" % _host_pm.fsm.get_state_name())
					_pm_step = "to_reject"
					_pm_t = 0.0
		"to_reject":
			if _pm_t > 0.05:
				# 再封存一次，这次走拒绝判负
				_host_pm.state.round = 4
				_host_pm.seal("test_reject")
				_pump_pair(0.05)
				_host_pm.submit_resume_vote(true)
				_pump_pair(0.05)
				_client_pm.submit_resume_vote(false)  # 拒绝
				_pump_pair(0.05)
				_exp("pm reject → fail", _host_failed or _client_failed or _host_pm.fsm.state == NetworkSessionFSM.State.FAIL)
				_exp("pm reject loser is rejecter", _host_fail_loser == 2 or _client_pm.fsm.get_fail_loser() == 2 or _host_pm.fsm.get_fail_loser() == 2)
				_phase = "done"
		_:
			_fail("unknown pm step %s" % _pm_step)
			_phase = "done"


func _tick_pm_reject(_delta: float) -> void:
	_phase = "done"


# ================= 通用 =================

func _pump_pair(dt: float) -> void:
	if _host_pm != null and _host_pm.provider != null:
		_host_pm.provider.poll(dt)
		_host_pm._pump_session(dt)
	if _client_pm != null and _client_pm.provider != null:
		_client_pm.provider.poll(dt)
		_client_pm._pump_session(dt)


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

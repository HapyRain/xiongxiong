## peer_manager.gd
## 会话与指令语义：后端切换、建房/加入、锁后提交、原子揭示、超时默认、封存挂钩。
## 房主权威；客户端只 apply 房主下发的结算，不本地 GameResolve。
## 信封统一 {v,type,round,from_role,payload}，传输细节全部走 NetworkProvider。
class_name PeerManager
extends Node

enum Mode { HOTSEAT, ENET, WEBSOCKET }
enum Session { IDLE, LOBBY, READY_CHECK, IN_BATTLE, SEALED, GAME_OVER }

const ENVELOPE_VERSION := 1
## 锁招宽限：双方 UI 开窗可能有时间差，给足 3.5s 避免超时默认吞掉对方已选招
const LOCK_GRACE_SEC := 3.5
const OPENING_DELAY := 0.8
## 开局（回合1）窗口：双方点「攒」才算正式开始
const OPENING_SELECT_WINDOW := 6.0

signal mode_changed(mode: int)
signal session_changed(session: int)
signal room_found(info: Dictionary)
signal peer_joined(peer_id: int, profile: Dictionary)
signal peer_left(peer_id: int, reason: String)
signal action_committed(who: int, action: int)
signal actions_revealed(actions: Array, results: Dictionary)
signal beat_received(beat_no: int)
signal battle_started(snapshot: Dictionary)
signal round_begun(round_no: int)
signal sealed(reason: String)
signal resume_countdown(sec: int)
signal battle_error(code: String, message: String)
signal status_text(text: String)
## 网络会话 FSM 对 UI 的归一化事件
signal net_state_changed(state_name: String, reason: String)
signal consent_needed(snap: Dictionary, need_from: Array)
signal countdown_tick(remain_ms: int)
signal session_failed(loser_role: int, reason: String)
signal session_restored(snap: Dictionary)
## 对方离开/掉线后本地改由人机接管（对局继续）
signal ai_takeover_started(reason: String)
## 对方申请加入，等房主「接受并开战」
signal join_requested(peer_id: int, profile: Dictionary)
## 对方提出再来一局
signal rematch_offer()
## 对方答复再来一局（true=开打，false=回菜单）
signal rematch_answered(yes: bool)

var state: BattleState = BattleState.new()
var provider: NetworkProvider = null
var fsm: NetworkSessionFSM = NetworkSessionFSM.new()

## 由 NetworkedBattleController 注入 beat / phase 元数据，进 SessionSnapshot。
var session_meta_hook: Callable = Callable()

## true=对方已离开，本地双座位结算（对方座位由 AiOpponent 驱动）
var ai_takeover: bool = false

var _mode: int = Mode.HOTSEAT
var _session: int = Session.IDLE
var _local_role: int = 0
var _token: String = ""
var _room_name: String = ""
var _self_closing: bool = false

## 本回合锁定缓存（权威侧）
var _pending_actions: Array = [-1, -1]
var _locks: Array = [false, false]
var _revealing: bool = false
var _grace_left: float = 0.0
var _opening_done: bool = false
## 开局亮相是否已结算（防 resolve_opening 重复加资源）
var _opening_applied: bool = false
## 本回合是否因超时自动出招（UI 角标「超时」）
var _timeout_flags: Array = [false, false]
var _last_commit_id: String = ""

## 心跳（应用层，ENet 默认 timeout 5–30s 太慢）
var _hb_timer: float = 0.0
var _hb_seq: int = 0
var _hb_inflight: Dictionary = {}
var _last_hb_rx_ms: int = 0
var _fsm_ready: bool = false
var _countdown_sent: bool = false
var _resume_sent: bool = false
## 再来一局：双方意愿
var _rematch_want: bool = false
var _peer_rematch_want: bool = false

## 最近一份 SessionSnapshot（含 checksum / seq）
var last_session_snap: Dictionary = {}


func _ready() -> void:
	set_process(true)
	_wire_fsm()


func _wire_fsm() -> void:
	if _fsm_ready:
		return
	_fsm_ready = true
	fsm.state_changed.connect(func(from_s: int, to_s: int, reason: String):
		net_state_changed.emit(NetworkSessionFSM.state_name(to_s), reason)
		_on_fsm_state(from_s, to_s, reason))
	fsm.sealed.connect(func(snap: Dictionary, reason: String):
		last_session_snap = snap)
	fsm.consent_needed.connect(func(snap: Dictionary, need_from: Array):
		consent_needed.emit(snap, need_from))
	fsm.countdown_tick.connect(func(remain_ms: int):
		countdown_tick.emit(remain_ms)
		resume_countdown.emit(int(ceil(remain_ms / 1000.0))))
	fsm.resumed.connect(func(snap: Dictionary):
		session_restored.emit(snap))
	fsm.failed.connect(_on_fsm_failed)


func _process(delta: float) -> void:
	if provider != null:
		provider.poll(delta)
	_pump_grace(delta)
	_pump_session(delta)


# ---------- 后端与模式 ----------

func set_backend(mode: int) -> Error:
	if _session != Session.IDLE:
		leave()
	if provider != null:
		provider.close()
		_disconnect_provider()
	provider = _make_provider(mode)
	if provider == null:
		return ERR_INVALID_PARAMETER
	_mode = mode
	_connect_provider()
	mode_changed.emit(_mode)
	return OK


## 测试钩子：注入已有 provider（如配对 LocalProvider / MockProvider）。
func install_provider(p: NetworkProvider, mode: int = Mode.ENET) -> Error:
	if p == null:
		return ERR_INVALID_PARAMETER
	if _session != Session.IDLE:
		leave()
	if provider != null:
		provider.close()
		_disconnect_provider()
	provider = p
	_mode = mode
	_connect_provider()
	mode_changed.emit(_mode)
	return OK


func _make_provider(mode: int) -> NetworkProvider:
	match mode:
		Mode.HOTSEAT:
			return LocalProvider.new()
		Mode.ENET:
			return EnetProvider.new()
		Mode.WEBSOCKET:
			return WebSocketProvider.new()
	return null


func _connect_provider() -> void:
	if provider == null:
		return
	provider.connected.connect(_on_provider_connected)
	provider.disconnected.connect(_on_provider_disconnected)
	provider.packet_received.connect(_on_provider_packet)
	provider.discovered_room.connect(func(info: Dictionary): room_found.emit(info))


func _disconnect_provider() -> void:
	if provider == null:
		return
	if provider.connected.is_connected(_on_provider_connected):
		provider.connected.disconnect(_on_provider_connected)
	if provider.disconnected.is_connected(_on_provider_disconnected):
		provider.disconnected.disconnect(_on_provider_disconnected)
	if provider.packet_received.is_connected(_on_provider_packet):
		provider.packet_received.disconnect(_on_provider_packet)


# ---------- 建房 / 加入 / 离开 ----------

## opts: {room_name?, port?, token?, max_players?, use_discover?, discover_port?}
func host_game(opts: Dictionary) -> Error:
	# 新开房间：清干净上一局
	_reset_rules_state()
	if provider == null:
		var err := set_backend(int(opts.get("mode", Mode.ENET)))
		if err != OK:
			return err
	_token = str(opts.get("token", ""))
	_room_name = str(opts.get("room_name", "xiongxiong-room"))
	var open_opts := opts.duplicate(true)
	open_opts["token"] = _token
	open_opts["room_name"] = _room_name
	var err := provider.open_as_host(open_opts)
	if err != OK:
		battle_error.emit("host_failed", "open_as_host failed: %s" % error_string(err))
		return err
	_local_role = 0
	_set_session(Session.LOBBY)
	_sync_fsm_identity()
	status_text.emit("已创建房间 %s，等待对手…" % _room_name)
	return OK


## ENET: {address, port, token}；HOTSEAT: {}；WEBSOCKET: {url, token}
func join_game(opts: Dictionary) -> Error:
	# 新加入：同样清干净
	_reset_rules_state()
	if provider == null:
		var err0 := set_backend(int(opts.get("mode", Mode.ENET)))
		if err0 != OK:
			return err0
	_token = str(opts.get("token", ""))
	var open_opts := opts.duplicate(true)
	open_opts["token"] = _token
	if _mode == Mode.HOTSEAT:
		# 热座：直接进入同屏对局
		var errh := provider.open_as_host(open_opts)
		if errh != OK:
			return errh
		_local_role = 0
		_set_session(Session.IN_BATTLE)
		start_battle()
		return OK
	var err := provider.open_as_client(open_opts)
	if err != OK:
		battle_error.emit("join_failed", "open_as_client failed: %s" % error_string(err))
		return err
	_local_role = 1
	_set_session(Session.LOBBY)
	_sync_fsm_identity()
	status_text.emit("正在连接 %s…" % str(opts.get("address", "")))
	return OK


func leave() -> void:
	_self_closing = true
	if provider != null:
		# 主动离开：尽量通知对方，由对方走人机接管
		if _session == Session.IN_BATTLE or _session == Session.READY_CHECK or _session == Session.SEALED or _session == Session.GAME_OVER:
			_broadcast(_envelope("bye", state.round, {"reason": "local_leave"}))
		_disconnect_provider()
		provider.close()
		provider = null
	_self_closing = false
	ai_takeover = false
	_pending_actions = [-1, -1]
	_locks = [false, false]
	_revealing = false
	_opening_done = false
	_opening_applied = false
	_grace_left = 0.0
	_reset_rules_state()
	_set_session(Session.IDLE)
	status_text.emit("已离开")


## 清空血/气/盾/回合/胜负，避免下一局继承上一局（0 血满气开局等）。
func _reset_rules_state() -> void:
	state = BattleState.new()
	_pending_actions = [-1, -1]
	_locks = [false, false]
	_revealing = false
	_opening_done = false
	_opening_applied = false
	_timeout_flags = [false, false]


## 对方离开/掉线：本地改由人机接管，对局继续（不再走封存判负）。
## 返回 true 表示已接管。
func begin_ai_takeover(reason: String = "peer_left") -> bool:
	if _mode == Mode.HOTSEAT or ai_takeover:
		return false
	if state.is_over():
		return false
	# 未开局（大厅/等待接受）不接管，避免菜单页被推进 IN_BATTLE
	if _session != Session.IN_BATTLE and _session != Session.SEALED:
		peer_left.emit(0, reason)
		_set_session(Session.IDLE)
		status_text.emit("对方已离开")
		return false
	ai_takeover = true
	_self_closing = true
	if provider != null:
		_disconnect_provider()
		provider.close()
		provider = null
	_self_closing = false
	fsm.force_local_play("ai_takeover")
	_grace_left = 0.0
	_revealing = false
	if not _opening_done and not state.is_over():
		_do_opening()
	_set_session(Session.IN_BATTLE)
	ai_takeover_started.emit(reason)
	status_text.emit("对方已离开，由人机接管")
	return true


func start_discover(timeout_sec: float = 5.0) -> Error:
	if provider == null:
		return ERR_UNCONFIGURED
	return provider.start_discover(timeout_sec)


func stop_discover() -> void:
	if provider != null:
		provider.stop_discover()


## 房主确认接受后开局（客户端发 ready 仍走此路径由房主触发）。
func start_battle() -> Error:
	if _mode == Mode.HOTSEAT:
		_set_session(Session.IN_BATTLE)
		_reset_rules_state()
		_do_opening()
		return OK
	if not is_host():
		# 客户端发 ready，等房主 accept → battle_start
		_send_to_host(_envelope("ready", 1, {}))
		_set_session(Session.READY_CHECK)
		return OK
	_local_role = 0
	_set_session(Session.IN_BATTLE)
	# 新一局必须重置规则状态，否则快照会带上一局的血/气
	_reset_rules_state()
	var snap := state.snapshot()
	_broadcast(_envelope("battle_start", 1, {"snapshot": snap, "seat": {"host": 0, "client": 1}}))
	battle_started.emit(snap)
	_do_opening()
	return OK


## 房主点「接受并开启对战」
func accept_join() -> Error:
	if _mode == Mode.HOTSEAT or not is_host():
		return start_battle()
	if _session != Session.LOBBY and _session != Session.READY_CHECK:
		return ERR_ALREADY_IN_USE
	status_text.emit("已接受，开始对战")
	return start_battle()


## 房主点「拒绝」：踢掉对端
func reject_join() -> void:
	if not is_host():
		return
	_broadcast(_envelope("join_rejected", 0, {"reason": "host_declined"}))
	status_text.emit("已拒绝加入")


## 终局后再来一局：任一方可发起，对方确认后开打。
func request_rematch() -> void:
	_rematch_want = true
	if _mode == Mode.HOTSEAT or ai_takeover:
		_start_rematch_local()
		return
	if is_host():
		_broadcast(_envelope("rematch_request", 0, {}))
	else:
		_send_to_host(_envelope("rematch_request", 0, {}))
	# 对端已点过 → 双方都同意
	if _peer_rematch_want:
		_confirm_rematch()
	else:
		status_text.emit("已发出「再来一局」，等待对方…")


## 回应对方的再来一局。yes=false 则回菜单。
func answer_rematch(yes: bool) -> void:
	_rematch_want = yes
	if _mode == Mode.HOTSEAT or ai_takeover:
		if yes:
			_start_rematch_local()
		return
	if is_host():
		_broadcast(_envelope("rematch_answer", 0, {"yes": yes}))
	else:
		_send_to_host(_envelope("rematch_answer", 0, {"yes": yes}))
	if not yes:
		rematch_answered.emit(false)
		return
	if _peer_rematch_want:
		_confirm_rematch()


func _confirm_rematch() -> void:
	# 双方都要收起终局/询问遮罩；仅房主开局
	if is_host() or _mode == Mode.HOTSEAT or ai_takeover:
		_start_rematch_local()
	else:
		rematch_answered.emit(true)
		status_text.emit("对方同意，进入新对局…")


func _start_rematch_local() -> void:
	_rematch_want = false
	_peer_rematch_want = false
	_reset_rules_state()
	_remotify_reset()
	var was_takeover := ai_takeover
	ai_takeover = false
	# 接管/无 provider 时视为本地房主，否则 is_host()==false 导致新局永不开始
	if was_takeover or provider == null or is_host() or _mode == Mode.HOTSEAT:
		start_battle()
	else:
		start_battle()
	rematch_answered.emit(true)


func _remotify_reset() -> void:
	# 心跳/状态清干净，避免沿用上一局 SEALED
	_countdown_sent = false
	_resume_sent = false
	_grace_left = 0.0
	_sync_fsm_identity()


# ---------- 指令（对局内） ----------

## who: 热座座位 0/1；联机下省略=本地角色。点击即上传，结算前可改。
func submit_action(action: int, who: int = -1) -> Error:
	if _session != Session.IN_BATTLE:
		return ERR_UNCONFIGURED
	if not is_input_open():
		return ERR_LOCKED
	if _revealing or state.is_over():
		return ERR_LOCKED
	var role: int = _local_role if who < 0 else who
	if role < 0 or role > 1:
		return ERR_INVALID_PARAMETER
	if not state.can_use_action(role, action):
		return FAILED
	state.pending[role] = action
	action_committed.emit(role, action)

	if _mode == Mode.HOTSEAT or ai_takeover:
		_locks[role] = true
		_pending_actions[role] = action
		return OK

	# 已锁过也允许覆盖（封盘前可改招）；不在此结算
	_locks[role] = true
	_pending_actions[role] = action
	var commit := {
		"round": state.round,
		"action": action,
		"from_role": role,
		"commit_id": "%d-%d-%d" % [state.round, role, Time.get_ticks_msec()],
	}
	_last_commit_id = str(commit["commit_id"])
	if is_host():
		_on_submit_received(role, commit)
	else:
		_send_to_host(_envelope("submit_action", state.round, commit))
	return OK


## 拍2 亮招时机；host 广播 actions_revealed。缺锁则进入 grace 超时默认。
func reveal_phase() -> void:
	if _session != Session.IN_BATTLE or state.is_over():
		return
	if not is_input_open():
		return
	if _mode == Mode.HOTSEAT or ai_takeover:
		_maybe_reveal_local()
		return
	if is_host():
		_try_host_reveal()
	else:
		# 客户端：确保自己已提交；真正 reveal 由房主广播
		if not _locks[_local_role] and state.pending[_local_role] >= 0:
			submit_action(int(state.pending[_local_role]))
		_send_to_host(_envelope("reveal_request", state.round, {}))


## 封盘：缺输入按规则补默认并打「超时」角标，但不结算。
func auto_fill_missing() -> void:
	if _session != Session.IN_BATTLE or state.is_over():
		return
	if not is_input_open():
		return
	if not is_host() and _mode != Mode.HOTSEAT and not ai_takeover:
		_send_to_host(_envelope("timeout_request", state.round, {"fill_only": true}))
		return
	for i in 2:
		if not _locks[i] or _pending_actions[i] < 0:
			var a: int = int(state.pending[i])
			if a < 0:
				a = int(_pending_actions[i])
			if a < 0:
				a = _default_action(i)
				_timeout_flags[i] = true
			if not state.can_use_action(i, a):
				a = GameRules.Action.ZAN
				_timeout_flags[i] = true
			_pending_actions[i] = a
			_locks[i] = true
			if state.pending[i] < 0:
				state.pending[i] = a
			action_committed.emit(i, a)


## 超时默认防/攒，由 host 执行（含结算）。
func request_timeout_default() -> void:
	if _session != Session.IN_BATTLE or state.is_over():
		return
	if not is_input_open():
		return
	if not is_host() and _mode != Mode.HOTSEAT and not ai_takeover:
		_send_to_host(_envelope("timeout_request", state.round, {}))
		return
	auto_fill_missing()
	if _mode == Mode.HOTSEAT or ai_takeover:
		_maybe_reveal_local()
	else:
		_do_host_reveal()


# ---------- 封存 / 恢复（Session FSM：断线封存 / 双方同意 / 3s 倒计时） ----------

## 立即封存当前局（血/气/盾/回合/pending/phase/beat）。热座可跳过；ENet 联机必须走。
func seal(reason: String) -> void:
	if _mode == Mode.HOTSEAT or ai_takeover:
		return
	if _session != Session.IN_BATTLE and _session != Session.SEALED and _session != Session.READY_CHECK:
		return
	if fsm.state == NetworkSessionFSM.State.FAIL:
		return
	var now := Time.get_ticks_msec()
	_countdown_sent = false
	_resume_sent = false
	var snap := fsm.request_seal(now, reason, state.snapshot(), _session_meta())
	last_session_snap = snap
	_set_session(Session.SEALED)
	sealed.emit(reason)
	if is_host():
		_broadcast(_envelope("sys_sealed", state.round, {"reason": reason, "snapshot": snap}))
	status_text.emit("已封存：%s" % reason)


## 点「继续」/「拒绝」。yes=true 同意恢复；false=拒绝（demo：拒绝方判负）。
func submit_resume_vote(yes: bool) -> void:
	if _mode == Mode.HOTSEAT or ai_takeover:
		return
	var now := Time.get_ticks_msec()
	var my_peer := fsm.local_peer_id
	if fsm.state == NetworkSessionFSM.State.SEALED:
		# 尚未进同意流程：先触发链路恢复握手
		fsm.on_link_ok(now)
		if is_host():
			_broadcast(_envelope("sys_link_ok", state.round, {}))
	if fsm.state != NetworkSessionFSM.State.AWAITING_CONSENT:
		# 仍把票发出去，让对端能补齐状态
		pass
	# 本地立刻记一票
	fsm.submit_consent(my_peer, yes, now)
	if not is_host():
		_send_to_host(_envelope("sys_consent", state.round, {"peer": my_peer, "yes": yes}))
	else:
		_broadcast(_envelope("sys_consent", state.round, {"peer": my_peer, "yes": yes}))
	status_text.emit("已确认继续，等待对方…" if yes else "已拒绝继续")


## 恢复：校验 SessionSnapshot（seq/checksum 闸门）→ restore rules → 开闸。
func restore_from_snapshot(snap: Dictionary) -> void:
	var rules_snap: Dictionary = snap
	var is_session_snap := snap.has("schema_version") and snap.has("rules") and snap.has("checksum")
	if is_session_snap:
		last_session_snap = snap.duplicate(true)
		var now := Time.get_ticks_msec()
		if not fsm.restore_from_snapshot(snap, now):
			# 校验失败 → Fail（宁可判负不静默 desync）
			return
		var r: Variant = snap.get("rules", {})
		if typeof(r) == TYPE_DICTIONARY:
			rules_snap = r
	state.restore(rules_snap)
	_pending_actions = [int(state.pending[0]), int(state.pending[1])]
	_locks = [_pending_actions[0] >= 0, _pending_actions[1] >= 0]
	_revealing = false
	# 显式字段才认；缺省当作未开局，避免误把 opening 当已完成导致结算走 resolve_turn
	_opening_done = _opening_done or bool((snap.get("session", {}) as Dictionary).get("opening_done", false))
	if state.is_over():
		_set_session(Session.GAME_OVER)
	else:
		_set_session(Session.IN_BATTLE)
	# 恢复后必须重开选招窗，否则按钮永久灰
	if is_session_snap and not state.is_over():
		if is_host() or _mode == Mode.HOTSEAT or ai_takeover:
			round_begun.emit(state.round)
			if is_host():
				_broadcast(_envelope("select_window", state.round, {"round": state.round, "window_ms": 5000}))
		else:
			round_begun.emit(state.round)
	if is_session_snap:
		# Resuming → Connected，打开输入闸门
		fsm.confirm_restore(true, Time.get_ticks_msec())


## 完整 SessionSnapshot（rules + session + consent + checksum）。热座/单机用 get_snapshot()。
func get_session_snapshot() -> Dictionary:
	return fsm.build_snapshot(Time.get_ticks_msec(), "manual", state.snapshot(), _session_meta())


func get_net_state_name() -> String:
	return fsm.get_state_name()


## Session 层输入闸门：非 Connected 一律拒绝选招。
func is_input_open() -> bool:
	if _mode == Mode.HOTSEAT or ai_takeover:
		return _session == Session.IN_BATTLE
	return fsm.is_input_open() and _session == Session.IN_BATTLE


# ---------- 查询 ----------

func get_mode() -> int:
	return _mode


func get_session() -> int:
	return _session


## 0=我/左座/房主, 1=对手/右座/客户端。热座下为当前焦点座位。
func get_local_role() -> int:
	return _local_role


func is_host() -> bool:
	if _mode == Mode.HOTSEAT or ai_takeover:
		return true
	if provider == null:
		return false
	return provider.is_host()


func get_snapshot() -> Dictionary:
	return state.snapshot()


func get_provider_endpoints() -> PackedStringArray:
	if provider == null:
		return PackedStringArray()
	return provider.get_local_endpoints()


func get_rtt_ms() -> int:
	if provider == null:
		return -1
	return provider.get_rtt_ms(1 if is_host() else 1)


# ---------- 传输回调 ----------

func _on_provider_connected(peer_id: int) -> void:
	status_text.emit("传输已连接 (id=%d)" % peer_id)
	if provider != null:
		_local_role = 0 if provider.is_host() else 1
	_sync_fsm_identity()
	if _mode == Mode.ENET and not is_host():
		# 会话层 hello，让房主知道本端就绪
		provider.send_reliable(1, _envelope("hello", 0, {"name": "client"}))


func _sync_fsm_identity() -> void:
	fsm.is_host = is_host()
	fsm.host_peer_id = 1
	fsm.local_peer_id = 1 if is_host() else 2
	fsm.state = NetworkSessionFSM.State.CONNECTED
	_last_hb_rx_ms = 0
	_hb_timer = 0.0
	_countdown_sent = false
	_resume_sent = false


func _on_provider_disconnected(reason: String) -> void:
	if _self_closing or ai_takeover:
		return
	status_text.emit("连接断开：%s" % reason)
	if _session == Session.GAME_OVER:
		peer_left.emit(0, reason)
		if _rematch_want:
			_rematch_want = false
			rematch_answered.emit(false)
		status_text.emit("对方已离开")
		return
	if _session == Session.IN_BATTLE or _session == Session.READY_CHECK or _session == Session.SEALED:
		peer_left.emit(0, reason)
		if _mode == Mode.ENET and not state.is_over():
			# 产品优先：对方掉线/离开 → 人机接管继续可玩
			begin_ai_takeover("peer_disconnected:%s" % reason)
			return
		if _mode == Mode.ENET:
			# 硬断 → 立即封存（不直接 IDLE）；保留判负恢复路径
			if _session == Session.IN_BATTLE or _session == Session.READY_CHECK:
				seal("peer_disconnected:%s" % reason)
			fsm.on_peer_lost(Time.get_ticks_msec(), reason)
		else:
			_set_session(Session.IDLE)
	elif _session == Session.LOBBY and _mode == Mode.ENET:
		peer_left.emit(0, reason)
		_set_session(Session.IDLE)


func _on_provider_packet(from_id: int, data: Dictionary) -> void:
	var type := str(data.get("type", ""))
	var payload: Dictionary = data.get("payload", {})
	if typeof(payload) != TYPE_DICTIONARY:
		payload = {}
	var round_no := int(data.get("round", 0))

	# 跨回合重放/旧包直接丢
	if round_no > 0 and state.round > 0 and round_no < state.round and type in [
		"submit_action", "actions_revealed", "round_result", "reveal_request", "timeout_request"
	]:
		return

	match type:
		"hello":
			# 对端就绪（房主收）→ 等房主点「接受」再开战
			if is_host():
				peer_joined.emit(from_id, payload)
				# 已在对局/已接受过则忽略重复 hello，避免把状态打回 READY_CHECK
				if _session == Session.LOBBY or _session == Session.IDLE:
					_set_session(Session.READY_CHECK)
					join_requested.emit(from_id, payload)
					status_text.emit("对方已连接，是否接受并开启对战？")
				elif _session == Session.READY_CHECK:
					join_requested.emit(from_id, payload)
		"ready":
			if is_host():
				peer_joined.emit(from_id, payload)
				if _session == Session.LOBBY or _session == Session.IDLE:
					_set_session(Session.READY_CHECK)
					join_requested.emit(from_id, payload)
					status_text.emit("对方已就绪，是否接受并开启对战？")
		"join_rejected":
			status_text.emit("房主拒绝了加入")
			battle_error.emit("join_rejected", "host declined")
			leave()
		"rematch_request":
			if not _rematch_want:
				rematch_offer.emit()
				status_text.emit("对方想再来一局")
			_peer_rematch_want = true
			if _rematch_want:
				_confirm_rematch()
		"rematch_answer":
			var yes := bool(payload.get("yes", false))
			_peer_rematch_want = yes
			if yes and _rematch_want:
				_confirm_rematch()
			else:
				rematch_answered.emit(yes)
				if not yes:
					status_text.emit("对方不想再来一局")
		"battle_start":
			if not is_host():
				var snap: Dictionary = payload.get("snapshot", state.snapshot())
				var seat: Dictionary = payload.get("seat", {})
				# 以房主下发的座位为准，避免本地 role 猜错导致 UI 对调
				if seat.has("client"):
					_local_role = int(seat["client"])
				else:
					_local_role = 1
				# 新一局：清掉上一局残留
				_pending_actions = [-1, -1]
				_locks = [false, false]
				_revealing = false
				_opening_done = false
				_opening_applied = false
				restore_from_snapshot(snap)
				_set_session(Session.IN_BATTLE)
				battle_started.emit(snap)
				if not _opening_done and int(snap.get("round", 1)) == GameRules.OPENING_ROUND and int(snap.get("phase", 0)) == GameRules.Phase.OPENING:
					pass
				elif int(snap.get("round", 1)) > GameRules.OPENING_ROUND:
					_opening_done = true
					round_begun.emit(state.round)
		"opening_result":
			if not is_host():
				var res: Dictionary = payload.get("result", {})
				var snap: Dictionary = payload.get("snapshot", {})
				# 开窗前清残留，避免旧 pending 让按钮灰死
				state.pending = [-1, -1]
				_pending_actions = [-1, -1]
				_locks = [false, false]
				if not snap.is_empty():
					restore_from_snapshot(snap)
				state.pending = [-1, -1]
				_pending_actions = [-1, -1]
				_locks = [false, false]
				_opening_done = true
				_opening_applied = true
				actions_revealed.emit([GameRules.Action.ZAN, GameRules.Action.ZAN], res)
				if not state.is_over():
					round_begun.emit(state.round)
		"submit_action":
			if is_host():
				var role := int(payload.get("from_role", from_id % 2))
				_on_submit_received(role, payload)
		"reveal_request":
			if is_host():
				_try_host_reveal()
		"timeout_request":
			if is_host():
				if bool(payload.get("fill_only", false)):
					auto_fill_missing()
				else:
					# 不立即填默认：交给拍2/封盘闸
					_try_host_reveal()
		"actions_revealed":
			if not is_host():
				var acts: Array = payload.get("actions", [-1, -1])
				state.pending = [int(acts[0]), int(acts[1])]
				_pending_actions = [int(acts[0]), int(acts[1])]
				_revealing = true
				# 等 round_result 再 emit 终态；此处先放招式
				# 完整 results 在 round_result
		"select_window":
			if not is_host():
				var rno := int(payload.get("round", state.round + 1))
				_begin_remote_round(rno)
				state.round = rno
				round_begun.emit(rno)
		"round_result":
			if not is_host():
				var res: Dictionary = payload.get("result", {})
				var snap: Dictionary = payload.get("snapshot", {})
				var acts: Array = payload.get("actions", [-1, -1])
				if not snap.is_empty():
					restore_from_snapshot(snap)
				# 快照里 pending 已被 resolve 清空；保留本回合招式供 UI/测试
				_pending_actions = [int(acts[0]), int(acts[1])] if acts.size() >= 2 else _pending_actions
				_locks = [true, true]
				_actions_revealed_emit(acts, res)
				if state.is_over():
					_set_session(Session.GAME_OVER)
				else:
					# 下一窗由 select_window 开
					_revealing = false
		"sealed":
			_set_session(Session.SEALED)
			sealed.emit(str(payload.get("reason", "remote")))
		"sys_sealed":
			var rsnap: Dictionary = payload.get("snapshot", {})
			var rreason := str(payload.get("reason", "remote"))
			if not rsnap.is_empty():
				last_session_snap = rsnap.duplicate(true)
				fsm.adopt_remote_seal(rsnap, rreason, Time.get_ticks_msec())
			else:
				fsm.request_seal(Time.get_ticks_msec(), rreason, {}, {})
			_countdown_sent = false
			_resume_sent = false
			_set_session(Session.SEALED)
			sealed.emit(rreason)
		"resume_vote":
			pass
		"sys_link_ok":
			if fsm.state == NetworkSessionFSM.State.SEALED:
				fsm.on_link_ok(Time.get_ticks_msec())
		"sys_consent":
			var cpeer := int(payload.get("peer", from_id))
			var cyes := bool(payload.get("yes", true))
			# 对端可能比本端先进入同意流程：先补齐 AWAITING_CONSENT，再记票
			if fsm.state == NetworkSessionFSM.State.SEALED:
				fsm.on_link_ok(Time.get_ticks_msec())
			fsm.submit_consent(cpeer, cyes, Time.get_ticks_msec())
			status_text.emit("对方已确认，继续对局…" if cyes else "对方拒绝继续")
		"sys_countdown":
			var resume_at := int(payload.get("resume_at_host_ms", 0))
			var cseq := int(payload.get("seq", 0))
			if cseq > 0 and cseq < fsm.seq:
				return
			_apply_host_clock(payload)
			fsm.begin_countdown(resume_at, Time.get_ticks_msec())
			fsm.on_resume_ack(fsm.host_peer_id)  # 房主发起 COUNTDOWN 即视为其已就绪
			if not is_host():
				_send_to_host(_envelope("sys_resume_ack", state.round, {"peer": fsm.local_peer_id, "seq": fsm.seq}))
		"sys_resume_ack":
			if is_host():
				fsm.on_resume_ack(int(payload.get("peer", from_id)))
		"sys_resume":
			var ssnap: Dictionary = payload.get("snapshot", {})
			var sseq := int(payload.get("seq", 0))
			if sseq > 0 and sseq < fsm.seq:
				return
			if not ssnap.is_empty():
				restore_from_snapshot(ssnap)
			else:
				fsm.confirm_restore(true, Time.get_ticks_msec())
		"sys_game_over":
			var loser := int(payload.get("loser", -1))
			var greason := str(payload.get("reason", "net_forfeit"))
			fsm.force_fail(loser, greason, Time.get_ticks_msec())
		"hb":
			# 收到对端心跳 → 回 echo，并记存活
			var hseq := int(payload.get("seq", 0))
			var t_send := int(payload.get("t_send", 0))
			_last_hb_rx_ms = Time.get_ticks_msec()
			if _mode != Mode.HOTSEAT:
				var echo := _envelope("hb_echo", 0, {"seq": hseq, "t_send": t_send, "t_echo": Time.get_ticks_msec(), "host_now": Time.get_ticks_msec()})
				if is_host():
					_send_reliable_to(from_id, echo)
				else:
					_send_to_host(echo)
		"hb_echo":
			_last_hb_rx_ms = Time.get_ticks_msec()
			var t_send2 := int(payload.get("t_send", 0))
			var now2 := Time.get_ticks_msec()
			if t_send2 > 0:
				var rtt := now2 - t_send2
				fsm.on_heartbeat_sample(now2, rtt)
			else:
				fsm.on_heartbeat_sample(now2, 0)
			# 仅客户端用 echo 的 host_now 校时；主机误用会污染 skew 卡死倒计时
			if not is_host():
				_apply_host_clock(payload)
		"bye":
			peer_left.emit(from_id, "bye")
			if _mode == Mode.ENET and not ai_takeover and not state.is_over():
				if _session == Session.IN_BATTLE or _session == Session.SEALED or _session == Session.READY_CHECK:
					begin_ai_takeover("peer_bye")
		_:
			pass


func _on_submit_received(role: int, payload: Dictionary) -> void:
	if _revealing:
		return
	if role < 0 or role > 1:
		return
	var action := int(payload.get("action", -1))
	if not state.can_use_action(role, action):
		action = GameRules.Action.FANG if state.shield[role] >= 1 else GameRules.Action.ZAN
		if not state.can_use_action(role, action):
			action = GameRules.Action.ZAN
	_pending_actions[role] = action
	_locks[role] = true
	action_committed.emit(role, action)
	# 只锁定，不在此结算：统一等拍 2 / 窗口结束（双方便招也等节奏）


# ---------- 权威侧揭示 / 结算 ----------

func _maybe_reveal_local() -> void:
	if _revealing or state.is_over():
		return
	if _locks[0] and _locks[1]:
		_do_host_reveal()
	elif _grace_left <= 0.0 and _session == Session.IN_BATTLE:
		_grace_left = LOCK_GRACE_SEC


func _try_host_reveal() -> void:
	if _revealing or state.is_over():
		return
	if _locks[0] and _locks[1]:
		_do_host_reveal()
	elif _grace_left <= 0.0:
		_grace_left = LOCK_GRACE_SEC


func _pump_grace(delta: float) -> void:
	if _grace_left <= 0.0:
		return
	_grace_left -= delta
	if _grace_left > 0.0:
		return
	_grace_left = 0.0
	if _session != Session.IN_BATTLE or state.is_over() or _revealing:
		return
	# grace 超时：缺锁方按默认
	request_timeout_default()


func _do_host_reveal() -> void:
	if _revealing or state.is_over():
		return
	_revealing = true
	_grace_left = 0.0
	var a0 := int(_pending_actions[0])
	if a0 < 0:
		a0 = int(state.pending[0])
	if a0 < 0:
		a0 = _default_action(0)
	var a1 := int(_pending_actions[1])
	if a1 < 0:
		a1 = int(state.pending[1])
	if a1 < 0:
		a1 = _default_action(1)
	_pending_actions = [a0, a1]
	state.pending = [a0, a1]

	# 开局：双方点「攒」（或超时默认攒）→ 亮相，不走常规对撞结算
	# 注意：这里不能把 _revealing 置回 false 后再落入 resolve_turn，
	# 否则第二次 reveal 会把开局再算成普通攒 → 气变 2。
	if state.round == GameRules.OPENING_ROUND:
		if _opening_applied or _opening_done:
			# 已经亮相过，忽略重复 reveal
			_revealing = false
			_locks = [false, false]
			_pending_actions = [-1, -1]
			state.pending = [-1, -1]
			return
		if a0 != GameRules.Action.ZAN:
			a0 = GameRules.Action.ZAN
		if a1 != GameRules.Action.ZAN:
			a1 = GameRules.Action.ZAN
		_pending_actions = [a0, a1]
		state.pending = [a0, a1]
		_broadcast(_envelope("actions_revealed", state.round, {"actions": [a0, a1], "opening": true}))
		_revealing = true
		_finish_opening()
		_locks = [false, false]
		_pending_actions = [-1, -1]
		return

	# 原子揭示：一次广播双方招式
	_broadcast(_envelope("actions_revealed", state.round, {"actions": [a0, a1]}))

	var result: GameRules.RoundResult = GameResolve.resolve_turn(state, a0, a1)
	var res_dict := _result_to_dict(result)
	var snap := state.snapshot()
	_broadcast(_envelope("round_result", state.round, {
		"actions": [a0, a1],
		"result": res_dict,
		"snapshot": snap,
	}))
	_actions_revealed_emit([a0, a1], res_dict)
	if state.is_over():
		_set_session(Session.GAME_OVER)
	else:
		# 稍后由上层/下一轮推进
		_schedule_next_round()


func _default_action(who: int) -> int:
	# 开局窗口：未点也算「攒」确认
	if state.round == GameRules.OPENING_ROUND and not _opening_done:
		return GameRules.Action.ZAN
	var a: int = GameRules.Action.FANG if state.shield[who] >= 1 else GameRules.Action.ZAN
	if not state.can_use_action(who, a):
		a = GameRules.Action.ZAN
	return a


func _schedule_next_round() -> void:
	# 无 SceneTree（headless 单测）时不自动推进，由 debug_advance_round 手动驱动
	if not is_inside_tree() or get_tree() == null:
		return
	# 结算画面独立停留 0.8s，退下后再进下一回合
	# 结算画面独立停留（勿在 await 里调 BattleTempo）
	await get_tree().create_timer(0.8).timeout
	if _session == Session.IN_BATTLE and not state.is_over():
		_begin_next_round()


## 测试钩子：跳过表现延迟，立即进入下一回合选招。
func debug_advance_round() -> void:
	if _session == Session.IN_BATTLE and not state.is_over():
		_begin_next_round()


func _begin_next_round() -> void:
	_opening_done = true
	state.round += 1
	state.pending = [-1, -1]
	_pending_actions = [-1, -1]
	_locks = [false, false]
	_timeout_flags = [false, false]
	_revealing = false
	state.phase = GameRules.Phase.SELECTING
	round_begun.emit(state.round)
	if is_host() or _mode == Mode.HOTSEAT:
		_broadcast(_envelope("select_window", state.round, {"round": state.round}))


func _begin_remote_round(round_no: int) -> void:
	# 客户端开局窗也必须保持 _opening_done=false，否则聚光灯/6s 窗全丢
	_opening_done = round_no > GameRules.OPENING_ROUND
	# 新窗清空点选残留，否则 UI 把上回合招式当「已选」永久灰
	state.pending = [-1, -1]
	_pending_actions = [-1, -1]
	_locks = [false, false]
	_timeout_flags = [false, false]
	_revealing = false
	state.phase = GameRules.Phase.SELECTING
	round_begun.emit(round_no)


func _do_opening() -> void:
	# 产品：开局不再强制结算，改为双方点「攒」确认后再亮相
	_opening_done = false
	_opening_applied = false
	state.round = GameRules.OPENING_ROUND
	state.phase = GameRules.Phase.SELECTING
	state.pending = [-1, -1]
	_pending_actions = [-1, -1]
	_locks = [false, false]
	_revealing = false
	_set_session(Session.IN_BATTLE)
	round_begun.emit(GameRules.OPENING_ROUND)
	if _mode != Mode.HOTSEAT:
		_broadcast(_envelope("select_window", GameRules.OPENING_ROUND, {
			"round": GameRules.OPENING_ROUND,
			"window_ms": int(OPENING_SELECT_WINDOW * 1000.0),
			"opening": true,
		}))
	status_text.emit("点击「攒」开始对决")


## 开局亮相（规则 resolve_opening，不改结算语义）。
func _finish_opening() -> void:
	if _opening_applied:
		return
	_opening_applied = true
	_opening_done = true
	_revealing = false
	state.round = GameRules.OPENING_ROUND
	state.phase = GameRules.Phase.OPENING
	var r := GameResolve.resolve_opening(state)
	var res_dict := _result_to_dict(r)
	var snap := state.snapshot()
	if _mode != Mode.HOTSEAT:
		_broadcast(_envelope("opening_result", state.round, {"result": res_dict, "snapshot": snap}))
	_actions_revealed_emit([GameRules.Action.ZAN, GameRules.Action.ZAN], res_dict)
	if state.is_over():
		_set_session(Session.GAME_OVER)
	else:
		_schedule_opening_to_select()


func _schedule_opening_to_select() -> void:
	if not is_inside_tree() or get_tree() == null:
		return
	await get_tree().create_timer(0.8).timeout
	if _session == Session.IN_BATTLE and not state.is_over():
		# 开局后进入回合 2 选招；round 仍为 1 时 next 会 +1 → 2
		if state.round == GameRules.OPENING_ROUND:
			_begin_next_round()
		else:
			round_begun.emit(state.round)


func _actions_revealed_emit(actions: Array, results: Dictionary) -> void:
	actions_revealed.emit(actions, results)


# ---------- 会话 FSM 驱动（心跳 / 超时 / 房主倒计时） ----------

func _pump_session(delta: float) -> void:
	if _mode == Mode.HOTSEAT or ai_takeover:
		return
	if _session != Session.IN_BATTLE and _session != Session.SEALED:
		return
	var now := Time.get_ticks_msec()
	# 应用层心跳 1000ms（ENet 默认 timeout 5–30s 太慢）
	_hb_timer += delta
	if _hb_timer * 1000.0 >= float(NetworkSessionFSM.HB_INTERVAL_MS):
		_hb_timer = 0.0
		_send_heartbeat(now)
		# 连续丢 2 → Degraded；连续 5 → Sealed（由 fsm 计数）
		if _last_hb_rx_ms > 0 and now - _last_hb_rx_ms >= NetworkSessionFSM.HB_INTERVAL_MS:
			fsm.on_heartbeat_miss(now)
	fsm.tick(now)
	# 房主：Consent 齐后由 fsm 自动 begin_countdown；此处把 COUNTDOWN 广播出去
	if is_host() and fsm.state == NetworkSessionFSM.State.COUNTDOWN and fsm.get_resume_at_host_ms() > 0:
		if not _countdown_sent:
			_countdown_sent = true
			_broadcast(_envelope("sys_countdown", state.round, {
				"resume_at_host_ms": fsm.get_resume_at_host_ms(),
				"seq": fsm.seq,
				"host_now": now,
			}))
			if not fsm._resume_acks.has(fsm.local_peer_id):
				fsm.on_resume_ack(fsm.local_peer_id)
	# 房主：倒计时结束且 ACK 齐 → 广播 RESUME
	if is_host() and fsm.state == NetworkSessionFSM.State.RESUMING:
		if not _resume_sent:
			_resume_sent = true
			_broadcast(_envelope("sys_resume", state.round, {
				"snapshot": last_session_snap.duplicate(true),
				"seq": fsm.seq,
			}))
			# 本地 restore
			if not last_session_snap.is_empty() and last_session_snap.has("rules"):
				restore_from_snapshot(last_session_snap.duplicate(true))
			else:
				fsm.confirm_restore(true, now)


func _send_heartbeat(now_ms: int) -> void:
	_hb_seq += 1
	var env := _envelope("hb", 0, {"seq": _hb_seq, "t_send": now_ms, "host_now": now_ms})
	if is_host():
		_broadcast(env)
	else:
		_send_to_host(env)


func _apply_host_clock(payload: Dictionary) -> void:
	var host_now := int(payload.get("host_now", 0))
	if host_now <= 0:
		return
	var local_now := Time.get_ticks_msec()
	fsm.set_host_skew(host_now - local_now)


func _send_reliable_to(to_id: int, env: Dictionary) -> void:
	if provider == null:
		return
	provider.send_reliable(to_id, env)


func _session_meta() -> Dictionary:
	var meta := {
		"game_phase_name": GameRules.Phase.keys()[state.phase] if state.phase >= 0 and state.phase < GameRules.Phase.keys().size() else "SELECTING",
		"beat": 0,
		"beat_elapsed_ms": 0,
		"select_window_ms": 5000,
		"opening_done": _opening_done,
		"round_resolved": false,
	}
	if session_meta_hook.is_valid():
		var extra: Variant = session_meta_hook.call()
		if typeof(extra) == TYPE_DICTIONARY:
			for k in (extra as Dictionary):
				meta[k] = extra[k]
	return meta


func _on_fsm_state(_from_s: int, to_s: int, reason: String) -> void:
	match to_s:
		NetworkSessionFSM.State.DEGRADED:
			status_text.emit("网络不佳")
		NetworkSessionFSM.State.SEALED:
			if _session != Session.SEALED:
				_set_session(Session.SEALED)
		NetworkSessionFSM.State.AWAITING_CONSENT:
			_set_session(Session.SEALED)
			status_text.emit("链路恢复，请双方确认是否继续")
		NetworkSessionFSM.State.COUNTDOWN:
			status_text.emit("即将恢复…")
		NetworkSessionFSM.State.RESUMING:
			status_text.emit("恢复中…")
		NetworkSessionFSM.State.CONNECTED:
			if _session == Session.SEALED:
				_set_session(Session.IN_BATTLE)
			status_text.emit("已恢复")
		NetworkSessionFSM.State.FAIL:
			_set_session(Session.GAME_OVER)
			status_text.emit("终局：%s" % reason)


func _on_fsm_failed(loser_peer: int, reason: String) -> void:
	var loser_role := -1
	if loser_peer == fsm.host_peer_id:
		loser_role = 0
	elif loser_peer > 0:
		loser_role = 1
	if is_host() or _mode == Mode.HOTSEAT:
		_broadcast(_envelope("sys_game_over", state.round, {"loser": loser_peer, "reason": reason}))
	session_failed.emit(loser_role, reason)
	# 把判负写进 rules.winner（0=左/房主胜, 1=右/客户端胜, 2=平），不改结算表
	var w := fsm.winner_on_fail()
	state.winner = w
	state.phase = GameRules.Phase.GAME_OVER


# ---------- 信封 ----------

func _envelope(type: String, round_no: int, payload: Dictionary) -> Dictionary:
	return {
		"v": ENVELOPE_VERSION,
		"type": type,
		"round": round_no,
		"from_role": _local_role,
		"payload": payload,
	}


func _broadcast(env: Dictionary) -> void:
	if provider == null:
		return
	if _mode == Mode.HOTSEAT:
		return
	provider.send_reliable(0, env)


func _send_to_host(env: Dictionary) -> void:
	if provider == null:
		return
	if is_host():
		# 房主本地直接走分发，不经网络
		_on_provider_packet(1, env)
		return
	provider.send_reliable(1, env)


func _set_session(s: int) -> void:
	if _session == s:
		return
	_session = s
	session_changed.emit(_session)


func _result_to_dict(r: GameRules.RoundResult) -> Dictionary:
	return {
		"actions": r.actions.duplicate(),
		"hp_delta": r.hp_delta.duplicate(),
		"qi_delta": r.qi_delta.duplicate(),
		"shield_delta": r.shield_delta.duplicate(),
		"hit": r.hit.duplicate(),
		"blocked": r.blocked.duplicate(),
		"opening": r.opening,
		"text": r.text,
		"timeout": _timeout_flags.duplicate(),
	}

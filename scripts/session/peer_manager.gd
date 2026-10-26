## peer_manager.gd
## 会话与指令语义：后端切换、建房/加入、锁后提交、原子揭示、超时默认、封存挂钩。
## 房主权威；客户端只 apply 房主下发的结算，不本地 GameResolve。
## 信封统一 {v,type,round,from_role,payload}，传输细节全部走 NetworkProvider。
class_name PeerManager
extends Node

enum Mode { HOTSEAT, ENET, WEBSOCKET }
## COUNTDOWN 加在尾部：旧枚举值不变（快照/测试都按名字判断）。
enum Session { IDLE, LOBBY, READY_CHECK, IN_BATTLE, SEALED, GAME_OVER, COUNTDOWN }

const ENVELOPE_VERSION := 1
## 双方准备后的开局倒计时（可注入时钟：debug_tick_countdown）。
const LOBBY_COUNTDOWN_MS := 5000
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
## 对方申请加入，等房主「同意 / 拒绝」
signal join_requested(peer_id: int, profile: Dictionary)
## 房主答复（客户端侧）：true=进等待页，false=回入口
signal join_answered(yes: bool)
## 房间信息 / 座位状态变化（房主本地与客户端都会发）
signal room_updated(room: Dictionary)
signal ready_changed(host_ready: bool, client_ready: bool)
## 等待页 5s 倒计时（可注入）
signal lobby_countdown_tick(remain_ms: int)
## 未开局时对方/房主离开 → 提示并回入口
signal lobby_left(reason: String)
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

## 房间模型：{room_id,name,mode,mastery,host_name,players,max}
var room: Dictionary = {}
## 最近一次 battle_start 下发的 MatchConfig（房主=发出的，客户端=收到的）
var last_battle_config: Dictionary = {}
var _host_ready: bool = false
var _client_ready: bool = false
var _lobby_cd_left_ms: int = 0
## 已弹过加入请求的 peer，防重复弹窗（只保留一个确认弹窗）
var _join_peer_id: int = -1

var _self_closing: bool = false
## 传输层唯一对端 id：客户端固定为房主 1（传输层已把 src 改写为 1）；
## 房主在收到第一包 hello 时学习。<=0 表示未知（热座/测试直连）→ 不启用发送者过滤。
var _remote_peer_id: int = -1

## 本回合锁定缓存（权威侧）
var _pending_actions: Array = [-1, -1]
var _locks: Array = [false, false]
var _revealing: bool = false
var _grace_left: float = 0.0
var _opening_done: bool = false
## 开局亮相是否已结算（防 resolve_opening 重复加资源）
var _opening_applied: bool = false
## 本小局刚结束、整场未到 12 分 → 等表现停留后重开一小局（回合 1 开局亮相）。
## 置位后由 _do_opening() 清除；debug_advance_round() 也据此走「重开小局」而不是「回合 +1」。
var _round_restart_pending: bool = false
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
	# 自主封存（心跳超时）拿不到局面 → 由注入方提供活快照
	fsm.snapshot_provider = _live_rules_snapshot
	fsm.state_changed.connect(func(from_s: int, to_s: int, reason: String):
		net_state_changed.emit(NetworkSessionFSM.state_name(to_s), reason)
		_on_fsm_state(from_s, to_s, reason))
	fsm.sealed.connect(func(snap: Dictionary, reason: String):
		last_session_snap = snap
		_broadcast_sealed(snap, reason))
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
	if _session == Session.COUNTDOWN and _lobby_cd_left_ms > 0:
		_tick_lobby_countdown(int(delta * 1000.0))
	_pump_grace(delta)
	_pump_session(delta)


# ---------- 后端与模式 ----------

func set_backend(mode: int) -> Error:
	# --script/headless 下 _ready 不保证触发，接线在这里幂等补一次
	_wire_fsm()
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
	# --script/headless 下 _ready 不保证触发，接线在这里幂等补一次
	_wire_fsm()
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

## opts: {room_name?, game_mode?, mastery?, host_name?, port?, token?, max_players?, use_discover?, discover_port?}
## 注意：opts["mode"] 仍是传输后端（Mode.ENET）；规则模式用 game_mode（"classic"|"lesson"）。
func host_game(opts: Dictionary) -> Error:
	if provider == null:
		var err0 := set_backend(int(opts.get("mode", Mode.ENET)))
		if err0 != OK:
			return err0
	_token = str(opts.get("token", ""))
	var gm := str(opts.get("game_mode", "lesson"))
	if not GameRules.PRESETS.has(gm):
		gm = "lesson"
	# 精通是课间专用选项（经典无技能解锁）
	var mastery := bool(opts.get("mastery", false)) and gm == "lesson"
	room = {
		"room_id": "%s-%d" % [OS.get_model_name(), Time.get_ticks_msec()],
		"name": str(opts.get("room_name", "")).strip_edges(),
		"mode": gm,
		"mastery": mastery,
		"host_name": str(opts.get("host_name", OS.get_model_name())),
		"players": 1,
		"max": int(opts.get("max_players", 2)),
	}
	if str(room["name"]).is_empty():
		room["name"] = default_room_name(gm, mastery)
	_reset_lobby_state()
	# 新开房间：清干净上一局（按本房模式构造 BattleState）
	_reset_rules_state()
	var open_opts := opts.duplicate(true)
	open_opts["token"] = _token
	open_opts["room_name"] = room["name"]
	open_opts["room_id"] = room["room_id"]
	open_opts["host_name"] = room["host_name"]
	open_opts["game_mode"] = gm
	open_opts["mastery"] = mastery
	var err := provider.open_as_host(open_opts)
	if err != OK:
		battle_error.emit("host_failed", "open_as_host failed: %s" % error_string(err))
		return err
	_local_role = 0
	_set_session(Session.LOBBY)
	_sync_fsm_identity()
	room_updated.emit(room.duplicate(true))
	status_text.emit("已创建房间 %s，等待对手…" % str(room["name"]))
	return OK


## 默认房间名：<机型> · <经典|课间>[ · 精通]（精通仅课间）。
static func default_room_name(game_mode: String, mastery: bool = false) -> String:
	var title := "经典" if game_mode == "classic" else "课间"
	var name := "%s · %s" % [OS.get_model_name(), title]
	if mastery and game_mode != "classic":
		name += " · 精通"
	return name


## ENET: {address, port, token}；HOTSEAT: {}；WEBSOCKET: {url, token}
func join_game(opts: Dictionary) -> Error:
	# 新加入：同样清干净
	room = {}
	_reset_lobby_state()
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
		# 主动离开：对局内尽量通知对方（对方走人机接管）；未开局由 leave_room 先发消息
		if _session == Session.IN_BATTLE or _session == Session.SEALED or _session == Session.GAME_OVER:
			_broadcast(_envelope("bye", state.round, {"reason": "local_leave"}))
		_disconnect_provider()
		provider.close()
		provider = null
	_self_closing = false
	ai_takeover = false
	_remote_peer_id = -1
	_grace_left = 0.0
	room = {}
	_reset_lobby_state()
	_reset_rules_state()
	_set_session(Session.IDLE)
	status_text.emit("已离开")


## 清空血/气/盾/回合/胜负，避免下一局继承上一局（0 血满气开局等）。
## 整场（再来一局）复位：score 也归零。规则模式/精通来自房间配置（未建房时默认 lesson）。
func _reset_rules_state() -> void:
	var gm := str(room.get("mode", "lesson"))
	var mastery := bool(room.get("mastery", false))
	state = BattleState.new(gm, mastery)
	_reset_round_flags()
	_reset_opening_flags()


## 等待页状态复位（不清房间：开局配置还要用）。
func _reset_lobby_state() -> void:
	_host_ready = false
	_client_ready = false
	_lobby_cd_left_ms = 0
	_join_peer_id = -1


## 回合选招窗复位表：点选/锁定/揭示/超时角标（新窗必清，漏清会把上回合招式当「已选」）。
func _reset_round_flags() -> void:
	state.pending = [-1, -1]
	_pending_actions = [-1, -1]
	_locks = [false, false]
	_revealing = false
	_timeout_flags = [false, false]


## 开局亮相/小局重开标记复位表。
func _reset_opening_flags() -> void:
	_opening_done = false
	_opening_applied = false
	_round_restart_pending = false


## 对方离开/掉线：本地改由人机接管，对局继续（不再走封存判负）。
## 返回 true 表示已接管。
func begin_ai_takeover(reason: String = "peer_left") -> bool:
	if _mode == Mode.HOTSEAT or ai_takeover:
		return false
	if state.is_over():
		return false
	# 未开局（大厅/等待/倒计时）不接管，避免菜单页被推进 IN_BATTLE
	if _session != Session.IN_BATTLE and _session != Session.SEALED:
		_handle_lobby_peer_gone(reason)
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


## 房主开局（等待页倒计时结束 / 测试直调）：下发 battle_start + MatchConfig。
func start_battle() -> Error:
	if _mode == Mode.HOTSEAT:
		_set_session(Session.IN_BATTLE)
		_reset_rules_state()
		_do_opening()
		return OK
	if not is_host():
		# 客户端不自行开局：只表示自己准备
		set_ready(true)
		return OK
	_local_role = 0
	_reset_lobby_state()
	_set_session(Session.IN_BATTLE)
	# 新一局必须重置规则状态，否则快照会带上一局的血/气（按房间 config 构造）
	_reset_rules_state()
	last_battle_config = get_match_config()
	var snap := state.snapshot()
	_broadcast(_envelope("battle_start", 1, {
		"snapshot": snap,
		"seat": {"host": 0, "client": 1},
		"config": last_battle_config.duplicate(true),
	}))
	battle_started.emit(snap)
	_do_opening()
	return OK


## 当前 MatchConfig（battle_start 下发；房主保存的唯一配置源）。
func get_match_config() -> Dictionary:
	return {
		"mode": str(room.get("mode", "lesson")),
		"mastery": bool(room.get("mastery", false)),
		"difficulty": str(room.get("difficulty", "normal")),
	}


## 客户端采纳房主下发的房间 config，并按它重建规则状态。
func _apply_room(r: Dictionary) -> void:
	if r.is_empty():
		return
	room = r.duplicate(true)
	_reset_rules_state()


## 客户端采纳 battle_start 的 MatchConfig（config 缺失时沿用房间值）。
func _apply_match_config(cfg: Dictionary) -> void:
	if not cfg.is_empty():
		last_battle_config = cfg.duplicate(true)
	room["mode"] = str(cfg.get("mode", room.get("mode", "lesson")))
	room["mastery"] = bool(cfg.get("mastery", room.get("mastery", false)))
	room["difficulty"] = str(cfg.get("difficulty", "normal"))
	_reset_rules_state()


## 房主点「同意加入」：进等待页（不是直接开战，双方都准备后才倒计时）。
func accept_join() -> Error:
	if _mode == Mode.HOTSEAT or not is_host():
		return start_battle()
	if _session != Session.LOBBY and _session != Session.READY_CHECK:
		return ERR_ALREADY_IN_USE
	_reset_lobby_state()
	room["players"] = 2
	_set_session(Session.READY_CHECK)
	_broadcast(_envelope("join_answer", 0, {"yes": true}))
	_broadcast_room_state()
	status_text.emit("已接受，等待双方准备")
	return OK


## 房主点「拒绝」：通知客户端被拒，房间继续等待其他人。
func reject_join() -> void:
	if not is_host():
		return
	_broadcast(_envelope("join_answer", 0, {"yes": false, "reason": "host_declined"}))
	_reset_lobby_peer()
	status_text.emit("已拒绝加入")


# ---------- 等待页：准备 / 倒计时 / 离开 ----------

## 本方准备/取消准备（双方都要点；房主汇总后广播 room_state）。
func set_ready(yes: bool) -> void:
	if _mode == Mode.HOTSEAT:
		return
	if _session == Session.COUNTDOWN or _session == Session.IN_BATTLE:
		return
	if _session != Session.LOBBY and _session != Session.READY_CHECK:
		return
	if is_host():
		if _host_ready == yes:
			return
		_host_ready = yes
		_broadcast_room_state()
	else:
		if _client_ready == yes:
			return
		_client_ready = yes
		_send_to_host(_envelope("ready", 0, {"yes": yes}))
		ready_changed.emit(_host_ready, _client_ready)
	_maybe_start_lobby_countdown()


func get_room() -> Dictionary:
	return room.duplicate(true)


## [host_ready, client_ready]（测试/UI 共用）
func get_ready_flags() -> Array:
	return [_host_ready, _client_ready]


func get_lobby_countdown_ms() -> int:
	return _lobby_cd_left_ms


## 测试钩子：注入等待页倒计时（不依赖真实时钟）。5s 断言用它推进。
func debug_tick_countdown(ms: int) -> void:
	_tick_lobby_countdown(ms)


## 未开局时离开房间：通知对方 → 对方提示并回入口。对局内离开走 leave()（人机接管）。
func leave_room() -> void:
	if _session != Session.LOBBY and _session != Session.READY_CHECK and _session != Session.COUNTDOWN:
		return
	if provider != null and _mode != Mode.HOTSEAT:
		_broadcast(_envelope("leave_room", 0, {}))
	leave()


func _maybe_start_lobby_countdown() -> void:
	if not is_host() or _session != Session.READY_CHECK:
		return
	if not _host_ready or not _client_ready:
		return
	_begin_lobby_countdown(LOBBY_COUNTDOWN_MS)
	_broadcast(_envelope("countdown_start", 0, {"remain_ms": LOBBY_COUNTDOWN_MS}))
	status_text.emit("双方已准备，%d 秒后开局" % int(ceil(LOBBY_COUNTDOWN_MS / 1000.0)))


func _begin_lobby_countdown(remain_ms: int) -> void:
	_lobby_cd_left_ms = maxi(0, remain_ms)
	_set_session(Session.COUNTDOWN)
	lobby_countdown_tick.emit(_lobby_cd_left_ms)


## 房主本地推进倒计时；到 0 由房主开局（客户端只更新显示，等 battle_start）。
func _tick_lobby_countdown(ms: int) -> void:
	if _session != Session.COUNTDOWN:
		return
	if ms <= 0 and _lobby_cd_left_ms <= 0:
		return
	_lobby_cd_left_ms = maxi(0, _lobby_cd_left_ms - ms)
	lobby_countdown_tick.emit(_lobby_cd_left_ms)
	if _lobby_cd_left_ms <= 0 and is_host():
		start_battle()


## 房主汇总座位状态：本地 emit + 广播（房主权威）。
func _broadcast_room_state() -> void:
	if is_host():
		_broadcast(_envelope("room_state", 0, {
			"room": room.duplicate(true),
			"host_ready": _host_ready,
			"client_ready": _client_ready,
		}))
	ready_changed.emit(_host_ready, _client_ready)
	room_updated.emit(room.duplicate(true))


## 解绑当前大厅对端：拒绝/掉线后房间继续等下一个客户端。
## 不解绑的话发送者过滤（_remote_peer_id）会把下一个客户端的 join_request 全丢掉。
func _reset_lobby_peer() -> void:
	_join_peer_id = -1
	_remote_peer_id = -1


## 未开局时对方离开：关房、提示、回入口（不做 host migration）。
func _handle_lobby_peer_gone(_reason: String) -> void:
	if _session == Session.IDLE:
		return
	var msg := "房主已离开，请重新选择模式" if not is_host() else "对方已离开"
	_self_closing = true
	if provider != null:
		_disconnect_provider()
		provider.close()
		provider = null
	_self_closing = false
	_reset_lobby_peer()
	room = {}
	_reset_lobby_state()
	_reset_rules_state()
	_set_session(Session.IDLE)
	status_text.emit(msg)
	lobby_left.emit(msg)


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
	# 接管态保留 ai_takeover=true：is_host() 才能走房主开局；清掉会落到客户端分支（READY_CHECK 死路）
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
				a = state.default_action(i)
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
	# sys_sealed 的广播已收敛到 _broadcast_sealed()（挂 fsm.sealed），此处不再重复发
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
	# 本地立刻记一票
	fsm.submit_consent(my_peer, yes, now)
	if not is_host():
		_send_to_host(_envelope("sys_consent", state.round, {"peer": my_peer, "yes": yes}))
	else:
		_broadcast(_envelope("sys_consent", state.round, {"peer": my_peer, "yes": yes}))
	status_text.emit("已确认继续，等待对方…" if yes else "已拒绝继续")


## 恢复：校验 SessionSnapshot（seq/checksum 闸门）→ restore rules → 开闸。
## 返回 false = 快照 mode/mastery 与本地房间配置不一致（房主权威，拒绝恢复）。
func restore_from_snapshot(snap: Dictionary) -> bool:
	var rules_snap: Dictionary = snap
	var is_session_snap := snap.has("schema_version") and snap.has("rules") and snap.has("checksum")
	if is_session_snap:
		last_session_snap = snap.duplicate(true)
		var now := Time.get_ticks_msec()
		if not fsm.restore_from_snapshot(snap, now):
			# 校验失败 → Fail（宁可判负不静默 desync）
			return false
		var r: Variant = snap.get("rules", {})
		if typeof(r) == TYPE_DICTIONARY:
			rules_snap = r
	if not state.restore(rules_snap):
		battle_error.emit("snapshot_mismatch", "mode/mastery mismatch")
		status_text.emit("对局配置不一致，已退出对局")
		_set_session(Session.IDLE)
		return false
	_pending_actions = [int(state.pending[0]), int(state.pending[1])]
	_locks = [_pending_actions[0] >= 0, _pending_actions[1] >= 0]
	_revealing = false
	# 快照带 opening_done 时以快照为准：只「或」不复位的话，空快照恢复后 round 回到 1
	# 而 _opening_done 仍为 true → 开局分支会把之后每一次揭示都吞掉（不结算/不广播/不推进）。
	var sess_meta: Dictionary = {}
	var raw_sess: Variant = snap.get("session", {})
	if typeof(raw_sess) == TYPE_DICTIONARY:
		sess_meta = raw_sess
	if sess_meta.has("opening_done"):
		_opening_done = bool(sess_meta["opening_done"])
		_opening_applied = _opening_done
	# 整场结束判据：小局 winner 已定 或 任一方 score 到 12（max(score) >= WIN_SCORE）
	var match_over_now: bool = state.is_over() or state.is_match_over()
	if match_over_now:
		_set_session(Session.GAME_OVER)
	else:
		_set_session(Session.IN_BATTLE)
	# 恢复后必须重开选招窗，否则按钮永久灰
	if is_session_snap and not match_over_now:
		if is_host() or _mode == Mode.HOTSEAT or ai_takeover:
			round_begun.emit(state.round)
			if is_host():
				var window_ms := int(BattleTempo.total_window(state.round) * 1000.0)
				if state.round == GameRules.OPENING_ROUND and not _opening_done:
					window_ms = int(OPENING_SELECT_WINDOW * 1000.0)
				_broadcast(_envelope("select_window", state.round, {"round": state.round, "window_ms": window_ms}))
		else:
			round_begun.emit(state.round)
	if is_session_snap:
		# Resuming → Connected，打开输入闸门
		fsm.confirm_restore(true, Time.get_ticks_msec())
	return true


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
	# 客户端侧对端恒为房主（EnetProvider 把 host 包 src 改写为 1；LocalProvider host=1）。
	# 房主侧尚不知对端 id（传输层在 hello 到达时才暴露）→ 由 hello 学习。
	_remote_peer_id = 1 if (provider != null and not provider.is_host()) else -1
	if provider != null:
		_local_role = 0 if provider.is_host() else 1
	_sync_fsm_identity()
	if _mode == Mode.ENET and not is_host():
		# 会话层 join_request：房主同意后才进等待页（不再自动开战）
		provider.send_reliable(1, _envelope("join_request", 0, {"name": OS.get_model_name()}))


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
	# 未开局（大厅/等待页/倒计时）离开：提示 + 回入口，不进人机接管/封存
	if _session == Session.LOBBY:
		# 大厅里房主还在等：加入方没连上/被拒 → 房间继续（解绑对端后接待下一个）。
		# 不解绑的话 _remote_peer_id 仍指向旧 id，下一个客户端的包会被发送者过滤丢掉。
		if is_host():
			_reset_lobby_peer()
		else:
			_handle_lobby_peer_gone(reason)
		return
	if _session == Session.READY_CHECK or _session == Session.COUNTDOWN:
		_handle_lobby_peer_gone(reason)
		return
	if _session == Session.GAME_OVER:
		peer_left.emit(0, reason)
		if _rematch_want:
			_rematch_want = false
			rematch_answered.emit(false)
		status_text.emit("对方已离开")
		return
	if _session == Session.IN_BATTLE or _session == Session.SEALED:
		peer_left.emit(0, reason)
		if _mode == Mode.ENET and not state.is_over():
			# 产品优先：对方掉线/离开 → 人机接管继续可玩。
			# 但先封存一份完整快照（rules+session），否则这次对局状态彻底丢失、也无从恢复。
			if _session != Session.SEALED:
				seal("peer_disconnected:%s" % reason)
			begin_ai_takeover("peer_disconnected:%s" % reason)
			return
		if _mode == Mode.ENET:
			# 硬断 → 立即封存（不直接 IDLE）；保留判负恢复路径
			if _session == Session.IN_BATTLE:
				seal("peer_disconnected:%s" % reason)
			fsm.on_peer_lost(Time.get_ticks_msec(), reason)
		else:
			_set_session(Session.IDLE)


func _on_provider_packet(from_id: int, data: Dictionary) -> void:
	var type := str(data.get("type", ""))
	var payload: Dictionary = data.get("payload", {})
	if typeof(payload) != TYPE_DICTIONARY:
		payload = {}
	var round_no := int(data.get("round", 0))

	# 发送者校验：只接受「唯一对端」的包（1v1 房间）。
	# 房主侧对端 id 由 hello 学习；_remote_peer_id<=0 表示热座/直连测试，不拦截。
	if _remote_peer_id > 0 and from_id != _remote_peer_id:
		push_warning("Net: drop %s from peer %d (bound remote=%d)" % [type, from_id, _remote_peer_id])
		return

	# 跨回合重放/旧包直接丢
	if round_no > 0 and state.round > 0 and round_no < state.round and type in [
		"submit_action", "actions_revealed", "round_result", "reveal_request", "timeout_request"
	]:
		return

	match type:
		"join_request", "hello":
			# 房主收：只提示，同意/拒绝由房主决定（join_answer）
			if not is_host():
				return
			if _remote_peer_id <= 0:
				_remote_peer_id = from_id
			peer_joined.emit(from_id, payload)
			if _session != Session.LOBBY and _session != Session.IDLE:
				# 已有对端/已开局：明确拒绝，别让后来者一直等
				_send_reliable_to(from_id, _envelope("join_answer", 0, {"yes": false, "reason": "room_full"}))
				return
			if _join_peer_id == from_id:
				return
			_join_peer_id = from_id
			join_requested.emit(from_id, payload)
			status_text.emit("有玩家申请加入，是否同意？")
		"join_answer":
			# 客户端收：同意 → 等待页；拒绝 → 回入口（对局内/已入房的迟到答复一律忽略）
			if is_host():
				return
			if bool(payload.get("yes", false)):
				if _session == Session.LOBBY:
					_set_session(Session.READY_CHECK)
					join_answered.emit(true)
			else:
				if _session != Session.LOBBY:
					return
				status_text.emit("房主拒绝了加入")
				battle_error.emit("join_rejected", "host declined")
				join_answered.emit(false)
				leave()
		"room_state":
			# 客户端收：房间 config + 双座位准备状态（房主权威）
			if is_host():
				return
			# 对局中/封存/终局的迟到房态包不能把客户端拉回准备页
			if _session == Session.IN_BATTLE or _session == Session.SEALED or _session == Session.GAME_OVER:
				return
			_apply_room(payload.get("room", {}))
			_host_ready = bool(payload.get("host_ready", false))
			_client_ready = bool(payload.get("client_ready", false))
			_set_session(Session.READY_CHECK)
			ready_changed.emit(_host_ready, _client_ready)
			room_updated.emit(room.duplicate(true))
		"ready":
			# 房主收：客户端准备状态
			if not is_host():
				return
			_client_ready = bool(payload.get("yes", true))
			_broadcast_room_state()
			_maybe_start_lobby_countdown()
		"countdown_start":
			# 客户端收：5s 倒计时（开局仍以 battle_start 为准）
			if is_host():
				return
			_begin_lobby_countdown(int(payload.get("remain_ms", LOBBY_COUNTDOWN_MS)))
			status_text.emit("双方已准备，即将开局")
		"leave_room":
			# 只有未开局阶段才算「大厅离房」；对局内对方离开走 bye（封存 → 人机接管）
			if _session == Session.LOBBY or _session == Session.READY_CHECK or _session == Session.COUNTDOWN:
				_handle_lobby_peer_gone("leave_room")
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
				# 房主权威：先按 config 重建 BattleState（禁止默认 lesson），再恢复快照
				_apply_match_config(payload.get("config", {}))
				_rematch_want = false
				_peer_rematch_want = false
				if not restore_from_snapshot(snap):
					return
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
				_reset_round_flags()
				if not snap.is_empty() and not restore_from_snapshot(snap):
					return
				_reset_round_flags()
				_opening_done = true
				_opening_applied = true
				actions_revealed.emit([GameRules.Action.ZAN, GameRules.Action.ZAN], res)
				if not state.is_over():
					round_begun.emit(state.round)
		"submit_action":
			if is_host():
				var role := int(payload.get("from_role", from_id % 2))
				# 房主座位只能房主自己写：网络对端只能提交客户端座位（1）。
				# 用 from_id != 1 而非只靠 is_remote_sender：hello 之前 _remote_peer_id 还是 -1。
				if is_host() and from_id != 1 and role != 1:
					push_warning("Net: reject remote submit for seat %d" % role)
					return
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
				if not snap.is_empty() and not restore_from_snapshot(snap):
					return
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
			# 无人会发这个包（封存统一走 sys_sealed）；收到即视为异常，且只有客户端可能采纳
			if is_host():
				push_warning("Net: ignore bare 'sealed' from client")
				return
			_set_session(Session.SEALED)
			sealed.emit(str(payload.get("reason", "remote")))
		"sys_sealed":
			# 封存快照由房主广播；房主不采纳对端快照（防快照/判定被反向改写）
			if is_host():
				push_warning("Net: ignore sys_sealed from client")
				return
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
			# 协议面保留兼容，不处理
			pass
		"sys_link_ok":
			# 链路恢复由房主发起广播；房主本地走 on_link_ok，不采纳对端
			if is_host():
				return
			if fsm.state == NetworkSessionFSM.State.SEALED:
				fsm.on_link_ok(Time.get_ticks_msec())
		"sys_consent":
			# 票只能代表发送者自己：忽略 payload.peer，防止客户端替房主投票
			var cpeer := from_id
			var cyes := bool(payload.get("yes", true))
			# 对端可能比本端先进入同意流程：先补齐 AWAITING_CONSENT，再记票
			if fsm.state == NetworkSessionFSM.State.SEALED:
				fsm.on_link_ok(Time.get_ticks_msec())
			fsm.submit_consent(cpeer, cyes, Time.get_ticks_msec())
			status_text.emit("对方已确认，继续对局…" if cyes else "对方拒绝继续")
		"sys_countdown":
			# 倒计时由房主广播
			if is_host():
				return
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
			# 恢复快照只能由房主下发（否则任何一端都能把对端局面改成任意值）
			if is_host():
				push_warning("Net: ignore sys_resume from client")
				return
			var ssnap: Dictionary = payload.get("snapshot", {})
			var sseq := int(payload.get("seq", 0))
			if sseq > 0 and sseq < fsm.seq:
				return
			if not ssnap.is_empty():
				if not restore_from_snapshot(ssnap):
					return
			else:
				fsm.confirm_restore(true, Time.get_ticks_msec())
		"sys_game_over":
			# 判负由房主广播；房主不采纳对端宣布的胜负
			if is_host():
				push_warning("Net: ignore sys_game_over from client")
				return
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
		action = _default_action(role)
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

	# 本回合号必须在结算/复位前定格：小局结束会把 round 复位成 1，
	# 若信封里带 1 而客户端还在第 N 回合，整包会被当「旧包」丢弃。
	var env_round: int = state.round
	var result: GameRules.RoundResult = GameResolve.resolve_turn(state, a0, a1)
	var res_dict := _result_to_dict(result)
	# ── T6 小局判分 / 终场（会话层唯一裁决；单机/热座/联机同款）─────────────
	# 先判分、再（若小局未终场）复位：随包的 snapshot 即新小局初值，对端不必自己算分。
	var settled := _settle_match_after_round()
	res_dict["round_end"] = bool(settled["round_end"])
	res_dict["match_over"] = bool(settled["match_over"])
	res_dict["score"] = state.score.duplicate()
	var snap := state.snapshot()
	_broadcast(_envelope("round_result", env_round, {
		"actions": [a0, a1],
		"result": res_dict,
		"snapshot": snap,
		"round_end": bool(settled["round_end"]),
		"match_over": bool(settled["match_over"]),
		"score": state.score.duplicate(),
	}))
	_actions_revealed_emit([a0, a1], res_dict)
	if bool(settled["match_over"]):
		_set_session(Session.GAME_OVER)
	elif bool(settled["round_end"]):
		# 小局结束但整场未到 12 分 → 结算停留后回到回合 1 开局亮相
		_schedule_round_restart()
	else:
		# 稍后由上层/下一轮推进
		_schedule_next_round()


## 房主/热座侧：一小局结算完成后的会话层裁决（判分 → 终场 / 重开一小局）。
## 判分内核是 state.settle_round_after_resolve()（与单机 BattleController 共用同一份）。
## 返回 {"round_end","match_over","match_winner","winner","score","scored"}。
func _settle_match_after_round() -> Dictionary:
	var info := state.settle_round_after_resolve()
	if bool(info["round_end"]) and not bool(info["match_over"]):
		# 本小局结束、整场未到 12 分 → 重开一小局：资源复位、保留 score、winner 归 -1
		state.reset_round_keep_score()
		_reset_round_flags()
		_reset_opening_flags()
		_grace_left = 0.0
		_round_restart_pending = true
	return info


func _default_action(who: int) -> int:
	# 开局窗口：未点也算「攒」确认
	if state.round == GameRules.OPENING_ROUND and not _opening_done:
		return GameRules.Action.ZAN
	return state.default_action(who)


func _schedule_next_round() -> void:
	# 无 SceneTree（headless 单测）时不自动推进，由 debug_advance_round 手动驱动
	if not is_inside_tree() or get_tree() == null:
		return
	# 结算画面独立停留 0.8s，退下后再进下一回合
	# 结算画面独立停留（勿在 await 里调 BattleTempo）
	await get_tree().create_timer(0.8).timeout
	if not is_instance_valid(self) or not is_inside_tree():
		return
	if _session == Session.IN_BATTLE and not state.is_over():
		_begin_next_round()


## 小局结束（分数未到 12）后重开一小局：结算停留 0.8s → 回合 1 开局亮相。
## 资源与 score 的复位已在 _settle_match_after_round() 做完，这里只负责进开局窗。
func _schedule_round_restart() -> void:
	if not is_inside_tree() or get_tree() == null:
		return
	await get_tree().create_timer(0.8).timeout
	if not is_instance_valid(self) or not is_inside_tree():
		return
	if _session == Session.IN_BATTLE and _round_restart_pending:
		_do_opening()


## 测试钩子：跳过表现延迟，立即进入下一回合选招。
## 小局刚结束（分数未到 12）时改为进入「重开一小局」的开局窗，而不是把回合号 +1。
func debug_advance_round() -> void:
	if _session != Session.IN_BATTLE or state.is_over():
		return
	if _round_restart_pending:
		_do_opening()
		return
	_begin_next_round()


func _begin_next_round() -> void:
	_opening_done = true
	state.round += 1
	_reset_round_flags()
	state.phase = GameRules.Phase.SELECTING
	round_begun.emit(state.round)
	if is_host() or _mode == Mode.HOTSEAT:
		_broadcast(_envelope("select_window", state.round, {"round": state.round}))


func _begin_remote_round(round_no: int) -> void:
	# 客户端开局窗也必须保持 _opening_done=false，否则聚光灯/6s 窗全丢
	_opening_done = round_no > GameRules.OPENING_ROUND
	# 新窗清空点选残留，否则 UI 把上回合招式当「已选」永久灰
	_reset_round_flags()
	state.phase = GameRules.Phase.SELECTING
	round_begun.emit(round_no)


func _do_opening() -> void:
	# 产品：开局不再强制结算，改为双方点「攒」确认后再亮相
	# 整场首局与「小局重开」共用本流程：小局的资源/score 复位由
	# _reset_rules_state()（整场）或 _settle_match_after_round()（小局）负责。
	_reset_opening_flags()
	state.round = GameRules.OPENING_ROUND
	state.phase = GameRules.Phase.SELECTING
	_reset_round_flags()
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
	if not is_instance_valid(self) or not is_inside_tree():
		return
	if _session == Session.IN_BATTLE and not state.is_over():
		# 开局后进入回合 2 选招；round 仍为 1 时 next 会 +1 → 2
		if state.round == GameRules.OPENING_ROUND:
			_begin_next_round()
		else:
			round_begun.emit(state.round)


func _actions_revealed_emit(actions: Array, results: Dictionary) -> void:
	actions_revealed.emit(actions, results)


# ---------- 会话 FSM 驱动（心跳 / 超时 / 房主倒计时） ----------

## 是否需要记一次「心跳丢失」。
## 窗口必须显著大于心跳间隔（HB_MISS_WINDOW_MS = 2.5×HB_INTERVAL_MS）：
## 旧实现直接拿心跳间隔当窗口，正常局域网里「刚好差几十毫秒」也会被算成丢包，
## 于是链路明明很好却提示「网络不佳」。抽成静态函数便于自检直接测边界。
static func hb_miss_due(now_ms: int, last_rx_ms: int) -> bool:
	if last_rx_ms <= 0:
		return false
	return now_ms - last_rx_ms >= NetworkSessionFSM.HB_MISS_WINDOW_MS


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
		# 静默窗口 HB_MISS_WINDOW_MS（2.5×心跳间隔）内一包都没收到才记一次丢包。
		# 旧实现窗口 == 心跳间隔，正常局域网「刚好差几十毫秒」就会被误记 → 误报「网络不佳」。
		# 连续 2 次 → Degraded（约 3.5s 静默），连续 5 次 → Sealed（约 6.5s 静默）。
		if hb_miss_due(now, _last_hb_rx_ms):
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


## 活局面快照（供 FSM 自主封存使用）：rules + session 双段，恢复时才能原样还原。
func _live_rules_snapshot() -> Dictionary:
	return {"rules": state.snapshot(), "session": _session_meta()}


## 本地封存后统一广播（房主权威：客户端只采纳房主快照，不反向广播）。
## 对端已经不在（get_peer_ids 为空）时跳过，避免向已断开连接发可靠包报错。
func _broadcast_sealed(snap: Dictionary, reason: String) -> void:
	if not is_host() or ai_takeover or provider == null or _mode == Mode.HOTSEAT:
		return
	if provider.get_peer_ids().is_empty():
		return
	_broadcast(_envelope("sys_sealed", state.round, {
		"reason": reason,
		"snapshot": snap.duplicate(true),
	}))


## 该包的 from_id 是否来自「网络对端」（热座/直连测试下为 false，不做角色约束）。
func is_remote_sender(from_id: int) -> bool:
	return _remote_peer_id > 0 and from_id == _remote_peer_id


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
	# 网络判负（拒绝继续 / 同意超时 / 封存链路超时 / 快照校验失败）＝**整场**结束：
	# 不判小局、不加分、不重开小局（与 GameResolve 的小局胜负是两条路）。
	_round_restart_pending = false


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
		"sealed": r.sealed.duplicate(),
		"quan_jiang": r.quan_jiang,
		"opening": r.opening,
		"text": r.text,
		"texts": [GameResolve.describe(r, 0), GameResolve.describe(r, 1)],
		"timeout": _timeout_flags.duplicate(),
	}


# T6 小局判分 / 终场裁决已迁至 BattleState：settle_round_after_resolve / is_match_over /
# match_winner / reset_round_keep_score（scripts/rules/battle_state.gd，含平局保底计分）。
# 单机 / 热座 / 联机房主共用同一份，不要在会话层重写 score 累加 / 12 分判定 / 复位字段表。

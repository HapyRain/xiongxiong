## networked_battle_controller.gd
## 热座 + 联机对局流程：开局强制攒 → 2 拍选招 → 锁定上传 → 原子揭示 → 结算。
## 与单机 battle_controller.gd 分开；规则/结算完全复用 GameResolve / BattleState。
## 输入源：热座双座位 / 联机本地座位。
class_name NetworkedBattleController
extends Node

signal phase_changed(phase: int, round_no: int)
signal beat(beat_no: int)
signal selected_changed(who: int, action: int)
signal preselect_changed(who: int, action: int)
signal round_resolved(result: Dictionary)
signal game_over(winner: int)
signal status_text(text: String)

const SELECT_WINDOW := 2.1
const OPENING_SELECT_WINDOW := 2.1

var peer: PeerManager = null
var state: BattleState:
	get:
		return peer.state if peer != null else _fallback_state

var _fallback_state: BattleState = BattleState.new()
var _select_left: float = 0.0
var _beat_fired: Array = [false, false]
var _window_open: bool = false
var _local_preselect: Array = [-1, -1]
var _resolving: bool = false
var _running: bool = false
var _ai_active: bool = false
var _ai_seat: int = 1
var _ai_timer: float = 0.0
var _did_lock_fill: bool = false
var _did_settle: bool = false


func attach(manager: PeerManager) -> void:
	if peer != null and peer.is_connected("round_begun", _on_round_begun):
		peer.round_begun.disconnect(_on_round_begun)
		peer.actions_revealed.disconnect(_on_actions_revealed)
		peer.battle_started.disconnect(_on_battle_started)
		peer.sealed.disconnect(_on_sealed)
	peer = manager
	if peer == null:
		return
	peer.round_begun.connect(_on_round_begun)
	peer.actions_revealed.connect(_on_actions_revealed)
	peer.battle_started.connect(_on_battle_started)
	peer.sealed.connect(_on_sealed)
	peer.ai_takeover_started.connect(_on_ai_takeover)
	peer.session_meta_hook = _session_meta
	if peer.ai_takeover:
		_on_ai_takeover("already")
	# 若已开局（信号在 attach 前发出），补开窗口
	if _running:
		_sync_window_from_peer()


func _session_meta() -> Dictionary:
	var elapsed := 0.0
	var win := _window_seconds()
	if _window_open:
		elapsed = win - _select_left
	return {
		"game_phase_name": GameRules.Phase.keys()[state.phase] if state.phase >= 0 and state.phase < GameRules.Phase.keys().size() else "SELECTING",
		"beat": 2 if _beat_fired[1] else (1 if _beat_fired[0] else 0),
		"beat_elapsed_ms": int(elapsed * 1000.0),
		"select_window_ms": int(win * 1000.0),
		"opening_done": peer != null and peer._opening_done,
		"round_resolved": _resolving,
	}


func _window_seconds() -> float:
	var s: BattleState = state
	if s == null:
		return BattleTempo.total_window(1)
	return BattleTempo.total_window(s.round)


func begin() -> void:
	if peer == null:
		push_error("NetworkedBattleController: peer not attached")
		return
	# 幂等：重复 begin 不要清掉已打开的选招窗
	if _running and _window_open:
		return
	_running = true
	_local_preselect = [-1, -1]
	# 关键：进场景前可能已发出 round_begun / battle_start（host start_battle 在 change_scene 前）
	# 必须按当前 state 补开窗口，否则双方选招后 lock_in 永不执行
	_sync_window_from_peer()
	status_text.emit(_mode_label())


## 按 PeerManager 当前局面补开选招窗（错过 round_begun 广播时用）。
func _sync_window_from_peer() -> void:
	if peer == null:
		return
	var s: BattleState = state
	if s == null or s.is_over() or _resolving:
		return
	if not peer.is_input_open() and not peer.ai_takeover:
		return
	var sess: int = peer.get_session()
	if sess != PeerManager.Session.IN_BATTLE and not peer.ai_takeover:
		return
	if _window_open:
		return
	# 已在选招/开局点攒阶段 → 开窗
	var phase_ok: bool = (
		s.phase == GameRules.Phase.SELECTING
		or s.phase == GameRules.Phase.OPENING
		or s.phase == GameRules.Phase.CLAP1
		or (s.round == GameRules.OPENING_ROUND and peer != null and not peer._opening_done)
	)
	if phase_ok:
		_on_round_begun(s.round)


func stop() -> void:
	_running = false
	_window_open = false


func _mode_label() -> String:
	if peer == null:
		return ""
	if peer.ai_takeover:
		return "联机对局（人机接管）"
	match peer.get_mode():
		PeerManager.Mode.HOTSEAT:
			return "人机/本地对局"
		PeerManager.Mode.ENET:
			return "联机对局（%s）" % ("房主" if peer.is_host() else "客户端")
	return "对局"


func _on_ai_takeover(reason: String) -> void:
	_ai_active = true
	_running = true
	if peer != null:
		_ai_seat = 1 - peer.get_local_role()
	_ai_timer = randf_range(0.8, 2.2)
	if reason != "" and reason != "already":
		status_text.emit("对方已离开，由人机接管")
	else:
		status_text.emit("对方已离开，由人机接管")


## 唯一输入闸：UI 禁用与 try_select 共用，避免“能点但无效 / 亮着却点不动”
func is_pick_open() -> bool:
	if peer == null or not _running:
		return false
	if _resolving or _did_settle or _did_lock_fill:
		return false
	if not _window_open:
		return false
	var s: BattleState = state
	if s == null or s.is_over():
		return false
	if not peer.is_input_open():
		return false
	return true


## 座位 who 预选/改选。热座：who=0/1；联机：who 忽略，用本地角色。
func try_select(who: int, action: int) -> bool:
	if not is_pick_open():
		return false
	var s: BattleState = state
	var seat: int = who
	if peer.get_mode() != PeerManager.Mode.HOTSEAT:
		seat = peer.get_local_role()
	if not s.can_use_action(seat, action):
		return false
	# 封盘前允许改招：submit 会置 _locks，但锁≠不能改
	_local_preselect[seat] = action
	s.pending[seat] = action
	if peer != null and peer._pending_actions != null and seat < peer._pending_actions.size():
		peer._pending_actions[seat] = action
	preselect_changed.emit(seat, action)
	if peer != null:
		peer.submit_action(action, seat)
	return true


## 人机座位预选（对方接管后由 _process 调用）。
func _ai_try_select(action: int) -> bool:
	if peer == null or not _running or not _ai_active:
		return false
	if not peer.is_input_open():
		return false
	var s: BattleState = state
	if s.is_over():
		return false
	var seat := _ai_seat
	if _window_open and _beat_fired[1] and _local_preselect[seat] < 0 and s.pending[seat] < 0:
		return false
	if not s.can_use_action(seat, action):
		return false
	_local_preselect[seat] = action
	s.pending[seat] = action
	preselect_changed.emit(seat, action)
	return true


## 拍 2 后锁定上传；由 UI 或 _process 在 CLAP2 时刻调用。
## 选招已在 try_select 时 submit；这里主要负责 reveal。
func lock_in() -> void:
	if peer == null or not _running or _resolving:
		return
	var s: BattleState = state
	if s.is_over():
		return
	if peer.get_mode() == PeerManager.Mode.HOTSEAT or _ai_active:
		for i in 2:
			var act: int = _local_preselect[i]
			if act < 0:
				act = int(s.pending[i])
			if act < 0:
				if _ai_active and i == _ai_seat:
					act = AiOpponent.choose(s, i)
				else:
					act = GameRules.Action.FANG if s.shield[i] >= 1 else GameRules.Action.ZAN
					if not s.can_use_action(i, act):
						act = GameRules.Action.ZAN
			_local_preselect[i] = act
			peer.submit_action(act, i)
		peer.reveal_phase()
		return
	var role: int = peer.get_local_role()
	var act2: int = _local_preselect[role]
	if act2 < 0:
		act2 = int(s.pending[role])
	if act2 >= 0:
		peer.submit_action(act2)
	# 拍 2 统一结算：缺招由 host 补默认并亮招，而不是谁先交谁先亮
	if peer.is_host() or peer.get_mode() == PeerManager.Mode.HOTSEAT or peer.ai_takeover:
		peer.request_timeout_default()
	else:
		peer.reveal_phase()


func request_timeout_default() -> void:
	if peer != null:
		peer.request_timeout_default()


func _process(delta: float) -> void:
	if not _running or peer == null or _resolving:
		return
	if not _window_open:
		return
	var s: BattleState = state
	if s.is_over():
		return

	_select_left -= delta
	var s2: BattleState = state
	var round_no := s2.round
	var win := _window_seconds()
	var elapsed := win - _select_left

	# 啪啪两声：0s 首声，+0.25s 次声；约 1.7s 结算
	if not _beat_fired[0]:
		_beat_fired[0] = true
		beat.emit(1)
	if not _beat_fired[1] and elapsed >= BattleTempo.clap2_at(round_no):
		_beat_fired[1] = true
		beat.emit(2)

	# 封盘：结算前 0.1s 无输入按规则补招（打超时角标）
	if not _did_lock_fill and elapsed >= BattleTempo.lock_time(round_no):
		_did_lock_fill = true
		if peer != null and (peer.get_mode() == PeerManager.Mode.HOTSEAT or peer.is_host() or _ai_active):
			peer.auto_fill_missing()

	# 人机接管：窗口内为对方座位自动预选
	if _ai_active and not _did_lock_fill and s2.pending[_ai_seat] < 0:
		_ai_timer -= delta
		if _ai_timer <= 0.0:
			_ai_try_select(AiOpponent.choose(s2, _ai_seat))
			_ai_timer = randf_range(0.4, 1.0)

	# 统一结算
	if not _did_settle and (elapsed >= BattleTempo.settle_time(round_no) or _select_left <= 0.0):
		_did_settle = true
		_window_open = false
		lock_in()
		# 结算开始立即刷 UI，禁止继续点击
		phase_changed.emit(GameRules.Phase.RESOLVING, state.round)


func _on_battle_started(_snap: Dictionary) -> void:
	status_text.emit(_mode_label() + " · 对局开始")


func _on_round_begun(round_no: int) -> void:
	# 再来一局/恢复：终局会把 _running 关掉，必须重新拉起
	_running = true
	_resolving = false
	_window_open = true
	_did_lock_fill = false
	_did_settle = false
	_select_left = _window_seconds()
	_beat_fired = [false, false]
	_local_preselect = [-1, -1]
	_resolving = false
	if _ai_active:
		_ai_timer = randf_range(0.8, 2.2)
	var s: BattleState = state
	s.round = round_no
	s.phase = GameRules.Phase.SELECTING
	phase_changed.emit(s.phase, s.round)
	if round_no == GameRules.OPENING_ROUND and peer != null and not peer._opening_done:
		status_text.emit("点击「攒」开始对决")
	else:
		status_text.emit("回合 %d · 同步出招" % round_no)


func _on_actions_revealed(actions: Array, results: Dictionary) -> void:
	_resolving = true
	_window_open = false
	var s: BattleState = state
	s.pending = [int(actions[0]), int(actions[1])] if actions.size() >= 2 else s.pending
	s.phase = GameRules.Phase.RESOLVING
	phase_changed.emit(s.phase, s.round)
	round_resolved.emit(results)
	if s.is_over():
		_emit_over()
		return
	s.phase = GameRules.Phase.PRESENTING
	phase_changed.emit(s.phase, s.round)


func _on_sealed(reason: String) -> void:
	_window_open = false
	status_text.emit("封存：%s" % reason)


func _emit_over() -> void:
	var s: BattleState = state
	s.phase = GameRules.Phase.GAME_OVER
	phase_changed.emit(s.phase, s.round)
	game_over.emit(s.winner)
	_running = false

## network_session_fsm.gd
## 纯网络会话状态机：7 态 + 阈值 + 信号。
## 对应 docs/arch/network-session-fsm.md（Connected/Degraded/Sealed/AwaitingConsent/Countdown/Resuming/Fail）。
## 不依赖 MultiplayerAPI / SceneTree；时间由调用方以 now_ms 注入（Time.get_ticks_msec() 单调源），
## 便于 headless 单测与房主绝对时刻倒计时（禁止各端独立 create_timer(3)）。
class_name NetworkSessionFSM
extends RefCounted

enum State {
	CONNECTED,
	DEGRADED,
	SEALED,
	AWAITING_CONSENT,
	COUNTDOWN,
	RESUMING,
	FAIL,
}

const SCHEMA_VERSION := 1

# ---- 阈值（docs/arch/network-session-fsm.md §9，实测可调值不调语义）----
const HB_INTERVAL_MS := 1000
const HB_WINDOW := 10
const DEGRADE_RTT_P95_MS := 250
const DEGRADE_JITTER_MS := 80
const DEGRADE_HB_MISS := 2
const RECOVER_RTT_MS := 150
const RECOVER_JITTER_MS := 50
const RECOVER_OK_STREAK := 3
const SEAL_HB_MISS := 5
const SEAL_RTT_MS := 800
const SEAL_RTT_HOLD_MS := 3000
const CONSENT_TIMEOUT_MS := 30000
const COUNTDOWN_MS := 3000
const COUNTDOWN_ACK_GRACE_MS := 1000
const SEAL_LINK_DEADLINE_MS := 60000

signal state_changed(from_state: int, to_state: int, reason: String)
signal quality_changed(rtt_p95: int, jitter: int, hb_miss: int)
signal sealed(snap: Dictionary, reason: String)
signal consent_needed(snap: Dictionary, need_from: Array)
signal consent_updated(need_from: Array)
signal countdown_started(resume_at_host_ms: int, seq: int)
signal countdown_tick(remain_ms: int)
signal resumed(snap: Dictionary)
signal failed(loser_peer: int, reason: String)

var state: int = State.CONNECTED
var last_snapshot: Dictionary = {}
var seq: int = 0
var is_host: bool = true
var host_peer_id: int = 1
var local_peer_id: int = 1

var _rtt_samples: Array = []
var _hb_miss: int = 0
var _good_streak: int = 0
var _high_rtt_since_ms: int = -1
var _last_rtt: int = -1
var _last_jit: int = 0

var _consent_yes: Dictionary = {}
var _consent_all: Array = []
var _consent_deadline_ms: int = 0

var _resume_at_host_ms: int = 0
var _resume_acks: Dictionary = {}
var _countdown_end_local_ms: int = 0
var _host_skew_ms: int = 0

var _seal_deadline_ms: int = 0
var _fail_loser: int = -1
var _fail_reason: String = ""


static func state_name(s: int) -> String:
	match s:
		State.CONNECTED: return "Connected"
		State.DEGRADED: return "Degraded"
		State.SEALED: return "Sealed"
		State.AWAITING_CONSENT: return "AwaitingConsent"
		State.COUNTDOWN: return "Countdown"
		State.RESUMING: return "Resuming"
		State.FAIL: return "Fail"
	return "?"


func get_state_name() -> String:
	return state_name(state)


## 仅 Connected 允许 try_select / 回合推进 RPC（迁移不变式 1）。
func is_input_open() -> bool:
	return state == State.CONNECTED


func is_sealed_family() -> bool:
	return state in [State.SEALED, State.AWAITING_CONSENT, State.COUNTDOWN, State.RESUMING]


func is_terminal() -> bool:
	return state == State.FAIL


# ---------- 心跳 / 质量 ----------

## 收到一次带 RTT 的心跳样本（hb_echo）。
func on_heartbeat_sample(now_ms: int, rtt_ms: int) -> void:
	_hb_miss = 0
	# 尖刺后的首个达标样本不把「与坏样本的差」算进 jitter（否则滞回永远退不出）
	if _last_rtt >= 0 and _last_rtt < RECOVER_RTT_MS:
		_last_jit = absi(int(rtt_ms) - _last_rtt)
	else:
		_last_jit = 0
	_last_rtt = int(rtt_ms)
	_rtt_samples.append(int(rtt_ms))
	if _rtt_samples.size() > HB_WINDOW:
		_rtt_samples.pop_front()
	_eval_quality(now_ms)


## 一个心跳周期未见对端存活。
func on_heartbeat_miss(now_ms: int) -> void:
	_hb_miss += 1
	_eval_quality(now_ms)


## 硬断兜底：peer_disconnected / server_disconnected / connection_failed。
func on_peer_lost(now_ms: int, reason: String) -> void:
	match state:
		State.FAIL, State.RESUMING:
			return
		State.CONNECTED, State.DEGRADED, State.SEALED:
			_do_seal(now_ms, "peer_lost:" + reason, {}, {})
		_:
			# 同意/倒计时中再硬断 → 掉线方（对端）判负
			_do_fail(_peer_of_other_side(), "peer_lost:" + reason, now_ms)


## 链路恢复（心跳重新到达 / HELLO 握手成功）→ Sealed 转同意流程。
func on_link_ok(now_ms: int) -> void:
	if state != State.SEALED:
		return
	_enter_consent(now_ms)


## 时钟偏移：host_now - local_now（客户端在心跳里带上 host 时间后估算）。
func set_host_skew(skew_ms: int) -> void:
	_host_skew_ms = int(skew_ms)


func get_host_skew() -> int:
	return _host_skew_ms


# ---------- 封存 ----------

## 立即封存并打 SessionSnapshot。rules_snap 来自 BattleState.snapshot()。
## session_meta 建议含 beat / beat_elapsed_ms / select_window_ms / opening_done / round_resolved。
func request_seal(now_ms: int, reason: String, rules_snap: Dictionary = {}, session_meta: Dictionary = {}) -> Dictionary:
	return _do_seal(now_ms, reason, rules_snap, session_meta)


## 收到对端（房主）SEALED 广播：采纳其快照，不本地重建（防 seq 分叉）。
func adopt_remote_seal(snap: Dictionary, reason: String, now_ms: int) -> void:
	if state == State.FAIL:
		return
	if snap.is_empty():
		_do_seal(now_ms, reason, {}, {})
		return
	last_snapshot = snap.duplicate(true)
	seq = maxi(seq, int(snap.get("seq", seq)))
	_seal_deadline_ms = now_ms + SEAL_LINK_DEADLINE_MS
	if state != State.SEALED and state != State.AWAITING_CONSENT and state != State.COUNTDOWN:
		_set_state(State.SEALED, reason)
	sealed.emit(last_snapshot, reason)


func _do_seal(now_ms: int, reason: String, rules_snap: Dictionary, session_meta: Dictionary) -> Dictionary:
	if state == State.FAIL:
		return last_snapshot
	if state == State.RESUMING:
		return last_snapshot
	var already := state == State.SEALED or state == State.AWAITING_CONSENT or state == State.COUNTDOWN
	var snap: Dictionary
	if already and not last_snapshot.is_empty() and rules_snap.is_empty():
		snap = last_snapshot
	else:
		snap = build_snapshot(now_ms, reason, rules_snap, session_meta)
		last_snapshot = snap
	_seal_deadline_ms = now_ms + SEAL_LINK_DEADLINE_MS
	if not already:
		_set_state(State.SEALED, reason)
	sealed.emit(snap, reason)
	return snap


## 组装 SessionSnapshot（rules + session + consent + checksum）。seq 单调递增。
func build_snapshot(now_ms: int, reason: String, rules_snap: Dictionary, session_meta: Dictionary = {}) -> Dictionary:
	seq += 1
	var session := {
		"net_state": "Sealed",
		"game_phase_name": str(session_meta.get("game_phase_name", "SELECTING")),
		"beat": int(session_meta.get("beat", 0)),
		"beat_elapsed_ms": int(session_meta.get("beat_elapsed_ms", 0)),
		"select_window_ms": int(session_meta.get("select_window_ms", 5000)),
		"opening_done": bool(session_meta.get("opening_done", false)),
		"round_resolved": bool(session_meta.get("round_resolved", false)),
	}
	for k in session_meta.keys():
		if not session.has(k):
			session[k] = session_meta[k]
	session["seal_reason"] = reason
	var peers := _all_peer_ids()
	var snap := {
		"schema_version": SCHEMA_VERSION,
		"snapshot_id": "snap_%d_%d" % [now_ms, seq],
		"seq": seq,
		"created_at_host_ms": now_ms,
		"host_peer_id": host_peer_id,
		"rules": rules_snap.duplicate(true),
		"session": session,
		"consent": {
			"need_continue_from": peers.duplicate(),
			"deadline_host_ms": now_ms + CONSENT_TIMEOUT_MS,
		},
		"checksum": "",
	}
	snap["checksum"] = compute_checksum(snap["rules"], snap["session"])
	return snap


static func compute_checksum(rules: Dictionary, session: Dictionary) -> String:
	var canon := _canon_json({"rules": rules, "session": session})
	return "sha256:" + canon.sha256_text()


static func _canon_json(v) -> String:
	match typeof(v):
		TYPE_DICTIONARY:
			var keys: Array = v.keys()
			keys.sort()
			var parts: PackedStringArray = []
			for k in keys:
				parts.append(JSON.stringify(str(k)) + ":" + _canon_json(v[k]))
			return "{" + ",".join(parts) + "}"
		TYPE_ARRAY:
			var items: PackedStringArray = []
			for item in v:
				items.append(_canon_json(item))
			return "[" + ",".join(items) + "]"
		_:
			return JSON.stringify(v)


# ---------- 同意 ----------

## 链路恢复后进入「是否继续」。need_from 缺省为双方 peer。
func begin_consent(now_ms: int, snap: Dictionary = {}, need_from: Array = []) -> void:
	if state != State.SEALED and state != State.AWAITING_CONSENT:
		return
	if not snap.is_empty():
		last_snapshot = snap
	_enter_consent(now_ms, need_from)


func _enter_consent(now_ms: int, need_from: Array = []) -> void:
	if need_from.is_empty():
		need_from = _all_peer_ids()
	_consent_all = need_from.duplicate()
	_consent_yes.clear()
	_consent_deadline_ms = now_ms + CONSENT_TIMEOUT_MS
	if not last_snapshot.is_empty():
		last_snapshot["consent"] = {
			"need_continue_from": _consent_all.duplicate(),
			"deadline_host_ms": _consent_deadline_ms,
		}
	_set_state(State.AWAITING_CONSENT, "link_ok")
	consent_needed.emit(last_snapshot, _consent_all.duplicate())


## 收到一方同意/拒绝。accepted=false → 拒绝方判负（P3 demo 简化）。
func submit_consent(peer_id: int, accepted: bool, now_ms: int) -> void:
	if state == State.SEALED:
		# 能收到票说明链路已恢复
		on_link_ok(now_ms)
	if state != State.AWAITING_CONSENT:
		return
	if not accepted:
		_do_fail(peer_id, "consent_reject", now_ms)
		return
	_consent_yes[peer_id] = true
	var need: Array = []
	for pid in _consent_all:
		if not _consent_yes.get(pid, false):
			need.append(pid)
	consent_updated.emit(need)
	if need.is_empty():
		_on_consent_all(now_ms)


func _on_consent_all(now_ms: int) -> void:
	if not is_host:
		# 客户端等房主 COUNTDOWN 广播；此处仅预备
		return
	begin_countdown(now_ms + COUNTDOWN_MS, now_ms)


# ---------- 倒计时（房主绝对时刻） ----------

## resume_at_host_ms 为房主时钟绝对时刻。客户端用 skew 对齐显示，禁止本地 3s 自数。
func begin_countdown(resume_at_host_ms: int, now_ms: int) -> void:
	if state == State.SEALED:
		on_link_ok(now_ms)
	if state != State.AWAITING_CONSENT and state != State.COUNTDOWN:
		return
	_resume_at_host_ms = int(resume_at_host_ms)
	# 只清空后重建会丢掉已记的对端 ACK；保留已有票
	var keep := {}
	for k in _resume_acks:
		if _resume_acks[k]:
			keep[k] = true
	_resume_acks = keep
	_resume_acks[local_peer_id] = true
	_countdown_end_local_ms = _to_local(_resume_at_host_ms) + COUNTDOWN_ACK_GRACE_MS
	_set_state(State.COUNTDOWN, "consent_all")
	countdown_started.emit(_resume_at_host_ms, seq)


func on_resume_ack(peer_id: int) -> void:
	# 允许在 Countdown 前预记（COUNTDOWN 包与 ACK 可能乱序）
	if state != State.COUNTDOWN and state != State.AWAITING_CONSENT and state != State.SEALED:
		return
	_resume_acks[peer_id] = true


## 每帧/每测步驱动：Consent 超时、封存链路超时、倒计时读秒与结束。
func tick(now_ms: int) -> void:
	match state:
		State.SEALED:
			if now_ms >= _seal_deadline_ms:
				_do_fail(_peer_of_other_side(), "seal_link_timeout", now_ms)
		State.AWAITING_CONSENT:
			if now_ms >= _consent_deadline_ms:
				var missing: Array = []
				for pid in _consent_all:
					if not _consent_yes.get(pid, false):
						missing.append(pid)
				if missing.is_empty():
					_on_consent_all(now_ms)
				elif missing.size() == _consent_all.size():
					# 双方都未点 → 平局（winner=2）
					_do_fail(-1, "consent_timeout_draw", now_ms)
				else:
					_do_fail(int(missing[0]), "consent_timeout", now_ms)
		State.COUNTDOWN:
			var remain := _resume_at_host_ms - _to_host(now_ms)
			if remain < 0:
				remain = 0
			countdown_tick.emit(remain)
			if now_ms >= _countdown_end_local_ms:
				var missing: Array = []
				for pid in _all_peer_ids():
					if not _resume_acks.get(pid, false):
						missing.append(pid)
				if missing.is_empty() or _acks_enough():
					_enter_resuming(now_ms)
				else:
					_do_fail(int(missing[0]), "countdown_ack_missing", now_ms)
		_:
			pass


func _acks_enough() -> bool:
	for pid in _all_peer_ids():
		if not _resume_acks.get(pid, false):
			return false
	return true


# ---------- 恢复 ----------

func _enter_resuming(_now_ms: int) -> void:
	_set_state(State.RESUMING, "countdown_end")


## 校验快照（schema/checksum/seq 闸门）并进入 Resuming。调用方随后 restore 再 confirm_restore。
func validate_snapshot(snap: Dictionary) -> bool:
	if int(snap.get("schema_version", -1)) != SCHEMA_VERSION:
		return false
	var rules: Dictionary = snap.get("rules", {})
	var session: Dictionary = snap.get("session", {})
	if typeof(rules) != TYPE_DICTIONARY or typeof(session) != TYPE_DICTIONARY:
		return false
	var expect := str(snap.get("checksum", ""))
	if expect.is_empty():
		return false
	if compute_checksum(rules, session) != expect:
		return false
	var snap_seq := int(snap.get("seq", 0))
	if snap_seq < seq:
		return false
	return true


## 从快照恢复入口：校验通过则转 Resuming；失败 demo 直接 Fail。
func restore_from_snapshot(snap: Dictionary, now_ms: int) -> bool:
	if state == State.FAIL:
		return false
	if not validate_snapshot(snap):
		_do_fail(-1, "restore_bad_checksum", now_ms)
		return false
	last_snapshot = snap.duplicate(true)
	seq = maxi(seq, int(snap.get("seq", seq)))
	if state != State.RESUMING and state != State.COUNTDOWN:
		_set_state(State.RESUMING, "restore")
	return true


## restore 完成后的确认。ok=false → Fail。
func confirm_restore(ok: bool, now_ms: int = 0) -> void:
	if state != State.RESUMING:
		return
	if not ok:
		_do_fail(-1, "restore_bad", now_ms)
		return
	_set_state(State.CONNECTED, "restore_ok")
	resumed.emit(last_snapshot)


## 外部主动判负/终局（拒绝、超时、校验失败统一出口）。
func force_fail(loser_peer: int, reason: String, now_ms: int = 0) -> void:
	_do_fail(loser_peer, reason, now_ms)


## 人机接管：从任意非终局（含 Sealed/Consent/Countdown）拉回本地可玩。
## 不走同意/倒计时；判负路径仍保留给显式拒绝/超时。
func force_local_play(reason: String = "ai_takeover") -> void:
	var prev := state
	state = State.CONNECTED
	_fail_loser = -1
	_fail_reason = ""
	_hb_miss = 0
	_good_streak = 0
	_consent_yes.clear()
	_resume_acks.clear()
	_seal_deadline_ms = 0
	_consent_deadline_ms = 0
	if prev != State.CONNECTED:
		state_changed.emit(prev, State.CONNECTED, reason)


func get_fail_loser() -> int:
	return _fail_loser


func get_fail_reason() -> String:
	return _fail_reason


## BattleState.winner 语义：0=左/房主胜, 1=右/客户端胜, 2=平局。
func winner_on_fail() -> int:
	if _fail_loser < 0:
		return 2
	if _fail_loser == host_peer_id:
		return 1
	return 0


func get_resume_at_host_ms() -> int:
	return _resume_at_host_ms


func get_countdown_remain_ms(now_ms: int) -> int:
	var remain := _resume_at_host_ms - _to_host(now_ms)
	return remain if remain > 0 else 0


func get_consent_need() -> Array:
	var need: Array = []
	for pid in _consent_all:
		if not _consent_yes.get(pid, false):
			need.append(pid)
	return need


# ---------- 内部 ----------

func _do_fail(loser_peer: int, reason: String, now_ms: int = 0) -> void:
	if state == State.FAIL:
		return
	_fail_loser = loser_peer
	_fail_reason = reason
	_set_state(State.FAIL, reason)
	failed.emit(loser_peer, reason)


func _set_state(s: int, reason: String) -> void:
	if state == s:
		return
	var prev := state
	state = s
	state_changed.emit(prev, s, reason)


func _eval_quality(now_ms: int) -> void:
	var rtt_p95 := calc_rtt_p95()
	var jitter := calc_jitter()
	quality_changed.emit(rtt_p95, jitter, _hb_miss)
	match state:
		State.CONNECTED:
			if _hb_miss >= SEAL_HB_MISS or _seal_by_rtt(now_ms, rtt_p95):
				_do_seal(now_ms, "hb_timeout", {}, {})
			elif _hb_miss >= DEGRADE_HB_MISS or rtt_p95 >= DEGRADE_RTT_P95_MS or jitter >= DEGRADE_JITTER_MS:
				_good_streak = 0
				_set_state(State.DEGRADED, "quality_drop")
		State.DEGRADED:
			if _hb_miss >= SEAL_HB_MISS or _seal_by_rtt(now_ms, rtt_p95):
				_do_seal(now_ms, "hb_timeout", {}, {})
			elif _hb_miss == 0 and _last_rtt >= 0 and _last_rtt < RECOVER_RTT_MS and _last_jit < RECOVER_JITTER_MS:
				# 连续 3 次「本拍」达标即退出降级（滞回防抖）
				_good_streak += 1
				if _good_streak >= RECOVER_OK_STREAK:
					_good_streak = 0
					_set_state(State.CONNECTED, "quality_ok")
			else:
				_good_streak = 0
		State.SEALED:
			# 封存期间心跳回来 → 视作链路恢复
			if _hb_miss == 0 and _rtt_samples.size() > 0:
				on_link_ok(now_ms)
		_:
			pass


func _seal_by_rtt(now_ms: int, rtt_p95: int) -> bool:
	if rtt_p95 < SEAL_RTT_MS:
		_high_rtt_since_ms = -1
		return false
	if _high_rtt_since_ms < 0:
		_high_rtt_since_ms = now_ms
		return false
	return now_ms - _high_rtt_since_ms >= SEAL_RTT_HOLD_MS


func calc_rtt_p95() -> int:
	if _rtt_samples.is_empty():
		return 0
	var sorted: Array = _rtt_samples.duplicate()
	sorted.sort()
	var idx := int(ceil(sorted.size() * 0.95)) - 1
	idx = clampi(idx, 0, sorted.size() - 1)
	return int(sorted[idx])


func calc_jitter() -> int:
	if _rtt_samples.size() < 2:
		return 0
	var acc := 0
	for i in range(1, _rtt_samples.size()):
		acc += absi(int(_rtt_samples[i]) - int(_rtt_samples[i - 1]))
	return acc / (_rtt_samples.size() - 1)


func _all_peer_ids() -> Array:
	# demo 1v1：房主 host_peer_id + 对端
	if is_host:
		var other := local_peer_id if local_peer_id != host_peer_id else 2
		return [host_peer_id, other] if other != host_peer_id else [host_peer_id]
	return [host_peer_id, local_peer_id]


func _peer_of_other_side() -> int:
	var ids := _all_peer_ids()
	for pid in ids:
		if pid != local_peer_id:
			return pid
	return local_peer_id


func _to_host(local_ms: int) -> int:
	return local_ms + _host_skew_ms


func _to_local(host_ms: int) -> int:
	return host_ms - _host_skew_ms

## battle_controller.gd
## 对局流程：开局点「攒」亮相 → 2 拍选招 → 锁定 → 结算 → 胜负。
## 单机原型：0=我（玩家），1=对手（简易 AI）。
class_name BattleController
extends Node

signal phase_changed(phase: int, round_no: int)
signal beat(beat_no: int)
signal selected_changed(who: int, action: int)
signal round_resolved(result: GameRules.RoundResult)
signal game_over(winner: int)

const SELECT_WINDOW := 3.4
const OPENING_SELECT_WINDOW := 3.4

var state: BattleState = BattleState.new()
var _select_left: float = 0.0
var _beat_fired: Array = [false, false]
var _ai_timer: float = 0.0
var _resolving: bool = false
var _opening_done: bool = false
var _window_total: float = SELECT_WINDOW
var _did_lock_fill: bool = false
var _did_settle: bool = false


func _ready() -> void:
	_start_opening()


## 唯一输入闸：UI 禁用与 try_select 共用
func is_pick_open() -> bool:
	if _resolving or _did_settle or _did_lock_fill:
		return false
	if state == null or state.is_over():
		return false
	if state.phase != GameRules.Phase.SELECTING and state.phase != GameRules.Phase.CLAP1:
		return false
	return true


func _start_opening() -> void:
	state = BattleState.new()
	_opening_done = false
	state.round = GameRules.OPENING_ROUND
	state.phase = GameRules.Phase.SELECTING
	state.pending = [-1, -1]
	_window_total = BattleTempo.total_window(state.round)
	_select_left = _window_total
	_beat_fired = [false, false]
	_resolving = false
	_did_lock_fill = false
	_did_settle = false
	_ai_timer = randf_range(0.8, 1.6)
	phase_changed.emit(state.phase, state.round)


func _start_selecting(round_no: int) -> void:
	if state.is_over():
		_emit_over()
		return
	state.round = round_no
	state.phase = GameRules.Phase.SELECTING
	state.pending = [-1, -1]
	_window_total = BattleTempo.total_window(round_no)
	_select_left = _window_total
	_beat_fired = [false, false]
	_resolving = false
	_did_lock_fill = false
	_did_settle = false
	_ai_timer = randf_range(0.8, 1.6)
	phase_changed.emit(state.phase, state.round)


func _process(delta: float) -> void:
	if state.is_over() or _resolving:
		return
	if state.phase != GameRules.Phase.SELECTING and state.phase != GameRules.Phase.CLAP1:
		return

	_select_left -= delta
	var elapsed := _window_total - _select_left
	var rno := state.round

	if not _beat_fired[0]:
		_beat_fired[0] = true
		beat.emit(1)
	if not _beat_fired[1] and elapsed >= BattleTempo.clap2_at(rno):
		_beat_fired[1] = true
		beat.emit(2)

	# AI 在输入窗内出招（可改）
	if not _did_lock_fill and _ai_timer > 0.0:
		_ai_timer -= delta
		if _ai_timer <= 0.0:
			try_select(1, _ai_choose())

	# 封盘：仅结算前 0.1s
	if not _did_lock_fill and elapsed >= BattleTempo.lock_time(rno):
		_did_lock_fill = true
		_force_timeout()

	# 统一结算
	if not _did_settle and elapsed >= BattleTempo.settle_time(rno):
		_did_settle = true
		_resolve_locked()
		return


func try_select(who: int, action: int) -> bool:
	if not is_pick_open():
		return false
	if not state.can_use_action(who, action):
		return false
	# 封盘前允许改招
	if _did_lock_fill or _did_settle:
		return false
	state.pending[who] = action
	selected_changed.emit(who, action)
	return true


func try_select_change(who: int, action: int) -> bool:
	return try_select(who, action)


## 封盘：只补默认出招，不结算
func _force_timeout() -> void:
	for i in 2:
		if state.pending[i] < 0:
			var a: int = GameRules.Action.FANG if state.shield[i] >= 1 else GameRules.Action.ZAN
			if not state.can_use_action(i, a):
				a = GameRules.Action.ZAN
			state.pending[i] = a
			selected_changed.emit(i, a)


func _resolve_locked() -> void:
	if _resolving or state.is_over():
		return
	_resolving = true
	# 开局：双方点「攒」→ 亮相（规则 resolve_opening，不改结算）
	if state.round == GameRules.OPENING_ROUND and not _opening_done:
		state.phase = GameRules.Phase.OPENING
		phase_changed.emit(state.phase, state.round)
		var ro := GameResolve.resolve_opening(state)
		_opening_done = true
		state.phase = GameRules.Phase.PRESENTING
		phase_changed.emit(state.phase, state.round)
		round_resolved.emit(ro)
		# 结算画面独立停留（勿在 await 里调 BattleTempo，外部类会卡死）
		await get_tree().create_timer(0.8).timeout
		_start_selecting(2)
		return
	state.phase = GameRules.Phase.RESOLVING
	phase_changed.emit(state.phase, state.round)
	var r := GameResolve.resolve_turn(state, state.pending[0], state.pending[1])
	state.phase = GameRules.Phase.PRESENTING
	phase_changed.emit(state.phase, state.round)
	round_resolved.emit(r)
	if state.is_over():
		_emit_over()
		return
	await get_tree().create_timer(0.8).timeout
	_start_selecting(state.round + 1)


func _emit_over() -> void:
	state.phase = GameRules.Phase.GAME_OVER
	phase_changed.emit(state.phase, state.round)
	game_over.emit(state.winner)


func _ai_choose() -> int:
	return AiOpponent.choose(state, 1)

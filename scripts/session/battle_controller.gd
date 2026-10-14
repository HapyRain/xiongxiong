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

const SELECT_WINDOW := 5.0
const OPENING_SELECT_WINDOW := 6.0
const CLAP1_ELAPSED := 1.8   # 距窗口开始 1.8s 拍1
const CLAP2_ELAPSED := 3.4   # 3.4s 拍2，随后亮招

var state: BattleState = BattleState.new()
var _select_left: float = 0.0
var _beat_fired: Array = [false, false]
var _ai_timer: float = 0.0
var _resolving: bool = false
var _opening_done: bool = false
var _window_total: float = SELECT_WINDOW


func _ready() -> void:
	_start_opening()


func _start_opening() -> void:
	# 产品：开局不再强制亮相，改为玩家点「攒」才算开始（AI 也会点）
	state = BattleState.new()
	_opening_done = false
	state.round = GameRules.OPENING_ROUND
	state.phase = GameRules.Phase.SELECTING
	state.pending = [-1, -1]
	_select_left = OPENING_SELECT_WINDOW
	_window_total = OPENING_SELECT_WINDOW
	_beat_fired = [false, false]
	_resolving = false
	_ai_timer = randf_range(1.2, 3.5)
	phase_changed.emit(state.phase, state.round)


func _start_selecting(round_no: int) -> void:
	if state.is_over():
		_emit_over()
		return
	state.round = round_no
	state.phase = GameRules.Phase.SELECTING
	state.pending = [-1, -1]
	_window_total = SELECT_WINDOW
	_select_left = SELECT_WINDOW
	_beat_fired = [false, false]
	_resolving = false
	_ai_timer = randf_range(1.2, 3.5)
	phase_changed.emit(state.phase, state.round)


func _process(delta: float) -> void:
	if state.is_over():
		return
	if state.phase != GameRules.Phase.SELECTING and state.phase != GameRules.Phase.CLAP1:
		return
	if _resolving:
		return

	_select_left -= delta
	var elapsed := _window_total - _select_left

	if not _beat_fired[0] and elapsed >= CLAP1_ELAPSED:
		_beat_fired[0] = true
		beat.emit(1)
	if not _beat_fired[1] and elapsed >= CLAP2_ELAPSED:
		_beat_fired[1] = true
		beat.emit(2)

	# AI 出招（拍 2 前完成即可）
	_ai_timer -= delta
	if _ai_timer <= 0.0 and state.pending[1] < 0:
		try_select(1, _ai_choose())

	if _select_left <= 0.0:
		_force_timeout()
		return

	# 双方锁定且拍 2 已响 → 亮招结算
	if state.pending[0] >= 0 and state.pending[1] >= 0 and _beat_fired[1]:
		_resolve_locked()


func try_select(who: int, action: int) -> bool:
	if _resolving or state.is_over():
		return false
	if state.phase != GameRules.Phase.SELECTING and state.phase != GameRules.Phase.CLAP1:
		return false
	# 拍 2 后不可再改/再选
	if _beat_fired[1] and state.pending[who] < 0:
		return false
	if not state.can_use_action(who, action):
		return false
	state.pending[who] = action
	selected_changed.emit(who, action)
	return true


func try_select_change(who: int, action: int) -> bool:
	# 拍 2 前允许改选
	if who == 0 and not _beat_fired[1] and not _resolving and not state.is_over():
		if state.phase == GameRules.Phase.SELECTING or state.phase == GameRules.Phase.CLAP1:
			if state.can_use_action(who, action):
				state.pending[0] = action
				selected_changed.emit(who, action)
				return true
	return try_select(who, action)


func _force_timeout() -> void:
	for i in 2:
		if state.pending[i] < 0:
			var a: int = GameRules.Action.FANG if state.shield[i] >= 1 else GameRules.Action.ZAN
			if not state.can_use_action(i, a):
				a = GameRules.Action.ZAN
			state.pending[i] = a
			selected_changed.emit(i, a)
	# 超时视为拍 2 已过，直接结算
	_beat_fired[1] = true
	_resolve_locked()


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
		await get_tree().create_timer(0.6).timeout
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
	await get_tree().create_timer(0.6).timeout
	_start_selecting(state.round + 1)


func _emit_over() -> void:
	state.phase = GameRules.Phase.GAME_OVER
	phase_changed.emit(state.phase, state.round)
	game_over.emit(state.winner)


func _ai_choose() -> int:
	return AiOpponent.choose(state, 1)

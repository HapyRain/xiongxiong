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

## 单人选择页 → 对战页的配置槽（无 autoload，跨场景用静态变量；main.gd 取走即清空）。
static var pending_cfg: Dictionary = {}

var state: BattleState = BattleState.new()
var difficulty: String = "normal"
var _select_left: float = 0.0
var _beat_fired: Array = [false, false]
var _ai_timer: float = 0.0
var _resolving: bool = false
var _opening_done: bool = false
var _window_total: float = 0.0
var _did_lock_fill: bool = false
var _did_settle: bool = false


## 契约：_ready 绝不自动开局。所有入口（main.gd、测试）必须显式调用 start_match(cfg)，
## 否则对局停在未初始化状态（window_seconds()==0）。「避免没选模式就进对局」是这条契约的由来。
func _ready() -> void:
	pass


## ── UI 只读访问器：表现层只许走这些，不许读 _select_left/_resolving 等私有字段 ──

## 当前选招窗总时长（秒）；未 start_match 前为 0。
func window_seconds() -> float:
	return _window_total


## 当前选招窗剩余（秒）。
func select_left() -> float:
	return _select_left


func resolving() -> bool:
	return _resolving


func did_settle() -> bool:
	return _did_settle


func did_lock_fill() -> bool:
	return _did_lock_fill


func opening_done() -> bool:
	return _opening_done


## 单人开局入口。cfg = {mode:"classic"|"lesson", mastery:bool, difficulty:"normal"|"hard"}
func start_match(cfg: Dictionary) -> void:
	difficulty = str(cfg.get("difficulty", "normal"))
	var mode: String = str(cfg.get("mode", "lesson"))
	if not GameRules.PRESETS.has(mode):
		mode = "lesson"
	state = BattleState.new(mode, bool(cfg.get("mastery", false)))
	_start_opening(false)


## 唯一输入闸：UI 禁用与 try_select 共用
func is_pick_open() -> bool:
	if _resolving or _did_settle or _did_lock_fill:
		return false
	if state == null or state.is_over():
		return false
	if state.phase != GameRules.Phase.SELECTING and state.phase != GameRules.Phase.CLAP1:
		return false
	return true


## 开局流程。keep_score=true 表示「小局重开」：资源复位但保留 score，
## 沿用回合 1 的「亮相 + 点攒」流程（v2 §1：每小局开局 血4/盾3/气0，技能 CD 每局重置）。
func _start_opening(keep_score: bool = false) -> void:
	if keep_score:
		# 复位字段表由会话层统一给出，避免与热座/联机路径分叉
		state.reset_round_keep_score()
	else:
		# 整场（含再来一局）首次开局：score 归零，保留模式/精通（不能退回默认 lesson）
		state = BattleState.new(state.mode, state.mastery)
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
			var a: int = state.default_action(i)
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
		if not is_instance_valid(self) or not is_inside_tree():
			return
		_start_selecting(2)
		return
	state.phase = GameRules.Phase.RESOLVING
	phase_changed.emit(state.phase, state.round)
	var r := GameResolve.resolve_turn(state, state.pending[0], state.pending[1])
	# ── T6 小局判分 / 终场：与热座/联机路径共用同一份会话层裁决 ──
	# winner∈{0,1} → score+1；score 到 12 → 整场结束；否则重开一小局（保留 score）。
	var settled := state.settle_round_after_resolve()
	state.phase = GameRules.Phase.PRESENTING
	phase_changed.emit(state.phase, state.round)
	round_resolved.emit(r)
	if bool(settled["match_over"]):
		_emit_over()
		return
	await get_tree().create_timer(0.8).timeout
	if not is_instance_valid(self) or not is_inside_tree():
		return
	if bool(settled["round_end"]):
		# 小局结束但整场未结束 → 重开一小局（资源复位、score 保留、回合 1 亮相）
		_start_opening(true)
		return
	_start_selecting(state.round + 1)


func _emit_over() -> void:
	state.phase = GameRules.Phase.GAME_OVER
	phase_changed.emit(state.phase, state.round)
	# 整场胜者按分数裁决（平局保底可能让 winner=2 的一方/双方到 12 分）
	var w: int = state.match_winner()
	game_over.emit(w if w >= 0 else state.winner)


func _ai_choose() -> int:
	return AiOpponent.choose(state, 1, difficulty)

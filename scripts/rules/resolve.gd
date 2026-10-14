## resolve.gd
## 同步结算 —— 冻结规则 §3 / §1.1 / §4。纯函数。
class_name GameResolve
extends RefCounted


## 开局回合 1：双方强制攒结果。跳过选择与对撞。
static func resolve_opening(state: BattleState) -> GameRules.RoundResult:
	var r: GameRules.RoundResult = GameRules.RoundResult.new()
	r.opening = true
	r.actions = [GameRules.Action.ZAN, GameRules.Action.ZAN]
	r.qi_delta = [1, 1]
	r.shield_delta = [
		GameRules.MAX_SHIELD - int(state.shield[0]),
		GameRules.MAX_SHIELD - int(state.shield[1]),
	]
	r.text = "开局亮相：双方气 +1，盾 = 3"
	_apply(state, r)
	return r


## 常规回合：双方已锁定指令，同步结算。
static func resolve_turn(state: BattleState, act_me: int, act_you: int) -> GameRules.RoundResult:
	var r: GameRules.RoundResult = GameRules.RoundResult.new()
	r.actions = [act_me, act_you]

	for i: int in 2:
		var me: int = i
		var op: int = 1 - i
		var my_act: int = act_me if i == 0 else act_you
		var op_act: int = act_you if i == 0 else act_me

		# 1) 先扣波的气（无论是否命中）
		if my_act == GameRules.Action.BO:
			r.qi_delta[me] = int(r.qi_delta[me]) - 1

		# 2) 命中判定
		match my_act:
			GameRules.Action.BO:
				match op_act:
					GameRules.Action.ZAN:
						r.hp_delta[op] = int(r.hp_delta[op]) - 1
						r.hit[op] = true
					GameRules.Action.BO:
						pass
					GameRules.Action.FANG:
						r.shield_delta[op] = int(r.shield_delta[op]) - 1
						r.blocked[op] = true

	# 3) 最后结算攒的资源（封顶在 _apply）
	if act_me == GameRules.Action.ZAN:
		r.qi_delta[0] = int(r.qi_delta[0]) + 1
		r.shield_delta[0] = int(r.shield_delta[0]) + 1
	if act_you == GameRules.Action.ZAN:
		r.qi_delta[1] = int(r.qi_delta[1]) + 1
		r.shield_delta[1] = int(r.shield_delta[1]) + 1

	r.text = _describe(r)
	_apply(state, r)
	_check_winner(state)
	return r


static func _apply(state: BattleState, r: GameRules.RoundResult) -> void:
	for i: int in 2:
		state.qi[i] = GameRules.clamp_i(int(state.qi[i]) + int(r.qi_delta[i]), 0, GameRules.MAX_QI)
		state.shield[i] = GameRules.clamp_i(int(state.shield[i]) + int(r.shield_delta[i]), 0, GameRules.MAX_SHIELD)
		state.hp[i] = GameRules.clamp_i(int(state.hp[i]) + int(r.hp_delta[i]), 0, GameRules.MAX_HP)
	state.pending = [-1, -1]


static func _check_winner(state: BattleState) -> void:
	var me_dead: bool = int(state.hp[0]) <= 0
	var you_dead: bool = int(state.hp[1]) <= 0
	if me_dead and you_dead:
		state.winner = 2
		return
	if you_dead:
		state.winner = 0
		return
	if me_dead:
		state.winner = 1
		return
	if state.round >= GameRules.MAX_ROUND:
		if int(state.hp[0]) > int(state.hp[1]):
			state.winner = 0
		elif int(state.hp[1]) > int(state.hp[0]):
			state.winner = 1
		else:
			state.winner = 2


static func _describe(r: GameRules.RoundResult) -> String:
	var n0: String = GameRules.action_name(r.actions[0])
	var n1: String = GameRules.action_name(r.actions[1])
	var parts := PackedStringArray()
	parts.append("我 %s vs 对手 %s" % [n0, n1])
	if r.hit[0]:
		parts.append("我 -1 血")
	if r.hit[1]:
		parts.append("对手 -1 血")
	if r.blocked[0]:
		parts.append("我格挡，盾 -1")
	if r.blocked[1]:
		parts.append("对手格挡，盾 -1")
	return " · ".join(parts)

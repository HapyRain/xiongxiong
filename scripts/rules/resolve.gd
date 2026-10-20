## resolve.gd
## 同步结算 —— v2 契约 §2（五步管线）+ docs/rules/game-rules-v2.md §3 对撞矩阵 / §4 结算管线。
## 纯逻辑：只读写 BattleState + RoundResult，不碰 UI / 网络 / 节点。静态函数，可 headless 单测。
##
## resolve_turn 顺序（契约 §2.2；全程只在末尾调一次 _apply，再 _check_winner）：
##   Step A 劝降：满气满血 + 对方仅 1 血 → 直接判胜（不占动作 / 不扣资源 / 不进 CD），立即返回
##   Step B 扣资源：扣气；FANG 使用即耗 1 盾
##   Step C 吸收：XI_SHOU 对撞特例（偷增益 / 被攻击掉 1 血 / 对防御无事），先于 D、E
##   Step D 资源增益：ZAN +1气+1盾 / JI_QI +3气 / HUI_FU +1血 / BAO_QI 补满盾（被偷则跳过）
##   Step E 对撞矩阵：契约 §2.2 Step E 的 1–19 条（_pair → _bao_vs / _break_vs / _zhong_vs）
##   Step F 状态更新：CD 记录（顶招也进 CD、资源照扣）；封盾在 Step E 写入 sealed_round
class_name GameResolve
extends RefCounted


## 回合 1 亮相：双方强制攒气。qi +1（封顶 10）、shield +1（封顶 3）。
static func resolve_opening(state: BattleState) -> GameRules.RoundResult:
	var r: GameRules.RoundResult = GameRules.RoundResult.new()
	r.opening = true
	r.actions = [GameRules.Action.ZAN, GameRules.Action.ZAN]
	r.qi_delta = [1, 1]
	r.shield_delta = [1, 1]
	r.text = "开局亮相：双方气 +1"
	_apply(state, r)
	return r


## 常规回合：双方已锁定指令，同步结算。
## acts[i] 为座位 i 的出招（0 = 我，1 = 对手）。
static func resolve_turn(state: BattleState, act_me: int, act_you: int) -> GameRules.RoundResult:
	var r: GameRules.RoundResult = GameRules.RoundResult.new()
	var acts: Array = [act_me, act_you]
	r.actions = [act_me, act_you]

	# ── Step A 劝降（结算前自动触发，不占动作、不扣资源、不进 CD）────────────
	for i: int in 2:
		var can_quan_jiang: bool = (
			int(state.qi[i]) == GameRules.MAX_QI
			and int(state.hp[i]) == GameRules.MAX_HP
			and int(state.hp[1 - i]) == 1
		)
		if can_quan_jiang:
			state.winner = i
			state.pending = [-1, -1]
			r.quan_jiang = i
			r.text = "劝降：%d 胜" % i
			return r

	# FANG 的合法性在扣资源前定格：盾为 0 时出 FANG = 非法出招 → 按「裸防」处理（契约 §2.2 D_bare）
	var bare: Array = [false, false]
	for i: int in 2:
		bare[i] = int(acts[i]) == GameRules.Action.FANG and int(state.shield[i]) < 1

	# ── Step B 扣资源 ──────────────────────────────────────────────────────
	for i: int in 2:
		r.qi_delta[i] = int(r.qi_delta[i]) - GameRules.qi_cost(int(acts[i]))
		if int(acts[i]) == GameRules.Action.FANG and int(state.shield[i]) >= 1:
			r.shield_delta[i] = int(r.shield_delta[i]) - 1

	# ── Step C 吸收 ────────────────────────────────────────────────────────
	var stolen: Array = [false, false]
	for i: int in 2:
		if int(acts[i]) != GameRules.Action.XI_SHOU:
			continue
		var op: int = 1 - i
		var op_act: int = int(acts[op])
		if op_act == GameRules.Action.XI_SHOU:
			continue  # 吸收 vs 吸收：双方 1 气白花、无效果、不递归
		if GameRules.is_gain(op_act):
			_gain(state, r, i, op_act)  # 偷走效果、原样照搬
			stolen[op] = true
		elif GameRules.is_attack(op_act):
			_hit(r, i, 1)               # 只 1 血；攻击本身的其余效果作废
		# 其余（普通防御 / 加强防御）：无事发生，1 气白花

	# ── Step D 资源增益 ────────────────────────────────────────────────────
	for i: int in 2:
		if GameRules.is_gain(int(acts[i])) and not stolen[i]:
			_gain(state, r, i, int(acts[i]))

	# ── Step E 对撞矩阵 ────────────────────────────────────────────────────
	_pair(state, r, acts, bare)

	# ── Step F 状态更新（CD；封盾已在 Step E 写入）────────────────────────
	for i: int in 2:
		if GameRules.cooldown_of(int(acts[i])) > 0:
			var cds: Dictionary = state.cooldowns[i]
			cds[int(acts[i])] = state.round

	r.text = _describe(r)
	_apply(state, r)
	_check_winner(state)
	return r


# ══════════════════════════ Step E 对撞矩阵 ══════════════════════════════

## 按「无先后」分情况裁决双方动作。契约 §2.2 Step E 的 1–19 条。
static func _pair(state: BattleState, r: GameRules.RoundResult, acts: Array, bare: Array) -> void:
	var a: int = int(acts[0])
	var b: int = int(acts[1])

	# 吸收已在 Step C 独占处理（含「任意攻击 vs 吸收 → 吸收方掉 1 血」），此处不再重复
	if a == GameRules.Action.XI_SHOU or b == GameRules.Action.XI_SHOU:
		return

	# 1) 包子 vs 包子
	if GameRules.is_bao(a) and GameRules.is_bao(b):
		var m: int = GameRules.bao_count(a)
		var n: int = GameRules.bao_count(b)
		if m > n:
			_bao_damage(state, r, 1, m - n)
		elif n > m:
			_bao_damage(state, r, 0, n - m)
		return

	# 2)–8) 包子 vs 其它
	if GameRules.is_bao(a):
		_bao_vs(state, r, 0, GameRules.bao_count(a), b, bare)
		return
	if GameRules.is_bao(b):
		_bao_vs(state, r, 1, GameRules.bao_count(b), a, bare)
		return

	# 9)–10) 破防技互撞
	if GameRules.is_break(a) and GameRules.is_break(b):
		if a == b:
			return  # 小羊 vs 小羊 / 大羊 vs 大羊：互相抵消
		var xiao_side: int = 0 if a == GameRules.Action.XIAO_YANG else 1
		_hit(r, xiao_side, 1)  # 小羊 vs 大羊：大羊赢
		return

	# 12) 终极技 vs 终极技：双方各掉 2 血
	if a == GameRules.Action.ZHONG_JI and b == GameRules.Action.ZHONG_JI:
		_hit(r, 0, 2)
		_hit(r, 1, 2)
		return

	# 11) 小羊/大羊 vs 终极技：终极技赢
	if GameRules.is_break(a) and b == GameRules.Action.ZHONG_JI:
		_hit(r, 0, 2)
		return
	if GameRules.is_break(b) and a == GameRules.Action.ZHONG_JI:
		_hit(r, 1, 2)
		return

	# 8) / 13) / 14) / 17) 破防技 vs 防御类 / 爆气 / 裸防
	if GameRules.is_break(a):
		_break_vs(state, r, 0, a, b, bare)
		return
	if GameRules.is_break(b):
		_break_vs(state, r, 1, b, a, bare)
		return

	# 15) / 16) / 17) / 18) 终极技 vs 防御类 / 爆气 / 裸防
	if a == GameRules.Action.ZHONG_JI:
		_zhong_vs(state, r, 0, b)
		return
	if b == GameRules.Action.ZHONG_JI:
		_zhong_vs(state, r, 1, a)
		return

	# 19) 其余组合（防御互撞 / 防御 vs 增益 / 增益 vs 增益 / 爆气 vs 爆气 / 爆气 vs 防御或增益 …）
	#     无额外伤害（资源增益已在 Step D 结算）。


## 2)–8) 座位 i 出了 n 连包，对手出 op_act。
static func _bao_vs(
	state: BattleState,
	r: GameRules.RoundResult,
	i: int,
	n: int,
	op_act: int,
	bare: Array
) -> void:
	var op: int = 1 - i
	match op_act:
		GameRules.Action.FANG:
			# 2) 防御：1–2 连被挡；3 连破防掉 1 血（FANG 使用耗盾已在 Step B 扣）
			if bare[op]:
				_hit(r, op, 1)
			elif n >= GameRules.BAO_MAX:
				_hit(r, op, 1)
			else:
				r.blocked[op] = true
		GameRules.Action.STRONG_FANG:
			r.blocked[op] = true  # 3) 被挡（不耗盾、不掉盾、不掉血）
		GameRules.Action.BAO_QI:
			# 4) 爆气先补满盾（Step D 已做）；只挡 1 个包子，剩余每个 2 盾伤
			var k: int = n - 1
			if k > 0:
				_bao_damage(state, r, op, k)
			else:
				r.blocked[op] = true
		GameRules.Action.XIAO_YANG:
			# 5) 1 包 + 1 盾挡下（0 盾 → 挡不住掉 1 血）；2 包挡下不掉盾；3 连包克制小羊
			if n == 1:
				_block_with_shield(state, r, i)
			elif n == 2:
				r.blocked[i] = true
			else:
				_hit(r, op, 1)
		GameRules.Action.DA_YANG:
			# 6) 1 包挡不住；2 包挡下耗 1 盾（0 盾 → 掉 1 血）；3 包完全挡下
			if n == 1:
				_hit(r, i, 1)
			elif n == 2:
				_block_with_shield(state, r, i)
			else:
				r.blocked[i] = true
		GameRules.Action.ZHONG_JI:
			# 7) 3 连包挡住（终极技无效）；1–2 连挡不住掉 2 血
			if n >= GameRules.BAO_MAX:
				r.blocked[i] = true
			else:
				_hit(r, i, 2)
		GameRules.Action.ZAN, GameRules.Action.JI_QI, GameRules.Action.HUI_FU:
			# 8) 裸防：不论几连包，只掉 1 血
			_hit(r, op, 1)
		_:
			pass


## 8) / 13) / 14) / 17) 座位 i 出了破防技 act（小羊 / 大羊），对手出 op_act。
static func _break_vs(
	state: BattleState,
	r: GameRules.RoundResult,
	i: int,
	act: int,
	op_act: int,
	bare: Array
) -> void:
	var op: int = 1 - i
	match op_act:
		GameRules.Action.FANG:
			if bare[op]:
				_hit(r, op, 1)  # 裸防（盾 0 出防御）：掉 1 血
			elif act == GameRules.Action.XIAO_YANG:
				state.sealed_round[op] = state.round + 1  # 13) 小羊破防：封盾 1 回合，不掉血
				r.sealed[op] = true
			else:
				_hit(r, op, 1)  # 13) 大羊穿普通防御 → 掉 1 血
		GameRules.Action.STRONG_FANG:
			r.blocked[op] = true  # 14) 被挡（不耗盾、不掉盾、不掉血）
		GameRules.Action.BAO_QI:
			_hit(r, op, 1)  # 17) 爆气照常命中 1 血（小羊 / 大羊同）
		GameRules.Action.ZAN, GameRules.Action.JI_QI, GameRules.Action.HUI_FU:
			_hit(r, op, 1)  # 8) 裸防：小羊 / 大羊 各 1 血
		_:
			pass


## 15) / 16) / 17) / 18) 座位 i 出了终极技，对手出 op_act。
static func _zhong_vs(state: BattleState, r: GameRules.RoundResult, i: int, op_act: int) -> void:
	var op: int = 1 - i
	match op_act:
		GameRules.Action.FANG:
			_hit(r, op, 2)  # 15) 无视普通防御 → 掉 2 血
		GameRules.Action.STRONG_FANG:
			# 16) 被挡，但掉光所有盾
			r.blocked[op] = true
			r.shield_delta[op] = int(r.shield_delta[op]) - _eff_shield(state, r, op)
		GameRules.Action.BAO_QI:
			_hit(r, op, 2)  # 17) 补满盾照常命中 2 血
		GameRules.Action.ZAN, GameRules.Action.JI_QI, GameRules.Action.HUI_FU:
			_hit(r, op, 2)  # 18) 裸防 → 2 血
		_:
			pass


# ══════════════════════════ 结算辅助 ══════════════════════════════════════

## 契约 §2.2 _bao_damage：k 个「剩余包子」打 victim —— 每包 2 盾伤，盾打穿后最多 1 血。
## 判盾用「有效盾」（当前盾 + 本轮已累积盾增量）：爆气「先补满盾再结算」要求如此；
## 无本轮盾增量的场合与契约字面写法（读 state.shield）完全等价。
static func _bao_damage(state: BattleState, r: GameRules.RoundResult, victim: int, k: int) -> void:
	var dmg: int = k * 2
	var eff: int = _eff_shield(state, r, victim)
	if eff >= dmg:
		r.shield_delta[victim] = int(r.shield_delta[victim]) - dmg
	else:
		r.shield_delta[victim] = int(r.shield_delta[victim]) - eff
		r.hp_delta[victim] = int(r.hp_delta[victim]) - 1
		r.hit[victim] = true


## 结算中的「有效盾」= 当前盾 + 本轮已累积盾增量，clamp 到 [0, 3]。
static func _eff_shield(state: BattleState, r: GameRules.RoundResult, who: int) -> int:
	return GameRules.clamp_i(
		int(state.shield[who]) + int(r.shield_delta[who]), 0, GameRules.MAX_SHIELD
	)


## 扣血 + 记命中。
static func _hit(r: GameRules.RoundResult, who: int, dmg: int) -> void:
	r.hp_delta[who] = int(r.hp_delta[who]) - dmg
	r.hit[who] = true


## 包子 1 连挡小羊 / 2 连挡大羊：盾 ≥1 则耗 1 盾挡下；0 盾 → 挡不住，掉 1 血。
static func _block_with_shield(state: BattleState, r: GameRules.RoundResult, who: int) -> void:
	if _eff_shield(state, r, who) >= 1:
		r.shield_delta[who] = int(r.shield_delta[who]) - 1
		r.blocked[who] = true
	else:
		_hit(r, who, 1)


## Step D 资源增益（也被 Step C 的「偷走原样照搬」复用）。
static func _gain(state: BattleState, r: GameRules.RoundResult, who: int, act: int) -> void:
	match act:
		GameRules.Action.ZAN:
			r.qi_delta[who] = int(r.qi_delta[who]) + 1
			r.shield_delta[who] = int(r.shield_delta[who]) + 1
		GameRules.Action.JI_QI:
			r.qi_delta[who] = int(r.qi_delta[who]) + 3
		GameRules.Action.HUI_FU:
			# +1 血（上限 4）；溢出作废、不结转（§1）——只能补到当前空位，
			# 否则满血出回复会把 +1 结转为「免疫本回合伤害」。
			var room: int = GameRules.MAX_HP - GameRules.clamp_i(
				int(state.hp[who]) + int(r.hp_delta[who]), 0, GameRules.MAX_HP
			)
			r.hp_delta[who] = int(r.hp_delta[who]) + maxi(0, mini(1, room))
		GameRules.Action.BAO_QI:
			r.shield_delta[who] = GameRules.MAX_SHIELD - int(state.shield[who])  # 补满 3
		_:
			pass


# ══════════════════════════ 收尾 ══════════════════════════════════════════

## 落地本轮增量：气 / 盾 / 血各自 clamp 到 [0, 上限]；清空 pending。
## 不动 cooldowns / score / sealed_round（分别由 Step F、会话层、Step E 写）。
static func _apply(state: BattleState, r: GameRules.RoundResult) -> void:
	for i: int in 2:
		state.qi[i] = GameRules.clamp_i(int(state.qi[i]) + int(r.qi_delta[i]), 0, GameRules.MAX_QI)
		state.shield[i] = GameRules.clamp_i(
			int(state.shield[i]) + int(r.shield_delta[i]), 0, GameRules.MAX_SHIELD
		)
		state.hp[i] = GameRules.clamp_i(int(state.hp[i]) + int(r.hp_delta[i]), 0, GameRules.MAX_HP)
	state.pending = [-1, -1]


## 终局判定：血量归零判负；双亡 = 平局；40 回合比血（血同判平，不比盾）。
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


## 文案：沿用「我 X vs 对手 Y · …」风格（GameRules.action_name）。
static func _describe(r: GameRules.RoundResult) -> String:
	return describe(r, 0)


## 文案按 viewer 座位生成：联机下客户端拿到同一份 RoundResult，文案必须换视角。
static func describe(r: GameRules.RoundResult, viewer: int = 0) -> String:
	var me: int = clampi(viewer, 0, 1)
	var op: int = 1 - me
	var parts := PackedStringArray()
	parts.append(
		"我 %s vs 对手 %s"
		% [
			GameRules.action_name(int(r.actions[me])),
			GameRules.action_name(int(r.actions[op])),
		]
	)
	var names: Array = ["我", "对手"]
	for p: int in 2:
		var seat: int = me if p == 0 else op
		var who: String = names[p]
		if int(r.hp_delta[seat]) < 0:
			parts.append("%s %d 血" % [who, int(r.hp_delta[seat])])
		if int(r.shield_delta[seat]) < 0:
			parts.append("%s %d 盾" % [who, int(r.shield_delta[seat])])
		if r.blocked[seat]:
			parts.append("%s格挡" % who)
		if r.sealed[seat]:
			parts.append("%s被封盾" % who)
	if int(r.actions[me]) == GameRules.Action.XI_SHOU or int(r.actions[op]) == GameRules.Action.XI_SHOU:
		parts.append("吸收")
	return " · ".join(parts)

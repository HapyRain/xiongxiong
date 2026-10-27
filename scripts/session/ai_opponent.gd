## ai_opponent.gd
## 简易人机选招：与单机 battle_controller 同策略，供人机对局 / 联机掉线接管复用。
## 只读 BattleState，不改 scripts/rules/* 结算语义。
##
## v2 迁移要点（docs/rules/game-rules-v2.md §1/§2）：
##   · 只返回「本回合真的可用」的招：候选必须满足 state.can_use_action(who, a)
##     （解锁分 / 耗气 / 盾≥1 / 封盾 / CD 全部由规则层裁决，AI 不再自己记一套数值）；
##   · 回合 1（开局亮相）规则只允许攒气 → 直接攒；
##   · 低气优先攒气（攒气还是唯一「无耗气 + 加盾」的基本招）；简单加权随机，够用即可。
## 难度（PLAN v1.1 R3）：normal = 现权重（攒气/包子×1/防御）；
## hard = 候选追加包子 2/3 连（lesson 才有，classic 会被 can_use_action 挡掉），
##        且「对手在攒气」时加重包子；自己盾少时收着防御。
class_name AiOpponent
extends RefCounted

## 候选权重表（choose 的唯一来源；测试直接比对权重，不依赖随机采样）。
## 只含 can_use_action 放行的招；权重 0 = 不进池（不写入本表，choose 拿不到）。
static func weights(state: BattleState, who: int = 1, difficulty: String = "normal") -> Dictionary:
	if state == null:
		return {}
	var seat: int = clampi(who, 0, 1)
	var hard: bool = difficulty == "hard"
	var foe: int = 1 - seat
	# hard 的「对手气量较上回合增长」：state 没有上一回合气量字段，用 qi[foe] >= 2 近似
	# （对手只有出攒气才会涨气，等价于「上回合攒过」的短记）。
	# shortcut: 久攒不用的气也会被当成刚增长；要精确需在 BattleState 记上一回合 qi（rules 层，走冻结流程）。
	var foe_building: bool = hard and int(state.qi[foe]) >= 2
	# 候选集：攒气 / 包子 1-3 连 / 防御（hard 才放 2/3 连，normal 维持原三招）
	var candidates: Array = [GameRules.Action.ZAN, GameRules.Action.BAO1, GameRules.Action.FANG]
	if hard:
		candidates = [GameRules.Action.ZAN, GameRules.Action.BAO1,
			GameRules.Action.BAO2, GameRules.Action.BAO3, GameRules.Action.FANG]
	var low_qi: bool = int(state.qi[seat]) <= 1
	var out: Dictionary = {}
	for a: int in candidates:
		if not state.can_use_action(seat, a):
			continue
		var w: int = 1
		match a:
			GameRules.Action.ZAN:
				w = 4 if low_qi else 2
			GameRules.Action.BAO1, GameRules.Action.BAO2, GameRules.Action.BAO3:
				# 低气只有 ×1 有边际价值；连数越高耗气越多，权重递减
				w = maxi(1, (3 if not low_qi else 1) - (a - GameRules.Action.BAO1))
				if foe_building:
					w += 3
			GameRules.Action.FANG:
				w = 2 if int(state.shield[seat]) >= 1 else 0
				# hard：自己盾少时省着用（盾 0 本来就非法，这里覆盖盾 1）
				if hard and int(state.shield[seat]) <= 1:
					w = 0
		# 权重 0 = 不进池：不写入表，choose 的采样池里就不会出现
		if w > 0:
			out[a] = w
	return out


## who=0/1 座位；difficulty = normal|hard。返回 GameRules.Action。
static func choose(state: BattleState, who: int = 1, difficulty: String = "normal") -> int:
	if state == null:
		return GameRules.Action.ZAN
	var seat: int = clampi(who, 0, 1)
	# 开局回合：规则只放行攒气（battle_state.gd can_use_action 第 1 条）
	if state.round == GameRules.OPENING_ROUND:
		return GameRules.Action.ZAN

	var pool: Array = []
	var w := weights(state, seat, difficulty)
	for a in w:
		for _i in maxi(0, int(w[a])):
			pool.append(a)
	if pool.is_empty():
		# 兜底：候选全被规则挡住时，退到本回合可用集里的第一个（含 ZAN）
		var avail: Array = state.available_actions(seat)
		if avail.is_empty():
			return GameRules.Action.ZAN
		return int(avail[0])
	return int(pool[randi() % pool.size()])

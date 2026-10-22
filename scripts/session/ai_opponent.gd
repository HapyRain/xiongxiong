## ai_opponent.gd
## 简易人机选招：与单机 battle_controller 同策略，供人机对局 / 联机掉线接管复用。
## 只读 BattleState，不改 scripts/rules/* 结算语义。
##
## v2 迁移要点（docs/rules/game-rules-v2.md §1/§2）：
##   · 只返回「本回合真的可用」的招：候选必须满足 state.can_use_action(who, a)
##     （解锁分 / 耗气 / 盾≥1 / 封盾 / CD 全部由规则层裁决，AI 不再自己记一套数值）；
##   · 回合 1（开局亮相）规则只允许攒气 → 直接攒；
##   · 低气优先攒气（攒气还是唯一「无耗气 + 加盾」的基本招）；简单加权随机，够用即可。
class_name AiOpponent
extends RefCounted

## who=0/1 座位。返回 GameRules.Action。
static func choose(state: BattleState, who: int = 1) -> int:
	if state == null:
		return GameRules.Action.ZAN
	var seat: int = clampi(who, 0, 1)
	# 开局回合：规则只放行攒气（battle_state.gd can_use_action 第 1 条）
	if state.round == GameRules.OPENING_ROUND:
		return GameRules.Action.ZAN

	# 候选集：攒气 / 包子×1 / 防御（低气时攒气权重最高）
	var candidates: Array = [GameRules.Action.ZAN, GameRules.Action.BAO1, GameRules.Action.FANG]
	var low_qi: bool = int(state.qi[seat]) <= 1
	var pool: Array = []
	for a: int in candidates:
		if not state.can_use_action(seat, a):
			continue
		var w: int = 1
		match a:
			GameRules.Action.ZAN:
				w = 4 if low_qi else 2
			GameRules.Action.BAO1:
				w = 3 if not low_qi else 1
			GameRules.Action.FANG:
				w = 2 if int(state.shield[seat]) >= 1 else 0
		for _i in maxi(0, w):
			pool.append(a)

	if pool.is_empty():
		# 兜底：候选全被规则挡住时，退到本回合可用集里的第一个（含 ZAN）
		var avail: Array = state.available_actions(seat)
		if avail.is_empty():
			return GameRules.Action.ZAN
		return int(avail[0])
	return int(pool[randi() % pool.size()])

## ai_opponent.gd
## 简易人机选招：与单机 battle_controller 同策略，供人机对局 / 联机掉线接管复用。
## 只读 BattleState，不改 scripts/rules/* 结算语义。
class_name AiOpponent
extends RefCounted


## who=0/1 座位。返回 GameRules.Action。
static func choose(state: BattleState, who: int = 1) -> int:
	if state == null:
		return GameRules.Action.ZAN
	var seat: int = clampi(who, 0, 1)
	var pool: Array = []
	if state.qi[seat] <= 1:
		pool.append_array([GameRules.Action.ZAN, GameRules.Action.ZAN, GameRules.Action.ZAN])
	if state.qi[seat] >= 1:
		pool.append_array([GameRules.Action.BO, GameRules.Action.BO])
	if state.shield[seat] >= 1:
		pool.append(GameRules.Action.FANG)
	if pool.is_empty():
		pool.append(GameRules.Action.ZAN)
	return int(pool[randi() % pool.size()])

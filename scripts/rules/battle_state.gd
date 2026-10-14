## battle_state.gd
## 对局状态 —— 双方资源 + 回合 + 胜负。纯数据。
class_name BattleState
extends RefCounted

var round: int = 1
var hp: Array = [GameRules.MAX_HP, GameRules.MAX_HP]       # [我, 对手]
var qi: Array = [0, 0]
var shield: Array = [0, 0]
var pending: Array = [-1, -1]  # -1 未选，否则 GameRules.Action
var phase: int = GameRules.Phase.OPENING
var winner: int = -1           # -1 未分, 0 我胜, 1 对手胜, 2 平局


func is_opening() -> bool:
	return round == GameRules.OPENING_ROUND and phase == GameRules.Phase.OPENING


func can_use_action(who: int, action: int) -> bool:
	# 回合 1：仅「攒」
	if round == GameRules.OPENING_ROUND:
		return action == GameRules.Action.ZAN
	match action:
		GameRules.Action.ZAN:
			return true
		GameRules.Action.BO:
			return qi[who] >= 1
		GameRules.Action.FANG:
			return shield[who] >= 1
	return false


func available_actions(who: int) -> Array:
	var out: Array = []
	for a in [GameRules.Action.ZAN, GameRules.Action.BO, GameRules.Action.FANG]:
		if can_use_action(who, a):
			out.append(a)
	return out


func is_over() -> bool:
	return winner >= 0


func snapshot() -> Dictionary:
	return {
		"round": round,
		"hp": hp.duplicate(),
		"qi": qi.duplicate(),
		"shield": shield.duplicate(),
		"pending": pending.duplicate(),
		"phase": phase,
		"winner": winner,
	}


func restore(s: Dictionary) -> void:
	round = s.get("round", 1)
	hp = s.get("hp", [GameRules.MAX_HP, GameRules.MAX_HP]).duplicate()
	qi = s.get("qi", [0, 0]).duplicate()
	shield = s.get("shield", [0, 0]).duplicate()
	pending = s.get("pending", [-1, -1]).duplicate()
	phase = s.get("phase", GameRules.Phase.SELECTING)
	winner = s.get("winner", -1)

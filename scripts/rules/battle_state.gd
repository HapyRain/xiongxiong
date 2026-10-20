## battle_state.gd
## 对局状态 —— 双方资源 + 回合 + 胜负 + 计分 / 冷却 / 封盾。纯数据。
class_name BattleState
extends RefCounted

var round: int = 1
var hp: Array = [GameRules.MAX_HP, GameRules.MAX_HP]             # [我, 对手]
var qi: Array = [0, 0]
var shield: Array = [GameRules.MAX_SHIELD, GameRules.MAX_SHIELD] # 开局盾 3
var pending: Array = [-1, -1]                                    # -1 未选，否则 GameRules.Action
var phase: int = GameRules.Phase.OPENING
var winner: int = -1                                             # -1 未分, 0 我胜, 1 对手胜, 2 平局
var score: Array = [0, 0]                                        # 每赢一小局 +1（会话层写入）
var cooldowns: Array = [{}, {}]                                  # cooldowns[who] = {action:int -> used_round:int}
var sealed_round: Array = [-1, -1]                               # 被封盾的回合号；-1 未封


func is_opening() -> bool:
	return round == GameRules.OPENING_ROUND and phase == GameRules.Phase.OPENING


func is_sealed(who: int) -> bool:
	return int(sealed_round[who]) == round


func is_over() -> bool:
	return winner >= 0


## 契约 §1 八条裁决：
## 1) 回合 1 仅攒气  2) 不在技能表  3) 未解锁  4) 气不足
## 5) 防御需盾 ≥1  6) 封盾禁 FANG/BAO_QI  7) 冷却中  8) 否则可用
func can_use_action(who: int, action: int) -> bool:
	if who < 0 or who > 1:
		return false
	if round == GameRules.OPENING_ROUND:
		return action == GameRules.Action.ZAN
	if not GameRules.SKILLS.has(action):
		return false
	if score[who] < GameRules.unlock_score(action):
		return false
	if qi[who] < GameRules.qi_cost(action):
		return false
	if action == GameRules.Action.FANG and shield[who] < 1:
		return false
	if is_sealed(who) and GameRules.is_sealable(action):
		return false
	var cd: int = GameRules.cooldown_of(action)
	if cd > 0 and round <= int(cooldowns[who].get(action, 0)) + cd:
		return false
	return true


func available_actions(who: int) -> Array:
	var out: Array = []
	for a in GameRules.SKILLS:
		if can_use_action(who, a):
			out.append(a)
	return out


func snapshot() -> Dictionary:
	return {
		"round": round,
		"hp": hp.duplicate(),
		"qi": qi.duplicate(),
		"shield": shield.duplicate(),
		"pending": pending.duplicate(),
		"phase": phase,
		"winner": winner,
		"score": score.duplicate(),
		"cooldowns": cooldowns.duplicate(true),
		"sealed_round": sealed_round.duplicate(),
	}


func restore(s: Dictionary) -> void:
	round = int(s.get("round", 1))
	hp = (s.get("hp", [GameRules.MAX_HP, GameRules.MAX_HP]) as Array).duplicate()
	qi = (s.get("qi", [0, 0]) as Array).duplicate()
	shield = (s.get("shield", [GameRules.MAX_SHIELD, GameRules.MAX_SHIELD]) as Array).duplicate()
	pending = (s.get("pending", [-1, -1]) as Array).duplicate()
	phase = int(s.get("phase", GameRules.Phase.OPENING))
	winner = int(s.get("winner", -1))
	score = (s.get("score", [0, 0]) as Array).duplicate()
	cooldowns = (s.get("cooldowns", [{}, {}]) as Array).duplicate(true)
	sealed_round = (s.get("sealed_round", [-1, -1]) as Array).duplicate()

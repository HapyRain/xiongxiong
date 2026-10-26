## battle_state.gd
## 对局状态 —— 双方资源 + 回合 + 胜负 + 计分 / 冷却 / 封盾。纯数据。
## 模式参数（血/气/盾上限、包子连数、可用动作、劝降、平局保底、分制、回合上限）一律读 GameRules.PRESETS；
## 默认 lesson（现有 v2 行为，全部断言不变），classic 见 docs/rules/game-rules-classic.md。
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
var draw_count: int = 0                                          # 平局累计：lesson 第 3 次起保底（§1/§5）；classic 重开本局
var cooldowns: Array = [{}, {}]                                  # cooldowns[who] = {action:int -> used_round:int}
var sealed_round: Array = [-1, -1]                               # 被封盾的回合号；-1 未封

var mode: String = "lesson"                                      # classic | lesson
var mastery: bool = false                                        # 精通（会话选项，不是规则）：旁路解锁分、不再累加解锁
var _params: Dictionary = {}


func _init(mode_name: String = "lesson", is_mastery: bool = false) -> void:
	set_preset(mode_name, is_mastery)
	hp = [max_hp(), max_hp()]
	shield = [max_shield(), max_shield()]


## 配置模式预设 + 精通开关（未知模式回退 lesson）。不动当前资源/比分：
## 新对局请先 set_preset() 再 reset_round_keep_score()（后者按新预设复位资源）。
func set_preset(mode_name: String, is_mastery: bool = false) -> void:
	mode = mode_name if GameRules.PRESETS.has(mode_name) else "lesson"
	mastery = is_mastery
	_params = GameRules.preset(mode)


func max_hp() -> int:
	return int(_params["max_hp"])


func max_qi() -> int:
	return int(_params["max_qi"])


func max_shield() -> int:
	return int(_params["max_shield"])


func bao_max() -> int:
	return int(_params["bao_max"])


func score_to_win() -> int:
	return int(_params["score_to_win"])


func round_cap() -> int:
	return int(_params["round_cap"])


func draw_replay_max() -> int:
	return int(_params["draw_replay_max"])


func draw_backstop() -> bool:
	return bool(_params["draw_backstop"])


func skills_enabled() -> bool:
	return bool(_params["skills_enabled"])


func quan_jiang_enabled() -> bool:
	return bool(_params["quan_jiang_enabled"])


func is_opening() -> bool:
	return round == GameRules.OPENING_ROUND and phase == GameRules.Phase.OPENING


func is_sealed(who: int) -> bool:
	return int(sealed_round[who]) == round


func is_over() -> bool:
	return winner >= 0


## 八条合法性裁决（docs/rules/game-rules-v2.md §1/§2 + 封盾 §3.6；classic 见 game-rules-classic.md）：
## 1) 回合 1 仅攒气  2) 不在技能表 / 不在本模式可用动作  3) 未解锁（精通旁路；classic 不看）
## 4) 气不足  5) 防御需盾 ≥1  6) 封盾禁 FANG/BAO_QI  7) 冷却中  8) 否则可用
func can_use_action(who: int, action: int) -> bool:
	if who < 0 or who > 1:
		return false
	if round == GameRules.OPENING_ROUND:
		return action == GameRules.Action.ZAN
	if not GameRules.SKILLS.has(action) or not (_params["actions"] as Array).has(action):
		return false
	# 精通（mastery）旁路解锁分支：视为全解锁，不再累加解锁分；classic 无解锁概念。
	if skills_enabled() and not mastery and score[who] < GameRules.unlock_score(action):
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
	var acts: Array = _params["actions"]
	for a in acts:
		if can_use_action(who, a):
			out.append(a)
	return out


## 超时/缺招兜底出招：优先防御（盾≥1），否则攒气；不合法（开局/封盾/CD 等）一律退到攒气。
func default_action(who: int) -> int:
	var a: int = GameRules.Action.FANG if int(shield[who]) >= 1 else GameRules.Action.ZAN
	if not can_use_action(who, a):
		a = GameRules.Action.ZAN
	return a


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
		"draw_count": draw_count,
		"cooldowns": cooldowns.duplicate(true),
		"sealed_round": sealed_round.duplicate(),
		"mode": mode,
		"mastery": mastery,
	}


## 快照恢复：外部数据（联机/回放）一律钳制到合法区间，越界就地修正而非信任。
## 带 mode/mastery 时必须与本地预设一致（房主权威），不一致或未知模式 → 拒绝并返回 false（状态不动）。
func restore(s: Dictionary) -> bool:
	if s.has("mode"):
		var m: String = str(s["mode"])
		if not GameRules.PRESETS.has(m) or m != mode:
			return false
	if s.has("mastery") and bool(s["mastery"]) != mastery:
		return false
	round = GameRules.clamp_i(int(s.get("round", 1)), 1, round_cap())
	hp = _pair(s.get("hp"), max_hp(), max_hp(), 0, max_hp())
	qi = _pair(s.get("qi"), 0, 0, 0, max_qi())
	shield = _pair(s.get("shield"), max_shield(), max_shield(), 0, max_shield())
	pending = _pair(s.get("pending"), -1, -1, -1, GameRules.Action.QUAN_JIANG)
	phase = GameRules.clamp_i(int(s.get("phase", GameRules.Phase.OPENING)), GameRules.Phase.OPENING, GameRules.Phase.GAME_OVER)
	winner = GameRules.clamp_i(int(s.get("winner", -1)), -1, 2)
	score = _pair(s.get("score"), 0, 0, 0, score_to_win())
	draw_count = GameRules.clamp_i(int(s.get("draw_count", 0)), 0, round_cap())
	cooldowns = _cooldowns(s.get("cooldowns"))
	sealed_round = _pair(s.get("sealed_round"), -1, -1, -1, round_cap())
	return true


func _pair(v: Variant, d0: int, d1: int, lo: int, hi: int) -> Array:
	if typeof(v) != TYPE_ARRAY or (v as Array).size() < 2:
		return [d0, d1]
	return [
		GameRules.clamp_i(int((v as Array)[0]), lo, hi),
		GameRules.clamp_i(int((v as Array)[1]), lo, hi),
	]


func _cooldowns(v: Variant) -> Array:
	var out: Array = [{}, {}]
	if typeof(v) != TYPE_ARRAY:
		return out
	var acts: Array = _params["actions"]
	for i: int in 2:
		if i >= (v as Array).size() or typeof((v as Array)[i]) != TYPE_DICTIONARY:
			continue
		var src: Dictionary = (v as Array)[i]
		for k in src.keys():
			var act: int = int(k)
			if not acts.has(act):
				continue
			out[i][act] = GameRules.clamp_i(int(src[k]), 0, round)
	return out


## 一小局结束后的判分（唯一口径，单机/热座/联机共用）：winner ∈ {0,1} → score+1；
## winner == 2（平局）→ draw_backstop 模式（lesson）draw_count+1，第 3 次起双方各 +1（§1/§5）；
## classic 无保底：draw_count+1 后由会话层重开本局，第 draw_replay_max+1 次平局整场判平（is_match_over）。
## 返回 {"round_end","match_over","match_winner","winner","score","scored"}；小局未分胜负时 round_end=false。
func settle_round_after_resolve() -> Dictionary:
	var info := {
		"round_end": false,
		"match_over": false,
		"match_winner": -1,
		"winner": -1,
		"score": [int(score[0]), int(score[1])],
		"scored": false,
	}
	if not is_over():
		return info
	var w: int = int(winner)
	info["winner"] = w
	info["round_end"] = true
	if w == 0 or w == 1:
		score[w] = int(score[w]) + 1
		info["scored"] = true
	elif w == 2:
		draw_count += 1
		if draw_backstop() and draw_count >= 3:
			score[0] = int(score[0]) + 1
			score[1] = int(score[1]) + 1
			info["scored"] = true
	info["score"] = [int(score[0]), int(score[1])]
	info["match_over"] = is_match_over()
	info["match_winner"] = match_winner()
	return info


## 整场是否结束：任一方达到本模式的分制；classic 另外「平局重开次数用尽 → 整场判平」。
func is_match_over() -> bool:
	if maxi(int(score[0]), int(score[1])) >= score_to_win():
		return true
	return not draw_backstop() and draw_count > draw_replay_max()


## 整场胜者：-1 未结束；分高者胜；平局保底同时到达分制 / classic 平局用尽 → 整场判平（2）。
func match_winner() -> int:
	if not is_match_over():
		return -1
	var a: int = int(score[0])
	var b: int = int(score[1])
	if a > b:
		return 0
	if b > a:
		return 1
	return 2


## 重开一小局：除 score / draw_count / mode / mastery 外全部复位（winner 重置为 -1，is_over() 恢复可开局）。
## 开局亮相（回合 1 点「攒」）的加分不在这里，由 PeerManager._do_opening() / BattleController._start_opening(true) 写入。
## 字段清单与 snapshot() 一致，缺一漏一都会导致重开后状态错位；资源上限按当前预设。
func reset_round_keep_score() -> void:
	restore({
		"round": GameRules.OPENING_ROUND,
		"hp": [max_hp(), max_hp()],
		"qi": [0, 0],
		"shield": [max_shield(), max_shield()],
		"pending": [-1, -1],
		"phase": GameRules.Phase.SELECTING,
		"winner": -1,
		"score": [int(score[0]), int(score[1])],
		"draw_count": draw_count,
		"cooldowns": [{}, {}],
		"sealed_round": [-1, -1],
	})

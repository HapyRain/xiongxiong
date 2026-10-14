## game_rules.gd
## 纯规则引擎 —— 对应 docs/rules/minimal-rules-v0.md（已冻结 2026-10-14）
## 无节点依赖，可单测。不读画质、不碰网络、不碰 UI。
class_name GameRules
extends RefCounted

enum Action { ZAN, BO, FANG }
enum Phase { OPENING, SELECTING, CLAP1, CLAP2, LOCKED, RESOLVING, PRESENTING, GAME_OVER }

const MAX_QI := 5
const MAX_HP := 5
const MAX_SHIELD := 3
const MAX_ROUND := 40
const OPENING_ROUND := 1

# 结算结果（供 UI/音效层消费，规则层不播表现）
class RoundResult:
	extends RefCounted
	var actions: Array = []          # [Action, Action] 我、对手
	var hp_delta: Array = [0, 0]     # 负数为扣血
	var qi_delta: Array = [0, 0]
	var shield_delta: Array = [0, 0]
	var hit: Array = [false, false]  # 我是否被打中 / 对手是否被打中
	var blocked: Array = [false, false]  # 我是否成功格挡 / 对手
	var opening: bool = false
	var text: String = ""


static func action_name(a: Action) -> String:
	match a:
		Action.ZAN: return "攒"
		Action.BO: return "波"
		Action.FANG: return "防"
	return "?"


static func clamp_i(v: int, lo: int, hi: int) -> int:
	return int(clamp(v, lo, hi))

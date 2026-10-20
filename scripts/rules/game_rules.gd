## game_rules.gd
## 纯规则引擎 —— 对应 docs/rules/game-rules-v2.md（v2 实现基线，唯一依据）。
## 无节点依赖，可单测。不读画质、不碰网络、不碰 UI。
##
## 接口约定（T1，Lead 冻结）：
##   Action 枚举值 = 技能身份；「包子」是多连动作本身（BAO1/BAO2/BAO3 = 同一技能 1–3 连，
##   每人每回合只能出 1 个动作）。劝降（QUAN_JIANG）不占动作、结算前自动触发、不可被吸收偷。
##   技能数据（耗气/ CD / 解锁分）统一由下面 4 个 static 查询函数给出，resolve 与会话层都读它，
##   不要在别处再抄一份数值表。
class_name GameRules
extends RefCounted

## 动作枚举。数值即序列化身份，跨端一致（房主下发/客户端 apply 用同一枚举）。
enum Action {
	ZAN,          ## 攒气：0 气，+1 气 +1 盾，无防御
	BAO1,         ## 包子 ×1：1 气
	BAO2,         ## 包子 ×2：2 气
	BAO3,         ## 包子 ×3：3 气
	FANG,         ## 防御：0 气，需盾 ≥1，使用即耗 1 盾
	STRONG_FANG,  ## 加强防御：1 气，CD1，挡当回合一切攻击（不耗盾）
	XIAO_YANG,    ## 小羊：1 气，CD3，破普通防御（盾 −1 且封盾 1 回合）
	JI_QI,        ## 集气：0 气，CD3，+3 气
	XI_SHOU,      ## 吸收：1 气，CD3，偷非攻击动作
	DA_YANG,      ## 大羊：2 气，CD6，穿普通防御
	BAO_QI,       ## 爆气：1 气，CD3，先把盾补满再结算
	HUI_FU,       ## 回复：0 气，CD8，+1 血
	ZHONG_JI,     ## 终极技：5 气，CD5，命中 2 血
	QUAN_JIANG,   ## 劝降（隐藏）：满气满血 + 对方仅剩 1 血 → 直接赢本小局
}

enum Phase { OPENING, SELECTING, CLAP1, CLAP2, LOCKED, RESOLVING, PRESENTING, GAME_OVER }

const MAX_HP := 4
const MAX_SHIELD := 3
const MAX_QI := 10
const MAX_ROUND := 40
const OPENING_ROUND := 1
## 先到 12 分获胜（每赢一小局 +1 分）
const WIN_SCORE := 12
const BAO_MAX := 3

## 技能条顺序（可出招的技能；劝降为隐藏自动技，不入本列）
const SKILLS := [
	Action.ZAN, Action.BAO1, Action.BAO2, Action.BAO3, Action.FANG,
	Action.STRONG_FANG, Action.XIAO_YANG, Action.JI_QI, Action.XI_SHOU,
	Action.DA_YANG, Action.BAO_QI, Action.HUI_FU, Action.ZHONG_JI,
]

# 结算结果（供 UI/音效/会话层消费，规则层不播表现）
class RoundResult:
	extends RefCounted
	var actions: Array = []               # [Action, Action] 我、对手
	var hp_delta: Array = [0, 0]          # 负数为扣血
	var qi_delta: Array = [0, 0]
	var shield_delta: Array = [0, 0]
	var hit: Array = [false, false]       # 我是否被打中 / 对手是否被打中
	var blocked: Array = [false, false]   # 我是否成功格挡 / 对手
	var sealed: Array = [false, false]    # 本轮是否给该方上了封盾（下一回合生效）
	var quan_jiang: int = -1              # 劝降获胜方（-1=未触发）
	var opening: bool = false
	var text: String = ""


static func action_name(a: int) -> String:
	match a:
		Action.ZAN: return "攒气"
		Action.BAO1: return "包子×1"
		Action.BAO2: return "包子×2"
		Action.BAO3: return "包子×3"
		Action.FANG: return "防御"
		Action.STRONG_FANG: return "加强防御"
		Action.XIAO_YANG: return "小羊"
		Action.JI_QI: return "集气"
		Action.XI_SHOU: return "吸收"
		Action.DA_YANG: return "大羊"
		Action.BAO_QI: return "爆气"
		Action.HUI_FU: return "回复"
		Action.ZHONG_JI: return "终极技"
		Action.QUAN_JIANG: return "劝降"
	return "?"


## 耗气
static func qi_cost(a: int) -> int:
	match a:
		Action.BAO1: return 1
		Action.BAO2: return 2
		Action.BAO3: return 3
		Action.STRONG_FANG: return 1
		Action.XIAO_YANG: return 1
		Action.XI_SHOU: return 1
		Action.DA_YANG: return 2
		Action.BAO_QI: return 1
		Action.ZHONG_JI: return 5
	return 0


## CD（使用后 T+CD+1 回合可再用；开局即计时，CD3 → 第 4 回合首次可用）
static func cooldown_of(a: int) -> int:
	match a:
		Action.STRONG_FANG: return 1
		Action.XIAO_YANG: return 3
		Action.JI_QI: return 3
		Action.XI_SHOU: return 3
		Action.DA_YANG: return 6
		Action.BAO_QI: return 3
		Action.HUI_FU: return 8
		Action.ZHONG_JI: return 5
	return 0


## 解锁分数（按自己分数；0 = 始终可用）
static func unlock_score(a: int) -> int:
	match a:
		Action.STRONG_FANG: return 1
		Action.XIAO_YANG: return 2
		Action.JI_QI: return 3
		Action.XI_SHOU: return 4
		Action.DA_YANG: return 5
		Action.BAO_QI: return 6
		Action.HUI_FU: return 7
		Action.ZHONG_JI: return 8
	return 0


## 包子连击数（非包子返回 0）
static func bao_count(a: int) -> int:
	match a:
		Action.BAO1: return 1
		Action.BAO2: return 2
		Action.BAO3: return 3
	return 0


static func is_bao(a: int) -> bool:
	return bao_count(a) > 0


## 攻击动作（包子 / 小羊 / 大羊 / 终极技）
static func is_attack(a: int) -> bool:
	return is_bao(a) or a == Action.XIAO_YANG or a == Action.DA_YANG or a == Action.ZHONG_JI


## 破防技（小羊 / 大羊）
static func is_break(a: int) -> bool:
	return a == Action.XIAO_YANG or a == Action.DA_YANG


## 防御类（普通防御 / 加强防御）
static func is_defense(a: int) -> bool:
	return a == Action.FANG or a == Action.STRONG_FANG


## 资源增益类（攒气 / 集气 / 回复 / 爆气）—— 可被吸收偷
static func is_gain(a: int) -> bool:
	return a == Action.ZAN or a == Action.JI_QI or a == Action.HUI_FU or a == Action.BAO_QI


## 封盾会被禁的技能（普通防御 / 爆气）
static func is_sealable(a: int) -> bool:
	return a == Action.FANG or a == Action.BAO_QI


static func clamp_i(v: int, lo: int, hi: int) -> int:
	return int(clamp(v, lo, hi))

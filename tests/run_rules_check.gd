## run_rules_check.gd
## Godot 无头规则层自检 —— v2 结算镜像。
## 权威：docs/rules/game-rules-v2.md §1–§9（逐条裁决）。
## 与 tests/test_rules_v2.py 是「同一套断言、两份独立实现」：
##   Python 侧不 import / 不调用 Godot，本文件直接跑 GameRules / BattleState / GameResolve。
## 改 scripts/rules/**.gd 的结算语义必须同步改 Python 侧（AGENTS 硬约束 2）。
##
## 历史坑：旧版本文件只有 14 条断言（旧 v1 数值）——删掉 clamp_i / _check_winner 仍 ALL PASS。
## 现在按 §3 矩阵逐类覆盖（包子 1/2/3 连 vs 全技能、破防技互撞、吸收碰撞、劝降、
## CD 计时、封盾、clamp/封顶、终局判定、can_use_action 合法性），并保留「能失败」原则。
## 双模式：classic 预设（血1/单包/3 动作/无劝降/无保底/一局定胜负）+ 精通（旁路解锁分，CD 照旧）。
extends SceneTree

const ZAN := GameRules.Action.ZAN
const BAO1 := GameRules.Action.BAO1
const BAO2 := GameRules.Action.BAO2
const BAO3 := GameRules.Action.BAO3
const FANG := GameRules.Action.FANG
const STRONG_FANG := GameRules.Action.STRONG_FANG
const XIAO_YANG := GameRules.Action.XIAO_YANG
const JI_QI := GameRules.Action.JI_QI
const XI_SHOU := GameRules.Action.XI_SHOU
const DA_YANG := GameRules.Action.DA_YANG
const BAO_QI := GameRules.Action.BAO_QI
const HUI_FU := GameRules.Action.HUI_FU
const ZHONG_JI := GameRules.Action.ZHONG_JI
const QUAN_JIANG := GameRules.Action.QUAN_JIANG

var _failed: Array = []


func _init() -> void:
	var ok := true
	var s: BattleState
	var r: GameRules.RoundResult

	# ── ① 开局亮相 ────────────────────────────────────────────────────
	s = BattleState.new()
	r = GameResolve.resolve_opening(s)
	ok = _exp(ok, "[开局] 亮相双方攒气：气[1,1]、盾 3+1 封顶 3、血不动",
		r.opening and r.actions == [ZAN, ZAN] and _chk(s, [4, 4], [1, 1], [3, 3]))

	# ── ② §3.2 包子 vs 包子 ──────────────────────────────────────────
	s = _mk([4, 4], [5, 5], [3, 3])
	GameResolve.resolve_turn(s, BAO1, BAO1)
	ok = _exp(ok, "[矩阵·包子vs包子] 1连 vs 1连：一对一抵消",
		_chk(s, [4, 4], [4, 4], [3, 3]))

	s = _mk([4, 4], [5, 5], [3, 3])
	GameResolve.resolve_turn(s, BAO2, BAO1)
	ok = _exp(ok, "[矩阵·包子vs包子] 2连 vs 1连：剩余 1 包 = 2 盾伤",
		_chk(s, [4, 4], [3, 4], [3, 1]))

	s = _mk([4, 4], [5, 5], [3, 3])
	GameResolve.resolve_turn(s, BAO3, BAO2)
	ok = _exp(ok, "[矩阵·包子vs包子] 3连 vs 2连：剩余 1 包 = 2 盾伤",
		_chk(s, [4, 4], [2, 3], [3, 1]))

	s = _mk([4, 4], [5, 5], [3, 3])
	GameResolve.resolve_turn(s, BAO3, BAO1)
	ok = _exp(ok, "[矩阵·包子vs包子] 3连 vs 1连：剩余 2 包 = 4 盾伤 > 盾 3 → 盾清 0、掉 1 血",
		_chk(s, [4, 3], [2, 4], [3, 0]))

	# ── ③ §3.2 包子 vs 普通防御 ──────────────────────────────────────
	s = _mk([4, 4], [5, 5], [3, 3])
	r = GameResolve.resolve_turn(s, BAO1, FANG)
	ok = _exp(ok, "[矩阵·包子vs防御] 1连：被挡（防御耗 1 盾、不再额外扣盾）",
		_chk(s, [4, 4], [4, 5], [3, 2]) and bool(r.blocked[1]))

	s = _mk([4, 4], [5, 5], [3, 3])
	GameResolve.resolve_turn(s, BAO2, FANG)
	ok = _exp(ok, "[矩阵·包子vs防御] 2连：被挡",
		_chk(s, [4, 4], [3, 5], [3, 2]))

	s = _mk([4, 4], [5, 5], [3, 3])
	GameResolve.resolve_turn(s, BAO3, FANG)
	ok = _exp(ok, "[矩阵·包子vs防御] 3连：破防 → 掉 1 血、盾不动（只耗防御的 1）",
		_chk(s, [4, 3], [2, 5], [3, 2]))

	# ── ④ §3.2 包子 vs 加强防御 ──────────────────────────────────────
	s = _mk([4, 4], [5, 5], [3, 3])
	GameResolve.resolve_turn(s, BAO1, STRONG_FANG)
	ok = _exp(ok, "[矩阵·包子vs加强防御] 1连：被挡、不耗盾",
		_chk(s, [4, 4], [4, 4], [3, 3]))

	s = _mk([4, 4], [5, 5], [3, 3])
	GameResolve.resolve_turn(s, BAO2, STRONG_FANG)
	ok = _exp(ok, "[矩阵·包子vs加强防御] 2连：被挡",
		_chk(s, [4, 4], [3, 4], [3, 3]))

	s = _mk([4, 4], [5, 5], [3, 3])
	GameResolve.resolve_turn(s, BAO3, STRONG_FANG)
	ok = _exp(ok, "[矩阵·包子vs加强防御] 3连：被挡（不破防）",
		_chk(s, [4, 4], [2, 4], [3, 3]))

	# ── ⑤ §3.2 包子 vs 爆气 ─────────────────────────────────────────
	s = _mk([4, 4], [5, 5], [3, 3])
	r = GameResolve.resolve_turn(s, BAO1, BAO_QI)
	ok = _exp(ok, "[矩阵·包子vs爆气] 1连：被挡（只挡 1 包），爆气先补满盾",
		_chk(s, [4, 4], [4, 4], [3, 3]) and bool(r.blocked[1]))

	s = _mk([4, 4], [5, 5], [3, 3])
	GameResolve.resolve_turn(s, BAO2, BAO_QI)
	ok = _exp(ok, "[矩阵·包子vs爆气] 2连：挡 1 剩 1 → 2 盾伤",
		_chk(s, [4, 4], [3, 4], [3, 1]))

	s = _mk([4, 4], [5, 5], [3, 0])
	GameResolve.resolve_turn(s, BAO3, BAO_QI)
	ok = _exp(ok, "[矩阵·包子vs爆气] 3连（爆气方 0 盾）：补满 3 再挡 1，剩 2 包 4 盾伤打穿 → 盾清 0、掉 1 血",
		_chk(s, [4, 3], [2, 4], [3, 0]))

	# ── ⑥ §3.2 包子 vs 小羊 ─────────────────────────────────────────
	s = _mk([4, 4], [5, 5], [3, 3])
	r = GameResolve.resolve_turn(s, BAO1, XIAO_YANG)
	ok = _exp(ok, "[矩阵·包子vs小羊] 1连：包子方耗 1 盾挡下小羊",
		_chk(s, [4, 4], [4, 4], [2, 3]) and bool(r.blocked[0]))

	s = _mk([4, 4], [5, 5], [0, 3])
	GameResolve.resolve_turn(s, BAO1, XIAO_YANG)
	ok = _exp(ok, "[矩阵·包子vs小羊] 1连（包子方 0 盾）：挡不住 → 包子方掉 1 血",
		_chk(s, [3, 4], [4, 4], [0, 3]))

	s = _mk([4, 4], [5, 5], [3, 3])
	GameResolve.resolve_turn(s, BAO2, XIAO_YANG)
	ok = _exp(ok, "[矩阵·包子vs小羊] 2连：挡下且不掉盾",
		_chk(s, [4, 4], [3, 4], [3, 3]))

	s = _mk([4, 4], [5, 5], [3, 3])
	GameResolve.resolve_turn(s, BAO3, XIAO_YANG)
	ok = _exp(ok, "[矩阵·包子vs小羊] 3连：3 连包克制小羊 → 小羊方掉 1 血，包子方无事",
		_chk(s, [4, 3], [2, 4], [3, 3]))

	# ── ⑥b 反向座位：包子在 1 号位（镜像 resolve.gd 的 is_bao(b) 分支）──────
	s = _mk([4, 4], [5, 5], [3, 3])
	GameResolve.resolve_turn(s, XIAO_YANG, BAO1)
	ok = _exp(ok, "[矩阵·反向座位] 小羊(0) vs 1连包(1)：包子方耗 1 盾挡下",
		_chk(s, [4, 4], [4, 4], [3, 2]))

	s = _mk([4, 4], [5, 5], [3, 0])
	GameResolve.resolve_turn(s, XIAO_YANG, BAO1)
	ok = _exp(ok, "[矩阵·反向座位] 小羊 vs 1连包（包子方 0 盾）：挡不住 → 包子方掉 1 血",
		_chk(s, [4, 3], [4, 4], [3, 0]))

	s = _mk([4, 4], [5, 5], [3, 3])
	GameResolve.resolve_turn(s, XIAO_YANG, BAO2)
	ok = _exp(ok, "[矩阵·反向座位] 小羊 vs 2连包：挡下且不掉盾",
		_chk(s, [4, 4], [4, 3], [3, 3]))

	s = _mk([4, 4], [5, 5], [3, 3])
	GameResolve.resolve_turn(s, XIAO_YANG, BAO3)
	ok = _exp(ok, "[矩阵·反向座位] 小羊 vs 3连包：3 连包克制小羊 → 小羊方掉 1 血",
		_chk(s, [3, 4], [4, 2], [3, 3]))

	s = _mk([4, 4], [5, 5], [3, 3])
	GameResolve.resolve_turn(s, DA_YANG, BAO1)
	ok = _exp(ok, "[矩阵·反向座位] 大羊 vs 1连包：挡不住 → 包子方掉 1 血",
		_chk(s, [4, 3], [3, 4], [3, 3]))

	s = _mk([4, 4], [5, 5], [3, 3])
	GameResolve.resolve_turn(s, DA_YANG, BAO3)
	ok = _exp(ok, "[矩阵·反向座位] 大羊 vs 3连包：完全挡下（不掉盾不掉血）",
		_chk(s, [4, 4], [3, 2], [3, 3]))

	s = _mk([4, 4], [5, 5], [3, 3])
	GameResolve.resolve_turn(s, ZHONG_JI, BAO1)
	ok = _exp(ok, "[矩阵·反向座位] 终极技 vs 1连包：挡不住 → 包子方掉 2 血",
		_chk(s, [4, 2], [0, 4], [3, 3]))

	# ── ⑦ §3.2 包子 vs 大羊 ─────────────────────────────────────────
	s = _mk([4, 4], [5, 5], [3, 3])
	GameResolve.resolve_turn(s, BAO1, DA_YANG)
	ok = _exp(ok, "[矩阵·包子vs大羊] 1连：挡不住 → 包子方掉 1 血",
		_chk(s, [3, 4], [4, 3], [3, 3]))

	s = _mk([4, 4], [5, 5], [3, 3])
	r = GameResolve.resolve_turn(s, BAO2, DA_YANG)
	ok = _exp(ok, "[矩阵·包子vs大羊] 2连：挡下并耗 1 盾",
		_chk(s, [4, 4], [3, 3], [2, 3]) and bool(r.blocked[0]))

	s = _mk([4, 4], [5, 5], [0, 3])
	GameResolve.resolve_turn(s, BAO2, DA_YANG)
	ok = _exp(ok, "[矩阵·包子vs大羊] 2连（包子方 0 盾）：挡不住 → 掉 1 血",
		_chk(s, [3, 4], [3, 3], [0, 3]))

	s = _mk([4, 4], [5, 5], [3, 3])
	r = GameResolve.resolve_turn(s, BAO3, DA_YANG)
	ok = _exp(ok, "[矩阵·包子vs大羊] 3连：完全挡下（不掉盾不掉血）",
		_chk(s, [4, 4], [2, 3], [3, 3]) and bool(r.blocked[0]))

	# ── ⑧ §3.2 包子 vs 终极技 ───────────────────────────────────────
	s = _mk([4, 4], [5, 5], [3, 3])
	GameResolve.resolve_turn(s, BAO1, ZHONG_JI)
	ok = _exp(ok, "[矩阵·包子vs终极技] 1连：挡不住 → 包子方掉 2 血",
		_chk(s, [2, 4], [4, 0], [3, 3]))

	s = _mk([4, 4], [5, 5], [3, 3])
	GameResolve.resolve_turn(s, BAO2, ZHONG_JI)
	ok = _exp(ok, "[矩阵·包子vs终极技] 2连：挡不住 → 掉 2 血",
		_chk(s, [2, 4], [3, 0], [3, 3]))

	s = _mk([4, 4], [5, 5], [3, 3])
	r = GameResolve.resolve_turn(s, BAO3, ZHONG_JI)
	ok = _exp(ok, "[矩阵·包子vs终极技] 3连：挡住（包子被吞、终极无效）",
		_chk(s, [4, 4], [2, 0], [3, 3]) and bool(r.blocked[0]))

	# ── ⑨ §3.1 裸防 ─────────────────────────────────────────────────
	s = _mk([4, 4], [5, 5], [3, 3])
	GameResolve.resolve_turn(s, BAO1, ZAN)
	ok = _exp(ok, "[矩阵·裸防] 1连包 vs 攒气：对方掉 1 血、攒气增益照给",
		_chk(s, [4, 3], [4, 6], [3, 3]))

	s = _mk([4, 4], [5, 5], [3, 3])
	GameResolve.resolve_turn(s, BAO3, JI_QI)
	ok = _exp(ok, "[矩阵·裸防] 3连包 vs 集气：仍只掉 1 血（集气 +3 气照给）",
		_chk(s, [4, 3], [2, 8], [3, 3]))

	s = _mk([4, 4], [5, 5], [3, 3])
	GameResolve.resolve_turn(s, BAO2, HUI_FU)
	ok = _exp(ok, "[矩阵·裸防] 2连包 vs 回复（满血）：掉 1 血，回复溢出作废",
		_chk(s, [4, 3], [3, 5], [3, 3]))

	# ── ⑩ §3.3 破防技互撞 ───────────────────────────────────────────
	s = _mk([4, 4], [5, 5], [3, 3])
	GameResolve.resolve_turn(s, XIAO_YANG, XIAO_YANG)
	ok = _exp(ok, "[矩阵·破防技互撞] 小羊 vs 小羊：互相抵消、双方无效果",
		_chk(s, [4, 4], [4, 4], [3, 3]))

	s = _mk([4, 4], [5, 5], [3, 3])
	GameResolve.resolve_turn(s, DA_YANG, DA_YANG)
	ok = _exp(ok, "[矩阵·破防技互撞] 大羊 vs 大羊：互相抵消",
		_chk(s, [4, 4], [3, 3], [3, 3]))

	s = _mk([4, 4], [5, 5], [3, 3])
	GameResolve.resolve_turn(s, XIAO_YANG, DA_YANG)
	ok = _exp(ok, "[矩阵·破防技互撞] 小羊 vs 大羊：大羊赢 → 小羊方掉 1 血",
		_chk(s, [3, 4], [4, 3], [3, 3]))

	s = _mk([4, 4], [5, 5], [3, 3])
	GameResolve.resolve_turn(s, XIAO_YANG, ZHONG_JI)
	ok = _exp(ok, "[矩阵·破防技互撞] 小羊 vs 终极技：终极技赢 → 小羊方掉 2 血",
		_chk(s, [2, 4], [4, 0], [3, 3]))

	s = _mk([4, 4], [5, 5], [3, 3])
	GameResolve.resolve_turn(s, DA_YANG, ZHONG_JI)
	ok = _exp(ok, "[矩阵·破防技互撞] 大羊 vs 终极技：终极技赢 → 大羊方掉 2 血",
		_chk(s, [2, 4], [3, 0], [3, 3]))

	s = _mk([4, 4], [5, 5], [3, 3])
	GameResolve.resolve_turn(s, ZHONG_JI, ZHONG_JI)
	ok = _exp(ok, "[矩阵·破防技互撞] 终极技 vs 终极技：双方各掉 2 血、未死则未分",
		_chk(s, [2, 2], [0, 0], [3, 3]) and s.winner == -1)

	# ── ⑪ §3.4 防御类对撞 ───────────────────────────────────────────
	s = _mk([4, 4], [5, 5], [3, 3])
	r = GameResolve.resolve_turn(s, XIAO_YANG, FANG)
	ok = _exp(ok, "[矩阵·防御类对撞] 小羊 vs 普通防御：破防 → 封盾 1 回合、不掉血",
		_chk(s, [4, 4], [4, 5], [3, 2])
		and s.sealed_round == [-1, 3] and bool(r.sealed[1]))

	s = _mk([4, 4], [5, 5], [3, 3])
	GameResolve.resolve_turn(s, DA_YANG, FANG)
	ok = _exp(ok, "[矩阵·防御类对撞] 大羊 vs 普通防御：穿防 → 掉 1 血",
		_chk(s, [4, 3], [3, 5], [3, 2]))

	s = _mk([4, 4], [5, 5], [3, 3])
	r = GameResolve.resolve_turn(s, XIAO_YANG, STRONG_FANG)
	ok = _exp(ok, "[矩阵·防御类对撞] 小羊 vs 加强防御：被挡（不耗盾不掉血）",
		_chk(s, [4, 4], [4, 4], [3, 3]) and bool(r.blocked[1]))

	s = _mk([4, 4], [5, 5], [3, 3])
	r = GameResolve.resolve_turn(s, DA_YANG, STRONG_FANG)
	ok = _exp(ok, "[矩阵·防御类对撞] 大羊 vs 加强防御：被挡",
		_chk(s, [4, 4], [3, 4], [3, 3]) and bool(r.blocked[1]))

	s = _mk([4, 4], [5, 5], [3, 3])
	GameResolve.resolve_turn(s, ZHONG_JI, FANG)
	ok = _exp(ok, "[矩阵·防御类对撞] 终极技 vs 普通防御：无视防御 → 掉 2 血",
		_chk(s, [4, 2], [0, 5], [3, 2]))

	s = _mk([4, 4], [5, 5], [3, 3])
	r = GameResolve.resolve_turn(s, ZHONG_JI, STRONG_FANG)
	ok = _exp(ok, "[矩阵·防御类对撞] 终极技 vs 加强防御：被挡但掉光所有盾",
		_chk(s, [4, 4], [0, 4], [3, 0]) and bool(r.blocked[1]))

	s = _mk([4, 4], [5, 5], [3, 0])
	GameResolve.resolve_turn(s, XIAO_YANG, BAO_QI)
	ok = _exp(ok, "[矩阵·防御类对撞] 小羊 vs 爆气（0 盾）：补满盾照常命中 1 血",
		_chk(s, [4, 3], [4, 4], [3, 3]))

	s = _mk([4, 4], [5, 5], [3, 1])
	GameResolve.resolve_turn(s, DA_YANG, BAO_QI)
	ok = _exp(ok, "[矩阵·防御类对撞] 大羊 vs 爆气：补满盾照常命中 1 血",
		_chk(s, [4, 3], [3, 4], [3, 3]))

	s = _mk([4, 4], [5, 5], [3, 0])
	GameResolve.resolve_turn(s, ZHONG_JI, BAO_QI)
	ok = _exp(ok, "[矩阵·防御类对撞] 终极技 vs 爆气：补满盾照常命中 2 血",
		_chk(s, [4, 2], [0, 4], [3, 3]))

	# ── ⑫ §3.5 吸收 ─────────────────────────────────────────────────
	s = _mk([4, 4], [4, 4], [1, 3])
	GameResolve.resolve_turn(s, XI_SHOU, ZAN)
	ok = _exp(ok, "[矩阵·吸收] vs 攒气：偷 +1 气 +1 盾、对方白费（对方气不加）",
		_chk(s, [4, 4], [4, 4], [2, 3]))

	s = _mk([4, 4], [3, 3], [3, 3])
	GameResolve.resolve_turn(s, XI_SHOU, JI_QI)
	ok = _exp(ok, "[矩阵·吸收] vs 集气：偷 +3 气、对方无收益",
		_chk(s, [4, 4], [5, 3], [3, 3]))

	s = _mk([2, 3], [3, 3], [3, 3])
	GameResolve.resolve_turn(s, XI_SHOU, HUI_FU)
	ok = _exp(ok, "[矩阵·吸收] vs 回复：偷 +1 血、对方无收益",
		_chk(s, [3, 3], [2, 3], [3, 3]))

	s = _mk([4, 4], [3, 3], [0, 3])
	GameResolve.resolve_turn(s, XI_SHOU, BAO_QI)
	ok = _exp(ok, "[矩阵·吸收] vs 爆气：偷「补满盾」、对方无收益",
		_chk(s, [4, 4], [2, 2], [3, 3]))

	s = _mk([4, 4], [3, 3], [3, 3])
	GameResolve.resolve_turn(s, XI_SHOU, BAO1)
	ok = _exp(ok, "[矩阵·吸收] vs 包子：吸收方掉 1 血、1 气白花",
		_chk(s, [3, 4], [2, 2], [3, 3]))

	s = _mk([4, 4], [3, 3], [3, 3])
	GameResolve.resolve_turn(s, XI_SHOU, XIAO_YANG)
	ok = _exp(ok, "[矩阵·吸收] vs 小羊：吸收方掉 1 血且不被封盾",
		_chk(s, [3, 4], [2, 2], [3, 3]) and s.sealed_round == [-1, -1])

	s = _mk([4, 4], [3, 3], [3, 3])
	GameResolve.resolve_turn(s, XI_SHOU, DA_YANG)
	ok = _exp(ok, "[矩阵·吸收] vs 大羊：吸收方掉 1 血",
		_chk(s, [3, 4], [2, 1], [3, 3]))

	s = _mk([4, 4], [3, 6], [3, 3])
	GameResolve.resolve_turn(s, XI_SHOU, ZHONG_JI)
	ok = _exp(ok, "[矩阵·吸收] vs 终极技：吸收方只掉 1 血（非 2）",
		_chk(s, [3, 4], [2, 1], [3, 3]))

	s = _mk([4, 4], [3, 3], [3, 3])
	GameResolve.resolve_turn(s, XI_SHOU, FANG)
	ok = _exp(ok, "[矩阵·吸收] vs 防御：无事发生、1 气白花（防御照耗 1 盾）",
		_chk(s, [4, 4], [2, 3], [3, 2]))

	s = _mk([4, 4], [3, 3], [3, 3])
	GameResolve.resolve_turn(s, XI_SHOU, STRONG_FANG)
	ok = _exp(ok, "[矩阵·吸收] vs 加强防御：无事发生、双方各耗气",
		_chk(s, [4, 4], [2, 2], [3, 3]))

	s = _mk([4, 4], [3, 3], [3, 3])
	GameResolve.resolve_turn(s, XI_SHOU, XI_SHOU)
	ok = _exp(ok, "[矩阵·吸收] vs 吸收：双方无事、各花 1 气、不递归",
		_chk(s, [4, 4], [2, 2], [3, 3]))

	# ── ⑬ 隐藏技·劝降 ───────────────────────────────────────────────
	s = _mk([4, 1], [10, 0], [3, 3])
	r = GameResolve.resolve_turn(s, ZHONG_JI, ZAN)
	ok = _exp(ok, "[劝降] 满气满血 + 对方 1 血：直接判胜（不扣资源、不进 CD、不占动作）",
		s.winner == 0 and int(r.quan_jiang) == 0
		and _chk(s, [4, 1], [10, 0], [3, 3])
		and (s.cooldowns[0] as Dictionary).is_empty())

	s = _mk([4, 1], [9, 0], [3, 3])
	GameResolve.resolve_turn(s, ZAN, ZAN)
	ok = _exp(ok, "[劝降] 气不满（9）：不触发", s.winner == -1)

	s = _mk([3, 1], [10, 0], [3, 3])
	GameResolve.resolve_turn(s, ZAN, ZAN)
	ok = _exp(ok, "[劝降] 自己血不满（3）：不触发", s.winner == -1)

	s = _mk([4, 2], [10, 0], [3, 3])
	GameResolve.resolve_turn(s, ZAN, ZAN)
	ok = _exp(ok, "[劝降] 对方血 >1（2）：不触发", s.winner == -1)

	s = _mk([4, 1], [10, 0], [1, 3])
	r = GameResolve.resolve_turn(s, XI_SHOU, BAO_QI)
	ok = _exp(ok, "[劝降] 优先于吸收结算（劝降短路：气/盾均未被改动）",
		s.winner == 0 and _chk(s, [4, 1], [10, 0], [1, 3]))

	# ── ⑭ CD 计时 ───────────────────────────────────────────────────
	s = _mk([4, 4], [10, 10], [3, 3], 8)
	s.score = [8, 0]
	s.cooldowns = [{XIAO_YANG: 5}, {}]
	ok = _exp(ok, "[CD] T=5 用小羊（CD3）→ 第 8 回合仍不可用（T+CD）",
		not s.can_use_action(0, XIAO_YANG))
	s.round = 9
	ok = _exp(ok, "[CD] T=5 用小羊（CD3）→ 第 9 回合可再用（T+CD+1）",
		s.can_use_action(0, XIAO_YANG))

	s = _mk([4, 4], [10, 10], [3, 3], 3)
	s.score = [8, 0]
	ok = _exp(ok, "[CD] 开局即计时：CD3 第 3 回合不可用",
		not s.can_use_action(0, XIAO_YANG) and not s.can_use_action(0, JI_QI))
	s.round = 4
	ok = _exp(ok, "[CD] 开局即计时：CD3 第 4 回合首次可用",
		s.can_use_action(0, XIAO_YANG) and s.can_use_action(0, JI_QI))

	s = _mk([4, 4], [10, 10], [3, 3], 2)
	s.score = [8, 0]
	ok = _exp(ok, "[CD] 开局即计时：CD1（加强防御）第 2 回合即可用",
		s.can_use_action(0, STRONG_FANG))

	s = _mk([4, 4], [10, 10], [3, 3], 6)
	s.score = [8, 0]
	ok = _exp(ok, "[CD] 开局即计时：CD6（大羊）第 6 回合不可用",
		not s.can_use_action(0, DA_YANG))
	s.round = 7
	ok = _exp(ok, "[CD] 开局即计时：CD6（大羊）第 7 回合首次可用",
		s.can_use_action(0, DA_YANG))

	s = _mk([4, 4], [10, 10], [3, 3], 5)
	s.score = [8, 0]
	ok = _exp(ok, "[CD] 开局即计时：CD5（终极技）第 5 回合不可用",
		not s.can_use_action(0, ZHONG_JI))
	s.round = 6
	ok = _exp(ok, "[CD] 开局即计时：CD5（终极技）第 6 回合首次可用",
		s.can_use_action(0, ZHONG_JI))

	s = _mk([4, 4], [10, 10], [3, 3], 8)
	s.score = [8, 0]
	ok = _exp(ok, "[CD] 开局即计时：CD8（回复）第 8 回合不可用",
		not s.can_use_action(0, HUI_FU))
	s.round = 9
	ok = _exp(ok, "[CD] 开局即计时：CD8（回复）第 9 回合首次可用",
		s.can_use_action(0, HUI_FU))

	s = _mk([4, 4], [5, 5], [3, 3], 5)
	s.score = [8, 8]
	GameResolve.resolve_turn(s, XIAO_YANG, XIAO_YANG)
	ok = _exp(ok, "[CD] 顶招也进 CD：小羊 vs 小羊互顶 → 双方均记录第 5 回合",
		int((s.cooldowns[0] as Dictionary).get(XIAO_YANG, -1)) == 5
		and int((s.cooldowns[1] as Dictionary).get(XIAO_YANG, -1)) == 5)
	s.round = 8
	ok = _exp(ok, "[CD] 顶招第 8 回合仍不可用（T+CD），第 9 回合才可用",
		not s.can_use_action(0, XIAO_YANG) and not s.can_use_action(1, XIAO_YANG))
	s.round = 9
	ok = _exp(ok, "[CD] 顶招第 9 回合可用（T+CD+1）",
		s.can_use_action(0, XIAO_YANG) and s.can_use_action(1, XIAO_YANG))

	s = _mk([4, 4], [5, 5], [3, 3], 5)
	s.score = [8, 8]
	GameResolve.resolve_turn(s, XIAO_YANG, XIAO_YANG)
	ok = _exp(ok, "[CD] 顶招资源照扣：互顶双方各废 1 气",
		s.qi == [4, 4])

	# ── ⑮ §3.6 封盾 ─────────────────────────────────────────────────
	s = _mk([4, 4], [5, 5], [3, 3], 2)
	s.score = [8, 0]
	GameResolve.resolve_turn(s, XIAO_YANG, FANG)
	ok = _exp(ok, "[封盾] 写入 sealed_round = 当回合+1，当回合 is_sealed 仍为 False",
		int(s.sealed_round[1]) == 3 and not s.is_sealed(1))
	s.round = 3
	ok = _exp(ok, "[封盾] 次回合 is_sealed 生效",
		s.is_sealed(1))

	s = _mk([4, 4], [10, 10], [3, 3], 3)
	s.score = [8, 8]
	s.sealed_round = [3, -1]
	ok = _exp(ok, "[封盾] 被封方次回合禁普通防御 / 爆气",
		not s.can_use_action(0, FANG) and not s.can_use_action(0, BAO_QI))
	ok = _exp(ok, "[封盾] 封盾期间加强防御仍可用（封的是盾不是气）",
		s.can_use_action(0, STRONG_FANG))

	s = _mk([4, 4], [10, 10], [3, 3], 4)
	s.score = [8, 8]
	s.sealed_round = [3, -1]
	ok = _exp(ok, "[封盾] 到期自动失效（round+1 后恢复正常）",
		s.can_use_action(0, FANG) and s.can_use_action(0, BAO_QI))

	s = _mk([4, 4], [5, 5], [3, 3], 3)
	s.score = [8, 0]
	s.sealed_round = [-1, 3]
	GameResolve.resolve_turn(s, ZHONG_JI, STRONG_FANG)
	ok = _exp(ok, "[封盾] 掉光盾不解除也不延长封盾（终极技 vs 加强防御）",
		s.shield == [3, 0] and s.sealed_round == [-1, 3])

	s = _mk([4, 4], [5, 5], [3, 3], 3)
	s.score = [0, 8]
	s.sealed_round = [3, -1]
	GameResolve.resolve_turn(s, ZAN, DA_YANG)
	ok = _exp(ok, "[封盾] 封盾期间被大羊命中：照常掉 1 血（封盾不免疫伤害）",
		_chk(s, [3, 4], [6, 3], [3, 3]) and s.sealed_round == [3, -1])

	# ── ⑯ 强断言（删掉实现就变红）────────────────────────────────────
	s = _mk([4, 4], [9, 9], [3, 3])
	s.score = [3, 3]
	GameResolve.resolve_turn(s, JI_QI, JI_QI)
	ok = _exp(ok, "[强断言] 气封顶 10（9 + 3 不溢出）",
		s.qi == [10, 10] and s.shield == [3, 3])

	s = _mk([4, 4], [4, 5], [3, 3])
	GameResolve.resolve_turn(s, ZAN, ZAN)
	ok = _exp(ok, "[强断言] 盾封顶 3（攒气 +1 不溢出）",
		s.qi == [5, 6] and s.shield == [3, 3])

	s = _mk([3, 3], [5, 5], [3, 3])
	s.score = [7, 7]
	GameResolve.resolve_turn(s, HUI_FU, HUI_FU)
	ok = _exp(ok, "[强断言] 血封顶 4（3 + 1 = 4）", s.hp == [4, 4])

	s = _mk([4, 4], [5, 5], [3, 3])
	GameResolve.resolve_turn(s, HUI_FU, BAO1)
	ok = _exp(ok, "[强断言] 回复溢出作废：满血出回复再被打 1 血 → 仍掉 1 血（不结转免伤）",
		_chk(s, [3, 4], [5, 4], [3, 3]))

	s = _mk([3, 4], [5, 5], [3, 3])
	GameResolve.resolve_turn(s, HUI_FU, BAO1)
	ok = _exp(ok, "[强断言] 增益先于伤害结算：3 血出回复再被打 1 → 净 0（仍 3，非 2）",
		_chk(s, [3, 4], [5, 4], [3, 3]))

	s = _mk([4, 1], [5, 5], [3, 3])
	GameResolve.resolve_turn(s, BAO1, ZAN)
	ok = _exp(ok, "[强断言] 对手血归零 → winner=0",
		s.winner == 0 and _chk(s, [4, 0], [4, 6], [3, 3]))

	s = _mk([1, 4], [5, 5], [3, 3])
	GameResolve.resolve_turn(s, ZAN, BAO1)
	ok = _exp(ok, "[强断言] 自己血归零 → winner=1",
		s.winner == 1 and _chk(s, [0, 4], [6, 4], [3, 3]))

	s = _mk([2, 2], [5, 5], [3, 3])
	GameResolve.resolve_turn(s, ZHONG_JI, ZHONG_JI)
	ok = _exp(ok, "[强断言] 双亡（双终极同时命中）→ winner=2 平局",
		s.winner == 2 and _chk(s, [0, 0], [0, 0], [3, 3]))

	s = _mk([4, 3], [5, 5], [3, 3], GameRules.MAX_ROUND)
	GameResolve.resolve_turn(s, ZAN, ZAN)
	ok = _exp(ok, "[强断言] 40 回合血多：我胜", s.winner == 0)

	s = _mk([3, 4], [5, 5], [3, 3], GameRules.MAX_ROUND)
	GameResolve.resolve_turn(s, ZAN, ZAN)
	ok = _exp(ok, "[强断言] 40 回合血少：对手胜", s.winner == 1)

	s = _mk([3, 3], [5, 5], [3, 0], GameRules.MAX_ROUND)
	GameResolve.resolve_turn(s, ZAN, ZAN)
	ok = _exp(ok, "[强断言] 40 回合血同：平局（盾 3 vs 1 不比盾）",
		s.winner == 2 and s.shield == [3, 1])

	s = _mk([4, 4], [5, 5], [3, 3])
	s.pending = [BAO1, ZAN]
	GameResolve.resolve_turn(s, ZAN, ZAN)
	ok = _exp(ok, "[强断言] 结算后 pending 清空（常规路径）",
		int(s.pending[0]) == -1 and int(s.pending[1]) == -1)

	s = _mk([4, 1], [10, 0], [3, 3])
	s.pending = [BAO1, BAO1]
	GameResolve.resolve_turn(s, BAO1, BAO1)
	ok = _exp(ok, "[强断言] 结算后 pending 清空（劝降路径）",
		int(s.pending[0]) == -1 and int(s.pending[1]) == -1 and s.winner == 0)

	var fresh := BattleState.new()
	ok = _exp(ok, "[强断言] can_use_action：回合 1 仅攒气可出",
		fresh.can_use_action(0, ZAN) and fresh.can_use_action(1, ZAN)
		and not fresh.can_use_action(0, BAO1)
		and not fresh.can_use_action(0, FANG)
		and not fresh.can_use_action(1, STRONG_FANG))

	s = _mk([4, 4], [10, 10], [3, 3], 2)
	s.score = [GameRules.WIN_SCORE, GameRules.WIN_SCORE]
	ok = _exp(ok, "[强断言] can_use_action：非法动作值（-1 / 劝降 / 越界）不可用",
		not s.can_use_action(0, -1) and not s.can_use_action(0, QUAN_JIANG)
		and not s.can_use_action(0, 14) and not s.can_use_action(0, 99))

	s = _mk([4, 4], [10, 10], [3, 3], 2)
	s.score = [0, 0]
	ok = _exp(ok, "[强断言] can_use_action：未解锁不可用（0 分仅基础三件套 + 包子）",
		not s.can_use_action(0, STRONG_FANG)
		and s.can_use_action(0, ZAN) and s.can_use_action(0, BAO1)
		and s.can_use_action(0, FANG))

	s = _mk([4, 4], [10, 10], [3, 3], 4)
	s.score = [2, 0]
	ok = _exp(ok, "[强断言] can_use_action：解锁按自己分数（2 分可用小羊；对手 0 分不可）",
		s.can_use_action(0, XIAO_YANG) and not s.can_use_action(1, XIAO_YANG))

	s = _mk([4, 4], [10, 10], [3, 3], 4)
	s.score = [0, 2]
	ok = _exp(ok, "[强断言] can_use_action：解锁只看自己分数（对手 2 分不算我的）",
		not s.can_use_action(0, XIAO_YANG) and s.can_use_action(1, XIAO_YANG))

	s = _mk([4, 4], [0, 0], [3, 3], 2)
	s.score = [GameRules.WIN_SCORE, 0]
	ok = _exp(ok, "[强断言] can_use_action：气不足不可用（0 气禁包子，攒气仍可）",
		not s.can_use_action(0, BAO1) and s.can_use_action(0, ZAN))

	s = _mk([4, 4], [10, 10], [0, 1], 2)
	s.score = [GameRules.WIN_SCORE, 0]
	ok = _exp(ok, "[强断言] can_use_action：盾 0 禁普通防御（盾 1 可）",
		not s.can_use_action(0, FANG) and s.can_use_action(1, FANG))

	s = _mk([4, 4], [10, 10], [3, 3], 9)
	s.score = [GameRules.WIN_SCORE, 0]
	var avail: Array = s.available_actions(0)
	avail.sort()
	var all_skills: Array = GameRules.SKILLS.duplicate()
	all_skills.sort()
	ok = _exp(ok, "[强断言] available_actions：满解锁 + 满气 + 无 CD → 13 个技能全可出",
		avail == all_skills and avail.size() == 13)

	s = _mk([4, 4], [10, 10], [3, 3], 2)
	s.score = [0, 0]
	avail = s.available_actions(0)
	avail.sort()
	ok = _exp(ok, "[强断言] available_actions：0 分回合 2 → 仅 5 个基础动作",
		avail == [ZAN, BAO1, BAO2, BAO3, FANG])

	# ── ⑳ 裸防兜底：盾 0 出防御 = 非法动作，按 §3.1 裸防结算（game-rules-v2.md §2 注）
	s = _mk([4, 4], [5, 5], [0, 3])
	GameResolve.resolve_turn(s, FANG, BAO1)
	ok = _exp(ok, "[裸防兜底] 0 盾出防御 vs 1连包：防御不生效 → 掉 1 血",
		_chk(s, [3, 4], [5, 4], [0, 3]))

	s = _mk([4, 4], [5, 5], [0, 3])
	GameResolve.resolve_turn(s, FANG, XIAO_YANG)
	ok = _exp(ok, "[裸防兜底] 0 盾出防御 vs 小羊：掉 1 血",
		_chk(s, [3, 4], [5, 4], [0, 3]))

	s = _mk([4, 4], [5, 5], [0, 3])
	GameResolve.resolve_turn(s, FANG, ZHONG_JI)
	ok = _exp(ok, "[裸防兜底] 0 盾出防御 vs 终极技：掉 2 血",
		_chk(s, [2, 4], [5, 0], [0, 3]))

	# ── ㉑ 判分 / 终场 / 平局保底（battle_state.gd 判分口径）────────────
	s = _mk([4, 4], [10, 10], [3, 3], 2)
	s.score = [3, 5]
	s.winner = 0
	var info: Dictionary = s.settle_round_after_resolve()
	ok = _exp(ok, "[判分] 胜者 +1 分（3→4），未到 12 不终场",
		info["score"] == [4, 5] and bool(info["scored"]) and bool(info["round_end"])
		and not bool(info["match_over"]) and int(info["match_winner"]) == -1)

	s = _mk([4, 4], [10, 10], [3, 3], 2)
	s.score = [3, 5]
	s.draw_count = 0
	s.winner = 2
	s.settle_round_after_resolve()
	ok = _exp(ok, "[平局保底] 第 1 次平局不得分（draw_count=1）",
		s.score == [3, 5] and s.draw_count == 1)
	s.winner = 2
	s.settle_round_after_resolve()
	ok = _exp(ok, "[平局保底] 第 2 次平局不得分（draw_count=2）",
		s.score == [3, 5] and s.draw_count == 2)
	s.winner = 2
	s.settle_round_after_resolve()
	ok = _exp(ok, "[平局保底] 第 3 次平局双方各 +1（3:5→4:6）",
		s.score == [4, 6] and s.draw_count == 3)

	s = _mk([4, 4], [10, 10], [3, 3], 2)
	s.score = [11, 11]
	s.draw_count = 2
	s.winner = 2
	info = s.settle_round_after_resolve()
	ok = _exp(ok, "[平局保底] 同时到 12 分 → 整场结束且整场判平",
		bool(info["match_over"]) and int(info["match_winner"]) == 2
		and s.score == [12, 12])

	s = _mk([4, 4], [10, 10], [3, 3], 2)
	s.score = [11, 5]
	s.winner = 0
	info = s.settle_round_after_resolve()
	ok = _exp(ok, "[终场] 先到 12 分者胜（match_winner=0）",
		bool(info["match_over"]) and int(info["match_winner"]) == 0 and s.score == [12, 5])

	s = _mk([4, 4], [10, 10], [3, 3], 2)
	s.score = [3, 5]
	s.draw_count = 2
	s.cooldowns = [{GameRules.Action.XIAO_YANG: 4}, {}]
	s.sealed_round = [8, -1]
	s.winner = 0
	s.settle_round_after_resolve()
	s.reset_round_keep_score()
	ok = _exp(ok, "[小局重开] score/draw_count 保留，其余复位",
		s.score == [4, 5] and s.draw_count == 2 and s.round == GameRules.OPENING_ROUND
		and s.hp == [GameRules.MAX_HP, GameRules.MAX_HP] and s.qi == [0, 0] and s.winner == -1
		and s.cooldowns == [{}, {}] and s.sealed_round == [-1, -1]
		and s.phase == GameRules.Phase.SELECTING)

	# ── ㉒ classic 模式预设（docs/rules/game-rules-classic.md）──────────────
	var c: BattleState = BattleState.new("classic")
	ok = _exp(ok, "[经典] 预设：血1/气5/盾3/单包/3 动作/无劝降/无保底/一局定胜负",
		c.mode == "classic" and not c.mastery
		and c.max_hp() == 1 and c.max_qi() == 5 and c.max_shield() == 3 and c.bao_max() == 1
		and c.score_to_win() == 1 and not c.skills_enabled() and not c.quan_jiang_enabled()
		and not c.draw_backstop() and c.draw_replay_max() == 3 and c.round_cap() == 40
		and c.hp == [1, 1] and c.shield == [3, 3])

	ok = _exp(ok, "[经典] 预设剔除死配置 cap_rule（文档 §5 同步删除）",
		not GameRules.preset("classic").has("cap_rule")
		and not GameRules.preset("lesson").has("cap_rule"))

	var c_open: BattleState = BattleState.new("classic")
	r = GameResolve.resolve_opening(c_open)
	ok = _exp(ok, "[经典] 开局亮相：气 +1、盾已满 3 不叠加、血不动",
		r.opening and _chk(c_open, [1, 1], [1, 1], [3, 3]))

	s = _mk_mode("classic", [5, 5], 9)
	s.score = [1, 1]
	avail = s.available_actions(0)
	avail.sort()
	ok = _exp(ok, "[经典] 可用动作仅 攒/包子×1/防御（分数再高也不解锁技能）",
		avail == [ZAN, BAO1, FANG])

	s = _mk_mode("classic", [5, 5])
	GameResolve.resolve_turn(s, BAO1, ZAN)
	ok = _exp(ok, "[经典] 包子打攒气 = 即死（1 血归零 → winner=0；气封顶 5）",
		s.winner == 0 and _chk(s, [1, 0], [4, 5], [3, 3]))

	s = _mk_mode("classic", [3, 3])
	GameResolve.resolve_turn(s, FANG, ZAN)
	ok = _exp(ok, "[经典] 防御 vs 攒气：无事发生（防御只耗 1 盾）",
		_chk(s, [1, 1], [3, 4], [2, 3]))

	s = _mk_mode("classic", [5, 5])
	r = GameResolve.resolve_turn(s, BAO1, FANG)
	ok = _exp(ok, "[经典] 包子 vs 防御：被挡、防御方盾 3→2、不掉血",
		_chk(s, [1, 1], [4, 5], [3, 2]) and bool(r.blocked[1]))

	s = _mk_mode("classic", [5, 5])
	s.shield = [0, 3]
	GameResolve.resolve_turn(s, FANG, BAO1)
	ok = _exp(ok, "[经典] 盾 0 出防御 = 裸防：被打 1 血即负（winner=1）",
		s.winner == 1 and _chk(s, [0, 1], [5, 4], [0, 3]))

	s = _mk_mode("classic", [5, 5])
	r = GameResolve.resolve_turn(s, BAO3, FANG)
	ok = _exp(ok, "[经典] 非法 3 连包按上限收口为单包（不破防、被挡）",
		_chk(s, [1, 1], [2, 5], [3, 2]) and bool(r.blocked[1]))

	s = _mk_mode("classic", [5, 5])
	GameResolve.resolve_turn(s, ZAN, ZAN)
	ok = _exp(ok, "[经典] 气上限 5 / 盾上限 3（5 气再攒不溢出）",
		_chk(s, [1, 1], [5, 5], [3, 3]))

	s = _mk_mode("classic", [5, 0])
	r = GameResolve.resolve_turn(s, ZAN, ZAN)
	ok = _exp(ok, "[经典] 无劝降：满气满血 + 对手 1 血也不触发",
		s.winner == -1 and int(r.quan_jiang) == -1)

	s = _mk_mode("classic", [5, 5], GameRules.MAX_ROUND)
	GameResolve.resolve_turn(s, ZAN, ZAN)
	ok = _exp(ok, "[经典] 40 回合血同 → 平局（一局定胜负，靠重开本局）", s.winner == 2)

	s = _mk_mode("classic", [0, 0])
	s.winner = 2
	info = s.settle_round_after_resolve()
	ok = _exp(ok, "[经典] 第 1 次平局：不得分、不终场（重开本局）",
		bool(info["round_end"]) and not bool(info["match_over"])
		and s.score == [0, 0] and s.draw_count == 1)
	s.winner = 2
	s.settle_round_after_resolve()
	s.winner = 2
	s.settle_round_after_resolve()
	ok = _exp(ok, "[经典] 第 2/3 次平局仍不终场（draw_count=3）",
		not s.is_match_over() and s.score == [0, 0] and s.draw_count == 3)
	s.winner = 2
	info = s.settle_round_after_resolve()
	ok = _exp(ok, "[经典] 第 4 次平局 → 整场判平（match_over + match_winner=2）",
		bool(info["match_over"]) and int(info["match_winner"]) == 2 and s.score == [0, 0])

	s = _mk_mode("classic", [5, 5])
	GameResolve.resolve_turn(s, BAO1, ZAN)
	info = s.settle_round_after_resolve()
	ok = _exp(ok, "[经典] 一局定胜负：胜者 +1 分即整场结束（match_winner=0）",
		bool(info["match_over"]) and int(info["match_winner"]) == 0 and s.score == [1, 0])

	# ── ㉓ 精通（mastery）：只旁路解锁分支，CD / 气 / 盾照旧（v2 §1）──────────
	s = BattleState.new("lesson", true)
	s.qi = [10, 10]
	s.round = 2
	s.score = [0, 0]
	avail = s.available_actions(0)
	avail.sort()
	ok = _exp(ok, "[精通] 第 2 回合解锁旁路：6 个可用（CD3+ 仍按 §1 计时，不是 13）",
		s.mastery and avail == [ZAN, BAO1, BAO2, BAO3, FANG, STRONG_FANG])
	s.round = 9
	avail = s.available_actions(0)
	avail.sort()
	ok = _exp(ok, "[精通] 回合 9（CD 全过）：13 个动作全可用（0 分也解锁）",
		avail.size() == 13 and avail == all_skills)
	s.score = [1, 0]
	var avail2: Array = s.available_actions(0)
	avail2.sort()
	ok = _exp(ok, "[精通] 解锁不累加：分数变化不改变动作集合（0 分即全解锁）",
		avail2 == avail)

	# ── ㉔ 快照：mode + mastery 随包，restore 校验一致 ───────────────────
	s = BattleState.new("classic")
	var snap_c: Dictionary = s.snapshot()
	ok = _exp(ok, "[快照] snapshot 带 mode + mastery",
		str(snap_c.get("mode", "")) == "classic" and not bool(snap_c.get("mastery", true)))
	var src: BattleState = BattleState.new()
	src.hp = [3, 2]
	src.qi = [7, 1]
	src.shield = [1, 2]
	src.round = 9
	src.score = [3, 5]
	src.draw_count = 2
	var snap2: Dictionary = src.snapshot()
	var c2: BattleState = BattleState.new()
	ok = _exp(ok, "[快照] restore 同模式：非默认 hp/qi/比分/回合/平局数原样落地",
		c2.restore(snap2) and c2.hp == [3, 2] and c2.qi == [7, 1]
		and c2.score == [3, 5] and c2.round == 9 and c2.draw_count == 2
		and c2.mode == "lesson" and not c2.mastery)
	var lesson_s: BattleState = BattleState.new()
	ok = _exp(ok, "[快照] restore 校验：mode 不一致 → 拒绝（状态不动）",
		not lesson_s.restore(snap_c) and lesson_s.mode == "lesson"
		and lesson_s.hp == [4, 4])
	lesson_s.hp = [3, 2]
	ok = _exp(ok, "[快照] restore 校验失败时不改任何字段",
		not lesson_s.restore(snap_c) and lesson_s.hp == [3, 2])

	# ── ㉕ restore 防篡改 / 防伪造（联机外部数据防御，2026-10-27）────────────
	var t1: BattleState = BattleState.new("classic")
	t1.qi = [2, 3]
	ok = _exp(ok, "[快照] restore 防篡改：缺 mode 键 → 拒绝（状态不动）",
		not t1.restore({"mastery": false, "round": 7, "hp": [0, 0]})
		and t1.round == 1 and t1.qi == [2, 3] and t1.hp == [1, 1])
	var t2: BattleState = BattleState.new("classic")
	ok = _exp(ok, "[快照] restore 防篡改：缺 mastery 键 → 拒绝（状态不动）",
		not t2.restore({"mode": "classic", "round": 7}) and t2.round == 1)
	var t3: BattleState = BattleState.new("classic")
	ok = _exp(ok, "[快照] restore 防伪造：classic draw_count 超出重开上限 → 拒绝（状态不动）",
		not t3.restore({"mode": "classic", "mastery": false, "draw_count": 40})
		and not t3.restore({"mode": "classic", "mastery": false, "draw_count": 5, "winner": 2})
		and t3.draw_count == 0)
	var t4: BattleState = BattleState.new()
	ok = _exp(ok, "[快照] restore 防伪造：lesson draw_count 超界 → 钳到保底阈值 3（结算等价）",
		t4.restore({"mode": "lesson", "mastery": false, "draw_count": 40})
		and t4.draw_count == 3)
	var t5: BattleState = BattleState.new("classic")
	ok = _exp(ok, "[快照] restore 防伪造：classic 伪造终场比分（[1,1] 双到线 / 未结算 [1,0]）→ 拒绝（状态不动）",
		not t5.restore({"mode": "classic", "mastery": false, "score": [1, 1]})
		and not t5.restore({"mode": "classic", "mastery": false, "score": [1, 1], "winner": 2})
		and not t5.restore({"mode": "classic", "mastery": false, "score": [1, 0]})
		and t5.score == [0, 0] and int(t5.winner) == -1)
	var t6: BattleState = BattleState.new("classic")
	ok = _exp(ok, "[快照] restore 终场快照例外：已结算（winner≥0）的合法终场可恢复",
		t6.restore({"mode": "classic", "mastery": false, "score": [1, 0], "winner": 0})
		and t6.score == [1, 0] and t6.is_match_over()
		and t6.restore({"mode": "classic", "mastery": false, "score": [0, 0], "draw_count": 4, "winner": 2})
		and t6.draw_count == 4 and t6.is_match_over() and t6.match_winner() == 2)

	# ── ㉖ restore 的 cooldowns：过滤非本模式动作 + 钳到当前回合（对齐 battle_state._cooldowns）──
	var c3: BattleState = BattleState.new("classic")
	ok = _exp(ok, "[快照] restore cooldowns 过滤本模式外动作、钳到当前回合",
		c3.restore({"mode": "classic", "mastery": false, "round": 5,
			"cooldowns": [{XIAO_YANG: 3, BAO1: 99}, {BAO2: 2}]})
		and c3.cooldowns == [{BAO1: 5}, {}])

	# ── ㉗ restore 脏输入防御：非数值强转 0（GDScript int() 语义），冷却表短列表缺位补空 ──
	var t7: BattleState = BattleState.new("classic")
	ok = _exp(ok, "[快照] restore 脏输入防御：非数值强转 0、cooldowns 短列表缺位补空",
		t7.restore({"mode": "classic", "mastery": false, "round": "abc",
			"draw_count": "xyz", "cooldowns": [{BAO1: 2}]})
		and t7.round == 1 and t7.draw_count == 0 and t7.cooldowns == [{BAO1: 1}, {}])

	# ── ㉘ phase 字段随快照传输并钳制（Python 镜像双向对齐）──────────────────
	var t8: BattleState = BattleState.new("classic")
	ok = _exp(ok, "[快照] phase 随包传输、越界钳制到 [OPENING, GAME_OVER]",
		t8.restore({"mode": "classic", "mastery": false, "phase": 99})
		and int(t8.phase) == GameRules.Phase.GAME_OVER
		and t8.restore({"mode": "classic", "mastery": false, "phase": -5})
		and int(t8.phase) == GameRules.Phase.OPENING
		and int((t8.snapshot()).get("phase", -1)) == GameRules.Phase.OPENING)

	# ── ㉙ 出招消毒：本模式禁用动作 / 技能表外值 → 兜底攒气（resolve.sanitize_action）──
	s = _mk_mode("classic", [0, 0])
	r = GameResolve.resolve_turn(s, ZHONG_JI, ZAN)
	ok = _exp(ok, "[消毒] classic 强出终极技 → 兜底攒气（ZAN vs ZAN，1 血不死、各 +1 气）",
		r.actions == [ZAN, ZAN] and s.winner == -1
		and _chk(s, [1, 1], [1, 1], [3, 3]))

	s = _mk([4, 4], [0, 0], [3, 3])
	r = GameResolve.resolve_turn(s, 99, ZAN)
	ok = _exp(ok, "[消毒] lesson 未知动作 id → 兜底攒气（ZAN vs ZAN）",
		r.actions == [ZAN, ZAN] and s.winner == -1
		and _chk(s, [4, 4], [1, 1], [3, 3]))

	# ── ㉚ set_preset 中途换模式：不缩资源（行为保持），reset 后按新预设归位 ──────
	var t9: BattleState = BattleState.new()
	t9.set_preset("classic")
	var kept: bool = (
		t9.mode == "classic" and t9.max_hp() == 1
		and t9.hp == [GameRules.MAX_HP, GameRules.MAX_HP]
	)
	t9.reset_round_keep_score()
	ok = _exp(ok, "[预设] set_preset 不缩资源（行为保持），reset_round_keep_score 按新预设归位",
		kept and t9.hp == [1, 1] and t9.qi == [0, 0])

	print("=".repeat(52))
	if not ok:
		for n in _failed:
			print("  FAILED: ", n)
	print("ALL PASS" if ok else "HAS FAILURES")
	quit(0 if ok else 1)


## 构造局面：hp / qi / shield / round 直接给（round 默认 2，绕开开局亮相）。
func _mk(hp: Array, qi: Array, shield: Array, round_no: int = 2) -> BattleState:
	var s := BattleState.new()
	s.hp = hp.duplicate()
	s.qi = qi.duplicate()
	s.shield = shield.duplicate()
	s.round = round_no
	return s


## 按模式构造局面：资源上限取自预设（hp / 盾默认满），qi / round 显式给。
func _mk_mode(mode: String, qi: Array, round_no: int = 2, mastery: bool = false) -> BattleState:
	var s := BattleState.new(mode, mastery)
	s.qi = qi.duplicate()
	s.round = round_no
	return s


## 三项资源同时相等。
func _chk(s: BattleState, hp: Array, qi: Array, sh: Array) -> bool:
	return s.hp == hp and s.qi == qi and s.shield == sh


func _exp(ok: bool, name: String, cond: bool) -> bool:
	# 按本行真实结果打印（打印 ok and cond 会让首个失败把后续每条都误显 FAIL）
	print(("PASS" if cond else "FAIL"), " - ", name)
	if not cond:
		_failed.append(name)
	return ok and cond

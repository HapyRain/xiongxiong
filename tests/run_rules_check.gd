## run_rules_check.gd
## Godot 无头自检：跑冻结结算表。
## 与 tests/test_rules_v0.py 的 14 条期望逐条对应（那是独立的 Python 拷贝，不是调用本文件）。
## 改 scripts/rules/resolve.gd 的结算语义必须同步改 Python 侧（AGENTS 硬约束 2）。
##
## 历史坑：本文件长期只有 5 条断言，赢法/封顶/40 回合/双亡全无覆盖——
## 把 resolve.gd 的 clamp_i 和 _check_winner 删掉仍然 ALL PASS。现在补齐。
extends SceneTree


func _init() -> void:
	var ok := true

	# ---------- 开局 ----------
	var s := BattleState.new()
	GameResolve.resolve_opening(s)
	ok = _exp(ok, "开局：气[1,1] 盾[3,3]", int(s.qi[0]) == 1 and int(s.qi[1]) == 1
		and int(s.shield[0]) == 3 and int(s.shield[1]) == 3)

	# ---------- 波 vs 攒 ----------
	s = _mk([5, 5], [3, 3], [3, 2])
	GameResolve.resolve_turn(s, GameRules.Action.BO, GameRules.Action.ZAN)
	ok = _exp(ok, "波vs攒：对手-1血；我 qi3→2；对手 qi3→4 盾2→3",
		s.hp == [5, 4] and s.qi == [2, 4] and s.shield == [3, 3])

	s = _mk([5, 5], [3, 3], [3, 3])
	GameResolve.resolve_turn(s, GameRules.Action.BO, GameRules.Action.ZAN)
	ok = _exp(ok, "波vs攒：对手盾 3+1 封顶 3",
		s.hp == [5, 4] and s.qi == [2, 4] and s.shield == [3, 3])

	# ---------- 波 vs 波 ----------
	s = _mk([5, 5], [3, 3], [3, 3])
	GameResolve.resolve_turn(s, GameRules.Action.BO, GameRules.Action.BO)
	ok = _exp(ok, "波vs波：互消 qi→2,2 且不掉血",
		s.hp == [5, 5] and s.qi == [2, 2] and s.shield == [3, 3])

	# ---------- 波 vs 防 ----------
	s = _mk([5, 5], [3, 3], [3, 3])
	GameResolve.resolve_turn(s, GameRules.Action.BO, GameRules.Action.FANG)
	ok = _exp(ok, "波vs防：我 qi→2；对手盾→2 且不掉血",
		s.hp == [5, 5] and s.qi == [2, 3] and s.shield == [3, 2])

	# ---------- 防 vs 攒（空防不扣） ----------
	s = _mk([5, 5], [1, 1], [3, 1])
	GameResolve.resolve_turn(s, GameRules.Action.FANG, GameRules.Action.ZAN)
	ok = _exp(ok, "防vs攒：我盾仍3；对手 qi盾+1",
		s.hp == [5, 5] and s.qi == [1, 2] and s.shield == [3, 2])

	# ---------- 防 vs 防 ----------
	s = _mk([5, 5], [1, 1], [2, 2])
	GameResolve.resolve_turn(s, GameRules.Action.FANG, GameRules.Action.FANG)
	ok = _exp(ok, "防vs防：无事", s.hp == [5, 5] and s.qi == [1, 1] and s.shield == [2, 2])

	# ---------- 攒 vs 攒（封顶） ----------
	s = _mk([5, 5], [4, 5], [3, 3])
	GameResolve.resolve_turn(s, GameRules.Action.ZAN, GameRules.Action.ZAN)
	ok = _exp(ok, "攒vs攒：气封顶5 盾封顶3", s.qi == [5, 5] and s.shield == [3, 3])

	# ---------- 击杀 / 被击杀 ----------
	s = _mk([5, 1], [3, 3], [0, 0])
	GameResolve.resolve_turn(s, GameRules.Action.BO, GameRules.Action.ZAN)
	ok = _exp(ok, "击杀对手：winner=0", s.winner == 0 and int(s.hp[1]) == 0)

	s = _mk([1, 5], [3, 3], [0, 0])
	GameResolve.resolve_turn(s, GameRules.Action.ZAN, GameRules.Action.BO)
	ok = _exp(ok, "被击杀：winner=1", s.winner == 1 and int(s.hp[0]) == 0)

	# ---------- 双亡（直接置血，测判定；常规出招不可能双亡） ----------
	s = _mk([0, 0], [3, 3], [0, 0])
	GameResolve._check_winner(s)
	ok = _exp(ok, "双亡：平局 winner=2", s.winner == 2)

	# ---------- 40 回合比血 ----------
	s = _mk([3, 5], [0, 0], [0, 0], 40)
	GameResolve._check_winner(s)
	ok = _exp(ok, "40回合血少：对手胜", s.winner == 1)

	s = _mk([4, 4], [0, 0], [0, 0], 40)
	GameResolve._check_winner(s)
	ok = _exp(ok, "40回合血同：平局", s.winner == 2)

	s = _mk([5, 2], [0, 0], [0, 0], 40)
	GameResolve._check_winner(s)
	ok = _exp(ok, "40回合血多：我胜", s.winner == 0)

	# ---------- 出招合法性（can_use_action，之前零覆盖） ----------
	var fresh := BattleState.new()  # round=1
	ok = _exp(ok, "回合1只准攒", fresh.can_use_action(0, GameRules.Action.ZAN)
		and not fresh.can_use_action(0, GameRules.Action.BO)
		and not fresh.can_use_action(0, GameRules.Action.FANG))
	var mid := _mk([5, 5], [0, 0], [0, 0])
	ok = _exp(ok, "0气禁波", not mid.can_use_action(0, GameRules.Action.BO))
	ok = _exp(ok, "0盾禁防", not mid.can_use_action(0, GameRules.Action.FANG))
	mid = _mk([5, 5], [1, 1], [1, 1])
	ok = _exp(ok, "1气可波 / 1盾可防", mid.can_use_action(0, GameRules.Action.BO)
		and mid.can_use_action(0, GameRules.Action.FANG))
	# 非法枚举不能当成合法招
	ok = _exp(ok, "非法出招值不可用", not mid.can_use_action(0, 9))

	# ---------- 结算副作用：pending 必须清空（会话层据此重开窗口） ----------
	s = _mk([5, 5], [3, 3], [3, 3])
	s.pending = [GameRules.Action.ZAN, GameRules.Action.BO]
	GameResolve.resolve_turn(s, GameRules.Action.ZAN, GameRules.Action.BO)
	ok = _exp(ok, "结算后 pending 清空", int(s.pending[0]) == -1 and int(s.pending[1]) == -1)

	print("ALL PASS" if ok else "HAS FAILURES")
	quit(0 if ok else 1)


## 构造局面：hp/qi/shield/round 直接给。
func _mk(hp: Array, qi: Array, shield: Array, round_no: int = 2) -> BattleState:
	var s := BattleState.new()
	s.hp = hp.duplicate()
	s.qi = qi.duplicate()
	s.shield = shield.duplicate()
	s.round = round_no
	return s


func _exp(ok: bool, name: String, cond: bool) -> bool:
	# 按本行真实结果打印：打印 ok and cond 会让首个失败把后续每条都误显 FAIL
	print(("PASS" if cond else "FAIL"), " - ", name)
	return ok and cond

## run_rules_check.gd
## Godot 无头自检：加载规则并跑冻结结算表。
extends SceneTree


func _init() -> void:
	var ok := true
	var s := BattleState.new()
	GameResolve.resolve_opening(s)
	ok = _exp(ok, "开局气盾", int(s.qi[0]) == 1 and int(s.qi[1]) == 1 and int(s.shield[0]) == 3 and int(s.shield[1]) == 3)

	s = BattleState.new()
	s.qi = [3, 3]
	s.shield = [3, 2]
	s.round = 2
	GameResolve.resolve_turn(s, GameRules.Action.BO, GameRules.Action.ZAN)
	ok = _exp(ok, "波vs攒", int(s.hp[1]) == 4 and int(s.qi[0]) == 2 and int(s.qi[1]) == 4 and int(s.shield[1]) == 3)

	s = BattleState.new()
	s.qi = [3, 3]
	s.shield = [3, 3]
	s.round = 2
	GameResolve.resolve_turn(s, GameRules.Action.BO, GameRules.Action.BO)
	ok = _exp(ok, "波vs波", int(s.hp[0]) == 5 and int(s.qi[0]) == 2 and int(s.qi[1]) == 2)

	s = BattleState.new()
	s.qi = [3, 3]
	s.shield = [3, 3]
	s.round = 2
	GameResolve.resolve_turn(s, GameRules.Action.BO, GameRules.Action.FANG)
	ok = _exp(ok, "波vs防", int(s.shield[1]) == 2 and int(s.qi[0]) == 2)

	s = BattleState.new()
	s.qi = [1, 1]
	s.shield = [3, 1]
	s.round = 2
	GameResolve.resolve_turn(s, GameRules.Action.FANG, GameRules.Action.ZAN)
	ok = _exp(ok, "空防不扣", int(s.shield[0]) == 3 and int(s.shield[1]) == 2)

	print("ALL PASS" if ok else "HAS FAILURES")
	quit(0 if ok else 1)


func _exp(ok: bool, name: String, cond: bool) -> bool:
	print(("PASS" if cond else "FAIL"), " - ", name)
	return ok and cond

## run_roundloop_check.gd
## 联机闭环回归：点招 → 双方锁定 → 亮招 → 下一回合按钮回弹（含 rematch 后再开一局）。
## 复现：客户端第一回合点一次后 UI 永久灰（state.pending 未在新窗清空）。
## v2：开局亮相只允许攒气（气 +1）；另含 T6「每小局判分 / 12 分终场 / 小局重开」断言。
extends SceneTree

var _ok := true
var _finished := false
var _host_pm: PeerManager
var _client_pm: PeerManager
var _host_ctrl: NetworkedBattleController
var _client_ctrl: NetworkedBattleController
var _reveals := 0


func _initialize() -> void:
	print("ROUNDLOOP_START")
	var hp := LocalProvider.new()
	var cp := LocalProvider.new()
	hp.pair_with(cp)

	_host_pm = PeerManager.new()
	root.add_child(_host_pm)
	_host_pm.install_provider(hp, PeerManager.Mode.ENET)
	_host_pm.actions_revealed.connect(func(_a, _r): _reveals += 1)

	_client_pm = PeerManager.new()
	root.add_child(_client_pm)
	_client_pm.install_provider(cp, PeerManager.Mode.ENET)

	hp.open_as_host({})
	cp.open_as_client({})
	_host_pm._sync_fsm_identity()
	_client_pm._sync_fsm_identity()
	_host_pm._set_session(PeerManager.Session.IN_BATTLE)
	_client_pm._set_session(PeerManager.Session.IN_BATTLE)
	_host_pm.start_battle()
	_pump()

	_host_ctrl = NetworkedBattleController.new()
	root.add_child(_host_ctrl)
	_host_ctrl.attach(_host_pm)
	_host_ctrl.begin()

	_client_ctrl = NetworkedBattleController.new()
	root.add_child(_client_ctrl)
	_client_ctrl.attach(_client_pm)
	_client_ctrl.begin()
	_pump()

	_exp("host window open", _host_ctrl._window_open)
	_exp("client window open", _client_ctrl._window_open)

	# ---------- 开局：双方点「攒」 ----------
	_exp("host pick zan", _host_ctrl.try_select(0, GameRules.Action.ZAN))
	_exp("client pick zan", _client_ctrl.try_select(1, GameRules.Action.ZAN))
	_exp("host locked after pick", _host_pm._locks[0])
	_exp("client locked after pick", _client_pm._locks[1])
	# 点完即灰：本地已选
	_exp("host picked set", int(_host_ctrl._local_preselect[0]) == GameRules.Action.ZAN)
	_exp("client picked set", int(_client_ctrl._local_preselect[1]) == GameRules.Action.ZAN)

	_host_ctrl.lock_in()
	_client_ctrl.lock_in()
	_pump()
	_pump()

	_exp("opening done", _host_pm._opening_done and _client_pm._opening_done)
	_exp("opening qi 1", int(_host_pm.state.qi[0]) == 1 and int(_client_pm.state.qi[1]) == 1)
	_exp("reveals after opening", _reveals >= 1)

	# 房主推进到回合 2（等价于 OPENING_DELAY 后的 _begin_next_round）
	_host_pm._begin_next_round()
	_pump()
	_pump()

	_exp("round is 2 host", _host_pm.state.round == 2)
	_exp("round is 2 client", _client_pm.state.round == 2)

	# 关键：新窗必须回弹 —— pending / locks / preselect 全清，UI 才会解灰
	_exp("host pending cleared", int(_host_pm.state.pending[0]) < 0 and int(_host_pm.state.pending[1]) < 0)
	_exp("client pending cleared", int(_client_pm.state.pending[0]) < 0 and int(_client_pm.state.pending[1]) < 0)
	_exp("host locks cleared", not _host_pm._locks[0] and not _host_pm._locks[1])
	_exp("client locks cleared", not _client_pm._locks[0] and not _client_pm._locks[1])
	_exp("host preselect cleared", int(_host_ctrl._local_preselect[0]) < 0)
	_exp("client preselect cleared", int(_client_ctrl._local_preselect[1]) < 0)
	_exp("host window reopened", _host_ctrl._window_open)
	_exp("client window reopened", _client_ctrl._window_open)

	# UI 判灰等价式（net_battle_ui._refresh_all）
	_exp("host ui can pick", _ui_can_pick(_host_pm, _host_ctrl, 0))
	_exp("client ui can pick", _ui_can_pick(_client_pm, _client_ctrl, 1))

	# ---------- 回合 2：再点招并亮招 ----------
	_exp("host pick r2", _host_ctrl.try_select(0, GameRules.Action.ZAN))
	_exp("client pick r2", _client_ctrl.try_select(1, GameRules.Action.ZAN))
	_host_ctrl.lock_in()
	_client_ctrl.lock_in()
	_pump()
	_pump()

	var reveals_after_r2 := _reveals
	_exp("r2 revealed", reveals_after_r2 >= 2)

	_host_pm._begin_next_round()
	_pump()
	_pump()

	_exp("round is 3", _host_pm.state.round == 3 and _client_pm.state.round == 3)
	_exp("client pending cleared r3", int(_client_pm.state.pending[1]) < 0)
	_exp("client ui can pick r3", _ui_can_pick(_client_pm, _client_ctrl, 1))
	_exp("client try_select r3", _client_ctrl.try_select(1, GameRules.Action.ZAN))

	# ---------- T6：每小局判分 / 12 分终场 / 小局重开 ----------
	_check_settle_v2()
	_check_net_round_restart()
	_check_solo_round_restart()
	_check_forfeit_ends_match()
	_check_ai_v2()
	_check_solo_modes()

	# ---------- rematch：强制终局后再来一局 ----------
	_host_pm.state.winner = 0
	_client_pm.state.winner = 0
	_host_pm._set_session(PeerManager.Session.GAME_OVER)
	_client_pm._set_session(PeerManager.Session.GAME_OVER)
	_host_ctrl.stop()
	_client_ctrl.stop()

	# GDScript 的 lambda 对标量是「按值捕获」，函数体里赋值不会回写外层局部变量。
	# 原来用 var host_rematch := false 记录回调 → 永远 false，断言靠 or 兜底才过。
	# 用 Dictionary（引用类型）才能真正观测到回调是否触发。
	var rematch_seen := {"host": false, "client": false}
	_host_pm.rematch_answered.connect(func(y): rematch_seen["host"] = y)
	_client_pm.rematch_answered.connect(func(y): rematch_seen["client"] = y)

	_host_pm.request_rematch()
	_pump()
	_client_pm.answer_rematch(true)
	_pump()
	_pump()

	_exp("host rematch_answered fired", bool(rematch_seen["host"]))
	_exp("client rematch_answered fired", bool(rematch_seen["client"]))
	_exp("host rematch started", _host_pm.get_session() == PeerManager.Session.IN_BATTLE)
	_exp("client rematch started", _client_pm.get_session() == PeerManager.Session.IN_BATTLE)
	_exp("rematch round reset", _host_pm.state.round == GameRules.OPENING_ROUND and _client_pm.state.round == GameRules.OPENING_ROUND)
	_exp("rematch hp reset", int(_host_pm.state.hp[0]) == GameRules.MAX_HP and int(_client_pm.state.hp[1]) == GameRules.MAX_HP)
	_exp("rematch pending clear", int(_client_pm.state.pending[1]) < 0)

	# rematch 后客户端必须还能点
	_client_ctrl.begin()
	_pump()
	_exp("client window after rematch", _client_ctrl._window_open)
	_exp("client ui can pick after rematch", _ui_can_pick(_client_pm, _client_ctrl, 1))
	_exp("client pick after rematch", _client_ctrl.try_select(1, GameRules.Action.ZAN))

	# ── 掉线接管后再来一局：必须真开新局（旧代码清掉 ai_takeover → READY_CHECK 死路）
	_host_pm.ai_takeover = true
	_host_pm.request_rematch()
	_exp("takeover rematch starts battle",
		_host_pm.get_session() == PeerManager.Session.IN_BATTLE
		and _host_pm.state.round == GameRules.OPENING_ROUND)
	_host_pm.ai_takeover = false

	# ── 联机 RoundResult 序列化：封盾/劝降/双视角文案必须带上
	var rr := GameRules.RoundResult.new()
	rr.actions = [GameRules.Action.XIAO_YANG, GameRules.Action.FANG]
	rr.sealed = [false, true]
	rr.quan_jiang = 1
	var rd: Dictionary = _host_pm._result_to_dict(rr)
	_exp("result dict 带 sealed", (rd.get("sealed", []) as Array) == [false, true])
	_exp("result dict 带 quan_jiang", int(rd.get("quan_jiang", -1)) == 1)
	var texts: Array = rd.get("texts", [])
	_exp("result dict 带双视角文案（两份不同）",
		texts.size() == 2 and str(texts[0]) != str(texts[1]))
	if _host_pm != null:
		_host_pm.leave()
	_finish()


## T6 会话层判分 / 终场（单机、热座、联机房主共用同一份裁决）。
## 用例 1：score=[11,0] 时本小局 winner=0 → score[0] 收到 12 → 整场 GAME_OVER，winner 保留胜者。
## 用例 2：score 未到 12 → 小局结束只重开一小局：资源全复位、score 保留、winner 归 -1、仍是回合 1 开局窗。
## 用例 3：平局（winner=2）前 2 次双方不得分，同样重开一小局。
## 用例 4：第 3 次平局 → 保底计分，双方各 +1（防无限拖，game-rules-v2.md §1/§5）。
## 用例 5：平局保底使双方同时到 12 分 → 整场结束且整场判平（match_winner=2）。
func _check_settle_v2() -> void:
	var pm := _make_settle_pm(11, 0, [4, 1], [1, 0])
	pm.reveal_phase()  # 包子×1 vs 攒气（裸防）→ 对手 -1 血 → 本小局 winner=0
	_exp("终场：score[0] 11→12", int(pm.state.score[0]) == 12 and int(pm.state.score[1]) == 0)
	_exp("终场：Session.GAME_OVER", pm.get_session() == PeerManager.Session.GAME_OVER)
	_exp("终场：winner 保留为胜者", int(pm.state.winner) == 0)
	_exp("终场：不再重开小局（回合/血保持终局态）",
		int(pm.state.round) == 3 and int(pm.state.hp[1]) == 0)
	pm.leave()

	var pm2 := _make_settle_pm(3, 5, [4, 1], [1, 0])
	pm2.reveal_phase()
	_exp("小局结束：score[0] 3→4 且保留对手分", int(pm2.state.score[0]) == 4 and int(pm2.state.score[1]) == 5)
	_exp("小局结束：未终场仍 IN_BATTLE", pm2.get_session() == PeerManager.Session.IN_BATTLE)
	_exp("小局结束：未到 12 分", not pm2.state.is_match_over())
	_exp("小局重开：round 回 1", int(pm2.state.round) == GameRules.OPENING_ROUND)
	_exp("小局重开：hp 复位 4/4",
		int(pm2.state.hp[0]) == GameRules.MAX_HP and int(pm2.state.hp[1]) == GameRules.MAX_HP)
	_exp("小局重开：气归 0", int(pm2.state.qi[0]) == 0 and int(pm2.state.qi[1]) == 0)
	_exp("小局重开：盾回 3/3",
		int(pm2.state.shield[0]) == GameRules.MAX_SHIELD
		and int(pm2.state.shield[1]) == GameRules.MAX_SHIELD)
	_exp("小局重开：pending 清空", int(pm2.state.pending[0]) < 0 and int(pm2.state.pending[1]) < 0)
	_exp("小局重开：CD 清空",
		(pm2.state.cooldowns[0] as Dictionary).is_empty()
		and (pm2.state.cooldowns[1] as Dictionary).is_empty())
	_exp("小局重开：封盾清空",
		int(pm2.state.sealed_round[0]) == -1 and int(pm2.state.sealed_round[1]) == -1)
	_exp("小局重开：winner 归 -1（不再 is_over）", not pm2.state.is_over())
	# 表现停留的等价物：小局重开必须进回合 1 开局亮相窗，而不是把回合号 +1
	pm2.debug_advance_round()
	_exp("小局重开：回到回合1开局窗",
		int(pm2.state.round) == GameRules.OPENING_ROUND and not pm2._opening_done
		and pm2.state.phase == GameRules.Phase.SELECTING)
	_exp("小局重开：score 未被清", int(pm2.state.score[0]) == 4 and int(pm2.state.score[1]) == 5)
	pm2.leave()

	# 用例 3：双终极技同归于尽 → winner=2 → 双方不得分，照样重开一小局
	var pm3 := _make_settle_pm(8, 8, [1, 1], [5, 5])
	pm3.state.pending = [GameRules.Action.ZHONG_JI, GameRules.Action.ZHONG_JI]
	pm3._pending_actions = [GameRules.Action.ZHONG_JI, GameRules.Action.ZHONG_JI]
	pm3.reveal_phase()
	_exp("平局：双方不得分", int(pm3.state.score[0]) == 8 and int(pm3.state.score[1]) == 8)
	_exp("平局：同样重开一小局",
		int(pm3.state.round) == GameRules.OPENING_ROUND and not pm3.state.is_over())
	_exp("平局：资源复位（血 4 / 气 0）",
		int(pm3.state.hp[0]) == GameRules.MAX_HP and int(pm3.state.qi[0]) == 0)
	pm3.leave()

	# 用例 4：第 3 次平局 → 保底计分，双方各 +1
	var pm4 := _make_settle_pm(8, 8, [1, 1], [5, 5])
	pm4.state.draw_count = 2
	pm4.state.pending = [GameRules.Action.ZHONG_JI, GameRules.Action.ZHONG_JI]
	pm4._pending_actions = [GameRules.Action.ZHONG_JI, GameRules.Action.ZHONG_JI]
	pm4.reveal_phase()
	_exp("第3次平局：双方各 +1 分", int(pm4.state.score[0]) == 9 and int(pm4.state.score[1]) == 9)
	_exp("第3次平局：draw_count 累计为 3", pm4.state.draw_count == 3)
	_exp("第3次平局：未到 12 分仍重开", int(pm4.state.round) == GameRules.OPENING_ROUND and not pm4.state.is_over())
	pm4.leave()

	# 用例 5：平局保底使双方同时到 12 分 → 整场结束、整场判平
	var pm5 := _make_settle_pm(11, 11, [1, 1], [5, 5])
	pm5.state.draw_count = 2
	pm5.state.pending = [GameRules.Action.ZHONG_JI, GameRules.Action.ZHONG_JI]
	pm5._pending_actions = [GameRules.Action.ZHONG_JI, GameRules.Action.ZHONG_JI]
	pm5.reveal_phase()
	_exp("同时到12：比分 12:12", int(pm5.state.score[0]) == 12 and int(pm5.state.score[1]) == 12)
	_exp("同时到12：整场 GAME_OVER", pm5.get_session() == PeerManager.Session.GAME_OVER)
	_exp("同时到12：整场判平", pm5.state.match_winner() == 2)
	pm5.leave()


## 联机双端「小局结束 → 重开一小局」：房主 round_result 里的快照即新小局初值
## （round=1 / 血4 / 盾3 / 气0），随后广播回合 1 开局窗；客户端必须能继续点「攒」。
## 回归点：重开后 round 复位成 1，若把 1 写进信封，客户端会按「旧包」丢弃整条结算 → 双端分叉。
func _check_net_round_restart() -> void:
	var hp := LocalProvider.new()
	var cp := LocalProvider.new()
	hp.pair_with(cp)
	var hpm := PeerManager.new()
	root.add_child(hpm)
	hpm.install_provider(hp, PeerManager.Mode.ENET)
	var cpm := PeerManager.new()
	root.add_child(cpm)
	cpm.install_provider(cp, PeerManager.Mode.ENET)
	hp.open_as_host({})
	cp.open_as_client({})
	hpm._sync_fsm_identity()
	cpm._sync_fsm_identity()
	hpm._set_session(PeerManager.Session.IN_BATTLE)
	cpm._set_session(PeerManager.Session.IN_BATTLE)
	hpm.start_battle()
	_pump_two(hpm, cpm)

	# 表现层也要一起验：重开小局后双方选招窗必须重新打开（否则按钮永久灰）
	var hctrl := NetworkedBattleController.new()
	root.add_child(hctrl)
	hctrl.attach(hpm)
	hctrl.begin()
	var cctrl := NetworkedBattleController.new()
	root.add_child(cctrl)
	cctrl.attach(cpm)
	cctrl.begin()
	_pump_two(hpm, cpm)

	# 开局：双方点「攒」→ 亮相（房主先泵一次才能收到客户端的锁招包）
	hpm.submit_action(GameRules.Action.ZAN, 0)
	cpm.submit_action(GameRules.Action.ZAN, 1)
	_pump_two(hpm, cpm)
	hpm.reveal_phase()
	_pump_two(hpm, cpm)
	_exp("联机小局：开局亮相完成", hpm._opening_done and cpm._opening_done)
	_exp("联机小局：双方气 1", int(hpm.state.qi[0]) == 1 and int(cpm.state.qi[1]) == 1)

	# 造「本小局即将结束」：对手 1 血；包子×1 vs 攒气（裸防）→ 命中 → 本小局 winner=0
	hpm._opening_done = true
	cpm._opening_done = true
	hpm.state.round = 3
	cpm.state.round = 3
	hpm.state.hp = [4, 1]
	hpm.state.qi = [1, 0]
	hpm.state.score = [3, 5]
	hpm.state.pending = [GameRules.Action.BAO1, GameRules.Action.ZAN]
	hpm._pending_actions = [GameRules.Action.BAO1, GameRules.Action.ZAN]
	hpm._locks = [true, true]
	hpm.reveal_phase()
	_pump_two(hpm, cpm)
	_exp("联机小局：房主判分 3→4", int(hpm.state.score[0]) == 4 and int(hpm.state.score[1]) == 5)
	_exp("联机小局：客户端同步到分数", int(cpm.state.score[0]) == 4 and int(cpm.state.score[1]) == 5)
	_exp("联机小局：房主未终场仍 IN_BATTLE", hpm.get_session() == PeerManager.Session.IN_BATTLE)
	_exp("联机小局：客户端未终场仍 IN_BATTLE", cpm.get_session() == PeerManager.Session.IN_BATTLE)
	_exp("联机小局：客户端资源随快照复位",
		int(cpm.state.hp[0]) == GameRules.MAX_HP and int(cpm.state.hp[1]) == GameRules.MAX_HP
		and int(cpm.state.qi[1]) == 0 and int(cpm.state.shield[1]) == GameRules.MAX_SHIELD)
	_exp("联机小局：客户端 winner 归 -1（不再 is_over）", not cpm.state.is_over())

	# 等价于结算停留后自动进新小局开局窗（headless 无计时器，手动推一把）
	hpm.debug_advance_round()
	_pump_two(hpm, cpm)
	_exp("联机小局重开：双端回回合 1",
		int(hpm.state.round) == GameRules.OPENING_ROUND and int(cpm.state.round) == GameRules.OPENING_ROUND)
	_exp("联机小局重开：双端回到点攒阶段",
		not hpm._opening_done and not cpm._opening_done
		and cpm.state.phase == GameRules.Phase.SELECTING)
	_exp("联机小局重开：score 双端保留", int(cpm.state.score[0]) == 4 and int(cpm.state.score[1]) == 5)
	_exp("联机小局重开：双端选招窗重新打开", hctrl._window_open and cctrl._window_open)
	_exp("联机小局重开：客户端选招闸放开（不会永久灰）", cctrl.is_pick_open() and hctrl.is_pick_open())
	_exp("联机小局重开：客户端还能点「攒」",
		cctrl.try_select(1, GameRules.Action.ZAN) and int(cpm.state.pending[1]) == GameRules.Action.ZAN)
	# 走完新小局的开局亮相：双方再点攒 → 气重新 1
	_exp("联机小局重开：房主能点「攒」", hctrl.try_select(0, GameRules.Action.ZAN))
	_pump_two(hpm, cpm)
	hpm.reveal_phase()
	_pump_two(hpm, cpm)
	_exp("联机小局重开：新小局亮相成功", hpm._opening_done and int(cpm.state.qi[1]) == 1)
	hpm.leave()
	cpm.leave()


## 单机路径：BattleController._start_opening(true) 也必须走同一份会话层复位（保留 score）。
func _check_solo_round_restart() -> void:
	var solo := BattleController.new()
	root.add_child(solo)
	solo.state.score = [4, 5]
	solo.state.round = 6
	solo.state.hp = [4, 1]
	solo.state.qi = [3, 2]
	solo.state.cooldowns = [{GameRules.Action.JI_QI: 2}, {}]
	solo.state.sealed_round = [-1, 6]
	solo.state.winner = 0
	solo._opening_done = true
	solo._start_opening(true)
	_exp("单机小局重开：score 保留", int(solo.state.score[0]) == 4 and int(solo.state.score[1]) == 5)
	_exp("单机小局重开：资源复位（血4/盾3/气0/winner -1）",
		int(solo.state.hp[0]) == GameRules.MAX_HP and int(solo.state.hp[1]) == GameRules.MAX_HP
		and int(solo.state.shield[0]) == GameRules.MAX_SHIELD and int(solo.state.qi[0]) == 0
		and not solo.state.is_over())
	_exp("单机小局重开：CD / 封盾 / pending 清空",
		(solo.state.cooldowns[0] as Dictionary).is_empty() and int(solo.state.sealed_round[1]) == -1
		and int(solo.state.pending[0]) < 0)
	_exp("单机小局重开：回回合 1 亮相流程",
		int(solo.state.round) == GameRules.OPENING_ROUND and not solo._opening_done)
	solo.free()


## AiOpponent v2 约定：返回的招必须满足 state.can_use_action（解锁分/耗气/盾/封盾/CD 全由规则层裁决）；
## 开局回合只攒气；低气偏攒气；候选只从攒气/包子×1/防御这一小撮可用集里挑。
func _check_ai_v2() -> void:
	var bad := 0
	var seen := {}
	for sc: int in [0, 3, 8, 12]:
		for qi: int in [0, 1, 3]:
			for sh: int in [0, 3]:
				for sealed: bool in [false, true]:
					var s := BattleState.new()
					s.round = 5
					s.score = [sc, sc]
					s.qi = [qi, qi]
					s.shield = [sh, sh]
					s.sealed_round = [5, 5] if sealed else [-1, -1]
					for i in 8:
						var a: int = AiOpponent.choose(s, 1)
						seen[a] = true
						if not s.can_use_action(1, a):
							bad += 1
						# hard：候选扩到包子 2/3 连，也必须过规则层
						if not s.can_use_action(1, AiOpponent.choose(s, 1, "hard")):
							bad += 1
	_exp("AI v2：返回的招全部可用（can_use_action，含 hard）", bad == 0)
	_exp("AI v2：开局回合只会攒气",
		AiOpponent.choose(BattleState.new(), 1) == GameRules.Action.ZAN)
	var only_basic := true
	for k in seen.keys():
		if k != GameRules.Action.ZAN and k != GameRules.Action.BAO1 and k != GameRules.Action.FANG:
			only_basic = false
	_exp("AI v2：normal 只从 攒气/包子×1/防御 里挑", only_basic)
	seed(20261021)
	var low := BattleState.new()
	low.round = 5
	low.qi = [1, 1]
	low.shield = [1, 1]
	var zan_cnt := 0
	var low_seen := {}
	for i in 40:
		var la: int = AiOpponent.choose(low, 1)
		low_seen[la] = true
		if la == GameRules.Action.ZAN:
			zan_cnt += 1
	_exp("AI v2：低气偏攒气（qi=1 时攒气占多数）", zan_cnt >= 18)
	_exp("AI v2：低气也不是永远攒气（包子/防御都会出）",
		low_seen.has(GameRules.Action.BAO1) and low_seen.has(GameRules.Action.FANG))

	seed(20261022)
	var rich := BattleState.new()
	rich.round = 5
	rich.qi = [5, 5]
	rich.shield = [3, 3]
	var rich_seen := {}
	for i in 40:
		rich_seen[AiOpponent.choose(rich, 1)] = true
	_exp("AI v2：气/盾充足时 攒气/包子/防御 都会出现",
		rich_seen.has(GameRules.Action.ZAN)
		and rich_seen.has(GameRules.Action.BAO1)
		and rich_seen.has(GameRules.Action.FANG))


## W2 单人配置：classic 一局定胜负 / mastery 第 2 回合可用数 / difficulty 传到 AI。
func _check_solo_modes() -> void:
	var ctrl := BattleController.new()
	root.add_child(ctrl)
	ctrl.start_match({"mode": "classic", "mastery": false, "difficulty": "normal"})
	var over := {"winner": -1}
	ctrl.game_over.connect(func(w): over["winner"] = w)
	_exp("单人 classic：按 cfg 构造状态（1 血 / 无技能）",
		ctrl.state.mode == "classic" and ctrl.state.max_hp() == 1 and not ctrl.state.skills_enabled())
	# 一局定胜负：单小局 winner=0 即 1 分到顶 → 整场 GAME_OVER
	ctrl._opening_done = true
	ctrl.state.round = 2
	ctrl.state.phase = GameRules.Phase.SELECTING
	ctrl.state.hp = [1, 1]
	ctrl.state.qi = [1, 0]
	ctrl.state.pending = [GameRules.Action.BAO1, GameRules.Action.ZAN]
	ctrl._resolve_locked()
	_exp("单人 classic：一小局结束 = 整场结束（score 1:0，game_over 0）",
		ctrl.state.is_match_over() and int(over["winner"]) == 0 and ctrl.state.score == [1, 0])
	root.remove_child(ctrl)
	ctrl.free()

	var m := BattleController.new()
	root.add_child(m)
	m.start_match({"mode": "lesson", "mastery": true, "difficulty": "normal"})
	m.state.round = 2
	m.state.qi = [10, 10]
	var acts: Array = m.state.available_actions(0)
	acts.sort()
	_exp("单人 mastery：第 2 回合可用 6 个（解锁旁路，CD 照旧）",
		m.state.mastery and acts == [GameRules.Action.ZAN, GameRules.Action.BAO1,
			GameRules.Action.BAO2, GameRules.Action.BAO3, GameRules.Action.FANG,
			GameRules.Action.STRONG_FANG])
	root.remove_child(m)
	m.free()

	var h := BattleController.new()
	root.add_child(h)
	h.start_match({"mode": "lesson", "difficulty": "hard"})
	_exp("单人 difficulty：cfg 的 hard 传到控制器", h.difficulty == "hard")
	root.remove_child(h)
	h.free()

	# AI hard：权重表直测（不靠随机采样，断言可失败）。
	# 对方 qi=3（≈上回合攒过）→ hard 包子权重必须整体高于 normal；normal 不扩包子 2/3 连。
	var s := BattleState.new()
	s.round = 5
	s.qi = [3, 3]
	s.shield = [3, 3]
	var bao_weight := func(w: Dictionary) -> int:
		return int(w.get(GameRules.Action.BAO1, 0)) + int(w.get(GameRules.Action.BAO2, 0)) + int(w.get(GameRules.Action.BAO3, 0))
	var w_normal := AiOpponent.weights(s, 1)
	var w_hard := AiOpponent.weights(s, 1, "hard")
	_exp("AI hard：对方气高时包子权重高于 normal",
		bao_weight.call(w_hard) > bao_weight.call(w_normal))
	_exp("AI hard：候选含包子 2/3 连（lesson）",
		w_hard.has(GameRules.Action.BAO2) and w_hard.has(GameRules.Action.BAO3))
	_exp("AI normal：候选仍是 攒气/包子×1/防御",
		not w_normal.has(GameRules.Action.BAO2) and not w_normal.has(GameRules.Action.BAO3))
	var hard_legal := true
	for a in w_hard:
		hard_legal = hard_legal and s.can_use_action(1, int(a))
	_exp("AI hard：权重表只含 can_use_action 合法招", hard_legal)

	var low_shield := BattleState.new()
	low_shield.round = 5
	low_shield.qi = [3, 3]
	low_shield.shield = [3, 1]
	_exp("AI hard：自己盾少时收着防御（normal 有，hard 权重 0）",
		int(AiOpponent.weights(low_shield, 1, "hard").get(GameRules.Action.FANG, 0)) == 0
		and int(AiOpponent.weights(low_shield, 1).get(GameRules.Action.FANG, 0)) > 0)


## 网络判负（forfeit / 拒绝继续 / 同意超时）是**整场**结束，不能当小局处理：
## 不加分、不重开小局、score 原样，winner 由判负写死（_on_fsm_failed，与结算判分是两条路）。
func _check_forfeit_ends_match() -> void:
	var pm := _make_settle_pm(4, 5, [4, 4], [0, 0])
	pm._wire_fsm()
	pm._sync_fsm_identity()
	pm._set_session(PeerManager.Session.IN_BATTLE)
	# 对端 peer 2 判负 → 房主胜（winner=0）
	pm.fsm.force_fail(2, "consent_reject")
	_exp("判负：整场结束（winner=0 / GAME_OVER）",
		int(pm.state.winner) == 0 and pm.get_session() == PeerManager.Session.GAME_OVER)
	_exp("判负：不加分（score 原样 4:5）", int(pm.state.score[0]) == 4 and int(pm.state.score[1]) == 5)
	_exp("判负：不重开小局（round 保持、无重开标记）",
		int(pm.state.round) == 3 and not pm._round_restart_pending)
	pm.leave()


## 造一个「房主权威」PM：回合 3 选招阶段、双方已锁招，可直接 reveal_phase() 结算。
## 热座（Mode.HOTSEAT，无 provider）与联机房主走的是同一条 _do_host_reveal 路径。
func _make_settle_pm(s0: int, s1: int, hp: Array, qi: Array) -> PeerManager:
	var pm := PeerManager.new()
	root.add_child(pm)
	pm._set_session(PeerManager.Session.IN_BATTLE)
	pm._opening_done = true
	pm.state.round = 3
	pm.state.phase = GameRules.Phase.SELECTING
	pm.state.hp = [int(hp[0]), int(hp[1])]
	pm.state.qi = [int(qi[0]), int(qi[1])]
	pm.state.shield = [GameRules.MAX_SHIELD, GameRules.MAX_SHIELD]
	pm.state.score = [s0, s1]
	pm.state.pending = [GameRules.Action.BAO1, GameRules.Action.ZAN]
	pm._pending_actions = [GameRules.Action.BAO1, GameRules.Action.ZAN]
	pm._locks = [true, true]
	return pm


func _ui_can_pick(pm: PeerManager, ctrl: NetworkedBattleController, seat: int) -> bool:
	# 与 net_battle_ui._refresh_all 同判据
	var s: BattleState = ctrl.state
	var picked: int = int(ctrl._local_preselect[seat]) if ctrl._local_preselect.size() > seat else -1
	if picked < 0:
		picked = int(s.pending[seat])
	var locked: bool = picked >= 0 or bool(pm._locks != null and seat < pm._locks.size() and bool(pm._locks[seat]))
	var can_lock: bool = not s.is_over() and pm.is_input_open() and ctrl._window_open
	return can_lock and not locked


func _process(_d: float) -> bool:
	return _finished


func _pump() -> void:
	if _host_pm != null and _host_pm.provider != null:
		_host_pm.provider.poll(0.0)
		_host_pm._pump_session(0.0)
	if _client_pm != null and _client_pm.provider != null:
		_client_pm.provider.poll(0.0)
		_client_pm._pump_session(0.0)


## 与 _pump 同语义，但作用于任意一对 PM（T6 用例用的是局部 host/client 对）。
func _pump_two(a: PeerManager, b: PeerManager) -> void:
	if a != null and a.provider != null:
		a.provider.poll(0.0)
		a._pump_session(0.0)
	if b != null and b.provider != null:
		b.provider.poll(0.0)
		b._pump_session(0.0)


func _exp(n: String, c: bool) -> void:
	# 按本行真实结果打印（用 _ok 打印会让首个失败把后续每条都误显 FAIL）
	print(("PASS" if c else "FAIL"), " - ", n)
	_ok = _ok and c


func _finish() -> void:
	if _finished:
		return
	_finished = true
	print("ALL PASS" if _ok else "HAS FAILURES")
	quit(0 if _ok else 1)

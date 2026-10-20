#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""「拍拍熊熊」v2 规则层自检 —— Python 独立镜像（不 import / 不调用 Godot）。

权威来源：
  * docs/rules/game-rules-v2.md §1–§9（唯一规则权威）
  * scratchpad/v2-contract.md §2（T1 冻结的逐条裁决）、§3（测试契约）

本文件按同一套语义**独立重写**结算管线（§4 五步）+ 对撞矩阵（§3）+ 出招合法性，
与 tests/run_rules_check.gd 是「同一套断言、两份实现」：两边必须同时 ALL PASS。
结论值一律从文档/契约手推，不从 resolve.gd 抄——两者若分歧必须报告，不得静默对齐。

运行：python tests\\test_rules_v2.py   → 末行 ALL PASS (exit 0)
"""
from __future__ import annotations

# ── §1 常量 ────────────────────────────────────────────────────────────
MAX_HP, MAX_SHIELD, MAX_QI, MAX_ROUND = 4, 3, 10, 40
OPENING_ROUND, BAO_MAX, WIN_SCORE = 1, 3, 12

# ── 动作枚举整数镜像（与 GameRules.Action 数值一一对应）───────────────
(ZAN, BAO1, BAO2, BAO3, FANG, STRONG_FANG, XIAO_YANG, JI_QI,
 XI_SHOU, DA_YANG, BAO_QI, HUI_FU, ZHONG_JI, QUAN_JIANG) = range(14)

QI_COST = {BAO1: 1, BAO2: 2, BAO3: 3, STRONG_FANG: 1, XIAO_YANG: 1,
           XI_SHOU: 1, DA_YANG: 2, BAO_QI: 1, ZHONG_JI: 5}
CD = {STRONG_FANG: 1, XIAO_YANG: 3, JI_QI: 3, XI_SHOU: 3,
      DA_YANG: 6, BAO_QI: 3, HUI_FU: 8, ZHONG_JI: 5}
UNLOCK = {STRONG_FANG: 1, XIAO_YANG: 2, JI_QI: 3, XI_SHOU: 4,
          DA_YANG: 5, BAO_QI: 6, HUI_FU: 7, ZHONG_JI: 8}
SKILLS = [ZAN, BAO1, BAO2, BAO3, FANG, STRONG_FANG, XIAO_YANG, JI_QI,
          XI_SHOU, DA_YANG, BAO_QI, HUI_FU, ZHONG_JI]
BAO_N = {BAO1: 1, BAO2: 2, BAO3: 3}
GAINS = (ZAN, JI_QI, HUI_FU, BAO_QI)          # 可被吸收偷的增益类
SEALABLE = (FANG, BAO_QI)                      # 封盾期间被禁
BREAKS = (XIAO_YANG, DA_YANG)                  # 破防技

# 对撞矩阵里「主动攻击类」的分类名
K_BAO, K_SHEEP, K_BIG, K_ZHONG = "bao", "sheep", "big_sheep", "zhong"
ATTACK_KINDS = (K_BAO, K_SHEEP, K_BIG, K_ZHONG)


def clamp(v, lo, hi):
    return max(lo, min(hi, v))


def bao_count(a):
    return BAO_N.get(a, 0)


def is_attack(a):
    return bao_count(a) > 0 or a in (XIAO_YANG, DA_YANG, ZHONG_JI)


def is_break(a):
    return a in BREAKS


def kind(a):
    """技能 → 对撞矩阵分类。"""
    if a in BAO_N:
        return K_BAO
    if a == FANG:
        return "fang"
    if a == STRONG_FANG:
        return "strong"
    if a == XIAO_YANG:
        return K_SHEEP
    if a == DA_YANG:
        return K_BIG
    if a == ZHONG_JI:
        return K_ZHONG
    if a == BAO_QI:
        return "burst"
    if a in GAINS:
        return "gain"
    if a == XI_SHOU:
        return "absorb"
    return "?"


class State:
    """对局状态（契约 §1 字段；cooldowns[who][action] = 上次使用回合）。"""

    def __init__(self, hp=None, qi=None, shield=None, round=1,
                 score=None, cooldowns=None, sealed_round=None, pending=None):
        self.round = round
        self.hp = list(hp if hp is not None else [MAX_HP, MAX_HP])
        self.qi = list(qi if qi is not None else [0, 0])
        self.shield = list(shield if shield is not None else [MAX_SHIELD, MAX_SHIELD])
        self.pending = list(pending if pending is not None else [-1, -1])
        self.winner = -1
        self.score = list(score if score is not None else [0, 0])
        self.cooldowns = [dict(cooldowns[0]) if cooldowns else {},
                          dict(cooldowns[1]) if cooldowns else {}]
        self.sealed_round = list(sealed_round if sealed_round is not None else [-1, -1])

    # ── 出招合法性（契约 §1 八条）──
    def is_sealed(self, who):
        return self.sealed_round[who] == self.round

    def can_use_action(self, who, action):
        if who not in (0, 1):
            return False
        if self.round == OPENING_ROUND:            # 1) 开局只准攒气
            return action == ZAN
        if action not in SKILLS:                   # 2) 不在技能表（-1 / 劝降 / 越界）
            return False
        if self.score[who] < UNLOCK.get(action, 0):  # 3) 未解锁（按自己分数）
            return False
        if self.qi[who] < QI_COST.get(action, 0):    # 4) 气不足
            return False
        if action == FANG and self.shield[who] < 1:  # 5) 防御需盾 ≥1
            return False
        if self.is_sealed(who) and action in SEALABLE:  # 6) 封盾禁 FANG/爆气
            return False
        cd = CD.get(action, 0)                       # 7) 冷却中：round > 上次 + CD
        if cd > 0 and self.round <= self.cooldowns[who].get(action, 0) + cd:
            return False
        return True

    def available_actions(self, who):
        return [a for a in SKILLS if self.can_use_action(who, a)]


class Result:
    """回合结算结果（与 GameRules.RoundResult 同字段）。"""

    def __init__(self, actions):
        self.actions = list(actions)
        self.hp_delta = [0, 0]
        self.qd = [0, 0]
        self.sd = [0, 0]
        self.hit = [False, False]
        self.blocked = [False, False]
        self.sealed = [False, False]
        self.quan_jiang = -1
        self.opening = False
        self.text = ""


# ══════════════════════════ §4 结算管线 ══════════════════════════════

def resolve_opening(s):
    """回合 1 亮相：双方攒气，气 +1、盾 +1（各自封顶）。"""
    r = Result([ZAN, ZAN])
    r.opening = True
    r.qd = [1, 1]
    r.sd = [1, 1]
    _apply(s, r)
    return r


def check_winner(s):
    """血量归零判负；双亡判平；40 回合比血（血同判平，不比盾）。"""
    me, you = s.hp[0] <= 0, s.hp[1] <= 0
    if me and you:
        s.winner = 2
    elif you:
        s.winner = 0
    elif me:
        s.winner = 1
    elif s.round >= MAX_ROUND:
        if s.hp[0] > s.hp[1]:
            s.winner = 0
        elif s.hp[1] > s.hp[0]:
            s.winner = 1
        else:
            s.winner = 2


def resolve_turn(s, a0, a1):
    """常规回合：①劝降 ②扣资源 ③吸收 ④增益 ⑤对撞 ⑥CD ⑦落地+终局。"""
    acts = [int(a0), int(a1)]
    r = Result(acts)

    # ① 劝降：满气满血 + 对方仅剩 1 血 → 直接判胜（不占动作 / 不扣资源 / 不进 CD）
    for i in (0, 1):
        if s.qi[i] == MAX_QI and s.hp[i] == MAX_HP and s.hp[1 - i] == 1:
            s.winner = i
            s.pending = [-1, -1]
            r.quan_jiang = i
            r.text = "劝降：%d 胜" % i
            return r

    # 盾 0 时出防御 = 非法出招 → 按「裸防」处理（契约 §2.2 D_bare）
    bare = [(acts[i] == FANG and s.shield[i] < 1) for i in (0, 1)]

    # ② 扣资源
    for i in (0, 1):
        r.qd[i] -= QI_COST.get(acts[i], 0)
        if acts[i] == FANG and s.shield[i] >= 1:
            r.sd[i] -= 1

    # ③ 吸收（先于增益处理：偷走对方增益 / 对方攻击则自己掉 1 血）
    stolen = [False, False]
    for i in (0, 1):
        if acts[i] != XI_SHOU:
            continue
        op = 1 - i
        oa = acts[op]
        if oa == XI_SHOU:            # 吸收 vs 吸收：各花 1 气、互不递归
            continue
        if oa in GAINS:              # 偷走效果、原样照搬
            _gain(s, r, i, oa)
            stolen[op] = True
        elif is_attack(oa):          # 只掉 1 血，攻击其余效果作废
            _hit(r, i, 1)

    # ④ 资源增益（被偷的一方白费）
    for i in (0, 1):
        if acts[i] in GAINS and not stolen[i]:
            _gain(s, r, i, acts[i])

    # ⑤ 对撞矩阵
    _pair(s, r, acts, bare)

    # ⑥ CD：顶招也进 CD（使用成功与否不影响计时）
    for i in (0, 1):
        if CD.get(acts[i], 0) > 0:
            s.cooldowns[i][acts[i]] = s.round

    # ⑦ 落地 + 终局
    _apply(s, r)
    check_winner(s)
    return r


def _apply(s, r):
    """增量落地：气 / 盾 / 血 各自 clamp 到 [0, 上限]；清空 pending。"""
    for i in (0, 1):
        s.qi[i] = clamp(s.qi[i] + r.qd[i], 0, MAX_QI)
        s.shield[i] = clamp(s.shield[i] + r.sd[i], 0, MAX_SHIELD)
        s.hp[i] = clamp(s.hp[i] + r.hp_delta[i], 0, MAX_HP)
    s.pending = [-1, -1]


def _gain(s, r, who, act):
    """资源增益（也被吸收的「原样照搬」复用）。溢出作废，不结转。"""
    if act == ZAN:
        r.qd[who] += 1
        r.sd[who] += 1
    elif act == JI_QI:
        r.qd[who] += 3
    elif act == HUI_FU:
        room = MAX_HP - clamp(s.hp[who] + r.hp_delta[who], 0, MAX_HP)
        r.hp_delta[who] += max(0, min(1, room))
    elif act == BAO_QI:
        r.sd[who] = MAX_SHIELD - s.shield[who]      # 先把盾补满 3，再结算攻击
    # 其余动作无增益


def _hit(r, who, dmg):
    r.hp_delta[who] -= dmg
    r.hit[who] = True


def _eff_shield(s, r, who):
    """结算中的有效盾 = 当前盾 + 本轮已累积盾增量（爆气「先补满再结算」依赖它）。"""
    return clamp(s.shield[who] + r.sd[who], 0, MAX_SHIELD)


def _bao_damage(s, r, victim, k):
    """k 个剩余包子打 victim：每包 2 盾伤；盾被打穿时只掉 1 血。"""
    dmg = k * 2
    eff = _eff_shield(s, r, victim)
    if eff >= dmg:
        r.sd[victim] -= dmg
    else:
        r.sd[victim] -= eff
        r.hp_delta[victim] -= 1
        r.hit[victim] = True


def _block_with_shield(s, r, who):
    """包子 1 连挡小羊 / 2 连挡大羊：盾 ≥1 则耗 1 盾挡下；0 盾挡不住掉 1 血。"""
    if _eff_shield(s, r, who) >= 1:
        r.sd[who] -= 1
        r.blocked[who] = True
    else:
        _hit(r, who, 1)


# ══════════════════════════ §3 对撞矩阵（表驱动）═══════════════════════

def _pair(s, r, acts, bare):
    ka, kb = kind(acts[0]), kind(acts[1])
    if "absorb" in (ka, kb):
        return                                # 吸收已在第 ③ 步独占处理
    if _dual(s, r, acts, ka, kb):
        return                                # 双方都是「攻击类」→ 同时裁决
    if ka in ATTACK_KINDS:
        me, op = 0, 1
    elif kb in ATTACK_KINDS:
        me, op = 1, 0
    else:
        return                                # 防御/增益互撞：无额外伤害
    # 包子在任一座位都要按「包子侧」派发（镜像 resolve.gd 的 is_bao(a)/is_bao(b) 双分支）
    if ka == K_BAO or kb == K_BAO:
        me = 0 if ka == K_BAO else 1
        op = 1 - me
        handler = RULES.get((K_BAO, kind(acts[op])))
        if handler is not None:
            handler(s, r, me, op, acts[me], bare)
        return
    handler = RULES.get((kind(acts[me]), kind(acts[op])))
    if handler is not None:
        handler(s, r, me, op, acts[me], bare)


def _dual(s, r, acts, ka, kb):
    """双方同为攻击类的对撞（包子/破防技/终极技）。"""
    a, b = acts
    if ka == K_BAO and kb == K_BAO:
        m, n = bao_count(a), bao_count(b)
        if m > n:
            _bao_damage(s, r, 1, m - n)       # 一对一抵消，剩余包打对方
        elif n > m:
            _bao_damage(s, r, 0, n - m)
        return True
    if a == ZHONG_JI and b == ZHONG_JI:
        _hit(r, 0, 2)                          # 同时命中，双方各掉 2 血
        _hit(r, 1, 2)
        return True
    if ka in (K_SHEEP, K_BIG) and kb in (K_SHEEP, K_BIG):
        if ka != kb:                           # 大羊赢 → 小羊方吃效果
            _hit(r, 0 if ka == K_SHEEP else 1, 1)
        return True
    if ka in (K_SHEEP, K_BIG) and kb == K_ZHONG:
        _hit(r, 0, 2)                          # 终极技赢
        return True
    if kb in (K_SHEEP, K_BIG) and ka == K_ZHONG:
        _hit(r, 1, 2)
        return True
    return False


# 单侧攻击（主侧 = me，另一侧 = op）的逐条裁决，键为 (主侧分类, 另一侧分类)
def _bao_fang(s, r, me, op, act, bare):
    if bare[op]:
        _hit(r, op, 1)                         # 盾 0 出防御 = 裸防
    elif bao_count(act) >= BAO_MAX:
        _hit(r, op, 1)                         # 3 连破防：掉 1 血、盾不动
    else:
        r.blocked[op] = True                   # 1–2 连被挡（不再额外扣盾）


def _bao_strong(s, r, me, op, act, bare):
    r.blocked[op] = True                        # 加强防御挡一切包子


def _bao_burst(s, r, me, op, act, bare):
    k = bao_count(act) - 1                      # 爆气只挡 1 包
    if k > 0:
        _bao_damage(s, r, op, k)
    else:
        r.blocked[op] = True


def _bao_sheep(s, r, me, op, act, bare):
    n = bao_count(act)
    if n == 1:
        _block_with_shield(s, r, me)            # 1 包 + 1 盾挡下；0 盾 → 掉 1 血
    elif n == 2:
        r.blocked[me] = True                    # 2 连挡下且不掉盾
    else:
        _hit(r, op, 1)                          # 3 连包克制小羊 → 小羊方掉 1 血


def _bao_big(s, r, me, op, act, bare):
    n = bao_count(act)
    if n == 1:
        _hit(r, me, 1)                          # 1 包挡不住
    elif n == 2:
        _block_with_shield(s, r, me)             # 2 包挡下、耗 1 盾；0 盾 → 掉 1 血
    else:
        r.blocked[me] = True                     # 3 连完全挡下


def _bao_zhong(s, r, me, op, act, bare):
    if bao_count(act) >= BAO_MAX:
        r.blocked[me] = True                     # 3 连挡住：包子被吞、终极无效
    else:
        _hit(r, me, 2)                           # 1–2 连挡不住 → 掉 2 血


def _bao_gain(s, r, me, op, act, bare):
    _hit(r, op, 1)                               # 裸防：不论几连包都只掉 1 血


def _br_fang(s, r, me, op, act, bare):
    if bare[op]:
        _hit(r, op, 1)                           # 裸防（盾 0 出防御）→ 1 血
    elif act == XIAO_YANG:
        s.sealed_round[op] = s.round + 1          # 小羊破防：封盾 1 回合、不掉血
        r.sealed[op] = True
    else:
        _hit(r, op, 1)                           # 大羊穿普通防御 → 掉 1 血


def _br_strong(s, r, me, op, act, bare):
    r.blocked[op] = True                         # 加强防御挡一切攻击


def _br_burst(s, r, me, op, act, bare):
    _hit(r, op, 1)                               # 爆气先补满盾，仍照常命中 1 血


def _br_gain(s, r, me, op, act, bare):
    _hit(r, op, 1)                               # 裸防 → 1 血


def _z_fang(s, r, me, op, act, bare):
    _hit(r, op, 2)                               # 终极技无视普通防御 → 2 血


def _z_strong(s, r, me, op, act, bare):
    r.blocked[op] = True                         # 被挡
    r.sd[op] -= _eff_shield(s, r, op)            # …但掉光所有盾


def _z_burst(s, r, me, op, act, bare):
    _hit(r, op, 2)                               # 补满盾照常命中 2 血


def _z_gain(s, r, me, op, act, bare):
    _hit(r, op, 2)                               # 裸防 → 2 血


RULES = {
    (K_BAO, "fang"): _bao_fang,
    (K_BAO, "strong"): _bao_strong,
    (K_BAO, "burst"): _bao_burst,
    (K_BAO, K_SHEEP): _bao_sheep,
    (K_BAO, K_BIG): _bao_big,
    (K_BAO, K_ZHONG): _bao_zhong,
    (K_BAO, "gain"): _bao_gain,
    (K_SHEEP, "fang"): _br_fang,
    (K_SHEEP, "strong"): _br_strong,
    (K_SHEEP, "burst"): _br_burst,
    (K_SHEEP, "gain"): _br_gain,
    (K_BIG, "fang"): _br_fang,
    (K_BIG, "strong"): _br_strong,
    (K_BIG, "burst"): _br_burst,
    (K_BIG, "gain"): _br_gain,
    (K_ZHONG, "fang"): _z_fang,
    (K_ZHONG, "strong"): _z_strong,
    (K_ZHONG, "burst"): _z_burst,
    (K_ZHONG, "gain"): _z_gain,
}


# ══════════════════════════ 断言脚手架 ══════════════════════════════

FAILED = []


def expect(name, cond):
    ok = bool(cond)
    print(("PASS" if ok else "FAIL"), "-", name)
    if not ok:
        FAILED.append(name)
    return ok


def mk(hp=None, qi=None, shield=None, rnd=2, score=None,
       cooldowns=None, sealed_round=None, pending=None):
    return State(hp, qi, shield, rnd, score, cooldowns, sealed_round, pending)


def chk(s, hp, qi, sh):
    return s.hp == hp and s.qi == qi and s.shield == sh


def main():
    ok = True

    # ── ① 开局亮相 ────────────────────────────────────────────────────
    s = State()
    r = resolve_opening(s)
    ok &= expect("[开局] 亮相双方攒气：气[1,1]、盾 3+1 封顶 3、血不动",
                 r.opening and r.actions == [ZAN, ZAN]
                 and chk(s, [4, 4], [1, 1], [3, 3]))

    # ── ② §3.2 包子 vs 包子 ──────────────────────────────────────────
    s = mk(qi=[5, 5])
    resolve_turn(s, BAO1, BAO1)
    ok &= expect("[矩阵·包子vs包子] 1连 vs 1连：一对一抵消",
                 chk(s, [4, 4], [4, 4], [3, 3]))

    s = mk(qi=[5, 5])
    resolve_turn(s, BAO2, BAO1)
    ok &= expect("[矩阵·包子vs包子] 2连 vs 1连：剩余 1 包 = 2 盾伤",
                 chk(s, [4, 4], [3, 4], [3, 1]))

    s = mk(qi=[5, 5])
    resolve_turn(s, BAO3, BAO2)
    ok &= expect("[矩阵·包子vs包子] 3连 vs 2连：剩余 1 包 = 2 盾伤",
                 chk(s, [4, 4], [2, 3], [3, 1]))

    s = mk(qi=[5, 5])
    resolve_turn(s, BAO3, BAO1)
    ok &= expect("[矩阵·包子vs包子] 3连 vs 1连：剩余 2 包 = 4 盾伤 > 盾 3 → 盾清 0、掉 1 血",
                 chk(s, [4, 3], [2, 4], [3, 0]))

    # ── ③ §3.2 包子 vs 普通防御 ──────────────────────────────────────
    s = mk(qi=[5, 5])
    r = resolve_turn(s, BAO1, FANG)
    ok &= expect("[矩阵·包子vs防御] 1连：被挡（防御耗 1 盾、不再额外扣盾）",
                 chk(s, [4, 4], [4, 5], [3, 2]) and bool(r.blocked[1]))

    s = mk(qi=[5, 5])
    resolve_turn(s, BAO2, FANG)
    ok &= expect("[矩阵·包子vs防御] 2连：被挡",
                 chk(s, [4, 4], [3, 5], [3, 2]))

    s = mk(qi=[5, 5])
    resolve_turn(s, BAO3, FANG)
    ok &= expect("[矩阵·包子vs防御] 3连：破防 → 掉 1 血、盾不动（只耗防御的 1）",
                 chk(s, [4, 3], [2, 5], [3, 2]))

    # ── ④ §3.2 包子 vs 加强防御 ──────────────────────────────────────
    s = mk(qi=[5, 5])
    resolve_turn(s, BAO1, STRONG_FANG)
    ok &= expect("[矩阵·包子vs加强防御] 1连：被挡、不耗盾",
                 chk(s, [4, 4], [4, 4], [3, 3]))

    s = mk(qi=[5, 5])
    resolve_turn(s, BAO2, STRONG_FANG)
    ok &= expect("[矩阵·包子vs加强防御] 2连：被挡",
                 chk(s, [4, 4], [3, 4], [3, 3]))

    s = mk(qi=[5, 5])
    resolve_turn(s, BAO3, STRONG_FANG)
    ok &= expect("[矩阵·包子vs加强防御] 3连：被挡（不破防）",
                 chk(s, [4, 4], [2, 4], [3, 3]))

    # ── ⑤ §3.2 包子 vs 爆气 ─────────────────────────────────────────
    s = mk(qi=[5, 5])
    r = resolve_turn(s, BAO1, BAO_QI)
    ok &= expect("[矩阵·包子vs爆气] 1连：被挡（只挡 1 包），爆气先补满盾",
                 chk(s, [4, 4], [4, 4], [3, 3]) and bool(r.blocked[1]))

    s = mk(qi=[5, 5])
    resolve_turn(s, BAO2, BAO_QI)
    ok &= expect("[矩阵·包子vs爆气] 2连：挡 1 剩 1 → 2 盾伤",
                 chk(s, [4, 4], [3, 4], [3, 1]))

    s = mk(qi=[5, 5], shield=[3, 0])
    resolve_turn(s, BAO3, BAO_QI)
    ok &= expect("[矩阵·包子vs爆气] 3连（爆气方 0 盾）：补满 3 再挡 1，剩 2 包 4 盾伤打穿 → 盾清 0、掉 1 血",
                 chk(s, [4, 3], [2, 4], [3, 0]))

    # ── ⑥ §3.2 包子 vs 小羊 ─────────────────────────────────────────
    s = mk(qi=[5, 5])
    r = resolve_turn(s, BAO1, XIAO_YANG)
    ok &= expect("[矩阵·包子vs小羊] 1连：包子方耗 1 盾挡下小羊",
                 chk(s, [4, 4], [4, 4], [2, 3]) and bool(r.blocked[0]))

    s = mk(qi=[5, 5], shield=[0, 3])
    resolve_turn(s, BAO1, XIAO_YANG)
    ok &= expect("[矩阵·包子vs小羊] 1连（包子方 0 盾）：挡不住 → 包子方掉 1 血",
                 chk(s, [3, 4], [4, 4], [0, 3]))

    s = mk(qi=[5, 5])
    resolve_turn(s, BAO2, XIAO_YANG)
    ok &= expect("[矩阵·包子vs小羊] 2连：挡下且不掉盾",
                 chk(s, [4, 4], [3, 4], [3, 3]))

    s = mk(qi=[5, 5])
    resolve_turn(s, BAO3, XIAO_YANG)
    ok &= expect("[矩阵·包子vs小羊] 3连：3 连包克制小羊 → 小羊方掉 1 血，包子方无事",
                 chk(s, [4, 3], [2, 4], [3, 3]))

    # ── ⑥b 反向座位：包子在 1 号位（此前镜像漏派发 → 静默不结算）────────
    s = mk(qi=[5, 5])
    resolve_turn(s, XIAO_YANG, BAO1)
    ok &= expect("[矩阵·反向座位] 小羊(0) vs 1连包(1)：包子方耗 1 盾挡下",
                 chk(s, [4, 4], [4, 4], [3, 2]))

    s = mk(qi=[5, 5], shield=[3, 0])
    resolve_turn(s, XIAO_YANG, BAO1)
    ok &= expect("[矩阵·反向座位] 小羊 vs 1连包（包子方 0 盾）：挡不住 → 包子方掉 1 血",
                 chk(s, [4, 3], [4, 4], [3, 0]))

    s = mk(qi=[5, 5])
    resolve_turn(s, XIAO_YANG, BAO2)
    ok &= expect("[矩阵·反向座位] 小羊 vs 2连包：挡下且不掉盾",
                 chk(s, [4, 4], [4, 3], [3, 3]))

    s = mk(qi=[5, 5])
    resolve_turn(s, XIAO_YANG, BAO3)
    ok &= expect("[矩阵·反向座位] 小羊 vs 3连包：3 连包克制小羊 → 小羊方掉 1 血",
                 chk(s, [3, 4], [4, 2], [3, 3]))

    s = mk(qi=[5, 5])
    resolve_turn(s, DA_YANG, BAO1)
    ok &= expect("[矩阵·反向座位] 大羊 vs 1连包：挡不住 → 包子方掉 1 血",
                 chk(s, [4, 3], [3, 4], [3, 3]))

    s = mk(qi=[5, 5])
    resolve_turn(s, DA_YANG, BAO3)
    ok &= expect("[矩阵·反向座位] 大羊 vs 3连包：完全挡下（不掉盾不掉血）",
                 chk(s, [4, 4], [3, 2], [3, 3]))

    s = mk(qi=[5, 5])
    resolve_turn(s, ZHONG_JI, BAO1)
    ok &= expect("[矩阵·反向座位] 终极技 vs 1连包：挡不住 → 包子方掉 2 血",
                 chk(s, [4, 2], [0, 4], [3, 3]))

    # ── ⑦ §3.2 包子 vs 大羊 ─────────────────────────────────────────
    s = mk(qi=[5, 5])
    resolve_turn(s, BAO1, DA_YANG)
    ok &= expect("[矩阵·包子vs大羊] 1连：挡不住 → 包子方掉 1 血",
                 chk(s, [3, 4], [4, 3], [3, 3]))

    s = mk(qi=[5, 5])
    r = resolve_turn(s, BAO2, DA_YANG)
    ok &= expect("[矩阵·包子vs大羊] 2连：挡下并耗 1 盾",
                 chk(s, [4, 4], [3, 3], [2, 3]) and bool(r.blocked[0]))

    s = mk(qi=[5, 5], shield=[0, 3])
    resolve_turn(s, BAO2, DA_YANG)
    ok &= expect("[矩阵·包子vs大羊] 2连（包子方 0 盾）：挡不住 → 掉 1 血",
                 chk(s, [3, 4], [3, 3], [0, 3]))

    s = mk(qi=[5, 5])
    r = resolve_turn(s, BAO3, DA_YANG)
    ok &= expect("[矩阵·包子vs大羊] 3连：完全挡下（不掉盾不掉血）",
                 chk(s, [4, 4], [2, 3], [3, 3]) and bool(r.blocked[0]))

    # ── ⑧ §3.2 包子 vs 终极技 ───────────────────────────────────────
    s = mk(qi=[5, 5])
    resolve_turn(s, BAO1, ZHONG_JI)
    ok &= expect("[矩阵·包子vs终极技] 1连：挡不住 → 包子方掉 2 血",
                 chk(s, [2, 4], [4, 0], [3, 3]))

    s = mk(qi=[5, 5])
    resolve_turn(s, BAO2, ZHONG_JI)
    ok &= expect("[矩阵·包子vs终极技] 2连：挡不住 → 掉 2 血",
                 chk(s, [2, 4], [3, 0], [3, 3]))

    s = mk(qi=[5, 5])
    r = resolve_turn(s, BAO3, ZHONG_JI)
    ok &= expect("[矩阵·包子vs终极技] 3连：挡住（包子被吞、终极无效）",
                 chk(s, [4, 4], [2, 0], [3, 3]) and bool(r.blocked[0]))

    # ── ⑨ §3.1 裸防 ─────────────────────────────────────────────────
    s = mk(qi=[5, 5])
    resolve_turn(s, BAO1, ZAN)
    ok &= expect("[矩阵·裸防] 1连包 vs 攒气：对方掉 1 血、攒气增益照给",
                 chk(s, [4, 3], [4, 6], [3, 3]))

    s = mk(qi=[5, 5])
    resolve_turn(s, BAO3, JI_QI)
    ok &= expect("[矩阵·裸防] 3连包 vs 集气：仍只掉 1 血（集气 +3 气照给）",
                 chk(s, [4, 3], [2, 8], [3, 3]))

    s = mk(qi=[5, 5])
    resolve_turn(s, BAO2, HUI_FU)
    ok &= expect("[矩阵·裸防] 2连包 vs 回复（满血）：掉 1 血，回复溢出作废",
                 chk(s, [4, 3], [3, 5], [3, 3]))

    # ── ⑩ §3.3 破防技互撞 ───────────────────────────────────────────
    s = mk(qi=[5, 5])
    resolve_turn(s, XIAO_YANG, XIAO_YANG)
    ok &= expect("[矩阵·破防技互撞] 小羊 vs 小羊：互相抵消、双方无效果",
                 chk(s, [4, 4], [4, 4], [3, 3]))

    s = mk(qi=[5, 5])
    resolve_turn(s, DA_YANG, DA_YANG)
    ok &= expect("[矩阵·破防技互撞] 大羊 vs 大羊：互相抵消",
                 chk(s, [4, 4], [3, 3], [3, 3]))

    s = mk(qi=[5, 5])
    resolve_turn(s, XIAO_YANG, DA_YANG)
    ok &= expect("[矩阵·破防技互撞] 小羊 vs 大羊：大羊赢 → 小羊方掉 1 血",
                 chk(s, [3, 4], [4, 3], [3, 3]))

    s = mk(qi=[5, 5])
    resolve_turn(s, XIAO_YANG, ZHONG_JI)
    ok &= expect("[矩阵·破防技互撞] 小羊 vs 终极技：终极技赢 → 小羊方掉 2 血",
                 chk(s, [2, 4], [4, 0], [3, 3]))

    s = mk(qi=[5, 5])
    resolve_turn(s, DA_YANG, ZHONG_JI)
    ok &= expect("[矩阵·破防技互撞] 大羊 vs 终极技：终极技赢 → 大羊方掉 2 血",
                 chk(s, [2, 4], [3, 0], [3, 3]))

    s = mk(qi=[5, 5])
    resolve_turn(s, ZHONG_JI, ZHONG_JI)
    ok &= expect("[矩阵·破防技互撞] 终极技 vs 终极技：双方各掉 2 血、未死则未分",
                 chk(s, [2, 2], [0, 0], [3, 3]) and s.winner == -1)

    # ── ⑪ §3.4 防御类对撞 ───────────────────────────────────────────
    s = mk(qi=[5, 5])
    r = resolve_turn(s, XIAO_YANG, FANG)
    ok &= expect("[矩阵·防御类对撞] 小羊 vs 普通防御：破防 → 封盾 1 回合、不掉血",
                 chk(s, [4, 4], [4, 5], [3, 2])
                 and s.sealed_round == [-1, 3] and bool(r.sealed[1]))

    s = mk(qi=[5, 5])
    resolve_turn(s, DA_YANG, FANG)
    ok &= expect("[矩阵·防御类对撞] 大羊 vs 普通防御：穿防 → 掉 1 血",
                 chk(s, [4, 3], [3, 5], [3, 2]))

    s = mk(qi=[5, 5])
    r = resolve_turn(s, XIAO_YANG, STRONG_FANG)
    ok &= expect("[矩阵·防御类对撞] 小羊 vs 加强防御：被挡（不耗盾不掉血）",
                 chk(s, [4, 4], [4, 4], [3, 3]) and bool(r.blocked[1]))

    s = mk(qi=[5, 5])
    r = resolve_turn(s, DA_YANG, STRONG_FANG)
    ok &= expect("[矩阵·防御类对撞] 大羊 vs 加强防御：被挡",
                 chk(s, [4, 4], [3, 4], [3, 3]) and bool(r.blocked[1]))

    s = mk(qi=[5, 5])
    resolve_turn(s, ZHONG_JI, FANG)
    ok &= expect("[矩阵·防御类对撞] 终极技 vs 普通防御：无视防御 → 掉 2 血",
                 chk(s, [4, 2], [0, 5], [3, 2]))

    s = mk(qi=[5, 5])
    r = resolve_turn(s, ZHONG_JI, STRONG_FANG)
    ok &= expect("[矩阵·防御类对撞] 终极技 vs 加强防御：被挡但掉光所有盾",
                 chk(s, [4, 4], [0, 4], [3, 0]) and bool(r.blocked[1]))

    s = mk(qi=[5, 5], shield=[3, 0])
    resolve_turn(s, XIAO_YANG, BAO_QI)
    ok &= expect("[矩阵·防御类对撞] 小羊 vs 爆气（0 盾）：补满盾照常命中 1 血",
                 chk(s, [4, 3], [4, 4], [3, 3]))

    s = mk(qi=[5, 5], shield=[3, 1])
    resolve_turn(s, DA_YANG, BAO_QI)
    ok &= expect("[矩阵·防御类对撞] 大羊 vs 爆气：补满盾照常命中 1 血",
                 chk(s, [4, 3], [3, 4], [3, 3]))

    s = mk(qi=[5, 5], shield=[3, 0])
    resolve_turn(s, ZHONG_JI, BAO_QI)
    ok &= expect("[矩阵·防御类对撞] 终极技 vs 爆气：补满盾照常命中 2 血",
                 chk(s, [4, 2], [0, 4], [3, 3]))

    # ── ⑫ §3.5 吸收 ─────────────────────────────────────────────────
    s = mk(qi=[4, 4], shield=[1, 3])
    resolve_turn(s, XI_SHOU, ZAN)
    ok &= expect("[矩阵·吸收] vs 攒气：偷 +1 气 +1 盾、对方白费（对方气不加）",
                 chk(s, [4, 4], [4, 4], [2, 3]))

    s = mk(qi=[3, 3])
    resolve_turn(s, XI_SHOU, JI_QI)
    ok &= expect("[矩阵·吸收] vs 集气：偷 +3 气、对方无收益",
                 chk(s, [4, 4], [5, 3], [3, 3]))

    s = mk(hp=[2, 3], qi=[3, 3])
    resolve_turn(s, XI_SHOU, HUI_FU)
    ok &= expect("[矩阵·吸收] vs 回复：偷 +1 血、对方无收益",
                 chk(s, [3, 3], [2, 3], [3, 3]))

    s = mk(qi=[3, 3], shield=[0, 3])
    resolve_turn(s, XI_SHOU, BAO_QI)
    ok &= expect("[矩阵·吸收] vs 爆气：偷「补满盾」、对方无收益",
                 chk(s, [4, 4], [2, 2], [3, 3]))

    s = mk(qi=[3, 3])
    resolve_turn(s, XI_SHOU, BAO1)
    ok &= expect("[矩阵·吸收] vs 包子：吸收方掉 1 血、1 气白花",
                 chk(s, [3, 4], [2, 2], [3, 3]))

    s = mk(qi=[3, 3])
    resolve_turn(s, XI_SHOU, XIAO_YANG)
    ok &= expect("[矩阵·吸收] vs 小羊：吸收方掉 1 血且不被封盾",
                 chk(s, [3, 4], [2, 2], [3, 3]) and s.sealed_round == [-1, -1])

    s = mk(qi=[3, 3])
    resolve_turn(s, XI_SHOU, DA_YANG)
    ok &= expect("[矩阵·吸收] vs 大羊：吸收方掉 1 血",
                 chk(s, [3, 4], [2, 1], [3, 3]))

    s = mk(qi=[3, 6])
    resolve_turn(s, XI_SHOU, ZHONG_JI)
    ok &= expect("[矩阵·吸收] vs 终极技：吸收方只掉 1 血（非 2）",
                 chk(s, [3, 4], [2, 1], [3, 3]))

    s = mk(qi=[3, 3])
    resolve_turn(s, XI_SHOU, FANG)
    ok &= expect("[矩阵·吸收] vs 防御：无事发生、1 气白花（防御照耗 1 盾）",
                 chk(s, [4, 4], [2, 3], [3, 2]))

    s = mk(qi=[3, 3])
    resolve_turn(s, XI_SHOU, STRONG_FANG)
    ok &= expect("[矩阵·吸收] vs 加强防御：无事发生、双方各耗气",
                 chk(s, [4, 4], [2, 2], [3, 3]))

    s = mk(qi=[3, 3])
    resolve_turn(s, XI_SHOU, XI_SHOU)
    ok &= expect("[矩阵·吸收] vs 吸收：双方无事、各花 1 气、不递归",
                 chk(s, [4, 4], [2, 2], [3, 3]))

    # ── ⑬ 隐藏技·劝降 ───────────────────────────────────────────────
    s = mk(hp=[4, 1], qi=[10, 0])
    r = resolve_turn(s, ZHONG_JI, ZAN)
    ok &= expect("[劝降] 满气满血 + 对方 1 血：直接判胜（不扣资源、不进 CD、不占动作）",
                 s.winner == 0 and r.quan_jiang == 0
                 and chk(s, [4, 1], [10, 0], [3, 3])
                 and not s.cooldowns[0])

    s = mk(hp=[4, 1], qi=[9, 0])
    resolve_turn(s, ZAN, ZAN)
    ok &= expect("[劝降] 气不满（9）：不触发", s.winner == -1)

    s = mk(hp=[3, 1], qi=[10, 0])
    resolve_turn(s, ZAN, ZAN)
    ok &= expect("[劝降] 自己血不满（3）：不触发", s.winner == -1)

    s = mk(hp=[4, 2], qi=[10, 0])
    resolve_turn(s, ZAN, ZAN)
    ok &= expect("[劝降] 对方血 >1（2）：不触发", s.winner == -1)

    s = mk(hp=[4, 1], qi=[10, 0], shield=[1, 3])
    r = resolve_turn(s, XI_SHOU, BAO_QI)
    ok &= expect("[劝降] 优先于吸收结算（劝降短路：气/盾均未被改动）",
                 s.winner == 0 and chk(s, [4, 1], [10, 0], [1, 3]))

    # ── ⑭ CD 计时 ───────────────────────────────────────────────────
    s = mk(qi=[10, 10], rnd=8, score=[8, 0], cooldowns=[{XIAO_YANG: 5}, {}])
    ok &= expect("[CD] T=5 用小羊（CD3）→ 第 8 回合仍不可用（T+CD）",
                 not s.can_use_action(0, XIAO_YANG))
    s.round = 9
    ok &= expect("[CD] T=5 用小羊（CD3）→ 第 9 回合可再用（T+CD+1）",
                 s.can_use_action(0, XIAO_YANG))

    s = mk(qi=[10, 10], rnd=3, score=[8, 0])
    ok &= expect("[CD] 开局即计时：CD3 第 3 回合不可用",
                 not s.can_use_action(0, XIAO_YANG) and not s.can_use_action(0, JI_QI))
    s.round = 4
    ok &= expect("[CD] 开局即计时：CD3 第 4 回合首次可用",
                 s.can_use_action(0, XIAO_YANG) and s.can_use_action(0, JI_QI))

    s = mk(qi=[10, 10], rnd=2, score=[8, 0])
    ok &= expect("[CD] 开局即计时：CD1（加强防御）第 2 回合即可用",
                 s.can_use_action(0, STRONG_FANG))

    s = mk(qi=[10, 10], rnd=6, score=[8, 0])
    ok &= expect("[CD] 开局即计时：CD6（大羊）第 6 回合不可用",
                 not s.can_use_action(0, DA_YANG))
    s.round = 7
    ok &= expect("[CD] 开局即计时：CD6（大羊）第 7 回合首次可用",
                 s.can_use_action(0, DA_YANG))

    s = mk(qi=[10, 10], rnd=5, score=[8, 0])
    ok &= expect("[CD] 开局即计时：CD5（终极技）第 5 回合不可用",
                 not s.can_use_action(0, ZHONG_JI))
    s.round = 6
    ok &= expect("[CD] 开局即计时：CD5（终极技）第 6 回合首次可用",
                 s.can_use_action(0, ZHONG_JI))

    s = mk(qi=[10, 10], rnd=8, score=[8, 0])
    ok &= expect("[CD] 开局即计时：CD8（回复）第 8 回合不可用",
                 not s.can_use_action(0, HUI_FU))
    s.round = 9
    ok &= expect("[CD] 开局即计时：CD8（回复）第 9 回合首次可用",
                 s.can_use_action(0, HUI_FU))

    s = mk(qi=[5, 5], rnd=5, score=[8, 8])
    resolve_turn(s, XIAO_YANG, XIAO_YANG)
    ok &= expect("[CD] 顶招也进 CD：小羊 vs 小羊互顶 → 双方均记录第 5 回合",
                 s.cooldowns[0].get(XIAO_YANG) == 5
                 and s.cooldowns[1].get(XIAO_YANG) == 5)
    s.round = 8
    ok &= expect("[CD] 顶招第 8 回合仍不可用（T+CD），第 9 回合才可用",
                 not s.can_use_action(0, XIAO_YANG) and not s.can_use_action(1, XIAO_YANG))
    s.round = 9
    ok &= expect("[CD] 顶招第 9 回合可用（T+CD+1）",
                 s.can_use_action(0, XIAO_YANG) and s.can_use_action(1, XIAO_YANG))

    s = mk(qi=[5, 5], rnd=5, score=[8, 8])
    resolve_turn(s, XIAO_YANG, XIAO_YANG)
    ok &= expect("[CD] 顶招资源照扣：互顶双方各废 1 气",
                 s.qi == [4, 4])

    # ── ⑮ §3.6 封盾 ─────────────────────────────────────────────────
    s = mk(qi=[5, 5], rnd=2, score=[8, 0])
    resolve_turn(s, XIAO_YANG, FANG)
    ok &= expect("[封盾] 写入 sealed_round = 当回合+1，当回合 is_sealed 仍为 False",
                 s.sealed_round[1] == 3 and not s.is_sealed(1))
    s.round = 3
    ok &= expect("[封盾] 次回合 is_sealed 生效",
                 s.is_sealed(1))

    s = mk(qi=[10, 10], shield=[3, 3], rnd=3, score=[8, 8], sealed_round=[3, -1])
    ok &= expect("[封盾] 被封方次回合禁普通防御 / 爆气",
                 not s.can_use_action(0, FANG) and not s.can_use_action(0, BAO_QI))
    ok &= expect("[封盾] 封盾期间加强防御仍可用（封的是盾不是气）",
                 s.can_use_action(0, STRONG_FANG))

    s = mk(qi=[10, 10], shield=[3, 3], rnd=4, score=[8, 8], sealed_round=[3, -1])
    ok &= expect("[封盾] 到期自动失效（round+1 后恢复正常）",
                 s.can_use_action(0, FANG) and s.can_use_action(0, BAO_QI))

    s = mk(qi=[5, 5], shield=[3, 3], rnd=3, score=[8, 0], sealed_round=[-1, 3])
    resolve_turn(s, ZHONG_JI, STRONG_FANG)
    ok &= expect("[封盾] 掉光盾不解除也不延长封盾（终极技 vs 加强防御）",
                 s.shield == [3, 0] and s.sealed_round == [-1, 3])

    s = mk(qi=[5, 5], shield=[3, 3], rnd=3, score=[0, 8], sealed_round=[3, -1])
    resolve_turn(s, ZAN, DA_YANG)
    ok &= expect("[封盾] 封盾期间被大羊命中：照常掉 1 血（封盾不免疫伤害）",
                 chk(s, [3, 4], [6, 3], [3, 3]) and s.sealed_round == [3, -1])

    # ── ⑯ 强断言（删掉实现就变红）────────────────────────────────────
    s = mk(qi=[9, 9], score=[3, 3])
    resolve_turn(s, JI_QI, JI_QI)
    ok &= expect("[强断言] 气封顶 10（9 + 3 不溢出）",
                 s.qi == [10, 10] and s.shield == [3, 3])

    s = mk(qi=[4, 5], shield=[3, 3])
    resolve_turn(s, ZAN, ZAN)
    ok &= expect("[强断言] 盾封顶 3（攒气 +1 不溢出）",
                 s.qi == [5, 6] and s.shield == [3, 3])

    s = mk(hp=[3, 3], qi=[5, 5], score=[7, 7])
    resolve_turn(s, HUI_FU, HUI_FU)
    ok &= expect("[强断言] 血封顶 4（3 + 1 = 4）", s.hp == [4, 4])

    s = mk(hp=[4, 4], qi=[5, 5])
    resolve_turn(s, HUI_FU, BAO1)
    ok &= expect("[强断言] 回复溢出作废：满血出回复再被打 1 血 → 仍掉 1 血（不结转免伤）",
                 chk(s, [3, 4], [5, 4], [3, 3]))

    s = mk(hp=[3, 4], qi=[5, 5])
    resolve_turn(s, HUI_FU, BAO1)
    ok &= expect("[强断言] 增益先于伤害结算：3 血出回复再被打 1 → 净 0（仍 3，非 2）",
                 chk(s, [3, 4], [5, 4], [3, 3]))

    s = mk(hp=[4, 1], qi=[5, 5])
    resolve_turn(s, BAO1, ZAN)
    ok &= expect("[强断言] 对手血归零 → winner=0",
                 s.winner == 0 and chk(s, [4, 0], [4, 6], [3, 3]))

    s = mk(hp=[1, 4], qi=[5, 5])
    resolve_turn(s, ZAN, BAO1)
    ok &= expect("[强断言] 自己血归零 → winner=1",
                 s.winner == 1 and chk(s, [0, 4], [6, 4], [3, 3]))

    s = mk(hp=[2, 2], qi=[5, 5])
    resolve_turn(s, ZHONG_JI, ZHONG_JI)
    ok &= expect("[强断言] 双亡（双终极同时命中）→ winner=2 平局",
                 s.winner == 2 and chk(s, [0, 0], [0, 0], [3, 3]))

    s = mk(hp=[4, 3], qi=[5, 5], rnd=MAX_ROUND)
    resolve_turn(s, ZAN, ZAN)
    ok &= expect("[强断言] 40 回合血多：我胜", s.winner == 0)

    s = mk(hp=[3, 4], qi=[5, 5], rnd=MAX_ROUND)
    resolve_turn(s, ZAN, ZAN)
    ok &= expect("[强断言] 40 回合血少：对手胜", s.winner == 1)

    s = mk(hp=[3, 3], qi=[5, 5], shield=[3, 0], rnd=MAX_ROUND)
    resolve_turn(s, ZAN, ZAN)
    ok &= expect("[强断言] 40 回合血同：平局（盾 3 vs 1 不比盾）",
                 s.winner == 2 and s.shield == [3, 1])

    s = mk(qi=[5, 5], pending=[BAO1, ZAN])
    resolve_turn(s, ZAN, ZAN)
    ok &= expect("[强断言] 结算后 pending 清空（常规路径）",
                 s.pending == [-1, -1])

    s = mk(hp=[4, 1], qi=[10, 0], pending=[BAO1, BAO1])
    resolve_turn(s, BAO1, BAO1)
    ok &= expect("[强断言] 结算后 pending 清空（劝降路径）",
                 s.pending == [-1, -1] and s.winner == 0)

    # ── 裸防兜底：盾 0 出防御 = 非法动作，按 §3.1 裸防结算（契约 D_bare）────
    s = mk(qi=[5, 5], shield=[0, 3])
    resolve_turn(s, FANG, BAO1)
    ok &= expect("[裸防兜底] 0 盾出防御 vs 1连包：防御不生效 → 掉 1 血",
                 chk(s, [3, 4], [5, 4], [0, 3]))

    s = mk(qi=[5, 5], shield=[0, 3])
    resolve_turn(s, FANG, XIAO_YANG)
    ok &= expect("[裸防兜底] 0 盾出防御 vs 小羊：掉 1 血",
                 chk(s, [3, 4], [5, 4], [0, 3]))

    s = mk(qi=[5, 5], shield=[0, 3])
    resolve_turn(s, FANG, ZHONG_JI)
    ok &= expect("[裸防兜底] 0 盾出防御 vs 终极技：掉 2 血",
                 chk(s, [2, 4], [5, 0], [0, 3]))
    fresh = State()
    ok &= expect("[强断言] can_use_action：回合 1 仅攒气可出",
                 fresh.can_use_action(0, ZAN) and fresh.can_use_action(1, ZAN)
                 and not fresh.can_use_action(0, BAO1)
                 and not fresh.can_use_action(0, FANG)
                 and not fresh.can_use_action(1, STRONG_FANG))

    s = mk(qi=[10, 10], rnd=2, score=[WIN_SCORE, WIN_SCORE])
    ok &= expect("[强断言] can_use_action：非法动作值（-1 / 劝降 / 越界）不可用",
                 not s.can_use_action(0, -1) and not s.can_use_action(0, QUAN_JIANG)
                 and not s.can_use_action(0, 14) and not s.can_use_action(0, 99))

    s = mk(qi=[10, 10], rnd=2, score=[0, 0])
    ok &= expect("[强断言] can_use_action：未解锁不可用（0 分仅基础三件套 + 包子）",
                 not s.can_use_action(0, STRONG_FANG)
                 and s.can_use_action(0, ZAN) and s.can_use_action(0, BAO1)
                 and s.can_use_action(0, FANG))

    s = mk(qi=[10, 10], rnd=4, score=[2, 0])
    ok &= expect("[强断言] can_use_action：解锁按自己分数（2 分可用小羊；对手 0 分不可）",
                 s.can_use_action(0, XIAO_YANG) and not s.can_use_action(1, XIAO_YANG))

    s = mk(qi=[10, 10], rnd=4, score=[0, 2])
    ok &= expect("[强断言] can_use_action：解锁只看自己分数（对手 2 分不算我的）",
                 not s.can_use_action(0, XIAO_YANG) and s.can_use_action(1, XIAO_YANG))

    s = mk(qi=[0, 0], rnd=2, score=[WIN_SCORE, 0])
    ok &= expect("[强断言] can_use_action：气不足不可用（0 气禁包子，攒气仍可）",
                 not s.can_use_action(0, BAO1) and s.can_use_action(0, ZAN))

    s = mk(qi=[10, 10], shield=[0, 1], rnd=2, score=[WIN_SCORE, 0])
    ok &= expect("[强断言] can_use_action：盾 0 禁普通防御（盾 1 可）",
                 not s.can_use_action(0, FANG) and s.can_use_action(1, FANG))

    s = mk(qi=[10, 10], rnd=9, score=[WIN_SCORE, 0])
    ok &= expect("[强断言] available_actions：满解锁 + 满气 + 无 CD → 13 个技能全可出",
                 sorted(s.available_actions(0)) == sorted(SKILLS)
                 and len(s.available_actions(0)) == 13)

    s = mk(qi=[10, 10], rnd=2, score=[0, 0])
    ok &= expect("[强断言] available_actions：0 分回合 2 → 仅 5 个基础动作",
                 sorted(s.available_actions(0)) == sorted([ZAN, BAO1, BAO2, BAO3, FANG]))

    print("=" * 52)
    print("ALL PASS" if ok else "HAS FAILURES")
    if not ok:
        print("失败项：")
        for n in FAILED:
            print("  -", n)
    raise SystemExit(0 if ok else 1)


if __name__ == "__main__":
    main()

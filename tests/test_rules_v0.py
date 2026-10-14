#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""冻结规则 v0 结算表校验（与 resolve.gd 同逻辑）。"""
from __future__ import annotations

MAX_QI, MAX_HP, MAX_SHIELD, MAX_ROUND = 5, 5, 3, 40
ZAN, BO, FANG = 0, 1, 2


def clamp(v, lo, hi):
    return max(lo, min(hi, v))


class State:
    def __init__(self):
        self.hp = [MAX_HP, MAX_HP]
        self.qi = [0, 0]
        self.shield = [0, 0]
        self.round = 1
        self.winner = -1


def resolve_opening(s: State):
    r = {"qi": [1, 1], "shield": [MAX_SHIELD - s.shield[0], MAX_SHIELD - s.shield[1]], "hp": [0, 0]}
    apply(s, r)


def resolve_turn(s: State, a0: int, a1: int):
    r = {"qi": [0, 0], "shield": [0, 0], "hp": [0, 0]}
    acts = [a0, a1]
    for i in (0, 1):
        me, op = i, 1 - i
        my, ot = acts[i], acts[1 - i]
        if my == BO:
            r["qi"][me] -= 1
            if ot == ZAN:
                r["hp"][op] -= 1
            elif ot == FANG:
                r["shield"][op] -= 1
    if a0 == ZAN:
        r["qi"][0] += 1
        r["shield"][0] += 1
    if a1 == ZAN:
        r["qi"][1] += 1
        r["shield"][1] += 1
    apply(s, r)
    check_winner(s)


def apply(s: State, r):
    for i in (0, 1):
        s.qi[i] = clamp(s.qi[i] + r["qi"][i], 0, MAX_QI)
        s.shield[i] = clamp(s.shield[i] + r["shield"][i], 0, MAX_SHIELD)
        s.hp[i] = clamp(s.hp[i] + r["hp"][i], 0, MAX_HP)


def check_winner(s: State):
    me_d, you_d = s.hp[0] <= 0, s.hp[1] <= 0
    if me_d and you_d:
        s.winner = 2
    elif you_d:
        s.winner = 0
    elif me_d:
        s.winner = 1
    elif s.round >= MAX_ROUND:
        s.winner = 0 if s.hp[0] > s.hp[1] else (1 if s.hp[1] > s.hp[0] else 2)


def expect(name, cond) -> bool:
    print(("PASS" if cond else "FAIL"), "-", name)
    return bool(cond)


def main() -> None:
    ok = True

    s = State()
    resolve_opening(s)
    ok &= expect("开局：气[1,1] 盾[3,3]", s.qi == [1, 1] and s.shield == [3, 3])

    # 波 vs 攒：我 BO, 对手 ZAN。初始 qi=3,3 shield=3,2
    s = State(); s.qi = [3, 3]; s.shield = [3, 2]; s.round = 2
    resolve_turn(s, BO, ZAN)
    ok &= expect("波vs攒：对手-1血；我 qi3→2；对手 qi3→4 shield2→3",
                 s.hp == [5, 4] and s.qi == [2, 4] and s.shield == [3, 3])

    s = State(); s.qi = [3, 3]; s.shield = [3, 3]; s.round = 2
    resolve_turn(s, BO, ZAN)
    ok &= expect("波vs攒：对手盾3+1封顶3",
                 s.hp == [5, 4] and s.qi == [2, 4] and s.shield == [3, 3])

    # 波 vs 波
    s = State(); s.qi = [3, 3]; s.shield = [3, 3]; s.round = 2
    resolve_turn(s, BO, BO)
    ok &= expect("波vs波：互消 qi→2,2", s.hp == [5, 5] and s.qi == [2, 2] and s.shield == [3, 3])

    # 波 vs 防
    s = State(); s.qi = [3, 3]; s.shield = [3, 3]; s.round = 2
    resolve_turn(s, BO, FANG)
    ok &= expect("波vs防：我 qi→2；对手盾→2",
                 s.hp == [5, 5] and s.qi == [2, 3] and s.shield == [3, 2])

    # 防 vs 攒：空防不扣
    s = State(); s.qi = [1, 1]; s.shield = [3, 1]; s.round = 2
    resolve_turn(s, FANG, ZAN)
    ok &= expect("防vs攒：我盾仍3；对手 qi盾+1",
                 s.hp == [5, 5] and s.qi == [1, 2] and s.shield == [3, 2])

    # 防 vs 防
    s = State(); s.qi = [1, 1]; s.shield = [2, 2]; s.round = 2
    resolve_turn(s, FANG, FANG)
    ok &= expect("防vs防：无事", s.hp == [5, 5] and s.qi == [1, 1] and s.shield == [2, 2])

    # 攒 vs 攒 封顶
    s = State(); s.qi = [4, 5]; s.shield = [3, 3]; s.round = 2
    resolve_turn(s, ZAN, ZAN)
    ok &= expect("攒vs攒：qi封顶5 盾封顶3", s.qi == [5, 5] and s.shield == [3, 3])

    # 击杀 / 被杀
    s = State(); s.hp = [5, 1]; s.qi = [3, 3]; s.shield = [0, 0]; s.round = 2
    resolve_turn(s, BO, ZAN)
    ok &= expect("击杀对手：winner=0", s.winner == 0)

    s = State(); s.hp = [1, 5]; s.qi = [3, 3]; s.shield = [0, 0]; s.round = 2
    resolve_turn(s, ZAN, BO)
    ok &= expect("被击杀：winner=1", s.winner == 1)

    # 双亡（直接置血，测判定）
    s = State(); s.hp = [0, 0]; s.round = 2
    check_winner(s)
    ok &= expect("双亡：平局 winner=2", s.winner == 2)

    # 40 回合
    s = State(); s.hp = [3, 5]; s.round = 40
    check_winner(s)
    ok &= expect("40回合血少：对手胜", s.winner == 1)
    s = State(); s.hp = [4, 4]; s.round = 40
    check_winner(s)
    ok &= expect("40回合血同：平局", s.winner == 2)
    s = State(); s.hp = [5, 2]; s.round = 40
    check_winner(s)
    ok &= expect("40回合血多：我胜", s.winner == 0)

    print("=" * 40)
    print("ALL PASS" if ok else "HAS FAILURES")
    raise SystemExit(0 if ok else 1)


if __name__ == "__main__":
    main()

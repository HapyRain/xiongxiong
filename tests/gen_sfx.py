#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
全量音效与渐进式 BGM 生成器（tests/gen_sfx.py 升级版）
生成列表（全部保存在 assets/audio/，单声道 16-bit PCM WAV，44100Hz）：
  1. 基础与兼容音效（保留原名，增强质感）：
     - clap.wav             : 拍手节奏点（清脆双拍掌声+木鱼底）
     - ding.wav             : 选招锁定提示音
     - hit.wav              : 通用受击重音
     - block.wav            : 通用护盾格挡音
     - zan.wav              : 攒气上行聚气音
  2. 新增开场与 UI 四态交互音：
     - game_start.wav       : 开局号角（课间铃声 + 战鼓咚咚 + 拔刀清响）
     - ui_select.wav        : 技能按下选招清脆音（支持按连击 pitch_scale 升调）
     - ui_deny.wav          : 不可用按钮（CD/未解锁/缺气/封盾）点击拒绝低音
  3. 新增 MOBA 级非对称博弈反馈音：
     - block_success.wav    : 格挡成功方——高亢清脆金属弹反+圣盾共鸣（强正反馈）
     - blocked_rebound.wav  : 被格挡方（攻击受挫）——沉闷撞铁反弹+碎裂低音
     - seal.wav             : 小羊破防封盾——金属锁链缠绕禁锢音
  4. 新增全技能专属演出音效：
     - bao1.wav             : 单包发射与爆裂
     - bao2.wav             : 双包二连发快节奏呼啸
     - bao3.wav             : 三包三连重炮破防轰鸣
     - strong_fang.wav      : 强防重装金钟罩展开音
     - xiao_yang.wav        : 小羊冲角破防音
     - da_yang.wav          : 大羊巨角重锤穿防震击音
     - ji_qi.wav            : 集气三连翡翠能量涌动音
     - xi_shou_ok.wav       : 吸收成功（黑洞虹吸+清脆得手和弦）
     - xi_shou_fail.wav     : 吸收失败反噬（漩涡崩裂+受击闷响）
     - bao_qi.wav           : 爆气护盾瞬满冲击波
     - hui_fu.wav           : 回复生命治愈圣咏泛音
     - zhong_ji.wav         : 终极技雷霆重炮贯穿轰鸣
     - quan_jiang.wav       : 劝降皇印砸落+胜利凯歌号角
  5. 新增随回合递进的循环对战 BGM：
     - bgm_battle.wav       : 8 小节无缝循环律动 BGM（125 BPM 基础，游戏内随回合/残血动态提升 pitch_scale 制造紧绷感）
"""
from __future__ import annotations
import math
import random
import struct
import wave
from pathlib import Path

SR = 44100
ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "audio"

random.seed(42)


def write_wav(name: str, samples: list[float]) -> None:
    path = OUT / name
    with wave.open(str(path), "w") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        frames = b"".join(
            struct.pack("<h", max(-32767, min(32767, int(s * 32767)))) for s in samples
        )
        w.writeframes(frames)
    print(f"wrote {path.name:20s} ({len(samples)/SR:.2f}s)")


def env(i: int, n: int, a: float = 0.003, r: float = 0.06) -> float:
    t = i / SR
    total = n / SR
    at = max(a, 1e-4)
    rt = max(r, 1e-4)
    if t < at:
        return t / at
    if t > total - rt:
        return max(0.0, (total - t) / rt)
    return 1.0


def clap(dur: float = 0.10) -> list[float]:
    n = int(SR * dur)
    out = []
    for i in range(n):
        t = i / SR
        e = env(i, n, 0.001, 0.05)
        noise = (math.sin(t * 9200) * 0.38 + math.sin(t * 4400 + 1.1) * 0.35
                 + math.sin(t * 15500) * 0.22)
        wood = math.sin(2 * math.pi * 680 * t) * math.exp(-t * 45) * 0.45
        kick = math.sin(2 * math.pi * 170 * t) * math.exp(-t * 38) * 0.45
        out.append((noise * e * 0.50 + wood + kick) * 0.85)
    return out


def ding(freq: float = 920.0, dur: float = 0.20) -> list[float]:
    n = int(SR * dur)
    out = []
    for i in range(n):
        t = i / SR
        e = math.exp(-t * 11) * env(i, n, 0.002, 0.04)
        s = (math.sin(2 * math.pi * freq * t) * 0.55
             + math.sin(2 * math.pi * freq * 2.0 * t) * 0.22
             + math.sin(2 * math.pi * freq * 1.5 * t) * 0.14)
        out.append(s * e * 0.75)
    return out


def ui_select(dur: float = 0.11) -> list[float]:
    n = int(SR * dur)
    out = []
    for i in range(n):
        t = i / SR
        e = math.exp(-t * 22) * env(i, n, 0.001, 0.03)
        f = 740.0 if t < 0.035 else 1110.0
        s = math.sin(2 * math.pi * f * t) * 0.6 + math.sin(2 * math.pi * f * 2 * t) * 0.25
        out.append(s * e * 0.72)
    return out


def ui_deny(dur: float = 0.16) -> list[float]:
    n = int(SR * dur)
    out = []
    for i in range(n):
        t = i / SR
        e = env(i, n, 0.002, 0.04) * math.exp(-t * 10)
        f = 210.0 if t < 0.07 else 155.0
        buzz = math.sin(2 * math.pi * f * t) * 0.55 + math.sin(2 * math.pi * f * 3 * t) * 0.30
        out.append(buzz * e * 0.75)
    return out


def game_start(dur: float = 0.68) -> list[float]:
    n = int(SR * dur)
    out = []
    notes = [(0.0, 523.25), (0.12, 659.25), (0.24, 783.99), (0.36, 1046.50)]
    for i in range(n):
        t = i / SR
        e = env(i, n, 0.005, 0.12)
        val = 0.0
        # 战鼓重拍
        if t < 0.18:
            val += math.sin(2 * math.pi * (140 - t * 300) * t) * math.exp(-t * 18) * 0.65
        if 0.34 <= t < 0.55:
            dt = t - 0.34
            val += math.sin(2 * math.pi * (160 - dt * 320) * dt) * math.exp(-dt * 15) * 0.70
        # 铜铃琶音号角
        for st, f in notes:
            if t >= st:
                dt = t - st
                ne = math.exp(-dt * 6.5)
                val += (math.sin(2 * math.pi * f * dt) * 0.38
                        + math.sin(2 * math.pi * f * 2 * dt) * 0.16
                        + math.sin(2 * math.pi * f * 3 * dt) * 0.08) * ne
        out.append(max(-0.95, min(0.95, val * e * 0.85)))
    return out


def hit(dur: float = 0.18) -> list[float]:
    n = int(SR * dur)
    out = []
    for i in range(n):
        t = i / SR
        e = math.exp(-t * 16)
        thud = math.sin(2 * math.pi * (135 - t * 85) * t) * 0.72
        crack = math.sin(t * 7500 + math.sin(t * 1200) * 3) * math.exp(-t * 42) * 0.38
        out.append((thud + crack) * e * 0.85)
    return out


def block(dur: float = 0.20) -> list[float]:
    n = int(SR * dur)
    out = []
    for i in range(n):
        t = i / SR
        e = math.exp(-t * 13)
        metal = math.sin(2 * math.pi * 560 * t) * 0.42 + math.sin(2 * math.pi * 840 * t) * 0.32
        noise = math.sin(t * 3800) * 0.15
        out.append((metal + noise) * e * 0.78)
    return out


def block_success(dur: float = 0.36) -> list[float]:
    """格挡成功方：清脆金属弹反 + 圣盾高亢共鸣和弦（强正反馈）"""
    n = int(SR * dur)
    out = []
    for i in range(n):
        t = i / SR
        e = env(i, n, 0.001, 0.08)
        # 初始金属锵声
        clang = (math.sin(2 * math.pi * 1320 * t) * 0.45
                 + math.sin(2 * math.pi * 1980 * t) * 0.30) * math.exp(-t * 18)
        # 随后扬起的正向大三和弦共鸣 (A5 - C#6 - E6)
        shimmer = 0.0
        if t >= 0.03:
            dt = t - 0.03
            se = math.exp(-dt * 6.5)
            shimmer = (math.sin(2 * math.pi * 880 * dt) * 0.30
                       + math.sin(2 * math.pi * 1108.7 * dt) * 0.25
                       + math.sin(2 * math.pi * 1318.5 * dt) * 0.25) * se
        out.append(max(-0.95, min(0.95, (clang + shimmer) * e * 0.88)))
    return out


def blocked_rebound(dur: float = 0.28) -> list[float]:
    """被格挡方：撞铁反弹 + 音高下坠受挫音"""
    n = int(SR * dur)
    out = []
    for i in range(n):
        t = i / SR
        e = env(i, n, 0.001, 0.06) * math.exp(-t * 9.5)
        # 撞击闷响 + 下滑音 (440Hz -> 160Hz)
        f = max(140.0, 440.0 - t * 1100.0)
        recoil = math.sin(2 * math.pi * f * t) * 0.55 + math.sin(2 * math.pi * (f * 1.41) * t) * 0.30
        clatter = math.sin(t * 5400) * math.exp(-t * 32) * 0.35
        out.append(max(-0.95, min(0.95, (recoil + clatter) * e * 0.82)))
    return out


def zan(dur: float = 0.22) -> list[float]:
    n = int(SR * dur)
    out = []
    for i in range(n):
        t = i / SR
        e = math.exp(-t * 7.5) * env(i, n, 0.008, 0.06)
        f = 420 + t * 680
        s = math.sin(2 * math.pi * f * t) * 0.52 + math.sin(2 * math.pi * f * 2 * t) * 0.18
        out.append(s * e * 0.72)
    return out


def bao_shot(count: int) -> list[float]:
    """包子 1/2/3 连发专属音效"""
    dur = 0.18 + count * 0.09
    n = int(SR * dur)
    out = [0.0] * n
    for k in range(count):
        offset = int(k * 0.085 * SR)
        base_f = 280.0 + k * 75.0
        for i in range(offset, n):
            dt = (i - offset) / SR
            if dt > 0.20:
                break
            e = math.exp(-dt * 15)
            whoosh = math.sin(2 * math.pi * (base_f + dt * 520) * dt) * 0.48
            pop = math.sin(2 * math.pi * (160 - dt * 400) * dt) * math.exp(-dt * 28) * 0.55
            out[i] = max(-0.95, min(0.95, out[i] + (whoosh + pop) * e * 0.78))
    return out


def strong_fang(dur: float = 0.28) -> list[float]:
    n = int(SR * dur)
    out = []
    for i in range(n):
        t = i / SR
        e = math.exp(-t * 8.5) * env(i, n, 0.002, 0.06)
        bell = (math.sin(2 * math.pi * 660 * t) * 0.40
                + math.sin(2 * math.pi * 990 * t) * 0.30
                + math.sin(2 * math.pi * 1320 * t) * 0.20)
        sub = math.sin(2 * math.pi * 220 * t) * math.exp(-t * 16) * 0.35
        out.append((bell + sub) * e * 0.82)
    return out


def xiao_yang(dur: float = 0.26) -> list[float]:
    n = int(SR * dur)
    out = []
    for i in range(n):
        t = i / SR
        e = math.exp(-t * 10) * env(i, n, 0.002, 0.05)
        f = 320 + math.sin(t * 45) * 90 + t * 300
        horn = math.sin(2 * math.pi * f * t) * 0.50 + math.sin(2 * math.pi * f * 2 * t) * 0.28
        crack = math.sin(t * 6800) * math.exp(-t * 30) * 0.30
        out.append((horn + crack) * e * 0.80)
    return out


def seal_sfx(dur: float = 0.32) -> list[float]:
    """封盾锁链声"""
    n = int(SR * dur)
    out = []
    for i in range(n):
        t = i / SR
        e = env(i, n, 0.001, 0.06)
        link1 = math.sin(2 * math.pi * 1480 * t) * math.exp(-t * 25) * 0.45
        link2 = math.sin(2 * math.pi * 1120 * max(0.0, t - 0.09)) * math.exp(-max(0.0, t - 0.09) * 22) * (0.45 if t >= 0.09 else 0.0)
        lock = math.sin(2 * math.pi * 240 * max(0.0, t - 0.16)) * math.exp(-max(0.0, t - 0.16) * 18) * (0.55 if t >= 0.16 else 0.0)
        out.append(max(-0.95, min(0.95, (link1 + link2 + lock) * e * 0.85)))
    return out


def da_yang(dur: float = 0.35) -> list[float]:
    n = int(SR * dur)
    out = []
    for i in range(n):
        t = i / SR
        e = math.exp(-t * 8.0) * env(i, n, 0.002, 0.07)
        roar = math.sin(2 * math.pi * (110 - t * 40) * t) * 0.65
        pierce = math.sin(2 * math.pi * (480 - t * 600) * t) * math.exp(-t * 14) * 0.45
        shatter = math.sin(t * 8400 + math.sin(t * 900) * 4) * math.exp(-t * 22) * 0.35
        out.append(max(-0.95, min(0.95, (roar + pierce + shatter) * e * 0.88)))
    return out


def ji_qi(dur: float = 0.34) -> list[float]:
    n = int(SR * dur)
    out = []
    freqs = [440.0, 554.37, 659.25, 880.0]
    for i in range(n):
        t = i / SR
        e = env(i, n, 0.005, 0.08)
        idx = min(3, int(t / 0.075))
        f = freqs[idx]
        s = math.sin(2 * math.pi * f * t) * 0.50 + math.sin(2 * math.pi * f * 2 * t) * 0.22
        out.append(s * e * 0.76)
    return out


def xi_shou_ok(dur: float = 0.38) -> list[float]:
    """吸收成功：漩涡吸入 + 璀璨得手音"""
    n = int(SR * dur)
    out = []
    for i in range(n):
        t = i / SR
        e = env(i, n, 0.004, 0.08)
        if t < 0.18:
            f = 680 - t * 1800
            vortex = math.sin(2 * math.pi * max(180.0, f) * t) * 0.55
            out.append(vortex * e * 0.80)
        else:
            dt = t - 0.18
            se = math.exp(-dt * 8.0)
            chime = (math.sin(2 * math.pi * 784.0 * dt) * 0.42
                     + math.sin(2 * math.pi * 987.77 * dt) * 0.32
                     + math.sin(2 * math.pi * 1174.66 * dt) * 0.26) * se
            out.append(chime * e * 0.85)
    return out


def xi_shou_fail(dur: float = 0.32) -> list[float]:
    """吸收失败受击：漩涡崩裂反噬"""
    n = int(SR * dur)
    out = []
    for i in range(n):
        t = i / SR
        e = env(i, n, 0.002, 0.06) * math.exp(-t * 9.0)
        f = 520 - t * 1200
        warble = math.sin(2 * math.pi * max(90.0, f) * t + math.sin(t * 90) * 2.5) * 0.55
        crack = math.sin(t * 6200) * math.exp(-t * 25) * 0.40
        out.append(max(-0.95, min(0.95, (warble + crack) * e * 0.85)))
    return out


def bao_qi(dur: float = 0.30) -> list[float]:
    n = int(SR * dur)
    out = []
    for i in range(n):
        t = i / SR
        e = env(i, n, 0.002, 0.07) * math.exp(-t * 7.5)
        burst = math.sin(2 * math.pi * (240 + t * 900) * t) * 0.50
        ring = math.sin(2 * math.pi * 720 * t) * 0.32
        out.append((burst + ring) * e * 0.82)
    return out


def hui_fu(dur: float = 0.38) -> list[float]:
    n = int(SR * dur)
    out = []
    for i in range(n):
        t = i / SR
        e = env(i, n, 0.01, 0.10) * math.exp(-t * 5.5)
        f = 523.25 if t < 0.14 else 659.25 if t < 0.26 else 783.99
        s = math.sin(2 * math.pi * f * t) * 0.48 + math.sin(2 * math.pi * f * 2 * t) * 0.20
        out.append(s * e * 0.75)
    return out


def zhong_ji(dur: float = 0.55) -> list[float]:
    """终极技：雷霆蓄力 + 毁天灭地重炮轰鸣"""
    n = int(SR * dur)
    out = []
    for i in range(n):
        t = i / SR
        e = env(i, n, 0.002, 0.12)
        if t < 0.12:
            # 雷电蓄力高音
            charge = math.sin(2 * math.pi * (400 + t * 3200) * t) * 0.55
            out.append(charge * e * 0.80)
        else:
            dt = t - 0.12
            be = math.exp(-dt * 5.2)
            sub = math.sin(2 * math.pi * max(55.0, 140 - dt * 180) * dt) * 0.65
            thunder = math.sin(dt * 9500 + math.sin(dt * 450) * 6) * math.exp(-dt * 12) * 0.42
            beam = math.sin(2 * math.pi * 330 * dt) * 0.25
            out.append(max(-0.95, min(0.95, (sub + thunder + beam) * be * e * 0.92)))
    return out


def quan_jiang(dur: float = 0.65) -> list[float]:
    """劝降：金印砸落 + 皇家号角"""
    n = int(SR * dur)
    out = []
    chord = [523.25, 659.25, 783.99, 1046.50]
    for i in range(n):
        t = i / SR
        e = env(i, n, 0.003, 0.14)
        stamp = math.sin(2 * math.pi * max(60.0, 180 - t * 400) * t) * math.exp(-t * 16) * 0.65
        horn = sum(math.sin(2 * math.pi * f * t) for f in chord) * 0.18 * math.exp(-t * 3.5)
        out.append(max(-0.95, min(0.95, (stamp + horn) * e * 0.90)))
    return out


def bgm_battle() -> list[float]:
    """
    8 小节无缝循环课间对决 BGM（125 BPM，1 拍 = 0.48s，16 拍 = 7.68s）。
    对局内随回合推进动态上调 pitch_scale（1.00 -> 1.25），越到后期越紧绷！
    """
    bpm = 125.0
    beat_sec = 60.0 / bpm          # 0.48s
    step_sec = beat_sec / 2.0      # 8分音符 = 0.24s
    total_steps = 32               # 16 拍 = 7.68s
    dur = total_steps * step_sec
    n = int(SR * dur)
    out = [0.0] * n

    # A小调五声战斗律动低音与旋律 (A2=110, C3=130.81, D3=146.83, E3=164.81, G3=196.0)
    bass_seq = [
        110.0, 110.0, 130.81, 110.0,  146.83, 146.83, 130.81, 110.0,
        110.0, 110.0, 164.81, 146.83, 130.81, 146.83, 164.81, 196.0,
        110.0, 110.0, 130.81, 146.83, 164.81, 164.81, 146.83, 130.81,
        146.83, 130.81, 110.0, 98.0,  110.0, 130.81, 164.81, 110.0,
    ]
    lead_seq = [
        440.0, 0.0, 523.25, 440.0,    587.33, 0.0, 523.25, 440.0,
        659.25, 0.0, 587.33, 523.25,  440.0, 523.25, 659.25, 0.0,
        440.0, 523.25, 587.33, 0.0,   659.25, 587.33, 523.25, 440.0,
        587.33, 523.25, 440.0, 392.0, 440.0, 0.0, 440.0, 0.0,
    ]

    for step in range(total_steps):
        st_idx = int(step * step_sec * SR)
        ed_idx = min(n, int((step + 1) * step_sec * SR))
        bf = bass_seq[step]
        lf = lead_seq[step]
        is_kick = (step % 2 == 0)
        is_clap = (step % 4 == 2)
        for i in range(st_idx, ed_idx):
            dt = (i - st_idx) / SR
            val = 0.0
            # 脉冲 Bass
            be = math.exp(-dt * 9.5)
            val += (math.sin(2 * math.pi * bf * dt) * 0.32
                    + math.sin(2 * math.pi * bf * 2 * dt) * 0.14) * be
            # 轻快芯片感主旋律
            if lf > 0.0:
                le = math.exp(-dt * 7.0)
                val += (math.sin(2 * math.pi * lf * dt) * 0.18
                        + math.sin(2 * math.pi * lf * 1.5 * dt) * 0.06) * le
            # 底鼓与课间拍手节拍
            if is_kick and dt < 0.12:
                val += math.sin(2 * math.pi * (130 - dt * 500) * dt) * math.exp(-dt * 28) * 0.30
            if is_clap and dt < 0.08:
                val += math.sin(dt * 8200) * math.exp(-dt * 45) * 0.16
            out[i] = max(-0.92, min(0.92, val * 0.65))
    return out


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    # 基础 5 音效
    write_wav("clap.wav", clap())
    write_wav("ding.wav", ding(920, 0.20))
    write_wav("hit.wav", hit())
    write_wav("block.wav", block())
    write_wav("zan.wav", zan())
    # 新增开场、UI 四态、MOBA 格挡正负反馈、封盾与全技能专属音效
    write_wav("game_start.wav", game_start())
    write_wav("ui_select.wav", ui_select())
    write_wav("ui_deny.wav", ui_deny())
    write_wav("block_success.wav", block_success())
    write_wav("blocked_rebound.wav", blocked_rebound())
    write_wav("seal.wav", seal_sfx())
    write_wav("bao1.wav", bao_shot(1))
    write_wav("bao2.wav", bao_shot(2))
    write_wav("bao3.wav", bao_shot(3))
    write_wav("strong_fang.wav", strong_fang())
    write_wav("xiao_yang.wav", xiao_yang())
    write_wav("da_yang.wav", da_yang())
    write_wav("ji_qi.wav", ji_qi())
    write_wav("xi_shou_ok.wav", xi_shou_ok())
    write_wav("xi_shou_fail.wav", xi_shou_fail())
    write_wav("bao_qi.wav", bao_qi())
    write_wav("hui_fu.wav", hui_fu())
    write_wav("zhong_ji.wav", zhong_ji())
    write_wav("quan_jiang.wav", quan_jiang())
    write_wav("bgm_battle.wav", bgm_battle())


if __name__ == "__main__":
    main()

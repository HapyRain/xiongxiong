#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""生成 demo 音效：拍手 x1（两拍可复用）、亮招、命中、格挡、攒气。纯标准库。"""
from __future__ import annotations
import math
import struct
import wave
from pathlib import Path

SR = 44100
OUT = Path(r"D:\xiongxiong\xiongxiong\assets\audio")


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
    print("wrote", path, "samples", len(samples))


def env(i: int, n: int, a: float = 0.002, r: float = 0.08) -> float:
    t = i / SR
    total = n / SR
    at = max(a, 1e-4)
    rt = max(r, 1e-4)
    if t < at:
        return t / at
    if t > total - rt:
        return max(0.0, (total - t) / rt)
    return 1.0


def clap(dur: float = 0.09) -> list[float]:
    n = int(SR * dur)
    out = []
    # 两次微噪声叠成「啪」
    for i in range(n):
        t = i / SR
        e = env(i, n, 0.001, 0.05)
        noise = (math.sin(t * 9000) * 0.4 + math.sin(t * 4200 + 1.3) * 0.35
                 + math.sin(t * 16000) * 0.2)
        # 低频冲击
        kick = math.sin(2 * math.pi * 180 * t) * math.exp(-t * 40) * 0.5
        out.append((noise * e * 0.55 + kick * e) * 0.85)
    return out


def ding(freq: float = 880.0, dur: float = 0.22) -> list[float]:
    n = int(SR * dur)
    out = []
    for i in range(n):
        t = i / SR
        e = math.exp(-t * 10) * env(i, n, 0.003, 0.05)
        s = math.sin(2 * math.pi * freq * t) * 0.55
        s += math.sin(2 * math.pi * freq * 2 * t) * 0.2
        s += math.sin(2 * math.pi * freq * 1.5 * t) * 0.12
        out.append(s * e * 0.7)
    return out


def hit(dur: float = 0.16) -> list[float]:
    n = int(SR * dur)
    out = []
    for i in range(n):
        t = i / SR
        e = math.exp(-t * 18)
        thud = math.sin(2 * math.pi * (120 - t * 80) * t) * 0.7
        crack = math.sin(t * 7000) * math.exp(-t * 50) * 0.35
        out.append((thud + crack) * e * 0.8)
    return out


def block(dur: float = 0.18) -> list[float]:
    n = int(SR * dur)
    out = []
    for i in range(n):
        t = i / SR
        e = math.exp(-t * 14)
        metal = math.sin(2 * math.pi * 520 * t) * 0.4 + math.sin(2 * math.pi * 780 * t) * 0.3
        noise = math.sin(t * 3500) * 0.15
        out.append((metal + noise) * e * 0.75)
    return out


def zan(dur: float = 0.2) -> list[float]:
    n = int(SR * dur)
    out = []
    for i in range(n):
        t = i / SR
        e = math.exp(-t * 8) * env(i, n, 0.01, 0.08)
        # 上行小滑音
        f = 420 + t * 600
        s = math.sin(2 * math.pi * f * t) * 0.5 + math.sin(2 * math.pi * f * 2 * t) * 0.15
        out.append(s * e * 0.65)
    return out


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    write_wav("clap.wav", clap())
    write_wav("ding.wav", ding(920, 0.2))
    write_wav("hit.wav", hit())
    write_wav("block.wav", block())
    write_wav("zan.wav", zan())


if __name__ == "__main__":
    main()

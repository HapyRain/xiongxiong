## battle_tempo.gd
## 对局节奏（加速版）：
##   0s 滴 → +0.5s 滴 → 纯输入窗 2.85s 后封盘(0.1s) → 结算
##   结算卡停留 0.8s 再进下一回合
## 每 5 回合：输入窗等比缩短 0.12s（整局变快，不是提前锁按钮）
## 新局 round=1 自然重置。
class_name BattleTempo
extends RefCounted

const CLAP2_DELAY := 0.5
## 纯输入窗（不含封盘 0.1s）
const BASE_INPUT_SEC := 2.85
const LOCK_LEAD := 0.1
const RESULT_HOLD := 0.8
const ROUND_STEP := 5
const INPUT_STEP := 0.12
const MIN_INPUT_SEC := 1.2


static func _tier(round_no: int) -> int:
	return maxi(0, (maxi(1, round_no) - 1) / ROUND_STEP)


## 第二声相对第一声（随局数略加快）
static func clap2_at(round_no: int) -> float:
	return maxf(0.22, CLAP2_DELAY - 0.02 * _tier(round_no))


## 纯输入窗结束（封盘时刻）——思考时间，每 5 回合 -0.12s
static func lock_time(round_no: int) -> float:
	return maxf(MIN_INPUT_SEC, BASE_INPUT_SEC - INPUT_STEP * _tier(round_no))


## 统一结算 = 输入窗 + 封盘 0.1s（总时长一起变短）
static func settle_time(round_no: int) -> float:
	return lock_time(round_no) + LOCK_LEAD


## 整窗
static func total_window(round_no: int) -> float:
	return settle_time(round_no) + 0.05


## 结算画面停留
static func result_hold() -> float:
	return RESULT_HOLD


## 音效/动画加速
static func speed_scale(round_no: int) -> float:
	return 1.0 + 0.08 * float(_tier(round_no))


## 拍声音拉长
static func clap_pitch(round_no: int) -> float:
	return maxf(0.72, 0.78 - 0.025 * _tier(round_no))

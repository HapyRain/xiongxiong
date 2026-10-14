## fps_guard.gd
## 帧率 / VSync / 刷新率自适配。纯静态工具，不读规则、不读 UI。
## 对应 docs/arch/quality-performance-tiers.md §3
class_name FpsGuard
extends RefCounted

const FALLBACK_REFRESH := 60.0
const FPS_SEGMENTS: Array[int] = [30, 60, 90, 120]


## 当前屏幕刷新率；失败/无效时兜底 60。
static func get_refresh_rate() -> float:
	var r := DisplayServer.screen_get_refresh_rate()
	if r <= 0.0:
		return FALLBACK_REFRESH
	return r


## 高档可达帧率：按刷新率取 120 / 90 / 60。
static func resolve_high_fps() -> int:
	var r := get_refresh_rate()
	if r >= 120.0:
		return 120
	if r >= 90.0:
		return 90
	return 60


## 把任意目标帧率吸附到 30/60/90/120 分段（取不超过目标的最近档；目标低于 30 时取 30）。
static func snap_to_segment(target: int) -> int:
	if target <= 30:
		return 30
	var best := 30
	for seg: int in FPS_SEGMENTS:
		if seg <= target:
			best = seg
	return best


## 应用帧率上限 + VSync。返回实际生效的 max_fps。
## vsync 开启时不会把 max_fps 设到超过刷新率（否则无意义且可能抖动）。
static func apply(target_fps: int, vsync_mode: int = DisplayServer.VSYNC_ENABLED) -> int:
	var mode: int = vsync_mode
	DisplayServer.window_set_vsync_mode(mode)
	# 某些平台不支持 Adaptive/Mailbox 会回退，读回真实值再定 max_fps
	mode = DisplayServer.window_get_vsync_mode()

	var cap := snap_to_segment(target_fps)
	if mode != DisplayServer.VSYNC_DISABLED:
		var refresh := get_refresh_rate()
		if float(cap) > refresh:
			cap = snap_to_segment(int(refresh))
	Engine.max_fps = cap
	return cap


## 诊断用快照。
static func snapshot() -> Dictionary:
	return {
		"refresh_rate": get_refresh_rate(),
		"max_fps": Engine.max_fps,
		"vsync_mode": DisplayServer.window_get_vsync_mode(),
		"fps": Engine.get_frames_per_second(),
		"high_capable": resolve_high_fps(),
	}

## websocket_provider.gd
## 抖音 / 远程对局后端预留桩。本迭代不实现，全部方法抛 not-implemented。
## 迁移时保持 NetworkProvider 接口与 Dictionary 信封不变即可替换。
class_name WebSocketProvider
extends NetworkProvider


func open_as_host(_opts: Dictionary) -> Error:
	push_error("WebSocketProvider not implemented (douyin reserved)")
	return ERR_UNAVAILABLE


func open_as_client(_opts: Dictionary) -> Error:
	push_error("WebSocketProvider not implemented (douyin reserved)")
	return ERR_UNAVAILABLE


func close() -> void:
	pass


func poll(_delta: float) -> void:
	pass


func start_discover(_timeout_sec: float) -> Error:
	push_error("WebSocketProvider.start_discover not implemented")
	return ERR_UNAVAILABLE


func stop_discover() -> void:
	pass


func get_local_endpoints() -> PackedStringArray:
	return PackedStringArray()


func send_reliable(_to_id: int, _data: Dictionary) -> Error:
	push_error("WebSocketProvider.send_reliable not implemented")
	return ERR_UNAVAILABLE


func send_unreliable(_to_id: int, _data: Dictionary) -> Error:
	push_error("WebSocketProvider.send_unreliable not implemented")
	return ERR_UNAVAILABLE


func is_host() -> bool:
	return false


func get_unique_id() -> int:
	return 0


func get_rtt_ms(_to_id: int) -> int:
	return -1

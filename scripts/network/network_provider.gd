## network_provider.gd
## 传输后端抽象接口。PeerManager 只依赖本接口，不感知 ENet / WS / 热座差异。
## 消息为 Dictionary 信封（见 peer_manager.gd），不用 MultiplayerSynchronizer。
class_name NetworkProvider
extends RefCounted

signal connected(peer_id: int)
signal disconnected(reason: String)
signal packet_received(from_id: int, data: Dictionary)
signal discovered_room(info: Dictionary)


## 建房。opts: {port, max_players, token, room_name, bind_address?}
func open_as_host(_opts: Dictionary) -> Error:
	return ERR_UNAVAILABLE


## 加入。opts: {address, port, token} 或 {url, token}
func open_as_client(_opts: Dictionary) -> Error:
	return ERR_UNAVAILABLE


func close() -> void:
	pass


## 由 PeerManager 每帧调用；无网络后端可空实现。
func poll(_delta: float) -> void:
	pass


func start_discover(_timeout_sec: float) -> Error:
	return ERR_UNAVAILABLE


func stop_discover() -> void:
	pass


func get_local_endpoints() -> PackedStringArray:
	return PackedStringArray()


## to_id=0 表示广播；本迭代 demo 全走可靠通道。
func send_reliable(_to_id: int, _data: Dictionary) -> Error:
	return ERR_UNAVAILABLE


func send_unreliable(to_id: int, data: Dictionary) -> Error:
	return send_reliable(to_id, data)


func is_host() -> bool:
	return false


func get_unique_id() -> int:
	return 0


## 当前已连接的对端 id 列表（不含自己）。
func get_peer_ids() -> Array:
	return []


## 可选：RTT 毫秒，不支持返回 -1。封存阈值用。
func get_rtt_ms(_to_id: int) -> int:
	return -1

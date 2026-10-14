## local_provider.gd
## 热座 / 本地环回后端。无真实网络。
## 两实例可通过 pair_with 互连（测试用）；单独使用时 send 直接丢弃但返回 OK。
class_name LocalProvider
extends NetworkProvider

var _is_host: bool = false
var _unique_id: int = 0
var _open: bool = false
# 对端实例。故意不写 LocalProvider 类型：class_name 自引用在赋值时会踩编译期类型解析
var _pair = null
var _inbox: Array = []
var _peer_ids: Array = []


func open_as_host(_opts: Dictionary) -> Error:
	_is_host = true
	_unique_id = 1
	_open = true
	connected.emit(_unique_id)
	return OK


func open_as_client(_opts: Dictionary) -> Error:
	_is_host = false
	_unique_id = 2
	_open = true
	connected.emit(_unique_id)
	return OK


func close() -> void:
	# 先摘链再通知，避免 close 重入时 _pair 已被清空
	var pair = _pair
	_pair = null
	_open = false
	_inbox.clear()
	_peer_ids.clear()
	if pair != null and is_instance_valid(pair) and pair.get("_pair") == self:
		pair.set("_peer_ids", [])
		pair.set("_pair", null)
		pair.disconnected.emit("pair closed")
	disconnected.emit("closed")


## 测试：把两个 LocalProvider 接成一对（host=1, client=2）。
func pair_with(other: LocalProvider) -> void:
	_pair = other
	if other != null:
		other.set("_pair", self)
	if not _peer_ids.has(other.get_unique_id()):
		_peer_ids.append(other.get_unique_id())
	if not other._peer_ids.has(_unique_id):
		other._peer_ids.append(_unique_id)


func poll(_delta: float) -> void:
	while not _inbox.is_empty():
		var item: Dictionary = _inbox.pop_front()
		packet_received.emit(int(item.get("from_id", 0)), item.get("data", {}))


func send_reliable(to_id: int, data: Dictionary) -> Error:
	if not _open:
		return ERR_UNCONFIGURED
	if _pair == null:
		# 热座：无网络对端，上层不发送，这里静默成功
		return OK
	if to_id != 0 and to_id != _pair.get_unique_id():
		return ERR_DOES_NOT_EXIST
	_pair._inbox.append({"from_id": _unique_id, "data": data.duplicate(true)})
	return OK


func is_host() -> bool:
	return _is_host


func get_unique_id() -> int:
	return _unique_id


func get_peer_ids() -> Array:
	return _peer_ids.duplicate()


func get_local_endpoints() -> PackedStringArray:
	return PackedStringArray(["local://hotseat"])

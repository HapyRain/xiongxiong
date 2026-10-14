## enet_provider.gd
## ENet 局域网后端：host/join、可靠信封收发、RTT、UDP 广播发现。
## 底层用 ENetConnection + ENetPacketPeer（put_packet 可靠通道），
## 不使用 MultiplayerSynchronizer / 裸 RPC，消息统一 Dictionary 信封。
class_name EnetProvider
extends NetworkProvider

const DEFAULT_GAME_PORT := 47001
const DEFAULT_DISCOVER_PORT := 47000
const DISCOVER_MAGIC := "XX_DISCOVER"
const ANNOUNCE_MAGIC := "XX_ANNOUNCE"
const MAX_SERVICE_EVENTS := 32

var _conn: ENetConnection = null
var _is_host: bool = false
var _unique_id: int = 0
var _open: bool = false
var _token: String = ""
var _room_info: Dictionary = {}

## 我们自己的会话 id -> ENetPacketPeer
var _id_to_peer: Dictionary = {}
## ENetPacketPeer 的 instance id -> 我们的会话 id
var _peer_key_to_id: Dictionary = {}
var _server_peer: ENetPacketPeer = null
var _next_remote_id: int = 2

var _discover: PacketPeerUDP = null
var _discover_timeout: float = 0.0
var _discover_listening: bool = false

## Android WiFi 锁持有（防 GC / 省电踢网卡）
var _mcast_lock = null
var _wifi_lock = null
var _last_host_err: String = ""


func open_as_host(opts: Dictionary) -> Error:
	close()
	_is_host = true
	_unique_id = 1
	_token = str(opts.get("token", ""))
	_room_info = opts.duplicate(true)
	_next_remote_id = 2

	# Android：先拿 MulticastLock + WifiLock，再 bind（部分机型不拿锁会 Can't create / 收不到包）
	_acquire_android_multicast_lock()
	_acquire_android_wifi_lock()

	var port := int(opts.get("port", DEFAULT_GAME_PORT))
	# peer 数给足：ENet 建 1 个 peer 在部分 Android 版本上会 Can't create
	var max_players := maxi(8, int(opts.get("max_players", 2)))

	# 绑定策略：显式 0.0.0.0 优先（空串在 Android 可能走 IPv6 被拒）
	var configured := str(opts.get("bind_address", "")).strip_edges()
	var addrs: Array[String] = []
	if configured != "" and configured != "*" and configured != "0.0.0.0":
		addrs.append(configured)
	addrs.append("0.0.0.0")
	addrs.append("")
	for ip in get_local_endpoints():
		if not addrs.has(ip):
			addrs.append(ip)

	var err: Error = ERR_CANT_CREATE
	var bound_port := port
	var tried := PackedStringArray()
	for attempt in 4:
		bound_port = port + attempt
		for addr in addrs:
			_conn = ENetConnection.new()
			# 显式给满 channel，避免 0 在部分 ENet/Android 上异常
			err = _conn.create_host_bound(addr, bound_port, max_players, 32, 0, 0)
			tried.append("%s:%d → %s" % [addr if addr != "" else "(any)", bound_port, error_string(err)])
			if err == OK:
				_room_info["bind_address"] = addr if addr != "" else "0.0.0.0"
				_room_info["port"] = bound_port
				break
			_conn.destroy()
			_conn = null
		if err == OK and _conn != null:
			break

	# 绑定全失败 → create_host 由系统选端口（Android 上有时 bound 会挂）
	if err != OK or _conn == null:
		_conn = ENetConnection.new()
		err = _conn.create_host(max_players, 32, 0, 0)
		tried.append("create_host → %s" % error_string(err))
		if err == OK:
			_room_info["bind_address"] = "0.0.0.0"
			if _conn.has_method("get_local_port"):
				_room_info["port"] = int(_conn.get_local_port())
		else:
			_conn = null

	if err != OK or _conn == null:
		_conn = null
		_last_host_err = "; ".join(tried)
		push_error("EnetProvider host bind failed: %s" % _last_host_err)
		_release_android_wifi_locks()
		return ERR_CANT_CREATE

	_open = true
	if bool(opts.get("use_discover", true)):
		_start_discover_listener(int(opts.get("discover_port", DEFAULT_DISCOVER_PORT)))
	connected.emit(_unique_id)
	return OK


func open_as_client(opts: Dictionary) -> Error:
	close()
	_is_host = false
	_unique_id = 0
	_token = str(opts.get("token", ""))

	_conn = ENetConnection.new()
	# 客户端侧也要 create_host 才能调用 connect_to_host（Godot 4.x 约定）
	var err := _conn.create_host(2, 32, 0, 0)
	if err != OK:
		_conn = null
		return err

	var address := str(opts.get("address", "127.0.0.1"))
	if address == "" or address == "*":
		address = "127.0.0.1"
	var port := int(opts.get("port", DEFAULT_GAME_PORT))
	var peer = _conn.connect_to_host(address, port, 1, 0)
	if peer == null or not (peer is ENetPacketPeer):
		_conn.destroy()
		_conn = null
		return ERR_CANT_CONNECT

	_server_peer = peer
	_open = true
	# connected 在收到 welcome 后再 emit（带分配到的 id）
	return OK


func close() -> void:
	_stop_discover()
	_release_android_wifi_locks()
	if _conn != null:
		_conn.destroy()
		_conn = null
	_server_peer = null
	_id_to_peer.clear()
	_peer_key_to_id.clear()
	var was_open := _open
	_open = false
	_unique_id = 0
	if was_open:
		disconnected.emit("closed")


func is_host() -> bool:
	return _is_host


func get_unique_id() -> int:
	return _unique_id


func get_peer_ids() -> Array:
	return _id_to_peer.keys()


func get_local_endpoints() -> PackedStringArray:
	var out := PackedStringArray()
	var seen := {}
	# 1) Godot 自带（桌面/部分设备可用）
	for addr in IP.get_local_addresses():
		_append_lan_ip(out, seen, str(addr))
	# 2) Android：IP.get_local_addresses() 常为空，用 Java 枚举网卡
	if OS.get_name() == "Android":
		for addr in _android_lan_ipv4s():
			_append_lan_ip(out, seen, str(addr))
	# 3) 仍没有：UDP 出口探测（不发包，仅让系统选网卡）
	if out.is_empty() and OS.get_name() == "Android":
		var probe := _android_udp_route_ipv4()
		if probe != "":
			_append_lan_ip(out, seen, probe)
	if out.is_empty():
		out.append("127.0.0.1")
	return _sort_lan_first(out)


func _append_lan_ip(out: PackedStringArray, seen: Dictionary, addr: String) -> void:
	var a := addr.strip_edges()
	if a == "" or a == "0.0.0.0":
		return
	# 去掉 IPv6 zone id，例如 fe80::1%wlan0
	if "%" in a:
		a = a.split("%")[0]
	if a.contains(":"):
		return
	if a.begins_with("127.") or a.begins_with("169.254."):
		return
	if seen.has(a):
		return
	seen[a] = true
	out.append(a)


## 优先局域网段（192.168 / 10. / 172.16-31），再其它。
func _sort_lan_first(list: PackedStringArray) -> PackedStringArray:
	var lan := PackedStringArray()
	var rest := PackedStringArray()
	for a in list:
		if a.begins_with("192.168.") or a.begins_with("10.") or _is_172_private(a):
			lan.append(a)
		else:
			rest.append(a)
	for a in rest:
		lan.append(a)
	return lan


func _is_172_private(a: String) -> bool:
	if not a.begins_with("172."):
		return false
	var parts := a.split(".")
	if parts.size() < 2:
		return false
	var second := int(parts[1])
	return second >= 16 and second <= 31


## Android：java.net.NetworkInterface 枚举 IPv4
func _android_lan_ipv4s() -> PackedStringArray:
	var out := PackedStringArray()
	if not _has_jcw():
		return out
	var ni_cls = JavaClassWrapper.wrap("java.net.NetworkInterface")
	if ni_cls == null:
		return out
	var ifaces = ni_cls.getNetworkInterfaces()
	if ifaces == null:
		return out
	while ifaces.hasMoreElements():
		var ni = ifaces.nextElement()
		if ni == null or not ni.isUp():
			continue
		var addrs = ni.getInetAddresses()
		if addrs == null:
			continue
		while addrs.hasMoreElements():
			var ia = addrs.nextElement()
			if ia == null:
				continue
			var s := str(ia.getHostAddress())
			if s != "" and not s.contains(":"):
				out.append(s)
	return out


## Android：DatagramSocket.connect 外网，读本地出口 IP（不真正发包）
func _android_udp_route_ipv4() -> String:
	if not _has_jcw():
		return ""
	var ds_cls = JavaClassWrapper.wrap("java.net.DatagramSocket")
	var isa_cls = JavaClassWrapper.wrap("java.net.InetSocketAddress")
	if ds_cls == null or isa_cls == null:
		return ""
	var sock = ds_cls.new()
	if sock == null:
		return ""
	var ret := ""
	sock.connect(isa_cls.new("8.8.8.8", 53))
	var local = sock.getLocalAddress()
	if local != null:
		ret = str(local.getHostAddress())
		if "%" in ret:
			ret = ret.split("%")[0]
	sock.close()
	return ret if not ret.contains(":") else ""


func _has_jcw() -> bool:
	if OS.get_name() != "Android":
		return false
	# JavaClassWrapper 仅 Android 构建存在；桌面 export 不会走到这里
	return true


func send_reliable(to_id: int, data: Dictionary) -> Error:
	if not _open or _conn == null:
		return ERR_UNCONFIGURED
	var bytes: PackedByteArray = var_to_bytes(data)
	var err: Error = OK
	if _is_host:
		if to_id == 0:
			for id in _id_to_peer.keys():
				var p: ENetPacketPeer = _id_to_peer[id]
				if p != null:
					if p.put_packet(bytes) != OK:
						err = FAILED
		elif _id_to_peer.has(to_id):
			var p: ENetPacketPeer = _id_to_peer[to_id]
			if p == null:
				return ERR_DOES_NOT_EXIST
			err = p.put_packet(bytes)
		else:
			return ERR_DOES_NOT_EXIST
	else:
		if to_id != 0 and to_id != 1 and to_id != get_unique_id():
			# 客户端只可达房主
			if to_id != 1:
				return ERR_DOES_NOT_EXIST
		if _server_peer == null:
			return ERR_UNCONFIGURED
		err = _server_peer.put_packet(bytes)
	_conn.flush()
	return err


func get_rtt_ms(to_id: int) -> int:
	var p: ENetPacketPeer = null
	if _is_host:
		if _id_to_peer.has(to_id):
			p = _id_to_peer[to_id]
	else:
		p = _server_peer
	if p == null:
		return -1
	return int(p.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME))


func get_last_host_err() -> String:
	return _last_host_err


func poll(delta: float) -> void:
	if _conn != null and _open:
		_pump_service()
		_conn.flush()
	if _discover != null and _discover_timeout > 0.0:
		_discover_timeout -= delta
		if _discover_timeout <= 0.0:
			stop_discover()
		else:
			_pump_discover()


# ---------- ENet 事件泵 ----------

func _pump_service() -> void:
	for i in MAX_SERVICE_EVENTS:
		var ev = _conn.service(0)
		if ev == null or not (ev is Array) or ev.is_empty():
			break
		var etype := int(ev[0])
		var peer: ENetPacketPeer = ev[1] if ev.size() > 1 else null
		match etype:
			ENetConnection.EVENT_CONNECT:
				_on_connect(peer)
			ENetConnection.EVENT_DISCONNECT:
				_on_disconnect(peer)
			ENetConnection.EVENT_RECEIVE:
				_on_receive(peer)
			_:
				pass


func _on_connect(peer: ENetPacketPeer) -> void:
	if peer == null:
		return
	if _is_host:
		var assigned := _next_remote_id
		_next_remote_id += 1
		_id_to_peer[assigned] = peer
		_peer_key_to_id[peer.get_instance_id()] = assigned
		# 给客户端分配座位 id，并校验 token（客户端 token 空则跳过）
		var hello := {
			"v": 1,
			"type": "_welcome",
			"payload": {"your_id": assigned, "host_id": 1, "token": _token},
		}
		peer.put_packet(var_to_bytes(hello))
		_conn.flush()
	else:
		_server_peer = peer
		# 客户端连上后立刻发 hello（带 token）
		var hello := {
			"v": 1,
			"type": "_hello",
			"payload": {"token": _token},
		}
		peer.put_packet(var_to_bytes(hello))
		_conn.flush()


func _on_disconnect(peer: ENetPacketPeer) -> void:
	var key: int = peer.get_instance_id() if peer != null else 0
	var from_id: int = int(_peer_key_to_id.get(key, -1))
	if peer != null:
		_peer_key_to_id.erase(peer.get_instance_id())
	if from_id >= 0:
		_id_to_peer.erase(from_id)
	if _is_host:
		disconnected.emit("peer %d left" % from_id)
	else:
		_open = false
		disconnected.emit("server disconnected")


func _on_receive(peer: ENetPacketPeer) -> void:
	if peer == null:
		return
	var raw: PackedByteArray = peer.get_packet()
	if raw.is_empty():
		return
	var decoded = bytes_to_var(raw)
	if typeof(decoded) != TYPE_DICTIONARY:
		return
	var data: Dictionary = decoded

	# 传输层握手：_hello / _welcome 不进入上层信封，但要更新身份
	var type := str(data.get("type", ""))
	if type == "_welcome" and not _is_host:
		var payload: Dictionary = data.get("payload", {})
		_unique_id = int(payload.get("your_id", 2))
		# 校验 token（房主声明的 token 若与本地不一致则拒绝）
		var expect := str(payload.get("token", ""))
		if _token != "" and expect != "" and expect != _token:
			close()
			disconnected.emit("token mismatch")
			return
		connected.emit(_unique_id)
		return
	if type == "_hello" and _is_host:
		var payload: Dictionary = data.get("payload", {})
		var tok := str(payload.get("token", ""))
		if _token != "" and tok != "" and tok != _token:
			var rid: int = int(_peer_key_to_id.get(peer.get_instance_id(), -1))
			if rid >= 0:
				send_reliable(rid, {"v": 1, "type": "_reject", "payload": {"reason": "token"}})
				_id_to_peer.erase(rid)
				_peer_key_to_id.erase(peer.get_instance_id())
			return
		return

	var from_id: int = int(_peer_key_to_id.get(peer.get_instance_id(), 0))
	if not _is_host and _server_peer != null and peer.get_instance_id() == _server_peer.get_instance_id():
		from_id = 1
	packet_received.emit(from_id, data)


# ---------- Android WiFi 锁（组播/省电，不拿锁建房或收广播会失败） ----------

## Android 上 UDP 组播会被系统拦。用 JavaClassWrapper 拿 WifiManager.MulticastLock。
func _acquire_android_multicast_lock() -> void:
	if OS.get_name() != "Android" or not _has_jcw():
		return
	if _mcast_lock != null:
		return
	var ctx = _android_context()
	if ctx == null:
		push_warning("EnetProvider: no Android Context, MulticastLock skipped")
		return
	var wifi = ctx.getSystemService("wifi")
	if wifi == null:
		return
	# WifiManager.MulticastLock
	var lock = wifi.createMulticastLock("xiongxiong_mc")
	if lock == null:
		return
	lock.setReferenceCounted(true)
	if not lock.isHeld():
		lock.acquire()
	_mcast_lock = lock


## WifiLock：防省电断 Wi-Fi 导致 ENet socket 异常
func _acquire_android_wifi_lock() -> void:
	if OS.get_name() != "Android" or not _has_jcw():
		return
	if _wifi_lock != null:
		return
	var ctx = _android_context()
	if ctx == null:
		return
	var wifi = ctx.getSystemService("wifi")
	if wifi == null:
		return
	# WIFI_MODE_FULL_HIGH_PERF = 3
	var lock = wifi.createWifiLock(3, "xiongxiong_wifi")
	if lock == null:
		return
	lock.setReferenceCounted(true)
	if not lock.isHeld():
		lock.acquire()
	_wifi_lock = lock


func _release_android_wifi_locks() -> void:
	for lock in [_mcast_lock, _wifi_lock]:
		if lock != null and lock.isHeld():
			lock.release()
	_mcast_lock = null
	_wifi_lock = null


## 拿 Application Context：优先 AndroidRuntime 插件，否则 ActivityThread 反射
func _android_context():
	if Engine.has_singleton("AndroidRuntime"):
		var ar = Engine.get_singleton("AndroidRuntime")
		if ar != null and ar.has_method("get_application_context"):
			var c = ar.get_application_context()
			if c != null:
				return c
	# JavaClassWrapper：android.app.ActivityThread.currentApplication()
	var at_cls = JavaClassWrapper.wrap("android.app.ActivityThread")
	if at_cls == null:
		return null
	var at = at_cls.currentActivityThread()
	if at == null:
		return null
	if at.has_method("getApplication"):
		return at.getApplication()
	return null


func _start_discover_listener(port: int) -> void:
	_discover = PacketPeerUDP.new()
	_discover.set_broadcast_enabled(true)
	var err := _discover.bind(port)
	if err != OK:
		push_warning("EnetProvider: discover bind failed on %d" % port)
		_discover = null
		return
	_discover_listening = true


func start_discover(timeout_sec: float) -> Error:
	if _discover != null and _discover_listening:
		# 已在监听（房主）则不重复
		_discover_timeout = timeout_sec
		return OK
	_discover = PacketPeerUDP.new()
	_discover.set_broadcast_enabled(true)
	_discover.set_dest_address("255.255.255.255", DEFAULT_DISCOVER_PORT)
	var probe := {
		"v": 1,
		"magic": DISCOVER_MAGIC,
		"proto": 1,
	}
	_discover.put_packet(JSON.stringify(probe).to_utf8_buffer())
	_discover_timeout = timeout_sec
	_discover_listening = false
	return OK


func stop_discover() -> void:
	_stop_discover()


func _stop_discover() -> void:
	if _discover != null:
		_discover.close()
		_discover = null
	_discover_listening = false
	_discover_timeout = 0.0


func _pump_discover() -> void:
	if _discover == null:
		return
	while _discover.get_available_packet_count() > 0:
		var pkt: PackedByteArray = _discover.get_packet()
		var text := pkt.get_string_from_utf8()
		var parsed = JSON.parse_string(text)
		if typeof(parsed) != TYPE_DICTIONARY:
			continue
		var msg: Dictionary = parsed
		var magic := str(msg.get("magic", ""))
		if magic == DISCOVER_MAGIC and _is_host and _discover_listening:
			# 回房卡
			var announce := {
				"v": 1,
				"magic": ANNOUNCE_MAGIC,
				"room_name": str(_room_info.get("room_name", "xiongxiong")),
				"host_name": str(_room_info.get("host_name", "host")),
				"port": int(_room_info.get("port", DEFAULT_GAME_PORT)),
				"token": _token,
				"players": _id_to_peer.size() + 1,
				"max_players": int(_room_info.get("max_players", 2)),
				"version": 1,
			}
			var dest_ip := _discover.get_packet_ip()
			var dest_port := _discover.get_packet_port()
			_discover.set_dest_address(dest_ip, dest_port)
			_discover.put_packet(JSON.stringify(announce).to_utf8_buffer())
		elif magic == ANNOUNCE_MAGIC and not _is_host:
			var info := msg.duplicate(true)
			info["address"] = _discover.get_packet_ip()
			info["port"] = int(msg.get("port", DEFAULT_GAME_PORT))
			discovered_room.emit(info)

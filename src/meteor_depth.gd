class_name MeteorDepthReceiver
extends RefCounted

## Receives depth maps from Nightfall Meteor's depth port (see
## meteor/src/depth_server.rs). On connecting it sends a key made for this
## connection; each message is then a 32-byte little-endian header and a
## zstd-compressed 8-bit map, encrypted (nightfall-stream's
## MeteorChannelCipher), tagged with the Moonlight frame number it was made
## from.
##
## A worker thread connects, reads and decompresses, and keeps the newest
## RING_SIZE maps. The main thread only picks the map for the frame on screen
## (pick()), so no network or decompression work lands on the render loop.
##
## Steam Frame: a second connection can run beside the first, to Meteor's
## address on the headset's second link (set_second()). Meteor sends every
## map down each connection it has; a map is kept the first time it arrives
## and its copy dropped, so the maps keep coming while either link holds.

const HEADER_LEN := 32
const MAGIC := 0x4D44464E # "NFDM", little-endian
const VERSION := 2
const HELLO_MAGIC := "NFDK"
const KDF_INFO := "nightfall-meteor depth v2"
const COMPRESSION_ZSTD := 1
const MAX_MAP_PIXELS := 4096 * 4096
## About 100 ms of maps at 120 Hz.
const RING_SIZE := 12
const RECONNECT_SEC := 2.0
## A connection gets this long to deliver its first map.
const FIRST_MAP_GRACE_SEC := 3.0
## After this long without a map, the client falls back to on-device depth.
const STALL_SEC := 1.0
## Worker sleep when no data is waiting.
const IDLE_USEC := 500
## With two connections a map can arrive a little behind its copy. Further
## behind than this it isn't late: the frame numbers have started again.
const LATE_FRAMES := 1000

var host := ""
var port := 0
## Meteor's public key (MeteorClient.meteor_key()).
var key := ""
# Written by the worker; plain ints and bools, read without the lock.
var maps_received := 0
var bytes_received := 0
var newest_frame := 0
var host_latency_ms := 0.0

## Maps that arrived first over each connection (the stream's own link, the
## second link), for the log.
var maps_by_link: Array[int] = [0, 0]

# One worker for each connection: [the stream's own link, the second link].
var _threads: Array = [null, null]
var _hosts: Array[String] = ["", ""]
var _link_running: Array[bool] = [false, false]
var _link_connected: Array[bool] = [false, false]
var _link_connected_at: Array[float] = [0.0, 0.0]
var _mutex := Mutex.new()
var _last_map_at := 0.0
# {frame, epoch, map, width, height, latency_us}, oldest first. Guarded by _mutex.
var _ring: Array[Dictionary] = []

## Whether this build can decrypt Meteor's maps.
static func is_supported() -> bool:
	return ClassDB.class_exists("MeteorChannelCipher")

func start(address: String, depth_port: int, meteor_key: String) -> void:
	if address == host and depth_port == port and meteor_key == key and _threads[0]:
		return
	stop()
	host = address
	port = depth_port
	key = meteor_key
	maps_by_link = [0, 0]
	_start_link(0, address)

## Meteor's address on the headset's second link, "" for none. Starts or
## stops the second connection; the first is left alone.
func set_second(address: String) -> void:
	if address == _hosts[1] or not _threads[0]:
		return
	_stop_link(1)
	if not address.is_empty():
		_start_link(1, address)

func second() -> String:
	return _hosts[1]

func _start_link(link: int, address: String) -> void:
	_hosts[link] = address
	_link_running[link] = true
	_threads[link] = Thread.new()
	_threads[link].start(_run.bind(link))

func _stop_link(link: int) -> void:
	_link_running[link] = false
	if _threads[link]:
		_threads[link].wait_to_finish()
	_threads[link] = null
	_hosts[link] = ""
	_link_connected[link] = false

func stop() -> void:
	_stop_link(1)
	_stop_link(0)
	host = ""
	port = 0
	_last_map_at = 0.0
	newest_frame = 0
	_mutex.lock()
	_ring.clear()
	_mutex.unlock()

func is_active() -> bool:
	return _threads[0] != null

func is_connected_to_meteor() -> bool:
	return _link_connected[0] or _link_connected[1]

## Seconds since the last map arrived, or since connecting when none has yet;
## 0 while not connected. `flowing`: a map has arrived over these connections.
func silent_for() -> float:
	return silence(_now(), _last_map_at, _connected_since())

func maps_flowing() -> bool:
	return is_connected_to_meteor() and _last_map_at > _connected_since()

# When the longer-standing of the connections there are was made; INF for none.
func _connected_since() -> float:
	var connected_at := INF
	for link in 2:
		if _link_connected[link]:
			connected_at = minf(connected_at, _link_connected_at[link])
	return connected_at

static func silence(now: float, last_map_at: float, connected_at: float) -> float:
	if connected_at == INF:
		return 0.0
	return maxf(now - maxf(last_map_at, connected_at), 0.0)

## True while maps are arriving, or a fresh connection is still within its
## grace period for the first one.
func is_delivering() -> bool:
	if not is_connected_to_meteor():
		return false
	# Since the longer-standing of the connections there are.
	var connected_at := INF
	for link in 2:
		if _link_connected[link]:
			connected_at = minf(connected_at, _link_connected_at[link])
	var now := _now()
	if _last_map_at > connected_at:
		return now - _last_map_at < STALL_SEC
	return now - connected_at < FIRST_MAP_GRACE_SEC

## The map for `target` (a Moonlight frame number) if it has arrived, else the
## newest one before it. Never a map from a later frame, unless target is 0
## (frame numbers unknown), when the newest map is returned. {} if none.
func pick(target: int) -> Dictionary:
	_mutex.lock()
	var best := {}
	for i in range(_ring.size() - 1, -1, -1):
		var entry: Dictionary = _ring[i]
		if target <= 0 or entry["frame"] <= target:
			best = entry
			break
	_mutex.unlock()
	return best

# StreamPeerTCP, or nightfall-stream's NightfallTcpPeer for a zoned
# link-local address (USB Link), which StreamPeerTCP can't reach. Both offer
# the calls _run() makes, with the same status values.
static func _new_peer(address: String):
	if "%" in address and ClassDB.class_exists("NightfallTcpPeer"):
		return ClassDB.instantiate("NightfallTcpPeer")
	return StreamPeerTCP.new()

func _run(link: int) -> void:
	var address := _hosts[link]
	var peer = null
	var cipher = null
	var counter := 0
	var buf := PackedByteArray()
	var retry_at := 0.0
	while _link_running[link]:
		var now := _now()
		if peer == null:
			if now < retry_at:
				OS.delay_msec(50)
				continue
			retry_at = now + RECONNECT_SEC
			peer = _new_peer(address)
			if peer.connect_to_host(address, port) != OK:
				peer = null
				continue
		peer.poll()
		var status: int = peer.get_status()
		if status == StreamPeerTCP.STATUS_CONNECTING:
			OS.delay_msec(5)
			continue
		if status != StreamPeerTCP.STATUS_CONNECTED:
			peer = null
			buf = PackedByteArray()
			_link_connected[link] = false
			continue
		if not _link_connected[link]:
			peer.set_no_delay(true)
			cipher = ClassDB.instantiate("MeteorChannelCipher")
			var err: String = cipher.init(key, KDF_INFO)
			var hello := HELLO_MAGIC.to_ascii_buffer()
			hello.append_array(cipher.get_public_key())
			if not err.is_empty() or peer.put_data(hello) != OK:
				push_warning("Meteor depth: can't start the encrypted connection (%s)" % err)
				peer.disconnect_from_host()
				peer = null
				continue
			counter = 0
			_link_connected_at[link] = now
			_link_connected[link] = true
		var available: int = peer.get_available_bytes()
		if available <= 0:
			OS.delay_usec(IDLE_USEC)
			continue
		var result: Array = peer.get_partial_data(available)
		if result[0] != OK:
			peer.disconnect_from_host()
			peer = null
			buf = PackedByteArray()
			_link_connected[link] = false
			continue
		var chunk: PackedByteArray = result[1]
		buf.append_array(chunk)
		bytes_received += chunk.size()
		var messages := parse_messages(buf)
		if messages.size() == 1 and messages[0].has("error"):
			push_warning("Meteor depth: %s; reconnecting" % messages[0]["error"])
			peer.disconnect_from_host()
			peer = null
			buf = PackedByteArray()
			_link_connected[link] = false
			continue
		var consumed := 0
		var forged := false
		for message: Dictionary in messages:
			consumed = message["payload_end"]
			var pixels: int = message["width"] * message["height"]
			var header := buf.slice(message["header_start"], message["payload_start"])
			var plain: PackedByteArray = cipher.open(counter, header, buf.slice(message["payload_start"], message["payload_end"]))
			counter += 1
			if plain.is_empty():
				forged = true
				break
			var map := plain.decompress(pixels, FileAccess.COMPRESSION_ZSTD)
			if map.size() != pixels:
				push_warning("Meteor depth: map for frame %d didn't decompress" % message["frame"])
				continue
			_store({
				"frame": message["frame"],
				"epoch": message["epoch"],
				"map": map,
				"width": message["width"],
				"height": message["height"],
				"latency_us": message["latency_us"],
			}, link)
		if forged:
			push_warning("Meteor depth: a map didn't decrypt; reconnecting")
			peer.disconnect_from_host()
			peer = null
			buf = PackedByteArray()
			_link_connected[link] = false
			continue
		if consumed > 0:
			buf = buf.slice(consumed)
	if peer:
		peer.disconnect_from_host()
	_link_connected[link] = false

## Whether a map is the late copy of one already kept: with two connections
## each map comes twice. `newest` and `newest_epoch` are the last map kept.
static func is_late_copy(frame: int, epoch: int, newest: int, newest_epoch: int, two_connections: bool) -> bool:
	return two_connections and epoch == newest_epoch and frame <= newest and newest - frame < LATE_FRAMES

func _store(entry: Dictionary, link: int = 0) -> void:
	var now := _now()
	_mutex.lock()
	if not _ring.is_empty():
		var last: Dictionary = _ring[-1]
		if is_late_copy(entry["frame"], entry["epoch"], last["frame"], last["epoch"], not _hosts[1].is_empty()):
			_mutex.unlock()
			return
		# A new stream epoch starts its frame numbers again.
		if entry["epoch"] != last["epoch"] or entry["frame"] < last["frame"]:
			_ring.clear()
	if _last_map_at > 0.0 and now - _last_map_at >= 0.1:
		push_warning("[METEOR-DEPTH] Receive gap %.0f ms before frame %d (previous %d)" % [
			(now - _last_map_at) * 1000.0, entry["frame"], newest_frame])
	_ring.append(entry)
	while _ring.size() > RING_SIZE:
		_ring.pop_front()
	maps_received += 1
	maps_by_link[link] += 1
	newest_frame = entry["frame"]
	host_latency_ms = entry["latency_us"] / 1000.0
	_last_map_at = now
	_mutex.unlock()

## The complete messages at the start of buf, each {frame, epoch, width,
## height, latency_us, header_start, payload_start, payload_end} (the payload
## still encrypted); or a single {error} for a stream that isn't Meteor's.
static func parse_messages(buf: PackedByteArray) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var offset := 0
	while buf.size() - offset >= HEADER_LEN:
		if buf.decode_u32(offset) != MAGIC:
			return [{"error": "bad magic"}]
		if buf.decode_u16(offset + 4) != VERSION:
			return [{"error": "unsupported version %d" % buf.decode_u16(offset + 4)}]
		var header_len := buf.decode_u16(offset + 6)
		var w := buf.decode_u16(offset + 16)
		var h := buf.decode_u16(offset + 18)
		var payload_len := buf.decode_u32(offset + 24)
		if header_len < HEADER_LEN or buf.decode_u8(offset + 20) != 0 or buf.decode_u8(offset + 21) != COMPRESSION_ZSTD:
			return [{"error": "unsupported map format"}]
		if w == 0 or h == 0 or w * h > MAX_MAP_PIXELS or payload_len > w * h + 65536 + 16:
			return [{"error": "bad map size %dx%d (%d bytes)" % [w, h, payload_len]}]
		var end := offset + header_len + payload_len
		if end > buf.size():
			break
		out.append({
			"epoch": buf.decode_u32(offset + 8),
			"frame": buf.decode_u32(offset + 12),
			"width": w,
			"height": h,
			"latency_us": buf.decode_u32(offset + 28),
			"header_start": offset,
			"payload_start": offset + header_len,
			"payload_end": end,
		})
		offset = end
	return out

static func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

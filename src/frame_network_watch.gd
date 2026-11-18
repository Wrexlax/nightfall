class_name FrameNetworkWatch
extends RefCounted

## Steam Frame: what the headset's own network link looks like, for the log.
##
## Why: on 2026-11-15 two streams ended because nothing passed between the
## headset and the PC for minutes, while both were running. Nightfall's log
## and the PC's could show that it happened but not where: the headset's
## Wi-Fi, the access point, or the PC's side. These lines answer that the next
## time, from what the headset's system already keeps:
##
## - is the Wi-Fi link up, and how strong is the signal;
## - how many packets arrive and leave each second. A home network always
##   carries a trickle of announcements, so "nothing arriving" means the
##   headset's own link is dead, and "a trickle arriving, the PC silent" means
##   the fault is past the headset;
## - did the PC (or the router, when the PC is reached through it) answer when
##   the headset last looked for it;
## - which band the Wi-Fi is on and whether the headset has moved to another
##   access point since the stream began.
##
## Nothing here names a network or shows an address: not the PC's, not the
## router's, not an access point's. Addresses are read to pick the right lines
## out of the system's tables and go no further.
##
## Two more things since 7w:
##
## - while a stream's picture has stopped, a line every second. Every roam
##   of the Wi-Fi from one access point to another has so far ended with
##   some nine seconds of nothing, the stream given up, and a new stream that
##   worked at once (2026-11-16 logs). A line a minute could not say whether
##   the Wi-Fi was dead until then or had been back for a while with the old
##   stream failing to pick up; a line a second can.
## - the wireless adapter's own link. The headset is the access point there
##   and the PC's adapter the device that joins, so the headset has the
##   figures: signal, speed, packets retried and given up on. (The adapter's
##   address is in the same answer and is not kept.)

const NET_ROOT := "/sys/class/net"
const ROUTES := "/proc/net/route"
const NEIGHBOURS := "/proc/net/arp"
const WIRELESS := "/proc/net/wireless"

## A line this often while a stream runs and all is well.
const QUIET_SECONDS := 60.0
## And this often from the moment a stream is lost until one runs again.
const TROUBLE_SECONDS := 5.0
## The access point is asked about (a short program run) this often in trouble.
const LINK_DETAILS_SECONDS := 30.0
## Trouble that lasts longer than this is somebody having gone to bed.
const TROUBLE_MAX_SECONDS := 900.0
## The picture counts as stopped in a second with no more frames than this
## (a stream is 72 to 144 a second; a frame or two can straggle in).
const STALLED_FRAMES := 2
## A stopped picture gets a line a second for this long, then is left alone
## until it has moved again: a PC showing a still screen may send nothing.
const STALL_MAX_LINES := 40
## The wireless adapter's link on the headset (its own access point).
const ADAPTER_IFACE := "wlanap"

## "192.168.1.20" -> a number; -1 for anything that isn't four numbers.
static func ip_number(text: String) -> int:
	var parts := text.strip_edges().split(".")
	if parts.size() != 4:
		return -1
	var number := 0
	for part in parts:
		if not part.is_valid_int() or int(part) < 0 or int(part) > 255:
			return -1
		number = number * 256 + int(part)
	return number

## The route table writes addresses as hex with the bytes back to front.
static func _table_number(hex: String) -> int:
	if hex.length() != 8 or not hex.is_valid_hex_number():
		return -1
	var value := hex.hex_to_int()
	return ((value & 0xff) << 24) | ((value & 0xff00) << 8) | ((value >> 8) & 0xff00) | ((value >> 24) & 0xff)

static func _address_text(number: int) -> String:
	return "%d.%d.%d.%d" % [(number >> 24) & 0xff, (number >> 16) & 0xff, (number >> 8) & 0xff, number & 0xff]

static func _bits(mask: int) -> int:
	var count := 0
	for bit in 32:
		if mask & (1 << bit):
			count += 1
	return count

## How the system would reach `ip`, from the text of /proc/net/route:
## { "iface": "wlan0", "next": the address it will look for on that link }.
## `next` is `ip` itself when the PC is on the same network, the router's
## when it is not. Empty when there is no route (or `ip` isn't an address).
static func route_for(ip: String, routes_text: String) -> Dictionary:
	var wanted := ip_number(ip)
	if wanted < 0:
		return {}
	var best := {}
	var best_bits := -1
	var best_metric := 0
	for line in routes_text.split("\n").slice(1):
		var cells := line.split("\t", false)
		if cells.size() < 8:
			continue
		var destination := _table_number(cells[1].strip_edges())
		var gateway := _table_number(cells[2].strip_edges())
		var mask := _table_number(cells[7].strip_edges())
		if destination < 0 or gateway < 0 or mask < 0 or (wanted & mask) != destination:
			continue
		var bits := _bits(mask)
		var metric := int(cells[6])
		if bits > best_bits or (bits == best_bits and metric < best_metric):
			best_bits = bits
			best_metric = metric
			best = {"iface": cells[0].strip_edges(), "next": ip if gateway == 0 else _address_text(gateway), "through_router": gateway != 0}
	return best

## Whether `ip` answered when the system last looked for it on the link, from
## the text of /proc/net/arp: "answered", "no answer" or "not looked for".
static func neighbour_state(ip: String, neighbours_text: String) -> String:
	for line in neighbours_text.split("\n").slice(1):
		var cells := line.split(" ", false)
		if cells.size() >= 3 and cells[0] == ip:
			return "answered" if (cells[2].hex_to_int() & 0x2) != 0 else "no answer"
	return "not looked for"

## Signal strength in dBm for `iface` from the text of /proc/net/wireless;
## 0 when the system doesn't keep that file or the link isn't listed.
static func signal_dbm(iface: String, wireless_text: String) -> int:
	for line in wireless_text.split("\n"):
		var cells := line.strip_edges().split(" ", false)
		if cells.size() >= 4 and cells[0] == iface + ":":
			return int(cells[3].trim_suffix("."))
	return 0

## What `iw dev <iface> link` printed, without the access point's address or
## the network's name: { "connected", "mhz", "dbm", "mbit", "point" }. `point`
## is kept only to notice a move to another access point; it is never logged.
static func link_details(iw_text: String) -> Dictionary:
	var details := {"connected": false, "mhz": 0, "dbm": 0, "mbit": 0.0, "point": ""}
	for raw in iw_text.split("\n"):
		var line := raw.strip_edges()
		if line.begins_with("Connected to "):
			details["connected"] = true
			details["point"] = line.split(" ", false)[2]
		elif line.begins_with("freq:"):
			details["mhz"] = int(line.trim_prefix("freq:").strip_edges())
		elif line.begins_with("signal:"):
			details["dbm"] = int(line.trim_prefix("signal:").strip_edges())
		elif line.begins_with("tx bitrate:"):
			details["mbit"] = float(line.trim_prefix("tx bitrate:").strip_edges())
	return details

## What `iw dev wlanap station dump` printed, without the adapter's address:
## { "joined": how many devices, and for the first of them "dbm", "tx_mbit",
## "rx_mbit" (the headset sending and receiving), "retries" and "failed"
## (packets sent again, and given up on, since it joined), "quiet_ms" (how
## long since it was last heard) }.
static func station_details(iw_text: String) -> Dictionary:
	var details := {"joined": 0, "dbm": 0, "tx_mbit": 0.0, "rx_mbit": 0.0, "retries": 0, "failed": 0, "quiet_ms": 0}
	# The Frame's driver prints "signal: 0 dBm" always and the real figure
	# under "avg ack signal" / "last ack signal": how strongly the headset
	# hears the PC's adapter answer (7y log: 0 beside -52 and -53).
	var ack_avg := 0
	var ack_last := 0
	for raw in iw_text.split("\n"):
		var line := raw.strip_edges()
		if line.begins_with("Station "):
			details["joined"] += 1
			continue
		if details["joined"] != 1:
			continue
		var cut := line.find(":")
		if cut < 0:
			continue
		# The first word after the colon: "-47 [-49, -51] dBm" is -47.
		var words := line.substr(cut + 1).strip_edges().split(" ", false)
		if words.is_empty():
			continue
		var value := words[0]
		match line.left(cut):
			"signal":
				details["dbm"] = int(value)
			"tx bitrate":
				details["tx_mbit"] = float(value)
			"rx bitrate":
				details["rx_mbit"] = float(value)
			"tx retries":
				details["retries"] = int(value)
			"tx failed":
				details["failed"] = int(value)
			"inactive time":
				details["quiet_ms"] = int(value)
			"avg ack signal":
				ack_avg = int(value)
			"last ack signal":
				ack_last = int(value)
	if details["dbm"] == 0:
		details["dbm"] = ack_avg if ack_avg != 0 else ack_last
	return details

## What the system printed, for the log, once: every address taken out, the
## first device's lines only, on one line. The first headset logs read
## "signal 0 dBm" and no retried packets where the adapter was plainly
## working, so either the driver gives no such figures or words them
## otherwise; this shows which.
static func station_dump_for_log(iw_text: String) -> String:
	var address := RegEx.new()
	address.compile("([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}")
	var kept := PackedStringArray()
	var stations := 0
	for raw in iw_text.split("\n"):
		var line := raw.strip_edges()
		if line.begins_with("Station "):
			stations += 1
		if line.is_empty() or stations != 1:
			continue
		kept.append(address.sub(line, "(address)", true).replace("\t", " "))
		if kept.size() >= 40:
			break
	return " | ".join(kept)

## The adapter's link as a sentence. `before` is the reading before this one
## (empty for the first), for the packets retried and given up on since.
static func describe_stations(now: Dictionary, before: Dictionary) -> String:
	if int(now.get("joined", 0)) == 0:
		return "adapter link: nothing has joined (the PC's adapter is not connected to the headset)"
	var text := "adapter link: signal %s, sending at %d Mbit/s, receiving at %d" % [
		"%d dBm" % now["dbm"] if now["dbm"] != 0 else "not reported", roundi(now["tx_mbit"]), roundi(now["rx_mbit"])]
	# Only from a driver that counts them: the Frame's prints 0 for both, always,
	# and "0 packets sent again" would read as a clean link.
	if int(before.get("joined", 0)) > 0 and now["retries"] >= before["retries"] and now["failed"] >= before["failed"] \
			and now["retries"] + now["failed"] > 0:
		text += "; since the last look %d packets sent again, %d given up on" % [
			now["retries"] - before["retries"], now["failed"] - before["failed"]]
	if now["quiet_ms"] >= 1000:
		text += "; not heard for %.1f s" % (now["quiet_ms"] / 1000.0)
	if int(now["joined"]) > 1:
		text += " (%d devices joined; figures for the first)" % int(now["joined"])
	return text

static func band(mhz: int) -> String:
	if mhz >= 5925:
		return "6 GHz"
	if mhz >= 4900:
		return "5 GHz"
	if mhz >= 2400:
		return "2.4 GHz"
	return "unknown band"

## One reading as a sentence. `before` is the reading `seconds` earlier (empty
## for the first), from which the packets a second are worked out.
static func describe(now: Dictionary, before: Dictionary, seconds: float) -> String:
	if now.is_empty():
		return "no route to the PC: the headset has no network that leads to it"
	var text := "%s: %s" % [now["iface"], "connected" if now["up"] else "not connected"]
	if now["dbm"] != 0:
		text += ", signal %d dBm" % now["dbm"]
	if not before.is_empty() and before.get("iface", "") == now["iface"] and seconds > 0.0:
		text += "; %d packets a second arriving, %d leaving" % [
			roundi(maxf(now["rx"] - before["rx"], 0.0) / seconds), roundi(maxf(now["tx"] - before["tx"], 0.0) / seconds)]
	text += "; the %s: %s" % ["router (the PC is reached through it)" if now["through_router"] else "PC", now["neighbour"]]
	return text

static func describe_link(details: Dictionary, point_at_start: String) -> String:
	if not details["connected"]:
		return "access point: none (the Wi-Fi is not joined to a network)"
	var text := "access point: %s band (%d MHz), signal %d dBm, sending at %d Mbit/s" % [
		band(details["mhz"]), details["mhz"], details["dbm"], roundi(details["mbit"])]
	if not point_at_start.is_empty():
		text += "; " + ("the same one as when the stream began" if details["point"] == point_at_start else "NOT the one the stream began on")
	return text

# --- the part that reads the headset -------------------------------------

var _before := {}
var _since_line := 0.0
var _since_details := 0.0
var _trouble_for := -1.0
var _point_at_start := ""
var _details_unavailable := false
var _watching := false
# The adapter's link: the reading before, and whether the question can be asked.
var _stations_before := {}
var _stations_unavailable := false
# What the system prints, kept from the first answer that names a device
# until it has been logged (once in a run of the app).
var _stations_raw := ""
var _stations_raw_logged := false
# A stopped picture: for how many seconds now, and whether its lines ran out.
var _stalled_for := 0

## The text of one of the system's small tables. Read in pieces until the
## end: the files under /proc report a length of zero, so asking for "the
## whole file" returns nothing (7k's lines all said "no route" for that).
static func file_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var bytes := PackedByteArray()
	while bytes.size() < 1048576:
		var piece := file.get_buffer(16384)
		if piece.is_empty():
			break
		bytes.append_array(piece)
	return bytes.get_string_from_utf8()

func _read(host: String) -> Dictionary:
	var route := route_for(host, file_text(ROUTES))
	if route.is_empty():
		return {}
	var folder := NET_ROOT.path_join(route["iface"])
	route["up"] = file_text(folder.path_join("operstate")).strip_edges() == "up"
	route["rx"] = float(file_text(folder.path_join("statistics/rx_packets")))
	route["tx"] = float(file_text(folder.path_join("statistics/tx_packets")))
	route["dbm"] = signal_dbm(route["iface"], file_text(WIRELESS))
	route["neighbour"] = neighbour_state(route["next"], file_text(NEIGHBOURS))
	return route

## Runs `iw` (a few milliseconds; only at a stream's start and in trouble).
func _link_line(iface: String, starting: bool) -> String:
	if _details_unavailable or iface.is_empty():
		return ""
	var output := []
	# Steam's library paths confuse system programs; see FrameDisplayRate.
	var code := OS.execute("/usr/bin/env", ["-u", "LD_LIBRARY_PATH", "-u", "LD_PRELOAD", "timeout", "2", "iw", "dev", iface, "link"], output)
	if code != 0 or output.is_empty():
		_details_unavailable = true
		return "access point details not available on this system (the 'iw' program did not run)"
	var details := link_details(str(output[0]))
	if starting:
		_point_at_start = details["point"]
	return describe_link(details, "" if starting else _point_at_start)

## Runs `iw` for the adapter's link, like _link_line(). "" when it can't be asked.
func adapter_line() -> String:
	if _stations_unavailable:
		return ""
	var output := []
	var code := OS.execute("/usr/bin/env", ["-u", "LD_LIBRARY_PATH", "-u", "LD_PRELOAD", "timeout", "2", "iw", "dev", ADAPTER_IFACE, "station", "dump"], output)
	if code != 0 or output.is_empty():
		_stations_unavailable = true
		return "adapter link: figures not available on this system ('iw dev %s station dump' did not run)" % ADAPTER_IFACE
	var details := station_details(str(output[0]))
	var text := describe_stations(details, _stations_before)
	_stations_before = details
	if not _stations_raw_logged and int(details["joined"]) > 0:
		_stations_raw_logged = true
		_stations_raw = station_dump_for_log(str(output[0]))
	return text

## The line that shows what the system prints for the adapter's link; "" once
## it has been given out (or before there is one).
func take_adapter_raw() -> String:
	var raw := _stations_raw
	_stations_raw = ""
	return "" if raw.is_empty() else "adapter link, as the system prints it (addresses removed): " + raw

## Once a second while a stream runs, with the video frames shown in that
## second: the lines for a picture that has stopped (and one when it moves
## again), none otherwise.
func video_second(frames: int, host: String) -> PackedStringArray:
	if not _watching:
		return PackedStringArray()
	if frames > STALLED_FRAMES:
		if _stalled_for == 0:
			return PackedStringArray()
		var back := _lines(host, "picture moving again after %d s; " % _stalled_for)
		_stalled_for = 0
		return back
	_stalled_for += 1
	if _stalled_for > STALL_MAX_LINES:
		return PackedStringArray()
	var lines := _lines(host, "picture stopped for %d s; " % _stalled_for)
	var link := _link_line(_before.get("iface", ""), false)
	if not link.is_empty():
		lines[0] += " | " + link
	var adapter := adapter_line()
	if not adapter.is_empty():
		lines[0] += " | " + adapter
	if _stalled_for == STALL_MAX_LINES:
		lines.append("picture still stopped; no more of these lines until it has moved")
	return lines

## A stream has just started to `host`: one line now, then quietly.
func stream_started(host: String) -> PackedStringArray:
	_trouble_for = -1.0
	_watching = ip_number(host) >= 0
	if not _watching:
		return PackedStringArray(["not watched: the PC is not reached by a plain four-number address"])
	_since_line = 0.0
	_before = _read(host)
	var lines := PackedStringArray(["stream started; " + describe(_before, {}, 0.0)])
	var link := _link_line(_before.get("iface", ""), true)
	if not link.is_empty():
		lines.append(link)
	_stalled_for = 0
	_stations_before = {}
	var adapter := adapter_line()
	if not adapter.is_empty():
		lines.append(adapter)
	var raw := take_adapter_raw()
	if not raw.is_empty():
		lines.append(raw)
	return lines

## A stream has just ended without being asked to.
func stream_lost(host: String) -> PackedStringArray:
	if not _watching:
		return PackedStringArray()
	_trouble_for = 0.0
	_since_details = 0.0
	var lines := _lines(host, "stream lost; ")
	var link := _link_line(_before.get("iface", ""), false)
	if not link.is_empty():
		lines.append(link)
	return lines

func _lines(host: String, lead: String) -> PackedStringArray:
	var now := _read(host)
	var text := lead + describe(now, _before, _since_line)
	_before = now
	_since_line = 0.0
	return PackedStringArray([text])

## Every frame; returns the lines to log (mostly none).
func tick(delta: float, streaming: bool, host: String) -> PackedStringArray:
	if not _watching:
		return PackedStringArray()
	_since_line += delta
	var in_trouble := _trouble_for >= 0.0
	if in_trouble:
		_trouble_for += delta
		_since_details += delta
		if _trouble_for > TROUBLE_MAX_SECONDS:
			_trouble_for = -1.0
			return PackedStringArray()
	elif not streaming:
		return PackedStringArray()
	if _since_line < (TROUBLE_SECONDS if in_trouble else QUIET_SECONDS):
		return PackedStringArray()
	var lines := _lines(host, "")
	if not in_trouble:
		# The quiet minute's line: the adapter's link with it.
		var adapter := adapter_line()
		if not adapter.is_empty():
			lines.append(adapter)
		var raw := take_adapter_raw()
		if not raw.is_empty():
			lines.append(raw)
	if in_trouble and _since_details >= LINK_DETAILS_SECONDS:
		_since_details = 0.0
		var link := _link_line(_before.get("iface", ""), false)
		if not link.is_empty():
			lines.append(link)
	return lines

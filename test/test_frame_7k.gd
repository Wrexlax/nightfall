extends SceneTree

# Steam Frame 7k: reading the headset's network link out of the system's
# tables for the log (FrameNetworkWatch). The addresses below are examples
# from the ranges set aside for documentation and home networks.

const ROUTES := "Iface\tDestination\tGateway \tFlags\tRefCnt\tUse\tMetric\tMask\t\tMTU\tWindow\tIRTT\n" \
	+ "wlan0\t00000000\t0101A8C0\t0003\t0\t0\t600\t00000000\t0\t0\t0\n" \
	+ "wlan0\t0001A8C0\t00000000\t0001\t0\t0\t600\t00FFFFFF\t0\t0\t0\n" \
	+ "wlanap\t006433C6\t00000000\t0001\t0\t0\t0\t00FFFFFF\t0\t0\t0\n"

const NEIGHBOURS := "IP address       HW type     Flags       HW address            Mask     Device\n" \
	+ "192.168.1.1      0x1         0x2         02:00:00:00:00:01     *        wlan0\n" \
	+ "192.168.1.20     0x1         0x0         00:00:00:00:00:00     *        wlan0\n"

const WIRELESS := "Inter-| sta-|   Quality        |   Discarded packets               | Missed | WE\n" \
	+ " face | tus | link level noise |  nwid  crypt   frag  retry   misc | beacon | 22\n" \
	+ " wlan0: 0000   60.  -50.  -256        0      0      0      0      0        0\n"

const IW := "Connected to 02:00:00:00:00:01 (on wlan0)\n\tSSID: example\n\tfreq: 5745\n\tRX: 1 bytes (1 packets)\n" \
	+ "\tsignal: -55 dBm\n\trx bitrate: 866.7 MBit/s\n\ttx bitrate: 780.0 MBit/s VHT-MCS 8\n"

func _init() -> void:
	_addresses()
	_routes()
	_neighbours()
	_signal()
	_link()
	_sentences()
	_reading()
	_pace()
	_remembered()
	_power()
	_quality_tips()
	_steady_max()
	_second_link()
	_build_7z()
	print("All frame_7k tests passed")
	quit()

# 7z: the Frame's own wording of the adapter's link, as the 7y log printed it
# (addresses removed): no figure under "signal", the real one under the two
# "ack signal" lines, and retries never counted.
const FRAME_STATION_DUMP := "Station 02:00:00:00:00:03 (on wlanap)\n\tinactive time:\t1485 ms\n\trx bytes:\t5605279005\n\ttx retries:\t0\n\ttx failed:\t0\n\tsignal:  \t0 dBm\n\tsignal avg:\t0 dBm\n\ttx bitrate:\t1152.8 MBit/s 160MHz HE-MCS 5 HE-NSS 2 HE-GI 0 HE-DCM 0\n\trx bitrate:\t288.2 MBit/s 160MHz HE-MCS 1 HE-NSS 2 HE-GI 0 HE-DCM 0\n\tlast ack signal:-53 dBm\n\tavg ack signal:\t-52 dBm\n\tconnected time:\t3420 seconds\n"

func _build_7z() -> void:
	var frame := FrameNetworkWatch.station_details(FRAME_STATION_DUMP)
	assert(frame["dbm"] == -52 and frame["retries"] == 0 and roundi(frame["tx_mbit"]) == 1153, str(frame))
	var after := frame.duplicate()
	assert(FrameNetworkWatch.describe_stations(after, frame) == "adapter link: signal -52 dBm, sending at 1153 Mbit/s, receiving at 288; not heard for 1.5 s")
	assert(FrameNetworkWatch.station_details(FRAME_STATION_DUMP.replace("\tavg ack signal:\t-52 dBm\n", ""))["dbm"] == -53)
	assert("signal not reported" in FrameNetworkWatch.describe_stations(
		FrameNetworkWatch.station_details("Station 02:00:00:00:00:03 (on wlanap)\n\tsignal:  \t0 dBm\n"), {}))
	# "Head lock" as it was heard after 7y, and "disabled" for "disable".
	for heard in ["A Dlock.", "At lock.", "Dlock", "a d lock"]:
		assert(VoiceCommands.match_command(heard, false).get("id", "") == "headlock_toggle", heard)
	assert(VoiceCommands.match_command("Disabled headlock.", false).get("id", "") == "headlock_off")
	assert(VoiceCommands.match_command("Enabled passthrough", false).get("id", "") == "passthrough_on")
	assert(VoiceCommands.match_command("I looked at lock screens all day", false).is_empty())
	# Stream Link in a stream that isn't going through Meteor: the tooltip and the notice say so.
	for mode in 3:
		assert(FrameSecondLink.tip(mode, false, false) == FrameSecondLink.MODE_TIPS[mode])
		assert(FrameSecondLink.tip(mode, true, true) == FrameSecondLink.MODE_TIPS[mode])
		assert(FrameSecondLink.tip(mode, true, false) == FrameSecondLink.NO_METEOR_TIP)
	var tip_lines := FrameSecondLink.NO_METEOR_TIP.split("\n")
	assert(tip_lines.size() == 2 and tip_lines[0].length() <= 98 and tip_lines[1].length() <= 98)
	assert(FrameSecondLink.unavailable_note(false, false, false, false, 0) == "")
	assert("isn't going through Meteor" in FrameSecondLink.unavailable_note(true, false, false, false, 0))
	assert("newer Nightfall Meteor" in FrameSecondLink.unavailable_note(true, true, false, false, 0))
	assert("adapter isn't answering" in FrameSecondLink.unavailable_note(true, true, true, false, FrameSecondLink.MODE_BOTH))
	assert(FrameSecondLink.unavailable_note(true, true, true, false, FrameSecondLink.MODE_FIRST_ONLY) == "")
	assert(FrameSecondLink.unavailable_note(true, true, true, true, FrameSecondLink.MODE_SECOND_ONLY) == "")
	# Meteor's word on its depth offer, read with the Stream Link choice.
	assert(MeteorClient.parse_link_pick('{"service":"nightfall-meteor","link":{"choice":0,"rev":3},"depth":false}') == {"choice": 0, "rev": 3, "depth": false})
	assert(MeteorClient.parse_link_pick('{"service":"nightfall-meteor","link":{"choice":0,"rev":3},"depth":true}')["depth"] == true)
	assert(not MeteorClient.parse_link_pick('{"service":"nightfall-meteor","link":{"choice":0,"rev":3},"depth":"yes"}').has("depth"))
	assert(FrameSecondLink.depth_offer_is_news(-1, true, false) and FrameSecondLink.depth_offer_is_news(-1, false, true))
	assert(not FrameSecondLink.depth_offer_is_news(-1, true, true) and not FrameSecondLink.depth_offer_is_news(-1, false, false))
	assert(FrameSecondLink.depth_offer_is_news(0, true, false) and FrameSecondLink.depth_offer_is_news(1, false, true))
	# An offer this headset can't use is not asked about every two seconds.
	assert(not FrameSecondLink.depth_offer_is_news(1, true, false))
	var started_with := {"version": "0.9.0-sf11", "ports": {"https": 48984}, "depth": {"port": 47901}}
	StreamManager.take_depth_offer(started_with, {"version": "x", "ports": {"https": 1}})
	assert(started_with == {"version": "0.9.0-sf11", "ports": {"https": 48984}})
	StreamManager.take_depth_offer(started_with, {"depth": {"port": 47901, "width": 518}})
	assert(started_with["depth"] == {"port": 47901, "width": 518} and started_with["ports"] == {"https": 48984})
	# The AI 3D page's note.
	assert(UIController.frame_ai3d_note(false, false, true, false, false, false, false).begins_with("AI 3D on the Steam Frame uses"))
	assert(UIController.frame_ai3d_note(false, true, true, true, true, false, false) == "")
	assert(UIController.frame_ai3d_note(true, false, true, false, false, false, false) == "")
	assert(UIController.frame_ai3d_note(true, true, true, false, false, false, false) == "")       # no Meteor at all: nothing to say
	assert("depth switched off" in UIController.frame_ai3d_note(true, true, true, true, false, false, false))
	assert("filling in until it returns" in UIController.frame_ai3d_note(true, true, true, true, true, false, true))
	assert(UIController.frame_ai3d_note(true, true, true, true, true, false, false) == "")
	assert(UIController.frame_ai3d_note(true, true, true, true, false, true, false) == "")        # a headset model was the choice
	assert(UIController.frame_ai3d_note(true, true, false, true, false, false, false) == "")       # AI 3D off
	# The second screen that kept coming back: 0 staged, 0 applied in this app run, 1 saved.
	assert(SettingsController.virtual_count_changed(0, 0, 1, true))
	assert(not SettingsController.virtual_count_changed(1, 1, 1, true))
	assert(SettingsController.virtual_count_changed(2, 1, 1, true))
	assert(not SettingsController.virtual_count_changed(0, 0, 1, false))

func _addresses() -> void:
	assert(FrameNetworkWatch.ip_number("192.168.1.20") == 0xC0A80114)
	assert(FrameNetworkWatch.ip_number("my-pc.local") == -1)
	assert(FrameNetworkWatch.ip_number("fe80::1") == -1)
	assert(FrameNetworkWatch.ip_number("300.1.1.1") == -1)

func _routes() -> void:
	# On the home network: looked for directly on the Wi-Fi.
	var home := FrameNetworkWatch.route_for("192.168.1.20", ROUTES)
	assert(home["iface"] == "wlan0" and home["next"] == "192.168.1.20" and not home["through_router"])
	# On the wireless adapter's own network: that link, not the Wi-Fi.
	var adapter := FrameNetworkWatch.route_for("198.51.100.23", ROUTES)
	assert(adapter["iface"] == "wlanap" and not adapter["through_router"])
	# Anywhere else: through the router.
	var far := FrameNetworkWatch.route_for("203.0.113.9", ROUTES)
	assert(far["iface"] == "wlan0" and far["next"] == "192.168.1.1" and far["through_router"])
	# No table, or a name instead of an address: nothing.
	assert(FrameNetworkWatch.route_for("192.168.1.20", "").is_empty())
	assert(FrameNetworkWatch.route_for("my-pc.local", ROUTES).is_empty())

func _neighbours() -> void:
	assert(FrameNetworkWatch.neighbour_state("192.168.1.1", NEIGHBOURS) == "answered")
	assert(FrameNetworkWatch.neighbour_state("192.168.1.20", NEIGHBOURS) == "no answer")
	assert(FrameNetworkWatch.neighbour_state("192.168.1.99", NEIGHBOURS) == "not looked for")
	# "192.168.1.2" must not match the line for "192.168.1.20".
	assert(FrameNetworkWatch.neighbour_state("192.168.1.2", NEIGHBOURS) == "not looked for")

func _signal() -> void:
	assert(FrameNetworkWatch.signal_dbm("wlan0", WIRELESS) == -50)
	assert(FrameNetworkWatch.signal_dbm("wlanap", WIRELESS) == 0)
	assert(FrameNetworkWatch.signal_dbm("wlan0", "") == 0)

func _link() -> void:
	var details := FrameNetworkWatch.link_details(IW)
	assert(details["connected"] and details["mhz"] == 5745 and details["dbm"] == -55)
	assert(is_equal_approx(details["mbit"], 780.0))
	assert(FrameNetworkWatch.band(5745) == "5 GHz" and FrameNetworkWatch.band(2437) == "2.4 GHz" and FrameNetworkWatch.band(6115) == "6 GHz")
	assert(not FrameNetworkWatch.link_details("Not connected.\n")["connected"])

func _sentences() -> void:
	var before := {"iface": "wlan0", "up": true, "dbm": -50, "rx": 1000.0, "tx": 500.0, "neighbour": "answered", "through_router": false}
	var now := {"iface": "wlan0", "up": true, "dbm": -52, "rx": 1030.0, "tx": 520.0, "neighbour": "no answer", "through_router": false}
	var text := FrameNetworkWatch.describe(now, before, 10.0)
	assert(text == "wlan0: connected, signal -52 dBm; 3 packets a second arriving, 2 leaving; the PC: no answer")
	assert(FrameNetworkWatch.describe({}, before, 10.0).begins_with("no route to the PC"))
	# Neither an address nor a network's name ever reaches the log.
	var details := FrameNetworkWatch.link_details(IW)
	for line in [text, FrameNetworkWatch.describe_link(details, ""), FrameNetworkWatch.describe_link(details, "02:00:00:00:00:02")]:
		assert(not line.contains("192.168") and not line.contains("02:00") and not line.contains("example"))
	assert(FrameNetworkWatch.describe_link(details, "02:00:00:00:00:01").ends_with("the same one as when the stream began"))
	assert(FrameNetworkWatch.describe_link(details, "02:00:00:00:00:02").ends_with("NOT the one the stream began on"))

# 7m: the graphics-chip depth model is remembered from one run to the next
# like the other two (in 7j to 7l every start went back to Detail).
func _remembered() -> void:
	for model in SettingsController.FRAME_DEPTH_LABELS.size():
		var source := AppSettings.new()
		source.frame_depth_model = model
		var config := ConfigFile.new()
		SettingsPersistence.write_app(config, source)
		var loaded := AppSettings.new()
		SettingsPersistence.read_app(config, loaded, true, [0, 6, 7])
		assert(loaded.frame_depth_model == model)

# 7q: Quality's tooltip is the one for the choice showing.
func _quality_tips() -> void:
	var seen := {}
	for choice in SettingsController.FRAME_DEPTH_LABELS + ["Meteor", "Needs Meteor"]:
		var tip := UIController.frame_depth_quality_tip(choice)
		assert(UIController.FRAME_DEPTH_QUALITY_TIPS.has(choice))
		assert(not seen.has(tip))   # each its own
		seen[tip] = true
		var lines := tip.split("\n")
		assert(lines.size() <= 2)
		for line in lines:
			assert(line.length() <= 100)
	# A label nobody wrote a tooltip for still gets a true sentence.
	assert(UIController.frame_depth_quality_tip("something new").contains("Nightfall Meteor"))

# 7r: Cursor Steady's Max, and the order the button goes through.
func _steady_max() -> void:
	var main_script: GDScript = load("res://main.gd")
	# The share of the gap closed grows with time and never passes all of it.
	var a_frame: float = main_script.steady_max_share(1.0 / 90.0)
	assert(a_frame > 0.0 and a_frame < 0.05)
	assert(is_equal_approx(main_script.steady_max_share(main_script.STEADY_MAX_SECONDS), 1.0 - exp(-1.0)))
	assert(main_script.steady_max_share(0.0) == 0.0 and main_script.steady_max_share(-1.0) == 0.0)
	# The same time passes the same share whatever the display rate: 12
	# frames at 144 Hz close what 6 frames at 72 Hz do.
	var left_144 := pow(1.0 - main_script.steady_max_share(1.0 / 144.0), 12)
	var left_72 := pow(1.0 - main_script.steady_max_share(1.0 / 72.0), 6)
	assert(is_equal_approx(left_144, left_72))
	# Every level is in the button's round once, Max after High.
	var order: Array = main_script.POINTER_STEADY_ORDER
	assert(order.size() == 5 and order.find(main_script.POINTER_STEADY_MAX) == order.find(2) + 1)
	for level in 5:
		assert(order.count(level) == 1)
	# A new install starts on Headset: GPU.
	assert(AppSettings.new().frame_depth_model == SettingsController.FRAME_DEPTH_GPU_MODEL)

# 7n: the battery line.
func _power() -> void:
	# The system's own figure, in millionths of a watt, either sign.
	assert(is_equal_approx(FramePowerWatch.watts("11400000\n", "", ""), 11.4))
	assert(is_equal_approx(FramePowerWatch.watts("-11400000", "", ""), 11.4))
	# Or current times voltage: 3 A at 3.8 V.
	assert(is_equal_approx(FramePowerWatch.watts("", "-3000000\n", "3800000\n"), 11.4))
	assert(FramePowerWatch.watts("", "", "3800000") < 0.0)
	# A controller's battery is not the headset's.
	assert(FramePowerWatch.is_own_battery("Battery\n", ""))
	assert(not FramePowerWatch.is_own_battery("Battery\n", "Device\n"))
	assert(not FramePowerWatch.is_own_battery("USB\n", ""))
	assert(FramePowerWatch.describe({"percent": 87, "status": "discharging", "watts": 11.4}) == "battery 87%, discharging, 11.4 W")
	assert(FramePowerWatch.describe({"percent": 100, "status": "full", "watts": -1.0}) == "battery 100%, full (the system gives no power figure)")
	assert(FramePowerWatch.describe({}).begins_with("no battery"))
	# 7p: the average of a minute's readings, with the lowest and highest.
	assert(FramePowerWatch.describe({"percent": 72, "status": "discharging", "watts": 17.2}, 18.4, 15.9, 22.4)
		== "battery 72%, discharging, 18.4 W on average since the last line (15.9 to 22.4)")
	# Whatever this machine has, reading it must not fail.
	assert(FramePowerWatch.read("").is_empty())
	var watch := FramePowerWatch.new()
	watch.sample()
	watch.sample()
	assert(not watch.line().is_empty())

func _reading() -> void:
	# The system's tables say they are zero bytes long and still have text.
	if FileAccess.file_exists("/proc/self/status"):
		assert(FrameNetworkWatch.file_text("/proc/self/status").contains("Name:"))
	assert(FrameNetworkWatch.file_text("/no/such/file") == "")
	# Where this machine has a route table, a stream's first line is read from it.
	var routes := FrameNetworkWatch.file_text(FrameNetworkWatch.ROUTES)
	if routes.contains("00000000"):
		var lines := FrameNetworkWatch.new().stream_started("192.0.2.7")
		assert(not lines[0].contains("no route"))

func _pace() -> void:
	# Before any stream, and to a PC known by name: silence.
	var watch := FrameNetworkWatch.new()
	assert(watch.tick(120.0, true, "192.168.1.20").is_empty())
	assert(watch.stream_started("my-pc.local").size() == 1)
	assert(watch.tick(120.0, true, "my-pc.local").is_empty())
	assert(watch.stream_lost("my-pc.local").is_empty())
	# A stream to an address (this machine has no such route, which is a line too).
	watch = FrameNetworkWatch.new()
	assert(watch.stream_started("192.0.2.7").size() >= 1)
	assert(watch.tick(FrameNetworkWatch.QUIET_SECONDS - 1.0, true, "192.0.2.7").is_empty())
	assert(watch.tick(2.0, true, "192.0.2.7").size() >= 1)
	# Lost: a line at once, then one every few seconds though nothing streams.
	assert(watch.stream_lost("192.0.2.7").size() >= 1)
	assert(watch.tick(FrameNetworkWatch.TROUBLE_SECONDS - 1.0, false, "192.0.2.7").is_empty())
	assert(watch.tick(2.0, false, "192.0.2.7").size() >= 1)
	# Until the next stream starts.
	watch.stream_started("192.0.2.7")
	assert(watch.tick(FrameNetworkWatch.TROUBLE_SECONDS + 1.0, false, "192.0.2.7").is_empty())

# 7s: the second link (Multi-Link through Meteor): finding the PC on the
# adapter's link, and the sentence for the log.
const STATION_DUMP := "Station 02:00:00:00:00:03 (on wlanap)\n" \
	+ "\tinactive time:\t12 ms\n" \
	+ "\trx bytes:\t81234567\n" \
	+ "\trx packets:\t912345\n" \
	+ "\ttx bytes:\t9123456789\n" \
	+ "\ttx packets:\t8123456\n" \
	+ "\ttx retries:\t5120\n" \
	+ "\ttx failed:\t14\n" \
	+ "\trx drop misc:\t3\n" \
	+ "\tsignal:  \t-47 [-49, -51] dBm\n" \
	+ "\tsignal avg:\t-46 dBm\n" \
	+ "\ttx bitrate:\t1200.9 MBit/s 80MHz HE-MCS 11 HE-NSS 2 HE-GI 0 HE-DCM 0\n" \
	+ "\trx bitrate:\t1080.6 MBit/s 80MHz HE-MCS 10 HE-NSS 2 HE-GI 0 HE-DCM 0\n" \
	+ "\tconnected time:\t1432 seconds\n"

const LINK_ROUTES := "Iface\tDestination\tGateway \tFlags\tRefCnt\tUse\tMetric\tMask\t\tMTU\tWindow\tIRTT\n" \
	+ "wlan0\t00000000\t0101A8C0\t0003\t0\t0\t600\t00000000\t0\t0\t0\n" \
	+ "wlan0\t0001A8C0\t00000000\t0001\t0\t0\t600\t00FFFFFF\t0\t0\t0\n" \
	+ "wlanap\t006433C6\t00000000\t0001\t0\t0\t0\t00FFFFFF\t0\t0\t0\n"
const LINK_NEIGHBOURS := "IP address       HW type     Flags       HW address            Mask     Device\n" \
	+ "192.168.1.1      0x1         0x2         02:00:00:00:00:01     *        wlan0\n" \
	+ "192.168.1.20     0x1         0x2         02:00:00:00:00:02     *        wlan0\n" \
	+ "198.51.100.23    0x1         0x2         02:00:00:00:00:03     *        wlanap\n" \
	+ "198.51.100.40    0x1         0x0         00:00:00:00:00:00     *        wlanap\n"

func _second_link() -> void:
	# Only what answered on that link counts.
	assert(FrameSecondLink.neighbours_on("wlanap", LINK_NEIGHBOURS) == PackedStringArray(["198.51.100.23"]))
	assert(FrameSecondLink.neighbours_on("wlan0", LINK_NEIGHBOURS).size() == 2)
	assert(FrameSecondLink.neighbours_on("wlanap", "").is_empty())
	# A stream on Wi-Fi: the PC's address on the adapter's link is the candidate.
	var found := FrameSecondLink.candidates("192.168.1.20", LINK_ROUTES, LINK_NEIGHBOURS)
	assert(found["iface"] == "wlanap" and found["first_iface"] == "wlan0")
	assert(found["candidates"] == PackedStringArray(["198.51.100.23"]))
	# A stream on the adapter's link, a PC known by name, nobody on the adapter: no.
	assert(FrameSecondLink.candidates("198.51.100.23", LINK_ROUTES, LINK_NEIGHBOURS).has("why"))
	assert(FrameSecondLink.candidates("my-pc.local", LINK_ROUTES, LINK_NEIGHBOURS).has("why"))
	assert(FrameSecondLink.candidates("192.168.1.20", LINK_ROUTES, "").has("why"))
	# The log's sentence: counts since the last line, and never an address.
	var before := {"first_link": 1000, "second_link": 900, "both": 500, "only_first": 10, "only_second": 2, "second_first": 300}
	var now := {"first_link": 31000, "second_link": 30800, "both": 30400, "only_first": 110, "only_second": 42, "second_first": 12300}
	var text := FrameSecondLink.describe(now, before, "wlan0", "wlanap")
	assert(text.begins_with("wlan0 30,000 packets, wlanap 29,900; wlanap's copy came first for 40%"))
	assert(text.contains("both 29,900") and text.contains("only wlan0 100 (lost on wlanap)") and text.contains("only wlanap 40 (lost on wlan0: saved)"))
	assert(not text.contains("192.168") and not text.contains("10.35"))
	assert(FrameSecondLink.describe({"first_link": 500, "second_link": 0}, {}, "wlan0", "wlanap").ends_with("nothing is arriving over wlanap"))
	assert(FrameSecondLink.describe({}, {}, "wlan0", "wlanap").contains("no second link"))
	assert(FrameSecondLink._thousands(1234567) == "1,234,567" and FrameSecondLink._thousands(999) == "999")
	# 7t: with each packet counted once the share is exact and never over 100.
	var counted := {"first_link": 13522, "second_link": 14289, "both": 14250, "only_first": 0, "only_second": 39, "second_first": 14100, "packets": 14289}
	assert(FrameSecondLink.describe(counted, {}, "wlan0", "wlanap").contains("came first for 99%"))
	counted["second_first"] = 20000
	assert(FrameSecondLink.describe(counted, {}, "wlan0", "wlanap").contains("came first for 100%"))
	# The three choices, and the 7s on/off switch read as one of them.
	assert(FrameSecondLink.MODE_LABELS == ["Multi-Link", "Wi-Fi only", "Adapter first"])
	# 7u: a tooltip for each, two lines at most, none too long.
	assert(FrameSecondLink.MODE_TIPS.size() == FrameSecondLink.MODE_LABELS.size())
	for tip in FrameSecondLink.MODE_TIPS:
		var lines: PackedStringArray = tip.split("\n")
		assert(lines.size() <= 2)
		for line in lines:
			assert(line.length() <= 98)
	# Meteor numbers the choices its own way; there and back is the same choice.
	assert(FrameSecondLink.wire_choice(FrameSecondLink.MODE_BOTH) == 0)
	assert(FrameSecondLink.wire_choice(FrameSecondLink.MODE_SECOND_ONLY) == 1)
	assert(FrameSecondLink.wire_choice(FrameSecondLink.MODE_FIRST_ONLY) == 2)
	for mode in 3:
		assert(FrameSecondLink.mode_of_wire(FrameSecondLink.wire_choice(mode)) == mode)
	assert(FrameSecondLink.mode_of_wire(77) == FrameSecondLink.MODE_FIRST_ONLY)
	# A pick in Meteor's menu is followed when it is news...
	assert(FrameSecondLink.follows_pick(3, 2, false))
	assert(FrameSecondLink.follows_pick(1, -1, false))
	# ...not when it has been seen, nor when Meteor has only just started
	# (number 0), nor when the headset's own choice is the newer one.
	assert(not FrameSecondLink.follows_pick(3, 3, false))
	assert(not FrameSecondLink.follows_pick(0, 3, false))
	assert(not FrameSecondLink.follows_pick(0, -1, false))
	assert(not FrameSecondLink.follows_pick(4, -1, true))
	assert(not FrameSecondLink.follows_pick(4, 3, true))
	# Meteor's small page for the pick: only its own answer counts.
	assert(MeteorClient.parse_link_pick('{"service":"nightfall-meteor","link":{"choice":2,"rev":7}}') == {"choice": 2, "rev": 7})
	assert(MeteorClient.parse_link_pick('{"service":"something-else","link":{"choice":2,"rev":7}}').is_empty())
	assert(MeteorClient.parse_link_pick('{"service":"nightfall-meteor"}').is_empty())
	assert(MeteorClient.parse_link_pick("<html>not found</html>").is_empty())
	assert(MeteorClient.parse_link_pick('{"service":"nightfall-meteor","link":{"choice":9,"rev":7}}')["choice"] == 2)
	# 7v: the log's line when the headset asks for Wi-Fi's copies as well.
	assert(FrameSecondLink.describe_hold({"hold_reason": 1, "hold_answered_ms": 0})
		== "asked Meteor for Wi-Fi's copies as well: nothing came over the adapter for a fifth of a second")
	assert(FrameSecondLink.describe_hold({"hold_reason": 2, "hold_missing": 37, "hold_answered_ms": 41})
		== "asked Meteor for Wi-Fi's copies as well: 37 of the adapter's packets went missing in a tenth of a second; Wi-Fi's first packet came 41 ms later")
	assert("asked 3 times this second" in FrameSecondLink.describe_hold({"hold_reason": 1}, 3))
	# The voice log says how many times the model listened to a clip.
	assert(VoiceTyping.passes_text(1) == "listened once")
	assert(VoiceTyping.passes_text(3) == "listened 3 times")
	assert(VoiceTyping.passes_text(0) == "listening not counted")
	assert(VoiceTyping.stretches_text([15.4]) == "" and VoiceTyping.stretches_text([]) == "")
	assert(VoiceTyping.stretches_text(PackedFloat32Array([15.4, 6.0])) == " (15.4 s, then 6.0 s)")
	# 7w: the adapter's own link, as the headset (its access point) sees it.
	var joined := FrameNetworkWatch.station_details(STATION_DUMP)
	assert(joined == {"joined": 1, "dbm": -47, "tx_mbit": 1200.9, "rx_mbit": 1080.6, "retries": 5120, "failed": 14, "quiet_ms": 12})
	assert(FrameNetworkWatch.describe_stations(joined, {})
		== "adapter link: signal -47 dBm, sending at 1201 Mbit/s, receiving at 1081")
	var later := joined.duplicate()
	later["retries"] = 5400
	later["failed"] = 19
	later["quiet_ms"] = 2300
	assert(FrameNetworkWatch.describe_stations(later, joined)
		== "adapter link: signal -47 dBm, sending at 1201 Mbit/s, receiving at 1081; since the last look 280 packets sent again, 5 given up on; not heard for 2.3 s")
	# The adapter's address is in what the system prints and nowhere in what is kept or said.
	assert(not "02:00:00:00:00:03" in str(joined) and not "02:00" in FrameNetworkWatch.describe_stations(later, joined))
	assert(FrameNetworkWatch.describe_stations(FrameNetworkWatch.station_details(""), {})
		== "adapter link: nothing has joined (the PC's adapter is not connected to the headset)")
	# 7y: what the system prints, for the log: no address in it.
	var raw_line := FrameNetworkWatch.station_dump_for_log(STATION_DUMP + "Station 02:00:00:00:00:09 (on wlanap)\n\tsignal:  \t-80 dBm\n")
	assert(raw_line.begins_with("Station (address) (on wlanap) | inactive time: 12 ms | "), raw_line)
	assert(not "02:00" in raw_line and "signal:   -47 [-49, -51] dBm" in raw_line and not "-80" in raw_line, raw_line)
	# A picture that stops gets a line a second, and one when it moves again.
	var watch := FrameNetworkWatch.new()
	assert(watch.video_second(0, "192.168.1.20").is_empty())  # not watching before a stream has started
	watch.stream_started("192.168.1.20")
	assert(watch.video_second(100, "192.168.1.20").is_empty())
	assert(watch.video_second(FrameNetworkWatch.STALLED_FRAMES + 1, "192.168.1.20").is_empty())
	var stopped := watch.video_second(0, "192.168.1.20")
	assert(stopped.size() == 1 and stopped[0].begins_with("picture stopped for 1 s; "), str(stopped))
	assert(watch.video_second(1, "192.168.1.20")[0].begins_with("picture stopped for 2 s; "))
	var moving := watch.video_second(90, "192.168.1.20")
	assert(moving.size() == 1 and moving[0].begins_with("picture moving again after 2 s; "), str(moving))
	assert(watch.video_second(90, "192.168.1.20").is_empty())
	# A picture that stays stopped (a still screen) doesn't fill the log.
	var said := 0
	for second in FrameNetworkWatch.STALL_MAX_LINES + 20:
		said += watch.video_second(0, "192.168.1.20").size()
	assert(said == FrameNetworkWatch.STALL_MAX_LINES + 1, str(said))
	assert(watch.video_second(80, "192.168.1.20")[0].begins_with("picture moving again after %d s; " % (FrameNetworkWatch.STALL_MAX_LINES + 20)))
	# 7x: the controls over both links show in the same line.
	assert(FrameSecondLink.describe_controls({}, {}, "wlan0", "wlanap") == "")
	assert(FrameSecondLink.describe_controls({"control_first": 0, "control_second": 0}, {}, "wlan0", "wlanap") == "")
	assert(FrameSecondLink.describe_controls({"control_first": 1500, "control_second": 2100}, {"control_first": 1000, "control_second": 1100}, "wlan0", "wlanap")
		== "; controls: wlan0 500, wlanap 1,000")
	assert(FrameSecondLink.describe({"first_link": 0, "second_link": 0, "control_first": 0, "control_second": 40}, {}, "wlan0", "wlanap")
		== "wlan0 0 packets, wlanap 0: nothing is arriving over wlanap; controls: wlan0 0, wlanap 40")
	# 7y: "head lock" as it keeps being heard, and "disable" / "enable".
	for heard in ["Edlock.", "Ad lock.", "Headset lock", "ed lock"]:
		assert(VoiceCommands.match_command(heard, false).get("id", "") == "headlock_toggle", heard)
	assert(VoiceCommands.match_command("Disable headlock.", false).get("id", "") == "headlock_off")
	assert(VoiceCommands.match_command("enable head lock", false).get("id", "") == "headlock_on")
	assert(VoiceCommands.match_command("Disable passthrough", false).get("id", "") == "passthrough_off")
	assert(VoiceCommands.match_command("enable passthrough", false).get("id", "") == "passthrough_on")
	# A sentence that merely starts that way is not a command.
	assert(VoiceCommands.match_command("Disable the firewall on my router", false).is_empty())
	# 7y: Meteor's maps over two connections: each is kept the first time it arrives.
	assert(MeteorDepthReceiver.is_late_copy(500, 3, 500, 3, true))       # the same map again
	assert(MeteorDepthReceiver.is_late_copy(498, 3, 500, 3, true))       # one the other link brought already
	assert(not MeteorDepthReceiver.is_late_copy(501, 3, 500, 3, true))   # a new one
	assert(not MeteorDepthReceiver.is_late_copy(5, 4, 500, 3, true))     # a new stream
	assert(not MeteorDepthReceiver.is_late_copy(5, 3, 5000, 3, true))    # the numbers started again
	assert(not MeteorDepthReceiver.is_late_copy(498, 3, 500, 3, false))  # one connection: as before
	var maps := MeteorDepthReceiver.new()
	maps._hosts[1] = "the second link"
	var one_map := func(frame: int) -> Dictionary:
		return {"frame": frame, "epoch": 3, "map": PackedByteArray([1]), "width": 1, "height": 1, "latency_us": 0}
	maps._store(one_map.call(10), 1)
	maps._store(one_map.call(10), 0)
	maps._store(one_map.call(11), 0)
	maps._store(one_map.call(11), 1)
	maps._store(one_map.call(12), 1)
	assert(maps.maps_received == 3 and maps.maps_by_link == [1, 2] and maps.newest_frame == 12, str(maps.maps_by_link))
	assert(maps.pick(11)["frame"] == 11 and maps.pick(0)["frame"] == 12)
	# Which link carries the stream, for the "Adapter first" notices.
	assert(FrameSecondLink.carrier(0, 900, "") == "adapter")
	assert(FrameSecondLink.carrier(900, 0, "adapter") == "wifi")
	assert(FrameSecondLink.carrier(900, 900, "wifi") == "wifi")
	assert(FrameSecondLink.carrier(0, 0, "adapter") == "adapter")
	for was_on in [true, false]:
		var config := ConfigFile.new()
		SettingsPersistence.write_app(config, AppSettings.new())
		config.erase_section_key("display", "frame_link_mode")
		config.set_value("display", "frame_second_link", was_on)
		var loaded := AppSettings.new()
		SettingsPersistence.read_app(config, loaded, true, [0, 6, 7])
		assert(loaded.frame_link_mode == (FrameSecondLink.MODE_BOTH if was_on else FrameSecondLink.MODE_FIRST_ONLY))

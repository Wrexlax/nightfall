class_name FrameSecondLink
extends RefCounted

## Steam Frame: the stream's picture and sound over two network paths at once
## ("Multi-Link" for a stream that passes through Nightfall Meteor).
##
## The headset reaches the PC over the home Wi-Fi and over the wireless
## adapter's direct link (the headset is that link's access point, the PC's
## adapter its one client). Steam's own streaming sends its packets over both
## and uses whichever copy arrives first. Here the three parts are:
##
## - this file finds the PC's address on the link the stream is NOT using and
##   checks that the Meteor answering there is the stream's own (same key);
## - the stream library then sends its video and audio pings there as well
##   (0004-second-link.patch), which is the request;
## - Meteor sends a copy of each video and audio packet to both addresses
##   (meteor/src/proxy.rs, "second-link").
##
## First build of this (7s): picture and sound only. The controls still use
## the one link the stream started on, so a link that dies outright still
## ends the stream. What this build is for is the counts in the log.
##
## No address is logged: links are named by their interface.

## Which links carry the picture and sound (AppSettings.frame_link_mode), and
## the names on the Stream Link button. "First" is the link the stream started
## on (Wi-Fi, for now always), "second" the other (the adapter's).
const MODE_BOTH := 0
const MODE_FIRST_ONLY := 1
const MODE_SECOND_ONLY := 2
const MODE_LABELS: Array[String] = ["Multi-Link", "Wi-Fi only", "Adapter first"]
## The button's tooltip for each (two lines at most).
const MODE_TIPS: Array[String] = [
	"Picture and sound over Wi-Fi and the wireless adapter at once; the first copy to arrive is used.\nThe steadiest. Needs the adapter and Meteor on the PC; can also be chosen in Meteor's menu.",
	"Picture and sound over Wi-Fi alone; the wireless adapter is not used.\nCan also be chosen in Meteor's menu on the PC.",
	"Picture and sound over the adapter alone while its signal holds. If it is lost the stream moves\nto Wi-Fi by itself, and back when the adapter returns. Can also be chosen in Meteor's menu.",
]

## The tooltip while a stream runs that doesn't pass through Meteor: none of
## the choices can do anything in it.
const NO_METEOR_TIP := "Stream Link needs Nightfall Meteor on your PC, and this stream isn't going through Meteor.\nStart Meteor on the PC, then reconnect. Until then the stream is over Wi-Fi alone."

## The Stream Link button's tooltip: the chosen mode's, or NO_METEOR_TIP.
static func tip(mode: int, streaming: bool, through_meteor: bool) -> String:
	if streaming and not through_meteor:
		return NO_METEOR_TIP
	return MODE_TIPS[clampi(mode, 0, MODE_TIPS.size() - 1)]

## What to tell someone who has just changed Stream Link when the choice can't
## take effect in the stream that is running; "" when it can, or no stream is.
## `offers`: this stream's Meteor knows second links; `found`: the PC has been
## found on the adapter's link.
static func unavailable_note(streaming: bool, through_meteor: bool, offers: bool, found: bool, mode: int) -> String:
	if not streaming:
		return ""
	if not through_meteor:
		return "Stream Link needs Nightfall Meteor on your PC. This stream isn't going through Meteor."
	if not offers:
		return "Stream Link needs a newer Nightfall Meteor on your PC (0.9.0-sf3 or later)."
	if not found and mode != MODE_FIRST_ONLY:
		return "The PC's wireless adapter isn't answering: streaming over Wi-Fi alone. Still looking for it."
	return ""

## Whether Meteor's word on its depth offer is news to act on. `flag`: what
## it said the last time (-1: not asked in this stream yet); `offered`: what
## it says now; `had`: whether this stream has a depth offer from it. At the
## first look the stream's own offer is what it is compared with (the offer
## may have changed between the stream's start and that look); after that
## only a change of Meteor's word counts, so that an offer this headset can't
## use is not asked about again every two seconds.
static func depth_offer_is_news(flag: int, offered: bool, had: bool) -> bool:
	if flag < 0:
		return offered != had
	return offered != (flag == 1)

## The same three choices as Meteor numbers them (its menu, its answer's
## "link" entry and the stream's pings): 0 both, 1 the adapter first, 2 Wi-Fi
## only. The two numberings swap 1 and 2, so one table turns either into the other.
const _OTHER_NUMBERING: Array[int] = [0, 2, 1]

static func wire_choice(mode: int) -> int:
	return _OTHER_NUMBERING[clampi(mode, 0, 2)]

static func mode_of_wire(choice: int) -> int:
	return _OTHER_NUMBERING[clampi(choice, 0, 2)]

## Whether a pick seen in Meteor's answer is one to follow. `rev` is the number
## of the last pick made in Meteor's menu (0: none since Meteor started, so
## there is nothing to follow, and a Meteor that has just restarted doesn't
## undo the headset's choice); `seen` the last number this headset saw (-1: it
## hasn't looked yet); `untold` whether the choice was changed on the headset
## while Meteor could not be told, in which case the headset's is the newer.
static func follows_pick(rev: int, seen: int, untold: bool) -> bool:
	return rev != 0 and rev != seen and not untold

## The log's sentence for the stream library asking Meteor for Wi-Fi's copies
## as well ("Adapter first"; see LiSetSecondLinkWatch): why, and how quickly
## Wi-Fi's first packet came if that is known yet. `times` is how many times it
## asked since the last look (more than one in a second is a link at its edge).
static func describe_hold(counts: Dictionary, times: int = 1) -> String:
	var text := "asked Meteor for Wi-Fi's copies as well: "
	if int(counts.get("hold_reason", 0)) == 2:
		text += "%d of the adapter's packets went missing in a tenth of a second" % int(counts.get("hold_missing", 0))
	else:
		text += "nothing came over the adapter for a fifth of a second"
	if times > 1:
		text += " (asked %d times this second)" % times
	var answered := int(counts.get("hold_answered_ms", 0))
	if answered > 0:
		text += "; Wi-Fi's first packet came %d ms later" % answered
	return text

## Which link is carrying the stream, from the packets that came over each in
## the last second: "adapter", "wifi", or `before` when both or neither did.
static func carrier(first_packets: int, second_packets: int, before: String) -> String:
	if second_packets > 0 and first_packets == 0:
		return "adapter"
	if first_packets > 0 and second_packets == 0:
		return "wifi"
	return before

## The adapter's link on the headset.
const ADAPTER_IFACE := "wlanap"
## A line in the log this often while a second link is in use.
const LOG_SECONDS := 10.0

## The addresses that answered on `iface`, from the text of /proc/net/arp.
static func neighbours_on(iface: String, neighbours_text: String) -> PackedStringArray:
	var found := PackedStringArray()
	for line in neighbours_text.split("\n").slice(1):
		var cells := line.split(" ", false)
		if cells.size() >= 6 and cells[5] == iface and (cells[2].hex_to_int() & 0x2) != 0:
			found.append(cells[0])
	return found

## Where a second link could go for a stream to `host`:
## { "iface", "candidates" } with the PC's possible addresses there, or
## { "why" } saying why there is none.
static func candidates(host: String, routes_text: String, neighbours_text: String) -> Dictionary:
	var route := FrameNetworkWatch.route_for(host, routes_text)
	if route.is_empty():
		return {"why": "the stream's own link was not found (the PC is not reached by a plain address)"}
	if route["iface"] == ADAPTER_IFACE:
		# The other way round needs the PC's Wi-Fi address, which nothing on
		# the headset knows yet.
		return {"why": "the stream itself is on the adapter's link; adding Wi-Fi as the second is not built yet"}
	var found := neighbours_on(ADAPTER_IFACE, neighbours_text)
	if found.is_empty():
		return {"why": "no PC has answered on the adapter's link (%s)" % ADAPTER_IFACE}
	return {"iface": ADAPTER_IFACE, "first_iface": route["iface"], "candidates": found}

static func _thousands(number: int) -> String:
	var digits := str(absi(number))
	var out := ""
	while digits.length() > 3:
		out = "," + digits.right(3) + out
		digits = digits.left(digits.length() - 3)
	return ("-" if number < 0 else "") + digits + out

## The counts since `before` as a sentence for the log.
static func describe(now: Dictionary, before: Dictionary, first_name: String, second_name: String) -> String:
	if now.is_empty():
		return "this build's stream library has no second link"
	var first := int(now.get("first_link", 0)) - int(before.get("first_link", 0))
	var second := int(now.get("second_link", 0)) - int(before.get("second_link", 0))
	var both := int(now.get("both", 0)) - int(before.get("both", 0))
	var only_first := int(now.get("only_first", 0)) - int(before.get("only_first", 0))
	var only_second := int(now.get("only_second", 0)) - int(before.get("only_second", 0))
	var won := int(now.get("second_first", 0)) - int(before.get("second_first", 0))
	var text := "%s %s packets, %s %s" % [first_name, _thousands(first), second_name, _thousands(second)]
	var controls := describe_controls(now, before, first_name, second_name)
	if second <= 0:
		return text + ": nothing is arriving over %s" % second_name + controls
	# Each packet once, however many copies came (a 7s library doesn't count
	# that, and it is worked out roughly: one line there said 103%).
	var packets := int(now.get("packets", 0)) - int(before.get("packets", 0))
	if packets <= 0:
		packets = first + second - both
	text += "; %s's copy came first for %d%%" % [second_name, clampi(roundi(100.0 * won / maxi(packets, 1)), 0, 100)]
	var settled := both + only_first + only_second
	if settled > 0:
		text += "; of %s old enough to judge: both %s, only %s %s (lost on %s), only %s %s (lost on %s: saved)" % [
			_thousands(settled), _thousands(both), first_name, _thousands(only_first), second_name,
			second_name, _thousands(only_second), first_name]
	return text + controls

## The controls' share of the line above, when they go over both links: how
## many of their packets came over each. "" when they don't.
static func describe_controls(now: Dictionary, before: Dictionary, first_name: String, second_name: String) -> String:
	var first := int(now.get("control_first", 0)) - int(before.get("control_first", 0))
	var second := int(now.get("control_second", 0)) - int(before.get("control_second", 0))
	if first <= 0 and second <= 0:
		return ""
	return "; controls: %s %s, %s %s" % [first_name, _thousands(maxi(first, 0)), second_name, _thousands(maxi(second, 0))]

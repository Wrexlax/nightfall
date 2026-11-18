class_name FrameSessionWatch
extends RefCounted

## Steam Frame: what Nightfall does while SteamVR isn't showing it (the
## headset taken off, or another app in front). OpenXR calls that session
## state SYNCHRONIZED: the app keeps running and nothing it draws is shown.
##
## Found in a log of 2026-11-17, the first with the headset left lying while
## Nightfall ran: 763,949 lines of
##   ERROR: Condition "image_acquired" is true. Returning: true
##      at: acquire (modules/openxr/openxr_api.cpp:186)
## about 1,000 a second, 89 MB in 23 minutes. In that state the engine still
## takes the next picture of every composition layer each frame, and hands
## none back, because handing back is part of composing a frame that is to be
## shown. Every later take fails with that error.
##
## The engine only takes a layer's picture when the layer's viewport is set to
## update, so while Nightfall isn't shown the layers' viewports are held at
## "don't update" in the renderer itself, each frame just before it draws.
## The viewport nodes keep the update modes the rest of the app gave them
## (many are set again every frame), and those are handed back to the renderer
## when Nightfall is shown again.
##
## The log gets one line when it stops being shown and one when it is shown
## again, and the once-a-second readings are held back in between.
##
## A stretch shorter than ANNOUNCE_MSEC gets one short line instead of the
## pair. The first day's logs had such blips, VISIBLE to SYNCHRONIZED and
## back inside a second, five in ten minutes; the displays were seen to go
## dark for an instant about as often, on SteamOS's desktop too, so they come
## from the headset and not from Nightfall. The line is kept because it is
## the only trace of them. The viewports are held from the first frame either
## way: the errors start at once.

## Lines the app writes every second whatever is happening.
const PERIODIC_TAGS: Array[String] = ["[FRAME-COST]", "[STATS]", "[DEPTH-PERF]", "[METEOR-DEPTH]", "[PERF]", "[GPU]"]
const RELIST_MSEC := 500
## Not shown for this long before the log says so.
const ANNOUNCE_MSEC := 1000

var main: Node
var shown := true
var held_back := 0
var _ever_shown := false
var _hidden_at := 0
var _hidden_clock := ""
var _announced := false
var _viewports: Array = []
var _listed_at := -RELIST_MSEC

func setup(owner: Node, xr_interface) -> void:
	main = owner
	if xr_interface == null:
		return
	for pair in [["session_synchronized", false], ["session_stopping", false],
			["session_visible", true], ["session_focussed", true]]:
		if xr_interface.has_signal(pair[0]):
			xr_interface.connect(pair[0], _set_shown.bind(pair[1]))
	RenderingServer.frame_pre_draw.connect(_before_draw)

## Whether a line of the app's log is held back just now.
func holds_back(line: String) -> bool:
	if shown or not _announced or not is_periodic(line):
		return false
	held_back += 1
	return true

static func is_periodic(line: String) -> bool:
	for tag in PERIODIC_TAGS:
		if line.begins_with(tag):
			return true
	return false

## "12 s", "3 min", "2 h 5 min".
static func duration_text(seconds: int) -> String:
	if seconds < 90:
		return "%d s" % seconds
	var minutes := int(round(seconds / 60.0))
	if minutes < 90:
		return "%d min" % minutes
	return "%d h %d min" % [floori(minutes / 60.0), minutes % 60]

func _set_shown(now_shown: bool) -> void:
	if now_shown == shown:
		_ever_shown = _ever_shown or now_shown
		return
	shown = now_shown
	if not shown:
		_hidden_at = Time.get_ticks_msec()
		_hidden_clock = Time.get_time_string_from_system()
		_announced = false
		held_back = 0
		_listed_at = -RELIST_MSEC
		return
	for viewport in _viewports:
		if is_instance_valid(viewport):
			RenderingServer.viewport_set_update_mode(viewport.get_viewport_rid(), viewport.render_target_update_mode)
	_viewports.clear()
	var lasted := Time.get_ticks_msec() - _hidden_at
	if _announced:
		main._log("[SESSION] %s Nightfall is being shown again after %s (%d once-a-second lines were held back)" % [
			Time.get_time_string_from_system(), duration_text(int(lasted / 1000.0)), held_back])
	elif _ever_shown:
		# Not at start-up, where the session passes through this state on its
		# way to being shown for the first time.
		main._log("[SESSION] %s Nightfall was not shown for a moment (%d ms)" % [_hidden_clock, lasted])
	_announced = false
	_ever_shown = true

## Says that Nightfall isn't being shown, once that has lasted ANNOUNCE_MSEC.
func _announce_if_lasting(now: int) -> void:
	if _announced or not _ever_shown or now - _hidden_at < ANNOUNCE_MSEC:
		return
	_announced = true
	main._log("[SESSION] %s Nightfall is not being shown (the headset is off, or something else is in front): its screens stop redrawing and the once-a-second readings stop until it is shown again" % _hidden_clock)

# Just before a frame is drawn, after everything else has had its say about
# the viewports for this frame.
func _before_draw() -> void:
	if shown or main == null or not is_instance_valid(main) or not main.is_inside_tree():
		return
	var now := Time.get_ticks_msec()
	_announce_if_lasting(now)
	if now - _listed_at >= RELIST_MSEC:
		_listed_at = now
		for layer in main.get_tree().root.find_children("*", "OpenXRCompositionLayer", true, false):
			var viewport = layer.layer_viewport
			if viewport != null and not _viewports.has(viewport):
				_viewports.append(viewport)
	for viewport in _viewports:
		if is_instance_valid(viewport):
			RenderingServer.viewport_set_update_mode(viewport.get_viewport_rid(), RenderingServer.VIEWPORT_UPDATE_DISABLED)

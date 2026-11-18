class_name VoiceMenu
extends RefCounted
## Voice commands made from the menu itself (Steam Frame voice typing).
##
## VoiceCommands holds the hand-written commands. This covers everything else
## in Nightfall's menu, so nobody has to guess which buttons have a command:
## say a button's name and what it should be.
##
##   "bezel off"            "cursor type pointer"      "fps 90"
##   "primary hand left"    "background black"         "next codec"
##   "reconnect stream"     (a button with no value: its name alone)
##
## The commands are read off the menu's own option buttons each time, so a
## new menu item gets its command without anything being added here. Only
## how people say a name needs help now and then (ALIASES).
##
## Left out on purpose (SKIP): buttons that undo or erase something, buttons
## that only open a page, and sliders (those have hand-written commands that
## take the slider's own units).

## Menu labels that get no command.
const SKIP := [
	"Language", "Licences", "Voice Commands",             # open a page
	"Forget Meteor Keys", "Original Default", "Save As Default", "Reset Settings", # undo or overwrite something
	"Type", "GPU Priority",                                # on-headset depth only
]

## Rows for the Voice Commands list.
const HELP := [
	["bezel off", "Say a button's name and what it should be: every button in the menu works this way"],
	["enable bezel / disable bezel", "The same as on and off"],
	["turn bezel off / switch bezel on", "Everyday wording works too"],
	["cursor type pointer", "...or one of its values"],
	["stream link wi-fi only", "New buttons get their command by themselves"],
	["fps 90", "...or a number it offers"],
	["next codec", "The button's next value"],
	["reconnect stream", "A button with nothing to choose: just its name"],
	["depth model meteor", "Where AI 3D's depth comes from (also \"model ...\")"],
	["profile <its name>", "Load one of your saved button profiles"],
	["off bezel", "Either order works, here and above"],
]

## Ways to ask for a saved button profile by name: "<these> <name>", or
## "<name> profile".
const PROFILE_WORDS := ["load profile", "use profile", "button profile", "buttons profile",
	"controller profile", "control profile", "game profile", "profile"]

## Other ways to say a button's name. Key: the label in lower case.
# Buttons that can show "Off" but have more than On and Off to choose from
# (Cursor Follow: Off, Standard, Capacitive Touch): stepped like the others.
const OFF_AND_MORE := ["Cursor Follow", "Foveation"]

const ALIASES := {
	"fps": ["frame rate", "framerate", "frames per second", "refresh rate"],
	"bitrate": ["bit rate"],
	"hz cap": ["hertz cap", "depth rate"],
	"3d mode": ["3 d mode"],
	"color": ["colour", "glow color", "glow colour", "ambient color", "ambient colour"],
	"icon backdrop": ["icons backdrop", "backdrop"],
	"primary hand": ["main hand", "pointing hand"],
	"controller models": ["controllers", "controller model"],
	"quality": ["depth model", "ai model", "3d model", "ai 3d model", "model", "depth quality"],
	"cursor type": ["cursor"],
	"cursor steady": ["steady", "cursor smoothing", "cursor stabilization"],
	"cursor follow": ["follow cursor", "mouse follow"],
	"cursor off screen": ["hide cursor", "park cursor", "cursor away"],
	"emulate": ["emulation", "controller mode"],
	"gamepad layout": ["button layout"],
	"flat screen": ["screen mode"],
	# "Reconnect Audio" until 8c; its old name still works.
	"reconnect stream": ["reconnect audio", "restart stream", "restart the stream", "fix audio", "restart audio", "reconnect sound", "fix sound"],
	"extended resolution": ["extended res"],
	"high refresh rates": ["high refresh", "high refresh rate"],
	"stats": ["statistics", "stats overlay"],
	"menu & keyboard follow": ["menu and keyboard follow", "menu follow", "keyboard follow"],
	"require 'nightfall'": ["require nightfall", "wake word"],
	"sharpen": ["sharpening", "sharpness"],
	"auto-reconnect": ["auto reconnect", "automatic reconnect"],
}

## Words for "the next value".
const NEXT_WORDS := ["next", "cycle", "change", "switch", "toggle"]

const MAX_PRESSES := 40

var main: Node
func _init(main_node: Node) -> void:
	main = main_node

# --- The menu's buttons ------------------------------------------------------

## Every option button a command may press: [{button, label, names}].
func entries() -> Array:
	var out := []
	var ui = main.ui_controller
	if ui == null:
		return out
	var seen := {}
	for root in ui.voice_menu_roots():
		_collect(root, out, seen)
	return out

func _collect(node: Node, out: Array, seen: Dictionary) -> void:
	if node is Button and node.has_meta(&"nightfall_option_label"):
		var label := String(node.get_meta(&"nightfall_option_label", ""))
		# `visible` is the button's own switch: off for buttons this device
		# doesn't have. (Its tab being closed doesn't count.)
		if label != "" and node.visible and not node.has_meta("slider") \
				and label not in SKIP and not seen.has(label):
			seen[label] = true
			out.append({"button": node, "label": label, "names": names_for(label)})
	for child in node.get_children():
		_collect(child, out, seen)

## The ways to say a label, longest first, as VoiceCommands.normalize() gives them.
static func names_for(label: String) -> Array:
	var names := [VoiceCommands.normalize(label.replace("&", " and "))]
	for alias in ALIASES.get(label.to_lower(), []):
		var a := VoiceCommands.normalize(alias)
		if a not in names:
			names.append(a)
	# And by the name the menu shows in its own language (VoicePacks), also
	# run together, as languages written without spaces are cut up.
	var shown := VoiceCommands.normalize(VoicePacks.tidy(Localization.t(label).replace("&", " ")))
	for local in [shown, shown.replace(" ", "")]:
		if local != "" and local not in names:
			names.append(local)
	names.sort_custom(func(a, b): return a.length() > b.length())
	return names

static func value_of(button: Button) -> String:
	return String(button.get_meta(&"nightfall_option_value", ""))

## The menu's names and values as it shows them now, for cutting up a clip
## in a language written without spaces (VoicePacks.segment()).
func vocabulary() -> Array:
	var words: Array = []
	for entry in entries():
		words.append_array(entry["names"])
		var value := VoicePacks.tidy(Localization.t(value_of(entry["button"])))
		if value != "":
			words.append(value)
	return words

## says(), for a value as the menu shows it in English or in its own language.
static func says_shown(value: String, said: String) -> bool:
	if says(value, said):
		return true
	var shown := Localization.t(value)
	return shown != value and says(VoicePacks.tidy(shown), said)

# A label or value as the menu shows it, for the popup after a command.
static func _shown(text: String) -> String:
	return Localization.t(text)

# --- Understanding a clip ----------------------------------------------------

## Splits a simplified command key into a menu button and what was said about
## it. {} when the clip doesn't name a button. `rest` is "" for the name alone.
static func parse(key: String, menu: Array) -> Dictionary:
	key = key.strip_edges()
	for next_word in NEXT_WORDS:
		if key.begins_with(next_word + " "):
			var named := _named(key.substr(next_word.length() + 1), menu)
			if not named.is_empty() and named["rest"] == "":
				return {"entry": named["entry"], "rest": "next", "name_first": true}
	var hit := _named(key, menu)
	if not hit.is_empty():
		hit["name_first"] = true
		return hit
	# "black background", "off bezel": the value first.
	for entry in menu:
		for name in entry["names"]:
			if key.ends_with(" " + name):
				return {"entry": entry, "rest": key.substr(0, key.length() - name.length()).strip_edges(), "name_first": false}
	return {}

static func _named(key: String, menu: Array) -> Dictionary:
	var best := {}
	var best_len := 0
	for entry in menu:
		for name in entry["names"]:
			if name.length() > best_len and (key == name or key.begins_with(name + " ")):
				var rest := key.substr(name.length()).strip_edges()
				if rest.begins_with("to "):
					rest = rest.substr(3).strip_edges() # "background to black"
				best = {"entry": entry, "rest": rest}
				best_len = name.length()
	return best

## Does a button value answer to what was said? "90" matches "90", "90 fps";
## "10" matches "+10%"; "pc cursor" matches "PC Cursor"; "3d scene", "3D Scene".
static func says(value: String, said: String) -> bool:
	var v := VoiceCommands.normalize(value.replace("+", " plus ").replace("&", " and ")).replace("  ", " ")
	if v.begins_with("plus ") and not v.substr(5, 1).is_valid_int():
		v = v.substr(5)
	if v == said or v.replace(" ", "") == said.replace(" ", "") or v.replace(" plus ", " and ") == said \
			or v.replace(" plus ", " ") == said:
		return true
	var number := RegEx.new()
	number.compile("^(minus |negative |plus )?(\\d+)( .*)?$")
	var s := number.search(said)
	if s == null:
		return false
	var said_n := int(s.get_string(2)) * (-1 if s.get_string(1).begins_with("m") or s.get_string(1).begins_with("n") else 1)
	number.compile("(minus |negative |plus )?(\\d+)")
	var all := number.search_all(v)
	if all.size() != 1:
		return false # "3d scene" and the like aren't numbers
	var m: RegExMatch = all[0]
	var value_n := int(m.get_string(2)) * (-1 if m.get_string(1).begins_with("m") or m.get_string(1).begins_with("n") else 1)
	# The number must be the value's main part: "20hz", "+10%", "50 mbps".
	return said_n == value_n and v.replace(m.get_string(0), "").strip_edges().length() <= 5

# --- Running a clip ----------------------------------------------------------

## Tries a spoken clip as a menu command. Returns "" when it isn't one (type
## it instead), otherwise the short message to show.
func run(text: String, require_prefix: bool) -> String:
	var k := VoiceCommands.command_key(text, require_prefix)
	if k.is_empty():
		return ""
	var profile := _profile(k["key"], k["prefixed"])
	if profile != "":
		return profile
	var hit := parse(k["key"], entries())
	if hit.is_empty():
		return ""
	var entry: Dictionary = hit["entry"]
	var button: Button = entry["button"]
	var label: String = entry["label"]
	var rest: String = hit["rest"]
	var current := value_of(button)
	# Certain it is a command: it started with a button's name (not just
	# ended with one), or "Nightfall" came first.
	var sure: bool = hit["name_first"] or k["prefixed"]

	if rest == "":
		# The name alone presses a button that has no value ("reconnect
		# audio"). For the others say what it should be, or "next".
		if current != "" or not hit["name_first"]:
			return ""
		return _press_action(button, label)
	if rest == "next":
		if current == "":
			return _press_action(button, label)
		if button.disabled:
			return "%s isn't available right now." % label
		main.ui_controller.press_option(button)
		return "%s: %s." % [_shown(label), _shown(value_of(button))]
	if current == "":
		return "" # an action button takes no value

	if current in ["On", "Off"] and label not in OFF_AND_MORE:
		if rest not in ["on", "off"]:
			return ""
		if button.disabled:
			return "%s isn't available right now." % label
		if current.to_lower() != rest:
			main.ui_controller.press_option(button)
		return "%s: %s." % [_shown(label), _shown(value_of(button))]

	# A button with several values.
	if says_shown(current, rest):
		return "%s: %s." % [_shown(label), _shown(current)]
	if not sure or (rest.split(" ", false).size() > 3 and not k["prefixed"]):
		# Don't step a button all the way round just to see whether this was
		# a command: a sentence that happens to start with "background ...".
		return ""
	if button.disabled:
		return "%s isn't available right now." % label
	return _step_to(button, label, rest, k["prefixed"])

func _press_action(button: Button, label: String) -> String:
	if button.disabled:
		return "%s isn't available right now." % label
	main.ui_controller.press_option(button)
	return "%s." % _shown(label)

## Presses the button until it shows what was asked for. If it comes back
## round to where it began, nothing has changed and the clip was not a
## command after all (unless "Nightfall" was said: then say what it can be).
func _step_to(button: Button, label: String, rest: String, prefixed: bool) -> String:
	var sc = main.settings_controller
	var restart_before: int = sc.get("_restart_seq") if sc else 0
	var start := value_of(button)
	var seen := [start]
	var unchanged := 0
	for i in MAX_PRESSES:
		main.ui_controller.press_option(button)
		var now := value_of(button)
		if says_shown(now, rest):
			return "%s: %s." % [_shown(label), _shown(now)]
		if now == start:
			# Back at the start: all the way round, if anything else came by.
			# (Some buttons show the same text for two settings in a row,
			# so one press that changes nothing isn't the end yet.)
			unchanged += 1
			if seen.size() > 1 or unchanged >= 3:
				break
		elif now not in seen:
			seen.append(now)
	# Where it started: a stream restart queued by stepping through
	# (Resolution, FPS, Codec...) has nothing to apply.
	if sc and value_of(button) == start and int(sc.get("_restart_seq")) != restart_before:
		sc.cancel_stream_restart()
	return "%s can be: %s." % [label, ", ".join(PackedStringArray(seen))] if prefixed else ""

# --- Button profiles ---------------------------------------------------------

## "profile racing", "load profile racing", "racing profile": loads the saved
## button profile of that name. "" when the clip isn't that.
func _profile(key: String, prefixed: bool) -> String:
	var bb = main.get("button_bindings")
	if bb == null:
		return ""
	var wanted := ""
	for words in PROFILE_WORDS:
		if key.begins_with(words + " "):
			wanted = key.substr(words.length() + 1).strip_edges()
			break
	if wanted == "" and key.ends_with(" profile"):
		wanted = key.substr(0, key.length() - 8).strip_edges()
	if wanted == "":
		return ""
	var names: Array = bb.profile_names()
	if wanted == "default" and "Default" not in names and "default" not in names:
		bb.load_default_profile()
		if main.ui_controller:
			main.ui_controller.refresh_buttons_tab()
		return "Button profile: Default."
	for name in names:
		var n := VoiceCommands.normalize(String(name))
		if n == wanted or n.replace(" ", "") == wanted.replace(" ", "") or n == key: # "Profile 1" is itself a name
			bb.load_profile(String(name))
			if main.ui_controller:
				main.ui_controller.refresh_buttons_tab()
			return "Button profile: %s." % name
	if not prefixed:
		return "" # no such profile: it was just a sentence
	if names.is_empty():
		return "No button profiles saved yet."
	return "Button profiles: %s." % ", ".join(PackedStringArray(names))

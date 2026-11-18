class_name VoiceCommands
extends RefCounted

# Voice commands for Nightfall's voice typing. A command only runs when it is
# the whole clip (said on its own), so the same words inside a sentence are
# typed as normal. With "Require 'Nightfall'" on, every command must start
# with "Nightfall" ("Nightfall select all").
#
# Each entry: id, the phrases that trigger it (# = a whole number; words may
# follow it, as in "volume minus # db"), and the text shown in the Voice
# Commands list.

const GROUPS := [
	["View", [
		["recenter", ["recenter", "recenter screen", "recenter view", "center screen"], "recenter", "Bring the screen in front of you"],
		["headlock_on", ["head lock on", "head lock", "lock screen to head"], "head lock on", "Screen follows your view"],
		["headlock_off", ["head lock off", "unlock head", "head unlock"], "head lock off", "Screen stays put"],
		["headlock_tilt", ["head lock tilt"], "head lock tilt", "Head Lock that tilts with your head"],
		["headlock_level", ["head lock level"], "head lock level", "Head Lock that stays upright"],
		["menu_show", ["show menu", "open menu", "menu", "menu on"], "show menu", "Menu in front of you"],
		["menu_hide", ["hide menu", "close menu", "menu off"], "hide menu", "Hide the menu"],
		["keyboard_show", ["show keyboard", "open keyboard", "keyboard", "keyboard on"], "show keyboard", "Show the keyboard"],
		["keyboard_hide", ["hide keyboard", "close keyboard", "keyboard off"], "hide keyboard", "Hide the keyboard"],
	]],
	["Picture", [
		["curve_n", ["curve #", "curve to #", "set curve #"], "curve 50", "Curve 0-100%"],
		["curve_flat", ["flat screen", "curve off", "no curve", "flat"], "flat screen", "No curve"],
		["passthrough_on", ["passthrough on", "show room", "show my room"], "passthrough on", "See your room"],
		["passthrough_off", ["passthrough off", "hide room"], "passthrough off", "Background instead of your room"],
		["pt_fade_n", ["passthrough fade #", "pt fade #", "ptfade #", "p t fade #", "fade #", "room fade #", "dim room #"], "passthrough fade 50", "Darken your room 0-100% (passthrough)"],
		["ambient_off", ["ambient off", "glow off"], "ambient off", "No glow around the screen"],
		["ambient_static", ["ambient static", "glow static"], "ambient static", "Glow: Static"],
		["ambient_slow", ["ambient slow", "glow slow", "glow on", "ambient on"], "ambient slow", "Glow: Slow"],
		["ambient_live", ["ambient live", "glow live"], "ambient live", "Glow: Live"],
		["glow_strength_n", ["glow strength #", "glow #", "glow brightness #"], "glow strength 70", "Glow strength 0-100%"],
		["glow_size_n", ["glow size #"], "glow size 40", "Glow size 0-100%"],
		["sbs_on", ["side by side on", "sbs on", "side by side"], "side by side on", "Show SBS 3D video as 3D"],
		["sbs_off", ["side by side off", "sbs off"], "side by side off", "Back to normal"],
		["ai3d_on", ["3d on", "ai 3d on", "turn on 3d", "three d on", "ready on", "reedy on", "readie on", "really on"], "3D on", "AI 3D on"],
		["ai3d_off", ["3d off", "ai 3d off", "turn off 3d", "three d off", "ready off", "reedy off", "readie off", "really off"], "3D off", "AI 3D off"],
		["depth_on", ["depth view on", "show depth", "depth view", "depth of view on"], "depth view on", "Show the depth map"],
		["depth_off", ["depth view off", "hide depth", "depth of view off"], "depth view off", "Hide the depth map"],
		["separation_n", ["separation #", "3d separation #", "3d strength #", "depth strength #"], "separation 150", "AI 3D strength, 25-400%"],
		["convergence_n", ["convergence #", "3d convergence #", "pop out #"], "convergence 30", "What sits on the screen's surface, 0-100% (lower pops out more)"],
	]],
	["Controls & sound", [
		["gamepad_on", ["gamepad mode on", "gamepad on", "game controller on", "gamepad mode"], "gamepad mode on", "Controllers act as a gamepad"],
		["gamepad_off", ["gamepad mode off", "gamepad off", "game controller off"], "gamepad mode off", "Controllers back to pointing"],
		["primary_right", ["primary hand right", "right hand primary", "main hand right", "point with right hand", "right handed"], "primary hand right", "Point and click with the right controller"],
		["primary_left", ["primary hand left", "left hand primary", "main hand left", "point with left hand", "left handed"], "primary hand left", "Point and click with the left controller"],
		["primary_auto", ["primary hand auto", "primary hand automatic", "main hand auto"], "primary hand auto", "Whichever controller pulled its trigger last"],
		["ray_on", ["pointer ray on", "show ray", "ray on"], "pointer ray on", "Show the pointer beam"],
		["ray_off", ["pointer ray off", "hide ray", "ray off"], "pointer ray off", "Hide the pointer beam"],
		["mic_on", ["microphone on", "mic on"], "microphone on", "Headset mic to your PC (voice chat)"],
		["mic_off", ["microphone off", "mic off"], "microphone off", "Stop sending the mic"],
		["buttons_on", ["custom buttons on", "buttons on", "my buttons on"], "custom buttons on", "Your own button assignments on"],
		["buttons_off", ["custom buttons off", "buttons off", "my buttons off"], "custom buttons off", "Buttons back to Nightfall's own"],
		["vibration_on", ["vibration on", "haptics on"], "vibration on", "Controller ticks on clicks"],
		["vibration_off", ["vibration off", "haptics off"], "vibration off", "No controller ticks"],
		["vol_up", ["volume up", "louder", "increase volume", "raise volume", "volume higher", "turn up volume", "turn it up"], "volume up", "Stream volume up one step"],
		["vol_down", ["volume down", "quieter", "decrease volume", "lower volume", "reduce volume", "volume lower", "turn down volume", "turn it down"], "volume down", "Stream volume down one step"],
		["volume_n", ["volume #"], "volume 80", "Stream volume 0-100% (80 is Normal)"],
		["volume_db_minus", ["volume minus # db", "volume negative # db"], "volume minus 12 decibels", "Stream volume below Normal, as the slider shows it"],
		["volume_db_plus", ["volume plus # db", "volume # db"], "volume plus 6 decibels", "Stream volume above Normal (up to +12)"],
		["volume_normal", ["volume normal", "normal volume", "volume default", "default volume", "reset volume", "volume reset"], "volume normal", "Stream volume back to Normal"],
		["mute_on", ["mute", "on mute", "volume mute", "mute volume", "mute sound", "mute audio", "volume off", "sound off"], "mute", "Mute the stream"],
		["mute_off", ["unmute", "un mute", "volume unmute", "unmute volume", "unmute sound", "unmute audio", "volume on", "sound on"], "unmute", "Sound back on"],
	]],
	["PC keys", [
		["k_select_all", ["select all"], "select all", "Ctrl+A"],
		["k_copy", ["copy", "copy that"], "copy", "Ctrl+C"],
		["k_paste", ["paste", "paste that"], "paste", "Ctrl+V"],
		["k_cut", ["cut", "cut that"], "cut", "Ctrl+X"],
		["k_undo", ["undo", "undo that"], "undo", "Ctrl+Z"],
		["k_redo", ["redo", "redo that"], "redo", "Ctrl+Y"],
		["k_save", ["save", "save file"], "save", "Ctrl+S"],
		["k_find", ["find", "search page"], "find", "Ctrl+F"],
		["k_new_tab", ["new tab"], "new tab", "Ctrl+T"],
		["k_close_tab", ["close tab"], "close tab", "Ctrl+W"],
		["k_close_window", ["close window"], "close window", "Alt+F4"],
		["k_switch", ["switch window", "alt tab"], "switch window", "Alt+Tab"],
		["k_desktop", ["show desktop"], "show desktop", "Win+D"],
		["k_task_manager", ["task manager"], "task manager", "Ctrl+Shift+Esc"],
		["k_start", ["start menu", "windows key"], "start menu", "Windows key"],
		["k_screenshot", ["screenshot", "snip"], "screenshot", "Win+Shift+S"],
		["k_dictation", ["windows dictation", "dictation"], "windows dictation", "Win+H"],
		["k_escape", ["escape", "press escape"], "escape", "Esc"],
		["k_enter", ["enter", "press enter"], "enter", "Enter"],
		["k_tab", ["tab key", "press tab"], "tab key", "Tab"],
		["k_backspace", ["backspace", "back space"], "backspace", "Backspace"],
		["k_delete", ["delete", "press delete"], "delete", "Delete"],
		["k_page_up", ["page up"], "page up", "Page Up"],
		["k_page_down", ["page down"], "page down", "Page Down"],
		["k_f", ["f#", "press f#"], "F1 ... F12", "Function keys (say \"F5\")"],
	]],
]

# Shown in the list but handled while typing (they work inside sentences).
const TYPING_HELP := [
	["clear ...", "First word: erase the last thing typed, then type the rest"],
	["... submit", "Last word: press Enter after typing"],
	["new line / new paragraph", "Line break (Shift+Enter)"],
	["open / close parenthesis", "( and )"],
]

const KEYS := {
	"k_select_all": [KEY_CTRL, KEY_A], "k_copy": [KEY_CTRL, KEY_C], "k_paste": [KEY_CTRL, KEY_V],
	"k_cut": [KEY_CTRL, KEY_X], "k_undo": [KEY_CTRL, KEY_Z], "k_redo": [KEY_CTRL, KEY_Y],
	"k_save": [KEY_CTRL, KEY_S], "k_find": [KEY_CTRL, KEY_F], "k_new_tab": [KEY_CTRL, KEY_T],
	"k_close_tab": [KEY_CTRL, KEY_W], "k_close_window": [KEY_ALT, KEY_F4], "k_switch": [KEY_ALT, KEY_TAB],
	"k_desktop": [KEY_META, KEY_D], "k_task_manager": [KEY_CTRL, KEY_SHIFT, KEY_ESCAPE],
	"k_start": [KEY_META], "k_screenshot": [KEY_META, KEY_SHIFT, KEY_S], "k_dictation": [KEY_META, KEY_H],
	"k_escape": [KEY_ESCAPE], "k_enter": [KEY_ENTER], "k_tab": [KEY_TAB], "k_backspace": [KEY_BACKSPACE],
	"k_delete": [KEY_DELETE], "k_page_up": [KEY_PAGEUP], "k_page_down": [KEY_PAGEDOWN],
}

const NUMBER_WORDS := {
	"zero": 0, "oh": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7,
	"eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14,
	"fifteen": 15, "sixteen": 16, "seventeen": 17, "eighteen": 18, "nineteen": 19, "twenty": 20,
	"thirty": 30, "forty": 40, "fifty": 50, "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90,
	"hundred": 100,
}

# Whisper's spellings of short commands, fixed up front.
const FIXES := [
	["headlock", "head lock"], ["head locked", "head lock"], ["re center", "recenter"],
	# "Head lock" as the speech model has kept hearing it from one user
	# (2026-11-16: typed into messages as "Edlock.", "Ad lock.", "headset lock").
	["edlock", "head lock"], ["ed lock", "head lock"], ["ad lock", "head lock"], ["headset lock", "head lock"],
	# And later the same day: "A Dlock.", "At lock."
	["a dlock", "head lock"], ["dlock", "head lock"], ["a d lock", "head lock"], ["at lock", "head lock"],
	["recentre", "recenter"], ["re centre", "recenter"], ["night fall", "nightfall"],
	["knightfall", "nightfall"], ["knight fall", "nightfall"], ["3 d", "3d"], ["a i", "ai"],
	["side-by-side", "side by side"], ["s b s", "sbs"], ["pass through", "passthrough"],
	["game pad", "gamepad"], ["glowed", "glow"], ["glo", "glow"], ["curb", "curve"], ["micro phone", "microphone"], ["back space", "backspace"],
]

static var _phrases := {}  # phrase -> id, built on first use
static var _numbered := []  # [words before the number, id, words after it]

# "Head-lock on." / "Nightfall, curve fifty percent!" -> "head lock on" / "nightfall curve 50"
static func normalize(s: String) -> String:
	var t := s.to_lower()
	# Signs, before the punctuation goes: "-20 dB" -> "minus 20 db".
	var sign := RegEx.new()
	sign.compile("(^|\\s)[-\u2212\u2013]\\s?(\\d)")
	t = sign.sub(t, "$1minus $2", true)
	sign.compile("(^|\\s)\\+\\s?(\\d)")
	t = sign.sub(t, "$1plus $2", true)
	for ch in [".", ",", "!", "?", ";", ":", "-", "\"", "'", "%"]:
		t = t.replace(ch, " ")
	t = " " + t.replace("percent", " ") + " "
	while t.contains("  "):
		t = t.replace("  ", " ")
	for f in FIXES:
		t = t.replace(" " + f[0] + " ", " " + f[1] + " ")
	t = t.replace(" the ", " ").replace(" please ", " ")
	while t.contains("  "):
		t = t.replace("  ", " ")
	t = _numbers(t.strip_edges())
	# Units: "20 decibels" / "20db" / "20 d b" -> "20 db"
	var unit := RegEx.new()
	unit.compile("(\\d) ?(decibels|decibel|d ?b)\\b")
	t = unit.sub(t, "$1 db", true)
	# Function keys: "F5" / "f 5" / "eff five" -> "f 5"
	t = (" " + t + " ").replace(" eff ", " f ").replace(" 3 d ", " 3d ").strip_edges()
	var re := RegEx.new()
	re.compile("\\bf(\\d{1,2})\\b")
	return re.sub(t, "f $1", true)

# Turns number words into digits ("seventy five" -> "75").
static func _numbers(t: String) -> String:
	var words := t.split(" ", false)
	var out: Array[String] = []
	var i := 0
	while i < words.size():
		var w: String = words[i]
		if NUMBER_WORDS.has(w):
			var n: int = NUMBER_WORDS[w]
			if n == 100 or (w == "one" and i + 1 < words.size() and words[i + 1] == "hundred"):
				n = 100
				if w == "one":
					i += 1
			elif n >= 20 and i + 1 < words.size() and NUMBER_WORDS.has(words[i + 1]) and NUMBER_WORDS[words[i + 1]] < 10:
				n += NUMBER_WORDS[words[i + 1]]
				i += 1
			out.append(str(n))
		else:
			out.append(w)
		i += 1
	return " ".join(out)

## Said on its own, the name of something that is either on or off flips it:
## "depth view" shows the depth map, "depth view" again hides it. phrase ->
## id; VoiceTyping turns the id into the matching "..._on" / "..._off" (or
## show / hide) command by looking at how things stand. These take the place
## of the bare names that used to mean "on" ("depth view", "head lock",
## "menu", "keyboard", "side by side", "gamepad mode").
const TOGGLE_PHRASES := {
	"head lock": "headlock_toggle", "menu": "menu_toggle", "keyboard": "keyboard_toggle",
	"passthrough": "passthrough_toggle", "side by side": "sbs_toggle", "sbs": "sbs_toggle",
	"ai 3d": "ai3d_toggle",
	"depth view": "depth_toggle", "depth of view": "depth_toggle", "depth map": "depth_toggle",
	"gamepad mode": "gamepad_toggle", "gamepad": "gamepad_toggle", "game controller": "gamepad_toggle",
	"pointer ray": "ray_toggle", "microphone": "mic_toggle", "mic": "mic_toggle",
	"custom buttons": "buttons_toggle", "vibration": "vibration_toggle", "haptics": "vibration_toggle",
}
## toggle id -> [command when it is off now, command when it is on now]
const TOGGLES := {
	"headlock_toggle": ["headlock_on", "headlock_off"], "menu_toggle": ["menu_show", "menu_hide"],
	"keyboard_toggle": ["keyboard_show", "keyboard_hide"], "passthrough_toggle": ["passthrough_on", "passthrough_off"],
	"sbs_toggle": ["sbs_on", "sbs_off"], "ai3d_toggle": ["ai3d_on", "ai3d_off"], "depth_toggle": ["depth_on", "depth_off"],
	"gamepad_toggle": ["gamepad_on", "gamepad_off"], "ray_toggle": ["ray_on", "ray_off"], "mic_toggle": ["mic_on", "mic_off"],
	"buttons_toggle": ["buttons_on", "buttons_off"], "vibration_toggle": ["vibration_on", "vibration_off"],
}

static func _build() -> void:
	if not _phrases.is_empty():
		return
	for g in GROUPS:
		for e in g[1]:
			for p in e[1]:
				if p.contains("#"):
					var parts: PackedStringArray = p.split("#")
					_numbered.append([parts[0].strip_edges(), e[0], parts[1].strip_edges()])
				else:
					_phrases[p] = e[0]
	for p in TOGGLE_PHRASES:
		_phrases[p] = TOGGLE_PHRASES[p]

## The clip as a command would be looked up: lower case, no punctuation,
## "Nightfall" taken off the front, everyday wording simplified. {} when
## "Nightfall" is required and wasn't said. {key, prefixed}
static func command_key(text: String, require_prefix: bool) -> Dictionary:
	_build()
	var key := normalize(text)
	var prefixed := false
	for pre in ["hey nightfall ", "ok nightfall ", "okay nightfall ", "nightfall "]:
		if key.begins_with(pre):
			key = key.substr(pre.length()).strip_edges()
			prefixed = true
			break
	if require_prefix and not prefixed:
		return {}
	return {"key": _simplify(key), "prefixed": prefixed}

# Returns {"id": String, "arg": int} for a command, or {} when the clip isn't one.
static func match_command(text: String, require_prefix: bool) -> Dictionary:
	var looked_up := command_key(text, require_prefix)
	if looked_up.is_empty():
		return {}
	var key: String = looked_up["key"]
	var prefixed: bool = looked_up["prefixed"]
	var exact := _lookup(key)
	if not exact.is_empty():
		return exact
	# The other way round: "normal volume", "50 curve", "on head lock".
	var words := key.split(" ", false)
	if words.size() >= 2:
		var n := words.size()
		for turned in [" ".join(words.slice(1)) + " " + words[0], words[n - 1] + " " + " ".join(words.slice(0, n - 1))]:
			exact = _lookup(turned)
			if not exact.is_empty():
				return exact
	var fuzzy := _fuzzy_head_lock(key)
	if fuzzy != "":
		return {"id": fuzzy, "arg": -1}
	# Near misses on short clips ("select awl", "show key board"). Checking
	# a few dozen phrases takes well under a millisecond. Said after
	# "Nightfall", a looser match is allowed, since you clearly meant a command.
	if key.split(" ", false).size() <= 4:
		var squeezed := key.replace(" ", "")
		var best_id := ""
		var best_d := 99
		for p in _phrases:
			var target: String = p.replace(" ", "")
			if not prefixed and target.length() < 5:
				continue # short words must match exactly unless "Nightfall" came first
			var allowed := int(target.length() * (0.34 if prefixed else 0.2))
			if absi(target.length() - squeezed.length()) > allowed:
				continue
			var d := _edit_distance(squeezed, target)
			if d <= allowed and d < best_d:
				best_d = d
				best_id = _phrases[p]
		if best_id != "":
			return {"id": best_id, "arg": -1}
	return {}

# The popup text after a command runs ("Select all (Ctrl+A)").
static func confirm_text(id: String) -> String:
	for g in GROUPS:
		for e in g[1]:
			if e[0] == id:
				var shown: String = e[2]
				shown = shown.substr(0, 1).to_upper() + shown.substr(1)
				return "%s (%s)" % [shown, e[3]] if id.begins_with("k_") else shown
	return ""

# Everyday wording around a command: "turn 3D on", "turn on 3D",
# "set glow to 50", "switch passthrough off", "please recenter".
static func _simplify(key: String) -> String:
	if _phrases.has(key):
		return key
	var t := " " + key + " "
	for verb in ["turn ", "set ", "switch ", "make ", "change ", "put ", "go ", "can you ", "could you "]:
		if t.begins_with(" " + verb):
			t = " " + t.substr(verb.length() + 1)
	t = t.strip_edges()
	# "disable head lock" is "head lock off"; "enable passthrough", "passthrough on".
	# ("Disabled headlock." was typed out once, 2026-11-16: heard with a d.)
	for said in [["disable ", "off"], ["enable ", "on"], ["disabled ", "off"], ["enabled ", "on"]]:
		if t.begins_with(said[0]) and not _phrases.has(t):
			t = t.substr(said[0].length()).strip_edges() + " " + said[1]
	for w in ["on ", "off "]:
		if t.begins_with(w) and not _phrases.has(t):
			t = t.substr(w.length()) + " " + w.strip_edges() # "on 3d" -> "3d on"
	var re := RegEx.new()
	re.compile(" (to|at) ((minus |negative |plus )?\\d+( db)?)$")
	t = re.sub(t, " $2")
	return t.strip_edges()

# A phrase from the table, word for word (numbers filled in), or {}.
static func _lookup(key: String) -> Dictionary:
	if _phrases.has(key):
		return {"id": _phrases[key], "arg": -1}
	for nb in _numbered:
		var pre: String = nb[0] + " "
		if key.begins_with(pre):
			var rest := key.substr(pre.length()).strip_edges()
			if nb[2] != "":
				if not rest.ends_with(" " + nb[2]):
					continue
				rest = rest.substr(0, rest.length() - nb[2].length()).strip_edges()
			if rest.is_valid_int():
				return {"id": nb[1], "arg": clampi(int(rest), 0, 1000)} # each command clamps to its own range
	return {}

# Whisper often mishears "head lock" ("head to lock off", "head block off",
# "good luck off", "Edelach off"). A short clip ending in on / off / level /
# tilt matches when the words before it are close to "head lock".
static func _fuzzy_head_lock(key: String) -> String:
	var words := key.split(" ", false)
	if words.size() < 2 or words.size() > 5:
		return ""
	var last: String = words[words.size() - 1]
	if last not in ["on", "off", "level", "tilt"]:
		return ""
	words.remove_at(words.size() - 1)
	if words.size() > 1 and words[words.size() - 1] in ["a", "to", "and"]:
		words.remove_at(words.size() - 1)
	var name := "".join(words)
	var best := 99
	for n in ["headlock", "eadlock", "edelock"]:
		best = mini(best, _edit_distance(name, n))
	if best > 4 or best * 2 > name.length():
		return ""
	return "headlock_" + last

static func _edit_distance(a: String, b: String) -> int:
	var prev: Array[int] = []
	for j in b.length() + 1:
		prev.append(j)
	for i in a.length():
		var cur: Array[int] = [i + 1]
		for j in b.length():
			var cost := 0 if a[i] == b[j] else 1
			cur.append(mini(mini(cur[j] + 1, prev[j + 1] + 1), prev[j] + cost))
		prev = cur
	return prev[b.length()]

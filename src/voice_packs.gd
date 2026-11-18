class_name VoicePacks
extends RefCounted
## Voice commands in the menu's language (Steam Frame voice typing).
##
## steam-frame/i18n/VOICE.md has the whole design. In short: a "pack" per
## language (locale/voice/<code>.json) holds the words the menu itself does
## not: on and off, the fixed commands, the words used while typing. What
## was said is put into the English command vocabulary with to_english(),
## and VoiceCommands and VoiceMenu then run on that as they always have.
## English has no pack. What gets typed is never changed here.

const DIR := "res://locale/voice"

## The little words a pack translates, as the English engines know them.
const WORD_KINDS := ["on", "off", "next", "enable", "disable", "minus", "plus", "to"]

## Punctuation taken off before a clip is looked at, beyond what
## VoiceCommands.normalize() removes itself.
const PUNCTUATION := [".", ",", "!", "?", ";", ":", "\"", "'", "%",
	"。", "、", "，", "！", "？", "：", "；", "「", "」", "『", "』", "（", "）", "・",
	"«", "»", "„", "“", "”", "‘", "’", "¿", "¡", "…", "(", ")"]

## What the Voice Commands list says beside a command that takes a number.
const RANGES := {
	"volume #": "0-100 (80)", "curve #": "0-100%", "passthrough fade #": "0-100%",
	"glow strength #": "0-100%", "glow size #": "0-100%", "separation #": "25-400%",
	"convergence #": "0-100%",
}

static var _packs := {}  # code -> pack ({} for a language without one)

## The pack for a language code; {} when there is none (English, or a file
## that is missing or unreadable).
static func pack(code: String) -> Dictionary:
	if _packs.has(code):
		return _packs[code]
	var loaded := {}
	var path := "%s/%s.json" % [DIR, code]
	if code != "en" and FileAccess.file_exists(path):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary and problems(parsed).is_empty():
			loaded = _indexed(parsed)
	_packs[code] = loaded
	return loaded

## The pack for the menu's language.
static func current() -> Dictionary:
	return pack(Localization.current())

## The language to tell a multilingual speech model for a menu language.
static func whisper_language(code: String) -> String:
	var p := pack(code)
	return String(p.get("whisper", "en")) if not p.is_empty() else "en"

## What is wrong with a pack as read from its file; empty when it can be used.
static func problems(p: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	if not p.get("whisper", "") is String or String(p.get("whisper", "")).is_empty():
		out.append("no whisper language code")
	for kind in WORD_KINDS + ["drop"]:
		if not p.get(kind, null) is Array:
			out.append("'%s' is not a list" % kind)
	for part in ["commands", "typing", "list"]:
		if not p.get(part, null) is Dictionary:
			out.append("'%s' is missing" % part)
	if not p.get("help", null) is Array or (p.get("help", []) as Array).size() != 3:
		out.append("'help' needs three lines")
	return out

## Lower case, punctuation off, single spaces. A hyphen between letters is a
## space; one before a digit stays for VoiceCommands.normalize() ("-20").
static func tidy(text: String) -> String:
	# (Lower-casing a Turkish capital İ leaves a dot behind as its own sign.)
	var t := text.to_lower().replace("\u0307", "")
	for mark in PUNCTUATION:
		t = t.replace(mark, " ")
	var hyphen := RegEx.new()
	hyphen.compile("(\\p{L})[-‐‑](?=\\p{L})")
	t = hyphen.sub(t, "$1 ", true)
	while t.contains("  "):
		t = t.replace("  ", " ")
	return t.strip_edges()

## A clip in the pack's language, put into the words the English command
## engines know. `menu_words`: the menu's translated names and values, for
## cutting up a language written without spaces (VoiceMenu.vocabulary()).
static func to_english(text: String, p: Dictionary, menu_words: Array = []) -> String:
	if p.is_empty():
		return text
	var t := tidy(text)
	var prefix := ""
	for wake in ["hey nightfall ", "ok nightfall ", "okay nightfall ", "nightfall "]:
		if t.begins_with(wake):
			prefix = "nightfall "
			t = t.substr(wake.length()).strip_edges()
			break
	var spaceless: bool = p.get("spaceless", false)
	if spaceless:
		t = segment(t, p["_words"] + menu_words)
	t = _without(t, p["drop"])
	var whole := _whole_command(t, p, spaceless)
	if whole != "":
		return prefix + whole
	return prefix + _swapped(t, p)

## A language written without spaces, cut into the words that are known,
## longest first; what lies between known words stays together. Digits are
## always their own word ("音量80" -> "音量 80").
static func segment(text: String, known: Array) -> String:
	var words: Array = []
	for w in known:
		var squeezed := String(w).replace(" ", "")
		if squeezed.length() > 0 and squeezed not in words:
			words.append(squeezed)
	words.sort_custom(func(a, b): return a.length() > b.length())
	var out: Array[String] = []
	for chunk in text.split(" ", false):
		var run := ""
		var i := 0
		while i < chunk.length():
			var hit := ""
			for w in words:
				if chunk.substr(i, w.length()) == w:
					hit = w
					break
			var ch := chunk.substr(i, 1)
			if hit != "":
				if run != "":
					out.append(run)
					run = ""
				out.append(hit)
				i += hit.length()
			else:
				# A run changes between digits and anything else.
				if run != "" and ch.is_valid_int() != run.substr(run.length() - 1, 1).is_valid_int():
					out.append(run)
					run = ""
				run += ch
				i += 1
		if run != "":
			out.append(run)
	return " ".join(out)

## The first words of a clip, if they are one of `phrases`: what follows
## them, as it was said. {} when the clip starts some other way.
## ("clear": erase the last thing typed, then type the rest.)
static func after_leading(text: String, phrases: Array, spaceless: bool) -> Dictionary:
	var said := text.strip_edges()
	var lower := said.to_lower()
	for phrase in _longest_first(phrases):
		if not lower.begins_with(phrase):
			continue
		var next := lower.substr(phrase.length(), 1)
		if spaceless or next == "" or _is_break(next):
			return {"rest": _unpunctuated_start(said.substr(phrase.length()))}
	return {}

## The same for the last words of a clip ("submit": press Enter after it).
static func before_trailing(text: String, phrases: Array, spaceless: bool) -> Dictionary:
	var said := text.strip_edges()
	while said.length() > 0 and _is_break(said.substr(said.length() - 1, 1)):
		said = said.substr(0, said.length() - 1)
	var lower := said.to_lower()
	for phrase in _longest_first(phrases):
		if not lower.ends_with(phrase):
			continue
		var before := lower.substr(lower.length() - phrase.length() - 1, 1) if lower.length() > phrase.length() else ""
		if spaceless or before == "" or _is_break(before):
			var rest := said.substr(0, said.length() - phrase.length())
			while rest.length() > 0 and rest.substr(rest.length() - 1, 1) in [" ", ",", "、", "，"]:
				rest = rest.substr(0, rest.length() - 1)
			return {"rest": rest}
	return {}

## The pack's spoken symbols as search-and-replace rules for what is typed:
## [pattern, replacement], most specific first.
static func symbol_rules(p: Dictionary) -> Array:
	var rules: Array = []
	if p.is_empty():
		return rules
	var edge := "" if p.get("spaceless", false) else "\\b"
	var typing: Dictionary = p["typing"]
	for made in [["open parenthesis", " (", "\\s*"], ["close parenthesis", ")", ""], ["new paragraph", "\n\n", "\\s*"], ["new line", "\n", "\\s*"]]:
		for phrase in _longest_first(typing.get(made[0], [])):
			rules.append(["(?i)\\s*%s%s%s[.,!?。，、]?%s" % [edge, _escaped(phrase), edge, made[2]], made[1]])
	return rules

## What to show after a fixed command ran: the pack's own words for it, or
## "" when the pack has none for that command.
static func confirm_text(id: String, p: Dictionary) -> String:
	var phrase := String(p.get("_said", {}).get(id, ""))
	if phrase == "":
		return ""
	phrase = phrase.replace("#", "").strip_edges()
	var keys: Array = VoiceCommands.KEYS.get(id, [])
	return phrase.substr(0, 1).to_upper() + phrase.substr(1) + ("" if keys.is_empty() else " (%s)" % _english_note(id))

## The Voice Commands list in the pack's language: [[title, [[say, note]]]].
## `menu_rows`: examples of the menu rule, made by the caller from the menu's
## own translated names.
static func list_sections(p: Dictionary, menu_rows: Array) -> Array:
	var commands: Array = []
	for english in p["_order"]:
		var id := String(p["_ids"].get(english, ""))
		var note := String(RANGES.get(english, ""))
		if note == "" and VoiceCommands.KEYS.has(id):
			note = _english_note(id)
		commands.append([String(p["commands"][english][0]).replace("#", "50" if english != "separation #" else "150"), note])
	commands.append(["F5", "F1 ... F12"])
	var typing: Array = []
	var words: Dictionary = p["typing"]
	for row in [["clear", "%s ...", "Backspace"], ["submit", "... %s", "Enter"], ["new line", "%s", "Shift+Enter"], ["new paragraph", "%s", "Shift+Enter x2"],
			["open parenthesis", "%s", "("], ["close parenthesis", "%s", ")"]]:
		if not (words.get(row[0], []) as Array).is_empty():
			typing.append([row[1] % words[row[0]][0], row[2]])
	var titles: Dictionary = p["list"]
	return [[titles.get("commands", "Commands"), commands], [titles.get("menu", "Any menu button"), menu_rows], [titles.get("typing", "While typing"), typing]]

# --- Inside -------------------------------------------------------------------

## A pack as read from its file, with what the lookups need added: every
## phrase tidied, `_exact` (phrase -> English), `_numbered` ([before the
## number, after it, English]), `_words` (every word of the pack, for
## cutting up a spaceless language), `_ids` and `_said` (English phrase ->
## command id -> the pack's first phrase), `_order` (the file's own order).
static func _indexed(raw: Dictionary) -> Dictionary:
	var p := raw.duplicate(true)
	var spaceless: bool = p.get("spaceless", false)
	var exact := {}
	var numbered: Array = []
	var words: Array = []
	var order: Array = []
	for kind in WORD_KINDS + ["drop"]:
		var tidied: Array = []
		for w in p[kind]:
			tidied.append(tidy(String(w)))
		p[kind] = tidied
		words.append_array(tidied)
	for english in p["commands"]:
		order.append(english)
		var phrases: Array = []
		for phrase in p["commands"][english]:
			var said := tidy(String(phrase).replace("#", " # ")) if String(phrase).contains("#") else tidy(String(phrase))
			phrases.append(said.replace(" # ", " #").replace("# ", "#") if spaceless else said)
			# Looked up as the clip will be: without the words that are dropped.
			var key := _without(said, p["drop"])
			if spaceless:
				key = key.replace(" ", "")
			if key.contains("#"):
				var parts := key.split("#")
				numbered.append([parts[0].strip_edges(), parts[1].strip_edges(), english])
			else:
				exact[key] = english
			for w in said.split(" ", false):
				if w != "#":
					words.append(w)
		p["commands"][english] = phrases
	for kind in p["typing"]:
		var tidied: Array = []
		for phrase in p["typing"][kind]:
			tidied.append(tidy(String(phrase)))
		p["typing"][kind] = tidied
	# Which command each English phrase is, straight from VoiceCommands' own table.
	var ids := {}
	var said_for := {}
	for group in VoiceCommands.GROUPS:
		for entry in group[1]:
			for phrase in entry[1]:
				if p["commands"].has(phrase):
					ids[phrase] = entry[0]
					if not said_for.has(entry[0]):
						said_for[entry[0]] = p["commands"][phrase][0]
	for phrase in VoiceCommands.TOGGLE_PHRASES:
		if p["commands"].has(phrase):
			ids[phrase] = VoiceCommands.TOGGLE_PHRASES[phrase]
	p["_exact"] = exact
	p["_numbered"] = numbered
	p["_words"] = words
	p["_ids"] = ids
	p["_said"] = said_for
	p["_order"] = order
	return p

static func _whole_command(t: String, p: Dictionary, spaceless: bool) -> String:
	var key := t.replace(" ", "") if spaceless else t
	if p["_exact"].has(key):
		return p["_exact"][key]
	for entry in p["_numbered"]:
		var before: String = entry[0]
		var after: String = entry[1]
		if not key.begins_with(before) or not key.ends_with(after) or key.length() <= before.length() + after.length():
			continue
		var number := key.substr(before.length(), key.length() - before.length() - after.length()).strip_edges()
		# "lautstärke auf 80", "volume à 60": the word for "to" may come first.
		for w in p["to"]:
			if number.begins_with(w + " "):
				number = number.substr(w.length()).strip_edges()
		for kind in ["minus", "plus"]:
			for w in p[kind]:
				if number.begins_with(w + " ") or (spaceless and number.begins_with(w)):
					number = kind + " " + number.substr(w.length()).strip_edges()
		var digits := number.trim_prefix("minus ").trim_prefix("plus ")
		if digits.is_valid_int() and not digits.begins_with("-") and not digits.begins_with("+"):
			return String(entry[2]).replace("#", number)
	return ""

static func _swapped(t: String, p: Dictionary) -> String:
	var padded := " " + t + " "
	for kind in WORD_KINDS:
		for w in _longest_first(p[kind]):
			padded = padded.replace(" " + w + " ", " " + kind + " ")
	return padded.strip_edges()

static func _without(t: String, dropped: Array) -> String:
	var padded := " " + t + " "
	for w in _longest_first(dropped):
		while padded.contains(" " + w + " "):
			padded = padded.replace(" " + w + " ", " ")
	return padded.strip_edges()

static func _longest_first(phrases: Array) -> Array:
	var sorted := phrases.duplicate()
	sorted.sort_custom(func(a, b): return String(a).length() > String(b).length())
	return sorted

static func _is_break(ch: String) -> bool:
	return ch == " " or ch in PUNCTUATION

static func _unpunctuated_start(text: String) -> String:
	var t := text
	while t.length() > 0 and _is_break(t.substr(0, 1)):
		t = t.substr(1)
	return t

static func _escaped(phrase: String) -> String:
	var out := ""
	for i in phrase.length():
		var ch := phrase.substr(i, 1)
		out += ("\\" + ch) if ch in ["\\", ".", "+", "*", "?", "(", ")", "[", "]", "{", "}", "^", "$", "|"] else ch
	return out.replace(" ", "\\s+")

# The key combination VoiceCommands' own list shows for a PC key ("Ctrl+A").
static func _english_note(id: String) -> String:
	for group in VoiceCommands.GROUPS:
		for entry in group[1]:
			if entry[0] == id:
				return entry[3]
	return ""

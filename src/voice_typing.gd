class_name VoiceTyping
extends RefCounted
## Steam Frame voice typing: hold the Voice Typing button (Y by default),
## speak, let go. VoiceTyper (native, whisper.cpp) records into memory only,
## transcribes on the headset and throws the audio away; this sends the text
## into the PC stream as typed text (Moonlight's encrypted input channel).
##
## Privacy: nothing said is ever logged or saved - only lengths and timings.
##
## Ideas taken from whisper-frame (MIT, github.com/groffta/whisper-frame):
## the silence gate, the list of phrases Whisper invents on silence, and the
## "clear" / "submit" words.

const MODEL_DIR := "/.local/share/nightfall/whisper"
# Whisper models from whisper.cpp's model page, fetched by install.sh.
# Index = AppSettings.voice_model.
const MODEL_FILES := ["ggml-base.en.bin", "ggml-small.en.bin"]
const MODEL_LABELS := ["Base", "Small"]
# The same two sizes of the multilingual model, for a menu in another
# language (steam-frame/i18n/VOICE.md). The installer fetches either kind.
const MULTILINGUAL_FILES := ["ggml-base.bin", "ggml-small.bin"]
const MIN_SECONDS := 0.3
const SILENCE_RMS := 30.0

# Whisper's well-known inventions on a quiet clip.
const ALWAYS_DROP := ["", ".", "...", "thank you", "thanks for watching",
	"thanks for listening", "please subscribe", "subtitles by the amara.org community",
	"the end", "[silence]", "(silence)", "[music]", "(music)", "silence", "music",
	"[blank_audio]", "[inaudible]"]
# Real one-word answers are kept when the clip is loud enough.
const QUIET_DROP := ["you", "thank you", "thanks", "bye", "hmm", "uh", "um", "so", "okay", "ok"]

var main: Node3D
var typer: Object = null
var _press_ms := 0
var _open_usec := 0        # when the microphone was asked for
var _open_toggle := false  # that press was a tap (keyboard Mic key), not a hold
var _last_typed := 0
var _pending := false
var _menu: VoiceMenu = null
var _model_name := ""
var _recheck_model := false
var _stop_usec := 0        # when the clip was handed over to be worked out

func setup(p_main: Node3D) -> void:
	main = p_main
	if not main.device_is_steam_frame or not ClassDB.class_exists("VoiceTyper"):
		return
	var path := _model_in_use()
	if not FileAccess.file_exists(path):
		main._log("[VOICE] speech model not installed (%s)" % path)
		return
	typer = ClassDB.instantiate("VoiceTyper")
	typer.connect("model_loaded", _on_model_loaded)
	typer.connect("transcribed", _on_transcribed)
	typer.connect("recording_started", _on_recording_started)
	typer.call("load_model", path, 4)
	_model_name = path.get_file()
	_tell_language()
	main._log("[VOICE] loading speech model %s (language: %s)" % [_model_name, _language_told])

static func model_path(index: int = 0) -> String:
	return OS.get_environment("HOME") + MODEL_DIR + "/" + MODEL_FILES[clampi(index, 0, MODEL_FILES.size() - 1)]

static func multilingual_path(index: int = 0) -> String:
	return OS.get_environment("HOME") + MODEL_DIR + "/" + MULTILINGUAL_FILES[clampi(index, 0, MULTILINGUAL_FILES.size() - 1)]

## Whether a speech model of that size is installed, of either kind.
static func size_installed(index: int) -> bool:
	return FileAccess.file_exists(model_path(index)) or FileAccess.file_exists(multilingual_path(index))

## Which model file to load. `size`: Speech Model (0 Base, 1 Small).
## `english_menu`: the menu is in English. `exists`: says whether a file is
## there. A menu in English takes an English-only model when one is
## installed (they hear English best), any other language a multilingual
## one; the chosen size first, then the other size, then the other kind.
## {path, multilingual}; the chosen English file when nothing is installed.
static func model_choice(size: int, english_menu: bool, exists: Callable) -> Dictionary:
	size = clampi(size, 0, MODEL_FILES.size() - 1)
	var kinds := [false, true] if english_menu else [true, false]
	for multilingual in kinds:
		for index in [size, 1 - size]:
			var path := multilingual_path(index) if multilingual else model_path(index)
			if exists.call(path):
				return {"path": path, "multilingual": multilingual}
	return {"path": model_path(size), "multilingual": false}

static func is_multilingual(file_name: String) -> bool:
	return file_name in MULTILINGUAL_FILES

## The language a model is told to listen for: the menu's, when the model
## knows other languages; English otherwise.
static func language_for(file_name: String, menu_language: String) -> String:
	return VoicePacks.whisper_language(menu_language) if is_multilingual(file_name) else "en"

# "Depth view. Depth view." -> "Depth view."; "" when the text isn't one
# phrase written twice. Only used to recognise a command: what gets typed is
# never changed.
static func said_twice(text: String) -> String:
	var words := text.split(" ", false)
	if words.size() < 2 or words.size() % 2 != 0:
		return ""
	var half := words.size() / 2
	for i in half:
		if VoiceCommands.normalize(words[i]) != VoiceCommands.normalize(words[half + i]):
			return ""
	return " ".join(words.slice(0, half))

## More text than the clip has room for is the model making words up, not
## speech: 242 characters came back from 1.4 seconds once (6y; the one word said
## was "connected"). Ordinary dictation runs at 8 to 15 characters a second.
const SPOKEN_CHARS_PER_SECOND := 30.0
const SPOKEN_CHARS_ALLOWANCE := 20

static func more_than_spoken(characters: int, seconds: float) -> bool:
	return characters > SPOKEN_CHARS_ALLOWANCE + int(SPOKEN_CHARS_PER_SECOND * maxf(seconds, 0.0))

## The same word or short phrase this many times in a row is the model stuck
## in a loop, not speech ("Meteor Meteor Meteor ..." 23 times from a one-second
## clip, 6p). Three in a row is left alone: people do say "no, no, no".
const RUNAWAY_REPEATS := 4
const RUNAWAY_PHRASE_WORDS := 4

## Text with any runaway repeat cut down to one. Everything else is returned
## exactly as it came.
static func collapse_runaway(text: String) -> String:
	var words := text.split(" ", false)
	var keys: Array[String] = []
	for w in words:
		keys.append(VoiceCommands.normalize(w))
	var out: Array[String] = []
	var i := 0
	while i < words.size():
		var cut := 0
		for n in range(1, RUNAWAY_PHRASE_WORDS + 1):
			if i + n * RUNAWAY_REPEATS > words.size():
				break
			var repeats := 1
			while i + (repeats + 1) * n <= words.size() and keys.slice(i + repeats * n, i + (repeats + 1) * n) == keys.slice(i, i + n):
				repeats += 1
			var phrase := "".join(keys.slice(i, i + n))
			# Not digits: "5 5 5 5" can be a number being read out.
			if repeats >= RUNAWAY_REPEATS and phrase != "" and not phrase.is_valid_int():
				for k in n:
					out.append(words[i + k])
				cut = repeats * n
				break
		if cut > 0:
			i += cut
		else:
			out.append(words[i])
			i += 1
	return " ".join(out) if out.size() != words.size() else text

# The file of the model to use: the chosen size, of the kind the menu's
# language calls for, or the nearest thing installed (model_choice()).
func _model_in_use() -> String:
	return model_choice(main.settings.voice_model, Localization.current() == "en", FileAccess.file_exists)["path"]

var _language_told := "en"

func _tell_language() -> void:
	_language_told = language_for(_model_name, Localization.current())
	if typer:
		typer.call("set_language", _language_told)

## The menu's language has changed (Advanced Settings > Language): the model
## for it, told which language to listen for. Says so when the menu is in a
## language the installed model doesn't know.
func language_changed() -> void:
	if typer == null:
		return
	if _model_in_use().get_file() != _model_name:
		if is_busy():
			_recheck_model = true
			return
		reload_model()
	else:
		_tell_language()
	main._log("[VOICE] menu language %s: speech model %s, listening for %s" % [Localization.current(), _model_name, _language_told])
	if Localization.current() != "en" and not is_multilingual(_model_name):
		_notice(Localization.t("Voice typing hears English only until a multilingual speech model is installed (run install.sh again)."), 6.0)

func is_busy() -> bool:
	return typer != null and (_pending or bool(typer.call("is_recording")) or bool(typer.call("is_loading")) or bool(typer.call("is_busy")))

# After Advanced > Speech Model changes: a fresh listener with the other
# model. The old one is dropped (it is reference counted) once nothing is
# recording or being worked out.
func reload_model() -> void:
	if typer == null or is_busy():
		return
	for sig in [["model_loaded", _on_model_loaded], ["transcribed", _on_transcribed], ["recording_started", _on_recording_started]]:
		if typer.is_connected(sig[0], sig[1]):
			typer.disconnect(sig[0], sig[1])
	typer = null
	setup(main)

func available() -> bool:
	return typer != null and typer.call("is_ready")

func _on_model_loaded(ok: bool, error: String) -> void:
	main._log("[VOICE] speech model %s" % ("ready" if ok else "failed: " + error))
	if _recheck_model:
		_recheck_model = false
		use_chosen_model.call_deferred()

## Called once the saved settings are in: voice typing is set up before them
## (with Base), so a saved choice of Small is put in force here. In 6h and 6i
## the menu said Small while Base was listening until the option was pressed.
func use_chosen_model() -> void:
	if typer == null:
		return
	if _model_in_use().get_file() == _model_name:
		_tell_language() # the saved language is known by now
		return
	if is_busy():
		_recheck_model = true   # still loading: look again when that is done
		return
	main._log("[VOICE] saved choice is %s" % MODEL_LABELS[main.settings.voice_model])
	reload_model()

func is_recording() -> bool:
	return typer != null and bool(typer.call("is_recording"))

func press(toggle: bool = false) -> void:
	if typer == null:
		_notice("Voice typing isn't installed. Run install.sh again to add it.")
		return
	if typer.call("is_loading"):
		_notice("Voice typing is still loading. Try again in a moment.")
		return
	if not typer.call("is_ready"):
		_notice("Voice typing couldn't load its speech model.")
		return
	if not main.is_streaming:
		_notice("Connect to your PC first, then hold to talk.")
		return
	if typer.call("is_busy") or typer.call("is_recording"):
		return
	# The microphone takes about half a second to open on the Frame. That
	# happens in the background (it used to freeze the picture on every
	# press); "Listening" and the buzz come when it is really open.
	_open_usec = Time.get_ticks_usec()
	_open_toggle = toggle
	if typer.call("start_recording"):
		_press_ms = Time.get_ticks_msec()
		_notice("Opening the microphone...", 5.0)
	else:
		_notice(Localization.t("Couldn't open the microphone: %s") % typer.call("get_error"))

func _on_recording_started(ok: bool, error: String) -> void:
	if ok:
		_press_ms = Time.get_ticks_msec()
		_notice("Listening... tap Mic again when you're done." if _open_toggle else "Listening... let go when you're done.", 30.0)
		_buzz(0.6, 0.06)
		main._log("[VOICE] listening (microphone opened in %d ms, in the background)" % ((Time.get_ticks_usec() - _open_usec) / 1000))
	elif error != "":
		_notice(Localization.t("Couldn't open the microphone: %s") % error)
	# Otherwise the button was let go before the microphone was open;
	# release() has already said so.

func release() -> void:
	if typer == null or not typer.call("is_recording"):
		return
	if typer.call("is_opening"):
		typer.call("stop_recording", false)
		_notice("Hold the button until it says Listening, then speak.", 2.5)
		return
	var held := (Time.get_ticks_msec() - _press_ms) / 1000.0
	if held < MIN_SECONDS:
		typer.call("stop_recording", false)
		_notice("Hold the button while you speak.", 2.0)
		return
	_pending = true
	main.settings_controller.set_voice_working(true)
	_stop_usec = Time.get_ticks_usec()
	typer.call("stop_recording", true)
	_notice("Typing...", 10.0)

func _on_transcribed(raw: String, rms: float, seconds: float) -> void:
	_pending = false
	var depth_eased: bool = main.settings_controller.voice_easing_depth()
	main.settings_controller.set_voice_working(false)
	var worked := (Time.get_ticks_usec() - _stop_usec) / 1000000.0
	if rms < SILENCE_RMS:
		_notice("Didn't hear anything.", 2.0)
		_buzz(0.8, 0.2)
		main._log("[VOICE] silence (%.1fs)" % seconds)
		return
	var text := _clean(raw)
	var tidied := collapse_runaway(text)
	if tidied != text:
		main._log("[VOICE] runaway repeat cut: %d characters to %d" % [text.length(), tidied.length()])
		text = tidied
	if more_than_spoken(text.length(), seconds):
		_notice("Didn't catch that.", 2.0)
		_buzz(0.8, 0.2)
		main._log("[VOICE] more text than speech, not typed: %d characters for %.1fs" % [text.length(), seconds])
		return
	var bare := _bare(text)
	if bare in ALWAYS_DROP or (bare in QUIET_DROP and rms < SILENCE_RMS * 4.0):
		_notice("Didn't catch that.", 2.0)
		_buzz(0.8, 0.2)
		main._log("[VOICE] nothing to type (%.1fs)" % seconds)
		return
	# Nightfall commands: only when the command is the whole clip, so the same
	# words inside a sentence are typed as normal.
	# Commands: Off (Advanced Settings) leaves all of this out: what was said
	# is typed, "clear" and "submit" included.
	var commands_on: bool = main.settings.voice_commands
	# In another language than English the clip is first put into the words
	# the command engines know (VoicePacks); what gets typed stays as said.
	var pack: Dictionary = VoicePacks.current() if commands_on else {}
	var as_command: String = text if pack.is_empty() else VoicePacks.to_english(text, pack, menu().vocabulary())
	var cmd: Dictionary = VoiceCommands.match_command(as_command, main.settings.voice_require_prefix) if commands_on else {}
	if cmd.is_empty() and commands_on:
		# The model now and then writes a short clip out twice ("Depth view.
		# Depth view.", seen with Small in 6i). Said once, it is the command.
		var once := said_twice(text)
		if once != "":
			cmd = VoiceCommands.match_command(once if pack.is_empty() else VoicePacks.to_english(once, pack, menu().vocabulary()), main.settings.voice_require_prefix)
	if not cmd.is_empty():
		cmd["id"] = _resolve_toggle(cmd["id"])
		_run_command(cmd["id"], cmd["arg"])
		_buzz(0.4, 0.04)
		main._log("[VOICE] command: %s" % cmd["id"])
		return
	# Anything else in the menu, by its own name ("bezel off", "fps 90").
	var menu_said: String = menu().run(as_command, main.settings.voice_require_prefix) if commands_on else ""
	if menu_said != "":
		_confirm("menu", menu_said)
		_buzz(0.4, 0.04)
		main._log("[VOICE] menu command -> %s" % menu_said)
		return
	# Whisper sometimes hears a lone "new line" as "new life", "new one"...
	if VoiceCommands.normalize(text) in ["new life", "newlife", "new lie", "new lane", "new on", "new one"]:
		text = "new line"
	# "clear" / "submit" as the whole clip, or its first or last word.
	var words := text.split(" ", false)
	var do_clear := false
	var do_submit := false
	if commands_on and words.size() > 0 and _bare(words[0]) == "clear":
		do_clear = true
		words.remove_at(0)
		# "clear that" / "clear it": the second word is part of the command.
		if words.size() > 0 and _bare(words[0]) in ["that", "this", "it", "last"]:
			words.remove_at(0)
	if commands_on and words.size() > 0 and _bare(words[words.size() - 1]) == "submit":
		do_submit = true
		words.remove_at(words.size() - 1)
	# The same two words in the menu's language.
	if not pack.is_empty():
		var said := " ".join(words)
		var spaceless: bool = pack.get("spaceless", false)
		if not do_clear:
			var cleared := VoicePacks.after_leading(said, pack["typing"].get("clear", []), spaceless)
			if not cleared.is_empty():
				do_clear = true
				said = cleared["rest"]
		if not do_submit:
			var submitted := VoicePacks.before_trailing(said, pack["typing"].get("submit", []), spaceless)
			if not submitted.is_empty():
				do_submit = true
				said = submitted["rest"]
		words = said.split(" ", false)
	if do_clear:
		for i in _last_typed:
			_tap(KEY_BACKSPACE)
		_last_typed = 0
	var body := _spoken_symbols(" ".join(words), VoicePacks.symbol_rules(pack))
	if not body.strip_edges().is_empty() or body.contains("\n"):
		if not body.ends_with("\n"):
			body += " "
		_send_with_newlines(body)
		_last_typed = body.length()
	if do_submit:
		_tap(KEY_ENTER)
		_last_typed = 0
	_notice("", 0.0)
	_buzz(0.4, 0.04)
	await main.get_tree().create_timer(0.1).timeout
	_buzz(0.4, 0.04)
	main._log("[VOICE] typed %d characters in %.1fs of speech, worked out in %.1fs with %s%s%s%s%s" % [
		body.length(), seconds, worked, _model_name, " (depth model eased)" if depth_eased else "",
		" (clear)" if do_clear else "", " (submit)" if do_submit else "",
		clip_stats_text(typer.get_last_clip_stats() if typer and typer.has_method("get_last_clip_stats") else {})])

## The clip's own numbers for the log: how much of it was quiet, how much of
## the pauses was cut before the model heard it, and how much the model made
## of it. For telling a sentence the microphone never delivered from one the
## model dropped. Loudness and counts only: nothing of what was said.
static func clip_stats_text(stats: Dictionary) -> String:
	if stats.is_empty():
		return ""
	return " | sound: %d%% quiet, %d%% dead, %.1fs of pauses cut | model: %d tokens in %d parts, %s, no-speech %d%%" % [
		roundi(float(stats.get("quiet_share", 0.0)) * 100.0), roundi(float(stats.get("zero_share", 0.0)) * 100.0),
		float(stats.get("trimmed_seconds", 0.0)), int(stats.get("tokens", 0)), int(stats.get("parts", 0)),
		passes_text(int(stats.get("passes", 0))) + stretches_text(stats.get("stretches", [])),
		roundi(float(stats.get("no_speech", 0.0)) * 100.0)]

## When a clip was listened to in more than one stretch: how long each was
## (the first is the whole clip, each later one what was left of it).
static func stretches_text(stretches) -> String:
	if stretches == null or stretches.size() < 2:
		return ""
	var parts := PackedStringArray()
	for seconds in stretches:
		parts.append("%.1f s" % seconds)
	return " (%s)" % ", then ".join(parts)

## How many times the model listened to the clip (each costs about the same).
static func passes_text(passes: int) -> String:
	return "listened once" if passes == 1 else "listened %d times" % passes if passes > 1 else "listening not counted"

# A short vibration on the right controller: it works even where the on-screen
# notice can't show (a curved screen doesn't draw notices yet).
func _buzz(strength: float, seconds: float) -> void:
	if main.right_hand and main.settings.haptics > 0:
		main.right_hand.trigger_haptic_pulse("haptic", 0.0, strength, seconds, 0.0)

# Spoken symbols: "open/close parenthesis" (or bracket) and "new line" /
# "new paragraph" (Shift+Enter, which makes a line break in chats without
# sending). Whisper often adds its own full stop or comma after them.
static func _spoken_symbols(t: String, more_rules: Array = []) -> String:
	var rules := more_rules + [
		["(?i)\\s*\\b(open|left) (paren|parenthesis|parentheses|bracket)\\b[.,]?\\s*", " ("],
		["(?i)\\s*\\b(close|closed|right) (paren|parenthesis|parentheses|bracket)\\b[.,]?", ")"],
		["(?i)\\s*\\bnew ?paragraph\\b[.,!?]?\\s*", "\n\n"],
		["(?i)\\s*\\bnew[ -]?(line|vine|mind)\\b[.,!?]?\\s*", "\n"],
	]
	for r in rules:
		var re := RegEx.new()
		re.compile(r[0])
		t = re.sub(t, r[1], true)
	# Only spaces are trimmed: a leading line break ("new line" said on its
	# own) must survive.
	return t.replace("( ", "(").lstrip(" ")

# Text goes as typed text; each line break as Shift+Enter.
func _send_with_newlines(text: String) -> void:
	var parts := text.split("\n")
	for i in parts.size():
		if not parts[i].is_empty():
			main.stream_backend.send_utf8_text(parts[i])
		if i < parts.size() - 1:
			main.stream_backend.send_keyboard_event(KEY_SHIFT, 3, 0)
			main.stream_backend.send_keyboard_event(KEY_ENTER, 3, 0x01)
			main.stream_backend.send_keyboard_event(KEY_ENTER, 4, 0x01)
			main.stream_backend.send_keyboard_event(KEY_SHIFT, 4, 0)

func _tap(key: int) -> void:
	main.stream_backend.send_keyboard_event(key, 3, 0)
	main.stream_backend.send_keyboard_event(key, 4, 0)

func _chord(keys: Array) -> void:
	var mods := 0
	var bits := {KEY_SHIFT: 0x01, KEY_CTRL: 0x02, KEY_ALT: 0x04, KEY_META: 0x08}
	for k in keys:
		main.stream_backend.send_keyboard_event(k, 3, mods)
		mods |= bits.get(k, 0)
	for idx in range(keys.size() - 1, -1, -1):
		var k = keys[idx]
		mods &= ~bits.get(k, 0)
		main.stream_backend.send_keyboard_event(k, 4, mods)

## The commands made from the menu's own buttons.
func menu() -> VoiceMenu:
	if _menu == null:
		_menu = VoiceMenu.new(main)
	return _menu

# "depth view" on its own flips Depth View: the on or the off command,
# whichever changes how things stand now. Other ids come back unchanged.
func _resolve_toggle(id: String) -> String:
	if not VoiceCommands.TOGGLES.has(id):
		return id
	var st = main.settings
	var on := false
	match id:
		"headlock_toggle": on = st.head_lock != 0
		"menu_toggle": on = main.ui_visible
		"keyboard_toggle": on = main.virtual_keyboard != null and main.virtual_keyboard.visible
		"passthrough_toggle": on = st.passthrough_enabled
		"sbs_toggle": on = st.host.sbs_mode > 0
		"ai3d_toggle": on = st.host.ai_3d_speed != 0
		"depth_toggle": on = st.host.ai_3d_depth_view
		"gamepad_toggle": on = main.controller_mapper != null and main.controller_mapper.is_active()
		"ray_toggle": on = st.show_pointer_ray
		"mic_toggle": on = st.microphone_enabled
		"buttons_toggle": on = main.button_bindings != null and main.button_bindings.enabled
		"vibration_toggle": on = st.haptics > 0
	return VoiceCommands.TOGGLES[id][1 if on else 0]

func _run_command(c: String, arg: int) -> void:
	var sc = main.settings_controller
	var st = main.settings
	if c != "separation_n":
		arg = mini(arg, 100) # everything else is 0-100 (or an F key)
	var msg := ""
	if VoiceCommands.KEYS.has(c) or c == "k_f":
		if c == "k_f":
			if arg < 1 or arg > 12:
				_notice(Localization.t("There's no F%d key.") % arg, 1.5)
				return
			_chord([KEY_F1 + arg - 1])
			msg = "F%d" % arg
		else:
			_chord(VoiceCommands.KEYS[c])
		_confirm(c, msg)
		return
	match c:
		"headlock_on":
			sc.set_head_lock(st.head_lock_last_on)
		"headlock_off":
			sc.set_head_lock(0)
		"headlock_tilt":
			sc.set_head_lock(2)
		"headlock_level":
			sc.set_head_lock(1)
		"recenter":
			main.recenter_view()
			msg = "Recentered."
		"menu_show":
			main.show_menu_in_view()
		"menu_hide":
			if main.ui_visible:
				main._toggle_ui()
		"keyboard_show":
			if main.virtual_keyboard and not main.virtual_keyboard.visible:
				main.virtual_keyboard.toggle()
		"keyboard_hide":
			if main.virtual_keyboard and main.virtual_keyboard.visible:
				main.virtual_keyboard.toggle()
		"curve_n", "curve_flat":
			var amount := 0 if c == "curve_flat" else int(round(arg / 5.0) * 5)
			main.screen_manager.set_curve_amount(amount, true)
			msg = "Curve %d%%." % amount if amount > 0 else "Flat screen."
		"passthrough_on", "passthrough_off":
			if st.passthrough_enabled != (c == "passthrough_on"):
				sc.toggle_passthrough()
			msg = "Passthrough on." if st.passthrough_enabled else "Passthrough off."
		"ambient_off", "ambient_static", "ambient_slow", "ambient_live":
			var want: int = ["ambient_off", "ambient_static", "ambient_slow", "ambient_live"].find(c)
			for i in 4:
				if st.ambient_mode == want:
					break
				sc.cycle_ambient_mode()
			msg = "Ambient: %s." % main.ambient_mode_labels[st.ambient_mode]
		"glow_strength_n":
			sc.set_glow_strength(int(round(arg / 5.0) * 5), true)
			msg = "Glow strength %d%%." % st.ambient_strength
		"glow_size_n":
			sc.set_glow_size(int(round(arg / 5.0) * 5), true)
			msg = "Glow size %d%%." % st.ambient_size
		"sbs_on", "sbs_off":
			if (st.host.sbs_mode > 0) != (c == "sbs_on"):
				main.auto_detect_enabled = false
				sc.toggle_sbs_mode()
			msg = "Side by side on." if st.host.sbs_mode > 0 else "Side by side off."
		"ai3d_on", "ai3d_off":
			if (st.host.ai_3d_speed != 0) != (c == "ai3d_on"):
				sc.toggle_ai_3d_enabled()
			msg = "3D on." if st.host.ai_3d_speed != 0 else "3D off."
		"depth_on", "depth_off":
			var on: bool = st.host.ai_3d_depth_view
			if (c == "depth_on") != on:
				main.ui_controller.on_ai_3d_depth_view_toggled()
			if st.host.ai_3d_depth_view == on and (c == "depth_on") != on:
				msg = "Depth View needs AI 3D on (and SBS off)."
			else:
				msg = "Depth View on." if st.host.ai_3d_depth_view else "Depth View off."
		"gamepad_on", "gamepad_off":
			if main.controller_mapper and main.controller_mapper.is_active() != (c == "gamepad_on"):
				main.controller_mapper.check_toggle_ui()
		"ray_on", "ray_off":
			if (c == "ray_on") != st.show_pointer_ray:
				sc.toggle_pointer_ray()
			msg = "Pointer ray on." if st.show_pointer_ray else "Pointer ray off."
		"mic_on", "mic_off":
			if st.microphone_enabled != (c == "mic_on"):
				sc.toggle_microphone()
			msg = "Microphone on." if st.microphone_enabled else "Microphone off."
		"vibration_on", "vibration_off":
			var want_h := 1 if c == "vibration_on" else 0
			if (st.haptics > 0) != (want_h > 0):
				st.haptics = want_h
				sc._save_setting(main._ui_haptics_btn, sc.HAPTICS_LABELS[st.haptics])
			msg = "Vibration on." if st.haptics > 0 else "Vibration off."
		"pt_fade_n":
			sc.set_passthrough_fade(int(round(arg / 5.0) * 5), true)
			msg = "Passthrough fade %s." % PassthroughFade.label(st.passthrough_fade_pct).to_lower()
			if not st.passthrough_enabled:
				msg += " (Shows when passthrough is on.)"
		"volume_n":
			sc.set_volume(int(round(arg / 5.0) * 5), true)
			msg = "Volume: %s." % sc.get_audio_boost_label()
		"vol_up":
			sc.step_volume("vol_up")
		"vol_down":
			sc.step_volume("vol_down")
		"mute_on", "mute_off":
			if (st.audio_boost_db <= -60) != (c == "mute_on"):
				sc.step_volume("mute")
			msg = "Muted." if st.audio_boost_db <= -60 else "Unmuted."
		"volume_db_minus", "volume_db_plus":
			# The slider's own scale: 3 dB steps from -45 to +12, Normal at 0.
			var db: int = clampi(-arg if c == "volume_db_minus" else arg, -45, 12)
			sc.set_volume(int(round((db + 48) / 3.0)) * 5, true)
			msg = "Volume: %s." % sc.get_audio_boost_label()
		"volume_normal":
			sc.set_volume(80, true)
			msg = "Volume: %s." % sc.get_audio_boost_label()
		"separation_n":
			# The slider runs 25-400% in steps of 25.
			var step: int = clampi(int(round((arg - 25) / 25.0)), 0, sc.AI3D_SEPARATION_SLIDER_STEPS)
			sc.set_ai_3d_separation(int(round(step * 100.0 / sc.AI3D_SEPARATION_SLIDER_STEPS)), true)
			msg = "Separation %d%%." % st.host.ai_3d_separation_pct
		"convergence_n":
			sc.set_ai_3d_convergence(arg, true)
			msg = "Convergence %d%%." % st.host.ai_3d_convergence_pct
		"primary_right", "primary_left", "primary_auto":
			var mapper = main.controller_mapper
			if mapper:
				mapper.primary_hand = ["primary_right", "primary_left", "primary_auto"].find(c)
				main.state_manager.save_state()
				main.ui_controller.update_primary_btn()
				msg = "Primary hand: %s." % mapper.primary_labels[mapper.primary_hand]
		"buttons_on", "buttons_off":
			var bb = main.button_bindings
			if bb:
				if bb.enabled != (c == "buttons_on"):
					bb.toggle_enabled()
				msg = "Custom buttons on." if bb.enabled else "Custom buttons off: Default layout."
	if c.begins_with("headlock_"):
		return # Head Lock shows its own popup
	_confirm(c, msg)

# Every command confirms itself with a short popup (unless turned off in
# Advanced Settings → Voice Commands → Confirm Commands).
func _confirm(c: String, msg: String) -> void:
	if not main.settings.voice_confirm:
		_notice("", 0.0)
		return
	if msg.is_empty():
		msg = VoicePacks.confirm_text(c, VoicePacks.current())
	if msg.is_empty():
		msg = VoiceCommands.confirm_text(c)
	_notice(msg, 1.8)

static func _clean(s: String) -> String:
	var t := s.strip_edges().replace("\n", " ")
	while t.contains("  "):
		t = t.replace("  ", " ")
	return t

static func _bare(s: String) -> String:
	var t := s.to_lower().strip_edges()
	for ch in [".", ",", "!", "?", ";", ":"]:
		t = t.trim_suffix(ch).trim_prefix(ch)
	return t.strip_edges()

func _notice(text: String, seconds: float = 3.0) -> void:
	if main.comp and main.comp.has_method("show_notice"):
		main.comp.show_notice(text, seconds)

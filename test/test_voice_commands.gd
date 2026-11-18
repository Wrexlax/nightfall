extends SceneTree

# What spoken clips count as which voice command (Steam Frame voice typing).

func _expect(said: String, id: String, arg: int = -1, prefix: bool = false) -> void:
	var m: Dictionary = VoiceCommands.match_command(said, prefix)
	assert(m.get("id", "") == id, "'%s' should be %s, got %s" % [said, id if id != "" else "typed text", str(m)])
	if id != "":
		assert(m["arg"] == arg, "'%s' should carry %d, got %d" % [said, arg, m["arg"]])

# Commands made from the menu's own buttons (VoiceMenu): which button a clip
# names, and whether a button's value answers to what was said.
func _menu_commands() -> void:
	var menu := []
	for label in ["Bezel", "Cursor Type", "Cursor Steady", "FPS", "Reconnect Stream", "Quality", "Menu & Keyboard Follow", "Color"]:
		menu.append({"label": label, "names": VoiceMenu.names_for(label)})
	var cases := [
		["bezel off", "Bezel", "off"], ["off bezel", "Bezel", "off"],
		["cursor type pointer", "Cursor Type", "pointer"], ["cursor steady high", "Cursor Steady", "high"],
		["frame rate 90", "FPS", "90"], ["fps to 120", "FPS", "120"],
		["next fps", "FPS", "next"], ["reconnect audio", "Reconnect Stream", ""], ["reconnect stream", "Reconnect Stream", ""],
		["depth model meteor", "Quality", "meteor"], ["model meteor", "Quality", "meteor"],
		["menu and keyboard follow off", "Menu & Keyboard Follow", "off"],
		["glow colour red", "Color", "red"],
	]
	for c in cases:
		var key: String = VoiceCommands.command_key(c[0], false)["key"]
		var hit: Dictionary = VoiceMenu.parse(key, menu)
		assert(not hit.is_empty() and hit["entry"]["label"] == c[1] and hit["rest"] == c[2],
			"'%s' should be %s / '%s', got %s" % [c[0], c[1], c[2], str(hit)])
	assert(VoiceMenu.parse("please save the file", menu).is_empty())
	for v in [["90", "90"], ["+10%", "10"], ["+10%", "plus 10"], ["-10%", "minus 10"], ["20hz", "20"],
			["50 Mbps", "50"], ["PC Cursor", "pc cursor"], ["3D Scene", "3d scene"], ["One Euro", "1 euro"],
			["Clicks + Hover", "clicks and hover"], ["Keyboard+Mouse", "keyboard and mouse"], ["Keyboard+Mouse", "keyboard mouse"], ["Meteor", "meteor"]]:
		assert(VoiceMenu.says(v[0], v[1]), "'%s' should answer to '%s'" % [v[0], v[1]])
	for v in [["90", "120"], ["+10%", "minus 10"], ["3D Scene", "3"], ["High", "low"], ["100%", "10"]]:
		assert(not VoiceMenu.says(v[0], v[1]), "'%s' should not answer to '%s'" % [v[0], v[1]])

func _init():
	# Plain commands and everyday wording around them.
	_expect("Select all.", "k_select_all")
	_expect("Head-lock on!", "headlock_on")
	_expect("Turn on 3D", "ai3d_on")
	_expect("Nightfall, recenter", "recenter", -1, true)
	_expect("recenter", "", -1, true) # "Require 'Nightfall'" is on and it wasn't said
	# Numbers: digits, words, percent, "set ... to".
	_expect("Curve fifty percent", "curve_n", 50)
	_expect("set glow to 70", "glow_strength_n", 70)
	_expect("Pass through fade 50.", "pt_fade_n", 50)
	_expect("PTFADE 50percent.", "pt_fade_n", 50)
	_expect("F5", "k_f", 5)
	# Volume, as a percentage and in the slider's decibels.
	_expect("Volume 80", "volume_n", 80)
	_expect("Volume negative 20 decibels.", "volume_db_minus", 20)
	_expect("Volume negative eight decibels", "volume_db_minus", 8)
	_expect("Volume -20 dB.", "volume_db_minus", 20)
	_expect("volume minus 12db", "volume_db_minus", 12)
	_expect("Set the volume to minus 9 decibels", "volume_db_minus", 9)
	_expect("Volume +6 dB", "volume_db_plus", 6)
	_expect("volume plus six decibels", "volume_db_plus", 6)
	_expect("Volume 3 decibels", "volume_db_plus", 3)
	_expect("Volume normal.", "volume_normal")
	_expect("Volume mute", "mute_on")
	_expect("Mute.", "mute_on")
	_expect("Volume unmute", "mute_off")
	_expect("Unmute", "mute_off")
	_expect("Increase volume", "vol_up")
	_expect("Decrease volume.", "vol_down")
	_expect("Turn the volume up", "vol_up")
	_expect("turn down the volume", "vol_down")
	# Either word order.
	_expect("Normal volume", "volume_normal")
	_expect("50 curve", "curve_n", 50)
	_expect("On head lock", "headlock_on")
	_expect("minus 12 decibels volume", "volume_db_minus", 12)
	# AI 3D strength and the Buttons tab's switch.
	_expect("Separation 150", "separation_n", 150)
	_expect("separation 400 percent", "separation_n", 400)
	_expect("Convergence thirty", "convergence_n", 30)
	_expect("Custom buttons off", "buttons_off")
	_menu_commands()
	# Sentences are typed, not run.
	_expect("I turned the volume up to 80 yesterday", "")
	_expect("please select all of the files", "")
	print("All voice_commands tests passed")
	quit()

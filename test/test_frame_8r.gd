extends SceneTree

# Steam Frame 8r: the PIN screen says what to do on the PC at each stage of
# pairing, in every language, and the text fits where it is shown.

func _init() -> void:
	var heads: Array[String] = [WelcomeScreen.PIN_HEAD_HOST, WelcomeScreen.PIN_HEAD_METEOR, WelcomeScreen.PIN_HEAD_EXPIRED]
	var helps: Array[String] = [WelcomeScreen.PIN_HELP_HOST, WelcomeScreen.PIN_HELP_METEOR, WelcomeScreen.PIN_HELP_EXPIRED]
	var problems := PackedStringArray()
	for language in Localization.LANGUAGES:
		var code: String = language["code"]
		Localization.apply(code)
		for text in heads:
			var shown := Localization.t(text)
			if code != "en" and shown == text:
				problems.append("%s: not translated: %s" % [code, text])
			# One line of the welcome screen (1920 wide) at the heading's size.
			var line := TextLine.new()
			line.add_string(shown, ThemeDB.fallback_font, 40)
			if line.get_line_width() > WelcomeScreen.WELCOME_FRAME.x - 200:
				problems.append("%s: heading too wide (%d px): %s" % [code, int(line.get_line_width()), text])
		for text in helps:
			var shown := Localization.t(text)
			if code != "en" and shown == text:
				problems.append("%s: not translated: %s" % [code, text.left(40)])
			var paragraph := TextParagraph.new()
			paragraph.break_flags = TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE
			paragraph.width = WelcomeScreen.PIN_HELP_WIDTH
			paragraph.add_string(shown, ThemeDB.fallback_font, WelcomeScreen.PIN_HELP_FONT)
			if paragraph.get_line_count() > 3:
				problems.append("%s: help of %d lines: %s" % [code, paragraph.get_line_count(), text.left(40)])
			# The names of things on the PC stay as the PC shows them.
			if text == WelcomeScreen.PIN_HELP_METEOR and not shown.contains("Approve pairing"):
				problems.append("%s: Meteor's menu item is not named as Meteor names it" % code)
	Localization.apply("en")
	assert(problems.is_empty(), "\n".join(problems))

	# The screen has the help line, and the two stages after the first are set
	# through one place.
	var source := FileAccess.get_file_as_string("res://src/welcome_screen.gd")
	assert(source.contains("help.name = \"PINHelp\""))
	assert(source.contains("set_pin_stage(PIN_HEAD_METEOR, PIN_HELP_METEOR)"))
	assert(source.contains("set_pin_stage(PIN_HEAD_EXPIRED, PIN_HELP_EXPIRED)"))

	# 8s: pressing Logging says when the change takes effect, unless the
	# choice is what this run is already doing.
	assert(SettingsController.logging_notice(true, false) == SettingsController.LOGGING_STARTS)
	assert(SettingsController.logging_notice(false, true) == SettingsController.LOGGING_STOPS)
	assert(SettingsController.logging_notice(true, true).is_empty())
	assert(SettingsController.logging_notice(false, false).is_empty())
	for language in Localization.LANGUAGES:
		Localization.apply(language["code"])
		for text in [SettingsController.LOGGING_STARTS, SettingsController.LOGGING_STOPS]:
			assert(language["code"] == "en" or Localization.t(text) != text, "%s: %s" % [language["code"], text])
	Localization.apply("en")

	print("test_frame_8r passed")
	quit()

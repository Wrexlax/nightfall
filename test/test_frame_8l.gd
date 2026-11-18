extends SceneTree

# Steam Frame 8l: voice typing and voice commands in the menu's language
# (steam-frame/i18n/VOICE.md).

const CODES := ["af", "cs", "da", "de", "es", "fi", "fr", "it", "ja", "ko", "nb", "nl", "pl", "pt_BR", "ru", "sv", "tr", "uk", "zh_CN", "zh_TW"]

func _id(said: String, pack: Dictionary) -> Dictionary:
	return VoiceCommands.match_command(VoicePacks.to_english(said, pack), false)

func _initialize() -> void:
	await process_frame
	Localization.load_translations()

	# English has no pack and nothing about it changes.
	assert(VoicePacks.pack("en").is_empty())
	assert(VoicePacks.to_english("Select all.", {}) == "Select all.")
	assert(VoicePacks.whisper_language("en") == "en")

	# Every language has a pack that loads, and every phrase in it leads to
	# the command it is filed under, as the speech model would write it
	# (capital letter, full stop) and plain.
	var phrases_checked := 0
	for code in CODES:
		var raw = JSON.parse_string(FileAccess.get_file_as_string("res://locale/voice/%s.json" % code))
		assert(raw is Dictionary, "%s: not readable" % code)
		assert(VoicePacks.problems(raw).is_empty(), "%s: %s" % [code, ", ".join(VoicePacks.problems(raw))])
		var pack := VoicePacks.pack(code)
		assert(not pack.is_empty(), "%s: no pack" % code)
		assert(VoicePacks.whisper_language(code) != "" and VoicePacks.whisper_language(code).length() <= 3)
		var seen := {}
		for english in pack["commands"]:
			assert(pack["_ids"].has(english), "%s: '%s' is not a phrase VoiceCommands knows" % [code, english])
			var wanted: String = pack["_ids"][english]
			assert(not (pack["commands"][english] as Array).is_empty(), "%s: nothing to say for '%s'" % [code, english])
			for phrase in pack["commands"][english]:
				assert(not seen.has(phrase), "%s: '%s' is filed under '%s' and '%s'" % [code, phrase, seen.get(phrase, ""), english])
				seen[phrase] = english
				var said: String = String(phrase).replace("#", "50" if pack.get("spaceless", false) else " 50").replace("  ", " ")
				for form in [said, said.substr(0, 1).to_upper() + said.substr(1) + "."]:
					var got := _id(form, pack)
					assert(got.get("id", "") == wanted, "%s: \"%s\" gave %s, not %s (as English: \"%s\")" % [code, form, got.get("id", "nothing"), wanted, VoicePacks.to_english(form, pack)])
					if String(phrase).contains("#"):
						assert(got["arg"] == 50, "%s: \"%s\" lost its number" % [code, form])
					phrases_checked += 1
		for kind in ["clear", "submit", "new line", "new paragraph", "open parenthesis", "close parenthesis"]:
			assert(not (pack["typing"].get(kind, []) as Array).is_empty(), "%s: no words for '%s'" % [code, kind])
		for kind in ["on", "off", "next"]:
			assert(not (pack[kind] as Array).is_empty(), "%s: no word for '%s'" % [code, kind])

		# Any menu button, by the name the menu shows in that language: the
		# button's name with the pack's word for off, on and next.
		Localization.apply(code)
		for label in ["Bezel", "Passthrough", "Stats"]:
			var menu := [{"label": label, "names": VoiceMenu.names_for(label)}]
			var shown := Localization.t(label)
			var gap := "" if pack.get("spaceless", false) else " "
			for word in [["off", "off"], ["on", "on"]]:
				for spoken in pack[word[0]]:
					var said := "%s%s%s." % [shown, gap, spoken]
					var key := VoiceCommands.command_key(VoicePacks.to_english(said, pack, menu[0]["names"]), false)
					var hit := VoiceMenu.parse(key["key"], menu)
					assert(not hit.is_empty() and hit["rest"] == word[1], "%s: \"%s\" was read as \"%s\"" % [code, said, key["key"]])
			var next_said := "%s%s%s" % [pack["next"][0], gap, shown]
			var next_key := VoiceCommands.command_key(VoicePacks.to_english(next_said, pack, menu[0]["names"]), false)
			var next_hit := VoiceMenu.parse(next_key["key"], menu)
			assert(not next_hit.is_empty() and next_hit["rest"] == "next", "%s: \"%s\" was read as \"%s\"" % [code, next_said, next_key["key"]])
		# A value the menu shows in that language answers to itself.
		assert(VoiceMenu.says_shown("Off", VoiceCommands.normalize(VoicePacks.tidy(Localization.t("Off")))), "%s: Off" % code)
		Localization.apply("en")

		# The Voice Commands list has all three parts, nothing empty.
		var sections := UIController.voice_list_sections(pack)
		assert(sections.size() == 3)
		for section in sections:
			assert(String(section[0]) != "" and not (section[1] as Array).is_empty(), "%s: an empty part of the list" % code)
			for row in section[1]:
				assert(String(row[0]).strip_edges() != "" and not String(row[0]).contains("#"), "%s: a row with nothing to say" % code)
		for line in ["note", "note_prefix", "note_off"]:
			assert(String(pack["list"].get(line, "")) != "", "%s: no '%s'" % [code, line])
	assert(phrases_checked > 2500, "only %d phrases were tried" % phrases_checked)

	# The languages with their own font have every character of their pack
	# in it (the list and the popups show the pack's words).
	for code in Localization.CJK_FONTS:
		var font: Font = load(Localization.CJK_FONTS[code])
		var text := FileAccess.get_file_as_string("res://locale/voice/%s.json" % code)
		var missing := {}
		for i in text.length():
			var c := text.unicode_at(i)
			if c > 0x7F and not font.has_char(c):
				missing[String.chr(c)] = true
		assert(missing.is_empty(), "%s font lacks %s (run tools/i18n/build_cjk_fonts.py)" % [code, "".join(missing.keys())])

	# By hand, a few as they would be said.
	var de := VoicePacks.pack("de")
	assert(_id("Alles auswählen.", de)["id"] == "k_select_all")
	assert(_id("Lautstärke 80", de) == {"id": "volume_n", "arg": 80})
	assert(_id("Nightfall, Lautstärke 80!", de) == {"id": "volume_n", "arg": 80})
	assert(_id("Bitte das Menü zeigen", de)["id"] == "menu_show", "the dropped words")
	assert(_id("Ich möchte alles auswählen und kopieren", de).is_empty(), "a sentence is not a command")
	assert(_id("Stell die Krümmung auf 50", de) == {"id": "curve_n", "arg": 50}, VoicePacks.to_english("Stell die Krümmung auf 50", de))
	assert(_id("Громкость на 40", VoicePacks.pack("ru")) == {"id": "volume_n", "arg": 40})
	var fr := VoicePacks.pack("fr")
	assert(_id("Afficher le menu.", fr)["id"] == "menu_show")
	assert(_id("Courbure 30 %", fr) == {"id": "curve_n", "arg": 30})
	var ja := VoicePacks.pack("ja")
	assert(_id("音量80", ja) == {"id": "volume_n", "arg": 80})
	assert(_id("音量を80にして。", ja) == {"id": "volume_n", "arg": 80}, VoicePacks.to_english("音量を80にして。", ja))
	assert(_id("すべて選択", ja)["id"] == "k_select_all")
	assert(VoicePacks.segment("ベゼルをオフ", ["ベゼル", "オフ", "を"]) == "ベゼル を オフ")
	assert(VoicePacks.segment("音量80", ["音量"]) == "音量 80")
	var ko := VoicePacks.pack("ko")
	assert(_id("볼륨 50", ko) == {"id": "volume_n", "arg": 50} and _id("볼륨50", ko) == {"id": "volume_n", "arg": 50})
	assert(_id("全选", VoicePacks.pack("zh_CN"))["id"] == "k_select_all" and _id("全選", VoicePacks.pack("zh_CN"))["id"] == "k_select_all", "either script")
	assert(VoicePacks.tidy("İleri al.") == "ileri al")

	# While typing: the first and last words, and the spoken symbols.
	assert(VoicePacks.after_leading("Löschen, das war falsch", de["typing"]["clear"], false) == {"rest": "das war falsch"})
	assert(VoicePacks.after_leading("Löschend ist es", de["typing"]["clear"], false).is_empty(), "only as a whole word")
	assert(VoicePacks.before_trailing("Bis morgen, senden.", de["typing"]["submit"], false) == {"rest": "Bis morgen"})
	assert(VoicePacks.before_trailing("Wir versenden", de["typing"]["submit"], false).is_empty())
	assert(VoicePacks.after_leading("クリア明日行きます", ja["typing"]["clear"], true) == {"rest": "明日行きます"})
	assert(VoicePacks.before_trailing("明日行きます送信。", ja["typing"]["submit"], true) == {"rest": "明日行きます"})
	assert(VoiceTyping._spoken_symbols("Erste Zeile neue Zeile zweite", VoicePacks.symbol_rules(de)) == "Erste Zeile\nzweite")
	assert(VoiceTyping._spoken_symbols("Hallo Klammer auf leise Klammer zu", VoicePacks.symbol_rules(de)) == "Hallo (leise)")
	assert(VoiceTyping._spoken_symbols("一行目改行二行目", VoicePacks.symbol_rules(ja)) == "一行目\n二行目")
	assert(VoiceTyping._spoken_symbols("first new line second") == "first\nsecond", "English as before")
	assert(VoicePacks.confirm_text("k_select_all", de) == "Alles auswählen (Ctrl+A)" and VoicePacks.confirm_text("recenter", de) == "Zentrieren")
	assert(VoicePacks.confirm_text("k_select_all", {}) == "")

	# Which speech model, for which menu language.
	var base_en := VoiceTyping.model_path(0)
	var small_en := VoiceTyping.model_path(1)
	var base_any := VoiceTyping.multilingual_path(0)
	var small_any := VoiceTyping.multilingual_path(1)
	assert(base_any.ends_with("/ggml-base.bin") and small_any.ends_with("/ggml-small.bin"))
	var have := func(files: Array) -> Callable: return func(path: String) -> bool: return path in files
	assert(VoiceTyping.model_choice(1, true, have.call([base_en, small_en, small_any])) == {"path": small_en, "multilingual": false})
	assert(VoiceTyping.model_choice(1, false, have.call([base_en, small_en, small_any])) == {"path": small_any, "multilingual": true})
	assert(VoiceTyping.model_choice(1, false, have.call([base_en, small_en, base_any])) == {"path": base_any, "multilingual": true}, "the other size before the other kind")
	assert(VoiceTyping.model_choice(0, false, have.call([base_en, small_en])) == {"path": base_en, "multilingual": false}, "English only until the other is installed")
	assert(VoiceTyping.model_choice(0, true, have.call([small_any])) == {"path": small_any, "multilingual": true}, "a multilingual model hears English too")
	assert(VoiceTyping.model_choice(1, true, have.call([])) == {"path": small_en, "multilingual": false})
	assert(VoiceTyping.language_for("ggml-small.bin", "de") == "de" and VoiceTyping.language_for("ggml-small.en.bin", "de") == "en")
	assert(VoiceTyping.language_for("ggml-base.bin", "pt_BR") == "pt" and VoiceTyping.language_for("ggml-base.bin", "nb") == "no")
	assert(VoiceTyping.language_for("ggml-base.bin", "zh_TW") == "zh" and VoiceTyping.language_for("ggml-base.bin", "en") == "en")

	print("All frame 8l tests passed (%d phrases)" % phrases_checked)
	quit()

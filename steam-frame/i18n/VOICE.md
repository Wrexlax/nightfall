# Voice typing and voice commands in the menu's language

So that Nightfall isn't English-only: voice commands and dictation follow
the language the menu is set to. Build 8l.

## The rule

The menu's language (Advanced Settings > Language) is the voice language.
Nothing else is set anywhere.

## Speech models

- English-only models (`ggml-base.en.bin`, `ggml-small.en.bin`): what the
  installer has always fetched. Best for English.
- Multilingual models (`ggml-base.bin`, `ggml-small.bin`): same sizes
  (142 MB, 466 MB). SHA-1 from whisper.cpp's `models/README.md`:
  base `465707469ff3a37a2b9b8d8f89f2f99de7299dac`, small
  `55356645c2b361a969dfd0ef2c5a50d530afd8d5`.
- `VoiceTyping.model_choice()` picks: menu in English, an English model if
  one is installed, else a multilingual one; any other language, a
  multilingual model if one is installed, else an English one (and a notice
  says voice typing will only take English until the other is installed).
  Speech Model: Base / Small chooses the size within the kind.
- A multilingual model is told the language (`VoiceTyper.set_language`, the
  code in the pack's `whisper`); an English one is always told "en".

## Commands: a pack per language, the English engine underneath

`locale/voice/<code>.json` (a "pack"). What was said is put into the English
command vocabulary first (`VoicePacks.to_english()`), and then the two
engines that already exist run on it unchanged: `VoiceCommands` (the fixed
commands) and `VoiceMenu` (every menu button by its name). What is typed is
never touched: this is only for deciding whether a clip is a command.

1. Lower case, punctuation off (also the punctuation other scripts use).
2. Languages written without spaces (`"spaceless": true`: ja, zh): the clip
   is cut into known words, longest first, from the pack's words and the
   menu's translated names and values.
3. `drop` words go (articles, "please").
4. The whole clip is looked up in `commands` (a phrase may hold `#` for a
   whole number): "alles auswählen" -> "select all", "lautstärke 80" ->
   "volume 80".
5. Otherwise the little words are swapped: `on`, `off`, `next`, `enable`,
   `disable`, `minus`, `plus`, `to`. "rahmen aus" -> "rahmen off".
6. `VoiceMenu` knows each button by its translated name as well as its
   English one, and each value by its translated text, so "rahmen off"
   finds Bezel. Every button in the menu gets a command in every language
   without anything being written for it.

So a pack only holds what the menu does not: recenter, menu and keyboard,
head lock, volume, the sliders, the PC keys, and the words used while typing
(`typing`: clear, submit, new line, new paragraph, parentheses).

`about` holds a short description of each command for the Voice Commands
list; a PC key shows its key combination instead. `help` holds the list's
three explanations of the menu rule.

English has no pack: it is the engine's own language. English commands keep
working in every language (the model may not hear them well, though).

## Not known

Every pack is a draft by Claude, without a native speaker's review, and
none of it has been heard by a speech model: there is no model or recording
where the build is made. How well Whisper's small multilingual models hear
short commands in each language is not known either.

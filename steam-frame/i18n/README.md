# Steam Frame: draft translations (2026-11-17)

`source.json` lists the 118 English strings of the Steam Frame's menu that had
no translation in any language: button names and section titles, the menu's
tooltips, the tooltips set in code (Stream Link's and the depth model's
choices), and 14 that upstream's dictionaries carried in English. Each entry is
`[text, kind]`; a `*` after the kind marks upstream's placeholders, a `+` the
tooltips set in code.

`drafts/<language>.json` holds one translation per entry, in the same order.
They were merged into `locale/<language>.json` (new keys added; a key whose
value was still the English text replaced; upstream's real translations left
alone), and the four CJK font subsets were rebuilt with
`tools/i18n/build_cjk_fonts.py`.

**These are drafts written without a native speaker's review.** What was
checked: every tooltip fits the tooltip bar's two lines in a real `Label`
(1160 px bar, 24 px margins, size 24, word wrap) in all 20 languages, and every
character is in the font used. Not checked: wording by native speakers, and
button names on the headset.

Kept in English on purpose: option *values* that are new on the Frame (Level,
Same Spot, Layer, 3D Scene, Stream Size, Small, Base, Detail, Light and the
like) and the words voice commands listen for. Tooltips name those values in
English so they match what the button shows.

Added the same evening (entries 121 on): 43 notices and popups (kind
`notice`), the Commands option and its two tooltips, and the "Voice &
Microphone" title. Notices are checked for the same blanks (`%s`, `%d`) in
the same order and for four lines at most in the notice panel
(`test/test_frame_8b.gd`).

Still untranslated: the voice commands' confirmations, the color camera
notices, the Buttons tab, the Voice Commands list, and those option values.

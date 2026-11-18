extends SceneTree

# Steam Frame 8w: in the address field of "Connect by hand", a key takes the
# place of what is highlighted, and DEL removes it, as typing does anywhere.

class Owner extends Node3D:
	func _log(_text: String) -> void:
		pass

func _init() -> void:
	# The rule itself.
	assert(WelcomeScreen.typed("192.168.1.20", 3, [0, 3], "1", 21) == ["1.168.1.20", 1])
	assert(WelcomeScreen.typed("192.168.1.20", 12, [0, 0], "5", 21) == ["192.168.1.205", 13])
	assert(WelcomeScreen.typed("192.168.1.20", 4, [0, 0], "7", 21) == ["192.7168.1.20", 5])
	assert(WelcomeScreen.typed("192.168.1.20", 0, [4, 7], "0", 21) == ["192.0.1.20", 5])
	# Full: nothing more goes in, unless it replaces something.
	var full := "255.255.255.255:65535"
	assert(WelcomeScreen.typed(full, 21, [0, 0], "1", 21) == [full, 21])
	assert(WelcomeScreen.typed(full, 21, [16, 21], "8", 21) == ["255.255.255.255:8", 17])
	assert(WelcomeScreen.deleted("192.168.1.20", 12, [0, 0]) == ["192.168.1.2", 11])
	assert(WelcomeScreen.deleted("192.168.1.20", 0, [0, 0]) == ["192.168.1.20", 0])
	assert(WelcomeScreen.deleted("192.168.1.20", 7, [4, 7]) == ["192..1.20", 4])
	assert(WelcomeScreen.deleted("192.168.1.20", 2, [0, 12]) == ["", 0])
	_on_the_screen.call_deferred()

func _on_the_screen() -> void:
	var owner := Owner.new()
	root.add_child(owner)
	var holder := Control.new()
	root.add_child(holder)
	var welcome := WelcomeScreen.new(owner)
	welcome.build_ip_screen(holder)
	var screen: Control = holder.get_node("IPScreen")
	screen.visible = true
	var field: LineEdit = screen.find_child("IPField", true, false)
	var numpad: GridContainer = screen.find_child("IPNumpad", true, false)
	var del: Button = screen.find_child("DelBtn", true, false)
	var keys := {}
	for key in numpad.get_children():
		keys[(key as Button).text] = key
	await process_frame

	# Three digits highlighted, then keys: the first key replaces all three.
	field.text = "192.168.1.20"
	field.grab_focus()
	field.select(0, 3)
	assert(field.has_selection())
	# Pressing a key takes the focus, as the pointer's click does; the
	# highlight has to still be there for the key to act on.
	(keys["1"] as Button).grab_focus()
	assert(field.has_selection(), "the highlight is gone once a key has the focus")
	(keys["1"] as Button).pressed.emit()
	assert(field.text == "1.168.1.20" and field.caret_column == 1 and not field.has_selection(), field.text)
	(keys["0"] as Button).pressed.emit()
	assert(field.text == "10.168.1.20" and field.caret_column == 2, field.text)

	# DEL with a highlight removes just that; without, the character before.
	field.select(3, 6)
	del.grab_focus()
	del.pressed.emit()
	assert(field.text == "10..1.20" and field.caret_column == 3, field.text)
	del.pressed.emit()
	assert(field.text == "10.1.20" and field.caret_column == 2, field.text)

	# Nothing highlighted: at the caret, as before.
	field.caret_column = field.text.length()
	(keys["5"] as Button).pressed.emit()
	assert(field.text == "10.1.205")
	print("All frame 8w tests passed")
	quit()

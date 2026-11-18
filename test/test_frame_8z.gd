extends SceneTree

# Steam Frame 8z and 9a: the engine build carries the patch that leaves
# " (DEBUG)" out of the window's title (an app can't: 8z tried), and what is
# published says where the port lives.

func _init() -> void:
	# The patch is in the tree, takes the suffix out in both places, and the
	# build recipe names the engine after it.
	var patch := FileAccess.get_file_as_string("res://steam-frame/engine/0004-no-debug-suffix-in-the-title.patch")
	assert(patch.contains("main/main.cpp") and patch.contains("scene/main/window.cpp"))
	assert(patch.count("-") > 0 and patch.count("(DEBUG)\", ") == 2, "both places that add the suffix are removed")
	var recipe := FileAccess.get_file_as_string("res://steam-frame/engine/README.md")
	assert(recipe.contains("BUILD_NAME=nightfall4") and recipe.contains("0004-no-debug-suffix-in-the-title.patch"))
	assert(FrameEngine.level_of("nightfall4") == FrameEngine.PLAIN_WINDOW_TITLE)
	assert(FrameEngine.level_of("nightfall4") >= FrameEngine.BACKGROUND_OPACITY, "PT Fade still counts on the newer engine")
	# The app no longer tries to set the title itself.
	assert(not FileAccess.get_file_as_string("res://main.gd").contains("window_set_title"))

	var home := "https://github.com/Wrexlax/nightfall"
	var names := Licences.names(true)
	assert("\n".join(Licences.lines(names.find("Nightfall for Steam Frame"), true)).contains(home))
	for path in ["res://steam-frame/RELEASE-README.md", "res://steam-frame/package/README.txt"]:
		var text := FileAccess.get_file_as_string(path)
		assert(text.contains(home), "%s says where the port lives" % path)
		assert(text.contains("/issues") or text.contains("Issues page"), "%s says where to report a problem" % path)

	# No controller button starts with nothing on it, and each default is an
	# action that exists.
	for id in ButtonBindings.CONTROL_ORDER:
		var action: String = ButtonBindings.CONTROLS[id][3]
		assert(action != "none" and ButtonBindings.ACTIONS.has(action), "%s starts empty" % id)
	assert(ButtonBindings.CONTROLS["rbumper"][3] == "rclick" and ButtonBindings.CONTROLS["lbumper"][3] == "rclick")
	assert(ButtonBindings.CONTROLS["view"][3] == "menu" and ButtonBindings.CONTROLS["lstick"][3] == "ctrl")
	print("All frame 8z tests passed")
	quit()

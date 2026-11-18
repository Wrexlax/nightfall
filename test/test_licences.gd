extends SceneTree

# Every component under Settings > About > Licences must have its text.
func _init():
	var names := Licences.names()
	assert(names.size() == Licences.ENTRIES.size())
	for i in names.size():
		var lines := Licences.lines(i)
		var text := "\n".join(lines)
		assert(lines.size() > 2, "%s has no text" % names[i])
		assert(not text.contains("is missing from this build"), "%s: licence file missing" % names[i])
	var godot := "\n".join(Licences.lines(names.find("Godot components")))
	assert(godot.contains("FreeType") and godot.contains("---- FTL ----"), "Godot components need FreeType's notice and licence")
	assert("\n".join(Licences.lines(names.find("ZipDepth"))).contains("Copyright (c) 2026 Fabio Tosi"))
	# The Steam Frame build's page: only what that build contains, each with
	# its text, and the port's own entries among them.
	var frame := Licences.names(true)
	assert(frame.size() == names.size() - Licences.NOT_ON_FRAME.size())
	for hidden in Licences.NOT_ON_FRAME:
		assert(names.has(hidden), "%s is not an entry" % hidden)
		assert(not frame.has(hidden))
	for i in frame.size():
		var lines := Licences.lines(i, true)
		assert(lines.size() > 2 and not "\n".join(lines).contains("is missing from this build"), frame[i])
	for kept in ["Nightfall", "Nightfall for Steam Frame", "Moonlight XR for Frame", "whisper.cpp", "FFmpeg", "LiteRT", "ncnn", "glslang", "Godot Engine"]:
		assert(frame.has(kept), kept)
	assert("\n".join(Licences.lines(frame.find("whisper.cpp"), true)).contains("whisper.cpp 1.9.5"))
	# Credit where it belongs (8y): the depth models are Moonlight XR's, the
	# decoder and the Steam helper Moonlight XR for Frame's, and the port's
	# entry names the Godot fix its engine carries.
	assert(frame.has("Moonlight XR"))
	var xr := "\n".join(Licences.lines(frame.find("Moonlight XR"), true))
	assert(xr.contains("Sean Gilleece") and xr.contains("ZipDepth") and xr.contains("Gilleece/moonlight-android-xr"), xr.left(300))
	var xr_frame := "\n".join(Licences.lines(frame.find("Moonlight XR for Frame"), true))
	assert(xr_frame.contains("decoder") and xr_frame.contains("Steam library") and not xr_frame.contains("depth models"), xr_frame.left(300))
	assert("\n".join(Licences.lines(frame.find("Nightfall for Steam Frame"), true)).contains("124811"))
	print("All licences tests passed")
	quit()

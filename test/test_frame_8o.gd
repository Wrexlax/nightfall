extends SceneTree

# Steam Frame 8o: Stream Link with the original Meteor's multipath (0.9.1 on),
# which has no list of fixes to say so in and takes only plain pings.

const PC := "192.0.2.10"

func _meteor(version: String, fixes = null) -> Dictionary:
	var meteor := {"service": "nightfall-meteor", "version": version, "key": "k"}
	if fixes != null:
		meteor["fixes"] = fixes
	return meteor

func _init() -> void:
	# Versions as Meteor writes them.
	assert(StreamManager.version_at_least("0.9.1-preview.2", [0, 9, 1]))
	assert(StreamManager.version_at_least("0.9.1", [0, 9, 1]))
	assert(StreamManager.version_at_least("0.10.0", [0, 9, 1]))
	assert(StreamManager.version_at_least("1.0", [0, 9, 1]))
	assert(not StreamManager.version_at_least("0.9.0", [0, 9, 1]))
	assert(not StreamManager.version_at_least("0.9.0-sf15", [0, 9, 1]))
	assert(not StreamManager.version_at_least("", [0, 9, 1]))

	# The original Meteor: nothing before 0.9.1, plain pings from then on.
	assert(not StreamManager.offers_second_link(_meteor("0.9.0"), PC))
	for version in ["0.9.1-preview.2", "0.9.1", "0.9.2", "0.10.0"]:
		assert(StreamManager.offers_second_link(_meteor(version), PC), version)
		assert(StreamManager.speaks_plain_second_link(_meteor(version)), version)
		# What it doesn't know stays off: these go by the list alone.
		assert(not StreamManager.offers_media_keys(_meteor(version), PC), version)

	# This port's Meteor says what it can do, and is never taken for plain.
	var ours := ["quiet-flows", "mic-stereo", "second-link", "second-link-only", "link-sync"]
	assert(StreamManager.offers_second_link(_meteor("0.9.0-sf15", ours), PC))
	assert(not StreamManager.speaks_plain_second_link(_meteor("0.9.0-sf15", ours)))
	assert(not StreamManager.speaks_plain_second_link(_meteor("0.9.1-sf1", ours)))
	assert(StreamManager.offers_second_link(_meteor("0.9.1-sf1", ours), PC))
	# This port's Meteor from before Stream Link (sf1, sf2).
	assert(not StreamManager.offers_second_link(_meteor("0.9.0-sf2", ["quiet-flows", "mic-stereo"]), PC))

	# Sound through Meteor: the original has the quiet-flows fix from 0.9.1,
	# so its sound goes through Meteor (and with that over both links); 0.9.0
	# keeps the way around it.
	assert(not StreamManager.keeps_quiet_flows(_meteor("0.9.0")))
	assert(StreamManager.keeps_quiet_flows(_meteor("0.9.1-preview.2")))
	assert(StreamManager.keeps_quiet_flows(_meteor("0.9.0-sf15", ours)))
	assert(not StreamManager.keeps_quiet_flows(_meteor("0.1.1")))
	assert(StreamManager.keeps_quiet_flows(_meteor("0.1.3")))
	assert(not StreamManager.keeps_quiet_flows({}))

	# A stream that doesn't pass through Meteor has no address for it.
	assert(not StreamManager.offers_second_link(_meteor("0.9.1"), ""))
	assert(not StreamManager.offers_second_link({}, PC))

	# The link's setup sends plain pings to a Meteor that can't be asked for
	# the adapter alone: the library's choice -1 (0004-second-link.patch,
	# secondLinkPing: nothing appended). Read here so that a change to that
	# line is seen.
	var main_source := FileAccess.get_file_as_string("res://main.gd")
	assert(main_source.contains("set_second_link_choice((1 if alone else 0) if stream_manager.meteor_offers_second_link_only() else -1, -1)"))

	print("test_frame_8o passed")
	quit()

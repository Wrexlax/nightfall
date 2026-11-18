extends SceneTree

# Steam Frame 6s: the server list names each saved PC, lets one be renamed or
# removed on its own, and keeps separate settings for two hosts at one address.

const SUNSHINE := {"id": 1, "hostname": "GAMING-PC", "name": "", "localaddress": "192.168.1.50",
	"usb_address": "", "https_port": 47984, "http_port": 47989, "server_unique_id": "AAAA"}
const BUILT_IN := {"id": 2, "hostname": "GAMING-PC (Nightfall)", "name": "", "localaddress": "192.168.1.50",
	"usb_address": "", "https_port": 49984, "http_port": 49989, "server_unique_id": "BBBB"}
# Paired before the PC's own name was kept: "hostname" is just the address.
const OLDER := {"id": 3, "hostname": "10.0.0.5", "name": "", "localaddress": "10.0.0.5",
	"usb_address": "fe80::1%usb0", "https_port": 47984, "http_port": 47989, "server_unique_id": ""}

func _named(host: Dictionary, name: String) -> Dictionary:
	var copy := host.duplicate()
	copy["name"] = name
	return copy

func _names() -> void:
	# The PC's own name, with its address underneath.
	assert(SavedHosts.title(SUNSHINE) == "GAMING-PC")
	assert(SavedHosts.detail(SUNSHINE) == "192.168.1.50:47989")  # the standard port is shown too (6z)
	# A host on another port, likewise.
	assert(SavedHosts.title(BUILT_IN) == "GAMING-PC (Nightfall)")
	assert(SavedHosts.detail(BUILT_IN) == "192.168.1.50:49989")
	# The user's own name goes first; the PC's name moves to the line under it.
	var den := _named(SUNSHINE, "Den")
	assert(SavedHosts.title(den) == "Den")
	assert(SavedHosts.detail(den) == "GAMING-PC" + SavedHosts.SEPARATOR + "192.168.1.50:47989")
	assert(SavedHosts.described(den) == SavedHosts.described(SUNSHINE))
	# Nothing but an address: it is the title, and there is no second line.
	assert(SavedHosts.title(OLDER) == "10.0.0.5:47989")
	assert(SavedHosts.detail(OLDER) == "")
	# A name the same as the PC's doesn't show it twice.
	assert(SavedHosts.detail(_named(SUNSHINE, "GAMING-PC")) == "192.168.1.50:47989")

func _clean() -> void:
	assert(SavedHosts.clean_name("  Living   Room PC ") == "Living Room PC")
	assert(SavedHosts.clean_name("   ") == "")
	assert(SavedHosts.clean_name("A".repeat(40)).length() == SavedHosts.NAME_MAX)
	# A cut that lands after a space doesn't leave the space.
	assert(SavedHosts.clean_name("A".repeat(SavedHosts.NAME_MAX - 1) + " B") == "A".repeat(SavedHosts.NAME_MAX - 1))

func _which() -> void:
	var hosts := [SUNSHINE, BUILT_IN, OLDER]
	# Two hosts at one address: the one picked in the list, else the first.
	assert(SavedHosts.pick(hosts, -1, "192.168.1.50").id == 1)
	assert(SavedHosts.pick(hosts, 2, "192.168.1.50").id == 2)
	assert(SavedHosts.pick(hosts, 3, "192.168.1.50").id == 1)
	assert(SavedHosts.pick(hosts, -1, "192.168.1.99").is_empty())
	# Over USB Link, with or without the interface on the end.
	assert(SavedHosts.pick(hosts, -1, "FE80::1").id == 3)
	assert(SavedHosts.pick(hosts, -1, "fe80::1%usb1").id == 3)
	# The same record after the list was renumbered.
	var renumbered := BUILT_IN.duplicate()
	renumbered["id"] = 1
	assert(SavedHosts.same(BUILT_IN, renumbered))
	assert(not SavedHosts.same(SUNSHINE, BUILT_IN))
	assert(SavedHosts.find([renumbered, OLDER], BUILT_IN).id == 1)
	assert(SavedHosts.find([renumbered, OLDER], SUNSHINE).is_empty())
	# Records without an id of their own go by address and port.
	assert(SavedHosts.same(OLDER, OLDER.duplicate()))
	assert(not SavedHosts.same(OLDER, SUNSHINE))
	assert(not SavedHosts.same({}, {}))
	assert(SavedHosts.by_id(hosts, 2) == BUILT_IN)
	assert(SavedHosts.by_id(hosts, 9).is_empty())

func _sections() -> void:
	# Each paired PC host has its own, whatever was typed to reach it.
	assert(SavedHosts.settings_section(SUNSHINE, "192.168.1.50") == "pc:AAAA")
	assert(SavedHosts.settings_section(BUILT_IN, "192.168.1.50") == "pc:BBBB")
	assert(SavedHosts.settings_section(BUILT_IN, "192.168.1.50:49989") == "pc:BBBB")
	# Not paired yet, or a record without an id: the address as typed, as before.
	assert(SavedHosts.settings_section({}, "192.168.1.60:50000") == "192.168.1.60:50000")
	assert(SavedHosts.settings_section(OLDER, "10.0.0.5") == "10.0.0.5")
	# Where the settings were before: both hosts start from the shared ones.
	assert(SavedHosts.older_sections(BUILT_IN, "192.168.1.50") == PackedStringArray(["192.168.1.50"]))
	assert(SavedHosts.older_sections(BUILT_IN, "192.168.1.50:49989") == PackedStringArray(["192.168.1.50:49989", "192.168.1.50"]))
	assert(SavedHosts.older_sections({}, "192.168.1.60") == PackedStringArray(["192.168.1.60"]))

# The store itself (native): a name is kept with its record, follows it when
# the list is renumbered, and is there for a new pairing of the same server.
func _store() -> void:
	var store = ClassDB.instantiate("NightfallConfigManager")
	store.config_path = "user://test_6s_hosts.ini"
	store.clear_hosts()
	for host in [SUNSHINE, BUILT_IN]:
		var record: Dictionary = host.duplicate()
		record.erase("name")
		record["uuid"] = "u"
		store.add_host(record)
	assert(store.get_hosts().size() == 2)
	assert(store.get_hosts()[0].name == "" and store.get_hosts()[1].name == "")
	store.update_host(2, {"name": "Den"})
	assert(store.get_hosts()[1].name == "Den")
	assert(store.get_hosts()[1].hostname == "GAMING-PC (Nightfall)")
	assert(store.get_host_name("BBBB") == "Den")
	assert(store.get_host_name("AAAA") == "" and store.get_host_name("") == "")
	# Removing the first: the second becomes number 1 and keeps its name.
	store.remove_host(1)
	var left: Array = store.get_hosts()
	assert(left.size() == 1 and left[0].id == 1)
	assert(left[0].name == "Den" and left[0].server_unique_id == "BBBB")
	# Giving the name up.
	store.update_host(1, {"name": ""})
	assert(store.get_hosts()[0].name == "")
	store.clear_hosts()

func _init() -> void:
	_names()
	_clean()
	_which()
	_sections()
	_store()
	print("All frame_6s tests passed")
	quit(0)

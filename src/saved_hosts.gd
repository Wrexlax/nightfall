class_name SavedHosts
extends RefCounted

## The paired PCs in the server list: what each one is called, which saved
## settings belong to it, and how to find one again after the list changed.
##
## A record (NightfallConfigManager.get_hosts()) carries two names: "hostname",
## the name the PC gives itself (its address in records paired before that was
## kept), and "name", the user's own name for the connection.
##
## One PC can run two hosts at one address on different ports (Sunshine next
## to Meteor's built-in host, say), so an address alone doesn't say which
## record is meant; the id the server reports for itself does.

const NAME_MAX := 24

## A typed name as it is saved: no stray spaces, never longer than NAME_MAX.
static func clean_name(text: String) -> String:
	var words := text.split(" ", false)
	return " ".join(words).left(NAME_MAX).strip_edges()

## Where the PC is: the address as it would be typed to pair with it.
static func address(host: Dictionary) -> String:
	return WelcomeScreen.pair_address(str(host.get("localaddress", "")), int(host.get("http_port", 47989)))

## The same for showing in the list, always with the port: two hosts on one PC
## differ only there, and a list that hides the standard port (47989) makes
## Sunshine's row look as if its port had been lost.
static func shown_address(host: Dictionary) -> String:
	var ip := str(host.get("localaddress", ""))
	if ip.is_empty():
		return ""
	var port := int(host.get("http_port", 47989))
	return ("[%s]:%d" if ip.contains(":") else "%s:%d") % [ip, port]

## The name the PC gives itself; empty when the record only holds its address.
static func pc_name(host: Dictionary) -> String:
	var hostname := str(host.get("hostname", ""))
	return "" if hostname == str(host.get("localaddress", "")) else hostname

## What the PC is called in the list: the user's name for it, else its own
## name, else its address.
static func title(host: Dictionary) -> String:
	var own := str(host.get("name", ""))
	if not own.is_empty():
		return own
	var pc := pc_name(host)
	return pc if not pc.is_empty() else shown_address(host)

const SEPARATOR := "  ·  "

## What identifies the PC whatever the user calls it: its own name and its
## address.
static func described(host: Dictionary) -> String:
	var parts := PackedStringArray()
	for part in [pc_name(host), shown_address(host)]:
		if not part.is_empty():
			parts.append(part)
	return SEPARATOR.join(parts)

## The smaller line under the title: whatever the title leaves out.
static func detail(host: Dictionary) -> String:
	var parts := described(host).split(SEPARATOR, false)
	var shown := parts.find(title(host))
	if shown >= 0:
		parts.remove_at(shown)
	return SEPARATOR.join(parts)

## Whether two records are the same PC host, whatever their place in the list
## (removing a record renumbers the ones after it).
static func same(a: Dictionary, b: Dictionary) -> bool:
	if a.is_empty() or b.is_empty():
		return false
	var id_a := str(a.get("server_unique_id", ""))
	var id_b := str(b.get("server_unique_id", ""))
	if not id_a.is_empty() or not id_b.is_empty():
		return id_a == id_b
	return str(a.get("localaddress", "")) == str(b.get("localaddress", "")) \
		and int(a.get("https_port", 0)) == int(b.get("https_port", 0))

## The record in `hosts` for the same PC host as `like`; empty when it's gone.
static func find(hosts: Array, like: Dictionary) -> Dictionary:
	for h in hosts:
		if same(h, like):
			return h
	return {}

static func by_id(hosts: Array, id: int) -> Dictionary:
	for h in hosts:
		if int(h.get("id", -1)) == id:
			return h
	return {}

## USB Link addresses carry a "%<interface>" zone that older records lack; it
## never tells two machines apart.
static func same_address(a: String, b: String) -> bool:
	return a.get_slice("%", 0).to_lower() == b.get_slice("%", 0).to_lower()

## A saved PC is reached at its network address and, once seen over USB Link,
## at its USB address too.
static func reached_at(host: Dictionary, addr: String) -> bool:
	for key in ["localaddress", "usb_address"]:
		var a := str(host.get(key, ""))
		if not a.is_empty() and same_address(a, addr):
			return true
	return false

## The saved PC an address means: of the records at that address, the one
## picked in the server list (`current_id`), else the first. Empty when
## nothing is saved there.
static func pick(hosts: Array, current_id: int, addr: String) -> Dictionary:
	var picked := {}
	for h in hosts:
		if reached_at(h, addr) and (picked.is_empty() or int(h.get("id", -1)) == current_id):
			picked = h
	return picked

## The part of host_state.cfg that holds a PC's stream settings and screen
## layout. A paired PC's goes by the id it reports, so two hosts at one
## address keep their own, and a PC keeps its settings when its address
## changes. Until a PC is paired there is only the address as typed.
static func settings_section(host: Dictionary, typed_address: String) -> String:
	var unique_id := str(host.get("server_unique_id", ""))
	return typed_address if unique_id.is_empty() else "pc:" + unique_id

## Where settings were filed before each paired PC had its own section: under
## the address as typed, which for a paired PC was its bare address.
static func older_sections(host: Dictionary, typed_address: String) -> PackedStringArray:
	var sections := PackedStringArray([typed_address])
	var bare := str(host.get("localaddress", ""))
	if not bare.is_empty() and bare != typed_address:
		sections.append(bare)
	return sections

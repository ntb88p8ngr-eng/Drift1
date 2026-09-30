extends Node
## Address handling for online play (IPv4 and IPv6): parsing what players type, the invite code,
## which IPv4 is usable for the code (no private / provider-NAT addresses), IPv6 /64 prefixes.
## Run: godot --headless --path . res://tests/address_test.tscn


func _ready() -> void:
	var fails := 0
	var cases := [
		["[2001:db8::1]:7777", ["2001:db8::1", 7777]],
		["2001:db8::1", ["2001:db8::1", 24590]],
		["1.2.3.4:9000", ["1.2.3.4", 9000]],
		[" 1.2.3.4 ", ["1.2.3.4", 24590]],
		["[2001:db8::1]", ["2001:db8::1", 24590]],
	]
	for c in cases:
		var got: Array = Net.split_address(c[0], 24590)
		if got != c[1]:
			print("FAIL split %s -> %s" % [c[0], got]); fails += 1
	if Net._prefix64("2001:db8:0:5::abcd") != "2001:0db8:0000:0005" or Net._prefix64("2001:db8::5:1:2:3") != "2001:0db8:0000:0000":
		print("FAIL prefix64 %s %s" % [Net._prefix64("2001:db8:0:5::abcd"), Net._prefix64("2001:db8::5:1:2:3")]); fails += 1
	for ip in ["100.72.3.4", "192.168.1.2", "10.0.0.1", "172.20.1.1", "2001::1"]:
		if Net.is_public_ipv4(ip):
			print("FAIL %s counted as public IPv4" % ip); fails += 1
	if not Net.is_public_ipv4("85.10.3.4"):
		print("FAIL 85.10.3.4 not public"); fails += 1
	# an invite code with an IPv6 address survives the round trip
	Game.persist = false
	var err := Net.host_lobby("T", 24633, 4, false, "pw")
	Net.public_ip = "2001:db8:1:2::abcd"
	var inv := Net.parse_invite(Net.invite_code())
	if err != "" or inv.get("ip", "") != "2001:db8:1:2::abcd" or int(inv.get("port", 0)) != 24633:
		print("FAIL invite round trip: %s %s" % [err, inv]); fails += 1
	Net.leave()
	# short codes
	const RV = preload("res://scripts/autoload/rendezvous.gd")
	var c := RV.make_code()
	if RV.normalize(RV.pretty(c).to_lower()) != c or RV.normalize("K7Q-M2") != "" or RV.normalize("K7Q-M2O") != "":
		print("FAIL short code normalize: %s" % c); fails += 1
	# relay messages: sealed with the code's key, tampering is rejected, another code can't read them
	var rv = RV.new()
	rv.code = c
	rv._key = ("md1|key|" + c).sha256_buffer()
	rv._mac_key = ("md1|mac|" + c).sha256_buffer()
	var sealed: String = rv._seal({"t": "join", "c": [["2001:db8::5", 4000]]})
	var back: Dictionary = rv._open(sealed)
	if str(back.get("t", "")) != "join" or sealed.contains("2001"):
		print("FAIL seal/open: %s" % back); fails += 1
	var raw := Marshalls.base64_to_raw(sealed)
	raw[raw.size() - 1] ^= 1
	if not rv._open(Marshalls.raw_to_base64(raw)).is_empty():
		print("FAIL tampered message accepted"); fails += 1
	var other = RV.new()
	other._key = ("md1|key|AAAAAA").sha256_buffer()
	other._mac_key = ("md1|mac|AAAAAA").sha256_buffer()
	if not other._open(sealed).is_empty():
		print("FAIL other code could read the message"); fails += 1
	rv.free()
	other.free()
	# STUN: XOR-MAPPED-ADDRESS for IPv4 85.10.3.4:51000 and IPv6 2001:db8::5:51000
	var tx := PackedByteArray([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12])
	var ck := PackedByteArray([0x21, 0x12, 0xA4, 0x42])
	var r4 := PackedByteArray([0x01, 0x01, 0x00, 0x0C, 0x21, 0x12, 0xA4, 0x42])
	r4.append_array(tx)
	var xp := 51000 ^ 0x2112
	r4.append_array(PackedByteArray([0x00, 0x20, 0x00, 0x08, 0x00, 0x01, xp >> 8, xp & 255,
		85 ^ ck[0], 10 ^ ck[1], 3 ^ ck[2], 4 ^ ck[3]]))
	var got4: Array = RV.parse_stun(r4, {tx.hex_encode(): tx})
	var r6 := PackedByteArray([0x01, 0x01, 0x00, 0x18, 0x21, 0x12, 0xA4, 0x42])
	r6.append_array(tx)
	r6.append_array(PackedByteArray([0x00, 0x20, 0x00, 0x14, 0x00, 0x02, xp >> 8, xp & 255]))
	var a6 := PackedByteArray([0x20, 0x01, 0x0d, 0xb8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 5])
	var m6 := ck.duplicate()
	m6.append_array(tx)
	for k in 16:
		r6.append(a6[k] ^ m6[k])
	var got6: Array = RV.parse_stun(r6, {tx.hex_encode(): tx})
	if got4 != ["85.10.3.4", 51000] or got6.size() != 2 or Net.expand_ipv6(str(got6[0])) != Net.expand_ipv6("2001:db8::5") or int(got6[1]) != 51000:
		print("FAIL STUN parse: %s %s" % [got4, got6]); fails += 1
	print("ADDRESS TEST: %s" % ("PASS" if fails == 0 else "FAIL"))
	get_tree().quit(1 if fails else 0)

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
	print("ADDRESS TEST: %s" % ("PASS" if fails == 0 else "FAIL"))
	get_tree().quit(1 if fails else 0)

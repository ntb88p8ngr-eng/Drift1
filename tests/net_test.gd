extends Node
## Two-process check of the encrypted, password-protected lobby.
## Host:   godot --headless --path . res://tests/net_test.tscn -- --role=host --pw=geheim
## Client: godot --headless --path . res://tests/net_test.tscn -- --role=client --pw=geheim



func _ready() -> void:
	Game.persist = false
	var args := {"role": "host", "pw": "", "port": "24590"}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and a.contains("="):
			var kv := a.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1]
	get_tree().create_timer(14.0).timeout.connect(func():
		print("NET TIMEOUT players=%d" % Net.players.size())
		get_tree().quit(2))
	if args["role"] == "host":
		var err := Net.host_lobby("Test", int(args["port"]), 4, false, args["pw"])
		print("NET HOST ", "ok" if err == "" else err)
		Net.public_ip = "127.0.0.1"
		var code := Net.invite_code()
		print("NET INVITE %d chars -> %s" % [code.length(), str(Net.parse_invite(code)).substr(0, 60)])
		var f := FileAccess.open("user://net_test_invite_%s.txt" % args["port"], FileAccess.WRITE)
		f.store_string(code)
		f.close()
		Net.lobby_changed.connect(func():
			if Net.players.size() >= 2:
				print("NET HOST SEES PLAYER ", Net.players[Net.players.keys().filter(func(k): return k != 1)[0]].get("name", "?"))
				await get_tree().create_timer(2.0).timeout
				get_tree().quit(0))
		Net.graffiti_claimed.connect(func(owner_id: int, cells: PackedInt32Array):
			print("NET HOST GRAFFITI from %s: %s" % ["client" if owner_id != 1 else "host", cells]))
	else:
		Net.connected_ok.connect(func(): print("NET CLIENT AUTHENTICATED"))
		Net.connection_failed.connect(func(r):
			print("NET CLIENT FAILED: ", r)
			get_tree().quit(1))
		Net.lobby_changed.connect(func():
			if Net.players.size() >= 2:
				print("NET CLIENT IN LOBBY ", Net.lobby.get("name", ""))
				Net.send_graffiti(PackedInt32Array([3, 4, 5]))
				await get_tree().create_timer(1.0).timeout
				get_tree().quit(0))
		Net.graffiti_claimed.connect(func(owner_id: int, cells: PackedInt32Array):
			print("NET CLIENT GRAFFITI ECHO owner=%d %s" % [owner_id, cells]))
		var cf := FileAccess.open("user://net_test_invite_%s.txt" % args["port"], FileAccess.READ)
		var code := cf.get_as_text() if cf else ""
		var inv := Net.parse_invite(code)
		# the right password comes with the invite; otherwise the same lobby with a wrong one
		var err := Net.join_invite(code) if args["pw"] == "geheim" else Net.join_lobby(inv["ip"], inv["port"], args["pw"], inv["cert"])
		print("NET JOIN ", "ok" if err == "" else err)

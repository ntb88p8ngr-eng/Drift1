extends Node
## Two-process check of the encrypted, password-protected lobby.
## Host:   godot --headless --path . res://tests/net_test.tscn -- --role=host --pw=geheim
## Client: godot --headless --path . res://tests/net_test.tscn -- --role=client --pw=geheim



func _ready() -> void:
	Game.persist = false
	var args := {"role": "host", "pw": "", "port": "24590", "ip": "127.0.0.1"}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and a.contains("="):
			var kv := a.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1]
	get_tree().create_timer(50.0 if args.has("stall") else 30.0).timeout.connect(func():
		print("NET TIMEOUT players=%d" % Net.players.size())
		get_tree().quit(2))
	if args["role"] == "host":
		var err := Net.host_lobby("Test", int(args["port"]), 4, false, args["pw"])
		print("NET HOST ", "ok" if err == "" else err)
		Net.public_ip = args["ip"]   # --ip=::1 checks IPv6
		var code := Net.invite_code()
		print("NET INVITE %d chars -> %s" % [code.length(), str(Net.parse_invite(code)).substr(0, 60)])
		var f := FileAccess.open("user://net_test_invite_%s.txt" % args["port"], FileAccess.WRITE)
		f.store_string(code)
		f.close()
		# short code (MD_SIGNAL=file: the relay is a folder, see rendezvous.gd)
		var fc := FileAccess.open("user://net_test_code_%s.txt" % args["port"], FileAccess.WRITE)
		fc.store_string(Net.host_code)
		fc.close()
		print("NET SHORT CODE ", Net.host_code)
		Net.lobby_changed.connect(func():
			if Net.players.size() >= 2:
				print("NET HOST SEES PLAYER ", Net.players[Net.players.keys().filter(func(k): return k != 1)[0]].get("name", "?"))
				if args.has("host_stall"):
					# the host loads the map as well: blocked for seconds while the client waits
					await get_tree().create_timer(1.5).timeout
					OS.delay_msec(int(args["host_stall"]))
					var t1 := Time.get_ticks_msec()
					while Time.get_ticks_msec() - t1 < int(args["host_stall"]):
						OS.delay_msec(20)
						Game.load_tick()
				await get_tree().create_timer(25.0 if args.has("stall") else 2.0).timeout
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
				if args.has("stall"):
					# loading a big map: one frame blocked for seconds (shader compile), then
					# load_tick-paced work – the connection must survive both
					var ms := int(args["stall"])
					OS.delay_msec(ms)
					var t0 := Time.get_ticks_msec()
					while Time.get_ticks_msec() - t0 < ms:
						OS.delay_msec(20)
						Game.load_tick()
					await get_tree().create_timer(float(args.get("after", "2"))).timeout
					var alive: bool = Net.peer != null and Net.peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED and Net.players.size() >= 2
					print("NET CLIENT AFTER %d ms STALL: %s" % [ms * 2, "CONNECTED" if alive else "DISCONNECTED"])
					get_tree().quit(0 if alive else 1)
					return
				get_tree().quit(0))
		Net.graffiti_claimed.connect(func(owner_id: int, cells: PackedInt32Array):
			print("NET CLIENT GRAFFITI ECHO owner=%d %s" % [owner_id, cells]))
		if args.get("mode", "") == "code":
			var sc := FileAccess.get_file_as_string("user://net_test_code_%s.txt" % args["port"])
			Net.join_status.connect(func(t): print("NET STATUS ", t))
			var e2 := Net.join_code(sc, args["pw"])
			print("NET JOIN CODE ", sc, " ", "ok" if e2 == "" else e2)
			return
		var cf := FileAccess.open("user://net_test_invite_%s.txt" % args["port"], FileAccess.READ)
		var code := cf.get_as_text() if cf else ""
		var inv := Net.parse_invite(code)
		# the right password comes with the invite; otherwise the same lobby with a wrong one
		var err := Net.join_invite(code) if args["pw"] == "geheim" else Net.join_lobby(inv["ip"], inv["port"], args["pw"], inv["cert"])
		print("NET JOIN ", "ok" if err == "" else err)

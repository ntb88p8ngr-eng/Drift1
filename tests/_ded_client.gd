extends Node
var phase := "scan"
var t := 0.0
func _ready() -> void:
	Game.persist = false
	Net.start_lan_scan()
	Net.race_start_requested.connect(func(cfg):
		print("CLIENT: race start, track ", cfg.get("track"), ", players ", (cfg.get("players", {}) as Dictionary).size())
		phase = "race"
		Net.notify_loaded())
	Net.countdown_requested.connect(func():
		print("CLIENT: countdown")
		await get_tree().create_timer(1.0).timeout
		Net.report_result({"time": 61.5, "best_lap": 61.5, "drift": 0.0, "finished": true}))
	Net.return_to_lobby_requested.connect(func():
		print("CLIENT: back in lobby, next track ", Net.lobby.get("track"))
		print("DEDICATED TEST: PASS")
		get_tree().quit(0))
	Net.lobby_changed.connect(func(): if phase == "joined" and not Net.players.is_empty(): print("CLIENT: lobby ", Net.lobby.get("name"), " dedicated ", Net.lobby.get("dedicated"), " players ", Net.players.size()); phase = "ready"; Net.set_ready(true))
func _process(delta: float) -> void:
	t += delta
	if t > 80.0:
		print("DEDICATED TEST: FAIL (timeout in phase %s)" % phase)
		get_tree().quit(1)
	if phase == "scan" and not Net.lan_lobbies.is_empty():
		var key: String = Net.lan_lobbies.keys()[0]
		var info: Dictionary = Net.lan_lobbies[key]
		print("CLIENT: found ", info.get("name"), " at ", key)
		var err := Net.join_lobby("127.0.0.1", int(info["port"]), "", str(info["cert"]))
		print("CLIENT: join ", err)
		phase = "joined"

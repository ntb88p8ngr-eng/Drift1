extends Node
## Race bots from the menu settings: 7 opponents must spawn – also with party mode switched on (it used
## to drop them all). During a party minigame they wait hidden and without collision where they were,
## afterwards they race on from there.
## Run: godot --headless --path . res://tests/bots_party_test.tscn

const World = preload("res://scripts/world/world.gd")
const MainScript = preload("res://scripts/main.gd")

var fails := 0


func _fail(msg: String) -> void:
	print("FAIL: " + msg)
	fails += 1


func _ready() -> void:
	Game.persist = false
	Game.settings["mode"] = "race"
	Game.settings["bots"] = 7
	Game.settings["bot_level"] = 2
	Game.settings["party"] = true
	Game.settings["party_coins"] = 3
	# the setting stays on for the Grüne Hölle (no party there) – bots must come anyway
	Game.settings["track"] = "gruene_hoelle"
	var cfg_gh: Dictionary = MainScript.offline_config()
	print("config Grüne Hölle + party: %d bots" % cfg_gh.get("bots", []).size())
	if cfg_gh.get("bots", []).size() != 7:
		_fail("7 bots selected, %d in the config (Grüne Hölle, party on)" % cfg_gh.get("bots", []).size())
	Game.settings["track"] = "playground"
	var cfg: Dictionary = MainScript.offline_config()
	cfg["weather"] = "dry"
	cfg["time_of_day"] = "day"
	cfg["day_cycle"] = 0
	var world := World.new()
	world.setup(cfg)
	add_child(world)
	if not world.is_loaded:
		await world.loaded
	var n_bots: int = world.race_ai.bots.size() if world.race_ai else 0
	print("playground + party: %d bots, party %s" % [n_bots, world.party != null])
	if n_bots != 7 or world.party == null:
		_fail("expected 7 bots and party mode")
		print("BOTS PARTY TEST: FAIL")
		get_tree().quit(1)
		return
	# start the race and let the bots drive a bit
	world.state = "running"
	world.local_car.controls_locked = false
	for f in 360:
		await get_tree().physics_frame
	var party = world.party
	var b0: Dictionary = world.race_ai.bots[0]
	var bc = b0["car"]
	var p_before: Vector3 = bc.global_position
	# a minigame starts (as if the player had collected a coin)
	party._stop_race({"by": 1})
	party.state = "choose"
	for f in 30:
		await get_tree().physics_frame
	var hidden := true
	for b in world.race_ai.bots:
		var c = b["car"]
		if c.visible or c.collision_layer != 0 or not c.freeze:
			hidden = false
	var drift: float = bc.global_position.distance_to(p_before)
	print("minigame: bots hidden/frozen %s, bot moved %.1f m since the stop" % [hidden, drift])
	if not hidden:
		_fail("the bots are still on the track during the minigame")
	var parked: Vector3 = bc.global_position
	for f in 240:
		await get_tree().physics_frame
	if bc.global_position.distance_to(parked) > 0.05:
		_fail("a parked bot moved (%.2f m)" % bc.global_position.distance_to(parked))
	# back to the race
	party.state = "idle"
	for f in 360:
		await get_tree().physics_frame
	var back := true
	for b in world.race_ai.bots:
		var c = b["car"]
		if not c.visible or c.collision_layer == 0 or c.freeze:
			back = false
	var moved: float = bc.global_position.distance_to(parked)
	print("after the minigame: bots back %s, bot drove %.0f m in 3 s" % [back, moved])
	if not back or moved < 10.0:
		_fail("the bots do not race on after the minigame")
	print("BOTS PARTY TEST: %s" % ("PASS" if fails == 0 else "FAIL"))
	get_tree().quit(1 if fails else 0)

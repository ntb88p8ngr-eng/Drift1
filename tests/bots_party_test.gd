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
	# an online player's car (big random peer id) must not be taken for a bot
	var other = world._make_car({"car": "r34", "paint": "blue", "name": "Mitspieler"}, true)
	other.peer_id = 1068007697
	world.cars[1068007697] = other
	other.place(world.track.grid_transform(9))
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
	print("online player during the minigame: visible %s, collision layer %d" % [other.visible, other.collision_layer])
	if not other.visible or other.collision_layer == 0:
		_fail("an online player was hidden / lost its collision")
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
	# choosing a minigame with the gamepad: the first game is focused, d-pad down + (A) picks the 2nd
	party.state = "idle"
	party._picked = false
	party._on_choose({"by": 1, "i": 0})
	for f in 4:
		await get_tree().process_frame
	var foc = get_viewport().gui_get_focus_owner()
	for jb: JoyButton in [JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_A]:
		for pressed in [true, false]:
			var ev := InputEventJoypadButton.new()
			ev.button_index = jb
			ev.pressed = pressed
			Input.parse_input_event(ev)
			await get_tree().process_frame
			await get_tree().process_frame
	var avail: Array = party._available_games()
	print("gamepad pick: first focus %s, picked %s, shown %s" % [foc.text if foc else "nothing", party._picked, party._b_game.text])
	if foc == null or not party._picked or party._b_game.text != str(party.GAMES[avail[1]]["name"]):
		_fail("the minigame cannot be chosen with the gamepad")
	var has_x := false
	for e in InputMap.action_get_events("fire"):
		if e is InputEventJoypadButton and (e as InputEventJoypadButton).button_index == JOY_BUTTON_X:
			has_x = true
	if not has_x:
		_fail("no gamepad fire button")
	print("BOTS PARTY TEST: %s" % ("PASS" if fails == 0 else "FAIL"))
	get_tree().quit(1 if fails else 0)

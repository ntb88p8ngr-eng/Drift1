extends Node
## Minigames can't be won beside the course: in the offroad parkour and red light / green light a
## car driven (carried) along the verge beyond the barrier is put back – parkour to its last
## checkpoint, never over the finish line; a car steered into the side barrier stays on the course.
## Run: godot --headless --path . res://tests/party_cheat_test.tscn [PC_TRACK=utah]

const World = preload("res://scripts/world/world.gd")
const MainScript = preload("res://scripts/main.gd")

var fails := 0


func _fail(msg: String) -> void:
	print("FAIL: " + msg)
	fails += 1


func _ready() -> void:
	Game.persist = false
	Game.settings["mode"] = "free"
	Game.settings["party"] = true
	Game.settings["party_coins"] = 3
	Game.settings["track"] = OS.get_environment("PC_TRACK") if OS.get_environment("PC_TRACK") != "" else "utah"
	var cfg: Dictionary = MainScript.offline_config()
	cfg["weather"] = "dry"
	cfg["time_of_day"] = "day"
	cfg["day_cycle"] = 0
	var world := World.new()
	world.setup(cfg)
	add_child(world)
	if not world.is_loaded:
		await world.loaded
	world.state = "running"
	world.local_car.controls_locked = false
	for f in 30:
		await get_tree().physics_frame
	var party = world.party
	var sites = party.sites
	var hz := float(Engine.physics_ticks_per_second)
	var car = world.local_car
	for gid in ["parkour", "rlgl"]:
		var g := -1
		for k in party.GAMES.size():
			if party.GAMES[k]["id"] == gid:
				g = k
		party.state = "idle"
		party._on_start({"t": "start", "i": -1, "g": g, "s": 77, "by": 1, "ids": [1]})
		while party.state != "play":
			await get_tree().physics_frame
		var len: float = sites.sites[gid]["len"]
		# 1) carried along the verge, 5 m beyond the barrier, to past the finish
		var resets := 0
		var a := 5.0
		var max_along := -1e9
		while a < len + 10.0 and not party._done:
			a += 18.0 / hz
			var lat: float = sites.edge_at(gid, a) + sites.SIDE_WALL + 5.0
			car.global_transform = sites.course_xf(gid, a, lat, 0.6)
			car.linear_velocity = Vector3.ZERO
			await get_tree().physics_frame
			var pa: float = sites.progress(gid, car.global_position)
			max_along = maxf(max_along, pa)
			if absf(float(world.track.project(car.global_position)[2])) < float(sites.edge_at(gid, pa)):
				resets += 1
				a = pa      # (it was put back: carry on beside the course from there)
			if party._t > 60.0:
				break
		print("CHEAT %s beside the course: put back %d times, finished %s, light-red penalty %s" % [gid, resets, party._done, party._penalty > 0.0])
		if party._done:
			_fail("%s: finished beside the course" % gid)
		if resets == 0:
			_fail("%s: never put back" % gid)
		# 2) steered into the side barrier at speed: stays on the course
		party._done = false
		party._pin = false
		party._out_t = 0.0
		var a2 := len * 0.4
		var xf: Transform3D = sites.course_xf(gid, a2, sites.edge_at(gid, a2) - 2.0, 0.6)
		car.place(xf)
		var right: Vector3 = xf.basis.x
		var worst := 0.0
		for f in int(hz * 1.5):
			car.linear_velocity = right * 14.0 + Vector3(0, car.linear_velocity.y, 0)
			await get_tree().physics_frame
			var lat2 := float(world.track.project(car.global_position)[2])
			worst = maxf(worst, absf(lat2) - float(sites.edge_at(gid, a2)))
		print("CHEAT %s into the barrier: at most %.1f m beyond the road edge (barrier at %.1f)" % [gid, worst, sites.SIDE_WALL])
		if worst > sites.SIDE_WALL + 0.5:
			_fail("%s: drove through the side barrier" % gid)
		party._t = 1e6
		party._finish_local()
		for f in int(hz * (party.RESULTS_TIME + 5.0)):
			await get_tree().physics_frame
			if party.state == "idle":
				break
	print("PARTY CHEAT TEST: %s" % ("PASS" if fails == 0 else "FAIL"))
	get_tree().quit(1 if fails else 0)

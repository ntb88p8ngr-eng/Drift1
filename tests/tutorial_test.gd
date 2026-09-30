extends Node
## Tutorial: the set is built on Grüne Hölle, the car starts in the garage, the intro can be skipped,
## the car drives out of the garage, the gravel track is loose, arriving at the camp plays the ending
## and finishing it pays out.
## Run: godot --headless --path . res://tests/tutorial_test.tscn

const World = preload("res://scripts/world/world.gd")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Game.persist = false
	var t0 := Time.get_ticks_msec()
	var world := World.new()
	world.setup({"track": "gruene_hoelle", "mode": "tutorial", "laps": 1, "time_of_day": "night", "hour": 23.98,
		"weather": "rain", "day_cycle": 0, "weather_seed": 77, "online": false, "collisions": true})
	add_child(world)
	if not world.is_loaded:
		await world.loaded
	print("TUTORIAL: loaded in %d ms" % (Time.get_ticks_msec() - t0))
	var fails := 0
	var tut = world.tutorial
	var site = world.tutorial_site
	if tut == null or site == null:
		print("FAIL: no tutorial")
		get_tree().quit(1)
		return
	var car = world.local_car
	if car.car_id != "r34":
		print("FAIL: not the R34"); fails += 1
	for f in 60:
		await get_tree().physics_frame
	var d0: float = car.global_position.distance_to(site.car_xf.origin)
	print("  car %.2f m from its garage spot, state %s, shot %d" % [d0, tut.state, tut._shot])
	if d0 > 1.0:
		print("FAIL: car not in the garage"); fails += 1
	# let the cutscene run a few seconds, then skip it
	for f in 120 * 4:
		await get_tree().process_frame
	print("  after 4 s: shot %d, clock strikes %d" % [tut._shot, tut._clock_strikes])
	# jump to the last shot and let the intro end on its own (it fades to black and must fade back in)
	while tut._shot < tut._shots.size() - 2:
		tut._next_shot()
	tut._next_shot()
	var wait_n := 0
	while tut.state != "drive" and wait_n < 120 * 10:
		await get_tree().process_frame
		wait_n += 1
	if tut.state != "drive" or not tut._hint_open or not get_tree().paused:
		print("FAIL: the end of the intro did not start the drive with a hint (state %s)" % tut.state); fails += 1
	for f in 120 * 2:
		await get_tree().process_frame
	print("  fade alpha 2 s into the drive: %.2f" % tut._fade.color.a)
	if tut._fade.color.a > 0.05:
		print("FAIL: the screen stays black after the intro"); fails += 1
	if not tut.world.camera.current:
		print("FAIL: the chase camera is not active"); fails += 1
	tut._close_hint()
	# drive out of the garage
	Input.action_press("accelerate", 0.6)
	var max_d := 0.0
	for f in 120 * 4:
		await get_tree().physics_frame
		max_d = maxf(max_d, car.global_position.distance_to(site.car_xf.origin))
	Input.action_release("accelerate")
	print("  drove %.1f m out of the garage (%.0f km/h)" % [max_d, car.speed_kmh()])
	if max_d < 10.0:
		print("FAIL: the car did not get out of the garage"); fails += 1
	# the gravel track: loose surface
	var mid: Vector3 = site.path_pts[site.path_pts.size() / 2]
	var s: Array = tut._surface(mid)
	print("  gravel track surface: %s" % str(s))
	if str(s[1]) != "gravel":
		print("FAIL: the gravel track is not gravel"); fails += 1
	# drive through the barrier gap at the turn-off (no wall there)
	var gap_ok: bool = world.track.in_wall_gap(world.track.index_at(site.EXIT_P), site.EXIT_SIDE)
	if not gap_ok:
		print("FAIL: no gap in the barrier at the turn-off"); fails += 1
	# arrive at the camp
	car.place(Transform3D(Basis.IDENTITY, site.path_pts[site.path_pts.size() - 6] + Vector3(0, 0.8, 0)))
	var guard := 0
	while tut.state != "ending" and guard < 240:
		await get_tree().physics_frame
		guard += 1
		if tut._hint_open:
			tut._close_hint()
	if tut.state != "ending":
		print("FAIL: arriving at the camp did not start the ending (state %s, %.0f m)" % [tut.state, car.global_position.distance_to(site.camp)]); fails += 1
	for f in 120 * 3:
		await get_tree().process_frame
	var credits: int = int(Game.settings["credits"])
	tut._skip_ending()
	await get_tree().process_frame
	if tut.state != "done" or int(Game.settings["credits"]) != credits + tut.REWARD:
		print("FAIL: finishing did not pay out (state %s)" % tut.state); fails += 1
	print("TUTORIAL TEST: %s" % ("PASS" if fails == 0 else "FAIL"))
	get_tree().quit(1 if fails else 0)

extends Node
## Time attack: the car is carried round the lap at a set speed (3 laps: 25, 30, 20 m/s). The first lap
## is saved as the best and becomes the ghost, the faster second replaces it, during the slower third
## the delta is positive and the ghost is ahead. The saved file loads again.
## Run: godot --headless --fixed-fps 60 --path . res://tests/time_attack_test.tscn

const World = preload("res://scripts/world/world.gd")
const TimeAttack = preload("res://scripts/world/time_attack.gd")

const TRACK := "playground"


func _ready() -> void:
	Game.persist = false
	# the player's own best lap here is kept aside and put back afterwards
	var path := TimeAttack.ghost_path(TimeAttack.ghost_key(TRACK, "normal", ""))
	var keep := path + ".keep"
	if FileAccess.file_exists(path):
		DirAccess.rename_absolute(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(keep))
	Game.settings["ghost"] = 1
	var world := World.new()
	world.setup({"track": TRACK, "mode": "time_attack", "laps": 1, "time_of_day": "day", "weather": "dry",
		"day_cycle": 0, "weather_seed": 3, "online": false, "traffic": 0})
	add_child(world)
	if not world.is_loaded:
		await world.loaded
	var ok := true
	var ta = world.time_attack
	var tr = world.track
	var car = world.local_car
	car.freeze = true
	print("TIME ATTACK: lap %.0f m, best before %.2f" % [tr.length, ta.best_time()])
	ok = ok and ta != null and ta.best_time() == 0.0
	var d: float = tr.length - 30.0
	var speeds := [25.0, 30.0, 20.0]
	var lap_before := 0
	var deltas: Array = [[], [], []]
	var ahead := 0
	var checks := 0
	for k in speeds.size():
		var v: float = speeds[k]
		while world.lap == lap_before:
			d += v / float(Engine.physics_ticks_per_second)
			var dd := fposmod(d, tr.length)
			var i: int = tr.index_at(dd)
			var j: int = (i + 1) % tr.samples.size()
			car.global_transform = Transform3D(Basis.looking_at(tr.tangents[i], Vector3.UP), (tr.samples[i] as Vector3) + Vector3(0, 0.4, 0))
			car.linear_velocity = (tr.tangents[i] as Vector3) * v
			await get_tree().physics_frame
			if ta.delta_valid:
				(deltas[k] as Array).append(float(ta.delta))
			# lap 3: the ghost (lap 2, faster) is ahead of the car
			var lap_t: float = float(world.race_time) - float(world.lap_start)
			if k == 2 and world.crossed_start and lap_t > 5.0 and lap_t < float(world.lap_times[1]) - 1.0 and not ta._ghosts.is_empty():
				# where it is in its lap, and that it is really there on the road
				var g = ta._ghosts[0]
				var g_dist: float = g.data[g.cursor * TimeAttack.F + 10]
				var gp: Vector3 = g.node.global_position
				var off: float = gp.distance_to(tr.samples[tr.index_at(g_dist)])
				checks += 1
				if g_dist > float(world.progress) + 20.0 and off < 4.0:
					ahead += 1
			if float(world.race_time) > 600.0:
				break
		lap_before = world.lap
		var dl: Array = deltas[k]
		var last_d: float = dl[dl.size() - 1] if not dl.is_empty() else 0.0
		print("TIME ATTACK: lap %d at %.0f m/s: %.2f s (expected ~%.2f), best %.2f, ghosts %d, delta samples %d, last delta %.2f" % [
			k + 1, v, float(world.last_lap), tr.length / v, ta.best_time(), ta._ghosts.size(), dl.size(), last_d])
	var t1: float = tr.length / 25.0
	var t2: float = tr.length / 30.0
	ok = ok and absf(float(world.lap_times[0]) - t1) < 1.0 and absf(float(world.lap_times[1]) - t2) < 1.0
	ok = ok and absf(ta.best_time() - float(world.lap_times[1])) < 0.01
	# lap 2 against lap 1: ahead (negative), growing; lap 3 against lap 2: behind
	var d2: Array = deltas[1]
	var d3: Array = deltas[2]
	ok = ok and d2.size() > 100 and float(d2[d2.size() - 1]) < -2.0
	ok = ok and d3.size() > 100 and float(d3[d3.size() - 1]) > 2.0
	print("TIME ATTACK: lap 3 – ghost ahead in %d of %d checks, ghosts shown %d (best + last)" % [ahead, checks, ta._ghosts.size()])
	ok = ok and checks > 50 and ahead > checks * 0.95 and ta._ghosts.size() == 2
	var saved := TimeAttack.load_ghost(ta.key)
	var n: int = (saved.get("data", PackedFloat32Array()) as PackedFloat32Array).size() / TimeAttack.F
	print("TIME ATTACK: saved %s: %.2f s, %d samples, car %s" % [TimeAttack.ghost_path(ta.key), float(saved.get("header", {}).get("time", 0.0)), n, saved.get("header", {}).get("car", "")])
	ok = ok and absf(float(saved.get("header", {}).get("time", 0.0)) - t2) < 1.0 and n > int(t2 * TimeAttack.RATE * 0.9)
	# the menu's look at it
	ok = ok and not TimeAttack.best_info(TRACK, "normal", "").is_empty()
	world.queue_free()
	await get_tree().process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if FileAccess.file_exists(keep):
		DirAccess.rename_absolute(ProjectSettings.globalize_path(keep), ProjectSettings.globalize_path(path))
	print("TIME ATTACK TEST: %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)

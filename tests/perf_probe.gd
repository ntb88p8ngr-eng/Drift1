extends Node
## Where the frame time goes: a race with bots on each map, the player's car driven round by the
## bot driver, every script's _process / _physics_process timed on its own (called from here
## instead of by the engine), plus the renderer's counts. Prints the costliest scripts, the mean
## and worst frame, and what caused the spikes.
## Run (a renderer for the counts): xvfb-run godot --rendering-driver opengl3 --path .
## res://tests/perf_probe.tscn [-- utah,ridge] [--secs=20]

const World = preload("res://scripts/world/world.gd")
const MainScript = preload("res://scripts/main.gd")

var _nodes_p: Array = []     # [node, script path]
var _nodes_pp: Array = []
var _cost := {}              # script path -> [usec total, calls, max]
var _frame_us := 0
var _frames := 0
var _spikes: Array = []
var _active := false


func _ready() -> void:
	Game.persist = false
	Game.first_boot = false
	var tracks: Array = ["ridge", "harbor", "playground", "tokyo", "utah", "gruene_hoelle"]
	var secs := 20.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--secs="):
			secs = float(a.substr(7))
		elif not a.begins_with("--"):
			tracks = a.split(",")
	for tid in tracks:
		Game.settings["mode"] = "race"
		Game.settings["bots"] = 3
		Game.settings["track"] = tid
		var cfg: Dictionary = MainScript.offline_config()
		cfg["weather"] = "dry"
		cfg["time_of_day"] = "day"
		cfg["day_cycle"] = 0
		cfg["traffic"] = 2
		var world := World.new()
		world.setup(cfg)
		add_child(world)
		var t0 := Time.get_ticks_msec()
		if not world.is_loaded:
			await world.loaded
		var load_ms := Time.get_ticks_msec() - t0
		for f in 10:
			await get_tree().process_frame
		# the player's car drives like a bot
		if world.race_ai:
			world.race_ai.add_bot(999, world.local_car, "Ausgeglichen")
		world.state = "running"
		world.local_car.controls_locked = false
		_collect(world)
		_cost.clear()
		_spikes.clear()
		_frame_us = 0
		_frames = 0
		var mon := {"objects": 0.0, "draws": 0.0, "prims": 0.0}
		var mon_max := {"objects": 0.0, "draws": 0.0, "prims": 0.0}
		_active = true
		var t_end := Time.get_ticks_msec() + int(secs * 1000.0)
		var n := 0
		while Time.get_ticks_msec() < t_end:
			await get_tree().process_frame
			n += 1
			for pair in [["objects", Performance.RENDER_TOTAL_OBJECTS_IN_FRAME], ["draws", Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME], ["prims", Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME]]:
				var v := Performance.get_monitor(pair[1])
				mon[pair[0]] += v
				mon_max[pair[0]] = maxf(mon_max[pair[0]], v)
		_active = false
		_restore()
		var nodes := Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
		print("== %s: load %d ms, %d nodes, %.0f km driven by the player car" % [tid, load_ms, nodes, 0.0])
		print("   render per frame: objects %.0f (max %.0f), draw calls %.0f (max %.0f), primitives %.0fk (max %.0fk)" % [
			mon["objects"] / n, mon_max["objects"], mon["draws"] / n, mon_max["draws"], mon["prims"] / n / 1000.0, mon_max["prims"] / 1000.0])
		print("   scripts per frame: %.2f ms mean over %d frames" % [float(_frame_us) / maxi(_frames, 1) / 1000.0, _frames])
		var rows: Array = []
		for k in _cost:
			rows.append([k, _cost[k][0], _cost[k][1], _cost[k][2]])
		rows.sort_custom(func(a, b): return a[1] > b[1])
		for r in rows.slice(0, 14):
			print("     %-48s %6.3f ms/frame  max %5.1f ms" % [str(r[0]).trim_prefix("res://scripts/"), float(r[1]) / maxi(_frames, 1) / 1000.0, float(r[3]) / 1000.0])
		_spikes.sort_custom(func(a, b): return a[0] > b[0])
		for s in _spikes.slice(0, 6):
			print("     spike %.1f ms: %s" % [s[0] / 1000.0, s[1]])
		world.queue_free()
		for f in 3:
			await get_tree().process_frame
	print("PERF PROBE DONE")
	get_tree().quit()


func _collect(root: Node) -> void:
	_nodes_p.clear()
	_nodes_pp.clear()
	for n in [root] + root.find_children("*", "Node", true, false):
		var s = n.get_script()
		if s == null:
			continue
		var path: String = (s as Script).resource_path
		if n.is_processing() and n.has_method("_process"):
			n.set_process(false)
			_nodes_p.append([n, path])
		if n.is_physics_processing() and n.has_method("_physics_process"):
			n.set_physics_process(false)
			_nodes_pp.append([n, path])


func _restore() -> void:
	for e in _nodes_p:
		if is_instance_valid(e[0]):
			e[0].set_process(true)
	for e in _nodes_pp:
		if is_instance_valid(e[0]):
			e[0].set_physics_process(true)


func _run(list: Array, delta: float, method: String) -> int:
	var total := 0
	for e in list:
		var n = e[0]
		if not is_instance_valid(n) or not n.is_inside_tree():
			continue
		var t := Time.get_ticks_usec()
		n.call(method, delta)
		var dt := Time.get_ticks_usec() - t
		total += dt
		var k: String = e[1] + ("" if method == "_process" else " (physics)")
		if not _cost.has(k):
			_cost[k] = [0, 0, 0]
		_cost[k][0] += dt
		_cost[k][1] += 1
		_cost[k][2] = maxi(_cost[k][2], dt)
		if dt > 4000:
			_spikes.append([dt, k])
	return total


func _process(delta: float) -> void:
	if not _active:
		return
	_frame_us += _run(_nodes_p, delta, "_process")
	_frames += 1


func _physics_process(delta: float) -> void:
	if not _active:
		return
	_frame_us += _run(_nodes_pp, delta, "_physics_process")

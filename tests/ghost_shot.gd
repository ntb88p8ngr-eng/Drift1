extends Node
## Screenshot of a time-attack ghost a few metres ahead of the car (needs a renderer).
## Run: xvfb-run godot --rendering-driver opengl3 --fixed-fps 60 --path . res://tests/ghost_shot.tscn -- out.png

const World = preload("res://scripts/world/world.gd")
const TimeAttack = preload("res://scripts/world/time_attack.gd")


func _ready() -> void:
	Game.persist = false
	var out := "user://ghost_shot.png"
	for a in OS.get_cmdline_user_args():
		out = a
	var path := TimeAttack.ghost_path(TimeAttack.ghost_key("playground", "normal", ""))
	var keep := path + ".keep"
	if FileAccess.file_exists(path):
		DirAccess.rename_absolute(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(keep))
	Game.settings["ghost"] = 0
	var world := World.new()
	world.setup({"track": "playground", "mode": "time_attack", "laps": 1, "time_of_day": "dusk", "weather": "dry",
		"day_cycle": 0, "weather_seed": 3, "online": false, "traffic": 0})
	add_child(world)
	if not world.is_loaded:
		await world.loaded
	var ta = world.time_attack
	var tr = world.track
	var car = world.local_car
	car.freeze = true
	get_viewport().disable_3d = true      # (software rendering: only the screenshot is drawn)
	var d: float = tr.length - 30.0
	var hz := float(Engine.physics_ticks_per_second)
	for k in 2:
		var v := 150.0 if k == 0 else 144.0
		while world.lap == k:
			d += v / hz
			var i: int = tr.index_at(fposmod(d, tr.length))
			car.global_transform = Transform3D(Basis.looking_at(tr.tangents[i], Vector3.UP), (tr.samples[i] as Vector3) + Vector3(0, 0.4, 0))
			car.linear_velocity = (tr.tangents[i] as Vector3) * v
			await get_tree().physics_frame
			if k == 1 and world.crossed_start and float(world.race_time) - float(world.lap_start) > 1.5:
				break
		if k == 1:
			break
	car.linear_velocity = Vector3.ZERO
	get_viewport().disable_3d = false
	for f in 8:
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png(out)
	print("GHOST SHOT: %s, ghosts %d, delta %.2f" % [out, ta._ghosts.size(), ta.delta])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if FileAccess.file_exists(keep):
		DirAccess.rename_absolute(ProjectSettings.globalize_path(keep), ProjectSettings.globalize_path(path))
	get_tree().quit(0)

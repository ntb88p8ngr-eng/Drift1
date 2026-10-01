extends Node
## Engine sound of the opponents: with 7 bots the nearest 4 are synthesized (the others wait
## silent), they keep their buffers filled (no skips once running) and play loud enough at 30 m.
## Run: godot --headless --path . res://tests/bot_audio_test.tscn
const World = preload("res://scripts/world/world.gd")
const RaceAI = preload("res://scripts/world/race_ai.gd")
func _ready() -> void:
	Game.persist = false
	var world := World.new()
	world.setup({"track": "ridge", "mode": "race", "laps": 1, "time_of_day": "day", "weather": "dry", "day_cycle": 0,
		"weather_seed": 5, "online": false, "collisions": true, "bots": RaceAI.make_roster(7, 5), "bot_level": 2})
	add_child(world)
	if not world.is_loaded:
		await world.loaded
	world.state = "running"
	for f in 240:
		await get_tree().process_frame
	var fails := 0
	var active := 0
	var skips0 := {}
	for b in world.race_ai.bots:
		var a = b["car"].audio
		skips0[b["id"]] = a.playback.get_skips()
	for f in 120:
		await get_tree().process_frame
	var new_skips := 0
	for b in world.race_ai.bots:
		var a = b["car"].audio
		var p: AudioStreamPlayer3D = a.player
		if not p.stream_paused:
			active += 1
			new_skips += a.playback.get_skips() - int(skips0[b["id"]])
	# loudness of an opponent 30 m away (inverse distance model)
	var p0: AudioStreamPlayer3D = world.race_ai.bots[0]["car"].audio.player
	var db30 := p0.volume_db - 20.0 * log(30.0 / p0.unit_size) / log(10.0)
	print("BOT AUDIO: %d of %d synthesized, %d skips on them in 2 s, %.1f dB at 30 m" % [active, world.race_ai.bots.size(), new_skips, db30])
	if active < 1 or active > 4 or db30 < -10.0:
		fails += 1
	print("BOT AUDIO TEST: %s" % ("PASS" if fails == 0 else "FAIL"))
	get_tree().quit(1 if fails else 0)

extends Node
## Bots move the minigames' loose things like a player does: a bot driving into a party tyre, a log
## and a bowling pin pushes them away (they used to ignore bots, which bounced off them as off a
## wall). Run: godot --headless --path . res://tests/bot_props_test.tscn

const World = preload("res://scripts/world/world.gd")
const MainScript = preload("res://scripts/main.gd")


func _ready() -> void:
	Game.persist = false
	Game.settings["mode"] = "race"
	Game.settings["bots"] = 1
	Game.settings["party"] = true
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
	var bot = null
	for id in world.cars:
		if world._bot_ids.has(int(id)):
			bot = world.cars[id]
	var sites = world.party_sites
	sites.build_course("parkour")
	for f in 5:
		await get_tree().physics_frame
	var bodies: Array = []
	for b in sites.find_children("*", "RigidBody3D", true, false):
		bodies.append(b)
	print("BOTPROPS: %d party bodies" % bodies.size())
	# one of each mass class: light (tyre, pin), heavy (log)
	var picks := {}
	for b in bodies:
		var cls := "light" if (b as RigidBody3D).mass < 20.0 else "heavy"
		if not picks.has(cls):
			picks[cls] = b
	var ok := bot != null and picks.size() == 2
	bot.ai_fn = func() -> Array: return [0.0, 0.0, 0.0, false, false]
	for cls in picks:
		var b: RigidBody3D = picks[cls]
		var o := b.global_position
		var dir := Vector3(1, 0, 0)
		var start := o - dir * 8.0
		start.y = o.y + 0.6
		bot.freeze = false
		bot.place(Transform3D(Basis.looking_at(dir, Vector3.UP), start))
		bot.linear_velocity = dir * 9.0
		b.sleeping = false
		for f in 120:
			await get_tree().physics_frame
		var moved := b.global_position.distance_to(o)
		print("BOTPROPS %s (%s, %.0f kg): moved %.2f m, bot now %.0f km/h" % [cls, b.name, b.mass, moved, bot.speed * 3.6])
		ok = ok and moved > 0.3
	print("BOT PROPS TEST: %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit()

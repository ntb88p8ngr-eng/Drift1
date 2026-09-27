extends Node
## Screenshots of menu screens and the race HUD (visual check).
## Run: godot --path . res://tests/ui_shots.tscn -- --out=/tmp/shots

const Main = preload("res://scripts/main.gd")


func _ready() -> void:
	Game.persist = false
	var out := "/tmp/shots"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(out)
	var main := Main.new()
	add_child(main)
	for f in 10:
		await get_tree().process_frame
	for screen in ["options", "garage", "single"]:
		main.menu.show_screen(screen)
		for f in 8:
			await get_tree().process_frame
		await _shot(out.path_join("ui_%s.png" % screen))
	main.menu.show_screen("online")
	for f in 8:
		await get_tree().process_frame
	await _shot(out.path_join("ui_online.png"))
	Net.host_lobby("Test Lobby", 24598, 4, false, "geheim")
	Net.public_ip = "203.0.113.7"
	main.menu.show_screen("lobby")
	for f in 8:
		await get_tree().process_frame
	await _shot(out.path_join("ui_lobby.png"))
	Net.leave()
	main.start_offline()
	while main.world == null:
		await get_tree().process_frame
	for f in 20:
		await get_tree().process_frame
	main.world.scorer.total = 23456.0
	main.world.scorer.best_chain = 8120.0
	main.world.scorer.chain = 2410.0
	main.world.scorer.drifting = true
	main.world.scorer.angle = 38.0
	for f in 10:
		await get_tree().process_frame
	await _shot(out.path_join("ui_hud.png"))
	main.world.pause_menu.toggle()
	main.world.pause_menu._show(main.world.pause_menu._options_box)
	for f in 6:
		await get_tree().process_frame
	await _shot(out.path_join("ui_pause_options.png"))
	get_tree().quit()


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("SHOT ", path)

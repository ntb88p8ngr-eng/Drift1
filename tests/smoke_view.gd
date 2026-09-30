extends Node3D
## Quick look at the tyre smoke alone: a floor, a light, a burst of smoke. Renders a few frames.
## Run: godot --path . res://tests/smoke_view.tscn -- --out=/tmp/shots [--soft=0]

const TexKit = preload("res://scripts/util/tex_kit.gd")
const TireFX = preload("res://scripts/car/tire_fx.gd")


func _ready() -> void:
	var out := "/tmp/shots"
	var soft := 0.7
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		if a.begins_with("--soft="):
			soft = float(a.substr(7))
	DirAccess.make_dir_recursive_absolute(out)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.45, 0.55, 0.7)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.55, 0.6)
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.8, 0.6, 0)
	sun.light_energy = 1.4
	add_child(sun)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	floor_mi.mesh = pm
	floor_mi.material_override = TexKit.std(Color(0.12, 0.12, 0.13), 0.9)
	add_child(floor_mi)
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(0, 1.6, 7.5)
	cam.look_at(Vector3(0, 1.0, 0), Vector3.UP)
	cam.current = true
	var fx := TireFX.new()
	var p: GPUParticles3D = fx._make_smoke(true)
	fx.remove_child(p)
	add_child(p)
	((p.draw_pass_1 as QuadMesh).material as ShaderMaterial).set_shader_parameter("soft_dist", maxf(soft, 0.001))
	p.position = Vector3(0, 0.3, 0)
	p.emitting = true
	for f in 150:
		# drag the emitter to the side like a sliding car
		p.position.x = -3.0 + f * 0.04
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join("smoke_view.png"))
	print("SHOT smoke_view")
	get_tree().quit()

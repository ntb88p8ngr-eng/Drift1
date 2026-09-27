extends Node3D
## Studio scene behind the menu: the selected car on a slowly turning platform, softbox lights that
## reflect in the colour-shifting paint, and an orbiting camera.

const Car = preload("res://scripts/car/car.gd")
const MeshKit = preload("res://scripts/util/mesh_kit.gd")
const TexKit = preload("res://scripts/util/tex_kit.gd")

var car: Car
var turntable: Node3D
var cam: Camera3D
var _t := 0.0


func _ready() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.015, 0.01, 0.03)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.25, 0.2, 0.35)
	env.ambient_light_energy = 0.4
	env.reflected_light_source = Environment.REFLECTION_SOURCE_BG
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.glow_enabled = true
	env.glow_intensity = 0.8
	env.glow_bloom = 0.05
	env.ssao_enabled = Game.quality() >= 2
	env.ssr_enabled = false
	env.fog_enabled = true
	env.fog_light_color = Color(0.08, 0.04, 0.14)
	env.fog_density = 0.02
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	# glossy floor
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.035, 0.035, 0.045)
	floor_mat.roughness = 0.35
	floor_mat.metallic = 0.2
	var plane := PlaneMesh.new()
	plane.size = Vector2(80, 80)
	var floor_mi := MeshKit.mesh_instance(plane, floor_mat, false)
	floor_mi.position.y = -0.002
	add_child(floor_mi)
	# glowing ring first (slightly lower and wider), then the turntable disc on top of it
	var ring := MeshKit.cyl_node(3.78, 3.78, 0.05, TexKit.emissive(Color(0.6, 0.25, 1.0), 2.5), Vector3(0, 0.025, 0), Vector3.ZERO, 96)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	var disc := MeshKit.cyl_node(3.62, 3.7, 0.07, TexKit.std(Color(0.08, 0.08, 0.1), 0.35, 0.6), Vector3(0, 0.035, 0), Vector3.ZERO, 96)
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(disc)
	turntable = Node3D.new()
	turntable.position.y = 0.07
	add_child(turntable)

	# softboxes (emissive panels) – they show up as reflections in the paint
	for k in 3:
		var sb := MeshKit.box_node(Vector3(6.0, 0.05, 1.2), TexKit.emissive(Color(1, 1, 1), 2.5), Vector3(0, 5.0, -3.0 + k * 3.0))
		sb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(sb)
	var side_panel := MeshKit.box_node(Vector3(0.05, 2.5, 8.0), TexKit.emissive(Color(0.65, 0.35, 1.0), 1.5), Vector3(-7.0, 1.8, 0))
	add_child(side_panel)
	var side_panel2 := MeshKit.box_node(Vector3(0.05, 2.5, 8.0), TexKit.emissive(Color(0.3, 0.8, 1.0), 0.9), Vector3(7.0, 1.8, 0))
	add_child(side_panel2)

	var key := SpotLight3D.new()
	key.position = Vector3(3, 6, 4)
	key.look_at_from_position(key.position, Vector3(0, 0.5, 0), Vector3.UP)
	key.spot_range = 20.0
	key.spot_angle = 40.0
	key.light_energy = 10.0
	key.shadow_enabled = true
	key.shadow_bias = 0.08
	key.shadow_normal_bias = 1.5
	key.shadow_blur = 1.5
	add_child(key)
	var fill := SpotLight3D.new()
	fill.position = Vector3(-4, 4, -3)
	fill.look_at_from_position(fill.position, Vector3(0, 0.5, 0), Vector3.UP)
	fill.spot_range = 20.0
	fill.spot_angle = 45.0
	fill.light_energy = 4.0
	fill.light_color = Color(0.7, 0.55, 1.0)
	add_child(fill)
	var rim := OmniLight3D.new()
	rim.position = Vector3(0, 1.5, -5)
	rim.omni_range = 9.0
	rim.light_energy = 2.0
	rim.light_color = Color(0.4, 0.8, 1.0)
	add_child(rim)

	var probe := ReflectionProbe.new()
	probe.size = Vector3(20, 10, 20)
	probe.position = Vector3(0, 2.0, 0)
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	probe.box_projection = true
	add_child(probe)

	cam = Camera3D.new()
	cam.fov = 45.0
	cam.current = true
	add_child(cam)
	rebuild_car()


func rebuild_car() -> void:
	if car:
		car.queue_free()
	car = Car.new()
	car.is_display = true
	car.car_id = Game.settings["car"]
	car.paint = Game.get_paint(Game.settings["paint"], Game.settings["custom_color"])
	turntable.add_child(car)
	car.headlights = true
	car.body.set_lights(true, false, false)


func refresh_paint() -> void:
	if car:
		car.set_paint(Game.get_paint(Game.settings["paint"], Game.settings["custom_color"]))


func _process(delta: float) -> void:
	_t += delta
	turntable.rotation.y = _t * 0.25
	var a := 0.6 + sin(_t * 0.12) * 0.25
	cam.position = Vector3(sin(a) * 7.2 - 1.6, 1.6 + sin(_t * 0.2) * 0.2, cos(a) * 7.2)
	cam.look_at(Vector3(-1.2, 0.6, 0), Vector3.UP)

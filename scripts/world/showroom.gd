extends Node3D
## Scene behind the menu: the selected car on a slowly turning platform in the middle of an old
## garage hall (assets/env/garage.glb), softbox lights that reflect in the paint and an orbiting camera.

const Car = preload("res://scripts/car/car.gd")
const MeshKit = preload("res://scripts/util/mesh_kit.gd")
const TexKit = preload("res://scripts/util/tex_kit.gd")

var car: Car
var turntable: Node3D
var cam: Camera3D
var _t := 0.0


const GARAGE_SCENE := "res://assets/env/garage.glb"
const POSTER_DIR := "res://assets/env/posters/"
const GARAGE_INFO := "res://assets/env/garage.json"


func _ready() -> void:
	var garage := _load_garage()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.012, 0.016, 0.03)   # night sky through the skylights
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.5, 0.45) if garage else Color(0.25, 0.2, 0.35)
	env.ambient_light_energy = 0.35 if garage else 0.4
	env.reflected_light_source = Environment.REFLECTION_SOURCE_BG
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.1
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.04
	env.ssao_enabled = Game.quality() >= 2
	env.ssr_enabled = false
	env.fog_enabled = true
	env.fog_light_color = Color(0.1, 0.08, 0.07) if garage else Color(0.08, 0.04, 0.14)
	env.fog_density = 0.012 if garage else 0.02
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	if garage == null:
		# fallback studio floor when the garage asset is missing
		var floor_mat := StandardMaterial3D.new()
		floor_mat.albedo_color = Color(0.035, 0.035, 0.045)
		floor_mat.roughness = 0.35
		floor_mat.metallic = 0.2
		var plane := PlaneMesh.new()
		plane.size = Vector2(80, 80)
		var floor_mi := MeshKit.mesh_instance(plane, floor_mat, false)
		floor_mi.position.y = -0.002
		add_child(floor_mi)
	# turntable in the middle of the hall: glowing ring first (slightly lower and wider), then the disc
	var r := 3.25 if garage else 3.7
	var ring := MeshKit.cyl_node(r + 0.08, r + 0.08, 0.05, TexKit.emissive(Color(0.6, 0.25, 1.0), 2.5), Vector3(0, 0.025, 0), Vector3.ZERO, 96)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	var disc_mat := TexKit.std(Color(0.08, 0.08, 0.1), 0.35, 0.6)
	var disc := MeshKit.cyl_node(r - 0.08, r, 0.07, disc_mat, Vector3(0, 0.035, 0), Vector3.ZERO, 96)
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(disc)
	turntable = Node3D.new()
	turntable.position.y = 0.07
	add_child(turntable)

	# softboxes (emissive panels hung from the roof trusses) – they show up as reflections in the paint
	for k in 3:
		var sb := MeshKit.box_node(Vector3(5.0, 0.05, 1.0), TexKit.emissive(Color(1, 0.97, 0.92), 2.2), Vector3(0, 4.6, -2.6 + k * 2.6))
		sb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(sb)
	if garage == null:
		var side_panel := MeshKit.box_node(Vector3(0.05, 2.5, 8.0), TexKit.emissive(Color(0.65, 0.35, 1.0), 1.5), Vector3(-7.0, 1.8, 0))
		add_child(side_panel)
		var side_panel2 := MeshKit.box_node(Vector3(0.05, 2.5, 8.0), TexKit.emissive(Color(0.3, 0.8, 1.0), 0.9), Vector3(7.0, 1.8, 0))
		add_child(side_panel2)
	else:
		_hall_lights()

	var key := SpotLight3D.new()
	key.position = Vector3(3, 4.4, 4)
	key.look_at_from_position(key.position, Vector3(0, 0.5, 0), Vector3.UP)
	key.spot_range = 20.0
	key.spot_angle = 40.0
	key.light_energy = 9.0
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
	fill.light_energy = 3.5
	fill.light_color = Color(0.7, 0.55, 1.0)
	add_child(fill)
	var rim := OmniLight3D.new()
	rim.position = Vector3(0, 1.5, -5)
	rim.omni_range = 9.0
	rim.light_energy = 1.6
	rim.light_color = Color(0.4, 0.8, 1.0)
	add_child(rim)

	var probe := ReflectionProbe.new()
	probe.size = Vector3(26, 7.5, 20) if garage else Vector3(20, 10, 20)
	probe.position = Vector3(0, 3.0, 0)
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	probe.box_projection = true
	probe.interior = garage != null
	add_child(probe)

	cam = Camera3D.new()
	cam.fov = 48.0
	cam.current = true
	add_child(cam)
	rebuild_car()


## The garage hall (converted from the 3ds Max scene, see tools/convert_garage.py), moved so that the
## middle of the hall – where the turntable stands – is the origin.
func _load_garage() -> Node3D:
	if not ResourceLoader.exists(GARAGE_SCENE):
		return null
	var scene := load(GARAGE_SCENE) as PackedScene
	if scene == null:
		return null
	var g := scene.instantiate() as Node3D
	var stage := Vector3.ZERO
	var f := FileAccess.open(GARAGE_INFO, FileAccess.READ)
	if f:
		var info = JSON.parse_string(f.get_as_text())
		if info is Dictionary and info.has("stage"):
			var st: Array = info["stage"]
			stage = Vector3(float(st[0]), float(st[1]), float(st[2]))
	g.position = -stage
	add_child(g)
	for mi in g.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if str(mi.name).begins_with("Poster_T"):
			_replace_poster(mi as MeshInstance3D)
	return g


## Old prints in a dusty hall: faded (less saturated), darker, a greyish dust film that is
## thicker towards the frame edges and a matte surface.
const POSTER_SHADER := """
shader_type spatial;
uniform sampler2D tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec2 uv_scale = vec2(1.0);
uniform vec2 uv_offset = vec2(0.0);
uniform float fade = 0.5;        // 0 = original colours, 1 = grey
uniform float dim = 0.6;
uniform vec3 dust : source_color = vec3(0.46, 0.44, 0.41);

float h(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h(i), h(i + vec2(1, 0)), f.x), mix(h(i + vec2(0, 1)), h(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	vec2 uv = UV * uv_scale + uv_offset;
	vec3 c = texture(tex, uv).rgb;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(c, vec3(l), fade) * dim;
	vec2 e = min(uv, 1.0 - uv);
	float edge = 1.0 - smoothstep(0.0, 0.18, min(e.x, e.y));
	float n = vnoise(uv * vec2(9.0, 12.0)) * 0.6 + vnoise(uv * vec2(40.0, 52.0)) * 0.4;
	float film = clamp(0.12 + edge * 0.3 + (n - 0.5) * 0.18, 0.0, 0.7);
	ALBEDO = mix(c, dust * 0.55, film);
	ROUGHNESS = 0.78;
	SPECULAR = 0.3;
}
"""
static var _poster_sh: Shader


static func _poster_shader() -> Shader:
	if _poster_sh == null:
		_poster_sh = Shader.new()
		_poster_sh.code = POSTER_SHADER
	return _poster_sh


## The five framed posters on the back wall show our own car pictures (assets/env/posters/poster_N.jpg,
## N = 1..5 from left to right). Each poster is a quad whose UVs point into the garage atlas; they are
## remapped to the whole picture.
func _replace_poster(mi: MeshInstance3D) -> void:
	var k := str(mi.name).substr(8, 1).to_int()
	var path := POSTER_DIR + "poster_%d.jpg" % k
	if k < 1 or mi.mesh == null or not ResourceLoader.exists(path):
		return
	var uvs: PackedVector2Array = mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
	if uvs.is_empty():
		return
	var lo := uvs[0]
	var hi := uvs[0]
	for uv in uvs:
		lo = lo.min(uv)
		hi = hi.max(uv)
	var size := (hi - lo).max(Vector2(1e-4, 1e-4))
	var m := ShaderMaterial.new()
	m.shader = _poster_shader()
	m.set_shader_parameter("tex", load(path))
	m.set_shader_parameter("uv_scale", Vector2(1.0 / size.x, 1.0 / size.y))
	m.set_shader_parameter("uv_offset", Vector2(-lo.x / size.x, -lo.y / size.y))
	mi.material_override = m


## Warm work lights under the roof trusses so the whole hall is visible behind the car.
func _hall_lights() -> void:
	# kept away from the walls and the office box so they don't burn hot spots into the textures
	for p in [Vector3(-5, 5.2, -4), Vector3(5, 5.2, -4), Vector3(-5, 5.2, 5.5), Vector3(5, 5.2, 5.5),
			Vector3(-10.5, 5.2, 3.0), Vector3(9.5, 5.2, 0.5), Vector3(0, 5.2, -7.5)]:
		var l := OmniLight3D.new()
		l.position = p
		l.omni_range = 8.5
		l.omni_attenuation = 1.6
		l.light_energy = 0.9
		l.light_color = Color(1.0, 0.82, 0.62)
		add_child(l)


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
	cam.position = Vector3(sin(a) * 8.0 - 1.7, 1.75 + sin(_t * 0.2) * 0.2, cos(a) * 8.0)
	cam.look_at(Vector3(-1.3, 0.75, 0), Vector3.UP)

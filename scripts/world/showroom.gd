extends Node3D
## Scene behind the menu: the selected car on the neon turntable of the Midnight Drift workshop
## (assets/main_menu/Midnight_Drift_Garage_Detailed: red-and-black garage, the open shutter onto a
## night street), its work lights and an orbiting camera. Falls back to the old garage hall
## (assets/env/garage.glb) when the workshop is missing.

const Car = preload("res://scripts/car/car.gd")
const MeshKit = preload("res://scripts/util/mesh_kit.gd")
const TexKit = preload("res://scripts/util/tex_kit.gd")
const MenuStorm = preload("res://scripts/world/menu_storm.gd")
const MeshMerge = preload("res://scripts/util/mesh_merge.gd")
const WorkshopTextures = preload("res://scripts/world/workshop_textures.gd")

var car: Car
var turntable: Node3D
var cam: Camera3D
var _t := 0.0


const GARAGE_SCENE := "res://assets/env/garage.glb"
const POSTER_DIR := "res://assets/env/posters/"
const GARAGE_INFO := "res://assets/env/garage.json"
const WORKSHOP := "res://assets/main_menu/Midnight_Drift_Garage_Detailed.glb"
const WORKSHOP_SKY := "res://assets/main_menu/Midnight_City_Skybox/Midnight_City_Skybox/Midnight_City_Panorama.png"
## the model's own animated storm parts (rain sheets, the lightning bolt): not merged
const STORM_PARTS := ["Turntable_ROTATE", "GLB_Rain", "Storm_lightning"]
const DECK_Y := 0.465            # top of the turntable deck
## glTF light intensities come in far too strong for Godot: energy per light name prefix
const WORKSHOP_LIGHTS := {"Overhead": 0.55, "Honeycomb": 0.6, "Booth": 0.5, "Office": 0.5, "Workbench": 0.7, "Neon": 1.4}

var _workshop := false
var _anim: AnimationPlayer
var _deck: Node3D
var _deck_base: Transform3D      # the deck as authored (turned about the world Y axis from there)
signal story_arrived
signal story_left

const FLY_TIME := 3.4
var story := false               # the camera is at (or on its way to) the office PC
var _fly_dir := 0                # 1: flying to the PC, -1: back to the car
var _fly_t := 0.0
var _fly_from: Array = []
var _pc_corners: Array = []      # the PC screen (Monitor_pixels) – world corners
var _pc_normal := Vector3.RIGHT  # the way the screen faces
var _door := Vector3(-6.75, 1.4, 4.0)   # the office door, out of the hall
var _ceiling_mat: BaseMaterial3D
var _platform_mat: BaseMaterial3D
var _ceiling_emission := 1.0
var _platform_emission := 1.0
var _ceiling_lights: Array = []
var _platform_lights: Array = []
var _light_base := {}

## The platform (menu buttons): it turns slowly on its own, always the same way; held buttons turn it
## either way; a view ("overview", "wheels", "front", "rear") swings it (forwards) and the camera to a
## preset – "wheels" shows the side of the car with the front rim close up.
const AUTO_SPEED := 0.1          # rad/s – about a minute per turn
const MANUAL_SPEED := 0.9
var auto_spin := true
var headlights := true           # the display car's headlights (L), on whenever the game starts
var manual_dir := 0.0            # -1 / 0 / 1 while a turn button is held
var view := "overview"
var _angle := 0.0
var _target := NAN               # platform angle a view turns to
var _cam_pos := Vector3(0, 2.6, 9.8)
var _cam_at := Vector3(-2.2, 1.0, -1.2)
const VIEWS := {
	# [platform angle, camera position, look at]
	# (the menu covers the left half of the screen: the car is framed in the right half)
	"wheels": [PI * 0.5, Vector3(-2.0, 0.8, 3.6), Vector3(-3.2, 0.45, 0.8)],
	"front": [PI, Vector3(-0.6, 1.3, 6.4), Vector3(-2.0, 0.6, 0.0)],
	"rear": [0.0, Vector3(-0.6, 1.3, 6.4), Vector3(-2.0, 0.6, 0.0)],
}


func set_view(v: String) -> void:
	view = v
	if VIEWS.has(v):
		auto_spin = false
		var want: float = VIEWS[v][0]
		# always forwards: the next time the platform reaches that angle
		_target = _angle + fposmod(want - _angle, TAU)
	else:
		_target = NAN
		auto_spin = true


func _ready() -> void:
	if _load_workshop():
		return
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
	if garage:
		# a stormy night outside: lightning, rain and thunder (seen through the gate and skylights)
		var storm := MenuStorm.new()
		storm.name = "Storm"
		add_child(storm)
		storm.setup(env, _hall_rect())

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


## The Midnight Drift workshop: the car stands on its turntable (spun by the scene's own
## 20-second animation), the night street panorama behind the open shutter.
func _load_workshop() -> bool:
	if not ResourceLoader.exists(WORKSHOP):
		return false
	var scene := load(WORKSHOP) as PackedScene
	if scene == null:
		return false
	var g := scene.instantiate() as Node3D
	add_child(g)
	_workshop = true
	WorkshopTextures.apply(g)
	_extend_room(g)
	_find_menu_lights(g)
	_find_pc(g)
	# ~9800 separate parts: everything but the turning deck becomes one mesh per material
	var t0 := Time.get_ticks_msec()
	var n := MeshMerge.merge(g, func(mi: MeshInstance3D) -> bool:
		var path := str(mi.get_path())
		for part in STORM_PARTS:
			if path.contains(part):
				return true
		return false)
	print("SHOWROOM: merged %d workshop meshes in %d ms" % [n, Time.get_ticks_msec() - t0])
	var env := Environment.new()
	if ResourceLoader.exists(WORKSHOP_SKY):
		# only the upper half of the photo: its lower half (street and buildings below the horizon)
		# is now the model's own street
		var sky_mat := ShaderMaterial.new()
		sky_mat.shader = _upper_sky_shader()
		sky_mat.set_shader_parameter("panorama", load(WORKSHOP_SKY))
		sky_mat.set_shader_parameter("energy", 0.62)
		var sky := Sky.new()
		sky.sky_material = sky_mat
		env.background_mode = Environment.BG_SKY
		env.sky = sky
		env.sky_rotation = Vector3(0, 0.37 * TAU, 0)     # the street faces the shutter
	else:
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color(0.01, 0.01, 0.015)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.58, 0.6)
	env.ambient_light_energy = 0.28
	env.reflected_light_source = Environment.REFLECTION_SOURCE_BG
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.05
	env.glow_enabled = true
	env.glow_intensity = 0.8
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.1
	env.ssao_enabled = Game.quality() >= 2
	env.fog_enabled = true
	env.fog_light_color = Color(0.08, 0.05, 0.05)
	env.fog_density = 0.006
	env.fog_sky_affect = 0.0          # (with the full default the street panorama was fogged to black)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	# a cloudburst outside: heavy rain round the workshop, splashes on the street, lightning and
	# thunder (the room: x ±6.9, z ±6.5)
	var storm_fx := MenuStorm.new()
	storm_fx.name = "Storm"
	add_child(storm_fx)
	storm_fx.setup_heavy(env, Rect2(-6.9, -6.5, 13.8, 13.0))
	for l in g.find_children("*", "Light3D", true, false):
		var light := l as Light3D
		for pre in WORKSHOP_LIGHTS:
			if str(light.name).begins_with(pre):
				light.light_energy = float(WORKSHOP_LIGHTS[pre])
		# only the ceiling lights cast shadows (a dozen shadowed omnis is plenty)
		light.shadow_enabled = (str(light.name).begins_with("Overhead") or str(light.name).begins_with("Honeycomb")) \
			and Vector2(light.global_position.x, light.global_position.z).length() < 4.5 and Game.quality() >= 2
	for l in _ceiling_lights + _platform_lights:
		_light_base[l] = (l as Light3D).light_energy
	apply_menu_lights()
	for c in g.find_children("*", "Camera3D", true, false):
		(c as Camera3D).current = false
	# the car is not parented to the deck (its node carries a mirroring axis swap, which would turn
	# the car inside out): it copies the deck's turn every frame
	_deck = g.find_child("Turntable_ROTATE", true, false) as Node3D
	turntable = Node3D.new()
	turntable.name = "CarOnDeck"
	turntable.position = Vector3(0, DECK_Y, 0)
	add_child(turntable)
	# the platform is turned here (not by the model's 20 s animation): slower, one way, by the buttons
	_anim = g.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _anim:
		_anim.stop()
		# the model's storm (rain sheets, lightning bolt) keeps running – without its turntable track
		if _anim.has_animation("Garage_Storm_20s"):
			var storm := (_anim.get_animation("Garage_Storm_20s") as Animation).duplicate() as Animation
			for t in range(storm.get_track_count() - 1, -1, -1):
				if str(storm.track_get_path(t)).ends_with("Turntable_ROTATE"):
					storm.remove_track(t)
			storm.loop_mode = Animation.LOOP_LINEAR
			var lib := AnimationLibrary.new()
			lib.add_animation("storm", storm)
			_anim.add_animation_library("menu", lib)
			_anim.play("menu/storm")
	if _deck:
		_deck_base = _deck.global_transform
	# a key light from the front for the paint, a red rim from the shutter side
	var key := SpotLight3D.new()
	key.position = Vector3(3.2, 4.0, 4.5)
	key.look_at_from_position(key.position, Vector3(0, 0.6, 0), Vector3.UP)
	key.spot_range = 14.0
	key.spot_angle = 38.0
	key.light_energy = 5.0
	key.shadow_enabled = true
	key.shadow_bias = 0.08
	key.shadow_normal_bias = 1.5
	add_child(key)
	var rim := OmniLight3D.new()
	rim.position = Vector3(0, 1.6, -5.5)
	rim.omni_range = 8.0
	rim.light_energy = 1.2
	rim.light_color = Color(1.0, 0.25, 0.25)
	add_child(rim)
	var probe := ReflectionProbe.new()
	probe.size = Vector3(17.4, 5.2, 20.4)
	probe.position = Vector3(0, 2.4, -3.8)
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	probe.box_projection = true
	probe.interior = true
	add_child(probe)
	cam = Camera3D.new()
	cam.fov = 58.0
	cam.current = true
	add_child(cam)
	rebuild_car()
	return true


## The office PC's screen: its corners in the world and the side it faces (towards the office door).
func _find_pc(g: Node3D) -> void:
	for node in g.find_children("Monitor_pixels*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		var bb := mi.mesh.get_aabb()
		var xf := mi.global_transform
		var lo := Vector3(1e9, 1e9, 1e9)
		var hi := -lo
		for k in 8:
			var p := xf * bb.get_endpoint(k)
			lo = lo.min(p)
			hi = hi.max(p)
		var size := hi - lo
		# thinnest axis: the screen's normal, towards the door
		var ax := 0 if size.x <= size.y and size.x <= size.z else (1 if size.y <= size.z else 2)
		var c := (lo + hi) * 0.5
		_pc_normal = Vector3.ZERO
		_pc_normal[ax] = signf(_door[ax] - c[ax]) if absf(_door[ax] - c[ax]) > 0.01 else 1.0
		_pc_corners = []
		for k in 8:
			var p := Vector3(lo.x if k & 1 == 0 else hi.x, lo.y if k & 2 == 0 else hi.y, lo.z if k & 4 == 0 else hi.z)
			p[ax] = c[ax]
			if not _pc_corners.has(p):
				_pc_corners.append(p)
		return


## The lights the menu can set: the honeycomb ceiling (its LED diffusers and work lights) and the
## neon ring round the platform (its strips get a material of their own, the wall neons keep theirs).
func _find_menu_lights(g: Node3D) -> void:
	for node in g.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		for si in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(si) as BaseMaterial3D
			if mat == null:
				continue
			if mat.resource_name == "Honeycomb_LED_diffuser":
				_ceiling_mat = mat
			elif str(mi.name).begins_with("Segmented_platform_neon"):
				if _platform_mat == null:
					_platform_mat = mat.duplicate() as BaseMaterial3D
				mi.set_surface_override_material(si, _platform_mat)
	if _ceiling_mat:
		_ceiling_emission = _ceiling_mat.emission_energy_multiplier
	if _platform_mat:
		_platform_emission = _platform_mat.emission_energy_multiplier
	for l in g.find_children("*", "Light3D", true, false):
		if str(l.name).begins_with("Honeycomb"):
			_ceiling_lights.append(l)
		elif str(l.name).begins_with("Neon") and str(l.get_path()).contains("Platform_Static"):
			_platform_lights.append(l)


## Ceiling and platform light from the settings ("menu_lights": ceiling / platform 0..2, colour).
func apply_menu_lights() -> void:
	var ml: Dictionary = Game.settings.get("menu_lights", {})
	var ceiling := float(ml.get("ceiling", 1.0))
	var platform := float(ml.get("platform", 1.0))
	var col := Color(str(ml.get("platform_color", "#ff0505")))
	if _ceiling_mat:
		_ceiling_mat.emission_energy_multiplier = _ceiling_emission * ceiling
	for l in _ceiling_lights:
		if is_instance_valid(l):
			l.light_energy = float(_light_base.get(l, 1.0)) * ceiling
			l.visible = ceiling > 0.01
	if _platform_mat:
		_platform_mat.emission = col
		_platform_mat.albedo_color = col.darkened(0.2)
		_platform_mat.emission_energy_multiplier = _platform_emission * platform
	for l in _platform_lights:
		if is_instance_valid(l):
			l.light_color = col
			l.light_energy = float(_light_base.get(l, 1.0)) * platform
			l.visible = platform > 0.01


## The camera stands in front of the open hall: the floor runs on out of the front and to the sides,
## and the front wall carries on left and right, so the edges of the view never show the void
## outside the model (same epoxy floor and concrete as the hall).
func _extend_room(g: Node3D) -> void:
	var floor_mat := _part_material(g, "Floor_surface*")
	var wall_mat := _part_material(g, "Front_facade_wing*")
	if floor_mat:
		# the epoxy repeats every 2.2 m in the hall; the rear street (z < -6.5) stays the model's
		_slab(Vector3(-30.0, -0.03, -6.5), Vector3(30.0, -0.01, 30.0), _world_tiled(floor_mat, 1.0 / 2.2))
	if wall_mat:
		var m := _world_tiled(wall_mat, 1.0 / 2.5)
		for side in [-1.0, 1.0]:
			_slab(Vector3(6.75 * side, 0.0, 6.3), Vector3(30.0 * side, 5.0, 6.5), m)
		# and the hall's sides carry on outwards past the front, closing the view to the sides
		_slab(Vector3(-30.0, 0.0, 6.5), Vector3(-6.75, 5.0, 30.0), m)


func _part_material(g: Node3D, pattern: String) -> Material:
	for node in g.find_children(pattern, "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh:
			return mi.get_active_material(0)
	return null


static func _world_tiled(mat: Material, per_metre: float) -> Material:
	if not (mat is BaseMaterial3D):
		return mat
	var m := (mat as BaseMaterial3D).duplicate() as BaseMaterial3D
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * per_metre
	return m


func _slab(a: Vector3, b: Vector3, mat: Material) -> void:
	var lo := Vector3(minf(a.x, b.x), minf(a.y, b.y), minf(a.z, b.z))
	var hi := Vector3(maxf(a.x, b.x), maxf(a.y, b.y), maxf(a.z, b.z))
	var box := BoxMesh.new()
	box.size = hi - lo
	var mi := MeshInstance3D.new()
	mi.name = "RoomExtension"
	mi.mesh = box
	mi.material_override = mat
	mi.position = (lo + hi) * 0.5
	add_child(mi)


static func _upper_sky_shader() -> Shader:
	var sh := Shader.new()
	sh.code = """shader_type sky;
uniform sampler2D panorama : source_color, filter_linear_mipmap, repeat_enable;
uniform float energy = 1.0;
void sky() {
	// equirectangular, as PanoramaSkyMaterial; below the horizon: night black
	vec3 c = texture(panorama, SKY_COORDS).rgb * energy;
	COLOR = EYEDIR.y >= 0.0 ? c : vec3(0.004, 0.004, 0.006);
}
"""
	return sh


func _turn_platform(delta: float) -> void:
	if manual_dir != 0.0:
		_target = NAN
		_angle += manual_dir * MANUAL_SPEED * delta
	elif not is_nan(_target):
		var left := _target - _angle
		_angle += minf(left, maxf(left * 2.5, 0.25) * delta)
		if left < 0.002:
			_angle = _target
	elif auto_spin:
		_angle += AUTO_SPEED * delta
	turntable.rotation.y = _angle
	if _deck:
		_deck.global_transform = Transform3D(Basis(Vector3.UP, _angle), Vector3.ZERO) * _deck_base


## Floor rectangle (x, z) of the hall in showroom coordinates.
func _hall_rect() -> Rect2:
	var f := FileAccess.open(GARAGE_INFO, FileAccess.READ)
	var info = JSON.parse_string(f.get_as_text()) if f else null
	if info is Dictionary and info.has("floor_min"):
		var st: Array = info.get("stage", [0, 0, 0])
		var mn: Array = info["floor_min"]
		var mx: Array = info["floor_max"]
		return Rect2(float(mn[0]) - float(st[0]), float(mn[2]) - float(st[2]), float(mx[0]) - float(mn[0]), float(mx[2]) - float(mn[2]))
	return Rect2(-15, -9, 27, 18)


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
	car.paint = Game.get_paint(Game.settings["paint"], Game.settings["custom_color"], str(Game.settings.get("paint_finish", "gloss")))
	turntable.add_child(car)
	car.headlights = headlights
	car.body.set_lights(headlights, false, false)


## L (the "lights" key) switches the car's headlights in the menu too – on by default.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("lights") and not event.is_echo() and car and is_instance_valid(car):
		headlights = not headlights
		car.headlights = headlights
		car.body.set_lights(headlights, false, false)
		get_viewport().set_input_as_handled()


func refresh_paint() -> void:
	if car:
		car.set_paint(Game.get_paint(Game.settings["paint"], Game.settings["custom_color"], str(Game.settings.get("paint_finish", "gloss"))))
		car.set_underglow(Game.get_underglow(car.car_id))


## The overview: from the front left, close to the car, turned towards the left wall (the street
## behind the shutter stays out of the picture). [position, look-at]
func _overview_cam() -> Array:
	var a := sin(_t * 0.08) * 0.12
	return [Vector3(sin(a) * 7.5 - 2.05, 2.2 + sin(_t * 0.17) * 0.15, cos(a) * 7.5), Vector3(-4.25, 0.9, -2.26)]


## Story mode: the camera flies from the car through the office door to the PC on the desk, until its
## screen fills the view (`story_arrived`); `leave_story` flies back (`story_left`).
func enter_story() -> bool:
	if not _workshop or _pc_corners.is_empty():
		return false
	story = true
	_fly_from = [cam.global_position, _cam_at]
	_fly_dir = 1
	_fly_t = 0.0
	return true


func leave_story() -> void:
	if not story:
		story_left.emit()
		return
	_fly_dir = -1
	_fly_t = 0.0


## The PC screen's corners (world), for the menu to lay its computer screen exactly over it.
func pc_screen_corners() -> Array:
	return _pc_corners


func _pc_centre() -> Vector3:
	var c := Vector3.ZERO
	for p in _pc_corners:
		c += p
	return c / float(_pc_corners.size())


## The screen fills ~85 % of the picture's height, seen square on.
func _pc_cam() -> Vector3:
	var lo := 1e9
	var hi := -1e9
	for p in _pc_corners:
		lo = minf(lo, (p as Vector3).y)
		hi = maxf(hi, (p as Vector3).y)
	var d := (hi - lo) / 0.85 * 0.5 / tan(deg_to_rad(cam.fov * 0.5))
	return _pc_centre() + _pc_normal * d


func _fly(delta: float) -> void:
	_fly_t = minf(_fly_t + delta / FLY_TIME, 1.0)
	var s := _fly_t * _fly_t * (3.0 - 2.0 * _fly_t)     # ease in and out
	s = s * s * (3.0 - 2.0 * s)                         # (softer still at both ends)
	var ov := _overview_cam()
	var start: Vector3 = _fly_from[0] if _fly_dir > 0 else ov[0]
	var start_at: Vector3 = _fly_from[1] if _fly_dir > 0 else ov[1]
	var centre := _pc_centre()
	# in the hall before the door, through the door, in front of the screen
	var door := Vector3(_door.x, _door.y, _door.z)
	var pts := [start, door + Vector3(2.4, 0.35, 0.3), door, door + (_pc_cam() - door) * 0.5, _pc_cam()]
	var u := s if _fly_dir > 0 else 1.0 - s
	var pos := _spline(pts, u)
	# the look turns from the car to the screen early, so the door comes up straight ahead
	var look_k := clampf(u * 1.8, 0.0, 1.0)
	look_k = look_k * look_k * (3.0 - 2.0 * look_k)
	var at := start_at.lerp(centre, look_k)
	cam.global_position = pos
	cam.look_at(at, Vector3.UP)
	_cam_pos = pos
	_cam_at = at
	if _fly_t >= 1.0:
		var dir := _fly_dir
		_fly_dir = 0
		if dir > 0:
			story_arrived.emit()
		else:
			story = false
			story_left.emit()


## Catmull-Rom through the points, u 0..1 over the whole path.
static func _spline(pts: Array, u: float) -> Vector3:
	var n := pts.size() - 1
	var f := clampf(u, 0.0, 1.0) * n
	var i := mini(int(f), n - 1)
	var t := f - i
	var p0: Vector3 = pts[maxi(i - 1, 0)]
	var p1: Vector3 = pts[i]
	var p2: Vector3 = pts[i + 1]
	var p3: Vector3 = pts[mini(i + 2, n)]
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t * t * t)


func _process(delta: float) -> void:
	_t += delta
	if _workshop:
		_turn_platform(delta)
		# overview: a slow sweep from outside the open front, the whole workshop and the shutter onto
		# the night street behind the car; the views come in close
		var pos := Vector3.ZERO
		var at := Vector3.ZERO
		if VIEWS.has(view):
			pos = VIEWS[view][1]
			at = VIEWS[view][2]
		else:
			var o := _overview_cam()
			pos = o[0]
			at = o[1]
		if _fly_dir != 0:
			_fly(delta)
			return
		if story:
			return
		var k := 1.0 - exp(-delta * 2.5)
		_cam_pos = _cam_pos.lerp(pos, k)
		_cam_at = _cam_at.lerp(at, k)
		cam.position = _cam_pos
		cam.look_at(_cam_at, Vector3.UP)
		return
	turntable.rotation.y = _t * 0.25
	var a := 0.6 + sin(_t * 0.12) * 0.25
	cam.position = Vector3(sin(a) * 8.0 - 1.7, 1.75 + sin(_t * 0.2) * 0.2, cos(a) * 8.0)
	cam.look_at(Vector3(-1.3, 0.75, 0), Vector3.UP)

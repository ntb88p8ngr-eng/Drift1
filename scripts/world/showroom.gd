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
const MenuStreet = preload("res://scripts/world/menu_street.gd")
const StoryPc = preload("res://scripts/ui/story_pc.gd")

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
const STORM_PARTS := ["Turntable_ROTATE", "GLB_Rain", "Storm_lightning", "Office_door_leaf", "Partially_closed_garage_shutter"]
const DECK_Y := 0.465            # top of the turntable deck (the old garage; the new one measures it)
const FOG_GREY := Color(0.2, 0.21, 0.23)
const PLATFORM_SCALE := 0.78     # the workshop's platform, a size smaller
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
var _office_door: Node3D         # its leaf (swings open for the story flight)
var _office_door_base := Transform3D.IDENTITY
var _door_open := 0.0
var _door_want := 0.0
const DOOR_HINGE := Vector3(-6.75, 0.0, 4.5)
const DOOR_SWING := 0.96         # from the model's ajar (~40°) to wide open (~95°), radians
var pc_viewport: SubViewport     # the PC's screen content (the story's chapter select)
var pc_ui: Control
var _pc_right := Vector3.BACK    # along the screen, left to right as seen from the front
var _pc_size := Vector2.ONE      # metres
var _ceiling_mat: BaseMaterial3D
var _platform_mat: BaseMaterial3D
var _ceiling_emission := 1.0
var _ceiling_albedo := Color.WHITE
var _platform_emission := 1.0
var _ceiling_lights: Array = []
var _platform_lights: Array = []
var _light_base := {}
var _ceiling_extra: Array = []    # [material, base emission] – the warm fixtures, dimmed with the ceiling
var _probe: ReflectionProbe       # the floor's mirror image: re-shot whenever the lights change
var _probe_t := -1.0
## the roller shutter: its lower edge (m above the floor), where it is going, the model's transform
const SHUTTER_TOP := 4.53
const SHUTTER_B0 := 2.91           # its lower edge in the model
const SHUTTER_DOWN := 0.02
const SHUTTER_UP := 2.91
var _shutter: Node3D
var _shutter_base := Transform3D.IDENTITY
var _shutter_b := 1.5
var _shutter_want := 1.5
var _shutter_paused := false

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


## The garage screen (choosing the car): from the front left corner, the lift and the engine on its
## stand in the back left, the whole car on its platform in the right half. [position, look at, fov]
const GARAGE_CAM := [Vector3(-2.25, 1.7, 4.0), Vector3(-2.0, 0.9, -1.0), 72.0]


## The rim view frames the front wheel facing the camera, whole, in the free right half of the
## screen (the menu covers the left): straight from the side, the wheel right of centre.
## [camera position, look at] or null.
func _wheel_frame():
	if car == null or not is_instance_valid(car) or car.body == null or car.body.wheel_nodes.size() < 2:
		return null
	var base: Vector3 = VIEWS["wheels"][1]
	var best: Node3D = null
	for i in 2:
		var w: Node3D = car.body.wheel_nodes[i][0]
		if best == null or w.global_position.distance_to(base) < best.global_position.distance_to(base):
			best = w
	var wp := best.global_position
	var side: Vector3 = car.global_transform.basis.x
	side = Vector3(side.x, 0, side.z).normalized()
	if side.dot(base - wp) < 0.0:
		side = -side
	var right := (-side).cross(Vector3.UP).normalized()
	var shift := right * -0.85
	return [wp + side * 2.7 + Vector3.UP * 0.25 + shift, wp + shift + Vector3.UP * 0.05]


## The shutter button: while it rolls, a press stops it where it is and the next one rolls it on the
## same way; standing at the top it goes down, at the bottom up (from part way: down).
func toggle_shutter() -> void:
	if _shutter_paused:
		_shutter_paused = false
		return
	if absf(_shutter_b - _shutter_want) > 0.001:
		_shutter_paused = true
		return
	_shutter_want = SHUTTER_UP if _shutter_b <= SHUTTER_DOWN + 0.01 else SHUTTER_DOWN


## The shutter with its lower edge at `b`: the slats squeezed up under the roll at the top.
func _set_shutter(b: float) -> void:
	_shutter_b = b
	if _shutter == null:
		return
	var k := (SHUTTER_TOP - b) / (SHUTTER_TOP - SHUTTER_B0)
	_shutter.global_transform = Transform3D(Basis.from_scale(Vector3(1.0, k, 1.0)), Vector3(0, SHUTTER_TOP * (1.0 - k), 0)) * _shutter_base


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
	env.ssr_enabled = Game.quality() >= 2
	env.ssr_max_steps = 48
	env.ssr_fade_in = 0.15
	env.ssr_fade_out = 2.0
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
	_epoxy_floor(g)
	_open_spanners(g)
	_replace_wall_tools(g)
	# the turning deck's skirt segments and their bolts ran through the static nameplate on the ring
	# ("MIDNIGHT DRIFT") all the time: gone
	for pat in ["*Turntable_skirt_segment*", "*Skirt_hex_bolt*"]:
		for n in g.find_children(pat, "Node3D", true, false):
			n.queue_free()
	# the roller shutter comes further down (from 2.9 m to 1.5 m): less of the street shows; the
	# menu's button rolls it right down or up (toggle_shutter)
	_shutter = g.find_child("*Partially_closed_garage_shutter*", true, false) as Node3D
	if _shutter:
		_shutter_base = _shutter.global_transform
		_set_shutter(_shutter_b)
	# a smaller platform (its turning deck and the fixed neon ring round it)
	for nm in ["Platform_Static", "Turntable_ROTATE"]:
		var pn := g.find_child(nm, true, false) as Node3D
		if pn:
			pn.global_transform = Transform3D(Basis.from_scale(Vector3(PLATFORM_SCALE, 1.0, PLATFORM_SCALE)), Vector3.ZERO) * pn.global_transform
	# the little suspension rods under the honeycomb panels (they read as spikes in the ceiling)
	for node in g.find_children("*LED_susp*", "MeshInstance3D", true, false):
		(node as MeshInstance3D).mesh = null
	# the model's lightning bolt (seen through the gate) stays hidden: the flashes light the hall
	for node in g.find_children("*Storm_lightning*", "Node3D", true, false):
		(node as Node3D).visible = false
	_extend_room(g)
	_find_menu_lights(g)
	_find_pc(g)
	_office_door = g.find_child("*Office_door_leaf*", true, false) as Node3D
	if _office_door:
		_office_door_base = _office_door.global_transform
	var asphalt := _material_named(g, "Wet_forecourt_asphalt")
	if asphalt is BaseMaterial3D:
		# the yard and the street outside: black asphalt with a little wet sheen (its texture's
		# metal channel made it a grey mirror of the sky)
		var am := asphalt as BaseMaterial3D
		# one even colour (no patches, no puddle texture)
		am.albedo_texture = null
		am.albedo_color = Color(0.035, 0.035, 0.038)
		am.normal_enabled = false
		am.roughness_texture = null
		am.metallic_texture = null
		if am is ORMMaterial3D:
			(am as ORMMaterial3D).orm_texture = null
		am.metallic = 0.0
		am.metallic_specular = 0.3
		am.roughness = 0.7
	_build_pc_screen()
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
		sky_mat.set_shader_parameter("horizon", FOG_GREY)
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
	# depth fog: the hall stays clear, the street behind the shutter vanishes into the mist
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_depth_begin = 16.0
	env.fog_depth_end = 70.0
	env.fog_depth_curve = 1.3
	env.fog_density = 0.97
	env.fog_light_color = FOG_GREY      # grey, rainy night (the sky fades into it at the horizon)
	env.fog_sky_affect = 0.55
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	# a cloudburst outside: heavy rain round the workshop, splashes on the street, lightning and
	# thunder (the room: x ±6.9, z ±6.5)
	var street := MenuStreet.new()
	street.name = "Street"
	add_child(street)
	street.build(_world_tiled(asphalt, 1.0 / 4.0) if asphalt else null)
	var storm_fx := MenuStorm.new()
	storm_fx.name = "Storm"
	add_child(storm_fx)
	# (no rain under the roofs beside the hall: the office annex on the left, the paint booth on the right)
	storm_fx.setup_heavy(env, Rect2(-6.9, -6.5, 13.8, 13.0), [Rect2(-10.3, 2.0, 3.7, 4.1), Rect2(6.6, -6.5, 7.1, 4.7)])
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
	turntable.position = Vector3(0, _deck_top(_deck) if _deck else DECK_Y, 0)
	add_child(turntable)
	# the platform is turned here (not by the model's 20 s animation): slower, one way, by the buttons
	_anim = g.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _anim:
		_anim.stop()
		# the model's storm (rain sheets, lightning bolt) keeps running – without its turntable track
		if _anim.has_animation("Garage_Storm_20s"):
			var storm := (_anim.get_animation("Garage_Storm_20s") as Animation).duplicate() as Animation
			for t in range(storm.get_track_count() - 1, -1, -1):
				var tp := str(storm.track_get_path(t))
				if tp.ends_with("Turntable_ROTATE") or tp.contains("Storm_lightning"):
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
	# (it hangs from the ceiling: the ceiling slider dims it too)
	_ceiling_lights.append(key)
	_light_base[key] = key.light_energy
	var rim := OmniLight3D.new()
	rim.position = Vector3(0, 1.6, -5.5)
	rim.omni_range = 8.0
	rim.light_energy = 1.2
	rim.light_color = Color(1.0, 0.25, 0.25)
	add_child(rim)
	var probe := ReflectionProbe.new()
	# (reaching over the extended floor in front of the hall too: outside the box the floor's
	# mirror image of the honeycomb came out stretched and smeared)
	probe.size = Vector3(17.4, 5.2, 24.0)
	probe.position = Vector3(0, 2.4, -2.0)
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	probe.box_projection = true
	probe.interior = true
	add_child(probe)
	_probe = probe
	apply_menu_lights()
	cam = Camera3D.new()
	cam.fov = 58.0
	cam.current = true
	add_child(cam)
	rebuild_car()
	return true


## The office PC's screen: its corners in the world and the side it faces (towards the office door).
func _find_pc(g: Node3D) -> void:
	for node in g.find_children("*Monitor_pixels*", "MeshInstance3D", true, false):
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


## The wrenches on the walls are ring spanners at both ends: the lower ring of each becomes an open
## jaw (a combination spanner) – the ring and its teeth go, a C-shaped jaw takes their place.
## The tools hanging on the back wall either side of the shutter: the model's spanners and
## screwdrivers give way to the uploaded models (assets/props/tools) – each new tool where the old
## one hung, as long as it, hanging straight down, flat against the wall.
const TOOL_DIR := "res://assets/props/tools/"
const WALL_TOOLS := [["Hanging_spanner_", ["combination_wrench", "adjustable_wrench", "wrench"]],
	["Hanging_screwdriver_", ["screwdriver", "flathead_screwdriver"]]]


func _replace_wall_tools(g: Node3D) -> void:
	var done := 0
	for wt in WALL_TOOLS:
		var prefix: String = wt[0]
		var kinds: Array = wt[1]
		var scenes: Array = []
		for k in kinds:
			if ResourceLoader.exists(TOOL_DIR + k + ".glb"):
				scenes.append(load(TOOL_DIR + k + ".glb"))
		if scenes.is_empty():
			continue
		var olds: Array = []
		for n in g.find_children(prefix + "*", "Node3D", true, false):
			# the tool itself (not its parts): exactly "<prefix>NNN"
			var nm := str(n.name)
			if nm.length() == prefix.length() + 3 and nm.substr(prefix.length()).is_valid_int():
				olds.append(n)
		olds.sort_custom(func(a, b): return (a as Node3D).global_position.x < (b as Node3D).global_position.x)
		# right of the shutter: a set of combination wrenches, small to large, side by side
		var spanners := prefix == "Hanging_spanner_" and ResourceLoader.exists(TOOL_DIR + "combination_wrench.glb")
		var set_scene: PackedScene = load(TOOL_DIR + "combination_wrench.glb") if spanners else null
		var right_n := 0
		for o in olds:
			if (o as Node3D).global_position.x > 0.0:
				right_n += 1
		var right_k := 0
		for i in olds.size():
			var old: Node3D = olds[i]
			var box := _tree_aabb(old)
			if box.size == Vector3.ZERO:
				continue
			var in_set: bool = spanners and old.global_position.x > 0.0
			old.get_parent().remove_child(old)
			old.free()
			var tool := (set_scene if in_set else scenes[i % scenes.size()] as PackedScene).instantiate() as Node3D
			if in_set:
				# 14 cm up to 30 cm, hanging from the same hook height (the box's top stays)
				var want := lerpf(0.14, 0.3, float(right_k) / maxf(right_n - 1, 1))
				right_k += 1
				var top := box.end.y
				box = AABB(Vector3(box.position.x, top - want, box.position.z), Vector3(box.size.x, want, box.size.z))
			add_child(tool)
			var mbox := _tree_aabb(tool)
			if mbox.size == Vector3.ZERO:
				tool.queue_free()
				continue
			# the model's long axis hangs down the wall, its flattest faces the room
			var ax := [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
			var ext := [mbox.size.x, mbox.size.y, mbox.size.z]
			var order := [0, 1, 2]
			order.sort_custom(func(a, b): return ext[a] > ext[b])
			var e_long: Vector3 = ax[order[0]]
			var e_mid: Vector3 = ax[order[1]]
			var e_flat: Vector3 = ax[order[2]]
			var m := Basis(e_mid, e_long, e_flat)        # columns: model axes that go to world x, y, z
			if m.determinant() < 0.0:
				m = Basis(-e_mid, e_long, e_flat)
			var r := m.transposed()
			var k: float = box.size.y / float(ext[order[0]])
			var b := r.scaled(Vector3(k, k, k))
			var c: Vector3 = box.get_center()
			# (its back a few millimetres off the wall board)
			var back: float = box.position.z
			var depth: float = float(ext[order[2]]) * k
			tool.global_transform = Transform3D(b, Vector3(c.x, c.y, back + depth * 0.5 + 0.005) - b * mbox.get_center())
			done += 1
	print("SHOWROOM: %d wall tools replaced" % done)


## Bounds of everything drawn under `n`, in world space.
static func _tree_aabb(n: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for c in [n] + n.find_children("*", "MeshInstance3D", true, false):
		if not (c is MeshInstance3D) or (c as MeshInstance3D).mesh == null:
			continue
		var mi := c as MeshInstance3D
		var bb: AABB = mi.global_transform * mi.get_aabb()
		box = bb if first else box.merge(bb)
		first = false
	return box


func _open_spanners(g: Node3D) -> void:
	var by_parent := {}
	for node in g.find_children("*Ring_spanner_head*", "MeshInstance3D", true, false):
		var p := node.get_parent()
		if not by_parent.has(p):
			by_parent[p] = []
		by_parent[p].append(node)
	for p in by_parent:
		var heads: Array = by_parent[p]
		if heads.size() < 2:
			continue
		heads.sort_custom(func(a, b): return _gaabb(a).get_center().y < _gaabb(b).get_center().y)
		var low: MeshInstance3D = heads[0]
		var high: MeshInstance3D = heads[heads.size() - 1]
		var lb := _gaabb(low)
		var hb := _gaabb(high)
		var mat := low.get_active_material(0)
		# its teeth: the ones nearer the lower head
		for t in (p as Node).find_children("*Ring_internal_tooth*", "MeshInstance3D", true, false):
			var tc := _gaabb(t).get_center()
			if tc.distance_to(lb.get_center()) < tc.distance_to(hb.get_center()):
				(t as MeshInstance3D).mesh = null
		low.mesh = null
		# the jaw: in the spanner's plane (its thinnest axis is the normal), open away from the shaft
		var size := lb.size
		var ax := 0 if size.x <= size.y and size.x <= size.z else (1 if size.y <= size.z else 2)
		var n := Vector3.ZERO
		n[ax] = 1.0
		var down := (lb.get_center() - hb.get_center()).normalized()
		var r := maxf(maxf(size.x, size.y), size.z) * 0.5
		var mi := MeshInstance3D.new()
		mi.mesh = _jaw_mesh(r, r * 0.55, maxf(size[ax], 0.004))
		mi.material_override = mat
		g.add_child(mi)
		var side := down.cross(n).normalized()
		mi.global_transform = Transform3D(Basis(side, -down, n), lb.get_center())


## Where the car stands: the top of the turning deck's surface.
static func _deck_top(deck: Node3D) -> float:
	var top := -1e9
	for node in deck.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		var b := _gaabb(mi)
		# only what lies in the middle (the deck), not something standing on its rim
		if Vector2(b.get_center().x, b.get_center().z).length() < 2.0 and b.end.y < 0.6:
			top = maxf(top, b.end.y)
	return top if top > -1e8 else DECK_Y


static func _gaabb(mi: MeshInstance3D) -> AABB:
	return mi.global_transform * mi.mesh.get_aabb() if mi.mesh else AABB(mi.global_position, Vector3.ZERO)


## An open-end jaw: a thick ring with a 80° gap towards -Y (local), `t` thick along Z.
static func _jaw_mesh(r_out: float, r_in: float, t: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := 20
	var a0 := deg_to_rad(-90.0 + 40.0)
	var a1 := deg_to_rad(270.0 - 40.0)
	for k in seg:
		var ta := lerpf(a0, a1, float(k) / seg)
		var tb := lerpf(a0, a1, float(k + 1) / seg)
		var oa := Vector3(cos(ta), sin(ta), 0)
		var ob := Vector3(cos(tb), sin(tb), 0)
		for z: float in [-t * 0.5, t * 0.5]:
			var zz := Vector3(0, 0, z)
			var nz := Vector3(0, 0, signf(z))
			var q := [oa * r_in + zz, oa * r_out + zz, ob * r_out + zz, ob * r_in + zz]
			_quad_n(st, q, nz, z < 0.0)
		_quad_n(st, [oa * r_out - Vector3(0, 0, t * 0.5), ob * r_out - Vector3(0, 0, t * 0.5), ob * r_out + Vector3(0, 0, t * 0.5), oa * r_out + Vector3(0, 0, t * 0.5)], (oa + ob).normalized(), false)
		_quad_n(st, [oa * r_in - Vector3(0, 0, t * 0.5), ob * r_in - Vector3(0, 0, t * 0.5), ob * r_in + Vector3(0, 0, t * 0.5), oa * r_in + Vector3(0, 0, t * 0.5)], -(oa + ob).normalized(), true)
	# the two flat jaw faces at the gap
	for a: float in [a0, a1]:
		var o := Vector3(cos(a), sin(a), 0)
		var nn := Vector3(-sin(a), cos(a), 0) * (1.0 if a == a0 else -1.0)
		_quad_n(st, [o * r_in - Vector3(0, 0, t * 0.5), o * r_out - Vector3(0, 0, t * 0.5), o * r_out + Vector3(0, 0, t * 0.5), o * r_in + Vector3(0, 0, t * 0.5)], nn, a == a0)
	return st.commit()


## A quad facing n (drawn both ways round so it never disappears).
static func _quad_n(st: SurfaceTool, q: Array, n: Vector3, _flip: bool) -> void:
	for idx in [[0, 1, 2, 0, 2, 3], [0, 2, 1, 0, 3, 2]]:
		for i in idx:
			st.set_normal(n)
			st.add_vertex(q[i])


## The hall's floor as a high-gloss epoxy coat: dark grey with fine flakes, a mirror-like clear coat.
func _epoxy_floor(g: Node3D) -> void:
	var mat := _part_material(g, "*Floor_surface*") as BaseMaterial3D
	if mat == null:
		return
	mat.albedo_texture = _flake_texture()
	mat.albedo_color = Color(1, 1, 1)
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	mat.uv1_scale = Vector3.ONE / 1.6
	# satin rather than a mirror: the honeycomb ceiling only shows as a soft, faint sheen in it
	mat.roughness = 0.32
	mat.metallic = 0.0
	mat.metallic_specular = 0.3
	mat.roughness_texture = null
	if mat is ORMMaterial3D:
		(mat as ORMMaterial3D).orm_texture = null
	mat.normal_enabled = false
	mat.clearcoat_enabled = true
	mat.clearcoat = 0.25
	mat.clearcoat_roughness = 0.35


## 1024² tile of epoxy: an even dark grey with a scatter of tiny light and dark flakes.
static func _flake_texture() -> ImageTexture:
	var n := 1024
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	img.fill(Color(0.17, 0.175, 0.19))
	var rng := RandomNumberGenerator.new()
	rng.seed = 4711
	var shades := [Color(0.36, 0.37, 0.4), Color(0.08, 0.08, 0.09), Color(0.26, 0.27, 0.3), Color(0.5, 0.5, 0.52)]
	for k in 26000:
		var x := rng.randi_range(0, n - 3)
		var y := rng.randi_range(0, n - 3)
		var c: Color = shades[rng.randi_range(0, shades.size() - 1)]
		img.set_pixel(x, y, c)
		if rng.randf() < 0.45:
			img.set_pixel(x + 1, y, c)
		if rng.randf() < 0.3:
			img.set_pixel(x, y + 1, c)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## The chapter select lives in a viewport of its own, shown on the monitor as a glowing screen.
func _build_pc_screen() -> void:
	if _pc_corners.is_empty():
		return
	var lo := Vector3(1e9, 1e9, 1e9)
	var hi := -lo
	for p in _pc_corners:
		lo = lo.min(p)
		hi = hi.max(p)
	_pc_right = (-_pc_normal).cross(Vector3.UP).normalized()
	var ext := hi - lo
	_pc_size = Vector2(absf(ext.dot(_pc_right)), ext.y)
	pc_viewport = SubViewport.new()
	pc_viewport.size = Vector2i(int(StoryPc.W), int(StoryPc.H))
	pc_viewport.disable_3d = true
	pc_viewport.gui_embed_subwindows = true
	pc_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(pc_viewport)
	pc_ui = StoryPc.new()
	pc_viewport.add_child(pc_ui)
	var quad := QuadMesh.new()
	quad.size = _pc_size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color.BLACK
	mat.emission_enabled = true
	mat.emission_texture = pc_viewport.get_texture()
	mat.emission_energy_multiplier = 1.1
	mat.roughness = 0.15
	var mi := MeshInstance3D.new()
	mi.name = "PcScreen"
	mi.mesh = quad
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_transform = Transform3D(Basis(_pc_right, Vector3.UP, _pc_normal), _pc_centre() + _pc_normal * 0.004)


## Where a screen point (mouse) hits the PC's screen, in the screen viewport's pixels (or null).
func pc_pixel(screen_pos: Vector2):
	if pc_viewport == null or cam == null:
		return null
	var o := cam.project_ray_origin(screen_pos)
	var d := cam.project_ray_normal(screen_pos)
	var c := _pc_centre()
	var den := d.dot(_pc_normal)
	if absf(den) < 1e-5:
		return null
	var t := (c - o).dot(_pc_normal) / den
	if t < 0.0:
		return null
	var p := o + d * t - c
	var u := p.dot(_pc_right) / _pc_size.x + 0.5
	var v := 0.5 - p.y / _pc_size.y
	return Vector2(u * StoryPc.W, v * StoryPc.H)


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
			elif mat.resource_name == "Warm_fixture" and not _ceiling_extra.any(func(e): return e[0] == mat):
				_ceiling_extra.append([mat, mat.emission_energy_multiplier, mat.albedo_color])
			elif str(mi.name).contains("Segmented_platform_neon"):
				if _platform_mat == null:
					_platform_mat = mat.duplicate() as BaseMaterial3D
				mi.set_surface_override_material(si, _platform_mat)
	if _ceiling_mat:
		_ceiling_emission = _ceiling_mat.emission_energy_multiplier
		_ceiling_albedo = _ceiling_mat.albedo_color
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
		# switched off it is a dark diffuser, not a pale one catching the other lights
		_ceiling_mat.albedo_color = Color(0.06, 0.06, 0.065).lerp(_ceiling_albedo, clampf(ceiling, 0.0, 1.0))
	for e in _ceiling_extra:
		(e[0] as BaseMaterial3D).emission_energy_multiplier = float(e[1]) * ceiling
		(e[0] as BaseMaterial3D).albedo_color = (e[2] as Color).darkened(0.85 * (1.0 - clampf(ceiling, 0.0, 1.0)))
	for l in _ceiling_lights:
		if is_instance_valid(l):
			l.light_energy = float(_light_base.get(l, 1.0)) * ceiling
			l.visible = ceiling > 0.01
	if _platform_mat:
		_platform_mat.emission = col
		_platform_mat.albedo_color = col.darkened(0.2 + 0.75 * (1.0 - clampf(platform, 0.0, 1.0)))
		_platform_mat.emission_energy_multiplier = _platform_emission * platform
	for l in _platform_lights:
		if is_instance_valid(l):
			l.light_color = col
			l.light_energy = float(_light_base.get(l, 1.0)) * platform
			l.visible = platform > 0.01
	# the floor mirrors what is lit now (not what was lit when the probe was first shot)
	if _probe:
		_probe_t = 0.35


## The camera stands in front of the open hall: the floor runs on out of the front and to the sides,
## and the front wall carries on left and right, so the edges of the view never show the void
## outside the model (same epoxy floor and concrete as the hall).
func _extend_room(g: Node3D) -> void:
	var floor_mat := _part_material(g, "*Floor_surface*")
	var wall_mat := _part_material(g, "*Front_facade_wing*")
	if floor_mat:
		# (the same flake epoxy as the hall; the rear street (z < -6.5) stays the model's)
		_slab(Vector3(-30.0, -0.03, -6.5), Vector3(30.0, -0.01, 30.0), _world_tiled(floor_mat, 1.0 / 1.6))
	if wall_mat:
		var m := _world_tiled(wall_mat, 1.0 / 2.5)
		for side in [-1.0, 1.0]:
			_slab(Vector3(6.75 * side, 0.0, 6.3), Vector3(30.0 * side, 5.0, 6.5), m)
		# and the hall's sides carry on outwards past the front, closing the view to the sides
		_slab(Vector3(-30.0, 0.0, 6.5), Vector3(-6.75, 5.0, 30.0), m)


func _material_named(g: Node3D, mat_name: String) -> Material:
	for node in g.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		for si in mi.mesh.get_surface_count():
			var m := mi.get_active_material(si)
			if m and m.resource_name == mat_name:
				return m
	return null


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
uniform vec3 horizon : source_color = vec3(0.2, 0.21, 0.23);   // the fog's colour
void sky() {
	// equirectangular, as PanoramaSkyMaterial; below the horizon: night black
	vec3 c = texture(panorama, SKY_COORDS).rgb * energy;
	// towards the horizon the photo fades into the fog's grey (the fogged ground ends in it: no
	// line where the ground stops); below it all fog
	COLOR = mix(horizon, c, smoothstep(0.02, 0.3, EYEDIR.y));
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


## The overview: from the front, close to the car, looking past it into the back right of the hall
## and out of the shutter onto the street. [position, look-at]
func _overview_cam() -> Array:
	var a := 0.2 + sin(_t * 0.08) * 0.12
	return [Vector3(sin(a) * 7.6 - 1.1, 2.4 + sin(_t * 0.17) * 0.15, cos(a) * 7.6), Vector3(-2.1, 1.0, -1.2)]


## Story mode: the camera flies from the car through the office door to the PC on the desk, until its
## screen fills the view (`story_arrived`); `leave_story` flies back (`story_left`).
func enter_story() -> bool:
	if not _workshop or _pc_corners.is_empty():
		return false
	story = true
	_door_want = 1.0         # the office door swings open while the camera comes
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
			_door_want = 0.0     # back out: the door swings to again
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
	if _shutter and not _shutter_paused and absf(_shutter_b - _shutter_want) > 0.001:
		# rolling at an even pace, easing in the last few centimetres
		var d := _shutter_want - _shutter_b
		_set_shutter(_shutter_b + signf(d) * minf(absf(d), delta * clampf(absf(d) * 3.0, 0.15, 0.7)))
	if _probe_t >= 0.0:
		# re-shot every frame while a slider moves, then frozen again
		_probe.update_mode = ReflectionProbe.UPDATE_ALWAYS
		_probe_t -= delta
		if _probe_t < 0.0:
			_probe.update_mode = ReflectionProbe.UPDATE_ONCE
	if _office_door and absf(_door_open - _door_want) > 0.001:
		# eased: quick at first, settling softly
		_door_open = move_toward(_door_open, _door_want, delta * (0.25 + 1.6 * absf(_door_want - _door_open)))
		var e := _door_open * _door_open * (3.0 - 2.0 * _door_open)
		_office_door.global_transform = Transform3D(Basis.IDENTITY, DOOR_HINGE) * Transform3D(Basis(Vector3.UP, e * DOOR_SWING), Vector3.ZERO) \
			* Transform3D(Basis.IDENTITY, -DOOR_HINGE) * _office_door_base
	if _workshop:
		_turn_platform(delta)
		# overview: a slow sweep from outside the open front, the whole workshop and the shutter onto
		# the night street behind the car; the views come in close
		var pos := Vector3.ZERO
		var at := Vector3.ZERO
		if VIEWS.has(view):
			pos = VIEWS[view][1]
			at = VIEWS[view][2]
			if view == "wheels":
				var wf = _wheel_frame()
				if wf != null:
					pos = wf[0]
					at = wf[1]
		elif view == "garage":
			pos = GARAGE_CAM[0]
			at = GARAGE_CAM[1]
		else:
			var o := _overview_cam()
			pos = o[0]
			at = o[1]
		# the garage shot is a little wider
		cam.fov = lerpf(cam.fov, float(GARAGE_CAM[2]) if view == "garage" else 58.0, 1.0 - exp(-delta * 2.5))
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

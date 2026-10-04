extends Node3D
## Behind the main-menu workshop: a short driveway from the shutter down to a street that runs past
## (left to right) – a kerb and pavement on the near side (dropped at the driveway), beyond the street
## the asphalt fades into a dark wet verge without a seam, grey-green verges, trees and
## bushes well back across the road, a few hydrants and one dim, flickering sodium street lamp;
## grey fog swallows the rest. The roadway is the model's own wet forecourt asphalt left uncovered
## (so street, driveway and yard are one surface).

const TreeFactory = preload("res://scripts/world/tree_factory.gd")
const TexKit = preload("res://scripts/util/tex_kit.gd")
const FlowerBeds = preload("res://scripts/world/city/flower_beds.gd")

const STREET_Z := -27.0    # the street's centre line (the shutter is at z = -6.5)
const LENGTH := 260.0      # along x, centred on the driveway
const HALF := 3.6          # half the carriageway
const WALK := 2.2          # pavement width
const KERB := 0.14
const STEP := 4.0
const DRIVE := 4.4         # half width of the driveway (and the dropped kerb)
const YARD_Z := -12.0      # the yard in front of the shutter ends here

var _lamp_light: SpotLight3D
var _lamp_glow: OmniLight3D
var _lamp_mat: StandardMaterial3D
var _flick := 0.0
var _flick_t := 0.0


## The street: s runs along it from its left end; lateral + is the near side (towards the garage).
static func centre(s: float) -> Vector3:
	return Vector3(s - LENGTH * 0.5, 0.0, STREET_Z)


static func side(_s: float) -> Vector3:
	return Vector3(0, 0, 1)


func at(s: float, lateral: float, y := 0.0) -> Vector3:
	return centre(s) + side(s) * lateral + Vector3(0, y, 0)


func build(_asphalt: Material) -> void:
	var walk_mat := TexKit.ground_material(Color(0.075, 0.075, 0.08), Color(0.09, 0.09, 0.095), Color(0.07, 0.07, 0.075), 0.7, 1.25)
	var grass_mat := TexKit.ground_material(Color(0.07, 0.08, 0.07), Color(0.085, 0.09, 0.075), Color(0.09, 0.085, 0.07), 0.9)
	var line_mat := TexKit.std(Color(0.85, 0.84, 0.8), 0.45)
	var mid := LENGTH * 0.5
	# grass: either side of the driveway between yard and pavement, and all beyond the far pavement
	var near_edge := STREET_Z + HALF + WALK
	_ground(Rect2(-300.0, near_edge, 300.0 - DRIVE - 0.4, YARD_Z - near_edge), grass_mat)
	_ground(Rect2(DRIVE + 0.4, near_edge, 300.0 - DRIVE - 0.4, YARD_Z - near_edge), grass_mat)
	# beyond the street no pavement: the ground fades from the wet asphalt into dark grass (no seam)
	_far_ground(STREET_Z - HALF + 0.3)
	# pavements with their kerbs (the near one dropped and open at the driveway)
	for sg in [-1.0, 1.0]:
		var spans: Array = [] if sg < 0.0 else [[0.0, mid - DRIVE], [mid + DRIVE, LENGTH]]
		for sp in spans:
			_wall(sg * HALF, 0.0, KERB, sp[0], sp[1], walk_mat, false)
			_strip(sg * HALF, sg * (HALF + WALK), KERB, sp[0], sp[1], walk_mat)
			_wall(sg * (HALF + WALK), 0.0, KERB, sp[0], sp[1], walk_mat, true)
		# edge lines
		var lines: Array = [[0.0, LENGTH]] if sg < 0.0 else [[0.0, mid - DRIVE - 1.0], [mid + DRIVE + 1.0, LENGTH]]
		# (over the yard's asphalt, which lies 2.6 cm up)
		for ln in lines:
			_strip(sg * (HALF - 0.32), sg * (HALF - 0.2), 0.04, ln[0], ln[1], line_mat)
	# the dropped kerb: a low ramp of pavement across the driveway mouth
	_strip(HALF, HALF + WALK, 0.03, mid - DRIVE, mid + DRIVE, walk_mat)
	var s := 3.0
	while s < LENGTH:
		_strip(-0.07, 0.07, 0.04, s, minf(s + 3.0, LENGTH), line_mat)
		s += 9.0
	# where the driveway meets the street: a give-way line of short dashes
	var g := mid - DRIVE
	while g < mid + DRIVE:
		_strip(HALF - 0.65, HALF - 0.4, 0.04, g, minf(g + 0.5, mid + DRIVE), line_mat)
		g += 0.9
	_plant()
	_yard_garden()
	_lamp(mid + 7.0, HALF + 0.55)
	_street_props()


const FAR_GROUND := """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled;
uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float edge_z = -30.0;     // where the street ends (the far ground fades in beyond it)
uniform float fade = 9.0;
varying vec3 wpos;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	float n1 = texture(noise_tex, wpos.xz * 0.05).r;
	float n2 = texture(noise_tex, wpos.xz * 0.43).r;
	float d = edge_z - wpos.z;
	// black asphalt on out to the trees (only a faint sheen: a shiny wet surface mirrored the pale sky
	// and turned it grey)
	vec3 asphalt = vec3(0.035, 0.035, 0.038) * (0.8 + 0.4 * n2) * (0.9 + 0.2 * n1);
	ALBEDO = asphalt;
	ROUGHNESS = mix(0.6, 0.9, smoothstep(0.35, 0.6, n1));
	SPECULAR = 0.25;
	// a ragged edge that fades in over a few metres
	ALPHA = smoothstep(0.0, fade, d + (n2 - 0.5) * 3.0 + (n1 - 0.5) * 4.0);
}
"""


func _far_ground(edge_z: float) -> void:
	var sh := Shader.new()
	sh.code = FAR_GROUND
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("noise_tex", TexKit.noise_texture(91, 0.03, false, 256))
	m.set_shader_parameter("edge_z", edge_z)
	var pm := PlaneMesh.new()
	pm.size = Vector2(600, 420)
	var mi := MeshInstance3D.new()
	mi.mesh = pm
	mi.material_override = m
	# its near end lies on the asphalt's edge (fully clear there)
	mi.position = Vector3(0, 0.015, edge_z - 210.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _ground(r: Rect2, mat: Material) -> void:
	var pm := PlaneMesh.new()
	pm.size = r.size.abs()
	var mi := MeshInstance3D.new()
	mi.mesh = pm
	mi.material_override = mat
	var c := r.abs().get_center()
	mi.position = Vector3(c.x, 0.02, c.y)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


## A flat strip between two lateral offsets, from s0 to s1 (UVs in metres, world-aligned).
func _strip(l0: float, l1: float, y: float, s0: float, s1: float, mat: Material) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var s := s0
	while s < s1 - 0.001:
		var e := minf(s + STEP, s1)
		var a0 := at(s, minf(l0, l1), y)
		var a1 := at(s, maxf(l0, l1), y)
		var b0 := at(e, minf(l0, l1), y)
		var b1 := at(e, maxf(l0, l1), y)
		# both windings: whichever is the front, it faces up
		for p in [a0, b0, b1, a0, b1, a1, a0, b1, b0, a0, a1, b1]:
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(p.x, p.z))
			st.add_vertex(p)
		s = e
	_add_mesh(st, mat)


## An upright face along the road (a kerb), lit as facing the centre (or away with `out`).
func _wall(l: float, y0: float, y1: float, s0: float, s1: float, mat: Material, out: bool) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var s := s0
	while s < s1 - 0.001:
		var e := minf(s + STEP, s1)
		var a0 := at(s, l, y0)
		var a1 := at(s, l, y1)
		var b0 := at(e, l, y0)
		var b1 := at(e, l, y1)
		var n := side(s) * (-signf(l) if not out else signf(l))
		for p in [a0, b1, b0, a0, a1, b1, a0, b0, b1, a0, b1, a1]:
			st.set_normal(n)
			st.set_uv(Vector2(p.x + p.z, p.y))
			st.add_vertex(p)
		s = e
	_add_mesh(st, mat)


func _add_mesh(st: SurfaceTool, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


## Trees well back across the street (and some far off to the sides on the near side), bushes
## along the far verge – dark and grey-green in the rain, the fog takes most of their colour.
func _plant() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2207
	var trees := [TreeFactory.deciduous(11, 0.45), TreeFactory.deciduous(23, 0.45), TreeFactory.oak(5, 0.45)]
	var far_trees := [TreeFactory.deciduous(41, 0.3), TreeFactory.oak(17, 0.3)]
	var bushes := [TreeFactory.bush(3), TreeFactory.bush(8), TreeFactory.shrub(4)]
	var items := {}
	for m in trees + far_trees + bushes:
		items[m] = []
	var x := -LENGTH * 0.5 + rng.randf_range(0.0, 6.0)
	while x < LENGTH * 0.5:
		# a loose row 9-16 m behind the far pavement, a second one further back
		items[trees[rng.randi() % trees.size()]].append(_xf_at(Vector3(x, 0.02, STREET_Z - HALF - WALK - rng.randf_range(9.0, 16.0)), rng, 0.9, 1.2))
		items[far_trees[rng.randi() % far_trees.size()]].append(_xf_at(Vector3(x + rng.randf_range(-4, 4), 0.02, STREET_Z - HALF - WALK - rng.randf_range(24.0, 45.0)), rng, 1.0, 1.4))
		if rng.randf() < 0.6:
			items[bushes[rng.randi() % bushes.size()]].append(_xf_at(Vector3(x + rng.randf_range(-3, 3), 0.02, STREET_Z - HALF - WALK - rng.randf_range(2.0, 6.0)), rng, 0.7, 1.2))
		x += rng.randf_range(8.0, 13.0)
	# near side: only far out to the left and right of the yard
	for sg in [-1.0, 1.0]:
		var nx := 22.0
		while nx < 90.0:
			items[trees[rng.randi() % trees.size()]].append(_xf_at(Vector3(sg * nx, 0.02, rng.randf_range(STREET_Z + HALF + WALK + 4.0, YARD_Z - 3.0)), rng, 0.85, 1.15))
			nx += rng.randf_range(10.0, 16.0)
	for m in items:
		_instances(m, items[m], rng)


## Beside the driveway: a row of big bushes on the left, a flower field on the right.
func _yard_garden() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4411
	var near_edge := STREET_Z + HALF + WALK
	var bushes := [TreeFactory.bush(3), TreeFactory.bush(8), TreeFactory.bush(12)]
	var items := {}
	for m in bushes:
		items[m] = []
	var x := -DRIVE - 2.2
	while x > -17.0:
		var z := rng.randf_range(YARD_Z - 2.5, YARD_Z - 1.2)
		items[bushes[rng.randi() % bushes.size()]].append(_xf_at(Vector3(x, 0.03, z), rng, 1.3, 1.8))
		if rng.randf() < 0.6:
			items[bushes[rng.randi() % bushes.size()]].append(_xf_at(Vector3(x + rng.randf_range(-0.6, 0.6), 0.03, z - rng.randf_range(1.6, 3.0)), rng, 1.0, 1.4))
		x -= rng.randf_range(1.6, 2.4)
	for m in items:
		_garden_instances(m, items[m], rng)
	var beds := FlowerBeds.new()
	beds.name = "FlowerField"
	add_child(beds)
	var w := 12.0
	var d := (YARD_Z - 1.0) - (near_edge + 1.0)
	beds.add_bed(Vector3(DRIVE + 2.6 + w * 0.5, 0.0, (YARD_Z - 1.0 + near_edge + 1.0) * 0.5), Vector2(w, absf(d)), 0.0, rng)
	beds.build(null)


## Garden bushes: a fresher green than the dark trees out in the rain.
func _garden_instances(mesh: Mesh, xfs: Array, rng: RandomNumberGenerator) -> void:
	if xfs.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])
		var g := rng.randf_range(0.7, 0.9)
		mm.set_instance_custom_data(i, Color(g * 0.8, g, g * 0.75, 1.0))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	add_child(mmi)


func _xf_at(p: Vector3, rng: RandomNumberGenerator, k0: float, k1: float) -> Transform3D:
	var k := rng.randf_range(k0, k1)
	return Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(k, k, k)), p)


func _instances(mesh: Mesh, xfs: Array, rng: RandomNumberGenerator) -> void:
	if xfs.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])
		# dark and grey-green: night, rain, fog
		var g := rng.randf_range(0.38, 0.5)
		mm.set_instance_custom_data(i, Color(g * rng.randf_range(0.95, 1.05), g, g * rng.randf_range(0.95, 1.05), 1.0))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	add_child(mmi)


const PACK := "res://assets/props/street_pack/"
## The street prop pack (uploaded): where the garage's opening shows them – the yard, the driveway's
## mouth and the near pavement. [model, x, z, y (on the pavement or the ground), turn]
## (signs face +Z: towards the garage, i.e. the cars coming out of the driveway)
const PROPS := [
	["fire_hydrant_red", 7.4, -21.5, KERB, 0.4],
	["sign_one_way", 14.5, -22.0, KERB, 0.0],
	["pedestrian_signal", -5.4, -21.9, KERB, 0.0],
	["sign_pedestrian_crossing", -8.2, -22.0, KERB, 0.0],
	["sign_street_names", -12.5, -21.8, KERB, 0.25],
	["traffic_light_overhead", -17.5, -21.8, KERB, PI * 0.5],
	["sign_speed_30", -22.0, -22.0, KERB, 0.0],
	["fire_hydrant_yellow", -6.2, -9.4, 0.0, -0.6],
	["sign_yield", 6.3, -13.0, 0.0, 0.0],
]

var _signals: Array = []     # [[red, amber, green] materials, light] per traffic light
var _signal_t := 0.0


func _street_props() -> void:
	for p in PROPS:
		var path: String = PACK + str(p[0]) + ".glb"
		if not ResourceLoader.exists(path):
			continue
		var scene := load(path) as PackedScene
		if scene == null:
			continue
		var n := scene.instantiate() as Node3D
		add_child(n)
		n.global_transform = Transform3D(Basis(Vector3.UP, float(p[4])), Vector3(float(p[1]), float(p[3]), float(p[2])))
		if str(p[0]).begins_with("traffic_light") or str(p[0]) == "pedestrian_signal":
			_signal_lenses(n)


## A traffic light's lenses get their own materials that light up in turn (red, green, amber), with
## a little coloured light in front of them.
func _signal_lenses(n: Node3D) -> void:
	var mats := {}
	var lens_pos := Vector3.ZERO
	for node in n.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		for si in mi.mesh.get_surface_count():
			var m := mi.get_active_material(si)
			if m == null or not m.resource_name.begins_with("lens_") or m.resource_name == "lens_off":
				continue
			var key := m.resource_name.trim_prefix("lens_")
			if not mats.has(key):
				var own := (m as BaseMaterial3D).duplicate() as BaseMaterial3D if m is BaseMaterial3D else StandardMaterial3D.new()
				own.emission_enabled = true
				mats[key] = own
			mi.set_surface_override_material(si, mats[key])
			lens_pos = mi.global_transform * mi.mesh.get_aabb().get_center()
	if mats.is_empty():
		return
	var l := OmniLight3D.new()
	l.omni_range = 3.5
	l.light_energy = 0.0
	add_child(l)
	l.global_position = lens_pos + Vector3(0, 0, 0.4)
	_signals.append([mats, l])
	_cycle_signals(0.0)


const SIGNAL_COLS := {"red": Color(1.0, 0.12, 0.08), "amber": Color(1.0, 0.6, 0.05), "green": Color(0.2, 1.0, 0.45)}


func _cycle_signals(t: float) -> void:
	# 9 s red, 7 s green, 2 s amber
	var ph := fmod(t, 18.0)
	var on := "red" if ph < 9.0 else ("green" if ph < 16.0 else "amber")
	for sg in _signals:
		var mats: Dictionary = sg[0]
		for key in mats:
			var m: BaseMaterial3D = mats[key]
			var lit: bool = key == on
			m.emission = SIGNAL_COLS.get(key, Color.WHITE)
			m.emission_energy_multiplier = 3.0 if lit else 0.05
		var l: OmniLight3D = sg[1]
		l.light_color = SIGNAL_COLS[on]
		l.light_energy = 0.6


## One old street lamp: a pole with an arm over the road and a weak orange sodium light.
func _lamp(s: float, l: float) -> void:
	var foot := at(s, l, KERB)
	var inward := -side(s) * signf(l)
	var root := Node3D.new()
	root.name = "StreetLamp"
	add_child(root)
	root.global_position = foot
	root.look_at(foot + inward, Vector3.UP)     # -Z towards the road
	var metal := TexKit.std(Color(0.16, 0.17, 0.18), 0.55, 0.6)
	var pole := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.06
	cyl.bottom_radius = 0.09
	cyl.height = 6.2
	pole.mesh = cyl
	pole.material_override = metal
	pole.position = Vector3(0, 3.1, 0)
	root.add_child(pole)
	var arm := MeshInstance3D.new()
	var bx := BoxMesh.new()
	bx.size = Vector3(0.08, 0.08, 1.6)
	arm.mesh = bx
	arm.material_override = metal
	arm.position = Vector3(0, 6.1, -0.75)
	root.add_child(arm)
	var head := MeshInstance3D.new()
	var hb := BoxMesh.new()
	hb.size = Vector3(0.28, 0.12, 0.55)
	head.mesh = hb
	head.material_override = metal
	head.position = Vector3(0, 6.02, -1.5)
	root.add_child(head)
	var lens := MeshInstance3D.new()
	var lb := BoxMesh.new()
	lb.size = Vector3(0.22, 0.02, 0.45)
	lens.mesh = lb
	_lamp_mat = TexKit.emissive(Color(1.0, 0.58, 0.25), 2.2)
	lens.material_override = _lamp_mat
	lens.position = Vector3(0, 5.95, -1.5)
	root.add_child(lens)
	_lamp_light = SpotLight3D.new()
	_lamp_light.light_color = Color(1.0, 0.6, 0.28)
	_lamp_light.light_energy = 1.6
	_lamp_light.spot_range = 13.0
	_lamp_light.spot_angle = 52.0
	_lamp_light.spot_attenuation = 0.8
	_lamp_light.position = Vector3(0, 5.9, -1.5)
	_lamp_light.rotation = Vector3(-PI * 0.5, 0, 0)
	root.add_child(_lamp_light)
	_lamp_glow = OmniLight3D.new()
	_lamp_glow.light_color = _lamp_light.light_color
	_lamp_glow.light_energy = 0.25
	_lamp_glow.omni_range = 4.0
	_lamp_glow.position = Vector3(0, 5.7, -1.5)
	root.add_child(_lamp_glow)


## The old lamp now and then flickers for a moment.
func _process(delta: float) -> void:
	if not _signals.is_empty():
		var before := _signal_t
		_signal_t += delta
		if int(before * 4.0) != int(_signal_t * 4.0):
			_cycle_signals(_signal_t)
	if _lamp_light == null:
		return
	_flick_t -= delta
	if _flick_t <= 0.0:
		_flick = randf_range(0.15, 0.6) if randf() < 0.35 else 0.0
		_flick_t = randf_range(0.04, 0.12) if _flick > 0.0 else randf_range(1.5, 6.0)
	var k := 1.0 - _flick
	_lamp_light.light_energy = 1.6 * k
	_lamp_glow.light_energy = 0.25 * k
	_lamp_mat.emission_energy_multiplier = 2.2 * k

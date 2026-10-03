extends Node3D
## The street behind the main-menu workshop: from the shutter a two-lane road runs away and bends
## gently off into the fog – kerbs and pavements, grass verges with trees and bushes, a few fire
## hydrants and one dim, slightly flickering sodium street lamp. Seen through the open shutter.

const TreeFactory = preload("res://scripts/world/tree_factory.gd")
const PropMeshes = preload("res://scripts/world/prop_meshes.gd")
const TexKit = preload("res://scripts/util/tex_kit.gd")

const START_Z := -9.0      # where the road leaves the forecourt (the shutter is at z = -6.5)
const LENGTH := 200.0
const HALF := 3.6          # half the carriageway
const WALK := 2.2          # pavement width
const KERB := 0.14
const STEP := 2.0

var _lamp_light: SpotLight3D
var _lamp_glow: OmniLight3D
var _lamp_mat: StandardMaterial3D
var _flick := 0.0
var _flick_t := 0.0


## Centre line: straight out of the yard, then a slow bend to the right.
static func centre(s: float) -> Vector3:
	var b := maxf(0.0, s - 30.0)
	return Vector3(0.0009 * b * b, 0.0, START_Z - s)


static func side(s: float) -> Vector3:
	var b := maxf(0.0, s - 30.0)
	var t := Vector3(0.0018 * b, 0.0, -1.0).normalized()
	return Vector3(-t.z, 0.0, t.x)      # +x at the start: the right-hand side looking out


func at(s: float, lateral: float, y := 0.0) -> Vector3:
	return centre(s) + side(s) * lateral + Vector3(0, y, 0)


func build(asphalt: Material) -> void:
	var road_mat := asphalt
	if road_mat == null:
		road_mat = TexKit.std(Color(0.05, 0.05, 0.055), 0.35)
	var walk_mat := TexKit.ground_material(Color(0.3, 0.3, 0.31), Color(0.36, 0.36, 0.37), Color(0.26, 0.26, 0.27), 0.6, 1.25)
	var grass_mat := TexKit.ground_material(Color(0.05, 0.08, 0.035), Color(0.07, 0.1, 0.04), Color(0.09, 0.08, 0.05), 0.85)
	var line_mat := TexKit.std(Color(0.78, 0.76, 0.66), 0.45)
	# the ground beyond the forecourt: verges, fields – fog swallows the far end
	_quad_ground(grass_mat)
	_strip(-HALF, HALF, 0.03, 0.0, LENGTH, road_mat)
	for sg in [-1.0, 1.0]:
		# edge line, kerb face, pavement, the pavement's outer edge
		_strip(sg * (HALF - 0.32), sg * (HALF - 0.2), 0.034, 0.0, LENGTH, line_mat)
		_wall(sg * HALF, 0.03, KERB, 2.0, LENGTH, walk_mat, false)
		_strip(sg * HALF, sg * (HALF + WALK), KERB, 2.0, LENGTH, walk_mat)
		_wall(sg * (HALF + WALK), 0.02, KERB, 2.0, LENGTH, walk_mat, true)
	var s := 4.0
	while s < LENGTH:
		_strip(-0.07, 0.07, 0.034, s, minf(s + 3.0, LENGTH), line_mat)
		s += 9.0
	_plant()
	_hydrants()
	_lamp(22.0, -(HALF + 0.55))


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


## Grass from the end of the yard outwards, under everything (the road and pavements lie on it).
func _quad_ground(mat: Material) -> void:
	var pm := PlaneMesh.new()
	pm.size = Vector2(600, 400)
	var mi := MeshInstance3D.new()
	mi.mesh = pm
	mi.material_override = mat
	mi.position = Vector3(0, 0.02, START_Z - 3.0 - 200.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _add_mesh(st: SurfaceTool, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


## Two loose rows of broadleaf trees on the verges, bushes and shrubs between them.
func _plant() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2207
	var near_trees := [TreeFactory.deciduous(11, 0.55), TreeFactory.deciduous(23, 0.55), TreeFactory.oak(5, 0.55)]
	var far_trees := [TreeFactory.deciduous(41, 0.3), TreeFactory.oak(17, 0.3)]
	var bushes := [TreeFactory.bush(3), TreeFactory.bush(8), TreeFactory.shrub(4), TreeFactory.shrub(9)]
	var items := {}
	for m in near_trees + far_trees + bushes:
		items[m] = []
	for sg in [-1.0, 1.0]:
		var s := 9.0 + rng.randf_range(0.0, 4.0)
		while s < LENGTH:
			if absf(s - 22.0) > 4.0 or sg > 0.0:     # (a gap round the lamp)
				var l: float = sg * (HALF + WALK + rng.randf_range(2.5, 5.5))
				items[near_trees[rng.randi_range(0, near_trees.size() - 1)]].append(_xf(s, l, rng, 0.85, 1.15))
			s += rng.randf_range(7.0, 11.0)
		s = 14.0 + rng.randf_range(0.0, 6.0)
		while s < LENGTH:
			var l2: float = sg * (HALF + WALK + rng.randf_range(10.0, 22.0))
			items[far_trees[rng.randi_range(0, far_trees.size() - 1)]].append(_xf(s, l2, rng, 0.9, 1.3))
			s += rng.randf_range(6.0, 12.0)
		s = 6.0
		while s < LENGTH:
			var l3: float = sg * (HALF + WALK + rng.randf_range(0.8, 9.0))
			items[bushes[rng.randi_range(0, bushes.size() - 1)]].append(_xf(s, l3, rng, 0.7, 1.4))
			s += rng.randf_range(2.5, 6.0)
	for m in items:
		_instances(m, items[m], rng)


func _xf(s: float, l: float, rng: RandomNumberGenerator, k0: float, k1: float) -> Transform3D:
	var k := rng.randf_range(k0, k1)
	return Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(k, k, k)), at(s, l, 0.02))


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
		var g := rng.randf_range(0.75, 1.0)
		mm.set_instance_custom_data(i, Color(g * rng.randf_range(0.85, 1.0), g, g * rng.randf_range(0.8, 1.0), 1.0))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	add_child(mmi)


## Three hydrants on the pavements (the prop shader takes its tint from the instance data).
func _hydrants() -> void:
	var xfs := []
	for h in [[14.0, 1.0], [41.0, -1.0], [78.0, 1.0]]:
		var l: float = float(h[1]) * (HALF + 0.5)
		xfs.append(Transform3D(Basis(Vector3.UP, randf() * TAU), at(float(h[0]), l, KERB)))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = PropMeshes.get_mesh("hydrant")
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])
		mm.set_instance_custom_data(i, Color(1, 1, 1, 1))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	add_child(mmi)


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

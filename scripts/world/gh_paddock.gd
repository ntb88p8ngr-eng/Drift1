extends Node3D
## Grüne Hölle, 24h weekend at the start/finish: two big covered grandstands full of people on one
## side of the straight, a Ferris wheel with food stalls on the other.

const MeshKit = preload("res://scripts/util/mesh_kit.gd")
const Props = preload("res://scripts/world/prop_meshes.gd")
const Crowd = preload("res://scripts/world/crowd.gd")
const Colliders = preload("res://scripts/util/colliders.gd")
const TexKit = preload("res://scripts/util/tex_kit.gd")

const AREA_FROM := -230.0     # the start/finish area: progress from the start line (m)
const AREA_TO := 130.0
const TEAMS := [Color(0.85, 0.1, 0.08), Color(0.1, 0.3, 0.8), Color(0.95, 0.75, 0.1), Color(0.1, 0.55, 0.3),
	Color(0.95, 0.95, 0.95), Color(0.1, 0.1, 0.12), Color(0.95, 0.45, 0.05), Color(0.45, 0.15, 0.65), Color(0.2, 0.7, 0.85)]

var track
var terrain
var scenery
var festival          # for the shared person / instancing helpers
var rng := RandomNumberGenerator.new()
var fair_side := -1.0  # the Ferris wheel side (the grandstands are opposite)
var _lat := 0.0       # lateral offset of the fair (Ferris wheel side) from the track centreline
var _wheel: Node3D
var _wheel_bulbs: StandardMaterial3D
var _night_mats: Array = []


func build(p_track, p_terrain, p_scenery, p_festival) -> void:
	track = p_track
	terrain = p_terrain
	scenery = p_scenery
	festival = p_festival
	rng.seed = 2424
	# the old start grandstand stands on the gantry's +X side: the fair goes on the other side
	var s0: int = track.start_index
	fair_side = -1.0 if (track.gantry_xf.basis.x as Vector3).dot(track.rights[s0]) > 0.0 else 1.0
	var max_off := 0.0
	for p in range(int(AREA_FROM), int(AREA_TO), 4):
		var i: int = track.index_at(p)
		max_off = maxf(max_off, float(track.off_left[i] if fair_side < 0.0 else track.off_right[i]))
	_lat = max_off + 7.5
	await Game.load_tick()
	_grandstand(70.0, 64.0)
	_grandstand(-120.0, 56.0)
	await Game.load_tick()
	_ferris_wheel()


## Plain vertex-colour material (the prop shader takes its tint from MultiMesh data, which a single
## mesh doesn't have); alpha < 1 marks metal like in the props.
var _vc_mat: StandardMaterial3D


func _vc() -> StandardMaterial3D:
	if _vc_mat == null:
		_vc_mat = StandardMaterial3D.new()
		_vc_mat.vertex_color_use_as_albedo = true
		_vc_mat.roughness = 0.75
	return _vc_mat


func set_night(n: float) -> void:
	for m in _night_mats:
		(m[0] as StandardMaterial3D).emission_energy_multiplier = lerpf(float(m[1]), float(m[2]), n)


func _process(delta: float) -> void:
	if _wheel:
		_wheel.rotate_object_local(Vector3(0, 0, 1), delta * 0.06)
		for g in _wheel.get_children():
			if g.name.begins_with("Gondola"):
				# gondolas hang straight down whatever the wheel's angle
				(g as Node3D).global_basis = Basis(Vector3.UP, _wheel.get_parent().global_rotation.y)


## Point beside the track at `progress`, `lat` metres from the centreline on the pit side (or the other).
func _at(progress: float, lat: float, side := 0.0) -> Vector3:
	var i: int = track.index_at(progress)
	var s := fair_side if side == 0.0 else side
	var p: Vector3 = track.samples[i] + track.rights[i] * s * lat
	return p


func _road_y(progress: float) -> float:
	return float(track.samples[track.index_at(progress)].y)


# ---------------------------------------------------------------------------
# Grandstands opposite the pits
# ---------------------------------------------------------------------------
func _grandstand(centre_p: float, length: float) -> void:
	var side := -fair_side
	var i0: int = track.index_at(centre_p)
	var off: float = float(track.off_left[i0] if side < 0.0 else track.off_right[i0])
	var a := _at(centre_p - length * 0.5, off + 5.0, side)
	var b := _at(centre_p + length * 0.5, off + 5.0, side)
	var along := b - a
	along.y = 0.0
	along = along.normalized()
	var out: Vector3 = Vector3.UP.cross(along).normalized()
	if out.dot(_at(centre_p, off + 6.0, side) - _at(centre_p, off + 5.0, side)) < 0.0:
		out = -out
	var base := (a + b) * 0.5
	base.y = _road_y(centre_p)
	var rows := 16
	var depth := rows * 0.85 + 2.0
	for q in range(-int(length * 0.5) - 4, int(length * 0.5) + 5, 8):
		terrain.level_to(base + along * q + out * depth * 0.5, depth * 0.5 + 3.0, 6.0, base.y - 0.05)
	var fr := Basis(along, Vector3.UP, out)
	var xf := Transform3D(fr, base)
	var st := MeshKit.new_st()
	var conc := Color(0.62, 0.62, 0.6)
	var seat_cols := [Color(0.1, 0.25, 0.65), Color(0.85, 0.1, 0.1), Color(0.95, 0.95, 0.95)]
	var people_xf: Array = []
	for r in rows:
		var z := 1.5 + r * 0.85
		var y := 0.6 + r * 0.55
		MeshKit.box(st, xf * Transform3D(Basis.IDENTITY, Vector3(0, y * 0.5, z)), Vector3(length, y, 0.85), conc)
		MeshKit.box(st, xf * Transform3D(Basis.IDENTITY, Vector3(0, y + 0.2, z + 0.15)), Vector3(length, 0.4, 0.4), seat_cols[(r / 4) % seat_cols.size()])
		var x := -length * 0.5 + 0.5
		while x < length * 0.5 - 0.5:
			if rng.randf() < 0.82:
				people_xf.append(xf * Vector3(x + rng.randf_range(-0.1, 0.1), y, z - 0.05))
			x += rng.randf_range(0.6, 0.75)
	# back wall, roof on columns, a front fence and team banners
	MeshKit.box(st, xf * Transform3D(Basis.IDENTITY, Vector3(0, 6.0, depth)), Vector3(length, 12.0, 0.4), conc)
	for x in range(-int(length * 0.5), int(length * 0.5) + 1, 12):
		MeshKit.box(st, xf * Transform3D(Basis.IDENTITY, Vector3(x, 7.5, depth - 0.4)), Vector3(0.5, 15.0, 0.5), Color(0.3, 0.3, 0.33, 0.5))
	MeshKit.box(st, xf * Transform3D(Basis.from_euler(Vector3(0.12, 0, 0)), Vector3(0, 14.5, depth * 0.55)), Vector3(length + 2.0, 0.35, depth + 3.0), Color(0.88, 0.88, 0.9))
	MeshKit.box(st, xf * Transform3D(Basis.IDENTITY, Vector3(0, 0.6, 0.5)), Vector3(length, 1.2, 0.2), Color(0.3, 0.3, 0.33))
	for k in int(length / 8.0):
		MeshKit.box(st, xf * Transform3D(Basis.IDENTITY, Vector3(-length * 0.5 + 4.0 + k * 8.0, 0.65, 0.38)), Vector3(6.5, 0.9, 0.04), TEAMS[k % TEAMS.size()])
	var mi := MeshInstance3D.new()
	mi.mesh = MeshKit.commit(st, _vc())
	mi.name = "Grandstand"
	add_child(mi)
	Colliders.add_trimesh(mi)
	for pp in people_xf:
		festival._person_raw(pp, base - out * 30.0 + along * rng.randf_range(-20.0, 20.0))
	for q in range(-int(length * 0.5), int(length * 0.5) + 1, 9):
		scenery.occupy(base + along * q + out * depth * 0.5, 9.5)


# ---------------------------------------------------------------------------
# Ferris wheel
# ---------------------------------------------------------------------------
func _ferris_wheel() -> void:
	var p := (AREA_FROM + AREA_TO) * 0.5 - 40.0
	var c := _at(p, _lat + 30.0)
	var h := 22.0
	var gy: float = _road_y(p) - 0.05
	terrain.level_to(c, 16.0, 10.0, gy)
	c.y = gy
	var along := _at(p + 10.0, 0.0) - _at(p, 0.0)
	along.y = 0.0
	var root := Node3D.new()
	root.name = "FerrisWheel"
	add_child(root)
	# the wheel's plane is parallel to the track (seen face-on from the grandstands)
	root.global_transform = Transform3D(Basis.looking_at(Vector3.UP.cross(along).normalized(), Vector3.UP), c)
	var steel := TexKit.std(Color(0.92, 0.92, 0.95), 0.35, 0.6)
	# A-frame legs on both sides
	for zs: float in [-1.6, 1.6]:
		for xs: float in [-1.0, 1.0]:
			var foot := Vector3(xs * 9.0, 0, zs * 1.8)
			var top := Vector3(0, h, zs)
			var leg := MeshKit.box_node(Vector3(0.6, foot.distance_to(top), 0.6), steel, (foot + top) * 0.5)
			leg.basis = Basis(Vector3(0, 0, 1), atan2(-(top.x - foot.x), top.y - foot.y))
			root.add_child(leg)
	root.add_child(MeshKit.box_node(Vector3(16.0, 0.6, 5.0), TexKit.std(Color(0.4, 0.4, 0.42), 0.8), Vector3(0, 0.3, 0)))
	Colliders.add_box(self, root.global_transform * Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0)), Vector3(19.0, 1.0, 5.0))
	_wheel = Node3D.new()
	_wheel.name = "Wheel"
	root.add_child(_wheel)
	_wheel.position = Vector3(0, h, 0)
	var r := 18.0
	var st := MeshKit.new_st()
	var white := Color(0.95, 0.95, 0.97, 0.6)
	for zs: float in [-1.2, 1.2]:
		var segs := 40
		for k in segs:
			var a0 := TAU * k / segs
			var a1 := TAU * (k + 1) / segs
			var p0 := Vector3(cos(a0) * r, sin(a0) * r, zs)
			var p1 := Vector3(cos(a1) * r, sin(a1) * r, zs)
			MeshKit.box(st, Transform3D(Basis(Vector3(0, 0, 1), (a0 + a1) * 0.5 + PI * 0.5), (p0 + p1) * 0.5), Vector3(p0.distance_to(p1) + 0.05, 0.35, 0.35), white)
		for k in 16:
			var a := TAU * k / 16.0
			MeshKit.box(st, Transform3D(Basis(Vector3(0, 0, 1), a), Vector3(cos(a), sin(a), 0) * r * 0.5 + Vector3(0, 0, zs)), Vector3(r, 0.18, 0.18), white)
	Props._cyl(st, Vector3(0, 0, -1.8), Vector3(0, 0, 1.8), 0.9, 0.9, Color(0.5, 0.5, 0.55, 0.5), 12)
	var wm := MeshInstance3D.new()
	wm.mesh = MeshKit.commit(st, _vc())
	_wheel.add_child(wm)
	# rim lights
	_wheel_bulbs = TexKit.emissive(Color(1.0, 0.85, 0.5), 0.3)
	_night_mats.append([_wheel_bulbs, 0.3, 3.0])
	var bst := MeshKit.new_st()
	for k in 64:
		var a := TAU * k / 64.0
		for zs: float in [-1.45, 1.45]:
			MeshKit.box(bst, Transform3D(Basis.IDENTITY, Vector3(cos(a) * r, sin(a) * r, zs)), Vector3(0.22, 0.22, 0.22))
	var bm := MeshInstance3D.new()
	bm.mesh = MeshKit.commit(bst, _wheel_bulbs)
	bm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_wheel.add_child(bm)
	# gondolas
	for k in 16:
		var a := TAU * k / 16.0
		var gnd := Node3D.new()
		gnd.name = "Gondola%d" % k
		_wheel.add_child(gnd)
		gnd.position = Vector3(cos(a) * r, sin(a) * r, 0)
		var col: Color = TEAMS[k % TEAMS.size()]
		gnd.add_child(MeshKit.box_node(Vector3(1.8, 1.4, 1.8), TexKit.std(col, 0.5), Vector3(0, -1.6, 0)))
		gnd.add_child(MeshKit.box_node(Vector3(2.0, 0.15, 2.0), TexKit.std(Color(0.9, 0.9, 0.9), 0.5), Vector3(0, -0.8, 0)))
		gnd.add_child(MeshKit.box_node(Vector3(0.1, 0.8, 0.1), TexKit.std(Color(0.5, 0.5, 0.5), 0.4, 0.7), Vector3(0, -0.4, 0)))
	scenery.occupy(c, 22.0)
	# a little fair around it: food stalls and people queueing
	for k in 6:
		var a := TAU * k / 6.0 + 0.3
		var sp := c + Vector3(cos(a), 0, sin(a)) * 17.0
		sp.y = terrain.height_at(sp.x, sp.z)
		festival._add("gazebo", Transform3D(Basis(Vector3.UP, a), sp), Color(TEAMS[k % TEAMS.size()]))
		festival._add("beer_set", Transform3D(Basis(Vector3.UP, a + PI * 0.5), sp))
		for m in 5:
			festival._person(sp + Vector3(rng.randf_range(-3.0, 3.0), 0, rng.randf_range(-3.0, 3.0)), c)

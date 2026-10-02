extends Node3D
## Grüne Hölle, 24h weekend at the start/finish: the pit lane beside the end of the long straight
## (open to the track at entry and exit), a pit building with a row of garages in team colours, cars,
## tyre sets and mechanics in front of them, two big covered grandstands full of people opposite,
## and a Ferris wheel turning behind the paddock.

const MeshKit = preload("res://scripts/util/mesh_kit.gd")
const Props = preload("res://scripts/world/prop_meshes.gd")
const Crowd = preload("res://scripts/world/crowd.gd")
const Colliders = preload("res://scripts/util/colliders.gd")
const TexKit = preload("res://scripts/util/tex_kit.gd")

const PIT_FROM := -150.0      # pit lane: progress from the start line (m)
const PIT_TO := 60.0
const LANE_W := 10.0
const GARAGE_W := 6.0
const GARAGES := 30
const GARAGE_D := 13.0
const TEAMS := [Color(0.85, 0.1, 0.08), Color(0.1, 0.3, 0.8), Color(0.95, 0.75, 0.1), Color(0.1, 0.55, 0.3),
	Color(0.95, 0.95, 0.95), Color(0.1, 0.1, 0.12), Color(0.95, 0.45, 0.05), Color(0.45, 0.15, 0.65), Color(0.2, 0.7, 0.85)]

var track
var terrain
var scenery
var festival          # for the shared person / instancing helpers
var rng := RandomNumberGenerator.new()
var pit_side := -1.0
var _wall_off := 0.0  # the barrier's largest offset along the pit stretch
var _fair_c := Vector3.ZERO
var _stand_backs: Array = []
var _lat := 0.0       # lateral offset of the pit lane centre from the track centreline
var _wheel: Node3D
var _wheel_bulbs: StandardMaterial3D
var _night_mats: Array = []


func build(p_track, p_terrain, p_scenery, p_festival) -> void:
	track = p_track
	terrain = p_terrain
	scenery = p_scenery
	festival = p_festival
	rng.seed = 2424
	# the old start grandstand stands on the gantry's +X side: the pits go on the other side
	var s0: int = track.start_index
	pit_side = -1.0 if (track.gantry_xf.basis.x as Vector3).dot(track.rights[s0]) > 0.0 else 1.0
	var max_off := 0.0
	for p in range(int(PIT_FROM), int(PIT_TO), 4):
		var i: int = track.index_at(p)
		max_off = maxf(max_off, float(track.off_left[i] if pit_side < 0.0 else track.off_right[i]))
	_wall_off = max_off
	_lat = max_off + 2.5 + LANE_W * 0.5
	_pit_lane()
	await Game.load_tick()
	_garages()
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


## The festival's camp paths reach the fair and the back of the grandstands.
func link_paths(fest) -> void:
	if _fair_c != Vector3.ZERO:
		fest.link_to_camps(_fair_c)
	for b in _stand_backs:
		fest.link_to_camps(b)


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
	var s := pit_side if side == 0.0 else side
	var p: Vector3 = track.samples[i] + track.rights[i] * s * lat
	return p


func _road_y(progress: float) -> float:
	return float(track.samples[track.index_at(progress)].y)


## The ground from the track's edge to behind the garages, from well before the pit entry to well
## after the exit: one smooth surface at the height of the road's edge right beside each point
## (spots levelled one by one left humps in between – a hill at the entry), blending into the
## hills around it.
func _level_corridor() -> void:
	var cell: float = terrain.CELL
	var o: Vector2 = terrain.origin
	var L: float = track.length
	var p0 := PIT_FROM - 75.0
	var p1 := PIT_TO + 75.0
	var far := _lat + LANE_W * 0.5 + GARAGE_D + 16.0
	var lo := Vector2(1e9, 1e9)
	var hi := Vector2(-1e9, -1e9)
	var p := p0
	while p <= p1:
		for lat: float in [float(track.half_w), far + 14.0]:
			var q := _at(p, lat)
			lo = Vector2(minf(lo.x, q.x), minf(lo.y, q.z))
			hi = Vector2(maxf(hi.x, q.x), maxf(hi.y, q.z))
		p += 5.0
	var hs: PackedFloat32Array = terrain.heights
	var nx: int = terrain.nx
	var nz: int = terrain.nz
	var hint := -1
	for iz in range(maxi(int(floor((lo.y - o.y) / cell)), 0), mini(int(ceil((hi.y - o.y) / cell)) + 1, nz)):
		for ix in range(maxi(int(floor((lo.x - o.x) / cell)), 0), mini(int(ceil((hi.x - o.x) / cell)) + 1, nx)):
			var wp := Vector3(o.x + ix * cell, 0.0, o.y + iz * cell)
			var pr: Array = track.project(wp, hint)
			hint = pr[0]
			var rel := fposmod(float(pr[1]) + L * 0.5, L) - L * 0.5
			var lat := float(pr[2]) * pit_side
			if lat < float(track.half_w) + 0.3:
				continue          # the road itself, or the other side
			var k := smoothstep(p0, p0 + 22.0, rel) * (1.0 - smoothstep(p1 - 22.0, p1, rel)) * (1.0 - smoothstep(far, far + 14.0, lat))
			if k <= 0.0:
				continue
			var edge: Vector3 = track.edge_point(int(pr[0]), pit_side * float(track.half_w))
			var idx := iz * nx + ix
			hs[idx] = lerpf(hs[idx], edge.y - 0.02, k)
	terrain.heights = hs


# ---------------------------------------------------------------------------
# Pit lane
# ---------------------------------------------------------------------------
func _pit_lane() -> void:
	var L: float = track.length
	# openings in the barrier: entry before the lane, exit after it
	track.wall_gaps.append([fposmod(PIT_FROM - 45.0, L), fposmod(PIT_FROM - 5.0, L), pit_side])
	track.wall_gaps.append([PIT_TO + 5.0, PIT_TO + 45.0, pit_side])
	track.rebuild_walls()
	# level the ground: lane, entry and exit, garages and the paddock behind them, as one smooth
	# surface at the height of the road's edge beside it
	_level_corridor()
	var p := PIT_FROM
	# the lane (curved entry and exit from the track edge)
	var pts: Array = []
	var edge: float = float(track.half_w) + 1.0
	pts.append(_at(PIT_FROM - 48.0, edge))
	pts.append(_at(PIT_FROM - 25.0, lerpf(edge, _lat, 0.55)))
	p = PIT_FROM
	while p <= PIT_TO:
		pts.append(_at(p, _lat))
		p += 10.0
	pts.append(_at(PIT_TO + 25.0, lerpf(edge, _lat, 0.55)))
	pts.append(_at(PIT_TO + 48.0, edge))
	scenery.add_path(pts, LANE_W, "asphalt", false)
	# white lines: the lane's edge and the fast lane / working lane split
	for lat_l in [_lat - LANE_W * 0.5 + 0.3, _lat + 0.5]:
		p = PIT_FROM
		while p < PIT_TO:
			var a := _at(p, lat_l)
			var b := _at(p + (10.0 if lat_l < _lat else 4.0), lat_l)
			var dir := b - a
			scenery.add_ground_line(Transform3D(Basis.looking_at(Vector3(dir.x, 0, dir.z).normalized(), Vector3.UP), (a + b) * 0.5), dir.length())
			p += 10.0 if lat_l < _lat else 7.0
	# "PIT" boards at entry and exit
	for pp in [PIT_FROM - 4.0, PIT_TO + 4.0]:
		var bp := _at(pp, _lat + LANE_W * 0.5 + 2.5)
		bp.y = terrain.height_at(bp.x, bp.z)
		var root := Node3D.new()
		add_child(root)
		root.global_position = bp
		root.add_child(MeshKit.box_node(Vector3(0.12, 3.0, 0.12), TexKit.std(Color(0.7, 0.7, 0.72), 0.4, 0.7), Vector3(0, 1.5, 0)))
		var board := TexKit.emissive(Color(0.95, 0.85, 0.1), 0.4)
		_night_mats.append([board, 0.4, 2.0])
		root.add_child(MeshKit.box_node(Vector3(1.6, 0.9, 0.08), board, Vector3(0, 3.2, 0)))
		root.look_at(_at(pp, 0.0) + Vector3(0, 3.2, 0), Vector3.UP)
	scenery.occupy(_at((PIT_FROM + PIT_TO) * 0.5, _lat), 9.5)
	for q in range(int(PIT_FROM) - 50, int(PIT_TO) + 50, 8):
		scenery.occupy(_at(q, _lat + 6.0), 9.5)
	# and the strip between the barrier and the lane (the pit wall): no spectators standing there
	for q in range(int(PIT_FROM) - 60, int(PIT_TO) + 60, 5):
		scenery.occupy(_at(q, (_wall_off + _lat) * 0.5), 4.5)


# ---------------------------------------------------------------------------
# Garages
# ---------------------------------------------------------------------------
## A slab between progress pa and pb, from lateral l0 to l1, heights y0..y1 above the road: its
## corners follow the curve, so neighbouring slabs meet without gaps.
func _slab(st: SurfaceTool, pa: float, pb: float, l0: float, l1: float, y0: float, y1: float, col: Color) -> void:
	var pt := func(pp: float, lat: float, y: float) -> Vector3:
		var q := _at(pp, lat)
		q.y = _road_y(pp) + float(track.ROAD_Y) + y
		return q
	var c := [pt.call(pa, l0, y0), pt.call(pb, l0, y0), pt.call(pb, l1, y0), pt.call(pa, l1, y0),
		pt.call(pa, l0, y1), pt.call(pb, l0, y1), pt.call(pb, l1, y1), pt.call(pa, l1, y1)]
	var ctr := Vector3.ZERO
	for v in c:
		ctr += v
	ctr /= 8.0
	for f in [[0, 1, 2, 3], [4, 5, 6, 7], [0, 1, 5, 4], [3, 2, 6, 7], [0, 3, 7, 4], [1, 2, 6, 5]]:
		var a: Vector3 = c[f[0]]
		var b: Vector3 = c[f[1]]
		var cc: Vector3 = c[f[2]]
		var d: Vector3 = c[f[3]]
		var n := ((a + b + cc + d) * 0.25 - ctr).normalized()
		MeshKit.quad(st, a, b, cc, d, n, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, col)


## A pit crew member in the team's racing overall (crowd.gd's person, one colour head to toe).
func _crew(p: Vector3, look_at: Vector3, team: Color) -> void:
	var g := p + Vector3(0, 0.04, 0)        # on the garage floor / apron
	var d := look_at - g
	d.y = 0.0
	if d.length() < 0.01:
		d = Vector3(0, 0, -1)
	var sc := rng.randf_range(0.95, 1.05)
	festival._add("person", Transform3D(Basis.looking_at(d.normalized(), Vector3.UP) * Basis.from_scale(Vector3(sc, sc, sc)), g),
		Color(team.r, team.g, team.b, 2.0 + rng.randf() * 0.5))
func _garages() -> void:
	var st := MeshKit.new_st()
	var wall := Color(0.86, 0.86, 0.84)
	var dark := Color(0.06, 0.06, 0.07)
	var glass := Color(0.15, 0.22, 0.3, 0.55)
	var floor_c := Color(0.55, 0.55, 0.57)
	var front_lat := _lat + LANE_W * 0.5 + 1.0
	var p := (PIT_FROM + PIT_TO) * 0.5 - GARAGES * GARAGE_W * 0.5
	var k := 0
	var bodies: Array = []
	while k < GARAGES:
		var team: Color = TEAMS[(k / 2) % TEAMS.size()]
		var a := _at(p, front_lat)
		var b := _at(p + GARAGE_W, front_lat)
		var along := (b - a)
		along.y = 0.0
		var w := along.length()
		along /= maxf(w, 0.01)
		var out: Vector3 = Vector3.UP.cross(along).normalized()
		if out.dot(_at(p, front_lat + 1.0) - a) < 0.0:
			out = -out
		var base := (a + b) * 0.5
		base.y = _road_y(p) + float(track.ROAD_Y)
		# frame: x along, z away from the lane (out), y up
		var fr := Basis(along, Vector3.UP, out)
		var xf := Transform3D(fr, base)
		var box := func(c: Vector3, s: Vector3, col: Color) -> void:
			MeshKit.box(st, xf * Transform3D(Basis.IDENTITY, c), s, col)
		# side walls, back wall, roof slab, upper floor with glass, open door with the dark inside
		# side wall, floor, team band, the glass of the upper floor, the dark inside (the back wall,
		# the slabs and the upper floor are built after the loop as one piece along the curve)
		box.call(Vector3(-w * 0.5 + 0.15, 3.0, GARAGE_D * 0.5), Vector3(0.3, 6.0, GARAGE_D), wall)
		box.call(Vector3(0, 0.02, GARAGE_D * 0.5), Vector3(w, 0.04, GARAGE_D), floor_c)
		box.call(Vector3(0, 4.3, 0.15), Vector3(w, 1.0, 0.3), team)
		box.call(Vector3(0, 7.7, 2.05), Vector3(w - 0.4, 1.8, 0.05), glass)
		box.call(Vector3(0, 2.0, GARAGE_D - 0.6), Vector3(w - 0.6, 3.6, 0.1), dark)
		# concrete apron and garage floor painted into the ground (no grass coming through)
		scenery.add_ground_patch(Transform3D(fr, base + out * (GARAGE_D * 0.5 - 0.5)), Vector2(w + 0.2, GARAGE_D + 1.0), "paving", false, 0.07)
		# guardrail along the front of the roof terrace (the spectators stand behind it)
		var rail := Color(0.75, 0.76, 0.78, 0.5)
		box.call(Vector3(0, 7.35, 0.12), Vector3(w + 0.02, 0.07, 0.07), rail)
		box.call(Vector3(0, 6.8, 0.12), Vector3(w + 0.02, 0.05, 0.05), rail)
		for px: float in [-w * 0.5 + 0.05, 0.0]:
			box.call(Vector3(px, 6.8, 0.12), Vector3(0.06, 1.1, 0.06), rail)
		bodies.append([xf * Transform3D(Basis.IDENTITY, Vector3(0, 6.8, 0.12)), Vector3(w, 1.1, 0.1)])
		# tool wall and a work bench inside

		box.call(Vector3(-w * 0.5 + 0.6, 0.5, GARAGE_D - 2.0), Vector3(0.6, 1.0, 2.5), Color(0.6, 0.1, 0.1, 0.6))
		bodies.append([xf * Transform3D(Basis.IDENTITY, Vector3(-w * 0.5 + 0.15, 3.0, GARAGE_D * 0.5)), Vector3(0.3, 6.0, GARAGE_D)])
		bodies.append([xf * Transform3D(Basis.IDENTITY, Vector3(0, 7.6, GARAGE_D * 0.5 + 1.0)), Vector3(w, 3.0, GARAGE_D - 2.0)])
		# no cars in the garages: now and then a crew member or two in the team's racing overall
		if rng.randf() < 0.45:
			for m in rng.randi_range(1, 2):
				var mp: Vector3 = base + out * rng.randf_range(0.6, 3.0) + along * rng.randf_range(-w * 0.3, w * 0.3)
				_crew(mp, mp - out * 4.0 + along * rng.randf_range(-3.0, 3.0), team)
		p += GARAGE_W
		k += 1
	# the back wall, the floor slab, the upper floor and the roof: continuous along the curve (each
	# garage on its own left wedge-shaped gaps at the back on the outside of the bend)
	var p0 := (PIT_FROM + PIT_TO) * 0.5 - GARAGES * GARAGE_W * 0.5
	for kk in GARAGES:
		var pa := p0 + kk * GARAGE_W
		var pb := pa + GARAGE_W
		_slab(st, pa, pb, front_lat + GARAGE_D - 0.3, front_lat + GARAGE_D, 0.0, 6.0, wall)
		_slab(st, pa, pb, front_lat - 1.0, front_lat + GARAGE_D, 5.95, 6.25, wall)
		_slab(st, pa, pb, front_lat + 2.0, front_lat + GARAGE_D, 6.25, 9.0, wall)
		_slab(st, pa, pb, front_lat + 1.8, front_lat + GARAGE_D + 0.2, 9.0, 9.2, Color(0.3, 0.3, 0.33, 0.5))
		var ba := _at(pa, front_lat + GARAGE_D - 0.15)
		var bb := _at(pb, front_lat + GARAGE_D - 0.15)
		var dir := Vector3(bb.x - ba.x, 0, bb.z - ba.z)
		var len := dir.length()
		if len > 0.01:
			dir /= len
			var y0 := _road_y(pa) + float(track.ROAD_Y)
			bodies.append([Transform3D(Basis(dir, Vector3.UP, dir.cross(Vector3.UP)), (ba + bb) * 0.5 + Vector3(0, y0 + 4.6 - (ba.y + bb.y) * 0.5, 0)), Vector3(len + 0.1, 9.2, 0.3)])
	# the last side wall and a row of floodlight masts on the roof
	var mi := MeshInstance3D.new()
	mi.mesh = MeshKit.commit(st, _vc())
	mi.name = "PitBuilding"
	add_child(mi)
	for bd in bodies:
		Colliders.add_box(self, bd[0], bd[1])
	# the pit wall crowd: people on the roof terrace
	p = (PIT_FROM + PIT_TO) * 0.5 - GARAGES * GARAGE_W * 0.5 + 1.0
	while p < (PIT_FROM + PIT_TO) * 0.5 + GARAGES * GARAGE_W * 0.5 - 1.0:
		var rp := _at(p, front_lat + 0.9)
		rp.y = _road_y(p) + 6.25
		if rng.randf() < 0.75:
			festival._person_raw(rp, _at(p, 0.0))
		p += rng.randf_range(0.8, 1.6)
	scenery.occupy(_at((PIT_FROM + PIT_TO) * 0.5, front_lat + GARAGE_D * 0.5), 9.5)
	for q in range(int(PIT_FROM), int(PIT_TO), 9):
		scenery.occupy(_at(q, front_lat + GARAGE_D * 0.5), 9.5)


# ---------------------------------------------------------------------------
# Grandstands opposite the pits
# ---------------------------------------------------------------------------
func _grandstand(centre_p: float, length: float) -> void:
	var side := -pit_side
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
	_stand_backs.append(base + out * (depth + 6.0))


# ---------------------------------------------------------------------------
# Ferris wheel
# ---------------------------------------------------------------------------
func _ferris_wheel() -> void:
	var p := (PIT_FROM + PIT_TO) * 0.5 - 40.0
	var c := _at(p, _lat + LANE_W * 0.5 + GARAGE_D + 38.0)
	var h := 22.0
	var gy: float = _road_y(p) - 0.05
	terrain.level_to(c, 16.0, 10.0, gy)
	_fair_c = c
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

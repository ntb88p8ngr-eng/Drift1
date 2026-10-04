extends Node3D
## Utah's lake (desert_water.gd has the shape): the water of the lake and both rivers, the ring
## road round the lake (it crosses the inflow on a bridge and the outflow on the dam's crest), the
## dam with its spillway, the lap's two bridges over the river, and the roads from the ring out to
## the lap – all of it paved: the cars get asphalt grip on it.

const MeshKit = preload("res://scripts/util/mesh_kit.gd")
const TexKit = preload("res://scripts/util/tex_kit.gd")
const Colliders = preload("res://scripts/util/colliders.gd")
const RoadBuilder = preload("res://scripts/editor/road_builder.gd")

const PAVE_CELL := 2.0

var track
var terrain
var scenery
var world
var water                  # desert_water.gd
var stats := {}
var _concrete: StandardMaterial3D
var _rail: StandardMaterial3D
var _pave := {}            # Vector2i (2 m cell) -> true: paved beside the lap
var _foam: Array = []      # waterfall materials (scrolling)


func build(p_track, p_terrain, p_scenery) -> void:
	track = p_track
	terrain = p_terrain
	scenery = p_scenery
	world = scenery.get_parent()
	water = track.water
	if water == null:
		return
	# the terrace round the lake is spoken for (car parks and signs elsewhere don't level it)
	scenery.occupy(Vector3(water.center.x, 0, water.center.y), water.terrace)
	_concrete = TexKit.std(Color(0.62, 0.6, 0.56), 0.85)
	_rail = TexKit.std(Color(0.72, 0.72, 0.7), 0.4, 0.6)
	_water_surfaces()
	_ring_road()
	_dam()
	_track_bridges()
	await Game.load_tick()
	_spokes()
	# the paved roads beside the lap drive like asphalt
	var prev: Callable = track.ground_fn
	track.ground_fn = func(pos: Vector3) -> Array:
		if _pave.has(Vector2i(int(floor(pos.x / PAVE_CELL)), int(floor(pos.z / PAVE_CELL)))):
			return [1.0 - 0.18 * float(track.wetness), "asphalt"]
		return prev.call(pos) if prev.is_valid() else []
	print("DESERT LAKE: %s" % str(stats))


func _stamp(p: Vector2, half: float) -> void:
	var r := int(ceil(half / PAVE_CELL))
	var c := Vector2i(int(floor(p.x / PAVE_CELL)), int(floor(p.y / PAVE_CELL)))
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var q := c + Vector2i(dx, dz)
			if ((Vector2(q) + Vector2(0.5, 0.5)) * PAVE_CELL).distance_to(p) <= half:
				_pave[q] = true


# ---------------------------------------------------------------------------
# Water
# ---------------------------------------------------------------------------
func _water_surfaces() -> void:
	var mat := TexKit.water_material()
	var st := MeshKit.new_st()
	# the lake: a disc at its level
	var c: Vector2 = water.center
	var segs := 160
	for k in segs:
		var a0 := TAU * k / segs
		var a1 := TAU * (k + 1) / segs
		# (its uneven shore: a little over it, the banks rise out of the water)
		var r0: float = water.lake_r_at(a0) + 3.0
		var r1: float = water.lake_r_at(a1) + 3.0
		var p0 := Vector3(c.x, water.level, c.y)
		var p1 := Vector3(c.x + cos(a0) * r0, water.level, c.y + sin(a0) * r0)
		var p2 := Vector3(c.x + cos(a1) * r1, water.level, c.y + sin(a1) * r1)
		MeshKit.tri(st, p0, p1, p2, Vector3.UP, Vector3.UP, Vector3.UP, Vector2(p0.x, p0.z), Vector2(p1.x, p1.z), Vector2(p2.x, p2.z), Vector3.UP)
	# the rivers: ribbons following their level (a step at the dam)
	for k in water.rivers.size():
		var pts: PackedVector2Array = water.rivers[k]["pts"]
		var ss: PackedFloat32Array = water.rivers[k]["s"]
		var half: float = water.RIVER_W * 0.5 + 3.5
		# (one side direction per point, shared by the quads either side of it: per-segment
		# normals left wedge-shaped gaps in every bend)
		var sides := PackedVector2Array()
		for i in pts.size():
			var t := (pts[mini(i + 1, pts.size() - 1)] - pts[maxi(i - 1, 0)]).normalized()
			sides.append(Vector2(-t.y, t.x) * half)
		for i in pts.size() - 1:
			var a := pts[i]
			var b := pts[i + 1]
			var n := sides[i]
			var nb := sides[i + 1]
			var ya: float = water.river_level(k, ss[i])
			var yb: float = water.river_level(k, ss[i + 1])
			if k == 1 and ss[i] < water.dam_s and ss[i + 1] >= water.dam_s:
				yb = ya          # (the fall itself is drawn at the dam)
			MeshKit.quad(st, Vector3(a.x - n.x, ya, a.y - n.y), Vector3(a.x + n.x, ya, a.y + n.y),
				Vector3(b.x + nb.x, yb, b.y + nb.y), Vector3(b.x - nb.x, yb, b.y - nb.y), Vector3.UP,
				Vector2(a.x, a.y), Vector2(b.x, b.y), Vector2(b.x, b.y), Vector2(a.x, a.y))
	var mi := MeshKit.mesh_instance(MeshKit.commit(st, mat), null, false)
	mi.name = "Water"
	add_child(mi)
	stats["water"] = true


# ---------------------------------------------------------------------------
# The ring road
# ---------------------------------------------------------------------------
func _ring_point(a: float, lateral := 0.0) -> Vector3:
	var r: float = water.ring_r + lateral
	return Vector3(water.center.x + cos(a) * r, water.plateau + 0.12, water.center.y + sin(a) * r)


func _ring_road() -> void:
	var st := MeshKit.new_st()
	var faces := PackedVector3Array()
	var half: float = water.ring_w * 0.5
	var segs := 120
	var circ: float = TAU * water.ring_r
	for k in segs:
		var a0 := TAU * k / segs
		var a1 := TAU * (k + 1) / segs
		var i0 := _ring_point(a0, -half)
		var o0 := _ring_point(a0, half)
		var i1 := _ring_point(a1, -half)
		var o1 := _ring_point(a1, half)
		var v0 := circ * k / segs
		var v1 := circ * (k + 1) / segs
		MeshKit.quad(st, i0, o0, o1, i1, Vector3.UP, Vector2(0, v0), Vector2(1, v0), Vector2(1, v1), Vector2(0, v1))
		faces.append_array(PackedVector3Array([i0, o1, o0, i0, i1, o1]))
		_stamp(Vector2(_ring_point(a0).x, _ring_point(a0).z), half + 0.5)
	var mi := MeshKit.mesh_instance(MeshKit.commit(st, track.road_material), null, false)
	mi.name = "RingRoad"
	add_child(mi)
	var body := StaticBody3D.new()
	body.name = "RingRoadBody"
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("surface", "road")
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	add_child(body)
	# where the ring crosses the inflow: a bridge (railings, the deck's concrete edge)
	var a_in := _river_angle(0)
	_ring_bridge(a_in, half)
	stats["ring"] = true


## The angle round the lake where river k crosses the ring.
func _river_angle(k: int) -> float:
	var pts: PackedVector2Array = water.rivers[k]["pts"]
	for p in pts:
		if p.distance_to(water.center) >= water.ring_r:
			return (p - water.center).angle()
	return 0.0


func _ring_bridge(a: float, half: float) -> void:
	var span: float = (water.RIVER_W * 0.5 + 7.0) / water.ring_r      # the angle either side
	var st := MeshKit.new_st()
	var steps := 10
	for side in [-1.0, 1.0]:
		var prev := Vector3.ZERO
		for k in steps + 1:
			var ak := a - span + 2.0 * span * k / steps
			var p := _ring_point(ak, (half + 0.25) * side)
			if k > 0:
				_rail_segment(st, prev, p)
			prev = p
	# the deck's edge down to the water (concrete faces under the road)
	for side in [-1.0, 1.0]:
		for k in steps:
			var a0 := a - span + 2.0 * span * k / steps
			var a1 := a - span + 2.0 * span * (k + 1) / steps
			var p0 := _ring_point(a0, half * side)
			var p1 := _ring_point(a1, half * side)
			MeshKit.quad(st, p0, p1, p1 - Vector3(0, 0.9, 0), p0 - Vector3(0, 0.9, 0), Vector3(cos(a0), 0, sin(a0)) * side)
	var under := MeshKit.new_st()
	for k in steps:
		var a0 := a - span + 2.0 * span * k / steps
		var a1 := a - span + 2.0 * span * (k + 1) / steps
		MeshKit.quad(under, _ring_point(a0, -half) - Vector3(0, 0.9, 0), _ring_point(a0, half) - Vector3(0, 0.9, 0),
			_ring_point(a1, half) - Vector3(0, 0.9, 0), _ring_point(a1, -half) - Vector3(0, 0.9, 0), Vector3.DOWN)
	var mi := MeshKit.mesh_instance(MeshKit.commit(st, _rail))
	add_child(mi)
	var mu := MeshKit.mesh_instance(MeshKit.commit(under, _concrete))
	add_child(mu)
	stats["bridges"] = int(stats.get("bridges", 0)) + 1


## A railing between two points: posts every 2 m, a top rail – solid.
func _rail_segment(st: SurfaceTool, a: Vector3, b: Vector3) -> void:
	var d := b - a
	var l := d.length()
	if l < 0.01:
		return
	var basis := Basis.looking_at(d / l, Vector3.UP)
	MeshKit.box(st, Transform3D(basis, (a + b) * 0.5 + Vector3(0, 1.0, 0)), Vector3(0.1, 0.12, l + 0.05), Color.WHITE)
	MeshKit.box(st, Transform3D(basis, (a + b) * 0.5 + Vector3(0, 0.55, 0)), Vector3(0.08, 0.08, l + 0.05), Color.WHITE)
	for t in [0.0, 1.0]:
		MeshKit.box(st, Transform3D(basis, a.lerp(b, t) + Vector3(0, 0.55, 0)), Vector3(0.12, 1.1, 0.12), Color.WHITE)
	Colliders.add_box(self, Transform3D(basis, (a + b) * 0.5 + Vector3(0, 0.55, 0)), Vector3(0.25, 1.1, l))


# ---------------------------------------------------------------------------
# The dam
# ---------------------------------------------------------------------------
func _dam() -> void:
	var a := _river_angle(1)
	var dir := Vector3(cos(a), 0, sin(a))           # downstream
	var across := Vector3(-dir.z, 0, dir.x)
	var mid := _ring_point(a)
	var half_w: float = water.RIVER_W * 0.5 + 9.0
	var top: float = water.plateau
	var bottom: float = water.level - water.DAM_DROP - 2.5
	var st := MeshKit.new_st()
	# the wall: across the valley under the road, its downstream face sloping out
	var xf := Transform3D(Basis.looking_at(dir, Vector3.UP), Vector3(mid.x, (top + bottom) * 0.5 - 0.05, mid.z))
	MeshKit.box(st, xf, Vector3(half_w * 2.0, top - bottom, water.ring_w + 1.0), Color.WHITE)
	# a buttress apron below it
	var apron := Transform3D(xf.basis, xf.origin + dir * (water.ring_w * 0.5 + 2.5) + Vector3(0, -(top - bottom) * 0.25, 0))
	MeshKit.box(st, apron, Vector3(half_w * 2.0, (top - bottom) * 0.5, 4.0), Color(0.9, 0.9, 0.9))
	# the parapets along the road
	for side in [-1.0, 1.0]:
		var pz: Vector3 = dir * (water.ring_w * 0.5 + 0.3) * side
		MeshKit.box(st, Transform3D(xf.basis, mid + pz + Vector3(0, 0.55, 0)), Vector3(half_w * 2.0, 1.1, 0.4), Color(0.95, 0.95, 0.95))
		Colliders.add_box(self, Transform3D(xf.basis, mid + pz + Vector3(0, 0.55, 0)), Vector3(half_w * 2.0, 1.1, 0.4))
	var mi := MeshKit.mesh_instance(MeshKit.commit(st, _concrete))
	mi.name = "Dam"
	add_child(mi)
	Colliders.add_box(self, Transform3D(xf.basis, xf.origin - Vector3(0, 0.15, 0)), Vector3(half_w * 2.0, top - bottom - 0.3, water.ring_w + 1.0))
	# the spillway: water pouring over the downstream face, white foam at its foot
	var foam_mat := ShaderMaterial.new()
	foam_mat.shader = Shader.new()
	foam_mat.shader.code = """
shader_type spatial;
render_mode cull_disabled, depth_draw_never, unshaded;
uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
void fragment() {
	float n = texture(noise_tex, vec2(UV.x * 3.0, UV.y * 1.5 - TIME * 1.4)).r;
	float n2 = texture(noise_tex, vec2(UV.x * 7.0 + 0.3, UV.y * 3.0 - TIME * 2.1)).r;
	ALBEDO = mix(vec3(0.55, 0.68, 0.72), vec3(0.95, 0.97, 1.0), smoothstep(0.4, 0.75, n * 0.6 + n2 * 0.4));
	ALPHA = clamp(0.55 + 0.4 * n2, 0.0, 0.9) * smoothstep(0.0, 0.08, UV.x) * smoothstep(1.0, 0.92, UV.x);
}
"""
	foam_mat.set_shader_parameter("noise_tex", TexKit.noise_texture(91, 0.05))
	_foam.append(foam_mat)
	var fall := MeshKit.new_st()
	var w2: float = water.RIVER_W * 0.5
	var f_top: Vector3 = mid + dir * (water.ring_w * 0.5 + 0.6) + Vector3(0, water.level - mid.y + 0.05, 0)
	var f_bot: Vector3 = mid + dir * (water.ring_w * 0.5 + 5.0) + Vector3(0, water.level - water.DAM_DROP - mid.y + 0.05, 0)
	MeshKit.quad(fall, f_top - across * w2, f_top + across * w2, f_bot + across * w2, f_bot - across * w2, dir + Vector3.UP,
		Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1))
	var fmi := MeshKit.mesh_instance(MeshKit.commit(fall, foam_mat), null, false)
	add_child(fmi)
	stats["dam"] = true


# ---------------------------------------------------------------------------
# The lap's bridges over the river
# ---------------------------------------------------------------------------
func _track_bridges() -> void:
	var n: int = track.sample_count()
	# the stretches of the lap over the river channel (the ground well below the road)
	var runs: Array = []
	var cur: Array = []
	for i in n:
		var p: Vector3 = track.samples[i]
		var under: bool = water.river_at(p.x, p.z).x < water.RIVER_W * 0.5 + 8.0 and float(water.carve(p.x, p.z)) < p.y - 1.0
		if under:
			cur.append(i)
		elif not cur.is_empty():
			runs.append(cur)
			cur = []
	if not cur.is_empty():
		runs.append(cur)
	for over in runs:
		if over.size() < 2:
			continue
		var st := MeshKit.new_st()
		var deck := MeshKit.new_st()
		# a little beyond the channel at both ends
		var ext: Array = []
		for d in range(int(over[0]) - 3, int(over[over.size() - 1]) + 4):
			ext.append((d + n) % n)
		for side in [-1.0, 1.0]:
			for j in ext.size() - 1:
				var i0: int = ext[j]
				var i1: int = ext[j + 1]
				var a: Vector3 = track.edge_point(i0, (float(track.hws[i0]) + 0.3) * side) + Vector3(0, track.ROAD_Y, 0)
				var b: Vector3 = track.edge_point(i1, (float(track.hws[i1]) + 0.3) * side) + Vector3(0, track.ROAD_Y, 0)
				_rail_segment(st, a, b)
				var e0: Vector3 = track.edge_point(i0, float(track.hws[i0]) * side)
				var e1: Vector3 = track.edge_point(i1, float(track.hws[i1]) * side)
				MeshKit.quad(deck, e0, e1, e1 - Vector3(0, 1.1, 0), e0 - Vector3(0, 1.1, 0), track.rights[i0] * side)
		for j in ext.size() - 1:
			var i0: int = ext[j]
			var i1: int = ext[j + 1]
			var hw0: float = track.hws[i0]
			var hw1: float = track.hws[i1]
			MeshKit.quad(deck, track.edge_point(i0, -hw0) - Vector3(0, 1.1, 0), track.edge_point(i0, hw0) - Vector3(0, 1.1, 0),
				track.edge_point(i1, hw1) - Vector3(0, 1.1, 0), track.edge_point(i1, -hw1) - Vector3(0, 1.1, 0), Vector3.DOWN)
		# two piers in the river
		var mid_i: int = over[over.size() / 2]
		for side in [-0.45, 0.45]:
			var p: Vector3 = track.edge_point(mid_i, float(track.hws[mid_i]) * side)
			var bed: float = terrain.height_at(p.x, p.z) - 0.5
			var hgt := p.y - 1.1 - bed
			if hgt > 0.5:
				var tg: Vector3 = track.tangents[mid_i]
				MeshKit.box(deck, Transform3D(Basis.looking_at(Vector3(tg.x, 0, tg.z).normalized(), Vector3.UP), Vector3(p.x, bed + hgt * 0.5, p.z)), Vector3(1.2, hgt, 2.4), Color.WHITE)
		var mi := MeshKit.mesh_instance(MeshKit.commit(st, _rail))
		add_child(mi)
		var md := MeshKit.mesh_instance(MeshKit.commit(deck, _concrete))
		add_child(md)
		stats["bridges"] = int(stats.get("bridges", 0)) + 1


# ---------------------------------------------------------------------------
# Roads from the ring out to the lap
# ---------------------------------------------------------------------------
func _spokes() -> void:
	var holder := Node3D.new()
	holder.name = "LakeRoads"
	add_child(holder)
	var n: int = track.sample_count()
	for a in water.spokes:
		var dir := Vector2(cos(a), sin(a))
		var start: Vector2 = water.center + dir * (water.ring_r + 1.0)
		# where the ray meets the lap: the sample closest to it, nearest the lake
		var best := -1
		var best_t := 1e9
		for i in n:
			var q: Vector2 = Vector2(track.samples[i].x, track.samples[i].z) - water.center
			var t: float = q.dot(dir)
			if t <= water.ring_r:
				continue
			if absf(q.cross(dir)) < 6.0 and t < best_t:
				best_t = t
				best = i
		if best < 0:
			continue
		var end := Vector2(track.samples[best].x, track.samples[best].z)
		var pts: Array = []
		var steps := 6
		for k in steps + 1:
			var p := start.lerp(end, float(k) / steps)
			pts.append(Vector3(p.x, 0, p.y))
		var r := {"pts": pts, "width": 9.0, "surface": "asphalt", "flatten": false, "height": 0.0, "lift": 0.0}
		var body: StaticBody3D = RoadBuilder.build(holder, world, r)
		if body:
			body.set_meta("surface", "road")
		var line := RoadBuilder.centre_line(world, pts)
		for p in line:
			_stamp(Vector2(p.x, p.z), 5.0)
		stats["spokes"] = int(stats.get("spokes", 0)) + 1

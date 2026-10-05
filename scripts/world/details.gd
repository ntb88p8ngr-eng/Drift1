extends Node3D
## Roadside details on both maps: chevron boards on the outside of tight corners, curve warnings,
## brake boards, speed limits and direction signs, big lit billboards, sponsor banners on the
## barriers, a banner arch over the road, a bus stop, benches, bins, flower pots and planters, tyre
## stacks and cones. Repeated props are instanced in chunks through the scenery (view distance aware);
## houses add their own pots, benches and mailboxes through add().

const MeshKit = preload("res://scripts/util/mesh_kit.gd")
const Colliders = preload("res://scripts/util/colliders.gd")
const TexKit = preload("res://scripts/util/tex_kit.gd")
const SignAtlas = preload("res://scripts/world/sign_atlas.gd")
const Props = preload("res://scripts/world/prop_meshes.gd")

const TIGHT := 1.0 / 42.0       # curvature of a "tight" corner (radius < 42 m)

var track
var terrain
var scenery
var rng := RandomNumberGenerator.new()
var _sets := {}                 # key -> chunk dictionary
var _meshes := {}               # key -> [mesh, range end, shadows]
var _sign_mat: ShaderMaterial
var _bill_mat: ShaderMaterial
var _banner_mat: ShaderMaterial
var _banner_st: SurfaceTool
var _banner_count := 0
var _stats := {}


func _ready() -> void:
	# the atlas painter needs a node in the tree; setup() may run before the world is added
	SignAtlas.ensure_painted(self)


func setup(p_track, p_terrain, p_scenery) -> void:
	track = p_track
	terrain = p_terrain
	scenery = p_scenery
	rng.seed = hash(track.track_id) + 991
	_sign_mat = SignAtlas.board_material(self)
	_bill_mat = SignAtlas.board_material(self, 0.0)
	_bill_mat.set_shader_parameter("roughness_front", 0.6)
	_bill_mat.set_shader_parameter("both_sides", true)      # (ad boards: readable from both sides)
	_banner_mat = SignAtlas.board_material(self, 0.0, true)
	_banner_mat.set_shader_parameter("roughness_front", 0.85)
	_banner_st = MeshKit.new_st()
	for k in ["bench", "pot_red", "pot_yellow", "pot_purple", "pot_white", "planter", "bin", "mailbox", "hay_bale", "cone", "tyre_stack"]:
		_meshes[k] = [Props.get_mesh(k), 140.0, k == "bench" or k == "planter" or k == "hay_bale" or k == "tyre_stack"]
	for k in ["car_sedan", "car_hatch", "car_kei", "car_van"]:
		_meshes[k] = [Props.get_mesh(k), 360.0, true]
	for k in ["bicycle", "wheelie_bin", "garden_lamp", "hydrant"]:
		_meshes[k] = [Props.get_mesh(k), 120.0, false]
	_meshes["fence"] = [Props.get_mesh("fence"), 160.0, true]
	_meshes["post"] = [Props.get_mesh("post"), 320.0, true]
	_meshes["billboard_frame"] = [Props.get_mesh("billboard_frame"), 1200.0, true]
	_meshes["banner_tower"] = [Props.get_mesh("banner_tower"), 700.0, true]
	_meshes["bus_shelter"] = [Props.get_mesh("bus_shelter"), 300.0, true]
	_meshes["sign"] = [_with_material(Props.board(0.03), _sign_mat), 320.0, true]
	_meshes["bill"] = [_with_material(Props.board(0.12), _bill_mat), 1200.0, true]


## Places a prop instance (world transform). tint multiplies the prop colours.
func add(key: String, xf: Transform3D, tint := Color(1, 1, 1, 1)) -> void:
	if not _sets.has(key):
		_sets[key] = {}
	scenery._push(_sets[key], xf.origin, [xf, tint])
	_stats[key] = int(_stats.get(key, 0)) + 1


const CAR_KINDS := ["car_sedan", "car_sedan", "car_hatch", "car_hatch", "car_kei", "car_van"]
const CAR_PAINTS := [Color(0.92, 0.92, 0.9), Color(0.1, 0.1, 0.11), Color(0.55, 0.56, 0.58), Color(0.62, 0.05, 0.05),
	Color(0.08, 0.18, 0.5), Color(0.75, 0.72, 0.62), Color(0.15, 0.3, 0.2), Color(0.95, 0.75, 0.1), Color(0.35, 0.2, 0.12)]


## A parked car (world transform on the ground, front = -Z) with a collider. kind "" = random.
func add_parked_car(xf: Transform3D, kind := "") -> void:
	if kind == "":
		kind = CAR_KINDS[rng.randi() % CAR_KINDS.size()]
	var tint: Color = CAR_PAINTS[rng.randi() % CAR_PAINTS.size()]
	add(kind, xf, tint)
	var sz: Vector3 = Props.CAR_SIZES[kind]
	var body := Colliders.add_box(self, xf * Transform3D(Basis.IDENTITY, Vector3(0, sz.y * 0.5 + 0.1, 0)), Vector3(sz.x, sz.y - 0.2, sz.z))
	# people_hits.gd turns it into a real car body when someone drives into it
	car_bodies[car_key(xf.origin)] = body
	_stats["parked_cars"] = int(_stats.get("parked_cars", 0)) + 1


var car_bodies := {}             # car_key(position) -> its static collider


static func car_key(p: Vector3) -> Vector3i:
	return Vector3i(int(round(p.x * 10.0)), int(round(p.y * 10.0)), int(round(p.z * 10.0)))


## A small car park beside the road (behind the barrier): asphalt, bay lines, two rows of cars with
## gaps, a lamp and a bin; the entrance leads to the road.
func add_car_park(i: int, side: float, rows := 2, bays := 5) -> bool:
	var n: int = track.sample_count()
	i = _idx(i)
	var depth := 5.5 * rows + 6.0
	var width := 2.7 * bays + 2.0
	var pos: Vector3 = scenery._roadside(i, depth * 0.5 + 3.0, side)
	if terrain.normal_at(pos.x, pos.z).y < 0.94 or not scenery.free_at(pos, maxf(depth, width) * 0.6, 2.0):
		return false
	pos.y = terrain.flatten(pos, maxf(depth, width) * 0.55, 6.0)
	var z: Vector3 = -track.rights[i] * side          # towards the road
	z.y = 0.0
	z = z.normalized()
	var x := Vector3.UP.cross(z).normalized()
	var basis := Basis(x, Vector3.UP, z)
	var lot := Transform3D(basis, pos)
	scenery.add_ground_patch(lot, Vector2(width, depth), "asphalt")
	for r in rows:
		var rz := -depth * 0.5 + 3.0 + r * (depth - 6.0) / maxf(rows - 1, 1) if rows > 1 else 0.0
		var facing := 0.0 if r == 0 else PI       # the rows face each other across the aisle
		for b in bays:
			var bx := -width * 0.5 + 1.0 + 1.35 + b * 2.7
			scenery.add_ground_line(lot * Transform3D(Basis.IDENTITY, Vector3(bx - 1.35, 0, rz)), 5.0)
			if rng.randf() < 0.72:
				add_parked_car(lot * Transform3D(Basis(Vector3.UP, facing + rng.randf_range(-0.05, 0.05)), Vector3(bx + rng.randf_range(-0.15, 0.15), 0, rz)))
		scenery.add_ground_line(lot * Transform3D(Basis.IDENTITY, Vector3(-width * 0.5 + 1.0 + bays * 2.7, 0, rz)), 5.0)
	add("garden_lamp", lot * Transform3D(Basis.IDENTITY, Vector3(width * 0.5 - 0.5, 0, 0)).scaled_local(Vector3(1.0, 3.2, 1.0)))
	add("wheelie_bin", lot * Transform3D(Basis.IDENTITY, Vector3(-width * 0.5 + 0.6, 0, depth * 0.5 - 0.8)), Color(0.2, 0.35, 0.2))
	# the entrance: a short strip to the road edge
	var edge: Vector3 = track.samples[i] + track.rights[i] * side * (float(track.half_w) + 0.8)
	scenery.add_path([lot * Vector3(0, 0, -depth * 0.5), edge], 4.5, "asphalt")
	scenery.occupy(pos, maxf(depth, width) * 0.6)
	_stats["car_parks"] = int(_stats.get("car_parks", 0)) + 1
	return true


func add_pot(pos: Vector3) -> void:
	var kinds := ["pot_red", "pot_yellow", "pot_purple", "pot_white"]
	var s := rng.randf_range(0.85, 1.25)
	add(kinds[rng.randi() % kinds.size()], Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s, s)), pos),
		Color(1, 1, 1).darkened(rng.randf_range(0.0, 0.15)))


## Everything along the track. Call before the forest so the trees keep clear of the props.
func build(quality: int) -> void:
	if track.track_id == "playground":
		return        # the playground brings its own boards, cones and barrels
	var corners := _corners()
	_stats["corners"] = corners.size()
	_corner_chevrons(corners)
	_warning_signs(corners)
	_brake_boards(corners)
	_speed_limits()
	_billboards(5 if track.track_id == "ridge" else 4)
	_wall_banners(corners)
	_banner_arch(corners)
	if track.track_id == "ridge":
		_direction_sign()
		_benches(6)
	else:
		_harbor_extras()
		_benches(8)
	_tyre_stacks(corners)


## Emits all instanced props (call after the houses added theirs).
func finish() -> void:
	for key in _sets.keys():
		var m: Array = _meshes.get(key, [])
		if m.is_empty():
			continue
		scenery._emit_chunks(m[0], _sets[key], 0.0, float(m[1]), "Prop_" + key, bool(m[2]))
	if _banner_count > 0:
		var mesh := MeshKit.commit(_banner_st, _banner_mat)
		var mi := MeshKit.mesh_instance(mesh, null, false)
		mi.name = "Banners"
		add_child(mi)


func set_night(n: float) -> void:
	if _bill_mat:
		_bill_mat.set_shader_parameter("glow", 0.9 * n)
	if _sign_mat:
		_sign_mat.set_shader_parameter("glow", 0.06 * n)   # retro-reflective hint in the headlights


func stats_text() -> String:
	var parts: Array = []
	for k in _stats.keys():
		parts.append("%s=%d" % [k, _stats[k]])
	return ", ".join(parts)


static func _with_material(mesh: ArrayMesh, mat: Material) -> ArrayMesh:
	var m := mesh.duplicate() as ArrayMesh
	m.surface_set_material(0, mat)
	return m


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
func _idx(i: int) -> int:
	var n: int = track.sample_count()
	return (i % n + n) % n


func _wall_off(i: int, side: float) -> float:
	i = _idx(i)
	return float(track.off_left[i]) if side < 0.0 else float(track.off_right[i])


## Point `extra` metres behind the barrier on `side`, on the ground.
func _behind_wall(i: int, side: float, extra: float) -> Vector3:
	i = _idx(i)
	var p: Vector3 = track.samples[i] + track.rights[i] * side * (_wall_off(i, side) + extra)
	p.y = terrain.height_at(p.x, p.z)
	return p


## Basis for a board facing the traffic that arrives at sample i (driving direction = +tangent),
## turned a little towards the road centre.
func _facing(i: int, side: float, toward_road := 0.3) -> Basis:
	i = _idx(i)
	var z: Vector3 = (-track.tangents[i] - track.rights[i] * side * toward_road)
	z.y = 0.0
	z = z.normalized()
	var x := Vector3.UP.cross(z).normalized()
	return Basis(x, Vector3.UP, z)


## A sign board on a post. `size` = board size, `bottom` = height of the board's lower edge.
func _sign(pos: Vector3, basis: Basis, name: String, size: Vector2, bottom: float, posts := 1) -> void:
	var cell := SignAtlas.cell("sign", name)
	var centre := pos + Vector3(0, bottom + size.y * 0.5, 0)
	add("sign", Transform3D(Basis(basis.x * size.x, basis.y * size.y, basis.z), centre), cell)
	var top := bottom + size.y * 0.8
	var post_xfs: Array = []
	if posts == 1:
		post_xfs.append(Transform3D(Basis.IDENTITY.scaled(Vector3(1, top + 0.4, 1)), pos - basis.z * 0.05 + Vector3(0, -0.4, 0)))
	else:
		for k in [-0.35, 0.35]:
			post_xfs.append(Transform3D(Basis.IDENTITY.scaled(Vector3(1, top + 0.4, 1)), pos + basis.x * size.x * k - basis.z * 0.05 + Vector3(0, -0.4, 0)))
	for pxf in post_xfs:
		add("post", pxf)
	# knocked down by a car (sign_hits.gd)
	if scenery.signs:
		scenery.signs.add_sign(Transform3D(Basis(basis.x * size.x, basis.y * size.y, basis.z), centre), post_xfs, pos)


## Corners: [apex index, side of the outside (+1 = right), first index, last index, peak curvature]
func _corners() -> Array:
	var n: int = track.sample_count()
	var out: Array = []
	var i := 0
	# start outside a corner so none is split across the wrap-around
	while i < n and absf(float(track.curvature[i])) > TIGHT:
		i += 1
	var start := i
	var k := 0
	while k < n:
		var j := _idx(start + k)
		var c: float = track.curvature[j]
		if absf(c) > TIGHT:
			var first := start + k
			var sign_c := signf(c)
			var peak := 0.0
			var apex := j
			while k < n and absf(float(track.curvature[_idx(start + k)])) > TIGHT * 0.7 and signf(float(track.curvature[_idx(start + k)])) == sign_c:
				var cc := absf(float(track.curvature[_idx(start + k)]))
				if cc > peak:
					peak = cc
					apex = _idx(start + k)
				k += 1
			var last := start + k - 1
			out.append([apex, 1.0 if sign_c > 0.0 else -1.0, first, last, peak])
		k += 1
	return out


# ---------------------------------------------------------------------------
# Signs
# ---------------------------------------------------------------------------
func _corner_chevrons(corners: Array) -> void:
	for c in corners:
		var side: float = c[1]
		var name := "chevron_l" if side > 0.0 else "chevron_r"
		var first: int = c[2]
		var last: int = c[3]
		var span := last - first
		var step := clampi(span / 5, 3, 6)
		var i := first + step / 2
		while i <= last + 2:
			var pos := _behind_wall(i, side, 0.75)
			if scenery.free_at(pos, 0.4, 0.3):
				_sign(pos, _facing(i, side, 0.55), name, Vector2(0.9, 0.65), 0.75)
				_stats["chevrons"] = int(_stats.get("chevrons", 0)) + 1
			else:
				_stats["chevrons_blocked"] = int(_stats.get("chevrons_blocked", 0)) + 1
			i += step


func _warning_signs(corners: Array) -> void:
	for ci in corners.size():
		var c: Array = corners[ci]
		var first: int = c[2]
		var at := first - 38      # ~75 m before the corner
		# S-bend: the previous corner turned the other way and ended close by
		var prev: Array = corners[(ci - 1 + corners.size()) % corners.size()]
		var gap := _idx(first - int(prev[3]))
		var name := "curve_l" if float(c[1]) > 0.0 else "curve_r"
		if gap < 40 and float(prev[1]) != float(c[1]):
			continue            # the previous corner's sign already warns ("winding")
		var nxt: Array = corners[(ci + 1) % corners.size()]
		if _idx(int(nxt[2]) - int(c[3])) < 40 and float(nxt[1]) != float(c[1]):
			name = "winding"
		var side := -1.0       # left-hand traffic: signs on the left
		var pos := _behind_wall(at, side, 1.0)
		if scenery.free_at(pos, 0.5, 0.4):
			_sign(pos, _facing(at, side, 0.25), name, Vector2(0.85, 0.85), 1.4)
			scenery.occupy(pos, 0.6)


func _brake_boards(corners: Array) -> void:
	var sorted := corners.duplicate()
	sorted.sort_custom(func(a, b): return float(a[4]) > float(b[4]))
	for c in sorted.slice(0, 2):
		var side: float = c[1]
		for d in [[50, "board_100"], [25, "board_50"]]:
			var i: int = int(c[2]) - int(d[0])
			var pos := _behind_wall(i, side, 0.9)
			if scenery.free_at(pos, 0.4, 0.3):
				_sign(pos, _facing(i, side, 0.15), d[1], Vector2(0.6, 0.85), 0.4)


func _speed_limits() -> void:
	var s0: int = track.start_index
	var spots: Array = [[s0 + 55, "speed_60" if track.track_id == "ridge" else "speed_40"], [s0 + 330, "speed_40"]]
	for sp in spots:
		var i: int = sp[0]
		var pos := _behind_wall(i, -1.0, 1.1)
		if scenery.free_at(pos, 0.5, 0.4):
			_sign(pos, _facing(i, -1.0, 0.2), sp[1], Vector2(0.75, 0.75), 1.5)
			scenery.occupy(pos, 0.6)
	if track.track_id == "harbor":
		for i in [s0 + 150, s0 + 470]:
			var pos := _behind_wall(i, 1.0, 1.4)
			if scenery.free_at(pos, 0.5, 0.4):
				_sign(pos, _facing(i, 1.0, -0.6), "no_entry" if i == s0 + 150 else "parking", Vector2(0.7, 0.7), 1.5)


func _direction_sign() -> void:
	var i: int = track.start_index + 170
	var pos := _behind_wall(i, -1.0, 2.0)
	if scenery.free_at(pos, 1.5, 1.0):
		_sign(pos, _facing(i, -1.0, 0.2), "direction", Vector2(2.2, 2.2), 1.2, 2)
		scenery.occupy(pos, 1.6)


# ---------------------------------------------------------------------------
# Billboards, banners, arch
# ---------------------------------------------------------------------------
func _billboards(count: int) -> void:
	var n: int = track.sample_count()
	# candidate spots: ends of straights (low curvature ahead), looking back down the straight
	var cand: Array = []
	for i in range(0, n, 6):
		var straight := 0.0
		for k in range(-50, 1, 5):
			straight += absf(float(track.curvature[_idx(i + k)]))
		cand.append([straight, i])
	cand.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	var placed: Array = []
	var ad := rng.randi() % SignAtlas.ADS.size()
	for c in cand:
		if placed.size() >= count:
			break
		var i: int = c[1]
		var far := false
		for p in placed:
			var d := absi(i - int(p))
			if mini(d, n - d) < 90:
				far = true
		if far:
			continue
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		for attempt in 2:
			var pos := _behind_wall(i, side, rng.randf_range(9.0, 16.0))
			var basis := _facing(i, side, 0.6)
			var l: Vector3 = pos - basis.x * 2.6
			var r: Vector3 = pos + basis.x * 2.6
			var hl: float = terrain.height_at(l.x, l.z)
			var hr: float = terrain.height_at(r.x, r.z)
			if absf(hl - hr) > 2.0 or not scenery.free_at(pos, 5.0, 3.0):
				side = -side
				continue
			pos.y = minf(hl, hr) - 0.3
			add("billboard_frame", Transform3D(basis, pos))
			var cell := SignAtlas.cell("ad", SignAtlas.ADS[ad % SignAtlas.ADS.size()])
			ad += 1
			add("bill", Transform3D(Basis(basis.x * 8.0, basis.y * 4.0, basis.z), pos + basis.y * 5.0 + basis.z * 0.12), cell)
			# floodlight for the night
			var l_node := SpotLight3D.new()
			l_node.light_color = Color(1.0, 0.92, 0.8)
			l_node.spot_range = 9.0
			l_node.spot_angle = 60.0
			l_node.shadow_enabled = false
			l_node.visible = false
			add_child(l_node)
			l_node.global_transform = Transform3D(Basis.looking_at(-basis.z * 0.6 - Vector3.UP, Vector3.UP), pos + basis.y * 7.3 + basis.z * 1.3)
			scenery._night_lights.append([l_node, 4.0])
			scenery.occupy(pos, 5.5)
			placed.append(i)
			break


## Sponsor banners zip-tied to the barriers: along the start straight, at the crowd corners and here
## and there around the lap.
func _wall_banners(corners: Array) -> void:
	var n: int = track.sample_count()
	var runs: Array = []
	var s0: int = track.start_index
	runs.append([s0 - 44, s0 + 36, -1.0])
	runs.append([s0 - 44, s0 + 36, 1.0])
	var by_peak := corners.duplicate()
	by_peak.sort_custom(func(a, b): return float(a[4]) > float(b[4]))
	for c in by_peak.slice(0, 4):
		runs.append([int(c[2]) - 6, int(c[3]) + 6, float(c[1])])
	for k in 5:
		var i := rng.randi_range(0, n - 1)
		runs.append([i, i + 20, -1.0 if rng.randf() < 0.5 else 1.0])
	var kinds: Array = ["drift_zone", "kurohana_motors", "takumi_tires", "nitro_x", "series"]
	if track.track_id == "harbor":
		kinds.append("harbor")
	var concrete: bool = track.def["wall"] == "concrete"
	var y0 := 0.28 if concrete else 0.1
	var y1 := 1.12 if concrete else 0.98
	for r in runs:
		var i: int = r[0]
		var end: int = r[1]
		var side: float = r[2]
		while i + 4 <= end:
			var kind: String = kinds[rng.randi() % kinds.size()]
			if kind == "drift_zone" and rng.randf() < 0.5:
				kind = "safety"
			_banner_strip(i, 4, side, SignAtlas.cell("banner", kind), y0, y1)
			i += 5


func _banner_strip(i0: int, count: int, side: float, cell: Color, y0: float, y1: float) -> void:
	var pts: Array = []
	for k in count + 1:
		var i := _idx(i0 + k)
		var off := _wall_off(i, side) - 0.04
		pts.append([track.samples[i] + track.rights[i] * side * off, -track.rights[i] * side])
	var total := float(count)
	var free_standing: bool = str(track.def.get("wall", "")) == "none"
	for k in count:
		var a: Vector3 = pts[k][0]
		var b: Vector3 = pts[k + 1][0]
		var nrm: Vector3 = pts[k][1]
		var u0 := cell.r + cell.b * (float(k) / total)
		var u1 := cell.r + cell.b * (float(k + 1) / total)
		# the banner reads left-to-right for someone looking at it from the road (on the right-hand
		# barrier the driving direction points to the viewer's left)
		if side > 0.0:
			u0 = cell.r + cell.b * (1.0 - float(k) / total)
			u1 = cell.r + cell.b * (1.0 - float(k + 1) / total)
		var v0 := cell.g + 0.002
		var v1 := cell.g + cell.a - 0.002
		MeshKit.quad(_banner_st, a + Vector3(0, y0, 0), b + Vector3(0, y0, 0), b + Vector3(0, y1, 0), a + Vector3(0, y1, 0), nrm,
			Vector2(u0, v1), Vector2(u1, v1), Vector2(u1, v0), Vector2(u0, v0))
		if free_standing:
			# no barrier behind it (Utah): printed on the back too, reading the right way round from there
			var m0 := cell.r * 2.0 + cell.b - u0
			var m1 := cell.r * 2.0 + cell.b - u1
			MeshKit.quad(_banner_st, b + Vector3(0, y0, 0), a + Vector3(0, y0, 0), a + Vector3(0, y1, 0), b + Vector3(0, y1, 0), -nrm,
				Vector2(m1, v1), Vector2(m0, v1), Vector2(m0, v0), Vector2(m1, v0))
	_banner_count += 1
	_stats["banners"] = int(_stats.get("banners", 0)) + 1


func _banner_arch(corners: Array) -> void:
	if corners.is_empty():
		return
	# over the straight leading into the first corner after the start
	var s0: int = track.start_index
	var best: Array = corners[0]
	var best_d := 1 << 30
	for c in corners:
		var d := _idx(int(c[2]) - s0)
		if d > 60 and d < best_d:
			best_d = d
			best = c
	var i: int = _idx(int(best[2]) - 30)
	var l := _behind_wall(i, -1.0, 1.0)
	var r := _behind_wall(i, 1.0, 1.0)
	var y := maxf(l.y, r.y)
	var across := (r - l)
	across.y = 0.0
	var width := across.length()
	var x := across.normalized()
	var z := Vector3.UP.cross(x).normalized()
	if z.dot(-track.tangents[i]) < 0.0:
		z = -z
		x = -x
	var basis := Basis(x, Vector3.UP, z)
	add("banner_tower", Transform3D(basis, Vector3(l.x, l.y, l.z)))
	add("banner_tower", Transform3D(basis, Vector3(r.x, r.y, r.z)))
	var mid := (l + r) * 0.5
	mid.y = y + 6.0
	var bw := minf(width - 1.2, 22.0)
	var h := bw / 8.0
	add("bill", Transform3D(Basis(x * bw, Vector3.UP * h, z), mid), SignAtlas.cell("banner", "drift_zone"))
	add("bill", Transform3D(Basis(-x * bw, Vector3.UP * h, -z), mid - z * 0.2), SignAtlas.cell("banner", "series"))
	scenery.occupy(l, 1.2)
	scenery.occupy(r, 1.2)


# ---------------------------------------------------------------------------
# Street furniture
# ---------------------------------------------------------------------------
func _benches(count: int) -> void:
	var n: int = track.sample_count()
	var placed := 0
	var tries := 0
	while placed < count and tries < 200:
		tries += 1
		var i := rng.randi_range(0, n - 1)
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var pos := _behind_wall(i, side, rng.randf_range(2.5, 4.5))
		var nrm: Vector3 = terrain.normal_at(pos.x, pos.z)
		if nrm.y < 0.93 or not scenery.free_at(pos, 1.6, 1.0):
			continue
		# bench looks at the road
		var z: Vector3 = -track.rights[_idx(i)] * side
		var basis := Basis(Vector3.UP.cross(z).normalized(), Vector3.UP, z)
		add("bench", Transform3D(basis, pos))
		add("bin", Transform3D(basis, pos + basis.x * 1.4))
		scenery.occupy(pos, 2.0)
		placed += 1


## A bus stop with shelter, sign and bench near the houses.
func add_bus_stop(i: int, side: float) -> void:
	var pos := _behind_wall(i, side, 3.2)
	if not scenery.free_at(pos, 2.5, 1.0):
		return
	var z: Vector3 = -track.rights[_idx(i)] * side
	var basis := Basis(Vector3.UP.cross(z).normalized(), Vector3.UP, z)
	add("bus_shelter", Transform3D(basis, pos))
	Colliders.add_box(self, Transform3D(basis, pos + Vector3(0, 1.3, 0)), Vector3(3.6, 2.6, 1.5))
	_sign(pos + basis.x * 2.4 + basis.z * 0.6, _facing(i, side, 0.0), "bus", Vector2(0.55, 0.55), 1.9)
	add("bin", Transform3D(basis, pos - basis.x * 2.3))
	scenery.occupy(pos, 3.0)


func _harbor_extras() -> void:
	var n: int = track.sample_count()
	# cones stacked beside the pit area
	var s0: int = track.start_index
	for j in 6:
		var pos := _behind_wall(s0 + 20 + j, 1.0, 1.6 + (j % 2) * 0.5)
		add("cone", Transform3D(Basis(Vector3.UP, rng.randf() * TAU), pos))


static var _tyre_meshes: Array = []
static var _tyre_shape: CylinderShape3D


## A stack of `levels` loose tyres standing on the ground at `pos`: every tyre is its own rigid body.
func loose_tyre_stack(pos: Vector3, levels: int) -> void:
	if _tyre_meshes.is_empty():
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.roughness = 0.9
		for k in 2:
			var one := MeshKit.new_st()
			Props._vlathe(one, [Vector2(0.18, -0.11), Vector2(0.3, -0.12), Vector2(0.33, 0.0), Vector2(0.3, 0.12), Vector2(0.18, 0.11)], 14,
				Color(0.06, 0.06, 0.065) if k == 0 else Color(0.88, 0.88, 0.86))
			Props._vlathe(one, [Vector2(0.18, 0.11), Vector2(0.17, 0.0), Vector2(0.18, -0.11)], 14, Color(0.03, 0.03, 0.03))
			_tyre_meshes.append(MeshKit.commit(one, mat))
		_tyre_shape = CylinderShape3D.new()
		_tyre_shape.radius = 0.33
		_tyre_shape.height = 0.24
	var g: float = terrain.height_at(pos.x, pos.z)
	for k in levels:
		var b := RigidBody3D.new()
		b.mass = 9.0
		b.collision_layer = 8     # props
		b.collision_mask = 1 | 2 | 4 | 8
		var pm := PhysicsMaterial.new()
		pm.friction = 0.7
		pm.bounce = 0.12
		b.physics_material_override = pm
		var mi := MeshInstance3D.new()
		mi.mesh = _tyre_meshes[1 if k == 2 else 0]
		b.add_child(mi)
		var cs := CollisionShape3D.new()
		cs.shape = _tyre_shape
		b.add_child(cs)
		add_child(b)
		b.global_transform = Transform3D(Basis(Vector3.UP, rng.randf() * TAU),
			Vector3(pos.x + rng.randf_range(-0.03, 0.03), g + 0.125 + k * 0.245, pos.z + rng.randf_range(-0.03, 0.03)))
		b.sleeping = true
	_stats["tyres"] = int(_stats.get("tyres", 0)) + levels


func _tyre_stacks(corners: Array) -> void:
	# tyre walls on the inside of the tightest corners, behind the barrier
	var by_peak := corners.duplicate()
	by_peak.sort_custom(func(a, b): return float(a[4]) > float(b[4]))
	for c in by_peak.slice(0, 3):
		var side := -float(c[1])   # inside
		var apex: int = c[0]
		for k in range(-6, 7, 2):
			var pos := _behind_wall(apex + k, side, 0.6)
			if scenery.free_at(pos, 0.4, 0.2):
				loose_tyre_stack(pos, 4)
				loose_tyre_stack(pos + track.tangents[_idx(apex + k)] * 0.7, 4)

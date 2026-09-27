extends Node3D
## The Playground: a huge asphalt pad around the figure-eight track, closed by a concrete barrier
## with sponsor boards, and full of physics toys – cone slaloms and donut circles, oil barrels,
## tyre stacks, water barriers and wooden crates / cardboard boxes that break apart when hit.
## Props are simulated locally (not synced online).

const MeshKit = preload("res://scripts/util/mesh_kit.gd")
const TexKit = preload("res://scripts/util/tex_kit.gd")
const Props = preload("res://scripts/world/prop_meshes.gd")
const SignAtlas = preload("res://scripts/world/sign_atlas.gd")
const Houses = preload("res://scripts/world/houses.gd")

const PROP_LAYER := 8
const PROP_MASK := 1 | 2 | 4 | 8
const MAX_DEBRIS := 160

var track
var terrain
var scenery
var rng := RandomNumberGenerator.new()
var _meshes := {}
var _shapes := {}
var _debris: Array = []
var _stats := {}


func build(p_track, p_terrain, p_scenery, quality: int) -> void:
	track = p_track
	terrain = p_terrain
	scenery = p_scenery
	rng.seed = 4242
	_make_assets()
	_perimeter()
	var free_spots := _open_spots()
	_donut_circles(free_spots, 2)
	_slaloms(free_spots, 3)
	_barrel_clusters(free_spots, 14 if quality >= 1 else 8)
	_crate_stacks(free_spots, 10)
	_box_walls(free_spots, 4)
	_tyre_stacks(free_spots, 12)
	_water_barriers()
	print("PLAYGROUND: ", _stats)


# ---------------------------------------------------------------------------
# Assets
# ---------------------------------------------------------------------------
func _vc_material(rough := 0.7, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = rough
	m.metallic = metal
	return m


func _make_assets() -> void:
	# oil drums in three paints
	for col in [Color(0.75, 0.1, 0.08), Color(0.1, 0.3, 0.7), Color(0.9, 0.7, 0.1)]:
		var st := MeshKit.new_st()
		Props._cyl(st, Vector3(0, -0.44, 0), Vector3(0, 0.44, 0), 0.29, 0.29, col, 14)
		for y in [-0.2, 0.2]:
			Props._cyl(st, Vector3(0, y - 0.02, 0), Vector3(0, y + 0.02, 0), 0.3, 0.3, col.darkened(0.3), 14)
		_meshes["barrel_%d" % (_meshes.size())] = MeshKit.commit(st, _vc_material(0.45, 0.4))
	var cone := MeshKit.new_st()
	Props._traffic_cone(cone)
	_meshes["cone"] = MeshKit.commit(cone, _vc_material(0.6))
	var tyres := MeshKit.new_st()
	Props._tyre_stack(tyres)
	_meshes["tyres"] = MeshKit.commit(tyres, _vc_material(0.9))
	var crate_mat := StandardMaterial3D.new()
	crate_mat.albedo_texture = Houses._tex("planks")
	crate_mat.albedo_color = Color(0.72, 0.52, 0.3)
	crate_mat.roughness = 0.85
	var crate := BoxMesh.new()
	crate.size = Vector3(1.0, 1.0, 1.0)
	crate.material = crate_mat
	_meshes["crate"] = crate
	var plank := BoxMesh.new()
	plank.size = Vector3(1.0, 0.1, 0.24)
	plank.material = crate_mat
	_meshes["plank"] = plank
	var card_mat := StandardMaterial3D.new()
	card_mat.albedo_color = Color(0.62, 0.46, 0.28)
	card_mat.roughness = 0.95
	var card := BoxMesh.new()
	card.size = Vector3(0.8, 0.6, 0.6)
	card.material = card_mat
	_meshes["carton"] = card
	var flap := BoxMesh.new()
	flap.size = Vector3(0.6, 0.02, 0.4)
	flap.material = card_mat
	_meshes["flap"] = flap
	var wb := BoxMesh.new()
	wb.size = Vector3(1.8, 0.8, 0.5)
	var wb_mat := StandardMaterial3D.new()
	wb_mat.albedo_color = Color(0.85, 0.12, 0.1)
	wb_mat.roughness = 0.5
	wb.material = wb_mat
	_meshes["water_red"] = wb
	var wb2 := BoxMesh.new()
	wb2.size = Vector3(1.8, 0.8, 0.5)
	var wb2_mat := StandardMaterial3D.new()
	wb2_mat.albedo_color = Color(0.95, 0.95, 0.93)
	wb2_mat.roughness = 0.5
	wb2.material = wb2_mat
	_meshes["water_white"] = wb2
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.29
	cyl.height = 0.88
	_shapes["barrel"] = cyl
	var cone_s := CylinderShape3D.new()
	cone_s.radius = 0.16
	cone_s.height = 0.7
	_shapes["cone"] = cone_s
	var ty := CylinderShape3D.new()
	ty.radius = 0.33
	ty.height = 0.96
	_shapes["tyres"] = ty
	for k in ["crate", "plank", "carton", "flap", "water_red"]:
		var bs := BoxShape3D.new()
		bs.size = (_meshes[k] as BoxMesh).size
		_shapes[k] = bs


func _body(mesh_key: String, shape_key: String, mass: float, xf: Transform3D, mesh_offset := Vector3.ZERO) -> RigidBody3D:
	var b := RigidBody3D.new()
	b.mass = mass
	b.collision_layer = PROP_LAYER
	b.collision_mask = PROP_MASK
	var pm := PhysicsMaterial.new()
	pm.friction = 0.7
	pm.bounce = 0.12
	b.physics_material_override = pm
	b.can_sleep = true
	var mi := MeshInstance3D.new()
	mi.mesh = _meshes[mesh_key]
	mi.position = mesh_offset
	b.add_child(mi)
	var cs := CollisionShape3D.new()
	cs.shape = _shapes[shape_key]
	b.add_child(cs)
	add_child(b)
	b.global_transform = xf
	b.sleeping = true
	_stats[shape_key] = int(_stats.get(shape_key, 0)) + 1
	return b


func _ground(x: float, z: float) -> float:
	return terrain.height_at(x, z)


# ---------------------------------------------------------------------------
# Layout
# ---------------------------------------------------------------------------
## Open asphalt away from the racing line and the start grid, on a 6 m grid.
func _open_spots() -> Array:
	var r: Rect2 = terrain.pad_rect()
	var out: Array = []
	var gz := r.position.y + 10.0
	while gz < r.end.y - 10.0:
		var gx := r.position.x + 10.0
		while gx < r.end.x - 10.0:
			var p := Vector3(gx, 0, gz)
			if terrain.pad_sd(p.x, p.z) < -8.0 and track.distance_to_center(p) > float(track.half_w) + 7.0:
				p.y = _ground(p.x, p.z)
				out.append(p)
			gx += 6.0
		gz += 6.0
	out.shuffle()
	return out


## Takes a spot whose surroundings (radius r) are clear of the track and of what was placed already.
func _take(spots: Array, r: float) -> Vector3:
	for i in spots.size():
		var p: Vector3 = spots[i]
		if track.distance_to_center(p) < float(track.half_w) + 3.0 + r:
			continue
		if terrain.pad_sd(p.x, p.z) > -4.0 - r:
			continue
		if not scenery.free_at(p, r, 0.0):
			continue
		spots.remove_at(i)
		scenery.occupy(p, r)
		return p
	return Vector3.INF


func _donut_circles(spots: Array, count: int) -> void:
	for n in count:
		var c := _take(spots, 13.0)
		if c == Vector3.INF:
			return
		for k in 16:
			var a := TAU * k / 16.0
			var p := c + Vector3(cos(a), 0, sin(a)) * 11.0
			p.y = _ground(p.x, p.z) + 0.02
			_body("cone", "cone", 3.0, Transform3D(Basis.IDENTITY, p), Vector3(0, -0.35, 0)).position.y += 0.35
		# a barrel in the middle to circle around
		_body("barrel_0", "barrel", 20.0, Transform3D(Basis.IDENTITY, c + Vector3(0, 0.45, 0)))


func _slaloms(spots: Array, count: int) -> void:
	for n in count:
		var c := _take(spots, 26.0)
		if c == Vector3.INF:
			return
		var dir := Vector3(cos(rng.randf() * TAU), 0, 0)
		dir = Vector3(1, 0, 0) if rng.randf() < 0.5 else Vector3(0, 0, 1)
		for k in 9:
			var p := c + dir * (-48.0 + k * 12.0)
			if terrain.pad_sd(p.x, p.z) > -4.0 or track.distance_to_center(p) < float(track.half_w) + 2.0:
				continue
			p.y = _ground(p.x, p.z) + 0.37
			_body("cone", "cone", 3.0, Transform3D(Basis.IDENTITY, p), Vector3(0, -0.35, 0))


func _barrel_clusters(spots: Array, count: int) -> void:
	for n in count:
		var c := _take(spots, 3.5)
		if c == Vector3.INF:
			return
		var num := rng.randi_range(3, 7)
		var key := "barrel_%d" % rng.randi_range(0, 2)
		for k in num:
			var p := c + Vector3(rng.randf_range(-1.6, 1.6), 0.45, rng.randf_range(-1.6, 1.6))
			if k >= 5:
				p.y += 0.9    # one or two on top
			_body(key, "barrel", 20.0, Transform3D(Basis(Vector3.UP, rng.randf() * TAU), p))


func _crate_stacks(spots: Array, count: int) -> void:
	for n in count:
		var c := _take(spots, 3.0)
		if c == Vector3.INF:
			return
		var yaw := rng.randf() * TAU
		var b := Basis(Vector3.UP, yaw)
		# pyramid: 3 + 2 + 1
		var rows := [[-1.05, 0.0, 1.05], [-0.52, 0.52], [0.0]]
		for lv in rows.size():
			for x in rows[lv]:
				var p: Vector3 = c + b * Vector3(float(x), 0.5 + lv * 1.0, 0)
				_breakable(_body("crate", "crate", 25.0, Transform3D(b, p)), "plank", 6, 5.0)


func _box_walls(spots: Array, count: int) -> void:
	for n in count:
		var c := _take(spots, 4.0)
		if c == Vector3.INF:
			return
		var b := Basis(Vector3.UP, rng.randf() * TAU)
		for lv in 3:
			for k in 5:
				var p: Vector3 = c + b * Vector3(-1.7 + k * 0.84 + (0.42 if lv % 2 == 1 else 0.0), 0.3 + lv * 0.6, 0)
				_breakable(_body("carton", "carton", 4.0, Transform3D(b, p)), "flap", 4, 3.0)


func _tyre_stacks(spots: Array, count: int) -> void:
	for n in count:
		var c := _take(spots, 1.5)
		if c == Vector3.INF:
			return
		_body("tyres", "tyres", 45.0, Transform3D(Basis(Vector3.UP, rng.randf() * TAU), c + Vector3(0, 0.48, 0)), Vector3(0, -0.48, 0))


## Red/white water-filled barriers as chicanes at the edge of the start straight.
func _water_barriers() -> void:
	var s0: int = track.start_index
	var n: int = track.sample_count()
	for side in [-1.0, 1.0]:
		for k in 10:
			var i: int = (s0 + 30 + k + n) % n
			var p: Vector3 = track.samples[i] + track.rights[i] * side * (float(track.half_w) + 3.5)
			p.y = _ground(p.x, p.z) + 0.4
			var b := Basis.looking_at(track.tangents[i], Vector3.UP).rotated(Vector3.UP, PI * 0.5)
			_body("water_red" if k % 2 == 0 else "water_white", "water_red", 60.0, Transform3D(b, p))


# ---------------------------------------------------------------------------
# Breakables
# ---------------------------------------------------------------------------
func _breakable(b: RigidBody3D, piece: String, pieces: int, threshold: float) -> void:
	b.contact_monitor = true
	b.max_contacts_reported = 2
	b.body_entered.connect(_on_hit.bind(b, piece, pieces, threshold))


func _on_hit(other: Node, b: RigidBody3D, piece: String, pieces: int, threshold: float) -> void:
	if not is_instance_valid(b) or b.is_queued_for_deletion():
		return
	if not (other is RigidBody3D):
		return
	var rel := ((other as RigidBody3D).linear_velocity - b.linear_velocity).length()
	# cars smash them; other props only when flying fast
	var car_hit: bool = other.has_method("visual_transform")
	if rel < (threshold if car_hit else threshold * 2.5):
		return
	call_deferred("_smash", b, piece, pieces, (other as RigidBody3D).linear_velocity)


func _smash(b: RigidBody3D, piece: String, pieces: int, hit_vel: Vector3) -> void:
	if not is_instance_valid(b):
		return
	var xf := b.global_transform
	var v0 := b.linear_velocity
	b.queue_free()
	for k in pieces:
		var off := Vector3(rng.randf_range(-0.35, 0.35), rng.randf_range(-0.35, 0.35), rng.randf_range(-0.35, 0.35))
		var p := _body(piece, piece, 2.0 if piece == "plank" else 0.3,
			Transform3D(xf.basis * Basis.from_euler(Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU)), xf * off))
		p.sleeping = false
		p.linear_velocity = v0 + hit_vel * rng.randf_range(0.3, 0.7) + Vector3(rng.randf_range(-2, 2), rng.randf_range(1.5, 4.0), rng.randf_range(-2, 2))
		p.angular_velocity = Vector3(rng.randf_range(-8, 8), rng.randf_range(-8, 8), rng.randf_range(-8, 8))
		_debris.append(p)
	# keep the pile of splinters bounded
	while _debris.size() > MAX_DEBRIS:
		var old = _debris.pop_front()
		if is_instance_valid(old):
			old.queue_free()


# ---------------------------------------------------------------------------
# Perimeter barrier with sponsor boards
# ---------------------------------------------------------------------------
func _perimeter() -> void:
	var r: Rect2 = terrain.pad_rect().grow(-1.5)
	var rad: float = terrain.PAD_CORNER - 1.5
	var c := r.get_center()
	var h := r.size * 0.5 - Vector2(rad, rad)
	var pts: Array = []
	var corners := [[Vector2(h.x, h.y), 0.0], [Vector2(-h.x, h.y), PI * 0.5], [Vector2(-h.x, -h.y), PI], [Vector2(h.x, -h.y), PI * 1.5]]
	for cr in corners:
		var cc: Vector2 = c + (cr[0] as Vector2)
		for k in 13:
			var a: float = float(cr[1]) + PI * 0.5 * k / 12.0
			pts.append(cc + Vector2(cos(a), sin(a)) * rad)
	# resample the loop every ~3 m
	var loop: Array = []
	for i in pts.size():
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[(i + 1) % pts.size()]
		var segs := maxi(1, int(ceil(a.distance_to(b) / 3.0)))
		for k in segs:
			loop.append(a.lerp(b, float(k) / segs))
	var st := MeshKit.new_st()
	var faces := PackedVector3Array()
	var hgt := 1.15
	var n := loop.size()
	for i in n:
		var a2: Vector2 = loop[i]
		var b2: Vector2 = loop[(i + 1) % n]
		var a := Vector3(a2.x, _ground(a2.x, a2.y), a2.y)
		var b := Vector3(b2.x, _ground(b2.x, b2.y), b2.y)
		var inward := Vector3(c.x - (a.x + b.x) * 0.5, 0, c.y - (a.z + b.z) * 0.5).normalized()
		var edge := (b - a).normalized()
		var nrm := edge.cross(Vector3.UP).normalized()
		if nrm.dot(inward) < 0.0:
			nrm = -nrm
		var col := Color(0.85, 0.12, 0.1) if (i / 2) % 2 == 0 else Color(0.92, 0.92, 0.9)
		var out := -nrm * 0.5
		var up := Vector3(0, hgt, 0)
		MeshKit.quad(st, a, b, b + up, a + up, nrm, Vector2.ZERO, Vector2.ONE, Vector2.ONE, Vector2.ZERO, col)
		MeshKit.quad(st, a + up, b + up, b + up + out, a + up + out, Vector3.UP, Vector2.ZERO, Vector2.ONE, Vector2.ONE, Vector2.ZERO, Color(0.7, 0.7, 0.68))
		MeshKit.quad(st, a + out, b + out, b + out + up, a + out + up, -nrm, Vector2.ZERO, Vector2.ONE, Vector2.ONE, Vector2.ZERO, Color(0.6, 0.6, 0.58))
		var hc := Vector3(0, hgt + 0.6, 0)
		faces.append_array(PackedVector3Array([a, b, b + hc, a, b + hc, a + hc]))
		# sponsor boards on top every ~36 m
		if i % 12 == 0 and scenery.details:
			var mid := (a + b) * 0.5 + Vector3(0, hgt + 0.8, 0) + out * 0.5
			var bx := Vector3.UP.cross(nrm).normalized()
			var kinds := ["drift_zone", "kurohana_motors", "takumi_tires", "nitro_x", "series", "safety"]
			scenery.details.add("bill", Transform3D(Basis(bx * 7.0, Vector3.UP * 0.875, nrm), mid),
				SignAtlas.cell("banner", kinds[(i / 12) % kinds.size()]))
	var mat := _vc_material(0.85)
	mat.albedo_texture = TexKit.noise_texture(51, 0.08, false, 256)
	var mi := MeshKit.mesh_instance(MeshKit.commit(st, mat))
	mi.name = "Barrier"
	add_child(mi)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("surface", "wall")
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	add_child(body)

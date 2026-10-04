extends Node3D
## The Utah desert round the track: saguaros (they can be mowed down like trees), barrel cacti and
## dry shrubs, red sandstone boulders and hoodoos with real collision, a rock arch over the road,
## tumbleweeds rolling with the wind, the street signs, traffic lights and hydrants of the street
## pack (they break off when hit) – and Neo Tokyo's fog bank all round, lying on the dunes.

const MeshKit = preload("res://scripts/util/mesh_kit.gd")
const TexKit = preload("res://scripts/util/tex_kit.gd")
const TreeFactory = preload("res://scripts/world/tree_factory.gd")
const Debris = preload("res://scripts/util/debris.gd")
const Sfx = preload("res://scripts/util/sfx_kit.gd")
const CityFog = preload("res://scripts/world/city/city_fog.gd")
const DesertTown = preload("res://scripts/world/desert_town.gd")
const DesertLake = preload("res://scripts/world/desert_lake.gd")

const PACK := "res://assets/props/street_pack/"
const PROP_CELL := 8.0
const BREAK_SPEED := 4.5        # m/s: slower than this a post just stops the car
const WIND := Vector3(1.0, 0.0, 0.35)

const SANDSTONE_SHADER := """
shader_type spatial;
render_mode diffuse_burley;
uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec3 col_a : source_color = vec3(0.6, 0.3, 0.17);
uniform vec3 col_b : source_color = vec3(0.78, 0.5, 0.3);
uniform vec3 col_c : source_color = vec3(0.42, 0.2, 0.12);
varying vec3 wp;
varying vec3 wn;
void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
void fragment() {
	// layered sandstone: wavy strata in red, orange and dark rust, fine grain, sand dust on top
	float n = texture(noise_tex, wp.xz * 0.05 + vec2(wp.y * 0.02, 0.0)).r;
	float band = fract(wp.y * 0.42 + n * 0.9);
	vec3 c = mix(col_a, col_b, smoothstep(0.2, 0.5, band));
	c = mix(c, col_c, smoothstep(0.78, 0.92, band));
	float fine = texture(noise_tex, vec2(wp.x + wp.z, wp.y) * 0.8).r;
	c *= 0.8 + 0.35 * fine;
	c = mix(c, vec3(0.76, 0.56, 0.38), smoothstep(0.55, 0.9, wn.y) * 0.45);
	ALBEDO = c;
	ROUGHNESS = 0.92;
}
"""

var track
var terrain
var scenery
var world
var fog
var rect: Rect2
var stats := {}
var rng := RandomNumberGenerator.new()
var _stone: ShaderMaterial
## breakable street props: {node, xf, r, h, size, centre, down}
var _props: Array = []
var _prop_grid := {}
var _debris: Array = []
var _weeds: Array = []
static var _hulls := {}


func build(p_track, p_terrain, p_scenery, quality: int) -> void:
	track = p_track
	terrain = p_terrain
	scenery = p_scenery
	world = scenery.get_parent()
	rng.seed = 7311
	rect = terrain.desert_rect()
	_stone = ShaderMaterial.new()
	_stone.shader = Shader.new()
	_stone.shader.code = SANDSTONE_SHADER
	_stone.set_shader_parameter("noise_tex", TexKit.noise_texture(417, 0.03))
	# the lake, its ring road, dam and bridges; then the buildings (they level their ground)
	var lake := DesertLake.new()
	lake.name = "Lake"
	add_child(lake)
	await lake.build(track, terrain, scenery)
	stats.merge(lake.stats)
	var town := DesertTown.new()
	town.name = "Town"
	add_child(town)
	await town.build(track, terrain, scenery, rect)
	stats.merge(town.stats)
	_street_signs()
	_arch()
	await Game.load_tick()
	_hoodoos()
	_outcrops()
	_boulders()
	await Game.load_tick()
	_cacti(quality)
	await Game.load_tick()
	_shrubs(quality)
	_tumbleweeds()
	# the edge of the desert: no fog, but whoever drives out past it is turned round
	fog = CityFog.new()
	fog.name = "DesertBorder"
	add_child(fog)
	fog.setup(world, rect, func(x: float, z: float) -> float: return terrain.height_at(x, z),
		"Hier draußen ist nur Wüste – zurück zur Strecke", false)
	print("DESERT: %s" % str(stats))


func set_night(n: float) -> void:
	if fog:
		fog.set_night(n)


# ---------------------------------------------------------------------------
# Placement helpers
# ---------------------------------------------------------------------------
## In the lake or a river, on the ring road or inside it (within `margin`).
func _wet(x: float, z: float, margin: float) -> bool:
	var wt = track.water
	return wt != null and (wt.wet(x, z, margin) or wt.ring_band(x, z, margin) or Vector2(x, z).distance_to(wt.center) < wt.ring_r)

## A free spot on the sand: off the road by `clear` metres, nothing else within `radius`.
func _spot(radius: float, clear: float, tries := 12) -> Variant:
	for _t in tries:
		var x := rng.randf_range(rect.position.x + 8.0, rect.end.x - 8.0)
		var z := rng.randf_range(rect.position.y + 8.0, rect.end.y - 8.0)
		if float(terrain.distance_to_road(x, z)) < float(track.half_w) + clear + radius:
			continue
		if _wet(x, z, radius + 2.0):
			continue
		var p := Vector3(x, 0.0, z)
		if not scenery.free_at(p, radius, 0.0):
			continue
		p.y = terrain.height_at(x, z)
		return p
	return null


func _static_convex(mesh: Mesh, xf: Transform3D, label: String) -> void:
	var body := StaticBody3D.new()
	body.name = label
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("surface", "wall")
	var pts := PackedVector3Array()
	# (the hull of each rock mesh is worked out once)
	if not _hulls.has(mesh):
		_hulls[mesh] = (mesh.create_convex_shape(true, true) as ConvexPolygonShape3D).points
	for v in (_hulls[mesh] as PackedVector3Array):
		pts.append(xf.basis * v)          # the shape takes the (non-uniform) scale, not the body
	var shape := ConvexPolygonShape3D.new()
	shape.points = pts
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	add_child(body)
	body.global_position = xf.origin


func _rock(seed_value: int, xf: Transform3D, collide: bool) -> void:
	var mesh: Mesh = scenery._cached("desert_rock_%d" % seed_value, func(): return TreeFactory.rock(seed_value))
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _stone
	mi.visibility_range_end = 900.0
	add_child(mi)
	mi.global_transform = xf
	if collide:
		_static_convex(mesh, xf, "Boulder")


# ---------------------------------------------------------------------------
# Rocks
# ---------------------------------------------------------------------------
## Red sandstone boulders: big lone ones and heaps of them, smaller ones scattered around.
func _boulders() -> void:
	var seeds := [11, 23, 37, 41, 53]
	for i in 70:
		var big := i < 22
		var s := rng.randf_range(3.5, 8.0) if big else rng.randf_range(1.2, 3.0)
		var p = _spot(s * 1.3, 4.0 if big else 2.5)
		if p == null:
			continue
		scenery.occupy(p, s * 1.2)
		var b := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, rng.randf_range(-0.15, 0.15))
		b = b.scaled(Vector3(s * rng.randf_range(0.8, 1.3), s * rng.randf_range(0.7, 1.15), s * rng.randf_range(0.8, 1.3)))
		_rock(seeds[i % seeds.size()], Transform3D(b, p - Vector3(0, s * 0.18, 0)), true)
		stats["boulders"] = int(stats.get("boulders", 0)) + 1
		# a few smaller ones round the big ones (no collision below half a metre)
		for k in (rng.randi_range(2, 5) if big else rng.randi_range(0, 2)):
			var a := rng.randf() * TAU
			var q: Vector3 = p + Vector3(cos(a), 0, sin(a)) * s * rng.randf_range(1.1, 1.8)
			if float(terrain.distance_to_road(q.x, q.z)) < float(track.half_w) + 2.0:
				continue
			q.y = terrain.height_at(q.x, q.z)
			var ss := s * rng.randf_range(0.12, 0.35)
			var bb := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(ss, ss * rng.randf_range(0.6, 1.0), ss))
			_rock(seeds[(i + k + 1) % seeds.size()], Transform3D(bb, q - Vector3(0, ss * 0.15, 0)), ss > 0.5)


## Rock formations between the loops: heaps of huge sandstone blocks piled up into crags and
## small buttes (10–25 m), smaller blocks tumbled at their feet. Solid.
func _outcrops() -> void:
	var seeds := [11, 23, 37, 41, 53, 61]
	for i in 40:
		var size := rng.randf_range(6.0, 14.0)
		var p = _spot(size * 1.2, 10.0, 30)
		if p == null:
			continue
		scenery.occupy(p, size * 1.1)
		var g: float = p.y
		var blocks := rng.randi_range(4, 9)
		for k in blocks:
			# the big ones low and in the middle, smaller and higher on top, a few sliding off
			var f := float(k) / blocks
			var s := size * lerpf(1.0, 0.45, f) * rng.randf_range(0.8, 1.1)
			var a := rng.randf() * TAU
			var off := Vector3(cos(a), 0, sin(a)) * size * rng.randf_range(0.0, 0.55) * (1.0 - f * 0.6)
			var y := g - s * 0.2 + size * f * rng.randf_range(0.8, 1.5)
			var b := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, rng.randf_range(-0.2, 0.2))
			b = b.scaled(Vector3(s * rng.randf_range(0.8, 1.2), s * rng.randf_range(0.7, 1.3), s * rng.randf_range(0.8, 1.2)))
			_rock(seeds[(i + k) % seeds.size()], Transform3D(b, Vector3(p.x, y, p.z) + off), true)
		for k in rng.randi_range(3, 7):
			var a := rng.randf() * TAU
			var q: Vector3 = p + Vector3(cos(a), 0, sin(a)) * size * rng.randf_range(1.1, 1.7)
			if float(terrain.distance_to_road(q.x, q.z)) < float(track.half_w) + 3.0:
				continue
			q.y = terrain.height_at(q.x, q.z)
			var ss := size * rng.randf_range(0.1, 0.3)
			var bb := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(ss, ss * rng.randf_range(0.6, 1.0), ss))
			_rock(seeds[k % seeds.size()], Transform3D(bb, q - Vector3(0, ss * 0.15, 0)), ss > 0.6)
		stats["outcrops"] = int(stats.get("outcrops", 0)) + 1


## Hoodoos: thin towers of stacked, narrowing stone with a wider cap rock on top.
func _hoodoos() -> void:
	for i in 34:
		var p = _spot(5.0, 10.0)
		if p == null:
			continue
		scenery.occupy(p, 5.0)
		var y: float = p.y - 0.6
		var w := rng.randf_range(2.2, 3.4)
		var parts := rng.randi_range(3, 5)
		for k in parts:
			var hk := rng.randf_range(2.4, 4.0)
			var wk := w * (1.0 - 0.13 * k) * rng.randf_range(0.9, 1.05)
			if k == parts - 1:
				wk = w * 0.95        # the cap rock
				hk *= 0.6
			var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(wk, hk, wk * rng.randf_range(0.85, 1.1)))
			var off := Vector3(rng.randf_range(-0.2, 0.2), 0, rng.randf_range(-0.2, 0.2))
			_rock([23, 37, 53][k % 3], Transform3D(b, Vector3(p.x, y + hk * 0.55, p.z) + off), true)
			y += hk * 1.15
		stats["hoodoos"] = int(stats.get("hoodoos", 0)) + 1


## A natural stone arch spanning the road on a calm stretch: two pillars beside the road and a
## bridge of stone high over it.
func _arch() -> void:
	var n: int = track.sample_count()
	var best := -1
	var best_k := 1e9
	for i in range(int(n * 0.3), int(n * 0.6)):
		var sp: Vector3 = track.samples[i]
		if _wet(sp.x, sp.z, 30.0):
			continue      # (not over the river: the bridges are there)
		var k := 0.0
		for d in range(-15, 16, 3):
			k += absf(float(track.curvature[(i + d) % n]))
		if k < best_k:
			best_k = k
			best = i
	if best < 0:
		return
	var c: Vector3 = track.samples[best]
	var r: Vector3 = track.rights[best]
	var t: Vector3 = track.tangents[best]
	var span: float = float(track.hws[best]) + 5.5
	var top := span + 5.0
	var yaw := atan2(t.x, t.z)
	for k in 13:
		var a := PI * float(k) / 12.0          # from the left pillar over the road to the right one
		var lat := -cos(a) * span
		var h := sin(a) * top
		var p := c + r * lat
		p.y = terrain.height_at(p.x, p.z) + h
		var s := 3.4 if k == 0 or k == 12 else 2.6
		var b := Basis(Vector3.UP, yaw + rng.randf_range(-0.2, 0.2)).scaled(Vector3(s * 1.1, s, s * 1.4))
		_rock([11, 23, 37][k % 3], Transform3D(b, p), h < 4.5)
	# the pillars down to the ground
	for side in [-1.0, 1.0]:
		var p: Vector3 = c + r * span * side
		var g: float = terrain.height_at(p.x, p.z)
		for j in 3:
			var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(3.6, 2.6, 4.0))
			_rock([41, 53, 11][j], Transform3D(b, Vector3(p.x, g + 1.0 + j * 2.2, p.z)), true)
		scenery.occupy(p, 4.5)
	stats["arch"] = best


# ---------------------------------------------------------------------------
# Plants
# ---------------------------------------------------------------------------
func _cacti(quality: int) -> void:
	# three kinds: saguaros (4 shapes), prickly pears and organ pipes (3 shapes each)
	var variants: Array = []
	for v in 4:
		variants.append(scenery._cached("saguaro_%d" % v, func(): return saguaro_mesh(100 + v)))
	for v in 3:
		variants.append(scenery._cached("pear_%d" % v, func(): return pear_mesh(200 + v)))
	for v in 3:
		variants.append(scenery._cached("organ_%d" % v, func(): return organ_mesh(300 + v)))
	var sets: Array = []
	for v in variants.size():
		sets.append({})
	var count: int = [140, 200, 260, 320][clampi(quality, 0, 3)]
	for i in count:
		var p = _spot(1.2, 3.0, 6)
		if p == null:
			continue
		scenery.occupy(p, 1.0)
		var roll := rng.randf()
		var v := rng.randi() % 4
		var kind := "saguaros"
		if roll > 0.45:
			v = 4 + rng.randi() % 3
			kind = "prickly_pears"
		if roll > 0.75:
			v = 7 + rng.randi() % 3
			kind = "organ_pipes"
		var s := rng.randf_range(0.75, 1.25) * (1.0 if v < 4 else rng.randf_range(1.2, 2.2) if v < 7 else 1.0)
		var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s, s)), p - Vector3(0, 0.15, 0))
		scenery._push(sets[v], p, [xf, Color(1, 1, 1, 1)], scenery.usize)
		stats[kind] = int(stats.get(kind, 0)) + 1
	for v in variants.size():
		scenery._emit_chunks(variants[v], sets[v], 0.0, 700.0 if v < 4 else 450.0, "Desert_cactus", true, scenery.usize)
	# small barrel cacti, no collision
	var barrel: Mesh = scenery._cached("barrel_cactus", func(): return barrel_mesh(7))
	var small := {}
	for i in count * 2:
		var p = _spot(0.4, 1.5, 4)
		if p == null:
			continue
		var s := rng.randf_range(0.6, 1.4)
		scenery._push(small, p, [Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s, s)), p - Vector3(0, 0.05, 0)), Color(1, 1, 1, 1)], scenery.usize)
	scenery._emit_chunks(barrel, small, 0.0, 260.0, "Desert_small", false, scenery.usize)


func _shrubs(quality: int) -> void:
	var meshes := [scenery._cached("desert_shrub_0", func(): return shrub_mesh(3)),
		scenery._cached("desert_shrub_1", func(): return shrub_mesh(9))]
	var sets: Array = [{}, {}]
	var count: int = [600, 900, 1300, 1700][clampi(quality, 0, 3)]
	for i in count:
		var x := rng.randf_range(rect.position.x, rect.end.x)
		var z := rng.randf_range(rect.position.y, rect.end.y)
		if float(terrain.distance_to_road(x, z)) < float(track.half_w) + 1.5 or _wet(x, z, 1.0):
			continue
		var p := Vector3(x, terrain.height_at(x, z) - 0.05, z)
		var s := rng.randf_range(0.5, 1.3)
		scenery._push(sets[i % 2], p, [Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.7, 1.1), s)), p), Color(1, 1, 1, 1)], scenery.usize)
	for k in 2:
		scenery._emit_chunks(meshes[k], sets[k], 0.0, 220.0, "Desert_shrub", false, scenery.usize)


## Tumbleweeds: light balls of twigs the wind rolls over the sand (cars knock them about).
func _tumbleweeds() -> void:
	var mesh := tumbleweed_mesh(5)
	for i in 18:
		var b := RigidBody3D.new()
		b.name = "Tumbleweed"
		b.mass = 2.5
		Debris.make(b)
		b.linear_damp = 0.3
		b.angular_damp = 0.2
		var pm := PhysicsMaterial.new()
		pm.bounce = 0.4
		pm.friction = 0.6
		b.physics_material_override = pm
		var r := rng.randf_range(0.35, 0.6)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.scale = Vector3.ONE * r
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		b.add_child(mi)
		var cs := CollisionShape3D.new()
		var sh := SphereShape3D.new()
		sh.radius = r * 0.9
		cs.shape = sh
		b.add_child(cs)
		add_child(b)
		var x := rng.randf_range(rect.position.x, rect.end.x)
		var z := rng.randf_range(rect.position.y, rect.end.y)
		b.global_position = Vector3(x, terrain.height_at(x, z) + r + 0.2, z)
		_weeds.append(b)


# ---------------------------------------------------------------------------
# Street signs (the street pack): beside the road, breakable
# ---------------------------------------------------------------------------
func _street_signs() -> void:
	var n: int = track.sample_count()
	var spots: Array = []     # [sample, side, kind]
	# the start: traffic lights either side, a street name sign
	var s0: int = track.start_index
	spots.append([(s0 + 3) % n, 1.0, "traffic_light_pole"])
	spots.append([(s0 + 3) % n, -1.0, "traffic_light_pole"])
	spots.append([(s0 + n - 12) % n, 1.0, "sign_street_names"])
	# warnings before the tight corners, "no entry" on the outside of the hairpins
	var warn := ["sign_yield", "sign_speed_30", "sign_one_way", "sign_stop", "sign_pedestrian_crossing"]
	var last := -1000
	var w := 0
	for i in n:
		var k := absf(float(track.curvature[i]))
		if k < 1.0 / 30.0 or i - last < 60:
			continue
		last = i
		var before := (i - 22 + n) % n
		var outside := -signf(float(track.curvature[i]))
		spots.append([before, outside, warn[w % warn.size()]])
		w += 1
		if k > 1.0 / 18.0:
			spots.append([i, outside, "sign_no_entry"])
	# a few hydrants and a lone pedestrian signal out in the sand (nobody knows why)
	for j in 10:
		spots.append([rng.randi() % n, 1.0 if rng.randf() < 0.5 else -1.0, "fire_hydrant_red" if j % 2 == 0 else "fire_hydrant_yellow"])
	spots.append([(s0 + n / 2) % n, -1.0, "pedestrian_signal"])
	for sp in spots:
		var i: int = sp[0]
		var side: float = sp[1]
		var kind: String = sp[2]
		var path: String = PACK + kind + ".glb"
		if not ResourceLoader.exists(path):
			continue
		var scene := load(path) as PackedScene
		if scene == null:
			continue
		var lat: float = (float(track.hws[i]) + (2.2 if not kind.begins_with("fire") else 3.0)) * side
		var p: Vector3 = track.edge_point(i, lat)
		p.y = terrain.height_at(p.x, p.z)
		if not scenery.free_at(p, 0.6, 0.0) or _wet(p.x, p.z, 2.0):
			continue
		scenery.occupy(p, 0.6)
		var node := scene.instantiate() as Node3D
		add_child(node)
		# the face (+Z) towards the cars coming along the road
		var xf := Transform3D(Basis.looking_at(track.tangents[i] * Vector3(1, 0, 1), Vector3.UP), p)
		if kind == "sign_no_entry":
			xf.basis = Basis.looking_at(-track.rights[i] * side, Vector3.UP)
		node.global_transform = xf
		_add_prop(node, kind)


func _add_prop(node: Node3D, kind: String) -> void:
	var inv := node.global_transform.affine_inverse()
	var box := AABB()
	var first := true
	for c in node.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		var b: AABB = (inv * mi.global_transform) * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	if first:
		return
	var p := {"node": node, "xf": node.global_transform, "r": clampf(maxf(box.size.x, box.size.z) * 0.25, 0.12, 0.5),
		"box": box, "down": false, "heavy": kind.begins_with("traffic") or kind.begins_with("fire")}
	_props.append(p)
	var o := node.global_position
	var g := Vector2i(int(floor(o.x / PROP_CELL)), int(floor(o.z / PROP_CELL)))
	if not _prop_grid.has(g):
		_prop_grid[g] = []
	_prop_grid[g].append(p)
	stats["signs"] = int(stats.get("signs", 0)) + 1


func _physics_process(delta: float) -> void:
	if world == null:
		return
	Debris.calm(_debris)
	_blow(delta)
	if _prop_grid.is_empty():
		return
	for car in world.cars.values():
		if not is_instance_valid(car) or not car.visible or not (car is RigidBody3D):
			continue
		var rb := car as RigidBody3D
		var v := rb.linear_velocity
		var sp := Vector2(v.x, v.z).length()
		if sp < 0.5:
			continue
		var cp := rb.global_position
		var inv := rb.global_transform.affine_inverse()
		var reach := sp * delta * 2.0
		var c := Vector2i(int(floor(cp.x / PROP_CELL)), int(floor(cp.z / PROP_CELL)))
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				for p in _prop_grid.get(c + Vector2i(dx, dz), []):
					if p["down"]:
						continue
					var o: Vector3 = (p["xf"] as Transform3D).origin
					var lp: Vector3 = inv * o
					var r: float = p["r"]
					if absf(lp.x) < 0.95 + r and absf(lp.z) < 2.2 + r + reach and lp.y > -3.0 and lp.y < 1.5:
						if sp >= BREAK_SPEED:
							_break(p, rb, v)
						else:
							var to := Vector3(o.x - cp.x, 0, o.z - cp.z).normalized()
							var into := v.dot(to)
							if into > 0.0:
								rb.linear_velocity = v - to * into * 1.3


## Snapped off at the foot: the whole sign flies off the way the car went, spinning.
func _break(p: Dictionary, car: RigidBody3D, v: Vector3) -> void:
	p["down"] = true
	var node: Node3D = p["node"]
	var box: AABB = p["box"]
	var xf: Transform3D = node.global_transform
	var b := RigidBody3D.new()
	b.name = "BrokenSign"
	b.mass = 90.0 if p["heavy"] else 25.0
	Debris.make(b)
	b.angular_damp = 0.6
	var centre := box.get_center()
	add_child(b)
	b.global_transform = Transform3D(xf.basis, xf * centre)
	node.reparent(b, true)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(maxf(box.size.x, 0.2), maxf(box.size.y, 0.2), maxf(box.size.z, 0.2))
	cs.shape = shape
	b.add_child(cs)
	var dir := Vector3(v.x, 0, v.z).normalized()
	var spd := minf(Vector2(v.x, v.z).length(), 30.0)
	b.linear_velocity = dir * spd * 0.75 + Vector3.UP * randf_range(1.5, 3.5)
	b.angular_velocity = Vector3.UP.cross(dir) * randf_range(3.0, 7.0) + Vector3(randf_range(-1, 1), randf_range(-2, 2), randf_range(-1, 1))
	_debris.append(b)
	car.apply_central_impulse(-dir * car.mass * spd * (0.08 if p["heavy"] else 0.03))
	Sfx.play(self, "pole_hit", 0.0, xf.origin + Vector3(0, 1.0, 0), randf_range(0.9, 1.15))
	stats["broken"] = int(stats.get("broken", 0)) + 1


## The wind rolls the tumbleweeds along; one that leaves the desert comes back in upwind.
func _blow(_delta: float) -> void:
	for b in _weeds:
		if not is_instance_valid(b):
			continue
		var rb := b as RigidBody3D
		var gust := 0.6 + 0.4 * sin(Time.get_ticks_msec() * 0.0007 + rb.get_instance_id() % 97)
		rb.apply_central_force(WIND.normalized() * rb.mass * 3.2 * gust)
		var p := rb.global_position
		if not rect.grow(-10.0).has_point(Vector2(p.x, p.z)):
			var x := rect.position.x + 15.0 if WIND.x > 0.0 else rect.end.x - 15.0
			var z := rng.randf_range(rect.position.y + 20.0, rect.end.y - 20.0)
			rb.global_position = Vector3(x, terrain.height_at(x, z) + 1.0, z)
			rb.linear_velocity = Vector3.ZERO


# ---------------------------------------------------------------------------
# Meshes
# ---------------------------------------------------------------------------
static func _cactus_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.7
	m.cull_mode = BaseMaterial3D.CULL_DISABLED      # (the needles are single triangles)
	return m


## A ribbed tube along `path` (closed with a dome on top), radius r.
static func _tube(st: SurfaceTool, path: Array, r: float, base_index: int, col: Color) -> int:
	const SEG := 16
	const RIBS := 12.0
	var idx := base_index
	var rings: Array = []
	var dome := 4
	var full: Array = path.duplicate()
	var last: Vector3 = path[path.size() - 1]
	var dir_end: Vector3 = (last - (path[path.size() - 2] as Vector3)).normalized()
	for k in range(1, dome + 1):
		full.append(last + dir_end * r * sin(PI * 0.5 * k / dome))
	var count := full.size()
	for j in count:
		var p: Vector3 = full[j]
		var t: Vector3 = ((full[mini(j + 1, count - 1)] as Vector3) - (full[maxi(j - 1, 0)] as Vector3)).normalized()
		var side := t.cross(Vector3.FORWARD if absf(t.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
		var up := side.cross(t).normalized()
		var rr := r
		if j >= path.size():
			rr = r * cos(PI * 0.5 * float(j - path.size() + 1) / dome)
		for s in SEG + 1:
			var a := TAU * s / SEG
			var rib := 1.0 + 0.08 * cos(a * RIBS)
			var dv := (side * cos(a) + up * sin(a))
			var groove := 0.75 + 0.25 * (0.5 + 0.5 * cos(a * RIBS))
			st.set_color(Color(col.r * groove, col.g * groove, col.b * groove))
			st.set_normal(dv)
			st.add_vertex(p + dv * rr * rib)
		rings.append(idx)
		idx += SEG + 1
		# spines: a little cluster on every rib crest, every other ring (and on the dome)
		if j % 2 == 1 and rr > 0.03:
			for m in int(RIBS):
				var am := TAU * m / RIBS + (0.13 if j % 4 == 1 else 0.0)
				var dm := side * cos(am) + up * sin(am)
				idx = _spine_cluster(st, idx, p + dm * rr * 1.07, dm, t, 0.045 + rr * 0.12)
	for j in count - 1:
		for s in SEG:
			var a: int = rings[j] + s
			var b: int = rings[j + 1] + s
			st.add_index(a)
			st.add_index(b)
			st.add_index(a + 1)
			st.add_index(a + 1)
			st.add_index(b)
			st.add_index(b + 1)
	return idx


## Three pale needles fanning out from `base` (indexed geometry, like the tube it sits on).
static func _spine_cluster(st: SurfaceTool, idx: int, base: Vector3, out: Vector3, along: Vector3, len: float) -> int:
	var spine := Color(0.93, 0.89, 0.72)
	var across := out.cross(along).normalized()
	for k in 3:
		var d := (out + along * (float(k) - 1.0) * 0.45 + across * (0.3 if k == 1 else -0.15)).normalized()
		var w := along.cross(d).normalized() * 0.006
		if w.length() < 0.001:
			w = across * 0.006
		for v in [base - w, base + w, base + d * len]:
			st.set_color(spine)
			st.set_normal(out)
			st.add_vertex(v)
		st.add_index(idx)
		st.add_index(idx + 1)
		st.add_index(idx + 2)
		idx += 3
	return idx


## A saguaro: the ribbed trunk and up to three arms bending up from the side.
static func saguaro_mesh(seed_value: int) -> ArrayMesh:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var col := Color(0.24, 0.38, 0.17)
	var h := r.randf_range(4.8, 7.2)
	var trunk: Array = []
	for k in 9:
		trunk.append(Vector3(0, -0.3 + (h + 0.3) * k / 8.0, 0))
	var idx := _tube(st, trunk, 0.34, 0, col)
	var arms := r.randi_range(1, 3)
	var a0 := r.randf() * TAU
	for k in arms:
		var a := a0 + TAU * k / arms + r.randf_range(-0.4, 0.4)
		var d := Vector3(cos(a), 0, sin(a))
		var y0 := r.randf_range(1.8, h * 0.6)
		var out := r.randf_range(0.7, 1.1)
		var up := r.randf_range(1.2, h - y0 - 0.4)
		var p0 := Vector3(0, y0, 0)
		var path: Array = []
		# out from the trunk, a round elbow, then straight up
		for j in 7:
			var t := float(j) / 6.0
			var q0 := p0
			var q1 := p0 + d * out
			var q2 := p0 + d * out + Vector3.UP * out
			path.append(q0 * (1 - t) * (1 - t) + q1 * 2.0 * t * (1 - t) + q2 * t * t)
		for j in range(1, 4):
			path.append(p0 + d * out + Vector3.UP * (out + (up - out) * j / 3.0))
		idx = _tube(st, path, 0.22, idx, col * 1.05)
	st.set_material(_cactus_material())
	return st.commit()


## An organ pipe cactus: a clump of ribbed stems rising from one base, bending out and up.
static func organ_mesh(seed_value: int) -> ArrayMesh:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var idx := 0
	var stems := r.randi_range(6, 11)
	for k in stems:
		var a := TAU * k / stems + r.randf_range(-0.3, 0.3)
		var d := Vector3(cos(a), 0, sin(a))
		var out := r.randf_range(0.25, 0.7)
		var h := r.randf_range(1.8, 3.8)
		var p0 := d * 0.15 + Vector3(0, -0.2, 0)
		var path: Array = []
		for j in 9:
			var t := float(j) / 8.0
			# out first, then straight up
			var o := out * (1.0 - pow(1.0 - minf(t * 2.5, 1.0), 2.0))
			path.append(p0 + d * o + Vector3(0, h * t, 0))
		var col := Color(0.27, 0.4, 0.19) * r.randf_range(0.85, 1.1)
		col.a = 1.0
		idx = _tube(st, path, r.randf_range(0.11, 0.16), idx, col)
	st.set_material(_cactus_material())
	return st.commit()


## A prickly pear: flat oval pads growing out of each other's rims, spines in little tufts on both
## faces, red fruit on the top pads.
static func pear_mesh(seed_value: int) -> ArrayMesh:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var idx := [0]
	var green := Color(0.32, 0.46, 0.2)
	# [transform of the pad's base point (its plane = local XY, up = +Y), depth]
	var todo: Array = []
	for k in r.randi_range(2, 3):
		var b := Basis(Vector3.UP, r.randf() * TAU) * Basis(Vector3.FORWARD, r.randf_range(-0.35, 0.35))
		todo.append([Transform3D(b, Vector3(r.randf_range(-0.2, 0.2), -0.05, r.randf_range(-0.2, 0.2))), 0])
	while not todo.is_empty():
		var it: Array = todo.pop_back()
		var xf: Transform3D = it[0]
		var depth: int = it[1]
		var w := r.randf_range(0.2, 0.27) * (1.0 - depth * 0.12)
		var h := w * r.randf_range(1.3, 1.55)
		var centre := xf * Vector3(0, h, 0)
		var pxf := Transform3D(xf.basis, centre)
		idx[0] = _pad(st, idx[0], pxf, w, h, 0.045, green * r.randf_range(0.9, 1.1), true)
		if depth < 2:
			for c in r.randi_range(1, 2):
				var ang := r.randf_range(-1.0, 1.0)
				var rim := Vector3(sin(ang) * w * 0.9, cos(ang) * h * 0.95, 0)
				var nb := xf.basis * Basis(Vector3.FORWARD, -ang * 0.9 + r.randf_range(-0.3, 0.3)) * Basis(Vector3.UP, r.randf_range(-0.7, 0.7))
				todo.append([Transform3D(nb, pxf * rim), depth + 1])
		else:
			for f in r.randi_range(1, 3):
				var ang := r.randf_range(-0.8, 0.8)
				var fp := pxf * Vector3(sin(ang) * w, cos(ang) * h + 0.03, 0)
				idx[0] = _pad(st, idx[0], Transform3D(xf.basis, fp), 0.035, 0.05, 0.035, Color(0.65, 0.08, 0.22), false)
	st.set_material(_cactus_material())
	return st.commit()


## An oval pad (or a fruit): a flattened ellipsoid in the local XY plane, tufts of spines on it.
static func _pad(st: SurfaceTool, idx: int, xf: Transform3D, w: float, h: float, th: float, col: Color, spines: bool) -> int:
	const U := 10
	const V := 7
	var start := idx
	for j in V + 1:
		var lat := PI * (float(j) / V - 0.5)
		for i in U + 1:
			var lon := TAU * i / U
			var v := Vector3(cos(lat) * cos(lon) * w, cos(lat) * sin(lon) * h, sin(lat) * th)
			st.set_color(col * (0.85 + 0.15 * absf(sin(lat))))
			st.set_normal((xf.basis * Vector3(v.x / (w * w), v.y / (h * h), v.z / (th * th))).normalized())
			st.add_vertex(xf * v)
			idx += 1
	for j in V:
		for i in U:
			var a := start + j * (U + 1) + i
			var b := a + U + 1
			for q in [a, b, a + 1, a + 1, b, b + 1]:
				st.add_index(q)
	if spines:
		for face in [-1.0, 1.0]:
			for gx in [-0.5, 0.0, 0.5]:
				for gy in [-0.55, -0.1, 0.35, 0.7]:
					var lp := Vector2(gx * w, gy * h)
					if (lp.x * lp.x) / (w * w) + (lp.y * lp.y) / (h * h) > 0.8:
						continue
					var base := xf * Vector3(lp.x, lp.y, face * th * 0.9)
					idx = _spine_cluster(st, idx, base, (xf.basis * Vector3(0, 0, face)).normalized(), (xf.basis * Vector3.UP).normalized(), 0.04)
	return idx


## A squat ribbed barrel cactus.
static func barrel_mesh(seed_value: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var path: Array = []
	for k in 4:
		path.append(Vector3(0, -0.1 + 0.4 * k / 3.0, 0))
	_tube(st, path, 0.28, 0, Color(0.3, 0.42, 0.18))
	st.set_material(_cactus_material())
	return st.commit()


static func _twig(st: SurfaceTool, a: Vector3, b: Vector3, w: float, col: Color) -> void:
	var t := (b - a).normalized()
	var s := t.cross(Vector3.UP if absf(t.y) < 0.9 else Vector3.RIGHT).normalized() * w
	var u := t.cross(s).normalized() * w
	for q in [[s, u], [u, -s]]:
		var o1: Vector3 = q[0]
		for v in [a - o1, a + o1, b + o1 * 0.4, a - o1, b + o1 * 0.4, b - o1 * 0.4]:
			st.set_color(col)
			st.add_vertex(v)


## Sagebrush / dead scrub: a low dome of grey-olive twigs.
static func shrub_mesh(seed_value: int) -> ArrayMesh:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 26:
		var a := r.randf() * TAU
		var el := r.randf_range(0.25, 1.2)
		var len := r.randf_range(0.5, 0.95)
		var d := Vector3(cos(a) * cos(el), sin(el), sin(a) * cos(el))
		var tone := r.randf_range(0.8, 1.1)
		var col := Color(0.42, 0.4, 0.3) * tone if k % 3 else Color(0.36, 0.4, 0.26) * tone
		var mid := d * len * 0.55
		_twig(st, Vector3.ZERO, mid, 0.03, col)
		for j in 2:
			var d2 := (d + Vector3(r.randf_range(-0.5, 0.5), r.randf_range(-0.2, 0.4), r.randf_range(-0.5, 0.5))).normalized()
			_twig(st, mid, mid + d2 * len * 0.5, 0.02, col * 1.1)
	st.generate_normals()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 0.95
	st.set_material(m)
	return st.commit()


## A tumbleweed: a tangle of dry twigs on a unit ball.
static func tumbleweed_mesh(seed_value: int) -> ArrayMesh:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 70:
		var a := Vector3(r.randf_range(-1, 1), r.randf_range(-1, 1), r.randf_range(-1, 1)).normalized() * r.randf_range(0.6, 1.0)
		var b := Vector3(r.randf_range(-1, 1), r.randf_range(-1, 1), r.randf_range(-1, 1)).normalized() * r.randf_range(0.6, 1.0)
		_twig(st, a, a.lerp(b, 0.6), 0.025, Color(0.55, 0.45, 0.3) * r.randf_range(0.8, 1.15))
	st.generate_normals()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 0.95
	st.set_material(m)
	return st.commit()

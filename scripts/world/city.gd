extends Node3D
## Neo Tokyo: the whole city around the race route. An organic network of connected streets
## (city/street_net.gd) with everything along them (city/streets.gd); detailed 3D buildings on lots
## facing their streets – shops at street level, towers in the high-rise district inside the expressway
## loop (city/buildings.gd); special places (city/places.gd): coffee and donut shops, ramen bar, sushi,
## izakaya, the iApfel store, konbinis, supermarkets with car parks, a multi-storey car park, coin
## parking, gas station, bowling, police HQ, karaoke and pachinko; parks with cherry trees, a fountain
## and a playground; the scramble crossing with its video walls and crowds; the elevated expressway;
## ads and neon everywhere, real light at night (city/city_lights.gd), pigeons (city/pigeons.gd).
## Prepared for free roam: the network hands out spawn points, every street is drivable, and the
## barriers closing the side streets in race mode can be taken away (set_race_closures).

const MeshKit = preload("res://scripts/util/mesh_kit.gd")
const TexKit = preload("res://scripts/util/tex_kit.gd")
const Props = preload("res://scripts/world/prop_meshes.gd")
const Crowd = preload("res://scripts/world/crowd.gd")
const Colliders = preload("res://scripts/util/colliders.gd")
const TreeFactory = preload("res://scripts/world/tree_factory.gd")
const StreetNet = preload("res://scripts/world/city/street_net.gd")
const CityMesh = preload("res://scripts/world/city/city_mesh.gd")
const Buildings = preload("res://scripts/world/city/buildings.gd")
const Places = preload("res://scripts/world/city/places.gd")
const Streets = preload("res://scripts/world/city/streets.gd")
const CityLights = preload("res://scripts/world/city/city_lights.gd")
const CityLamps = preload("res://scripts/world/city/city_lamps.gd")
const FlowerBeds = preload("res://scripts/world/city/flower_beds.gd")
const PhotoWindows = preload("res://scripts/world/city/photo_windows.gd")
const Pigeons = preload("res://scripts/world/city/pigeons.gd")
const CityFog = preload("res://scripts/world/city/city_fog.gd")
const CityAtlas = preload("res://scripts/world/city/city_atlas.gd")

const DOWNTOWN := Vector2(560.0, -230.0)     # inside the expressway loop: the high-rise district

const SCREEN_SHADER := """
shader_type spatial;
render_mode unshaded;

uniform float glow = 1.0;
uniform float seed = 0.0;

float h(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233)) + seed) * 43758.5453); }

void fragment() {
	float t = TIME * 0.6 + seed * 10.0;
	float scene = floor(t / 4.0);
	vec2 uv = UV;
	vec3 a = vec3(h(vec2(scene, 1.0)), h(vec2(scene, 2.0)), h(vec2(scene, 3.0)));
	vec3 b = vec3(h(vec2(scene, 4.0)), h(vec2(scene, 5.0)), h(vec2(scene, 6.0)));
	float wave = 0.5 + 0.5 * sin(uv.x * 9.0 + t * 3.0 + sin(uv.y * 6.0 + t));
	vec3 c = mix(a, b, wave);
	float blob = smoothstep(0.32, 0.28, length((uv - vec2(0.5 + 0.15 * sin(t), 0.45)) * vec2(1.6, 1.0)));
	c = mix(c, vec3(1.0, 0.95, 0.85), blob * 0.7);
	if (uv.y > 0.85) {
		float tick = step(0.5, fract(uv.x * 14.0 - t * 2.0)) * step(0.88, uv.y) * step(uv.y, 0.96);
		c = mix(vec3(0.05), vec3(1.0, 0.9, 0.2), tick);
	}
	vec2 px = fract(uv * vec2(160.0, 90.0));
	c *= 0.75 + 0.25 * step(0.15, px.x) * step(0.15, px.y);
	ALBEDO = c * (0.35 + 0.65 * glow);
}
"""

const PETAL_SHADER := """
shader_type spatial;
render_mode cull_disabled, diffuse_burley;

void fragment() {
	ALBEDO = vec3(1.0, 0.72, 0.84);
	ROUGHNESS = 0.8;
}
"""

const SPECIALS := [
	# [kind, width, depth, count, near the race route]
	["iapfel", 26.0, 22.0, 1, true], ["coffee", 13.0, 14.0, 2, true], ["donut", 12.0, 12.0, 2, true],
	["ramen", 8.0, 12.0, 3, true], ["sushi", 11.0, 14.0, 1, true], ["izakaya", 11.0, 14.0, 2, true],
	["konbini", 17.0, 14.0, 3, true], ["karaoke", 20.0, 16.0, 1, true], ["pachinko", 22.0, 18.0, 1, true],
	["bowling", 40.0, 26.0, 1, true], ["police", 38.0, 36.0, 1, true], ["gas", 32.0, 26.0, 1, true],
	["supermarket", 60.0, 76.0, 2, false], ["garage", 54.0, 44.0, 2, false], ["coin_parking", 20.0, 18.0, 5, false],
]

var track
var terrain
var scenery
var quality := 2
var net
var cm
var bld
var places
var streets
var lights_node
var lamps
var pigeons
var rng := RandomNumberGenerator.new()
var emitters: Array = []
var builds: Array = []
var lots: Array = []
var parks: Array = []
var halls: Array = []        # towers with a drive-in entrance hall (builds entries)
var groves: Array = []       # small green corners between the buildings: [centre, half size, along]
var flowers                  # flower_beds.gd
var photo_windows            # photo_windows.gd
var plazas: Array = []
var pigeon_spots: Array = []
var _sets := {}
var _meshes := {}
var _screen_mats: Array = []
var _sakura_spots: Array = []
var _crossing_i := 0
var _stats := {}
var fog


func build(p_track, p_terrain, p_scenery, p_quality: int) -> void:
	track = p_track
	terrain = p_terrain
	scenery = p_scenery
	quality = p_quality
	rng.seed = 8128
	_lap("")
	CityAtlas.ensure_painted(self)
	net = StreetNet.new()
	net.build(track)
	_lap("net")
	_crossing_i = track.index_at(net.crossing_progress)
	# openings in the race route's walls wherever a street joins it
	for j in net.junctions:
		var half: float = float(j["w"]) * 0.5 + 2.0
		track.wall_gaps.append([fposmod(float(j["progress"]) - half, track.length), fposmod(float(j["progress"]) + half, track.length), j["side"]])
	track.rebuild_walls()
	await Game.load_tick()
	cm = CityMesh.new(track.road_material)
	_make_inst_meshes()
	_crossing_plazas()
	var runs := _slots()
	_layout_specials(runs)
	_drive_ins()
	await Game.load_tick()
	_layout_frontage(runs)
	await Game.load_tick()
	_layout_interior()
	_lap("layout")
	await Game.load_tick()
	# geometry
	_round_towers()
	_mark_blind_faces()
	_halls_and_plinths()
	bld = Buildings.new(cm)
	var body := StaticBody3D.new()
	body.name = "BuildingColliders"
	body.collision_layer = Colliders.LAYER_WORLD
	body.collision_mask = 0
	add_child(body)
	for k in builds.size():
		var b: Dictionary = builds[k]
		bld.building(b)
		if b.has("boxes"):
			# drive-in halls, raised floors with steps: their own set of boxes
			for bx in b["boxes"]:
				var bcs := CollisionShape3D.new()
				var bsh := BoxShape3D.new()
				bsh.size = bx[1]
				bcs.shape = bsh
				bcs.transform = bx[0]
				body.add_child(bcs)
			continue
		var cs := CollisionShape3D.new()
		if b["style"] == "round":
			var cy := CylinderShape3D.new()
			cy.radius = minf(float(b["w"]), float(b["d"])) * 0.5
			cy.height = float(b["h"])
			cs.shape = cy
		else:
			var bs := BoxShape3D.new()
			bs.size = Vector3(float(b["w"]), float(b["h"]), float(b["d"]))
			cs.shape = bs
		cs.transform = Transform3D(Basis(b["ax"], Vector3.UP, b["az"]), (b["c"] as Vector3) + Vector3(0, float(b["h"]) * 0.5, 0))
		body.add_child(cs)
		if k % 150 == 149:
			await Game.load_tick()
	photo_windows = PhotoWindows.new()
	photo_windows.name = "PhotoWindows"
	add_child(photo_windows)
	photo_windows.build(bld.photo_spots)
	_lap("buildings")
	places = Places.new()
	places.setup(cm, self, scenery, _add, _light, _person)
	for l in lots:
		places.build(l[0], l[1])
	_lap("places")
	await Game.load_tick()
	streets = Streets.new()
	lamps = CityLamps.new()
	lamps.name = "Streetlights"
	lamps.emitters = emitters
	add_child(lamps)
	streets.lamps = lamps
	streets.keep_clear = drive_ins
	cm.ground = func(x: float, z: float) -> float: return maxf(float(terrain.height_at(x, z)), 0.0)
	streets.build(net, cm, track, scenery, _add, _light, self)
	cm.ground = Callable()
	_lap("streets")
	_race_route_lights()
	_route_markings()
	_viaduct()
	_crossing_extras()
	flowers = FlowerBeds.new()
	flowers.name = "FlowerBeds"
	add_child(flowers)
	for p in parks:
		_park(p[0], p[1])
	for g in groves:
		_grove(g[0], g[1], g[2])
	_hall_extras()
	_pedestrians()
	_lap("extras")
	await Game.load_tick()
	for f in bld.far:
		_add({"tower": "far_tower", "round": "far_round"}.get(f[1], "far_block"), f[0], Color(1, 1, 1, 1))
	cm.commit(self, {"frame": 620.0, "metal": 360.0, "glass": 620.0, "sign": 460.0, "glow": 620.0, "road": 900.0, "line": 320.0})
	_lap("commit")
	for kind in _sets.keys():
		var m: Array = _meshes[kind]
		scenery._emit_chunks(m[0], _sets[kind], float(m[3]), float(m[1]), "City_" + kind, bool(m[2]), 96.0)
	_lap("instances")
	_sakura_petals()
	emitters.append_array(bld.emitters)
	lights_node = CityLights.new()
	lights_node.name = "CityLights"
	add_child(lights_node)
	lights_node.setup(emitters, quality)
	pigeons = Pigeons.new()
	pigeons.name = "Pigeons"
	add_child(pigeons)
	var world = scenery.get_parent()
	pigeons.cars = func() -> Array:
		var out: Array = []
		if world != null and "cars" in world:
			for c in world.cars.values():
				if is_instance_valid(c):
					out.append([c.global_position, float(c.speed)])
		return out
	_flocks()
	lamps.build(world)
	flowers.build(world)
	# low fog along the city's square border, a little in from its edge: it turns you round
	fog = CityFog.new()
	fog.name = "BorderFog"
	add_child(fog)
	fog.setup(world, net.area.grow(-3.0))
	_stats.merge({"streets": net.streets.size(), "junctions": net.junctions.size(), "parks": parks.size(), "lots": lots.size()})
	_stats.merge(bld.stats)
	_stats.merge(places.stats)
	_stats.merge(streets.stats)
	_stats.merge(cm.stats)
	_stats["lights"] = emitters.size()
	_stats["pigeons"] = pigeons.stats.get("pigeons", 0)
	_lap("rest")
	print("CITY: %s" % str(_stats))
	print("CITY TIMES (ms): %s" % str(_times))


var _times := {}
var _t_last := 0


func _lap(label: String) -> void:
	var now := Time.get_ticks_msec()
	if label != "":
		_times[label] = now - _t_last
	_t_last = now


func set_night(n: float) -> void:
	if photo_windows:
		photo_windows.set_night(n)
	if cm:
		cm.set_night(n)
	if lamps:
		lamps.set_night(n)
	if fog:
		fog.set_night(n)
	if lights_node:
		lights_node.set_night(n)
	for m in _screen_mats:
		(m as ShaderMaterial).set_shader_parameter("glow", lerpf(0.75, 1.0, n))


## Free roam: take the barriers off the side streets (or put them back for a race).
func set_race_closures(on: bool) -> void:
	for b in streets.closures:
		if is_instance_valid(b):
			b.visible = on
			b.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
			(b as RigidBody3D).collision_layer = 8 if on else 0


func spawn_points(count: int) -> Array:
	return net.spawn_points(count)


# ---------------------------------------------------------------------------
# Instanced meshes (trees, people, street furniture, far buildings)
# ---------------------------------------------------------------------------
func _add(kind: String, xf: Transform3D, custom := Color(1, 1, 1, 1)) -> void:
	if not _sets.has(kind):
		_sets[kind] = {}
	scenery._push(_sets[kind], xf.origin, [xf, custom], 96.0)
	_stats[kind] = int(_stats.get(kind, 0)) + 1


func _light(p: Vector3, col: Color, range_m: float, energy: float, kind := 0) -> void:
	emitters.append([p, col, range_m, energy, kind])


func _person(p: Vector3, look_at: Vector3, shirt = null) -> void:
	var d := look_at - p
	d.y = 0.0
	if d.length() < 0.01:
		d = Vector3(0, 0, -1)
	var sc := rng.randf_range(0.9, 1.06)
	var c: Color = Crowd.SHIRTS[rng.randi() % Crowd.SHIRTS.size()]
	if shirt is Color:
		c = shirt
	elif rng.randf() < 0.45:
		c = [Color(0.08, 0.08, 0.1), Color(0.2, 0.2, 0.24), Color(0.92, 0.92, 0.94)][rng.randi() % 3]
	_add("person", Transform3D(Basis.looking_at(d.normalized(), Vector3.UP) * Basis.from_scale(Vector3(sc, sc, sc)), p), Color(c.r, c.g, c.b, rng.randf()))


func _make_inst_meshes() -> void:
	# [mesh, range end, shadows, range begin]
	_meshes["person"] = [Crowd.person_mesh(), 240.0, true, 0.0]
	_meshes["sakura"] = [TreeFactory.sakura(311, 1.0), 420.0, true, 0.0]
	_meshes["tree"] = [TreeFactory.deciduous(121, 1.0), 420.0, true, 0.0]
	for k in ["hydrant", "bicycle", "bench", "bin"]:
		_meshes[k] = [Props.get_mesh(k), 160.0, k == "bench", 0.0]
	var pm := Props.material()
	var st := MeshKit.new_st()
	Props._b(st, Vector3(0, 0.03, 0), Vector3(1.3, 0.06, 1.3), Color(0.25, 0.25, 0.27, 0.5))
	Props._b(st, Vector3(0, 0.05, 0), Vector3(1.1, 0.04, 1.1), Color(0.18, 0.13, 0.09))
	_meshes["tree_pit"] = [MeshKit.commit(st, pm), 120.0, false, 0.0]
	st = MeshKit.new_st()
	for k in 2:
		Props._b(st, Vector3(-0.55 + k * 1.1, 0.92, 0), Vector3(1.0, 1.85, 0.8), [Color(0.85, 0.1, 0.1), Color(0.15, 0.35, 0.85)][k])
		Props._b(st, Vector3(-0.55 + k * 1.1, 0.35, -0.41), Vector3(0.6, 0.2, 0.04), Color(0.1, 0.1, 0.1))
	_meshes["vending"] = [MeshKit.commit(st, pm), 200.0, true, 0.0]
	st = MeshKit.new_st()
	Props._b(st, Vector3(0, 0.55, 0), Vector3(0.45, 1.1, 0.4), Color(0.85, 0.08, 0.06))
	Props._cyl(st, Vector3(0, 1.1, 0), Vector3(0, 1.3, 0), 0.25, 0.22, Color(0.85, 0.08, 0.06), 10)
	Props._b(st, Vector3(0, 0.85, -0.21), Vector3(0.3, 0.05, 0.02), Color(0.1, 0.1, 0.1))
	_meshes["postbox"] = [MeshKit.commit(st, pm), 150.0, true, 0.0]
	st = MeshKit.new_st()
	Props._cyl(st, Vector3.ZERO, Vector3(0, 10.0, 0), 0.16, 0.12, Color(0.6, 0.6, 0.58), 8)
	for y: float in [8.6, 9.5]:
		Props._b(st, Vector3(0, y, 0), Vector3(1.8, 0.1, 0.1), Color(0.35, 0.35, 0.37, 0.6))
	Props._cyl(st, Vector3(0.3, 6.8, 0), Vector3(0.3, 7.6, 0), 0.25, 0.25, Color(0.55, 0.57, 0.6, 0.6), 8)
	Props._b(st, Vector3(0, 2.5, -0.17), Vector3(0.35, 1.2, 0.03), Color(0.95, 0.85, 0.2))
	_meshes["pole"] = [MeshKit.commit(st, pm), 420.0, true, 0.0]
	st = MeshKit.new_st()
	Props._b(st, Vector3(0, 0.5, 0), Vector3(0.1, 1.0, 0.1), Color(0.4, 0.4, 0.42, 0.5))
	Props._b(st, Vector3(0, 1.15, 0), Vector3(0.25, 0.35, 0.2), Color(0.85, 0.85, 0.82))
	_meshes["meter"] = [MeshKit.commit(st, pm), 120.0, false, 0.0]
	# far buildings: a box with the facade texture (beyond the detailed meshes)
	var box := BoxMesh.new()
	box.size = Vector3(0.94, 1.0, 0.94)
	var far_tower := box.duplicate() as BoxMesh
	far_tower.material = _far_material(0, Color(0.5, 0.62, 0.75))
	_meshes["far_tower"] = [far_tower, 2400.0, false, 520.0]
	var far_round := CylinderMesh.new()
	far_round.top_radius = 0.5
	far_round.bottom_radius = 0.5
	far_round.height = 1.0
	far_round.radial_segments = 24
	far_round.rings = 1
	far_round.material = far_tower.material
	_meshes["far_round"] = [far_round, 2400.0, false, 520.0]
	var far_block := box.duplicate() as BoxMesh
	far_block.material = _far_material(1, Color(0.8, 0.78, 0.72))
	_meshes["far_block"] = [far_block, 2400.0, false, 520.0]


func _far_material(kind: int, tint: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = tint
	m.albedo_texture = _facade_texture(kind, false)
	m.emission_enabled = true
	m.emission_texture = _facade_texture(kind, true)
	m.emission = Color(1.0, 0.86, 0.62)
	m.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3(1.0 / 12.0, 1.0 / 12.0, 1.0 / 12.0)
	m.roughness = 0.3 if kind == 0 else 0.75
	m.metallic = 0.4 if kind == 0 else 0.0
	scenery._glow_mats.append([m, 0.0, 1.6])
	return m


## Facade tile = 12 x 12 m (4 floors, 4 bays) for the far boxes. lights = which windows glow at night.
func _facade_texture(kind: int, lights: bool) -> ImageTexture:
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	var r2 := RandomNumberGenerator.new()
	r2.seed = 91 + kind * 13 + (1 if lights else 0)
	img.fill(Color(0, 0, 0) if lights else Color(0.85, 0.85, 0.85))
	var cell := n / 4
	for fy in 4:
		for bx in 4:
			var lit := r2.randf() < 0.3
			var col_lit := Color(1.0, 0.86, 0.6).lerp(Color(0.85, 0.93, 1.0), r2.randf()) * r2.randf_range(0.5, 1.0)
			for y in cell:
				for x in cell:
					var inside := (x > 1 and x < cell - 1 and y > 4 and y < cell - 2) if kind == 0 else (x > 5 and x < cell - 5 and y > 6 and y < cell - 10)
					if lights:
						if inside and lit:
							img.set_pixel(bx * cell + x, fy * cell + y, col_lit)
					elif inside:
						var v := 0.18 + 0.12 * float(y) / cell
						img.set_pixel(bx * cell + x, fy * cell + y, Color(v, v, v * 1.05))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


# ---------------------------------------------------------------------------
# Layout
# ---------------------------------------------------------------------------
## Building lines along every street side and both sides of the race route, as runs of slots:
## {p: point on the building line, t: along, away: away from the street, route, kind, step}.
func _slots() -> Array:
	var runs: Array = []
	var n: int = track.sample_count()
	for side: float in [-1.0, 1.0]:
		var run: Array = []
		for i in range(0, n, 2):
			var s: Vector3 = track.samples[i]
			if s.y > 0.15:
				if not run.is_empty():
					runs.append(run)
					run = []
				continue
			var r: Vector3 = track.rights[i]
			var t: Vector3 = track.tangents[i]
			var off: float = track.off_right[i] if side > 0.0 else track.off_left[i]
			var line := Vector2(s.x + r.x * side * (off + 1.0 + StreetNet.SIDEWALK), s.z + r.z * side * (off + 1.0 + StreetNet.SIDEWALK))
			run.append({"p": line, "t": Vector2(t.x, t.z).normalized(), "away": Vector2(r.x, r.z).normalized() * side, "route": true, "kind": "route", "step": 4.0})
		if not run.is_empty():
			runs.append(run)
	for k in net.streets.size():
		var st: Dictionary = net.streets[k]
		var pts: PackedVector2Array = st["pts"]
		var hw: float = float(st["w"]) * 0.5
		for side: float in [-1.0, 1.0]:
			var run: Array = []
			for j in pts.size() - 1:
				var a := pts[j]
				var b := pts[j + 1]
				var l := a.distance_to(b)
				var t := (b - a) / maxf(l, 0.01)
				var nrm := Vector2(-t.y, t.x) * side
				var q := 0.0
				while q < l:
					var p := a + t * q
					run.append({"p": p + nrm * (hw + StreetNet.SIDEWALK + 0.6), "t": t, "away": nrm, "route": false, "kind": st["kind"], "step": 3.0})
					q += 3.0
			runs.append(run)
	return runs


## A lot of w x d behind the slot's building line (front on the line), or {} when it doesn't fit.
func _try_lot(slot: Dictionary, w: float, d: float) -> Dictionary:
	var t: Vector2 = slot["t"]
	var away: Vector2 = slot["away"]
	var c2: Vector2 = (slot["p"] as Vector2) + away * d * 0.5 + t * w * 0.5
	if not net.rect_is(c2, t, w * 0.5 + 0.4, d * 0.5 + 0.4, [StreetNet.FREE]):
		return {}
	net.mark_rect(c2, t, w * 0.5 + 0.8, d * 0.5 + 0.8, StreetNet.BUILT)
	var away3 := Vector3(away.x, 0, away.y)
	return {"c": Vector3(c2.x, 0, c2.y), "ax": Vector3.UP.cross(away3), "az": away3, "w": w, "d": d}


func _layout_specials(runs: Array) -> void:
	var near: Array = []
	var any: Array = []
	for run in runs:
		for k in range(0, run.size(), 3):
			var s: Dictionary = run[k]
			if bool(s["route"]) or s["kind"] == "crossing":
				near.append(s)
			else:
				any.append(s)
	_shuffle(near)
	_shuffle(any)
	var placed_at: Array = []
	for spec in SPECIALS:
		for c in int(spec[3]):
			var pools: Array = [near, any] if bool(spec[4]) else [any, near]
			var done := false
			for tries in 2:
				for pool in pools:
					for s in pool:
						var sp: Vector2 = s["p"]
						var too_close := false
						for q in placed_at:
							if q[0] == spec[0] and (q[1] as Vector2).distance_to(sp) < 220.0:
								too_close = true
								break
						if too_close:
							continue
						var scale := 1.0 if tries == 0 else 0.82
						var lot := _try_lot(s, float(spec[1]) * scale, float(spec[2]) * scale)
						if lot.is_empty():
							continue
						lots.append([spec[0], lot])
						placed_at.append([spec[0], sp])
						done = true
						break
					if done:
						break
				if done:
					break
	_stats["specials"] = lots.size()


func _shuffle(a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = a[i]
		a[i] = a[j]
		a[j] = tmp


## The lots a car drives into (car parks, the gas station): the entrance in front of each is kept
## free of street furniture and parking bays, and the race route's barrier opens in front of it.
const DRIVE_IN := ["supermarket", "garage", "coin_parking", "gas"]
var drive_ins: Array = []      # [front centre: Vector2, along: Vector2, half width]


func _drive_ins() -> void:
	var gaps := false
	for l in lots:
		if not DRIVE_IN.has(l[0]):
			continue
		var lot: Dictionary = l[1]
		var c: Vector3 = lot["c"]
		var az: Vector3 = lot["az"]
		var ax: Vector3 = lot["ax"]
		var front := c - az * float(lot["d"]) * 0.5
		var half := clampf(float(lot["w"]) * 0.3, 4.0, 9.0)
		drive_ins.append([Vector2(front.x, front.z), Vector2(ax.x, ax.z).normalized(), half])
		# on the race route: an opening in its barrier
		var pr: Array = track.project(front - az * 1.0, -1)
		var i: int = pr[0]
		var off: float = maxf(float(track.off_left[i]), float(track.off_right[i]))
		if absf(float(pr[2])) < off + StreetNet.SIDEWALK + 6.0 and float(track.samples[i].y) < 0.15:
			track.wall_gaps.append([fposmod(float(pr[1]) - half - 2.0, track.length), fposmod(float(pr[1]) + half + 2.0, track.length), signf(float(pr[2]))])
			gaps = true
	if gaps:
		track.rebuild_walls()


## A share of the towers on the street get a drive-in entrance hall (its opening kept free of
## street furniture and of the race route's barrier); houses and flats without a shop now and then
## stand on a raised basement with steps up to the door.
func _halls_and_plinths() -> void:
	var gaps := false
	for b in builds:
		var style: String = b["style"]
		if style == "tower" and bool(b.get("shop", false)) and float(b["w"]) >= 18.0 and rng.randf() < 0.4:
			b["hall"] = true
			var c: Vector3 = b["c"]
			var az: Vector3 = b["az"]
			var ax: Vector3 = b["ax"]
			var front := c - az * float(b["d"]) * 0.5
			halls.append(b)
			drive_ins.append([Vector2(front.x, front.z), Vector2(ax.x, ax.z).normalized(), Buildings.HALL_GAP * 0.5 + 1.0])
			var pr: Array = track.project(front - az * 1.0, -1)
			var i: int = pr[0]
			var off: float = maxf(float(track.off_left[i]), float(track.off_right[i]))
			if absf(float(pr[2])) < off + StreetNet.SIDEWALK + 6.0 and float(track.samples[i].y) < 0.15:
				var half := Buildings.HALL_GAP * 0.5
				track.wall_gaps.append([fposmod(float(pr[1]) - half - 2.0, track.length), fposmod(float(pr[1]) + half + 2.0, track.length), signf(float(pr[2]))])
				gaps = true
		elif (style == "house" or style == "apartment") and not bool(b.get("shop", false)) and rng.randf() < 0.5:
			b["plinth"] = rng.randf_range(1.2, 1.8)
	if gaps:
		track.rebuild_walls()


## People and flower pots in the drive-in halls.
func _hall_extras() -> void:
	var pots := ["pot_red", "pot_yellow", "pot_purple", "pot_white"]
	for b in halls:
		var c: Vector3 = b["c"]
		var az: Vector3 = b["az"]
		var ax: Vector3 = b["ax"]
		var front := c - az * float(b["d"]) * 0.5
		var hd := Buildings.hall_depth(b)
		var w: float = b["w"]
		for sg in [-1.0, 1.0]:
			for k in 3:
				lamps.add_prop(pots[(k + int(sg > 0)) % 4], front + az * (2.5 + k * (hd - 5.0) * 0.5) + ax * sg * (w * 0.5 - 1.3), ax * -sg)
		for k in rng.randi_range(3, 7):
			var p := front + az * rng.randf_range(2.0, hd - 4.5) + ax * rng.randf_range(-w * 0.3, w * 0.3)
			_person(p, p + Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)))


## Some of the tallest towers become round skyscrapers (city/buildings.gd), every one a different
## design: 8 of the 12 tallest, the designs dealt out in turn.
func _round_towers() -> void:
	var towers: Array = []
	for b in builds:
		if b["style"] == "tower" and minf(float(b["w"]), float(b["d"])) >= 18.0:
			towers.append(b)
	towers.sort_custom(func(x, y): return float(x["h"]) > float(y["h"]))
	var n := 0
	for k in mini(towers.size(), 12):
		if k % 3 == 2:
			continue
		var b: Dictionary = towers[k]
		b["style"] = "round"
		b["variant"] = n
		n += 1
	_stats["round_towers"] = n


## Buildings along every building line: their type, size and height by the area (high-rise district,
## the race route, the ring, back streets).
func _layout_frontage(runs: Array) -> void:
	for run in runs:
		var i := 0
		while i < run.size():
			var s: Dictionary = run[i]
			var pick := _pick(s)
			var lot := _try_lot(s, pick["w"], pick["d"])
			if lot.is_empty():
				lot = _try_lot(s, float(pick["w"]) * 0.7, float(pick["d"]) * 0.7)
				if lot.is_empty():
					i += 1
					continue
				pick["h"] = float(pick["h"]) * 0.8
			lot.merge(pick, false)
			builds.append(lot)
			i += maxi(int(ceil((float(lot["w"]) + rng.randf_range(0.0, 1.5)) / float(s["step"]))), 1)


func _pick(s: Dictionary) -> Dictionary:
	var p: Vector2 = s["p"]
	var down := 1.0 - smoothstep(120.0, 340.0, p.distance_to(DOWNTOWN))
	var main: bool = bool(s["route"]) or s["kind"] == "feeder" or s["kind"] == "crossing"
	var r := rng.randf()
	if down > 0.3 and r < 0.65 * down:
		return {"style": "tower", "w": rng.randf_range(20.0, 32.0), "d": rng.randf_range(20.0, 30.0), "h": rng.randf_range(70.0, 130.0) + down * rng.randf_range(0.0, 100.0), "shop": true}
	if main:
		if r < 0.45:
			return {"style": "zakkyo", "w": rng.randf_range(6.5, 10.0), "d": rng.randf_range(12.0, 17.0), "h": rng.randf_range(14.0, 34.0), "shop": true}
		if r < 0.75:
			return {"style": "office", "w": rng.randf_range(16.0, 28.0), "d": rng.randf_range(14.0, 22.0), "h": rng.randf_range(22.0, 58.0), "shop": rng.randf() < 0.75}
		return {"style": "apartment", "w": rng.randf_range(14.0, 24.0), "d": rng.randf_range(12.0, 17.0), "h": rng.randf_range(15.0, 40.0), "shop": rng.randf() < 0.6}
	if s["kind"] == "ring":
		if r < 0.5:
			return {"style": "apartment", "w": rng.randf_range(16.0, 28.0), "d": rng.randf_range(12.0, 18.0), "h": rng.randf_range(20.0, 48.0), "shop": rng.randf() < 0.4}
		return {"style": "office", "w": rng.randf_range(18.0, 30.0), "d": rng.randf_range(16.0, 24.0), "h": rng.randf_range(25.0, 70.0), "shop": rng.randf() < 0.5}
	if r < 0.3:
		return {"style": "house", "w": rng.randf_range(8.0, 12.0), "d": rng.randf_range(9.0, 12.0), "h": rng.randf_range(6.0, 9.0), "shop": rng.randf() < 0.2}
	if r < 0.6:
		return {"style": "zakkyo", "w": rng.randf_range(6.5, 10.0), "d": rng.randf_range(11.0, 15.0), "h": rng.randf_range(10.0, 26.0), "shop": true}
	return {"style": "apartment", "w": rng.randf_range(12.0, 22.0), "d": rng.randf_range(11.0, 16.0), "h": rng.randf_range(12.0, 32.0), "shop": rng.randf() < 0.3}


## Inside the blocks: parks where there's lots of room, towers and blocks of flats in the rest
## (each turned to face away from the nearest obstacle – usually the street behind the frontage).
func _layout_interior() -> void:
	var clr: PackedFloat32Array = net.clearance()
	var nx: int = net.nx
	var cand: Array = []
	for i in range(0, clr.size(), 3):
		if clr[i] >= 9.0:
			cand.append(Vector2(-clr[i], i))
	cand.sort()
	var placed := 0
	for c: Vector2 in cand:
		var r := -c.x
		var ci := int(c.y)
		var p: Vector2 = net.cell_center(ci)
		if net.value_at(p) != StreetNet.FREE:
			continue
		if r >= 20.0 and parks.size() < 12:
			var far_ok := true
			for pk in parks:
				if Vector2((pk[0] as Vector3).x, (pk[0] as Vector3).z).distance_to(p) < 120.0:
					far_ok = false
			if far_ok:
				var pr := minf(r - 3.0, 46.0)
				net.mark_rect(p, Vector2.RIGHT, pr, pr, StreetNet.RESERVED)
				parks.append([Vector3(p.x, 0, p.y), pr])
				continue
		var size := minf(r * 1.3, 30.0)
		if size < 11.0:
			continue
		# orientation: along the gradient of the clearance field
		var gx := clr[mini(ci + 1, clr.size() - 1)] - clr[maxi(ci - 1, 0)]
		var gz := clr[mini(ci + nx, clr.size() - 1)] - clr[maxi(ci - nx, 0)]
		var g := Vector2(gx, gz)
		var t := Vector2(-g.y, g.x).normalized() if g.length() > 0.01 else Vector2.RIGHT
		if not net.rect_is(p, t, size * 0.5, size * 0.5, [StreetNet.FREE]):
			continue
		var down := 1.0 - smoothstep(120.0, 340.0, p.distance_to(DOWNTOWN))
		# now and then a green corner instead of a building: trees, a flower bed, pots
		if down < 0.6 and groves.size() < 80 and rng.randf() < 0.22:
			net.mark_rect(p, t, size * 0.5, size * 0.5, StreetNet.RESERVED)
			groves.append([Vector3(p.x, 0, p.y), size * 0.5, Vector3(t.x, 0, t.y)])
			continue
		net.mark_rect(p, t, size * 0.5 + 1.0, size * 0.5 + 1.0, StreetNet.BUILT)
		var away3 := Vector3(-t.y, 0, t.x)
		var style := "tower" if down > 0.4 or rng.randf() < 0.25 else ("office" if rng.randf() < 0.5 else "apartment")
		var h := (rng.randf_range(60.0, 120.0) + down * rng.randf_range(20.0, 110.0)) if style == "tower" else rng.randf_range(18.0, 50.0)
		builds.append({"c": Vector3(p.x, 0, p.y), "ax": Vector3.UP.cross(away3), "az": away3, "w": size, "d": size, "h": h, "style": style, "shop": false})
		placed += 1
		if placed > 420:
			break


## Side and back walls with a neighbour right next to them (3 m out is built on all along) are
## bare firewalls: nobody sees those windows, and Tokyo's side walls look like that.
func _mark_blind_faces() -> void:
	for b in builds:
		var blind := [false, false, false, false]
		if b["style"] != "tower":
			var c: Vector3 = b["c"]
			var ax: Vector3 = b["ax"]
			var az: Vector3 = b["az"]
			var w: float = b["w"]
			var d: float = b["d"]
			var faces := [[c + az * d * 0.5, az, ax, w], [c - ax * w * 0.5, -ax, az, d], [c + ax * w * 0.5, ax, az, d]]
			for k in 3:
				var f: Array = faces[k]
				var all := true
				for t: float in [-0.35, 0.0, 0.35]:
					var p: Vector3 = (f[0] as Vector3) + (f[2] as Vector3) * t * float(f[3]) + (f[1] as Vector3) * 3.0
					if net.value_at(Vector2(p.x, p.z)) != StreetNet.BUILT:
						all = false
						break
				blind[k + 1] = all
		b["blind"] = blind


## Four plazas around the scramble crossing (crowds, the koban, pigeons).
func _crossing_plazas() -> void:
	var i := _crossing_i
	var s: Vector3 = track.samples[i]
	var r := Vector2(track.rights[i].x, track.rights[i].z)
	var t := Vector2(track.tangents[i].x, track.tangents[i].z).normalized()
	for side: float in [-1.0, 1.0]:
		var off: float = track.off_right[i] if side > 0.0 else track.off_left[i]
		for sz: float in [-1.0, 1.0]:
			var c := Vector2(s.x, s.z) + r * side * (off + 1.0 + StreetNet.SIDEWALK + 7.0) + t * sz * (8.0 + StreetNet.SIDEWALK + 7.5)
			if net.rect_is(c, t, 7.0, 7.0, [StreetNet.FREE, StreetNet.WALK]):
				net.mark_rect(c, t, 7.0, 7.0, StreetNet.RESERVED)
				plazas.append([Vector3(c.x, 0, c.y), side, sz])


# ---------------------------------------------------------------------------
# Along the race route, the expressway, the crossing
# ---------------------------------------------------------------------------
## The race route like a real expressway: a dashed white line between its two lanes all the way
## round (up on the viaduct too), the speed limit painted in both lanes now and then and ◇ marks
## before the scramble crossing.
func _route_markings() -> void:
	var n: int = track.sample_count()
	var L: float = track.length
	var white := Color(0.93, 0.93, 0.9)
	var lift := Vector3(0, float(track.ROAD_Y) + 0.02, 0)
	var next_num := 160.0
	for i in n:
		var i2 := (i + 1) % n
		var prog := fposmod(float(track.dists[i]) - float(track.start_dist), L)
		if prog < 30.0 or prog > L - 45.0:
			continue                      # the start grid
		if absf(prog - net.crossing_progress) < 16.0:
			continue                      # the zebras of the scramble crossing
		# dashes: 6 m painted, 6 m gap
		if int(prog / 6.0) % 2 == 0:
			var a: Vector3 = track.edge_point(i, -0.08) + lift
			var b: Vector3 = track.edge_point(i, 0.08) + lift
			var c: Vector3 = track.edge_point(i2, 0.08) + lift
			var d: Vector3 = track.edge_point(i2, -0.08) + lift
			cm.quad("line", a, b, c, d, Vector3.UP, white)
		# on the ground: speed numbers in both lanes, diamonds before the crossing
		var flat := absf(float(track.samples[i].y)) < 0.1 and absf(float(track.samples[(i + 3) % n].y)) < 0.1
		var t2 := Vector2(track.tangents[i].x, track.tangents[i].z).normalized()
		var hw: float = track.half_w
		if flat and prog > next_num and absf(prog - net.crossing_progress) > 60.0:
			next_num = prog + 420.0
			for side: float in [-1.0, 1.0]:
				var q: Vector3 = track.edge_point(i, side * hw * 0.42)
				streets._digits("60", Vector2(q.x, q.z), t2, q.y + lift.y, white)
		var to_x: float = float(net.crossing_progress) - prog
		if flat and (absf(to_x - 30.0) < 1.0 or absf(to_x - 50.0) < 1.0):
			for side: float in [-1.0, 1.0]:
				var q: Vector3 = track.edge_point(i, side * hw * 0.42)
				streets._diamond(Vector2(q.x, q.z), t2, q.y + lift.y, white)


func _race_route_lights() -> void:
	var n: int = track.sample_count()
	# both sides every 18 m, staggered (a lamp every 9 m)
	for i in range(0, n, 9):
		if track.samples[i].y > 0.15:
			continue
		var side := 1.0 if (i / 9) % 2 == 0 else -1.0
		if track.in_wall_gap(i, side):
			continue
		var off: float = track.off_right[i] if side > 0.0 else track.off_left[i]
		var p: Vector3 = track.edge_point(i, side * (off + 1.0))
		p.y = 0.0
		streets._streetlight(p, -track.rights[i] * side, float(track.half_w) * 0.8)


func _viaduct() -> void:
	var n: int = track.sample_count()
	var conc := Color(0.66, 0.66, 0.64)
	var dark := Color(0.4, 0.4, 0.41)
	var pier_k := 0
	for i in n:
		var y0: float = track.samples[i].y
		var i2 := (i + 1) % n
		var y1: float = track.samples[i2].y
		if y0 < 0.15 and y1 < 0.15:
			continue
		var l0: float = track.off_left[i] + 0.8
		var r0: float = track.off_right[i] + 0.8
		var l1: float = track.off_left[i2] + 0.8
		var r1: float = track.off_right[i2] + 0.8
		var a: Vector3 = track.edge_point(i, -l0)
		var b: Vector3 = track.edge_point(i, r0)
		var c: Vector3 = track.edge_point(i2, r1)
		var e: Vector3 = track.edge_point(i2, -l1)
		var g0 := minf(y0, 1.6) if y0 > 2.6 else y0 + 0.05
		var g1 := minf(y1, 1.6) if y1 > 2.6 else y1 + 0.05
		var dn0 := Vector3(0, -g0, 0)
		var dn1 := Vector3(0, -g1, 0)
		cm.quad("frame", b + dn0, a + dn0, e + dn1, c + dn1, Vector3.DOWN, dark)
		cm.quad("frame", a + dn0, a, e, e + dn1, -track.rights[i], conc)
		cm.quad("frame", c + dn1, c, b, b + dn0, track.rights[i], conc)
		var hw: float = track.hws[i]
		var hw2: float = track.hws[i2]
		var up := Vector3(0, float(track.ROAD_Y) - 0.005, 0)
		cm.quad("frame", a + up, track.edge_point(i, -hw) + up, track.edge_point(i2, -hw2) + up, e + up, Vector3.UP, dark)
		cm.quad("frame", track.edge_point(i, hw) + up, b + up, c + up, track.edge_point(i2, hw2) + up, Vector3.UP, dark)
		# piers every 24 m where it's high enough – not standing in a street that passes beneath
		if y0 > 3.5 and i % 12 == 0:
			var mid: Vector3 = track.samples[i]
			var m2 := Vector2(mid.x, mid.z)
			if not (net.value_at(m2) == StreetNet.ROAD and net.owner_at(m2) >= 0):
				var r: Vector3 = track.rights[i]
				var t: Vector3 = Vector3(track.tangents[i].x, 0, track.tangents[i].z).normalized()
				var pier_h := y0 - 1.6
				var pb := Basis(r, Vector3.UP, -t)
				cm.box("frame", Transform3D(pb, Vector3(mid.x, pier_h * 0.5, mid.z)), Vector3(2.6, pier_h, 2.2), conc)
				cm.box("frame", Transform3D(pb, Vector3(mid.x, pier_h - 0.8, mid.z)), Vector3(l0 + r0, 1.6, 2.4), conc)
				Colliders.add_box(self, Transform3D(pb, Vector3(mid.x, pier_h * 0.5, mid.z)), Vector3(2.6, pier_h, 2.2))
				pier_k += 1
		# lamps on both walls every 20 m, staggered; lights under the deck too
		if y0 > 1.0 and i % 10 == 0:
			var side := 1.0 if (i / 10) % 2 == 0 else -1.0
			var off: float = track.off_right[i] if side > 0.0 else track.off_left[i]
			var lp: Vector3 = track.edge_point(i, side * (off + 0.25))
			var inward: Vector3 = -track.rights[i] * side
			var lb := Basis.looking_at(inward, Vector3.UP)
			cm.box("metal", Transform3D(lb, lp + Vector3(0, 4.5, 0)), Vector3(0.18, 9.0, 0.18), Color(0.55, 0.56, 0.58, 0.6))
			cm.box("metal", Transform3D(lb, lp + Vector3(0, 8.9, 0) + inward * 1.0), Vector3(0.12, 0.12, 2.0), Color(0.55, 0.56, 0.58, 0.6))
			cm.glow_box(Transform3D(lb, lp + Vector3(0, 8.8, 0) + inward * 2.0), Vector3(0.5, 0.15, 0.9), Color(1.0, 0.86, 0.6), 0.1)
			_light(lp + Vector3(0, 8.6, 0) + inward * 2.0, Color(1.0, 0.82, 0.55), 24.0, 5.0, 1)
			if y0 > 5.0:
				_light(Vector3(lp.x, y0 - 2.2, lp.z) + inward * 6.0, Color(0.85, 0.92, 1.0), 14.0, 1.4, 1)
	for prog in [_highest_progress(-1), _highest_progress(1)]:
		_gantry_sign(prog)
	_stats["piers"] = pier_k


## Progress (m) of the first (dir -1) / last (dir 1) fully raised sample, a bit inside.
func _highest_progress(dir: int) -> float:
	var n: int = track.sample_count()
	var first := -1
	var last := -1
	for k in n:
		var i: int = track.index_at(k * track.SPACING)
		if track.samples[i].y > 8.0:
			if first < 0:
				first = k
			last = k
	return (first + 30) * track.SPACING if dir < 0 else (last - 30) * track.SPACING


func _gantry_sign(progress: float) -> void:
	var i: int = track.index_at(progress)
	var t: Vector3 = Vector3(track.tangents[i].x, 0, track.tangents[i].z).normalized()
	var base: Vector3 = track.samples[i]
	var gb := Basis.looking_at(t, Vector3.UP)
	var span: float = (track.off_left[i] + track.off_right[i]) * 0.5
	var steel := Color(0.55, 0.56, 0.58, 0.5)
	for s: float in [-1.0, 1.0]:
		cm.box("metal", Transform3D(gb, base + gb.x * s * (span + 0.2) + Vector3(0, 3.5, 0)), Vector3(0.4, 7.0, 0.4), steel)
		Colliders.add_box(self, Transform3D(gb, base + gb.x * s * (span + 0.2) + Vector3(0, 3.5, 0)), Vector3(0.4, 7.0, 0.4))
	cm.box("metal", Transform3D(gb, base + Vector3(0, 6.8, 0)), Vector3(span * 2.0 + 0.8, 0.4, 0.4), steel)
	# the green direction board (lit), facing the oncoming cars
	cm.box("frame", Transform3D(gb, base + Vector3(0, 5.5, 0) - t * 0.3), Vector3(span * 1.4, 2.4, 0.15), Color(0.05, 0.42, 0.22))
	cm.sign_box(Transform3D(gb, base + Vector3(0, 5.9, 0) - t * 0.42), Vector3(span * 0.7, 0.7, 0.05), CityAtlas.ad(9), 0.6)


## The scramble crossing: zebra stripes across the avenue and the diagonals, video walls on the
## buildings around it, crowds on the corner plazas, a koban.
func _crossing_extras() -> void:
	var i := _crossing_i
	var c: Vector3 = track.samples[i]
	var t: Vector3 = Vector3(track.tangents[i].x, 0, track.tangents[i].z).normalized()
	var r: Vector3 = track.rights[i]
	var hw: float = track.half_w
	var y := float(track.ROAD_Y) + 0.012
	for s: float in [-1.0, 1.0]:
		_zebra(c + t * s * 10.5 + Vector3(0, y, 0), r, hw * 2.0, 3.8)
	var d1 := (r + t).normalized()
	var d2 := (r - t).normalized()
	_zebra(c + Vector3(0, y + 0.002, 0), d1, 30.0, 3.4)
	_zebra(c + Vector3(0, y + 0.004, 0), d2, 30.0, 3.4)
	# video walls on the buildings facing the crossing
	var screens := 0
	var cand := builds.duplicate()
	cand.sort_custom(func(a, b): return (a["c"] as Vector3).distance_to(c) < (b["c"] as Vector3).distance_to(c))
	for b in cand:
		if screens >= 3 or (b["c"] as Vector3).distance_to(c) > 80.0:
			break
		if float(b["h"]) < 22.0 or float(b["w"]) < 14.0:
			continue
		var az: Vector3 = b["az"]
		var front: Vector3 = (b["c"] as Vector3) - az * float(b["d"]) * 0.5
		_screen(front, -az, minf(float(b["w"]) * 0.8, 20.0), minf(float(b["h"]) - 6.0, 18.0), screens)
		screens += 1
	# crowds waiting on the plazas, the koban on one of them
	for pz in plazas:
		var pc: Vector3 = pz[0]
		for k in (60 if quality >= 1 else 30):
			var pp := pc + Vector3(rng.randf_range(-6.0, 6.0), 0, rng.randf_range(-6.0, 6.0))
			_person(pp, c + t * rng.randf_range(-6.0, 6.0))
	if not plazas.is_empty():
		var kp: Vector3 = plazas[0][0]
		var away := (kp - c)
		away.y = 0.0
		away = away.normalized()
		_koban(kp + away * 3.0, -away)


func _zebra(centre: Vector3, walk: Vector3, length: float, bar: float) -> void:
	var across := Vector3(-walk.z, 0, walk.x).normalized()
	var n := int(length / 0.9)
	for k in n:
		var p := centre + walk * (-length * 0.5 + (k + 0.5) * 0.9)
		cm.box("line", Transform3D(Basis.looking_at(across, Vector3.UP), p), Vector3(0.45, 0.01, bar), Color(0.92, 0.92, 0.9))


func _screen(front: Vector3, n: Vector3, w: float, top: float, k: int) -> void:
	var h := w * 9.0 / 16.0
	var centre := front + n * 0.4 + Vector3(0, maxf(top - h * 0.5, 8.0 + h * 0.5), 0)
	var fb := Basis.looking_at(-n, Vector3.UP)
	cm.box("metal", Transform3D(fb, centre - n * 0.2), Vector3(w + 0.8, h + 0.8, 0.6), Color(0.1, 0.1, 0.11, 0.5))
	var sm := ShaderMaterial.new()
	sm.shader = Shader.new()
	sm.shader.code = SCREEN_SHADER
	sm.set_shader_parameter("seed", float(k) * 3.7)
	_screen_mats.append(sm)
	var q := QuadMesh.new()
	q.size = Vector2(w, h)
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = sm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_transform = Transform3D(fb, centre + n * 0.12)
	_light(centre + n * 8.0, Color(0.7, 0.8, 1.0), 40.0, 2.5, 0)


func _koban(p: Vector3, face: Vector3) -> void:
	var b := Basis.looking_at(face, Vector3.UP)
	var fb := Basis.looking_at(-face, Vector3.UP)
	cm.box("frame", Transform3D(b, p + Vector3(0, 1.6, 0)), Vector3(4.0, 3.2, 3.5), Color(0.55, 0.42, 0.32))
	cm.box("frame", Transform3D(b, p + Vector3(0, 3.35, 0)), Vector3(4.4, 0.3, 3.9), Color(0.3, 0.3, 0.32))
	cm.glow_box(Transform3D(b, p + Vector3(0, 3.0, 0) + face * 1.8), Vector3(0.4, 0.4, 0.1), Color(1.0, 0.08, 0.05), 0.6)
	cm.glow_box(Transform3D(b, p + Vector3(0, 1.3, 0) + face * 1.76), Vector3(2.0, 1.6, 0.04), Color(1.0, 0.95, 0.85), 0.4)
	cm.sign_box(Transform3D(fb, p + Vector3(0, 2.6, 0) + face * 1.8), Vector3(1.8, 0.45, 0.05), CityAtlas.shop(10), 0.8)
	Colliders.add_box(self, Transform3D(b, p + Vector3(0, 1.6, 0)), Vector3(4.0, 3.2, 3.5))
	_light(p + face * 3.0 + Vector3(0, 2.5, 0), Color(1.0, 0.95, 0.85), 8.0, 1.2, 0)


# ---------------------------------------------------------------------------
# Parks
# ---------------------------------------------------------------------------
## A park: lawn (real grass), a ring path and paths across, a fountain, cherry trees and others,
## benches and lamps, a playground, picnics under the blossom, pigeons.
func _park(c: Vector3, r: float) -> void:
	for k in 36:
		var a := TAU * k / 36.0
		for rr in [r * 0.2, r * 0.45, r * 0.7, r * 0.92]:
			scenery._ground_paints.append([c + Vector3(cos(a), 0, sin(a)) * rr, 7.0, Color(0.0, 0.04, 0.0, 0.92)])
	scenery._ground_paints.append([c, 8.0, Color(0.0, 0.04, 0.0, 0.92)])
	var ring: Array = []
	for k in 33:
		var a := TAU * k / 32.0
		ring.append(c + Vector3(cos(a), 0, sin(a)) * r * 0.6)
	scenery.add_path(ring, 3.0, "paving")
	for a: float in [0.3, 0.3 + PI * 0.5]:
		var dir := Vector3(cos(a), 0, sin(a))
		scenery.add_path([c - dir * r * 0.95, c + dir * r * 0.95], 2.6, "paving")
	# fountain: stone basin, water, a lit jet column
	_ring_wall(c, 4.5, 0.6, Color(0.7, 0.68, 0.64))
	var water := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 4.3
	cyl.bottom_radius = 4.3
	cyl.height = 0.1
	cyl.radial_segments = 32
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.1, 0.22, 0.28)
	wm.metallic = 0.5
	wm.roughness = 0.03
	water.mesh = cyl
	water.material_override = wm
	add_child(water)
	water.global_position = c + Vector3(0, 0.45, 0)
	_ring_wall(c, 1.0, 1.4, Color(0.75, 0.73, 0.7))
	cm.glow_box(Transform3D(Basis.IDENTITY, c + Vector3(0, 2.4, 0)), Vector3(0.25, 2.0, 0.25), Color(0.75, 0.9, 1.0), 0.5)
	Colliders.add_box(self, Transform3D(Basis.IDENTITY, c + Vector3(0, 0.3, 0)), Vector3(9.0, 0.6, 9.0))
	_light(c + Vector3(0, 1.0, 0), Color(0.6, 0.85, 1.0), 10.0, 1.6, 0)
	# trees: away from the paths and the fountain
	var n_trees := int(r * r * 0.012) + 8
	for k in n_trees:
		var a := rng.randf() * TAU
		var d := rng.randf_range(r * 0.15, r * 0.95)
		if absf(d - r * 0.6) < 3.0 or d < 7.0:
			continue
		var tp := c + Vector3(cos(a), 0, sin(a)) * d
		if _in_park_bed(c, r, tp):
			continue
		var kind := "sakura" if rng.randf() < 0.65 else "tree"
		var sc := rng.randf_range(0.9, 1.25) * (1.0 if kind == "sakura" else 0.8)
		_add(kind, Transform3D(Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3(sc, sc, sc)), tp))
		if kind == "sakura" and rng.randf() < 0.3:
			# a picnic under the blossom
			var sheet := tp + Vector3(cos(a + 1.0), 0, sin(a + 1.0)) * 3.0
			cm.box("frame", Transform3D(Basis(Vector3.UP, rng.randf() * TAU), sheet + Vector3(0, 0.03, 0)), Vector3(2.0, 0.02, 1.8), [Color(0.2, 0.4, 0.85), Color(0.95, 0.5, 0.65), Color(0.95, 0.85, 0.2)][k % 3])
			for m in rng.randi_range(2, 5):
				_person(sheet + Vector3(rng.randf_range(-1.0, 1.0), 0, rng.randf_range(-1.0, 1.0)), sheet)
	# benches and lamps around the ring path
	for k in 12:
		var a := TAU * (k + 0.5) / 12.0
		var out := Vector3(cos(a), 0, sin(a))
		var bp := c + out * (r * 0.6 + 2.4)
		_add("bench", Transform3D(Basis.looking_at(-out, Vector3.UP), bp))
		if k % 2 == 0:
			var lp := c + out * (r * 0.6 - 2.2)
			cm.box("metal", Transform3D(Basis.IDENTITY, lp + Vector3(0, 2.0, 0)), Vector3(0.12, 4.0, 0.12), Color(0.2, 0.22, 0.2, 0.5))
			cm.glow_box(Transform3D(Basis.IDENTITY, lp + Vector3(0, 4.1, 0)), Vector3(0.4, 0.4, 0.4), Color(1.0, 0.9, 0.7), 0.05)
			_light(lp + Vector3(0, 4.0, 0), Color(1.0, 0.88, 0.68), 12.0, 1.8, 0)
	# playground in one quadrant: slide, swings, sandbox
	var pg := c + Vector3(r * 0.32, 0, -r * 0.32)
	cm.box("frame", Transform3D(Basis.IDENTITY, pg + Vector3(0, 1.0, 0)), Vector3(1.6, 2.0, 1.6), Color(0.9, 0.3, 0.2))
	cm.box("frame", Transform3D(Basis(Vector3(1, 0, 0), 0.6), pg + Vector3(0, 1.0, 2.0)), Vector3(0.8, 0.08, 3.4), Color(0.95, 0.8, 0.1))
	var sw := pg + Vector3(-5.0, 0, 0)
	for x: float in [-1.6, 1.6]:
		cm.box("metal", Transform3D(Basis.IDENTITY, sw + Vector3(x, 1.25, 0)), Vector3(0.1, 2.5, 0.1), Color(0.3, 0.5, 0.8, 0.5))
	cm.box("metal", Transform3D(Basis.IDENTITY, sw + Vector3(0, 2.5, 0)), Vector3(3.4, 0.1, 0.1), Color(0.3, 0.5, 0.8, 0.5))
	for x: float in [-0.7, 0.7]:
		cm.box("frame", Transform3D(Basis.IDENTITY, sw + Vector3(x, 0.5, 0)), Vector3(0.5, 0.05, 0.25), Color(0.2, 0.2, 0.2))
	cm.box("frame", Transform3D(Basis.IDENTITY, pg + Vector3(0, 0.1, -4.0)), Vector3(3.0, 0.2, 3.0), Color(0.85, 0.75, 0.55))
	# flower beds: inside the ring between the paths, and outside it towards the edge
	for k in 4:
		var a := 0.3 + PI * 0.25 + PI * 0.5 * k
		var out := Vector3(cos(a), 0, sin(a))
		flowers.add_bed(c + out * r * 0.38, Vector2(minf(r * 0.3, 9.0), 2.6), -a + PI * 0.5, rng)
		flowers.add_bed(c + out * r * 0.8, Vector2(minf(r * 0.34, 11.0), 3.2), -a + PI * 0.5, rng)
	# flower pots round the fountain (they tumble when hit)
	var pots := ["pot_red", "pot_yellow", "pot_purple", "pot_white"]
	for k in 12:
		var a := TAU * (k + 0.5) / 12.0
		var out := Vector3(cos(a), 0, sin(a))
		lamps.add_prop(pots[k % 4], c + out * 5.6, -out)
	_people_around(c, r * 0.6, 18)
	pigeon_spots.append([c + Vector3(6.0, 0, 0), 14, 3.0])


## A small green corner: lawn, a few trees (fellable), a flower bed in the middle, flower pots on
## the corners, sometimes a bench.
func _grove(c: Vector3, half: float, along: Vector3) -> void:
	var side := Vector3(-along.z, 0, along.x)
	for k in 12:
		var a := TAU * k / 12.0
		scenery._ground_paints.append([c + Vector3(cos(a), 0, sin(a)) * half * 0.55, half * 0.55, Color(0.0, 0.04, 0.0, 0.92)])
	scenery._ground_paints.append([c, half * 0.6, Color(0.0, 0.04, 0.0, 0.92)])
	var bed_l := minf(half * 1.1, 10.0)
	var bed_w := minf(half * 0.5, 3.4)
	flowers.add_bed(c, Vector2(bed_l, bed_w), atan2(-along.z, along.x), rng)
	var n := clampi(int(half * half * 0.07), 4, 12)
	for k in n:
		var tp := c + along * rng.randf_range(-half * 0.85, half * 0.85) + side * rng.randf_range(-half * 0.85, half * 0.85)
		var rel := tp - c
		if absf(rel.dot(along)) < bed_l * 0.5 + 1.5 and absf(rel.dot(side)) < bed_w * 0.5 + 1.5:
			continue      # (not in the bed)
		var kind := "sakura" if rng.randf() < 0.45 else "tree"
		var sc := rng.randf_range(0.8, 1.15) * (1.0 if kind == "sakura" else 0.8)
		_add(kind, Transform3D(Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3(sc, sc, sc)), tp))
	var pots := ["pot_red", "pot_yellow", "pot_purple", "pot_white"]
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var pp := c + along * sx * (bed_l * 0.5 + 0.8) + side * sz * (bed_w * 0.5 + 0.2)
			lamps.add_prop(pots[rng.randi() % 4], pp, -along * sx)
	if rng.randf() < 0.5:
		lamps.add_prop("bench", c + side * (bed_w * 0.5 + 1.6), -side)


## Whether a point lies in (or right beside) one of a park's flower beds (see _park).
func _in_park_bed(c: Vector3, r: float, p: Vector3) -> bool:
	for k in 4:
		var a := 0.3 + PI * 0.25 + PI * 0.5 * k
		var out := Vector3(cos(a), 0, sin(a))
		var tan := Vector3(-out.z, 0, out.x)
		for b in [[r * 0.38, minf(r * 0.3, 9.0), 2.6], [r * 0.8, minf(r * 0.34, 11.0), 3.2]]:
			var rel: Vector3 = p - (c + out * float(b[0]))
			if absf(rel.dot(tan)) < float(b[1]) * 0.5 + 1.5 and absf(rel.dot(out)) < float(b[2]) * 0.5 + 1.5:
				return true
	return false


func _ring_wall(c: Vector3, r: float, h: float, col: Color) -> void:
	for k in 20:
		var a := TAU * (k + 0.5) / 20.0
		var p := c + Vector3(cos(a), 0, sin(a)) * r
		cm.box("frame", Transform3D(Basis(Vector3.UP, -a + PI * 0.5), p + Vector3(0, h * 0.5, 0)), Vector3(TAU * r / 20.0 + 0.05, h, 0.35), col)


func _people_around(c: Vector3, r: float, n: int) -> void:
	for k in n:
		var a := rng.randf() * TAU
		var p := c + Vector3(cos(a), 0, sin(a)) * (r + rng.randf_range(-1.0, 1.0))
		_person(p, p + Vector3(-sin(a), 0, cos(a)))


func _pedestrians() -> void:
	for s in streets.people_spots:
		var p: Vector3 = s[0]
		var f: Vector3 = s[1]
		for k in rng.randi_range(1, 3):
			var pp := p + Vector3(rng.randf_range(-1.0, 1.0), 0, rng.randf_range(-1.0, 1.0))
			_person(pp, pp + f)


func _flocks() -> void:
	for pz in plazas:
		pigeons.add_flock((pz[0] as Vector3) + Vector3(rng.randf_range(-3, 3), 0, rng.randf_range(-3, 3)), rng.randi_range(8, 16), 2.5)
	for s in pigeon_spots:
		pigeons.add_flock(s[0], s[1], s[2])
	# some on the pavements by the shops
	var k := 0
	for l in lots:
		if k >= 14:
			break
		var lot: Dictionary = l[1]
		if l[0] in ["coffee", "donut", "konbini", "ramen", "supermarket"]:
			var front: Vector3 = (lot["c"] as Vector3) - (lot["az"] as Vector3) * (float(lot["d"]) * 0.5 + 2.8)
			pigeons.add_flock(front, rng.randi_range(5, 10), 1.8)
			k += 1


## Falling petals: one particle system per group of cherry trees (visible within ~130 m).
func _sakura_petals() -> void:
	_sakura_spots.clear()
	for key in _sets.get("sakura", {}):
		for it in _sets["sakura"][key]:
			_sakura_spots.append((it[0] as Transform3D).origin)
	if _sakura_spots.is_empty():
		return
	var pm := QuadMesh.new()
	pm.size = Vector2(0.07, 0.05)
	var mat := ShaderMaterial.new()
	mat.shader = Shader.new()
	mat.shader.code = PETAL_SHADER
	pm.material = mat
	var groups := {}
	for p in _sakura_spots:
		var key := Vector2i(int(floor(p.x / 40.0)), int(floor(p.z / 40.0)))
		if not groups.has(key):
			groups[key] = []
		groups[key].append(p)
	for key in groups:
		var pts: Array = groups[key]
		var lo := Vector3(1e9, 0, 1e9)
		var hi := Vector3(-1e9, 0, -1e9)
		for q in pts:
			lo = Vector3(minf(lo.x, q.x), 0, minf(lo.z, q.z))
			hi = Vector3(maxf(hi.x, q.x), 0, maxf(hi.z, q.z))
		var centre := (lo + hi) * 0.5 + Vector3(0, 4.0, 0)
		var ext := (hi - lo) * 0.5 + Vector3(3.0, 1.2, 3.0)
		var ps := GPUParticles3D.new()
		var proc := ParticleProcessMaterial.new()
		proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		proc.emission_box_extents = ext
		proc.direction = Vector3(0.3, -1.0, 0.1)
		proc.spread = 30.0
		proc.initial_velocity_min = 0.2
		proc.initial_velocity_max = 0.6
		proc.gravity = Vector3(0.25, -0.45, 0.1)
		proc.angular_velocity_min = -180.0
		proc.angular_velocity_max = 180.0
		proc.turbulence_enabled = true
		proc.turbulence_noise_strength = 0.6
		proc.turbulence_noise_scale = 3.0
		proc.particle_flag_rotate_y = true
		ps.process_material = proc
		ps.draw_pass_1 = pm
		ps.amount = clampi(pts.size() * 40, 40, 500) * [1, 1, 2, 2][quality] / 2
		ps.lifetime = 9.0
		ps.preprocess = 9.0
		ps.visibility_aabb = AABB(-ext - Vector3(4, 6, 4), ext * 2.0 + Vector3(8, 8, 8))
		ps.visibility_range_end = 130.0
		ps.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(ps)
		ps.global_position = centre
	_stats["petal_systems"] = groups.size()

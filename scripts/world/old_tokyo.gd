extends Node3D
## Old Tokyo: the uploaded Tokyo Midnight Circuit district (assets/world_upload/Tokyo_Midnight_Circuit,
## textures in assets/maps/old_tokyo) built around our street circuit. A grid of dense blocks
## (brick, concrete and metal shells with lit ribbon windows, shop canopies, neon signs, rooftop plant),
## the streets between them, a ground-level expressway, three car-meet parking lots, the pits and a
## grandstand – and the Japanese multi-storey car park (assets/props/parking_garage), driveable down to
## its second basement. Every box goes into one mesh per material (tens of thousands of parts would
## be as many draw calls); buildings, barriers, pits and the car park are solid. The barriers of the
## circuit open where the streets cross it; the misty border of the district turns you round.

const MeshKit = preload("res://scripts/util/mesh_kit.gd")
const MeshMerge = preload("res://scripts/util/mesh_merge.gd")
const Props = preload("res://scripts/world/prop_meshes.gd")
const Colliders = preload("res://scripts/util/colliders.gd")
const CityLights = preload("res://scripts/world/city/city_lights.gd")
const CityFog = preload("res://scripts/world/city/city_fog.gd")

const HALF := 322.0
const STEP := 50.0
const TEX := "res://assets/maps/old_tokyo/textures/"
const GARAGE := "res://assets/props/parking_garage/parking_garage.glb"
const GARAGE_AT := Vector3(200, 0, 196)
const GARAGE_RECT := Rect2(156, 170, 88, 52)     # x, z: the car park's ground plate (no streets there)
## [texture set, triplanar scale]
const TEXTURE_SETS := {
	"asphalt": ["asphalt", 0.85], "road_dark": ["road_dark", 0.5],
	"concrete": ["concrete", 0.5], "concrete_dark": ["concrete", 0.5],
	"brick": ["brick", 0.3], "metal": ["metal", 0.45],
	"sidewalk": ["sidewalk", 0.2], "roof": ["roof", 0.28], "glass": ["glass", 0.24],
}
const PALETTE := {
	"asphalt": Color("20242b"), "road_dark": Color("151a21"), "concrete": Color("676e74"),
	"concrete_dark": Color("424950"), "sidewalk": Color("81878a"), "line": Color("e9e5d9"),
	"yellow": Color("f1bd45"), "glass": Color("172634"), "window": Color("ffd996"),
	"window_cool": Color("86c9ed"), "brick": Color("625454"), "roof": Color("303740"),
	"metal": Color("515d68"), "black": Color("0d1117"), "red": Color("df342e"),
	"blue": Color("198ce0"), "cyan": Color("35e7f2"), "pink": Color("ff4ebd"),
	"green": Color("4cdb8b"), "orange": Color("f78c35"), "white": Color("e6e5df"),
}
const GLOWING := ["window", "window_cool", "cyan", "pink", "green", "orange", "red", "blue"]

var track
var terrain
var scenery
var world
var fog
var lights_node
var stats := {}
var rng := RandomNumberGenerator.new()
var _mats := {}
var _st := {}                  # material key -> SurfaceTool
var _glow: Array = []          # [material, day energy, night energy]
var _body: StaticBody3D
var _outline: PackedVector2Array
var _emitters: Array = []
var _labels: Array = []


func build(p_track, p_terrain, p_scenery, quality: int) -> void:
	track = p_track
	terrain = p_terrain
	scenery = p_scenery
	world = scenery.get_parent()
	rng.seed = 410031
	_outline = PackedVector2Array()
	for i in range(0, track.sample_count(), 2):
		var s: Vector3 = track.samples[i]
		_outline.append(Vector2(s.x, s.z))
	_make_materials()
	_body = StaticBody3D.new()
	_body.name = "OldTokyoColliders"
	_body.collision_layer = Colliders.LAYER_WORLD
	_body.collision_mask = 0
	add_child(_body)
	_dig_garage_pit()
	_box("road_dark", Vector3(0, -0.5 + 0.012, 0), Vector3(HALF * 2.4, 1.0, HALF * 2.4))
	await Game.load_tick()
	_make_blocks()
	await Game.load_tick()
	_make_streets()
	_make_expressway()
	_make_pits_and_stand()
	_make_lots()
	await Game.load_tick()
	_make_street_furniture()
	_commit()
	await Game.load_tick()
	_place_garage()
	_open_crossings()
	lights_node = CityLights.new()
	lights_node.name = "OldTokyoLights"
	add_child(lights_node)
	lights_node.setup(_emitters, quality)
	fog = CityFog.new()
	fog.name = "BorderFog"
	add_child(fog)
	fog.setup(world, Rect2(-HALF - 8.0, -HALF - 8.0, HALF * 2.0 + 16.0, HALF * 2.0 + 16.0))
	stats["lights"] = _emitters.size()


func set_night(n: float) -> void:
	for g in _glow:
		(g[0] as StandardMaterial3D).emission_energy_multiplier = lerpf(float(g[1]), float(g[2]), n)
	if lights_node:
		lights_node.set_night(n)
	if fog:
		fog.set_night(n)


# ---------------------------------------------------------------------------
# Materials and geometry batches
# ---------------------------------------------------------------------------
func _make_materials() -> void:
	for key in PALETTE:
		var m := StandardMaterial3D.new()
		m.albedo_color = PALETTE[key]
		if key in ["concrete", "concrete_dark", "brick", "metal", "roof", "sidewalk"]:
			# the textures are dark already: the shells read as black blocks otherwise
			m.albedo_color = (PALETTE[key] as Color).lightened(0.35)
		m.roughness = 0.78 if key not in ["glass", "metal"] else 0.34
		if key.begins_with("window") or key == "glass":
			m.metallic = 0.38
		if GLOWING.has(key):
			m.emission_enabled = true
			m.emission = PALETTE[key]
			var night_e := 0.75 if key.begins_with("window") else 1.8
			m.emission_energy_multiplier = night_e
			_glow.append([m, night_e * 0.12, night_e])
		if TEXTURE_SETS.has(key):
			var set: Array = TEXTURE_SETS[key]
			var tex: String = set[0]
			m.albedo_texture = _tex(tex + "_albedo.png")
			var nrm := _tex(tex + "_normal.png")
			if nrm:
				m.normal_enabled = true
				m.normal_texture = nrm
				m.normal_scale = 0.45
			var rough := _tex(tex + "_roughness.png")
			if rough:
				m.roughness_texture = rough
			m.uv1_triplanar = true
			m.uv1_world_triplanar = true
			m.uv1_scale = Vector3.ONE * float(set[1])
			m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		_mats[key] = m


func _tex(file: String) -> Texture2D:
	return load(TEX + file) as Texture2D if ResourceLoader.exists(TEX + file) else null


func _box(key: String, pos: Vector3, size: Vector3, yaw := 0.0, solid := false) -> void:
	if not _st.has(key):
		_st[key] = MeshKit.new_st()
	var xf := Transform3D(Basis(Vector3.UP, yaw), pos)
	MeshKit.box(_st[key], xf, size)
	if solid:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		cs.shape = bs
		cs.transform = xf
		_body.add_child(cs)


func _cyl(key: String, pos: Vector3, r: float, h: float) -> void:
	if not _st.has(key):
		_st[key] = MeshKit.new_st()
	Props._cyl(_st[key], pos - Vector3(0, h * 0.5, 0), pos + Vector3(0, h * 0.5, 0), r, r, Color.WHITE, 10)


func _text(words: String, pos: Vector3, size: float, yaw := 0.0) -> void:
	var label := Label3D.new()
	label.text = words
	label.position = pos
	label.rotation.y = yaw
	label.font_size = int(size * 64)
	label.pixel_size = 0.006
	label.modulate = Color.WHITE
	label.outline_size = 6
	label.outline_modulate = Color("11141a")
	label.visibility_range_end = 220.0
	add_child(label)


func _commit() -> void:
	for key in _st:
		var mi := MeshInstance3D.new()
		mi.name = "OT_" + key
		mi.mesh = MeshKit.commit(_st[key], _mats[key])
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if key in ["line", "road_dark", "sidewalk"] or GLOWING.has(key) \
			else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(mi)
	_st.clear()


## Distance from p to the circuit's centre line.
func _to_circuit(p: Vector2) -> float:
	var best := 1e9
	for i in _outline.size():
		var a := _outline[i]
		var b := _outline[(i + 1) % _outline.size()]
		var ab := b - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
		best = minf(best, p.distance_to(a + ab * t))
	return best


# ---------------------------------------------------------------------------
# The district
# ---------------------------------------------------------------------------
func _make_blocks() -> void:
	var index := 0
	for ix in range(-6, 7):
		for iz in range(-6, 7):
			var cx := float(ix) * STEP
			var cz := float(iz) * STEP
			if absf(cx) > HALF - 24.0 or absf(cz) > HALF - 24.0:
				continue
			var meet := (absf(cx + 200.0) < 42.0 and absf(cz - 200.0) < 42.0) or (absf(cx - 200.0) < 42.0 and absf(cz + 200.0) < 42.0) \
				or (absf(cx - 200.0) < 42.0 and absf(cz - 200.0) < 42.0)
			# keep clear: the circuit, the expressway, the grandstand and pits
			if meet or _to_circuit(Vector2(cx, cz)) < 30.0 or absf(cz) < 22.0 or (absf(cx) < 50.0 and cz > -60.0 and cz < 60.0):
				continue
			_box("sidewalk", Vector3(cx, 0.07, cz), Vector3(37, 0.14, 37))
			_building(cx, cz, index)
			index += 1
	stats["blocks"] = index


func _building(cx: float, cz: float, index: int) -> void:
	var w := rng.randf_range(25.0, 34.0)
	var d := rng.randf_range(25.0, 34.0)
	var floors := rng.randi_range(3, 15)
	var fh := rng.randf_range(3.2, 3.8)
	var h := floors * fh
	var shell: String = ["brick", "concrete", "concrete_dark", "roof", "metal"][rng.randi_range(0, 4)]
	var o := Vector3(cx, 0.14, cz)
	_box(shell, o + Vector3(0, h * 0.5, 0), Vector3(w, h, d), 0.0, true)
	_box("roof", o + Vector3(0, h + 0.12, 0), Vector3(w + 0.6, 0.24, d + 0.6))
	var columns := int(w / 4.1)
	var cool := index % 3 == 0
	for fl in range(1, floors):
		var y := fl * fh
		_box("metal", o + Vector3(0, y, d * 0.5 + 0.08), Vector3(w, 0.18, 0.2))
		_box("metal", o + Vector3(0, y, -d * 0.5 - 0.08), Vector3(w, 0.18, 0.2))
		var lit := rng.randf() < 0.72
		var a := "window" if lit else "glass"
		var b := ("window_cool" if cool else "window") if lit else "glass"
		_box(a, o + Vector3(0, y + 1.45, d * 0.5 + 0.12), Vector3(w * 0.88, 1.55, 0.09))
		_box(b, o + Vector3(0, y + 1.45, -d * 0.5 - 0.12), Vector3(w * 0.88, 1.55, 0.09))
		_box(a, o + Vector3(w * 0.5 + 0.12, y + 1.45, 0), Vector3(0.09, 1.55, d * 0.84))
		_box(b, o + Vector3(-w * 0.5 - 0.12, y + 1.45, 0), Vector3(0.09, 1.55, d * 0.84))
		for col in columns:
			var x := -w * 0.5 + 2.1 + col * 4.1
			var on := rng.randf() < 0.57
			_box("window" if on else "glass", o + Vector3(x, y + 1.45, d * 0.5 + 0.16), Vector3(2.25, 1.55, 0.09))
			_box((("window_cool" if cool else "window") if on else "glass"), o + Vector3(x, y + 1.45, -d * 0.5 - 0.16), Vector3(2.25, 1.55, 0.09))
	# shop front, canopy and lit name panel towards the street (+z)
	_box("glass", o + Vector3(0, 1.65, d * 0.5 + 0.24), Vector3(w * 0.78, 2.5, 0.12))
	var sign: String = ["pink", "cyan", "orange", "green", "red"][index % 5]
	_box(sign, o + Vector3(0, 3.05, d * 0.5 + 0.8), Vector3(w * 0.94, 0.48, 1.5))
	_box(sign, o + Vector3(0, 4.05, d * 0.5 + 0.31), Vector3(w * 0.72, 0.9, 0.16))
	_emitters.append([o + Vector3(0, 3.0, d * 0.5 + 2.0), (PALETTE[sign] as Color).lerp(Color.WHITE, 0.3), 12.0, 1.4, 0])
	if index % 4 == 0:
		_text(["KONBINI", "TOKYO RAMEN", "NIGHT GARAGE", "SUSHI • BAR"][(index / 4) % 4], o + Vector3(0, 3.75, d * 0.5 + 0.43), 0.43)
	# rooftop plant room, water tank, antenna
	_box("concrete_dark", o + Vector3(rng.randf_range(-4, 4), h + 1.5, rng.randf_range(-3, 3)), Vector3(5.5, 2.7, 5.0))
	_cyl("metal", o + Vector3(w * 0.26, h + 1.1, -d * 0.2), 1.05, 2.2)
	_cyl("metal", o + Vector3(-w * 0.27, h + 3.7, d * 0.24), 0.09, 5.5)
	if floors > 7 and index % 3 == 0:
		for level in range(1, floors, 2):
			_box("metal", o + Vector3(w * 0.5 + 0.6, level * fh, 0), Vector3(1.8, 0.16, 6.2))
			_box("metal", o + Vector3(w * 0.5 + 0.6, level * fh + 1.7, 0), Vector3(1.2, 3.4, 0.22), 0.3)
	if index % 9 == 0:
		_box(sign, o + Vector3(0, h + 4.5, d * 0.5), Vector3(12, 3.2, 0.3))
		_text("TOKYO", o + Vector3(0, h + 4.05, d * 0.5 + 0.2), 0.8)


## Lane markings down the streets between the blocks (the dark ground is the road), crossings at the
## junctions – none on the circuit or in the car park.
func _make_streets() -> void:
	for k in range(-7, 7):
		var c := float(k) * STEP + STEP * 0.5
		for m in range(-6, 7):
			var along := float(m) * STEP
			for lane: float in [-2.0, 2.0]:
				for p in [Vector2(c + lane, along), Vector2(along, c + lane)]:
					var pv: Vector2 = p
					if absf(pv.x) > HALF or absf(pv.y) > HALF or _to_circuit(pv) < 14.0 or GARAGE_RECT.has_point(pv) or absf(pv.y) < 17.0:
						continue
					var vertical: bool = pv.x == c + lane
					_box("line", Vector3(pv.x, 0.02, pv.y), Vector3(0.13, 0.02, 4.6) if vertical else Vector3(4.6, 0.02, 0.13))
	# zebra crossings and signal masts at the junctions
	for i in range(-6, 6):
		for j in range(-6, 6):
			var x := float(i) * STEP + STEP * 0.5
			var z := float(j) * STEP + STEP * 0.5
			if (i + j) % 2 != 0 or _to_circuit(Vector2(x, z)) < 18.0 or GARAGE_RECT.has_point(Vector2(x, z)) or absf(z) < 20.0:
				continue
			for k in 5:
				_box("line", Vector3(x - 5.0 + k * 2.3, 0.02, z + 8.0), Vector3(1.2, 0.02, 4.8))
			_cyl("metal", Vector3(x + 7.0, 3.2, z + 7.0), 0.12, 6.4)
			_box("black", Vector3(x + 7.0, 6.15, z + 7.0), Vector3(0.48, 1.5, 0.45))
			_box("red", Vector3(x + 7.0, 6.55, z + 7.25), Vector3(0.22, 0.22, 0.08))
			_box("green", Vector3(x + 7.0, 5.86, z + 7.25), Vector3(0.22, 0.22, 0.08))


## The multilane expressway along z = 0 (at street level: the circuit crosses it).
func _make_expressway() -> void:
	_box("road_dark", Vector3(0, 0.016, 0), Vector3(HALF * 2.1, 0.01, 29))
	for lane: float in [-9.0, -3.0, 3.0, 9.0]:
		for seg in range(-10, 11):
			var x := seg * 31.0
			if _to_circuit(Vector2(x, lane)) > 14.0:
				_box("line", Vector3(x, 0.024, lane), Vector3(18, 0.012, 0.18))
	for side: float in [-1.0, 1.0]:
		# crash barriers, opened where the circuit and the streets cross
		var x := -HALF * 1.05
		while x < HALF * 1.05:
			var nx := minf(x + 10.0, HALF * 1.05)
			var mid := (x + nx) * 0.5
			var street := absf(fposmod(mid, STEP) - STEP * 0.5) < 8.0
			if _to_circuit(Vector2(mid, side * 14.5)) > 16.0 and not street:
				_box("metal", Vector3(mid, 0.75, side * 14.5), Vector3(nx - x, 1.5, 0.6), 0.0, true)
			x = nx
		for k in range(-9, 10):
			var px := k * 34.0
			if _to_circuit(Vector2(px, side * 16.0)) < 16.0 or absf(fposmod(px, STEP) - STEP * 0.5) < 8.0:
				continue
			_box("metal", Vector3(px, 5.7, side * 16.0), Vector3(0.34, 11.0, 0.34), 0.0, true)
			_box("metal", Vector3(px - side * 2.0, 11.1, side * 15.6), Vector3(4.2, 0.22, 0.24))
			_box("window", Vector3(px - side * 3.5, 10.95, side * 15.6), Vector3(1.5, 0.24, 0.7))
			_emitters.append([Vector3(px - side * 3.5, 10.7, side * 15.6), Color(1.0, 0.9, 0.72), 26.0, 4.0, 1])
	for k in range(-9, 10, 2):
		var gx := k * 34.0
		if _to_circuit(Vector2(gx, 0)) < 18.0:
			continue
		_box("metal", Vector3(gx, 11.6, 0), Vector3(0.42, 0.6, 31))
		_box("green", Vector3(gx, 12.3, 0), Vector3(8, 2.5, 0.3))
		_text("SHIBUYA  •  SHINJUKU", Vector3(gx, 12.0, 0.22), 0.3)


## Pit garages behind the south straight, the grandstand inside the loop, flags and lanterns.
func _make_pits_and_stand() -> void:
	for i in 10:
		var x := -37.0 + i * 8.2
		_box("concrete_dark", Vector3(x, 3.5, 124), Vector3(7.4, 7, 13), 0.0, true)
		_box("metal", Vector3(x, 2.5, 117.35), Vector3(5.5, 4.5, 0.16))
		_box(["red", "blue", "green", "orange"][i % 4], Vector3(x, 6.8, 117.4), Vector3(6, 0.8, 0.2))
		_text("PIT %02d" % (i + 1), Vector3(x, 6.55, 117.55), 0.3)
		_emitters.append([Vector3(x, 5.0, 116.0), Color(1.0, 0.95, 0.85), 10.0, 1.2, 0])
	for row in 9:
		_box("red" if row % 2 == 0 else "metal", Vector3(0, 1.0 + row * 0.72, -25.0 - row * 2.0), Vector3(76, 0.55, 2.2), 0.0, true)
	_box("concrete_dark", Vector3(0, 3.0, -34.0), Vector3(76, 6.0, 14.0), 0.0, true)
	_box("roof", Vector3(0, 9.0, -35), Vector3(82, 0.65, 5.0))
	for x: float in [-35.0, -20.0, 20.0, 35.0]:
		_box("metal", Vector3(x, 4.2, -35), Vector3(0.7, 8.4, 0.7))
	for i in 18:
		var x := -42.0 + i * 4.8
		_box("red", Vector3(x, 5.0, -152), Vector3(1.15, 1.6, 1.0))
		_box("window", Vector3(x, 5.0, -152.55), Vector3(0.64, 0.88, 0.08))
	for i in 16:
		var x := -135.0 + i * 18.0
		if _to_circuit(Vector2(x, 128)) < 12.0:
			continue
		_cyl("metal", Vector3(x, 4.0, 131), 0.11, 8.0)
		_box("red" if i % 2 == 0 else "white", Vector3(x + 1.1, 6.4, 131), Vector3(2.1, 1.1, 0.12))
	_box("pink", Vector3(-98, 9.0, -60), Vector3(8.5, 1.0, 30))


## Two car-meet lots with real parked cars (the third meet spot holds the multi-storey car park).
func _make_lots() -> void:
	_lot(Vector3(-198, 0, 190), 12, 8, "SHIBUYA CAR MEET")
	_lot(Vector3(190, 0, -190), 10, 7, "MIDNIGHT MEET")
	_box("pink", Vector3(-198, 5.8, 164), Vector3(29, 0.9, 0.9))
	_box("cyan", Vector3(-211.5, 3.0, 164), Vector3(0.9, 5.5, 0.9), 0.0, true)
	_box("cyan", Vector3(-184.5, 3.0, 164), Vector3(0.9, 5.5, 0.9), 0.0, true)
	_text("TOKYO CAR MEET • OPEN ALL NIGHT", Vector3(-198, 5.5, 164.5), 0.36)


func _lot(c: Vector3, columns: int, rows: int, title: String) -> void:
	var w := float(columns) * 5.4 + 8.0
	var d := float(rows) * 5.4 + 8.0
	_box("asphalt", c + Vector3(0, 0.02, 0), Vector3(w, 0.02, d))
	for row in rows:
		for col in columns:
			var x := c.x - (columns - 1) * 2.7 + col * 5.4
			var z := c.z - (rows - 1) * 2.7 + row * 5.4
			_box("line", Vector3(x - 2.55, 0.034, z), Vector3(0.14, 0.01, 5.0))
			_box("line", Vector3(x + 2.55, 0.034, z), Vector3(0.12, 0.01, 5.0))
			if rng.randf() < 0.61 and scenery.details:
				scenery.details.add_parked_car(Transform3D(Basis(Vector3.UP, PI if row % 2 == 0 else 0.0), Vector3(x, 0, z - 0.1)))
	_box("blue", Vector3(c.x, 5.2, c.z - d * 0.5 - 1.3), Vector3(minf(w * 0.75, 30.0), 2.0, 0.4))
	_text(title, Vector3(c.x, 4.8, c.z - d * 0.5 - 1.0), 0.38)
	for k in 4:
		var lp := c + Vector3((k - 1.5) * w * 0.28, 0, -d * 0.5 + 1.0)
		_cyl("metal", lp + Vector3(0, 4.5, 0), 0.14, 9.0)
		_emitters.append([lp + Vector3(0, 8.8, 0), Color(1.0, 0.92, 0.8), 24.0, 4.0, 1])


func _make_street_furniture() -> void:
	# lamps on the block corners, planters with trees
	for i in range(-6, 7):
		for j in range(-6, 7):
			var x := float(i) * STEP + 17.0
			var z := float(j) * STEP + 17.0
			if absf(x) > HALF - 10.0 or absf(z) > HALF - 10.0 or _to_circuit(Vector2(x, z)) < 12.0 or GARAGE_RECT.has_point(Vector2(x, z)) or absf(z) < 18.0:
				continue
			_cyl("metal", Vector3(x, 4.2, z), 0.12, 8.4)
			_box("metal", Vector3(x + 0.8, 8.2, z), Vector3(1.8, 0.18, 0.18))
			_box("window", Vector3(x + 1.5, 8.05, z), Vector3(0.8, 0.22, 0.4))
			_emitters.append([Vector3(x + 1.5, 7.8, z), Color(1.0, 0.86, 0.62), 20.0, 3.0, 1])
			if (i + j) % 4 == 0:
				_cyl("concrete_dark", Vector3(x - 1.8, 0.58, z + 1.5), 0.85, 1.15)
				_cyl("brick", Vector3(x - 1.8, 2.2, z + 1.5), 0.16, 2.4)
				var tree := MeshInstance3D.new()
				var foliage := SphereMesh.new()
				foliage.radius = 1.45
				foliage.height = 2.8
				tree.mesh = foliage
				tree.material_override = _mats["green"]
				tree.position = Vector3(x - 1.8, 3.6, z + 1.5)
				add_child(tree)
	# vending machines and bollards in the street gaps
	for i in 52:
		var p := Vector2(rng.randf_range(-HALF + 20, HALF - 20), rng.randf_range(-HALF + 20, HALF - 20))
		if _to_circuit(p) < 14.0 or absf(p.y) < 18.0 or GARAGE_RECT.has_point(p):
			continue
		if rng.randf() < 0.54:
			_box("blue", Vector3(p.x, 1.0, p.y), Vector3(0.82, 2.0, 0.72), 0.0, true)
			_box("window", Vector3(p.x, 1.1, p.y - 0.37), Vector3(0.58, 0.8, 0.025))
		else:
			_cyl("yellow", Vector3(p.x, 0.65, p.y), 0.16, 1.3)
	# floodlights along the circuit
	for i in range(0, _outline.size(), 14):
		var a := _outline[i]
		var b := _outline[(i + 1) % _outline.size()]
		var n := Vector2(-(b - a).normalized().y, (b - a).normalized().x)
		for side: float in [-1.0, 1.0]:
			var p := a + n * side * 12.5
			if absf(p.y) < 18.0:
				continue
			_cyl("metal", Vector3(p.x, 6.0, p.y), 0.16, 12.0)
			_box("window", Vector3(p.x, 12.2, p.y), Vector3(2.2, 0.45, 0.5))
			_emitters.append([Vector3(p.x, 12.0, p.y), Color(0.95, 0.97, 1.0), 30.0, 5.0, 1])


# ---------------------------------------------------------------------------
# The multi-storey car park
# ---------------------------------------------------------------------------
## Its two basements go 7 m down: the ground under its plate is lowered (the plate covers it).
func _dig_garage_pit() -> void:
	if not ResourceLoader.exists(GARAGE):
		return
	for dx in range(-24, 25, 8):
		terrain.level_to(GARAGE_AT + Vector3(dx, 0, 0), 12.0, 6.0, -8.0)


func _place_garage() -> void:
	if not ResourceLoader.exists(GARAGE):
		return
	var scene := load(GARAGE) as PackedScene
	if scene == null:
		return
	var g := scene.instantiate() as Node3D
	g.name = "ParkingGarage"
	add_child(g)
	g.position = GARAGE_AT
	var t0 := Time.get_ticks_msec()
	var n := MeshMerge.merge(g, func(_mi: MeshInstance3D) -> bool: return false)
	var shapes := 0
	for c in g.get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).mesh != null and str(c.name).begins_with("Merged"):
			var shape := ((c as MeshInstance3D).mesh as ArrayMesh).create_trimesh_shape()
			if shape:
				var cs := CollisionShape3D.new()
				cs.shape = shape
				cs.transform = (c as Node3D).transform
				var body := StaticBody3D.new()
				body.collision_layer = Colliders.LAYER_WORLD
				body.collision_mask = 0
				body.add_child(cs)
				g.add_child(body)
				shapes += 1
	stats["garage_parts"] = n
	stats["garage_shapes"] = shapes
	print("OLD TOKYO: car park %d parts merged, %d shapes in %d ms" % [n, shapes, Time.get_ticks_msec() - t0])


# ---------------------------------------------------------------------------
# Openings in the circuit's barriers
# ---------------------------------------------------------------------------
## Wherever a street or the expressway crosses the circuit, both barriers open.
func _open_crossings() -> void:
	var lines: Array = []          # [point on the line, direction, half width]
	for k in range(-7, 7):
		var c := float(k) * STEP + STEP * 0.5
		lines.append([Vector2(c, 0), Vector2(0, 1), 8.0])
		if absf(c) > 20.0:
			lines.append([Vector2(0, c), Vector2(1, 0), 8.0])
	lines.append([Vector2(0, 0), Vector2(1, 0), 16.5])
	var n: int = _outline.size()
	var gaps := 0
	for ln in lines:
		var p0: Vector2 = ln[0]
		var dir: Vector2 = ln[1]
		var nrm := Vector2(-dir.y, dir.x)
		for i in n:
			var a := _outline[i]
			var b := _outline[(i + 1) % n]
			var da := (a - p0).dot(nrm)
			var db := (b - p0).dot(nrm)
			if da * db > 0.0 or absf(da - db) < 1e-6:
				continue
			var hit := a.lerp(b, da / (da - db))
			# only where the line actually crosses (not where a street runs along the circuit)
			var seg_dir := (b - a).normalized()
			if absf(seg_dir.dot(dir)) > 0.6:
				continue
			var pr: Array = track.project(Vector3(hit.x, 0, hit.y), -1)
			var prog: float = pr[1]
			var half: float = float(ln[2]) / maxf(absf(seg_dir.dot(nrm)), 0.5) + 1.0
			for side: float in [-1.0, 1.0]:
				track.wall_gaps.append([fposmod(prog - half, track.length), fposmod(prog + half, track.length), side])
			gaps += 1
	if gaps > 0:
		track.rebuild_walls()
	stats["crossings"] = gaps

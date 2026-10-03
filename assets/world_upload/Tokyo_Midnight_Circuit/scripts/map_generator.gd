extends Node3D
## Procedural, self-contained Tokyo-inspired driving district. 1 unit = 1 metre.

const HALF := 322.0
const BLOCK_STEP := 50.0
const TRACK_Y := 20.0
const TEXTURE_SETS := {
	"asphalt": ["asphalt", 0.85], "road_dark": ["road_dark", 0.85],
	"concrete": ["concrete", 0.5], "concrete_dark": ["concrete", 0.5],
	"brick": ["brick", 0.3], "metal": ["metal", 0.45],
	"sidewalk": ["sidewalk", 0.2], "roof": ["roof", 0.28], "glass": ["glass", 0.24],
	"car_red": ["paint", 0.8], "car_blue": ["paint", 0.8], "car_silver": ["paint", 0.8],
	"car_yellow": ["paint", 0.8], "car_black": ["paint", 0.8], "car_green": ["paint", 0.8]
}
var rng := RandomNumberGenerator.new()
var mats: Dictionary = {}
var camera: Camera3D
var look_yaw := 0.0
var look_pitch := -0.35
var mouse_look := false
var fly_speed := 42.0

func _ready() -> void:
	rng.seed = 410031
	_make_materials()
	_make_world()
	_make_city()
	_make_ground_highway()
	_make_raceway()
	_make_lots()
	_make_street_furniture()
	_make_scene_camera()

func _make_materials() -> void:
	var palette := {
		"asphalt": Color("20242b"), "road_dark": Color("151a21"), "concrete": Color("676e74"),
		"concrete_dark": Color("424950"), "sidewalk": Color("81878a"), "line": Color("e9e5d9"),
		"yellow": Color("f1bd45"), "glass": Color("172634"), "window": Color("ffd996"),
		"window_cool": Color("86c9ed"), "brick": Color("625454"), "roof": Color("303740"),
		"metal": Color("515d68"), "black": Color("0d1117"), "red": Color("df342e"),
		"blue": Color("198ce0"), "cyan": Color("35e7f2"), "pink": Color("ff4ebd"),
		"green": Color("4cdb8b"), "orange": Color("f78c35"), "white": Color("e6e5df"),
		"car_red": Color("a92232"), "car_blue": Color("256ca3"), "car_silver": Color("aeb8bd"),
		"car_yellow": Color("d9aa35"), "car_black": Color("20252d"), "car_green": Color("39775f")
	}
	for key in palette:
		var m := StandardMaterial3D.new()
		m.albedo_color = palette[key]
		m.roughness = 0.78 if key not in ["glass", "metal"] else 0.34
		if key.begins_with("window") or key == "glass":
			m.metallic = 0.38
		if key in ["window", "window_cool", "cyan", "pink", "green", "orange", "red", "blue"]:
			m.emission_enabled = true
			m.emission = palette[key]
			m.emission_energy_multiplier = 1.35 if key.begins_with("window") else 2.0
		if TEXTURE_SETS.has(key):
			var set: Array = TEXTURE_SETS[key]
			var texture_name: String = set[0]
			m.albedo_texture = load("res://textures/%s_albedo.png" % texture_name)
			m.normal_enabled = true
			m.normal_texture = load("res://textures/%s_normal.png" % texture_name)
			m.normal_scale = 0.45
			m.roughness_texture = load("res://textures/%s_roughness.png" % texture_name)
			m.uv1_triplanar = true
			m.uv1_world_triplanar = true
			m.uv1_scale = Vector3(float(set[1]), float(set[1]), float(set[1]))
			m.texture_repeat = true
		mats[key] = m

func _make_world() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("07101c")
	sky_mat.sky_horizon_color = Color("3a4057")
	sky_mat.ground_bottom_color = Color("090d14")
	sky_mat.ground_horizon_color = Color("222a37")
	sky.sky_material = sky_mat
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("53677f")
	e.ambient_light_energy = 0.38
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.glow_enabled = true
	e.glow_intensity = 0.7
	e.fog_enabled = true
	e.fog_light_color = Color("343c50")
	e.fog_density = 0.0015
	env.environment = e
	add_child(env)
	var moon := DirectionalLight3D.new()
	moon.rotation_degrees = Vector3(-48, -32, 0)
	moon.light_color = Color("9bb4df")
	moon.light_energy = 0.46
	moon.shadow_enabled = true
	add_child(moon)
	_box("City Ground", Vector3(0, -1.5, 0), Vector3(HALF * 2.4, 3, HALF * 2.4), "road_dark")

func _mat(key: String) -> Material:
	return mats[key]

func _box(label: String, pos: Vector3, size: Vector3, material_key: String, parent: Node3D = null, yaw: float = 0.0) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var inst := MeshInstance3D.new()
	inst.name = label
	inst.mesh = mesh
	inst.material_override = _mat(material_key)
	inst.position = pos
	inst.rotation.y = yaw
	if parent == null:
		add_child(inst)
	else:
		parent.add_child(inst)
	return inst

func _cylinder(label: String, pos: Vector3, radius: float, height: float, material_key: String, parent: Node3D = null) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 10
	var inst := MeshInstance3D.new()
	inst.name = label
	inst.mesh = mesh
	inst.material_override = _mat(material_key)
	inst.position = pos
	if parent == null:
		add_child(inst)
	else:
		parent.add_child(inst)
	return inst

func _make_city() -> void:
	# Broad sidewalks and a dense, varied street-wall for every block.
	var block_index := 0
	var circuit_outline := _rounded_loop(270.0, 206.0, 45.0, 8)
	for ix in range(-6, 7):
		for iz in range(-6, 7):
			var cx := float(ix) * BLOCK_STEP
			var cz := float(iz) * BLOCK_STEP
			if abs(cx) > HALF - 24 or abs(cz) > HALF - 24:
				continue
			var reserved_for_meet := (abs(cx + 200) < 42 and abs(cz - 200) < 42) or (abs(cx - 200) < 42 and abs(cz + 200) < 42) or (abs(cx - 200) < 42 and abs(cz - 200) < 42)
			if reserved_for_meet or _distance_to_outline(Vector2(cx, cz), circuit_outline) < 27.0:
				continue
			_box("Block sidewalk", Vector3(cx, 0.12, cz), Vector3(37, 0.24, 37), "sidewalk")
			_make_building(cx, cz, block_index)
			block_index += 1
	# Four arterial streets through the grid, lane separators and crosswalks.
	for axis in [0, 1]:
		for road in range(-6, 7):
			var coord := float(road) * BLOCK_STEP
			if axis == 0:
				_box("North south street", Vector3(coord, 0.04, 0), Vector3(12, 0.08, HALF * 2), "asphalt")
				for lane in [-2.0, 2.0]:
					for mark in range(-6, 7):
						_box("Dashed lane marking", Vector3(coord + lane, 0.095, mark * 50.0), Vector3(0.13, 0.025, 4.6), "line")
			else:
				_box("East west street", Vector3(0, 0.04, coord), Vector3(HALF * 2, 0.08, 12), "asphalt")
				for lane in [-2.0, 2.0]:
					for mark in range(-6, 7):
						_box("Dashed lane marking", Vector3(mark * 50.0, 0.095, coord + lane), Vector3(4.6, 0.025, 0.13), "line")
	# Corner paint, narrow alleys, bollards and vending machines fill street gaps.
	for i in range(52):
		var x := rng.randf_range(-HALF + 20, HALF - 20)
		var z := rng.randf_range(-HALF + 20, HALF - 20)
		if rng.randf() < 0.54:
			_box("Japanese vending machine", Vector3(x, 1.0, z), Vector3(0.82, 2.0, 0.72), "blue")
			_box("Vending machine display", Vector3(x, 1.1, z - 0.37), Vector3(0.58, 0.8, 0.025), "window")
		else:
			_cylinder("Street bollard", Vector3(x, 0.65, z), 0.16, 1.3, "yellow")

func _make_building(cx: float, cz: float, index: int) -> void:
	var w := rng.randf_range(25.0, 34.0)
	var d := rng.randf_range(25.0, 34.0)
	var floors := rng.randi_range(3, 15)
	var floor_h := rng.randf_range(3.2, 3.8)
	var h := floors * floor_h
	var shell := ["brick", "concrete", "concrete_dark", "roof", "metal"][rng.randi_range(0, 4)]
	var b := Node3D.new()
	b.name = "Block %03d" % index
	b.position = Vector3(cx, 0.24, cz)
	add_child(b)
	_box("Building shell", Vector3(0, h * 0.5, 0), Vector3(w, h, d), shell, b)
	_box("Flat rooftop", Vector3(0, h + 0.12, 0), Vector3(w + 0.6, 0.24, d + 0.6), "roof", b)
	# Repeating lit window bands across each facade.
	var columns := int(w / 4.1)
	for floor in range(1, floors):
		var y := floor * floor_h
		_box("Floor ledge", Vector3(0, y, d * 0.5 + 0.08), Vector3(w, 0.18, 0.2), "metal", b)
		_box("Floor ledge", Vector3(0, y, -d * 0.5 - 0.08), Vector3(w, 0.18, 0.2), "metal", b)
		var lit := rng.randf() < 0.72
		_box("Continuous ribbon window", Vector3(0, y + 1.45, d * 0.5 + 0.12), Vector3(w * 0.88, 1.55, 0.09), "window" if lit else "glass", b)
		_box("Continuous ribbon window", Vector3(0, y + 1.45, -d * 0.5 - 0.12), Vector3(w * 0.88, 1.55, 0.09), "window_cool" if lit and index % 3 == 0 else ("window" if lit else "glass"), b)
		_box("Side ribbon window", Vector3(w * 0.5 + 0.12, y + 1.45, 0), Vector3(0.09, 1.55, d * 0.84), "window" if lit else "glass", b)
		_box("Side ribbon window", Vector3(-w * 0.5 - 0.12, y + 1.45, 0), Vector3(0.09, 1.55, d * 0.84), "window_cool" if lit and index % 3 == 0 else ("window" if lit else "glass"), b)
		for col in range(columns):
			var x := -w * 0.5 + 2.1 + col * 4.1
			var lit := rng.randf() < 0.57
			_box("Window", Vector3(x, y + 1.45, d * 0.5 + 0.12), Vector3(2.25, 1.55, 0.09), "window" if lit else "glass", b)
			_box("Window", Vector3(x, y + 1.45, -d * 0.5 - 0.12), Vector3(2.25, 1.55, 0.09), "window_cool" if lit and index % 3 == 0 else ("window" if lit else "glass"), b)
	# Shopfront glazing, colored canopy and luminous name panel facing the main road.
	_box("Shopfront glazing", Vector3(0, 1.65, d * 0.5 + 0.24), Vector3(w * 0.78, 2.5, 0.12), "glass", b)
	var sign_color := ["pink", "cyan", "orange", "green", "red"][index % 5]
	_box("Shop canopy", Vector3(0, 3.05, d * 0.5 + 0.8), Vector3(w * 0.94, 0.48, 1.5), sign_color, b)
	var sign := _box("Illuminated shop sign", Vector3(0, 4.05, d * 0.5 + 0.31), Vector3(w * 0.72, 0.9, 0.16), sign_color, b)
	if index % 4 == 0:
		_add_text(b, ["KONBINI", "TOKYO RAMEN", "NIGHT GARAGE", "SUSHI • BAR"][index % 4], Vector3(0, 3.75, d * 0.5 + 0.43), 0.43, Color.WHITE)
	# Rooftop plant room, water tank and antenna make the skyline less uniform.
	_box("Rooftop utility room", Vector3(rng.randf_range(-4, 4), h + 1.5, rng.randf_range(-3, 3)), Vector3(5.5, 2.7, 5.0), "concrete_dark", b)
	_cylinder("Rooftop water tank", Vector3(w * 0.26, h + 1.1, -d * 0.2), 1.05, 2.2, "metal", b)
	_cylinder("Antenna mast", Vector3(-w * 0.27, h + 3.7, d * 0.24), 0.09, 5.5, "metal", b)
	# Side fire stairs on a subset of taller blocks.
	if floors > 7 and index % 3 == 0:
		for level in range(1, floors, 2):
			_box("Fire escape landing", Vector3(w * 0.5 + 0.6, level * floor_h, 0), Vector3(1.8, 0.16, 6.2), "metal", b)
			_box("Fire escape stair", Vector3(w * 0.5 + 0.6, level * floor_h + 1.7, 0), Vector3(1.2, 3.4, 0.22), "metal", b, 0.3)
	if index % 9 == 0:
		var roof_sign := _box("Rooftop neon panel", Vector3(0, h + 4.5, d * 0.5), Vector3(12, 3.2, 0.3), sign_color, b)
		_add_text(b, "TOKYO", Vector3(0, h + 4.05, d * 0.5 + 0.2), 0.8, Color.WHITE)

func _add_text(parent: Node3D, words: String, pos: Vector3, size: float, color: Color) -> void:
	var label := Label3D.new()
	label.text = words
	label.position = pos
	label.font_size = int(size * 64)
	label.pixel_size = 0.006
	label.modulate = color
	label.outline_size = 6
	label.outline_modulate = Color("11141a")
	label.no_depth_test = false
	parent.add_child(label)

func _make_ground_highway() -> void:
	# Multilane city expressway cutting directly under the elevated circuit.
	_box("Ground-level expressway", Vector3(0, 0.03, 0), Vector3(HALF * 2.1, 0.12, 29), "road_dark")
	for lane in [-9.0, -3.0, 3.0, 9.0]:
		for seg in range(-10, 11):
			_box("Highway lane dash", Vector3(seg * 31.0, 0.11, lane), Vector3(18, 0.03, 0.18), "line")
	for side in [-1.0, 1.0]:
		_box("Highway crash barrier", Vector3(0, 0.8, side * 14.5), Vector3(HALF * 2.1, 1.5, 0.6), "metal")
		for x in range(-9, 10):
			_box("Expressway light pylon", Vector3(x * 34.0, 5.7, side * 16.0), Vector3(0.34, 11.0, 0.34), "metal")
			_box("Expressway lamp arm", Vector3(x * 34.0 + side * -2, 11.1, side * 15.6), Vector3(4.2, 0.22, 0.24), "metal")
			_box("Expressway lamp", Vector3(x * 34.0 + side * -3.5, 10.95, side * 15.6), Vector3(1.5, 0.24, 0.7), "window")
	# Flyover piers and overhead directional signs.
	for x in range(-9, 10, 2):
		_box("Highway gantry", Vector3(x * 34.0, 8.3, 0), Vector3(0.42, 7, 31), "metal")
		_box("Expressway direction board", Vector3(x * 34.0, 12.3, 0), Vector3(8, 2.5, 0.3), "green")
		_add_text(self, "SHIBUYA  •  SHINJUKU", Vector3(x * 34.0, 12.0, 0.22), 0.3, Color.WHITE)

func _make_raceway() -> void:
	# Rounded rectangular loop sweeps above the highway and urban blocks.
	var points := _rounded_loop(270.0, 206.0, 45.0, 8)
	for i in range(points.size()):
		var a := points[i]
		var b := points[(i + 1) % points.size()]
		var delta := b - a
		var length := delta.length()
		var mid := (a + b) * 0.5
		var yaw := atan2(delta.x, delta.y)
		_box("Elevated race circuit", Vector3(mid.x, TRACK_Y, mid.y), Vector3(15.0, 0.62, length + 0.8), "asphalt", self, yaw)
		_box("Racing surface inner kerb", Vector3(mid.x, TRACK_Y + 0.34, mid.y), Vector3(1.4, 0.16, length), "red", self, yaw)
		_box("Racing surface outer kerb", Vector3(mid.x, TRACK_Y + 0.34, mid.y), Vector3(1.4, 0.16, length), "line", self, yaw)
		# Twin steel barriers plus luminous edge strips.
		for side in [-1.0, 1.0]:
			var offset := Vector3(cos(yaw), 0, -sin(yaw)) * side * 7.7
			_box("Raceway safety wall", Vector3(mid.x + offset.x, TRACK_Y + 1.0, mid.y + offset.z), Vector3(0.58, 1.8, length + 0.4), "concrete_dark", self, yaw)
			_box("LED track edge", Vector3(mid.x + offset.x * 0.88, TRACK_Y + 1.96, mid.y + offset.z * 0.88), Vector3(0.18, 0.12, length), "cyan", self, yaw)
		# Piers under each section; dramatic clearance over the ground highway.
		if i % 2 == 0:
			for side in [-1.0, 1.0]:
				var off := Vector3(cos(yaw), 0, -sin(yaw)) * side * 8.3
				_box("Circuit concrete support", Vector3(mid.x + off.x, TRACK_Y * 0.5, mid.y + off.z), Vector3(2.1, TRACK_Y, 2.2), "concrete")
		# Repeated track floodlights.
		if i % 2 == 0:
			for side in [-1.0, 1.0]:
				var off := Vector3(cos(yaw), 0, -sin(yaw)) * side * 10.0
				_cylinder("Circuit light mast", Vector3(mid.x + off.x, TRACK_Y + 5.0, mid.y + off.z), 0.16, 10.0, "metal")
				_box("Circuit floodlight", Vector3(mid.x + off.x, TRACK_Y + 10.2, mid.y + off.z), Vector3(2.2, 0.45, 0.5), "window")
	# Start finish straight gantry and pit boxes along the south side.
	_box("Start finish gantry", Vector3(0, TRACK_Y + 5.2, 103), Vector3(18, 0.6, 0.8), "red")
	_add_text(self, "TOKYO NIGHT GRAND PRIX", Vector3(0, TRACK_Y + 5.0, 103.55), 0.44, Color.WHITE)
	for i in range(10):
		var x := -37.0 + i * 8.2
		_box("Pit garage", Vector3(x, 3.5, 121), Vector3(7.4, 7, 13), "concrete_dark")
		_box("Pit door", Vector3(x, 2.5, 114.35), Vector3(5.5, 4.5, 0.16), "metal")
		_box("Pit team sign", Vector3(x, 6.8, 114.4), Vector3(6, 0.8, 0.2), ["red", "blue", "green", "orange"][i % 4])
		_add_text(self, "PIT %02d" % (i + 1), Vector3(x, 6.55, 114.55), 0.3, Color.WHITE)
	# Grandstand overlooks the circuit inside the loop.
	for row in range(9):
		_box("Grandstand seating tier", Vector3(0, 1.0 + row * 0.72, -25 - row * 2.0), Vector3(76, 0.55, 2.2), "red" if row % 2 == 0 else "metal")
	_box("Grandstand roof", Vector3(0, 9.0, -35), Vector3(82, 0.65, 5.0), "roof")
	for x in [-35.0, -20.0, 20.0, 35.0]:
		_box("Grandstand column", Vector3(x, 4.2, -35), Vector3(0.7, 8.4, 0.7), "metal")

func _rounded_loop(width: float, depth: float, radius: float, steps: int) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var centers := [Vector2(width * 0.5 - radius, -depth * 0.5 + radius), Vector2(width * 0.5 - radius, depth * 0.5 - radius), Vector2(-width * 0.5 + radius, depth * 0.5 - radius), Vector2(-width * 0.5 + radius, -depth * 0.5 + radius)]
	var starts := [-90.0, 0.0, 90.0, 180.0]
	for c in range(4):
		for s in range(steps + 1):
			var angle := deg_to_rad(starts[c] + 90.0 * float(s) / steps)
			out.append(centers[c] + Vector2(cos(angle), sin(angle)) * radius)
	return out

func _distance_to_outline(point: Vector2, points: Array[Vector2]) -> float:
	var nearest := INF
	for i in range(points.size()):
		var a := points[i]
		var segment := points[(i + 1) % points.size()] - a
		var t := clamp((point - a).dot(segment) / segment.length_squared(), 0.0, 1.0)
		nearest = min(nearest, point.distance_to(a + segment * t))
	return nearest

func _make_lots() -> void:
	_make_parking_lot(Vector3(-198, 0.16, 190), 12, 8, "SHIBUYA CAR MEET")
	_make_parking_lot(Vector3(190, 0.16, -190), 10, 7, "MIDNIGHT MEET")
	_make_parking_lot(Vector3(200, 0.16, 198), 8, 6, "RIVERFRONT PARK")
	# Cars are placed inside marked stalls by _make_parking_lot.
	# Arrival arch with banners and meet spotlights.
	_box("Car meet arch top", Vector3(-198, 5.8, 164), Vector3(29, 0.9, 0.9), "pink")
	_box("Car meet arch left", Vector3(-211.5, 3.0, 164), Vector3(0.9, 5.5, 0.9), "cyan")
	_box("Car meet arch right", Vector3(-184.5, 3.0, 164), Vector3(0.9, 5.5, 0.9), "cyan")
	_add_text(self, "TOKYO CAR MEET • OPEN ALL NIGHT", Vector3(-198, 5.5, 164.5), 0.36, Color.WHITE)

func _make_parking_lot(center: Vector3, columns: int, rows: int, title: String) -> void:
	var width := float(columns) * 5.4 + 8
	var depth := float(rows) * 5.4 + 8
	_box("Parking lot asphalt", center, Vector3(width, 0.12, depth), "asphalt")
	for row in range(rows):
		for col in range(columns):
			var x := center.x - (columns - 1) * 2.7 + col * 5.4
			var z := center.z - (rows - 1) * 2.7 + row * 5.4
			_box("Parking stall boundary", Vector3(x - 2.55, center.y + 0.12, z), Vector3(0.14, 0.035, 5.0), "line")
			_box("Parking stall boundary", Vector3(x + 2.55, center.y + 0.12, z), Vector3(0.12, 0.035, 5.0), "line")
			var number := Label3D.new()
			number.text = "%02d" % (row * columns + col + 1)
			number.font_size = 34
			number.pixel_size = 0.018
			number.position = Vector3(x, center.y + 0.18, z + 1.6)
			number.rotation.x = -PI * 0.5
			number.modulate = Color("d8d8d0")
			add_child(number)
			if rng.randf() < 0.61:
				var colors := ["car_red", "car_blue", "car_silver", "car_yellow", "car_black", "car_green"]
				_make_car(Vector3(x, center.y + 0.12, z - 0.1), colors[rng.randi_range(0, colors.size() - 1)], 0.0)
	_box("Parking lot title board", Vector3(center.x, 5.2, center.z - depth * 0.5 - 1.3), Vector3(min(width * 0.75, 30.0), 2.0, 0.4), "blue")
	_add_text(self, title, Vector3(center.x, 4.8, center.z - depth * 0.5 - 1.0), 0.38, Color.WHITE)

func _make_car(pos: Vector3, color_key: String, yaw: float) -> void:
	var car := Node3D.new()
	car.name = "Parked tuner car"
	car.position = pos
	car.rotation.y = yaw
	add_child(car)
	_box("Car body", Vector3(0, 0.75, 0), Vector3(2.15, 0.75, 4.5), color_key, car)
	_box("Cabin", Vector3(0, 1.35, -0.15), Vector3(1.7, 0.72, 2.15), "glass", car)
	_box("Front bumper", Vector3(0, 0.42, 2.27), Vector3(2.2, 0.24, 0.24), "metal", car)
	_box("Rear bumper", Vector3(0, 0.42, -2.27), Vector3(2.2, 0.24, 0.24), "metal", car)
	for side in [-1.0, 1.0]:
		for z in [-1.45, 1.45]:
			var wheel := _cylinder("Tire", Vector3(side * 1.08, 0.45, z), 0.48, 0.28, "black", car)
			wheel.rotation.z = PI * 0.5
			var hub := _cylinder("Alloy wheel", Vector3(side * 1.24, 0.45, z), 0.23, 0.06, "metal", car)
			hub.rotation.z = PI * 0.5
	for side in [-1.0, 1.0]:
		_box("Headlight", Vector3(side * 0.68, 0.78, 2.29), Vector3(0.48, 0.2, 0.08), "window", car)
		_box("Tail lamp", Vector3(side * 0.69, 0.8, -2.3), Vector3(0.42, 0.22, 0.08), "red", car)

func _make_street_furniture() -> void:
	# Lamps on the main grid, crosswalks, signal heads, planters and street banners.
	for i in range(-6, 7, 2):
		for j in range(-6, 7, 2):
			var x := float(i) * BLOCK_STEP + 8.0
			var z := float(j) * BLOCK_STEP + 8.0
			_cylinder("Streetlight pole", Vector3(x, 4.2, z), 0.12, 8.4, "metal")
			_box("Streetlight arm", Vector3(x + 0.8, 8.2, z), Vector3(1.8, 0.18, 0.18), "metal")
			_box("Warm streetlight", Vector3(x + 1.5, 8.05, z), Vector3(0.8, 0.22, 0.4), "window")
			if (i + j) % 4 == 0:
				_cylinder("Planter", Vector3(x - 1.8, 0.58, z + 1.5), 0.85, 1.15, "concrete_dark")
				_cylinder("Planter tree trunk", Vector3(x - 1.8, 2.2, z + 1.5), 0.16, 2.4, "brick")
				var foliage := SphereMesh.new()
				foliage.radius = 1.45
				foliage.height = 2.8
				var tree := MeshInstance3D.new()
				tree.mesh = foliage
				tree.position = Vector3(x - 1.8, 3.6, z + 1.5)
				tree.material_override = _mat("green")
				add_child(tree)
	# 4-way signal heads and broad zebra crossings at arterial intersections.
	for i in range(-5, 6, 2):
		for j in range(-5, 6, 2):
			var x := float(i) * BLOCK_STEP
			var z := float(j) * BLOCK_STEP
			for k in range(5):
				_box("Zebra crossing stripe", Vector3(x - 5 + k * 2.3, 0.12, z + 8), Vector3(1.2, 0.045, 4.8), "line")
			_cylinder("Traffic signal mast", Vector3(x + 7.0, 3.2, z + 7.0), 0.12, 6.4, "metal")
			_box("Traffic signal housing", Vector3(x + 7.0, 6.15, z + 7.0), Vector3(0.48, 1.5, 0.45), "black")
			_box("Traffic signal red", Vector3(x + 7.0, 6.55, z + 7.25), Vector3(0.22, 0.22, 0.08), "red")
			_box("Traffic signal green", Vector3(x + 7.0, 5.86, z + 7.25), Vector3(0.22, 0.22, 0.08), "green")
	# Urban overhead walkway and decorative lantern row.
	_box("Pedestrian skybridge", Vector3(-98, 9.0, 0), Vector3(8.5, 1.0, 30), "metal")
	for k in range(5):
		_box("Skybridge window", Vector3(-98, 9.7, -11 + k * 5.5), Vector3(7.9, 0.28, 0.12), "cyan")
	for i in range(18):
		var x := -42.0 + i * 4.8
		_box("Festival lantern", Vector3(x, 5.0, -152), Vector3(1.15, 1.6, 1.0), "red")
		_box("Lantern glow", Vector3(x, 5.0, -152.55), Vector3(0.64, 0.88, 0.08), "window")
	# Decorative route markers and roadside race flags.
	for i in range(16):
		var x := -135.0 + i * 18.0
		_cylinder("Race flag pole", Vector3(x, 4.0, 117), 0.11, 8.0, "metal")
		_box("Race flag", Vector3(x + 1.1, 6.4, 117), Vector3(2.1, 1.1, 0.12), "red" if i % 2 == 0 else "white")

func _make_scene_camera() -> void:
	camera = Camera3D.new()
	camera.name = "Free roaming overview camera"
	camera.position = Vector3(0, 250, 350)
	camera.current = true
	camera.fov = 66
	camera.near = 0.1
	camera.far = 1800
	add_child(camera)
	look_yaw = 0.0
	look_pitch = -0.50
	_update_camera_rotation()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			mouse_look = event.pressed
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if mouse_look else Input.MOUSE_MODE_VISIBLE
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			fly_speed = min(fly_speed * 1.25, 260.0)
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			fly_speed = max(fly_speed / 1.25, 4.0)
	if event is InputEventMouseMotion and mouse_look:
		look_yaw -= event.relative.x * 0.0025
		look_pitch = clamp(look_pitch - event.relative.y * 0.0022, -1.52, 0.3)
		_update_camera_rotation()

func _process(delta: float) -> void:
	if camera == null:
		return
	var input_dir := Vector3.ZERO
	if Input.is_key_pressed(KEY_W): input_dir.z -= 1.0
	if Input.is_key_pressed(KEY_S): input_dir.z += 1.0
	if Input.is_key_pressed(KEY_A): input_dir.x -= 1.0
	if Input.is_key_pressed(KEY_D): input_dir.x += 1.0
	if Input.is_key_pressed(KEY_E): input_dir.y += 1.0
	if Input.is_key_pressed(KEY_Q): input_dir.y -= 1.0
	if input_dir != Vector3.ZERO:
		var basis := camera.global_transform.basis
		var motion := (basis * input_dir).normalized() * fly_speed * delta
		camera.position += motion

func _update_camera_rotation() -> void:
	if camera:
		camera.rotation = Vector3(look_pitch, look_yaw, 0)

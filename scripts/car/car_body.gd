extends Node3D
## Procedural car body: lofted bodywork with wheel arches, glass cabin, lights, wing and wheels.
## The paint is a colour-shifting metallic shader (Midnight Purple II by default), lights are dynamic
## (headlight spots, brake/reverse lights, emissive lenses).
## Coordinates: forward = -Z, ground = y 0 at rest.

const MeshKit = preload("res://scripts/util/mesh_kit.gd")
const TexKit = preload("res://scripts/util/tex_kit.gd")

## Loft tables: [z, half width, top height]
const BODIES := {
	"r34": {
		"length": 4.62, "wheel_r": 0.34, "wheel_w": 0.27, "track": 0.78, "axle_f": -1.33, "axle_r": 1.33,
		"base": 0.21, "nose_base": 0.15, "tail_base": 0.25, "crown": 0.035,
		"loft": [[-2.31, 0.66, 0.50], [-2.27, 0.80, 0.60], [-2.16, 0.87, 0.70], [-1.95, 0.89, 0.78], [-1.5, 0.895, 0.85],
			[-0.9, 0.9, 0.90], [-0.7, 0.9, 0.93], [0.2, 0.905, 0.97], [1.5, 0.905, 1.01], [1.95, 0.895, 1.035],
			[2.2, 0.87, 1.03], [2.3, 0.82, 0.97], [2.33, 0.74, 0.88]],
		"cabin": [[-0.75, 0.0], [-0.1, 1.0], [0.95, 1.0], [1.62, 0.0]], "roof": 1.37, "cabin_top_w": 0.64,
		"wing": "tall", "tail": "quad_round", "head": "angular", "flare": 0.03, "exhaust": "single_right",
	},
	"s15": {
		"length": 4.45, "wheel_r": 0.33, "wheel_w": 0.25, "track": 0.75, "axle_f": -1.26, "axle_r": 1.26,
		"base": 0.19, "nose_base": 0.14, "tail_base": 0.24, "crown": 0.04,
		"loft": [[-2.23, 0.6, 0.46], [-2.18, 0.76, 0.57], [-2.05, 0.84, 0.66], [-1.8, 0.86, 0.73], [-1.2, 0.865, 0.82],
			[-0.7, 0.865, 0.88], [0.2, 0.87, 0.93], [1.4, 0.87, 0.96], [1.9, 0.86, 0.98], [2.12, 0.83, 0.96],
			[2.2, 0.78, 0.9], [2.23, 0.7, 0.8]],
		"cabin": [[-0.72, 0.0], [-0.05, 1.0], [0.85, 1.0], [1.6, 0.0]], "roof": 1.29, "cabin_top_w": 0.6,
		"wing": "low", "tail": "bar", "head": "swept", "flare": 0.015, "exhaust": "single_right",
	},
	"ae86": {
		"length": 4.2, "wheel_r": 0.30, "wheel_w": 0.22, "track": 0.70, "axle_f": -1.2, "axle_r": 1.2,
		"base": 0.2, "nose_base": 0.16, "tail_base": 0.24, "crown": 0.02,
		"loft": [[-2.1, 0.7, 0.55], [-2.06, 0.8, 0.66], [-1.95, 0.815, 0.72], [-1.2, 0.82, 0.8], [-0.7, 0.82, 0.85],
			[0.5, 0.82, 0.9], [1.6, 0.82, 0.92], [2.0, 0.81, 0.92], [2.08, 0.77, 0.86], [2.1, 0.7, 0.78]],
		"cabin": [[-0.8, 0.0], [-0.15, 1.0], [0.9, 1.0], [2.02, 0.0]], "roof": 1.34, "cabin_top_w": 0.62,
		"wing": "lip", "tail": "wide_bar", "head": "popup", "flare": 0.0, "exhaust": "single_left",
	},
	"a80": {
		"length": 4.52, "wheel_r": 0.345, "wheel_w": 0.28, "track": 0.79, "axle_f": -1.28, "axle_r": 1.27,
		"base": 0.2, "nose_base": 0.15, "tail_base": 0.26, "crown": 0.06,
		"loft": [[-2.26, 0.5, 0.45], [-2.2, 0.74, 0.55], [-2.05, 0.86, 0.65], [-1.7, 0.9, 0.74], [-1.1, 0.905, 0.82],
			[-0.65, 0.905, 0.87], [0.3, 0.91, 0.92], [1.3, 0.91, 0.96], [1.9, 0.9, 0.99], [2.15, 0.87, 0.97],
			[2.24, 0.8, 0.9], [2.26, 0.7, 0.8]],
		"cabin": [[-0.7, 0.0], [0.0, 1.0], [0.75, 1.0], [1.7, 0.0]], "roof": 1.28, "cabin_top_w": 0.6,
		"wing": "hoop", "tail": "round_pairs", "head": "round", "flare": 0.02, "exhaust": "dual",
	},
}

var body_id := "r34"
var spec: Dictionary
var paint_mat: ShaderMaterial
var head_mat: StandardMaterial3D
var tail_mat: StandardMaterial3D
var reverse_mat: StandardMaterial3D
var head_spots: Array = []
var brake_light: OmniLight3D
var wheel_nodes: Array = []   # [pivot, spin] for FL, FR, RL, RR
var exhaust_points: Array = []
var shadows_for_lights := true


func build(p_body_id: String, paint: Dictionary, detailed_lights: bool) -> void:
	body_id = p_body_id if BODIES.has(p_body_id) else "r34"
	spec = BODIES[body_id]
	shadows_for_lights = detailed_lights
	paint_mat = TexKit.paint_material(paint)
	head_mat = TexKit.emissive(Color(0.95, 0.97, 1.0), 0.3)
	tail_mat = TexKit.emissive(Color(1.0, 0.05, 0.03), 0.6)
	reverse_mat = TexKit.emissive(Color(1.0, 1.0, 1.0), 0.0)
	_build_body()
	_build_cabin()
	_build_front()
	_build_rear()
	_build_misc()
	_build_wheels()
	_build_lights(detailed_lights)


func set_paint(paint: Dictionary) -> void:
	TexKit.apply_paint(paint_mat, paint)


func set_lights(headlights: bool, braking: bool, reversing: bool) -> void:
	head_mat.emission_energy_multiplier = 5.0 if headlights else 0.25
	for s in head_spots:
		(s as SpotLight3D).visible = headlights
	var tail := 0.6
	if headlights:
		tail = 1.6
	if braking:
		tail = 7.0
	tail_mat.emission_energy_multiplier = tail
	if brake_light:
		brake_light.visible = braking or headlights
		brake_light.light_energy = 1.4 if braking else 0.35
	reverse_mat.emission_energy_multiplier = 5.0 if reversing else 0.0


# ---------------------------------------------------------------------------
# Loft helpers
# ---------------------------------------------------------------------------
func _table_lerp(table: Array, z: float, col: int) -> float:
	if z <= float(table[0][0]):
		return float(table[0][col])
	for i in range(table.size() - 1):
		var a: Array = table[i]
		var b: Array = table[i + 1]
		if z <= float(b[0]):
			var t := (z - float(a[0])) / (float(b[0]) - float(a[0]))
			t = t * t * (3.0 - 2.0 * t)
			return lerpf(float(a[col]), float(b[col]), t)
	return float(table[table.size() - 1][col])


func _bottom_at(z: float) -> float:
	var length: float = spec["length"]
	var base: float = spec["base"]
	var y := base
	var front := -length * 0.5
	var rear := length * 0.5
	if z < front + 0.5:
		y = lerpf(spec["nose_base"], base, clampf((z - front) / 0.5, 0.0, 1.0))
	elif z > rear - 0.6:
		y = lerpf(base, spec["tail_base"], clampf((z - (rear - 0.6)) / 0.6, 0.0, 1.0))
	var r: float = spec["wheel_r"]
	var arch_r := r + 0.07
	for axle in [spec["axle_f"], spec["axle_r"]]:
		var dz: float = z - float(axle)
		if absf(dz) < arch_r:
			y = maxf(y, r + 0.03 + sqrt(arch_r * arch_r - dz * dz))
	return y


func _flare_at(z: float) -> float:
	var f: float = spec["flare"]
	var out := 0.0
	var r: float = spec["wheel_r"] + 0.25
	for axle in [spec["axle_f"], spec["axle_r"]]:
		var dz: float = absf(z - float(axle))
		if dz < r:
			out = maxf(out, f * (0.5 + 0.5 * cos(dz / r * PI)))
	return out


func _section(z: float, hw: float, yb: float, yt: float, crown: float) -> PackedVector3Array:
	var h := yt - yb
	var left: Array = [
		Vector2(-hw * 0.93, yb),
		Vector2(-hw, yb + minf(0.08, h * 0.25)),
		Vector2(-hw * 1.005, yb + h * 0.55),
		Vector2(-hw * 0.99, yt - h * 0.12),
		Vector2(-hw * 0.92, yt - 0.01),
		Vector2(-hw * 0.55, yt + crown * 0.7),
	]
	var ring := PackedVector3Array()
	ring.append(Vector3(0, yb, z))
	for p in left:
		ring.append(Vector3(p.x, p.y, z))
	ring.append(Vector3(0, yt + crown, z))
	for k in range(left.size() - 1, -1, -1):
		var p: Vector2 = left[k]
		ring.append(Vector3(-p.x, p.y, z))
	return ring


# ---------------------------------------------------------------------------
# Body
# ---------------------------------------------------------------------------
func _build_body() -> void:
	var loft: Array = spec["loft"]
	var z0: float = loft[0][0]
	var z1: float = loft[loft.size() - 1][0]
	var rows: Array = []
	var centers: Array = []
	var steps := 110
	for s in steps + 1:
		var t := float(s) / steps
		var z := lerpf(z0, z1, t)
		var hw := _table_lerp(loft, z, 1) + _flare_at(z)
		var yt := _table_lerp(loft, z, 2)
		var yb := minf(_bottom_at(z), yt - 0.06)
		rows.append(_section(z, hw, yb, yt, spec["crown"]))
		centers.append(Vector3(0, (yb + yt) * 0.5, z))
	var st := MeshKit.new_st()
	MeshKit.grid(st, rows, centers, true)
	var first: PackedVector3Array = rows[0]
	var last: PackedVector3Array = rows[rows.size() - 1]
	MeshKit.cap(st, first, centers[0] + Vector3(0, 0, -0.01), Vector3(0, 0, -1))
	MeshKit.cap(st, last, centers[centers.size() - 1] + Vector3(0, 0, 0.01), Vector3(0, 0, 1))
	var mi := MeshKit.mesh_instance(MeshKit.commit(st, paint_mat))
	mi.name = "Body"
	add_child(mi)
	# dark wheel wells so the arches read as openings
	var well := TexKit.std(Color(0.02, 0.02, 0.02), 0.9)
	var r: float = spec["wheel_r"]
	for axle in [spec["axle_f"], spec["axle_r"]]:
		var w := MeshKit.cyl_node(r + 0.06, r + 0.06, 1.55, well, Vector3(0, r + 0.03, float(axle)), Vector3(0, 0, PI * 0.5), 20)
		w.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(w)
	# underbody plate
	add_child(MeshKit.box_node(Vector3(1.6, 0.05, float(spec["length"]) * 0.8), TexKit.std(Color(0.05, 0.05, 0.05), 0.9), Vector3(0, float(spec["base"]) + 0.03, 0)))


func _build_cabin() -> void:
	var cab: Array = spec["cabin"]
	var loft: Array = spec["loft"]
	var z0: float = cab[0][0]
	var z1: float = cab[cab.size() - 1][0]
	var roof: float = spec["roof"]
	var top_w: float = spec["cabin_top_w"]
	var rows: Array = []
	var centers: Array = []
	var roof_rows: Array = []
	var roof_centers: Array = []
	var steps := 40
	var glass_mat := StandardMaterial3D.new()
	glass_mat.albedo_color = Color(0.015, 0.015, 0.025)
	glass_mat.metallic = 0.85
	glass_mat.roughness = 0.03
	glass_mat.clearcoat_enabled = true
	glass_mat.clearcoat = 1.0
	glass_mat.clearcoat_roughness = 0.0
	for s in steps + 1:
		var t := float(s) / steps
		var z := lerpf(z0, z1, t)
		var belt := _table_lerp(loft, z, 2) - 0.015
		var hw := _table_lerp(loft, z, 1) * 0.93
		var hfac := _table_lerp(cab, z, 1)
		var y_roof := belt + (roof - belt) * hfac
		var tw := lerpf(hw, top_w, hfac)
		var ring := PackedVector3Array()
		ring.append(Vector3(0, belt, z))
		ring.append(Vector3(-hw, belt, z))
		ring.append(Vector3(-lerpf(hw, tw, 0.55), lerpf(belt, y_roof, 0.55), z))
		ring.append(Vector3(-tw, y_roof - 0.025 * hfac, z))
		ring.append(Vector3(-tw * 0.55, y_roof, z))
		ring.append(Vector3(0, y_roof + 0.012 * hfac, z))
		ring.append(Vector3(tw * 0.55, y_roof, z))
		ring.append(Vector3(tw, y_roof - 0.025 * hfac, z))
		ring.append(Vector3(lerpf(hw, tw, 0.55), lerpf(belt, y_roof, 0.55), z))
		ring.append(Vector3(hw, belt, z))
		rows.append(ring)
		centers.append(Vector3(0, belt, z))
		# painted roof skin over the flat part of the cabin
		if hfac > 0.97:
			var rr := PackedVector3Array()
			var lift := 0.006
			rr.append(Vector3(-tw * 1.01, y_roof - 0.03, z))
			rr.append(Vector3(-tw * 0.55, y_roof + lift, z))
			rr.append(Vector3(0, y_roof + 0.012 + lift, z))
			rr.append(Vector3(tw * 0.55, y_roof + lift, z))
			rr.append(Vector3(tw * 1.01, y_roof - 0.03, z))
			roof_rows.append(rr)
			roof_centers.append(Vector3(0, belt, z))
	var st := MeshKit.new_st()
	MeshKit.grid(st, rows, centers, true)
	var mi := MeshKit.mesh_instance(MeshKit.commit(st, glass_mat))
	mi.name = "Cabin"
	add_child(mi)
	if roof_rows.size() >= 2:
		var rst := MeshKit.new_st()
		MeshKit.grid(rst, roof_rows, roof_centers, false)
		var rmi := MeshKit.mesh_instance(MeshKit.commit(rst, paint_mat))
		rmi.name = "Roof"
		add_child(rmi)
	# pillars (A, B, C) as painted / black tubes following the cabin edges
	for side in [-1.0, 1.0]:
		var a_pts: Array = []
		var c_pts: Array = []
		for s in steps + 1:
			var t := float(s) / steps
			var z := lerpf(z0, z1, t)
			var hfac := _table_lerp(cab, z, 1)
			var belt := _table_lerp(loft, z, 2) - 0.015
			var hw := _table_lerp(loft, z, 1) * 0.93
			var y_roof := belt + (roof - belt) * hfac
			var tw := lerpf(hw, top_w, hfac)
			var p := Vector3(side * tw * 1.005, y_roof - 0.025 * hfac, z)
			if hfac < 0.999 and z < (z0 + z1) * 0.5:
				a_pts.append(p)
			elif hfac < 0.999:
				c_pts.append(p)
		if a_pts.size() >= 2:
			var st2 := MeshKit.new_st()
			MeshKit.tube(st2, a_pts, _filled(a_pts.size(), 0.035), 6)
			add_child(MeshKit.mesh_instance(MeshKit.commit(st2, paint_mat)))
		if c_pts.size() >= 2:
			var st3 := MeshKit.new_st()
			MeshKit.tube(st3, c_pts, _filled(c_pts.size(), 0.07), 6)
			add_child(MeshKit.mesh_instance(MeshKit.commit(st3, paint_mat)))
		# B pillar
		var zb := lerpf(z0, z1, 0.5)
		var belt_b := _table_lerp(loft, zb, 2)
		var hw_b := _table_lerp(loft, zb, 1) * 0.93
		var b_pts := [Vector3(side * hw_b * 1.003, belt_b, zb), Vector3(side * lerpf(hw_b, top_w, 0.55) * 1.01, lerpf(belt_b, roof, 0.55), zb), Vector3(side * top_w * 1.01, roof - 0.03, zb)]
		var st4 := MeshKit.new_st()
		MeshKit.tube(st4, b_pts, [0.03, 0.03, 0.03], 5)
		add_child(MeshKit.mesh_instance(MeshKit.commit(st4, TexKit.black_plastic())))
		# window trim along the beltline
		var trim: Array = []
		for s in range(0, steps + 1, 2):
			var z := lerpf(z0 + 0.1, z1 - 0.1, float(s) / steps)
			trim.append(Vector3(side * _table_lerp(loft, z, 1) * 0.935, _table_lerp(loft, z, 2) - 0.005, z))
		var st5 := MeshKit.new_st()
		MeshKit.tube(st5, trim, _filled(trim.size(), 0.012), 4)
		add_child(MeshKit.mesh_instance(MeshKit.commit(st5, TexKit.chrome())))


func _filled(n: int, v: float) -> Array:
	var a: Array = []
	a.resize(n)
	a.fill(v)
	return a


func _front_z() -> float:
	return -float(spec["length"]) * 0.5


func _rear_z() -> float:
	return float(spec["length"]) * 0.5


func _build_front() -> void:
	var fz := _front_z()
	var loft: Array = spec["loft"]
	var black := TexKit.black_plastic()
	var hood_y := _table_lerp(loft, fz + 0.2, 2)
	# lower intake & upper grille
	add_child(MeshKit.box_node(Vector3(1.15, 0.2, 0.12), black, Vector3(0, 0.34, fz + 0.06)))
	add_child(MeshKit.box_node(Vector3(0.75, 0.07, 0.08), black, Vector3(0, hood_y - 0.1, fz + 0.1)))
	# splitter
	add_child(MeshKit.box_node(Vector3(1.72, 0.025, 0.22), TexKit.carbon(), Vector3(0, float(spec["nose_base"]) + 0.01, fz + 0.14)))
	# brake ducts / fog lights
	for side in [-1.0, 1.0]:
		add_child(MeshKit.box_node(Vector3(0.24, 0.1, 0.08), black, Vector3(side * 0.62, 0.33, fz + 0.1)))
		add_child(MeshKit.box_node(Vector3(0.12, 0.05, 0.03), TexKit.emissive(Color(1.0, 0.55, 0.05), 0.8), Vector3(side * 0.72, 0.42, fz + 0.09)))
	# headlights
	var head_style: String = spec["head"]
	for side in [-1.0, 1.0]:
		var hx := side * 0.58
		var hy := hood_y - 0.05
		var hz := fz + 0.2
		match head_style:
			"round":
				for k in 2:
					var lens := MeshKit.cyl_node(0.07, 0.07, 0.05, head_mat, Vector3(side * (0.55 + k * 0.15), hy - 0.02, hz - 0.02), Vector3(PI * 0.5, 0, 0), 16)
					add_child(lens)
				var housing := MeshKit.box_node(Vector3(0.42, 0.13, 0.22), TexKit.glass(), Vector3(side * 0.62, hy - 0.01, hz + 0.02))
				housing.rotation = Vector3(0.35, side * 0.15, 0)
				add_child(housing)
			"popup":
				var lid := MeshKit.box_node(Vector3(0.36, 0.03, 0.26), paint_mat, Vector3(hx, hood_y + 0.005, hz + 0.08))
				add_child(lid)
				add_child(MeshKit.box_node(Vector3(0.34, 0.04, 0.04), black, Vector3(hx, hood_y - 0.02, hz - 0.05)))
				add_child(MeshKit.box_node(Vector3(0.3, 0.08, 0.04), head_mat, Vector3(hx, 0.5, fz + 0.04)))
			_:
				var housing := MeshKit.box_node(Vector3(0.44, 0.12, 0.28), black, Vector3(hx, hy, hz))
				housing.rotation = Vector3(0.2, side * (0.28 if head_style == "angular" else 0.4), 0)
				add_child(housing)
				var lens := MeshKit.box_node(Vector3(0.38, 0.07, 0.24), head_mat, Vector3(hx, hy + 0.005, hz - 0.03))
				lens.rotation = housing.rotation
				add_child(lens)
				var proj := MeshKit.sphere_node(0.045, TexKit.chrome(), Vector3(hx + side * 0.08, hy, hz - 0.12))
				add_child(proj)
		var spot := SpotLight3D.new()
		spot.position = Vector3(hx, hy, fz - 0.05)
		spot.rotation = Vector3(-0.06, 0, 0)
		spot.light_color = Color(0.95, 0.95, 1.0)
		spot.light_energy = 7.0
		spot.spot_range = 70.0
		spot.spot_angle = 26.0
		spot.spot_attenuation = 0.6
		spot.shadow_enabled = shadows_for_lights and side > 0.0
		spot.visible = false
		add_child(spot)
		head_spots.append(spot)


func _build_rear() -> void:
	var rz := _rear_z()
	var loft: Array = spec["loft"]
	var deck_y := _table_lerp(loft, rz - 0.15, 2)
	var black := TexKit.black_plastic()
	# diffuser + plate
	add_child(MeshKit.box_node(Vector3(1.35, 0.12, 0.25), TexKit.carbon(), Vector3(0, float(spec["tail_base"]) + 0.05, rz - 0.1)))
	add_child(MeshKit.box_node(Vector3(0.52, 0.13, 0.02), TexKit.std(Color(0.92, 0.92, 0.9), 0.5), Vector3(0, 0.56, rz + 0.005)))
	var ty := deck_y - 0.16
	var tail_style: String = spec["tail"]
	match tail_style:
		"quad_round", "round_pairs":
			var xs := [0.34, 0.6] if tail_style == "quad_round" else [0.45, 0.66]
			var rad := 0.075 if tail_style == "quad_round" else 0.09
			for side in [-1.0, 1.0]:
				for x in xs:
					var zpos := rz + 0.005 - absf(float(x)) * 0.06
					add_child(MeshKit.cyl_node(rad + 0.018, rad + 0.018, 0.04, TexKit.chrome(), Vector3(side * float(x), ty, zpos - 0.01), Vector3(PI * 0.5, 0, 0), 20))
					add_child(MeshKit.cyl_node(rad, rad, 0.05, tail_mat, Vector3(side * float(x), ty, zpos), Vector3(PI * 0.5, 0, 0), 20))
		"wide_bar":
			add_child(MeshKit.box_node(Vector3(1.5, 0.14, 0.04), black, Vector3(0, ty, rz + 0.0)))
			for side in [-1.0, 1.0]:
				add_child(MeshKit.box_node(Vector3(0.5, 0.11, 0.05), tail_mat, Vector3(side * 0.5, ty, rz + 0.005)))
		_:
			for side in [-1.0, 1.0]:
				var bar := MeshKit.box_node(Vector3(0.5, 0.09, 0.08), tail_mat, Vector3(side * 0.55, ty, rz - 0.02))
				bar.rotation.y = side * -0.12
				add_child(bar)
	for side in [-1.0, 1.0]:
		add_child(MeshKit.box_node(Vector3(0.1, 0.05, 0.03), reverse_mat, Vector3(side * 0.18, 0.42, rz - 0.02)))
	# exhaust
	var ex_style: String = spec["exhaust"]
	var ex_x: Array = [0.55]
	if ex_style == "single_left":
		ex_x = [-0.55]
	elif ex_style == "dual":
		ex_x = [-0.5, 0.5]
	for x in ex_x:
		var pos := Vector3(float(x), float(spec["tail_base"]) + 0.07, rz - 0.05)
		add_child(MeshKit.cyl_node(0.06, 0.06, 0.3, TexKit.chrome(), pos, Vector3(PI * 0.5, 0, 0), 16))
		add_child(MeshKit.cyl_node(0.045, 0.045, 0.31, black, pos, Vector3(PI * 0.5, 0, 0), 16))
		exhaust_points.append(pos + Vector3(0, 0, 0.16))
	# wing
	var wing: String = spec["wing"]
	var wz := rz - 0.28
	match wing:
		"tall":
			for side in [-1.0, 1.0]:
				add_child(MeshKit.box_node(Vector3(0.05, 0.17, 0.2), paint_mat, Vector3(side * 0.62, deck_y + 0.08, wz)))
			var blade := MeshKit.box_node(Vector3(1.56, 0.035, 0.28), paint_mat, Vector3(0, deck_y + 0.18, wz + 0.02))
			blade.rotation.x = -0.1
			add_child(blade)
			var flap := MeshKit.box_node(Vector3(1.5, 0.02, 0.1), TexKit.carbon(), Vector3(0, deck_y + 0.21, wz + 0.16))
			flap.rotation.x = -0.35
			add_child(flap)
		"hoop":
			var pts: Array = []
			for k in 13:
				var a := PI * float(k) / 12.0
				pts.append(Vector3(-cos(a) * 0.72, deck_y + 0.02 + sin(a) * 0.26, wz))
			var st := MeshKit.new_st()
			MeshKit.tube(st, pts, _filled(pts.size(), 0.035), 8)
			add_child(MeshKit.mesh_instance(MeshKit.commit(st, paint_mat)))
			var blade := MeshKit.box_node(Vector3(1.3, 0.03, 0.22), paint_mat, Vector3(0, deck_y + 0.28, wz))
			add_child(blade)
		"low":
			var blade := MeshKit.box_node(Vector3(1.45, 0.04, 0.22), paint_mat, Vector3(0, deck_y + 0.09, wz + 0.05))
			blade.rotation.x = -0.12
			add_child(blade)
			for side in [-1.0, 1.0]:
				add_child(MeshKit.box_node(Vector3(0.04, 0.08, 0.14), paint_mat, Vector3(side * 0.55, deck_y + 0.04, wz + 0.05)))
		_:
			add_child(MeshKit.box_node(Vector3(1.4, 0.04, 0.12), black, Vector3(0, deck_y + 0.02, rz - 0.15)))


func _build_misc() -> void:
	var loft: Array = spec["loft"]
	var black := TexKit.black_plastic()
	var cab: Array = spec["cabin"]
	var mz: float = float(cab[0][0]) + 0.35
	for side in [-1.0, 1.0]:
		var hw := _table_lerp(loft, mz, 1)
		var belt := _table_lerp(loft, mz, 2)
		# mirror
		add_child(MeshKit.box_node(Vector3(0.05, 0.03, 0.06), black, Vector3(side * (hw + 0.02), belt + 0.04, mz)))
		var mirror := MeshKit.box_node(Vector3(0.16, 0.1, 0.12), paint_mat, Vector3(side * (hw + 0.1), belt + 0.08, mz + 0.02))
		mirror.rotation.y = side * 0.15
		add_child(mirror)
		# side skirt
		var len_side := (float(spec["axle_r"]) - float(spec["axle_f"])) - float(spec["wheel_r"]) * 2.0 - 0.2
		var zc := (float(spec["axle_r"]) + float(spec["axle_f"])) * 0.5
		add_child(MeshKit.box_node(Vector3(0.05, 0.1, len_side), black, Vector3(side * (_table_lerp(loft, zc, 1) - 0.005), float(spec["base"]) + 0.04, zc)))
		# door handle + door gap line
		add_child(MeshKit.box_node(Vector3(0.02, 0.025, 0.14), black, Vector3(side * (_table_lerp(loft, 0.35, 1) + 0.004), _table_lerp(loft, 0.35, 2) - 0.1, 0.35)))
		for gz in [mz + 0.15, 0.9]:
			var hwz := _table_lerp(loft, gz, 1) + _flare_at(gz)
			var line := MeshKit.box_node(Vector3(0.006, _table_lerp(loft, gz, 2) - float(spec["base"]) - 0.12, 0.008), black,
				Vector3(side * (hwz + 0.004), (float(spec["base"]) + _table_lerp(loft, gz, 2)) * 0.5, gz))
			add_child(line)
	# hood duct (carbon) on the R34 / A80
	if body_id == "r34" or body_id == "a80":
		var hz := _front_z() + 0.9
		var duct := MeshKit.box_node(Vector3(0.5, 0.015, 0.36), TexKit.carbon(), Vector3(0, _table_lerp(loft, hz, 2) + 0.03, hz))
		duct.rotation.x = 0.08
		add_child(duct)


# ---------------------------------------------------------------------------
# Wheels
# ---------------------------------------------------------------------------
func _build_wheels() -> void:
	var r: float = spec["wheel_r"]
	var w: float = spec["wheel_w"]
	var tr: float = spec["track"]
	var positions := [
		Vector3(-tr, r, spec["axle_f"]), Vector3(tr, r, spec["axle_f"]),
		Vector3(-tr, r, spec["axle_r"]), Vector3(tr, r, spec["axle_r"]),
	]
	var rim_mat := TexKit.std(Color(0.55, 0.55, 0.58), 0.25, 0.9)
	if body_id == "r34":
		rim_mat = TexKit.std(Color(0.12, 0.12, 0.13), 0.3, 0.8)
	var disc_mat := TexKit.std(Color(0.4, 0.4, 0.42), 0.45, 0.9)
	var caliper_mat := TexKit.std(Color(0.8, 0.1, 0.08), 0.35, 0.3)
	if body_id == "r34":
		caliper_mat = TexKit.std(Color(0.85, 0.65, 0.05), 0.35, 0.3)
	for i in 4:
		var side := -1.0 if i % 2 == 0 else 1.0
		var pivot := Node3D.new()
		pivot.name = ["WheelFL", "WheelFR", "WheelRL", "WheelRR"][i]
		pivot.position = positions[i]
		add_child(pivot)
		var spin := Node3D.new()
		pivot.add_child(spin)
		# tyre with rounded shoulders: main tread + two sidewall rings
		var tread := MeshKit.cyl_node(r, r, w * 0.82, TexKit.rubber(), Vector3.ZERO, Vector3(0, 0, PI * 0.5), 32)
		spin.add_child(tread)
		for s in [-1.0, 1.0]:
			var wall := MeshKit.cyl_node(r * 0.95, r, w * 0.09, TexKit.rubber(), Vector3(s * w * 0.455, 0, 0), Vector3(0, 0, -s * PI * 0.5), 32)
			spin.add_child(wall)
		# rim barrel, face, spokes, hub
		var face_x := side * (w * 0.5 - 0.02)
		spin.add_child(MeshKit.cyl_node(r * 0.7, r * 0.7, 0.03, rim_mat, Vector3(face_x, 0, 0), Vector3(0, 0, PI * 0.5), 32))
		spin.add_child(MeshKit.cyl_node(r * 0.62, r * 0.62, 0.035, TexKit.std(Color(0.03, 0.03, 0.03), 0.8), Vector3(face_x + side * 0.004, 0, 0), Vector3(0, 0, PI * 0.5), 32))
		var spokes := 6 if body_id == "r34" else 5
		for k in spokes:
			var a := TAU * float(k) / spokes
			var spoke := MeshKit.box_node(Vector3(0.03, r * 0.62, 0.055), rim_mat, Vector3(face_x + side * 0.012, 0, 0))
			spoke.rotation.x = a
			spoke.position += Vector3(0, cos(a) * r * 0.31, sin(a) * r * 0.31)
			spin.add_child(spoke)
		spin.add_child(MeshKit.cyl_node(r * 0.14, r * 0.16, 0.05, rim_mat, Vector3(face_x + side * 0.015, 0, 0), Vector3(0, 0, PI * 0.5), 12))
		spin.add_child(MeshKit.cyl_node(r * 0.5, r * 0.5, 0.025, disc_mat, Vector3(side * (w * 0.5 - 0.1), 0, 0), Vector3(0, 0, PI * 0.5), 24))
		# caliper does not spin
		var cal := MeshKit.box_node(Vector3(0.06, 0.16, 0.1), caliper_mat, Vector3(side * (w * 0.5 - 0.08), r * 0.36, 0.09 if i < 2 else -0.09))
		pivot.add_child(cal)
		wheel_nodes.append([pivot, spin])


func _build_lights(detailed: bool) -> void:
	brake_light = OmniLight3D.new()
	brake_light.light_color = Color(1.0, 0.08, 0.04)
	brake_light.omni_range = 4.5
	brake_light.light_energy = 0.35
	brake_light.shadow_enabled = false
	brake_light.position = Vector3(0, 0.8, _rear_z() + 0.4)
	brake_light.visible = false
	add_child(brake_light)
	if detailed:
		# subtle purple underglow for the player's car
		var glow := OmniLight3D.new()
		glow.light_color = Color(0.55, 0.2, 1.0)
		glow.omni_range = 2.6
		glow.light_energy = 0.5
		glow.position = Vector3(0, 0.1, 0)
		glow.name = "Underglow"
		add_child(glow)

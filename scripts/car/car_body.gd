extends Node3D
## Procedural car body (v2).
## The body is a loft of 12-point cross-section profiles (rocker, flare, character line, shoulder,
## hood/deck) that are interpolated smoothly along the car. Wheel arches are cut out of the loft,
## the greenhouse is a separate parametric surface with real (tinted, see-through) glass, a
## right-hand-drive interior, panel gaps, lamps, grilles, wing and lathe-turned wheels.
## Coordinates: forward = -Z, ground = y 0 at rest, wheel centres at y = wheel_r.

const MeshKit = preload("res://scripts/util/mesh_kit.gd")
const TexKit = preload("res://scripts/util/tex_kit.gd")

## Tables are [z, value] pairs, interpolated smoothly.
## hw = half width at the character line, char = character line height, shoulder = height of the
## side's upper edge (beltline under the cabin, fender top elsewhere).
const BODIES := {
	"r34": {
		"length": 4.60, "wheel_r": 0.335, "wheel_w": 0.245, "track": 0.765, "axle_f": -1.33, "axle_r": 1.335,
		"base": 0.19, "roof": 1.355, "crown": 0.022, "valley": 0.018, "flare_f": 0.03, "flare_r": 0.042, "arch_gap": 0.06,
		"hw": [[-2.30, 0.70], [-2.28, 0.80], [-2.22, 0.855], [-2.08, 0.876], [-1.75, 0.884], [0.0, 0.888], [1.85, 0.888], [2.12, 0.876], [2.25, 0.845], [2.30, 0.80]],
		"bottom": [[-2.30, 0.24], [-2.27, 0.15], [-2.0, 0.145], [-1.72, 0.19], [1.72, 0.2], [2.05, 0.24], [2.26, 0.30], [2.30, 0.36]],
		"char": [[-2.30, 0.44], [-2.22, 0.53], [-2.0, 0.62], [-1.4, 0.69], [0.0, 0.73], [1.4, 0.77], [2.2, 0.79], [2.30, 0.77]],
		"shoulder": [[-2.30, 0.54], [-2.27, 0.605], [-2.16, 0.665], [-1.92, 0.73], [-1.3, 0.795], [-0.74, 0.845], [-0.35, 0.915], [0.3, 0.955], [1.5, 0.99], [2.0, 1.015], [2.22, 1.005], [2.30, 0.94]],
		"cabin": [[-0.76, 0.0], [-0.45, 0.56], [-0.1, 1.0], [0.9, 1.0], [1.2, 0.66], [1.55, 0.0]],
		"ws_top": -0.1, "rw_top": 0.9, "side_end": 0.98, "b_pillar": 0.34, "cabin_top_w": 0.60, "tumble": 0.018,
		"head": "r34", "tail": "quad_round", "wing": "r34", "exhaust": [0.52], "grille": "r34", "vent": true,
		"rim": Color(0.16, 0.16, 0.18), "caliper": Color(0.85, 0.62, 0.08), "spokes": 5, "twin": true,
	},
	"s15": {
		"length": 4.445, "wheel_r": 0.32, "wheel_w": 0.235, "track": 0.73, "axle_f": -1.23, "axle_r": 1.295,
		"base": 0.17, "roof": 1.285, "crown": 0.03, "valley": 0.012, "flare_f": 0.012, "flare_r": 0.018, "arch_gap": 0.055,
		"hw": [[-2.22, 0.62], [-2.19, 0.76], [-2.10, 0.82], [-1.9, 0.842], [-1.4, 0.847], [0.5, 0.85], [1.8, 0.848], [2.07, 0.835], [2.18, 0.80], [2.22, 0.74]],
		"bottom": [[-2.22, 0.24], [-2.19, 0.14], [-1.95, 0.14], [-1.6, 0.18], [1.7, 0.19], [2.0, 0.23], [2.18, 0.30], [2.22, 0.36]],
		"char": [[-2.22, 0.40], [-2.1, 0.50], [-1.8, 0.58], [-1.0, 0.64], [0.5, 0.68], [1.6, 0.72], [2.22, 0.74]],
		"shoulder": [[-2.22, 0.50], [-2.18, 0.57], [-2.05, 0.63], [-1.7, 0.69], [-1.1, 0.755], [-0.72, 0.80], [-0.3, 0.87], [0.4, 0.905], [1.5, 0.935], [2.0, 0.955], [2.16, 0.94], [2.22, 0.88]],
		"cabin": [[-0.74, 0.0], [-0.4, 0.6], [-0.02, 1.0], [0.8, 1.0], [1.15, 0.6], [1.5, 0.0]],
		"ws_top": -0.02, "rw_top": 0.8, "side_end": 0.95, "b_pillar": 0.3, "cabin_top_w": 0.57, "tumble": 0.022,
		"head": "swept", "tail": "bar", "wing": "low", "exhaust": [0.5], "grille": "s15", "vent": false,
		"rim": Color(0.62, 0.63, 0.66), "caliper": Color(0.75, 0.1, 0.08), "spokes": 6, "twin": false,
	},
	"ae86": {
		"length": 4.18, "wheel_r": 0.29, "wheel_w": 0.2, "track": 0.69, "axle_f": -1.17, "axle_r": 1.23,
		"base": 0.18, "roof": 1.33, "crown": 0.015, "valley": 0.006, "flare_f": 0.0, "flare_r": 0.004, "arch_gap": 0.06,
		"hw": [[-2.09, 0.74], [-2.07, 0.79], [-2.0, 0.805], [-1.6, 0.81], [1.8, 0.812], [2.03, 0.80], [2.09, 0.77]],
		"bottom": [[-2.09, 0.22], [-2.06, 0.17], [-1.8, 0.17], [1.8, 0.2], [2.05, 0.25], [2.09, 0.30]],
		"char": [[-2.09, 0.5], [-1.9, 0.6], [-1.0, 0.64], [1.5, 0.68], [2.09, 0.70]],
		"shoulder": [[-2.09, 0.6], [-2.05, 0.66], [-1.9, 0.70], [-1.2, 0.76], [-0.75, 0.8], [-0.3, 0.86], [0.5, 0.89], [1.6, 0.91], [2.0, 0.92], [2.09, 0.89]],
		"cabin": [[-0.78, 0.0], [-0.45, 0.6], [-0.08, 1.0], [0.95, 1.0], [1.6, 0.45], [2.02, 0.0]],
		"ws_top": -0.08, "rw_top": 0.95, "side_end": 1.3, "b_pillar": 0.35, "cabin_top_w": 0.62, "tumble": 0.012,
		"head": "popup", "tail": "wide_bar", "wing": "lip", "exhaust": [-0.45], "grille": "ae86", "vent": false,
		"rim": Color(0.55, 0.56, 0.58), "caliper": Color(0.25, 0.25, 0.27), "spokes": 8, "twin": false,
	},
	"a80": {
		"length": 4.52, "wheel_r": 0.34, "wheel_w": 0.255, "track": 0.785, "axle_f": -1.25, "axle_r": 1.30,
		"base": 0.18, "roof": 1.275, "crown": 0.05, "valley": 0.01, "flare_f": 0.025, "flare_r": 0.035, "arch_gap": 0.06,
		"hw": [[-2.26, 0.55], [-2.22, 0.74], [-2.12, 0.84], [-1.9, 0.89], [-1.3, 0.903], [0.5, 0.905], [1.7, 0.905], [2.05, 0.89], [2.2, 0.84], [2.26, 0.77]],
		"bottom": [[-2.26, 0.22], [-2.22, 0.14], [-1.9, 0.15], [-1.6, 0.18], [1.7, 0.19], [2.1, 0.25], [2.26, 0.34]],
		"char": [[-2.26, 0.38], [-2.1, 0.5], [-1.6, 0.6], [-0.5, 0.66], [1.2, 0.7], [2.26, 0.73]],
		"shoulder": [[-2.26, 0.46], [-2.2, 0.55], [-2.05, 0.63], [-1.7, 0.70], [-1.1, 0.76], [-0.7, 0.81], [-0.3, 0.87], [0.4, 0.90], [1.4, 0.93], [1.95, 0.96], [2.15, 0.95], [2.26, 0.86]],
		"cabin": [[-0.7, 0.0], [-0.35, 0.62], [0.0, 1.0], [0.72, 1.0], [1.15, 0.55], [1.62, 0.0]],
		"ws_top": 0.0, "rw_top": 0.72, "side_end": 0.95, "b_pillar": 0.3, "cabin_top_w": 0.56, "tumble": 0.03,
		"head": "a80", "tail": "round_pairs", "wing": "hoop", "exhaust": [-0.48, 0.48], "grille": "a80", "vent": false,
		"rim": Color(0.7, 0.71, 0.73), "caliper": Color(0.8, 0.1, 0.08), "spokes": 5, "twin": false,
	},
}

## Imported car models (converted from Blend Swap files with tools/convert_cars.py).
## Positions are in car space (forward = -Z, ground = y 0); values come from the converter's JSON.
const MODELS := {
	"r34": {
		"path": "res://assets/cars/r34.glb", "wheel_r": 0.343, "wheel_w": 0.3, "track": 0.734,
		"axle_f": -1.33, "axle_r": 1.33, "length": 4.6, "half_width": 0.89, "base": 0.16, "roof": 1.3,
		"head": [[-0.65, 0.666, -2.0], [0.65, 0.666, -2.0]], "tail": [[-0.53, 0.85, 2.17], [0.53, 0.85, 2.17]],
		"exhaust": [[-0.409, 0.317, 2.29]], "exhaust_r": 0.045,
		# the model is an empty shell from below: floor pan, wheel arch liners, exhaust added
		"underbody": true,
	},
	"mustang": {
		"path": "res://assets/cars/mustang.glb", "wheel_r": 0.34, "wheel_w": 0.27, "track": 0.834,
		"axle_f": -1.357, "axle_r": 1.357, "length": 4.78, "half_width": 0.95, "base": 0.14, "roof": 1.36,
		"head": [[-0.75, 0.55, -1.8], [0.75, 0.55, -1.8]], "tail": [[-0.58, 0.66, 2.27], [0.58, 0.66, 2.27]],
		"exhaust": [[-0.66, 0.29, 2.27], [0.66, 0.29, 2.27]], "exhaust_r": 0.065,
	},
	"m3gt3": {
		"path": "res://assets/cars/m3gt3.glb", "wheel_r": 0.322, "wheel_w": 0.28, "track": 0.793,
		"axle_f": -1.3265, "axle_r": 1.3265, "length": 4.62, "half_width": 0.93, "base": 0.1, "roof": 1.23,
		"head": [[-0.54, 0.49, -1.85], [0.54, 0.49, -1.85]], "tail": [[-0.47, 0.68, 2.17], [0.47, 0.68, 2.17]],
		"exhaust": [[-0.526, 0.179, 2.24], [-0.452, 0.179, 2.255], [0.452, 0.179, 2.255], [0.526, 0.179, 2.24]], "exhaust_r": 0.026,
	},
	"m3e46": {
		"path": "res://assets/cars/m3e46.glb", "wheel_r": 0.315, "wheel_w": 0.3, "track": 0.716,
		"axle_f": -1.375, "axle_r": 1.375, "length": 4.49, "half_width": 0.89, "base": 0.184, "roof": 1.378,
		"head": [[-0.565, 0.599, -1.925], [0.571, 0.599, -1.924]], "tail": [[-0.58, 0.752, 2.213], [0.581, 0.745, 2.213]],
		"exhaust": [[-0.384, 0.274, 2.31], [-0.308, 0.274, 2.31], [0.308, 0.274, 2.31], [0.384, 0.274, 2.31]], "exhaust_r": 0.035,
	},
	"gallardo": {
		"path": "res://assets/cars/gallardo.glb", "wheel_r": 0.335, "wheel_w": 0.29, "track": 0.817,
		"axle_f": -1.292, "axle_r": 1.288, "length": 4.3, "half_width": 0.95, "base": 0.182, "roof": 1.184,
		"head": [[-0.745, 0.609, -1.864], [0.744, 0.606, -1.867]], "tail": [[-0.66, 0.862, 1.787], [0.653, 0.86, 1.792]],
		"exhaust": [[-0.59, 0.405, 1.95], [0.59, 0.405, 1.95]], "exhaust_r": 0.06,
	},
	"gt3rsr": {
		"path": "res://assets/cars/gt3rsr.glb", "wheel_r": 0.311, "wheel_w": 0.269, "track": 0.869,
		"axle_f": -1.177, "axle_r": 1.176, "length": 4.43, "half_width": 0.975, "base": 0.064, "roof": 1.187,
		"head": [[-0.677, 0.619, -1.653], [0.677, 0.619, -1.653]], "tail": [[-0.636, 0.591, 1.95], [0.639, 0.59, 1.948]],
		"exhaust": [[-0.085, 0.272, 2.25], [0.085, 0.272, 2.25]], "exhaust_r": 0.042,
	},
	"aventador": {
		"path": "res://assets/cars/aventador.glb", "wheel_r": 0.361, "wheel_w": 0.3, "track": 0.82,
		"axle_f": -1.369, "axle_r": 1.369, "length": 4.78, "half_width": 1.015, "base": 0.148, "roof": 1.141,
		"head": [[-0.636, 0.582, -2.051], [0.636, 0.582, -2.051]], "tail": [[-0.677, 0.767, 2.048], [0.677, 0.767, 2.048]],
		"exhaust": [[-0.13, 0.36, 2.26], [0.0, 0.33, 2.27], [0.13, 0.36, 2.26]], "exhaust_r": 0.05,
	},
	"supra": {
		"path": "res://assets/cars/supra.glb", "wheel_r": 0.308, "wheel_w": 0.266, "track": 0.788,
		"axle_f": -1.277, "axle_r": 1.277, "length": 4.515, "half_width": 0.92, "base": 0.064, "roof": 1.195,
		"head": [[-0.531, 0.531, -1.936], [0.532, 0.531, -1.935]], "tail": [[-0.383, 0.739, 2.126], [0.383, 0.739, 2.126]],
		"exhaust": [[-0.522, 0.265, 2.2]], "exhaust_r": 0.05,
	},
	"yaris": {
		"path": "res://assets/cars/yaris.glb", "wheel_r": 0.307, "wheel_w": 0.212, "track": 0.731,
		"axle_f": -1.194, "axle_r": 1.194, "length": 3.66, "half_width": 0.86, "base": 0.187, "roof": 1.5,
		"head": [[-0.656, 0.694, -1.658], [0.656, 0.694, -1.658]], "tail": [[-0.673, 0.86, 1.531], [0.673, 0.86, 1.531]],
		"exhaust": [[-0.42, 0.22, 1.8]], "exhaust_r": 0.025,
	},
	"m6gt3": {
		"path": "res://assets/cars/m6gt3.glb", "wheel_r": 0.367, "wheel_w": 0.33, "track": 0.865,
		"axle_f": -1.419, "axle_r": 1.419, "length": 4.94, "half_width": 1.03, "base": 0.042, "roof": 1.336,
		"head": [[-0.668, 0.564, -1.93], [0.666, 0.566, -1.929]], "tail": [[-0.562, 0.737, 2.293], [0.568, 0.735, 2.291]],
		"exhaust": [[-0.98, 0.2, 0.8], [0.98, 0.2, 0.8]], "exhaust_r": 0.045,
	},
	"m4f82": {
		"path": "res://assets/cars/m4f82.glb", "wheel_r": 0.302, "wheel_w": 0.23, "track": 0.725,
		"axle_f": -1.427, "axle_r": 1.427, "length": 4.67, "half_width": 0.935, "base": 0.141, "roof": 1.318,
		"head": [[-0.599, 0.574, -1.894], [0.6, 0.574, -1.894]], "tail": [[-0.512, 0.73, 2.123], [0.512, 0.73, 2.123]],
		"exhaust": [[-0.328, 0.236, 2.384], [-0.245, 0.236, 2.384], [0.245, 0.236, 2.384], [0.328, 0.236, 2.384]], "exhaust_r": 0.037,
	},
}

const U_MAX := 11.0   # profile parameter range (12 control points)
const U_CHAR := 5.0
const U_SHOULDER := 8.0

static var _wheel_cache := {}

var body_id := "r34"
var spec: Dictionary
var paint_mat: StandardMaterial3D
var head_mat: StandardMaterial3D
var tail_mat: StandardMaterial3D
var reverse_mat: StandardMaterial3D
var glass_mat: StandardMaterial3D
var trim_mat: StandardMaterial3D
var head_spots: Array = []
var brake_light: OmniLight3D
var wheel_nodes: Array = []   # [pivot, spin] for FL, FR, RL, RR
var exhaust_points: Array = []    # exhaust tip centres in car space (flames start here, pointing +Z)
var exhaust_radius := 0.05
var shadows_for_lights := true
var _front := -2.3
var _rear := 2.3


## Physics dimensions for a car id (imported model if available, procedural body otherwise).
static func physics_spec(car_id: String) -> Dictionary:
	if MODELS.has(car_id):
		return MODELS[car_id]
	return BODIES.get(car_id, BODIES["r34"])


func build(p_body_id: String, paint: Dictionary, detailed_lights: bool) -> void:
	if MODELS.has(p_body_id) and ResourceLoader.exists(MODELS[p_body_id]["path"]):
		body_id = p_body_id
		shadows_for_lights = detailed_lights
		_build_from_model(MODELS[p_body_id], paint)
		return
	if MODELS.has(p_body_id):
		push_warning("MODEL MISSING: %s – using the procedural fallback body" % MODELS[p_body_id]["path"])
	body_id = p_body_id if BODIES.has(p_body_id) else "r34"
	spec = BODIES[body_id]
	shadows_for_lights = detailed_lights
	_front = -float(spec["length"]) * 0.5
	_rear = float(spec["length"]) * 0.5
	paint_mat = TexKit.paint_material(paint)
	head_mat = TexKit.std(Color(0.78, 0.8, 0.84), 0.08, 0.7, Color(0.95, 0.97, 1.0), 0.25)
	tail_mat = TexKit.emissive(Color(1.0, 0.04, 0.03), 0.6)
	tail_mat.albedo_color = Color(0.45, 0.02, 0.02)
	tail_mat.roughness = 0.08
	reverse_mat = TexKit.std(Color(0.8, 0.8, 0.82), 0.1, 0.3, Color(1, 1, 1), 0.0)
	trim_mat = TexKit.black_plastic()
	glass_mat = StandardMaterial3D.new()
	glass_mat.albedo_color = Color(0.02, 0.025, 0.035, 0.62)
	glass_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass_mat.roughness = 0.02
	glass_mat.metallic = 0.25
	glass_mat.metallic_specular = 1.0
	glass_mat.clearcoat_enabled = true
	glass_mat.clearcoat = 1.0
	glass_mat.clearcoat_roughness = 0.0
	_build_body()
	_build_cabin()
	_build_panel_lines()
	_build_front()
	_build_rear()
	_build_side_details()
	_build_wing()
	_build_interior()
	_build_wheels()
	_build_lights()


func set_paint(paint: Dictionary) -> void:
	TexKit.apply_paint(paint_mat, paint)


func set_lights(headlights: bool, braking: bool, reversing: bool) -> void:
	head_mat.emission_energy_multiplier = 4.5 if headlights else 0.25
	for s in head_spots:
		(s as SpotLight3D).visible = headlights
	var tail := 0.5
	if headlights:
		tail = 1.8
	if braking:
		tail = 7.0
	tail_mat.emission_energy_multiplier = tail
	if brake_light:
		brake_light.visible = braking or headlights
		brake_light.light_energy = 1.4 if braking else 0.3
	reverse_mat.emission_energy_multiplier = 5.0 if reversing else 0.0


# ---------------------------------------------------------------------------
# Profile evaluation
# ---------------------------------------------------------------------------
func _t(key: String, z: float) -> float:
	var table: Array = spec[key]
	if z <= float(table[0][0]):
		return float(table[0][1])
	for i in range(table.size() - 1):
		var a: Array = table[i]
		var b: Array = table[i + 1]
		if z <= float(b[0]):
			var t := (z - float(a[0])) / (float(b[0]) - float(a[0]))
			t = t * t * (3.0 - 2.0 * t)
			return lerpf(float(a[1]), float(b[1]), t)
	return float(table[table.size() - 1][1])


func _flare_at(z: float) -> float:
	var out := 0.0
	var r: float = spec["wheel_r"]
	for pair in [[spec["axle_f"], spec["flare_f"]], [spec["axle_r"], spec["flare_r"]]]:
		var dz := absf(z - float(pair[0]))
		var f: float = pair[1]
		var t := clampf((r + 0.42 - dz) / 0.22, 0.0, 1.0)
		out = maxf(out, f * t * t * (3.0 - 2.0 * t))
	return out


## Height of the wheel arch opening at z (or -1 outside the arches).
func _arch_y(z: float) -> float:
	var r: float = spec["wheel_r"]
	var arch_r: float = r + float(spec["arch_gap"])
	var y := -1.0
	for axle in [spec["axle_f"], spec["axle_r"]]:
		var dz: float = z - float(axle)
		if absf(dz) < arch_r:
			y = maxf(y, r + sqrt(arch_r * arch_r - dz * dz))
	return y


func _half_profile(z: float) -> Array:
	var hw := _t("hw", z)
	var yb := _t("bottom", z)
	var ys := _t("shoulder", z)
	var yc := clampf(_t("char", z), yb + 0.1, ys - 0.05)
	var yt := ys - float(spec["valley"])
	var crown: float = spec["crown"]
	var fl := _flare_at(z)
	return [
		Vector2(0.0, yb),
		Vector2(-(hw - 0.07), yb),
		Vector2(-(hw - 0.014 + fl * 0.6), yb + 0.045),
		Vector2(-(hw + fl), lerpf(yb, yc, 0.38)),
		Vector2(-(hw + fl * 0.85), lerpf(yb, yc, 0.76)),
		Vector2(-(hw + 0.004 + fl * 0.3), yc),
		Vector2(-(hw - 0.006), lerpf(yc, ys, 0.45)),
		Vector2(-(hw - 0.022), ys - 0.018),
		Vector2(-(hw - 0.06), ys + 0.001),
		Vector2(-(hw - 0.15), lerpf(ys, yt, 0.6)),
		Vector2(-(hw * 0.45), yt + crown * 0.65),
		Vector2(0.0, yt + crown),
	]


static func _cr(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (p2 - p0) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (3.0 * p1 - p0 - 3.0 * p2 + p3) * t3)


static func _profile_eval(ctrl: Array, u: float) -> Vector2:
	var n := ctrl.size()
	var i := clampi(int(floor(u)), 0, n - 2)
	var t := clampf(u - float(i), 0.0, 1.0)
	return _cr(ctrl[maxi(i - 1, 0)], ctrl[i], ctrl[i + 1], ctrl[mini(i + 2, n - 1)], t)


## Point on the body surface. side = -1 (left) / +1 (right).
func _body_point(z: float, u: float, side: float) -> Vector3:
	var p := _profile_eval(_half_profile(z), u)
	var y := p.y
	var ay := _arch_y(z)
	if ay > 0.0 and y < ay:
		y = ay
	return Vector3(-side * p.x, y, z)


## [point offset along the surface normal, normal]
func _body_frame(z: float, u: float, side: float, off := 0.0) -> Array:
	var p := _body_point(z, u, side)
	var tz := _body_point(z + 0.01, u, side) - _body_point(z - 0.01, u, side)
	var tu := _body_point(z, u + 0.06, side) - _body_point(z, u - 0.06, side)
	var n := tz.cross(tu)
	if n.length_squared() < 1e-12:
		n = Vector3(side, 0.2, 0)
	n = n.normalized()
	if n.dot(p - Vector3(0, 0.55, z)) < 0.0:
		n = -n
	return [p + n * off, n]


## Point on the greenhouse. s: 0 = left beltline … 0.5 = roof centre … 1 = right beltline.
func _cab_point(z: float, s: float) -> Vector3:
	var hfac := clampf(_t("cabin", z), 0.0, 1.0)
	var ys := _t("shoulder", z) - 0.004
	var hw_b := _t("hw", z) - 0.062
	var roof: float = spec["roof"]
	var y_roof := ys + (roof - ys) * hfac
	var tw := lerpf(hw_b, float(spec["cabin_top_w"]), hfac)
	var side := -1.0 if s < 0.5 else 1.0
	var ss := s if s < 0.5 else 1.0 - s
	var x := 0.0
	var y := 0.0
	if ss < 0.3:
		var t := ss / 0.3
		x = lerpf(hw_b, tw, t) + sin(t * PI) * float(spec["tumble"]) * hfac
		y = lerpf(ys, y_roof - 0.035 * hfac, t)
	else:
		var t := (ss - 0.3) / 0.2
		var a := t * PI * 0.5
		x = tw * (1.0 - t)
		y = y_roof - 0.035 * hfac * (1.0 - sin(a)) + 0.012 * hfac * sin(a)
	return Vector3(side * x, y, z)


func _cab_frame(z: float, s: float, off := 0.0) -> Array:
	var p := _cab_point(z, s)
	var tz := _cab_point(z + 0.01, s) - _cab_point(z - 0.01, s)
	var ts := _cab_point(z, s + 0.004) - _cab_point(z, s - 0.004)
	var n := tz.cross(ts)
	if n.length_squared() < 1e-12:
		n = Vector3.UP
	n = n.normalized()
	if n.dot(p - Vector3(0, _t("shoulder", z) - 0.25, z)) < 0.0:
		n = -n
	return [p + n * off, n]


# ---------------------------------------------------------------------------
# Generic surface patches
# ---------------------------------------------------------------------------
## Builds a patch mesh from a Callable f(a: float, b: float) -> Vector3 with a, b in [0, 1].
func _patch_mesh(f: Callable, na: int, nb: int, inside: Vector3, mat: Material, shadows := true) -> MeshInstance3D:
	var rows: Array = []
	var centers: Array = []
	for i in na + 1:
		var row := PackedVector3Array()
		row.resize(nb + 1)
		for j in nb + 1:
			row[j] = f.call(float(i) / na, float(j) / nb)
		rows.append(row)
		centers.append(inside)
	var st := MeshKit.new_st()
	MeshKit.grid(st, rows, centers, false)
	var mi := MeshKit.mesh_instance(MeshKit.commit(st, mat), null, shadows)
	add_child(mi)
	return mi


func _cab_patch(z0: float, z1: float, s0: float, s1: float, off: float, mat: Material, na := 12, nb := 10) -> void:
	var inside := Vector3(0, _t("shoulder", (z0 + z1) * 0.5) - 0.2, (z0 + z1) * 0.5)
	_patch_mesh(func(a, b): return _cab_frame(lerpf(z0, z1, a), lerpf(s0, s1, b), off)[0], na, nb, inside, mat, mat != glass_mat)


func _surface_line(points: Array, radius: float, mat: Material) -> void:
	if points.size() < 2:
		return
	var st := MeshKit.new_st()
	var radii: Array = []
	radii.resize(points.size())
	radii.fill(radius)
	MeshKit.tube(st, points, radii, 4)
	add_child(MeshKit.mesh_instance(MeshKit.commit(st, mat), null, false))


## Place a node on the body surface, oriented with -Z along the surface normal.
func _place_on_body(node: Node3D, z: float, u: float, side: float, off: float) -> void:
	var fr := _body_frame(z, u, side, off)
	var n: Vector3 = fr[1]
	var up := Vector3.UP if absf(n.dot(Vector3.UP)) < 0.95 else Vector3.FORWARD
	node.transform = Transform3D(Basis.looking_at(-n, up), fr[0])
	add_child(node)


# ---------------------------------------------------------------------------
# Body shell
# ---------------------------------------------------------------------------
func _build_body() -> void:
	var rows: Array = []
	var centers: Array = []
	var steps := 150
	var ustep := 0.25
	var ucount := int(U_MAX / ustep)
	for s in steps + 1:
		var z := lerpf(_front, _rear, float(s) / steps)
		var ctrl := _half_profile(z)
		var ay := _arch_y(z)
		var ring := PackedVector3Array()
		for k in ucount + 1:
			var p := _profile_eval(ctrl, k * ustep)
			ring.append(Vector3(p.x, maxf(p.y, ay), z))
		for k in range(ucount - 1, 0, -1):
			var p := _profile_eval(ctrl, k * ustep)
			ring.append(Vector3(-p.x, maxf(p.y, ay), z))
		rows.append(ring)
		var yb := maxf(_t("bottom", z), ay)
		centers.append(Vector3(0, (yb + _t("shoulder", z)) * 0.5, z))
	var st := MeshKit.new_st()
	MeshKit.grid(st, rows, centers, true)
	MeshKit.cap(st, rows[0], centers[0] + Vector3(0, 0, -0.01), Vector3(0, 0, -1))
	MeshKit.cap(st, rows[rows.size() - 1], centers[centers.size() - 1] + Vector3(0, 0, 0.01), Vector3(0, 0, 1))
	var mi := MeshKit.mesh_instance(MeshKit.commit(st, paint_mat))
	mi.name = "Body"
	add_child(mi)
	# dark wheel wells
	var well := TexKit.std(Color(0.015, 0.015, 0.015), 0.95)
	var r: float = spec["wheel_r"]
	for axle in [spec["axle_f"], spec["axle_r"]]:
		var z := float(axle)
		var width := (_t("hw", z) - 0.03) * 2.0
		var w := MeshKit.cyl_node(r + float(spec["arch_gap"]) - 0.005, r + float(spec["arch_gap"]) - 0.005, width, well, Vector3(0, r, z), Vector3(0, 0, PI * 0.5), 24)
		w.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(w)
	# underbody
	add_child(MeshKit.box_node(Vector3(1.55, 0.04, float(spec["length"]) * 0.78), TexKit.std(Color(0.04, 0.04, 0.045), 0.9), Vector3(0, float(spec["base"]) + 0.02, 0)))


# ---------------------------------------------------------------------------
# Greenhouse: painted shell + glass + trims + headliner
# ---------------------------------------------------------------------------
func _build_cabin() -> void:
	var cab: Array = spec["cabin"]
	var z0: float = cab[0][0]
	var z1: float = cab[cab.size() - 1][0]
	var rows: Array = []
	var inner: Array = []
	var centers: Array = []
	var nz := 60
	var ns := 48
	for i in nz + 1:
		var z := lerpf(z0, z1, float(i) / nz)
		var row := PackedVector3Array()
		var irow := PackedVector3Array()
		for j in ns + 1:
			var s := float(j) / ns
			row.append(_cab_point(z, s))
			var fr := _cab_frame(z, s, -0.014)
			irow.append(fr[0])
		rows.append(row)
		inner.append(irow)
		centers.append(Vector3(0, _t("shoulder", z) - 0.25, z))
	var st := MeshKit.new_st()
	MeshKit.grid(st, rows, centers, false)
	var mi := MeshKit.mesh_instance(MeshKit.commit(st, paint_mat))
	mi.name = "Cabin"
	add_child(mi)
	var hst := MeshKit.new_st()
	MeshKit.grid(hst, inner, centers, false, Vector2.ONE, Color.WHITE, true)
	var headliner := MeshKit.mesh_instance(MeshKit.commit(hst, TexKit.std(Color(0.2, 0.2, 0.21), 0.95)), null, false)
	add_child(headliner)

	var ws_top: float = spec["ws_top"]
	var rw_top: float = spec["rw_top"]
	var side_end: float = spec["side_end"]
	var bp: float = spec["b_pillar"]
	# windscreen
	_cab_patch(z0 + 0.015, ws_top - 0.005, 0.305, 0.695, 0.0025, trim_mat)
	_cab_patch(z0 + 0.035, ws_top - 0.025, 0.318, 0.682, 0.0045, glass_mat)
	# rear window
	_cab_patch(rw_top + 0.01, z1 - 0.012, 0.31, 0.69, 0.0025, trim_mat)
	_cab_patch(rw_top + 0.03, z1 - 0.03, 0.325, 0.675, 0.0045, glass_mat)
	# side windows + B pillar
	for side in [0, 1]:
		var s0 := 0.02 if side == 0 else 0.715
		var s1 := 0.285 if side == 0 else 0.98
		_cab_patch(z0 + 0.05, side_end + 0.01, s0, s1, 0.0025, trim_mat, 16, 6)
		_cab_patch(z0 + 0.07, side_end - 0.012, s0 + 0.012, s1 - 0.012, 0.0045, glass_mat, 16, 6)
		_cab_patch(bp - 0.035, bp + 0.035, s0 - 0.01, s1 + 0.01, 0.0065, trim_mat, 2, 6)
	# wipers
	for k in 2:
		var pts: Array = []
		for j in 6:
			var s := lerpf(0.36 + k * 0.17, 0.49 + k * 0.17, float(j) / 5.0)
			pts.append(_cab_frame(z0 + 0.06, s, 0.012)[0])
		_surface_line(pts, 0.006, trim_mat)


# ---------------------------------------------------------------------------
# Panel gaps
# ---------------------------------------------------------------------------
func _build_panel_lines() -> void:
	var gap := TexKit.std(Color(0.01, 0.01, 0.012), 0.8)
	var cab: Array = spec["cabin"]
	var z_ws: float = cab[0][0]
	var z_rw: float = cab[cab.size() - 1][0]
	for side in [-1.0, 1.0]:
		# hood edges
		var hood: Array = []
		for k in 14:
			hood.append(_body_frame(lerpf(_front + 0.22, z_ws - 0.02, float(k) / 13.0), 8.8, side, 0.001)[0])
		_surface_line(hood, 0.0035, gap)
		# trunk edges
		var trunk: Array = []
		for k in 8:
			trunk.append(_body_frame(lerpf(z_rw + 0.04, _rear - 0.08, float(k) / 7.0), 8.8, side, 0.001)[0])
		_surface_line(trunk, 0.0035, gap)
		# door front / rear cut lines and front bumper line
		for zc in [z_ws + 0.06, float(spec["side_end"]) - 0.12, _front + 0.3]:
			var door: Array = []
			for k in 10:
				door.append(_body_frame(zc, lerpf(1.6, 8.4, float(k) / 9.0), side, 0.001)[0])
			_surface_line(door, 0.003, gap)
		# door bottom line above the rocker
		var sill: Array = []
		for k in 8:
			sill.append(_body_frame(lerpf(z_ws + 0.06, float(spec["side_end"]) - 0.12, float(k) / 7.0), 2.2, side, 0.001)[0])
		_surface_line(sill, 0.003, gap)
	# hood front edge and trunk rear edge across the car
	for zc in [_front + 0.22, _rear - 0.08]:
		var across: Array = []
		for k in 13:
			var u := lerpf(8.8, U_MAX, float(k) / 12.0)
			across.append(_body_frame(zc, u, -1.0, 0.001)[0])
		for k in range(11, -1, -1):
			var u := lerpf(8.8, U_MAX, float(k) / 12.0)
			across.append(_body_frame(zc, u, 1.0, 0.001)[0])
		_surface_line(across, 0.0035, gap)


# ---------------------------------------------------------------------------
# Front
# ---------------------------------------------------------------------------
func _build_front() -> void:
	var fz := _front
	var black := trim_mat
	var grille := StandardMaterial3D.new()
	grille.albedo_texture = TexKit.grille_texture()
	grille.uv1_scale = Vector3(6, 2, 1)
	grille.roughness = 0.7
	grille.metallic = 0.3
	var style: String = spec["grille"]
	var bottom_front := _t("bottom", fz + 0.03)
	match style:
		"r34":
			add_child(MeshKit.box_node(Vector3(0.94, 0.2, 0.08), grille, Vector3(0, 0.285, fz + 0.02)))
			add_child(MeshKit.box_node(Vector3(0.96, 0.028, 0.03), paint_mat, Vector3(0, 0.29, fz - 0.018)))
			add_child(MeshKit.box_node(Vector3(0.6, 0.055, 0.04), grille, Vector3(0, 0.5, fz + 0.012)))
			add_child(MeshKit.box_node(Vector3(0.1, 0.028, 0.012), TexKit.std(Color(0.8, 0.05, 0.05), 0.2, 0.6), Vector3(0, 0.505, fz - 0.01)))
			for side in [-1.0, 1.0]:
				var duct := MeshKit.box_node(Vector3(0.2, 0.11, 0.05), grille, Vector3(side * 0.61, 0.275, fz + 0.03))
				duct.rotation.y = side * -0.35
				add_child(duct)
				var sig := MeshKit.box_node(Vector3(0.15, 0.03, 0.02), TexKit.emissive(Color(1.0, 0.5, 0.02), 0.6), Vector3(side * 0.6, 0.355, fz + 0.02))
				sig.rotation.y = side * -0.35
				add_child(sig)
				var canard := MeshKit.box_node(Vector3(0.18, 0.012, 0.1), TexKit.carbon(), Vector3(side * 0.72, 0.21, fz + 0.06))
				canard.rotation = Vector3(0, side * -0.4, side * 0.15)
				add_child(canard)
			# front plate (offset like on the real car)
			add_child(MeshKit.box_node(Vector3(0.33, 0.1, 0.01), TexKit.std(Color(0.92, 0.92, 0.88), 0.5), Vector3(-0.22, 0.29, fz - 0.036)))
		"s15":
			add_child(MeshKit.box_node(Vector3(0.7, 0.16, 0.06), grille, Vector3(0, 0.3, fz + 0.02)))
			for side in [-1.0, 1.0]:
				add_child(MeshKit.box_node(Vector3(0.22, 0.08, 0.05), grille, Vector3(side * 0.56, 0.26, fz + 0.04)))
		"a80":
			var mouth := MeshKit.box_node(Vector3(0.9, 0.16, 0.06), grille, Vector3(0, 0.3, fz + 0.035))
			add_child(mouth)
			for side in [-1.0, 1.0]:
				add_child(MeshKit.box_node(Vector3(0.14, 0.05, 0.04), TexKit.emissive(Color(1.0, 0.5, 0.02), 0.6), Vector3(side * 0.62, 0.28, fz + 0.05)))
		_:
			add_child(MeshKit.box_node(Vector3(1.2, 0.07, 0.05), grille, Vector3(0, 0.47, fz + 0.02)))
			add_child(MeshKit.box_node(Vector3(1.5, 0.08, 0.06), TexKit.std(Color(0.1, 0.1, 0.11), 0.6), Vector3(0, 0.3, fz + 0.01)))
	# lip splitter
	add_child(MeshKit.box_node(Vector3(float(_t("hw", fz + 0.1)) * 1.9, 0.02, 0.16), TexKit.carbon(), Vector3(0, bottom_front - 0.005, fz + 0.1)))
	_build_headlights()


func _build_headlights() -> void:
	var style: String = spec["head"]
	var fz := _front
	var u0 := 5.6
	var u1 := 10.1
	var zf := fz + 0.012
	var zb_out := fz + 0.27
	var zb_in := fz + 0.2
	match style:
		"swept":
			u0 = 6.0
			u1 = 10.2
			zb_out = fz + 0.4
			zb_in = fz + 0.16
		"a80":
			u0 = 6.3
			u1 = 9.9
			zf = fz + 0.06
			zb_out = fz + 0.28
			zb_in = fz + 0.24
		"popup":
			u0 = 8.9
			u1 = 10.3
			zf = fz + 0.08
			zb_out = fz + 0.4
			zb_in = fz + 0.4
	for side in [-1.0, 1.0]:
		var f_house := func(a, b):
			var u := lerpf(u0 - 0.15, u1 + 0.1, a)
			var zb := lerpf(zb_out, zb_in, a) + 0.012
			return _body_frame(lerpf(zf - 0.004, zb, b), u, side, 0.0025)[0]
		if style == "popup":
			# closed pop-up lids: body coloured panels with a thin gap
			_patch_mesh(f_house, 6, 6, Vector3(0, 0.5, -1.5), trim_mat)
			var f_lid := func(a, b):
				var u := lerpf(u0, u1, a)
				return _body_frame(lerpf(zf + 0.01, zb_out - 0.01, b), u, side, 0.004)[0]
			_patch_mesh(f_lid, 6, 6, Vector3(0, 0.5, -1.5), paint_mat)
			# small bumper lamps
			var lamp := MeshKit.box_node(Vector3(0.26, 0.07, 0.03), head_mat, Vector3(side * 0.45, 0.42, fz + 0.01))
			add_child(lamp)
		else:
			_patch_mesh(f_house, 8, 8, Vector3(0, 0.5, -1.5), trim_mat)
			var f_lens := func(a, b):
				var u := lerpf(u0, u1, a)
				var zb := lerpf(zb_out, zb_in, a)
				return _body_frame(lerpf(zf, zb, b), u, side, 0.006)[0]
			_patch_mesh(f_lens, 8, 8, Vector3(0, 0.5, -1.5), head_mat, false)
			# projector lamps sitting in the lens
			var zc := (zf + lerpf(zb_out, zb_in, 0.5)) * 0.5
			var count := 2 if style != "a80" else 3
			for k in count:
				var u := lerpf(u0 + 0.9, u1 - 0.9, float(k) / maxf(count - 1, 1))
				var ring := MeshKit.cyl_node(0.045, 0.045, 0.012, TexKit.chrome(), Vector3.ZERO, Vector3(PI * 0.5, 0, 0), 20)
				var holder := Node3D.new()
				holder.add_child(ring)
				var lens := MeshKit.cyl_node(0.034, 0.034, 0.016, head_mat, Vector3.ZERO, Vector3(PI * 0.5, 0, 0), 20)
				holder.add_child(lens)
				_place_on_body(holder, zc, u, side, 0.008)
		# spot light from the lamp centre
		var centre: Vector3 = _body_frame((zf + zb_in) * 0.5, (u0 + u1) * 0.5, side, 0.05)[0]
		var spot := SpotLight3D.new()
		spot.position = Vector3(centre.x, centre.y, fz - 0.05) if style != "popup" else Vector3(side * 0.45, 0.42, fz - 0.05)
		spot.rotation = Vector3(-0.06, 0, 0)
		spot.light_color = Color(0.95, 0.96, 1.0)
		spot.light_energy = 7.0
		spot.spot_range = 70.0
		spot.spot_angle = 26.0
		spot.spot_attenuation = 0.6
		spot.shadow_enabled = shadows_for_lights and side > 0.0
		spot.visible = false
		add_child(spot)
		head_spots.append(spot)


# ---------------------------------------------------------------------------
# Rear
# ---------------------------------------------------------------------------
func _build_rear() -> void:
	var rz := _rear
	var ty := _t("shoulder", rz - 0.02) - 0.1
	var style: String = spec["tail"]
	match style:
		"quad_round", "round_pairs":
			var lamps := [[0.37, 0.078], [0.63, 0.09]] if style == "quad_round" else [[0.44, 0.095], [0.69, 0.095]]
			for side in [-1.0, 1.0]:
				for li in lamps.size():
					var x: float = lamps[li][0]
					var rad: float = lamps[li][1]
					var pos := Vector3(side * x, ty, rz + 0.004)
					add_child(MeshKit.cyl_node(rad + 0.016, rad + 0.016, 0.02, TexKit.chrome(), pos + Vector3(0, 0, -0.004), Vector3(PI * 0.5, 0, 0), 28))
					add_child(MeshKit.cyl_node(rad, rad, 0.024, tail_mat, pos, Vector3(PI * 0.5, 0, 0), 28))
					add_child(MeshKit.cyl_node(rad * 0.62, rad * 0.62, 0.028, TexKit.std(Color(0.3, 0.02, 0.02), 0.15, 0.4), pos, Vector3(PI * 0.5, 0, 0), 24))
					if li == 0:
						add_child(MeshKit.cyl_node(rad * 0.38, rad * 0.38, 0.032, reverse_mat, pos, Vector3(PI * 0.5, 0, 0), 20))
					else:
						add_child(MeshKit.cyl_node(rad * 0.38, rad * 0.38, 0.032, tail_mat, pos, Vector3(PI * 0.5, 0, 0), 20))
		"wide_bar":
			add_child(MeshKit.box_node(Vector3(float(_t("hw", rz - 0.02)) * 1.9, 0.15, 0.03), trim_mat, Vector3(0, ty, rz + 0.004)))
			for side in [-1.0, 1.0]:
				add_child(MeshKit.box_node(Vector3(0.52, 0.12, 0.02), tail_mat, Vector3(side * 0.5, ty, rz + 0.016)))
				add_child(MeshKit.box_node(Vector3(0.12, 0.05, 0.02), reverse_mat, Vector3(side * 0.16, ty, rz + 0.016)))
		_:
			for side in [-1.0, 1.0]:
				var f_lamp := func(a, b):
					return _body_frame(lerpf(rz - 0.16, rz - 0.004, b), lerpf(5.6, 8.6, a), side, 0.004)[0]
				_patch_mesh(f_lamp, 8, 6, Vector3(0, 0.6, 1.5), tail_mat, false)
				add_child(MeshKit.box_node(Vector3(0.14, 0.05, 0.02), reverse_mat, Vector3(side * 0.3, ty - 0.02, rz + 0.006)))
	# bumper line, plate, reflectors
	var hw_r := _t("hw", rz - 0.02)
	add_child(MeshKit.box_node(Vector3(hw_r * 1.7, 0.006, 0.006), TexKit.std(Color(0.01, 0.01, 0.01), 0.8), Vector3(0, 0.62, rz + 0.002)))
	add_child(MeshKit.box_node(Vector3(0.56, 0.17, 0.02), trim_mat, Vector3(0, 0.5, rz + 0.004)))
	add_child(MeshKit.box_node(Vector3(0.52, 0.125, 0.01), TexKit.std(Color(0.92, 0.92, 0.88), 0.5), Vector3(0, 0.5, rz + 0.016)))
	for side in [-1.0, 1.0]:
		add_child(MeshKit.box_node(Vector3(0.12, 0.03, 0.01), TexKit.emissive(Color(0.8, 0.02, 0.02), 0.2), Vector3(side * (hw_r - 0.18), 0.42, rz + 0.004)))
	# diffuser with fins
	var carbon := TexKit.carbon()
	var tb := _t("bottom", rz - 0.1)
	add_child(MeshKit.box_node(Vector3(1.3, 0.035, 0.34), carbon, Vector3(0, tb - 0.01, rz - 0.13)))
	for k in 5:
		add_child(MeshKit.box_node(Vector3(0.012, 0.09, 0.3), carbon, Vector3(-0.5 + k * 0.25, tb - 0.05, rz - 0.12)))
	# exhaust tips (oval)
	for x in spec["exhaust"]:
		var pos := Vector3(float(x), tb - 0.02, rz - 0.04)
		var tip := MeshKit.cyl_node(0.068, 0.072, 0.26, TexKit.chrome(), pos, Vector3(PI * 0.5, 0, 0), 24)
		tip.scale = Vector3(1.0, 1.0, 0.72)
		add_child(tip)
		var inner := MeshKit.cyl_node(0.055, 0.055, 0.262, TexKit.std(Color(0.02, 0.02, 0.02), 0.9), pos, Vector3(PI * 0.5, 0, 0), 20)
		inner.scale = Vector3(1.0, 1.0, 0.7)
		add_child(inner)
		exhaust_points.append(pos + Vector3(0, 0, 0.14))
	# badge on the trunk
	add_child(MeshKit.box_node(Vector3(0.16, 0.035, 0.008), TexKit.chrome(), Vector3(0.45, ty + 0.1, rz - 0.002)))


# ---------------------------------------------------------------------------
# Sides: mirrors, vents, skirts, handles, fuel door, side markers
# ---------------------------------------------------------------------------
func _build_side_details() -> void:
	var cab: Array = spec["cabin"]
	var z_ws: float = cab[0][0]
	var mz := z_ws + 0.22
	for side in [-1.0, 1.0]:
		# mirror: stalk + aerodynamic housing + glass
		var base: Vector3 = _cab_point(mz, 0.03 if side < 0.0 else 0.97)
		var housing := MeshKit.sphere_node(0.5, paint_mat, base + Vector3(side * 0.13, 0.065, 0.03), Vector3(0.24, 0.13, 0.17))
		add_child(housing)
		add_child(MeshKit.box_node(Vector3(0.1, 0.03, 0.05), trim_mat, base + Vector3(side * 0.05, 0.03, 0.02)))
		var mglass := MeshKit.box_node(Vector3(0.2, 0.1, 0.008), TexKit.chrome(), base + Vector3(side * 0.13, 0.065, 0.115))
		add_child(mglass)
		# side skirt (black lower strip)
		var sk: Array = []
		var za: float = float(spec["axle_f"]) + float(spec["wheel_r"]) + 0.12
		var zb: float = float(spec["axle_r"]) - float(spec["wheel_r"]) - 0.12
		for k in 10:
			sk.append(_body_frame(lerpf(za, zb, float(k) / 9.0), 1.6, side, 0.004)[0])
		_surface_line(sk, 0.02, trim_mat)
		# door handle
		var handle := MeshKit.box_node(Vector3(0.14, 0.022, 0.012), trim_mat)
		_place_on_body(handle, float(spec["b_pillar"]) - 0.12, 6.4, side, 0.003)
		# side marker on the front fender
		var marker := MeshKit.box_node(Vector3(0.06, 0.025, 0.008), TexKit.emissive(Color(1.0, 0.5, 0.02), 0.5))
		_place_on_body(marker, float(spec["axle_f"]) + 0.6, 5.3, side, 0.002)
		# fender vents behind the front wheel (R34 GT-R)
		if spec["vent"]:
			for k in 3:
				var slat := MeshKit.box_node(Vector3(0.15, 0.012, 0.012), trim_mat)
				_place_on_body(slat, float(spec["axle_f"]) + 0.5 + k * 0.035, 4.2 + k * 0.08, side, 0.002)
	# fuel door on the right rear quarter
	var ring: Array = []
	var fz := float(spec["axle_r"]) - 0.55
	for k in 17:
		var a := TAU * float(k) / 16.0
		ring.append(_body_frame(fz + cos(a) * 0.075, 6.6 + sin(a) * 0.55, 1.0, 0.001)[0])
	_surface_line(ring, 0.0028, TexKit.std(Color(0.01, 0.01, 0.01), 0.8))


# ---------------------------------------------------------------------------
# Wing
# ---------------------------------------------------------------------------
func _airfoil_mesh(span: float, chord: float, thick: float, aoa: float, center: Vector3, mat: Material) -> void:
	# symmetric-ish airfoil ring in the (z, y) plane, lofted along x
	var prof: Array = []
	var n := 14
	for k in n:
		var t := float(k) / (n - 1)
		var x := 1.0 - cos(t * PI * 0.5)
		var yt := 5.0 * thick * (0.2969 * sqrt(x) - 0.126 * x - 0.3516 * x * x + 0.2843 * x * x * x - 0.1015 * x * x * x * x)
		prof.append(Vector2(x, yt))
	var ring2d: Array = []
	for k in range(n - 1, -1, -1):
		ring2d.append(Vector2(prof[k].x, prof[k].y + 0.02))
	for k in range(1, n - 1):
		ring2d.append(Vector2(prof[k].x, -prof[k].y * 0.6 + 0.02))
	var rows: Array = []
	var centers: Array = []
	var segs := 16
	for i in segs + 1:
		var fx := lerpf(-span * 0.5, span * 0.5, float(i) / segs)
		var ring := PackedVector3Array()
		for p in ring2d:
			var v: Vector2 = p
			# chord runs from leading edge (-z) to trailing edge (+z)
			var zz := (v.x - 0.5) * chord
			var yy := v.y * chord
			var rz := zz * cos(aoa) - yy * sin(aoa)
			var ry := zz * sin(aoa) + yy * cos(aoa)
			ring.append(center + Vector3(fx, ry, rz))
		rows.append(ring)
		centers.append(center + Vector3(fx, 0.02 * chord, 0))
	var st := MeshKit.new_st()
	MeshKit.grid(st, rows, centers, true)
	MeshKit.cap(st, rows[0], centers[0] - Vector3(0.002, 0, 0), Vector3(-1, 0, 0))
	MeshKit.cap(st, rows[segs], centers[segs] + Vector3(0.002, 0, 0), Vector3(1, 0, 0))
	add_child(MeshKit.mesh_instance(MeshKit.commit(st, mat)))


func _build_wing() -> void:
	var wz := _rear - 0.24
	var deck := _t("shoulder", wz)
	match str(spec["wing"]):
		"r34":
			for side in [-1.0, 1.0]:
				var post := MeshKit.box_node(Vector3(0.05, 0.2, 0.17), paint_mat, Vector3(side * 0.6, deck + 0.09, wz + 0.02))
				post.rotation.x = -0.18
				add_child(post)
			_airfoil_mesh(1.52, 0.27, 0.13, 0.1, Vector3(0, deck + 0.2, wz + 0.04), paint_mat)
			var flap := MeshKit.box_node(Vector3(1.48, 0.03, 0.012), TexKit.carbon(), Vector3(0, deck + 0.235, wz + 0.175))
			add_child(flap)
			add_child(MeshKit.box_node(Vector3(0.4, 0.012, 0.02), tail_mat, Vector3(0, deck + 0.19, wz + 0.17)))
		"hoop":
			var pts: Array = []
			for k in 17:
				var a := PI * float(k) / 16.0
				pts.append(Vector3(-cos(a) * 0.72, deck + sin(a) * 0.24, wz))
			var st := MeshKit.new_st()
			var radii: Array = []
			radii.resize(pts.size())
			radii.fill(0.03)
			MeshKit.tube(st, pts, radii, 10)
			add_child(MeshKit.mesh_instance(MeshKit.commit(st, paint_mat)))
			_airfoil_mesh(1.3, 0.22, 0.12, 0.08, Vector3(0, deck + 0.255, wz), paint_mat)
		"low":
			for side in [-1.0, 1.0]:
				add_child(MeshKit.box_node(Vector3(0.04, 0.08, 0.13), paint_mat, Vector3(side * 0.55, deck + 0.04, wz + 0.05)))
			_airfoil_mesh(1.4, 0.22, 0.1, 0.1, Vector3(0, deck + 0.09, wz + 0.06), paint_mat)
		_:
			add_child(MeshKit.box_node(Vector3(1.3, 0.035, 0.12), trim_mat, Vector3(0, deck + 0.02, _rear - 0.1)))


# ---------------------------------------------------------------------------
# Interior (right-hand drive)
# ---------------------------------------------------------------------------
func _build_interior() -> void:
	var cab: Array = spec["cabin"]
	var z0: float = cab[0][0]
	var z1: float = cab[cab.size() - 1][0]
	var bp: float = spec["b_pillar"]
	var belt := _t("shoulder", bp)
	var hw := _t("hw", bp) - 0.12
	var st := MeshKit.new_st()
	var dark := Color(0.08, 0.08, 0.09)
	var fabric := Color(0.16, 0.16, 0.18)
	var floor_y := float(spec["base"]) + 0.12
	var ib := Basis.IDENTITY
	MeshKit.box(st, Transform3D(ib, Vector3(0, floor_y, (z0 + z1) * 0.5)), Vector3(hw * 2.0, 0.04, z1 - z0), dark)
	for side in [-1.0, 1.0]:
		MeshKit.box(st, Transform3D(ib, Vector3(side * hw, (floor_y + belt) * 0.5, (z0 + z1) * 0.5 + 0.05)), Vector3(0.05, belt - floor_y, z1 - z0 - 0.2), dark)
	# dashboard + binnacle on the right (RHD)
	var dash_z := z0 + 0.3
	var dash_y := _t("shoulder", dash_z) - 0.06
	MeshKit.box(st, Transform3D(ib, Vector3(0, dash_y, dash_z)), Vector3(hw * 2.0, 0.2, 0.45), dark)
	MeshKit.box(st, Transform3D(ib, Vector3(0.37, dash_y + 0.1, dash_z + 0.08)), Vector3(0.36, 0.08, 0.2), Color(0.04, 0.04, 0.05))
	MeshKit.box(st, Transform3D(ib, Vector3(0, dash_y - 0.2, dash_z + 0.35)), Vector3(0.22, 0.24, 0.75), dark)
	# seats
	var seat_z := bp - 0.02
	for x in [-0.37, 0.37]:
		MeshKit.box(st, Transform3D(ib, Vector3(x, floor_y + 0.14, seat_z)), Vector3(0.5, 0.14, 0.5), fabric)
		var back := Basis(Vector3.RIGHT, 0.22)
		MeshKit.box(st, Transform3D(back, Vector3(x, floor_y + 0.5, seat_z + 0.3)), Vector3(0.5, 0.62, 0.13), fabric)
		MeshKit.box(st, Transform3D(back, Vector3(x, floor_y + 0.9, seat_z + 0.39)), Vector3(0.28, 0.2, 0.12), fabric)
		for bx in [-0.24, 0.24]:
			MeshKit.box(st, Transform3D(back, Vector3(x + bx, floor_y + 0.5, seat_z + 0.27)), Vector3(0.06, 0.5, 0.17), Color(0.1, 0.1, 0.11))
	# rear bench and parcel shelf
	var rear_z := minf(float(spec["side_end"]) - 0.05, z1 - 0.45)
	MeshKit.box(st, Transform3D(ib, Vector3(0, floor_y + 0.16, rear_z)), Vector3(hw * 1.7, 0.14, 0.42), fabric)
	MeshKit.box(st, Transform3D(Basis(Vector3.RIGHT, 0.3), Vector3(0, floor_y + 0.45, rear_z + 0.27)), Vector3(hw * 1.7, 0.5, 0.13), fabric)
	MeshKit.box(st, Transform3D(ib, Vector3(0, _t("shoulder", z1 - 0.2) - 0.03, z1 - 0.2)), Vector3(hw * 1.8, 0.03, 0.36), dark)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.85
	add_child(MeshKit.mesh_instance(MeshKit.commit(st, mat), null, false))
	# steering wheel (right side)
	var ring: Array = []
	for k in 25:
		var a := TAU * float(k) / 24.0
		ring.append(Vector3(cos(a) * 0.18, sin(a) * 0.18, 0))
	var wst := MeshKit.new_st()
	var radii: Array = []
	radii.resize(ring.size())
	radii.fill(0.022)
	MeshKit.tube(wst, ring, radii, 6, Vector2.ONE, Color.WHITE, false)
	var wheel := MeshKit.mesh_instance(MeshKit.commit(wst, TexKit.std(Color(0.05, 0.05, 0.05), 0.6)), null, false)
	wheel.position = Vector3(0.37, dash_y + 0.05, dash_z + 0.35)
	wheel.rotation = Vector3(-0.45, 0, 0)
	add_child(wheel)
	var hub := MeshKit.cyl_node(0.06, 0.06, 0.04, TexKit.std(Color(0.05, 0.05, 0.05), 0.6), Vector3.ZERO, Vector3(PI * 0.5, 0, 0), 12)
	wheel.add_child(hub)
	# rear-view mirror
	var ws_top: float = spec["ws_top"]
	add_child(MeshKit.box_node(Vector3(0.22, 0.06, 0.03), trim_mat, Vector3(0, float(spec["roof"]) - 0.12, ws_top + 0.05)))


# ---------------------------------------------------------------------------
# Wheels (lathe-turned tyre + rim, shared per body type)
# ---------------------------------------------------------------------------
## Rim tuning: [name, spokes, twin spokes]; 0 = the car's own wheels.
const RIM_STYLES := [["Original", 0, false], ["5 Speichen", 5, false], ["Doppelspeichen", 5, true], ["10 Speichen", 10, false],
	["Y-Speichen", 6, true], ["8 Speichen", 8, false], ["Turbofan", 20, false],
	["JDM Mesh", -1, false], ["JDM Sechsspeichen", -2, false], ["JDM Gold", -3, false], ["JDM Tiefbett", -4, false]]
## The modelled wheels of the JDM rim pack (tools/convert_rims.py): style spokes -n -> jdm_<n>.glb
const RIM_GLB := "res://assets/cars/rims/jdm_%d.glb"
static var _rim_scenes := {}
## [name, colour, roughness]
const RIM_COLORS := [["Silber", Color(0.75, 0.76, 0.78), 0.28], ["Schwarz", Color(0.04, 0.04, 0.045), 0.35],
	["Gunmetal", Color(0.22, 0.23, 0.25), 0.3], ["Gold", Color(0.78, 0.57, 0.2), 0.25], ["Bronze", Color(0.45, 0.28, 0.14), 0.3],
	["Weiß", Color(0.9, 0.9, 0.9), 0.35], ["Chrom", Color(0.95, 0.95, 0.97), 0.04]]
var wheel_r := 0.33
var wheel_w := 0.24
var model_root: Node3D         # the imported body (the wheels are separate): squashed by the "jelly" cars


## Puts the chosen rims on all four wheels (style 0: the car's own again).
func apply_rims(cfg: Dictionary) -> void:
	var style := clampi(int(cfg.get("style", 0)), 0, RIM_STYLES.size() - 1)
	var ci := clampi(int(cfg.get("color", 0)), 0, RIM_COLORS.size() - 1)
	var mesh: ArrayMesh = null
	var model: PackedScene = null
	var model_size := Vector2.ONE       # its tyre radius, width
	if style > 0:
		var st: Array = RIM_STYLES[style]
		var cl: Array = RIM_COLORS[ci]
		if int(st[1]) < 0:
			var n := -int(st[1])
			if not _rim_scenes.has(n):
				var path := RIM_GLB % n
				var info = JSON.parse_string(FileAccess.get_file_as_string(path.get_basename() + ".json"))
				_rim_scenes[n] = [load(path) if ResourceLoader.exists(path) else null,
					Vector2(float(info["radius"]), float(info["width"])) if info is Dictionary else Vector2(0.29, 0.5)]
			model = _rim_scenes[n][0]
			model_size = _rim_scenes[n][1]
		else:
			mesh = _make_wheel(wheel_r, wheel_w, int(st[1]), bool(st[2]), cl[1], float(cl[2]), "%d_%d" % [style, ci])
	for i in wheel_nodes.size():
		var spin: Node3D = wheel_nodes[i][1]
		var old := spin.get_node_or_null("CustomRim")
		if old:
			spin.remove_child(old)
			old.free()
		for c in spin.get_children():
			(c as Node3D).visible = mesh == null and model == null
		if model:
			var w := model.instantiate() as Node3D
			w.name = "CustomRim"
			# the pack's wheel scaled to this car's tyre size (its face looks along +X)
			var k := wheel_r / model_size.x
			w.scale = Vector3(wheel_w / model_size.y, k, k)
			if i % 2 == 0:
				w.rotation.y = PI
			spin.add_child(w)
		elif mesh:
			var mi := MeshKit.mesh_instance(mesh)
			mi.name = "CustomRim"
			if i % 2 == 0:
				mi.rotation.y = PI
			spin.add_child(mi)


func _wheel_mesh() -> ArrayMesh:
	if _wheel_cache.has(body_id):
		return _wheel_cache[body_id]
	var mesh := _make_wheel(spec["wheel_r"], spec["wheel_w"], int(spec["spokes"]), bool(spec["twin"]), spec["rim"], 0.28, body_id)
	_wheel_cache[body_id] = mesh
	return mesh


func _make_wheel(R: float, w: float, spokes: int, twin: bool, rim_col: Color, rim_rough: float, key: String) -> ArrayMesh:
	if _wheel_cache.has("rim_%s_%.3f_%.3f" % [key, R, w]):
		return _wheel_cache["rim_%s_%.3f_%.3f" % [key, R, w]]
	var hw := w * 0.5
	var rim_r := R * 0.69
	# tyre
	var tyre := [
		Vector2(-hw + 0.012, rim_r + 0.004), Vector2(-hw, rim_r + 0.03), Vector2(-hw - 0.004, R - 0.05),
		Vector2(-hw + 0.006, R - 0.014), Vector2(-hw + 0.03, R),
		Vector2(-hw * 0.36, R), Vector2(-hw * 0.34, R - 0.006), Vector2(-hw * 0.26, R - 0.006), Vector2(-hw * 0.24, R),
		Vector2(hw * 0.24, R), Vector2(hw * 0.26, R - 0.006), Vector2(hw * 0.34, R - 0.006), Vector2(hw * 0.36, R),
		Vector2(hw - 0.03, R), Vector2(hw - 0.006, R - 0.014), Vector2(hw + 0.004, R - 0.05),
		Vector2(hw, rim_r + 0.03), Vector2(hw - 0.012, rim_r + 0.004),
	]
	var st := MeshKit.new_st()
	MeshKit.lathe(st, tyre, 48)
	var mesh := MeshKit.commit(st, TexKit.std(Color(0.035, 0.035, 0.038), 0.82))
	# rim: lip + barrel (normals face the viewer / the axle)
	var face_x := hw - 0.02
	var rim := [
		Vector2(hw - 0.024, rim_r + 0.012), Vector2(hw - 0.004, rim_r + 0.006), Vector2(hw - 0.006, rim_r - 0.01),
		Vector2(hw - 0.03, rim_r - 0.016), Vector2(-hw + 0.03, rim_r - 0.016),
	]
	var rst := MeshKit.new_st()
	MeshKit.lathe(rst, rim, 48)
	# hub / centre cap
	var hub := [Vector2(face_x - 0.045, 0.085), Vector2(face_x - 0.028, 0.08), Vector2(face_x - 0.018, 0.05), Vector2(face_x - 0.016, 0.0)]
	MeshKit.lathe(rst, hub, 24)
	# spokes
	for k in spokes:
		var a := TAU * float(k) / spokes
		if twin:
			_spoke(rst, a - 0.06, a - 0.13, rim_r, face_x)
			_spoke(rst, a + 0.06, a + 0.13, rim_r, face_x)
		else:
			_spoke(rst, a, a, rim_r, face_x, 0.045 if spokes <= 6 else 0.03)
	# lug nuts
	for k in 5:
		var a := TAU * float(k) / 5.0 + 0.3
		var p := Vector3(face_x - 0.02, cos(a) * 0.058, sin(a) * 0.058)
		MeshKit.box(rst, Transform3D(Basis.IDENTITY, p), Vector3(0.018, 0.016, 0.016), Color.WHITE)
	var rim_mat := TexKit.std(rim_col, rim_rough, 0.9)
	MeshKit.commit(rst, rim_mat, mesh)
	# brake disc
	var dst := MeshKit.new_st()
	MeshKit.lathe(dst, [Vector2(hw - 0.13, R * 0.52), Vector2(hw - 0.1, R * 0.52), Vector2(hw - 0.1, R * 0.22)], 32)
	MeshKit.commit(dst, TexKit.std(Color(0.35, 0.35, 0.37), 0.4, 0.9), mesh)
	_wheel_cache["rim_%s_%.3f_%.3f" % [key, R, w]] = mesh
	return mesh


## One tapered spoke from the hub to the rim, slightly concave.
func _spoke(st: SurfaceTool, a_hub: float, a_rim: float, rim_r: float, face_x: float, width := 0.026) -> void:
	var r0 := 0.075
	var r1 := rim_r - 0.012
	var d0 := Vector3(0, cos(a_hub), sin(a_hub))
	var d1 := Vector3(0, cos(a_rim), sin(a_rim))
	var t0 := Vector3(0, -sin(a_hub), cos(a_hub))
	var t1 := Vector3(0, -sin(a_rim), cos(a_rim))
	var x0 := face_x - 0.03   # hub end deeper (concave face)
	var x1 := face_x - 0.004
	var th := 0.03
	var w0 := width * 0.6
	var w1 := width * 0.5
	var p := [
		Vector3(x0, 0, 0) + d0 * r0 - t0 * w0, Vector3(x0, 0, 0) + d0 * r0 + t0 * w0,
		Vector3(x1, 0, 0) + d1 * r1 + t1 * w1, Vector3(x1, 0, 0) + d1 * r1 - t1 * w1,
	]
	var back := Vector3(-th, 0, 0)
	var col := Color.WHITE
	var nf := Vector3(1, 0, 0)
	# front face, back face, sides
	MeshKit.quad(st, p[0], p[1], p[2], p[3], nf, Vector2.ZERO, Vector2(1, 0), Vector2(1, 1), Vector2(0, 1), col)
	MeshKit.quad(st, p[0] + back, p[1] + back, p[2] + back, p[3] + back, -nf, Vector2.ZERO, Vector2(1, 0), Vector2(1, 1), Vector2(0, 1), col)
	var side_a := -((t0 + t1) * 0.5).normalized()
	MeshKit.quad(st, p[0], p[3], p[3] + back, p[0] + back, side_a, Vector2.ZERO, Vector2(1, 0), Vector2(1, 1), Vector2(0, 1), col)
	MeshKit.quad(st, p[1], p[2], p[2] + back, p[1] + back, -side_a, Vector2.ZERO, Vector2(1, 0), Vector2(1, 1), Vector2(0, 1), col)


func _build_wheels() -> void:
	var r: float = spec["wheel_r"]
	wheel_r = r
	wheel_w = float(spec["wheel_w"])
	var tr: float = spec["track"]
	var mesh := _wheel_mesh()
	var positions := [
		Vector3(-tr, r, spec["axle_f"]), Vector3(tr, r, spec["axle_f"]),
		Vector3(-tr, r, spec["axle_r"]), Vector3(tr, r, spec["axle_r"]),
	]
	var caliper_mat := TexKit.std(spec["caliper"], 0.35, 0.3)
	var w: float = spec["wheel_w"]
	for i in 4:
		var side := -1.0 if i % 2 == 0 else 1.0
		var pivot := Node3D.new()
		pivot.name = ["WheelFL", "WheelFR", "WheelRL", "WheelRR"][i]
		pivot.position = positions[i]
		add_child(pivot)
		var spin := Node3D.new()
		pivot.add_child(spin)
		var mi := MeshKit.mesh_instance(mesh)
		if side < 0.0:
			mi.rotation.y = PI
		spin.add_child(mi)
		var cal := MeshKit.box_node(Vector3(0.05, 0.17, 0.1), caliper_mat, Vector3(side * (w * 0.5 - 0.115), r * 0.38, 0.1 if i < 2 else -0.1))
		pivot.add_child(cal)
		wheel_nodes.append([pivot, spin])


func _build_lights() -> void:
	brake_light = OmniLight3D.new()
	brake_light.light_color = Color(1.0, 0.08, 0.04)
	brake_light.omni_range = 4.5
	brake_light.light_energy = 0.3
	brake_light.shadow_enabled = false
	brake_light.position = Vector3(0, 0.8, _rear + 0.4)
	brake_light.visible = false
	add_child(brake_light)


# ---------------------------------------------------------------------------
# Underbody (models without one)
# ---------------------------------------------------------------------------
## What a car looks like from below: the floor pan (narrow between the wheels, full width between
## the axles), black wheel arch liners round every wheel, the engine's sump, the transmission
## tunnel with the prop shaft, the fuel tank, and the exhaust from the engine back to the tip:
## down-pipe, catalytic converter, centre silencer, rear box.
func _underbody(m: Dictionary) -> void:
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.045, 0.045, 0.05)
	dark.roughness = 0.85
	dark.cull_mode = BaseMaterial3D.CULL_DISABLED
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.42, 0.4, 0.38)
	metal.metallic = 0.8
	metal.roughness = 0.38
	var rusty := StandardMaterial3D.new()
	rusty.albedo_color = Color(0.3, 0.22, 0.17)
	rusty.metallic = 0.5
	rusty.roughness = 0.6
	var wr := float(m["wheel_r"])
	var ww := float(m["wheel_w"])
	var tr := float(m["track"])
	var af := float(m["axle_f"])
	var ar := float(m["axle_r"])
	var hw := float(m["half_width"]) - 0.16    # well inside the sills (it must not show from the side)
	var y := float(m["base"]) + 0.03
	var st := MeshKit.new_st()
	var inner := tr - ww * 0.5 - 0.07          # inboard edge of the wheel arches
	var gap := wr + 0.12
	# floor pan: between the axles full width, at the ends between the wheels
	MeshKit.box(st, Transform3D(Basis.IDENTITY, Vector3(0, y, (af + gap + ar - gap) * 0.5)), Vector3(hw * 2.0, 0.03, (ar - gap) - (af + gap)))
	MeshKit.box(st, Transform3D(Basis.IDENTITY, Vector3(0, y + 0.02, af)), Vector3(inner * 2.0, 0.03, gap * 2.0))
	MeshKit.box(st, Transform3D(Basis.IDENTITY, Vector3(0, y + 0.02, ar)), Vector3(inner * 2.0, 0.03, gap * 2.0))
	# (nothing ahead of the front wheels or behind the rear ones: under the overhangs a flat plate
	# stuck out of the bumpers)
	# the transmission tunnel and the sump, the fuel tank in front of the rear axle
	MeshKit.box(st, Transform3D(Basis.IDENTITY, Vector3(0, y + 0.06, (af + ar) * 0.5)), Vector3(0.3, 0.1, ar - af - 0.6))
	MeshKit.box(st, Transform3D(Basis.IDENTITY, Vector3(0, y + 0.02, af + 0.15)), Vector3(0.45, 0.12, 0.6))
	MeshKit.box(st, Transform3D(Basis.IDENTITY, Vector3(0.15, y + 0.04, ar - gap - 0.35)), Vector3(0.9, 0.12, 0.5))
	# wheel arch liners: a half tube over each wheel and the inner wall beside it
	for side in [-1.0, 1.0]:
		for az in [af, ar]:
			var cx: float = side * tr
			var rr := wr + 0.07
			var segs := 14
			for k in segs:
				var a0 := lerpf(0.12, PI - 0.12, float(k) / segs)
				var a1 := lerpf(0.12, PI - 0.12, float(k + 1) / segs)
				var p0 := Vector3(0, wr + sin(a0) * rr, az + cos(a0) * rr)
				var p1 := Vector3(0, wr + sin(a1) * rr, az + cos(a1) * rr)
				# from the inner wall out to just inside the tyre's outer face (never past the fender)
				var xo: float = cx - side * (ww * 0.5 + 0.05)
				var xi: float = cx + side * (ww * 0.5 - 0.06)
				MeshKit.quad(st, Vector3(xo, p0.y, p0.z), Vector3(xi, p0.y, p0.z), Vector3(xi, p1.y, p1.z), Vector3(xo, p1.y, p1.z),
					-(p0 - Vector3(0, wr, az)).normalized())
				# the inner wall (towards the middle of the car)
				var xw: float = cx - side * (ww * 0.5 + 0.05)
				MeshKit.tri(st, Vector3(xw, wr, az), Vector3(xw, p0.y, p0.z), Vector3(xw, p1.y, p1.z),
					Vector3(-side, 0, 0), Vector3(-side, 0, 0), Vector3(-side, 0, 0), Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector3(-side, 0, 0))
	var under := MeshKit.mesh_instance(MeshKit.commit(st, dark))
	under.name = "Underbody"
	add_child(under)
	# the exhaust: from under the engine back along the tunnel's side to the tip
	var ex := Vector3(-0.3, 0.3, _rear)
	if not exhaust_points.is_empty():
		ex = exhaust_points[0]
	var sx := signf(ex.x) if absf(ex.x) > 0.05 else -1.0
	var pipe_y := y - 0.06
	var path: Array = [Vector3(0.12 * sx, y + 0.12, af + 0.45), Vector3(0.18 * sx, pipe_y, af + 0.9),
		Vector3(0.2 * sx, pipe_y, 0.0), Vector3(0.22 * sx, pipe_y, ar - gap - 0.1),
		Vector3(ex.x * 0.7, pipe_y + 0.02, ar + gap * 0.6), Vector3(ex.x, ex.y - 0.02, _rear - 0.35), ex - Vector3(0, 0, 0.05)]
	var pst := MeshKit.new_st()
	var radii: Array = []
	for i in path.size():
		radii.append(float(m.get("exhaust_r", 0.045)) * 0.85)
	MeshKit.tube(pst, path, radii, 10)
	var pipe := MeshKit.mesh_instance(MeshKit.commit(pst, metal))
	pipe.name = "Exhaust"
	add_child(pipe)
	# catalytic converter, centre silencer, rear box
	var bst := MeshKit.new_st()
	MeshKit.box(bst, Transform3D(Basis.IDENTITY, Vector3(0.19 * sx, pipe_y, af + 1.25)), Vector3(0.16, 0.11, 0.42))
	MeshKit.box(bst, Transform3D(Basis.IDENTITY, Vector3(0.21 * sx, pipe_y, 0.35)), Vector3(0.2, 0.13, 0.6))
	MeshKit.box(bst, Transform3D(Basis.IDENTITY, Vector3(ex.x * 0.8, pipe_y + 0.03, _rear - 0.55)), Vector3(0.55, 0.18, 0.32))
	var boxes := MeshKit.mesh_instance(MeshKit.commit(bst, rusty))
	add_child(boxes)


# ---------------------------------------------------------------------------
# Imported model
# ---------------------------------------------------------------------------
func _build_from_model(m: Dictionary, paint: Dictionary) -> void:
	wheel_r = float(m["wheel_r"])
	wheel_w = float(m.get("wheel_w", 0.25))
	spec = m
	_front = -float(m["length"]) * 0.5
	_rear = float(m["length"]) * 0.5
	paint_mat = TexKit.paint_material(paint)
	head_mat = TexKit.std(Color(0.85, 0.87, 0.9), 0.05, 0.4, Color(0.95, 0.97, 1.0), 0.25)
	tail_mat = TexKit.emissive(Color(1.0, 0.04, 0.03), 0.6)
	tail_mat.albedo_color = Color(0.5, 0.02, 0.02)
	tail_mat.roughness = 0.08
	reverse_mat = TexKit.std(Color(0.8, 0.8, 0.82), 0.1, 0.3, Color(1, 1, 1), 0.0)
	var indicator_mat := TexKit.emissive(Color(1.0, 0.45, 0.02), 0.35)
	# tinted glass you can see the cabin through, drawn from both sides (some models' windows face
	# inwards: one-sided they vanished from outside)
	glass_mat = StandardMaterial3D.new()
	glass_mat.albedo_color = Color(0.02, 0.025, 0.03, 0.62)
	glass_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	glass_mat.metallic = 0.4
	glass_mat.roughness = 0.03
	glass_mat.clearcoat_enabled = true
	glass_mat.clearcoat = 1.0
	glass_mat.clearcoat_roughness = 0.0
	var packed: PackedScene = load(m["path"])
	var inst := packed.instantiate()
	add_child(inst)
	model_root = inst
	var replace := {
		"md_paint": paint_mat, "md_glass": glass_mat, "md_head_lens": head_mat, "md_tail": tail_mat,
		"md_indicator": indicator_mat, "md_chrome": TexKit.chrome(), "md_mirror": TexKit.chrome(),
	}
	for k in replace:
		if replace[k] is BaseMaterial3D and k != "md_glass":
			(replace[k] as BaseMaterial3D).cull_mode = BaseMaterial3D.CULL_DISABLED
	for node in _mesh_instances(inst):
		var mi: MeshInstance3D = node
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		for i in mi.mesh.get_surface_count():
			var sm: Material = mi.mesh.surface_get_material(i)
			if sm == null:
				continue
			var key := String(sm.resource_name)
			if replace.has(key):
				mi.set_surface_override_material(i, replace[key])
	# wheels: re-parent the imported wheel meshes into steer pivot + spin nodes
	var names := ["fl", "fr", "rl", "rr"]
	for i in 4:
		var wheel := inst.find_child("wheel_" + names[i], true, false) as Node3D
		var pivot := Node3D.new()
		pivot.name = "Wheel" + names[i].to_upper()
		var spin := Node3D.new()
		pivot.add_child(spin)
		add_child(pivot)
		if wheel:
			pivot.position = wheel.position
			wheel.get_parent().remove_child(wheel)
			spin.add_child(wheel)
			wheel.transform = Transform3D.IDENTITY
			var cal := inst.find_child("caliper_" + names[i], true, false) as Node3D
			if cal:
				cal.get_parent().remove_child(cal)
				pivot.add_child(cal)
				cal.transform = Transform3D.IDENTITY
		else:
			var side := -1.0 if i % 2 == 0 else 1.0
			pivot.position = Vector3(side * float(m["track"]), float(m["wheel_r"]), float(m["axle_f"] if i < 2 else m["axle_r"]))
		wheel_nodes.append([pivot, spin])
	# measured tip centres of the model's pipes (see tools/find_exhausts.py)
	for e in m["exhaust"]:
		exhaust_points.append(Vector3(e[0], e[1], e[2]) + Vector3(0, 0, 0.01))
	exhaust_radius = float(m.get("exhaust_r", 0.05))
	# headlight spots
	for k in m["head"].size():
		var h: Array = m["head"][k]
		var spot := SpotLight3D.new()
		# in front of the bumper, otherwise the car body shadows its own headlights
		spot.position = Vector3(h[0], h[1], _front - 0.08)
		spot.rotation = Vector3(-0.07, 0, 0)
		spot.light_color = Color(0.95, 0.96, 1.0)
		spot.light_energy = 16.0
		spot.spot_range = 90.0
		spot.spot_angle = 32.0
		spot.spot_attenuation = 0.35
		spot.shadow_enabled = shadows_for_lights and k == 1
		spot.visible = false
		add_child(spot)
		head_spots.append(spot)
	brake_light = OmniLight3D.new()
	brake_light.light_color = Color(1.0, 0.08, 0.04)
	brake_light.omni_range = 4.5
	brake_light.light_energy = 0.3
	brake_light.shadow_enabled = false
	brake_light.position = Vector3(0, float(m["tail"][0][1]), float(m["tail"][0][2]) + 0.4)
	brake_light.visible = false
	add_child(brake_light)
	if bool(m.get("underbody", false)):
		_underbody(m)
	# reverse lamps: small emissive discs next to the tail lights
	for t in m["tail"]:
		var rv := MeshKit.cyl_node(0.03, 0.03, 0.01, reverse_mat, Vector3(float(t[0]) * 0.55, float(t[1]) - 0.08, float(t[2]) + 0.02), Vector3(PI * 0.5, 0, 0), 12)
		rv.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(rv)


func _mesh_instances(root: Node) -> Array:
	var out: Array = []
	if root is MeshInstance3D:
		out.append(root)
	for c in root.get_children():
		out.append_array(_mesh_instances(c))
	return out

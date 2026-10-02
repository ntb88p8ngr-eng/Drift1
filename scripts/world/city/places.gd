extends RefCounted
## Neo Tokyo's special places, each on a lot {c (ground centre), ax (along the street), az (away from
## it), w, d} whose front faces the street (-az): a coffee shop with a terrace, a donut shop with the
## giant donut on its roof, a ramen bar, a sushi restaurant and an izakaya, the iApfel store (a glass
## cube with its phone tables inside), konbinis, supermarkets with big car parks, a multi-storey car
## park you can drive up, coin parking lots, a gas station, the bowling hall, the police headquarters
## and karaoke / pachinko halls covered in neon. Geometry goes into the chunked city meshes; solid
## parts get colliders; light sources go to the light pool.

const MeshKit = preload("res://scripts/util/mesh_kit.gd")
const TexKit = preload("res://scripts/util/tex_kit.gd")
const CityAtlas = preload("res://scripts/world/city/city_atlas.gd")
const Colliders = preload("res://scripts/util/colliders.gd")
const Crowd = preload("res://scripts/world/crowd.gd")

var cm
var parent: Node3D
var scenery
var add_inst: Callable
var light: Callable
var person: Callable            # (position, look_at, shirt colour or null)
var rng := RandomNumberGenerator.new()
var stats := {}


func setup(p_cm, p_parent: Node3D, p_scenery, p_add: Callable, p_light: Callable, p_person: Callable) -> void:
	cm = p_cm
	parent = p_parent
	scenery = p_scenery
	add_inst = p_add
	light = p_light
	person = p_person
	rng.seed = 3131


func build(kind: String, lot: Dictionary) -> void:
	match kind:
		"coffee": _coffee(lot)
		"donut": _donut(lot)
		"ramen": _ramen(lot)
		"sushi": _japanese(lot, 3, 1)
		"izakaya": _japanese(lot, 4, 2)
		"iapfel": _iapfel(lot)
		"konbini": _konbini(lot)
		"supermarket": _supermarket(lot)
		"garage": _garage(lot)
		"coin_parking": _coin_parking(lot)
		"gas": _gas(lot)
		"bowling": _bowling(lot)
		"police": _police(lot)
		"karaoke": _neon_hall(lot, 13)
		"pachinko": _neon_hall(lot, 14)
	stats[kind] = int(stats.get(kind, 0)) + 1


# --- lot helpers --------------------------------------------------------------------------------------
func _b(lot: Dictionary) -> Basis:
	return Basis(lot["ax"], Vector3.UP, lot["az"])


## World point at lot coordinates (x along the street, y up, z away from it; the front at z = -d/2).
func _p(lot: Dictionary, x: float, y: float, z: float) -> Vector3:
	return (lot["c"] as Vector3) + (lot["ax"] as Vector3) * x + Vector3(0, y, 0) + (lot["az"] as Vector3) * z


func _box(lot: Dictionary, mat: String, x: float, y: float, z: float, size: Vector3, col: Color, solid := false) -> void:
	var xf := Transform3D(_b(lot), _p(lot, x, y, z))
	cm.box(mat, xf, size, col)
	if solid:
		Colliders.add_box(parent, xf, size)


## Facing the street: +Z of this basis looks out of the front.
func _front_basis(lot: Dictionary) -> Basis:
	return Basis(-(lot["ax"] as Vector3), Vector3.UP, -(lot["az"] as Vector3))


func _sign(lot: Dictionary, x: float, y: float, z: float, size: Vector3, rect: Rect2, lit := 1.0) -> void:
	cm.sign_box(Transform3D(_front_basis(lot), _p(lot, x, y, z)), size, rect, lit)


func _glow(lot: Dictionary, x: float, y: float, z: float, size: Vector3, col: Color, day := 0.3) -> void:
	cm.glow_box(Transform3D(_b(lot), _p(lot, x, y, z)), size, col, day)


## Shell of a building: three walls and a roof (the front left open for the caller), solid.
func _shell(lot: Dictionary, w: float, d: float, h: float, z0: float, col: Color) -> void:
	_box(lot, "frame", -w * 0.5 + 0.15, h * 0.5, z0 + d * 0.5, Vector3(0.3, h, d), col, true)
	_box(lot, "frame", w * 0.5 - 0.15, h * 0.5, z0 + d * 0.5, Vector3(0.3, h, d), col, true)
	_box(lot, "frame", 0, h * 0.5, z0 + d - 0.15, Vector3(w, h, 0.3), col, true)
	_box(lot, "frame", 0, h + 0.15, z0 + d * 0.5, Vector3(w + 0.3, 0.3, d + 0.3), col.darkened(0.25))
	_box(lot, "frame", 0, 0.02, z0 + d * 0.5, Vector3(w - 0.4, 0.04, d - 0.4), Color(0.55, 0.52, 0.48))


## A glazed front at z0 between x0..x1, up to `h`, the interior glowing `col`.
func _glazed_front(lot: Dictionary, x0: float, x1: float, h: float, z0: float, frame: Color, col: Color, bars := 3.0) -> void:
	var w := x1 - x0
	_glow(lot, (x0 + x1) * 0.5, h * 0.5, z0 + 0.5, Vector3(w - 0.3, h - 0.3, 0.05), col, 0.35)
	var n := maxi(int(w / bars), 1)
	for k in n + 1:
		_box(lot, "metal", x0 + w * float(k) / n, h * 0.5, z0, Vector3(0.12, h, 0.14), frame)
	_box(lot, "metal", (x0 + x1) * 0.5, h - 0.06, z0, Vector3(w, 0.12, 0.14), frame)
	_box(lot, "metal", (x0 + x1) * 0.5, 0.1, z0, Vector3(w, 0.2, 0.16), frame)
	Colliders.add_box(parent, Transform3D(_b(lot), _p(lot, (x0 + x1) * 0.5, h * 0.5, z0)), Vector3(w, h, 0.2))


func _people(lot: Dictionary, n: int, x0: float, x1: float, z0: float, z1: float, look_z := -100.0, shirt = null) -> void:
	for k in n:
		var pp := _p(lot, rng.randf_range(x0, x1), 0, rng.randf_range(z0, z1))
		var la := _p(lot, rng.randf_range(x0, x1), 0, look_z) if look_z > -99.0 else pp + Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1))
		person.call(pp, la, shirt)


func _cyl(lot: Dictionary, mat: String, x: float, y: float, z: float, r: float, h: float, col: Color, seg := 12) -> void:
	cm.cyl(mat, _p(lot, x, y, z), r, h, col, seg)


## A paper lantern (red akachōchin): glowing cylinder with dark caps.
func _lantern(lot: Dictionary, x: float, y: float, z: float, col := Color(1.0, 0.18, 0.08)) -> void:
	_cyl(lot, "glow", x, y - 0.35, z, 0.22, 0.7, Color(col.r, col.g, col.b, 0.6), 10)
	_cyl(lot, "frame", x, y + 0.33, z, 0.16, 0.06, Color(0.08, 0.08, 0.08), 8)
	_cyl(lot, "frame", x, y - 0.41, z, 0.16, 0.06, Color(0.08, 0.08, 0.08), 8)


# ---------------------------------------------------------------------------
# Food & drink
# ---------------------------------------------------------------------------
func _coffee(lot: Dictionary) -> void:
	var w: float = minf(lot["w"], 14.0)
	var d: float = minf(lot["d"], 14.0)
	var z0: float = -float(lot["d"]) * 0.5
	var h := 7.4
	var brick := Color(0.52, 0.3, 0.22)
	var wood := Color(0.24, 0.15, 0.09, 0.9)
	_shell(lot, w, d, h, z0, brick)
	_glazed_front(lot, -w * 0.5 + 0.4, w * 0.5 - 0.4, 3.6, z0, wood, Color(1.0, 0.76, 0.48), 2.4)
	# upper floor: brick with arched-looking windows (frames) lit warm
	_box(lot, "frame", 0, 5.6, z0 + 0.15, Vector3(w, 3.6, 0.3), brick, true)
	for k in 3:
		var x := -w * 0.3 + k * w * 0.3
		_glow(lot, x, 5.6, z0 - 0.02, Vector3(1.6, 2.0, 0.05), Color(1.0, 0.8, 0.55), 0.2)
		_box(lot, "frame", x, 4.5, z0 - 0.06, Vector3(1.9, 0.15, 0.15), Color(0.85, 0.82, 0.75))
	# fascia, sign, the big 3D cup on top of the sign
	_box(lot, "frame", 0, 3.95, z0 - 0.1, Vector3(w, 0.7, 0.35), Color(0.12, 0.09, 0.07))
	_sign(lot, 0, 3.95, z0 - 0.3, Vector3(minf(w - 2.0, 8.0), 0.6, 0.08), CityAtlas.shop(0), 1.0)
	_cyl(lot, "frame", w * 0.38, 4.35, z0 - 0.4, 0.55, 1.0, Color(0.95, 0.93, 0.88))
	_cyl(lot, "frame", w * 0.38, 5.33, z0 - 0.4, 0.5, 0.06, Color(0.32, 0.18, 0.1))
	_box(lot, "frame", w * 0.38 + 0.7, 4.85, z0 - 0.4, Vector3(0.18, 0.55, 0.14), Color(0.95, 0.93, 0.88))
	# terrace on the pavement: tables, chairs, umbrellas
	for k in 3:
		var x := -w * 0.32 + k * w * 0.32
		var z := z0 - 2.3
		_cyl(lot, "metal", x, 0.0, z, 0.04, 0.75, Color(0.2, 0.2, 0.2, 0.5), 6)
		_cyl(lot, "frame", x, 0.75, z, 0.4, 0.04, Color(0.85, 0.85, 0.82), 10)
		for cx: float in [-0.75, 0.75]:
			_box(lot, "frame", x + cx, 0.45, z, Vector3(0.42, 0.06, 0.42), wood)
			_box(lot, "frame", x + cx * 1.3, 0.75, z, Vector3(0.06, 0.6, 0.42), wood)
		_cyl(lot, "metal", x, 0.75, z, 0.03, 1.4, Color(0.6, 0.6, 0.6, 0.5), 6)
		_cyl(lot, "frame", x, 2.15, z, 1.2, 0.05, [Color(0.15, 0.35, 0.2), Color(0.9, 0.88, 0.8)][k % 2], 12)
		if rng.randf() < 0.7:
			person.call(_p(lot, x - 0.75, 0, z), _p(lot, x, 0, z), null)
	_people(lot, 4, -w * 0.4, w * 0.4, z0 + 1.0, z0 + d * 0.6, z0)
	light.call(_p(lot, 0, 3.0, z0 - 2.0), Color(1.0, 0.78, 0.5), 10.0, 2.0, 0)
	light.call(_p(lot, 0, 2.8, z0 + 3.0), Color(1.0, 0.78, 0.5), 8.0, 1.5, 0)


func _donut(lot: Dictionary) -> void:
	var w: float = minf(lot["w"], 13.0)
	var d: float = minf(lot["d"], 12.0)
	var z0: float = -float(lot["d"]) * 0.5
	var h := 4.8
	_shell(lot, w, d, h, z0, Color(0.98, 0.94, 0.96))
	_glazed_front(lot, -w * 0.5 + 0.4, w * 0.5 - 0.4, 3.4, z0, Color(1.0, 0.45, 0.7, 0.8), Color(1.0, 0.86, 0.9), 2.2)
	# pink and white striped awning, fascia, sign
	for k in int(w / 0.8):
		var x := -w * 0.5 + 0.4 + k * 0.8
		_box(lot, "frame", x, 3.55, z0 - 0.8, Vector3(0.8, 0.06, 1.6), Color(1.0, 0.45, 0.7) if k % 2 == 0 else Color(1, 1, 1))
	_box(lot, "frame", 0, 4.3, z0 - 0.1, Vector3(w, 0.9, 0.3), Color(1.0, 0.5, 0.75))
	_sign(lot, 0, 4.3, z0 - 0.28, Vector3(minf(w - 2.0, 7.0), 0.7, 0.06), CityAtlas.shop(1), 1.0)
	# the giant donut standing on the roof, facing the street
	var dc := _p(lot, 0, h + 4.2, z0 + d * 0.4)
	var dough := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 1.3
	tm.outer_radius = 3.6
	tm.rings = 32
	tm.ring_segments = 16
	dough.mesh = tm
	dough.material_override = TexKit.std(Color(0.86, 0.6, 0.32), 0.7)
	parent.add_child(dough)
	dough.global_transform = Transform3D(_b(lot).rotated(lot["ax"], PI * 0.5), dc)
	var icing := MeshInstance3D.new()
	var ti := TorusMesh.new()
	ti.inner_radius = 1.45
	ti.outer_radius = 3.45
	ti.rings = 32
	ti.ring_segments = 16
	icing.mesh = ti
	var im := TexKit.std(Color(1.0, 0.45, 0.72), 0.35)
	im.emission_enabled = true
	im.emission = Color(1.0, 0.3, 0.6)
	im.emission_energy_multiplier = 0.35
	scenery._glow_mats.append([im, 0.35, 2.0])
	icing.material_override = im
	parent.add_child(icing)
	icing.global_transform = Transform3D(_b(lot).rotated(lot["ax"], PI * 0.5), dc - (lot["az"] as Vector3) * 0.35) * Transform3D(Basis.from_scale(Vector3(1, 1, 0.75)), Vector3.ZERO)
	# sprinkles on the icing
	for k in 40:
		var a := rng.randf() * TAU
		var r := rng.randf_range(1.8, 3.1)
		var sp := dc + (lot["ax"] as Vector3) * cos(a) * r + Vector3(0, sin(a) * r, 0) - (lot["az"] as Vector3) * 0.95
		cm.box("frame", Transform3D(Basis(Vector3(0, 0, 1), rng.randf() * PI).rotated(Vector3.UP, 0.0), sp), Vector3(0.28, 0.08, 0.08),
			[Color(1, 1, 1), Color(0.3, 0.6, 1.0), Color(1.0, 0.9, 0.2), Color(0.4, 0.9, 0.4)][k % 4])
	# its stand
	_box(lot, "metal", 0, h + 0.4, z0 + d * 0.4, Vector3(0.4, 0.8, 0.4), Color(0.6, 0.6, 0.62, 0.5))
	_people(lot, 5, -w * 0.4, w * 0.4, z0 - 3.0, z0 - 1.0, z0)
	light.call(_p(lot, 0, 3.0, z0 - 2.0), Color(1.0, 0.7, 0.85), 10.0, 2.0, 0)
	light.call(dc - (lot["az"] as Vector3) * 3.0, Color(1.0, 0.5, 0.75), 12.0, 1.6, 0)


func _ramen(lot: Dictionary) -> void:
	var w: float = minf(lot["w"], 9.0)
	var d: float = minf(lot["d"], 12.0)
	var z0: float = -float(lot["d"]) * 0.5
	var h := 7.0
	var wood := Color(0.18, 0.11, 0.07)
	_shell(lot, w, d, h, z0, Color(0.3, 0.22, 0.16))
	# ground floor: sliding door with the warm light behind, noren hanging over it
	_glazed_front(lot, -w * 0.5 + 0.3, w * 0.5 - 0.3, 2.6, z0, wood, Color(1.0, 0.7, 0.4), 1.2)
	for k in 3:
		var x := -0.9 + k * 0.9
		cm.sign_box(Transform3D(_front_basis(lot), _p(lot, x, 2.25, z0 - 0.12)), Vector3(0.85, 1.0, 0.02), CityAtlas.misc(2 + 3 * (k % 2)), 0.2)
	_box(lot, "metal", 0, 2.78, z0 - 0.12, Vector3(2.9, 0.05, 0.05), Color(0.3, 0.2, 0.1, 0.8))
	# upper floor: vertical wooden slats
	_box(lot, "frame", 0, 4.9, z0 + 0.1, Vector3(w, 4.2, 0.2), Color(0.25, 0.17, 0.11), true)
	for k in int(w / 0.35):
		_box(lot, "frame", -w * 0.5 + 0.2 + k * 0.35, 4.9, z0 - 0.06, Vector3(0.12, 3.8, 0.12), wood)
	# big sign, blade sign, red lanterns either side of the door, the ticket machine, the menu board
	_box(lot, "frame", 0, 3.1, z0 - 0.15, Vector3(w, 0.7, 0.3), Color(0.08, 0.06, 0.05))
	_sign(lot, 0, 3.1, z0 - 0.33, Vector3(minf(w - 1.0, 6.5), 0.6, 0.06), CityAtlas.shop(2), 1.0)
	cm.sign_box(Transform3D(Basis(-(lot["az"] as Vector3), Vector3.UP, (lot["ax"] as Vector3)), _p(lot, w * 0.5 - 0.3, 5.0, z0 - 0.7)), Vector3(1.0, 3.2, 0.2), CityAtlas.blade(0), 1.0, true)
	for x: float in [-w * 0.5 + 0.6, w * 0.5 - 0.6]:
		_lantern(lot, x, 2.3, z0 - 0.45)
	_box(lot, "frame", -w * 0.5 + 1.0, 0.9, z0 - 0.5, Vector3(0.9, 1.8, 0.6), Color(0.85, 0.85, 0.8))
	_glow(lot, -w * 0.5 + 1.0, 1.2, z0 - 0.81, Vector3(0.7, 0.9, 0.03), Color(0.9, 0.95, 1.0), 0.6)
	cm.sign_box(Transform3D(_front_basis(lot), _p(lot, w * 0.5 - 1.1, 0.75, z0 - 0.7)), Vector3(0.6, 0.9, 0.05), CityAtlas.misc(8), 0.5)
	_people(lot, rng.randi_range(2, 5), -w * 0.3, w * 0.3, z0 - 2.5, z0 - 1.0, z0)
	light.call(_p(lot, 0, 2.4, z0 - 1.5), Color(1.0, 0.45, 0.25), 8.0, 1.8, 0)


## Sushi / izakaya: a wooden lattice front, a small tiled roof over the ground floor, lanterns, noren.
func _japanese(lot: Dictionary, sign_cell: int, noren: int) -> void:
	var w: float = minf(lot["w"], 12.0)
	var d: float = minf(lot["d"], 14.0)
	var z0: float = -float(lot["d"]) * 0.5
	var h := 6.6
	var wood := Color(0.42, 0.28, 0.16)
	var dark := Color(0.16, 0.11, 0.07)
	_shell(lot, w, d, h, z0, Color(0.85, 0.8, 0.7))
	_glow(lot, 0, 1.4, z0 + 0.35, Vector3(w - 0.6, 2.6, 0.05), Color(1.0, 0.78, 0.5), 0.3)
	# kōshi lattice: thin vertical slats in front of the glow
	for k in int((w - 2.6) / 0.16):
		var x := -w * 0.5 + 0.4 + k * 0.16
		if absf(x) < 1.2:
			continue           # the entrance
		_box(lot, "frame", x, 1.4, z0, Vector3(0.05, 2.8, 0.08), wood)
	_box(lot, "frame", 0, 2.85, z0, Vector3(w, 0.1, 0.12), dark)
	Colliders.add_box(parent, Transform3D(_b(lot), _p(lot, 0, 1.4, z0)), Vector3(w, 2.8, 0.2))
	# noren over the entrance
	for k in 2:
		cm.sign_box(Transform3D(_front_basis(lot), _p(lot, -0.55 + k * 1.1, 2.25, z0 - 0.08)), Vector3(1.05, 1.0, 0.02), CityAtlas.misc(2 + noren), 0.2)
	# little tiled roof: a sloped slab with ridge tiles
	var rb := _b(lot).rotated(lot["ax"], 0.42)
	cm.box("frame", Transform3D(rb, _p(lot, 0, 3.3, z0 - 0.55)), Vector3(w + 0.4, 0.14, 1.5), Color(0.24, 0.26, 0.28))
	for k in int(w / 0.3):
		cm.box("frame", Transform3D(rb, _p(lot, -w * 0.5 + 0.15 + k * 0.3, 3.36, z0 - 0.55)), Vector3(0.12, 0.08, 1.5), Color(0.2, 0.22, 0.24))
	# upper floor: plaster with a small window, the sign board, lanterns in a row
	_box(lot, "frame", 0, 5.1, z0 + 0.15, Vector3(w, 3.0, 0.3), Color(0.88, 0.85, 0.78), true)
	_glow(lot, 0, 5.0, z0 - 0.02, Vector3(w * 0.5, 1.2, 0.05), Color(1.0, 0.82, 0.6), 0.15)
	for k in int(w * 0.5 / 0.14):
		_box(lot, "frame", -w * 0.25 + k * 0.14, 5.0, z0 - 0.06, Vector3(0.04, 1.2, 0.05), wood)
	_box(lot, "frame", 0, 6.2, z0 - 0.1, Vector3(w * 0.7, 0.7, 0.2), dark)
	_sign(lot, 0, 6.2, z0 - 0.22, Vector3(w * 0.6, 0.55, 0.04), CityAtlas.shop(sign_cell), 0.8)
	for k in int(w / 1.4):
		_lantern(lot, -w * 0.5 + 0.7 + k * 1.4, 3.75, z0 - 1.2, Color(1.0, 0.2, 0.08) if k % 2 == 0 else Color(1.0, 0.85, 0.5))
	# potted plants and a bamboo screen at the side
	for x: float in [-w * 0.5 + 0.5, w * 0.5 - 0.5]:
		_cyl(lot, "frame", x, 0, z0 - 0.5, 0.3, 0.5, Color(0.3, 0.25, 0.2))
		_cyl(lot, "frame", x, 0.5, z0 - 0.5, 0.35, 0.9, Color(0.2, 0.45, 0.18))
	_people(lot, rng.randi_range(1, 4), -w * 0.3, w * 0.3, z0 - 2.5, z0 - 1.2, z0)
	light.call(_p(lot, 0, 2.6, z0 - 1.8), Color(1.0, 0.55, 0.3), 9.0, 2.0, 0)


# ---------------------------------------------------------------------------
# iApfel store: a glass cube with the shop floor inside
# ---------------------------------------------------------------------------
func _iapfel(lot: Dictionary) -> void:
	var w: float = minf(lot["w"], 26.0)
	var d: float = minf(lot["d"], 22.0)
	var z0: float = -float(lot["d"]) * 0.5
	var h := 9.0
	var steel := Color(0.82, 0.84, 0.86, 0.35)
	var wood := Color(0.78, 0.62, 0.42)
	# floor (light stone), the back wall with the big glowing logo, the ceiling with light panels
	_box(lot, "frame", 0, 0.05, z0 + d * 0.5, Vector3(w, 0.1, d), Color(0.86, 0.85, 0.82))
	_box(lot, "frame", 0, h * 0.5, z0 + d - 0.2, Vector3(w, h, 0.4), Color(0.95, 0.95, 0.96), true)
	cm.sign_box(Transform3D(_front_basis(lot), _p(lot, 0, 5.4, z0 + d - 0.45)), Vector3(3.6, 5.4, 0.1), CityAtlas.misc(7), 1.0)
	_box(lot, "frame", 0, h + 0.2, z0 + d * 0.5, Vector3(w + 0.2, 0.4, d + 0.2), Color(0.9, 0.9, 0.92))
	for k in 4:
		_glow(lot, 0, h - 0.05, z0 + d * (0.15 + k * 0.22), Vector3(w - 2.0, 0.05, 1.2), Color(1.0, 1.0, 0.98), 0.9)
	# the glass: thin steel posts and transparent panes all round (a real see-through glass)
	var gm := StandardMaterial3D.new()
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gm.albedo_color = Color(0.75, 0.85, 0.9, 0.18)
	gm.metallic = 0.6
	gm.roughness = 0.03
	var panes := MeshKit.new_st()
	for side in 3:
		var fw := w if side == 0 else d
		var n := maxi(int(fw / 3.0), 1)
		for k in n:
			var x0 := -fw * 0.5 + fw * float(k) / n
			var x1 := -fw * 0.5 + fw * float(k + 1) / n
			var a: Vector3
			var b: Vector3
			if side == 0:
				a = _p(lot, x0, 0, z0)
				b = _p(lot, x1, 0, z0)
			else:
				var sx := -w * 0.5 if side == 1 else w * 0.5
				a = _p(lot, sx, 0, z0 + d * 0.5 + x0)
				b = _p(lot, sx, 0, z0 + d * 0.5 + x1)
			var out := (a - _p(lot, 0, 0, z0 + d * 0.5)).normalized()
			MeshKit.quad(panes, a, b, b + Vector3(0, h, 0), a + Vector3(0, h, 0), Vector3(out.x, 0, out.z))
			cm.box("metal", Transform3D(_b(lot), a + Vector3(0, h * 0.5, 0)), Vector3(0.1, h, 0.1), steel)
	var pm := MeshInstance3D.new()
	pm.mesh = MeshKit.commit(panes, gm)
	pm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(pm)
	for side in 3:
		var size := Vector3(w, h, 0.2) if side == 0 else Vector3(0.2, h, d)
		var pos := _p(lot, 0, h * 0.5, z0) if side == 0 else _p(lot, (-w if side == 1 else w) * 0.5, h * 0.5, z0 + d * 0.5)
		if side == 0:
			# the entrance in the middle stays open for people (cars are kept out by the bollards)
			Colliders.add_box(parent, Transform3D(_b(lot), _p(lot, -w * 0.3, h * 0.5, z0)), Vector3(w * 0.4, h, 0.2))
			Colliders.add_box(parent, Transform3D(_b(lot), _p(lot, w * 0.3, h * 0.5, z0)), Vector3(w * 0.4, h, 0.2))
			for x: float in [-1.5, 0.0, 1.5]:
				_cyl(lot, "metal", x, 0, z0 - 1.0, 0.12, 0.9, steel, 8)
		else:
			Colliders.add_box(parent, Transform3D(_b(lot), pos), size)
	# the sign above the entrance, glowing
	_sign(lot, 0, h - 1.0, z0 - 0.1, Vector3(5.0, 1.25, 0.06), CityAtlas.shop(6), 1.0)
	# long wooden tables with phones and tablets (glowing screens), stools; a glass stair at the back
	for row in 3:
		var tz := z0 + 4.0 + row * 4.2
		for col in 2:
			var tx := -w * 0.22 + col * w * 0.44
			_box(lot, "frame", tx, 0.85, tz, Vector3(5.5, 0.08, 1.4), wood)
			for leg: float in [-2.4, 2.4]:
				_box(lot, "frame", tx + leg, 0.42, tz, Vector3(0.12, 0.84, 1.2), wood.darkened(0.2))
			for k in 6:
				var px := tx - 2.2 + k * 0.88
				cm.box("frame", Transform3D(_b(lot).rotated(Vector3.UP, 0.1), _p(lot, px, 0.9, tz)), Vector3(0.36, 0.02, 0.74), Color(0.12, 0.12, 0.13, 0.4))
				cm.glow_box(Transform3D(_b(lot), _p(lot, px, 0.92, tz)), Vector3(0.32, 0.01, 0.68), [Color(0.3, 0.6, 1.0), Color(1.0, 0.5, 0.75), Color(0.4, 1.0, 0.7)][k % 3], 0.9)
	for k in 8:
		_box(lot, "metal", w * 0.35, 0.35 + k * 0.4, z0 + d - 3.0 - k * 0.3, Vector3(2.2, 0.06, 0.32), Color(0.85, 0.9, 0.95, 0.35))
	# customers and staff (blue shirts)
	_people(lot, 14, -w * 0.4, w * 0.4, z0 + 2.5, z0 + d - 3.5)
	_people(lot, 5, -w * 0.4, w * 0.4, z0 + 3.0, z0 + d - 4.0, -100.0, Color(0.1, 0.35, 0.85))
	_people(lot, 6, -w * 0.45, w * 0.45, z0 - 3.5, z0 - 1.5, z0)
	for k in 3:
		light.call(_p(lot, -w * 0.3 + k * w * 0.3, h - 1.0, z0 + d * 0.4), Color(0.95, 0.97, 1.0), 14.0, 2.4, 0)
	light.call(_p(lot, 0, 4.0, z0 - 3.0), Color(0.95, 0.97, 1.0), 14.0, 2.0, 0)


# ---------------------------------------------------------------------------
# Shops for everyday: konbini, supermarket
# ---------------------------------------------------------------------------
func _konbini(lot: Dictionary) -> void:
	var w: float = minf(lot["w"], 18.0)
	var d: float = minf(lot["d"], 14.0)
	var z0: float = -float(lot["d"]) * 0.5
	var h := 4.6
	_shell(lot, w, d, h, z0, Color(0.95, 0.95, 0.94))
	_glazed_front(lot, -w * 0.5 + 0.3, w * 0.5 - 0.3, 3.0, z0, Color(0.8, 0.8, 0.82, 0.4), Color(1.0, 0.99, 0.95), 2.5)
	for k in 3:
		_glow(lot, 0, 4.25 - k * 0.32, z0 - 0.08, Vector3(w, 0.3, 0.06), [Color(0.98, 0.45, 0.05), Color(0.1, 0.6, 0.3), Color(0.9, 0.08, 0.1)][k], 0.5)
	_sign(lot, -w * 0.25, 3.3, z0 - 0.16, Vector3(3.2, 0.5, 0.05), CityAtlas.shop(5), 1.0)
	# shelves inside (rows of coloured boxes), ATM, bins, bike rack
	for row in 3:
		for k in int((w - 4.0) / 1.0):
			_box(lot, "frame", -w * 0.5 + 2.0 + k * 1.0, 0.8, z0 + 3.0 + row * 2.5, Vector3(0.9, 1.6, 0.6), [Color(0.9, 0.3, 0.3), Color(0.3, 0.6, 0.9), Color(0.95, 0.85, 0.3), Color(0.4, 0.8, 0.4)][(k + row) % 4])
	for k in 3:
		add_inst.call("bin", Transform3D(_front_basis(lot), _p(lot, w * 0.5 - 1.0 - k * 0.7, 0, z0 - 0.6)), Color(1, 1, 1, 1))
	_box(lot, "metal", -w * 0.5 + 1.5, 0.5, z0 - 2.5, Vector3(3.0, 0.06, 0.06), Color(0.6, 0.6, 0.62, 0.4))
	_people(lot, 6, -w * 0.4, w * 0.4, z0 + 1.5, z0 + d - 1.5)
	_people(lot, 3, -w * 0.4, w * 0.4, z0 - 2.5, z0 - 0.8, z0)
	light.call(_p(lot, 0, 2.5, z0 - 2.0), Color(0.95, 0.98, 1.0), 12.0, 2.6, 0)


func _supermarket(lot: Dictionary) -> void:
	var w: float = lot["w"]
	var d: float = lot["d"]
	var z0 := -d * 0.5
	var park_d := minf(d * 0.48, 38.0)
	var sd := d - park_d - 2.0
	var sz := z0 + park_d + 2.0
	var h := 8.5
	# the car park: asphalt with stall lines in rows, lamp posts, a cart corral, cars
	scenery.add_ground_patch(Transform3D(_b(lot), _p(lot, 0, 0, z0 + park_d * 0.5)), Vector2(w, park_d), "asphalt")
	var white := Color(0.9, 0.9, 0.88)
	var rows := int((park_d - 4.0) / 12.5)
	for r in rows:
		var rz := z0 + 3.0 + r * 12.5
		var n := int((w - 6.0) / 2.6)
		for k in n + 1:
			var x := -w * 0.5 + 3.0 + k * 2.6
			for half: float in [0.0, 1.0]:
				cm.box("line", Transform3D(_b(lot), _p(lot, x, 0.05, rz + 2.6 + half * 5.4)), Vector3(0.12, 0.01, 5.0), white)
			if k < n:
				for half: float in [0.0, 1.0]:
					if rng.randf() < 0.6 and scenery.details:
						var yaw_b := _b(lot).rotated(Vector3.UP, (0.0 if half == 0.0 else PI) + rng.randf_range(-0.05, 0.05))
						scenery.details.add_parked_car(Transform3D(yaw_b, _p(lot, x + 1.3, 0, rz + 2.6 + half * 5.4)))
		# lamp posts down the middle of the row
		for k in int(w / 20.0):
			var lp := _p(lot, -w * 0.5 + 10.0 + k * 20.0, 0, rz + 5.3)
			cm.box("metal", Transform3D(_b(lot), lp + Vector3(0, 4.5, 0)), Vector3(0.18, 9.0, 0.18), Color(0.5, 0.5, 0.52, 0.5))
			cm.glow_box(Transform3D(_b(lot), lp + Vector3(0, 9.0, 0)), Vector3(1.2, 0.12, 0.5), Color(1.0, 0.96, 0.88), 0.05)
			light.call(lp + Vector3(0, 8.8, 0), Color(1.0, 0.95, 0.85), 24.0, 4.0, 1)
	_box(lot, "metal", w * 0.35, 0.5, z0 + park_d - 3.0, Vector3(4.0, 1.0, 1.4), Color(0.7, 0.72, 0.75, 0.4))
	# the store: big box, glass entrance, signs (on the facade and a tall pylon at the street)
	_box(lot, "frame", 0, h * 0.5, sz + sd * 0.5, Vector3(w - 2.0, h, sd), Color(0.88, 0.84, 0.76), true)
	_box(lot, "frame", 0, h + 0.4, sz + sd * 0.5, Vector3(w - 1.6, 0.8, sd + 0.4), Color(0.7, 0.2, 0.15))
	_glow(lot, 0, 1.8, sz - 0.03, Vector3(w * 0.45, 3.2, 0.05), Color(1.0, 0.97, 0.9), 0.4)
	for k in int(w * 0.45 / 2.5) + 1:
		_box(lot, "metal", -w * 0.225 + k * 2.5, 1.8, sz - 0.08, Vector3(0.12, 3.6, 0.1), Color(0.7, 0.7, 0.72, 0.4))
	_box(lot, "frame", 0, 4.4, sz - 1.4, Vector3(w * 0.5, 0.3, 2.8), Color(0.7, 0.2, 0.15))
	_sign(lot, 0, 6.4, sz - 0.12, Vector3(minf(w * 0.5, 16.0), 2.4, 0.1), CityAtlas.shop(7), 1.0)
	_box(lot, "metal", -w * 0.5 + 2.0, 4.0, z0 + 1.0, Vector3(0.4, 8.0, 0.4), Color(0.5, 0.5, 0.52, 0.5), true)
	_sign(lot, -w * 0.5 + 2.0, 8.6, z0 + 1.0, Vector3(4.0, 1.4, 0.3), CityAtlas.shop(7), 1.0)
	# carts lined up by the door, shoppers
	for k in 8:
		_box(lot, "metal", w * 0.28 + k * 0.45, 0.5, sz - 3.0, Vector3(0.5, 0.9, 0.9), Color(0.75, 0.76, 0.8, 0.3))
	_people(lot, 16, -w * 0.4, w * 0.4, z0 + 2.0, sz - 1.0)
	light.call(_p(lot, 0, 3.5, sz - 3.0), Color(1.0, 0.97, 0.9), 16.0, 2.4, 0)


# ---------------------------------------------------------------------------
# Parking
# ---------------------------------------------------------------------------
## A multi-storey car park: four decks on columns, ramps up the side (all drivable), parapets,
## parked cars on every deck, lights under the decks, the big blue P.
func _garage(lot: Dictionary) -> void:
	var w: float = minf(lot["w"], 34.0)
	var d: float = minf(lot["d"], 46.0)
	var z0: float = -float(lot["d"]) * 0.5
	var levels := 4
	var lh := 3.2
	var conc := Color(0.66, 0.66, 0.64)
	var ramp_w := 6.0
	var deck_w := w - ramp_w
	var dx := -ramp_w * 0.5       # decks on the left, the ramp lane on the right
	for lv in range(1, levels + 1):
		var y := lv * lh
		# deck slab (leaving the ramp lane open), solid
		_box(lot, "frame", dx, y - 0.18, z0 + d * 0.5, Vector3(deck_w, 0.36, d), conc, true)
		# parapets with gaps, a coloured band per level
		for s: float in [-1.0, 1.0]:
			_box(lot, "frame", dx - deck_w * 0.5 + 0.15 if s < 0.0 else dx, y + 0.5, z0 + d * 0.5 if s < 0.0 else z0 + 0.15, Vector3(0.3, 1.0, d) if s < 0.0 else Vector3(deck_w, 1.0, 0.3), conc, true)
		_box(lot, "frame", dx, y + 0.5, z0 + d - 0.15, Vector3(deck_w, 1.0, 0.3), conc, true)
		_box(lot, "frame", dx, y + 0.9, z0 - 0.02, Vector3(deck_w, 0.18, 0.05), [Color(0.2, 0.5, 0.9), Color(0.9, 0.6, 0.1), Color(0.3, 0.75, 0.35), Color(0.85, 0.2, 0.2)][lv - 1])
		# lights under the deck
		for k in 3:
			_glow(lot, dx - deck_w * 0.3 + k * deck_w * 0.3, y - 0.4, z0 + d * 0.5, Vector3(0.2, 0.06, d * 0.8), Color(0.95, 1.0, 0.95), 0.4)
		light.call(_p(lot, dx, y - 0.6, z0 + d * 0.5), Color(0.92, 1.0, 0.95), 16.0, 1.8, 0)
	# ramps in the lane: each climbs one level over the depth of the building, alternating direction
	for lv in levels:
		var y0 := lv * lh
		var len := d - 4.0
		var slope := atan2(lh, len)
		var dir := 1.0 if lv % 2 == 0 else -1.0
		var rb := _b(lot).rotated(lot["ax"], -slope * dir)
		var rc := _p(lot, w * 0.5 - ramp_w * 0.5, y0 + lh * 0.5 - 0.15, z0 + d * 0.5)
		var xf := Transform3D(rb, rc)
		cm.box("frame", xf, Vector3(ramp_w - 0.4, 0.3, len / cos(slope)), conc.darkened(0.1))
		Colliders.add_box(parent, xf, Vector3(ramp_w - 0.4, 0.3, len / cos(slope)))
		_box(lot, "frame", w * 0.5 - 0.15, y0 + lh * 0.5 + 0.5, z0 + d * 0.5, Vector3(0.3, lh, d), conc, true)
	# columns
	for cx in range(0, int(deck_w / 8.0) + 1):
		for cz in range(0, int(d / 8.0) + 1):
			var x := dx - deck_w * 0.5 + minf(cx * 8.0, deck_w) + (0.3 if cx == 0 else -0.3)
			_box(lot, "frame", x, levels * lh * 0.5, z0 + minf(cz * 8.0, d - 0.3) + 0.3, Vector3(0.6, levels * lh, 0.6), conc, true)
	# parked cars on the decks and on the ground
	if scenery.details:
		for lv in levels + 1:
			var y := lv * lh
			for row: float in [0.25, 0.75]:
				for k in int(deck_w / 2.6):
					if rng.randf() < 0.55:
						var yaw_b := _b(lot).rotated(Vector3.UP, PI * 0.5 if row < 0.5 else -PI * 0.5)
						scenery.details.add_parked_car(Transform3D(yaw_b, _p(lot, dx - deck_w * 0.5 + 1.3 + k * 2.6, y + (0.0 if lv == 0 else 0.0), z0 + d * row)))
	# the blue P on a pylon at the street, the entrance sign, the barrier booth
	_box(lot, "metal", w * 0.5 - 1.0, 5.0, z0 - 1.0, Vector3(0.4, 10.0, 0.4), Color(0.5, 0.5, 0.52, 0.5), true)
	_sign(lot, w * 0.5 - 1.0, 9.0, z0 - 1.0, Vector3(2.2, 3.2, 0.3), CityAtlas.misc(6), 1.0)
	_sign(lot, w * 0.5 - ramp_w * 0.5, lh - 0.6, z0 - 0.1, Vector3(4.0, 0.7, 0.08), CityAtlas.shop(8), 1.0)
	_box(lot, "frame", w * 0.5 - ramp_w - 0.8, 1.2, z0 + 1.0, Vector3(1.4, 2.4, 1.4), Color(0.9, 0.9, 0.88), true)
	_box(lot, "metal", w * 0.5 - ramp_w * 0.5, 1.0, z0 + 1.0, Vector3(ramp_w - 1.0, 0.1, 0.1), Color(0.95, 0.85, 0.2, 0.6))
	light.call(_p(lot, w * 0.5 - 1.0, 8.0, z0 - 2.0), Color(0.4, 0.6, 1.0), 12.0, 1.4, 0)


## Coin parking: a small asphalt lot with marked stalls, flaps, a pay machine and the yellow P sign.
func _coin_parking(lot: Dictionary) -> void:
	var w: float = minf(lot["w"], 22.0)
	var d: float = minf(lot["d"], 18.0)
	var z0: float = -float(lot["d"]) * 0.5
	scenery.add_ground_patch(Transform3D(_b(lot), _p(lot, 0, 0, z0 + d * 0.5)), Vector2(w, d), "asphalt")
	var n := int((w - 2.0) / 2.6)
	for k in n + 1:
		cm.box("line", Transform3D(_b(lot), _p(lot, -w * 0.5 + 1.0 + k * 2.6, 0.05, z0 + d - 2.8)), Vector3(0.12, 0.01, 5.0), Color(0.95, 0.85, 0.2))
	for k in n:
		var x := -w * 0.5 + 2.3 + k * 2.6
		_box(lot, "metal", x, 0.08, z0 + d - 2.6, Vector3(0.9, 0.16, 0.5), Color(0.35, 0.35, 0.37, 0.5))
		if rng.randf() < 0.7 and scenery.details:
			scenery.details.add_parked_car(Transform3D(_b(lot).rotated(Vector3.UP, PI), _p(lot, x, 0, z0 + d - 2.8)))
	_box(lot, "frame", w * 0.5 - 1.0, 0.8, z0 + 0.8, Vector3(0.7, 1.6, 0.5), Color(0.95, 0.85, 0.2))
	_box(lot, "metal", -w * 0.5 + 0.8, 1.6, z0 + 0.4, Vector3(0.12, 3.2, 0.12), Color(0.5, 0.5, 0.52, 0.5))
	_sign(lot, -w * 0.5 + 0.8, 3.6, z0 + 0.4, Vector3(1.4, 2.0, 0.12), CityAtlas.misc(6), 1.0)
	light.call(_p(lot, 0, 4.0, z0 + d * 0.5), Color(1.0, 0.95, 0.85), 14.0, 1.6, 1)
	cm.box("metal", Transform3D(_b(lot), _p(lot, 0, 2.0, z0 + d - 0.3)), Vector3(0.14, 4.0, 0.14), Color(0.5, 0.5, 0.52, 0.5))
	cm.glow_box(Transform3D(_b(lot), _p(lot, 0, 4.05, z0 + d - 0.6)), Vector3(0.8, 0.1, 0.5), Color(1.0, 0.95, 0.85), 0.05)


# ---------------------------------------------------------------------------
# Gas station, bowling hall, police headquarters, neon halls
# ---------------------------------------------------------------------------
func _gas(lot: Dictionary) -> void:
	var z0: float = -float(lot["d"]) * 0.5
	scenery.add_ground_patch(Transform3D(_b(lot), _p(lot, 0, 0, z0 + 9.0)), Vector2(minf(lot["w"], 32.0), 18.0), "asphalt")
	var steel := Color(0.85, 0.85, 0.86, 0.5)
	for x: float in [-9.0, 9.0]:
		for z: float in [5.0, 11.0]:
			_box(lot, "metal", x, 2.5, z0 + z, Vector3(0.45, 5.0, 0.45), steel, true)
	_box(lot, "frame", 0, 5.45, z0 + 8.0, Vector3(24.0, 0.9, 11.0), Color(0.95, 0.95, 0.95))
	_box(lot, "frame", 0, 5.75, z0 + 8.0, Vector3(24.1, 0.35, 11.1), Color(0.95, 0.35, 0.05))
	_glow(lot, 0, 4.98, z0 + 8.0, Vector3(23.0, 0.05, 10.0), Color(1.0, 0.98, 0.95), 0.4)
	for x: float in [-4.5, 4.5]:
		_box(lot, "frame", x, 0.12, z0 + 8.0, Vector3(1.2, 0.25, 4.0), Color(0.6, 0.6, 0.6))
		for z: float in [-1.0, 1.0]:
			_box(lot, "frame", x, 1.15, z0 + 8.0 + z, Vector3(0.8, 1.8, 0.6), Color(0.95, 0.4, 0.05), true)
			_glow(lot, x, 1.6, z0 + 8.0 + z - 0.31, Vector3(0.6, 0.4, 0.02), Color(0.6, 0.9, 1.0), 0.4)
	for k in 2:
		light.call(_p(lot, -5.0 + k * 10.0, 4.6, z0 + 8.0), Color(1.0, 0.97, 0.92), 16.0, 2.6, 0)
	_box(lot, "frame", -13.0, 3.0, z0 + 1.0, Vector3(1.6, 6.0, 0.5), Color(0.95, 0.4, 0.05), true)
	_sign(lot, -13.0, 4.6, z0 + 0.7, Vector3(1.5, 0.6, 0.06), CityAtlas.shop(12), 1.0)
	if scenery.details:
		scenery.details.add_parked_car(Transform3D(_b(lot), _p(lot, -4.5, 0, z0 + 10.5)))
	# the kiosk at the back
	if float(lot["d"]) > 24.0:
		var kz := z0 + 20.0
		_box(lot, "frame", 4.0, 2.1, kz, Vector3(12.0, 4.2, 6.0), Color(0.95, 0.95, 0.94), true)
		_glow(lot, 4.0, 1.5, kz - 3.03, Vector3(10.0, 2.4, 0.05), Color(1.0, 0.98, 0.92), 0.5)


func _bowling(lot: Dictionary) -> void:
	var w: float = minf(lot["w"], 40.0)
	var d: float = minf(lot["d"], 26.0)
	var z0: float = -float(lot["d"]) * 0.5
	_box(lot, "frame", 0, 5.5, z0 + d * 0.5, Vector3(w, 11.0, d), Color(0.88, 0.86, 0.9), true)
	_glow(lot, 0, 1.5, z0 - 0.03, Vector3(w * 0.75, 2.6, 0.05), Color(1.0, 0.95, 0.85), 0.5)
	var prof := [Vector2(0.0, 0.0), Vector2(1.6, 0.0), Vector2(2.4, 2.5), Vector2(2.5, 4.0), Vector2(1.7, 6.5), Vector2(1.0, 8.0),
		Vector2(1.2, 9.3), Vector2(1.3, 10.3), Vector2(0.9, 11.4), Vector2(0.0, 11.8)]
	var base := _p(lot, w * 0.25, 11.0, z0 + d * 0.5)
	for k in prof.size() - 1:
		var col := Color(0.85, 0.08, 0.08) if k == 5 else Color(0.96, 0.96, 0.95)
		var p0: Vector2 = prof[k]
		var p1: Vector2 = prof[k + 1]
		for j in 18:
			var a0 := TAU * j / 18.0
			var a1 := TAU * (j + 1) / 18.0
			var v00 := base + Vector3(cos(a0) * p0.x, p0.y, sin(a0) * p0.x)
			var v01 := base + Vector3(cos(a1) * p0.x, p0.y, sin(a1) * p0.x)
			var v10 := base + Vector3(cos(a0) * p1.x, p1.y, sin(a0) * p1.x)
			var v11 := base + Vector3(cos(a1) * p1.x, p1.y, sin(a1) * p1.x)
			var nn := Vector3(cos((a0 + a1) * 0.5), 0.2, sin((a0 + a1) * 0.5)).normalized()
			cm.quad("frame", v00, v01, v11, v10, nn, col)
	_sign(lot, -w * 0.15, 13.0, z0 + 2.0, Vector3(16.0, 2.6, 0.3), CityAtlas.shop(9), 1.0)
	_glow(lot, -w * 0.15, 14.5, z0 + 1.8, Vector3(16.4, 0.12, 0.12), Color(1.0, 0.2, 0.6), 0.6)
	_glow(lot, -w * 0.15, 11.5, z0 + 1.8, Vector3(16.4, 0.12, 0.12), Color(1.0, 0.2, 0.6), 0.6)
	_people(lot, 10, -w * 0.3, w * 0.3, z0 - 3.0, z0 - 0.8, z0)
	light.call(_p(lot, -w * 0.15, 11.0, z0 - 3.0), Color(1.0, 0.3, 0.7), 20.0, 2.2, 0)
	light.call(_p(lot, 0, 3.0, z0 - 2.0), Color(1.0, 0.95, 0.85), 12.0, 1.8, 0)


func _police(lot: Dictionary) -> void:
	var z0: float = -float(lot["d"]) * 0.5
	var c := 17.0
	var h := 92.0
	var stone := Color(0.78, 0.74, 0.66)
	_box(lot, "frame", 0, 4.5, z0 + c, Vector3(36.0, 9.0, 30.0), stone, true)
	_glow(lot, 0, 2.2, z0 + c - 15.03, Vector3(20.0, 3.6, 0.05), Color(1.0, 0.95, 0.85), 0.4)
	_box(lot, "frame", 0, h * 0.5 + 9.0, z0 + c + 2.0, Vector3(26.0, h - 9.0, 22.0), Color(0.72, 0.7, 0.66), true)
	# windows: glass bands all round the tower
	var t := Transform3D(_b(lot), _p(lot, 0, 9.0, z0 + c + 2.0))
	var faces := [[_p(lot, 0, 9.0, z0 + c + 2.0 - 11.0), -(lot["az"] as Vector3), 26.0], [_p(lot, 0, 9.0, z0 + c + 13.0), (lot["az"] as Vector3), 26.0],
		[_p(lot, -13.0, 9.0, z0 + c + 2.0), -(lot["ax"] as Vector3), 22.0], [_p(lot, 13.0, 9.0, z0 + c + 2.0), (lot["ax"] as Vector3), 22.0]]
	for f in faces:
		var cf: Vector3 = f[0]
		var n: Vector3 = f[1]
		var fw: float = f[2]
		var u := Vector3.UP.cross(n)
		var o := cf - u * fw * 0.5 + n * 0.02
		cm.quad("glass", o, o + u * fw, o + u * fw + Vector3(0, h - 12.0, 0), o + Vector3(0, h - 12.0, 0), n, Color(0.7, 0.55, 0.3, 0.0),
			Vector2(0, 9.0), Vector2(fw, 9.0), Vector2(fw, h - 3.0), Vector2(0, h - 3.0))
		for y in range(0, int((h - 12.0) / 3.8)):
			cm.box("frame", Transform3D(Basis(u, Vector3.UP, n), cf + Vector3(0, y * 3.8 + 0.3, 0) + n * 0.15), Vector3(fw + 0.2, 0.6, 0.3), Color(0.72, 0.7, 0.66))
	t = t
	_box(lot, "frame", 0, h + 4.0, z0 + c + 2.0, Vector3(20.0, 8.0, 16.0), stone)
	_box(lot, "frame", 0, h + 13.0, z0 + c + 2.0, Vector3(9.0, 10.0, 9.0), stone)
	_box(lot, "metal", 0, h + 31.0, z0 + c + 2.0, Vector3(0.8, 26.0, 0.8), Color(0.8, 0.8, 0.82, 0.4))
	_glow(lot, 0, h + 44.5, z0 + c + 2.0, Vector3(1.0, 1.0, 1.0), Color(1.0, 0.1, 0.05), 0.8)
	_sign(lot, 0, 7.0, z0 + c - 15.2, Vector3(12.0, 1.6, 0.1), CityAtlas.shop(11), 0.8)
	_glow(lot, 0, 12.5, z0 + c - 11.1, Vector3(1.6, 1.6, 0.1), Color(1.0, 0.8, 0.2), 0.6)
	if scenery.details:
		for k in 5:
			scenery.details.add_parked_car(Transform3D(_b(lot).rotated(Vector3.UP, PI * 0.5), _p(lot, -10.0 + k * 3.2, 0, z0 + 1.5)), "car_sedan")
	for x: float in [-6.0, 6.0]:
		_box(lot, "metal", x, 1.5, z0 - 0.5, Vector3(0.2, 3.0, 0.2), Color(0.3, 0.3, 0.32, 0.5))
		_glow(lot, x, 3.2, z0 - 0.5, Vector3(0.4, 0.4, 0.4), Color(0.2, 0.4, 1.0), 0.6)
	light.call(_p(lot, 0, 4.0, z0 - 3.0), Color(0.9, 0.95, 1.0), 16.0, 2.2, 0)


## Karaoke / pachinko: a hall covered in neon – glowing bands, a huge sign, flashing borders.
func _neon_hall(lot: Dictionary, sign_cell: int) -> void:
	var w: float = minf(lot["w"], 22.0)
	var d: float = minf(lot["d"], 18.0)
	var z0: float = -float(lot["d"]) * 0.5
	var h := rng.randf_range(12.0, 18.0)
	_box(lot, "frame", 0, h * 0.5, z0 + d * 0.5, Vector3(w, h, d), Color(0.12, 0.1, 0.14), true)
	var cols := [Color(1.0, 0.2, 0.6), Color(0.2, 0.8, 1.0), Color(1.0, 0.85, 0.2), Color(0.6, 0.3, 1.0), Color(0.3, 1.0, 0.5)]
	var y := 4.0
	var k := 0
	while y < h - 1.0:
		_glow(lot, 0, y, z0 - 0.05, Vector3(w, 0.25, 0.08), cols[k % cols.size()], 0.8)
		y += rng.randf_range(1.2, 2.2)
		k += 1
	for x: float in [-w * 0.5, w * 0.5]:
		_glow(lot, x, h * 0.5, z0 - 0.05, Vector3(0.25, h, 0.1), cols[(k + 1) % cols.size()], 0.8)
	_sign(lot, 0, h - 3.0, z0 - 0.25, Vector3(minf(w - 2.0, 14.0), 3.0, 0.2), CityAtlas.shop(sign_cell), 1.0)
	_glow(lot, 0, 1.6, z0 - 0.03, Vector3(w * 0.6, 3.0, 0.05), Color(1.0, 0.85, 0.6), 0.6)
	for kk in 3:
		cm.sign_box(Transform3D(Basis(-(lot["az"] as Vector3), Vector3.UP, (lot["ax"] as Vector3)), _p(lot, w * 0.5 + 0.6, 5.0 + kk * 3.6, z0 + 0.6)), Vector3(1.2, 3.2, 0.2), CityAtlas.blade(3 if sign_cell == 13 else 11), 1.0, true)
	_people(lot, 8, -w * 0.4, w * 0.4, z0 - 3.0, z0 - 0.8, z0)
	light.call(_p(lot, 0, 4.0, z0 - 3.0), cols[0], 14.0, 2.0, 0)
	light.call(_p(lot, 0, h - 3.0, z0 - 4.0), cols[1], 16.0, 1.6, 0)

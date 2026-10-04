extends Node3D
## Life in the Utah desert round the track: a gas station, a motel with its neon sign, a diner,
## ranch shacks and barns, water towers, windpumps turning in the wind, nodding oil pump jacks,
## rusty wrecks, roadside billboards, a radio mast with its red light, telephone poles with
## wires along the road, ranch fences – and red stones lying about everywhere.
## Every building stands on levelled ground, solid (box collision), lit at night.

const MeshKit = preload("res://scripts/util/mesh_kit.gd")
const TexKit = preload("res://scripts/util/tex_kit.gd")
const Colliders = preload("res://scripts/util/colliders.gd")
const TreeFactory = preload("res://scripts/world/tree_factory.gd")

var track
var terrain
var scenery
var rect: Rect2
var rng := RandomNumberGenerator.new()
var stats := {}
var _mat: StandardMaterial3D          # vertex colours, matt
var _metal: StandardMaterial3D        # vertex colours, a bit of sheen
var _spinners: Array = []             # [node, axis, speed]
var _jacks: Array = []                # [beam node, phase]
var _blink: Array = []                # [material, phase]
var _t := 0.0
var ranch_xf = null                    # where the ranch stands (+Z: its gate side)


func build(p_track, p_terrain, p_scenery, p_rect: Rect2) -> void:
	track = p_track
	terrain = p_terrain
	scenery = p_scenery
	rect = p_rect
	rng.seed = 9137
	_mat = StandardMaterial3D.new()
	_mat.vertex_color_use_as_albedo = true
	_mat.roughness = 0.9
	_metal = StandardMaterial3D.new()
	_metal.vertex_color_use_as_albedo = true
	_metal.roughness = 0.45
	_metal.metallic = 0.5
	# round the lake: the buildings line the ring road, facing it
	var wt = track.water
	if wt != null:
		_gas_station(_ring_slot(0.0, 9.0, 20.0))
		_diner(_ring_slot(120.0, 4.0, 13.0))
		_motel(_ring_slot(195.0, 7.0, 22.0))
		for a in [50.0, 70.0, 165.0, 265.0, 285.0, 335.0]:
			_shack(_ring_slot(a, 5.0, 7.0))
		for i in 3:
			_shack()
	else:
		_gas_station()
		_motel()
		_diner()
		for i in 9:
			_shack()
	for i in 3:
		_barn()
	_ranch()
	await Game.load_tick()
	for i in 3:
		_water_tower()
	for i in 7:
		_windpump()
	for i in 6:
		_pump_jack()
	for i in 12:
		_wreck()
	_radio_mast()
	await Game.load_tick()
	_billboards()
	_telephone_line()
	_fences()
	await Game.load_tick()
	_red_stones()
	print("DESERT TOWN: %s" % str(stats))


## In the lake or a river, on the ring road (or within `margin` of them).
func _wet(x: float, z: float, margin: float) -> bool:
	var wt = track.water
	return wt != null and (wt.wet(x, z, margin) or wt.ring_band(x, z, margin) or Vector2(x, z).distance_to(wt.center) < wt.ring_r)


func _count(key: String) -> void:
	stats[key] = int(stats.get(key, 0)) + 1


# ---------------------------------------------------------------------------
# Placement
# ---------------------------------------------------------------------------
## A building plot: `radius` free, between `near` and `far` metres from the road's edge. The
## ground is levelled there. Returns its transform (facing the road) or null.
func _site(radius: float, near: float, far: float, tries := 40) -> Variant:
	var hw: float = track.half_w
	for _t2 in tries:
		var x := rng.randf_range(rect.position.x + radius + 10.0, rect.end.x - radius - 10.0)
		var z := rng.randf_range(rect.position.y + radius + 10.0, rect.end.y - radius - 10.0)
		var d: float = terrain.distance_to_road(x, z) - hw
		if d < near + radius or d > far + radius:
			continue
		var p := Vector3(x, 0, z)
		if not scenery.free_at(p, radius, 0.0) or _wet(x, z, radius + 4.0):
			continue
		scenery.occupy(p, radius)
		p.y = terrain.flatten(p, radius, 7.0)
		var i: int = track.nearest_index(p)
		var to: Vector3 = track.samples[i] - p
		to.y = 0.0
		var b := Basis.looking_at(-to.normalized(), Vector3.UP) if to.length() > 0.5 else Basis.IDENTITY
		return Transform3D(b, p)      # +Z faces the road
	return null


## A plot on the outside of the lake's ring road at `deg` round the lake, its front `front` metres
## from its origin, facing the ring; the ground levelled.
func _ring_slot(deg: float, front: float, radius: float) -> Transform3D:
	var wt = track.water
	var a := deg_to_rad(deg)
	var dir := Vector2(cos(a), sin(a))
	var r: float = wt.ring_r + wt.ring_w * 0.5 + 3.0 + front
	var c: Vector2 = wt.center + dir * r
	var p := Vector3(c.x, 0, c.y)
	scenery.occupy(p, radius)
	# exactly the terrace's height (the ring road runs along the front)
	terrain.level_to(p, radius * 0.8, 5.0, float(wt.plateau))
	p.y = float(wt.plateau)
	var to := Vector3(-dir.x, 0, -dir.y)
	return Transform3D(Basis.looking_at(-to, Vector3.UP), p)


func _mesh(st: SurfaceTool, xf: Transform3D, metal := false, shadows := true) -> MeshInstance3D:
	st.generate_normals()
	var mi := MeshKit.mesh_instance(MeshKit.commit(st, _metal if metal else _mat), null, shadows)
	mi.visibility_range_end = 1200.0
	add_child(mi)
	mi.global_transform = xf
	return mi


## A box in the building's frame, drawn and (optionally) solid.
func _part(st: SurfaceTool, xf: Transform3D, c: Vector3, size: Vector3, col: Color, solid := true, rot := 0.0) -> void:
	var lx := Transform3D(Basis(Vector3.UP, rot), c)
	MeshKit.box(st, lx, size, col)
	if solid:
		Colliders.add_box(self, xf * lx, size)


## A pitched roof over a w x d footprint at height h (ridge along x).
func _roof(st: SurfaceTool, c: Vector3, w: float, d: float, rise: float, col: Color) -> void:
	var h := w * 0.5 + 0.3
	var e := d * 0.5 + 0.4
	var a := c + Vector3(-h, 0, -e)
	var b := c + Vector3(h, 0, -e)
	var cc := c + Vector3(h, 0, e)
	var dd := c + Vector3(-h, 0, e)
	var r0 := c + Vector3(-h, rise, 0)
	var r1 := c + Vector3(h, rise, 0)
	MeshKit.quad(st, a, b, r1, r0, Vector3(0, 0.7, -0.7), Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, col)
	MeshKit.quad(st, cc, dd, r0, r1, Vector3(0, 0.7, 0.7), Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, col)
	for s in [-1.0, 1.0]:
		var p0 := c + Vector3(h * s, 0, -e)
		var p1 := c + Vector3(h * s, 0, e)
		var p2 := c + Vector3(h * s, rise, 0)
		var nn := Vector3(s, 0, 0)
		MeshKit.tri(st, p0, p1, p2, nn, nn, nn, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, nn, col)


func _label(text: String, xf: Transform3D, size: int, col: Color, outline := Color(0, 0, 0, 0.8)) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.01
	l.modulate = col
	l.outline_modulate = outline
	l.outline_size = 8
	l.double_sided = false
	add_child(l)
	l.global_transform = xf
	return l


func _glow(col: Color, day: float, night: float) -> StandardMaterial3D:
	var m := TexKit.std(col, 0.4, 0.0, col, day)
	scenery._glow_mats.append([m, day, night])
	return m


func _night_light(pos: Vector3, col: Color, energy: float, rng_m: float) -> void:
	var l := OmniLight3D.new()
	l.light_color = col
	l.omni_range = rng_m
	l.light_energy = energy
	l.shadow_enabled = false
	add_child(l)
	l.global_position = pos
	l.visible = false
	scenery._night_lights.append([l, energy])


# ---------------------------------------------------------------------------
# Buildings
# ---------------------------------------------------------------------------
func _gas_station(xf = null) -> void:
	if xf == null:
		xf = _site(22.0, 10.0, 30.0)
	if xf == null:
		return
	var st := MeshKit.new_st()
	var white := Color(0.85, 0.83, 0.78)
	var red := Color(0.7, 0.1, 0.08)
	# the shop at the back, the canopy over the pumps in front
	_part(st, xf, Vector3(0, 2.0, -9.0), Vector3(14.0, 4.0, 7.0), white)
	_part(st, xf, Vector3(0, 4.15, -9.0), Vector3(14.6, 0.3, 7.6), red, false)
	_part(st, xf, Vector3(-3.0, 1.6, -5.45), Vector3(5.0, 2.2, 0.1), Color(0.15, 0.22, 0.28), false)     # window
	_part(st, xf, Vector3(3.5, 1.2, -5.45), Vector3(1.6, 2.4, 0.1), Color(0.25, 0.18, 0.12), false)      # door
	_part(st, xf, Vector3(0, 5.2, 2.0), Vector3(16.0, 0.7, 9.0), white, false)                            # canopy
	_part(st, xf, Vector3(0, 4.75, 2.0), Vector3(16.2, 0.25, 9.2), red, false)
	for px in [-6.5, 6.5]:
		for pz in [-1.5, 5.5]:
			_part(st, xf, Vector3(px, 1.9, pz), Vector3(0.35, 5.8, 0.35), white)
	for px in [-3.5, 0.0, 3.5]:
		_part(st, xf, Vector3(px, -0.2, 2.0), Vector3(1.2, 1.0, 4.0), Color(0.5, 0.5, 0.48))                 # island
		_part(st, xf, Vector3(px, 1.0, 2.0), Vector3(0.7, 1.6, 0.5), red)                                    # pump
	# the price sign on a pole by the road
	_part(st, xf, Vector3(9.5, 3.5, 7.6), Vector3(0.35, 9.0, 0.35), Color(0.4, 0.4, 0.4))      # (behind the sign, into the ground)
	_part(st, xf, Vector3(9.5, 7.6, 8.0), Vector3(3.2, 2.2, 0.3), red, false)
	_mesh(st, xf)
	_label("GAS\n$ 3.99", xf * Transform3D(Basis.IDENTITY, Vector3(9.5, 7.6, 8.17)), 64, Color(1, 0.95, 0.8))
	_label("DESERT FUEL", xf * Transform3D(Basis.IDENTITY, Vector3(0, 5.2, 6.52)), 90, Color(0.75, 0.08, 0.06), Color(1, 1, 1, 0.9))
	var lamp := _glow(Color(1.0, 0.95, 0.85), 0.0, 2.5)
	var lights := MeshKit.box_node(Vector3(12.0, 0.05, 6.0), lamp)
	add_child(lights)
	lights.global_transform = xf * Transform3D(Basis.IDENTITY, Vector3(0, 4.82, 2.0))
	_night_light(xf * Vector3(0, 4.0, 2.0), Color(1.0, 0.93, 0.8), 2.5, 16.0)
	_count("gas_station")


func _motel(xf = null) -> void:
	if xf == null:
		xf = _site(24.0, 12.0, 40.0)
	if xf == null:
		return
	var st := MeshKit.new_st()
	var wall := Color(0.82, 0.62, 0.46)
	var trim := Color(0.2, 0.45, 0.5)
	# an L of rooms: the long wing and a short one, doors and windows along the front
	_part(st, xf, Vector3(0, 1.6, -6.0), Vector3(30.0, 3.2, 7.0), wall)
	_part(st, xf, Vector3(-12.0, 1.6, 2.0), Vector3(6.0, 3.2, 9.0), wall)
	_part(st, xf, Vector3(0, 3.35, -6.0), Vector3(31.0, 0.3, 8.6), trim, false)
	_part(st, xf, Vector3(-12.0, 3.35, 2.0), Vector3(7.0, 0.3, 10.0), trim, false)
	for k in 8:
		var x := -9.0 + k * 3.2
		_part(st, xf, Vector3(x, 1.1, -2.45), Vector3(1.0, 2.2, 0.1), trim, false)
		_part(st, xf, Vector3(x + 1.2, 1.6, -2.45), Vector3(0.9, 0.9, 0.1), Color(0.95, 0.85, 0.5), false)
	# the tall sign
	_part(st, xf, Vector3(14.0, 4.5, 6.0), Vector3(0.4, 9.0, 0.4), Color(0.35, 0.35, 0.35))
	_part(st, xf, Vector3(14.0, 8.0, 6.0), Vector3(5.0, 2.4, 0.4), trim, false)
	_mesh(st, xf)
	var neon := _glow(Color(1.0, 0.25, 0.4), 0.4, 4.0)
	var bar := MeshKit.box_node(Vector3(4.6, 0.12, 0.1), neon)
	add_child(bar)
	bar.global_transform = xf * Transform3D(Basis.IDENTITY, Vector3(14.0, 6.7, 6.25))
	_label("MOTEL", xf * Transform3D(Basis.IDENTITY, Vector3(14.0, 8.2, 6.22)), 110, Color(1.0, 0.45, 0.55))
	_label("VACANCY", xf * Transform3D(Basis.IDENTITY, Vector3(14.0, 7.3, 6.22)), 48, Color(0.5, 1.0, 0.7))
	_night_light(xf * Vector3(14.0, 7.5, 7.0), Color(1.0, 0.35, 0.5), 2.0, 12.0)
	_night_light(xf * Vector3(0, 2.8, -1.0), Color(1.0, 0.85, 0.6), 1.2, 14.0)
	_count("motel")


func _diner(xf = null) -> void:
	if xf == null:
		xf = _site(14.0, 10.0, 35.0)
	if xf == null:
		return
	var st := MeshKit.new_st()
	var steel := Color(0.78, 0.8, 0.82)
	_part(st, xf, Vector3(0, 1.8, 0), Vector3(16.0, 3.0, 5.5), steel)
	_part(st, xf, Vector3(0, 0.3, 0), Vector3(16.4, 0.6, 5.9), Color(0.25, 0.25, 0.27), false)
	_part(st, xf, Vector3(0, 2.1, 2.78), Vector3(13.0, 1.1, 0.06), Color(0.95, 0.85, 0.55), false)   # windows
	_part(st, xf, Vector3(0, 1.0, 2.79), Vector3(16.0, 0.25, 0.06), Color(0.75, 0.1, 0.1), false)  # red stripe
	_part(st, xf, Vector3(0, 3.45, 0), Vector3(16.0, 0.3, 4.0), steel, false)
	_mesh(st, xf, true)
	_label("DINER", xf * Transform3D(Basis.IDENTITY, Vector3(0, 4.3, 0.2)), 120, Color(0.4, 0.95, 1.0))
	_night_light(xf * Vector3(0, 3.5, 4.0), Color(0.6, 0.95, 1.0), 1.5, 12.0)
	_count("diner")


func _shack(xf = null) -> void:
	if xf == null:
		xf = _site(7.0, 8.0, 120.0)
	if xf == null:
		return
	var st := MeshKit.new_st()
	var wood := Color(0.42, 0.3, 0.2) * rng.randf_range(0.8, 1.15)
	wood.a = 1.0
	var w := rng.randf_range(5.0, 8.0)
	var d := rng.randf_range(4.0, 6.0)
	_part(st, xf, Vector3(0, 1.4, 0), Vector3(w, 2.8, d), wood)
	_roof(st, Vector3(0, 2.8, 0), w, d, 1.4, Color(0.45, 0.42, 0.4))
	_part(st, xf, Vector3(0, 1.0, d * 0.5 + 0.02), Vector3(1.0, 2.0, 0.06), Color(0.2, 0.14, 0.1), false)
	_part(st, xf, Vector3(w * 0.3, 1.6, d * 0.5 + 0.02), Vector3(0.9, 0.8, 0.06), Color(0.12, 0.14, 0.16), false)
	# a porch
	_part(st, xf, Vector3(0, 0.15, d * 0.5 + 1.0), Vector3(w, 0.3, 2.0), wood * 0.85, false)
	for s in [-1.0, 1.0]:
		_part(st, xf, Vector3(s * (w * 0.5 - 0.2), 1.3, d * 0.5 + 1.9), Vector3(0.15, 2.3, 0.15), wood, false)
	_part(st, xf, Vector3(0, 2.5, d * 0.5 + 1.0), Vector3(w, 0.1, 2.2), Color(0.45, 0.42, 0.4), false)
	_mesh(st, xf)
	# a barrel or two
	for k in rng.randi_range(1, 3):
		var b := MeshKit.cyl_node(0.3, 0.3, 0.9, TexKit.std(Color(0.45, 0.2, 0.1), 0.7, 0.3), Vector3.ZERO, Vector3.ZERO, 12)
		add_child(b)
		b.global_position = xf * Vector3(w * 0.5 + 0.6, 0.45, -d * 0.3 + k * 0.7)
	if rng.randf() < 0.6:
		_night_light(xf * Vector3(0, 2.2, d * 0.5 + 1.2), Color(1.0, 0.75, 0.45), 0.8, 8.0)
	_count("shacks")


## A big ranch: a fenced yard behind a log gate with its sign, the two-storey ranch house with a
## porch all round, a big red barn with a hayloft, a stable with its stalls, a round corral, grain
## silos, a windpump, a water tower, hay bales, a tractor and a water trough.
func _ranch() -> void:
	var xf = _site(46.0, 14.0, 260.0, 160)
	if xf == null:
		xf = _site(36.0, 10.0, 300.0, 160)
	if xf == null:
		return
	var half := 34.0
	ranch_xf = xf
	print("RANCH at ", (xf as Transform3D).origin)
	var st := MeshKit.new_st()
	var wood := Color(0.46, 0.34, 0.22)
	var log := Color(0.38, 0.27, 0.17)
	var white := Color(0.88, 0.86, 0.8)
	var red := Color(0.55, 0.12, 0.08)
	var roof := Color(0.32, 0.3, 0.3)
	var glass := Color(0.12, 0.15, 0.18)
	# --- the fence round the yard (posts, three rails), the gate in the front side ---
	var gate_w := 8.0
	for side in 4:
		var a: Vector3
		var b: Vector3
		match side:
			0: a = Vector3(-half, 0, half); b = Vector3(half, 0, half)
			1: a = Vector3(half, 0, half); b = Vector3(half, 0, -half)
			2: a = Vector3(half, 0, -half); b = Vector3(-half, 0, -half)
			_: a = Vector3(-half, 0, -half); b = Vector3(-half, 0, half)
		var n := int(a.distance_to(b) / 3.0)
		for k in n:
			var p0 := a.lerp(b, float(k) / n)
			var p1 := a.lerp(b, float(k + 1) / n)
			var mid := (p0 + p1) * 0.5
			if side == 0 and absf(mid.x) < gate_w * 0.5:
				continue
			MeshKit.box(st, Transform3D(Basis.IDENTITY, p0 + Vector3(0, 0.75, 0)), Vector3(0.2, 1.6, 0.2), wood)
			var dir := (p1 - p0).normalized()
			var rb := Basis(Vector3.UP, atan2(-dir.z, dir.x))
			for ry in [0.45, 0.85, 1.25]:
				MeshKit.box(st, Transform3D(rb, mid + Vector3(0, ry, 0)), Vector3(p0.distance_to(p1), 0.14, 0.07), wood * 0.92)
		# solid: one long box per side (the front in two, either side of the gate)
		if side == 0:
			for sx in [-1.0, 1.0]:
				var w := half - gate_w * 0.5
				Colliders.add_box(self, xf * Transform3D(Basis.IDENTITY, Vector3(sx * (gate_w * 0.5 + w * 0.5), 0.8, half)), Vector3(w, 1.6, 0.3))
		else:
			var c := (a + b) * 0.5
			var size := Vector3(absf(b.x - a.x) + 0.3, 1.6, absf(b.z - a.z) + 0.3)
			Colliders.add_box(self, xf * Transform3D(Basis.IDENTITY, c + Vector3(0, 0.8, 0)), size)
	# the log gate with the ranch's name
	for sx in [-1.0, 1.0]:
		_part(st, xf, Vector3(sx * (gate_w * 0.5 + 0.3), 3.2, half), Vector3(0.6, 6.4, 0.6), log)
	_part(st, xf, Vector3(0, 6.2, half), Vector3(gate_w + 2.4, 0.55, 0.55), log, false)
	_part(st, xf, Vector3(0, 5.2, half + 0.05), Vector3(6.4, 1.3, 0.12), Color(0.3, 0.2, 0.12), false)
	for sx in [-1.0, 1.0]:
		_part(st, xf, Vector3(sx * 2.6, 5.9, half + 0.05), Vector3(0.06, 0.5, 0.06), Color(0.2, 0.2, 0.2), false)
	# a cattle skull over the sign (a few boxes)
	_part(st, xf, Vector3(0, 6.75, half + 0.1), Vector3(0.5, 0.45, 0.2), white, false)
	_part(st, xf, Vector3(0, 6.85, half + 0.1), Vector3(1.6, 0.12, 0.12), white, false)
	for sx in [-1.0, 1.0]:
		_part(st, xf, Vector3(sx * 0.85, 7.0, half + 0.1), Vector3(0.1, 0.35, 0.1), white, false)
	_label("BROKEN SPUR RANCH", xf * Transform3D(Basis.IDENTITY, Vector3(0, 5.2, half + 0.12)), 64, Color(0.95, 0.8, 0.55), Color(0.1, 0.05, 0.02, 0.9))
	var back_l := _label("BROKEN SPUR RANCH", xf * Transform3D(Basis(Vector3.UP, PI), Vector3(0, 5.2, half - 0.06)), 64, Color(0.95, 0.8, 0.55), Color(0.1, 0.05, 0.02, 0.9))
	back_l.double_sided = false
	# the drive: packed dirt from the gate to the house
	_part(st, xf, Vector3(0, 0.02, half * 0.5 + 4.0), Vector3(5.0, 0.06, half - 6.0), Color(0.55, 0.42, 0.3), false)
	# --- the ranch house: two storeys, a porch all round on the ground floor, the roof over it ---
	var hc := Vector3(0, 0, 2.0)
	var hw := 16.0
	var hd := 10.0
	_part(st, xf, hc + Vector3(0, 3.2, 0), Vector3(hw, 6.4, hd), white)
	_part(st, xf, hc + Vector3(0, 0.2, 0), Vector3(hw + 5.0, 0.4, hd + 5.0), wood * 0.8, false)        # porch deck
	_part(st, xf, hc + Vector3(0, 3.1, 0), Vector3(hw + 5.0, 0.2, hd + 5.0), roof, false)              # porch roof
	for px in [-1.0, -0.5, 0.0, 0.5, 1.0]:
		for pz in [-1.0, 1.0]:
			_part(st, xf, hc + Vector3(px * (hw * 0.5 + 2.2), 1.65, pz * (hd * 0.5 + 2.2)), Vector3(0.22, 2.9, 0.22), white, false)
	for pz in [-0.5, 0.0, 0.5]:
		for px in [-1.0, 1.0]:
			_part(st, xf, hc + Vector3(px * (hw * 0.5 + 2.2), 1.65, pz * (hd * 0.5 + 2.2)), Vector3(0.22, 2.9, 0.22), white, false)
	# the railing along the porch's front, open at the steps
	for sx in [-1.0, 1.0]:
		_part(st, xf, hc + Vector3(sx * (hw * 0.25 + 2.0), 1.0, hd * 0.5 + 2.4), Vector3(hw * 0.5 - 1.0, 0.1, 0.1), white, false)
	_part(st, xf, hc + Vector3(0, 0.1, hd * 0.5 + 3.0), Vector3(3.0, 0.2, 1.0), wood * 0.75, false)      # steps
	# windows (warm at night) and the front door
	var win := _glow(Color(1.0, 0.82, 0.5), 0.05, 1.8)
	var wst := MeshKit.new_st()
	for fl in [1.6, 4.6]:
		for wx in [-6.0, -3.5, 3.5, 6.0]:
			MeshKit.box(wst, Transform3D(Basis.IDENTITY, hc + Vector3(wx, fl, hd * 0.5 + 0.03)), Vector3(1.2, 1.4, 0.05), Color.WHITE)
			MeshKit.box(wst, Transform3D(Basis.IDENTITY, hc + Vector3(wx, fl, -hd * 0.5 - 0.03)), Vector3(1.2, 1.4, 0.05), Color.WHITE)
		for wz in [-2.5, 2.5]:
			for sx in [-1.0, 1.0]:
				MeshKit.box(wst, Transform3D(Basis.IDENTITY, hc + Vector3(sx * (hw * 0.5 + 0.03), fl, wz)), Vector3(0.05, 1.4, 1.2), Color.WHITE)
	MeshKit.box(wst, Transform3D(Basis.IDENTITY, hc + Vector3(0, 4.6, hd * 0.5 + 0.03)), Vector3(1.2, 1.4, 0.05), Color.WHITE)
	wst.generate_normals()
	var wmi := MeshKit.mesh_instance(MeshKit.commit(wst, win), null, false)
	add_child(wmi)
	wmi.global_transform = xf
	for wx in [-6.0, -3.5, 3.5, 6.0]:
		for fl in [1.6, 4.6]:
			_part(st, xf, hc + Vector3(wx, fl, hd * 0.5 + 0.06), Vector3(1.45, 0.12, 0.06), Color(0.25, 0.32, 0.3), false)
	_part(st, xf, hc + Vector3(0, 1.2, hd * 0.5 + 0.04), Vector3(1.3, 2.4, 0.06), Color(0.32, 0.18, 0.1), false)
	_mesh(st, xf)
	var hst := MeshKit.new_st()
	_roof(hst, Vector3.ZERO, hw, hd, 3.2, roof)
	_part(hst, xf, Vector3(5.0, 2.2, -1.5), Vector3(1.2, 4.0, 1.2), Color(0.5, 0.3, 0.22), false)       # chimney
	_mesh(hst, xf * Transform3D(Basis.IDENTITY, hc + Vector3(0, 6.4, 0)))
	_night_light(xf * (hc + Vector3(0, 2.7, hd * 0.5 + 2.0)), Color(1.0, 0.8, 0.5), 1.6, 12.0)
	# rocking chairs and a bench on the porch
	var pst := MeshKit.new_st()
	for cx in [-4.5, -3.0, 4.0]:
		_part(pst, xf, hc + Vector3(cx, 0.65, hd * 0.5 + 1.2), Vector3(0.6, 0.08, 0.6), wood, false)
		_part(pst, xf, hc + Vector3(cx, 1.05, hd * 0.5 + 0.95), Vector3(0.6, 0.8, 0.08), wood, false)
		_part(pst, xf, hc + Vector3(cx, 0.4, hd * 0.5 + 1.2), Vector3(0.5, 0.45, 0.5), wood * 0.8, false)
	_mesh(pst, xf)
	# --- the big barn (doors to the yard), a hayloft door up in its gable ---
	var bxf: Transform3D = xf * Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(-20.0, 0, -14.0))
	var bst := MeshKit.new_st()
	_part(bst, bxf, Vector3(0, 4.0, 0), Vector3(14.0, 8.0, 22.0), red)
	# the white trim round the edges and the big doors with their X braces
	for c in [Vector3(-6.95, 4.0, 10.95), Vector3(6.95, 4.0, 10.95)]:
		_part(bst, bxf, c, Vector3(0.3, 8.0, 0.3), white, false)
	_part(bst, bxf, Vector3(0, 7.9, 11.02), Vector3(14.2, 0.3, 0.1), white, false)
	for dx in [-1.0, 1.0]:
		var dc := Vector3(dx * 2.0, 2.6, 11.03)
		_part(bst, bxf, dc, Vector3(3.8, 5.2, 0.08), Color(0.45, 0.1, 0.07), false)
		_part(bst, bxf, dc + Vector3(0, 0, 0.03), Vector3(3.9, 0.22, 0.05), white, false)
		_part(bst, bxf, dc + Vector3(0, 2.5, 0.03), Vector3(3.9, 0.22, 0.05), white, false)
		_part(bst, bxf, dc + Vector3(dx * 1.85, 0, 0.03), Vector3(0.22, 5.2, 0.05), white, false)
		_part(bst, bxf, dc + Vector3(0, 0, 0.04), Vector3(0.18, 6.2, 0.04), white, false, 0.62)
		_part(bst, bxf, dc + Vector3(0, 0, 0.04), Vector3(0.18, 6.2, 0.04), white, false, -0.62)
	_part(bst, bxf, Vector3(0, 9.3, 11.34), Vector3(2.4, 2.0, 0.08), Color(0.3, 0.08, 0.05), false)
	_part(bst, bxf, Vector3(0, 10.6, 11.6), Vector3(0.25, 0.25, 1.4), Color(0.35, 0.33, 0.3), false)     # hay hoist beam
	_mesh(bst, bxf)
	var brst := MeshKit.new_st()
	_roof(brst, Vector3.ZERO, 22.0, 14.0, 5.0, roof)
	_mesh(brst, bxf * Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(0, 8.0, 0)))
	_night_light(bxf * Vector3(0, 7.2, 12.0), Color(1.0, 0.85, 0.6), 1.4, 14.0)
	# --- the stable: a long low building, a stall door every 3 m, a lean-to roof ---
	var sxf: Transform3D = xf * Transform3D(Basis.IDENTITY, Vector3(16.0, 0, -24.0))
	var sst := MeshKit.new_st()
	_part(sst, sxf, Vector3(0, 1.8, 0), Vector3(24.0, 3.6, 7.0), wood)
	_part(sst, sxf, Vector3(0, 3.75, 1.2), Vector3(25.0, 0.25, 10.0), roof, false)
	for k in 8:
		var x := -10.5 + k * 3.0
		_part(sst, sxf, Vector3(x, 0.75, 3.52), Vector3(1.6, 1.5, 0.08), Color(0.3, 0.2, 0.12), false)
		_part(sst, sxf, Vector3(x, 2.2, 3.52), Vector3(1.6, 1.2, 0.04), Color(0.06, 0.05, 0.04), false)
		_part(sst, sxf, Vector3(x, 0.75, 3.57), Vector3(1.5, 0.12, 0.04), white, false, 0.75)
	for k in 5:
		_part(sst, sxf, Vector3(-12.0 + k * 6.0, 1.8, 6.0), Vector3(0.2, 3.6, 0.2), wood * 0.9, false)
	_mesh(sst, sxf)
	# --- the round corral: posts in a ring, three rails ---
	var cc := Vector3(19.0, 0, 14.0)
	var cr := 9.0
	var cst := MeshKit.new_st()
	var segs := 22
	for k in segs:
		var a0 := TAU * k / segs
		var a1 := TAU * (k + 1) / segs
		var p0 := cc + Vector3(cos(a0), 0, sin(a0)) * cr
		var p1 := cc + Vector3(cos(a1), 0, sin(a1)) * cr
		var mid := (p0 + p1) * 0.5
		var rb := Basis(Vector3.UP, -(a0 + a1) * 0.5 + PI * 0.5)
		MeshKit.box(cst, Transform3D(Basis.IDENTITY, p0 + Vector3(0, 0.8, 0)), Vector3(0.22, 1.7, 0.22), log)
		for ry in [0.5, 0.95, 1.4]:
			MeshKit.box(cst, Transform3D(rb, mid + Vector3(0, ry, 0)), Vector3(p0.distance_to(p1) + 0.05, 0.14, 0.08), wood)
		Colliders.add_box(self, xf * Transform3D(rb, mid + Vector3(0, 0.8, 0)), Vector3(p0.distance_to(p1) + 0.1, 1.6, 0.3))
	# sand inside, a water trough by it
	MeshKit.box(cst, Transform3D(Basis.IDENTITY, cc + Vector3(0, 0.02, 0)), Vector3(cr * 1.7, 0.05, cr * 1.7), Color(0.72, 0.6, 0.45))
	_mesh(cst, xf)
	var tst := MeshKit.new_st()
	_part(tst, xf, cc + Vector3(-cr - 2.5, 0.4, 0), Vector3(1.0, 0.8, 3.0), Color(0.45, 0.47, 0.5))
	_mesh(tst, xf, true)
	var water := MeshKit.box_node(Vector3(0.8, 0.02, 2.8), TexKit.std(Color(0.2, 0.35, 0.4), 0.05, 0.0))
	add_child(water)
	water.global_transform = xf * Transform3D(Basis.IDENTITY, cc + Vector3(-cr - 2.5, 0.75, 0))
	# --- grain silos with domed tops ---
	var silo_mat := TexKit.std(Color(0.72, 0.72, 0.7), 0.35, 0.6)
	for sp in [Vector3(-27.0, 0, -28.0), Vector3(-20.5, 0, -29.0)]:
		var silo := MeshKit.cyl_node(2.8, 2.8, 13.0, silo_mat, Vector3.ZERO, Vector3.ZERO, 24)
		add_child(silo)
		silo.global_transform = xf * Transform3D(Basis.IDENTITY, sp + Vector3(0, 6.5, 0))
		var dome := MeshKit.cyl_node(0.4, 2.9, 1.8, silo_mat, Vector3.ZERO, Vector3.ZERO, 24)
		add_child(dome)
		dome.global_transform = xf * Transform3D(Basis.IDENTITY, sp + Vector3(0, 13.9, 0))
		Colliders.add_box(self, xf * Transform3D(Basis.IDENTITY, sp + Vector3(0, 6.5, 0)), Vector3(4.6, 13.0, 4.6))
	# --- a windpump and a water tower inside the fence ---
	_windpump(xf * Transform3D(Basis.IDENTITY, Vector3(-26.0, 0, 22.0)))
	_water_tower(xf * Transform3D(Basis(Vector3.UP, PI * 0.25), Vector3(27.0, 0, -6.0)))
	# --- round hay bales (some stacked) and square ones by the barn ---
	var hay := TexKit.std(Color(0.78, 0.64, 0.32), 0.95, 0.0)
	for k in 9:
		var bp := Vector3(-9.0 + (k % 5) * 1.9, 0.75, -27.0 + (k / 5) * 2.2)
		var bale := MeshKit.cyl_node(0.75, 0.75, 1.4, hay, Vector3.ZERO, Vector3.ZERO, 16)
		add_child(bale)
		bale.global_transform = xf * Transform3D(Basis(Vector3.FORWARD, PI * 0.5), bp)
	Colliders.add_box(self, xf * Transform3D(Basis.IDENTITY, Vector3(-5.2, 0.75, -26.0)), Vector3(9.5, 1.5, 4.0))
	var sqst := MeshKit.new_st()
	for k in 10:
		var lvl := 0 if k < 5 else (1 if k < 8 else 2)
		var i := k if k < 5 else (k - 5 if k < 8 else k - 8)
		_part(sqst, xf, Vector3(-11.0 + i * 1.25 + lvl * 0.6, 0.3 + lvl * 0.6, -6.0), Vector3(1.2, 0.58, 0.8), Color(0.82, 0.7, 0.4) * rng.randf_range(0.9, 1.05), false)
	_mesh(sqst, xf)
	Colliders.add_box(self, xf * Transform3D(Basis.IDENTITY, Vector3(-8.5, 0.9, -6.0)), Vector3(6.4, 1.8, 0.9))
	# --- an old tractor in front of the barn ---
	var trxf: Transform3D = xf * Transform3D(Basis(Vector3.UP, 0.4), Vector3(-4.5, 0, -13.0))
	var trst := MeshKit.new_st()
	var green := Color(0.15, 0.4, 0.15)
	_part(trst, trxf, Vector3(0, 1.3, 0.6), Vector3(1.1, 0.9, 2.4), green)                                    # bonnet
	_part(trst, trxf, Vector3(0, 1.6, -1.0), Vector3(1.4, 0.3, 1.0), green, false)                         # seat deck
	_part(trst, trxf, Vector3(0, 2.05, -1.2), Vector3(0.5, 0.15, 0.5), Color(0.1, 0.1, 0.1), false)        # seat
	_part(trst, trxf, Vector3(0.15, 2.3, 0.4), Vector3(0.12, 1.2, 0.12), Color(0.2, 0.2, 0.2), false)      # exhaust
	_part(trst, trxf, Vector3(0, 1.9, -0.3), Vector3(0.06, 0.6, 0.06), Color(0.2, 0.2, 0.2), false, 0.5)   # wheel column
	_mesh(trst, trxf)
	var tyre := TexKit.std(Color(0.08, 0.08, 0.08), 0.9, 0.0)
	var rim := TexKit.std(Color(0.85, 0.7, 0.15), 0.5, 0.3)
	for w in [[Vector3(-0.95, 0.85, -1.0), 0.85, 0.5], [Vector3(0.95, 0.85, -1.0), 0.85, 0.5], [Vector3(-0.75, 0.45, 1.4), 0.45, 0.3], [Vector3(0.75, 0.45, 1.4), 0.45, 0.3]]:
		var t := MeshKit.cyl_node(w[1], w[1], w[2], tyre, Vector3.ZERO, Vector3.ZERO, 18)
		add_child(t)
		t.global_transform = trxf * Transform3D(Basis(Vector3.FORWARD, PI * 0.5), w[0])
		var hub := MeshKit.cyl_node(float(w[1]) * 0.55, float(w[1]) * 0.55, float(w[2]) + 0.02, rim, Vector3.ZERO, Vector3.ZERO, 14)
		add_child(hub)
		hub.global_transform = t.global_transform
	_count("ranch")


func _barn() -> void:
	var xf = _site(12.0, 20.0, 150.0)
	if xf == null:
		return
	var st := MeshKit.new_st()
	var red := Color(0.5, 0.12, 0.08)
	_part(st, xf, Vector3(0, 3.0, 0), Vector3(10.0, 6.0, 14.0), red, true, PI * 0.5)
	# the roof runs along the long side
	var rst := MeshKit.new_st()
	_roof(rst, Vector3.ZERO, 14.0, 10.0, 3.5, Color(0.3, 0.3, 0.32))
	_part(st, xf, Vector3(0, 2.0, 5.02), Vector3(4.0, 4.0, 0.06), Color(0.85, 0.82, 0.75), false)
	_part(st, xf, Vector3(0, 2.0, 5.06), Vector3(3.6, 0.2, 0.04), red, false)
	_mesh(st, xf)
	_mesh(rst, xf * Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(0, 6.0, 0)))
	_count("barns")


func _water_tower(xf = null) -> void:
	if xf == null:
		xf = _site(6.0, 15.0, 200.0)
	if xf == null:
		return
	var st := MeshKit.new_st()
	var steel := Color(0.55, 0.52, 0.48)
	for s in [Vector2(-2, -2), Vector2(2, -2), Vector2(2, 2), Vector2(-2, 2)]:
		_part(st, xf, Vector3(s.x, 6.0, s.y), Vector3(0.35, 12.0, 0.35), steel)
	for y in [3.0, 7.0]:
		_part(st, xf, Vector3(0, y, 2), Vector3(4.2, 0.15, 0.15), steel, false)
		_part(st, xf, Vector3(0, y, -2), Vector3(4.2, 0.15, 0.15), steel, false)
		_part(st, xf, Vector3(2, y, 0), Vector3(0.15, 0.15, 4.2), steel, false)
		_part(st, xf, Vector3(-2, y, 0), Vector3(0.15, 0.15, 4.2), steel, false)
	_mesh(st, xf, true)
	var tank := MeshKit.cyl_node(3.2, 3.2, 4.5, TexKit.std(Color(0.75, 0.72, 0.66), 0.5, 0.4))
	add_child(tank)
	tank.global_transform = xf * Transform3D(Basis.IDENTITY, Vector3(0, 14.2, 0))
	var cone := MeshKit.cyl_node(0.2, 3.5, 1.6, TexKit.std(Color(0.55, 0.52, 0.48), 0.5, 0.4))
	add_child(cone)
	cone.global_transform = xf * Transform3D(Basis.IDENTITY, Vector3(0, 17.25, 0))
	_label("UTAH", xf * Transform3D(Basis.IDENTITY, Vector3(0, 14.4, 3.25)), 140, Color(0.35, 0.12, 0.08), Color(0, 0, 0, 0))
	_count("water_towers")


func _windpump(xf = null) -> void:
	if xf == null:
		xf = _site(3.0, 12.0, 200.0)
	if xf == null:
		return
	var st := MeshKit.new_st()
	var steel := Color(0.5, 0.48, 0.45)
	var h := rng.randf_range(9.0, 12.0)
	for s in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var base := Vector3(s.x * 1.4, 0, s.y * 1.4)
		var top := Vector3(s.x * 0.25, h, s.y * 0.25)
		var mid := (base + top) * 0.5
		var dir := (top - base).normalized()
		# the leg leans in: the box's up axis turned onto the leg
		var axis := Vector3.UP.cross(dir)
		var lean := Basis(axis.normalized(), acos(clampf(dir.y, -1.0, 1.0))) if axis.length() > 1e-4 else Basis.IDENTITY
		MeshKit.box(st, Transform3D(lean, mid), Vector3(0.14, (top - base).length(), 0.14), steel)
	Colliders.add_box(self, xf * Transform3D(Basis.IDENTITY, Vector3(0, 1.5, 0)), Vector3(2.4, 3.0, 2.4))
	_mesh(st, xf, true)
	# the wheel of blades and the tail vane, turning in the wind
	var head := Node3D.new()
	add_child(head)
	head.global_transform = xf * Transform3D(Basis.IDENTITY, Vector3(0, h + 0.3, 0))
	var hst := MeshKit.new_st()
	for k in 14:
		var a := TAU * k / 14.0
		var bx := Transform3D(Basis(Vector3.FORWARD, a) * Basis(Vector3.UP, 0.35), Vector3(cos(a + PI * 0.5) * -1.05, sin(a + PI * 0.5) * 1.05, 0))
		MeshKit.box(hst, bx, Vector3(0.28, 1.5, 0.03), Color(0.75, 0.73, 0.7))
	hst.generate_normals()
	var wheel := MeshKit.mesh_instance(MeshKit.commit(hst, _metal))
	head.add_child(wheel)
	wheel.position = Vector3(0, 0, 0.6)
	var vane := MeshKit.box_node(Vector3(0.05, 1.0, 1.8), TexKit.std(Color(0.7, 0.68, 0.64), 0.5, 0.4))
	head.add_child(vane)
	vane.position = Vector3(0, 0, -1.2)
	_spinners.append([wheel, Vector3.FORWARD, rng.randf_range(1.2, 2.4)])
	_count("windpumps")


func _pump_jack() -> void:
	var xf = _site(6.0, 15.0, 180.0)
	if xf == null:
		return
	var st := MeshKit.new_st()
	var dark := Color(0.18, 0.18, 0.2)
	var steel := Color(0.42, 0.43, 0.45)
	var yellow := Color(0.78, 0.56, 0.1)
	var concrete := Color(0.5, 0.49, 0.46)
	const PIVOT := Vector3(0, 4.3, 0)
	const SHAFT := Vector3(0, 1.75, -2.5)
	# the concrete pad, the steel skid on it
	_part(st, xf, Vector3(0, 0.15, 0.2), Vector3(2.6, 0.3, 8.8), concrete)
	for sx in [-0.8, 0.8]:
		MeshKit.box(st, Transform3D(Basis.IDENTITY, Vector3(sx, 0.42, -0.4)), Vector3(0.22, 0.24, 6.6), dark)
	for z in [-3.2, -1.2, 0.8, 2.2]:
		MeshKit.box(st, Transform3D(Basis.IDENTITY, Vector3(0, 0.42, z)), Vector3(1.8, 0.2, 0.18), dark)
	# the Samson post: an A-frame of four legs up to the saddle bearing, braced, with a ladder
	for sx in [-0.85, 0.85]:
		for sz in [-0.9, 0.9]:
			_strut(st, Vector3(sx, 0.5, sz), PIVOT + Vector3(sx * 0.25, -0.25, 0), 0.16, yellow)
		_strut(st, Vector3(sx, 1.6, -0.62), Vector3(sx, 1.6, 0.62), 0.08, yellow)
		_strut(st, Vector3(sx * 0.7, 2.8, -0.38), Vector3(sx * 0.7, 2.8, 0.38), 0.08, yellow)
	for sz in [-0.9, 0.9]:
		_strut(st, Vector3(-0.85, 0.6, sz), Vector3(0.85, 2.2, sz * 0.6), 0.07, yellow)
	MeshKit.box(st, Transform3D(Basis.IDENTITY, PIVOT + Vector3(0, -0.2, 0)), Vector3(0.9, 0.22, 0.5), dark)   # saddle bearing
	for k in 12:
		var y := 0.7 + k * 0.28
		MeshKit.box(st, Transform3D(Basis.IDENTITY, Vector3(1.05 - y * 0.04, y, 1.0 - y * 0.16)), Vector3(0.04, 0.04, 0.42), steel)
	_strut(st, Vector3(1.0, 0.5, 1.08), Vector3(0.88, 3.8, 0.42), 0.05, steel)
	_strut(st, Vector3(1.0, 0.5, 0.68), Vector3(0.88, 3.8, 0.02), 0.05, steel)
	# the gear reducer on its pedestal, the motor with its belt guard
	MeshKit.box(st, Transform3D(Basis.IDENTITY, Vector3(0, 0.75, -2.5)), Vector3(1.0, 0.7, 1.3), dark)
	MeshKit.box(st, Transform3D(Basis.IDENTITY, SHAFT + Vector3(0, -0.15, 0)), Vector3(1.2, 1.0, 1.5), Color(0.25, 0.3, 0.32))
	MeshKit.box(st, Transform3D(Basis.IDENTITY, SHAFT + Vector3(0, 0.4, 0)), Vector3(1.3, 0.12, 1.6), Color(0.25, 0.3, 0.32))
	MeshKit.box(st, Transform3D(Basis.IDENTITY, Vector3(0, 0.9, -4.0)), Vector3(0.75, 0.75, 0.9), Color(0.15, 0.3, 0.5))   # motor
	MeshKit.box(st, Transform3D(Basis.IDENTITY, Vector3(0.55, 1.3, -3.25)), Vector3(0.12, 1.3, 1.9), yellow)                # belt guard
	# the wellhead: casing, tee, valves with hand wheels, the flow line along the ground
	var wz := 3.75
	MeshKit.box(st, Transform3D(Basis.IDENTITY, Vector3(0, 0.6, wz)), Vector3(0.45, 0.6, 0.45), dark)
	MeshKit.box(st, Transform3D(Basis.IDENTITY, Vector3(0, 1.1, wz)), Vector3(0.28, 0.6, 0.28), steel)
	MeshKit.box(st, Transform3D(Basis.IDENTITY, Vector3(0.35, 1.0, wz)), Vector3(0.6, 0.18, 0.18), steel)          # tee
	MeshKit.box(st, Transform3D(Basis.IDENTITY, Vector3(0.0, 1.45, wz)), Vector3(0.22, 0.2, 0.22), dark)           # stuffing box
	for vx in [0.45, 0.9]:
		MeshKit.box(st, Transform3D(Basis.IDENTITY, Vector3(vx, 1.0, wz)), Vector3(0.16, 0.3, 0.3), Color(0.6, 0.12, 0.08))
		MeshKit.box(st, Transform3D(Basis.IDENTITY, Vector3(vx, 1.25, wz)), Vector3(0.04, 0.2, 0.04), steel)
		MeshKit.box(st, Transform3D(Basis.IDENTITY, Vector3(vx, 1.36, wz)), Vector3(0.3, 0.03, 0.3), Color(0.6, 0.12, 0.08))
	_strut(st, Vector3(1.05, 1.0, wz), Vector3(1.05, 0.25, wz + 0.4), 0.12, steel)
	_strut(st, Vector3(1.05, 0.2, wz + 0.4), Vector3(6.0, 0.2, wz + 2.5), 0.12, steel)
	_mesh(st, xf, true)
	Colliders.add_box(self, xf * Transform3D(Basis.IDENTITY, Vector3(0, 2.0, 0)), Vector3(2.0, 4.0, 2.0))
	Colliders.add_box(self, xf * Transform3D(Basis.IDENTITY, Vector3(0, 1.2, -3.0)), Vector3(1.4, 2.0, 2.6))
	# moving parts: the walking beam with the horse head (nodding), the cranks with their
	# counterweights (turning), the pitman arms between them, the bridle and the polished rod
	var root := Node3D.new()
	add_child(root)
	root.global_transform = xf
	var pivot := Node3D.new()
	pivot.position = PIVOT
	root.add_child(pivot)
	var bst := MeshKit.new_st()
	# an I-beam: flanges and web
	for fy in [-0.28, 0.28]:
		MeshKit.box(bst, Transform3D(Basis.IDENTITY, Vector3(0, fy, 0.35)), Vector3(0.45, 0.06, 6.4), yellow)
	MeshKit.box(bst, Transform3D(Basis.IDENTITY, Vector3(0, 0, 0.35)), Vector3(0.08, 0.56, 6.4), yellow)
	# the horse head: a curved face round the pivot (radius R) so the bridle hangs straight
	var R := 3.55
	for k in 9:
		var a0 := lerpf(-0.42, 0.42, float(k) / 9.0)
		var a1 := lerpf(-0.42, 0.42, float(k + 1) / 9.0)
		var am := (a0 + a1) * 0.5
		var c := Vector3(0, sin(am) * R, cos(am) * R)
		MeshKit.box(bst, Transform3D(Basis(Vector3.RIGHT, -am), c), Vector3(0.7, (a1 - a0) * R + 0.02, 0.12), yellow)
		MeshKit.box(bst, Transform3D(Basis(Vector3.RIGHT, -am), c - Vector3(0, sin(am), cos(am)) * 0.35), Vector3(0.12, (a1 - a0) * R + 0.02, 0.6), yellow)
	# the equalizer bar at the tail
	MeshKit.box(bst, Transform3D(Basis.IDENTITY, Vector3(0, -0.35, -2.75)), Vector3(1.5, 0.2, 0.3), dark)
	var beam := MeshKit.mesh_instance(MeshKit.commit(bst, _metal))
	pivot.add_child(beam)
	var crank := Node3D.new()
	crank.position = SHAFT
	root.add_child(crank)
	var cst := MeshKit.new_st()
	for sx in [-0.72, 0.72]:
		MeshKit.box(cst, Transform3D(Basis.IDENTITY, Vector3(sx, 0, 0.35)), Vector3(0.14, 0.3, 1.2), dark)          # crank arm
		MeshKit.box(cst, Transform3D(Basis.IDENTITY, Vector3(sx, 0, -0.55)), Vector3(0.22, 0.9, 0.8), Color(0.55, 0.12, 0.08))   # counterweight
	MeshKit.box(cst, Transform3D.IDENTITY, Vector3(1.6, 0.14, 0.14), steel)
	crank.add_child(MeshKit.mesh_instance(MeshKit.commit(cst, _metal)))
	var pitmen: Array = []
	for sx in [-0.72, 0.72]:
		var pm := MeshKit.box_node(Vector3(0.1, 0.1, 1.0), _metal, Vector3.ZERO)
		root.add_child(pm)
		pitmen.append([pm, sx])
	var bridle := MeshKit.box_node(Vector3(0.03, 1.0, 0.03), _metal, Vector3.ZERO)
	root.add_child(bridle)
	var carrier := MeshKit.box_node(Vector3(0.5, 0.08, 0.12), _metal, Vector3.ZERO)
	root.add_child(carrier)
	var rod := MeshKit.box_node(Vector3(0.05, 1.0, 0.05), TexKit.chrome(), Vector3.ZERO)
	root.add_child(rod)
	_jacks.append({"pivot": pivot, "crank": crank, "pitmen": pitmen, "bridle": bridle, "carrier": carrier, "rod": rod,
		"phase": rng.randf() * TAU, "R": R, "well": Vector3(0, 1.55, PIVOT.z + R)})
	_count("pump_jacks")


## A square strut from a to b in a building's frame.
static func _strut(st: SurfaceTool, a: Vector3, b: Vector3, w: float, col: Color) -> void:
	var d := b - a
	var up := Vector3.UP if absf(d.normalized().y) < 0.95 else Vector3.FORWARD
	MeshKit.box(st, Transform3D(Basis.looking_at(d.normalized(), up), (a + b) * 0.5), Vector3(w, w, d.length()), col)


## A pump jack at crank angle `phi`: the beam nods with it, the pitman arms join crank pins and
## beam tail, the bridle and rod follow the horse head.
func _jack_pose(j: Dictionary, phi: float) -> void:
	var pivot: Node3D = j["pivot"]
	var crank: Node3D = j["crank"]
	var th := sin(phi) * 0.3
	pivot.rotation.x = th
	crank.rotation.x = phi
	var tail: Vector3 = pivot.transform * Vector3(0, -0.35, -2.75)
	for pm in j["pitmen"]:
		var sx: float = pm[1]
		var pin: Vector3 = crank.transform * Vector3(sx, 0, 0.85)
		var top := Vector3(sx, tail.y, tail.z)
		var d := top - pin
		(pm[0] as Node3D).transform = Transform3D(Basis.looking_at(d.normalized(), Vector3.RIGHT) * Basis.from_scale(Vector3(1, 1, d.length())), (pin + top) * 0.5)
	# the bridle hangs from the horse head's face (always above the well), its length paid out by
	# the head's turn
	var R: float = j["R"]
	var well: Vector3 = j["well"]
	var hang_top: float = pivot.position.y
	var car_y: float = well.y + 1.4 - R * th
	var bridle: Node3D = j["bridle"]
	bridle.position = Vector3(0, (hang_top + car_y) * 0.5, well.z)
	bridle.scale = Vector3(1, hang_top - car_y, 1)
	(j["carrier"] as Node3D).position = Vector3(0, car_y, well.z)
	var rod: Node3D = j["rod"]
	rod.position = Vector3(0, (car_y + well.y) * 0.5, well.z)
	rod.scale = Vector3(1, maxf(car_y - well.y, 0.05), 1)


func _wreck() -> void:
	var xf = _site(3.5, 4.0, 90.0)
	if xf == null:
		return
	var st := MeshKit.new_st()
	var rust := Color(0.45, 0.22, 0.1).lerp(Color(0.3, 0.32, 0.35), rng.randf() * 0.5)
	var yaw := rng.randf() * TAU
	var tilt := Basis(Vector3.UP, yaw) * Basis(Vector3.FORWARD, rng.randf_range(-0.08, 0.08))
	var b := Transform3D(tilt, Vector3.ZERO)
	MeshKit.box(st, b * Transform3D(Basis.IDENTITY, Vector3(0, 0.55, 0)), Vector3(1.8, 0.7, 4.3), rust)
	MeshKit.box(st, b * Transform3D(Basis.IDENTITY, Vector3(0, 1.15, -0.3)), Vector3(1.6, 0.6, 2.0), rust * 0.9)
	for wx in [-0.85, 0.85]:
		for wz in [-1.3, 1.4]:
			if rng.randf() < 0.75:
				MeshKit.box(st, b * Transform3D(Basis.IDENTITY, Vector3(wx, 0.25, wz)), Vector3(0.25, 0.5, 0.6), Color(0.08, 0.08, 0.08))
	_mesh(st, xf)
	Colliders.add_box(self, xf * b * Transform3D(Basis.IDENTITY, Vector3(0, 0.7, 0)), Vector3(1.8, 1.3, 4.3))
	_count("wrecks")


func _radio_mast() -> void:
	var xf = _site(5.0, 40.0, 220.0)
	if xf == null:
		return
	var st := MeshKit.new_st()
	var h := 42.0
	for k in 8:
		var y0 := h * k / 8.0
		var w := lerpf(2.4, 0.6, float(k) / 8.0)
		var col := Color(0.8, 0.15, 0.1) if k % 2 == 0 else Color(0.9, 0.9, 0.88)
		for s in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			MeshKit.box(st, Transform3D(Basis.IDENTITY, Vector3(s.x * w * 0.5, y0 + h / 16.0, s.y * w * 0.5)), Vector3(0.16, h / 8.0, 0.16), col)
		MeshKit.box(st, Transform3D(Basis.IDENTITY, Vector3(0, y0, 0)), Vector3(w, 0.1, w), col)
	_mesh(st, xf, true)
	Colliders.add_box(self, xf * Transform3D(Basis.IDENTITY, Vector3(0, 2.0, 0)), Vector3(2.6, 4.0, 2.6))
	var lamp := TexKit.std(Color(1, 0.1, 0.05), 0.4, 0.0, Color(1, 0.1, 0.05), 3.0)
	var bulb := MeshKit.sphere_node(0.35, lamp)
	add_child(bulb)
	bulb.global_position = xf * Vector3(0, h + 0.4, 0)
	_blink.append([lamp, 0.0])
	_count("radio_mast")


# ---------------------------------------------------------------------------
# Along the road
# ---------------------------------------------------------------------------
const BILLBOARDS := [
	["MIDNIGHT DRIFT\nUTAH DESERT", Color(0.15, 0.05, 0.25), Color(1.0, 0.75, 1.0)],
	["LAST GAS\nFOR 120 MILES", Color(0.85, 0.75, 0.2), Color(0.15, 0.1, 0.05)],
	["TAKUMI TIRES\nGRIP IN THE DUST", Color(0.1, 0.1, 0.12), Color(1.0, 0.85, 0.2)],
	["MOTEL  ★ ★ ★\nNEXT EXIT", Color(0.2, 0.45, 0.5), Color(1, 1, 1)],
	["KUROHANA MOTORS\nSINCE 1987", Color(0.6, 0.08, 0.06), Color(1, 0.95, 0.9)],
	["WATCH FOR\nTUMBLEWEEDS", Color(0.95, 0.9, 0.8), Color(0.35, 0.15, 0.08)],
	["NITRO-X\nGO FASTER", Color(0.05, 0.25, 0.6), Color(0.6, 1.0, 1.0)],
	["DINER  OPEN 24H\nPIE & COFFEE", Color(0.85, 0.85, 0.82), Color(0.7, 0.1, 0.1)],
]


func _billboards() -> void:
	var n: int = track.sample_count()
	for k in BILLBOARDS.size():
		var i := int((k + 0.35) / BILLBOARDS.size() * n) % n
		# on a straight bit, outside the road, facing the cars that come
		for _tries in 30:
			if absf(float(track.curvature[i])) < 1.0 / 120.0:
				break
			i = (i + 7) % n
		var side := 1.0 if k % 2 == 0 else -1.0
		var p: Vector3 = track.edge_point(i, (float(track.hws[i]) + 9.0) * side)
		if not scenery.free_at(p, 4.0, 0.0):
			continue
		scenery.occupy(p, 4.0)
		p.y = terrain.height_at(p.x, p.z)
		var fwd: Vector3 = track.tangents[i]
		fwd = Vector3(fwd.x, 0, fwd.z).normalized()
		# turned a little towards the road
		var face := (-fwd + Vector3(track.rights[i]) * -side * 0.35).normalized()
		var xf := Transform3D(Basis.looking_at(-face, Vector3.UP), p)
		var st := MeshKit.new_st()
		var bb: Array = BILLBOARDS[k]
		# the posts reach down to the ground under each of them (it slopes), into it a little
		for s in [-2.6, 2.6]:
			var foot: Vector3 = xf * Vector3(s, 0, -0.2)
			var gy: float = minf(terrain.height_at(foot.x, foot.z) - p.y, 0.0) - 0.6
			_part(st, xf, Vector3(s, (gy + 4.8) * 0.5, -0.2), Vector3(0.3, 4.8 - gy, 0.3), Color(0.35, 0.28, 0.2))
		_part(st, xf, Vector3(0, 6.6, 0), Vector3(8.0, 3.6, 0.25), bb[1], true)
		_mesh(st, xf)
		_label(str(bb[0]), xf * Transform3D(Basis.IDENTITY, Vector3(0, 6.6, 0.14)), 82, bb[2], Color(0, 0, 0, 0))
		# printed on the back as well
		_label(str(bb[0]), xf * Transform3D(Basis(Vector3.UP, PI), Vector3(0, 6.6, -0.14)), 82, bb[2], Color(0, 0, 0, 0))
		_night_light(xf * Vector3(0, 9.0, 1.5), Color(1.0, 0.9, 0.7), 1.0, 9.0)
		_count("billboards")


## Telephone poles with sagging wires along two long stretches of the road.
func _telephone_line() -> void:
	var n: int = track.sample_count()
	var wood := Color(0.32, 0.24, 0.17)
	for stretch in [[0.08, 0.3, 1.0], [0.55, 0.8, -1.0]]:
		var st := MeshKit.new_st()
		var wst := MeshKit.new_st()
		var tops: Array = []
		var i := int(float(stretch[0]) * n)
		var i_end := int(float(stretch[1]) * n)
		while i < i_end:
			var side: float = stretch[2]
			var p: Vector3 = track.edge_point(i % n, (float(track.hws[i % n]) + 14.0) * side)
			if terrain.distance_to_road(p.x, p.z) > float(track.half_w) + 10.0 and scenery.free_at(p, 0.5, 0.0) and not _wet(p.x, p.z, 3.0):
				p.y = terrain.height_at(p.x, p.z)
				var fwd: Vector3 = track.tangents[i % n]
				var b := Basis.looking_at(Vector3(fwd.x, 0, fwd.z).normalized(), Vector3.UP)
				MeshKit.box(st, Transform3D(b, p + Vector3(0, 4.5, 0)), Vector3(0.28, 9.0, 0.28), wood)
				MeshKit.box(st, Transform3D(b, p + Vector3(0, 8.4, 0)), Vector3(2.2, 0.18, 0.2), wood)
				Colliders.add_box(self, Transform3D(b, p + Vector3(0, 2.0, 0)), Vector3(0.3, 4.0, 0.3))
				tops.append([p, b])
				scenery.occupy(p, 0.6)
				_count("poles")
			i += 22      # ~44 m
		# the wires: three, sagging between the poles
		for k in range(tops.size() - 1):
			var a: Vector3 = tops[k][0]
			var c: Vector3 = tops[k + 1][0]
			if a.distance_to(c) > 70.0:
				continue
			for off in [-0.9, 0.0, 0.9]:
				var oa: Vector3 = a + (tops[k][1] as Basis).x * off + Vector3(0, 8.5, 0)
				var oc: Vector3 = c + (tops[k + 1][1] as Basis).x * off + Vector3(0, 8.5, 0)
				var prev := oa
				for s in range(1, 9):
					var t := s / 8.0
					var q := oa.lerp(oc, t) - Vector3(0, sin(t * PI) * 0.9, 0)
					MeshKit.box(wst, Transform3D(Basis.looking_at((q - prev).normalized(), Vector3.UP), (q + prev) * 0.5), Vector3(0.03, 0.03, prev.distance_to(q)), Color(0.08, 0.08, 0.08))
					prev = q
		_mesh(st, Transform3D.IDENTITY)
		_mesh(wst, Transform3D.IDENTITY, false, false)


## Ranch fences: rows of posts with two rails, here and there.
func _fences() -> void:
	var wood := Color(0.45, 0.35, 0.25)
	for f in 14:
		var xf = _site(2.0, 6.0, 100.0, 20)
		if xf == null:
			continue
		var st := MeshKit.new_st()
		var len := rng.randf_range(12.0, 30.0)
		var segs := int(len / 2.5)
		var x0 := -len * 0.5
		for k in segs + 1:
			var x := x0 + k * 2.5
			var p: Vector3 = (xf as Transform3D) * Vector3(x, 0, 0)
			var gy: float = terrain.height_at(p.x, p.z) - (xf as Transform3D).origin.y
			MeshKit.box(st, Transform3D(Basis.IDENTITY, Vector3(x, gy + 0.6, 0)), Vector3(0.14, 1.3, 0.14), wood)
			if k < segs and rng.randf() < 0.9:
				for ry in [0.5, 1.0]:
					MeshKit.box(st, Transform3D(Basis.IDENTITY, Vector3(x + 1.25, gy + ry, 0)), Vector3(2.5, 0.1, 0.06), wood * 0.9)
		_mesh(st, xf)
		_count("fences")


## Red stones lying about everywhere: thousands of small ones and a few hundred bigger ones you
## can bump into.
func _red_stones() -> void:
	var stone_mat := StandardMaterial3D.new()
	stone_mat.albedo_color = Color(0.56, 0.17, 0.1)
	stone_mat.roughness = 0.92
	var meshes := [TreeFactory.rock(61), TreeFactory.rock(73), TreeFactory.rock(89)]
	var sets: Array = [[], [], []]
	var body := StaticBody3D.new()
	body.name = "RedStones"
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("surface", "wall")
	add_child(body)
	for k in 5200:
		var x := rng.randf_range(rect.position.x, rect.end.x)
		var z := rng.randf_range(rect.position.y, rect.end.y)
		var d: float = terrain.distance_to_road(x, z) - float(track.half_w)
		if d < 1.2 or _wet(x, z, 1.5):
			continue
		var big := rng.randf() < 0.07
		var s := rng.randf_range(0.6, 1.4) if big else rng.randf_range(0.08, 0.4)
		if big and d < 3.0:
			continue
		var p := Vector3(x, terrain.height_at(x, z) - s * 0.25, z)
		var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s * rng.randf_range(0.8, 1.3), s * rng.randf_range(0.6, 1.0), s * rng.randf_range(0.8, 1.3)))
		var tint := rng.randf_range(0.7, 1.15)
		sets[k % 3].append([Transform3D(b, p), Color(tint, tint * rng.randf_range(0.85, 1.0), tint * rng.randf_range(0.8, 1.0), 1.0)])
		if big:
			var cs := CollisionShape3D.new()
			var sh := SphereShape3D.new()
			sh.radius = s * 0.75
			cs.shape = sh
			cs.position = p + Vector3(0, s * 0.2, 0)
			body.add_child(cs)
			_count("red_stones_big")
		_count("red_stones")
	for m in 3:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = meshes[m]
		mm.instance_count = sets[m].size()
		for i in sets[m].size():
			mm.set_instance_transform(i, sets[m][i][0])
			mm.set_instance_color(i, sets[m][i][1])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		var mat := stone_mat.duplicate() as StandardMaterial3D
		mat.vertex_color_use_as_albedo = true
		mmi.material_override = mat
		mmi.visibility_range_end = 450.0
		add_child(mmi)


func _process(delta: float) -> void:
	_t += delta
	for s in _spinners:
		(s[0] as Node3D).rotate_object_local(s[1], float(s[2]) * delta)
	for j in _jacks:
		_jack_pose(j, _t * 1.6 + float(j["phase"]))
	for b in _blink:
		(b[0] as StandardMaterial3D).emission_energy_multiplier = 4.0 if fmod(_t + float(b[1]), 1.6) < 0.5 else 0.2

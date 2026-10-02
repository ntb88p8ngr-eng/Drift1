extends RefCounted
## Detailed 3D buildings for Neo Tokyo, written into the chunked city meshes (city_mesh.gd):
##   tower     – glass curtain wall: recessed mirror glass, mullions, floor slabs, a setback crown,
##               helipad / mast and red aircraft lights on the tall ones
##   office    – punched facade: piers and spandrels in front of recessed windows
##   apartment – like office, the street side with balconies, rails, dividers and AC units
##   zakkyo    – the narrow multi-tenant buildings: big windows, a tenant sign on every floor, a
##               column of vertical blade signs at the front corner, AC units on the side walls
##   house     – two or three storeys, small windows, a pitched roof
## Shop ground floors (glass front lit from inside, fascia sign, awning) and roofs (parapet, plant,
## water tanks, antennas, billboards) are added per building. Light sources go to `emitters`.

const CityAtlas = preload("res://scripts/world/city/city_atlas.gd")

const FRAME_TOWER := [Color(0.72, 0.74, 0.78, 0.45), Color(0.2, 0.21, 0.23, 0.5), Color(0.42, 0.34, 0.24, 0.5), Color(0.88, 0.89, 0.9, 0.6)]
const WALLS := [Color(0.82, 0.78, 0.7), Color(0.62, 0.62, 0.62), Color(0.9, 0.89, 0.86), Color(0.56, 0.4, 0.32),
	Color(0.62, 0.32, 0.24), Color(0.7, 0.76, 0.72), Color(0.78, 0.74, 0.66), Color(0.46, 0.46, 0.48)]
const AWNINGS := [Color(0.8, 0.12, 0.1), Color(0.1, 0.35, 0.2), Color(0.12, 0.2, 0.5), Color(0.92, 0.75, 0.15),
	Color(0.95, 0.95, 0.92), Color(0.3, 0.15, 0.1)]
const SHOP_LIGHT := [Color(1.0, 0.86, 0.62), Color(0.88, 0.94, 1.0), Color(1.0, 0.75, 0.5)]

var cm
var rng := RandomNumberGenerator.new()
var emitters: Array = []        # [position, colour, range, energy, kind (0 omni, 1 spot down)]
var far: Array = []             # [Transform3D of the far-LOD box, tint]
var stats := {}


func _init(p_cm) -> void:
	cm = p_cm
	rng.seed = 909


func light(p: Vector3, col: Color, rng_m: float, energy: float, kind := 0) -> void:
	emitters.append([p, col, rng_m, energy, kind])


## b: {c: Vector3 ground centre, ax: along the street, az: away from it (the front faces -az), w, d, h,
## style, shop: bool, shop_sign: int (atlas shop cell, -1 random)}
func building(b: Dictionary) -> void:
	var style: String = b["style"]
	var h: float = b["h"]
	var gh := 4.6 if bool(b.get("shop", false)) else 0.0
	var seed := rng.randf()
	var faces := _faces(b)
	var blind: Array = b.get("blind", [false, false, false, false])
	match style:
		"tower":
			var col: Color = FRAME_TOWER[rng.randi() % FRAME_TOWER.size()]
			var bay := rng.randf_range(2.6, 3.4)
			var crown := 0.0
			if h > 70.0:
				crown = rng.randf_range(10.0, 22.0)
			for f in faces:
				_curtain(f, gh, h - crown, col, bay, seed, 0.0)
			if gh > 0.0:
				_lobby(b, faces, gh, col)
			if crown > 0.0:
				var b2 := b.duplicate()
				b2["w"] = float(b["w"]) * 0.7
				b2["d"] = float(b["d"]) * 0.7
				b2["c"] = (b["c"] as Vector3) + Vector3(0, h - crown, 0)
				for f in _faces(b2):
					_curtain(f, 0.0, crown, col, bay, seed, 0.0)
				_roof(b2, crown, col, true)
				_slab_cap(b, h - crown, col)
			else:
				_roof(b, h, col, true)
		"office", "apartment":
			var wall: Color = WALLS[rng.randi() % WALLS.size()]
			var bay := rng.randf_range(2.8, 3.6)
			var fh := 3.6 if style == "office" else 3.0
			for k in faces.size():
				if blind[k]:
					_firewall(faces[k], h, wall)
				elif style == "apartment" and k == 0:
					_balconies(faces[k], gh, h, wall, bay, fh, seed)
				else:
					_punched(faces[k], gh if k == 0 else 0.0, h, wall, bay, fh, seed, 0.0 if style == "office" else 1.0)
			if gh > 0.0:
				_shop_front(b, faces[0], gh, wall)
			_roof(b, h, wall, style == "office")
		"zakkyo":
			var wall: Color = WALLS[rng.randi() % WALLS.size()].lerp(Color(0.9, 0.9, 0.9), 0.3)
			var fh := 3.4
			for k in faces.size():
				if blind[k]:
					_firewall(faces[k], h, wall)
				else:
					_punched(faces[k], gh if k == 0 else 0.0, h, wall, rng.randf_range(2.2, 2.8), fh, seed, 0.6, k == 0)
			if gh > 0.0:
				_shop_front(b, faces[0], gh, wall)
			_tenant_signs(b, faces[0], gh, h, fh)
			_blade_column(b, faces[0], gh, h)
			_side_units(faces, gh, h)
			_roof(b, h, wall, false)
		_:
			var wall: Color = WALLS[rng.randi() % WALLS.size()].lerp(Color(0.95, 0.93, 0.88), 0.4)
			for k in faces.size():
				if blind[k]:
					_firewall(faces[k], h, wall)
				else:
					_punched(faces[k], gh if k == 0 else 0.0, h, wall, rng.randf_range(2.6, 3.2), 3.0, seed, 1.0)
			if gh > 0.0:
				_shop_front(b, faces[0], gh, wall)
			_pitched_roof(b, h)
	far.append([Transform3D(Basis(b["ax"], Vector3.UP, b["az"]) * Basis.from_scale(Vector3(b["w"], h, b["d"])), (b["c"] as Vector3) + Vector3(0, h * 0.5, 0)), style])
	stats[style] = int(stats.get(style, 0)) + 1


## The four facades: [ground centre of the face, outward normal, width] – the front (towards the
## street) first.
func _faces(b: Dictionary) -> Array:
	var c: Vector3 = b["c"]
	var ax: Vector3 = b["ax"]
	var az: Vector3 = b["az"]
	var w: float = b["w"]
	var d: float = b["d"]
	return [[c - az * d * 0.5, -az, w], [c + az * d * 0.5, az, w], [c - ax * w * 0.5, -ax, d], [c + ax * w * 0.5, ax, d]]


# ---------------------------------------------------------------------------
# Facades
# ---------------------------------------------------------------------------
## Curtain wall: mirror glass set back, mullions every bay, a slab band every floor.
func _curtain(f: Array, y0: float, y1: float, col: Color, bay: float, seed: float, homes: float) -> void:
	var cf: Vector3 = f[0]
	var n: Vector3 = f[1]
	var w: float = f[2]
	var u := Vector3.UP.cross(n)
	var o := cf - u * w * 0.5 + Vector3(0, cf.y * 0.0, 0)
	_glass(o, u, n, w, y0, y1, seed, 0.38, bay, homes, 0.14)
	var m := maxi(int(round(w / bay)), 1)
	var hgt := y1 - y0
	var basis := Basis(u, Vector3.UP, n)
	for k in m + 1:
		var x := w * float(k) / m
		var wide := 0.32 if (k == 0 or k == m) else 0.16
		cm.box("metal", Transform3D(basis, o + u * x + Vector3(0, y0 + hgt * 0.5, 0) + n * 0.03), Vector3(wide, hgt, 0.26), col)
	var floors := int(hgt / 3.8)
	for j in floors + 1:
		var y := y0 + float(j) * hgt / maxf(floors, 1)
		cm.box("metal", Transform3D(basis, o + u * w * 0.5 + Vector3(0, y, 0) + n * 0.05), Vector3(w + 0.1, 0.3, 0.32), col.darkened(0.15))


## Punched facade: piers between the windows, spandrels below them, glass set back behind.
func _punched(f: Array, y0: float, y1: float, wall: Color, bay: float, fh: float, seed: float, homes: float, big_windows := false) -> void:
	if y1 - y0 < 1.0:
		return
	var cf: Vector3 = f[0]
	var n: Vector3 = f[1]
	var w: float = f[2]
	var u := Vector3.UP.cross(n)
	var o := cf - u * w * 0.5
	var basis := Basis(u, Vector3.UP, n)
	_glass(o, u, n, w, y0, y1, seed, 0.3 if homes > 0.5 else 0.42, bay, homes, 0.3)
	var hgt := y1 - y0
	var m := maxi(int(round(w / bay)), 1)
	var pier := 1.1 if big_windows else 0.75
	for k in m + 1:
		var x := w * float(k) / m
		var pw := pier * (1.4 if (k == 0 or k == m) else 1.0)
		cm.box("frame", Transform3D(basis, o + u * clampf(x, pw * 0.5, w - pw * 0.5) + Vector3(0, y0 + hgt * 0.5, 0) - n * 0.13), Vector3(pw, hgt, 0.3), wall)
	var floors := maxi(int(round(hgt / fh)), 1)
	var sp := 0.6 if big_windows else 1.05
	for j in floors:
		var y := y0 + float(j) * hgt / floors
		cm.box("frame", Transform3D(basis, o + u * w * 0.5 + Vector3(0, y + sp * 0.5, 0) - n * 0.13), Vector3(w, sp, 0.3), wall)
		# window sills
		cm.detail = true
		cm.box("frame", Transform3D(basis, o + u * w * 0.5 + Vector3(0, y + sp + 0.03, 0) + n * 0.04), Vector3(w - 0.2, 0.06, 0.12), wall.darkened(0.1))
		cm.detail = false
	cm.box("frame", Transform3D(basis, o + u * w * 0.5 + Vector3(0, y1 - 0.25, 0) - n * 0.13), Vector3(w, 0.5, 0.3), wall)


## The street side of an apartment block: a balcony on every floor of every bay.
func _balconies(f: Array, y0: float, y1: float, wall: Color, bay: float, fh: float, seed: float) -> void:
	_punched(f, y0, y1, wall, bay, fh, seed, 1.0, true)
	var cf: Vector3 = f[0]
	var n: Vector3 = f[1]
	var w: float = f[2]
	var u := Vector3.UP.cross(n)
	var o := cf - u * w * 0.5
	var basis := Basis(u, Vector3.UP, n)
	var floors := maxi(int(round((y1 - y0) / fh)), 1)
	var rail := Color(0.85, 0.87, 0.9, 0.45) if rng.randf() < 0.5 else wall.lightened(0.15)
	var m := maxi(int(round(w / bay)), 1)
	for j in range(1, floors):
		var y := y0 + float(j) * (y1 - y0) / floors
		cm.box("frame", Transform3D(basis, o + u * w * 0.5 + Vector3(0, y, 0) + n * 0.6), Vector3(w - 0.4, 0.18, 1.2), wall.lightened(0.08))
		cm.box("metal", Transform3D(basis, o + u * w * 0.5 + Vector3(0, y + 0.55, 0) + n * 1.18), Vector3(w - 0.4, 1.0, 0.05), rail)
		cm.detail = true
		for k in range(1, m):
			cm.box("frame", Transform3D(basis, o + u * (w * float(k) / m) + Vector3(0, y + 1.2, 0) + n * 0.6), Vector3(0.08, 2.3, 1.15), wall.darkened(0.06))
		# AC units and laundry poles on some balconies
		for k in m:
			if rng.randf() < 0.35:
				cm.box("frame", Transform3D(basis, o + u * (w * (k + 0.3) / m) + Vector3(0, y + 0.42, 0) + n * 0.85), Vector3(0.8, 0.55, 0.3), Color(0.88, 0.88, 0.86))
			if rng.randf() < 0.2:
				cm.box("metal", Transform3D(basis, o + u * (w * (k + 0.5) / m) + Vector3(0, y + 1.9, 0) + n * 0.9), Vector3(w / m - 0.4, 0.04, 0.04), Color(0.7, 0.7, 0.72, 0.4))
		cm.detail = false


## A blank wall where the neighbour stands close (Tokyo's bare side walls): one slab, a downpipe,
## the floor lines faintly marked.
func _firewall(f: Array, h: float, wall: Color) -> void:
	var cf: Vector3 = f[0]
	var n: Vector3 = f[1]
	var w: float = f[2]
	var u := Vector3.UP.cross(n)
	var basis := Basis(u, Vector3.UP, n)
	var c := wall.darkened(0.12)
	cm.box("frame", Transform3D(basis, cf + Vector3(0, h * 0.5, 0) - n * 0.13), Vector3(w, h, 0.3), c)
	cm.detail = true
	cm.box("metal", Transform3D(basis, cf + u * (w * 0.5 - 0.5) + Vector3(0, h * 0.5, 0) + n * 0.1), Vector3(0.12, h, 0.12), Color(0.45, 0.45, 0.47, 0.5))
	cm.detail = false
	stats["firewalls"] = int(stats.get("firewalls", 0)) + 1


## Glass across a facade, set back by `inset`.
func _glass(o: Vector3, u: Vector3, n: Vector3, w: float, y0: float, y1: float, seed: float, lit: float, bay: float, homes: float, inset: float) -> void:
	var a := o + Vector3(0, y0, 0) - n * inset
	var col := Color(seed, lit * rng.randf_range(0.7, 1.2), clampf((bay - 2.4) / 2.5, 0.0, 1.0), homes)
	var u0 := (o.x + o.z) * 0.37
	cm.quad("glass", a, a + u * w, a + u * w + Vector3(0, y1 - y0, 0), a + Vector3(0, y1 - y0, 0), n, col,
		Vector2(u0, y0), Vector2(u0 + w, y0), Vector2(u0 + w, y1), Vector2(u0, y1))


## Glass lobby of a tower: tall windows, a canopy over the entrance, lit at night.
func _lobby(b: Dictionary, faces: Array, gh: float, col: Color) -> void:
	for k in faces.size():
		var f: Array = faces[k]
		var cf: Vector3 = f[0]
		var n: Vector3 = f[1]
		var w: float = f[2]
		var u := Vector3.UP.cross(n)
		var basis := Basis(u, Vector3.UP, n)
		cm.glow_box(Transform3D(basis, cf + Vector3(0, gh * 0.5, 0) - n * 0.6), Vector3(w - 0.6, gh - 0.4, 0.05), Color(0.95, 0.88, 0.72), 0.25)
		cm.detail = true
		for x in range(0, int(w / 2.5) + 1):
			cm.box("metal", Transform3D(basis, cf - u * w * 0.5 + u * minf(x * 2.5, w) + Vector3(0, gh * 0.5, 0)), Vector3(0.12, gh, 0.15), col)
		cm.detail = false
		if k == 0:
			cm.box("metal", Transform3D(basis, cf + Vector3(0, gh - 0.4, 0) + n * 2.0), Vector3(minf(w * 0.5, 14.0), 0.25, 4.0), col.darkened(0.2))
			light(cf + Vector3(0, gh - 0.8, 0) + n * 2.5, Color(1.0, 0.9, 0.75), 12.0, 2.2, 0)
	cm.box("metal", Transform3D(Basis(b["ax"], Vector3.UP, b["az"]), (b["c"] as Vector3) + Vector3(0, gh - 0.2, 0)), Vector3(float(b["w"]) + 0.3, 0.4, float(b["d"]) + 0.3), col)


## Ground floor shop on the front face: glass lit from inside, frame, fascia with the shop sign,
## sometimes an awning; a light in front of it.
func _shop_front(b: Dictionary, f: Array, gh: float, wall: Color) -> void:
	var cf: Vector3 = f[0]
	var n: Vector3 = f[1]
	var w: float = f[2]
	var u := Vector3.UP.cross(n)
	var basis := Basis(u, Vector3.UP, n)
	var lc: Color = SHOP_LIGHT[rng.randi() % SHOP_LIGHT.size()]
	# corner piers either side of the shop window
	for s: float in [-1.0, 1.0]:
		cm.box("frame", Transform3D(basis, cf + u * s * (w * 0.5 - 0.3) + Vector3(0, gh * 0.5, 0) - n * 0.13), Vector3(0.6, gh, 0.6), wall)
	cm.glow_box(Transform3D(basis, cf + Vector3(0, 1.7, 0) - n * 0.45), Vector3(w - 0.8, 3.0, 0.05), lc, 0.35)
	# mullions of the shop window, a door frame
	var parts := maxi(int(w / 3.0), 1)
	cm.detail = true
	for k in parts + 1:
		cm.box("metal", Transform3D(basis, cf - u * w * 0.5 + u * (w * float(k) / parts) + Vector3(0, 1.6, 0) - n * 0.3), Vector3(0.12, 3.2, 0.12), Color(0.15, 0.15, 0.16, 0.5))
	cm.box("metal", Transform3D(basis, cf + Vector3(0, 0.15, 0) - n * 0.3), Vector3(w - 0.6, 0.3, 0.2), Color(0.2, 0.2, 0.22, 0.5))
	cm.detail = false
	# fascia and the shop sign over the window
	cm.box("frame", Transform3D(basis, cf + Vector3(0, gh - 0.65, 0) - n * 0.05), Vector3(w, 1.3, 0.4), wall.darkened(0.25))
	var si: int = b.get("shop_sign", -1)
	if si < 0:
		si = rng.randi_range(13, 63)
	cm.sign_box(Transform3D(basis, cf + Vector3(0, gh - 0.65, 0) + n * 0.2), Vector3(minf(w - 1.0, 7.5), 0.95, 0.12), CityAtlas.shop(si), 1.0)
	if rng.randf() < 0.55:
		var ac: Color = AWNINGS[rng.randi() % AWNINGS.size()]
		var aw := Basis(u, Vector3.UP, n).rotated(u, -0.3)
		cm.box("frame", Transform3D(aw, cf + Vector3(0, gh - 1.55, 0) + n * 0.7), Vector3(w - 0.6, 0.06, 1.5), ac)
	light(cf + Vector3(0, 2.6, 0) + n * 1.6, lc, 8.0, 1.6, 0)
	stats["shops"] = int(stats.get("shops", 0)) + 1


## Zakkyo: a tenant sign band on every floor of the street side.
func _tenant_signs(b: Dictionary, f: Array, gh: float, h: float, fh: float) -> void:
	var cf: Vector3 = f[0]
	var n: Vector3 = f[1]
	var w: float = f[2]
	var u := Vector3.UP.cross(n)
	var basis := Basis(u, Vector3.UP, n)
	var floors := int((h - gh) / fh)
	for j in floors:
		if rng.randf() < 0.75:
			var y := gh + j * fh + 0.35
			cm.sign_box(Transform3D(basis, cf + Vector3(0, y, 0) + n * 0.12), Vector3(w * 0.8, 0.55, 0.08), CityAtlas.shop(rng.randi_range(13, 63)), 0.8)


## Zakkyo: the stack of vertical blade signs on the front corner, lit, with a light for the street.
func _blade_column(b: Dictionary, f: Array, gh: float, h: float) -> void:
	var cf: Vector3 = f[0]
	var n: Vector3 = f[1]
	var w: float = f[2]
	var u := Vector3.UP.cross(n)
	var x := w * 0.5 - 0.6
	var side := 1.0 if rng.randf() < 0.5 else -1.0
	var y := gh + 0.5
	var basis := Basis(n * side, Vector3.UP, -u * side)
	var lit_col := Color(1, 1, 1)
	while y + 3.2 < h - 0.5:
		var sh := rng.randf_range(2.6, 4.2)
		if y + sh > h - 0.3:
			break
		# board sticks out from the wall, readable from both directions along the street
		cm.sign_box(Transform3D(basis, cf + u * x * side + n * 0.75 + Vector3(0, y + sh * 0.5, 0)), Vector3(1.1, sh, 0.22), CityAtlas.blade(rng.randi()), 1.0, true)
		y += sh + 0.25
	light(cf + u * x * side + n * 1.6 + Vector3(0, gh + 3.0, 0), lit_col.lerp(Color(1.0, 0.5, 0.7), rng.randf()), 9.0, 1.4, 0)


## Outdoor AC units, pipes and a fire escape on the side walls.
func _side_units(faces: Array, gh: float, h: float) -> void:
	cm.detail = true
	for k in [2, 3]:
		var f: Array = faces[k]
		var cf: Vector3 = f[0]
		var n: Vector3 = f[1]
		var w: float = f[2]
		var u := Vector3.UP.cross(n)
		var basis := Basis(u, Vector3.UP, n)
		var y := gh + 1.5
		while y < h - 2.0:
			if rng.randf() < 0.6:
				cm.box("frame", Transform3D(basis, cf + u * rng.randf_range(-w * 0.35, w * 0.35) + Vector3(0, y, 0) + n * 0.25), Vector3(0.85, 0.6, 0.32), Color(0.86, 0.86, 0.84))
			y += 3.4
		cm.box("metal", Transform3D(basis, cf + u * (w * 0.5 - 0.4) + Vector3(0, h * 0.5, 0) + n * 0.12), Vector3(0.12, h, 0.12), Color(0.5, 0.5, 0.52, 0.5))
	cm.detail = false


# ---------------------------------------------------------------------------
# Roofs
# ---------------------------------------------------------------------------
func _slab_cap(b: Dictionary, y: float, col: Color) -> void:
	cm.box("frame", Transform3D(Basis(b["ax"], Vector3.UP, b["az"]), (b["c"] as Vector3) + Vector3(0, y + 0.15, 0)), Vector3(float(b["w"]) + 0.2, 0.3, float(b["d"]) + 0.2), Color(0.4, 0.4, 0.42))


func _roof(b: Dictionary, h: float, col: Color, tall: bool) -> void:
	var c: Vector3 = (b["c"] as Vector3) + Vector3(0, h, 0)
	var ax: Vector3 = b["ax"]
	var az: Vector3 = b["az"]
	var w: float = b["w"]
	var d: float = b["d"]
	var basis := Basis(ax, Vector3.UP, az)
	# roof slab and a parapet around it
	cm.box("frame", Transform3D(basis, c + Vector3(0, 0.1, 0)), Vector3(w, 0.2, d), Color(0.38, 0.38, 0.4))
	var pc := col.darkened(0.1) if col.a > 0.9 else Color(0.55, 0.56, 0.58)
	for s: float in [-1.0, 1.0]:
		cm.box("frame", Transform3D(basis, c + az * s * (d * 0.5 - 0.15) + Vector3(0, 0.6, 0)), Vector3(w, 1.0, 0.3), pc)
		cm.box("frame", Transform3D(basis, c + ax * s * (w * 0.5 - 0.15) + Vector3(0, 0.6, 0)), Vector3(0.3, 1.0, d - 0.6), pc)
	# plant: a block for lifts / AC, sometimes a water tank, antennas
	if w > 8.0 and d > 8.0:
		var pw := minf(w * 0.4, 9.0)
		var pd := minf(d * 0.35, 7.0)
		var pp := c + ax * rng.randf_range(-w, w) * 0.15 + az * rng.randf_range(-d, d) * 0.15
		cm.box("frame", Transform3D(basis, pp + Vector3(0, 1.6, 0)), Vector3(pw, 3.2, pd), Color(0.7, 0.7, 0.68))
		cm.detail = true
		for k in rng.randi_range(1, 4):
			cm.box("frame", Transform3D(basis, c + ax * rng.randf_range(-w, w) * 0.35 + az * rng.randf_range(-d, d) * 0.35 + Vector3(0, 0.6, 0)), Vector3(1.4, 1.0, 1.0), Color(0.8, 0.8, 0.78))
		if rng.randf() < 0.4:
			var tp := c + ax * w * 0.28 + az * d * 0.25
			_cyl("frame", tp, 1.3, 2.6, Color(0.72, 0.74, 0.76))
		cm.detail = false
	if tall:
		var hgt: float = (b["c"] as Vector3).y + h
		if hgt > 110.0 and rng.randf() < 0.5:
			# helipad
			_cyl("frame", c + Vector3(0, 0.25, 0), minf(w, d) * 0.38, 0.3, Color(0.3, 0.32, 0.34))
			cm.glow_box(Transform3D(basis, c + Vector3(0, 0.42, 0)), Vector3(0.8, 0.04, 4.0), Color(1.0, 0.95, 0.7), 0.3)
			cm.glow_box(Transform3D(basis, c + Vector3(0, 0.42, 0)), Vector3(3.0, 0.04, 0.8), Color(1.0, 0.95, 0.7), 0.3)
		elif hgt > 60.0:
			var mh := rng.randf_range(8.0, 22.0)
			cm.box("metal", Transform3D(basis, c + Vector3(0, mh * 0.5, 0)), Vector3(0.4, mh, 0.4), Color(0.75, 0.75, 0.78, 0.4))
			cm.glow_box(Transform3D(basis, c + Vector3(0, mh + 0.3, 0)), Vector3(0.5, 0.5, 0.5), Color(1.0, 0.08, 0.05), 0.8)
		# red aircraft lights on the corners
		if hgt > 45.0:
			for sx: float in [-1.0, 1.0]:
				for sz: float in [-1.0, 1.0]:
					cm.glow_box(Transform3D(basis, c + ax * sx * (w * 0.5 - 0.4) + az * sz * (d * 0.5 - 0.4) + Vector3(0, 1.4, 0)), Vector3(0.35, 0.35, 0.35), Color(1.0, 0.1, 0.05), 0.9)
	else:
		cm.detail = true
		for k in rng.randi_range(0, 2):
			cm.box("metal", Transform3D(basis, c + ax * rng.randf_range(-w, w) * 0.3 + az * rng.randf_range(-d, d) * 0.3 + Vector3(0, 2.0, 0)), Vector3(0.08, 4.0, 0.08), Color(0.6, 0.6, 0.62, 0.4))
		cm.detail = false
	# a billboard on the roof, facing the street
	if h < 45.0 and rng.randf() < 0.35 and w > 7.0:
		_rooftop_billboard(c, ax, az, w, d)


func _rooftop_billboard(c: Vector3, ax: Vector3, az: Vector3, w: float, d: float) -> void:
	var bw := minf(w * 0.85, 16.0)
	var bh := bw * 0.5
	var basis := Basis(-ax, Vector3.UP, -az)       # +Z (the ad) looks at the street
	var p := c - az * (d * 0.5 - 2.0) + Vector3(0, 2.2 + bh * 0.5, 0)
	cm.sign_box(Transform3D(basis, p), Vector3(bw, bh, 0.3), CityAtlas.ad(rng.randi()), 1.0)
	# steel frame behind it
	for x: float in [-0.4, 0.0, 0.4]:
		cm.box("metal", Transform3D(basis, p + ax * bw * x + Vector3(0, -bh * 0.5 - 1.1, 0) + az * 0.6), Vector3(0.2, 2.2 + bh * 0.6, 0.2), Color(0.45, 0.45, 0.47, 0.5))
		cm.box("metal", Transform3D(basis.rotated(ax, 0.55), p + ax * bw * x + az * 1.4 + Vector3(0, -0.6, 0)), Vector3(0.15, bh + 1.0, 0.15), Color(0.45, 0.45, 0.47, 0.5))
	# lamps along the top edge
	for x: float in [-0.35, 0.0, 0.35]:
		cm.glow_box(Transform3D(basis, p + ax * bw * x + Vector3(0, bh * 0.5 + 0.35, 0) - az * 0.6), Vector3(0.6, 0.15, 0.3), Color(1.0, 0.95, 0.85), 0.1)
	light(p - az * 3.0, Color(1.0, 0.95, 0.85), 14.0, 1.0, 0)
	stats["billboards"] = int(stats.get("billboards", 0)) + 1


func _pitched_roof(b: Dictionary, h: float) -> void:
	var c: Vector3 = (b["c"] as Vector3) + Vector3(0, h, 0)
	var ax: Vector3 = b["ax"]
	var az: Vector3 = b["az"]
	var w: float = b["w"]
	var d: float = b["d"]
	var tile: Color = [Color(0.25, 0.27, 0.3), Color(0.45, 0.2, 0.15), Color(0.3, 0.35, 0.3)][rng.randi() % 3]
	var rise := minf(d * 0.3, 3.0)
	var slope := atan2(rise, d * 0.5)
	for s: float in [-1.0, 1.0]:
		var basis := Basis(ax, Vector3.UP, az).rotated(ax, slope * s)
		cm.box("frame", Transform3D(basis, c + az * s * d * 0.25 + Vector3(0, rise * 0.5, 0)), Vector3(w + 0.6, 0.15, d * 0.5 / cos(slope) + 0.5), tile)
	# gable ends
	for s: float in [-1.0, 1.0]:
		cm.box("frame", Transform3D(Basis(ax, Vector3.UP, az), c + ax * s * (w * 0.5 - 0.1) + Vector3(0, rise * 0.35, 0)), Vector3(0.2, rise * 0.7, d * 0.5), Color(0.85, 0.83, 0.78))


func _cyl(mat: String, base: Vector3, r: float, hgt: float, col: Color) -> void:
	cm.cyl(mat, base, r, hgt, col)

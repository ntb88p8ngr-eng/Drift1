extends RefCounted
## Detailed procedural buildings. Every building is one ArrayMesh with a few shared materials
## (walls, roof tiles, wood, trim, metal, concrete; colours come from vertex colours so all houses
## share them) plus the scenery's window glass, which glows at night.
## Styles: "jp" (two-storey Japanese house with hip or gable roof, balcony, garden wall), "shop"
## (convenience store with glass front and parking), "office" (three storeys, ribbon windows) and
## "barn". Local frame: the front faces -Z (the road).

const MeshKit = preload("res://scripts/util/mesh_kit.gd")
const TexKit = preload("res://scripts/util/tex_kit.gd")
const SignAtlas = preload("res://scripts/world/sign_atlas.gd")

enum { WALL, ROOF, WOOD, TRIM, METAL, CONCRETE, GLASS, PLASTER, COUNT }

static var _mats := {}

var rng: RandomNumberGenerator
var window_mat: Material
var details          # details.gd – pots, mailboxes, benches, signs
var _st: Array = []
var _xf := Transform3D.IDENTITY     # world transform of the building (for props placed via details)


static func _tex(kind: String) -> ImageTexture:
	var key := "tex_" + kind
	if _mats.has(key):
		return _mats[key]
	var size := 128
	var img := Image.create(size, size, true, Image.FORMAT_RGB8)
	var noise := FastNoiseLite.new()
	noise.seed = hash(kind)
	noise.frequency = 0.09
	for y in size:
		for x in size:
			var n := noise.get_noise_2d(x, y) * 0.5 + 0.5
			var v := 0.85 + n * 0.15
			match kind:
				"siding":
					var row := y % 16
					v *= 0.78 if row == 0 else (0.9 if row == 1 else 1.0)
					v *= 1.0 - float(row) * 0.004
				"tiles":
					var row := y % 32
					var col := (x + (16 if (y / 32) % 2 == 1 else 0)) % 32
					var curve := sin(float(col) / 32.0 * PI)
					v = 0.55 + 0.45 * curve
					v *= 1.0 - smoothstep(24.0, 31.0, float(row)) * 0.45
					v *= 0.9 + n * 0.2
				"planks":
					var col := x % 21
					var grain := sin((float(y) + noise.get_noise_2d(x * 3.0, y * 0.2) * 30.0) * 0.35) * 0.06
					v = (0.8 if col == 0 else 0.95) + grain + (n - 0.5) * 0.2
				"corrugated":
					v = 0.75 + 0.25 * sin(float(x) / 8.0 * TAU) + (n - 0.5) * 0.15
				"concrete":
					v = 0.8 + n * 0.25 - (0.12 if x % 64 == 0 or y % 64 == 0 else 0.0)
				_:
					v = 0.9 + n * 0.12
			img.set_pixel(x, y, Color(v, v, v))
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	_mats[key] = t
	return t


static func _material(surf: int) -> Material:
	var key := "mat_%d" % surf
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.85
	match surf:
		WALL:
			m.albedo_texture = _tex("siding")
		PLASTER:
			m.albedo_texture = _tex("plaster")
		ROOF:
			m.albedo_texture = _tex("tiles")
			m.roughness = 0.6
			m.metallic = 0.15
		WOOD:
			m.albedo_texture = _tex("planks")
		TRIM:
			m.roughness = 0.55
		METAL:
			m.albedo_texture = _tex("corrugated")
			m.metallic = 0.55
			m.roughness = 0.45
		CONCRETE:
			m.albedo_texture = _tex("concrete")
			m.roughness = 0.95
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_mats[key] = m
	return m


## Builds a building; returns a Node3D whose origin is on the ground in the middle of the lot.
## `xf` = the transform the node will get (needed for the props placed through `details`).
## Paths of the last building: [local start, width, kind] – the scenery leads them to the road.
var paths: Array = []


func make(style: String, xf: Transform3D) -> Node3D:
	_xf = xf
	paths = []
	_st.clear()
	for k in COUNT:
		_st.append(MeshKit.new_st())
	var root := Node3D.new()
	root.name = "House_" + style
	match style:
		"shop":
			_shop(root)
		"office":
			_office(root)
		"barn":
			_barn(root)
		_:
			_jp_house(root)
	var mesh := ArrayMesh.new()
	var counts := [0]
	for k in COUNT:
		var st: SurfaceTool = _st[k]
		var arr := st.commit_to_arrays()
		var verts = arr[Mesh.ARRAY_VERTEX]
		if verts == null or (verts as PackedVector3Array).is_empty():
			continue
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		mesh.surface_set_material(mesh.get_surface_count() - 1, window_mat if k == GLASS else _material(k))
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.name = "Building"
	root.add_child(mi)
	return root


# ---------------------------------------------------------------------------
# Primitive helpers (local coordinates)
# ---------------------------------------------------------------------------
func _box(surf: int, pos: Vector3, size: Vector3, col := Color.WHITE, rot := Vector3.ZERO, uv := 1.0) -> void:
	MeshKit.box(_st[surf], Transform3D(Basis.from_euler(rot), pos), size, col, uv)


func _quad(surf: int, a: Vector3, b: Vector3, c: Vector3, d: Vector3, outward: Vector3, col := Color.WHITE, uv := 1.0) -> void:
	# planar UVs in metres along the quad's edges
	var u := (b - a).length() * uv
	var v := (d - a).length() * uv
	MeshKit.quad(_st[surf], a, b, c, d, outward, Vector2(0, v), Vector2(u, v), Vector2(u, 0), Vector2(0, 0), col)


func _tri(surf: int, a: Vector3, b: Vector3, c: Vector3, outward: Vector3, col := Color.WHITE, uv := 1.0) -> void:
	var n := outward.normalized()
	var w := (b - a).length() * uv
	MeshKit.tri(_st[surf], a, b, c, n, n, n, Vector2(0, 0), Vector2(w, 0), Vector2(w * 0.5, (c - a).length() * uv), outward, col)


## Window in a wall. `pos` = centre on the wall surface, `n` = outward normal (horizontal).
func _window(pos: Vector3, n: Vector3, w: float, h: float, frame_col: Color, sill := true, lattice := false, shutter := false) -> void:
	var x := Vector3.UP.cross(n).normalized()
	var basis := Basis(x, Vector3.UP, n)
	var t := 0.07
	var out := n * 0.04
	# glass pane
	MeshKit.box(_st[GLASS], Transform3D(basis, pos + n * 0.01), Vector3(w, h, 0.04))
	# frame
	MeshKit.box(_st[TRIM], Transform3D(basis, pos + out + Vector3.UP * (h * 0.5)), Vector3(w + t * 2.0, t, 0.08), frame_col)
	MeshKit.box(_st[TRIM], Transform3D(basis, pos + out - Vector3.UP * (h * 0.5)), Vector3(w + t * 2.0, t, 0.08), frame_col)
	MeshKit.box(_st[TRIM], Transform3D(basis, pos + out + x * (w * 0.5)), Vector3(t, h, 0.08), frame_col)
	MeshKit.box(_st[TRIM], Transform3D(basis, pos + out - x * (w * 0.5)), Vector3(t, h, 0.08), frame_col)
	# mullion
	MeshKit.box(_st[TRIM], Transform3D(basis, pos + out * 0.8), Vector3(0.04, h, 0.05), frame_col)
	if lattice:
		for k in range(1, 4):
			MeshKit.box(_st[WOOD], Transform3D(basis, pos + n * 0.06 + Vector3.UP * (h * (float(k) / 4.0 - 0.5))), Vector3(w, 0.025, 0.03), Color(0.45, 0.3, 0.18))
		for k in range(1, 5):
			MeshKit.box(_st[WOOD], Transform3D(basis, pos + n * 0.06 + x * (w * (float(k) / 5.0 - 0.5))), Vector3(0.025, h, 0.03), Color(0.45, 0.3, 0.18))
	if sill:
		MeshKit.box(_st[TRIM], Transform3D(basis, pos + n * 0.08 - Vector3.UP * (h * 0.5 + 0.05)), Vector3(w + 0.25, 0.06, 0.18), frame_col.darkened(0.1))
	if shutter:
		# rain-shutter box (amado) above the window
		MeshKit.box(_st[METAL], Transform3D(basis, pos + n * 0.14 + Vector3.UP * (h * 0.5 + 0.2)), Vector3(w + 0.2, 0.3, 0.26), Color(0.6, 0.6, 0.58, 1.0))


func _door(pos: Vector3, n: Vector3, w: float, h: float, col: Color, glass := true) -> void:
	var x := Vector3.UP.cross(n).normalized()
	var basis := Basis(x, Vector3.UP, n)
	MeshKit.box(_st[WOOD], Transform3D(basis, pos + n * 0.02 + Vector3.UP * (h * 0.5)), Vector3(w, h, 0.06), col)
	if glass:
		MeshKit.box(_st[GLASS], Transform3D(basis, pos + n * 0.055 + Vector3.UP * (h * 0.62)), Vector3(w * 0.5, h * 0.45, 0.02))
	MeshKit.box(_st[TRIM], Transform3D(basis, pos + n * 0.07 + x * (w * 0.35) + Vector3.UP * (h * 0.48)), Vector3(0.04, 0.2, 0.05), Color(0.8, 0.78, 0.7, 0.5))
	# frame
	MeshKit.box(_st[TRIM], Transform3D(basis, pos + n * 0.05 + Vector3.UP * (h + 0.04)), Vector3(w + 0.16, 0.08, 0.1), Color(0.2, 0.2, 0.2))
	for s in [-1.0, 1.0]:
		MeshKit.box(_st[TRIM], Transform3D(basis, pos + n * 0.05 + x * (w * 0.5 + 0.04) * s + Vector3.UP * (h * 0.5)), Vector3(0.08, h, 0.1), Color(0.2, 0.2, 0.2))


## Hip roof over the rectangle (centre c at eave height), `rise` = ridge height above the eaves.
func _hip_roof(c: Vector3, w: float, d: float, rise: float, col: Color) -> void:
	var hx := w * 0.5
	var hz := d * 0.5
	var along_x := w >= d
	var r := (hx - hz) if along_x else (hz - hx)
	var p0 := c + Vector3(-hx, 0, -hz)
	var p1 := c + Vector3(hx, 0, -hz)
	var p2 := c + Vector3(hx, 0, hz)
	var p3 := c + Vector3(-hx, 0, hz)
	var ra: Vector3
	var rb: Vector3
	if along_x:
		ra = c + Vector3(-r, rise, 0)
		rb = c + Vector3(r, rise, 0)
		_quad(ROOF, p0, p1, rb, ra, Vector3(0, hz, -rise).normalized() + Vector3(0, 0.001, 0), col, 1.0)
		_quad(ROOF, p2, p3, ra, rb, Vector3(0, hz, rise).normalized(), col, 1.0)
		_tri(ROOF, p3, p0, ra, Vector3(-rise, hx - r, 0).normalized(), col)
		_tri(ROOF, p1, p2, rb, Vector3(rise, hx - r, 0).normalized(), col)
		_box(ROOF, (ra + rb) * 0.5 + Vector3(0, 0.06, 0), Vector3(r * 2.0 + 0.3, 0.16, 0.26), col.darkened(0.25))
	else:
		ra = c + Vector3(0, rise, -r)
		rb = c + Vector3(0, rise, r)
		_quad(ROOF, p1, p2, rb, ra, Vector3(hx, rise * 0.0 + hx, 0).normalized(), col)
		_quad(ROOF, p3, p0, ra, rb, Vector3(-hx, hx, 0).normalized(), col)
		_tri(ROOF, p0, p1, ra, Vector3(0, hz - r, -rise).normalized(), col)
		_tri(ROOF, p2, p3, rb, Vector3(0, hz - r, rise).normalized(), col)
		_box(ROOF, (ra + rb) * 0.5 + Vector3(0, 0.06, 0), Vector3(0.26, 0.16, r * 2.0 + 0.3), col.darkened(0.25))
	# underside of the eaves and fascia boards
	_quad(TRIM, p0, p1, p2, p3, Vector3.DOWN, Color(0.35, 0.3, 0.26))
	for e in [[p0, p1], [p1, p2], [p2, p3], [p3, p0]]:
		var a: Vector3 = e[0]
		var b: Vector3 = e[1]
		var mid := (a + b) * 0.5 - Vector3(0, 0.08, 0)
		var len := (b - a).length()
		var dir := (b - a).normalized()
		MeshKit.box(_st[TRIM], Transform3D(Basis(dir, Vector3.UP, dir.cross(Vector3.UP)), mid), Vector3(len, 0.2, 0.05), Color(0.3, 0.28, 0.25))
		# gutter
		var outn := dir.cross(Vector3.UP).normalized()
		if outn.dot(mid - c) < 0.0:
			outn = -outn
		MeshKit.box(_st[METAL], Transform3D(Basis(dir, Vector3.UP, outn), mid + outn * 0.1 - Vector3(0, 0.05, 0)), Vector3(len, 0.1, 0.12), Color(0.5, 0.5, 0.5, 0.6))


## Gable roof, ridge along X, with gable walls of `gable_surf`.
func _gable_roof(c: Vector3, w: float, d: float, rise: float, over: float, col: Color, gable_surf: int, gable_col: Color) -> void:
	var hx := w * 0.5 + over
	var hz := d * 0.5 + over
	var ridge_a := c + Vector3(-hx, rise, 0)
	var ridge_b := c + Vector3(hx, rise, 0)
	var e0 := c + Vector3(-hx, 0, -hz)
	var e1 := c + Vector3(hx, 0, -hz)
	var e2 := c + Vector3(hx, 0, hz)
	var e3 := c + Vector3(-hx, 0, hz)
	# slope compensated for the overhang (eaves drop a bit)
	var drop := rise * over / (d * 0.5 + over)
	e0.y -= drop * 0.0
	_quad(ROOF, e0, e1, ridge_b, ridge_a, Vector3(0, hz, -rise).normalized(), col)
	_quad(ROOF, e2, e3, ridge_a, ridge_b, Vector3(0, hz, rise).normalized(), col)
	# thickness: underside
	_quad(TRIM, e0 - Vector3(0, 0.12, 0), e1 - Vector3(0, 0.12, 0), ridge_b - Vector3(0, 0.12, 0), ridge_a - Vector3(0, 0.12, 0), Vector3(0, -hz, rise).normalized(), Color(0.3, 0.27, 0.24))
	_quad(TRIM, e2 - Vector3(0, 0.12, 0), e3 - Vector3(0, 0.12, 0), ridge_a - Vector3(0, 0.12, 0), ridge_b - Vector3(0, 0.12, 0), Vector3(0, -hz, -rise).normalized(), Color(0.3, 0.27, 0.24))
	# gable triangles (walls)
	var gx := w * 0.5
	var grise := rise * (d * 0.5) / hz
	for s in [-1.0, 1.0]:
		var a := c + Vector3(gx * s, 0, -d * 0.5)
		var b := c + Vector3(gx * s, 0, d * 0.5)
		var top := c + Vector3(gx * s, grise, 0)
		_tri(gable_surf, a, b, top, Vector3(s, 0, 0), gable_col)
		# barge boards
		for q in [[a, top], [b, top]]:
			var p: Vector3 = q[0]
			var t: Vector3 = q[1]
			var len := (t - p).length() + over
			var dir := (t - p).normalized()
			MeshKit.box(_st[TRIM], Transform3D(Basis(Vector3(s, 0, 0).cross(dir).normalized(), dir, Vector3(s, 0, 0)).orthonormalized(),
				(p + t) * 0.5 + Vector3(s * (over + 0.03), 0.02, 0)), Vector3(0.22, len, 0.05), Color(0.3, 0.27, 0.24))
	_box(ROOF, (ridge_a + ridge_b) * 0.5 + Vector3(0, 0.05, 0), Vector3(hx * 2.0 + 0.1, 0.14, 0.26), col.darkened(0.25))


func _prop(key: String, local: Vector3, yaw := 0.0, tint := Color(1, 1, 1, 1)) -> void:
	if details:
		details.add(key, _xf * Transform3D(Basis(Vector3.UP, yaw), local), tint)


func _car(local: Vector3, yaw: float, kind := "") -> void:
	if details:
		details.add_parked_car(_xf * Transform3D(Basis(Vector3.UP, yaw), local), kind)


func _pot(local: Vector3) -> void:
	if details:
		details.add_pot(_xf * local)


func _ac_unit(pos: Vector3, n: Vector3) -> void:
	var x := Vector3.UP.cross(n).normalized()
	var basis := Basis(x, Vector3.UP, n)
	MeshKit.box(_st[TRIM], Transform3D(basis, pos + n * 0.18), Vector3(0.8, 0.6, 0.3), Color(0.88, 0.88, 0.85))
	MeshKit.box(_st[METAL], Transform3D(basis, pos + n * 0.335 + x * 0.12), Vector3(0.42, 0.42, 0.02), Color(0.3, 0.3, 0.3, 0.6))
	MeshKit.box(_st[METAL], Transform3D(basis, pos + n * 0.05 - x * 0.46 + Vector3.UP * 0.4), Vector3(0.05, 1.0, 0.05), Color(0.85, 0.85, 0.82, 0.8))


# ---------------------------------------------------------------------------
# Styles
# ---------------------------------------------------------------------------
func _jp_house(root: Node3D) -> void:
	var walls := [Color(0.93, 0.9, 0.82), Color(0.86, 0.84, 0.8), Color(0.84, 0.78, 0.66), Color(0.78, 0.83, 0.86), Color(0.95, 0.95, 0.94), Color(0.72, 0.62, 0.52)]
	var roofs := [Color(0.22, 0.24, 0.28), Color(0.16, 0.2, 0.3), Color(0.35, 0.22, 0.16), Color(0.42, 0.14, 0.1), Color(0.3, 0.32, 0.33)]
	var wall_col: Color = walls[rng.randi() % walls.size()]
	var roof_col: Color = roofs[rng.randi() % roofs.size()]
	var frame_col: Color = [Color(0.85, 0.85, 0.83), Color(0.35, 0.3, 0.26), Color(0.2, 0.2, 0.22)][rng.randi() % 3]
	var w := rng.randf_range(8.0, 10.0)
	var d := rng.randf_range(7.0, 8.6)
	var base := 0.5
	var h1 := 2.9
	var h2 := 2.7
	var top := base + h1 + h2
	# foundation reaching into the ground, walls, floor band
	_box(CONCRETE, Vector3(0, base * 0.5 - 0.7, 0), Vector3(w + 0.2, base + 1.4, d + 0.2), Color(0.62, 0.62, 0.6))
	_box(WALL, Vector3(0, base + (h1 + h2) * 0.5, 0), Vector3(w, h1 + h2, d), wall_col, Vector3.ZERO, 0.5)
	_box(TRIM, Vector3(0, base + h1, 0), Vector3(w + 0.08, 0.18, d + 0.08), frame_col.darkened(0.2))
	# roof
	if rng.randf() < 0.55:
		_hip_roof(Vector3(0, top, 0), w + 1.4, d + 1.4, 2.1, roof_col)
	else:
		_gable_roof(Vector3(0, top, 0), w, d, 2.3, 0.65, roof_col, WALL, wall_col)
	var front := Vector3(0, 0, -1)
	var fz := -d * 0.5
	# entrance with small canopy
	var door_x := -w * 0.25
	_door(Vector3(door_x, base, fz), front, 1.0, 2.1, Color(0.4, 0.27, 0.16))
	_box(CONCRETE, Vector3(door_x, base * 0.5, fz - 0.55), Vector3(1.8, base, 1.1), Color(0.7, 0.7, 0.68))
	_box(ROOF, Vector3(door_x, base + 2.55, fz - 0.55), Vector3(1.9, 0.1, 1.2), roof_col, Vector3(-0.2, 0, 0))
	_box(TRIM, Vector3(door_x + 0.75, base + 1.9, fz - 0.03), Vector3(0.14, 0.2, 0.06), Color(1.0, 0.95, 0.8))   # door lamp
	# ground floor windows
	_window(Vector3(w * 0.15, base + 1.45, fz), front, 1.6, 1.2, frame_col, true, rng.randf() < 0.4, rng.randf() < 0.5)
	_window(Vector3(w * 0.38, base + 1.45, fz), front, 0.9, 1.1, frame_col, true, false, false)
	# upper floor: balcony with sliding door and railing, window next to it
	var bal_w := w * 0.55
	var bal_x := w * 0.12
	var y2 := base + h1
	_box(CONCRETE, Vector3(bal_x, y2 + 0.05, fz - 0.55), Vector3(bal_w, 0.18, 1.1), Color(0.75, 0.75, 0.73))
	for k in 9:
		var t := float(k) / 8.0
		_box(METAL, Vector3(bal_x - bal_w * 0.5 + t * bal_w, y2 + 0.6, fz - 1.07), Vector3(0.035, 0.95, 0.035), Color(0.3, 0.3, 0.32, 0.5))
	_box(METAL, Vector3(bal_x, y2 + 1.1, fz - 1.07), Vector3(bal_w, 0.06, 0.07), Color(0.3, 0.3, 0.32, 0.5))
	for s in [-1.0, 1.0]:
		_box(METAL, Vector3(bal_x + bal_w * 0.5 * s, y2 + 0.6, fz - 0.55), Vector3(0.05, 0.95, 1.05), Color(0.3, 0.3, 0.32, 0.5))
	_window(Vector3(bal_x, y2 + 1.2, fz), front, 1.8, 1.9, frame_col, false)
	# laundry pole
	_box(METAL, Vector3(bal_x, y2 + 1.75, fz - 0.8), Vector3(bal_w * 0.8, 0.04, 0.04), Color(0.8, 0.8, 0.8, 0.5))
	_window(Vector3(-w * 0.32, y2 + 1.35, fz), front, 1.1, 1.1, frame_col, true, false, true)
	# sides and back
	for s in [-1.0, 1.0]:
		var n := Vector3(s, 0, 0)
		for k in 2:
			var z := -d * 0.22 + k * d * 0.44
			_window(Vector3(w * 0.5 * s, base + 1.45, z), n, 1.0, 1.0, frame_col, true, false, rng.randf() < 0.4)
			_window(Vector3(w * 0.5 * s, y2 + 1.35, z), n, 1.0, 1.0, frame_col, true)
	for k in 3:
		_window(Vector3(-w * 0.3 + k * w * 0.3, y2 + 1.35, d * 0.5), Vector3(0, 0, 1), 1.0, 1.0, frame_col, true)
	_window(Vector3(-w * 0.2, base + 1.45, d * 0.5), Vector3(0, 0, 1), 1.4, 1.1, frame_col, true)
	# AC units, downpipes
	_ac_unit(Vector3(w * 0.5, base + 0.35, d * 0.15), Vector3(1, 0, 0))
	_ac_unit(Vector3(bal_x + bal_w * 0.3, y2 + 0.45, fz - 0.95 + 0.3), front)
	for c in [Vector3(-1, 0, -1), Vector3(1, 0, -1), Vector3(1, 0, 1), Vector3(-1, 0, 1)]:
		_box(METAL, Vector3(c.x * (w * 0.5 + 0.1), top * 0.5, c.z * (d * 0.5 + 0.1)), Vector3(0.09, top, 0.09), Color(0.5, 0.5, 0.5, 0.6))
	# TV antenna
	var ax := w * 0.2
	_box(METAL, Vector3(ax, top + 2.8, 0), Vector3(0.05, 2.0, 0.05), Color(0.6, 0.6, 0.6, 0.5))
	for k in 3:
		_box(METAL, Vector3(ax, top + 3.2 + k * 0.25, 0), Vector3(0.03, 0.03, 1.2 - k * 0.25), Color(0.6, 0.6, 0.6, 0.5))
	# garden: block wall with gate towards the road, mailbox, flower pots
	var gz := fz - 3.0
	var gate_x := door_x
	var wall_c := Color(0.72, 0.71, 0.68)
	var left_len := (gate_x - 0.9) - (-w * 0.5 - 1.0)
	var right_len := (w * 0.5 + 1.0) - (gate_x + 0.9)
	_box(CONCRETE, Vector3(-w * 0.5 - 1.0 + left_len * 0.5, 0.35, gz), Vector3(left_len, 1.5, 0.2), wall_c)
	_box(CONCRETE, Vector3(gate_x + 0.9 + right_len * 0.5, 0.35, gz), Vector3(right_len, 1.5, 0.2), wall_c)
	_box(TRIM, Vector3(-w * 0.5 - 1.0 + left_len * 0.5, 1.13, gz), Vector3(left_len + 0.04, 0.06, 0.26), wall_c.darkened(0.2))
	_box(TRIM, Vector3(gate_x + 0.9 + right_len * 0.5, 1.13, gz), Vector3(right_len + 0.04, 0.06, 0.26), wall_c.darkened(0.2))
	for s in [-1.0, 1.0]:
		_box(CONCRETE, Vector3(gate_x + 0.95 * s, 0.55, gz), Vector3(0.35, 1.9, 0.35), wall_c.darkened(0.1))
		_box(WALL, Vector3(-w * 0.5 - 1.0 if s < 0 else w * 0.5 + 1.0, 0.35, (gz + d * 0.5) * 0.5 - 0.1), Vector3(0.2, 1.5, d * 0.5 - gz + 0.2), wall_c)
	# stepping stones
	for k in 3:
		_box(CONCRETE, Vector3(gate_x + rng.randf_range(-0.1, 0.1), 0.03, gz + 0.8 + k * 0.7), Vector3(0.6, 0.08, 0.5), Color(0.6, 0.6, 0.58))
	_prop("mailbox", Vector3(gate_x + 1.4, 0, gz - 0.25))
	# lamps at the gate, bins and a bicycle outside the wall
	_prop("garden_lamp", Vector3(gate_x - 1.25, 0, gz - 0.35))
	_prop("garden_lamp", Vector3(gate_x + 1.25, 0, gz - 0.35))
	_prop("wheelie_bin", Vector3(gate_x + 2.3, 0, gz - 0.5), rng.randf_range(-0.2, 0.2), Color(0.2, 0.4, 0.25))
	_prop("wheelie_bin", Vector3(gate_x + 3.0, 0, gz - 0.5), rng.randf_range(-0.2, 0.2), Color(0.25, 0.3, 0.6))
	if rng.randf() < 0.7:
		_prop("bicycle", Vector3(gate_x - 2.1, 0, gz - 0.35), PI * 0.5 + rng.randf_range(-0.15, 0.15), Color.from_hsv(rng.randf(), 0.6, 0.8))
	# parking space in front of the wall: concrete pad, a car on it most of the time
	var px := w * 0.25 + 0.5
	_box(CONCRETE, Vector3(px, 0.02, gz - 2.3), Vector3(5.2, 0.08, 2.8), Color(0.66, 0.66, 0.64))
	if rng.randf() < 0.75:
		_car(Vector3(px, 0.06, gz - 2.3), PI * 0.5 * (1.0 if rng.randf() < 0.5 else -1.0))
	paths.append([Vector3(gate_x, 0, gz - 0.25), 1.3, "paving"])
	paths.append([Vector3(px, 0, gz - 3.7), 3.0, "asphalt"])
	# washing on the balcony pole
	for k in rng.randi_range(2, 5):
		var cx := bal_x - bal_w * 0.35 + k * 0.45
		_box(TRIM, Vector3(cx, y2 + 1.45, fz - 0.8), Vector3(0.36, 0.55, 0.02), Color.from_hsv(rng.randf(), rng.randf_range(0.2, 0.7), rng.randf_range(0.6, 0.95)))
	_pot(Vector3(door_x + 0.9, base, fz - 0.7))
	_pot(Vector3(door_x - 0.9, base, fz - 0.7))
	for k in rng.randi_range(1, 3):
		_pot(Vector3(w * 0.1 + k * 0.7, 0.0, gz + 0.5))


func _shop(root: Node3D) -> void:
	var w := 11.0
	var d := 8.0
	var h := 3.8
	var white := Color(0.94, 0.94, 0.92)
	_box(CONCRETE, Vector3(0, -0.6, 0), Vector3(w + 0.4, 1.4, d + 0.4), Color(0.6, 0.6, 0.58))
	_box(PLASTER, Vector3(0, h * 0.5, 0), Vector3(w, h, d), white)
	# glass front with mullions
	var fz := -d * 0.5
	MeshKit.box(_st[GLASS], Transform3D(Basis.IDENTITY, Vector3(0, 1.45, fz - 0.01)), Vector3(w - 0.6, 2.5, 0.04))
	for k in 7:
		_box(TRIM, Vector3(-w * 0.5 + 0.3 + k * (w - 0.6) / 6.0, 1.45, fz - 0.05), Vector3(0.08, 2.6, 0.1), Color(0.25, 0.25, 0.27))
	_box(TRIM, Vector3(0, 0.18, fz - 0.05), Vector3(w - 0.5, 0.12, 0.12), Color(0.25, 0.25, 0.27))
	_box(TRIM, Vector3(0, 2.72, fz - 0.05), Vector3(w - 0.5, 0.12, 0.12), Color(0.25, 0.25, 0.27))
	# colour stripes (fascia) and the sign board
	_box(TRIM, Vector3(0, 3.0, fz - 0.06), Vector3(w + 0.1, 0.18, 0.14), Color(0.1, 0.55, 0.3))
	_box(TRIM, Vector3(0, 3.18, fz - 0.06), Vector3(w + 0.1, 0.18, 0.14), Color(0.95, 0.5, 0.1))
	_box(TRIM, Vector3(0, 3.36, fz - 0.06), Vector3(w + 0.1, 0.18, 0.14), Color(0.85, 0.12, 0.12))
	if details:
		# board front (+Z of the board) must face the road (-Z here): mirror X to keep it right-handed
		details.add("bill", _xf * Transform3D(Basis(Vector3(-4.8, 0, 0), Vector3(0, 0.6, 0), Vector3(0, 0, -1)), Vector3(0, 4.25, fz - 0.1)),
			SignAtlas.cell("banner", "hana_mart"))
	# parapet and rooftop units
	_box(PLASTER, Vector3(0, h + 0.35, fz + 0.1), Vector3(w, 0.9, 0.2), white)
	_box(PLASTER, Vector3(0, h + 0.35, -fz - 0.1), Vector3(w, 0.9, 0.2), white)
	for s in [-1.0, 1.0]:
		_box(PLASTER, Vector3(s * (w * 0.5 - 0.1), h + 0.35, 0), Vector3(0.2, 0.9, d), white)
	_box(CONCRETE, Vector3(0, h + 0.05, 0), Vector3(w - 0.4, 0.1, d - 0.4), Color(0.5, 0.5, 0.5))
	for k in 3:
		_box(METAL, Vector3(-3.0 + k * 2.4, h + 0.5, 1.5), Vector3(1.4, 0.9, 1.0), Color(0.8, 0.8, 0.78, 0.7))
	# side door, back
	_door(Vector3(w * 0.5, 0, d * 0.25), Vector3(1, 0, 0), 0.9, 2.1, Color(0.6, 0.6, 0.6), false)
	_ac_unit(Vector3(-w * 0.5, 0.3, 0.0), Vector3(-1, 0, 0))
	# forecourt: parking bays with white lines and wheel stops
	var pz := fz - 6.0
	_box(CONCRETE, Vector3(0, -0.02, pz + 1.0), Vector3(w + 6.0, 0.1, 9.0), Color(0.3, 0.3, 0.31))
	for k in 5:
		var x := -w * 0.5 + 1.0 + k * 2.6
		_box(TRIM, Vector3(x, 0.035, pz), Vector3(0.12, 0.01, 5.0), Color(0.92, 0.92, 0.9))
		if k < 4:
			_box(CONCRETE, Vector3(x + 1.3, 0.1, pz + 2.1), Vector3(1.4, 0.15, 0.22), Color(0.75, 0.75, 0.72))
	# cars in the bays (nose in), bicycles by the door, a hydrant
	for k in 4:
		if rng.randf() < 0.6:
			_car(Vector3(-w * 0.5 + 1.0 + k * 2.6 + 1.3, 0.04, pz - 0.3), PI + rng.randf_range(-0.04, 0.04))
	for k in rng.randi_range(1, 3):
		_prop("bicycle", Vector3(w * 0.5 - 0.6, 0, fz - 1.4 - k * 0.55), PI * 0.5, Color.from_hsv(rng.randf(), 0.7, 0.8))
	_prop("hydrant", Vector3(w * 0.5 + 1.2, 0, pz - 3.5))
	paths.append([Vector3(0, 0, pz - 3.6), 6.0, "asphalt"])
	# furniture along the glass front
	_prop("bin", Vector3(-w * 0.5 + 0.8, 0, fz - 0.8))
	_prop("bin", Vector3(-w * 0.5 + 1.5, 0, fz - 0.8))
	_prop("bench", Vector3(w * 0.2, 0, fz - 1.0), PI)
	_prop("planter", Vector3(-w * 0.2, 0, fz - 0.9), PI)
	_pot(Vector3(w * 0.45, 0, fz - 0.7))


func _office(root: Node3D) -> void:
	var w := 14.0
	var d := 10.0
	var floors := 3
	var fh := 3.4
	var h := floors * fh
	var panel: Color = [Color(0.7, 0.72, 0.74), Color(0.78, 0.75, 0.7), Color(0.55, 0.58, 0.62)][rng.randi() % 3]
	_box(CONCRETE, Vector3(0, -0.6, 0), Vector3(w + 0.4, 1.4, d + 0.4), Color(0.6, 0.6, 0.58))
	_box(PLASTER, Vector3(0, h * 0.5, 0), Vector3(w, h, d), panel)
	var fz := -d * 0.5
	for f in floors:
		var y := f * fh
		# ribbon windows with mullions on all four sides
		for side in 4:
			var n: Vector3 = [Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(-1, 0, 0)][side]
			var len := w if side % 2 == 0 else d
			var c := n * ((d if side % 2 == 0 else w) * 0.5)
			var x := Vector3.UP.cross(n).normalized()
			var basis := Basis(x, Vector3.UP, n)
			if f == 0 and side == 0:
				continue
			MeshKit.box(_st[GLASS], Transform3D(basis, c + n * 0.01 + Vector3.UP * (y + 1.75)), Vector3(len - 1.0, 1.5, 0.04))
			var mcount := int(len / 1.6)
			for k in mcount + 1:
				MeshKit.box(_st[TRIM], Transform3D(basis, c + n * 0.05 + x * (-len * 0.5 + 0.5 + k * (len - 1.0) / mcount) + Vector3.UP * (y + 1.75)),
					Vector3(0.07, 1.55, 0.08), Color(0.2, 0.22, 0.25))
			MeshKit.box(_st[TRIM], Transform3D(basis, c + n * 0.06 + Vector3.UP * (y + 0.95)), Vector3(len, 0.1, 0.14), panel.darkened(0.25))
	# ground floor entrance: glass front, canopy, steps
	MeshKit.box(_st[GLASS], Transform3D(Basis.IDENTITY, Vector3(0, 1.4, fz - 0.01)), Vector3(w * 0.6, 2.6, 0.04))
	for k in 6:
		_box(TRIM, Vector3(-w * 0.3 + k * w * 0.12, 1.4, fz - 0.05), Vector3(0.08, 2.7, 0.1), Color(0.2, 0.22, 0.25))
	_box(CONCRETE, Vector3(0, 3.0, fz - 1.3), Vector3(5.0, 0.25, 2.6), panel.darkened(0.15))
	for s in [-1.0, 1.0]:
		_box(METAL, Vector3(s * 2.2, 1.45, fz - 2.4), Vector3(0.12, 2.9, 0.12), Color(0.7, 0.7, 0.7, 0.5))
	_box(CONCRETE, Vector3(0, 0.08, fz - 1.3), Vector3(5.2, 0.16, 2.8), Color(0.7, 0.7, 0.68))
	# roof parapet, rooftop units, water tank
	_box(PLASTER, Vector3(0, h + 0.5, fz + 0.12), Vector3(w, 1.0, 0.25), panel.darkened(0.1))
	_box(PLASTER, Vector3(0, h + 0.5, -fz - 0.12), Vector3(w, 1.0, 0.25), panel.darkened(0.1))
	for s in [-1.0, 1.0]:
		_box(PLASTER, Vector3(s * (w * 0.5 - 0.12), h + 0.5, 0), Vector3(0.25, 1.0, d), panel.darkened(0.1))
	_box(CONCRETE, Vector3(0, h + 0.05, 0), Vector3(w - 0.4, 0.1, d - 0.4), Color(0.45, 0.45, 0.45))
	for k in 4:
		_box(METAL, Vector3(-4.5 + k * 2.2, h + 0.6, 2.0), Vector3(1.6, 1.1, 1.2), Color(0.82, 0.82, 0.8, 0.7))
	_box(METAL, Vector3(4.5, h + 1.4, -1.5), Vector3(2.2, 2.4, 2.2), Color(0.3, 0.45, 0.6, 0.7))
	# company sign on the facade
	if details:
		var company := "harbor" if rng.randf() < 0.5 else "kurohana_motors"
		details.add("bill", _xf * Transform3D(Basis(Vector3(-9.0, 0, 0), Vector3(0, 1.125, 0), Vector3(0, 0, -1)), Vector3(0, h - 0.9, fz - 0.15)),
			SignAtlas.cell("banner", company))
	# car park row in front, bicycles by the entrance
	_box(CONCRETE, Vector3(0, 0.0, fz - 6.2), Vector3(w + 2.0, 0.06, 5.2), Color(0.32, 0.32, 0.33))
	for k in 4:
		var cx: float = [-5.6, -2.9, 2.9, 5.6][k]
		_box(TRIM, Vector3(cx - 1.35, 0.035, fz - 6.2), Vector3(0.1, 0.01, 4.6), Color(0.9, 0.9, 0.88))
		if rng.randf() < 0.75:
			_car(Vector3(cx, 0.04, fz - 6.2), PI + rng.randf_range(-0.04, 0.04))
	for k in 3:
		_prop("bicycle", Vector3(-w * 0.5 + 1.0, 0, fz - 1.2 - k * 0.6), PI * 0.5, Color.from_hsv(rng.randf(), 0.6, 0.8))
	paths.append([Vector3(0, 0, fz - 2.9), 2.4, "paving"])
	paths.append([Vector3(4.2, 0, fz - 8.8), 4.5, "asphalt"])
	_prop("planter", Vector3(-3.6, 0, fz - 1.4), PI)
	_prop("planter", Vector3(3.6, 0, fz - 1.4), PI)
	_prop("bin", Vector3(2.9, 0, fz - 2.8))


func _barn(root: Node3D) -> void:
	var w := 9.0
	var d := 12.0
	var h := 4.6
	var red: Color = [Color(0.48, 0.14, 0.1), Color(0.42, 0.32, 0.22), Color(0.3, 0.3, 0.28)][rng.randi() % 3]
	_box(CONCRETE, Vector3(0, -0.5, 0), Vector3(w + 0.3, 1.2, d + 0.3), Color(0.5, 0.5, 0.48))
	# plank walls: planks run vertically, so the texture is rotated via the box (uv scale 0.5)
	_box(WOOD, Vector3(0, h * 0.5, 0), Vector3(w, h, d), red, Vector3.ZERO, 0.5)
	# the gable faces the road: ridge along Z -> build rotated
	var roof_col := Color(0.55, 0.55, 0.55)
	var hz := d * 0.5 + 0.4
	var hx := w * 0.5 + 0.5
	var rise := 3.2
	var ra := Vector3(0, h + rise, -hz)
	var rb := Vector3(0, h + rise, hz)
	_quad(METAL, Vector3(-hx, h - 0.3, -hz), Vector3(-hx, h - 0.3, hz), rb, ra, Vector3(-rise, hx, 0).normalized(), roof_col, 0.5)
	_quad(METAL, Vector3(hx, h - 0.3, hz), Vector3(hx, h - 0.3, -hz), ra, rb, Vector3(rise, hx, 0).normalized(), roof_col, 0.5)
	_quad(TRIM, Vector3(-hx, h - 0.4, -hz), Vector3(-hx, h - 0.4, hz), rb - Vector3(0, 0.1, 0), ra - Vector3(0, 0.1, 0), Vector3(rise, -hx, 0).normalized(), Color(0.25, 0.2, 0.16))
	_quad(TRIM, Vector3(hx, h - 0.4, hz), Vector3(hx, h - 0.4, -hz), ra - Vector3(0, 0.1, 0), rb - Vector3(0, 0.1, 0), Vector3(-rise, -hx, 0).normalized(), Color(0.25, 0.2, 0.16))
	for s in [-1.0, 1.0]:
		var zc: float = d * 0.5 * s
		_tri(WOOD, Vector3(-w * 0.5, h, zc), Vector3(w * 0.5, h, zc), Vector3(0, h + rise * (w * 0.5) / hx, zc), Vector3(0, 0, s), red, 0.5)
	# big sliding door with cross braces, hay loft door
	var fz := -d * 0.5
	var door_col := red.lightened(0.15)
	_box(WOOD, Vector3(0, 1.7, fz - 0.06), Vector3(3.4, 3.4, 0.1), door_col)
	for k in [-1.0, 1.0]:
		_box(TRIM, Vector3(0, 1.7, fz - 0.13), Vector3(0.14, 4.6, 0.05), Color(0.9, 0.88, 0.8), Vector3(0, 0, 0.78 * k))
	_box(TRIM, Vector3(0, 1.7, fz - 0.12), Vector3(3.5, 0.14, 0.03), Color(0.9, 0.88, 0.8))
	_box(METAL, Vector3(0, 3.55, fz - 0.15), Vector3(4.4, 0.1, 0.12), Color(0.3, 0.3, 0.3, 0.5))
	_box(WOOD, Vector3(0, h + 1.0, fz - 0.06), Vector3(1.4, 1.3, 0.08), door_col)
	for s in [-1.0, 1.0]:
		_window(Vector3(w * 0.5 * s, 2.2, 0.0), Vector3(s, 0, 0), 0.9, 0.8, Color(0.9, 0.88, 0.8), false)
	# the farm van in front of the barn, a gravel drive
	_car(Vector3(2.8, 0.0, fz - 4.6), rng.randf_range(-0.4, 0.4), "car_van")
	paths.append([Vector3(0, 0, fz - 0.4), 4.0, "gravel"])
	# hay bales and a fence
	_prop("hay_bale", Vector3(w * 0.5 + 1.6, 0, fz + 1.5), 0.3)
	_prop("hay_bale", Vector3(w * 0.5 + 1.8, 0, fz + 3.0), 1.4)
	_prop("hay_bale", Vector3(w * 0.5 + 1.7, 1.2, fz + 2.2), 0.8)
	for k in 8:
		var z := fz - 2.0 + k * 2.2
		_box(WOOD, Vector3(-w * 0.5 - 3.0, 0.6, z), Vector3(0.14, 1.4, 0.14), Color(0.45, 0.35, 0.25))
		if k < 7:
			for y in [0.45, 0.95]:
				_box(WOOD, Vector3(-w * 0.5 - 3.0, y, z + 1.1), Vector3(0.06, 0.12, 2.2), Color(0.5, 0.4, 0.28))

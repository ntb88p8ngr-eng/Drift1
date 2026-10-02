extends Node3D
## The Japanese city ("tokyo" track): blocks of buildings along every street – shops with lit fronts,
## awnings and vertical neon signs at street level, apartment blocks and office towers behind, a
## cluster of skyscrapers inside the expressway loop; the elevated expressway itself (deck, piers,
## lamps, overhead signs); the scramble crossing on the start avenue with its giant video screens,
## zebra stripes in every direction and crowds waiting at the corners; cherry trees with falling
## petals along the streets and in a park; a gas station with a konbini (drive-in through the wall),
## a bowling hall with the giant pin on the roof and the police headquarters with its patrol cars.
## Buildings, signs, trees and people are instanced; the facades light up window by window at night.

const MeshKit = preload("res://scripts/util/mesh_kit.gd")
const TexKit = preload("res://scripts/util/tex_kit.gd")
const Props = preload("res://scripts/world/prop_meshes.gd")
const Crowd = preload("res://scripts/world/crowd.gd")
const Colliders = preload("res://scripts/util/colliders.gd")

const SIGN_SHADER := """
shader_type spatial;
render_mode cull_disabled;

uniform sampler2D glyphs : source_color, filter_linear_mipmap;
uniform float glow = 0.2;
varying vec3 col;
varying float seed;

void vertex() {
	col = INSTANCE_CUSTOM.rgb;
	seed = INSTANCE_CUSTOM.a;
}

void fragment() {
	// each sign shows another column of the glyph sheet
	vec2 uv = vec2(UV.x * 0.25 + floor(seed * 4.0) * 0.25, UV.y);
	float g = texture(glyphs, uv).r;
	vec3 base = mix(col, vec3(1.0), g * 0.6);
	ALBEDO = base * 0.6;
	EMISSION = col * glow * (0.35 + 0.65 * g);
	ROUGHNESS = 0.4;
}
"""

const SCREEN_SHADER := """
shader_type spatial;
render_mode unshaded;

uniform float glow = 1.0;
uniform float seed = 0.0;

float h(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233)) + seed) * 43758.5453); }

void fragment() {
	// a video wall: scenes change every few seconds, scrolling colour fields, a ticker at the bottom
	float t = TIME * 0.6 + seed * 10.0;
	float scene = floor(t / 4.0);
	vec2 uv = UV;
	vec3 a = vec3(h(vec2(scene, 1.0)), h(vec2(scene, 2.0)), h(vec2(scene, 3.0)));
	vec3 b = vec3(h(vec2(scene, 4.0)), h(vec2(scene, 5.0)), h(vec2(scene, 6.0)));
	float wave = 0.5 + 0.5 * sin(uv.x * 9.0 + t * 3.0 + sin(uv.y * 6.0 + t));
	vec3 c = mix(a, b, wave);
	// a "face" / product blob in the middle
	float blob = smoothstep(0.32, 0.28, length((uv - vec2(0.5 + 0.15 * sin(t), 0.45)) * vec2(1.6, 1.0)));
	c = mix(c, vec3(1.0, 0.95, 0.85), blob * 0.7);
	// ticker
	if (uv.y > 0.85) {
		float tick = step(0.5, fract(uv.x * 14.0 - t * 2.0)) * step(0.88, uv.y) * step(uv.y, 0.96);
		c = mix(vec3(0.05), vec3(1.0, 0.9, 0.2), tick);
	}
	// pixel grid
	vec2 px = fract(uv * vec2(160.0, 90.0));
	c *= 0.75 + 0.25 * step(0.15, px.x) * step(0.15, px.y);
	ALBEDO = c * (0.35 + 0.65 * glow);
}
"""

const PETAL_SHADER := """
shader_type spatial;
render_mode cull_disabled, diffuse_burley;

void fragment() {
	ALBEDO = vec3(1.0, 0.78, 0.86);
	ROUGHNESS = 0.8;
	SSS_STRENGTH = 0.3;
}
"""

const SHOP_COLS := [Color(1.0, 0.25, 0.3), Color(0.2, 0.75, 1.0), Color(1.0, 0.8, 0.2), Color(0.4, 1.0, 0.5),
	Color(1.0, 0.45, 0.9), Color(1.0, 0.55, 0.1), Color(0.75, 0.4, 1.0), Color(1.0, 1.0, 1.0)]
const FACADES := [
	# [tint, kind] – kind: 0 glass office, 1 concrete apartments, 2 tiled mixed use
	[Color(0.62, 0.72, 0.84), 0], [Color(0.55, 0.6, 0.66), 0], [Color(0.86, 0.84, 0.8), 1], [Color(0.78, 0.7, 0.62), 1],
	[Color(0.9, 0.88, 0.84), 2], [Color(0.7, 0.66, 0.6), 2], [Color(0.48, 0.52, 0.58), 0], [Color(0.92, 0.9, 0.86), 1],
]

var track
var terrain
var scenery
var rng := RandomNumberGenerator.new()
var quality := 2
var _box_mesh: BoxMesh
var _facade_mats: Array = []
var _sets := {}          # kind -> chunk dict (scenery._push)
var _meshes := {}        # kind -> [mesh, range, shadows]
var _sign_mat: ShaderMaterial
var _screen_mats: Array = []
var _night_lights: Array = []
var _sakura_spots: Array = []
var _crossing_p := 0.0   # progress of the scramble crossing
var _crossing_i := 0
var _stats := {}


func build(p_track, p_terrain, p_scenery, p_quality: int) -> void:
	track = p_track
	terrain = p_terrain
	scenery = p_scenery
	quality = p_quality
	rng.seed = 8128
	_make_assets()
	_crossing()
	_places()
	await Game.load_tick()
	_viaduct()
	await Game.load_tick()
	_street_furniture()
	await Game.load_tick()
	await _blocks()
	_park()
	_sakura_rows()
	for kind in _sets.keys():
		var m: Array = _meshes[kind]
		scenery._emit_chunks(m[0], _sets[kind], 0.0, float(m[1]), "City_" + kind, bool(m[2]), 96.0)
	print("CITY: %s" % str(_stats))


func set_night(n: float) -> void:
	if _sign_mat:
		_sign_mat.set_shader_parameter("glow", lerpf(0.2, 1.5, n))
	for m in _screen_mats:
		(m as ShaderMaterial).set_shader_parameter("glow", lerpf(0.75, 1.0, n))
	for l in _night_lights:
		(l[0] as Light3D).visible = n > 0.3
		(l[0] as Light3D).light_energy = float(l[1]) * n


func _add(kind: String, xf: Transform3D, custom := Color(1, 1, 1, 1)) -> void:
	if not _sets.has(kind):
		_sets[kind] = {}
	scenery._push(_sets[kind], xf.origin, [xf, custom], 96.0)
	_stats[kind] = int(_stats.get(kind, 0)) + 1


func _road_dist(p: Vector3) -> float:
	return terrain.distance_to_road(p.x, p.z)


## Lateral clearance from the centreline that buildings keep (wall + pavement).
func _kerb() -> float:
	return float(track.wall_base) + 5.0


func _person(p: Vector3, look_at: Vector3) -> void:
	var d := look_at - p
	d.y = 0.0
	if d.length() < 0.01:
		d = Vector3(0, 0, -1)
	var sc := rng.randf_range(0.9, 1.06)
	var shirt: Color = Crowd.SHIRTS[rng.randi() % Crowd.SHIRTS.size()]
	# city crowd: more dark suits and white shirts
	if rng.randf() < 0.45:
		shirt = [Color(0.08, 0.08, 0.1), Color(0.2, 0.2, 0.24), Color(0.92, 0.92, 0.94)][rng.randi() % 3]
	_add("person", Transform3D((Basis.looking_at(d.normalized(), Vector3.UP) * Basis.from_scale(Vector3(sc, sc, sc))), Vector3(p.x, 0.0, p.z)), Color(shirt.r, shirt.g, shirt.b, rng.randf()))


# ---------------------------------------------------------------------------
# Assets
# ---------------------------------------------------------------------------
func _make_assets() -> void:
	_box_mesh = BoxMesh.new()
	_box_mesh.size = Vector3.ONE
	for f in FACADES:
		var tint: Color = f[0]
		var kind: int = f[1]
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
		m.metallic = 0.3 if kind == 0 else 0.0
		scenery._glow_mats.append([m, 0.0, 1.6])
		_facade_mats.append(m)
		var bm := _box_mesh.duplicate() as BoxMesh
		bm.material = m
		_meshes["bld_%d" % _facade_mats.size()] = [bm, 1400.0, true]
	# roofs: flat grey caps (the facade's triplanar windows would show on the top otherwise)
	var roof := _box_mesh.duplicate() as BoxMesh
	roof.material = TexKit.std(Color(0.42, 0.42, 0.44), 0.9)
	_meshes["roof"] = [roof, 1400.0, false]
	# roof clutter: AC units, water tanks, antennas
	var st := MeshKit.new_st()
	for k in 3:
		Props._b(st, Vector3(-1.5 + k * 1.5, 0.45, 0), Vector3(1.1, 0.9, 0.8), Color(0.75, 0.76, 0.78, 0.6))
	Props._cyl(st, Vector3(3.0, 0.0, 1.5), Vector3(3.0, 2.2, 1.5), 0.9, 0.9, Color(0.7, 0.72, 0.75, 0.6), 10)
	Props._b(st, Vector3(-3.0, 3.0, 1.5), Vector3(0.12, 6.0, 0.12), Color(0.5, 0.5, 0.52, 0.5))
	_meshes["roofstuff"] = [MeshKit.commit(st, Props.material()), 500.0, false]
	# shop front: glowing glass at street level (unit width along X, front at -Z) and an awning
	var shop := _box_mesh.duplicate() as BoxMesh
	var shop_mat := TexKit.emissive(Color(1.0, 0.92, 0.78), 0.5)
	scenery._glow_mats.append([shop_mat, 0.5, 2.2])
	shop.material = shop_mat
	_meshes["shopfront"] = [shop, 400.0, false]
	st = MeshKit.new_st()
	Props._b(st, Vector3(0, 0, -0.6), Vector3(1.0, 0.08, 1.2), Color(1, 1, 1), Vector3(-0.25, 0, 0))
	_meshes["awning"] = [MeshKit.commit(st, Props.material()), 300.0, true]
	# neon signs (vertical and horizontal): unit quad boxes, glyph sheet shader
	_sign_mat = ShaderMaterial.new()
	_sign_mat.shader = Shader.new()
	_sign_mat.shader.code = SIGN_SHADER
	_sign_mat.set_shader_parameter("glyphs", _glyph_texture())
	var sm := _box_mesh.duplicate() as BoxMesh
	sm.material = _sign_mat
	_meshes["sign"] = [sm, 500.0, false]
	# people
	_meshes["person"] = [Crowd.person_mesh(), 260.0, true]
	# cherry tree: dark trunk and branches, clouds of pink blossom
	st = MeshKit.new_st()
	var bark := Color(0.25, 0.17, 0.14)
	Props._cyl(st, Vector3.ZERO, Vector3(0, 2.2, 0), 0.22, 0.16, bark, 8)
	var brng := RandomNumberGenerator.new()
	brng.seed = 77
	for k in 5:
		var a := TAU * k / 5.0 + brng.randf_range(-0.3, 0.3)
		var tip := Vector3(cos(a) * brng.randf_range(1.6, 2.4), brng.randf_range(3.2, 4.2), sin(a) * brng.randf_range(1.6, 2.4))
		Props._cyl(st, Vector3(0, 2.0, 0), tip, 0.13, 0.05, bark, 6)
	for k in 26:
		var a := brng.randf_range(0.0, TAU)
		var r := brng.randf_range(0.6, 2.8)
		var c := Vector3(cos(a) * r, brng.randf_range(3.1, 4.9) - r * 0.18, sin(a) * r)
		var s := brng.randf_range(0.8, 1.4)
		var pink := Color(1.0, 0.72, 0.82).lerp(Color(1.0, 0.9, 0.94), brng.randf())
		_ball(st, c, s, pink)
	_meshes["sakura"] = [MeshKit.commit(st, Props.material()), 600.0, true]
	# street tree (zelkova): green
	st = MeshKit.new_st()
	Props._cyl(st, Vector3.ZERO, Vector3(0, 2.6, 0), 0.18, 0.13, Color(0.32, 0.25, 0.2), 8)
	for k in 14:
		var a := brng.randf_range(0.0, TAU)
		var r := brng.randf_range(0.3, 1.6)
		_ball(st, Vector3(cos(a) * r, brng.randf_range(3.0, 5.4), sin(a) * r), brng.randf_range(0.9, 1.3), Color(0.25, 0.45, 0.2).lerp(Color(0.38, 0.55, 0.25), brng.randf()))
	_meshes["tree"] = [MeshKit.commit(st, Props.material()), 500.0, true]
	# utility pole with crossarms and a transformer (wires are drawn per street)
	st = MeshKit.new_st()
	Props._cyl(st, Vector3.ZERO, Vector3(0, 10.0, 0), 0.16, 0.12, Color(0.6, 0.6, 0.58), 8)
	for y: float in [8.6, 9.5]:
		Props._b(st, Vector3(0, y, 0), Vector3(1.8, 0.1, 0.1), Color(0.35, 0.35, 0.37, 0.6))
	Props._cyl(st, Vector3(0.3, 6.8, 0), Vector3(0.3, 7.6, 0), 0.25, 0.25, Color(0.55, 0.57, 0.6, 0.6), 8)
	_meshes["pole"] = [MeshKit.commit(st, Props.material()), 400.0, true]
	# vending machine pair (glowing fronts come from the shopfront glass)
	st = MeshKit.new_st()
	for k in 2:
		Props._b(st, Vector3(-0.55 + k * 1.1, 0.92, 0), Vector3(1.0, 1.85, 0.8), [Color(0.85, 0.1, 0.1), Color(0.15, 0.35, 0.85)][k])
	_meshes["vending"] = [MeshKit.commit(st, Props.material()), 200.0, true]
	# traffic light (car signals on a mast arm)
	st = MeshKit.new_st()
	Props._cyl(st, Vector3.ZERO, Vector3(0, 5.6, 0), 0.12, 0.1, Color(0.55, 0.56, 0.58, 0.6), 8)
	Props._b(st, Vector3(-2.5, 5.5, 0), Vector3(5.0, 0.12, 0.12), Color(0.55, 0.56, 0.58, 0.6))
	Props._b(st, Vector3(-4.2, 5.3, 0), Vector3(1.3, 0.42, 0.25), Color(0.15, 0.15, 0.16))
	Props._b(st, Vector3(-4.6, 5.3, -0.14), Vector3(0.3, 0.3, 0.05), Color(0.2, 1.0, 0.5))
	Props._b(st, Vector3(-3.8, 5.3, -0.14), Vector3(0.3, 0.3, 0.05), Color(0.35, 0.1, 0.1))
	Props._b(st, Vector3(0, 2.6, -0.15), Vector3(0.35, 0.8, 0.2), Color(0.15, 0.15, 0.16))
	_meshes["signal"] = [MeshKit.commit(st, Props.material()), 300.0, true]


static func _ball(st: SurfaceTool, c: Vector3, s: float, col: Color) -> void:
	var prof := [Vector2(0.0, -0.75), Vector2(0.72, -0.42), Vector2(0.88, 0.1), Vector2(0.58, 0.58), Vector2(0.0, 0.78)]
	var seg := 7
	for i in prof.size() - 1:
		var p0: Vector2 = prof[i] * s
		var p1: Vector2 = prof[i + 1] * s
		for j in seg:
			var a0 := TAU * j / float(seg)
			var a1 := TAU * (j + 1) / float(seg)
			var v00 := c + Vector3(cos(a0) * p0.x, p0.y, sin(a0) * p0.x)
			var v01 := c + Vector3(cos(a1) * p0.x, p0.y, sin(a1) * p0.x)
			var v10 := c + Vector3(cos(a0) * p1.x, p1.y, sin(a0) * p1.x)
			var v11 := c + Vector3(cos(a1) * p1.x, p1.y, sin(a1) * p1.x)
			var am := (a0 + a1) * 0.5
			var nrm := (Vector3(cos(am) * (p0.x + p1.x) * 0.5, (p0.y + p1.y) * 0.5, sin(am) * (p0.x + p1.x) * 0.5)).normalized()
			if p0.x < 0.001:
				MeshKit.tri(st, v00, v10, v11, nrm, nrm, nrm, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, nrm, col)
			elif p1.x < 0.001:
				MeshKit.tri(st, v00, v01, v10, nrm, nrm, nrm, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, nrm, col)
			else:
				MeshKit.quad(st, v00, v01, v11, v10, nrm, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, col)


## Facade tile = 12 x 12 m: 4 floors of 3 m, 4 bays of 3 m. lights = which windows glow at night.
func _facade_texture(kind: int, lights: bool) -> ImageTexture:
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	var r2 := RandomNumberGenerator.new()
	r2.seed = 91 + kind * 13 + (1 if lights else 0)
	img.fill(Color(0, 0, 0) if lights else Color(0.85, 0.85, 0.85))
	var cell := n / 4
	for fy in 4:
		for bx in 4:
			var lit := r2.randf() < 0.22 + 0.12 * float(fy % 2)
			var warm := r2.randf()
			var col_lit := Color(1.0, 0.86, 0.6).lerp(Color(0.85, 0.93, 1.0), warm) * r2.randf_range(0.5, 1.0)
			for y in cell:
				for x in cell:
					var px := bx * cell + x
					var py := fy * cell + y
					var inside := false
					match kind:
						0:   # glass curtain wall: wide windows, thin mullions, slab edge
							inside = x > 1 and x < cell - 1 and y > 4 and y < cell - 2
						1:   # apartments: smaller windows, balcony band below
							inside = x > 5 and x < cell - 5 and y > 6 and y < cell - 12
						2:   # mixed: square windows
							inside = x > 7 and x < cell - 7 and y > 7 and y < cell - 9
					if lights:
						if inside and lit:
							img.set_pixel(px, py, col_lit)
					else:
						var v := 0.85
						if inside:
							v = (0.18 + 0.12 * float(y) / cell) if kind == 0 else 0.2
						elif kind == 1 and y >= cell - 10 and y < cell - 8:
							v = 0.55          # balcony slab shadow
						elif kind == 0 and (y <= 4):
							v = 0.5
						img.set_pixel(px, py, Color(v, v, v * 1.03))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## Glyph sheet for the neon signs: 4 columns of stacked blocky "characters".
func _glyph_texture() -> ImageTexture:
	var w := 128
	var h := 256
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	img.fill(Color(0, 0, 0))
	var r2 := RandomNumberGenerator.new()
	r2.seed = 4242
	for col in 4:
		var x0 := col * 32 + 5
		var y := 8
		while y < h - 30:
			# a character: a few strokes in a 22 x 22 box
			for s in r2.randi_range(3, 6):
				var horiz := r2.randf() < 0.5
				var a := r2.randi_range(0, 18)
				var b := r2.randi_range(0, 18)
				var l := r2.randi_range(8, 22)
				for t in l:
					for th in 3:
						var px := x0 + (mini(a + t, 21) if horiz else a + th)
						var py := y + (b + th if horiz else mini(b + t, 21))
						if px < w and py < h:
							img.set_pixel(px, py, Color(1, 1, 1))
			y += 30
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


# ---------------------------------------------------------------------------
# Buildings
# ---------------------------------------------------------------------------
## Fills the area around the course with blocks of buildings (low shops at the street, taller further
## back, towers inside the expressway loop), each facing its street.
func _blocks() -> void:
	var b: Rect2 = track.bounds.grow(230.0)
	var step := 22.0 if quality >= 2 else 26.0
	var kerb := _kerb()
	var c_loop := Vector2(560.0, -230.0)      # inside the expressway loop: the high-rise district
	var gz := b.position.y
	var rows := 0
	while gz < b.end.y:
		rows += 1
		if rows % 4 == 0:
			await Game.load_tick()
		var gx := b.position.x
		while gx < b.end.x:
			var p := Vector3(gx + rng.randf_range(-3.0, 3.0), 0.0, gz + rng.randf_range(-3.0, 3.0))
			gx += step
			var d := _road_dist(p)
			if d < kerb + 6.0:
				continue
			# frame: face the nearest street within reach, else the grid
			var yaw := 0.0
			if d < 120.0:
				var pr: Array = track.project(p, -1)
				var t: Vector3 = track.tangents[int(pr[0])]
				yaw = atan2(t.x, t.z)
			var basis := Basis(Vector3.UP, yaw)
			var w := rng.randf_range(12.0, step - 2.0)
			var dep := rng.randf_range(12.0, step - 2.0)
			# shrink until the footprint keeps clear of the street
			var ok := false
			for tries in 4:
				ok = true
				for cx: float in [-0.5, 0.5]:
					for cz: float in [-0.5, 0.5]:
						var q := p + basis * Vector3(w * cx, 0, dep * cz)
						if _road_dist(q) < kerb:
							ok = false
				if ok:
					break
				w *= 0.75
				dep *= 0.75
			if not ok or w < 7.0 or not scenery.free_at(p, minf(w, dep) * 0.45, -100.0):
				continue
			# height: low along the streets, rising further back; a high-rise district in the loop
			var downtown := 1.0 - smoothstep(120.0, 330.0, Vector2(p.x, p.z).distance_to(c_loop))
			var hgt := rng.randf_range(7.0, 20.0)
			if d > 45.0:
				hgt = rng.randf_range(15.0, 45.0)
			if d > 60.0 and rng.randf() < 0.18 + 0.6 * downtown:
				hgt = rng.randf_range(60.0, 120.0) + downtown * rng.randf_range(0.0, 110.0)
				w = maxf(w, minf(step - 2.0, 18.0))
				dep = maxf(dep, minf(step - 2.0, 18.0))
			_building(p, basis, w, dep, hgt, d)
			scenery.occupy(p, minf(maxf(w, dep) * 0.55, 9.5))
		gz += step


func _building(p: Vector3, basis: Basis, w: float, dep: float, hgt: float, d: float) -> void:
	var f := rng.randi() % _facade_mats.size()
	var xf := Transform3D((basis * Basis.from_scale(Vector3(w, hgt, dep))), p + Vector3(0, hgt * 0.5, 0))
	_add("bld_%d" % (f + 1), xf)
	_add("roof", Transform3D((basis * Basis.from_scale(Vector3(w + 0.4, 0.5, dep + 0.4))), p + Vector3(0, hgt + 0.25, 0)))
	if rng.randf() < 0.55 and hgt < 80.0:
		_add("roofstuff", Transform3D(basis.rotated(Vector3.UP, rng.randf_range(0.0, PI)), p + Vector3(rng.randf_range(-w, w) * 0.2, hgt + 0.5, rng.randf_range(-dep, dep) * 0.2)))
	# a setback crown on some towers
	if hgt > 70.0 and rng.randf() < 0.5:
		var hc := rng.randf_range(10.0, 25.0)
		_add("bld_%d" % ((f + 3) % _facade_mats.size() + 1), Transform3D((basis * Basis.from_scale(Vector3(w * 0.65, hc, dep * 0.65))), p + Vector3(0, hgt + hc * 0.5, 0)))
		_add("roof", Transform3D((basis * Basis.from_scale(Vector3(w * 0.65 + 0.3, 0.5, dep * 0.65 + 0.3))), p + Vector3(0, hgt + hc + 0.25, 0)))
		if rng.randf() < 0.5:
			var tip := MeshKit.sphere_node(0.7, scenery._glow_material(Color(1.0, 0.1, 0.05), 0.5, 6.0), p + Vector3(0, hgt + hc + 1.0, 0))
			add_child(tip)
	if d < 90.0:
		Colliders.add_box(self, Transform3D(basis, p + Vector3(0, hgt * 0.5, 0)), Vector3(w, hgt, dep))
	# street level: the side towards the road gets shop fronts, awnings and signs
	if d < 60.0:
		var pr: Array = track.project(p, -1)
		var road: Vector3 = track.samples[int(pr[0])]
		var to_road := Vector3(road.x - p.x, 0, road.z - p.z).normalized()
		# which face of the box looks at the road (+-X or +-Z of the basis)
		var axes := [basis.x, -basis.x, basis.z, -basis.z]
		var best := 0
		for k in 4:
			if (axes[k] as Vector3).dot(to_road) > (axes[best] as Vector3).dot(to_road):
				best = k
		var n: Vector3 = axes[best]
		var face_w := dep if best < 2 else w
		var half := (w if best < 2 else dep) * 0.5
		var along: Vector3 = n.cross(Vector3.UP).normalized()
		var fb := Basis(along, Vector3.UP, -n)        # -Z of the frame looks out of the facade
		var front := p + n * (half + 0.05)
		_add("shopfront", Transform3D((fb * Basis.from_scale(Vector3(face_w * 0.9, 2.8, 0.15))), front + Vector3(0, 1.6, 0)))
		if rng.randf() < 0.7:
			var ac: Color = SHOP_COLS[rng.randi() % SHOP_COLS.size()]
			_add("awning", Transform3D((fb * Basis.from_scale(Vector3(face_w * 0.85, 1.0, 1.0))), front + Vector3(0, 3.3, 0)), Color(ac.r, ac.g, ac.b, 1))
		# vertical neon signs sticking out from the corners, a horizontal one over the shop
		for k in rng.randi_range(1, 3):
			var sc: Color = SHOP_COLS[rng.randi() % SHOP_COLS.size()]
			var sh := rng.randf_range(3.5, minf(hgt - 4.0, 10.0))
			if sh < 2.0:
				break
			var sx := rng.randf_range(-face_w * 0.45, face_w * 0.45)
			var sp: Vector3 = front + along * sx + n * 0.6 + Vector3(0, 4.2 + sh * 0.5, 0)
			_add("sign", Transform3D((Basis(n, Vector3.UP, along) * Basis.from_scale(Vector3(1.0, sh, 0.25))), sp), Color(sc.r, sc.g, sc.b, rng.randf()))
		if rng.randf() < 0.6:
			var hc: Color = SHOP_COLS[rng.randi() % SHOP_COLS.size()]
			_add("sign", Transform3D((fb.rotated(fb.z, PI * 0.5) * Basis.from_scale(Vector3(1.2, face_w * 0.7, 0.2))), front + Vector3(0, 4.0, 0) + n * 0.12), Color(hc.r, hc.g, hc.b, rng.randf()))
		# billboard on the roof of the low buildings that face the road
		if hgt < 30.0 and rng.randf() < 0.25:
			var bc: Color = SHOP_COLS[rng.randi() % SHOP_COLS.size()]
			_add("sign", Transform3D((fb.rotated(fb.z, PI * 0.5) * Basis.from_scale(Vector3(5.0, face_w * 0.8, 0.3))), p + Vector3(0, hgt + 3.0, 0) + n * (half - 1.0)), Color(bc.r, bc.g, bc.b, rng.randf()))
		_stats["shops"] = int(_stats.get("shops", 0)) + 1
	_stats["buildings"] = int(_stats.get("buildings", 0)) + 1


# ---------------------------------------------------------------------------
# Expressway viaduct
# ---------------------------------------------------------------------------
func _viaduct() -> void:
	var n: int = track.sample_count()
	var st := MeshKit.new_st()
	var conc := Color(0.66, 0.66, 0.64)
	var dark := Color(0.4, 0.4, 0.41)
	var lamp_mat: StandardMaterial3D = scenery._glow_material(Color(1.0, 0.86, 0.6), 0.2, 4.0)
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
		# the girder's depth: a solid ramp near the ground, a 1.6 m box girder higher up
		var g0 := minf(y0, 1.6) if y0 > 2.6 else y0 + 0.05
		var g1 := minf(y1, 1.6) if y1 > 2.6 else y1 + 0.05
		var dn0 := Vector3(0, -g0, 0)
		var dn1 := Vector3(0, -g1, 0)
		# underside and the two outer faces
		MeshKit.quad(st, b + dn0, a + dn0, e + dn1, c + dn1, Vector3.DOWN, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, dark)
		MeshKit.quad(st, a + dn0, a, e, e + dn1, -track.rights[i], Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, conc)
		MeshKit.quad(st, c + dn1, c, b, b + dn0, track.rights[i], Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, conc)
		# the deck surface between the road edge and the wall (the road ribbon covers the middle)
		var hw: float = track.hws[i]
		var hw2: float = track.hws[i2]
		var up := Vector3(0, float(track.ROAD_Y) - 0.005, 0)
		MeshKit.quad(st, a + up, track.edge_point(i, -hw) + up, track.edge_point(i2, -hw2) + up, e + up, Vector3.UP, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, dark)
		MeshKit.quad(st, track.edge_point(i, hw) + up, b + up, c + up, track.edge_point(i2, hw2) + up, Vector3.UP, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, dark)
		# piers every 24 m where the deck is high enough
		if y0 > 3.5 and i % 12 == 0:
			var mid: Vector3 = track.samples[i]
			var r: Vector3 = track.rights[i]
			var t: Vector3 = Vector3(track.tangents[i].x, 0, track.tangents[i].z).normalized()
			var pier_h := y0 - 1.6
			var pb := Basis(r, Vector3.UP, -t)
			MeshKit.box(st, Transform3D(pb, Vector3(mid.x, pier_h * 0.5, mid.z)), Vector3(2.6, pier_h, 2.2), conc)
			MeshKit.box(st, Transform3D(pb, Vector3(mid.x, pier_h - 0.8, mid.z)), Vector3(l0 + r0, 1.6, 2.4), conc)
			Colliders.add_box(self, Transform3D(pb, Vector3(mid.x, pier_h * 0.5, mid.z)), Vector3(2.6, pier_h, 2.2))
			pier_k += 1
		# lamps on the walls every 36 m, alternating sides
		if y0 > 1.0 and i % 18 == 0:
			var side := 1.0 if (i / 18) % 2 == 0 else -1.0
			var off: float = track.off_right[i] if side > 0.0 else track.off_left[i]
			var lp: Vector3 = track.edge_point(i, side * (off + 0.25))
			var inward: Vector3 = -track.rights[i] * side
			MeshKit.box(st, Transform3D(Basis.IDENTITY, lp + Vector3(0, 4.5, 0)), Vector3(0.18, 9.0, 0.18), Color(0.55, 0.56, 0.58, 0.6))
			MeshKit.box(st, Transform3D(Basis.looking_at(inward, Vector3.UP), lp + Vector3(0, 8.9, 0) + inward * 1.0), Vector3(0.12, 0.12, 2.0), Color(0.55, 0.56, 0.58, 0.6))
			var head := MeshKit.box_node(Vector3(0.5, 0.15, 0.9), lamp_mat, lp + Vector3(0, 8.8, 0) + inward * 2.0)
			add_child(head)
			if true:
				var sl := SpotLight3D.new()
				sl.light_color = Color(1.0, 0.82, 0.55)
				sl.spot_range = 20.0
				sl.spot_angle = 60.0
				sl.shadow_enabled = false
				sl.visible = false
				add_child(sl)
				sl.global_transform = Transform3D(Basis.looking_at(Vector3.DOWN, inward), lp + Vector3(0, 8.7, 0) + inward * 2.0)
				sl.spot_range = 24.0
				_night_lights.append([sl, 8.0])
				scenery._night_lights.append([sl, 8.0])
	var mi := MeshInstance3D.new()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.9
	mat.albedo_texture = TexKit.noise_texture(51, 0.08, false, 256)
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	mat.uv1_scale = Vector3(0.2, 0.2, 0.2)
	mi.mesh = MeshKit.commit(st, mat)
	mi.name = "Viaduct"
	add_child(mi)
	# overhead direction signs on the expressway
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
	var root := Node3D.new()
	add_child(root)
	root.global_transform = Transform3D(Basis.looking_at(t, Vector3.UP), track.samples[i])
	var span: float = (track.off_left[i] + track.off_right[i]) * 0.5
	var steel := TexKit.std(Color(0.55, 0.56, 0.58), 0.5, 0.6)
	for s: float in [-1.0, 1.0]:
		root.add_child(MeshKit.box_node(Vector3(0.4, 7.0, 0.4), steel, Vector3(s * (span + 0.2), 3.5, 0)))
	root.add_child(MeshKit.box_node(Vector3(span * 2.0 + 0.8, 0.4, 0.4), steel, Vector3(0, 6.8, 0)))
	var green: StandardMaterial3D = scenery._glow_material(Color(0.05, 0.42, 0.22), 0.1, 0.8)
	root.add_child(MeshKit.box_node(Vector3(span * 1.4, 2.4, 0.15), green, Vector3(0, 5.5, 0.3)))
	for k in 2:
		var l := Label3D.new()
		l.text = ["C1  SHIBUYA  ▲  2 km", "HANEDA  ◀   SHINJUKU  ▶"][k]
		l.font_size = 96
		l.pixel_size = 0.012
		l.modulate = Color(1, 1, 1)
		l.outline_size = 0
		l.position = Vector3(0, 6.05 - k * 0.9, 0.39)
		l.rotation.y = PI
		root.add_child(l)
	Colliders.add_box(self, root.global_transform * Transform3D(Basis.IDENTITY, Vector3(-(span + 0.2), 3.5, 0)), Vector3(0.4, 7.0, 0.4))
	Colliders.add_box(self, root.global_transform * Transform3D(Basis.IDENTITY, Vector3(span + 0.2, 3.5, 0)), Vector3(0.4, 7.0, 0.4))


# ---------------------------------------------------------------------------
# Scramble crossing
# ---------------------------------------------------------------------------
func _crossing() -> void:
	# on the start avenue, 90 m after the start line (the middle of the long straight north)
	_crossing_p = 90.0
	_crossing_i = track.index_at(_crossing_p)
	var i := _crossing_i
	var c: Vector3 = track.samples[i]
	var t: Vector3 = Vector3(track.tangents[i].x, 0, track.tangents[i].z).normalized()
	var r: Vector3 = track.rights[i]
	# the cross street: openings in both walls, asphalt out to the blocks on both sides
	var gap := 9.5
	track.wall_gaps.append([_crossing_p - gap, _crossing_p + gap, -1.0])
	track.wall_gaps.append([_crossing_p - gap, _crossing_p + gap, 1.0])
	track.rebuild_walls()
	for s: float in [-1.0, 1.0]:
		var a: Vector3 = c + r * s * (track.half_w - 0.5)
		var b: Vector3 = c + r * s * 130.0
		scenery.add_path([a, b], 16.0, "asphalt")
		for q in range(12, 130, 9):
			scenery.occupy(c + r * s * q, 9.5)
		# a dead end with a building across it
		_building(c + r * s * 142.0, Basis.looking_at(-r * s, Vector3.UP), 26.0, 18.0, rng.randf_range(30.0, 60.0), 50.0)
	# zebra stripes: across the avenue on both sides of the crossing, across the side street on
	# both sides, and the two diagonals
	var hw: float = track.half_w
	for s: float in [-1.0, 1.0]:
		_zebra(c + t * s * 11.5, r, hw * 2.0, t)
		_zebra(c + r * s * (hw + 4.5), t, 16.0, r)
	var diag1 := (r + t).normalized()
	var diag2 := (r - t).normalized()
	_zebra(c, diag1, 30.0, diag2)
	_zebra(c, diag2, 30.0, diag1)
	# the crowds waiting on the four corners
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var corner := c + r * sx * (hw + 7.5) + t * sz * 15.0
			for k in 70 if quality >= 1 else 35:
				var p := corner + r * sx * rng.randf_range(-3.0, 4.0) + t * sz * rng.randf_range(-4.0, 6.0)
				_person(p, c + rng.randf_range(-6.0, 6.0) * t)
			# pedestrian signals
			_add("signal", Transform3D(Basis.looking_at(-r * sx, Vector3.UP), corner - r * sx * 3.5 - t * sz * 2.0))
	# the big video screens on the buildings around the crossing
	for k in 3:
		var s := -1.0 if k != 1 else 1.0
		var along: float = [-26.0, 4.0, 30.0][k]
		var bp: Vector3 = c + r * s * (hw + 26.0) + t * along
		var hgt := rng.randf_range(32.0, 48.0)
		_building(bp, Basis.looking_at(-r * s, Vector3.UP), 22.0, 18.0, hgt, 30.0)
		var sm := ShaderMaterial.new()
		sm.shader = Shader.new()
		sm.shader.code = SCREEN_SHADER
		sm.set_shader_parameter("seed", float(k) * 3.7)
		_screen_mats.append(sm)
		var q := QuadMesh.new()
		q.size = Vector2(19.0, 10.7)
		var mi := MeshInstance3D.new()
		mi.mesh = q
		mi.material_override = sm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		var face: Vector3 = bp - r * s * 9.2
		mi.global_transform = Transform3D(Basis.looking_at(r * s, Vector3.UP), face + Vector3(0, 15.0, 0))
		var l := OmniLight3D.new()
		l.light_color = Color(0.7, 0.8, 1.0)
		l.omni_range = 40.0
		l.visible = false
		add_child(l)
		l.global_position = face - r * s * 8.0 + Vector3(0, hgt * 0.55, 0)
		_night_lights.append([l, 2.5])
		scenery._night_lights.append([l, 2.5])
	# a police box on one corner
	var kp: Vector3 = c - r * (hw + 13.0) - t * 22.0
	_koban(kp, r)


func _zebra(centre: Vector3, across: Vector3, length: float, along: Vector3) -> void:
	# white bars 0.45 m wide every 0.9 m, 4 m long, laid across `across`
	var n := int(length / 0.9)
	for k in n:
		var p := centre + across * (-length * 0.5 + (k + 0.5) * 0.9)
		var b := Basis(across, Vector3.UP, across.cross(Vector3.UP).normalized())
		scenery.add_ground_patch(Transform3D(b, p + Vector3(0, 0.02, 0)), Vector2(0.45, 4.0), "line")


func _koban(p: Vector3, r: Vector3) -> void:
	var root := Node3D.new()
	add_child(root)
	root.global_transform = Transform3D(Basis.looking_at(r, Vector3.UP), p)
	root.add_child(MeshKit.box_node(Vector3(4.0, 3.2, 3.5), TexKit.std(Color(0.55, 0.42, 0.32), 0.8), Vector3(0, 1.6, 0)))
	root.add_child(MeshKit.box_node(Vector3(4.4, 0.3, 3.9), TexKit.std(Color(0.3, 0.3, 0.32), 0.7), Vector3(0, 3.35, 0)))
	var red: StandardMaterial3D = scenery._glow_material(Color(1.0, 0.08, 0.05), 0.6, 4.0)
	root.add_child(MeshKit.sphere_node(0.28, red, Vector3(0, 3.0, -1.85)))
	var l := Label3D.new()
	l.text = "KOBAN"
	l.font_size = 64
	l.pixel_size = 0.01
	l.position = Vector3(0, 2.4, -1.8)
	l.rotation.y = PI
	root.add_child(l)
	Colliders.add_box(root, root.global_transform * Transform3D(Basis.IDENTITY, Vector3(0, 1.6, 0)), Vector3(4.0, 3.2, 3.5))
	scenery.occupy(p, 3.0)


# ---------------------------------------------------------------------------
# Landmarks: gas station + konbini, bowling hall, police headquarters
# ---------------------------------------------------------------------------
## Sample index nearest to a plan point, the side of the road it's on and the frame facing the road.
func _site(px: float, pz: float, extra: float) -> Array:
	var i: int = track.nearest_index(Vector3(px, 0, pz))
	var r: Vector3 = track.rights[i]
	var side := signf((Vector3(px, 0, pz) - track.samples[i]).dot(r))
	var off: float = track.off_right[i] if side > 0.0 else track.off_left[i]
	var p: Vector3 = track.samples[i] + r * side * (off + extra)
	p.y = 0.0
	var t: Vector3 = Vector3(track.tangents[i].x, 0, track.tangents[i].z).normalized()
	# frame: -Z looks at the road, X along it
	return [i, side, p, Basis(t * side, Vector3.UP, r * side)]


func _places() -> void:
	_gas_station()
	_bowling()
	_police_hq()


func _gas_station() -> void:
	var s := _site(130.0, 260.0, 16.0)
	var i: int = s[0]
	var side: float = s[1]
	var p: Vector3 = s[2]
	var fb: Basis = s[3]
	var prog := fposmod(float(track.dists[i]) - float(track.start_dist), float(track.length))
	# drive in and out through two openings in the wall
	track.wall_gaps.append([prog - 22.0, prog - 10.0, side])
	track.wall_gaps.append([prog + 10.0, prog + 22.0, side])
	track.rebuild_walls()
	scenery.add_ground_patch(Transform3D(fb, p + fb.z * -4.0), Vector2(46.0, 22.0), "asphalt")
	var root := Node3D.new()
	add_child(root)
	root.global_transform = Transform3D(fb, p)
	# canopy on four columns with glowing underside, pump islands
	var steel := TexKit.std(Color(0.85, 0.85, 0.86), 0.4, 0.5)
	for x: float in [-9.0, 9.0]:
		for z: float in [-3.0, 3.0]:
			root.add_child(MeshKit.box_node(Vector3(0.45, 5.0, 0.45), steel, Vector3(x, 2.5, z)))
			Colliders.add_box(root, root.global_transform * Transform3D(Basis.IDENTITY, Vector3(x, 2.5, z)), Vector3(0.45, 5.0, 0.45))
	root.add_child(MeshKit.box_node(Vector3(24.0, 0.9, 11.0), TexKit.std(Color(0.95, 0.95, 0.95), 0.5), Vector3(0, 5.45, 0)))
	root.add_child(MeshKit.box_node(Vector3(24.1, 0.35, 11.1), TexKit.std(Color(0.95, 0.35, 0.05), 0.5), Vector3(0, 5.75, 0)))
	var under: StandardMaterial3D = scenery._glow_material(Color(1.0, 0.98, 0.95), 0.4, 3.0)
	root.add_child(MeshKit.box_node(Vector3(23.0, 0.05, 10.0), under, Vector3(0, 4.98, 0)))
	for x: float in [-4.5, 4.5]:
		root.add_child(MeshKit.box_node(Vector3(1.2, 0.25, 4.0), TexKit.std(Color(0.6, 0.6, 0.6), 0.8), Vector3(x, 0.12, 0)))
		for z: float in [-1.0, 1.0]:
			var pump := MeshKit.box_node(Vector3(0.8, 1.8, 0.6), TexKit.std(Color(0.95, 0.4, 0.05), 0.5), Vector3(x, 1.15, z))
			root.add_child(pump)
			root.add_child(MeshKit.box_node(Vector3(0.6, 0.4, 0.62), scenery._glow_material(Color(0.6, 0.9, 1.0), 0.4, 2.0), Vector3(x, 1.6, z)))
		Colliders.add_box(root, root.global_transform * Transform3D(Basis.IDENTITY, Vector3(x, 0.9, 0)), Vector3(1.2, 1.8, 4.0))
	for k in 2:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.97, 0.92)
		l.omni_range = 14.0
		l.visible = false
		l.position = Vector3(-5.0 + k * 10.0, 4.6, 0)
		root.add_child(l)
		_night_lights.append([l, 2.0])
		scenery._night_lights.append([l, 2.0])
	# price pylon
	root.add_child(MeshKit.box_node(Vector3(1.6, 6.0, 0.5), TexKit.std(Color(0.95, 0.4, 0.05), 0.5), Vector3(-14.0, 3.0, -5.0)))
	var pl := Label3D.new()
	pl.text = "GAS\nR 172\nH 183\nD 151"
	pl.font_size = 72
	pl.pixel_size = 0.008
	pl.position = Vector3(-14.0, 3.6, -5.27)
	pl.rotation.y = PI
	root.add_child(pl)
	# the konbini behind: white box, a stripe in three colours, glowing glass front
	var kb := MeshKit.box_node(Vector3(16.0, 4.2, 10.0), TexKit.std(Color(0.95, 0.95, 0.94), 0.6), Vector3(4.0, 2.1, 12.5))
	root.add_child(kb)
	Colliders.add_box(root, root.global_transform * Transform3D(Basis.IDENTITY, Vector3(4.0, 2.1, 12.5)), Vector3(16.0, 4.2, 10.0))
	for k in 3:
		var col: Color = [Color(0.95, 0.45, 0.05), Color(0.1, 0.55, 0.3), Color(0.85, 0.08, 0.1)][k]
		root.add_child(MeshKit.box_node(Vector3(16.05, 0.3, 0.05), scenery._glow_material(col, 0.3, 1.6), Vector3(4.0, 3.75 - k * 0.3, 7.47)))
	root.add_child(MeshKit.box_node(Vector3(14.0, 2.4, 0.05), scenery._glow_material(Color(1.0, 0.98, 0.92), 0.5, 2.6), Vector3(4.0, 1.4, 7.47)))
	var kl := Label3D.new()
	kl.text = "24h MART"
	kl.font_size = 96
	kl.pixel_size = 0.012
	kl.modulate = Color(0.1, 0.45, 0.25)
	kl.position = Vector3(4.0, 4.4, 7.45)
	kl.rotation.y = PI
	root.add_child(kl)
	_add("vending", Transform3D(fb, p + fb * Vector3(13.5, 0, 7.3)))
	for k in 6:
		_person(p + fb * Vector3(rng.randf_range(-3.0, 10.0), 0, rng.randf_range(5.0, 7.0)), p + fb * Vector3(0, 0, -10.0))
	if scenery.details:
		scenery.details.add_parked_car(Transform3D(fb, p + fb * Vector3(-4.5, 0, 2.5)))
		scenery.details.add_parked_car(Transform3D(fb.rotated(Vector3.UP, PI * 0.5), p + fb * Vector3(-6.0, 0, 13.0)))
	scenery.occupy(p + fb * Vector3(0, 0, 4.0), 9.5)
	scenery.occupy(p + fb * Vector3(10.0, 0, 10.0), 9.5)
	scenery.occupy(p + fb * Vector3(-10.0, 0, 10.0), 9.5)


func _bowling() -> void:
	var s := _site(130.0, -330.0, 16.0)
	var p: Vector3 = s[2]
	var fb: Basis = s[3]
	var root := Node3D.new()
	add_child(root)
	root.global_transform = Transform3D(fb, p + fb.z * 12.0)
	root.add_child(MeshKit.box_node(Vector3(40.0, 11.0, 24.0), TexKit.std(Color(0.88, 0.86, 0.9), 0.6), Vector3(0, 5.5, 0)))
	Colliders.add_box(root, root.global_transform * Transform3D(Basis.IDENTITY, Vector3(0, 5.5, 0)), Vector3(40.0, 11.0, 24.0))
	root.add_child(MeshKit.box_node(Vector3(30.0, 2.6, 0.05), scenery._glow_material(Color(1.0, 0.95, 0.85), 0.5, 2.4), Vector3(0, 1.5, -12.03)))
	# the giant pin on the roof (white, two red stripes)
	var st := MeshKit.new_st()
	var prof := [Vector2(0.0, 0.0), Vector2(1.6, 0.0), Vector2(2.4, 2.5), Vector2(2.5, 4.0), Vector2(1.7, 6.5), Vector2(1.0, 8.0),
		Vector2(1.2, 9.3), Vector2(1.3, 10.3), Vector2(0.9, 11.4), Vector2(0.0, 11.8)]
	for k in prof.size() - 1:
		var stripe: bool = k == 5
		Props._vlathe(st, [prof[k], prof[k + 1]], 18, Color(0.85, 0.08, 0.08) if stripe else Color(0.96, 0.96, 0.95))
	var pin := MeshInstance3D.new()
	var pm := StandardMaterial3D.new()
	pm.vertex_color_use_as_albedo = true
	pm.roughness = 0.3
	pin.mesh = MeshKit.commit(st, pm)
	pin.position = Vector3(10.0, 11.0, 2.0)
	root.add_child(pin)
	var neon: StandardMaterial3D = scenery._glow_material(Color(1.0, 0.2, 0.6), 0.6, 5.0)
	root.add_child(MeshKit.box_node(Vector3(22.0, 3.0, 0.3), TexKit.std(Color(0.1, 0.1, 0.12), 0.6), Vector3(-6.0, 12.6, -8.0)))
	var l := Label3D.new()
	l.text = "BOWLING"
	l.font_size = 220
	l.pixel_size = 0.012
	l.modulate = Color(1.0, 0.35, 0.75)
	l.outline_size = 0
	l.position = Vector3(-6.0, 12.6, -8.2)
	l.rotation.y = PI
	root.add_child(l)
	root.add_child(MeshKit.box_node(Vector3(22.4, 0.12, 0.12), neon, Vector3(-6.0, 14.2, -8.2)))
	root.add_child(MeshKit.box_node(Vector3(22.4, 0.12, 0.12), neon, Vector3(-6.0, 11.0, -8.2)))
	var ol := OmniLight3D.new()
	ol.light_color = Color(1.0, 0.3, 0.7)
	ol.omni_range = 25.0
	ol.visible = false
	ol.position = Vector3(-6.0, 11.0, -14.0)
	root.add_child(ol)
	_night_lights.append([ol, 2.0])
	scenery._night_lights.append([ol, 2.0])
	for k in 12:
		_person(p + fb * Vector3(rng.randf_range(-12.0, 12.0), 0, rng.randf_range(-3.0, -0.5)), p + fb * Vector3(0, 0, 10.0))
	for q in [-14.0, 0.0, 14.0]:
		scenery.occupy(p + fb * Vector3(q, 0, 12.0), 9.5)


func _police_hq() -> void:
	var s := _site(-60.0, -90.0, 18.0)
	var p: Vector3 = s[2]
	var fb: Basis = s[3]
	var c := p + fb.z * 16.0
	var h := 92.0
	var root := Node3D.new()
	add_child(root)
	root.global_transform = Transform3D(fb, c)
	var stone := TexKit.std(Color(0.78, 0.74, 0.66), 0.7)
	root.add_child(MeshKit.box_node(Vector3(30.0, h, 26.0), _facade_mats[3], Vector3(0, h * 0.5, 0)))
	root.add_child(MeshKit.box_node(Vector3(38.0, 9.0, 32.0), stone, Vector3(0, 4.5, 0)))
	# the crown: a stepped top with the antenna mast
	root.add_child(MeshKit.box_node(Vector3(24.0, 8.0, 20.0), stone, Vector3(0, h + 4.0, 0)))
	root.add_child(MeshKit.box_node(Vector3(10.0, 10.0, 10.0), stone, Vector3(0, h + 13.0, 0)))
	root.add_child(MeshKit.cyl_node(0.4, 0.8, 26.0, TexKit.std(Color(0.8, 0.8, 0.82), 0.4, 0.7), Vector3(0, h + 31.0, 0)))
	root.add_child(MeshKit.sphere_node(0.8, scenery._glow_material(Color(1.0, 0.1, 0.05), 0.6, 6.0), Vector3(0, h + 44.5, 0)))
	Colliders.add_box(root, root.global_transform * Transform3D(Basis.IDENTITY, Vector3(0, 4.5, 0)), Vector3(38.0, 9.0, 32.0))
	var l := Label3D.new()
	l.text = "METROPOLITAN POLICE"
	l.font_size = 150
	l.pixel_size = 0.012
	l.modulate = Color(0.95, 0.95, 0.9)
	l.position = Vector3(0, 7.0, -16.05)
	l.rotation.y = PI
	root.add_child(l)
	# the emblem: a gold star
	root.add_child(MeshKit.sphere_node(1.1, scenery._glow_material(Color(1.0, 0.8, 0.2), 0.8, 3.0), Vector3(0, 12.0, -13.2)))
	# patrol cars in front (white body, black doors read as a tint here: two-tone pairs)
	if scenery.details:
		for k in 4:
			scenery.details.add_parked_car(Transform3D(fb.rotated(Vector3.UP, PI * 0.5), p + fb * Vector3(-10.0 + k * 3.2, 0, 5.0)), "car_sedan")
	# blue lights on poles at the gate
	var blue: StandardMaterial3D = scenery._glow_material(Color(0.2, 0.4, 1.0), 0.6, 5.0)
	for x: float in [-6.0, 6.0]:
		var pole := MeshKit.box_node(Vector3(0.2, 3.0, 0.2), TexKit.std(Color(0.3, 0.3, 0.32), 0.5), p + fb * Vector3(x, 1.5, 0.0))
		add_child(pole)
		add_child(MeshKit.sphere_node(0.25, blue, p + fb * Vector3(x, 3.2, 0.0)))
	for q in [-12.0, 0.0, 12.0]:
		scenery.occupy(c + fb * Vector3(q, 0, 0), 9.5)
		scenery.occupy(c + fb * Vector3(q, 0, -12.0), 9.5)


# ---------------------------------------------------------------------------
# Street furniture, trees, the park
# ---------------------------------------------------------------------------
func _street_furniture() -> void:
	var n: int = track.sample_count()
	var wire_st := MeshKit.new_st()
	var poles: Array = [[], []]
	for i in range(0, n, 3):
		if track.samples[i].y > 0.15:
			continue
		var ci := absi(i - _crossing_i)
		if mini(ci, n - ci) < 12:
			continue
		for side: float in [-1.0, 1.0]:
			if track.in_wall_gap(i, side):
				continue
			var off: float = track.off_right[i] if side > 0.0 else track.off_left[i]
			var r: Vector3 = track.rights[i] * side
			var base: Vector3 = track.samples[i] + r * off
			base.y = 0.0
			var t: Vector3 = Vector3(track.tangents[i].x, 0, track.tangents[i].z).normalized()
			# utility poles every ~30 m (one side), street trees every ~12 m, vending machines now and then
			if i % 15 == 0 and side > 0.0:
				var pp := base + r * 1.2
				if scenery.free_at(pp, 0.4, -100.0):
					_add("pole", Transform3D(Basis.looking_at(t, Vector3.UP), pp))
					poles[0].append(pp)
					scenery.occupy(pp, 0.6)
			elif i % 6 == 0 and rng.randf() < 0.75:
				var tp := base + r * 2.6
				if scenery.free_at(tp, 0.8, -100.0) and _road_dist(tp) > float(track.wall_base) + 1.0:
					var kind := "sakura" if _sakura_zone(tp) else "tree"
					var sc := rng.randf_range(0.85, 1.15)
					_add(kind, Transform3D((Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3(sc, sc, sc))), tp))
					if kind == "sakura":
						_sakura_spots.append(tp)
					scenery.occupy(tp, 1.2)
			elif i % 27 == 0 and rng.randf() < 0.5:
				var vp := base + r * 3.4
				if scenery.free_at(vp, 1.2, -100.0):
					_add("vending", Transform3D(Basis.looking_at(-r, Vector3.UP), vp))
					scenery.occupy(vp, 1.3)
			# a few pedestrians on the pavement
			if rng.randf() < 0.18:
				var wp := base + r * rng.randf_range(1.5, 4.0) + t * rng.randf_range(-2.0, 2.0)
				_person(wp, wp + t * (1.0 if rng.randf() < 0.5 else -1.0))
	# sagging wires between neighbouring poles
	var pl: Array = poles[0]
	for k in pl.size() - 1:
		var a: Vector3 = pl[k]
		var b: Vector3 = pl[k + 1]
		if a.distance_to(b) > 45.0:
			continue
		for wy: float in [8.6, 9.5]:
			for wx: float in [-0.8, 0.8]:
				var t := (b - a).normalized()
				var side := Vector3(-t.z, 0, t.x) * wx
				var segs := 8
				for s in segs:
					var u0 := float(s) / segs
					var u1 := float(s + 1) / segs
					var p0 := a.lerp(b, u0) + side + Vector3(0, wy - sin(u0 * PI) * 0.6, 0)
					var p1 := a.lerp(b, u1) + side + Vector3(0, wy - sin(u1 * PI) * 0.6, 0)
					MeshKit.box(wire_st, Transform3D(Basis.looking_at(p1 - p0, Vector3.UP), (p0 + p1) * 0.5), Vector3(0.025, 0.025, p0.distance_to(p1)), Color(0.05, 0.05, 0.05))
	var wm := MeshInstance3D.new()
	var wmat := StandardMaterial3D.new()
	wmat.vertex_color_use_as_albedo = true
	wm.mesh = MeshKit.commit(wire_st, wmat)
	wm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	wm.visibility_range_end = 220.0
	add_child(wm)
	# traffic signals at the corners
	for i in range(0, n, 4):
		if absf(track.curvature[i]) > 1.0 / 35.0 and track.samples[i].y < 0.15 and i % 40 == 0:
			var side := -signf(track.curvature[i])
			var off: float = track.off_right[i] if side > 0.0 else track.off_left[i]
			var sp: Vector3 = track.samples[i] + track.rights[i] * side * (off + 1.0)
			sp.y = 0.0
			_add("signal", Transform3D(Basis.looking_at(Vector3(track.tangents[i].x, 0, track.tangents[i].z), Vector3.UP).rotated(Vector3.UP, PI * 0.5 * side), sp))


## Cherry trees along the southern streets and around the park (the rest of the city: zelkovas).
func _sakura_zone(p: Vector3) -> bool:
	return p.z > 40.0 or Vector2(p.x, p.z).distance_to(Vector2(130.0, 120.0)) < 120.0 or p.x < 20.0


## A park in the southern loop: lawn, a pond, paths and a grove of cherry trees.
func _park() -> void:
	var c := Vector3(130.0, 0.0, 135.0)
	var r := 55.0
	# make sure it stays clear of the road
	while _road_dist(c) < float(track.wall_base) + r * 0.6 and r > 25.0:
		r -= 5.0
	for k in 40:
		var a := TAU * k / 40.0
		for rr in [r * 0.25, r * 0.5, r * 0.75, r * 0.95]:
			scenery._ground_paints.append([c + Vector3(cos(a), 0, sin(a)) * rr, 8.0, Color(0.0, 0.05, 0.0, 0.9)])
	scenery._ground_paints.append([c, 10.0, Color(0.0, 0.05, 0.0, 0.9)])
	# pond (a dark disc) and a paved ring path
	var pond := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r * 0.28
	cm.bottom_radius = r * 0.28
	cm.height = 0.1
	cm.radial_segments = 32
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.1, 0.18, 0.2)
	wm.roughness = 0.05
	wm.metallic = 0.4
	pond.mesh = cm
	pond.material_override = wm
	add_child(pond)
	pond.global_position = c + Vector3(r * 0.2, 0.02, 0)
	var ring: Array = []
	for k in 25:
		var a := TAU * k / 24.0
		ring.append(c + Vector3(cos(a), 0, sin(a)) * r * 0.62)
	scenery.add_path(ring, 3.0, "paving")
	# the grove, picnic sheets and people under the blossom (hanami)
	for k in 60:
		var a := rng.randf_range(0.0, TAU)
		var d := rng.randf_range(r * 0.35, r * 0.95)
		var tp := c + Vector3(cos(a), 0, sin(a)) * d
		if absf(d - r * 0.62) < 2.5 or not scenery.free_at(tp, 1.5, -100.0):
			continue
		var sc := rng.randf_range(0.9, 1.3)
		_add("sakura", Transform3D((Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3(sc, sc, sc))), tp))
		_sakura_spots.append(tp)
		scenery.occupy(tp, 2.0)
		if rng.randf() < 0.35:
			var sheet := c + Vector3(cos(a + 0.05), 0, sin(a + 0.05)) * (d + 2.5)
			scenery.add_ground_patch(Transform3D(Basis(Vector3.UP, rng.randf() * TAU), sheet), Vector2(2.2, 1.8), "line")
			for m in rng.randi_range(2, 5):
				_person(sheet + Vector3(rng.randf_range(-1.4, 1.4), 0, rng.randf_range(-1.4, 1.4)), sheet)
	scenery.occupy(c, minf(r, 9.5))


## Falling petals: one particle system per group of cherry trees (visible within ~120 m).
func _sakura_rows() -> void:
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
		var centre := (lo + hi) * 0.5 + Vector3(0, 4.5, 0)
		var ext := (hi - lo) * 0.5 + Vector3(3.0, 1.0, 3.0)
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
		ps.amount = clampi(pts.size() * 40, 40, 600) * [1, 1, 2, 2][quality] / 2
		ps.lifetime = 9.0
		ps.preprocess = 9.0
		ps.visibility_aabb = AABB(-ext - Vector3(4, 6, 4), ext * 2.0 + Vector3(8, 8, 8))
		ps.visibility_range_end = 130.0
		ps.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(ps)
		ps.global_position = centre
	_stats["petal_systems"] = groups.size()

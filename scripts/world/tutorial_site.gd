extends Node3D
## The tutorial's set on Grüne Hölle: a lonely house in the woods beside the track (at Hatzenbach),
## with a furnished interior and a garage for the R34, a driveway through a gap in the barrier, and –
## 3 km further, just before Adenauer Forst – a gravel track into the forest to a clearing with a
## caravan and a campfire. Plus a few things for the night drive: a shape between the trees that only
## the lightning shows, the Schwedenkreuz with a grave lantern, a friend's car with its hazards on.
## House frame: origin on the ground in the middle of the lot, -Z faces the road, +X = garage side.

const MeshKit = preload("res://scripts/util/mesh_kit.gd")
const TexKit = preload("res://scripts/util/tex_kit.gd")
const Colliders = preload("res://scripts/util/colliders.gd")
const TT = preload("res://scripts/world/tutorial_textures.gd")

const HOUSE_P := 1860.0      # progress (m from the start line) the garage door looks at
const HOUSE_SIDE := 1.0      # right of the road
const EXIT_P := 4980.0       # the gravel track leaves the road here …
const EXIT_SIDE := 1.0       # … to the right
const FIGURE_P := 2560.0     # the shape between the trees
const FIGURE_SIDE := -1.0
const CROSS_P := 3400.0      # Schwedenkreuz
const CROSS_SIDE := -1.0
const FL := 0.3              # house floor above the lot
const GF := 0.08             # garage floor
const CEIL := 3.0            # top of the walls
const GARAGE_X := 5.3        # car / roller door centre line
const WARM := Color(1.0, 0.76, 0.5)

var track
var terrain
var scenery
var house: Node3D
var house_xf := Transform3D.IDENTITY
var ground := 0.0
var car_xf := Transform3D.IDENTITY
var shelter := AABB()          # world box that keeps the rain out (house + garage)

# animated parts, used by the cutscene
var clock_hands: Array = []    # pivots: hour, minute, second
var tv_mat: ShaderMaterial
var tv_light: OmniLight3D
var phone: Node3D
var phone_mat: StandardMaterial3D
var phone_light: OmniLight3D
var door_pivot: Node3D
var roller: Node3D
var roller_body: StaticBody3D
var garage_lights: Array = []  # [OmniLight3D, emissive tube material]
var lightning: DirectionalLight3D
var window_mat: ShaderMaterial

# route
var exit_xf := Transform3D.IDENTITY   # road frame at the turn-off
var path_pts := PackedVector3Array()   # gravel track, from the road to the clearing
var camp := Vector3.ZERO
var caravan: Node3D
var fire_light: OmniLight3D
var lantern_light: OmniLight3D
var caravan_light: OmniLight3D
var kenji: Node3D
var eyes: Array = []
var figure: Node3D
var hazards: Array = []        # [OmniLight3D, material] × 4
var beacon: Node3D

var _sts := {}                 # material key -> SurfaceTool (merged geometry of the house)
var _mats := {}
var _cols: Array = []          # [local xf, size] boxes that get a collider
var _paints: Array = []        # [world pos, radius, splat colour] applied to the terrain at the end


## Openings in the barriers for the driveway and the gravel track (progress from, to, side).
static func wall_gaps() -> Array:
	return [[HOUSE_P - 12.0, HOUSE_P + 12.0, HOUSE_SIDE], [EXIT_P - 10.0, EXIT_P + 10.0, EXIT_SIDE]]


func build(p_track, p_terrain, p_scenery) -> void:
	track = p_track
	terrain = p_terrain
	scenery = p_scenery
	_materials()
	_place_house()
	await Game.load_tick()
	_build_structure()
	_build_living()
	_build_kitchen()
	_build_hall()
	await Game.load_tick()
	_build_garage()
	_build_outside()
	_commit()
	_build_lights()
	await Game.load_tick()
	_build_exit_and_camp()
	await Game.load_tick()
	_build_figure()
	_build_cross()
	_apply_paints()


# ---------------------------------------------------------------------------
# Materials
# ---------------------------------------------------------------------------
func _mat(key: String, tex: Texture2D, rough: float, metal := 0.0, uv := 1.0, tint := Color.WHITE) -> void:
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.albedo_color = tint
	m.roughness = rough
	m.metallic = metal
	m.vertex_color_use_as_albedo = true
	m.uv1_scale = Vector3(uv, uv, uv)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_mats[key] = m


func _materials() -> void:
	_mat("floor", TT.floor_wood(), 0.42, 0.0, 0.45)
	_mat("wall_in", TT.wallpaper(), 0.85, 0.0, 0.8)
	_mat("white", null, 0.8)
	_mat("tiles", TT.tiles(), 0.18, 0.0, 1.6)
	_mat("rug", TT.rug(), 0.95)
	_mat("fabric", TT.fabric(), 0.95, 0.0, 2.0)
	_mat("walnut", TT.walnut(), 0.5, 0.0, 1.2)
	_mat("oak", TT.floor_wood(), 0.55, 0.0, 0.8)
	_mat("metal", null, 0.35, 0.85)
	_mat("chrome", null, 0.12, 1.0)
	_mat("gloss", null, 0.1)
	_mat("matte", null, 0.9)
	_mat("concrete", TT.concrete(), 0.7, 0.0, 0.22)
	_mat("blocks", TT.blocks(), 0.9, 0.0, 0.62)
	_mat("pegboard", TT.pegboard(), 0.8, 0.0, 4.0)
	_mat("roof", TT.roof(), 0.75, 0.0, 0.7)
	_mat("plaster", TT.plaster(), 0.95, 0.0, 0.5)
	_mat("slats", TT.slats(), 0.4, 0.4, 1.0)
	_mat("stone", null, 0.25)
	_mat("leaf", null, 0.6)
	(_mats["leaf"] as StandardMaterial3D).cull_mode = BaseMaterial3D.CULL_DISABLED
	var glass := TexKit.glass(Color(0.1, 0.12, 0.15, 0.35))
	_mats["glass"] = glass
	# lamp shades glow from the inside
	var shade := StandardMaterial3D.new()
	shade.albedo_color = Color(0.95, 0.85, 0.7)
	shade.emission_enabled = true
	shade.emission = WARM
	shade.emission_energy_multiplier = 1.4
	shade.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats["shade"] = shade
	var bulb := StandardMaterial3D.new()
	bulb.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bulb.albedo_color = Color(1.0, 0.9, 0.7)
	_mats["bulb"] = bulb
	# the big living room window: glass with rain running down it
	window_mat = ShaderMaterial.new()
	window_mat.shader = _rain_glass_shader()
	window_mat.set_shader_parameter("noise_tex", TexKit.noise_texture(61, 0.05, false, 256))


func _rain_glass_shader() -> Shader:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, specular_schlick_ggx;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform float flash = 0.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void fragment() {
	// small beads of rain that slide down now and then, and a few streaks – dark, clear glass
	vec2 uv = UV * vec2(6.0, 3.0);
	vec2 cell = floor(uv * vec2(14.0, 8.0));
	vec2 f = fract(uv * vec2(14.0, 8.0));
	float h = hash(cell);
	float t = fract(TIME * (0.04 + h * 0.12) + h);
	float y = 1.0 - t;
	vec2 d = vec2((f.x - 0.5 - (h - 0.5) * 0.5) * 2.4, f.y - y);
	float drop = smoothstep(0.1, 0.04, length(d * vec2(1.0, 1.5))) * step(0.45, h);
	float trail = smoothstep(0.035, 0.0, abs(d.x)) * step(y, f.y) * (1.0 - smoothstep(0.0, 0.35, f.y - y)) * 0.35 * step(0.45, h);
	float beads = smoothstep(0.8, 0.86, texture(noise_tex, UV * 7.0).r) * 0.5;
	float wet = clamp(drop + trail + beads, 0.0, 1.0);
	ALBEDO = vec3(0.03, 0.035, 0.045);
	ALPHA = 0.1 + wet * 0.22;
	ROUGHNESS = 0.02;
	SPECULAR = 0.35 + wet * 0.3;
	NORMAL_MAP = normalize(vec3(0.5 + d.x * wet * 0.6, 0.5 - d.y * wet * 0.6, 1.0));
	EMISSION = vec3(0.6, 0.65, 0.8) * flash * wet * 0.35;
}
"""
	return sh


func _st(key: String) -> SurfaceTool:
	if not _sts.has(key):
		_sts[key] = MeshKit.new_st()
	return _sts[key]


## A box in house space. uv: texture metres scale (1 = texture repeats per metre × material scale).
func _b(key: String, pos: Vector3, size: Vector3, col := Color.WHITE, rot := Vector3.ZERO, collide := false) -> void:
	var xf := Transform3D(Basis.from_euler(rot), pos)
	MeshKit.box(_st(key), xf, size, col)
	if collide:
		_cols.append([xf, size])


func _cyl(key: String, base: Vector3, top: Vector3, r0: float, r1: float, col := Color.WHITE, seg := 16) -> void:
	var st := _st(key)
	MeshKit.tube(st, [base, top], [r0, r1], seg, Vector2(1, 1), col, false)
	var ring_t := PackedVector3Array()
	var ring_b := PackedVector3Array()
	var axis := (top - base).normalized()
	var ref := Vector3.UP if absf(axis.y) < 0.9 else Vector3.RIGHT
	var u := axis.cross(ref).normalized()
	var v := axis.cross(u)
	for k in seg:
		var a := TAU * k / float(seg)
		ring_t.append(top + (u * cos(a) + v * sin(a)) * r1)
		ring_b.append(base + (u * cos(a) + v * sin(a)) * r0)
	MeshKit.cap(st, ring_t, top, axis, col)
	MeshKit.cap(st, ring_b, base, -axis, col)


func _sphere(key: String, c: Vector3, r: float, col := Color.WHITE, sc := Vector3.ONE) -> void:
	var st := _st(key)
	var rings := 8
	var seg := 12
	for i in rings:
		var a0 := PI * i / rings - PI * 0.5
		var a1 := PI * (i + 1) / rings - PI * 0.5
		for j in seg:
			var b0 := TAU * j / seg
			var b1 := TAU * (j + 1) / seg
			var p := func(a: float, b: float) -> Vector3: return Vector3(cos(a) * cos(b), sin(a), cos(a) * sin(b))
			var n00: Vector3 = p.call(a0, b0)
			var n01: Vector3 = p.call(a0, b1)
			var n11: Vector3 = p.call(a1, b1)
			var n10: Vector3 = p.call(a1, b0)
			MeshKit.quad(st, c + n00 * r * sc, c + n01 * r * sc, c + n11 * r * sc, c + n10 * r * sc, (n00 + n11).normalized(),
				Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, col)


func _commit() -> void:
	var mesh := ArrayMesh.new()
	for key in _sts:
		var st: SurfaceTool = _sts[key]
		st.set_material(_mats[key])
		st.commit(mesh)
	var mi := MeshInstance3D.new()
	mi.name = "HouseMesh"
	mi.mesh = mesh
	house.add_child(mi)
	for c in _cols:
		Colliders.add_box(house, house_xf * (c[0] as Transform3D), c[1])
	_sts.clear()
	_cols.clear()


# ---------------------------------------------------------------------------
# Placement
# ---------------------------------------------------------------------------
func _place_house() -> void:
	var i: int = track.index_at(HOUSE_P)
	var t: Vector3 = track.tangents[i]
	var away: Vector3 = track.rights[i] * HOUSE_SIDE
	away.y = 0.0
	away = away.normalized()
	var x_axis := Vector3.UP.cross(away).normalized()
	var off: float = track.off_right[i] if HOUSE_SIDE > 0.0 else track.off_left[i]
	var road: Vector3 = track.samples[i]
	var centre := road + away * (off + 18.0) - x_axis * GARAGE_X
	ground = terrain.flatten(centre, 13.0, 10.0)
	centre.y = ground
	house_xf = Transform3D(Basis(x_axis, Vector3.UP, away), centre)
	house = Node3D.new()
	house.name = "TutorialHouse"
	add_child(house)
	house.global_transform = house_xf
	scenery.occupy(centre, 15.0)
	# no grass through the floors: concrete ground under the whole house and garage
	for k in 5:
		_paint(house_xf * Vector3(-7.0 + k * 3.8, 0, 0), 6.5, Color(1.0, 0.0, 0.0, 0.0))
	# the car in the garage, nose towards the roller door
	car_xf = house_xf * Transform3D(Basis.IDENTITY, Vector3(GARAGE_X, GF + 0.45, -0.3))
	var a := house_xf * Vector3(-9.6, -1.0, -5.0)
	var b := house_xf * Vector3(8.9, CEIL + 3.0, 4.8)
	shelter = AABB(Vector3(minf(a.x, b.x), a.y, minf(a.z, b.z)), Vector3(absf(a.x - b.x), b.y - a.y, absf(a.z - b.z)))
	# driveway and the path to the front door: concrete, and no grass / trees on them
	var door_l := Vector3(GARAGE_X, 0, -4.6)
	var road_l := house_xf.affine_inverse() * (road + away * (float(track.half_w) + 0.8))
	_strip([door_l, Vector3(GARAGE_X, 0, lerpf(-4.6, road_l.z, 0.5)), Vector3(lerpf(GARAGE_X, road_l.x, 0.6), 0, road_l.z * 0.8), road_l], 4.4, "drive")
	_strip([Vector3(0.55, 0, -4.6), Vector3(0.55, 0, -6.4), Vector3(3.2, 0, -7.6)], 1.2, "path")
	for k in 12:
		scenery.occupy(house_xf * Vector3(lerpf(GARAGE_X, road_l.x, k / 11.0), 0, lerpf(-5.0, road_l.z, k / 11.0)), 3.5)


## A flat strip over the terrain (driveway, footpath, gravel track) through local points `pts`.
func _strip(pts: Array, width: float, kind: String) -> void:
	var world_pts: Array = []
	for p in pts:
		world_pts.append(house_xf * (p as Vector3))
	_strip_world(world_pts, width, kind, house)


func _strip_world(pts: Array, width: float, kind: String, parent: Node3D) -> void:
	# resample the polyline every metre
	var dense: Array = []
	for k in pts.size() - 1:
		var a: Vector3 = pts[k]
		var b: Vector3 = pts[k + 1]
		var n := maxi(int(Vector2(b.x - a.x, b.z - a.z).length() / 1.0), 1)
		for j in n:
			dense.append(a.lerp(b, float(j) / n))
	dense.append(pts[pts.size() - 1])
	var st := MeshKit.new_st()
	var u := 0.0
	for k in dense.size() - 1:
		var a: Vector3 = dense[k]
		var b: Vector3 = dense[k + 1]
		var dir := Vector3(b.x - a.x, 0, b.z - a.z).normalized()
		var side := Vector3(-dir.z, 0, dir.x) * width * 0.5
		var segs := 4
		for s in segs:
			var f0 := -1.0 + 2.0 * s / segs
			var f1 := -1.0 + 2.0 * (s + 1) / segs
			var q := [a + side * f0, a + side * f1, b + side * f1, b + side * f0]
			for m in 4:
				var qv: Vector3 = q[m]
				qv.y = terrain.height_at(qv.x, qv.z) + 0.035
				q[m] = qv
			var l := Vector2(b.x - a.x, b.z - a.z).length()
			MeshKit.quad(st, q[0], q[1], q[2], q[3], Vector3.UP, Vector2(f0 * width * 0.25, u), Vector2(f1 * width * 0.25, u),
				Vector2(f1 * width * 0.25, u + l * 0.25), Vector2(f0 * width * 0.25, u + l * 0.25))
		u += Vector2(b.x - a.x, b.z - a.z).length() * 0.25
		# the terrain under it: no grass, the ground colour of a track
		_paint(a, width * 0.5 + 1.5, Color(1.0, 0.0, 0.0, 0.0) if kind != "gravel" else Color(0.5, 1.0, 0.0, 0.0))
	var m := StandardMaterial3D.new()
	if kind == "gravel":
		m.albedo_texture = load("res://assets/textures/gravel_albedo.jpg")
		m.normal_enabled = true
		m.normal_texture = load("res://assets/textures/gravel_normal.png")
		m.albedo_color = Color(0.62, 0.56, 0.48)
		m.roughness = 0.8
	else:
		m.albedo_texture = TT.concrete()
		m.albedo_color = Color(0.72, 0.72, 0.7) if kind == "drive" else Color(0.8, 0.78, 0.74)
		m.roughness = 0.55
	m.uv1_scale = Vector3(1, 1, 1)
	var mi := MeshKit.mesh_instance(MeshKit.commit(st, m, null, true), null, false)
	mi.name = "Strip_" + kind
	parent.add_child(mi)
	mi.global_transform = Transform3D.IDENTITY


## Blends the terrain's ground types around p (R concrete, G dirt, B forest floor, A meadow) – queued,
## applied in one go (the splat array is huge on this map: one copy, not one per change).
func _paint(p: Vector3, radius: float, col: Color) -> void:
	_paints.append([p, radius, col])


func _apply_paints() -> void:
	var sp: PackedColorArray = terrain.splat
	for pt in _paints:
		_paint_into(sp, pt[0], pt[1], pt[2])
	terrain.splat = sp
	_paints.clear()


func _paint_into(sp: PackedColorArray, p: Vector3, radius: float, col: Color) -> void:
	var cell: float = terrain.CELL
	var o: Vector2 = terrain.origin
	var cx := int(round((p.x - o.x) / cell))
	var cz := int(round((p.z - o.y) / cell))
	var r := int(ceil(radius / cell)) + 1
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var ix := cx + dx
			var iz := cz + dz
			if ix < 0 or iz < 0 or ix >= terrain.nx or iz >= terrain.nz:
				continue
			var d := Vector2(o.x + ix * cell - p.x, o.y + iz * cell - p.z).length()
			var k := 1.0 - smoothstep(radius * 0.6, radius + cell, d)
			if k <= 0.0:
				continue
			var idx: int = iz * terrain.nx + ix
			sp[idx] = sp[idx].lerp(col, k)


# ---------------------------------------------------------------------------
# Shell: walls, floors, ceilings, roofs
# ---------------------------------------------------------------------------
## Wall along X at z (from x0 to x1), y from y0 to y1, with openings [x_a, x_b, y_a, y_b].
func _wall_x(key: String, z: float, x0: float, x1: float, y0: float, y1: float, holes: Array, th := 0.25, collide := true, col := Color.WHITE) -> void:
	var xs := [x0]
	for h in holes:
		xs.append(h[0])
		xs.append(h[1])
	xs.append(x1)
	# solid pieces between the holes, and above / below every hole
	for k in range(0, xs.size() - 1, 2):
		var a: float = xs[k]
		var b: float = xs[k + 1]
		if b - a > 0.01:
			_b(key, Vector3((a + b) * 0.5, (y0 + y1) * 0.5, z), Vector3(b - a, y1 - y0, th), col, Vector3.ZERO, collide)
	for h in holes:
		var ha: float = h[0]
		var hb: float = h[1]
		var ya: float = h[2]
		var yb: float = h[3]
		if ya - y0 > 0.01:
			_b(key, Vector3((ha + hb) * 0.5, (y0 + ya) * 0.5, z), Vector3(hb - ha, ya - y0, th), col, Vector3.ZERO, collide)
		if y1 - yb > 0.01:
			_b(key, Vector3((ha + hb) * 0.5, (yb + y1) * 0.5, z), Vector3(hb - ha, y1 - yb, th), col, Vector3.ZERO, collide)


func _wall_z(key: String, x: float, z0: float, z1: float, y0: float, y1: float, holes: Array, th := 0.25, collide := true, col := Color.WHITE) -> void:
	var zs := [z0]
	for h in holes:
		zs.append(h[0])
		zs.append(h[1])
	zs.append(z1)
	for k in range(0, zs.size() - 1, 2):
		var a: float = zs[k]
		var b: float = zs[k + 1]
		if b - a > 0.01:
			_b(key, Vector3(x, (y0 + y1) * 0.5, (a + b) * 0.5), Vector3(th, y1 - y0, b - a), col, Vector3.ZERO, collide)
	for h in holes:
		var ha: float = h[0]
		var hb: float = h[1]
		var ya: float = h[2]
		var yb: float = h[3]
		if ya - y0 > 0.01:
			_b(key, Vector3(x, (y0 + ya) * 0.5, (ha + hb) * 0.5), Vector3(th, ya - y0, hb - ha), col, Vector3.ZERO, collide)
		if y1 - yb > 0.01:
			_b(key, Vector3(x, (yb + y1) * 0.5, (ha + hb) * 0.5), Vector3(th, y1 - yb, hb - ha), col, Vector3.ZERO, collide)


## A window frame (white, with a mullion) in a wall along X (n = -1 front, +1 back) or Z.
func _frame_x(z: float, xa: float, xb: float, ya: float, yb: float, glass_key := "glass") -> void:
	var w := xb - xa
	var cx := (xa + xb) * 0.5
	_b("white", Vector3(cx, ya - 0.03, z), Vector3(w + 0.12, 0.06, 0.34))          # sill
	_b("white", Vector3(cx, yb + 0.03, z), Vector3(w + 0.12, 0.06, 0.3))
	_b("white", Vector3(xa - 0.03, (ya + yb) * 0.5, z), Vector3(0.06, yb - ya, 0.3))
	_b("white", Vector3(xb + 0.03, (ya + yb) * 0.5, z), Vector3(0.06, yb - ya, 0.3))
	_b("white", Vector3(cx, (ya + yb) * 0.5, z), Vector3(0.05, yb - ya, 0.12))
	if glass_key == "glass":
		_b("glass", Vector3(cx, (ya + yb) * 0.5, z), Vector3(w, yb - ya, 0.02))


func _frame_z(x: float, za: float, zb: float, ya: float, yb: float) -> void:
	var w := zb - za
	var cz := (za + zb) * 0.5
	_b("white", Vector3(x, ya - 0.03, cz), Vector3(0.34, 0.06, w + 0.12))
	_b("white", Vector3(x, yb + 0.03, cz), Vector3(0.3, 0.06, w + 0.12))
	_b("white", Vector3(x, (ya + yb) * 0.5, za - 0.03), Vector3(0.3, yb - ya, 0.06))
	_b("white", Vector3(x, (ya + yb) * 0.5, zb + 0.03), Vector3(0.3, yb - ya, 0.06))
	_b("white", Vector3(x, (ya + yb) * 0.5, cz), Vector3(0.12, yb - ya, 0.05))
	_b("glass", Vector3(x, (ya + yb) * 0.5, cz), Vector3(0.02, yb - ya, w))


func _gable(key_roof: String, x0: float, x1: float, z0: float, z1: float, eave: float, rise: float, over: float) -> void:
	var st := _st(key_roof)
	var zc := (z0 + z1) * 0.5
	var hz := (z1 - z0) * 0.5 + over
	var ridge := Vector3(0, eave + rise, zc)
	var a0 := Vector3(x0 - over, eave - over * rise / hz, zc - hz)
	var a1 := Vector3(x1 + over, eave - over * rise / hz, zc - hz)
	var r0 := Vector3(x0 - over, ridge.y, zc)
	var r1 := Vector3(x1 + over, ridge.y, zc)
	var b0 := Vector3(x0 - over, eave - over * rise / hz, zc + hz)
	var b1 := Vector3(x1 + over, eave - over * rise / hz, zc + hz)
	var slope := Vector2(hz, ridge.y - a0.y).length()
	MeshKit.quad(st, a0, a1, r1, r0, Vector3(0, hz, -rise).normalized(), Vector2(0, slope), Vector2(x1 - x0, slope), Vector2(x1 - x0, 0), Vector2(0, 0))
	MeshKit.quad(st, b1, b0, r0, r1, Vector3(0, hz, rise).normalized(), Vector2(0, slope), Vector2(x1 - x0, slope), Vector2(x1 - x0, 0), Vector2(0, 0))
	# underside of the overhang and the gable walls
	var pl := _st("plaster")
	for x: float in [x0, x1]:
		var n := Vector3(-1 if x == x0 else 1, 0, 0)
		MeshKit.tri(pl, Vector3(x, eave, z0), Vector3(x, eave, z1), Vector3(x, eave + rise, zc), n, n, n,
			Vector2(0, 0), Vector2(z1 - z0, 0), Vector2((z1 - z0) * 0.5, rise), n)
	# fascia boards along the eaves
	_b("white", Vector3((x0 + x1) * 0.5, a0.y - 0.05, zc - hz), Vector3(x1 - x0 + over * 2.0, 0.18, 0.06))
	_b("white", Vector3((x0 + x1) * 0.5, b0.y - 0.05, zc + hz), Vector3(x1 - x0 + over * 2.0, 0.18, 0.06))
	# gutters
	_cyl("metal", Vector3(x0 - over, a0.y - 0.12, zc - hz - 0.08), Vector3(x1 + over, a0.y - 0.12, zc - hz - 0.08), 0.06, 0.06, Color(0.5, 0.5, 0.52), 8)


func _build_structure() -> void:
	var ext := Color(0.86, 0.84, 0.8)
	# foundations and floor slabs
	_b("concrete", Vector3(-3.5, FL * 0.5 - 0.6, 0), Vector3(11.3, FL + 1.2, 9.3), Color(0.7, 0.7, 0.68))
	_b("concrete", Vector3(GARAGE_X, GF * 0.5 - 0.6, -0.35), Vector3(6.8, GF + 1.2, 8.6), Color(0.85, 0.85, 0.83), Vector3.ZERO, true)
	_b("floor", Vector3(-3.5, FL + 0.005, 0), Vector3(10.8, 0.01, 8.8))
	# exterior walls (plaster outside, wallpaper inside = two thin layers)
	var front_holes := [[-8.2, -4.4, FL + 0.8, FL + 2.35], [0.05, 1.05, FL, FL + 2.1], [-2.8, -1.8, FL + 1.1, FL + 2.2]]
	_wall_x("plaster", -4.62, -9.12, 2.0, -0.6, CEIL, front_holes, 0.12, true, ext)
	_wall_x("wall_in", -4.5, -9.0, -1.0, FL, CEIL, [[-8.2, -4.4, FL + 0.8, FL + 2.35], [-2.8, -1.8, FL + 1.1, FL + 2.2]], 0.1, false)
	_wall_x("white", -4.5, -1.0, 2.0, FL, CEIL, [[0.05, 1.05, FL, FL + 2.1]], 0.1, false, Color(0.9, 0.88, 0.84))
	var back_holes := [[-7.5, -5.8, FL + 1.1, FL + 2.15]]
	_wall_x("plaster", 4.62, -9.12, 2.0, -0.6, CEIL, back_holes, 0.12, true, ext)
	_wall_x("tiles", 4.5, -9.0, -3.6, FL, CEIL, back_holes, 0.1, false)
	_wall_x("white", 4.5, -1.0, 2.0, FL, CEIL, [], 0.1, false, Color(0.9, 0.88, 0.84))
	var left_holes := [[1.6, 3.6, FL + 1.1, FL + 2.2]]
	_wall_z("plaster", -9.12, -4.62, 4.62, -0.6, CEIL, left_holes, 0.12, true, ext)
	_wall_z("wall_in", -9.0, -4.5, 4.5, FL, CEIL, left_holes, 0.1, false)
	# shared wall house / garage with the door
	_wall_z("blocks", 2.0, -4.5, 4.5, -0.6, CEIL, [[-0.45, 0.45, FL, FL + 2.1]], 0.2, true, Color(0.93, 0.93, 0.9))
	_wall_z("wall_in", 1.88, -4.5, 4.5, FL, CEIL, [[-0.45, 0.45, FL, FL + 2.1]], 0.02, false, Color(0.95, 0.93, 0.9))
	# partition living room | hallway, with a wide passage
	_wall_z("wall_in", -1.0, -4.5, 4.5, FL, CEIL, [[-0.9, 0.3, FL, FL + 2.25]], 0.14, false)
	# ceilings
	_b("white", Vector3(-3.5, CEIL + 0.04, 0), Vector3(11.0, 0.08, 9.0), Color(0.93, 0.92, 0.9))
	_b("white", Vector3(GARAGE_X, CEIL + 0.04, -0.35), Vector3(6.6, 0.08, 8.3), Color(0.82, 0.82, 0.8))
	# window frames
	_frame_x(-4.56, -2.8, -1.8, FL + 1.1, FL + 2.2)
	_frame_x(4.56, -7.5, -5.8, FL + 1.1, FL + 2.15)
	_frame_z(-9.06, 1.6, 3.6, FL + 1.1, FL + 2.2)
	# the big living room window (rain on the glass)
	var wx0 := -8.2
	var wx1 := -4.4
	_b("white", Vector3((wx0 + wx1) * 0.5, FL + 0.77, -4.56), Vector3(wx1 - wx0 + 0.2, 0.06, 0.42))
	_b("white", Vector3((wx0 + wx1) * 0.5, FL + 2.38, -4.56), Vector3(wx1 - wx0 + 0.1, 0.06, 0.3))
	for x: float in [wx0 - 0.03, (wx0 + wx1) * 0.5, wx1 + 0.03]:
		_b("white", Vector3(x, FL + 1.575, -4.56), Vector3(0.07, 1.55, 0.3))
	_b("white", Vector3((wx0 + wx1) * 0.5, FL + 1.9, -4.56), Vector3(wx1 - wx0, 0.05, 0.12))
	var glass := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(wx1 - wx0, 1.55)
	glass.mesh = qm
	glass.material_override = window_mat
	glass.position = Vector3((wx0 + wx1) * 0.5, FL + 1.575, -4.56)
	glass.rotation = Vector3(0, PI, 0)
	glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	house.add_child(glass)
	# garage shell
	_wall_x("blocks", -4.56, 2.0, 8.7, -0.6, CEIL, [[3.0, 7.6, GF, GF + 2.5]], 0.25, true, Color(0.9, 0.9, 0.88))
	_wall_x("blocks", 3.9, 2.0, 8.7, -0.6, CEIL, [], 0.25, true, Color(0.9, 0.9, 0.88))
	_wall_z("blocks", 8.7, -4.56, 3.9, -0.6, CEIL, [[2.6, 3.5, GF + 1.4, GF + 2.2]], 0.25, true, Color(0.9, 0.9, 0.88))
	_frame_z(8.66, 2.6, 3.5, GF + 1.4, GF + 2.2)
	# roofs: main house gable along X, lower garage gable
	_gable("roof", -9.12, 2.0, -4.62, 4.62, CEIL + 0.1, 2.3, 0.55)
	_gable("roof", 2.0, 8.82, -4.7, 4.0, CEIL + 0.1, 1.4, 0.45)
	# chimney
	_b("blocks", Vector3(-6.8, CEIL + 2.6, 2.2), Vector3(0.7, 2.4, 0.7), Color(0.55, 0.3, 0.25))
	_b("metal", Vector3(-6.8, CEIL + 3.85, 2.2), Vector3(0.8, 0.08, 0.8), Color(0.3, 0.3, 0.3))
	# front door (outside: canopy)
	_b("walnut", Vector3(0.55, FL + 1.05, -4.58), Vector3(0.98, 2.1, 0.06), Color(0.8, 0.8, 0.8))
	_b("chrome", Vector3(0.9, FL + 1.0, -4.63), Vector3(0.14, 0.03, 0.04))
	_b("roof", Vector3(0.55, FL + 2.45, -5.1), Vector3(1.8, 0.08, 1.1), Color(0.8, 0.8, 0.8), Vector3(-0.15, 0, 0))
	_b("concrete", Vector3(0.55, FL * 0.5, -5.0), Vector3(1.6, FL, 0.9), Color(0.75, 0.75, 0.72))


# ---------------------------------------------------------------------------
# Living room (x -9 … -1, z -4.5 … 1)
# ---------------------------------------------------------------------------
func _build_living() -> void:
	var f := FL
	# rug
	_b("rug", Vector3(-6.9, f + 0.012, -1.8), Vector3(2.9, 0.012, 2.2))
	# TV sideboard, TV, soundbar, console with a blue light
	_b("walnut", Vector3(-8.72, f + 0.3, -1.8), Vector3(0.46, 0.6, 1.9))
	for k in 3:
		_b("walnut", Vector3(-8.48, f + 0.3, -2.4 + k * 0.6), Vector3(0.02, 0.5, 0.56), Color(0.85, 0.85, 0.85))
		_b("chrome", Vector3(-8.46, f + 0.45, -2.4 + k * 0.6), Vector3(0.02, 0.02, 0.2))
	_b("gloss", Vector3(-8.85, f + 1.2, -1.8), Vector3(0.06, 0.8, 1.36), Color(0.02, 0.02, 0.02))
	_b("gloss", Vector3(-8.75, f + 0.66, -1.8), Vector3(0.1, 0.1, 0.9), Color(0.05, 0.05, 0.05))
	_b("matte", Vector3(-8.7, f + 0.64, -2.55), Vector3(0.28, 0.06, 0.3), Color(0.9, 0.9, 0.9))
	tv_mat = ShaderMaterial.new()
	var tvs := Shader.new()
	tvs.code = """
shader_type spatial;
render_mode unshaded;
uniform float on = 1.0;
float h(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
void fragment() {
	vec2 uv = UV;
	// late night news: a studio in blue, a ticker at the bottom, scanlines and a flicker
	vec3 c = mix(vec3(0.05, 0.12, 0.3), vec3(0.15, 0.3, 0.6), uv.y);
	float desk = step(0.62, uv.y) * step(uv.y, 0.8);
	c = mix(c, vec3(0.5, 0.5, 0.55), desk * 0.6);
	float anchor = smoothstep(0.1, 0.08, length((uv - vec2(0.5, 0.5)) * vec2(1.0, 0.8)));
	c = mix(c, vec3(0.7, 0.55, 0.45), anchor);
	float ticker = step(0.86, uv.y) * step(uv.y, 0.95);
	float txt = step(0.5, h(floor(vec2(uv.x * 60.0 + TIME * 8.0, 1.0)))) * ticker;
	c = mix(c, vec3(0.8, 0.1, 0.1), ticker * 0.8);
	c += vec3(txt) * 0.5;
	c *= 0.85 + 0.1 * sin(uv.y * 400.0) + 0.08 * sin(TIME * 13.0) * sin(TIME * 7.3);
	ALBEDO = c * on;
}
"""
	tv_mat.shader = tvs
	var screen := MeshInstance3D.new()
	var sq := QuadMesh.new()
	sq.size = Vector2(1.28, 0.72)
	screen.mesh = sq
	screen.material_override = tv_mat
	screen.position = Vector3(-8.815, f + 1.2, -1.8)
	screen.rotation = Vector3(0, PI * 0.5, 0)
	house.add_child(screen)
	# sofa facing the TV (back to the partition)
	var teal := Color(0.16, 0.33, 0.36)
	var sx := -5.0
	_b("fabric", Vector3(sx, f + 0.22, -1.8), Vector3(0.95, 0.28, 2.4), teal * 0.8)
	for k in 3:
		_b("fabric", Vector3(sx - 0.05, f + 0.44, -2.55 + k * 0.75), Vector3(0.78, 0.18, 0.72), teal)
		_b("fabric", Vector3(sx + 0.36, f + 0.72, -2.55 + k * 0.75), Vector3(0.22, 0.5, 0.72), teal, Vector3(0, 0, -0.12))
	for s: float in [-1.0, 1.0]:
		_b("fabric", Vector3(sx, f + 0.45, -1.8 + s * 1.28), Vector3(0.95, 0.5, 0.18), teal * 0.9)
	for k in 4:
		_b("walnut", Vector3(sx + (0.38 if k < 2 else -0.38), f + 0.05, -1.8 + (1.1 if k % 2 == 0 else -1.1)), Vector3(0.06, 0.1, 0.06))
	_b("fabric", Vector3(sx + 0.1, f + 0.66, -2.75), Vector3(0.14, 0.38, 0.38), Color(0.85, 0.62, 0.2), Vector3(0.1, 0, -0.35))
	_b("fabric", Vector3(sx + 0.1, f + 0.66, -0.9), Vector3(0.14, 0.36, 0.36), Color(0.9, 0.86, 0.78), Vector3(-0.2, 0, -0.3))
	_b("fabric", Vector3(sx + 0.05, f + 0.56, -1.2), Vector3(0.6, 0.05, 0.55), Color(0.55, 0.2, 0.18), Vector3(0.05, 0, 0.05))   # blanket
	# coffee table with the phone, a mug, a book and the remote
	var tx := -6.85
	var tz := -1.8
	_b("walnut", Vector3(tx, f + 0.42, tz), Vector3(0.7, 0.04, 1.2))
	_b("walnut", Vector3(tx, f + 0.14, tz), Vector3(0.62, 0.02, 1.1), Color(0.8, 0.8, 0.8))
	for k in 4:
		_b("walnut", Vector3(tx + (0.3 if k < 2 else -0.3), f + 0.2, tz + (0.54 if k % 2 == 0 else -0.54)), Vector3(0.04, 0.4, 0.04))
	_cyl("gloss", Vector3(tx - 0.12, f + 0.44, tz - 0.35), Vector3(tx - 0.12, f + 0.54, tz - 0.35), 0.042, 0.045, Color(0.9, 0.9, 0.88))
	_cyl("matte", Vector3(tx - 0.12, f + 0.535, tz - 0.35), Vector3(tx - 0.12, f + 0.537, tz - 0.35), 0.038, 0.038, Color(0.2, 0.1, 0.04))
	_b("matte", Vector3(tx + 0.12, f + 0.455, tz + 0.3), Vector3(0.24, 0.03, 0.32), Color(0.6, 0.15, 0.12), Vector3(0, 0.3, 0))
	_b("gloss", Vector3(tx + 0.2, f + 0.45, tz - 0.05), Vector3(0.05, 0.02, 0.18), Color(0.05, 0.05, 0.05), Vector3(0, -0.4, 0))
	phone = Node3D.new()
	phone.name = "Phone"
	house.add_child(phone)
	phone.position = Vector3(tx - 0.05, f + 0.447, tz + 0.12)
	phone.rotation = Vector3(0, 0.35, 0)
	var body := MeshKit.box_node(Vector3(0.075, 0.009, 0.155), TexKit.std(Color(0.03, 0.03, 0.035), 0.2, 0.4))
	phone.add_child(body)
	phone_mat = StandardMaterial3D.new()
	phone_mat.albedo_color = Color(0.02, 0.02, 0.03)
	phone_mat.emission_enabled = true
	phone_mat.emission = Color(0.6, 0.75, 1.0)
	phone_mat.emission_energy_multiplier = 0.0
	var scr := MeshKit.box_node(Vector3(0.068, 0.002, 0.145), phone_mat, Vector3(0, 0.005, 0))
	phone.add_child(scr)
	phone_light = OmniLight3D.new()
	phone_light.light_color = Color(0.6, 0.75, 1.0)
	phone_light.omni_range = 1.4
	phone_light.light_energy = 0.0
	phone_light.position = Vector3(0, 0.12, 0)
	phone.add_child(phone_light)
	# armchair by the window, angled to the TV
	var leather := Color(0.36, 0.2, 0.12)
	var ac := Vector3(-7.7, f, -3.75)
	var rot := Vector3(0, -0.7, 0)
	var b := Basis.from_euler(rot)
	_b("gloss", ac + b * Vector3(0, 0.25, 0), Vector3(0.85, 0.3, 0.8), leather, rot)
	_b("gloss", ac + b * Vector3(0, 0.45, 0.04), Vector3(0.7, 0.14, 0.7), leather * 1.15, rot)
	_b("gloss", ac + b * Vector3(0, 0.75, 0.36), Vector3(0.85, 0.65, 0.16), leather, rot)
	for s: float in [-1.0, 1.0]:
		_b("gloss", ac + b * Vector3(s * 0.38, 0.5, 0.0), Vector3(0.12, 0.3, 0.8), leather * 0.9, rot)
	# floor lamp in the corner (the warm light of the room)
	var lp := Vector3(-8.55, f, -4.1)
	_cyl("metal", lp + Vector3(0, 0.01, 0), lp + Vector3(0, 0.03, 0), 0.16, 0.16, Color(0.1, 0.1, 0.1))
	_cyl("metal", lp + Vector3(0, 0.03, 0), lp + Vector3(0, 1.5, 0), 0.015, 0.015, Color(0.1, 0.1, 0.1), 8)
	_cyl("shade", lp + Vector3(0, 1.45, 0), lp + Vector3(0, 1.75, 0), 0.24, 0.17)
	# side table with a small lamp next to the sofa
	_b("walnut", Vector3(-5.0, f + 0.28, -3.35), Vector3(0.45, 0.56, 0.45))
	_cyl("gloss", Vector3(-5.0, f + 0.56, -3.35), Vector3(-5.0, f + 0.78, -3.35), 0.07, 0.05, Color(0.2, 0.35, 0.3))
	_cyl("shade", Vector3(-5.0, f + 0.78, -3.35), Vector3(-5.0, f + 0.98, -3.35), 0.16, 0.11)
	# bookshelf on the left wall
	var bx := -8.8
	_b("oak", Vector3(bx, f + 1.0, 0.2), Vector3(0.36, 2.0, 1.2), Color(0.8, 0.8, 0.8))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var book_cols := [Color(0.5, 0.1, 0.1), Color(0.1, 0.2, 0.4), Color(0.2, 0.35, 0.2), Color(0.8, 0.7, 0.5), Color(0.2, 0.2, 0.2), Color(0.6, 0.4, 0.1), Color(0.9, 0.9, 0.85)]
	for shelf in 5:
		var y := f + 0.08 + shelf * 0.4
		_b("oak", Vector3(bx + 0.02, y - 0.02, 0.2), Vector3(0.34, 0.03, 1.14))
		var z := -0.34
		while z < 0.72:
			if rng.randf() < 0.12:
				z += rng.randf_range(0.1, 0.2)
				continue
			var th := rng.randf_range(0.03, 0.06)
			var bh := rng.randf_range(0.2, 0.32)
			var lean := 0.0 if rng.randf() < 0.85 else rng.randf_range(-0.25, 0.25)
			_b("matte", Vector3(bx + 0.03, y + bh * 0.5, z), Vector3(rng.randf_range(0.18, 0.24), bh, th), book_cols[rng.randi() % book_cols.size()] * rng.randf_range(0.7, 1.1), Vector3(lean, 0, 0))
			z += th + 0.004
	# a model car and a trophy on the shelves
	_b("gloss", Vector3(bx + 0.05, f + 1.28, 0.55), Vector3(0.1, 0.05, 0.22), Color(0.1, 0.2, 0.55))
	_cyl("chrome", Vector3(bx + 0.05, f + 1.68, -0.2), Vector3(bx + 0.05, f + 1.9, -0.2), 0.03, 0.06, Color(0.85, 0.7, 0.3))
	# big plant by the window
	_plant(Vector3(-4.1, f, -4.05), 1.4, 11)
	_plant(Vector3(-1.4, f, 0.75), 0.9, 5)
	# curtains, rod
	_b("chrome", Vector3(-6.3, f + 2.5, -4.36), Vector3(4.6, 0.03, 0.03), Color(0.2, 0.2, 0.2))
	for s: float in [-1.0, 1.0]:
		for k in 5:
			_b("fabric", Vector3(-6.3 + s * (2.05 + k * 0.08), f + 1.25, -4.33 - (k % 2) * 0.04), Vector3(0.12, 2.5, 0.05), Color(0.72, 0.62, 0.48))
	# a wall light between the clock and the poster
	_b("metal", Vector3(-1.1, f + 2.3, -2.35), Vector3(0.06, 0.08, 0.1), Color(0.15, 0.12, 0.1))
	_cyl("shade", Vector3(-1.22, f + 2.22, -2.35), Vector3(-1.22, f + 2.4, -2.35), 0.1, 0.07)
	# wall clock on the partition (faces the living room, -X)
	_build_clock(Vector3(-1.08, f + 1.95, -3.0))
	# pictures: the Skyline poster and a photo of the Nordschleife gang
	_picture(Vector3(-1.09, f + 1.55, -1.75), 0.9, 0.62, "res://assets/env/posters/poster_3.jpg", -PI * 0.5)
	_picture(Vector3(-6.3, f + 2.55, 4.4), 0.7, 0.5, "res://assets/env/posters/poster_5.jpg", PI)
	# pendant lamp over the coffee table
	_cyl("metal", Vector3(tx, CEIL - 0.9, tz), Vector3(tx, CEIL, tz), 0.006, 0.006, Color(0.1, 0.1, 0.1), 6)
	_cyl("shade", Vector3(tx, CEIL - 1.1, tz), Vector3(tx, CEIL - 0.9, tz), 0.3, 0.12)


func _plant(p: Vector3, h: float, leaves: int) -> void:
	_cyl("gloss", p + Vector3(0, 0, 0), p + Vector3(0, 0.36, 0), 0.16, 0.2, Color(0.85, 0.83, 0.78))
	_cyl("matte", p + Vector3(0, 0.34, 0), p + Vector3(0, 0.35, 0), 0.19, 0.19, Color(0.18, 0.12, 0.08))
	var rng := RandomNumberGenerator.new()
	rng.seed = int(p.x * 100.0 + p.z * 17.0)
	for k in leaves:
		var a := TAU * k / leaves + rng.randf_range(-0.3, 0.3)
		var tilt := rng.randf_range(0.4, 1.0)
		var len := h * rng.randf_range(0.5, 0.8)
		var stem_top := p + Vector3(cos(a) * len * 0.35 * tilt, 0.35 + len * 0.8, sin(a) * len * 0.35 * tilt)
		_cyl("leaf", p + Vector3(0, 0.35, 0), stem_top, 0.01, 0.008, Color(0.2, 0.35, 0.12), 5)
		var leaf_c := stem_top + Vector3(cos(a) * 0.14, -0.05, sin(a) * 0.14)
		_b("leaf", leaf_c, Vector3(0.34, 0.01, 0.26) * rng.randf_range(0.8, 1.2), Color(0.12, 0.38, 0.14), Vector3(0.0, -a, 0.5 * tilt))


func _picture(p: Vector3, w: float, h: float, tex_path: String, yaw: float) -> void:
	var fr := Node3D.new()
	house.add_child(fr)
	fr.position = p
	fr.rotation = Vector3(0, yaw, 0)
	fr.add_child(MeshKit.box_node(Vector3(w + 0.08, h + 0.08, 0.03), TexKit.std(Color(0.08, 0.07, 0.06), 0.4)))
	var m := StandardMaterial3D.new()
	if ResourceLoader.exists(tex_path):
		m.albedo_texture = load(tex_path)
	m.roughness = 0.3
	var q := QuadMesh.new()
	q.size = Vector2(w, h)
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = m
	mi.position = Vector3(0, 0, 0.017)
	fr.add_child(mi)


func _build_clock(p: Vector3) -> void:
	var root := Node3D.new()
	root.name = "Clock"
	house.add_child(root)
	root.position = p
	root.rotation = Vector3(0, -PI * 0.5, 0)      # face -X
	root.add_child(MeshKit.cyl_node(0.25, 0.25, 0.05, TexKit.std(Color(0.28, 0.17, 0.08), 0.35), Vector3(0, 0, -0.02), Vector3(PI * 0.5, 0, 0), 40))
	var fm := StandardMaterial3D.new()
	fm.albedo_texture = TT.clock_face()
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	fm.roughness = 0.5
	var face := MeshInstance3D.new()
	var fq := QuadMesh.new()
	fq.size = Vector2(0.46, 0.46)
	face.mesh = fq
	face.material_override = fm
	face.position = Vector3(0, 0, 0.012)
	root.add_child(face)
	var glass := MeshKit.cyl_node(0.235, 0.235, 0.004, TexKit.glass(Color(0.1, 0.1, 0.1, 0.12)), Vector3(0, 0, 0.035), Vector3(PI * 0.5, 0, 0), 40)
	root.add_child(glass)
	for k in 4:
		var l := Label3D.new()
		l.text = ["12", "3", "6", "9"][k]
		l.font_size = 64
		l.pixel_size = 0.0009
		l.modulate = Color(0.1, 0.08, 0.06)
		l.outline_size = 0
		var a := k * PI * 0.5
		l.position = Vector3(sin(a) * 0.14, cos(a) * 0.14, 0.015)
		root.add_child(l)
	# hands (pivot at the centre, pointing up = 12)
	var specs := [[0.1, 0.014, Color(0.08, 0.06, 0.05)], [0.16, 0.009, Color(0.08, 0.06, 0.05)], [0.18, 0.004, Color(0.7, 0.1, 0.08)]]
	for k in 3:
		var pv := Node3D.new()
		pv.position = Vector3(0, 0, 0.02 + k * 0.004)
		root.add_child(pv)
		var len: float = specs[k][0]
		pv.add_child(MeshKit.box_node(Vector3(float(specs[k][1]), len, 0.003), TexKit.std(specs[k][2], 0.4), Vector3(0, len * 0.4, 0)))
		clock_hands.append(pv)
	root.add_child(MeshKit.cyl_node(0.012, 0.012, 0.01, TexKit.std(Color(0.7, 0.55, 0.2), 0.3, 0.8), Vector3(0, 0, 0.034), Vector3(PI * 0.5, 0, 0), 12))


## Shows the time h:m:s on the wall clock.
func set_clock(h: float, m: float, s: float) -> void:
	if clock_hands.size() < 3:
		return
	(clock_hands[0] as Node3D).rotation.z = -TAU * fposmod(h + m / 60.0, 12.0) / 12.0
	(clock_hands[1] as Node3D).rotation.z = -TAU * (m + s / 60.0) / 60.0
	(clock_hands[2] as Node3D).rotation.z = -TAU * s / 60.0


# ---------------------------------------------------------------------------
# Kitchen (x -9 … -1, z 1 … 4.5)
# ---------------------------------------------------------------------------
func _build_kitchen() -> void:
	var f := FL
	var front := Color(0.9, 0.9, 0.87)
	# base cabinets along the back wall, stone top, sink and hob
	_b("matte", Vector3(-6.3, f + 0.44, 4.15), Vector3(5.4, 0.88, 0.62), front)
	for k in 9:
		_b("matte", Vector3(-8.7 + k * 0.6, f + 0.47, 3.83), Vector3(0.56, 0.78, 0.02), front * 0.97)
		_b("chrome", Vector3(-8.7 + k * 0.6, f + 0.78, 3.81), Vector3(0.22, 0.02, 0.02))
	_b("stone", Vector3(-6.3, f + 0.9, 4.12), Vector3(5.5, 0.04, 0.68), Color(0.12, 0.12, 0.13))
	_b("chrome", Vector3(-6.65, f + 0.9, 4.1), Vector3(0.7, 0.045, 0.42), Color(0.7, 0.7, 0.72))
	_cyl("chrome", Vector3(-6.65, f + 0.92, 4.38), Vector3(-6.65, f + 1.2, 4.38), 0.015, 0.015)
	_cyl("chrome", Vector3(-6.65, f + 1.2, 4.38), Vector3(-6.65, f + 1.2, 4.2), 0.012, 0.012)
	_b("gloss", Vector3(-4.4, f + 0.925, 4.1), Vector3(0.6, 0.01, 0.52), Color(0.03, 0.03, 0.03))
	for k in 4:
		_cyl("matte", Vector3(-4.55 + (k % 2) * 0.3, f + 0.93, 3.98 + (k / 2) * 0.24), Vector3(-4.55 + (k % 2) * 0.3, f + 0.935, 3.98 + (k / 2) * 0.24), 0.09, 0.09, Color(0.15, 0.15, 0.15))
	# range hood, upper cabinets (not over the window)
	_b("metal", Vector3(-4.4, f + 1.85, 4.25), Vector3(0.62, 0.12, 0.45), Color(0.7, 0.7, 0.72))
	_b("metal", Vector3(-4.4, f + 2.3, 4.35), Vector3(0.28, 0.8, 0.25), Color(0.7, 0.7, 0.72))
	for x: float in [-8.4, -5.2]:
		_b("matte", Vector3(x, f + 1.95, 4.3), Vector3(1.2 if x < -6.0 else 0.9, 0.7, 0.35), front)
	# kettle, knife block, fruit bowl, microwave
	_cyl("chrome", Vector3(-5.5, f + 0.92, 4.2), Vector3(-5.5, f + 1.12, 4.2), 0.09, 0.07)
	_b("walnut", Vector3(-7.9, f + 1.02, 4.25), Vector3(0.12, 0.2, 0.18), Color.WHITE, Vector3(0.25, 0, 0))
	_b("gloss", Vector3(-8.5, f + 1.06, 4.2), Vector3(0.5, 0.28, 0.36), Color(0.15, 0.15, 0.15))
	# fridge with magnets
	_b("gloss", Vector3(-3.25, f + 0.93, 4.12), Vector3(0.7, 1.86, 0.66), Color(0.85, 0.86, 0.86))
	_b("chrome", Vector3(-3.55, f + 1.2, 3.78), Vector3(0.03, 0.5, 0.03))
	for k in 5:
		_b("matte", Vector3(-3.1 + (k % 3) * 0.12, f + 1.3 + (k / 3) * 0.2, 3.785), Vector3(0.05, 0.05, 0.01), Color.from_hsv(k * 0.2, 0.7, 0.9))
	_b("matte", Vector3(-3.2, f + 1.1, 3.785), Vector3(0.15, 0.2, 0.004), Color(0.95, 0.95, 0.9))   # a note
	# dining table with two chairs, fruit bowl
	var tc := Vector3(-6.2, f, 2.4)
	_b("oak", tc + Vector3(0, 0.74, 0), Vector3(1.4, 0.04, 0.85))
	for k in 4:
		_b("oak", tc + Vector3((0.62 if k < 2 else -0.62), 0.37, (0.36 if k % 2 == 0 else -0.36)), Vector3(0.05, 0.74, 0.05))
	for s: float in [-1.0, 1.0]:
		var cc := tc + Vector3(s * 0.95, 0, 0)
		_b("oak", cc + Vector3(0, 0.45, 0), Vector3(0.42, 0.04, 0.42))
		_b("oak", cc + Vector3(s * 0.19, 0.72, 0), Vector3(0.03, 0.55, 0.4))
		for k in 4:
			_b("oak", cc + Vector3((0.18 if k < 2 else -0.18), 0.22, (0.18 if k % 2 == 0 else -0.18)), Vector3(0.03, 0.45, 0.03))
	_cyl("gloss", tc + Vector3(0, 0.76, 0), tc + Vector3(0, 0.84, 0), 0.08, 0.16, Color(0.85, 0.85, 0.8))
	for k in 5:
		_sphere("gloss", tc + Vector3(-0.06 + (k % 3) * 0.06, 0.86 + (k / 3) * 0.04, -0.03 + (k % 2) * 0.06), 0.04, [Color(0.8, 0.1, 0.05), Color(0.9, 0.7, 0.1), Color(0.4, 0.7, 0.1)][k % 3])
	_cyl("metal", tc + Vector3(0, CEIL - FL - 0.7, 0), tc + Vector3(0, CEIL - FL, 0), 0.005, 0.005, Color(0.1, 0.1, 0.1), 6)
	_cyl("shade", tc + Vector3(0, CEIL - FL - 0.95, 0), tc + Vector3(0, CEIL - FL - 0.7, 0), 0.22, 0.05)


# ---------------------------------------------------------------------------
# Hallway (x -1 … 2)
# ---------------------------------------------------------------------------
func _build_hall() -> void:
	var f := FL
	_b("rug", Vector3(0.5, f + 0.01, -0.5), Vector3(0.9, 0.01, 6.5), Color(0.55, 0.5, 0.5))
	# shoe rack and shoes by the front door
	_b("oak", Vector3(1.7, f + 0.25, -3.6), Vector3(0.35, 0.5, 0.9))
	for k in 4:
		_b("matte", Vector3(1.62, f + 0.55, -3.95 + k * 0.23), Vector3(0.28, 0.1, 0.1), [Color(0.1, 0.1, 0.1), Color(0.9, 0.9, 0.9), Color(0.5, 0.25, 0.1), Color(0.8, 0.1, 0.1)][k])
	# coat hooks with a jacket
	_b("walnut", Vector3(1.87, f + 1.75, -2.6), Vector3(0.04, 0.1, 1.0))
	for k in 4:
		_b("chrome", Vector3(1.8, f + 1.72, -3.0 + k * 0.27), Vector3(0.08, 0.02, 0.02))
	_b("fabric", Vector3(1.75, f + 1.35, -2.73), Vector3(0.18, 0.75, 0.45), Color(0.12, 0.14, 0.2), Vector3(0, 0, 0.05))
	# console table with the key bowl, a mirror, a picture
	_b("walnut", Vector3(-0.78, f + 0.8, 2.3), Vector3(0.3, 0.04, 1.1))
	for k in 2:
		_b("walnut", Vector3(-0.78, f + 0.4, 1.8 + k * 1.0), Vector3(0.04, 0.8, 0.04))
	_cyl("gloss", Vector3(-0.78, f + 0.82, 2.1), Vector3(-0.78, f + 0.88, 2.1), 0.06, 0.1, Color(0.6, 0.3, 0.2))
	_b("chrome", Vector3(-0.91, f + 1.55, 2.3), Vector3(0.02, 0.9, 0.6), Color(0.8, 0.85, 0.9))
	_picture(Vector3(1.88, f + 1.6, 2.4), 0.5, 0.36, "res://assets/env/posters/poster_2.jpg", -PI * 0.5)
	# bedroom door at the end, door to the garage (opens into the garage)
	_b("walnut", Vector3(0.5, f + 1.05, 4.44), Vector3(0.9, 2.1, 0.05), Color(0.85, 0.85, 0.85))
	_b("chrome", Vector3(0.85, f + 1.0, 4.4), Vector3(0.12, 0.03, 0.04))
	door_pivot = Node3D.new()
	door_pivot.name = "GarageDoor"
	house.add_child(door_pivot)
	door_pivot.position = Vector3(2.0, FL, -0.45)
	var leaf := MeshKit.box_node(Vector3(0.05, 2.08, 0.88), TexKit.std(Color(0.92, 0.92, 0.9), 0.5), Vector3(0.0, 1.04, 0.45))
	door_pivot.add_child(leaf)
	door_pivot.add_child(MeshKit.box_node(Vector3(0.12, 0.03, 0.04), TexKit.std(Color(0.8, 0.8, 0.8), 0.2, 1.0), Vector3(0.0, 1.0, 0.78)))
	# steps down into the garage
	_b("concrete", Vector3(2.35, (FL + GF) * 0.5 - 0.05, 0), Vector3(0.45, FL - GF + 0.1, 1.0), Color(0.75, 0.75, 0.72))
	# hallway ceiling light
	_sphere("shade", Vector3(0.5, CEIL - 0.08, -1.0), 0.18, Color.WHITE, Vector3(1, 0.4, 1))


# ---------------------------------------------------------------------------
# Garage (x 2 … 8.7, z -4.5 … 3.9)
# ---------------------------------------------------------------------------
func _build_garage() -> void:
	var g := GF
	_b("concrete", Vector3(GARAGE_X, g + 0.004, -0.3), Vector3(6.5, 0.008, 8.2), Color(0.85, 0.85, 0.85))
	# painted lines and an oil drip tray
	for x: float in [3.7, 6.9]:
		_b("matte", Vector3(x, g + 0.01, -0.3), Vector3(0.08, 0.004, 6.5), Color(0.85, 0.7, 0.1))
	_b("metal", Vector3(GARAGE_X, g + 0.02, -1.4), Vector3(0.8, 0.03, 0.6), Color(0.15, 0.15, 0.15))
	# workbench along the back wall with vice, toolbox, lamp
	var wz := 3.45
	_b("oak", Vector3(4.2, g + 0.92, wz), Vector3(2.6, 0.06, 0.72))
	_b("oak", Vector3(4.2, g + 0.2, wz), Vector3(2.5, 0.03, 0.66), Color(0.75, 0.75, 0.75))
	for k in 4:
		_b("metal", Vector3(3.0 + (k % 2) * 2.4, g + 0.45, wz + (0.3 if k < 2 else -0.3)), Vector3(0.06, 0.9, 0.06), Color(0.3, 0.32, 0.35))
	_b("metal", Vector3(3.3, g + 1.02, wz - 0.25), Vector3(0.2, 0.14, 0.16), Color(0.25, 0.35, 0.5))
	_b("metal", Vector3(3.3, g + 1.1, wz - 0.36), Vector3(0.24, 0.1, 0.06), Color(0.25, 0.35, 0.5))
	_b("gloss", Vector3(4.6, g + 1.07, wz + 0.1), Vector3(0.55, 0.24, 0.26), Color(0.75, 0.08, 0.06))
	_b("chrome", Vector3(4.6, g + 1.21, wz + 0.1), Vector3(0.3, 0.03, 0.03))
	_cyl("metal", Vector3(5.3, g + 0.95, wz + 0.2), Vector3(5.2, g + 1.5, wz + 0.1), 0.012, 0.012, Color(0.1, 0.1, 0.1), 6)
	_cyl("shade", Vector3(5.2, g + 1.5, wz + 0.1), Vector3(5.05, g + 1.42, wz - 0.05), 0.09, 0.05)
	_cyl("gloss", Vector3(3.9, g + 0.95, wz + 0.15), Vector3(3.9, g + 1.1, wz + 0.15), 0.05, 0.05, Color(0.2, 0.3, 0.2))   # coffee can
	_b("fabric", Vector3(4.0, g + 0.965, wz - 0.2), Vector3(0.3, 0.02, 0.25), Color(0.7, 0.2, 0.15), Vector3(0, 0.4, 0))  # rag
	# pegboard with tools
	_b("pegboard", Vector3(4.2, g + 1.85, 3.74), Vector3(2.6, 1.2, 0.02))
	var rng := RandomNumberGenerator.new()
	rng.seed = 12
	for k in 7:
		var x := 3.2 + k * 0.3
		var l := 0.18 + k * 0.03
		_b("chrome", Vector3(x, g + 1.9, 3.71), Vector3(0.025, l, 0.012), Color(0.8, 0.8, 0.82), Vector3(0, 0, 0.1))
	_b("walnut", Vector3(5.35, g + 1.8, 3.71), Vector3(0.035, 0.36, 0.03))
	_b("metal", Vector3(5.35, g + 1.98, 3.71), Vector3(0.14, 0.05, 0.04), Color(0.2, 0.2, 0.22))
	for k in 4:
		_b("gloss", Vector3(3.3 + k * 0.12, g + 1.5, 3.71), Vector3(0.025, 0.1, 0.025), Color.from_hsv(k * 0.25, 0.8, 0.8))
		_b("chrome", Vector3(3.3 + k * 0.12, g + 1.4, 3.71), Vector3(0.008, 0.12, 0.008))
	_picture(Vector3(7.3, g + 1.75, 3.73), 1.0, 0.7, "res://assets/env/posters/poster_3.jpg", PI)
	# steel shelving on the right wall with boxes and paint cans
	var sx := 8.35
	for k in 4:
		_b("metal", Vector3(sx, g + 0.3 + k * 0.55, 1.2), Vector3(0.5, 0.03, 2.2), Color(0.4, 0.42, 0.45))
	for k in 4:
		_b("metal", Vector3(sx + (0.22 if k < 2 else -0.22), g + 1.0, 1.2 + (1.08 if k % 2 == 0 else -1.08)), Vector3(0.04, 2.0, 0.04), Color(0.4, 0.42, 0.45))
	for shelf in 3:
		var y := g + 0.32 + shelf * 0.55
		var z := 0.2
		while z < 2.15:
			var w := rng.randf_range(0.25, 0.5)
			if rng.randf() < 0.3:
				_cyl("metal", Vector3(sx, y, z + 0.1), Vector3(sx, y + 0.2, z + 0.1), 0.09, 0.09, Color.from_hsv(rng.randf(), 0.5, 0.7))
				z += 0.24
			else:
				var hh := rng.randf_range(0.2, 0.4)
				_b("matte", Vector3(sx, y + hh * 0.5, z + w * 0.5), Vector3(0.4, hh, w - 0.03), Color(0.62, 0.48, 0.3) * rng.randf_range(0.85, 1.1))
				z += w
	# wheel rack with four spare wheels
	for k in 4:
		var c := Vector3(8.2, g + 0.34, -2.1 + k * 0.28)
		_cyl("matte", c - Vector3(0, 0, 0.11), c + Vector3(0, 0, 0.11), 0.33, 0.33, Color(0.06, 0.06, 0.065), 20)
		_cyl("chrome", c - Vector3(0, 0, 0.115), c + Vector3(0, 0, 0.115), 0.22, 0.22, Color(0.75, 0.75, 0.78), 14)
	_b("metal", Vector3(8.2, g + 0.05, -1.7), Vector3(0.5, 0.06, 1.3), Color(0.2, 0.2, 0.2))
	# rolling tool chest, floor jack, creeper, fire extinguisher
	_b("gloss", Vector3(2.5, g + 0.55, 2.9), Vector3(0.55, 1.0, 0.9), Color(0.72, 0.06, 0.05))
	for k in 6:
		_b("chrome", Vector3(2.79, g + 0.2 + k * 0.15, 2.9), Vector3(0.02, 0.02, 0.6))
	_b("gloss", Vector3(7.3, g + 0.12, -3.6), Vector3(0.35, 0.16, 0.8), Color(0.75, 0.1, 0.05))
	_cyl("chrome", Vector3(7.3, g + 0.2, -3.2), Vector3(7.3, g + 0.75, -2.7), 0.02, 0.02)
	_b("matte", Vector3(3.2, g + 0.06, -2.9), Vector3(0.45, 0.06, 1.0), Color(0.15, 0.15, 0.15))
	_cyl("gloss", Vector3(2.18, g + 0.6, -1.3), Vector3(2.18, g + 1.1, -1.3), 0.08, 0.08, Color(0.8, 0.05, 0.05))
	# fluorescent fittings (off until the cutscene switches them on)
	for z: float in [-2.2, 1.4]:
		_b("metal", Vector3(GARAGE_X, CEIL - 0.06, z), Vector3(0.25, 0.06, 1.5), Color(0.85, 0.85, 0.85))
	# roller door: slats on a pivot at the lintel, drum housing above
	_b("metal", Vector3(GARAGE_X, GF + 2.72, -4.3), Vector3(4.8, 0.36, 0.36), Color(0.8, 0.8, 0.8))
	roller = Node3D.new()
	roller.name = "RollerDoor"
	house.add_child(roller)
	roller.position = Vector3(GARAGE_X, GF + 2.5, -4.5)
	var panel_m := StandardMaterial3D.new()
	panel_m.albedo_texture = TT.slats()
	panel_m.roughness = 0.4
	panel_m.metallic = 0.3
	panel_m.uv1_scale = Vector3(1, 3.2, 1)
	var panel := MeshKit.box_node(Vector3(4.6, 2.5, 0.05), panel_m, Vector3(0, -1.25, 0))
	panel.name = "Panel"
	roller.add_child(panel)
	roller_body = Colliders.add_box(self, house_xf * Transform3D(Basis.IDENTITY, Vector3(GARAGE_X, GF + 1.25, -4.5)), Vector3(4.6, 2.5, 0.2))


## 0 = closed … 1 = open (the slats roll up into the drum).
func set_roller(k: float) -> void:
	if roller == null:
		return
	var panel: Node3D = roller.get_node("Panel")
	var h := 2.5 * (1.0 - k)
	panel.scale = Vector3(1, maxf(1.0 - k, 0.02), 1)
	panel.position = Vector3(0, -h * 0.5, 0)
	if roller_body:
		roller_body.process_mode = Node.PROCESS_MODE_DISABLED if k > 0.7 else Node.PROCESS_MODE_INHERIT
		for c in roller_body.get_children():
			(c as CollisionShape3D).disabled = k > 0.7


# ---------------------------------------------------------------------------
# Outside: lights, bins, a bike, the woodpile, the mailbox by the road
# ---------------------------------------------------------------------------
func _build_outside() -> void:
	# lamps above the front door and the garage door
	for p in [Vector3(0.55, FL + 2.2, -4.72), Vector3(GARAGE_X, GF + 3.0, -4.74)]:
		_b("metal", p, Vector3(0.18, 0.26, 0.1), Color(0.1, 0.1, 0.1))
		_b("shade", p + Vector3(0, -0.02, -0.06), Vector3(0.12, 0.18, 0.02))
	# bins beside the garage, a bicycle leaning at the wall
	for k in 2:
		_b("gloss", Vector3(9.3, 0.55, -3.2 + k * 0.75), Vector3(0.6, 1.1, 0.7), [Color(0.2, 0.3, 0.2), Color(0.15, 0.15, 0.4)][k])
		_b("gloss", Vector3(9.25, 1.12, -3.2 + k * 0.75), Vector3(0.66, 0.05, 0.74), [Color(0.15, 0.22, 0.15), Color(0.1, 0.1, 0.3)][k], Vector3(0, 0, 0.08))
	var bk := Vector3(-9.45, 0, -2.0)
	for dz: float in [-0.52, 0.52]:
		_cyl("matte", bk + Vector3(0, 0.34, dz) - Vector3(0.02, 0, 0), bk + Vector3(0, 0.34, dz) + Vector3(0.02, 0, 0), 0.34, 0.34, Color(0.05, 0.05, 0.05), 20)
	_cyl("gloss", bk + Vector3(0, 0.34, -0.52), bk + Vector3(0, 0.8, 0.0), 0.02, 0.02, Color(0.1, 0.4, 0.6), 6)
	_cyl("gloss", bk + Vector3(0, 0.34, 0.52), bk + Vector3(0, 0.8, 0.0), 0.02, 0.02, Color(0.1, 0.4, 0.6), 6)
	_cyl("gloss", bk + Vector3(0, 0.8, 0.0), bk + Vector3(0, 0.95, 0.48), 0.02, 0.02, Color(0.1, 0.4, 0.6), 6)
	_b("matte", bk + Vector3(0, 0.88, -0.05), Vector3(0.1, 0.04, 0.24), Color(0.05, 0.05, 0.05))
	# woodpile under a small roof against the back wall
	var bark: Array = TexKit.log_materials()
	var wp := Vector3(-5.0, 0, 5.3)
	_b("roof", wp + Vector3(0, 1.6, 0.1), Vector3(3.2, 0.06, 1.0), Color.WHITE, Vector3(-0.2, 0, 0))
	for k in 30:
		var lx := -1.4 + (k % 10) * 0.3
		var ly := 0.15 + (k / 10) * 0.28
		var lg := MeshKit.cyl_node(0.14, 0.14, 0.7, bark[0], wp + Vector3(lx, ly, 0), Vector3(PI * 0.5, 0, 0), 8)
		house.add_child(lg)
	# the mailbox by the road, a lamp post at the end of the driveway
	var i: int = track.index_at(HOUSE_P)
	var away: Vector3 = track.rights[i] * HOUSE_SIDE
	var off: float = track.off_right[i] if HOUSE_SIDE > 0.0 else track.off_left[i]
	var mb_w: Vector3 = track.samples[i] + away * (off + 2.5) + track.tangents[i] * 4.0
	var mb := house_xf.affine_inverse() * mb_w
	mb.y = terrain.height_at(mb_w.x, mb_w.z) - ground
	_b("metal", mb + Vector3(0, 0.55, 0), Vector3(0.06, 1.1, 0.06), Color(0.1, 0.1, 0.1))
	_b("gloss", mb + Vector3(0, 1.2, 0), Vector3(0.3, 0.25, 0.45), Color(0.1, 0.25, 0.15))
	var nm := Label3D.new()
	nm.text = "TAKEDA"
	nm.font_size = 40
	nm.pixel_size = 0.002
	nm.modulate = Color(0.9, 0.9, 0.85)
	nm.position = mb + Vector3(-0.16, 1.2, 0)
	nm.rotation = Vector3(0, -PI * 0.5, 0)
	house.add_child(nm)
	var lp_w: Vector3 = track.samples[i] + away * (off + 2.5) - track.tangents[i] * 5.0
	var lp := house_xf.affine_inverse() * lp_w
	lp.y = terrain.height_at(lp_w.x, lp_w.z) - ground
	_cyl("metal", lp, lp + Vector3(0, 3.2, 0), 0.06, 0.05, Color(0.12, 0.12, 0.12), 8)
	_b("metal", lp + Vector3(0, 3.25, 0), Vector3(0.3, 0.12, 0.3), Color(0.12, 0.12, 0.12))
	_b("shade", lp + Vector3(0, 3.15, 0), Vector3(0.24, 0.1, 0.24))
	_lamp(lp + Vector3(0, 3.0, 0), Color(1.0, 0.8, 0.55), 1.3, 10.0, false)


# ---------------------------------------------------------------------------
# Lights
# ---------------------------------------------------------------------------
func _lamp(local: Vector3, col: Color, energy: float, rng: float, shadow := false) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = col
	l.light_energy = energy
	l.omni_range = rng
	l.omni_attenuation = 1.4
	l.shadow_enabled = shadow
	l.position = local
	house.add_child(l)
	return l


func _build_lights() -> void:
	_lamp(Vector3(-8.55, FL + 1.6, -4.1), WARM, 1.8, 8.5, true)            # floor lamp
	_lamp(Vector3(-4.2, CEIL - 0.5, -1.9), WARM, 0.55, 8.0)                 # soft fill from the ceiling
	_lamp(Vector3(-1.35, FL + 2.3, -2.35), WARM, 0.7, 4.0)                  # wall light by the clock
	_lamp(Vector3(-5.0, FL + 0.95, -3.35), WARM, 0.5, 3.0)                  # side table
	_lamp(Vector3(-6.85, CEIL - 1.2, -1.8), WARM, 0.9, 5.5, true)           # pendant
	_lamp(Vector3(-6.2, CEIL - 1.05, 2.4), WARM, 0.8, 5.0)                  # kitchen
	_lamp(Vector3(-6.3, FL + 1.3, 4.0), Color(1.0, 0.85, 0.65), 0.35, 3.0)  # under the wall cabinets
	_lamp(Vector3(0.5, CEIL - 0.3, -1.0), WARM, 0.6, 5.0)                   # hallway
	_lamp(Vector3(0.55, FL + 2.0, -5.1), WARM, 0.9, 7.0)                    # porch
	_lamp(Vector3(GARAGE_X, GF + 2.8, -5.2), WARM, 1.2, 9.0)                # above the garage door
	_lamp(Vector3(5.1, GF + 1.35, 3.3), Color(1.0, 0.9, 0.75), 0.4, 2.5)   # workbench lamp
	tv_light = _lamp(Vector3(-8.2, FL + 1.2, -1.8), Color(0.45, 0.6, 1.0), 0.6, 4.5)
	for z: float in [-2.2, 1.4]:
		var tube := StandardMaterial3D.new()
		tube.albedo_color = Color(0.9, 0.95, 1.0)
		tube.emission_enabled = true
		tube.emission = Color(0.9, 0.95, 1.0)
		tube.emission_energy_multiplier = 0.0
		var tm := MeshKit.box_node(Vector3(0.08, 0.04, 1.4), tube, Vector3(GARAGE_X, CEIL - 0.1, z))
		house.add_child(tm)
		var l := _lamp(Vector3(GARAGE_X, CEIL - 0.3, z), Color(0.9, 0.95, 1.0), 0.0, 8.5, z < 0.0)
		garage_lights.append([l, tube])
	# the lightning: a cold light from above that throws the window frames into the room
	lightning = DirectionalLight3D.new()
	lightning.name = "Lightning"
	lightning.light_color = Color(0.78, 0.84, 1.0)
	lightning.light_energy = 0.0
	lightning.shadow_enabled = true
	lightning.directional_shadow_max_distance = 60.0
	add_child(lightning)
	lightning.global_transform = Transform3D(Basis.looking_at((house_xf.basis * Vector3(0.3, -0.8, 1.0)).normalized(), Vector3.UP), house_xf.origin)


## 0 … 1: the garage fluorescents (k > 0 flickers between on and off while starting).
func set_garage_lights(k: float) -> void:
	for gl in garage_lights:
		(gl[0] as OmniLight3D).light_energy = 1.5 * k
		(gl[1] as StandardMaterial3D).emission_energy_multiplier = 3.0 * k


# ---------------------------------------------------------------------------
# The gravel track, the clearing, the caravan and the campfire
# ---------------------------------------------------------------------------
func _build_exit_and_camp() -> void:
	var i: int = track.index_at(EXIT_P)
	var t: Vector3 = track.tangents[i]
	t.y = 0.0
	t = t.normalized()
	var away: Vector3 = track.rights[i] * EXIT_SIDE
	away.y = 0.0
	away = away.normalized()
	var off: float = track.off_right[i] if EXIT_SIDE > 0.0 else track.off_left[i]
	var road: Vector3 = track.samples[i]
	exit_xf = Transform3D(Basis.looking_at(t, Vector3.UP), road)
	var p0 := road + away * (float(track.half_w) + 0.8)
	var ctrl := [p0, road + away * (off + 8.0) + t * 2.0, road + away * (off + 35.0) + t * 9.0, road + away * (off + 70.0) - t * 3.0,
		road + away * (off + 100.0) + t * 6.0, road + away * (off + 118.0) + t * 4.0]
	camp = ctrl[ctrl.size() - 1]
	var cy: float = terrain.flatten(camp, 13.0, 10.0)
	camp.y = cy
	# smooth track through the control points
	path_pts.clear()
	for k in ctrl.size() - 1:
		var a: Vector3 = ctrl[maxi(k - 1, 0)]
		var b: Vector3 = ctrl[k]
		var c: Vector3 = ctrl[k + 1]
		var d: Vector3 = ctrl[mini(k + 2, ctrl.size() - 1)]
		var n := maxi(int(b.distance_to(c) / 2.0), 2)
		for j in n:
			var p := _catmull(a, b, c, d, float(j) / n)
			p.y = terrain.height_at(p.x, p.z)
			path_pts.append(p)
	path_pts.append(camp)
	for p in path_pts:
		scenery.occupy(p, 3.4)
	scenery.occupy(camp, 17.0)
	_paint(camp, 12.0, Color(0.15, 0.55, 0.3, 0.0))
	var strip: Array = []
	for p in path_pts:
		strip.append(p)
	var holder := Node3D.new()
	holder.name = "TutorialTrack"
	add_child(holder)
	_strip_world(strip, 3.4, "gravel", holder)
	# reflector posts along the track
	var post_m := TexKit.std(Color(0.9, 0.9, 0.9), 0.6)
	var refl := StandardMaterial3D.new()
	refl.albedo_color = Color(1.0, 0.55, 0.1)
	refl.emission_enabled = true
	refl.emission = Color(1.0, 0.5, 0.1)
	refl.emission_energy_multiplier = 1.2
	for k in range(4, path_pts.size() - 4, 6):
		var p: Vector3 = path_pts[k]
		var q: Vector3 = path_pts[k + 1]
		var dir := (q - p)
		dir.y = 0.0
		dir = dir.normalized()
		var side := Vector3(-dir.z, 0, dir.x)
		for s: float in [-1.0, 1.0]:
			var pp := p + side * s * 2.3
			pp.y = terrain.height_at(pp.x, pp.z)
			holder.add_child(MeshKit.box_node(Vector3(0.1, 1.0, 0.1), post_m, pp + Vector3(0, 0.5, 0)))
			holder.add_child(MeshKit.box_node(Vector3(0.11, 0.12, 0.11), refl, pp + Vector3(0, 0.85, 0)))
	# a sign at the turn-off and a faint beacon of light above the trees
	var sp := road + away * (off + 4.0) - t * 6.0
	sp.y = terrain.height_at(sp.x, sp.z)
	holder.add_child(MeshKit.box_node(Vector3(0.12, 2.2, 0.12), TexKit.std(Color(0.35, 0.25, 0.15), 0.8), sp + Vector3(0, 1.1, 0)))
	var board := Node3D.new()
	holder.add_child(board)
	board.global_transform = Transform3D(Basis.looking_at(-away, Vector3.UP), sp + Vector3(0, 1.9, 0))
	board.add_child(MeshKit.box_node(Vector3(1.5, 0.45, 0.05), TexKit.std(Color(0.4, 0.28, 0.16), 0.8)))
	var sl := Label3D.new()
	sl.text = "Waldweg ↗\nAdenauer Forst"
	sl.font_size = 44
	sl.pixel_size = 0.0045
	sl.modulate = Color(0.95, 0.92, 0.8)
	sl.position = Vector3(0, 0, 0.03)
	board.add_child(sl)
	beacon = Node3D.new()
	add_child(beacon)
	beacon.global_position = camp
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	bm.albedo_color = Color(1.0, 0.55, 0.2, 0.08)
	bm.cull_mode = BaseMaterial3D.CULL_DISABLED
	var col := MeshKit.cyl_node(1.2, 3.0, 60.0, bm, Vector3(0, 30.0, 0), Vector3.ZERO, 16)
	col.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beacon.add_child(col)
	# the friend's car at the turn-off: hazards on, left in a hurry
	_friend_car(road + away * (off + 6.0) + t * 5.0, away)
	_build_camp()


static func _catmull(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (p2 - p0) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (3.0 * p1 - p0 - 3.0 * p2 + p3) * t3)


func _friend_car(p: Vector3, away: Vector3) -> void:
	p.y = terrain.height_at(p.x, p.z)
	var root := Node3D.new()
	root.name = "FriendCar"
	add_child(root)
	root.global_transform = Transform3D(Basis.looking_at(away.rotated(Vector3.UP, 0.5), Vector3.UP), p)
	var st := MeshKit.new_st()
	var paint := Color(0.85, 0.85, 0.82)
	MeshKit.box(st, Transform3D(Basis.IDENTITY, Vector3(0, 0.62, 0)), Vector3(1.76, 0.62, 4.4), paint)
	MeshKit.box(st, Transform3D(Basis.IDENTITY, Vector3(0, 1.12, 0.25)), Vector3(1.56, 0.46, 2.3), paint)
	MeshKit.box(st, Transform3D(Basis.IDENTITY, Vector3(0, 1.12, 0.25)), Vector3(1.6, 0.36, 2.2), Color(0.05, 0.06, 0.08))
	var car_m := StandardMaterial3D.new()
	car_m.vertex_color_use_as_albedo = true
	car_m.roughness = 0.25
	car_m.metallic = 0.4
	root.add_child(MeshKit.mesh_instance(MeshKit.commit(st, car_m)))
	for z: float in [-1.35, 1.35]:
		for x: float in [-0.8, 0.8]:
			root.add_child(MeshKit.cyl_node(0.32, 0.32, 0.22, TexKit.rubber(), Vector3(x, 0.32, z), Vector3(0, 0, PI * 0.5), 16))
	# hazard lights at the four corners (blinking, see set_hazards)
	for c in [Vector3(-0.72, 0.72, -2.2), Vector3(0.72, 0.72, -2.2), Vector3(-0.72, 0.8, 2.2), Vector3(0.72, 0.8, 2.2)]:
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(1.0, 0.6, 0.1)
		m.emission_enabled = true
		m.emission = Color(1.0, 0.55, 0.05)
		var bulb := MeshKit.box_node(Vector3(0.2, 0.1, 0.05), m, c)
		root.add_child(bulb)
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.55, 0.1)
		l.omni_range = 6.0
		l.position = c + Vector3(0, 0, signf(c.z) * 0.3)
		root.add_child(l)
		hazards.append([l, m])
	Colliders.add_box(root, root.global_transform * Transform3D(Basis.IDENTITY, Vector3(0, 0.75, 0)), Vector3(1.8, 1.4, 4.4))
	# the driver's door stands open
	root.add_child(MeshKit.box_node(Vector3(0.06, 0.6, 1.1), TexKit.std(paint, 0.25, 0.4), Vector3(1.25, 0.8, -0.2), Vector3(0, -0.9, 0)))


func set_hazards(on: bool) -> void:
	for h in hazards:
		(h[0] as OmniLight3D).light_energy = 1.2 if on else 0.0
		(h[1] as StandardMaterial3D).emission_energy_multiplier = 3.0 if on else 0.05


func _build_camp() -> void:
	var root := Node3D.new()
	root.name = "Camp"
	add_child(root)
	# the camp faces back down the gravel track
	var back := (path_pts[maxi(path_pts.size() - 8, 0)] - camp)
	back.y = 0.0
	back = back.normalized()
	root.global_transform = Transform3D(Basis.looking_at(back, Vector3.UP), camp)
	# caravan: body, rounded roof, stripe, windows, door, wheels, drawbar, awning, gas bottles
	caravan = Node3D.new()
	caravan.name = "Caravan"
	root.add_child(caravan)
	caravan.position = Vector3(5.5, 0, 4.0)
	caravan.rotation = Vector3(0, -0.35, 0)
	var st := MeshKit.new_st()
	var cream := Color(0.78, 0.76, 0.7)
	MeshKit.box(st, Transform3D(Basis.IDENTITY, Vector3(0, 1.45, 0)), Vector3(2.2, 1.9, 5.2), cream)
	MeshKit.box(st, Transform3D(Basis.IDENTITY, Vector3(0, 2.45, 0)), Vector3(2.0, 0.2, 5.0), cream * 0.97)
	MeshKit.box(st, Transform3D(Basis.IDENTITY, Vector3(0, 1.0, 0)), Vector3(2.22, 0.12, 5.22), Color(0.2, 0.45, 0.55))
	MeshKit.box(st, Transform3D(Basis.IDENTITY, Vector3(0, 0.45, 0)), Vector3(1.9, 0.12, 4.8), Color(0.15, 0.15, 0.15))
	MeshKit.box(st, Transform3D(Basis.IDENTITY, Vector3(0, 0.5, -3.2)), Vector3(0.12, 0.1, 1.6), Color(0.3, 0.3, 0.3))
	MeshKit.box(st, Transform3D(Basis.IDENTITY, Vector3(0, 0.65, -2.8)), Vector3(0.7, 0.5, 0.35), Color(0.75, 0.75, 0.75))
	var cm := StandardMaterial3D.new()
	cm.vertex_color_use_as_albedo = true
	cm.roughness = 0.5
	caravan.add_child(MeshKit.mesh_instance(MeshKit.commit(st, cm)))
	for z: float in [-0.3]:
		for x: float in [-1.0, 1.0]:
			caravan.add_child(MeshKit.cyl_node(0.33, 0.33, 0.2, TexKit.rubber(), Vector3(x, 0.33, z), Vector3(0, 0, PI * 0.5), 16))
	for k in 2:
		caravan.add_child(MeshKit.cyl_node(0.15, 0.15, 0.55, TexKit.std(Color(0.2, 0.35, 0.8), 0.4, 0.2), Vector3(-0.2 + k * 0.4, 0.95, -2.8)))
	# windows: one lit from inside, warm and flickering
	var win_lit := StandardMaterial3D.new()
	win_lit.albedo_color = Color(0.3, 0.2, 0.1)
	win_lit.emission_enabled = true
	win_lit.emission = Color(1.0, 0.65, 0.3)
	win_lit.emission_energy_multiplier = 1.6
	caravan.add_child(MeshKit.box_node(Vector3(0.02, 0.6, 1.1), win_lit, Vector3(-1.11, 1.8, 1.2)))
	caravan.add_child(MeshKit.box_node(Vector3(0.02, 0.5, 0.9), TexKit.glass(), Vector3(-1.11, 1.8, -1.3)))
	caravan.add_child(MeshKit.box_node(Vector3(0.03, 1.8, 0.7), TexKit.std(cream * 0.9, 0.5), Vector3(-1.12, 1.35, -0.1)))
	caravan.add_child(MeshKit.box_node(Vector3(0.5, 0.2, 0.8), TexKit.std(Color(0.4, 0.4, 0.4), 0.7), Vector3(-1.45, 0.3, -0.1)))
	caravan_light = OmniLight3D.new()
	caravan_light.light_color = Color(1.0, 0.65, 0.3)
	caravan_light.omni_range = 7.0
	caravan_light.light_energy = 0.9
	caravan_light.position = Vector3(-1.8, 1.8, 1.2)
	caravan.add_child(caravan_light)
	# awning
	var aw := TexKit.std(Color(0.22, 0.32, 0.26), 0.9)
	caravan.add_child(MeshKit.box_node(Vector3(2.4, 0.03, 3.2), aw, Vector3(-2.3, 2.35, 0.2), Vector3(0, 0, -0.18)))
	for z: float in [-1.3, 1.7]:
		caravan.add_child(MeshKit.cyl_node(0.025, 0.025, 2.2, TexKit.std(Color(0.6, 0.6, 0.6), 0.3, 0.8), Vector3(-3.45, 1.1, z)))
	Colliders.add_box(root, root.global_transform * caravan.transform * Transform3D(Basis.IDENTITY, Vector3(0, 1.4, 0)), Vector3(2.2, 2.4, 5.2))
	# campfire: stones, logs, flames, embers, smoke and a flickering light that throws shadows
	var fire := Node3D.new()
	fire.name = "Fire"
	root.add_child(fire)
	fire.position = Vector3(0.0, 0, 3.2)
	var stone := TexKit.rock_material()
	for k in 11:
		var a := TAU * k / 11.0
		var sm := MeshKit.sphere_node(0.16, stone, Vector3(cos(a) * 0.62, 0.06, sin(a) * 0.62), Vector3(1.2, 0.7, 1.0))
		fire.add_child(sm)
	var bark: Array = TexKit.log_materials()
	for k in 4:
		var a := TAU * k / 4.0 + 0.4
		fire.add_child(MeshKit.cyl_node(0.07, 0.08, 0.8, bark[0], Vector3(cos(a) * 0.15, 0.2, sin(a) * 0.15), Vector3(0.9, a, 0.0), 8))
	fire.add_child(_flames())
	fire_light = OmniLight3D.new()
	fire_light.light_color = Color(1.0, 0.55, 0.2)
	fire_light.light_energy = 1.6
	fire_light.omni_range = 12.0
	fire_light.shadow_enabled = true
	fire_light.position = Vector3(0, 0.8, 0)
	fire.add_child(fire_light)
	# log benches, two camping chairs, a table with a lantern
	for k in 2:
		var a := PI * 0.5 + k * PI + 0.3
		fire.add_child(MeshKit.cyl_node(0.22, 0.22, 1.6, bark[0], Vector3(cos(a) * 1.9, 0.22, sin(a) * 1.9), Vector3(0, a, PI * 0.5), 10))
	for k in 2:
		var ch := Node3D.new()
		fire.add_child(ch)
		ch.position = Vector3(-1.6 + k * 3.2, 0, -1.2)
		ch.rotation = Vector3(0, (0.7 if k == 0 else -0.7), 0)
		ch.add_child(MeshKit.box_node(Vector3(0.55, 0.05, 0.5), TexKit.std(Color(0.15, 0.3, 0.2), 0.9), Vector3(0, 0.45, 0)))
		ch.add_child(MeshKit.box_node(Vector3(0.55, 0.55, 0.05), TexKit.std(Color(0.15, 0.3, 0.2), 0.9), Vector3(0, 0.75, 0.25), Vector3(-0.2, 0, 0)))
		for x: float in [-0.25, 0.25]:
			ch.add_child(MeshKit.box_node(Vector3(0.03, 0.62, 0.03), TexKit.std(Color(0.2, 0.2, 0.2), 0.3, 0.8), Vector3(x, 0.3, 0.0), Vector3(0.3, 0, 0)))
	var table := Vector3(-3.0, 0, 1.5)
	fire.add_child(MeshKit.box_node(Vector3(0.9, 0.04, 0.6), TexKit.std(Color(0.8, 0.8, 0.78), 0.5), table + Vector3(0, 0.7, 0)))
	fire.add_child(MeshKit.cyl_node(0.08, 0.08, 0.22, TexKit.glass(Color(1.0, 0.8, 0.4, 0.3)), table + Vector3(0.2, 0.83, 0)))
	lantern_light = OmniLight3D.new()
	lantern_light.light_color = Color(1.0, 0.8, 0.5)
	lantern_light.light_energy = 0.6
	lantern_light.omni_range = 5.0
	lantern_light.position = table + Vector3(0.2, 0.9, 0)
	fire.add_child(lantern_light)
	# Kenji, standing by the fire and looking down the track
	kenji = _person(Color(0.1, 0.12, 0.2), Color(0.18, 0.18, 0.2), Color(0.85, 0.66, 0.5), true)
	root.add_child(kenji)
	kenji.position = Vector3(0.7, 0, 4.9)
	kenji.rotation = Vector3(0, 0.15, 0)
	# eyes between the trees behind the camp (only the last lightning shows them)
	var eye_m := StandardMaterial3D.new()
	eye_m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	eye_m.albedo_color = Color(1.0, 0.15, 0.1)
	for k in 3:
		var e := Node3D.new()
		root.add_child(e)
		var ex := -8.0 + k * 7.0
		var ez := 17.0 + k * 3.0
		e.position = Vector3(ex, terrain.height_at((root.global_transform * Vector3(ex, 0, ez)).x, (root.global_transform * Vector3(ex, 0, ez)).z) - camp.y + 1.7, ez)
		for s: float in [-1.0, 1.0]:
			e.add_child(MeshKit.sphere_node(0.035, eye_m, Vector3(s * 0.09, 0, 0)))
		e.visible = false
		eyes.append(e)


## Flames, embers and smoke for the campfire.
func _flames() -> Node3D:
	var root := Node3D.new()
	# flames: short-lived, rising, orange to red, additive
	var p := GPUParticles3D.new()
	p.amount = 140
	p.lifetime = 0.7
	p.local_coords = true
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	m.emission_sphere_radius = 0.22
	m.direction = Vector3(0, 1, 0)
	m.spread = 12.0
	m.initial_velocity_min = 0.6
	m.initial_velocity_max = 1.3
	m.gravity = Vector3(0, 1.2, 0)
	m.scale_min = 0.6
	m.scale_max = 1.2
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.6))
	sc.add_point(Vector2(0.3, 1.0))
	sc.add_point(Vector2(1, 0.1))
	var sct := CurveTexture.new()
	sct.curve = sc
	m.scale_curve = sct
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.62, 0.22, 0.75))
	g.add_point(0.4, Color(0.95, 0.32, 0.06, 0.55))
	g.set_color(1, Color(0.5, 0.08, 0.02, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	m.color_ramp = gt
	p.process_material = m
	var q := QuadMesh.new()
	q.size = Vector2(0.26, 0.38)
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	fm.vertex_color_use_as_albedo = true
	fm.albedo_texture = TexKit.smoke_texture()
	q.material = fm
	p.draw_pass_1 = q
	p.position = Vector3(0, 0.15, 0)
	root.add_child(p)
	# embers
	var e := GPUParticles3D.new()
	e.amount = 30
	e.lifetime = 2.2
	var em := ParticleProcessMaterial.new()
	em.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	em.emission_sphere_radius = 0.2
	em.direction = Vector3(0, 1, 0)
	em.spread = 25.0
	em.initial_velocity_min = 1.0
	em.initial_velocity_max = 2.5
	em.gravity = Vector3(0, 0.3, 0)
	em.turbulence_enabled = true
	em.turbulence_noise_strength = 1.5
	em.color = Color(1.0, 0.5, 0.1)
	e.process_material = em
	var eq := QuadMesh.new()
	eq.size = Vector2(0.025, 0.025)
	var emt := StandardMaterial3D.new()
	emt.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	emt.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	emt.albedo_color = Color(1.0, 0.6, 0.2)
	emt.vertex_color_use_as_albedo = true
	eq.material = emt
	e.draw_pass_1 = eq
	e.position = Vector3(0, 0.3, 0)
	root.add_child(e)
	# thin smoke above the flames (the tyre smoke shader, darker)
	var s := GPUParticles3D.new()
	s.amount = 40
	s.lifetime = 5.0
	var sm := ParticleProcessMaterial.new()
	sm.direction = Vector3(0, 1, 0)
	sm.spread = 10.0
	sm.initial_velocity_min = 0.6
	sm.initial_velocity_max = 1.0
	sm.gravity = Vector3(0.1, 0.1, 0)
	sm.scale_min = 0.8
	sm.scale_max = 1.4
	var ssc := Curve.new()
	ssc.add_point(Vector2(0, 0.5))
	ssc.add_point(Vector2(1, 3.0))
	ssc.max_value = 3.0
	var ssct := CurveTexture.new()
	ssct.curve = ssc
	sm.scale_curve = ssct
	var sg := Gradient.new()
	sg.set_color(0, Color(0.5, 0.48, 0.45, 0.0))
	sg.add_point(0.15, Color(0.5, 0.48, 0.45, 0.25))
	sg.set_color(1, Color(0.4, 0.4, 0.42, 0.0))
	var sgt := GradientTexture1D.new()
	sgt.gradient = sg
	sm.color_ramp = sgt
	s.process_material = sm
	var sq := QuadMesh.new()
	sq.size = Vector2(0.8, 0.8)
	sq.material = TexKit.smoke_material()
	s.draw_pass_1 = sq
	s.position = Vector3(0, 1.0, 0)
	root.add_child(s)
	return root


## A low-poly person (hoodie, trousers, trainers): rounded head with a face, limbs with joints.
## Origin at the feet, facing -Z.
func _person(top: Color, legs: Color, skin: Color, hood: bool) -> Node3D:
	var root := Node3D.new()
	var st := MeshKit.new_st()
	var limb := func(a: Vector3, b: Vector3, r0: float, r1: float, col: Color) -> void:
		MeshKit.tube(st, [a, b], [r0, r1], 10, Vector2(1, 1), col, false)
		_sphere_into(st, a, r0, col)
		_sphere_into(st, b, r1, col)
	# legs (slightly apart), trainers
	for s in [-1.0, 1.0]:
		limb.call(Vector3(s * 0.1, 0.92, 0.0), Vector3(s * 0.11, 0.5, -0.02), 0.085, 0.07, legs)
		limb.call(Vector3(s * 0.11, 0.5, -0.02), Vector3(s * 0.11, 0.1, 0.02), 0.068, 0.055, legs)
		MeshKit.box(st, Transform3D(Basis.IDENTITY, Vector3(s * 0.11, 0.05, -0.05)), Vector3(0.12, 0.1, 0.28), Color(0.92, 0.92, 0.9))
	# torso: tapered, hoodie pocket
	MeshKit.tube(st, [Vector3(0, 0.9, 0), Vector3(0, 1.2, 0), Vector3(0, 1.45, 0)], [0.16, 0.19, 0.2], 12, Vector2(1, 1), top, false)
	_sphere_into(st, Vector3(0, 1.45, 0), 0.2, top, Vector3(1.15, 0.55, 0.8))
	MeshKit.box(st, Transform3D(Basis.IDENTITY, Vector3(0, 1.05, -0.155)), Vector3(0.24, 0.12, 0.03), top * 0.85)
	# arms: hands in the pockets / hanging, a bit bent
	for s in [-1.0, 1.0]:
		limb.call(Vector3(s * 0.23, 1.42, 0.0), Vector3(s * 0.28, 1.17, -0.04), 0.06, 0.055, top)
		limb.call(Vector3(s * 0.28, 1.17, -0.04), Vector3(s * 0.2, 1.0, -0.14), 0.052, 0.045, top)
		_sphere_into(st, Vector3(s * 0.18, 0.97, -0.16), 0.042, skin)
	# neck, head with ears, eyes, brows, hair
	limb.call(Vector3(0, 1.5, 0.0), Vector3(0, 1.58, -0.01), 0.05, 0.05, skin)
	var hc := Vector3(0, 1.7, -0.01)
	_sphere_into(st, hc, 0.115, skin, Vector3(0.92, 1.05, 1.0))
	for s in [-1.0, 1.0]:
		_sphere_into(st, hc + Vector3(s * 0.105, 0.0, 0.01), 0.025, skin * 0.95)
		MeshKit.box(st, Transform3D(Basis.IDENTITY, hc + Vector3(s * 0.04, 0.02, -0.105)), Vector3(0.028, 0.014, 0.01), Color(0.05, 0.04, 0.04))
		MeshKit.box(st, Transform3D(Basis.from_euler(Vector3(0, 0, s * -0.15)), hc + Vector3(s * 0.042, 0.05, -0.103)), Vector3(0.04, 0.01, 0.01), Color(0.1, 0.07, 0.05))
	MeshKit.box(st, Transform3D(Basis.IDENTITY, hc + Vector3(0, -0.05, -0.107)), Vector3(0.04, 0.008, 0.008), skin * 0.6)
	_sphere_into(st, hc + Vector3(0, 0.05, 0.02), 0.11, Color(0.06, 0.05, 0.04), Vector3(0.95, 0.75, 0.95))
	if hood:
		# hood down over the shoulders, strings
		_sphere_into(st, Vector3(0, 1.52, 0.1), 0.15, top * 0.9, Vector3(1.3, 0.7, 1.0))
		for s in [-1.0, 1.0]:
			MeshKit.box(st, Transform3D(Basis.IDENTITY, Vector3(s * 0.05, 1.33, -0.19)), Vector3(0.012, 0.14, 0.012), Color(0.9, 0.9, 0.88))
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.85
	root.add_child(MeshKit.mesh_instance(MeshKit.commit(st, m)))
	return root


func _sphere_into(st: SurfaceTool, c: Vector3, r: float, col: Color, sc := Vector3.ONE) -> void:
	var rings := 6
	var seg := 10
	for i in rings:
		var a0 := PI * i / rings - PI * 0.5
		var a1 := PI * (i + 1) / rings - PI * 0.5
		for j in seg:
			var b0 := TAU * j / seg
			var b1 := TAU * (j + 1) / seg
			var n00 := Vector3(cos(a0) * cos(b0), sin(a0), cos(a0) * sin(b0))
			var n01 := Vector3(cos(a0) * cos(b1), sin(a0), cos(a0) * sin(b1))
			var n11 := Vector3(cos(a1) * cos(b1), sin(a1), cos(a1) * sin(b1))
			var n10 := Vector3(cos(a1) * cos(b0), sin(a1), cos(a1) * sin(b0))
			MeshKit.quad(st, c + n00 * r * sc, c + n01 * r * sc, c + n11 * r * sc, c + n10 * r * sc, (n00 + n11).normalized(),
				Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, col)


# ---------------------------------------------------------------------------
# Along the route
# ---------------------------------------------------------------------------
## A dark figure at the edge of the woods – only visible while the lightning flashes.
func _build_figure() -> void:
	var i: int = track.index_at(FIGURE_P)
	var away: Vector3 = track.rights[i] * FIGURE_SIDE
	var off: float = track.off_right[i] if FIGURE_SIDE > 0.0 else track.off_left[i]
	var p: Vector3 = track.samples[i] + away * (off + 14.0)
	p.y = terrain.height_at(p.x, p.z)
	figure = _person(Color(0.02, 0.02, 0.02), Color(0.02, 0.02, 0.02), Color(0.03, 0.03, 0.03), true)
	figure.scale = Vector3(1.15, 1.2, 1.15)
	add_child(figure)
	figure.global_transform = Transform3D(Basis.looking_at(-away, Vector3.UP).scaled(Vector3(1.15, 1.2, 1.15)), p)
	var eye_m := StandardMaterial3D.new()
	eye_m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	eye_m.albedo_color = Color(1.0, 0.2, 0.1)
	for s: float in [-1.0, 1.0]:
		figure.add_child(MeshKit.sphere_node(0.02, eye_m, Vector3(s * 0.06, 1.64, -0.13)))
	figure.visible = false
	scenery.occupy(p, 2.0)


## The Schwedenkreuz: an old stone cross by the road with a red grave lantern.
func _build_cross() -> void:
	var i: int = track.index_at(CROSS_P)
	var away: Vector3 = track.rights[i] * CROSS_SIDE
	var off: float = track.off_right[i] if CROSS_SIDE > 0.0 else track.off_left[i]
	var p: Vector3 = track.samples[i] + away * (off + 3.5)
	p.y = terrain.height_at(p.x, p.z)
	var root := Node3D.new()
	root.name = "Schwedenkreuz"
	add_child(root)
	root.global_transform = Transform3D(Basis.looking_at(-away, Vector3.UP), p)
	var stone := TexKit.rock_material()
	root.add_child(MeshKit.box_node(Vector3(0.9, 0.4, 0.6), stone, Vector3(0, 0.2, 0)))
	root.add_child(MeshKit.box_node(Vector3(0.28, 2.1, 0.22), stone, Vector3(0, 1.4, 0)))
	root.add_child(MeshKit.box_node(Vector3(1.1, 0.24, 0.22), stone, Vector3(0, 1.95, 0)))
	var lm := StandardMaterial3D.new()
	lm.albedo_color = Color(0.8, 0.1, 0.05, 0.8)
	lm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	lm.emission_enabled = true
	lm.emission = Color(1.0, 0.2, 0.05)
	lm.emission_energy_multiplier = 2.0
	root.add_child(MeshKit.cyl_node(0.06, 0.07, 0.2, lm, Vector3(0.3, 0.5, -0.2)))
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.3, 0.1)
	l.omni_range = 3.5
	l.light_energy = 0.7
	l.position = Vector3(0.3, 0.6, -0.4)
	root.add_child(l)
	scenery.occupy(p, 2.5)


# ---------------------------------------------------------------------------
# Helpers for the cutscene
# ---------------------------------------------------------------------------
## World transform of a camera at local `eye` looking at local `target`.
func cam_xf(eye: Vector3, target: Vector3) -> Transform3D:
	var e := house_xf * eye
	var t := house_xf * target
	return Transform3D(Basis.looking_at((t - e).normalized(), Vector3.UP), e)


func to_world(local: Vector3) -> Vector3:
	return house_xf * local


## Is p on the gravel track (for the tyre grip)?
func on_track_path(p: Vector3) -> bool:
	for k in range(0, path_pts.size(), 2):
		var q: Vector3 = path_pts[k]
		if Vector2(p.x - q.x, p.z - q.z).length_squared() < 9.0:
			return true
	return Vector2(p.x - camp.x, p.z - camp.z).length() < 13.0

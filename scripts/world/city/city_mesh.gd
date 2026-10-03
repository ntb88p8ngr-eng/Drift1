extends RefCounted
## Collects the city's static geometry per 96 m chunk and material, then builds one mesh per chunk and
## material (thousands of buildings in a few hundred draw calls). Materials:
##   frame  – walls, mullions, slabs, roofs, props (vertex colours, a little grime)
##   metal  – railings, poles, frames (vertex colours, metallic)
##   glass  – windows: dark mirror-like glass; at night a share of the windows lit, each its own room
##   sign   – boards with their front in a cell of the sign atlas (city_atlas.gd), glowing at night
##   glow   – lamps, neon tubes, shop interiors (vertex colour as emission, brighter at night)
##   road   – asphalt (the race track's own road material: same wetness, puddles and night)
##   line   – road markings

const MeshKit = preload("res://scripts/util/mesh_kit.gd")
const TexKit = preload("res://scripts/util/tex_kit.gd")
const CityAtlas = preload("res://scripts/world/city/city_atlas.gd")

const CHUNK := 96.0

const GLASS_SHADER := """
shader_type spatial;
render_mode diffuse_burley;

uniform float night = 0.0;
uniform vec3 sky_top : source_color = vec3(0.33, 0.52, 0.85);
uniform vec3 sky_horizon : source_color = vec3(0.8, 0.86, 0.93);
uniform vec3 city : source_color = vec3(0.2, 0.21, 0.24);
// flat: the building's codes are the same at every corner of a pane – interpolated, they wobbled
// by a hair from pixel to pixel, and the hash below turned that into a different window state
// for every pixel (black and white noise crawling over the facades)
varying flat vec4 vcol;

// hash without sin(): stable for the large cell numbers along a facade
float h(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void vertex() {
	vcol = COLOR;
}

void fragment() {
	// UV = metres along the facade / above the ground; COLOR: r = building seed, g = share of lit
	// windows, b = bay width code, a = style (0 office glass, 1 homes)
	float bay = 2.4 + vcol.b * 2.5;
	vec2 g = UV / vec2(bay, 3.6);
	vec2 cell = floor(g);
	vec2 f = fract(g);
	// windows only a few pixels big: fade the per-window detail to its average (no sparkling)
	vec2 fw = fwidth(g);
	float detail = 1.0 - smoothstep(0.12, 0.45, max(fw.x, fw.y));
	float seed = floor(vcol.r * 255.0 + 0.5) * 0.7;
	float r = h(cell + seed);
	// lit rooms: the building's share at night, fewer by day (offices with the lights on)
	float share = mix(vcol.g * 0.35, vcol.g, night);
	float lit = mix(share, step(1.0 - share, r), detail);
	vec3 room = mix(vec3(1.0, 0.84, 0.58), vec3(0.82, 0.92, 1.0), mix(0.5, h(cell * 1.7 + seed), detail));
	room = mix(room, vec3(1.0, 0.6, 0.35), step(0.93, h(cell * 3.1 + seed)) * vcol.a * detail);
	float blind = mix(0.25, step(f.y, 0.25 + 0.6 * h(cell + seed + 7.0)) * step(0.5, h(cell + seed + 2.0)), detail);
	// the window frames, antialiased
	float edge = 0.04 + fw.x * 1.2;
	float frame = (1.0 - smoothstep(0.04, edge, f.x) + smoothstep(1.0 - edge, 0.96, f.x)) * detail + 0.08 * (1.0 - detail);
	frame = clamp(frame, 0.0, 1.0);
	vec3 tint = mix(vec3(0.07, 0.11, 0.15), vec3(0.11, 0.1, 0.08), vcol.a);
	tint *= 0.75 + 0.5 * h(vec2(seed, 3.0));
	// a steady reflection of the sky and the skyline (no screen-space tricks): every pane sits a
	// little differently in its frame, so the facade shimmers as you drive past
	vec3 n = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 v = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	vec3 rf = reflect(-v, n);
	rf.y += (h(cell * 1.9 + seed) - 0.5) * 0.14 * detail;
	rf.x += (h(cell * 2.7 + seed) - 0.5) * 0.08 * detail;
	rf = normalize(rf);
	vec3 env = rf.y > 0.0 ? mix(sky_horizon, sky_top, smoothstep(0.0, 0.55, rf.y))
		: mix(sky_horizon * 0.5, city, smoothstep(0.0, -0.2, rf.y));
	float az = atan(rf.x, rf.z);
	float towers = step(rf.y, 0.05 + 0.12 * h(vec2(floor(az * 14.0), 3.0)));
	env = mix(env, city * 1.4, towers * step(0.0, rf.y));
	float fres = 0.1 + 0.9 * pow(1.0 - clamp(dot(n, v), 0.0, 1.0), 4.0);
	ALBEDO = mix(tint * 0.5, vec3(0.05), frame);
	METALLIC = 0.0;
	ROUGHNESS = mix(0.16, 0.5, frame);
	SPECULAR = 0.6;
	float on = lit * (1.0 - frame) * mix(1.0, 0.55, blind);
	EMISSION = env * fres * (1.0 - frame) * mix(0.9, 0.22, night)
		+ room * on * mix(0.55, 2.4, night) * (0.6 + 0.4 * r);
}
"""

const FRAME_SHADER := """
shader_type spatial;
render_mode diffuse_burley;

uniform sampler2D grime : filter_linear_mipmap, repeat_enable;
varying vec3 wpos;
varying vec4 vcol;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vcol = COLOR;
}

void fragment() {
	vec3 n = abs(normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz));
	float g = texture(grime, wpos.xz * 0.11).r * n.y + texture(grime, wpos.xy * 0.11).r * n.z + texture(grime, wpos.zy * 0.11).r * n.x;
	// darker streaks down the walls
	float streak = texture(grime, vec2((wpos.x + wpos.z) * 0.6, wpos.y * 0.03)).r;
	vec3 c = vcol.rgb * (0.82 + 0.3 * g) * mix(1.0, 0.86, smoothstep(0.55, 0.8, streak) * (1.0 - n.y));
	ALBEDO = c;
	float metal = clamp((1.0 - vcol.a) * 2.0, 0.0, 1.0);
	METALLIC = metal * 0.85;
	ROUGHNESS = mix(0.82, 0.3, metal);
}
"""

const GLOW_SHADER := """
shader_type spatial;

uniform float night = 0.0;
varying vec4 vcol;

void vertex() {
	vcol = COLOR;
}

void fragment() {
	ALBEDO = vcol.rgb * 0.5;
	// alpha = how much it glows in daylight (neon signs and shop windows clearly, lamp glass a little)
	EMISSION = vcol.rgb * mix(vcol.a * 2.6 + 0.08, 3.2, night);
	ROUGHNESS = 0.3;
}
"""

var chunks := {}          # Vector2i -> {layer name: Buf}
var mats := {}
var road_material: Material
var stats := {}
## While set, geometry goes to the detail layer of its material: small parts (balconies, AC units,
## sills, rails) that are only drawn up close and cast no shadows.
var detail := false
## While set: (x, z) -> ground height. Road and markings are lifted onto the ground (near the race
## route the ground rises to the road's height).
var ground := Callable()

## One chunk's geometry of one material, as plain arrays (non-indexed triangles).
class Buf:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var uv := PackedVector2Array()

## Paint on the road: drawn a hair towards the camera (0.15 % of the distance), so the markings never
## flicker against the asphalt, the junction plates or each other, near or far.
const LINE_SHADER := """
shader_type spatial;
render_mode cull_disabled;
varying vec4 vc;
void vertex() {
	vc = COLOR;
	vec4 vp = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vp.xyz *= 0.9985;
	POSITION = PROJECTION_MATRIX * vp;
}
void fragment() {
	ALBEDO = vc.rgb;
	ROUGHNESS = 0.6;
}
"""

# a unit box (corners at ±0.5) as 36 vertices with normals; the mirrored variant for bases with a
# negative determinant (winding reversed)
static var _box_v: PackedVector3Array
static var _box_n: PackedVector3Array
static var _box_v_flip: PackedVector3Array
static var _box_uv: PackedVector2Array
var _cols := PackedColorArray()
var _cols_of := Color(-1, -1, -1, -1)


func _init(p_road_material: Material) -> void:
	road_material = p_road_material
	var g := ShaderMaterial.new()
	g.shader = Shader.new()
	g.shader.code = GLASS_SHADER
	mats["glass"] = g
	var f := ShaderMaterial.new()
	f.shader = Shader.new()
	f.shader.code = FRAME_SHADER
	f.set_shader_parameter("grime", TexKit.noise_texture(611, 0.06, false, 256))
	mats["frame"] = f
	mats["metal"] = f
	var gl := ShaderMaterial.new()
	gl.shader = Shader.new()
	gl.shader.code = GLOW_SHADER
	mats["glow"] = gl
	mats["sign"] = CityAtlas.material()
	var line := ShaderMaterial.new()
	line.shader = Shader.new()
	line.shader.code = LINE_SHADER
	mats["line"] = line
	mats["road"] = road_material
	if _box_v.is_empty():
		_make_unit_box()


static func _make_unit_box() -> void:
	var c := [Vector3(-0.5, -0.5, -0.5), Vector3(0.5, -0.5, -0.5), Vector3(0.5, 0.5, -0.5), Vector3(-0.5, 0.5, -0.5),
		Vector3(-0.5, -0.5, 0.5), Vector3(0.5, -0.5, 0.5), Vector3(0.5, 0.5, 0.5), Vector3(-0.5, 0.5, 0.5)]
	var faces := [[0, 1, 2, 3, Vector3(0, 0, -1)], [5, 4, 7, 6, Vector3(0, 0, 1)], [4, 0, 3, 7, Vector3(-1, 0, 0)],
		[1, 5, 6, 2, Vector3(1, 0, 0)], [3, 2, 6, 7, Vector3(0, 1, 0)], [4, 5, 1, 0, Vector3(0, -1, 0)]]
	for f in faces:
		var q: Array = [c[f[0]], c[f[1]], c[f[2]], c[f[3]]]
		var nrm: Vector3 = f[4]
		for t in [[0, 1, 2], [0, 2, 3]]:
			var a: Vector3 = q[t[0]]
			var b: Vector3 = q[t[1]]
			var cc: Vector3 = q[t[2]]
			if (b - a).cross(cc - a).dot(nrm) > 0.0:
				var tv := b
				b = cc
				cc = tv
			_box_v.append_array([a, b, cc])
			_box_v_flip.append_array([a, cc, b])
			_box_n.append_array([nrm, nrm, nrm])
	_box_uv.resize(36)


func set_night(n: float) -> void:
	(mats["glass"] as ShaderMaterial).set_shader_parameter("night", n)
	(mats["glow"] as ShaderMaterial).set_shader_parameter("night", n)
	(mats["sign"] as ShaderMaterial).set_shader_parameter("glow", lerpf(1.0, 2.4, n))
	var g := mats["glass"] as ShaderMaterial
	g.set_shader_parameter("sky_top", Color(0.33, 0.52, 0.85).lerp(Color(0.02, 0.03, 0.07), n))
	g.set_shader_parameter("sky_horizon", Color(0.8, 0.86, 0.93).lerp(Color(0.1, 0.08, 0.14), n))
	g.set_shader_parameter("city", Color(0.2, 0.21, 0.24).lerp(Color(0.05, 0.04, 0.06), n))


func buf(mat: String, p: Vector3) -> Buf:
	var key := Vector2i(int(floor(p.x / CHUNK)), int(floor(p.z / CHUNK)))
	var c: Dictionary = chunks.get(key, {})
	if c.is_empty():
		chunks[key] = c
	var layer := mat + "_d" if detail and mat != "glass" and mat != "sign" else mat
	var b: Buf = c.get(layer)
	if b == null:
		b = Buf.new()
		c[layer] = b
	return b


func box(mat: String, xf: Transform3D, size: Vector3, col: Color) -> void:
	var b := buf(mat, xf.origin)
	var m := Transform3D(xf.basis * Basis.from_scale(size), xf.origin)
	b.v.append_array(m * (_box_v_flip if m.basis.determinant() < 0.0 else _box_v))
	b.n.append_array(Transform3D(xf.basis.orthonormalized(), Vector3.ZERO) * _box_n)
	if col != _cols_of:
		_cols_of = col
		_cols.resize(36)
		_cols.fill(col)
	b.c.append_array(_cols)
	b.uv.append_array(_box_uv)


func _tri(b: Buf, a: Vector3, p1: Vector3, p2: Vector3, n: Vector3, col: Color, ua: Vector2, u1: Vector2, u2: Vector2) -> void:
	if (p1 - a).cross(p2 - a).dot(n) > 0.0:
		b.v.append(a)
		b.v.append(p2)
		b.v.append(p1)
		b.uv.append(ua)
		b.uv.append(u2)
		b.uv.append(u1)
	else:
		b.v.append(a)
		b.v.append(p1)
		b.v.append(p2)
		b.uv.append(ua)
		b.uv.append(u1)
		b.uv.append(u2)
	b.n.append(n)
	b.n.append(n)
	b.n.append(n)
	b.c.append(col)
	b.c.append(col)
	b.c.append(col)


func quad(mat: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, col: Color,
		uva := Vector2(0, 0), uvb := Vector2(1, 0), uvc := Vector2(1, 1), uvd := Vector2(0, 1)) -> void:
	var bf := buf(mat, (a + c) * 0.5)
	var nn := n.normalized()
	if ground.is_valid() and (mat == "road" or mat == "line"):
		a.y += float(ground.call(a.x, a.z))
		b.y += float(ground.call(b.x, b.z))
		c.y += float(ground.call(c.x, c.z))
		d.y += float(ground.call(d.x, d.z))
	_tri(bf, a, b, c, nn, col, uva, uvb, uvc)
	_tri(bf, a, c, d, nn, col, uva, uvc, uvd)


func tri(mat: String, a: Vector3, b: Vector3, c: Vector3, n: Vector3, col: Color) -> void:
	if ground.is_valid() and (mat == "road" or mat == "line"):
		a.y += float(ground.call(a.x, a.z))
		b.y += float(ground.call(b.x, b.z))
		c.y += float(ground.call(c.x, c.z))
	_tri(buf(mat, (a + b + c) / 3.0), a, b, c, n.normalized(), col, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)


## An upright cylinder (with a top cap) standing on `base`.
func cyl(mat: String, base: Vector3, r: float, hgt: float, col: Color, seg := 12) -> void:
	var bf := buf(mat, base)
	var top := Vector3(0, hgt, 0)
	for k in seg:
		var a0 := TAU * k / seg
		var a1 := TAU * (k + 1) / seg
		var p0 := base + Vector3(cos(a0) * r, 0, sin(a0) * r)
		var p1 := base + Vector3(cos(a1) * r, 0, sin(a1) * r)
		var n := Vector3(cos((a0 + a1) * 0.5), 0, sin((a0 + a1) * 0.5))
		_tri(bf, p0, p1, p1 + top, n, col, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
		_tri(bf, p0, p1 + top, p0 + top, n, col, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
		_tri(bf, base + top, p0 + top, p1 + top, Vector3.UP, col, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)


## A board of `size`; its +Z face shows the atlas cell `rect` (the -Z face too, mirrored correctly,
## when `both`), the rim plain. lit: how much the board glows at night (1 = neon / backlit).
func sign_box(xf: Transform3D, size: Vector3, rect: Rect2, lit := 1.0, both := false, rim := Color(0.12, 0.12, 0.13)) -> void:
	var s := buf("sign", xf.origin)
	var h := size * 0.5
	var col := Color(lit, 0, 0, 1)
	var b := xf.basis
	var o := xf.origin
	var u0 := rect.position.x
	var u1 := rect.end.x
	var v0 := rect.position.y
	var v1 := rect.end.y
	var nz := (b.z).normalized()
	var f0 := o + b * Vector3(-h.x, -h.y, h.z)
	var f1 := o + b * Vector3(h.x, -h.y, h.z)
	var f2 := o + b * Vector3(h.x, h.y, h.z)
	var f3 := o + b * Vector3(-h.x, h.y, h.z)
	_tri(s, f0, f1, f2, nz, col, Vector2(u0, v1), Vector2(u1, v1), Vector2(u1, v0))
	_tri(s, f0, f2, f3, nz, col, Vector2(u0, v1), Vector2(u1, v0), Vector2(u0, v0))
	var back := rect if both else CityAtlas.misc(0)
	var bu0 := back.position.x
	var bu1 := back.end.x
	var bv0 := back.position.y
	var bv1 := back.end.y
	var g0 := o + b * Vector3(h.x, -h.y, -h.z)
	var g1 := o + b * Vector3(-h.x, -h.y, -h.z)
	var g2 := o + b * Vector3(-h.x, h.y, -h.z)
	var g3 := o + b * Vector3(h.x, h.y, -h.z)
	_tri(s, g0, g1, g2, -nz, col, Vector2(bu0, bv1), Vector2(bu1, bv1), Vector2(bu1, bv0))
	_tri(s, g0, g2, g3, -nz, col, Vector2(bu0, bv1), Vector2(bu1, bv0), Vector2(bu0, bv0))
	# rim (frame material)
	box("frame", Transform3D(b, o + b * Vector3(0, h.y + 0.04, 0)), Vector3(size.x + 0.08, 0.08, size.z + 0.04), rim)
	box("frame", Transform3D(b, o + b * Vector3(0, -h.y - 0.04, 0)), Vector3(size.x + 0.08, 0.08, size.z + 0.04), rim)
	box("frame", Transform3D(b, o + b * Vector3(h.x + 0.04, 0, 0)), Vector3(0.08, size.y, size.z + 0.04), rim)
	box("frame", Transform3D(b, o + b * Vector3(-h.x - 0.04, 0, 0)), Vector3(0.08, size.y, size.z + 0.04), rim)
	stats["signs"] = int(stats.get("signs", 0)) + 1


## A flat glowing panel (lamp glass, neon strip, lit shop interior) facing +Z of xf.
func glow_box(xf: Transform3D, size: Vector3, col: Color, day := 0.2) -> void:
	box("glow", xf, size, Color(col.r, col.g, col.b, day))


## Builds the meshes under `parent`. ranges: layer -> visibility range end (m); a detail layer
## ("frame_d") without an entry gets DETAIL_RANGE.
const DETAIL_RANGE := 240.0

func commit(parent: Node3D, ranges: Dictionary) -> void:
	for key in chunks:
		var c: Dictionary = chunks[key]
		for layer: String in c:
			var b: Buf = c[layer]
			if b.v.is_empty():
				continue
			var is_detail := layer.ends_with("_d")
			var mat := layer.trim_suffix("_d")
			# the mesh sits at its chunk's centre (visibility ranges are measured from a node's
			# position: with every chunk at the world origin, half the city vanished)
			var centre := Vector3((key.x + 0.5) * CHUNK, 0.0, (key.y + 0.5) * CHUNK)
			var arr := []
			arr.resize(Mesh.ARRAY_MAX)
			arr[Mesh.ARRAY_VERTEX] = Transform3D(Basis.IDENTITY, -centre) * b.v
			arr[Mesh.ARRAY_NORMAL] = b.n
			arr[Mesh.ARRAY_COLOR] = b.c
			# only glass (metres along the facade), signs (atlas) and the road read UVs
			if mat == "glass" or mat == "sign" or mat == "road":
				arr[Mesh.ARRAY_TEX_UV] = b.uv
			var mesh: ArrayMesh
			if mat == "road":
				var st := SurfaceTool.new()
				st.create_from_arrays(arr)
				st.generate_tangents()
				mesh = st.commit()
			else:
				# 16 bit positions within the chunk's bounds: half the memory, millimetre precision
				mesh = ArrayMesh.new()
				mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES)
			mesh.surface_set_material(0, mats[mat])
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			mi.position = centre
			mi.name = "City_%s_%d_%d" % [layer, key.x, key.y]
			var reach: float = float(ranges.get(layer, DETAIL_RANGE if is_detail else 600.0))
			mi.visibility_range_end = reach + CHUNK * 0.75
			mi.visibility_range_end_margin = 30.0
			mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			var shadows: bool = not is_detail and (mat == "frame" or mat == "metal" or mat == "glass")
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			parent.add_child(mi)
			stats["meshes"] = int(stats.get("meshes", 0)) + 1
			stats["tris_" + layer] = int(stats.get("tris_" + layer, 0)) + b.v.size() / 3
	chunks.clear()

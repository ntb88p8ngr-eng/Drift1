extends Node3D
## Grass that exists only near the camera. A grid of grass clumps (MultiMesh) follows the camera;
## the vertex shader moves every clump onto the terrain (height map texture), picks its type, size
## and colour from world-space hashes and a density map (no grass on the road, concrete, gravel or
## rock, thinner in the forest, tall grass and flowers in meadows), sways it in the wind and bends it
## away from the car. Two rings: dense near the camera, sparser further out, fading at the edge.

const Terrain = preload("res://scripts/world/terrain.gd")
const TexKit = preload("res://scripts/util/tex_kit.gd")

const GRASS_SHADER := """
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx, shadows_disabled;

uniform sampler2D height_tex : filter_nearest, repeat_disable;
uniform sampler2D mask_tex : filter_linear, repeat_disable;     // r density, g tall, b flowers, a dry
uniform sampler2D road_tex : filter_linear, repeat_disable;     // distance to the road edge (0..8 m)
uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec2 map_origin = vec2(0.0);
uniform float map_cell = 4.0;
uniform ivec2 map_size = ivec2(2, 2);
uniform vec2 road_origin = vec2(0.0);
uniform vec2 road_inv_size = vec2(0.001);
uniform float spacing = 0.5;
uniform vec3 cam_pos = vec3(0.0);
uniform vec3 car_pos = vec3(0.0, -1000.0, 0.0);
uniform float fade_start = 18.0;
uniform float fade_end = 24.0;
uniform float inner_start = 0.0;
uniform float inner_end = 0.0;
uniform float wind = 1.0;
uniform float wetness = 0.0;
uniform float road_clear = 1.4;
uniform float trap_w = 4.6;
uniform vec3 color_a : source_color = vec3(0.12, 0.32, 0.06);
uniform vec3 color_b : source_color = vec3(0.22, 0.46, 0.1);
uniform vec3 color_dry : source_color = vec3(0.38, 0.42, 0.18);

varying vec3 g_col;
varying float g_tip;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

// wavy outer border of the gravel shoulder (identical in TexKit.TERRAIN_SHADER)
float shoulder_w(vec2 p) {
	return 1.8 + 0.28 * sin(p.x * 0.53 + p.y * 0.21) + 0.2 * sin(p.y * 1.37 - p.x * 0.83) + 0.1 * sin(p.x * 3.1 + p.y * 2.3);
}

float height_at(vec2 p) {
	vec2 g = (p - map_origin) / map_cell;
	ivec2 i0 = clamp(ivec2(floor(g)), ivec2(0), map_size - 2);
	vec2 f = clamp(g - vec2(i0), 0.0, 1.0);
	float h00 = texelFetch(height_tex, i0, 0).r;
	float h10 = texelFetch(height_tex, i0 + ivec2(1, 0), 0).r;
	float h01 = texelFetch(height_tex, i0 + ivec2(0, 1), 0).r;
	float h11 = texelFetch(height_tex, i0 + ivec2(1, 1), 0).r;
	if (f.x >= f.y) {
		return h00 + (h10 - h00) * f.x + (h11 - h10) * f.y;
	}
	return h00 + (h11 - h01) * f.x + (h01 - h00) * f.y;
}

void vertex() {
	vec3 base = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec2 cell = floor(base.xz / spacing + 0.5) * spacing;
	float r1 = hash(cell);
	float r2 = hash(cell + 17.13);
	float r3 = hash(cell + 41.7);
	float r4 = hash(cell + 73.1);
	vec2 p = cell + (vec2(r1, r2) - 0.5) * spacing * 0.95;
	vec2 muv = (p - map_origin) / (map_cell * vec2(map_size - 1));
	vec4 mask = texture(mask_tex, muv);
	vec2 edge = texture(road_tex, (p - road_origin) * road_inv_size).rg;
	float road = edge.r * 8.0;
	// the gravel shoulder and the gravel traps have no grass (same wavy border as the terrain shader)
	float sh = shoulder_w(p);
	float clear_to = max(road_clear, sh);
	if (edge.g > 0.3) {
		clear_to = max(clear_to, mix(sh, trap_w + 0.3 * sin(p.x * 0.37 + p.y * 0.51), smoothstep(0.3, 0.6, edge.g)));
	}
	float dist = length(p - cam_pos.xz);
	float fade = 1.0 - smoothstep(fade_start, fade_end, dist);
	if (inner_end > 0.0) {
		fade *= smoothstep(inner_start, inner_end, dist);
	}
	float wn = texture(noise_tex, p * 0.03).r;
	float dens = mask.r * smoothstep(clear_to, clear_to + 0.35, road) * (0.75 + 0.7 * wn);
	// never on the asphalt: hard cut besides the smooth density falloff (a hash of exactly 0 used to
	// let single clumps through on the road)
	float keep = step(r3 + 0.002, dens) * fade * step(clear_to, road);
	float tall = mask.g * smoothstep(0.35, 0.7, texture(noise_tex, p * 0.09 + vec2(0.3)).r);
	float hgt = mix(0.16, 0.38, r4) * (1.0 + tall * 1.9) * mix(0.4, 1.0, smoothstep(0.0, 0.25, keep));
	float is_flower = COLOR.g;
	float flower_p = mask.b * smoothstep(0.55, 0.75, texture(noise_tex, p * 0.05 + vec2(0.7)).r);
	float show = keep;
	if (is_flower > 0.5 && hash(cell + 5.5) > flower_p) {
		show = 0.0;
	}
	vec3 v = VERTEX;
	float ang = r1 * 6.2831;
	float c = cos(ang);
	float s = sin(ang);
	v = vec3(v.x * c - v.z * s, v.y, v.x * s + v.z * c);
	v.y *= hgt;
	v.xz *= mix(0.8, 1.25, r2);
	float t = UV.y;
	// wind: slow gusts across the field plus flutter
	float gust = sin(TIME * 1.1 + p.x * 0.07 + p.y * 0.05) * 0.5 + 0.5;
	vec2 sway = vec2(sin(TIME * 1.9 + p.x * 0.4 + p.y * 0.3), cos(TIME * 1.6 + p.y * 0.35)) * (0.05 + 0.1 * gust) * wind;
	v.xz += sway * t * t * hgt * 2.0;
	// bend away from the car
	vec2 away = p - car_pos.xz;
	float cd = length(away);
	float push = (1.0 - smoothstep(1.2, 3.0, cd)) * step(abs(car_pos.y - base.y), 20.0);
	if (cd > 0.001) {
		v.xz += normalize(away) * push * t * hgt * 0.9;
	}
	v.y *= 1.0 - push * 0.6;
	float y = height_at(p) - 0.02;
	vec3 world = vec3(p.x, y, p.y) + v * show;
	VERTEX = world - base;
	NORMAL = normalize(vec3(0.0, 1.0, 0.0) + NORMAL * 0.35);
	// colour
	float dry = clamp(mask.a * smoothstep(0.45, 0.75, texture(noise_tex, p * 0.012).r) + r4 * 0.15, 0.0, 1.0);
	vec3 col = mix(color_a, color_b, clamp(r2 * 0.7 + wn * 0.5, 0.0, 1.0));
	col = mix(col, color_dry, dry * 0.85);
	col *= mix(0.4, 1.1, t) * mix(0.85, 1.12, r3);
	if (is_flower > 0.5) {
		float fc = hash(cell + 9.1);
		col = fc < 0.3 ? vec3(0.95, 0.95, 0.9) : (fc < 0.55 ? vec3(0.95, 0.8, 0.12) : (fc < 0.75 ? vec3(0.55, 0.3, 0.85) : (fc < 0.9 ? vec3(0.3, 0.45, 0.95) : vec3(0.95, 0.4, 0.55))));
	}
	g_col = col * (1.0 - wetness * 0.25);
	g_tip = t;
}

void fragment() {
	ALBEDO = g_col;
	ROUGHNESS = mix(0.75, 0.4, wetness);
	SPECULAR = 0.3;
	BACKLIGHT = g_col * 0.55 * g_tip;
	AO = mix(0.5, 1.0, g_tip);
	AO_LIGHT_AFFECT = 0.4;
}
"""

## [near spacing, near radius, far spacing, far radius] per quality level (0 = off)
const LEVELS := [[], [0.6, 18.0, 0.0, 0.0], [0.46, 22.0, 1.0, 44.0], [0.4, 24.0, 0.85, 56.0], [0.34, 27.0, 0.75, 68.0]]

var terrain
var track
var world
var _layers: Array = []   # [MultiMeshInstance3D, ShaderMaterial, spacing]
var _height_tex: ImageTexture
var _mask_tex: ImageTexture
var _road_tex: ImageTexture
var _road_origin := Vector2.ZERO
var _road_size := Vector2.ONE
var _level := -1
var wetness := 0.0
var wind := 1.0

static var _clumps := {}


func setup(p_terrain, p_track, p_world) -> void:
	terrain = p_terrain
	track = p_track
	world = p_world
	await _build_textures()
	_rebuild(int(Game.settings.get("grass_quality", 2)))
	Game.settings_changed.connect(_on_settings_changed)


func _on_settings_changed() -> void:
	var q := int(Game.settings.get("grass_quality", 2))
	if q != _level:
		_rebuild(q)


func _build_textures() -> void:
	_height_tex = ImageTexture.create_from_image(terrain.height_image())
	# density mask from the terrain ground types (one texel per terrain vertex)
	var nx: int = terrain.nx
	var nz: int = terrain.nz
	var bytes := PackedByteArray()
	bytes.resize(nx * nz * 4)
	bytes.fill(0)
	var big: bool = terrain.big
	# data tracks: grass only ever grows around the car, i.e. along the road (distance-field cells
	# looked up directly – a call per node would cost a second on 2.4 M nodes)
	var dist: PackedFloat32Array = terrain._dist
	var dn: Vector2i = terrain._dn
	var dk := float(Terrain.CELL) / float(Terrain.DIST_CELL)
	var d_off: Vector2 = (terrain.origin - terrain._dorigin) / Terrain.DIST_CELL
	for iz in nz:
		if iz % 16 == 0:
			await Game.load_tick(float(iz) / nz)
		var drow := mini(int(d_off.y + iz * dk), dn.y - 1) * dn.x
		for ix in nx:
			var k: int = iz * nx + ix
			if big and dist[drow + mini(int(d_off.x + ix * dk), dn.x - 1)] > 90.0:
				continue
			var sp: Color = terrain.splat[k]
			var n: Vector3 = terrain._vertex_normal(ix, iz)
			var dens := (1.0 - sp.r) * (1.0 - sp.g * 0.85) * (1.0 - sp.b * 0.6) * smoothstep(0.78, 0.9, n.y)
			var tall := sp.a * (1.0 - sp.b)
			var flowers := sp.a * 0.9
			var dry := clampf(sp.a * 0.8 + 0.2, 0.0, 1.0)
			bytes[k * 4] = int(clampf(dens, 0.0, 1.0) * 255.0)
			bytes[k * 4 + 1] = int(clampf(tall, 0.0, 1.0) * 255.0)
			bytes[k * 4 + 2] = int(clampf(flowers, 0.0, 1.0) * 255.0)
			bytes[k * 4 + 3] = int(clampf(dry, 0.0, 1.0) * 255.0)
	_mask_tex = ImageTexture.create_from_image(Image.create_from_data(nx, nz, false, Image.FORMAT_RGBA8, bytes))
	# distance to the road edge + gravel traps (shared with the terrain's gravel shoulder)
	var ed: Dictionary = track.edge_data()
	_road_tex = ed["tex"]
	_road_origin = ed["origin"]
	_road_size = Vector2(1.0 / ed["inv_size"].x, 1.0 / ed["inv_size"].y)


func _rebuild(level: int) -> void:
	_level = clampi(level, 0, LEVELS.size() - 1)
	for l in _layers:
		(l[0] as Node).queue_free()
	_layers.clear()
	var spec: Array = LEVELS[_level]
	if spec.is_empty():
		return
	var near_r: float = spec[1]
	_add_layer(spec[0], near_r, near_r - 4.0, near_r, 0.0, 0.0, 10)
	if float(spec[2]) > 0.0:
		_add_layer(spec[2], spec[3], float(spec[3]) - 10.0, spec[3], near_r - 4.0, near_r, 6)


func _add_layer(spacing: float, radius: float, fade0: float, fade1: float, inner0: float, inner1: float, blades: int) -> void:
	var count := int(ceil(radius / spacing))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = clump_mesh(blades)
	var xfs: Array = []
	for iz in range(-count, count + 1):
		for ix in range(-count, count + 1):
			var off := Vector2(ix * spacing, iz * spacing)
			var r := off.length()
			if r > radius + spacing or r < inner0 - spacing:
				continue
			xfs.append(Vector3(off.x, 0.0, off.y))
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, xfs[i]))
	var mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = GRASS_SHADER
	mat.shader = sh
	mat.set_shader_parameter("height_tex", _height_tex)
	mat.set_shader_parameter("mask_tex", _mask_tex)
	mat.set_shader_parameter("road_tex", _road_tex)
	mat.set_shader_parameter("noise_tex", TexKit.noise_texture(81, 0.02, false, 256))
	mat.set_shader_parameter("map_origin", terrain.origin)
	mat.set_shader_parameter("map_cell", Terrain.CELL)
	mat.set_shader_parameter("map_size", Vector2i(terrain.nx, terrain.nz))
	mat.set_shader_parameter("road_origin", _road_origin)
	mat.set_shader_parameter("trap_w", float(track.trap_w))
	mat.set_shader_parameter("road_inv_size", Vector2(1.0 / _road_size.x, 1.0 / _road_size.y))
	mat.set_shader_parameter("spacing", spacing)
	mat.set_shader_parameter("fade_start", fade0)
	mat.set_shader_parameter("fade_end", fade1)
	mat.set_shader_parameter("inner_start", inner0)
	mat.set_shader_parameter("inner_end", inner1)
	if track.track_id == "harbor":
		mat.set_shader_parameter("color_a", Color(0.14, 0.3, 0.07))
		mat.set_shader_parameter("color_b", Color(0.24, 0.42, 0.11))
		mat.set_shader_parameter("color_dry", Color(0.4, 0.42, 0.2))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Grass"
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(-radius - 2.0, -60.0, -radius - 2.0), Vector3(radius * 2.0 + 4.0, 200.0, radius * 2.0 + 4.0))
	mmi.top_level = true
	add_child(mmi)
	_layers.append([mmi, mat, spacing])


## One clump: curved, tapered blades and one flower on a stem (COLOR.g = 1 marks the flower).
## Fewer, wider blades for the outer ring.
static func clump_mesh(blades: int) -> ArrayMesh:
	if _clumps.has(blades):
		return _clumps[blades]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var widen := 10.0 / float(blades)
	for b in blades + 1:
		var flower := b == blades
		var a := rng.randf() * TAU
		var dir := Vector3(cos(a), 0, sin(a))
		var side := Vector3(-dir.z, 0, dir.x)
		var root := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)) * 0.16
		var lean := rng.randf_range(0.1, 0.4) if not flower else 0.08
		var h := rng.randf_range(0.6, 1.0) if not flower else 1.15
		var w := rng.randf_range(0.009, 0.016) * widen if not flower else 0.006
		var pts: Array = []
		for k in 4:
			var t := float(k) / 3.0
			pts.append(root + dir * lean * t * t * h + Vector3.UP * h * t)
		var col := Color(rng.randf(), 1.0 if flower else 0.0, float(b) / float(blades + 1))
		var nrm := dir.cross(Vector3.UP).cross(side).normalized()
		for k in 3:
			var t0 := float(k) / 3.0
			var t1 := float(k + 1) / 3.0
			var w0 := w * (1.0 - t0 * 0.85)
			var w1 := w * (1.0 - t1 * 0.85)
			var p0: Vector3 = pts[k]
			var p1: Vector3 = pts[k + 1]
			_blade_quad(st, p0 - side * w0, p0 + side * w0, p1 + side * w1, p1 - side * w1, nrm, t0, t1, col)
		if flower:
			# small star-shaped blossom made of two crossed quads
			var top: Vector3 = pts[3]
			var fcol := Color(col.r, 1.0, col.b)
			for q in 2:
				var ax := Vector3(1, 0, 0) if q == 0 else Vector3(0, 0, 1)
				var s := 0.05
				_blade_quad(st, top - ax * s + Vector3(0, -0.03, 0), top + ax * s + Vector3(0, -0.03, 0),
					top + ax * s + Vector3(0, 0.05, 0), top - ax * s + Vector3(0, 0.05, 0), Vector3.UP, 1.0, 1.0, fcol)
	var mesh := st.commit()
	_clumps[blades] = mesh
	return mesh


static func _blade_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, t0: float, t1: float, col: Color) -> void:
	for v in [[a, t0], [b, t0], [c, t1], [a, t0], [c, t1], [d, t1]]:
		st.set_color(col)
		st.set_normal(n)
		st.set_uv(Vector2(0.5, float(v[1])))
		st.add_vertex(v[0])


func _process(_delta: float) -> void:
	if _layers.is_empty():
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var cp := cam.global_position
	var car_p := Vector3(0, -1000, 0)
	if world and world.local_car:
		car_p = world.local_car.visual_transform().origin
	if world and world.atmosphere:
		wetness = world.atmosphere.wetness
		wind = 1.0 + float(world.atmosphere.rain) * 1.2
	for l in _layers:
		var mmi: MultiMeshInstance3D = l[0]
		var mat: ShaderMaterial = l[1]
		var sp: float = l[2]
		mmi.global_position = Vector3(floor(cp.x / sp) * sp, 0.0, floor(cp.z / sp) * sp)
		mat.set_shader_parameter("cam_pos", cp)
		mat.set_shader_parameter("car_pos", car_p)
		mat.set_shader_parameter("wetness", wetness)
		mat.set_shader_parameter("wind", wind)

extends Node3D
## Stormy night outside the menu garage: dark cloud sky with lightning (flashing clouds and a jagged
## bolt), a cold flash of light falling through the gate and the skylights (it also shows in the car
## paint), rain around the hall and wet asphalt outside the gate.
## setup_heavy(): for a garage with its own street outside and a photo panorama as sky – a
## cloudburst (dense rain, splashes on the ground), the panorama flashing with the lightning, the
## rain's roar and thunder rolling in a moment after each strike (its own volume: main-menu sounds).

const TexKit = preload("res://scripts/util/tex_kit.gd")
const Sfx = preload("res://scripts/util/sfx_kit.gd")

const SKY_SHADER := """
shader_type sky;

uniform float flash = 0.0;          // current lightning brightness
uniform float bolt = 0.0;           // visibility of the bolt itself
uniform vec3 flash_dir = vec3(0.3, 0.4, -0.8);
uniform float bolt_seed = 1.0;

float hash2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1.0, 0.0)), u.x), mix(hash2(i + vec2(0.0, 1.0)), hash2(i + vec2(1.0, 1.0)), u.x), u.y);
}
float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 6; i++) {
		v += a * vnoise(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}

float h1(float x, float s) { return fract(sin(x * 12.9898 + s * 78.233) * 43758.5453); }

// one row of high-rises around the horizon: returns colour (rgb) and coverage (a)
// n = buildings around the full circle, hmin/hmax = roof heights (tangent of the elevation),
// win_h = floor height (same unit)
vec4 city_layer(vec3 d, float n, float hmin, float hmax, float win_h, float seed, float flash_lit) {
	float e = d.y / max(length(d.xz), 1e-4);
	float x = (atan(d.z, d.x) / 6.2831853 + 0.5) * n;
	float cell = floor(x);
	float fx = fract(x);
	float r = h1(cell, seed);           // height
	float r2 = h1(cell, seed + 3.1);    // lot use / facade style
	float r3 = h1(cell, seed + 7.7);    // material
	float r4 = h1(cell, seed + 11.3);   // how many lights are on
	float r5 = h1(cell, seed + 17.9);   // roof
	// lots of different widths; some are empty
	float inset = 0.03 + 0.2 * h1(cell, seed + 23.0);
	if (r2 < 0.1 || fx < inset || fx > 1.0 - inset) {
		return vec4(0.0);
	}
	float u = (fx - inset) / (1.0 - 2.0 * inset);   // 0..1 across the facade
	float top = mix(hmin, hmax, pow(r, 2.2));
	// roofs: stepped crown, slanted top, or a spire on the tall ones
	if (r5 > 0.55 && r5 < 0.8 && abs(u - 0.5) > 0.3) {
		top *= 0.86;
	} else if (r5 >= 0.8) {
		top -= abs(u - 0.5) * (top - hmin) * 0.25;
	}
	bool spire = r > 0.72 && r5 < 0.3;
	if (e > top) {
		float ex = e - top;
		if (spire && abs(u - 0.5) < 0.03 && ex < (top - hmin) * 0.35) {
			float blink = step(0.5, fract(TIME * 0.5 + r * 7.0));
			float tip = step((top - hmin) * 0.33, ex);
			return vec4(mix(vec3(0.02), vec3(1.0, 0.08, 0.05) * 3.0 * blink, tip), 1.0);
		}
		// aviation light on flat roofs of tall buildings
		float tall = step(0.62, r) * step(0.3, r5);
		float blink2 = step(0.5, fract(TIME * 0.45 + r2 * 5.0));
		float dotl = exp(-(pow((u - 0.5) * 70.0, 2.0) + pow(ex / win_h * 2.2 - 0.6, 2.0)));
		return vec4(vec3(1.0, 0.08, 0.05) * 3.0, dotl * tall * blink2);
	}
	// facade material: concrete, blue glass, brick, dark stone
	vec3 body = r3 < 0.3 ? vec3(0.034, 0.034, 0.037) : (r3 < 0.6 ? vec3(0.018, 0.026, 0.04) : (r3 < 0.8 ? vec3(0.036, 0.026, 0.022) : vec3(0.014, 0.014, 0.016)));
	float grain = vnoise(vec2(u * 30.0 + cell, e / win_h * 0.7));
	vec3 col = body * (0.8 + 0.4 * grain) + vec3(0.35, 0.4, 0.55) * flash_lit * 0.05;
	// the edge towards the city glow is a bit lighter (gives the towers some volume)
	col *= 0.85 + 0.3 * smoothstep(0.0, 1.0, u);
	float style = floor(r2 * 4.0);
	float floor_i = floor(e / win_h);
	float fy = fract(e / win_h);
	float cols = floor(10.0 + r * 16.0);
	float cx = u * cols;
	float col_i = floor(cx);
	float fxw = fract(cx);
	// share of lit windows and their brightness: each building differs
	float lit_share = mix(0.08, 0.8, pow(r4, 1.4));
	float bright = mix(0.35, 1.25, h1(cell, seed + 29.0));
	float win = 0.0;
	float lit_hash = 0.0;
	if (style < 1.0) {
		// punched windows in a grid
		win = step(0.25, fxw) * step(fxw, 0.75) * step(0.3, fy) * step(fy, 0.75);
		lit_hash = h1(col_i + floor_i * 37.0 + cell * 911.0, seed + 1.3);
	} else if (style < 2.0) {
		// ribbon windows: bands along whole floors, lit in stretches
		win = step(0.35, fy) * step(fy, 0.72);
		lit_hash = h1(floor(cx / 4.0) + floor_i * 53.0 + cell * 577.0, seed + 2.9);
	} else if (style < 3.0) {
		// glass curtain wall: faint blue glow on the mullions, whole floors lit
		col += vec3(0.02, 0.035, 0.06) * step(0.9, fxw) * 0.6;
		win = step(0.12, fy) * step(fy, 0.9) * step(fxw, 0.88);
		lit_hash = h1(floor_i * 71.0 + cell * 313.0 + floor(cx / 6.0), seed + 4.1);
	} else {
		// residential: small windows further apart
		win = step(0.35, fract(cx * 0.5)) * step(fract(cx * 0.5), 0.6) * step(0.4, fy) * step(fy, 0.7);
		lit_hash = h1(floor(cx * 0.5) + floor_i * 41.0 + cell * 997.0, seed + 5.3);
	}
	float lit = step(1.0 - lit_share, lit_hash);
	// now and then a light switches on / off
	lit *= step(0.02, fract(lit_hash * 13.0 + floor(TIME * 0.05 + lit_hash * 4.0) * 0.37));
	float tone = h1(col_i * 3.0 + floor_i + cell, seed + 9.0);
	vec3 wc = tone < 0.5 ? vec3(1.0, 0.72, 0.4) : (tone < 0.82 ? vec3(0.85, 0.9, 1.0) : (tone < 0.93 ? vec3(0.5, 0.95, 0.9) : vec3(1.0, 0.5, 0.25)));
	col += wc * win * lit * bright * (0.55 + 0.45 * lit_hash);
	// dark, unlit windows still reflect a little
	col += vec3(0.02, 0.025, 0.035) * win * (1.0 - lit);
	// neon signs at the foot of some buildings
	if (h1(cell, seed + 31.0) > 0.82 && e < win_h * 1.7 && e > win_h * 0.7) {
		col += (h1(cell, seed + 37.0) > 0.5 ? vec3(0.9, 0.2, 0.7) : vec3(0.2, 0.8, 1.0)) * 0.55;
	}
	return vec4(col, 1.0);
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float h = d.y;
	vec3 fd = normalize(flash_dir);
	// night sky under a thick storm cover, orange city glow low on the horizon
	vec3 col = mix(vec3(0.03, 0.03, 0.038), vec3(0.008, 0.01, 0.018), pow(clamp(h, 0.0, 1.0), 0.45));
	col += vec3(0.1, 0.05, 0.025) * exp(-max(h, 0.0) * 14.0) * 0.6;
	float near_flash = pow(max(dot(d, fd), 0.0), 4.0);
	if (h > 0.0) {
		vec2 uv = d.xz / (h + 0.12);
		float t = TIME * 0.018;
		float n = fbm(uv * 0.55 + vec2(t, t * 0.35));
		float n2 = fbm(uv * 1.6 - vec2(t * 1.7, 0.0) + vec2(4.0, 1.0));
		float dens = smoothstep(0.3, 0.72, n);
		vec3 cloud = vec3(0.028, 0.03, 0.038) * (0.55 + 0.9 * n2);
		col = mix(col, cloud, dens * 0.92);
		// lightning inside the clouds: the whole sky brightens, the clouds around the strike glow
		col += vec3(0.5, 0.56, 0.8) * flash * (0.06 + near_flash * 1.6) * (0.35 + dens * 0.9 + n2 * 0.4);
		// the bolt: a jagged line from the cloud base down to the horizon near the strike direction
		if (bolt > 0.001 && dot(d, fd) > 0.8) {
			vec3 right = normalize(cross(fd, vec3(0.0, 1.0, 0.0)));
			vec3 upv = cross(right, fd);
			vec2 q = vec2(dot(d, right), dot(d, upv)) / dot(d, fd);
			float v = q.y;
			if (v < 0.08 && h > 0.0) {
				float x = (vnoise(vec2(v * 9.0, bolt_seed)) - 0.5) * 0.09 + (vnoise(vec2(v * 34.0, bolt_seed * 3.1)) - 0.5) * 0.025;
				float core = exp(-abs(q.x - x) / 0.0016);
				float halo = exp(-abs(q.x - x) / 0.02);
				// a side branch
				float bx = x + (0.08 - v) * 0.35 * sign(vnoise(vec2(bolt_seed, 7.0)) - 0.5);
				float branch = exp(-abs(q.x - bx) / 0.0012) * step(-0.12, v) * 0.6;
				col += vec3(0.85, 0.9, 1.0) * bolt * (core * 6.0 + branch * 4.0 + halo * 0.5);
			}
		}
	} else {
		// dark wet land below the horizon
		col = mix(col * 0.6, vec3(0.006, 0.007, 0.009), clamp(-h * 6.0, 0.0, 1.0)) + vec3(0.2, 0.22, 0.3) * flash * 0.04;
	}
	// the city on the horizon, a few kilometres away: three rows, the further ones hazier
	// (seen through the gate the view goes slightly down: the skyline starts well below the
	// horizon, so the opening shows towers from the street up, no empty land)
	if (h < 0.34 && h > -0.32) {
		vec3 dc = vec3(d.x, d.y + 0.26 * length(d.xz), d.z);
		vec3 haze = vec3(0.07, 0.05, 0.045);
		// back row: a closed wall of towers (no empty lots) so nothing shows between the rows
		// the dense city behind the rows: dark facades with a random scatter of lit windows
		float be = dc.y / max(length(dc.xz), 1e-4);
		if (be < 0.262) {
			float ax = (atan(dc.z, dc.x) / 6.2831853 + 0.5) * 5200.0;
			float ay = be / 0.0021;
			vec2 wcell = floor(vec2(ax, ay));
			vec2 wf = fract(vec2(ax, ay));
			float wwin = step(0.2, wf.x) * step(wf.x, 0.7) * step(0.3, wf.y) * step(wf.y, 0.75);
			float wlit = step(0.8, h1(wcell.x + wcell.y * 57.0, 41.0));
			vec3 wcol = h1(wcell.x * 3.0 + wcell.y, 43.0) < 0.6 ? vec3(1.0, 0.72, 0.42) : vec3(0.8, 0.88, 1.0);
			vec3 bcol = vec3(0.011, 0.011, 0.013) + wcol * wwin * wlit * 0.45;
			col = mix(bcol, haze * 0.5, 0.25);
		}
		vec4 c4 = city_layer(dc, 420.0, 0.25, 0.28, 0.0024, 5.0, flash);
		col = mix(col, mix(c4.rgb, haze, 0.5), c4.a);
		vec4 c3 = city_layer(dc, 260.0, 0.255, 0.295, 0.003, 3.0, flash);
		col = mix(col, mix(c3.rgb, haze, 0.4), c3.a);
		vec4 c2 = city_layer(dc, 170.0, 0.26, 0.31, 0.0038, 1.0, flash);
		col = mix(col, mix(c2.rgb, haze, 0.25), c2.a);
		vec4 c1 = city_layer(dc, 110.0, 0.265, 0.335, 0.005, 2.0, flash);
		col = mix(col, mix(c1.rgb, haze, 0.1), c1.a);
	}
	COLOR = col;
}
"""

var sky_mat: ShaderMaterial
var light: DirectionalLight3D
var _rain_mats: Array = []
var _next := 3.0
var _pulses: Array = []       # [start time, strength]
var _t := 0.0
var _heavy := false
var _roofs: Array = []         # heavy: roofed ground beside the hall (office, paint booth): no rain
var _rain_alpha := 0.12
var _pano: ShaderMaterial          # heavy: the photo sky (its "energy"), brightened by the flashes
var _pano_energy := 1.0
var _rain_player: AudioStreamPlayer
var _thunder_at := -1.0
var _thunder_near := false
## heavy: the flash comes in as a window: a spot from behind the camera (the hall's open front)
## with a window-pane shape, throwing the car's shadow into the room
var _window: SpotLight3D


## hall: floor rectangle of the garage (x/z) – rain falls only outside of it.
func setup(env: Environment, hall: Rect2) -> void:
	sky_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SKY_SHADER
	sky_mat.shader = sh
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	sky.process_mode = Sky.PROCESS_MODE_REALTIME
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	# the hall's fog must not swallow the sky (the city outside the gate); outside it is the city
	# haze, so the far fields fade into the skyline
	env.fog_sky_affect = 0.0
	env.fog_light_color = Color(0.07, 0.05, 0.045)
	env.fog_density = 0.006
	# the lightning: a cold directional light that falls in through the openings
	light = DirectionalLight3D.new()
	light.light_color = Color(0.72, 0.78, 1.0)
	light.light_energy = 0.0
	light.shadow_enabled = true
	light.directional_shadow_max_distance = 60.0
	light.visible = false
	add_child(light)
	_build_ground(hall)
	_build_rain(hall)


## The heavy storm round a hall with its own street outside and a panorama sky (env keeps it).
func setup_heavy(env: Environment, hall: Rect2, roofs: Array = []) -> void:
	_roofs = roofs
	_heavy = true
	_rain_alpha = 0.2
	if env.sky and env.sky.sky_material is ShaderMaterial:
		_pano = env.sky.sky_material
		_pano_energy = float(_pano.get_shader_parameter("energy"))
	light = DirectionalLight3D.new()
	light.light_color = Color(0.72, 0.78, 1.0)
	light.light_energy = 0.0
	light.shadow_enabled = false
	light.visible = false
	add_child(light)
	_window = SpotLight3D.new()
	_window.name = "LightningWindow"
	_window.light_color = Color(0.74, 0.8, 1.0)
	_window.light_energy = 0.0
	_window.spot_range = 70.0
	_window.spot_angle = 17.0
	_window.spot_attenuation = 0.4
	# (no shadow map: rendering one for each flash over the whole workshop made the menu hitch;
	# the window's shape comes from the projector)
	_window.shadow_enabled = false
	_window.light_projector = _window_texture()
	_window.visible = false
	add_child(_window)
	# high behind the camera, out in front of the open hall, looking in and down
	var from := Vector3(hall.get_center().x + 3.0, 9.0, hall.end.y + 22.0)
	_window.global_transform = Transform3D(Basis.looking_at(Vector3(hall.get_center().x, 0.3, hall.get_center().y - 1.0) - from, Vector3.UP), from)
	_build_rain(hall, 2.6, 30.0)
	_build_splashes(hall)
	_rain_player = AudioStreamPlayer.new()
	_rain_player.stream = _rain_loop()
	add_child(_rain_player)
	_rain_player.play()
	_apply_volume()
	Game.settings_changed.connect(_apply_volume)
	_next = 2.0
	# the thunder is synthesised: done in the background now, not on the first clap (a hitch)
	WorkerThreadPool.add_task(func():
		Sfx.get_sound("thunder_near")
		Sfx.get_sound("thunder_far"))


func _apply_volume() -> void:
	var v := float(Game.settings.get("menu_sfx_volume", 0.35))
	if _rain_player:
		# (the rain only a quiet hiss under everything)
		_rain_player.volume_db = linear_to_db(maxf(v, 0.001)) - 20.0


## Splashes where the rain hits the ground outside: tiny bright flecks that pop up and fade.
## The ground round the hall that the rain reaches: a 2 m grid without the roofed parts (the hall,
## the annexes in `_roofs`) and without the strip in front where the camera stands, merged back into
## a few rectangles (one rain system each).
func _open_sky(hall: Rect2, reach: float) -> Array:
	var covered: Array = [hall.grow(1.5)]
	for r in _roofs:
		covered.append((r as Rect2).grow(0.8))
	var area := Rect2(hall.position.x - reach, hall.position.y - reach, hall.size.x + reach * 2.0, hall.size.y + reach)
	var cell := 2.0
	var nx := int(ceil(area.size.x / cell))
	var nz := int(ceil(area.size.y / cell))
	var rows: Array = []
	for iz in nz:
		var spans: Array = []
		var start := -1
		for ix in nx + 1:
			var free := false
			if ix < nx:
				var c := Rect2(area.position.x + ix * cell, area.position.y + iz * cell, cell, cell)
				free = c.end.y <= hall.end.y + 1.5      # (nothing in front of the hall)
				for cv in covered:
					if (cv as Rect2).intersects(c):
						free = false
						break
			if free and start < 0:
				start = ix
			elif not free and start >= 0:
				spans.append(Vector2i(start, ix))
				start = -1
		rows.append(spans)
	# rows with the same spans one after another become one rectangle
	var out: Array = []
	var open := {}       # span -> first row
	for iz in nz + 1:
		var spans: Array = rows[iz] if iz < nz else []
		for sp in open.keys():
			if not spans.has(sp):
				var z0: int = open[sp]
				out.append(Rect2(area.position.x + sp.x * cell, area.position.y + z0 * cell, (sp.y - sp.x) * cell, (iz - z0) * cell))
				open.erase(sp)
		for sp in spans:
			if not open.has(sp):
				open[sp] = iz
	return out


func _build_splashes(hall: Rect2) -> void:
	var outer := hall.grow(1.0)
	var rects: Array = [Rect2(outer.position.x - 12.0, outer.position.y - 30.0, outer.size.x + 24.0, 30.0),
			Rect2(outer.position.x - 12.0, outer.end.y, outer.size.x + 24.0, 10.0)]
	if _heavy:
		rects = _open_sky(hall, 30.0)
	for r in rects:
		var rect: Rect2 = r
		var p := GPUParticles3D.new()
		p.amount = int(rect.size.x * rect.size.y * [0.4, 0.7, 1.0, 1.4][clampi(Game.quality(), 0, 3)])
		p.lifetime = 0.25
		p.preprocess = 0.5
		p.local_coords = false
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		p.position = Vector3(rect.get_center().x, 0.03, rect.get_center().y)
		p.visibility_aabb = AABB(Vector3(-rect.size.x, -2, -rect.size.y), Vector3(rect.size.x * 2.0, 4, rect.size.y * 2.0))
		var pm := ParticleProcessMaterial.new()
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		pm.emission_box_extents = Vector3(rect.size.x * 0.5, 0.01, rect.size.y * 0.5)
		pm.direction = Vector3(0, 1, 0)
		pm.spread = 35.0
		pm.initial_velocity_min = 0.6
		pm.initial_velocity_max = 1.4
		pm.gravity = Vector3(0, -9.8, 0)
		pm.scale_min = 0.6
		pm.scale_max = 1.4
		var fade := Gradient.new()
		fade.set_color(0, Color(1, 1, 1, 0.5))
		fade.set_color(1, Color(1, 1, 1, 0.0))
		var ft := GradientTexture1D.new()
		ft.gradient = fade
		pm.color_ramp = ft
		p.process_material = pm
		var quad := QuadMesh.new()
		quad.size = Vector2(0.06, 0.05)
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		m.vertex_color_use_as_albedo = true
		m.albedo_color = Color(0.75, 0.8, 0.9, 0.6)
		quad.material = m
		p.draw_pass_1 = quad
		add_child(p)
		add_child(_ripples(rect))


const RIPPLE_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
void fragment() {
	float r = length(UV - 0.5) * 2.0;
	// a thin ring at the edge and a fainter one inside it
	float ring = smoothstep(0.78, 0.9, r) * (1.0 - smoothstep(0.9, 1.0, r));
	float inner = smoothstep(0.42, 0.5, r) * (1.0 - smoothstep(0.5, 0.58, r)) * 0.4;
	ALBEDO = vec3(0.78, 0.83, 0.92);
	ALPHA = (ring + inner) * COLOR.a;
}
"""


## Where a drop hits: a thin circle on the wet ground that runs out quickly and fades (subtle).
func _ripples(rect: Rect2) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = maxi(8, int(rect.size.x * rect.size.y * [0.12, 0.2, 0.3, 0.4][clampi(Game.quality(), 0, 3)]))
	p.lifetime = 0.45
	p.preprocess = 0.5
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.position = Vector3(rect.get_center().x, 0.02, rect.get_center().y)
	p.visibility_aabb = AABB(Vector3(-rect.size.x, -1, -rect.size.y), Vector3(rect.size.x * 2.0, 2, rect.size.y * 2.0))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(rect.size.x * 0.5, 0.0, rect.size.y * 0.5)
	pm.gravity = Vector3.ZERO
	pm.initial_velocity_min = 0.0
	pm.initial_velocity_max = 0.0
	pm.scale_min = 0.7
	pm.scale_max = 1.3
	# out fast at first, then slowing down
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.08), 0.0, 4.0)
	grow.add_point(Vector2(1.0, 1.0), 0.3, 0.0)
	var gt := CurveTexture.new()
	gt.curve = grow
	pm.scale_curve = gt
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.22))
	fade.set_color(1, Color(1, 1, 1, 0.0))
	var ft := GradientTexture1D.new()
	ft.gradient = fade
	pm.color_ramp = ft
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.32, 0.32)
	quad.orientation = PlaneMesh.FACE_Y
	var sh := Shader.new()
	sh.code = RIPPLE_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	quad.material = m
	p.draw_pass_1 = quad
	return p


## A loop of heavy rain: a wash of filtered noise (the roar), a low rumble and dense patter.
static func _rain_loop() -> AudioStreamWAV:
	var rate := 22050
	var n := rate * 4
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var lp := 0.0
	var lp2 := 0.0
	var samples := PackedFloat32Array()
	samples.resize(n)
	for i in n:
		var w := rng.randf_range(-1.0, 1.0)
		lp += (w - lp) * 0.35          # the hiss of the downpour
		lp2 += (w - lp2) * 0.02        # the low roar
		var v := lp * 0.45 + lp2 * 1.6
		if rng.randf() < 0.012:
			v += rng.randf_range(-0.6, 0.6)  # drops on the roof and the street
		samples[i] = v
	# cross-fade the ends so the loop has no click
	var fade := rate / 4
	for i in fade:
		var k := float(i) / fade
		samples[i] = samples[i] * k + samples[n - fade + i] * (1.0 - k)
	for i in n:
		data.encode_s16(i * 2, int(clampf(samples[i] * 0.55, -1.0, 1.0) * 32000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.data = data.slice(0, (n - fade) * 2)
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_end = n - fade
	return wav


func _build_ground(hall: Rect2) -> void:
	# wet asphalt apron around the hall (just below the hall floor, so it never shows inside)
	var apron := PlaneMesh.new()
	apron.size = hall.grow(14.0).size
	var mat := StandardMaterial3D.new()
	var at: Texture2D = TexKit.photo_texture("asphalt_albedo.jpg")
	if at:
		mat.albedo_texture = at
		mat.normal_enabled = true
		mat.normal_texture = TexKit.photo_texture("asphalt_normal.png")
		mat.normal_scale = 0.25
	mat.albedo_color = Color(0.1, 0.1, 0.11)
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	mat.uv1_scale = Vector3(1.0 / 1.2, 1.0 / 1.2, 1.0 / 1.2)
	mat.roughness = 0.12
	mat.metallic_specular = 0.7
	var mi := MeshInstance3D.new()
	mi.mesh = apron
	mi.material_override = mat
	mi.position = Vector3(hall.get_center().x, -0.03, hall.get_center().y)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	# (no fields beyond the apron: the skyline in the sky shader starts right behind it)


func _build_rain(hall: Rect2, density := 1.0, reach := 14.0) -> void:
	var outer := hall.grow(1.5)
	var slabs := [
		Rect2(outer.position.x - reach, outer.position.y - reach, outer.size.x + reach * 2.0, reach),   # back
		Rect2(outer.position.x - reach, outer.end.y, outer.size.x + reach * 2.0, reach),                 # front
		Rect2(outer.position.x - reach, outer.position.y, reach, outer.size.y),                          # left
		Rect2(outer.end.x, outer.position.y, reach, outer.size.y),                                       # right
	]
	if _heavy:
		# everywhere round the hall that has no roof over it (not the office and the paint booth
		# beside the hall, and not in front of the camera)
		slabs = _open_sky(hall, reach)
	var q := clampi(Game.quality(), 0, 3)
	for r in slabs:
		var rect: Rect2 = r
		var p := GPUParticles3D.new()
		p.amount = mini(int(rect.size.x * rect.size.y * [0.6, 0.9, 1.3, 1.6][q] * density), 60000)
		p.lifetime = 0.95
		p.preprocess = 1.0
		p.local_coords = false
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		p.position = Vector3(rect.get_center().x, 14.0, rect.get_center().y)
		p.visibility_aabb = AABB(Vector3(-rect.size.x, -20, -rect.size.y), Vector3(rect.size.x * 2.0, 30, rect.size.y * 2.0))
		var pm := ParticleProcessMaterial.new()
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		pm.emission_box_extents = Vector3(rect.size.x * 0.5, 0.5, rect.size.y * 0.5)
		pm.direction = Vector3(0.1, -1, 0.05)
		pm.spread = 3.0
		pm.initial_velocity_min = 15.0
		pm.initial_velocity_max = 18.0
		pm.gravity = Vector3.ZERO
		p.process_material = pm
		var quad := QuadMesh.new()
		quad.size = Vector2(0.014, 0.55)
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
		m.albedo_color = Color(0.6, 0.65, 0.75, _rain_alpha)
		if _heavy:
			quad.size = Vector2(0.018, 0.75)
		quad.material = m
		_rain_mats.append(m)
		p.draw_pass_1 = quad
		add_child(p)


## The window the lightning shines through: four panes in a frame, soft at the edges.
static func _window_texture() -> ImageTexture:
	var n := 256
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var u := float(x) / (n - 1)
			var v := float(y) / (n - 1)
			var inside := smoothstep(0.04, 0.1, u) * smoothstep(0.96, 0.9, u) * smoothstep(0.04, 0.1, v) * smoothstep(0.96, 0.9, v)
			# the cross bars (glazing bars) between the panes
			var bar := maxf(1.0 - smoothstep(0.018, 0.03, absf(u - 0.5)), 1.0 - smoothstep(0.018, 0.03, absf(v - 0.5)))
			var k := inside * (1.0 - bar)
			img.set_pixel(x, y, Color(k, k, k, 1.0))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _strike() -> void:
	var az := randf() * TAU
	var el := randf_range(0.18, 0.5)
	var dir := Vector3(cos(az) * cos(el), sin(el), sin(az) * cos(el))
	if sky_mat:
		sky_mat.set_shader_parameter("flash_dir", dir)
		sky_mat.set_shader_parameter("bolt_seed", randf() * 100.0)
	if _heavy:
		# the thunder follows: close strikes crack soon and loud, far ones roll in later
		_thunder_near = randf() < 0.45
		_thunder_at = _t + (randf_range(0.25, 0.9) if _thunder_near else randf_range(1.5, 4.0))
	light.global_transform = Transform3D(Basis.looking_at(-dir, Vector3.UP), Vector3.ZERO)
	_pulses.clear()
	var t0 := _t
	var n := randi_range(2, 4)
	for k in n:
		_pulses.append([t0, randf_range(0.5, 1.0) if k > 0 else 1.0])
		t0 += randf_range(0.06, 0.18)


func _process(delta: float) -> void:
	_t += delta
	_next -= delta
	if _next <= 0.0:
		_next = randf_range(4.0, 9.0) if _heavy else randf_range(5.0, 13.0)
		_strike()
	if _thunder_at >= 0.0 and _t >= _thunder_at:
		_thunder_at = -1.0
		var v := float(Game.settings.get("menu_sfx_volume", 0.35))
		if v > 0.01:
			Sfx.play(self, "thunder_near" if _thunder_near else "thunder_far", linear_to_db(v) + (-2.0 if _thunder_near else -6.0), null, randf_range(0.85, 1.1))
	var f := 0.0
	var b := 0.0
	for p in _pulses:
		var age := _t - float(p[0])
		if age >= 0.0:
			var e := float(p[1]) * exp(-age / 0.07)
			f = maxf(f, e)
			b = maxf(b, float(p[1]) * exp(-age / 0.05))
	if sky_mat:
		sky_mat.set_shader_parameter("flash", f)
		sky_mat.set_shader_parameter("bolt", b)
	if _pano:
		_pano.set_shader_parameter("energy", _pano_energy * (1.0 + f * 3.5))
	if _window:
		# the room lights up only in the window's shape (a faint fill elsewhere)
		_window.visible = f > 0.01
		_window.light_energy = f * 16.0
		light.visible = f > 0.01
		light.light_energy = f * 0.25
	else:
		light.visible = f > 0.01
		light.light_energy = f * 2.2
	for m in _rain_mats:
		(m as StandardMaterial3D).albedo_color = Color(0.6 + f * 0.4, 0.65 + f * 0.35, 0.75 + f * 0.25, _rain_alpha + f * 0.35)

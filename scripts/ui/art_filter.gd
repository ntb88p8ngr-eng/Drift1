extends CanvasLayer
## Art-style filters over the 3D picture (below the HUD and the menus): "Retro 90er" (low resolution,
## few colours with ordered dithering, scanlines, a bit of VHS colour bleed and noise) and "Comic"
## (flat colour bands, ink outlines, halftone dots in the shadows). Settings key "art_style".

const RETRO := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform float lines = 240.0;

const float BAYER[16] = float[](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);

float rnd(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }

void fragment() {
	vec2 res = vec2(lines * SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x, lines);
	vec2 cell = floor(SCREEN_UV * res);
	vec2 uv = (cell + 0.5) / res;
	// VHS: the colours bleed a little sideways, the picture wobbles now and then
	float wob = sin(uv.y * 40.0 + TIME * 3.0) * 0.0006 * step(0.985, rnd(vec2(floor(TIME * 8.0), 1.0)));
	vec3 c;
	c.r = texture(screen_tex, uv + vec2(1.2 / res.x + wob, 0.0)).r;
	c.g = texture(screen_tex, uv + vec2(wob, 0.0)).g;
	c.b = texture(screen_tex, uv - vec2(1.2 / res.x - wob, 0.0)).b;
	// few colours: ordered dithering to 24 levels per channel
	int bi = int(mod(cell.x, 4.0)) + int(mod(cell.y, 4.0)) * 4;
	float d = BAYER[bi] / 16.0 - 0.5;
	float levels = 24.0;
	c = floor(c * levels + d + 0.5) / levels;
	// a warmer, punchier CRT
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(l), c, 1.18) * vec3(1.04, 1.0, 0.95);
	// scanlines and grain
	c *= 0.8 + 0.2 * sin((SCREEN_UV.y * res.y) * 6.28318);
	c += (rnd(cell + fract(TIME) * 100.0) - 0.5) * 0.035;
	vec2 q = SCREEN_UV - 0.5;
	c *= 1.0 - dot(q, q) * 0.9;
	COLOR = vec4(clamp(c, 0.0, 1.0), 1.0);
}
"""

const COMIC := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;

float lum(vec3 c) { return dot(c, vec3(0.299, 0.587, 0.114)); }

void fragment() {
	vec2 px = SCREEN_PIXEL_SIZE * 1.5;
	// ink: Sobel on the brightness
	float tl = lum(texture(screen_tex, SCREEN_UV + vec2(-px.x, -px.y)).rgb);
	float tc = lum(texture(screen_tex, SCREEN_UV + vec2(0.0, -px.y)).rgb);
	float tr = lum(texture(screen_tex, SCREEN_UV + vec2(px.x, -px.y)).rgb);
	float ml = lum(texture(screen_tex, SCREEN_UV + vec2(-px.x, 0.0)).rgb);
	float mr = lum(texture(screen_tex, SCREEN_UV + vec2(px.x, 0.0)).rgb);
	float bl = lum(texture(screen_tex, SCREEN_UV + vec2(-px.x, px.y)).rgb);
	float bc = lum(texture(screen_tex, SCREEN_UV + vec2(0.0, px.y)).rgb);
	float br = lum(texture(screen_tex, SCREEN_UV + vec2(px.x, px.y)).rgb);
	float gx = -tl - 2.0 * ml - bl + tr + 2.0 * mr + br;
	float gy = -tl - 2.0 * tc - tr + bl + 2.0 * bc + br;
	float edge = sqrt(gx * gx + gy * gy);
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	float l = lum(c);
	// flat colour bands, stronger colours
	float band = floor(l * 4.0 + 0.5) / 4.0;
	vec3 hue = c / max(l, 0.002);
	vec3 cel = clamp(hue * max(band, 0.06), 0.0, 1.0);
	float cl = lum(cel);
	cel = clamp(mix(vec3(cl), cel, 1.35), 0.0, 1.0);
	// halftone dots in the shadows (45° screen)
	vec2 g = FRAGCOORD.xy / 5.0;
	g = vec2(g.x + g.y, g.y - g.x) * 0.7071;
	float dotr = length(fract(g) - 0.5);
	float shade = smoothstep(0.45, 0.1, l);
	cel *= mix(1.0, 0.45, shade * step(dotr, 0.18 + shade * 0.25));
	// ink lines
	float ink = smoothstep(0.22, 0.45, edge / max(l + 0.25, 0.25));
	cel = mix(cel, vec3(0.04, 0.03, 0.06), ink);
	COLOR = vec4(cel, 1.0);
}
"""

var _rect: ColorRect
var _mats := []


func _ready() -> void:
	layer = -4
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rect)
	for code in [RETRO, COMIC]:
		var sh := Shader.new()
		sh.code = code
		var m := ShaderMaterial.new()
		m.shader = sh
		_mats.append(m)
	Game.settings_changed.connect(_apply)
	_apply()


func _apply() -> void:
	var s := clampi(int(Game.settings.get("art_style", 0)), 0, 2)
	_rect.visible = s > 0
	if s > 0:
		_rect.material = _mats[s - 1]

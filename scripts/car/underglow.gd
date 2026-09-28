extends Node3D
## Underglow: neon tubes along the whole front, rear and both sides of the car. Each tube lights a
## continuous strip of ground (an emissive decal the length of that side) plus the underbody (two
## soft lights per side). Every side can join the flasher mode or stay lit steadily; holding the
## flash key (N) strobes all tubes, flashers installed or not.
## Config (Game.get_underglow): {"on", "mode", "speed", "sides": {side: {"on", "color": "#rrggbb", "flash", "bright"}}}

const SIDES := ["front", "rear", "left", "right"]

var cfg: Dictionary = {}
var manual := false          # flash key held (set by the car every frame)

var _strips: Array = []      # {mat, decal, lights, color, flash, side, bright}
var _t := 0.0
var _mt := 0.0               # time since the flash key went down
static var _glow_tex := {}
## base strength (a subtle glow; the brightness slider scales it)
const TUBE_E := 3.5
const DECAL_E := 1.5
const LIGHT_E := 0.9
## overall scale: the brightest setting (2x) now gives what 1/8 of the old maximum was
const SCALE := 0.125


## dims: CarBody.physics_spec (track, axle_f, axle_r, base).
func setup(p_cfg: Dictionary, dims: Dictionary, lights: bool) -> void:
	cfg = p_cfg
	# remove the old tubes right away (queue_free would leave them flashing until the frame ends)
	for c in get_children():
		remove_child(c)
		c.free()
	_strips.clear()
	visible = bool(cfg.get("on", false))
	set_process(visible)
	if not visible:
		return
	var tr: float = float(dims.get("track", 0.75))
	var af: float = float(dims.get("axle_f", -1.3))
	var ar: float = float(dims.get("axle_r", 1.3))
	var y: float = float(dims.get("base", 0.15)) + 0.02
	var zf := af + signf(af) * 0.62
	var zr := ar + signf(ar) * 0.5
	var zc := (zf + zr) * 0.5
	var side_len := absf(zr - zf) - 0.35
	var sides: Dictionary = cfg.get("sides", {})
	for i in SIDES.size():
		var sd: Dictionary = sides.get(SIDES[i], {})
		if not bool(sd.get("on", true)):
			continue
		var col := Color.from_string(str(sd.get("color", "#8a3dff")), Color(0.55, 0.25, 1.0))
		# brightness per side: quadratic, so the slider is clearly visible through tone mapping/glow
		var br := clampf(float(sd.get("bright", 1.0)), 0.1, 2.0)
		var bf := br * br * SCALE
		# tube: centre, direction along it (x = across the car, z = along it) and length
		var along_x := i < 2
		var pos: Vector3
		var length: float
		match i:
			0:
				pos = Vector3(0, y, zf)
				length = tr * 1.85
			1:
				pos = Vector3(0, y, zr)
				length = tr * 1.75
			2:
				pos = Vector3(-tr - 0.02, y, zc)
				length = side_len
			_:
				pos = Vector3(tr + 0.02, y, zc)
				length = side_len
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = col
		mat.emission_enabled = true
		mat.emission = col
		mat.emission_energy_multiplier = TUBE_E * bf
		var tube := MeshInstance3D.new()
		var cm := CapsuleMesh.new()
		cm.radius = 0.018
		cm.height = length
		cm.radial_segments = 8
		cm.rings = 1
		cm.material = mat
		tube.mesh = cm
		tube.position = pos
		# capsules stand along y: lay them along the side
		tube.rotation = Vector3(PI * 0.5, 0, 0) if not along_x else Vector3(0, 0, PI * 0.5)
		tube.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(tube)
		# the neon wash on the ground: one decal the length of the tube, spilling outwards
		var decal := Decal.new()
		decal.texture_emission = _glow_texture(i)
		decal.texture_albedo = _glow_texture(i)
		decal.albedo_mix = 0.0
		decal.emission_energy = DECAL_E * bf
		decal.modulate = col
		decal.upper_fade = 0.2
		decal.lower_fade = 0.4
		decal.cull_mask = 1
		var out := 0.45
		# a brighter tube throws a wider glow
		var across := 1.9 * (0.6 + 0.4 * br)
		if along_x:
			decal.size = Vector3(length + 0.8, 1.0, across)
			decal.position = Vector3(0, y - 0.45, pos.z + signf(pos.z) * out)
		else:
			decal.size = Vector3(across, 1.0, length + 0.8)
			decal.position = Vector3(pos.x + signf(pos.x) * out, y - 0.45, zc)
			decal.rotation = Vector3(0, PI * 0.5, 0)
			decal.size = Vector3(length + 0.8, 1.0, across)
		add_child(decal)
		var ls: Array = []
		if lights:
			# two soft lights per side (one at the ends) tint the underbody and the wheels
			var n := 1 if along_x else 2
			for k in n:
				var l := OmniLight3D.new()
				l.light_color = col
				l.omni_range = 1.9 * (0.7 + 0.3 * br)
				l.omni_attenuation = 1.4
				l.light_energy = LIGHT_E * bf
				l.shadow_enabled = false
				l.light_specular = 0.15
				var f := 0.0 if n == 1 else (float(k) / (n - 1) - 0.5) * 0.6
				l.position = pos + (Vector3(f * length, -0.06, 0) if along_x else Vector3(signf(pos.x) * 0.15, -0.06, f * length))
				add_child(l)
				ls.append(l)
		_strips.append({"mat": mat, "decal": decal, "lights": ls, "color": col, "flash": bool(sd.get("flash", false)), "side": i,
			"bright": bf})


## Soft, see-through neon wash: brightest along the middle, but its width and strength wander along
## the side (noise) and the ends fade out unevenly – not a clean stripe. One variant per side.
static func _glow_texture(variant := 0) -> Texture2D:
	if _glow_tex.has(variant):
		return _glow_tex[variant]
	var w := 256
	var h := 48
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var nz := FastNoiseLite.new()
	nz.seed = 71 + variant * 13
	nz.frequency = 0.035
	nz.fractal_octaves = 3
	for x in w:
		var t := (float(x) + 0.5) / w
		# width and strength along the tube, plus ragged ends
		var width := 0.82 + 0.18 * (0.5 + 0.5 * nz.get_noise_1d(x * 0.5))
		var gain := 0.85 + 0.15 * (0.5 + 0.5 * nz.get_noise_1d(x * 0.5 + 500.0))
		var e0 := 0.1 + 0.08 * nz.get_noise_1d(900.0 + x * 0.2)
		var ends := smoothstep(0.0, e0 + 0.12, t) * smoothstep(1.0, 0.88 - e0, t)
		for y in h:
			var across := absf((float(y) + 0.5) / h - 0.5) * 2.0 / width
			var wisp := 0.96 + 0.04 * nz.get_noise_2d(x * 2.0, y * 6.0)
			var a := exp(-across * across * 3.2) * wisp
			var v := clampf(a * ends * gain * 0.45, 0.0, 1.0)
			img.set_pixel(x, y, Color(v, v, v, v))
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_glow_tex[variant] = tex
	return tex


## Brightness 0..1 of a flashing side at time t (side index 0 front, 1 rear, 2 left, 3 right).
static func pattern(mode: int, t: float, side: int) -> float:
	match mode:
		1:  # pulse
			return 0.25 + 0.75 * (0.5 + 0.5 * sin(t * TAU * 0.7))
		2:  # blink
			return 1.0 if fmod(t * 2.0, 1.0) < 0.5 else 0.0
		3:  # strobe: double flash
			var p := fmod(t * 1.3, 1.0)
			return 1.0 if (p < 0.06 or (p > 0.14 and p < 0.2)) else 0.0
		4:  # alternate: front/left vs rear/right
			var on := fmod(t * 2.0, 1.0) < 0.5
			var group := side == 0 or side == 2
			return 1.0 if on == group else 0.0
		5:  # chase: front → right → rear → left
			var order := [0, 3, 1, 2]
			var k := int(fmod(t * 4.0, 4.0))
			return 1.0 if order[k] == side else 0.12
		6:  # police: two quick flashes left group, then right group
			var p2 := fmod(t * 1.2, 1.0)
			var first := side == 0 or side == 2
			var ph := p2 if first else fmod(p2 + 0.5, 1.0)
			return 1.0 if (ph < 0.08 or (ph > 0.14 and ph < 0.22)) else 0.0
		7:  # rainbow: brightness stays, the colour cycles (see _process)
			return 1.0
	return 1.0


func _process(delta: float) -> void:
	_t += delta * float(cfg.get("speed", 1.0))
	_mt = _mt + delta if manual else 0.0
	var mode := int(cfg.get("mode", 0))
	for s in _strips:
		var k := 1.0
		var col: Color = s["color"]
		var side: int = s["side"]
		if manual:
			# flash key: fast double strobe on every tube
			var p := fmod(_mt * 3.0, 1.0)
			k = 1.0 if (p < 0.12 or (p > 0.25 and p < 0.37)) else 0.0
		elif bool(s["flash"]) and mode > 0:
			k = pattern(mode, _t, side)
			if mode == 7:
				col = Color.from_hsv(fposmod(_t * 0.25 + side * 0.25, 1.0), 0.9, 1.0)
		# brightness per side: the tube, the glow on the ground and the lights scale with it
		var br: float = s.get("bright", 1.0)
		var mat: StandardMaterial3D = s["mat"]
		mat.emission = col
		mat.albedo_color = col * (0.25 + 0.75 * k)
		mat.emission_energy_multiplier = (0.04 + 0.96 * k) * TUBE_E * br
		var decal: Decal = s["decal"]
		decal.modulate = col
		decal.emission_energy = DECAL_E * k * br
		decal.visible = k > 0.02
		for l in s["lights"]:
			(l as OmniLight3D).light_color = col
			(l as OmniLight3D).light_energy = LIGHT_E * k * br
			(l as OmniLight3D).visible = k > 0.02

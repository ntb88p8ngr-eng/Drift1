extends Node3D
## Underglow: four neon strips under the car (front, rear, left, right), each with its own colour,
## lighting the ground below. Every side can join the flasher mode or stay lit steadily.
## Config (Game.get_underglow): {"on", "mode", "speed", "sides": {side: {"color": "#rrggbb", "flash"}}}

const SIDES := ["front", "rear", "left", "right"]

var cfg: Dictionary = {}
var _strips: Array = []      # [StandardMaterial3D, OmniLight3D, Color, flash, side index]
var _t := 0.0


## dims: CarBody.physics_spec (track, axle_f, axle_r, base).
func setup(p_cfg: Dictionary, dims: Dictionary, lights: bool) -> void:
	cfg = p_cfg
	for c in get_children():
		c.queue_free()
	_strips.clear()
	visible = bool(cfg.get("on", false))
	if not visible:
		set_process(false)
		return
	set_process(true)
	var tr: float = float(dims.get("track", 0.75))
	var af: float = float(dims.get("axle_f", -1.3))
	var ar: float = float(dims.get("axle_r", 1.3))
	var y: float = float(dims.get("base", 0.15)) + 0.02
	var zf := af + signf(af) * 0.55
	var zr := ar + signf(ar) * 0.45
	var side_len := absf(ar - af) - 0.9
	var sides: Dictionary = cfg.get("sides", {})
	for i in SIDES.size():
		var sd: Dictionary = sides.get(SIDES[i], {})
		var col := Color.from_string(str(sd.get("color", "#8a3dff")), Color(0.55, 0.25, 1.0))
		if not bool(sd.get("on", true)):
			continue
		var pos: Vector3
		var size: Vector3
		match i:
			0: pos = Vector3(0, y, zf); size = Vector3(tr * 1.7, 0.03, 0.05)
			1: pos = Vector3(0, y, zr); size = Vector3(tr * 1.6, 0.03, 0.05)
			2: pos = Vector3(-tr + 0.05, y, (af + ar) * 0.5); size = Vector3(0.05, 0.03, side_len)
			_: pos = Vector3(tr - 0.05, y, (af + ar) * 0.5); size = Vector3(0.05, 0.03, side_len)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = col
		mat.emission_enabled = true
		mat.emission = col
		mat.emission_energy_multiplier = 6.0
		var strip := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = size
		bm.material = mat
		strip.mesh = bm
		strip.position = pos
		strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(strip)
		var l: OmniLight3D = null
		if lights:
			# the glow on the ground: a flat-ish light just under the strip
			l = OmniLight3D.new()
			l.light_color = col
			l.omni_range = 2.6 if i >= 2 else 2.2
			l.omni_attenuation = 1.6
			l.light_energy = 3.0
			l.shadow_enabled = false
			l.light_specular = 0.2
			l.position = pos + Vector3(0, -0.05, 0) + (Vector3(0, 0, 0) if i < 2 else Vector3(signf(pos.x) * 0.15, 0, 0))
			add_child(l)
		_strips.append([mat, l, col, bool(sd.get("flash", false)), i])


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
	var mode := int(cfg.get("mode", 0))
	for s in _strips:
		var k := 1.0
		var col: Color = s[2]
		if bool(s[3]) and mode > 0:
			k = pattern(mode, _t, int(s[4]))
			if mode == 7:
				col = Color.from_hsv(fposmod(_t * 0.25 + int(s[4]) * 0.25, 1.0), 0.9, 1.0)
		var mat: StandardMaterial3D = s[0]
		mat.emission = col
		mat.albedo_color = col
		mat.emission_energy_multiplier = 0.3 + 5.7 * k
		var l: OmniLight3D = s[1]
		if l:
			l.light_color = col
			l.light_energy = 3.0 * k
			l.visible = k > 0.02

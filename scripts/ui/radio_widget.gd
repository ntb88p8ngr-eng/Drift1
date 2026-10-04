extends SubViewportContainer
## The car radio as a 3D object to click (main menu: big, floating; in a race: small): the Alpine model
## in its own little world, its display showing radio_display.gd, every button working (Radio.*):
##   volume knob: turn (drag up / down or the mouse wheel anywhere on the radio), push (click) = on / off
##   eject, TUNER BAND (FM1 / FM2 / back from the tape), TAPE (play / pause), UP / DN (next station, track),
##   TUNE (frequency / name), TIME (the clock), A.P.I. (titles scroll by), T.INFO (the title now),
##   presets 1-6, the cassette slot (pick a tape: it slides in).
## Its orange volume ring lights up as far as the volume goes.

signal tape_list_wanted        # the slot clicked without a tape: the owner shows the tapes

const RadioDisplay = preload("res://scripts/ui/radio_display.gd")
const MODEL := "res://assets/props/radio/car_radio.glb"
const KNOB_C := Vector2(-0.5538, 0.1975)     # model space (x, y), the knob's axis
const KNOB_R := 0.064
const FRONT_Z := 0.05
const ARC_FROM := 225.0                       # degrees: the volume ring from 7 o'clock …
const ARC_SPAN := 270.0                       # … clockwise round to 5 o'clock

## the buttons: name -> [min x, min y, max x, max y] in model space (measured on the model)
const BUTTONS := {
	"eject": [-0.46, 0.313, -0.342, 0.40], "band": [-0.46, 0.215, -0.342, 0.30], "tape": [-0.46, 0.105, -0.342, 0.19],
	"time": [0.387, 0.398, 0.495, 0.467], "tune": [0.387, 0.30, 0.48, 0.395], "up": [0.387, 0.209, 0.48, 0.30],
	"dn": [0.387, 0.105, 0.48, 0.203], "api": [0.197, 0.399, 0.307, 0.467], "tinfo": [0.197, 0.312, 0.307, 0.387],
	"p1": [0.494, 0.313, 0.59, 0.406], "p2": [0.59, 0.313, 0.671, 0.406], "p3": [0.494, 0.209, 0.59, 0.302],
	"p4": [0.59, 0.209, 0.671, 0.302], "p5": [0.494, 0.105, 0.59, 0.21], "p6": [0.59, 0.105, 0.671, 0.21],
	"slot": [-0.31, 0.34, 0.09, 0.46],
}
const PRESS_DEPTH := 0.009
const PRESS_TIME := 0.22
## the TREB / BASS sliders: their thumbs [min x, min y, max x, max y] (they slide along x), the tracks
const SLIDERS := {"bass": [-0.59, 0.318, -0.516, 0.348], "treble": [-0.59, 0.398, -0.516, 0.428]}
const SLIDER_TRACKS := {"bass": [-0.652, 0.312, -0.452, 0.354], "treble": [-0.652, 0.392, -0.452, 0.434]}
const SLIDE_C := -0.553          # the thumbs' middle (0 dB) …
const SLIDE_R := 0.061           # … and how far they go either way

var floating := true            # the menu's: drifts and turns a little
var _vp: SubViewport
var _cam: Camera3D
var _pivot: Node3D               # floats
var _radio: Node3D
var _knob: Node3D
var _arc_mat: ShaderMaterial
var _display: Control
var _flash: MeshInstance3D
var _flash_t := 0.0
var _tape_node: Node3D
var _tape_anim := -1.0           # > 0: the cassette going in (0..1), < -1: coming out
var _tape_dir := 0
var _drag := false
var _drag_from := Vector2.ZERO
var _drag_vol := 0.0
var _drag_moved := false
var _slider := ""                # "bass" / "treble" while its thumb is dragged
var _t := 0.0
var _hover := ""
var _btn_nodes := {}             # button -> Node3D with its own pieces of the model (they press in)
var _btn_press := {}             # button -> seconds of its press left


func _ready() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_PASS
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.55, 0.55, 0.62)
	env.environment.ambient_light_energy = 0.9
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment.glow_enabled = true
	env.environment.glow_intensity = 0.5
	env.environment.glow_bloom = 0.05
	_vp.add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation = Vector3(-0.55, 0.35, 0)
	key.light_energy = 1.1
	_vp.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation = Vector3(-0.2, -2.6, 0)
	rim.light_energy = 0.6
	rim.light_color = Color(0.75, 0.6, 1.0)
	_vp.add_child(rim)
	_pivot = Node3D.new()
	_vp.add_child(_pivot)
	_radio = (load(MODEL) as PackedScene).instantiate()
	_pivot.add_child(_radio)
	_radio.position = Vector3(0, -0.283, 0)        # the face's middle on the pivot
	_cam = Camera3D.new()
	_cam.fov = 26.0
	_cam.position = Vector3(0, 0.0, 3.25)
	_vp.add_child(_cam)
	_cam.current = true
	_setup_display()
	_split_knob()
	_setup_arc()
	_split_buttons()
	# the press flash: a soft white glow over the button (drawn over everything)
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fm.no_depth_test = true
	fm.albedo_color = Color(1, 0.8, 0.6, 0.0)
	_flash = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.1, 0.1)
	_flash.mesh = q
	_flash.material_override = fm
	_flash.visible = false
	_radio.add_child(_flash)
	_build_tape()
	resized.connect(_fit)
	_fit()


## The camera framing: the whole radio (1.42 x 0.4) fills the control's width.
func _fit() -> void:
	if size.x <= 1.0 or size.y <= 1.0:
		return
	var aspect := size.x / size.y
	# vertical fov that shows 1.55 m of width at the camera's distance
	var half_w := 0.8
	var dist := 3.25
	_cam.fov = rad_to_deg(2.0 * atan(half_w / aspect / dist))


func _setup_display() -> void:
	var dvp := SubViewport.new()
	dvp.size = Vector2i(RadioDisplay.W, RadioDisplay.H)
	dvp.transparent_bg = false
	dvp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	# (inside the 3D one: a SubViewportContainer would show every SubViewport child flat on screen)
	_vp.add_child(dvp)
	_display = RadioDisplay.new()
	dvp.add_child(_display)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_texture = dvp.get_texture()
	# the display's UVs cover only a part of the model's texture: that part spread over 0..1
	var u0 := Vector2(0.1158, 0.3799)
	var u1 := Vector2(0.9239, 0.7239)
	var sc := Vector2(1.0, 1.0) / (u1 - u0)
	# (upside down: the model's display UVs run bottom to top)
	m.uv1_scale = Vector3(sc.x, -sc.y, 1)
	m.uv1_offset = Vector3(-u0.x * sc.x, u1.y * sc.y, 0)
	m.emission_enabled = true
	m.emission_texture = dvp.get_texture()
	m.emission_energy_multiplier = 1.4
	for n in _radio.find_children("*display*", "MeshInstance3D", true, false):
		(n as MeshInstance3D).material_override = m


## The model's knob is part of its body: its triangles (in front of the face, round the axis) are taken
## out into a mesh of their own that turns.
func _split_knob() -> void:
	for n in _radio.find_children("radio_base*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var rel: Transform3D = _radio.global_transform.affine_inverse() * mi.global_transform
		var mesh := mi.mesh as ArrayMesh
		if mesh == null:
			continue
		var out := ArrayMesh.new()
		var knob := ArrayMesh.new()
		for si in mesh.get_surface_count():
			var arr := mesh.surface_get_arrays(si)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			if idx.is_empty():
				idx = PackedInt32Array(range(v.size()))
			var keep := PackedInt32Array()
			var take := PackedInt32Array()
			for t in range(0, idx.size(), 3):
				var c: Vector3 = rel * ((v[idx[t]] + v[idx[t + 1]] + v[idx[t + 2]]) / 3.0)
				var inside := Vector2(c.x, c.y).distance_to(KNOB_C) < KNOB_R and c.z > 0.042
				# (packed arrays are copied on assignment: appended to directly)
				if inside:
					take.append_array([idx[t], idx[t + 1], idx[t + 2]])
				else:
					keep.append_array([idx[t], idx[t + 1], idx[t + 2]])
			var mat := mi.get_active_material(si)
			var a1 := arr.duplicate()
			a1[Mesh.ARRAY_INDEX] = keep
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a1)
			out.surface_set_material(out.get_surface_count() - 1, mat)
			if take.size() > 0:
				var a2 := arr.duplicate()
				a2[Mesh.ARRAY_INDEX] = take
				knob.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a2)
				knob.surface_set_material(knob.get_surface_count() - 1, mat)
		mi.mesh = out
		if knob.get_surface_count() == 0:
			continue
		# the turning part: pivot on the axis, the mesh offset back by it
		_knob = Node3D.new()
		_radio.add_child(_knob)
		_knob.position = Vector3(KNOB_C.x, KNOB_C.y, 0)
		var km := MeshInstance3D.new()
		km.mesh = knob
		_knob.add_child(km)
		km.transform = Transform3D(Basis.IDENTITY, -Vector3(KNOB_C.x, KNOB_C.y, 0)) * rel
		# a white line on its cap: so the turning shows
		var mark := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.008, 0.032, 0.004)
		mark.mesh = bm
		var mm := StandardMaterial3D.new()
		mm.albedo_color = Color(0.95, 0.95, 0.95)
		mm.emission_enabled = true
		mm.emission = Color(1, 1, 1)
		mm.emission_energy_multiplier = 0.4
		mark.material_override = mm
		mark.position = Vector3(0, 0.035, 0.107)
		_knob.add_child(mark)


## Every button's triangles (all corners inside its outline, in front of the case) are taken out of the
## model's meshes into a node of its own – pushed in a few millimetres when it is pressed.
func _split_buttons() -> void:
	var g := 0.006
	for n in _radio.find_children("radio_*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var nm := String(mi.name)
		if nm.contains("display") or nm.contains("glass") or not (mi.mesh is ArrayMesh) or mi.get_parent() != _radio and not _radio.is_ancestor_of(mi):
			continue
		if _knob and _knob.is_ancestor_of(mi):
			continue
		var rel: Transform3D = _radio.global_transform.affine_inverse() * mi.global_transform
		var mesh := mi.mesh as ArrayMesh
		var out := ArrayMesh.new()
		var pieces := {}          # button -> ArrayMesh
		for si in mesh.get_surface_count():
			var arr := mesh.surface_get_arrays(si)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			if idx.is_empty():
				idx = PackedInt32Array(range(v.size()))
			var keep := PackedInt32Array()
			var per := {}
			for t in range(0, idx.size(), 3):
				var p0: Vector3 = rel * v[idx[t]]
				var p1: Vector3 = rel * v[idx[t + 1]]
				var p2: Vector3 = rel * v[idx[t + 2]]
				var hit := ""
				if p0.z >= 0.0 and p1.z >= 0.0 and p2.z >= 0.0:
					for b in BUTTONS.keys() + SLIDERS.keys():
						if b == "slot":
							continue
						var r: Array = BUTTONS[b] if BUTTONS.has(b) else SLIDERS[b]
						var lo := Vector2(float(r[0]) - g, float(r[1]) - g)
						var hi := Vector2(float(r[2]) + g, float(r[3]) + g)
						var inside := true
						for p in [p0, p1, p2]:
							if p.x < lo.x or p.x > hi.x or p.y < lo.y or p.y > hi.y:
								inside = false
								break
						if inside:
							hit = b
							break
				var dst: PackedInt32Array = keep
				if hit != "":
					if not per.has(hit):
						per[hit] = PackedInt32Array()
					dst = per[hit]
				dst.append(idx[t])
				dst.append(idx[t + 1])
				dst.append(idx[t + 2])
				if hit != "":
					per[hit] = dst
				else:
					keep = dst
			var mat := mi.get_active_material(si)
			if keep.size() > 0:
				var a1 := arr.duplicate()
				a1[Mesh.ARRAY_INDEX] = keep
				out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a1)
				out.surface_set_material(out.get_surface_count() - 1, mat)
			for b in per:
				if not pieces.has(b):
					pieces[b] = ArrayMesh.new()
				var a2 := arr.duplicate()
				a2[Mesh.ARRAY_INDEX] = per[b]
				var pm: ArrayMesh = pieces[b]
				pm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a2)
				pm.surface_set_material(pm.get_surface_count() - 1, mat)
		if pieces.is_empty():
			continue
		mi.mesh = out
		for b in pieces:
			if not _btn_nodes.has(b):
				var bn := Node3D.new()
				bn.name = "Button_" + str(b)
				_radio.add_child(bn)
				_btn_nodes[b] = bn
			var pmi := MeshInstance3D.new()
			pmi.mesh = pieces[b]
			pmi.material_override = mi.material_override
			(_btn_nodes[b] as Node3D).add_child(pmi)
			pmi.transform = rel


## The orange ring round the knob: lit as far round as the volume goes.
func _setup_arc() -> void:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform vec2 centre;
uniform float lit = 0.5;
uniform float from_deg = 225.0;
uniform float span = 270.0;
uniform vec4 col : source_color = vec4(1.0, 0.45, 0.08, 1.0);
uniform float on = 1.0;
varying vec3 p;
void vertex() { p = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 d = p.xy - centre;
	float a = degrees(atan(d.y, d.x));
	float cw = mod(from_deg - a + 720.0, 360.0);
	float k = (cw <= lit * span && on > 0.5) ? 1.0 : 0.12;
	if (cw > span) { k = 0.12; }
	ALBEDO = col.rgb * k * 2.2;
}
"""
	_arc_mat = ShaderMaterial.new()
	_arc_mat.shader = sh
	for n in _radio.find_children("radio_emissives*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var rel: Transform3D = _radio.global_transform.affine_inverse() * mi.global_transform
		var mesh := mi.mesh as ArrayMesh
		if mesh == null:
			continue
		var out := ArrayMesh.new()
		var ring := ArrayMesh.new()
		for si in mesh.get_surface_count():
			var arr := mesh.surface_get_arrays(si)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			if idx.is_empty():
				idx = PackedInt32Array(range(v.size()))
			var keep := PackedInt32Array()
			var take := PackedInt32Array()
			for t in range(0, idx.size(), 3):
				var c: Vector3 = rel * ((v[idx[t]] + v[idx[t + 1]] + v[idx[t + 2]]) / 3.0)
				var r := Vector2(c.x, c.y).distance_to(KNOB_C)
				if r < 0.1:
					take.append_array([idx[t], idx[t + 1], idx[t + 2]])
				else:
					keep.append_array([idx[t], idx[t + 1], idx[t + 2]])
			var a1 := arr.duplicate()
			a1[Mesh.ARRAY_INDEX] = keep
			if keep.size() > 0:
				out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a1)
				out.surface_set_material(out.get_surface_count() - 1, mi.get_active_material(si))
			if take.size() > 0:
				var a2 := arr.duplicate()
				a2[Mesh.ARRAY_INDEX] = take
				ring.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a2)
		mi.mesh = out
		if ring.get_surface_count() > 0:
			var rm := MeshInstance3D.new()
			rm.mesh = ring
			rm.material_override = _arc_mat
			_radio.add_child(rm)
			rm.transform = rel


## The cassette for the slot's animation (lying flat, its open edge first).
func _build_tape() -> void:
	_tape_node = Node3D.new()
	_tape_node.visible = false
	_radio.add_child(_tape_node)
	var shell := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.33, 0.04, 0.21)
	shell.mesh = bm
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.1, 0.1, 0.12)
	sm.roughness = 0.4
	shell.material_override = sm
	_tape_node.add_child(shell)
	var label := MeshInstance3D.new()
	var lm := BoxMesh.new()
	lm.size = Vector3(0.28, 0.002, 0.11)
	label.mesh = lm
	label.position = Vector3(0, 0.021, 0.02)
	var lmat := StandardMaterial3D.new()
	lmat.albedo_color = Color(0.9, 0.15, 0.1)
	label.material_override = lmat
	label.name = "Label"
	_tape_node.add_child(label)
	for rx in [-0.07, 0.07]:
		var hub := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.022
		cm.bottom_radius = 0.022
		cm.height = 0.003
		hub.mesh = cm
		var hm := StandardMaterial3D.new()
		hm.albedo_color = Color(0.92, 0.92, 0.9)
		hub.material_override = hm
		hub.position = Vector3(rx, 0.022, 0.02)
		_tape_node.add_child(hub)


## The tape goes in (with its label's colour) and starts playing.
func insert(id: String) -> void:
	var t: Dictionary = Radio.tapes().get(id, {})
	var lab := _tape_node.get_node("Label") as MeshInstance3D
	(lab.material_override as StandardMaterial3D).albedo_color = t.get("color", Color(0.9, 0.15, 0.1))
	_tape_anim = 0.0
	_tape_dir = 1
	_tape_node.visible = true
	Radio.click_sound(true)
	get_tree().create_timer(0.55).timeout.connect(func(): Radio.insert_tape(id))


func _eject() -> void:
	if Radio.tape == "":
		Radio.flash("NO TAPE", 1.2)
		return
	var t: Dictionary = Radio.tapes().get(Radio.tape, {})
	var lab := _tape_node.get_node("Label") as MeshInstance3D
	(lab.material_override as StandardMaterial3D).albedo_color = t.get("color", Color(0.9, 0.15, 0.1))
	_tape_anim = 0.0
	_tape_dir = -1
	_tape_node.visible = true
	Radio.click_sound(true)
	Radio.eject()


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_t += delta
	if floating:
		# (gently: a little sway, it has to stay easy to hit)
		_pivot.rotation = Vector3(0.05 + sin(_t * 0.37) * 0.015, sin(_t * 0.5) * 0.04, sin(_t * 0.29) * 0.004)
		_pivot.position.y = sin(_t * 0.8) * 0.006
	else:
		_pivot.rotation = Vector3(0.06, 0.0, 0.0)
	# the knob and its ring follow the volume
	if _knob:
		var ang := deg_to_rad(ARC_FROM - Radio.volume * ARC_SPAN - 90.0)
		_knob.rotation.z = ang
	_arc_mat.set_shader_parameter("centre", _arc_centre())
	_arc_mat.set_shader_parameter("lit", Radio.volume)
	_arc_mat.set_shader_parameter("on", 1.0 if Radio.on else 0.0)
	# the TREB / BASS thumbs where their values are
	for k in SLIDERS:
		if _btn_nodes.has(k):
			(_btn_nodes[k] as Node3D).position.x = (Radio.bass if k == "bass" else Radio.treble) * SLIDE_R
	# pressed buttons: in, and back out again
	for b in _btn_press.keys():
		var left: float = _btn_press[b] - delta
		var node: Node3D = _btn_nodes.get(b, _knob if b == "knob" else null)
		if left <= 0.0:
			_btn_press.erase(b)
			if node:
				node.position.z = 0.0 if b != "knob" else 0.0
			continue
		_btn_press[b] = left
		if node:
			var k := 1.0 - left / PRESS_TIME          # 0 → 1
			var depth := sin(minf(k * 2.2, 1.0) * PI * 0.5) * (1.0 - smoothstep(0.55, 1.0, k))
			node.position.z = -PRESS_DEPTH * depth * (1.6 if b == "knob" else 1.0)
	# the press flash fades
	if _flash.visible:
		_flash_t -= delta
		(_flash.material_override as StandardMaterial3D).albedo_color.a = clampf(_flash_t / 0.18, 0.0, 1.0) * 0.6
		if _flash_t <= 0.0:
			_flash.visible = false
	# the cassette sliding in / out of the slot
	if _tape_dir != 0:
		_tape_anim += delta / 0.6
		var k := clampf(_tape_anim, 0.0, 1.0)
		var e := k * k * (3.0 - 2.0 * k)
		var z_out := 0.42
		var z_in := -0.2
		var z := lerpf(z_out, z_in, e) if _tape_dir > 0 else lerpf(z_in, z_out + 0.1, e)
		_tape_node.position = Vector3(-0.107, 0.398, z)
		_tape_node.rotation = Vector3(0.0, 0.0, 0.0)
		if k >= 1.0:
			_tape_dir = 0
			_tape_node.visible = false


## The ring's centre in world space of the little scene (the shader works in world coordinates).
func _arc_centre() -> Vector2:
	var p := _radio.global_transform * Vector3(KNOB_C.x, KNOB_C.y, 0.035)
	return Vector2(p.x, p.y)


## Where the mouse points on the radio's face (model space x, y), or null.
func _face_point(pos: Vector2):
	var vp_pos := pos * (Vector2(_vp.size) / size)
	var o := _cam.project_ray_origin(vp_pos)
	var d := _cam.project_ray_normal(vp_pos)
	var inv := _radio.global_transform.affine_inverse()
	var lo := inv * o
	var ld := (inv.basis * d).normalized()
	if absf(ld.z) < 1e-4:
		return null
	var t := (FRONT_Z - lo.z) / ld.z
	if t < 0.0:
		return null
	var hit := lo + ld * t
	if hit.x < -0.72 or hit.x > 0.72 or hit.y < 0.07 or hit.y > 0.5:
		return null
	return Vector2(hit.x, hit.y)


func _button_at(pos: Vector2) -> String:
	var fp = _face_point(pos)
	if fp == null:
		return ""
	var p: Vector2 = fp
	if p.distance_to(KNOB_C) < KNOB_R + 0.012:
		return "knob"
	for k in SLIDER_TRACKS:
		var r: Array = SLIDER_TRACKS[k]
		if p.x >= float(r[0]) and p.x <= float(r[2]) and p.y >= float(r[1]) and p.y <= float(r[3]):
			return k
	for b in BUTTONS:
		var r: Array = BUTTONS[b]
		if p.x >= float(r[0]) and p.x <= float(r[2]) and p.y >= float(r[1]) and p.y <= float(r[3]):
			return b
	return "face"


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _slider != "":
			_slide_to(mm.position)
			accept_event()
			return
		if _drag:
			var dv := (_drag_from.y - mm.position.y + mm.position.x - _drag_from.x) / 160.0
			if absf(mm.position.y - _drag_from.y) + absf(mm.position.x - _drag_from.x) > 4.0:
				_drag_moved = true
			if _drag_moved:
				Radio.set_volume(_drag_vol + dv)
			accept_event()
			return
		_hover = _button_at(mm.position)
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if _hover != "" and _hover != "face" else Control.CURSOR_ARROW
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		var b := _button_at(mb.position)
		if b == "":
			return      # past the radio: the click goes on to what is behind
		var wheel := 0.0
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			wheel = 1.0
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			wheel = -1.0
		if wheel != 0.0:
			if SLIDERS.has(b):
				# over a slider: that one, a step at a time
				Radio.set_tone(b, (Radio.bass if b == "bass" else Radio.treble) + wheel / 6.0)
			else:
				Radio.set_volume(Radio.volume + wheel / 30.0)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if not mb.pressed and _slider != "":
				_slider = ""
				accept_event()
				return
			if mb.pressed:
				if SLIDERS.has(b):
					_slider = b
					Radio.click_sound()
					_slide_to(mb.position)
				elif b == "knob":
					_drag = true
					_drag_from = mb.position
					_drag_vol = Radio.volume
					_drag_moved = false
				else:
					_press(b)
			elif _drag:
				_drag = false
				if not _drag_moved:
					_press("knob")
			accept_event()


## The dragged TREB / BASS thumb under the mouse (along its track).
func _slide_to(pos: Vector2) -> void:
	var fp = _face_point(pos)
	if fp == null:
		return
	var v := clampf(((fp as Vector2).x - SLIDE_C) / SLIDE_R, -1.0, 1.0)
	# notches: 13 steps (-6 … +6)
	v = roundf(v * 6.0) / 6.0
	if not is_equal_approx(v, Radio.bass if _slider == "bass" else Radio.treble):
		Radio.set_tone(_slider, v)


## A button pressed: it goes in, clicks, does its thing.
func _press(b: String) -> void:
	if b == "face":
		return
	# (the button itself goes in – no light)
	if b != "slot":
		_btn_press[b] = PRESS_TIME
	Radio.click_sound()
	match b:
		"knob":
			Radio.toggle_power()
		"eject":
			_eject()
		"band":
			Radio.next_band()
		"tape":
			Radio.tape_button()
		"up":
			Radio.seek(1)
		"dn":
			Radio.seek(-1)
		"tune":
			if Radio.on:
				Radio.toggle_freq()
		"time":
			if Radio.on:
				_display.show_clock()
		"api":
			if Radio.on:
				Radio.toggle_api()
		"tinfo":
			if Radio.on:
				Radio.flash(Radio.title.to_upper().left(12) if Radio.title != "" else "NO INFO", 2.5)
		"slot":
			if Radio.tape != "":
				Radio.tape_button()
			else:
				tape_list_wanted.emit()
		_:
			if b.begins_with("p"):
				Radio.pick_preset(int(b.substr(1)) - 1)

extends Node3D
## Behind the main-menu workshop: a short driveway from the shutter down to a street that runs past
## (left to right) – a kerb and pavement on the near side (dropped at the driveway), beyond the street
## the asphalt fades into a dark wet verge without a seam, grey-green verges, trees and
## bushes well back across the road, a few hydrants and one dim, flickering sodium street lamp;
## grey fog swallows the rest. The roadway is the model's own wet forecourt asphalt left uncovered
## (so street, driveway and yard are one surface).

const TreeFactory = preload("res://scripts/world/tree_factory.gd")
const TexKit = preload("res://scripts/util/tex_kit.gd")
const MeshKit = preload("res://scripts/util/mesh_kit.gd")
const FlowerBeds = preload("res://scripts/world/city/flower_beds.gd")
const TrafficCars = preload("res://scripts/world/traffic_cars.gd")

## Traffic going by on the street: a few cars each way, headlights on, looping round from end to end.
const TRAFFIC_PER_LANE := 3
const TRAFFIC_SPAN := 300.0      # the loop along x (the street plus a bit out of sight either end)
var _traffic                     # traffic_cars.gd (draws them)
var _tcars: Array = []           # {lane: ±1, x, v, want, model, paint, odo, spot}
var _trng := RandomNumberGenerator.new()

const STREET_Z := -27.0    # the street's centre line (the shutter is at z = -6.5)
const LENGTH := 260.0      # along x, centred on the driveway
const HALF := 3.6          # half the carriageway
const WALK := 2.2          # pavement width
const KERB := 0.14
const STEP := 4.0
const DRIVE := 4.4         # half width of the driveway (and the dropped kerb)
const YARD_Z := -12.0      # the yard in front of the shutter ends here

var _lamp_light: SpotLight3D
var _lamp_glow: OmniLight3D
var _lamp_mat: StandardMaterial3D
var _flick := 0.0
var _flick_t := 0.0


## The street: s runs along it from its left end; lateral + is the near side (towards the garage).
static func centre(s: float) -> Vector3:
	return Vector3(s - LENGTH * 0.5, 0.0, STREET_Z)


static func side(_s: float) -> Vector3:
	return Vector3(0, 0, 1)


func at(s: float, lateral: float, y := 0.0) -> Vector3:
	return centre(s) + side(s) * lateral + Vector3(0, y, 0)


func build(asphalt: Material) -> void:
	var walk_mat := TexKit.ground_material(Color(0.075, 0.075, 0.08), Color(0.09, 0.09, 0.095), Color(0.07, 0.07, 0.075), 0.7, 1.25)
	var grass_mat := TexKit.ground_material(Color(0.07, 0.08, 0.07), Color(0.085, 0.09, 0.075), Color(0.09, 0.085, 0.07), 0.9)
	var line_mat := TexKit.std(Color(0.85, 0.84, 0.8), 0.45)
	var mid := LENGTH * 0.5
	# grass: either side of the driveway between yard and pavement, and all beyond the far pavement
	var near_edge := STREET_Z + HALF + WALK
	_ground(Rect2(-300.0, near_edge, 300.0 - DRIVE - 0.4, YARD_Z - near_edge), grass_mat)
	# (right of the driveway the yard's black asphalt goes on to the fence; the flowers sit on it)
	_ground(Rect2(DRIVE + 0.4, near_edge, 30.0 - DRIVE - 0.4, YARD_Z - near_edge), asphalt if asphalt else grass_mat)
	_ground(Rect2(30.0, near_edge, 270.0, YARD_Z - near_edge), grass_mat)
	# beyond the street no pavement: the ground fades from the wet asphalt into dark grass (no seam)
	_far_ground(STREET_Z - HALF + 0.3)
	# pavements with their kerbs (the near one dropped and open at the driveway)
	for sg in [-1.0, 1.0]:
		var spans: Array = [] if sg < 0.0 else [[0.0, mid - DRIVE], [mid + DRIVE, LENGTH]]
		for sp in spans:
			_wall(sg * HALF, 0.0, KERB, sp[0], sp[1], walk_mat, false)
			_strip(sg * HALF, sg * (HALF + WALK), KERB, sp[0], sp[1], walk_mat)
			_wall(sg * (HALF + WALK), 0.0, KERB, sp[0], sp[1], walk_mat, true)
		# edge lines
		var lines: Array = [[0.0, LENGTH]] if sg < 0.0 else [[0.0, mid - DRIVE - 1.0], [mid + DRIVE + 1.0, LENGTH]]
		# (over the yard's asphalt, which lies 2.6 cm up)
		for ln in lines:
			_strip(sg * (HALF - 0.32), sg * (HALF - 0.2), 0.04, ln[0], ln[1], line_mat)
	# the dropped kerb: a low ramp of pavement across the driveway mouth
	_strip(HALF, HALF + WALK, 0.03, mid - DRIVE, mid + DRIVE, walk_mat)
	var s := 3.0
	# the middle: a double line, broken (dashes) where cars turn in and out of the driveway
	for off in [-0.13, 0.13]:
		for sp in [[0.0, mid - DRIVE - 6.0], [mid + DRIVE + 6.0, LENGTH]]:
			_strip(off - 0.06, off + 0.06, 0.04, sp[0], sp[1], line_mat)
	while s < LENGTH:
		if s > mid - DRIVE - 7.0 and s < mid + DRIVE + 6.0:
			_strip(-0.07, 0.07, 0.04, s, minf(s + 3.0, LENGTH), line_mat)
		s += 6.0
	# where the driveway meets the street: a give-way line of short dashes
	var g := mid - DRIVE
	while g < mid + DRIVE:
		_strip(HALF - 0.65, HALF - 0.4, 0.04, g, minf(g + 0.5, mid + DRIVE), line_mat)
		g += 0.9
	_plant()
	_yard_garden()
	_fence()
	_gate()
	_brick_wall()
	_traffic_setup()
	_lamp(mid + 7.0, HALF + 0.55)
	_street_props()


const FAR_GROUND := """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled;
uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float edge_z = -30.0;     // where the street ends (the far ground fades in beyond it)
uniform float fade = 9.0;
varying vec3 wpos;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	float n1 = texture(noise_tex, wpos.xz * 0.05).r;
	float n2 = texture(noise_tex, wpos.xz * 0.43).r;
	float d = edge_z - wpos.z;
	// black asphalt on out to the trees (only a faint sheen: a shiny wet surface mirrored the pale sky
	// and turned it grey)
	vec3 asphalt = vec3(0.035, 0.035, 0.038) * (0.8 + 0.4 * n2) * (0.9 + 0.2 * n1);
	ALBEDO = asphalt;
	ROUGHNESS = mix(0.6, 0.9, smoothstep(0.35, 0.6, n1));
	SPECULAR = 0.25;
	// a ragged edge that fades in over a few metres
	ALPHA = smoothstep(0.0, fade, d + (n2 - 0.5) * 3.0 + (n1 - 0.5) * 4.0);
}
"""


func _far_ground(edge_z: float) -> void:
	var sh := Shader.new()
	sh.code = FAR_GROUND
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("noise_tex", TexKit.noise_texture(91, 0.03, false, 256))
	m.set_shader_parameter("edge_z", edge_z)
	var pm := PlaneMesh.new()
	pm.size = Vector2(600, 420)
	var mi := MeshInstance3D.new()
	mi.mesh = pm
	mi.material_override = m
	# its near end lies on the asphalt's edge (fully clear there)
	mi.position = Vector3(0, 0.015, edge_z - 210.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _ground(r: Rect2, mat: Material) -> void:
	var pm := PlaneMesh.new()
	pm.size = r.size.abs()
	var mi := MeshInstance3D.new()
	mi.mesh = pm
	mi.material_override = mat
	var c := r.abs().get_center()
	mi.position = Vector3(c.x, 0.02, c.y)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


## A flat strip between two lateral offsets, from s0 to s1 (UVs in metres, world-aligned).
func _strip(l0: float, l1: float, y: float, s0: float, s1: float, mat: Material) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var s := s0
	while s < s1 - 0.001:
		var e := minf(s + STEP, s1)
		var a0 := at(s, minf(l0, l1), y)
		var a1 := at(s, maxf(l0, l1), y)
		var b0 := at(e, minf(l0, l1), y)
		var b1 := at(e, maxf(l0, l1), y)
		# both windings: whichever is the front, it faces up
		for p in [a0, b0, b1, a0, b1, a1, a0, b1, b0, a0, a1, b1]:
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(p.x, p.z))
			st.add_vertex(p)
		s = e
	_add_mesh(st, mat)


## An upright face along the road (a kerb), lit as facing the centre (or away with `out`).
func _wall(l: float, y0: float, y1: float, s0: float, s1: float, mat: Material, out: bool) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var s := s0
	while s < s1 - 0.001:
		var e := minf(s + STEP, s1)
		var a0 := at(s, l, y0)
		var a1 := at(s, l, y1)
		var b0 := at(e, l, y0)
		var b1 := at(e, l, y1)
		var n := side(s) * (-signf(l) if not out else signf(l))
		for p in [a0, b1, b0, a0, a1, b1, a0, b0, b1, a0, b1, a1]:
			st.set_normal(n)
			st.set_uv(Vector2(p.x + p.z, p.y))
			st.add_vertex(p)
		s = e
	_add_mesh(st, mat)


func _add_mesh(st: SurfaceTool, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


## Trees well back across the street (and some far off to the sides on the near side), bushes
## along the far verge – dark and grey-green in the rain, the fog takes most of their colour.
func _plant() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2207
	var trees := [TreeFactory.deciduous(11, 0.45), TreeFactory.deciduous(23, 0.45), TreeFactory.oak(5, 0.45)]
	var far_trees := [TreeFactory.deciduous(41, 0.3), TreeFactory.oak(17, 0.3)]
	var bushes := [TreeFactory.bush(3), TreeFactory.bush(8), TreeFactory.shrub(4)]
	var items := {}
	for m in trees + far_trees + bushes:
		items[m] = []
	var x := -LENGTH * 0.5 + rng.randf_range(0.0, 6.0)
	while x < LENGTH * 0.5:
		# a loose row 9-16 m behind the far pavement, a second one further back
		items[trees[rng.randi() % trees.size()]].append(_xf_at(Vector3(x, 0.02, STREET_Z - HALF - WALK - rng.randf_range(9.0, 16.0)), rng, 0.9, 1.2))
		items[far_trees[rng.randi() % far_trees.size()]].append(_xf_at(Vector3(x + rng.randf_range(-4, 4), 0.02, STREET_Z - HALF - WALK - rng.randf_range(24.0, 45.0)), rng, 1.0, 1.4))
		if rng.randf() < 0.6:
			items[bushes[rng.randi() % bushes.size()]].append(_xf_at(Vector3(x + rng.randf_range(-3, 3), 0.02, STREET_Z - HALF - WALK - rng.randf_range(2.0, 6.0)), rng, 0.7, 1.2))
		x += rng.randf_range(8.0, 13.0)
	# near side: only far out to the left and right of the yard
	for sg in [-1.0, 1.0]:
		var nx := 22.0
		while nx < 90.0:
			items[trees[rng.randi() % trees.size()]].append(_xf_at(Vector3(sg * nx, 0.02, rng.randf_range(STREET_Z + HALF + WALK + 4.0, YARD_Z - 3.0)), rng, 0.85, 1.15))
			nx += rng.randf_range(10.0, 16.0)
	for m in items:
		_instances(m, items[m], rng)


## A metal palisade fence closing the yard off from the street (along the near pavement).
func _fence() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var z := STREET_Z + HALF + WALK + 0.5
	var x0 := -42.0
	var x1 := 42.0
	var h := 1.7
	var col := Color(0.16, 0.16, 0.17)
	# posts, two rails, pickets with pointed tops
	var x := x0
	var gap := DRIVE + 0.25              # the driveway's opening (closed by the sliding gate)
	while x <= x1 + 0.01:
		if absf(x) > gap:
			MeshKit.box(st, Transform3D(Basis.IDENTITY, Vector3(x, h * 0.5 + 0.05, z)), Vector3(0.09, h + 0.1, 0.09), col)
		x += 2.5
	for sg in [-1.0, 1.0]:
		# the posts either side of the opening, heavier
		MeshKit.box(st, Transform3D(Basis.IDENTITY, Vector3(sg * gap, h * 0.5 + 0.1, z)), Vector3(0.14, h + 0.2, 0.14), col)
	for ry in [0.25, h - 0.2]:
		for span in [[x0, -gap], [gap, x1]]:
			MeshKit.box(st, Transform3D(Basis.IDENTITY, Vector3((span[0] + span[1]) * 0.5, ry, z)), Vector3(span[1] - span[0], 0.05, 0.04), col)
	x = x0 + 0.08
	while x < x1:
		if absf(x) < gap + 0.05:
			x += 0.14
			continue
		MeshKit.box(st, Transform3D(Basis.IDENTITY, Vector3(x, h * 0.5, z)), Vector3(0.025, h, 0.025), col)
		MeshKit.box(st, Transform3D(Basis(Vector3.BACK, PI * 0.25), Vector3(x, h + 0.01, z)), Vector3(0.04, 0.04, 0.03), col)
		x += 0.14
	st.generate_normals()
	var m := TexKit.std(Color(0.16, 0.16, 0.17), 0.45, 0.7)
	var mi := MeshInstance3D.new()
	mi.name = "YardFence"
	mi.mesh = st.commit()
	mi.material_override = m
	add_child(mi)


## The driveway's sliding gate: a palisade panel on rollers along a ground rail, sliding to the right
## (seen from the garage) behind the fence; it opens and closes with the shutter (set_gate).
var _gate_node: Node3D
var _gate_closed_x := 0.0
var _gate_travel := 0.0


func _gate() -> void:
	var z := STREET_Z + HALF + WALK + 0.5 + 0.16     # just inside the fence line
	var w := (DRIVE + 0.25) * 2.0 + 0.3
	var h := 1.75
	var col := Color(0.16, 0.16, 0.17)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# frame, a diagonal brace, pickets
	for ry in [0.12, h - 0.06]:
		MeshKit.box(st, Transform3D(Basis.IDENTITY, Vector3(0, ry, 0)), Vector3(w, 0.08, 0.06), col)
	for ex in [-w * 0.5 + 0.04, w * 0.5 - 0.04]:
		MeshKit.box(st, Transform3D(Basis.IDENTITY, Vector3(ex, h * 0.5 + 0.05, 0)), Vector3(0.08, h - 0.1, 0.06), col)
	MeshKit.box(st, Transform3D(Basis.IDENTITY, Vector3(0, h * 0.5, 0)), Vector3(w, 0.05, 0.04), col)
	var px := -w * 0.5 + 0.12
	while px < w * 0.5 - 0.08:
		MeshKit.box(st, Transform3D(Basis.IDENTITY, Vector3(px, h * 0.5 + 0.1, 0)), Vector3(0.025, h - 0.1, 0.025), col)
		MeshKit.box(st, Transform3D(Basis(Vector3.BACK, PI * 0.25), Vector3(px, h + 0.06, 0)), Vector3(0.04, 0.04, 0.03), col)
		px += 0.14
	# the rollers underneath
	for rx in [-w * 0.35, w * 0.35]:
		MeshKit.box(st, Transform3D(Basis.IDENTITY, Vector3(rx, 0.05, 0)), Vector3(0.14, 0.1, 0.08), Color(0.3, 0.3, 0.3))
	st.generate_normals()
	_gate_node = MeshInstance3D.new()
	_gate_node.name = "YardGate"
	(_gate_node as MeshInstance3D).mesh = st.commit()
	(_gate_node as MeshInstance3D).material_override = TexKit.std(col, 0.45, 0.7)
	add_child(_gate_node)
	_gate_closed_x = 0.0
	_gate_travel = w + 0.2
	_gate_node.position = Vector3(_gate_closed_x, 0.0, z)
	# the ground rail it runs on, the guide post at its far end and the motor box by the gate post
	var fix := SurfaceTool.new()
	fix.begin(Mesh.PRIMITIVE_TRIANGLES)
	var r0 := -w * 0.5
	var r1 := w * 1.5 + 0.4
	MeshKit.box(fix, Transform3D(Basis.IDENTITY, Vector3((r0 + r1) * 0.5, 0.025, z)), Vector3(r1 - r0, 0.03, 0.06), Color(0.35, 0.35, 0.36))
	MeshKit.box(fix, Transform3D(Basis.IDENTITY, Vector3(r1, 1.0, z + 0.12)), Vector3(0.1, 2.0, 0.1), col)
	MeshKit.box(fix, Transform3D(Basis.IDENTITY, Vector3(DRIVE + 0.6, 0.3, z + 0.32)), Vector3(0.32, 0.45, 0.24), Color(0.55, 0.55, 0.53))
	fix.generate_normals()
	var fm := MeshInstance3D.new()
	fm.mesh = fix.commit()
	fm.material_override = TexKit.std(Color(1, 1, 1), 0.5, 0.4)
	add_child(fm)


## 0 = closed, 1 = right open (it follows the shutter).
func set_gate(open: float) -> void:
	if _gate_node:
		_gate_node.position.x = _gate_closed_x + _gate_travel * clampf(open, 0.0, 1.0)


## A brick wall along the far side of the street (the trees show over it).
func _brick_wall() -> void:
	var z := STREET_Z - HALF - 0.9
	var h := 2.3
	var len := LENGTH
	var m := StandardMaterial3D.new()
	var tex := _brick_textures()
	m.albedo_texture = tex[0]
	m.normal_enabled = true
	m.normal_texture = tex[1]
	m.normal_scale = 0.9
	m.roughness = 0.9
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3(1.0 / 0.96, 1.0, 1.0 / 0.96)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	MeshKit.box(st, Transform3D(Basis.IDENTITY, Vector3(0, h * 0.5, z)), Vector3(len, h, 0.3))
	# piers every 6 m
	var x := -len * 0.5
	while x <= len * 0.5:
		MeshKit.box(st, Transform3D(Basis.IDENTITY, Vector3(x, h * 0.5 + 0.05, z)), Vector3(0.5, h + 0.1, 0.45))
		x += 6.0
	st.generate_normals()
	var wall := MeshInstance3D.new()
	wall.name = "BrickWall"
	wall.mesh = st.commit()
	wall.material_override = m
	add_child(wall)
	# a concrete coping on top
	var cap := MeshKit.box_node(Vector3(len, 0.08, 0.42), TexKit.std(Color(0.32, 0.31, 0.3), 0.8), Vector3(0, h + 0.04, z))
	add_child(cap)
	_graffiti(z + 0.16, h)


## Sprayed tags on the street side of the brick wall: big outlined letters in a few colours, some
## tilted, with paint blobs round them.
const TAGS := ["DRIFT", "KAIDO", "JDM", "MIDNIGHT", "R34", "SKRRT", "NO GRIP", "TOUGE", "NOS", "BOOST", "旋", "夜"]
const TAG_COLS := [[Color(1.0, 0.25, 0.6), Color(0.1, 0.05, 0.2)], [Color(0.2, 0.9, 1.0), Color(0.05, 0.1, 0.35)],
	[Color(1.0, 0.85, 0.1), Color(0.55, 0.1, 0.05)], [Color(0.55, 1.0, 0.25), Color(0.05, 0.2, 0.1)],
	[Color(0.95, 0.95, 0.95), Color(0.85, 0.1, 0.1)], [Color(0.75, 0.4, 1.0), Color(0.1, 0.0, 0.15)]]


func _graffiti(z: float, h: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 6611
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Impact", "Arial Black", "DejaVu Sans", "Noto Sans CJK JP", "sans-serif"])
	font.font_weight = 900
	font.font_italic = true
	var x := -60.0
	while x < 60.0:
		var t := Label3D.new()
		t.text = TAGS[rng.randi() % TAGS.size()]
		var cols: Array = TAG_COLS[rng.randi() % TAG_COLS.size()]
		t.font = font
		t.font_size = 160
		t.pixel_size = rng.randf_range(0.0045, 0.0075)
		t.modulate = cols[0]
		t.outline_modulate = cols[1]
		t.outline_size = 34
		t.shaded = true
		t.double_sided = false
		t.alpha_cut = Label3D.ALPHA_CUT_DISCARD
		t.position = Vector3(x + rng.randf_range(-1.0, 1.0), rng.randf_range(0.7, h - 0.8), z)
		t.rotation = Vector3(0, 0, rng.randf_range(-0.18, 0.18))
		t.scale = Vector3(rng.randf_range(1.0, 1.35), 1.0, 1.0)
		add_child(t)
		x += rng.randf_range(5.0, 9.0)


## Albedo + normal map of a running-bond brick wall: 4 bricks × 14 courses per tile (0.96 × 1 m).
static func _brick_textures() -> Array:
	var bw := 60
	var bh := 18
	var w := bw * 4
	var hh := bh * 14
	var img := Image.create(w, hh, false, Image.FORMAT_RGBA8)
	var bump := Image.create(w, hh, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5150
	var tones := []
	for i in 4 * 14 + 8:
		var t := rng.randf_range(-0.07, 0.07)
		tones.append(Color(0.42 + t, 0.17 + t * 0.6 + rng.randf_range(-0.02, 0.02), 0.12 + t * 0.4))
	for y in hh:
		var row := y / bh
		var off := (bw / 2) if row % 2 == 1 else 0
		for x in w:
			var xx := (x + off) % w
			var col := xx / bw
			var mortar := (y % bh) < 2 or (xx % bw) < 2
			var c: Color
			if mortar:
				c = Color(0.36, 0.35, 0.33) * rng.randf_range(0.9, 1.05)
			else:
				c = (tones[row * 4 + col] as Color) * rng.randf_range(0.88, 1.08)
			img.set_pixel(x, y, c)
			var hv := 0.0 if mortar else 0.8 + rng.randf_range(-0.08, 0.08)
			bump.set_pixel(x, y, Color(hv, hv, hv))
	bump.bump_map_to_normal_map(6.0)
	img.generate_mipmaps()
	bump.generate_mipmaps()
	return [ImageTexture.create_from_image(img), ImageTexture.create_from_image(bump)]


## Beside the driveway: a row of big bushes on the left, a flower field on the right.
func _yard_garden() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4411
	var near_edge := STREET_Z + HALF + WALK
	var bushes := [TreeFactory.bush(3), TreeFactory.bush(8), TreeFactory.bush(12)]
	var items := {}
	for m in bushes:
		items[m] = []
	var x := -DRIVE - 2.2
	while x > -17.0:
		var z := rng.randf_range(YARD_Z - 2.5, YARD_Z - 1.2)
		items[bushes[rng.randi() % bushes.size()]].append(_xf_at(Vector3(x, 0.03, z), rng, 1.3, 1.8))
		if rng.randf() < 0.6:
			items[bushes[rng.randi() % bushes.size()]].append(_xf_at(Vector3(x + rng.randf_range(-0.6, 0.6), 0.03, z - rng.randf_range(1.6, 3.0)), rng, 1.0, 1.4))
		x -= rng.randf_range(1.6, 2.4)
	for m in items:
		_garden_instances(m, items[m], rng)
	var beds := FlowerBeds.new()
	beds.name = "FlowerField"
	add_child(beds)
	var w := 12.0
	var d := (YARD_Z - 1.0) - (near_edge + 1.0)
	beds.add_bed(Vector3(DRIVE + 2.6 + w * 0.5, 0.0, (YARD_Z - 1.0 + near_edge + 1.0) * 0.5), Vector2(w, absf(d)), 0.0, rng)
	beds.build(null)


## Garden bushes: a fresher green than the dark trees out in the rain.
func _garden_instances(mesh: Mesh, xfs: Array, rng: RandomNumberGenerator) -> void:
	if xfs.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])
		var g := rng.randf_range(0.7, 0.9)
		mm.set_instance_custom_data(i, Color(g * 0.8, g, g * 0.75, 1.0))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	add_child(mmi)


func _xf_at(p: Vector3, rng: RandomNumberGenerator, k0: float, k1: float) -> Transform3D:
	var k := rng.randf_range(k0, k1)
	return Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(k, k, k)), p)


func _instances(mesh: Mesh, xfs: Array, rng: RandomNumberGenerator) -> void:
	if xfs.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])
		# dark and grey-green: night, rain, fog
		var g := rng.randf_range(0.38, 0.5)
		mm.set_instance_custom_data(i, Color(g * rng.randf_range(0.95, 1.05), g, g * rng.randf_range(0.95, 1.05), 1.0))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	add_child(mmi)


const PACK := "res://assets/props/street_pack/"
## The street prop pack (uploaded): where the garage's opening shows them – the yard, the driveway's
## mouth and the near pavement. [model, x, z, y (on the pavement or the ground), turn]
## (signs face +Z: towards the garage, i.e. the cars coming out of the driveway)
const PROPS := [
	["fire_hydrant_red", 7.4, -21.5, KERB, 0.4],
	["sign_street_names", -12.5, -21.8, KERB, 0.25],
	["traffic_light_overhead", -17.5, -21.8, KERB, PI * 0.5],
	["sign_speed_30", -22.0, -22.0, KERB, 0.0],
	["fire_hydrant_yellow", -6.2, -9.4, 0.0, -0.6],
	["sign_yield", 6.3, -13.0, 0.0, 0.0],
]

var _signals: Array = []     # [[red, amber, green] materials, light] per traffic light
var _signal_t := 0.0


func _street_props() -> void:
	for p in PROPS:
		var path: String = PACK + str(p[0]) + ".glb"
		if not ResourceLoader.exists(path):
			continue
		var scene := load(path) as PackedScene
		if scene == null:
			continue
		var n := scene.instantiate() as Node3D
		add_child(n)
		n.global_transform = Transform3D(Basis(Vector3.UP, float(p[4])), Vector3(float(p[1]), float(p[3]), float(p[2])))
		if str(p[0]).begins_with("traffic_light") or str(p[0]) == "pedestrian_signal":
			_signal_lenses(n)


## A traffic light's lenses get their own materials that light up in turn (red, green, amber), with
## a little coloured light in front of them.
func _signal_lenses(n: Node3D) -> void:
	var mats := {}
	var lens_pos := Vector3.ZERO
	for node in n.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		for si in mi.mesh.get_surface_count():
			var m := mi.get_active_material(si)
			if m == null or not m.resource_name.begins_with("lens_") or m.resource_name == "lens_off":
				continue
			var key := m.resource_name.trim_prefix("lens_")
			if not mats.has(key):
				var own := (m as BaseMaterial3D).duplicate() as BaseMaterial3D if m is BaseMaterial3D else StandardMaterial3D.new()
				own.emission_enabled = true
				mats[key] = own
			mi.set_surface_override_material(si, mats[key])
			lens_pos = mi.global_transform * mi.mesh.get_aabb().get_center()
	if mats.is_empty():
		return
	var l := OmniLight3D.new()
	l.omni_range = 3.5
	l.light_energy = 0.0
	add_child(l)
	l.global_position = lens_pos + Vector3(0, 0, 0.4)
	_signals.append([mats, l])
	_cycle_signals(0.0)


const SIGNAL_COLS := {"red": Color(1.0, 0.12, 0.08), "amber": Color(1.0, 0.6, 0.05), "green": Color(0.2, 1.0, 0.45)}


func _cycle_signals(t: float) -> void:
	# 9 s red, 7 s green, 2 s amber
	var ph := fmod(t, 18.0)
	var on := "red" if ph < 9.0 else ("green" if ph < 16.0 else "amber")
	for sg in _signals:
		var mats: Dictionary = sg[0]
		for key in mats:
			var m: BaseMaterial3D = mats[key]
			var lit: bool = key == on
			m.emission = SIGNAL_COLS.get(key, Color.WHITE)
			m.emission_energy_multiplier = 3.0 if lit else 0.05
		var l: OmniLight3D = sg[1]
		l.light_color = SIGNAL_COLS[on]
		l.light_energy = 0.6


## One old street lamp: a pole with an arm over the road and a weak orange sodium light.
func _lamp(s: float, l: float) -> void:
	var foot := at(s, l, KERB)
	var inward := -side(s) * signf(l)
	var root := Node3D.new()
	root.name = "StreetLamp"
	add_child(root)
	root.global_position = foot
	root.look_at(foot + inward, Vector3.UP)     # -Z towards the road
	var metal := TexKit.std(Color(0.16, 0.17, 0.18), 0.55, 0.6)
	var pole := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.06
	cyl.bottom_radius = 0.09
	cyl.height = 6.2
	pole.mesh = cyl
	pole.material_override = metal
	pole.position = Vector3(0, 3.1, 0)
	root.add_child(pole)
	var arm := MeshInstance3D.new()
	var bx := BoxMesh.new()
	bx.size = Vector3(0.08, 0.08, 1.6)
	arm.mesh = bx
	arm.material_override = metal
	arm.position = Vector3(0, 6.1, -0.75)
	root.add_child(arm)
	var head := MeshInstance3D.new()
	var hb := BoxMesh.new()
	hb.size = Vector3(0.28, 0.12, 0.55)
	head.mesh = hb
	head.material_override = metal
	head.position = Vector3(0, 6.02, -1.5)
	root.add_child(head)
	var lens := MeshInstance3D.new()
	var lb := BoxMesh.new()
	lb.size = Vector3(0.22, 0.02, 0.45)
	lens.mesh = lb
	_lamp_mat = TexKit.emissive(Color(1.0, 0.58, 0.25), 2.2)
	lens.material_override = _lamp_mat
	lens.position = Vector3(0, 5.95, -1.5)
	root.add_child(lens)
	_lamp_light = SpotLight3D.new()
	_lamp_light.light_color = Color(1.0, 0.6, 0.28)
	_lamp_light.light_energy = 1.6
	_lamp_light.spot_range = 13.0
	_lamp_light.spot_angle = 52.0
	_lamp_light.spot_attenuation = 0.8
	_lamp_light.position = Vector3(0, 5.9, -1.5)
	_lamp_light.rotation = Vector3(-PI * 0.5, 0, 0)
	root.add_child(_lamp_light)
	_lamp_glow = OmniLight3D.new()
	_lamp_glow.light_color = _lamp_light.light_color
	_lamp_glow.light_energy = 0.25
	_lamp_glow.omni_range = 4.0
	_lamp_glow.position = Vector3(0, 5.7, -1.5)
	root.add_child(_lamp_glow)


## The old lamp now and then flickers for a moment.
func _traffic_setup() -> void:
	_traffic = TrafficCars.new()
	_traffic.name = "StreetTraffic"
	add_child(_traffic)
	_traffic.setup(null)
	if not _traffic.ok:
		return
	_traffic.night_override = 1.0
	_trng.seed = 7071
	for lane in [-1.0, 1.0]:
		var x := _trng.randf_range(-TRAFFIC_SPAN * 0.5, 0.0)
		for k in TRAFFIC_PER_LANE:
			var c := {"lane": lane, "x": x, "v": 0.0, "want": 0.0, "model": 0, "paint": Color.WHITE, "odo": _trng.randf() * 50.0}
			_new_car(c)
			c["v"] = c["want"]
			# a headlight beam that lights the wet road in front of it
			var spot := SpotLight3D.new()
			spot.light_color = Color(1.0, 0.95, 0.85)
			spot.light_energy = 7.0
			spot.spot_range = 32.0
			spot.spot_angle = 28.0
			spot.spot_attenuation = 0.6
			spot.shadow_enabled = false
			add_child(spot)
			c["spot"] = spot
			var tail := OmniLight3D.new()
			tail.light_color = Color(1.0, 0.1, 0.05)
			tail.light_energy = 0.8
			tail.omni_range = 4.0
			add_child(tail)
			c["tail"] = tail
			_tcars.append(c)
			x += _trng.randf_range(45.0, 110.0)


## A fresh car for the loop: another model, another paint, its own pace.
func _new_car(c: Dictionary) -> void:
	var pick: Array = _traffic.pick(_trng)
	c["model"] = pick[0]
	c["paint"] = pick[1]
	c["want"] = _trng.randf_range(9.0, 15.0)


func _traffic_step(delta: float) -> void:
	if _traffic == null or not _traffic.ok:
		return
	for c in _tcars:
		var lane: float = c["lane"]
		var dir := -lane        # the near lane (+z side) runs towards -x, the far one towards +x
		# keep a gap to the one in front in the same lane
		var gap := 1e9
		var lead_v := 0.0
		for o in _tcars:
			if o == c or float(o["lane"]) != lane:
				continue
			var ahead := fposmod((float(o["x"]) - float(c["x"])) * dir, TRAFFIC_SPAN)
			if ahead < gap:
				gap = ahead
				lead_v = o["v"]
		var want: float = c["want"]
		if gap < 18.0:
			want = minf(want, lead_v * clampf((gap - 7.0) / 11.0, 0.0, 1.0))
		c["v"] = move_toward(float(c["v"]), want, delta * 3.0)
		var x: float = float(c["x"]) + dir * float(c["v"]) * delta
		# off one end: round again from the other, as a different car
		if x > TRAFFIC_SPAN * 0.5 or x < -TRAFFIC_SPAN * 0.5:
			x -= dir * TRAFFIC_SPAN
			_new_car(c)
		c["x"] = x
		c["odo"] = float(c["odo"]) + float(c["v"]) * delta
		var fwd := Vector3(dir, 0, 0)
		var xf := Transform3D(Basis.looking_at(fwd, Vector3.UP), Vector3(x, 0.03, STREET_Z + lane * HALF * 0.5))
		_traffic.add(int(c["model"]), xf, c["paint"], float(c["odo"]), float(c["v"]) < float(c["want"]) - 1.0, float(c["v"]))
		var half: float = _traffic.half_length(int(c["model"]))
		var spot: SpotLight3D = c["spot"]
		spot.global_transform = Transform3D(Basis.looking_at(fwd + Vector3(0, -0.12, 0), Vector3.UP), xf.origin + fwd * (half + 0.1) + Vector3(0, 0.7, 0))
		(c["tail"] as OmniLight3D).global_position = xf.origin - fwd * (half + 0.4) + Vector3(0, 0.7, 0)


func _process(delta: float) -> void:
	_traffic_step(delta)
	if not _signals.is_empty():
		var before := _signal_t
		_signal_t += delta
		if int(before * 4.0) != int(_signal_t * 4.0):
			_cycle_signals(_signal_t)
	if _lamp_light == null:
		return
	_flick_t -= delta
	if _flick_t <= 0.0:
		_flick = randf_range(0.15, 0.6) if randf() < 0.35 else 0.0
		_flick_t = randf_range(0.04, 0.12) if _flick > 0.0 else randf_range(1.5, 6.0)
	var k := 1.0 - _flick
	_lamp_light.light_energy = 1.6 * k
	_lamp_glow.light_energy = 0.25 * k
	_lamp_mat.emission_energy_multiplier = 2.2 * k

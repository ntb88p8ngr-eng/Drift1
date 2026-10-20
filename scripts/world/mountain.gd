extends Node3D
## Takioro Mountain's own structures (the ground, the course and the woods come from the track
## data, tools/make_takioro.py):
## - tunnels: a tiled tube with orange sodium lamps (a few real lights follow the camera through it),
##   concrete portals with the name plate, and the rock over it – the ground in the road's corridor
##   is levelled to the road, a cover mesh puts the mountain back on top (trees on it too)
## - slope frames: the concrete lattice (法枠) on the cut slopes above the road, a low retaining wall
## - the rock gallery: a roof on columns along the cliff
## - cherry trees along the valley and the lower switchbacks, a red torii over the start straight
##   with stone lanterns, the waterfall (滝) falling down a rock face beside the road

const MeshKit = preload("res://scripts/util/mesh_kit.gd")
const TexKit = preload("res://scripts/util/tex_kit.gd")
const Colliders = preload("res://scripts/util/colliders.gd")
const TreeFactory = preload("res://scripts/world/tree_factory.gd")

const WALL_H := 4.6          # tunnel: wall height, then the arch
const SIDE := 1.8            # tunnel: walls this far beyond the road edge
const LAMP_STEP := 7.5
const LIGHT_POOL := 6
const COVER_W := 84.0        # the rock over a tunnel reaches this far either side
const TREE_LOD := 70.0

var track
var terrain
var scenery
var rng := RandomNumberGenerator.new()
var stats := {}
var tunnel_spans: Array = []      # [i0, i1] sample ranges
var _lamps: Array = []            # world positions of all tunnel lamps
var _lights: Array = []           # OmniLight3D pool
var _sets := {}                   # sakura instances (chunks)
var _mat_cache := {}


func build(p_track, p_terrain, p_scenery, _quality: int) -> void:
	track = p_track
	terrain = p_terrain
	scenery = p_scenery
	rng.seed = 8128
	var meta: Dictionary = track.meta
	var n: int = track.sample_count()
	for t in meta.get("tunnels", []):
		var i0 := _idx(float(t[0]))
		var i1 := _idx(float(t[1]))
		tunnel_spans.append([i0, i1])
	await Game.load_tick()
	for k in tunnel_spans.size():
		_tunnel(k, tunnel_spans[k][0], tunnel_spans[k][1])
		await Game.load_tick()
	var g: Array = meta.get("gallery", [])
	if g.size() == 2:
		_gallery(_idx(float(g[0])), _idx(float(g[1])))
	await Game.load_tick()
	_slope_frames()
	await Game.load_tick()
	for s in meta.get("sakura", []):
		_sakura_row(float(s[0]), float(s[1]))
	_emit_sakura()
	_torii()
	if meta.has("waterfall"):
		_waterfall(_idx(float(meta["waterfall"])))
	_make_light_pool()
	print("MOUNTAIN: %s" % str(stats))


## Sample index at `d` metres along the lap (as measured in the track data, from sample 0).
func _idx(d: float) -> int:
	var n: int = track.sample_count()
	return posmod(int(round(d / float(track.SPACING))), n)


func in_tunnel(i: int) -> bool:
	for sp in tunnel_spans:
		if _between(i, sp[0], sp[1]):
			return true
	return false


func _between(i: int, a: int, b: int) -> bool:
	var n: int = track.sample_count()
	return posmod(i - a, n) <= posmod(b - a, n)


func _p(i: int, lateral: float, y := 0.0) -> Vector3:
	var n: int = track.sample_count()
	i = posmod(i, n)
	return (track.samples[i] as Vector3) + (track.rights[i] as Vector3) * lateral + Vector3(0, float(track.ROAD_Y) + y, 0)


func _hw(i: int) -> float:
	return float(track.hws[posmod(i, track.sample_count())])


func _mat(key: String, make: Callable) -> Material:
	if not _mat_cache.has(key):
		_mat_cache[key] = make.call()
	return _mat_cache[key]


# ---------------------------------------------------------------------------
# Tunnels
# ---------------------------------------------------------------------------
## The tube's cross-section (lateral, height above the road), left to right: walls with a kerb,
## an arch over the top.
func _profile(w: float) -> Array:
	var out: Array = [Vector2(-w, -0.4), Vector2(-w, WALL_H)]
	var rise := w * 0.42
	for k in range(1, 12):
		var a := PI - PI * k / 12.0
		out.append(Vector2(cos(a) * w, WALL_H + sin(a) * rise))
	out.append(Vector2(w, WALL_H))
	out.append(Vector2(w, -0.4))
	return out


func _tunnel(k: int, i0: int, i1: int) -> void:
	var n: int = track.sample_count()
	var cnt := posmod(i1 - i0, n)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := PackedVector3Array()
	var prev: Array = []
	var lamps := PackedVector3Array()
	var walk := SurfaceTool.new()
	walk.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in range(0, cnt + 1):
		var i := posmod(i0 + j, n)
		var w := _hw(i) + SIDE
		var prof := _profile(w)
		var ring: Array = []
		for q in prof:
			ring.append(_p(i, q.x, q.y))
		if not prev.is_empty():
			for e in prof.size() - 1:
				var a: Vector3 = prev[e]
				var b: Vector3 = prev[e + 1]
				var c: Vector3 = ring[e + 1]
				var d: Vector3 = ring[e]
				var mid_y: float = ((prof[e] as Vector2).y + (prof[e + 1] as Vector2).y) * 0.5
				# tiles low down (white), dark grey above, the vault darker still
				var col := Color(0.82, 0.82, 0.78) if mid_y < 2.6 else (Color(0.3, 0.3, 0.31) if mid_y < WALL_H + 0.1 else Color(0.18, 0.18, 0.19))
				var centre: Vector3 = _p(i, 0.0, WALL_H * 0.6)
				var nrm := (b - a).cross(d - a).normalized()
				if nrm.dot(centre - a) < 0.0:
					nrm = -nrm
				# facing inwards (seen from the road)
				MeshKit.tri(st, a, b, c, nrm, nrm, nrm, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, nrm, col)
				MeshKit.tri(st, a, c, d, nrm, nrm, nrm, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, nrm, col)
				faces.append_array([a, b, c, a, c, d])
		prev = ring
		# kerbs (walkways) along both walls
		if j < cnt:
			for side: float in [-1.0, 1.0]:
				var hw := _hw(i)
				var xf := Transform3D(Basis.looking_at(track.tangents[i], Vector3.UP), _p(i, side * (hw + SIDE * 0.5), 0.12))
				MeshKit.box(walk, xf, Vector3(SIDE, 0.28, float(track.SPACING) + 0.05), Color(0.55, 0.55, 0.53))
		if j % int(LAMP_STEP / float(track.SPACING)) == 0 and j > 1 and j < cnt - 1:
			for side: float in [-1.0, 1.0]:
				lamps.append(_p(i, side * (w - 0.45), WALL_H + 0.5))
	var mat := _mat("tube", func():
		var m := TexKit.std(Color.WHITE, 0.55)
		m.vertex_color_use_as_albedo = true
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		return m)
	var tube := MeshKit.mesh_instance(st.commit(), mat, true)
	tube.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED      # (no sun inside)
	tube.name = "Tunnel%d" % (k + 1)
	add_child(tube)
	var wmi := MeshKit.mesh_instance(walk.commit(), _mat("kerb", func(): return TexKit.std(Color(0.6, 0.6, 0.58), 0.85)), false)
	add_child(wmi)
	# collision: walls and vault (the road brings its own), from both sides
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	add_child(body)
	# the lamps: orange sodium fixtures in two rows
	var lamp_mesh := BoxMesh.new()
	lamp_mesh.size = Vector3(0.35, 0.16, 1.1)
	var lm := MultiMesh.new()
	lm.transform_format = MultiMesh.TRANSFORM_3D
	lm.mesh = lamp_mesh
	lm.instance_count = lamps.size()
	for q in lamps.size():
		var ii := posmod(i0 + int(q / 2) * int(LAMP_STEP / float(track.SPACING)), n)
		lm.set_instance_transform(q, Transform3D(Basis.looking_at(track.tangents[ii], Vector3.UP), lamps[q]))
		_lamps.append(lamps[q])
	var lmi := MultiMeshInstance3D.new()
	lmi.multimesh = lm
	lmi.material_override = _mat("sodium", func():
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(1.0, 0.6, 0.2)
		m.emission_enabled = true
		m.emission = Color(1.0, 0.55, 0.15)
		m.emission_energy_multiplier = 5.0
		return m)
	lmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(lmi)
	_portal(k, i0, 1.0)
	_portal(k, i1, -1.0)
	_cover(i0, i1)
	stats["tunnels"] = int(stats.get("tunnels", 0)) + 1
	stats["tunnel_m"] = int(stats.get("tunnel_m", 0)) + int(cnt * float(track.SPACING))


## A concrete headwall at sample i: `into` +1 when the tunnel lies ahead (in the driving direction).
## The face: a block either side of the opening, the lintel over it, the spandrels between the arch
## and the lintel; a coping on top and the name plate.
func _portal(k: int, i: int, into: float) -> void:
	var hw := _hw(i)
	var w := hw + SIDE
	var apex := WALL_H + w * 0.42
	var outer_w := w + 9.0
	var top := apex + 6.0
	var fwd: Vector3 = (track.tangents[i] as Vector3) * into
	fwd.y = 0.0
	fwd = fwd.normalized()
	var right: Vector3 = track.rights[i]
	var base := _p(i, 0.0, 0.0)
	var depth := 1.4
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var col := Color(0.66, 0.65, 0.62)
	var face := func(x: float, y: float, back := 0.0) -> Vector3:
		return base + right * x + Vector3(0, y, 0) + fwd * back
	var out_n := -fwd
	var quad := func(a: Vector3, b: Vector3, c: Vector3, d: Vector3, nrm: Vector3) -> void:
		MeshKit.quad(st, a, b, c, d, nrm, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, col)
	# side blocks and lintel (down below the road a little: the ground of the cut meets them)
	quad.call(face.call(-outer_w, -2.0), face.call(-w, -2.0), face.call(-w, top), face.call(-outer_w, top), out_n)
	quad.call(face.call(w, -2.0), face.call(outer_w, -2.0), face.call(outer_w, top), face.call(w, top), out_n)
	quad.call(face.call(-w, apex), face.call(w, apex), face.call(w, top), face.call(-w, top), out_n)
	# spandrels: from each piece of the arch up to the lintel
	var prof := _profile(w)
	for e in range(1, prof.size() - 2):
		var a2: Vector2 = prof[e]
		var b2: Vector2 = prof[e + 1]
		quad.call(face.call(a2.x, a2.y), face.call(b2.x, b2.y), face.call(b2.x, apex), face.call(a2.x, apex), out_n)
	# thickness: the top and both ends of the slab
	quad.call(face.call(-outer_w, top), face.call(outer_w, top), face.call(outer_w, top, depth), face.call(-outer_w, top, depth), Vector3.UP)
	quad.call(face.call(-outer_w, -2.0), face.call(-outer_w, top), face.call(-outer_w, top, depth), face.call(-outer_w, -2.0, depth), -right)
	quad.call(face.call(outer_w, top), face.call(outer_w, -2.0), face.call(outer_w, -2.0, depth), face.call(outer_w, top, depth), right)
	# a coping band along the top
	MeshKit.box(st, Transform3D(Basis(right, Vector3.UP, -fwd), base + Vector3(0, top + 0.25, 0) + fwd * (depth * 0.5 - 0.15)), Vector3(outer_w * 2.0 + 0.4, 0.5, depth + 0.3), Color(0.55, 0.54, 0.52))
	var mi := MeshKit.mesh_instance(st.commit(), _mat("portal", func():
		var m := TexKit.std(Color.WHITE, 0.85)
		m.vertex_color_use_as_albedo = true
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		return m), true)
	mi.name = "Portal"
	add_child(mi)
	# the name plate over the opening
	var plate := MeshKit.box_node(Vector3(7.4, 1.1, 0.2), _mat("plate", func(): return TexKit.std(Color(0.12, 0.2, 0.42), 0.4)))
	add_child(plate)
	plate.global_transform = Transform3D(Basis(right, Vector3.UP, -fwd), base + Vector3(0, apex + 2.4, 0) - fwd * 0.12)
	var names := ["ICHI", "NI", "SAN"]
	var lbl := Label3D.new()
	lbl.text = "TAKIORO-TUNNEL %s" % names[mini(k, 2)]
	lbl.font_size = 64
	lbl.pixel_size = 0.009
	lbl.modulate = Color(0.95, 0.95, 0.95)
	add_child(lbl)
	lbl.global_transform = Transform3D(Basis(right, Vector3.UP, -fwd), base + Vector3(0, apex + 2.4, 0) - fwd * 0.25)


## The mountain over a tunnel: the ground of the road's corridor is levelled to the road – a mesh at
## the real ground height closes the cut again (just under the ground where that is higher), with a
## rock face at both ends round the portals. Trees go on it too.
func _cover(i0: int, i1: int) -> void:
	var n: int = track.sample_count()
	var cnt := posmod(i1 - i0, n)
	var step := 2              # every 4 m along
	var cols := int(COVER_W * 2.0 / 4.0) + 1
	var verts := PackedVector3Array()
	var colors := PackedColorArray()
	var idx := PackedInt32Array()
	var rows := 0
	var j := 0
	var row_ends: Array = []
	while j <= cnt:
		var i := posmod(i0 + j, n)
		for c in cols:
			var lat := -COVER_W + c * 4.0
			var p := _p(i, lat, 0.0)
			var dem: float = terrain.dem_at(p.x, p.z)
			var g: float = terrain.height_at(p.x, p.z)
			var y := maxf(dem - 0.12, g - 0.4)
			# (never down into the vault: at the portals the rock may be thin)
			if absf(lat) < _hw(i) + SIDE + 3.0:
				y = maxf(y, p.y + WALL_H + (_hw(i) + SIDE) * 0.42 + 1.6)
			verts.append(Vector3(p.x, y, p.z))
			colors.append(Color(0.0, 0.0, 1.0, 0.0))
			# a tree where the cover stands well above the cut, away from the tube
			if dem - g > 2.0 and absf(lat) > _hw(i) + 8.0 and j % 3 == 0 and rng.randf() < 0.5:
				scenery.extra_trees.append(Vector3(p.x + rng.randf_range(-1.5, 1.5), dem - 0.3, p.z + rng.randf_range(-1.5, 1.5)))
		row_ends.append(i)
		rows += 1
		if j == cnt:
			break
		j = mini(j + step, cnt)
	for r in rows - 1:
		for c in cols - 1:
			var a := r * cols + c
			var b := a + 1
			var cc := a + cols
			var d := cc + 1
			idx.append_array(PackedInt32Array([a, b, d, a, d, cc]))
	var norms := PackedVector3Array()
	norms.resize(verts.size())
	for t in range(0, idx.size(), 3):
		var a3 := verts[idx[t]]
		var b3 := verts[idx[t + 1]]
		var c3 := verts[idx[t + 2]]
		var nn := (b3 - a3).cross(c3 - a3).normalized()
		if nn.y < 0.0:
			nn = -nn
		for q in 3:
			norms[idx[t + q]] += nn
	for v in norms.size():
		norms[v] = norms[v].normalized() if norms[v].length() > 0.0 else Vector3.UP
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, terrain.material)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.name = "TunnelCover"
	add_child(mi)
	# rock faces at both ends: from the cover down to the cut ground, round the portal
	var rock := SurfaceTool.new()
	rock.begin(Mesh.PRIMITIVE_TRIANGLES)
	for e in 2:
		var r0 := 0 if e == 0 else rows - 1
		var ie: int = row_ends[r0]
		var outward: Vector3 = -(track.tangents[ie] as Vector3) if e == 0 else (track.tangents[ie] as Vector3)
		outward.y = 0.0
		for c in cols - 1:
			var ta: Vector3 = verts[r0 * cols + c]
			var tb: Vector3 = verts[r0 * cols + c + 1]
			var ga: float = terrain.height_at(ta.x, ta.z) - 0.6
			var gb: float = terrain.height_at(tb.x, tb.z) - 0.6
			if ta.y - ga < 0.4 and tb.y - gb < 0.4:
				continue
			MeshKit.quad(rock, Vector3(ta.x, ga, ta.z), Vector3(tb.x, gb, tb.z), tb, ta, outward.normalized(),
				Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Color(0.42, 0.4, 0.37))
	var rmi := MeshKit.mesh_instance(rock.commit(), _mat("rockface", func():
		var m := TexKit.std(Color.WHITE, 0.95)
		m.vertex_color_use_as_albedo = true
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		return m), true)
	add_child(rmi)
	# nothing else grows in the cut (the forest leaves it to the cover)
	var jj := 0
	while jj <= cnt:
		scenery.occupy(_p(i0 + jj, 0.0), 30.0)
		jj += 10


func _make_light_pool() -> void:
	if _lamps.is_empty():
		return
	for k in LIGHT_POOL:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.62, 0.28)
		l.light_energy = 1.6
		l.omni_range = 11.0
		l.shadow_enabled = false
		l.visible = false
		add_child(l)
		_lights.append(l)


func _process(_dt: float) -> void:
	if _lights.is_empty():
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var cp := cam.global_position
	# the lamps nearest the camera get a real light (only near the tunnels)
	var best: Array = []
	for p: Vector3 in _lamps:
		var d := p.distance_squared_to(cp)
		if d > 60.0 * 60.0:
			continue
		best.append([d, p])
	best.sort_custom(func(a, b): return a[0] < b[0])
	for k in _lights.size():
		var l: OmniLight3D = _lights[k]
		if k < best.size():
			l.visible = true
			l.global_position = best[k][1] - Vector3(0, 0.4, 0)
		else:
			l.visible = false


# ---------------------------------------------------------------------------
# Rock gallery: a roof on columns along the cliff
# ---------------------------------------------------------------------------
func _gallery(i0: int, i1: int) -> void:
	var n: int = track.sample_count()
	var cnt := posmod(i1 - i0, n)
	# uphill side: where the ground beside the road is higher
	var mid := posmod(i0 + cnt / 2, n)
	var pl := _p(mid, -(float(track.wall_base) + 10.0))
	var pr := _p(mid, float(track.wall_base) + 10.0)
	var up := 1.0 if terrain.height_at(pr.x, pr.z) > terrain.height_at(pl.x, pl.z) else -1.0
	var roof_h := 6.4
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var conc := Color(0.7, 0.69, 0.66)
	var wb: float = float(track.wall_base)
	var step := 3
	var j := 0
	while j < cnt:
		var i := posmod(i0 + j, n)
		var tg: Vector3 = track.tangents[i]
		var b := Basis.looking_at(Vector3(tg.x, 0, tg.z).normalized(), Vector3.UP)
		var seg := float(step) * float(track.SPACING) + 0.08
		# the roof slab from the uphill wall out over the road to the columns
		var lat_mid := up * ((wb + 0.6) - (wb + 0.9)) * 0.5
		MeshKit.box(st, Transform3D(b, _p(i, lat_mid, roof_h + 0.4)), Vector3((wb + 0.6) + (wb + 0.9) + 0.6, 0.8, seg), conc)
		# the uphill wall
		MeshKit.box(st, Transform3D(b, _p(i, up * (wb + 0.6), roof_h * 0.5 - 0.2)), Vector3(0.7, roof_h + 0.4, seg), conc.darkened(0.08))
		Colliders.add_box(self, Transform3D(b, _p(i, up * (wb + 0.6), roof_h * 0.5 - 0.2)), Vector3(0.7, roof_h + 0.4, seg))
		# a column every other step on the valley side (outside the barrier)
		if (j / step) % 2 == 0:
			var cxf := Transform3D(b, _p(i, -up * (wb + 0.9), roof_h * 0.5))
			MeshKit.box(st, cxf, Vector3(0.8, roof_h, 0.8), conc)
			Colliders.add_box(self, cxf, Vector3(0.8, roof_h, 0.8))
		j += step
	var mi := MeshKit.mesh_instance(st.commit(), _mat("gallery", func():
		var m := TexKit.std(Color.WHITE, 0.85)
		m.vertex_color_use_as_albedo = true
		return m), true)
	mi.name = "Gallery"
	add_child(mi)
	stats["gallery_m"] = int(cnt * float(track.SPACING))


# ---------------------------------------------------------------------------
# Slope frames (法枠): the concrete lattice on the cut slopes above the road
# ---------------------------------------------------------------------------
const FRAME_SHADER := """
shader_type spatial;
render_mode diffuse_burley;
varying vec3 wpos;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
float h(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
void fragment() {
	// UV in metres: x along the road, y up the slope
	vec2 g = UV / 2.2;
	vec2 f = fract(g);
	vec2 fw = fwidth(g);
	float bx = 1.0 - smoothstep(0.07, 0.07 + fw.x * 1.5, min(f.x, 1.0 - f.x));
	float by = 1.0 - smoothstep(0.07, 0.07 + fw.y * 1.5, min(f.y, 1.0 - f.y));
	float frame = max(bx, by);
	float r = h(floor(g));
	vec3 grass = mix(vec3(0.2, 0.3, 0.1), vec3(0.32, 0.38, 0.16), r) * (0.85 + 0.3 * h(floor(UV * 3.0)));
	vec3 conc = vec3(0.66, 0.65, 0.61) * (0.9 + 0.12 * h(floor(UV * 1.3)));
	ALBEDO = mix(grass, conc, frame);
	ROUGHNESS = mix(0.95, 0.85, frame);
}
"""


func _slope_frames() -> void:
	var n: int = track.sample_count()
	var wb: float = float(track.wall_base)
	var mat := _mat("frames", func():
		var m := ShaderMaterial.new()
		m.shader = Shader.new()
		m.shader.code = FRAME_SHADER
		return m)
	var wall_mat := _mat("retaining", func(): return TexKit.std(Color(0.62, 0.61, 0.58), 0.9))
	for side: float in [-1.0, 1.0]:
		var run: Array = []
		for i in range(0, n, 2):
			var steep := false
			if not in_tunnel(i):
				var probe := _p(i, side * (wb + 6.0))
				var road_y: float = (track.samples[i] as Vector3).y
				steep = terrain.height_at(probe.x, probe.z) - road_y > 1.8
			if steep:
				run.append(i)
			elif run.size() >= 6:
				_frame_run(run, side, mat, wall_mat)
				run = []
			else:
				run = []
		if run.size() >= 6:
			_frame_run(run, side, mat, wall_mat)


func _frame_run(run: Array, side: float, mat: Material, wall_mat: Material) -> void:
	var wb: float = float(track.wall_base)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var wall := SurfaceTool.new()
	wall.begin(Mesh.PRIMITIVE_TRIANGLES)
	const STEPS := 7
	var along := 0.0
	var prev: Array = []
	var prev_along := 0.0
	for r in run.size():
		var i: int = run[r]
		if r > 0:
			along += float(track.SPACING) * float(posmod(i - int(run[r - 1]), track.sample_count()))
		var row: Array = []
		var up := 0.0
		var last := Vector3.ZERO
		for c in STEPS + 1:
			var lat := side * (wb + 0.6 + c * 1.8)
			var p := _p(i, lat)
			var y: float = terrain.height_at(p.x, p.z) + 0.12
			var q := Vector3(p.x, y, p.z)
			if c > 0:
				up += q.distance_to(last)
			last = q
			row.append([q, up])
		if not prev.is_empty():
			for c in STEPS:
				var a: Vector3 = prev[c][0]
				var b: Vector3 = row[c][0]
				var cc: Vector3 = row[c + 1][0]
				var d: Vector3 = prev[c + 1][0]
				var nrm := (b - a).cross(d - a).normalized()
				if nrm.y < 0.0:
					nrm = -nrm
				var uva := Vector2(prev_along, float(prev[c][1]))
				var uvb := Vector2(along, float(row[c][1]))
				var uvc := Vector2(along, float(row[c + 1][1]))
				var uvd := Vector2(prev_along, float(prev[c + 1][1]))
				MeshKit.quad(st, a, b, cc, d, nrm, uva, uvb, uvc, uvd)
			# the low retaining wall at the foot of the slope
			var w0: Vector3 = prev[0][0]
			var w1: Vector3 = row[0][0]
			var base0 := _p(run[r - 1], side * (wb + 0.6), -0.3)
			var base1 := _p(i, side * (wb + 0.6), -0.3)
			var top0 := Vector3(base0.x, maxf(w0.y, base0.y + 1.2), base0.z)
			var top1 := Vector3(base1.x, maxf(w1.y, base1.y + 1.2), base1.z)
			var toward_road: Vector3 = -(track.rights[i] as Vector3) * side
			MeshKit.quad(wall, base0, base1, top1, top0, toward_road, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
		prev = row
		prev_along = along
	var mi := MeshKit.mesh_instance(st.commit(), mat, true)
	mi.name = "SlopeFrame"
	mi.visibility_range_end = 600.0
	add_child(mi)
	var wmi := MeshKit.mesh_instance(wall.commit(), wall_mat, true)
	wmi.visibility_range_end = 600.0
	add_child(wmi)
	stats["frame_m"] = int(stats.get("frame_m", 0)) + int(along)


# ---------------------------------------------------------------------------
# Cherry trees, torii, lanterns, waterfall
# ---------------------------------------------------------------------------
func _sakura_row(d0: float, d1: float) -> void:
	var wb: float = float(track.wall_base)
	var d := d0
	while d < d1:
		d += rng.randf_range(10.0, 17.0)
		var i := _idx(d)
		if in_tunnel(i):
			continue
		for side: float in [-1.0, 1.0]:
			if rng.randf() < 0.18:
				continue
			var p := _p(i, side * (wb + rng.randf_range(2.6, 6.5)))
			var g: float = terrain.height_at(p.x, p.z)
			if absf(g - p.y) > 3.5 or terrain.normal_at(p.x, p.z).y < 0.8:
				continue
			if not scenery.free_at(Vector3(p.x, g, p.z), 2.5, 0.0):
				continue
			var s := rng.randf_range(0.85, 1.25)
			var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.9, 1.1), s)), Vector3(p.x, g - 0.15, p.z))
			scenery._push(_sets, xf.origin, [xf, Color(1, 1, 1, 1)], 96.0)
			scenery.occupy(xf.origin, 3.0)
			stats["sakura"] = int(stats.get("sakura", 0)) + 1


func _emit_sakura() -> void:
	if _sets.is_empty():
		return
	var hi: Mesh = TreeFactory.sakura(311, 1.0)
	var lo: Mesh = TreeFactory.sakura(311, 0.25)
	var e := TREE_LOD
	scenery._emit_chunks(hi, _sets, 0.0, e + 20.0, "City_sakura", false, 96.0, false, false, Vector4(-2.0, -1.0, e - 10.0, e + 10.0))
	scenery._emit_chunks(lo, _sets, 0.0, 200.0, "City_sakura_shadow", true, 96.0, true)
	scenery._emit_chunks(lo, _sets, e - 20.0, 900.0, "City_sakura_lo", false, 96.0, false, false, Vector4(e - 10.0, e + 10.0, 1e9, 2e9))


## A red torii over the start straight (before the line), stone lanterns along it.
func _torii() -> void:
	var i := posmod(int(track.start_index) - int(45.0 / float(track.SPACING)), track.sample_count())
	var wb: float = float(track.wall_base)
	var tg: Vector3 = track.tangents[i]
	var b := Basis.looking_at(Vector3(tg.x, 0, tg.z).normalized(), Vector3.UP)
	var red := _mat("torii_red", func(): return TexKit.std(Color(0.78, 0.12, 0.06), 0.55))
	var black := _mat("torii_black", func(): return TexKit.std(Color(0.06, 0.05, 0.05), 0.6))
	var stone := _mat("stone", func(): return TexKit.std(Color(0.55, 0.54, 0.5), 0.95))
	var half := wb + 1.2
	var hgt := 10.5
	for side: float in [-1.0, 1.0]:
		var base := _p(i, side * half, 0.0)
		var g: float = terrain.height_at(base.x, base.z)
		var y0 := minf(g, base.y) - 0.3
		var pil := CylinderMesh.new()
		pil.top_radius = 0.42
		pil.bottom_radius = 0.5
		pil.height = hgt + (base.y - y0)
		var mi := MeshInstance3D.new()
		mi.mesh = pil
		mi.material_override = red
		add_child(mi)
		mi.global_position = Vector3(base.x, y0 + pil.height * 0.5, base.z)
		Colliders.add_box(self, Transform3D(Basis.IDENTITY, mi.global_position), Vector3(1.0, pil.height, 1.0))
		# black foot
		var foot := MeshKit.box_node(Vector3(1.2, 1.0, 1.2), black)
		add_child(foot)
		foot.global_position = Vector3(base.x, y0 + 0.5, base.z)
		# stone lanterns along the straight
		for k in 4:
			var li := posmod(i + int((18.0 + k * 22.0) / float(track.SPACING)), track.sample_count())
			var lp := _p(li, side * (wb + 1.6))
			var lg: float = terrain.height_at(lp.x, lp.z)
			_lantern(Vector3(lp.x, lg, lp.z), stone)
	var top := _p(i, 0.0, hgt)
	# kasagi (top beam, black cap, ends sweeping up) and nuki (tie beam)
	var kasagi := MeshKit.box_node(Vector3(half * 2.0 + 5.0, 0.7, 1.0), red)
	add_child(kasagi)
	kasagi.global_transform = Transform3D(b, top + Vector3(0, 0.6, 0))
	var cap := MeshKit.box_node(Vector3(half * 2.0 + 5.6, 0.35, 1.25), black)
	add_child(cap)
	cap.global_transform = Transform3D(b, top + Vector3(0, 1.1, 0))
	for side: float in [-1.0, 1.0]:
		var tip := MeshKit.box_node(Vector3(2.2, 0.35, 1.25), black)
		add_child(tip)
		tip.global_transform = Transform3D(b * Basis(Vector3.BACK, side * 0.22), top + Vector3(0, 1.3, 0) + (track.rights[i] as Vector3) * side * (half + 2.6))
	var nuki := MeshKit.box_node(Vector3(half * 2.0 + 2.4, 0.55, 0.55), red)
	add_child(nuki)
	nuki.global_transform = Transform3D(b, top - Vector3(0, 1.8, 0))
	var gakuzuka := MeshKit.box_node(Vector3(0.9, 1.6, 0.3), black)
	add_child(gakuzuka)
	gakuzuka.global_transform = Transform3D(b, top - Vector3(0, 0.6, 0))
	stats["torii"] = 1


func _lantern(at: Vector3, stone: Material) -> void:
	var parts := [[Vector3(0.7, 0.3, 0.7), 0.15], [Vector3(0.3, 0.9, 0.3), 0.75], [Vector3(0.6, 0.2, 0.6), 1.3],
		[Vector3(0.5, 0.45, 0.5), 1.62], [Vector3(0.85, 0.18, 0.85), 1.94], [Vector3(0.25, 0.25, 0.25), 2.15]]
	for pr in parts:
		var mi := MeshKit.box_node(pr[0], stone)
		add_child(mi)
		mi.global_position = at + Vector3(0, pr[1], 0)
	# a warm glow in the light box
	var glow := MeshKit.box_node(Vector3(0.3, 0.28, 0.52), _mat("lantern_glow", func():
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(1.0, 0.8, 0.5)
		m.emission_enabled = true
		m.emission = Color(1.0, 0.7, 0.35)
		m.emission_energy_multiplier = 2.0
		return m))
	add_child(glow)
	glow.global_position = at + Vector3(0, 1.62, 0)
	Colliders.add_box(self, Transform3D(Basis.IDENTITY, at + Vector3(0, 1.1, 0)), Vector3(0.7, 2.2, 0.7))


const FALL_SHADER := """
shader_type spatial;
render_mode cull_disabled, depth_draw_never, specular_schlick_ggx;
uniform sampler2D noise : filter_linear_mipmap, repeat_enable;
void fragment() {
	// streaks rushing down, foam at the edges and the foot
	vec2 uv = UV;
	float s1 = texture(noise, vec2(uv.x * 3.0, uv.y * 0.6 - TIME * 1.6)).r;
	float s2 = texture(noise, vec2(uv.x * 7.0 + 0.3, uv.y * 1.4 - TIME * 2.6)).r;
	float streak = smoothstep(0.35, 0.8, s1 * 0.6 + s2 * 0.6);
	float edge = smoothstep(0.0, 0.18, uv.x) * smoothstep(1.0, 0.82, uv.x);
	vec3 water = mix(vec3(0.55, 0.68, 0.72), vec3(0.95, 0.97, 1.0), streak);
	ALBEDO = water;
	ALPHA = (0.6 + 0.4 * streak) * edge;
	ROUGHNESS = 0.15;
	EMISSION = vec3(0.08, 0.1, 0.11) * streak;
}
"""


## The waterfall: a rock face on the uphill side of the road, water rushing down it into a pool
## with spray; a culvert under the road (no stream across the asphalt).
func _waterfall(i: int) -> void:
	var wb: float = float(track.wall_base)
	var pl := _p(i, -(wb + 12.0))
	var pr := _p(i, wb + 12.0)
	var up := 1.0 if terrain.height_at(pr.x, pr.z) > terrain.height_at(pl.x, pl.z) else -1.0
	var tg: Vector3 = track.tangents[i]
	var toward_road := -(track.rights[i] as Vector3) * up
	var basis := Basis.looking_at(-toward_road, Vector3.UP)      # -z away from the road: +z faces it
	var road_y: float = (track.samples[i] as Vector3).y
	var foot := _p(i, up * (wb + 11.0))
	# as tall as the rock wall the terrain has behind it
	var behind := foot - toward_road * 8.0
	var height := clampf(terrain.height_at(behind.x, behind.z) - road_y, 10.0, 28.0)
	# the rock face: a rough wall (noise pushed out towards the road), sunk into the slope
	var rw := 22.0
	var rh := height + 8.0
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var noise := FastNoiseLite.new()
	noise.seed = 77
	noise.frequency = 0.18
	var nx := 12
	var ny := 16
	var grid: Array = []
	for yy in ny + 1:
		var row: Array = []
		for xx in nx + 1:
			var u := (float(xx) / nx - 0.5) * rw
			var v := float(yy) / ny * rh - 3.0
			# the middle (behind the water) set back a little: a groove the fall has cut
			var groove := -2.2 * exp(-u * u / 8.0)
			# sides lean back into the slope, the top above the lip the water comes over
			var out := noise.get_noise_2d(u, v) * 1.4 + groove - u * u * 0.035 - smoothstep(height, height + 5.0, v) * 5.0
			row.append(Transform3D(basis, Vector3(foot.x, road_y, foot.z)) * Vector3(u, v, out))
		grid.append(row)
	for yy in ny:
		for xx in nx:
			var a: Vector3 = grid[yy][xx]
			var b: Vector3 = grid[yy][xx + 1]
			var c: Vector3 = grid[yy + 1][xx + 1]
			var d: Vector3 = grid[yy + 1][xx]
			var nrm := (b - a).cross(d - a).normalized()
			if nrm.dot(toward_road) < 0.0:
				nrm = -nrm
			# wet and dark in the groove, grey with moss further out
			var cx := absf((a.x + c.x) * 0.5 - foot.x) + absf((a.z + c.z) * 0.5 - foot.z)
			var col := Color(0.32, 0.31, 0.3) if cx < 3.5 else Color(0.55, 0.53, 0.49).lerp(Color(0.34, 0.42, 0.24), clampf(noise.get_noise_2d(a.x, a.y) * 0.8 + 0.3, 0.0, 0.7))
			MeshKit.quad(st, a, b, c, d, nrm, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, col)
	var rock := MeshKit.mesh_instance(st.commit(), _mat("fall_rock", func():
		var m := TexKit.std(Color.WHITE, 0.92)
		m.vertex_color_use_as_albedo = true
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		return m), true)
	rock.name = "WaterfallRock"
	add_child(rock)
	# the falling water: a sheet in the groove, wider at the foot
	var q := QuadMesh.new()
	q.size = Vector2(6.5, height)
	var fall := MeshInstance3D.new()
	fall.mesh = q
	var fm := ShaderMaterial.new()
	fm.shader = Shader.new()
	fm.shader.code = FALL_SHADER
	fm.set_shader_parameter("noise", TexKit.noise_texture(303, 0.08))
	fall.material_override = fm
	fall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(fall)
	fall.global_transform = Transform3D(basis, Vector3(foot.x, road_y + height * 0.5 + 0.2, foot.z) + toward_road * 1.1)
	# the pool at its foot
	var pool := CylinderMesh.new()
	pool.top_radius = 4.2
	pool.bottom_radius = 4.0
	pool.height = 0.3
	var pm := MeshInstance3D.new()
	pm.mesh = pool
	pm.material_override = TexKit.water_material()
	add_child(pm)
	pm.global_position = Vector3(foot.x, road_y + 0.05, foot.z) + toward_road * 1.5
	# spray
	var p := GPUParticles3D.new()
	p.amount = 40
	p.lifetime = 2.2
	p.preprocess = 2.0
	var ppm := ParticleProcessMaterial.new()
	ppm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	ppm.emission_box_extents = Vector3(2.4, 0.3, 0.6)
	ppm.direction = Vector3(0, 1, 0)
	ppm.spread = 60.0
	ppm.initial_velocity_min = 1.0
	ppm.initial_velocity_max = 3.0
	ppm.gravity = Vector3(0, -1.2, 0)
	ppm.scale_min = 1.0
	ppm.scale_max = 2.4
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.35), Color(1, 1, 1, 0.0)])
	g.offsets = PackedFloat32Array([0.0, 0.2, 1.0])
	var gt := GradientTexture1D.new()
	gt.gradient = g
	ppm.color_ramp = gt
	p.process_material = ppm
	var sq := QuadMesh.new()
	sq.size = Vector2(1.6, 1.6)
	var sm := StandardMaterial3D.new()
	sm.albedo_texture = TexKit.smoke_texture()
	sm.vertex_color_use_as_albedo = true
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	sm.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	sq.material = sm
	p.draw_pass_1 = sq
	p.visibility_range_end = 220.0
	add_child(p)
	p.global_position = Vector3(foot.x, road_y + 0.5, foot.z) + toward_road * 0.8
	scenery.occupy(foot, 12.0)
	# a clearing on that side of the road so the fall is seen on the approach
	for k in range(-24, 9, 4):
		scenery.occupy(_p(i + k, up * (wb + 9.0)), 9.0)
	stats["waterfall"] = 1

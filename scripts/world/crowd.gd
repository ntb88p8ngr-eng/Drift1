extends Node3D
## Spectators: groups on the outside of the biggest corners (behind a safety net, with flags and
## pop-up tents) and a full grandstand at the start. People are low-poly figures drawn with one
## MultiMesh per group; a vertex shader lets them sway, clap or cheer with raised arms.

const MeshKit = preload("res://scripts/util/mesh_kit.gd")
const TexKit = preload("res://scripts/util/tex_kit.gd")

const SHIRTS := [Color(0.85, 0.1, 0.1), Color(0.1, 0.25, 0.75), Color(0.95, 0.95, 0.95), Color(0.08, 0.08, 0.09),
	Color(0.95, 0.75, 0.1), Color(0.2, 0.55, 0.25), Color(0.55, 0.2, 0.7), Color(0.95, 0.45, 0.1),
	Color(0.4, 0.42, 0.45), Color(0.1, 0.55, 0.65), Color(0.7, 0.1, 0.35)]

const CROWD_SHADER := """
shader_type spatial;
render_mode diffuse_burley;

varying vec3 part_col;

float h1(float n) { return fract(sin(n * 12.9898 + 4.1414) * 43758.5453); }

vec3 rot_z(vec3 v, float a) { float c = cos(a); float s = sin(a); return vec3(v.x * c - v.y * s, v.x * s + v.y * c, v.z); }
vec3 rot_x(vec3 v, float a) { float c = cos(a); float s = sin(a); return vec3(v.x, v.y * c - v.z * s, v.y * s + v.z * c); }

void vertex() {
	vec4 cd = INSTANCE_CUSTOM;              // rgb = shirt colour, a = phase / mood (> 1.5: racing overall)
	float id = float(INSTANCE_ID);
	bool overall = cd.a > 1.5;              // pit crew: one-colour overall, arms down
	float phase = fract(cd.a) * 6.2831 + id * 0.37;
	float mood = overall ? 0.1 : fract(cd.a * 7.13 + h1(id) * 0.3);
	float t = TIME * (0.85 + h1(id + 3.0) * 0.4);
	float part = COLOR.r;
	float arm = COLOR.a;
	vec3 v = VERTEX;
	vec3 n = NORMAL;
	if (arm > 0.25) {
		float side = arm > 0.75 ? 1.0 : -1.0;
		vec3 pivot = vec3(0.27 * side, 1.43, 0.0);
		vec3 lv = v - pivot;
		if (mood > 0.72) {
			// cheering: arms up, waving
			float a = side * (2.55 + 0.35 * sin(t * 7.0 + phase + side));
			lv = rot_z(lv, a);
			n = rot_z(n, a);
		} else if (mood > 0.4) {
			// clapping: forearms forward and together
			float a = 1.25 + 0.12 * sin(t * 10.0 + phase);
			lv = rot_x(lv, a);
			n = rot_x(n, a);
			lv = rot_z(lv, -side * (0.35 + 0.1 * sin(t * 10.0 + phase)));
		} else {
			float a = 0.08 * sin(t * 1.3 + phase + side);
			lv = rot_x(lv, a);
		}
		v = pivot + lv;
	}
	// body motion: bouncing when cheering, slight sway otherwise
	float bounce = mood > 0.72 ? abs(sin(t * 3.5 + phase)) * 0.07 : 0.0;
	v.y += bounce * smoothstep(0.1, 0.6, v.y);
	v.x += sin(t * 0.9 + phase) * 0.025 * v.y;
	VERTEX = v;
	NORMAL = n;
	// colours per body part
	float r = h1(id);
	vec3 skin = mix(vec3(0.95, 0.76, 0.62), vec3(0.42, 0.27, 0.18), h1(id + 7.0));
	vec3 pants = mix(vec3(0.08, 0.1, 0.18), vec3(0.3, 0.28, 0.25), h1(id + 11.0));
	if (h1(id + 13.0) > 0.8) { pants = vec3(0.55, 0.5, 0.38); }
	vec3 hair = mix(vec3(0.05, 0.04, 0.03), vec3(0.45, 0.32, 0.18), h1(id + 17.0) * h1(id + 19.0));
	if (h1(id + 23.0) > 0.7) { hair = cd.rgb * 0.9; }   // cap in the shirt colour
	vec3 shoes = h1(id + 29.0) > 0.5 ? vec3(0.9) : vec3(0.06);
	if (overall) {
		pants = cd.rgb;
		shoes = vec3(0.05);
	}
	part_col = part < 0.2 ? pants : (part < 0.4 ? cd.rgb : (part < 0.6 ? skin : (part < 0.8 ? hair : shoes)));
}

void fragment() {
	ALBEDO = part_col;
	ROUGHNESS = 0.85;
}
"""

const FLAG_SHADER := """
shader_type spatial;
render_mode cull_disabled, diffuse_burley;

uniform vec3 flag_color : source_color = vec3(0.8, 0.1, 0.1);
uniform vec3 stripe_color : source_color = vec3(1.0);

void vertex() {
	float w = UV.x;
	VERTEX.z += sin(TIME * 5.0 - w * 6.0 + VERTEX.y) * 0.18 * w;
	VERTEX.y -= w * w * 0.12;
}

void fragment() {
	float s = step(0.4, UV.y) * step(UV.y, 0.6);
	ALBEDO = mix(flag_color, stripe_color, s);
	ROUGHNESS = 0.8;
	BACKLIGHT = flag_color * 0.4;
}
"""

var track
var terrain
var scenery
var rng := RandomNumberGenerator.new()
static var _person_mesh: ArrayMesh
static var _net_mat: StandardMaterial3D


func build(p_track, p_terrain, p_scenery, quality: int) -> void:
	track = p_track
	terrain = p_terrain
	scenery = p_scenery
	rng.seed = hash(track.track_id) + 77
	var zones: int = [3, 4, 6, 7][clampi(quality, 0, 3)]
	# the open playground pad has no barriers to stand behind: only the grandstand there
	if track.track_id != "playground" and not Game.is_city(track.track_id) and not Game.is_glb_map(track.track_id):
		for i in _corner_indices(zones):
			await Game.load_tick()
			_build_zone(i, quality)
	_build_grandstand()


## Sample indices of the tightest corners, at least ~140 m apart.
func _corner_indices(count: int) -> Array:
	var n: int = track.sample_count()
	var cand: Array = []
	for i in n:
		cand.append([absf(float(track.curvature[i])), i])
	cand.sort_custom(func(a, b): return float(a[0]) > float(b[0]))
	var out: Array = []
	for c in cand:
		var i: int = c[1]
		var ok := true
		for o in out:
			var d := absi(i - int(o))
			if mini(d, n - d) < 70:
				ok = false
				break
		if track.samples[i].y > 0.15:
			ok = false        # raised road (the city expressway)
		# keep the start/finish area free (the grandstand is there)
		var ds := absi(i - int(track.start_index))
		if mini(ds, n - ds) < 25:
			ok = false
		# the Grüne Hölle's pit straight (pit lane, garages, grandstands): no corner crowd, net or flags
		if track.track_id == "gruene_hoelle":
			var rel := fposmod(float(track.dists[i]) - float(track.start_dist) + float(track.length) * 0.5, float(track.length)) - float(track.length) * 0.5
			if rel > -300.0 and rel < 160.0:
				ok = false
		if ok:
			out.append(i)
		if out.size() >= count:
			break
	return out


func _build_zone(center: int, quality: int) -> void:
	var n: int = track.sample_count()
	var k: float = track.curvature[center]
	var side := 1.0 if k > 0.0 else -1.0   # outside of the corner
	var half := 14
	var rows: int = [2, 3, 3, 4][clampi(quality, 0, 3)]
	var xfs: Array = []
	var customs: Array = []
	var net := MeshKit.new_st()
	var posts: Array = []
	for s in range(center - half, center + half + 1):
		var i := (s % n + n) % n
		var off: float = track.off_left[i] if side < 0.0 else track.off_right[i]
		var right: Vector3 = track.rights[i] * side
		var tangent: Vector3 = track.tangents[i]
		var base: Vector3 = track.samples[i]
		# safety net 2 m behind the barrier
		var net_p: Vector3 = base + right * (off + 2.0)
		net_p.y = terrain.height_at(net_p.x, net_p.z)
		posts.append(net_p)
		for r in rows:
			for slot in 2:
				if rng.randf() < 0.18:
					continue
				var along := (float(slot) - 0.5) * 1.0 + rng.randf_range(-0.25, 0.25)
				var p: Vector3 = base + right * (off + 3.2 + r * 1.05 + rng.randf_range(-0.2, 0.2)) + tangent * along
				var nrm: Vector3 = terrain.normal_at(p.x, p.z)
				if nrm.y < 0.7:
					continue
				p.y = terrain.height_at(p.x, p.z)
				var look: Vector3 = base + tangent * rng.randf_range(-8.0, 8.0) - p
				look.y = 0.0
				var b := Basis.looking_at(look.normalized(), Vector3.UP)
				var sc := rng.randf_range(0.9, 1.08)
				xfs.append(Transform3D(b.scaled(Vector3(sc, sc * rng.randf_range(0.95, 1.06), sc)), p))
				var shirt: Color = SHIRTS[rng.randi() % SHIRTS.size()]
				customs.append(Color(shirt.r, shirt.g, shirt.b, rng.randf()))
		scenery.occupy(base + right * (off + 4.5), 3.5)
	_add_people(xfs, customs, "Crowd")
	_build_net(posts)
	# flags and tents behind the people
	for f in 3:
		var s2 := center + rng.randi_range(-half, half)
		var i2 := (s2 % n + n) % n
		var off2: float = track.off_left[i2] if side < 0.0 else track.off_right[i2]
		var fp: Vector3 = track.samples[i2] + track.rights[i2] * side * (off2 + 4.0 + rows * 1.05 + rng.randf_range(0.5, 2.0))
		fp.y = terrain.height_at(fp.x, fp.z)
		_flag(fp)
	for t in 2:
		var s3 := center + rng.randi_range(-half, half)
		var i3 := (s3 % n + n) % n
		var off3: float = track.off_left[i3] if side < 0.0 else track.off_right[i3]
		var tp: Vector3 = track.samples[i3] + track.rights[i3] * side * (off3 + 6.5 + rows * 1.05)
		if scenery.free_at(tp, 2.5, 4.0):
			tp.y = terrain.height_at(tp.x, tp.z)
			_tent(tp, track.tangents[i3])
			scenery.occupy(tp, 2.5)


func _build_grandstand() -> void:
	var g: Transform3D = track.gantry_xf
	var span: float = track.stand_x
	var xfs: Array = []
	var customs: Array = []
	for k in 5:
		var x: float = span + 5.6 + k * 0.7
		var y: float = 2.75 + k * 0.5
		var z := -14.0
		while z < 14.0:
			if rng.randf() > 0.12:
				var local := Vector3(x + rng.randf_range(-0.1, 0.1), y, z + rng.randf_range(-0.15, 0.15))
				# face the track (-X in gantry space)
				var b := g.basis * Basis.looking_at(Vector3(-1, 0, rng.randf_range(-0.3, 0.3)).normalized(), Vector3.UP)
				var sc := rng.randf_range(0.92, 1.06)
				xfs.append(Transform3D(b.scaled(Vector3(sc, sc, sc)), g * local))
				var shirt: Color = SHIRTS[rng.randi() % SHIRTS.size()]
				customs.append(Color(shirt.r, shirt.g, shirt.b, rng.randf()))
			z += rng.randf_range(0.75, 1.0)
	_add_people(xfs, customs, "Grandstand")


func _add_people(xfs: Array, customs: Array, label: String) -> void:
	if xfs.is_empty():
		return
	var center := Vector3.ZERO
	for xf in xfs:
		center += (xf as Transform3D).origin
	center /= float(xfs.size())
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = person_mesh()
	mm.instance_count = xfs.size()
	for i in xfs.size():
		var xf: Transform3D = xfs[i]
		mm.set_instance_transform(i, Transform3D(xf.basis, xf.origin - center))
		mm.set_instance_custom_data(i, customs[i])
		if scenery != null and scenery.people != null:
			scenery.people.register(mm, i, xf, customs[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.name = label
	mmi.position = center
	mmi.visibility_range_end = 320.0
	mmi.visibility_range_end_margin = 20.0
	add_child(mmi)


## Low-poly person facing -Z, feet at y = 0. COLOR.r = body part, COLOR.a = arm flag (0.5 left, 1 right).
static func person_mesh() -> ArrayMesh:
	if _person_mesh:
		return _person_mesh
	var st := MeshKit.new_st()
	var pants := Color(0.1, 0, 0, 0)
	var shirt := Color(0.3, 0, 0, 0)
	var skin := Color(0.5, 0, 0, 0)
	var hair := Color(0.7, 0, 0, 0)
	var shoes := Color(0.9, 0, 0, 0)
	for side: float in [-1.0, 1.0]:
		MeshKit.box(st, Transform3D(Basis.IDENTITY, Vector3(side * 0.1, 0.045, -0.03)), Vector3(0.12, 0.09, 0.27), shoes)
		MeshKit.box(st, Transform3D(Basis.IDENTITY, Vector3(side * 0.1, 0.5, 0)), Vector3(0.14, 0.82, 0.16), pants)
		var arm_flag := 0.5 if side < 0.0 else 1.0
		var sleeve := Color(shirt.r, 0, 0, arm_flag)
		var hand := Color(skin.r, 0, 0, arm_flag)
		MeshKit.box(st, Transform3D(Basis.IDENTITY, Vector3(side * 0.27, 1.27, 0)), Vector3(0.11, 0.34, 0.12), sleeve)
		MeshKit.box(st, Transform3D(Basis.IDENTITY, Vector3(side * 0.27, 0.95, 0)), Vector3(0.09, 0.3, 0.1), hand)
	MeshKit.box(st, Transform3D(Basis.IDENTITY, Vector3(0, 0.95, 0)), Vector3(0.36, 0.2, 0.2), pants)
	MeshKit.box(st, Transform3D(Basis.IDENTITY, Vector3(0, 1.22, 0)), Vector3(0.42, 0.52, 0.24), shirt)
	MeshKit.box(st, Transform3D(Basis.IDENTITY, Vector3(0, 1.51, 0)), Vector3(0.1, 0.08, 0.1), skin)
	MeshKit.box(st, Transform3D(Basis.IDENTITY, Vector3(0, 1.64, -0.01)), Vector3(0.19, 0.22, 0.21), skin)
	MeshKit.box(st, Transform3D(Basis.IDENTITY, Vector3(0, 1.765, 0.01)), Vector3(0.2, 0.06, 0.22), hair)
	var mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = CROWD_SHADER
	mat.shader = sh
	_person_mesh = MeshKit.commit(st, mat)
	return _person_mesh


func _build_net(posts: Array) -> void:
	if posts.size() < 2:
		return
	if _net_mat == null:
		_net_mat = StandardMaterial3D.new()
		_net_mat.albedo_color = Color(1.0, 0.45, 0.08)
		_net_mat.roughness = 0.8
	# a real net: ropes along it (thicker top and bottom), strands every 30 cm, posts every other sample
	var st := MeshKit.new_st()
	var pole := MeshKit.new_st()
	for i in range(posts.size() - 1):
		var a: Vector3 = posts[i]
		var b: Vector3 = posts[i + 1]
		var len := a.distance_to(b)
		if len < 0.05:
			continue
		var dir := (b - a) / len
		var basis := Basis.looking_at(dir, Vector3.UP)
		var mid := (a + b) * 0.5
		for r in 6:
			var y := 0.08 + r * 0.232
			var th := 0.035 if (r == 0 or r == 5) else 0.018
			MeshKit.box(st, Transform3D(basis, mid + Vector3(0, y, 0)), Vector3(th, th, len + 0.02))
		var k := maxi(int(len / 0.3), 1)
		for j in k:
			var p := a.lerp(b, (j + 0.5) / k)
			MeshKit.box(st, Transform3D(basis, p + Vector3(0, 0.66, 0)), Vector3(0.016, 1.16, 0.016))
		if i % 2 == 0:
			MeshKit.box(pole, Transform3D(Basis.IDENTITY, a + Vector3(0, 0.7, 0)), Vector3(0.06, 1.4, 0.06))
	var mi := MeshKit.mesh_instance(MeshKit.commit(st, _net_mat), null, false)
	mi.name = "SafetyNet"
	mi.visibility_range_end = 300.0
	add_child(mi)
	var pm := MeshKit.mesh_instance(MeshKit.commit(pole, TexKit.std(Color(0.3, 0.3, 0.32), 0.5, 0.6)), null, false)
	pm.visibility_range_end = 350.0
	add_child(pm)


func _flag(pos: Vector3) -> void:
	var root := Node3D.new()
	root.name = "Flag"
	root.position = pos
	root.rotation.y = rng.randf() * TAU
	add_child(root)
	root.add_child(MeshKit.cyl_node(0.03, 0.04, 5.0, TexKit.std(Color(0.8, 0.8, 0.82), 0.3, 0.8), Vector3(0, 2.5, 0), Vector3.ZERO, 8))
	var pm := PlaneMesh.new()
	pm.size = Vector2(1.6, 1.0)
	pm.subdivide_width = 8
	pm.subdivide_depth = 3
	pm.orientation = PlaneMesh.FACE_Z
	var mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = FLAG_SHADER
	mat.shader = sh
	var c: Color = SHIRTS[rng.randi() % SHIRTS.size()]
	mat.set_shader_parameter("flag_color", c)
	mat.set_shader_parameter("stripe_color", Color(1, 1, 1) if c.v < 0.8 else Color(0.1, 0.1, 0.1))
	var mi := MeshKit.mesh_instance(pm, mat, true)
	mi.position = Vector3(0.82, 4.4, 0)
	mi.visibility_range_end = 400.0
	root.add_child(mi)


func _tent(pos: Vector3, along: Vector3) -> void:
	var root := Node3D.new()
	root.name = "Tent"
	add_child(root)
	root.global_transform = Transform3D(Basis.looking_at(along, Vector3.UP), pos)
	var c: Color = SHIRTS[rng.randi() % SHIRTS.size()]
	var cloth := TexKit.std(c, 0.7)
	cloth.cull_mode = BaseMaterial3D.CULL_DISABLED
	var legs := TexKit.std(Color(0.75, 0.75, 0.78), 0.4, 0.7)
	for sx: float in [-1.4, 1.4]:
		for sz: float in [-1.4, 1.4]:
			root.add_child(MeshKit.box_node(Vector3(0.05, 2.2, 0.05), legs, Vector3(sx, 1.1, sz)))
	var roof := PrismMesh.new()
	roof.size = Vector3(3.0, 0.7, 3.0)
	var r1 := MeshKit.mesh_instance(roof, cloth)
	r1.position = Vector3(0, 2.55, 0)
	root.add_child(r1)
	var r2 := MeshKit.mesh_instance(roof, cloth)
	r2.position = Vector3(0, 2.55, 0)
	r2.rotation.y = PI * 0.5
	root.add_child(r2)
	root.add_child(MeshKit.box_node(Vector3(1.6, 0.75, 0.6), TexKit.std(Color(0.9, 0.9, 0.9), 0.6), Vector3(0, 0.375, 0.6)))

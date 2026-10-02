extends Node3D
## Pigeons: flocks pecking on pavements, plazas and in the parks. When a car comes close (or the
## camera walks into them) the whole flock flutters up, circles a moment and lands again a little
## further away. One MultiMesh per flock; the wing beat and the pecking are done in the shader.

const MeshKit = preload("res://scripts/util/mesh_kit.gd")

const SHADER := """
shader_type spatial;
render_mode diffuse_burley;

varying vec3 col;

void vertex() {
	col = COLOR.rgb;
	float part = COLOR.a;             // 1 body, 0.75 head, 0.5 left wing, 0.25 right wing
	float fly = INSTANCE_CUSTOM.r;
	float ph = INSTANCE_CUSTOM.g * 6.2831 + float(INSTANCE_ID) * 1.7;
	if (part < 0.6) {
		float side = part > 0.4 ? -1.0 : 1.0;
		float a = fly > 0.5 ? sin(TIME * 22.0 + ph) * 1.1 : -0.15;
		vec3 pivot = vec3(0.06 * side, 0.15, 0.0);
		vec3 v = VERTEX - pivot;
		float c = cos(a * side);
		float s = sin(a * side);
		VERTEX = pivot + vec3(v.x * c - v.y * s, v.x * s + v.y * c, v.z);
	} else if (part < 0.8 && fly < 0.5) {
		// pecking: the head dips now and then
		float peck = max(sin(TIME * 2.3 + ph), 0.0);
		peck = pow(peck, 8.0);
		VERTEX.y -= peck * 0.09;
		VERTEX.z -= peck * 0.04;
	}
}

void fragment() {
	ALBEDO = col;
	ROUGHNESS = 0.8;
}
"""

var flocks: Array = []           # {home, birds: [{p, yaw, v, spot}], mm, state, t, scare_cool}
var cars: Callable               # () -> Array of [position, speed]
var _mesh: ArrayMesh
var rng := RandomNumberGenerator.new()
var stats := {}


func _ready() -> void:
	rng.seed = 1212


func add_flock(home: Vector3, n: int, radius: float) -> void:
	if _mesh == null:
		_mesh = _pigeon_mesh()
	var birds: Array = []
	for k in n:
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * radius
		var p := home + Vector3(cos(a) * r, 0, sin(a) * r)
		birds.append({"p": p, "yaw": rng.randf() * TAU, "v": Vector3.ZERO, "spot": p, "phase": rng.randf()})
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = _mesh
	mm.instance_count = n
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.visibility_range_end = 140.0
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# placed at the flock (visibility ranges are measured from the node, not from the birds)
	mmi.position = home
	mmi.custom_aabb = AABB(Vector3(-40, -2, -40), Vector3(80, 30, 80))
	add_child(mmi)
	var f := {"home": home, "origin": home, "radius": radius, "birds": birds, "mm": mm, "mmi": mmi, "state": "ground", "t": 0.0, "cool": 0.0}
	flocks.append(f)
	_write(f)
	stats["pigeons"] = int(stats.get("pigeons", 0)) + n


func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var cp := cam.global_position
	var list: Array = cars.call() if cars.is_valid() else []
	for f in flocks:
		var home: Vector3 = f["home"]
		if home.distance_to(cp) > 150.0:
			continue
		f["cool"] = float(f["cool"]) - delta
		if f["state"] == "ground":
			# a car close by and moving, or the camera right in the flock: up they go
			var threat := Vector3.INF
			for c in list:
				var cpos: Vector3 = c[0]
				if Vector2(cpos.x - home.x, cpos.z - home.z).length() < float(f["radius"]) + 11.0 and float(c[1]) > 2.0:
					threat = cpos
			if threat == Vector3.INF and Vector2(cp.x - home.x, cp.z - home.z).length() < float(f["radius"]) + 2.0 and cp.y < home.y + 4.0:
				threat = cp
			if threat != Vector3.INF and float(f["cool"]) <= 0.0:
				_scare(f, threat)
		else:
			_fly(f, delta)


func _scare(f: Dictionary, from: Vector3) -> void:
	f["state"] = "fly"
	f["t"] = 0.0
	# a new place to land: some way off, away from whatever scared them
	var home: Vector3 = f["home"]
	var away := Vector3(home.x - from.x, 0, home.z - from.z)
	if away.length() < 0.1:
		away = Vector3(1, 0, 0)
	away = away.normalized().rotated(Vector3.UP, rng.randf_range(-0.7, 0.7))
	f["land"] = home + away * rng.randf_range(10.0, 22.0)
	for b in f["birds"]:
		var p: Vector3 = b["p"]
		var out := Vector3(p.x - from.x, 0, p.z - from.z).normalized()
		b["v"] = out * rng.randf_range(2.5, 5.0) + Vector3(0, rng.randf_range(3.5, 6.0), 0)


func _fly(f: Dictionary, delta: float) -> void:
	f["t"] = float(f["t"]) + delta
	var t: float = f["t"]
	var land: Vector3 = f["land"]
	var r: float = f["radius"]
	var all_down := true
	for b in f["birds"]:
		var p: Vector3 = b["p"]
		var v: Vector3 = b["v"]
		if t < 2.5:
			# climb and scatter, a little circling
			v += Vector3(0, -2.0, 0) * delta + Vector3(-v.z, 0, v.x).normalized() * 1.2 * delta
			if p.y > land.y + 7.0:
				v.y = minf(v.y, 0.5)
		else:
			# glide down to a spot around the landing point
			if not b.has("dest") or b["dest"] == null:
				var a := rng.randf() * TAU
				b["dest"] = land + Vector3(cos(a), 0, sin(a)) * sqrt(rng.randf()) * r
			var dest: Vector3 = b["dest"]
			var to := dest - p
			v = v.lerp(to.normalized() * minf(to.length() * 1.5, 6.0), minf(delta * 2.5, 1.0))
			if to.length() < 0.15:
				p = dest
				v = Vector3.ZERO
		p += v * delta
		p.y = maxf(p.y, land.y)
		if v.length() > 0.2:
			b["yaw"] = atan2(v.x, v.z)
			all_down = false
		b["p"] = p
		b["v"] = v
	if t > 3.0 and all_down:
		f["state"] = "ground"
		f["home"] = land
		f["cool"] = 4.0
		for b in f["birds"]:
			b["dest"] = null
	_write(f)


func _write(f: Dictionary) -> void:
	var mm: MultiMesh = f["mm"]
	var origin: Vector3 = f["origin"]
	var flying: bool = f["state"] == "fly"
	var birds: Array = f["birds"]
	for k in birds.size():
		var b: Dictionary = birds[k]
		var air := flying and (b["v"] as Vector3).length() > 0.2
		mm.set_instance_transform(k, Transform3D(Basis(Vector3.UP, float(b["yaw"])), (b["p"] as Vector3) - origin))
		mm.set_instance_custom_data(k, Color(1.0 if air else 0.0, float(b["phase"]), 0, 0))


## A low-poly pigeon facing +Z: grey body, darker head with the green-purple neck sheen, wings
## (flagged for the wing beat), tail, pink feet.
static func _pigeon_mesh() -> ArrayMesh:
	var st := MeshKit.new_st()
	var body := Color(0.55, 0.57, 0.62, 1.0)
	var dark := Color(0.32, 0.34, 0.4, 0.75)
	MeshKit.box(st, Transform3D(Basis(Vector3(1, 0, 0), -0.25), Vector3(0, 0.15, 0)), Vector3(0.13, 0.12, 0.26), body)
	MeshKit.box(st, Transform3D(Basis.IDENTITY, Vector3(0, 0.23, 0.11)), Vector3(0.08, 0.09, 0.09), dark)
	MeshKit.box(st, Transform3D(Basis.IDENTITY, Vector3(0, 0.19, 0.09)), Vector3(0.09, 0.06, 0.06), Color(0.3, 0.55, 0.45, 0.75))
	MeshKit.box(st, Transform3D(Basis.IDENTITY, Vector3(0, 0.215, 0.165)), Vector3(0.025, 0.02, 0.04), Color(0.2, 0.2, 0.2, 0.75))
	MeshKit.box(st, Transform3D(Basis(Vector3(1, 0, 0), 0.2), Vector3(0, 0.15, -0.17)), Vector3(0.1, 0.02, 0.1), dark.darkened(0.2))
	for side: float in [-1.0, 1.0]:
		var flag := 0.5 if side < 0.0 else 0.25
		MeshKit.box(st, Transform3D(Basis.IDENTITY, Vector3(side * 0.13, 0.16, -0.01)), Vector3(0.16, 0.02, 0.17), Color(0.5, 0.52, 0.58, flag))
		MeshKit.box(st, Transform3D(Basis.IDENTITY, Vector3(side * 0.03, 0.04, 0.02)), Vector3(0.02, 0.08, 0.02), Color(0.85, 0.45, 0.45, 1.0))
	var m := ShaderMaterial.new()
	m.shader = Shader.new()
	m.shader.code = SHADER
	return MeshKit.commit(st, m)

extends Node3D
## Draws all NPC traffic (race route and city streets): a Toyota Camry, a Subaru Impreza WRX STI and a
## Honda Civic Type-R (assets/cars/traffic, converted by tools/convert_cars.py) as MultiMeshes in three
## tiers (detailed close up, light further away, without shadows in the distance). The wheels turn in
## the shader from each car's odometer; brake lights light up, head and tail lights glow at night.
## The traffic systems call add() for every car each frame; a small pool of solid boxes follows the
## cars closest to the players (they push you; a crash doesn't throw them off their lane).

const Sfx = preload("res://scripts/util/sfx_kit.gd")

const MODELS := ["camry", "impreza", "civic"]
const WEIGHTS := [4, 3, 3]
## Paints: lots of white, silver and black like real Japanese traffic, some colour.
const PAINTS := [Color(0.93, 0.93, 0.91), Color(0.93, 0.93, 0.91), Color(0.95, 0.95, 0.96), Color(0.62, 0.63, 0.66),
	Color(0.62, 0.63, 0.66), Color(0.05, 0.05, 0.06), Color(0.05, 0.05, 0.06), Color(0.32, 0.33, 0.35),
	Color(0.06, 0.14, 0.42), Color(0.55, 0.04, 0.04), Color(0.1, 0.22, 0.14), Color(0.72, 0.66, 0.55)]
const STI_BLUE := Color(0.02, 0.12, 0.48)
const CIVIC_RED := Color(0.72, 0.03, 0.03)
## Tiers: [up to (m), detailed model, shadows]
const TIERS := [[75.0, true, true], [200.0, false, true], [480.0, false, false]]
const CAPACITY := [80, 260, 420]
const POOL := 20
const BRAKE_FLAG := 5000.0      # custom.a = odometer (wrapped) + this while braking
const VOICES := 6               # soft engine sounds on the cars closest to the camera
const SOUND_RANGE := 60.0

const SHADER := """
shader_type spatial;
render_mode diffuse_burley;

uniform vec3 albedo : source_color = vec3(0.5);
uniform float metallic = 0.0;
uniform float roughness = 0.5;
uniform float paint = 0.0;        // 1: the colour comes from the instance (car paint)
uniform float lamp = 0.0;         // 1 head light, 2 tail light, 3 indicator
uniform float night = 0.0;
uniform float hub_y = 0.3;
uniform float front_z = -1.3;
uniform float rear_z = 1.3;
uniform float wheel_r = 0.3;

varying vec4 inst;

void vertex() {
	inst = INSTANCE_CUSTOM;
	if (COLOR.a > 0.5) {
		// a wheel: turn it about its axle by the distance driven
		float odo = INSTANCE_CUSTOM.a - step(5000.0, INSTANCE_CUSTOM.a) * 5000.0;
		float ang = -odo / wheel_r;
		float hz = VERTEX.z < 0.0 ? front_z : rear_z;
		vec2 yz = VERTEX.yz - vec2(hub_y, hz);
		float c = cos(ang);
		float s = sin(ang);
		VERTEX.yz = vec2(hub_y, hz) + vec2(yz.x * c - yz.y * s, yz.x * s + yz.y * c);
		NORMAL.yz = vec2(NORMAL.y * c - NORMAL.z * s, NORMAL.y * s + NORMAL.z * c);
	}
}

void fragment() {
	vec3 base = paint > 0.5 ? inst.rgb : albedo;
	ALBEDO = base;
	METALLIC = metallic;
	ROUGHNESS = roughness;
	if (paint > 0.5) {
		CLEARCOAT = 1.0;
		CLEARCOAT_ROUGHNESS = 0.08;
	}
	float brake = step(5000.0, inst.a);
	if (lamp > 0.5 && lamp < 1.5) {
		EMISSION = vec3(1.0, 0.95, 0.86) * (0.15 + 4.0 * night);
	} else if (lamp > 1.5 && lamp < 2.5) {
		EMISSION = vec3(1.0, 0.05, 0.02) * (0.1 + 1.5 * night + 3.5 * brake);
	} else if (lamp > 2.5) {
		EMISSION = vec3(1.0, 0.4, 0.05) * 0.15;
	}
}
"""

## Per model: {size: Vector3 (width, height, length), half: half length, radius, wrap, meshes: [hi, lo], mm: [3 MultiMeshes]}
var models: Array = []
var world
var _shader: Shader
var _mats: Array = []
var _night := -1.0
var _counts: Array = []          # [model][tier]
var _cam := Vector3.ZERO
var _players: Array = []         # positions of the player and bot cars
var _cand: Array = []            # [distance², Transform3D, model] close to a player
var _bodies: Array = []
var _shapes: Array = []
var ok := false
var _snd: Array = []             # AudioStreamPlayer3D pool
var _snd_cand: Array = []        # [distance², position, speed]


func setup(p_world) -> void:
	world = p_world
	_shader = Shader.new()
	_shader.code = SHADER
	for name in MODELS:
		var m := _load(name)
		if m.is_empty():
			push_warning("traffic car %s missing (not imported?)" % name)
			continue
		m["name"] = name
		models.append(m)
	if models.is_empty():
		return
	ok = true
	for m in models:
		var mms: Array = []
		for t in TIERS.size():
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_custom_data = true
			mm.mesh = (m["meshes"] as Array)[0 if bool(TIERS[t][1]) else 1]
			mm.instance_count = CAPACITY[t]
			mm.visible_instance_count = 0
			var mmi := MultiMeshInstance3D.new()
			mmi.name = "Traffic_%s_%d" % [m["name"], t]
			mmi.multimesh = mm
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if bool(TIERS[t][2]) else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			# the cars are spread over the whole map
			mmi.custom_aabb = AABB(Vector3(-6000, -200, -6000), Vector3(12000, 600, 12000))
			add_child(mmi)
			mms.append(mm)
		m["mm"] = mms
		_counts.append([0, 0, 0])
	for k in POOL:
		var body := AnimatableBody3D.new()
		body.name = "TrafficBody%d" % k
		body.sync_to_physics = true
		body.collision_layer = 0
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(1.8, 1.4, 4.5)
		cs.shape = box
		cs.position = Vector3(0, 0.75, 0)
		body.add_child(cs)
		add_child(body)
		body.global_position = Vector3(0, -500.0 - k * 10.0, 0)
		_bodies.append(body)
		_shapes.append([box, cs])
	# draw after the traffic systems have added their cars for this frame
	process_priority = 100
	for k in VOICES:
		var a := AudioStreamPlayer3D.new()
		a.stream = Sfx.get_sound("traffic_engine")
		a.unit_size = 7.0
		a.max_distance = SOUND_RANGE
		a.volume_db = -80.0
		a.attenuation_filter_cutoff_hz = 6000.0
		add_child(a)
		_snd.append([a, 0.0])


## A random model (index into models) and a paint for it.
func pick(rng: RandomNumberGenerator) -> Array:
	var total := 0
	var ids: Array = []
	for i in models.size():
		var w: int = WEIGHTS[MODELS.find(models[i]["name"])]
		total += w
		ids.append([i, w])
	var r := rng.randi_range(0, total - 1)
	var mi := 0
	for e in ids:
		r -= int(e[1])
		if r < 0:
			mi = int(e[0])
			break
	var name: String = models[mi]["name"]
	var paint: Color = PAINTS[rng.randi() % PAINTS.size()]
	if name == "impreza" and rng.randf() < 0.45:
		paint = STI_BLUE
	elif name == "civic" and rng.randf() < 0.3:
		paint = CIVIC_RED
	return [mi, paint]


func half_length(model: int) -> float:
	return float(models[model]["half"])


## One car for this frame. odo: metres driven (turns the wheels); speed in m/s (its engine sound).
func add(model: int, xf: Transform3D, paint: Color, odo: float, brake: bool, speed := 0.0) -> void:
	var d2 := _cam.distance_squared_to(xf.origin)
	if d2 < SOUND_RANGE * SOUND_RANGE:
		_snd_cand.append([d2, xf.origin, speed])
	var m: Dictionary = models[model]
	for p in _players:
		var pd := (p as Vector3).distance_squared_to(xf.origin)
		if pd < 2500.0:
			_cand.append([pd, xf, model])
			break
	var t := 0
	while t < TIERS.size() and d2 > float(TIERS[t][0]) * float(TIERS[t][0]):
		t += 1
	if t >= TIERS.size():
		return
	var c: Array = _counts[model]
	var mm: MultiMesh = (m["mm"] as Array)[t]
	var k: int = c[t]
	if k >= mm.instance_count:
		return
	mm.set_instance_transform(k, xf)
	mm.set_instance_custom_data(k, Color(paint.r, paint.g, paint.b, fposmod(odo, float(m["wrap"])) + (BRAKE_FLAG if brake else 0.0)))
	c[t] = k + 1


func _process(_delta: float) -> void:
	if not ok:
		return
	for i in models.size():
		var mms: Array = models[i]["mm"]
		var c: Array = _counts[i]
		for t in TIERS.size():
			(mms[t] as MultiMesh).visible_instance_count = int(c[t])
			c[t] = 0
	_update_sound()
	# where the camera and the players are, for the next frame
	var cam := get_viewport().get_camera_3d()
	if cam:
		_cam = cam.global_position
	_players.clear()
	if world != null:
		for car in world.cars.values():
			if is_instance_valid(car) and car.visible:
				_players.append(car.global_position)
	var n: float = world.atmosphere.night if world != null and world.atmosphere != null else 0.0
	if absf(n - _night) > 0.01:
		_night = n
		for mat in _mats:
			(mat as ShaderMaterial).set_shader_parameter("night", n)


## The nearest few cars hum softly: louder and higher the faster they go, a quiet idle when stopped.
func _update_sound() -> void:
	_snd_cand.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	var dt := get_process_delta_time()
	for k in _snd.size():
		var v: Array = _snd[k]
		var a: AudioStreamPlayer3D = v[0]
		if k < _snd_cand.size():
			var c: Array = _snd_cand[k]
			var spd: float = c[2]
			a.global_position = c[1]
			var want := lerpf(-24.0, -12.0, clampf(spd / 16.0, 0.0, 1.0))
			v[1] = move_toward(float(v[1]), 1.0, dt * 2.0)
			a.volume_db = lerpf(-60.0, want, float(v[1]))
			a.pitch_scale = 0.8 + spd * 0.045
			if not a.playing:
				a.play(randf())
		else:
			v[1] = move_toward(float(v[1]), 0.0, dt * 3.0)
			a.volume_db = lerpf(-60.0, a.volume_db, float(v[1])) if float(v[1]) > 0.0 else -80.0
			if float(v[1]) <= 0.0 and a.playing:
				a.stop()
	_snd_cand.clear()


func _physics_process(_delta: float) -> void:
	if not ok:
		return
	_cand.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	for k in POOL:
		var body: AnimatableBody3D = _bodies[k]
		if k < _cand.size():
			var e: Array = _cand[k]
			var m: Dictionary = models[int(e[2])]
			var sz: Vector3 = m["size"]
			var sh: Array = _shapes[k]
			if not (sh[0] as BoxShape3D).size.is_equal_approx(sz):
				(sh[0] as BoxShape3D).size = sz
				(sh[1] as CollisionShape3D).position = Vector3(0, sz.y * 0.5 + 0.05, 0)
			body.collision_layer = 1
			body.global_transform = e[1]
		elif body.collision_layer != 0:
			body.collision_layer = 0
			body.global_position = Vector3(0, -500.0 - k * 10.0, 0)
	_cand.clear()


# ---------------------------------------------------------------------------
# Models
# ---------------------------------------------------------------------------
## Both detail levels of a car merged into one mesh each (one surface per material class), the wheel
## vertices flagged (vertex colour alpha) for the shader.
func _load(name: String) -> Dictionary:
	var hi := _merge("res://assets/cars/traffic/%s.glb" % name)
	if hi.is_empty():
		return {}
	var lo := _merge("res://assets/cars/traffic/%s_lo.glb" % name)
	if lo.is_empty():
		lo = hi
	var hubs: Dictionary = hi["hubs"]
	var front_z := 0.0
	var rear_z := 0.0
	var hub_y := 0.0
	var nf := 0
	var nr := 0
	for key in hubs:
		var h: Vector3 = hubs[key]
		hub_y += h.y / hubs.size()
		if h.z < 0.0:
			front_z += h.z
			nf += 1
		else:
			rear_z += h.z
			nr += 1
	front_z /= maxf(nf, 1)
	rear_z /= maxf(nr, 1)
	var radius: float = hi["radius"]
	var mats := {}
	for res: Dictionary in [hi, lo]:
		var mesh: ArrayMesh = res["mesh"]
		for s in mesh.get_surface_count():
			var cls: String = (res["classes"] as Array)[s]
			if not mats.has(cls):
				mats[cls] = _material(cls, res["albedo"][s], hub_y, front_z, rear_z, radius)
			mesh.surface_set_material(s, mats[cls])
	var aabb: AABB = (hi["mesh"] as ArrayMesh).get_aabb()
	if aabb.size.z < 1.0:
		aabb = AABB(Vector3(-0.9, 0, -2.3), Vector3(1.8, 1.45, 4.6))     # headless: no mesh data
	if radius < 0.1:
		radius = 0.32
	return {"meshes": [hi["mesh"], lo["mesh"]], "size": Vector3(aabb.size.x * 0.92, aabb.size.y * 0.9, aabb.size.z * 0.98),
		"half": aabb.size.z * 0.5, "radius": radius, "wrap": TAU * radius * 200.0}


func _material(cls: String, base: Array, hub_y: float, front_z: float, rear_z: float, radius: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _shader
	m.set_shader_parameter("albedo", base[0])
	m.set_shader_parameter("metallic", base[1])
	m.set_shader_parameter("roughness", base[2])
	m.set_shader_parameter("paint", 1.0 if cls == "paint" else 0.0)
	var lamp := 0.0
	if cls == "head_lens" or cls == "head_inner":
		lamp = 1.0
	elif cls == "tail":
		lamp = 2.0
	elif cls == "indicator":
		lamp = 3.0
	m.set_shader_parameter("lamp", lamp)
	if cls == "glass":
		m.set_shader_parameter("albedo", Color(0.02, 0.025, 0.03))
		m.set_shader_parameter("metallic", 0.4)
		m.set_shader_parameter("roughness", 0.04)
	m.set_shader_parameter("hub_y", hub_y)
	m.set_shader_parameter("front_z", front_z)
	m.set_shader_parameter("rear_z", rear_z)
	m.set_shader_parameter("wheel_r", radius)
	_mats.append(m)
	return m


static func _merge(path: String) -> Dictionary:
	if not ResourceLoader.exists(path):
		return {}
	var ps := load(path) as PackedScene
	if ps == null:
		return {}
	var root := ps.instantiate()
	var by_class := {}            # class -> [verts, normals, colours, indices, [albedo, metallic, roughness]]
	var hubs := {}
	var radius := 0.0
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var mesh := mi.mesh
		if mesh == null:
			continue
		var xf := Transform3D.IDENTITY
		var n: Node = mi
		while n != null and n != root:
			if n is Node3D:
				xf = (n as Node3D).transform * xf
			n = n.get_parent()
		var nm := str(mi.name).to_lower()
		var wheel := nm.begins_with("wheel_")
		if wheel:
			hubs[nm.substr(6, 2)] = xf.origin
			radius = maxf(radius, mesh.get_aabb().size.y * 0.5)
		var rot := Transform3D(xf.basis.orthonormalized(), Vector3.ZERO)
		for s in mesh.get_surface_count():
			var arr := mesh.surface_get_arrays(s)
			var mat := mesh.surface_get_material(s)
			if mi.get_surface_override_material(s) != null:
				mat = mi.get_surface_override_material(s)
			var cls := "black"
			var base := [Color(0.05, 0.05, 0.05), 0.0, 0.6]
			if mat != null:
				cls = str(mat.resource_name).trim_prefix("md_")
				if mat is BaseMaterial3D:
					var bm := mat as BaseMaterial3D
					base = [bm.albedo_color, bm.metallic, bm.roughness]
			if not by_class.has(cls):
				by_class[cls] = [PackedVector3Array(), PackedVector3Array(), PackedColorArray(), PackedInt32Array(), base]
			var b: Array = by_class[cls]
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var nrm: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			# (packed arrays are copied out of an Array: append to a local, store it back)
			var vv: PackedVector3Array = b[0]
			var nn: PackedVector3Array = b[1]
			var cc: PackedColorArray = b[2]
			var start: int = vv.size()
			vv.append_array(xf * verts)
			nn.append_array(rot * nrm)
			var cols := PackedColorArray()
			cols.resize(verts.size())
			cols.fill(Color(1, 1, 1, 1.0 if wheel else 0.0))
			cc.append_array(cols)
			b[0] = vv
			b[1] = nn
			b[2] = cc
			var idx = arr[Mesh.ARRAY_INDEX]
			var out: PackedInt32Array = b[3]
			if idx == null or (idx as PackedInt32Array).is_empty():
				for i in verts.size():
					out.append(start + i)
			else:
				for i in (idx as PackedInt32Array):
					out.append(start + i)
			b[3] = out
	root.free()
	if by_class.is_empty():
		return {}
	var mesh := ArrayMesh.new()
	var classes: Array = []
	var albedo: Array = []
	for cls in by_class:
		var b: Array = by_class[cls]
		if (b[0] as PackedVector3Array).is_empty():
			continue        # (no mesh data without a renderer: headless)
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = b[0]
		arr[Mesh.ARRAY_NORMAL] = b[1]
		arr[Mesh.ARRAY_COLOR] = b[2]
		arr[Mesh.ARRAY_INDEX] = b[3]
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		classes.append(cls)
		albedo.append(b[4])
	return {"mesh": mesh, "classes": classes, "albedo": albedo, "hubs": hubs, "radius": radius}

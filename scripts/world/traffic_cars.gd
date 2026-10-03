extends Node3D
## Draws all NPC traffic (race route and city streets): a Toyota Camry, a Subaru Impreza WRX STI and a
## Honda Civic Type-R (assets/cars/traffic, converted by tools/convert_cars.py) as MultiMeshes in three
## tiers (detailed close up, light further away, without shadows in the distance). The wheels turn in
## the shader from each car's odometer; brake lights light up, head and tail lights glow at night.
## The traffic systems call add() for every car each frame. The cars closest to the players are
## solid: a pool of rigid bodies (car mass, kept upright) that follow their lane exactly (frozen,
## kinematic) – until a player is about to hit one. Then it turns loose: the crash is real physics
## (it is knocked aside, spins, pushes back with its own mass), and afterwards it drives back into
## its lane like a car (steering towards a point on the lane ahead, its tyres holding it against
## sliding sideways) and freezes onto the lane again. The traffic systems ask hit() and
## disturbance() to carry on from where the car ended up.

const Sfx = preload("res://scripts/util/sfx_kit.gd")

const MODELS := ["camry", "impreza", "civic", "s13", "yaris", "ktruck"]
const WEIGHTS := [4, 3, 3, 2, 3, 1]
## Paints: lots of white, silver and black like real Japanese traffic, some colour.
const PAINTS := [Color(0.93, 0.93, 0.91), Color(0.93, 0.93, 0.91), Color(0.95, 0.95, 0.96), Color(0.62, 0.63, 0.66),
	Color(0.62, 0.63, 0.66), Color(0.05, 0.05, 0.06), Color(0.05, 0.05, 0.06), Color(0.32, 0.33, 0.35),
	Color(0.06, 0.14, 0.42), Color(0.55, 0.04, 0.04), Color(0.1, 0.22, 0.14), Color(0.72, 0.66, 0.55)]
const STI_BLUE := Color(0.02, 0.12, 0.48)
const CIVIC_RED := Color(0.72, 0.03, 0.03)
## The Silvia in the 80s two-tone-era colours as often as not.
const S13_PAINTS := [Color(0.85, 0.55, 0.22), Color(0.12, 0.12, 0.14), Color(0.88, 0.88, 0.86), Color(0.5, 0.06, 0.07), Color(0.15, 0.3, 0.2)]
## Tiers: [up to (m), detailed model, shadows]
const TIERS := [[75.0, true, true], [200.0, false, true], [480.0, false, false]]
const CAPACITY := [120, 380, 700]
const POOL := 20
const NEAR_R := 55.0            # solid within this distance of a player
const MASS := 1100.0
const MAX_ACC := 8.5            # what the tyres can do (m/s²)
const MAX_ALPHA := 8.0          # rad/s²
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
uniform sampler2D tex : source_color, filter_linear_mipmap, hint_default_white;
uniform float textured = 0.0;     // 1: the source model's own texture (keep_* classes)

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
	if (textured > 0.5) {
		base *= texture(tex, UV).rgb;
	}
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
var _bodies: Array = []          # RigidBody3D pool
var _shapes: Array = []
var _owner: Array = []           # per body: the car id it carries (-1 free)
var _body_of := {}               # car id -> body index
var _targets := {}               # car id -> [Transform3D, speed, model, physics time, distance² to a player]
var _err := {}                   # car id -> Vector3(along, across, yaw): where the body is against the target
var _err_step := {}              # car id -> the physics step it was measured in
var _err_seen := {}              # car id -> the step disturbance() last handed out
var _step := 0
var _vis := {}                   # car id -> [previous, current body transform] (drawn interpolated)
var _loose := {}                 # car id -> seconds it has been back on its lane (loose after a hit)
var _hits := {}                  # car id -> true: just hit (hit() hands it out once)
var _stun := {}                  # car id -> seconds it still just slides (after a hard hit: no steering, skidding tyres)
var _prev_v := {}                # car id -> its body's velocity last step (a jump = it was hit)
var _phys_t := 0.0
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
	var pm := PhysicsMaterial.new()
	pm.friction = 0.05          # the controller is the tyres; the box itself slides
	pm.bounce = 0.05
	for k in POOL:
		var body := RigidBody3D.new()
		body.name = "TrafficBody%d" % k
		body.mass = MASS
		body.physics_material_override = pm
		body.axis_lock_angular_x = true
		body.axis_lock_angular_z = true
		body.can_sleep = false
		body.continuous_cd = true
		body.freeze = true
		body.collision_layer = 0
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(1.8, 1.4, 4.5)
		cs.shape = box
		cs.position = Vector3(0, 0.7, 0)
		body.add_child(cs)
		add_child(body)
		body.global_position = Vector3(0, -500.0 - k * 10.0, 0)
		_bodies.append(body)
		_shapes.append([box, cs])
		_owner.append(-1)
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
	elif name == "s13" and rng.randf() < 0.6:
		paint = S13_PAINTS[rng.randi() % S13_PAINTS.size()]
	return [mi, paint]


func half_length(model: int) -> float:
	return float(models[model]["half"])


## One car for this frame. odo: metres driven (turns the wheels); speed in m/s (its engine sound);
## id: the car's own number (stable from frame to frame) – it can then be solid near the players.
func add(model: int, xf: Transform3D, paint: Color, odo: float, brake: bool, speed := 0.0, id := -1) -> void:
	if id >= 0:
		var near := 1e9
		for p in _players:
			near = minf(near, (p as Vector3).distance_squared_to(xf.origin))
		if near < NEAR_R * NEAR_R or _body_of.has(id):
			_targets[id] = [xf, speed, model, _phys_t, near]
		# a loose one is drawn where its body is (interpolated between the physics steps)
		if _loose.has(id) and _vis.has(id):
			var v: Array = _vis[id]
			xf = (v[0] as Transform3D).interpolate_with(v[1], clampf(Engine.get_physics_interpolation_fraction(), 0.0, 1.0))
	var d2 := _cam.distance_squared_to(xf.origin)
	if d2 < SOUND_RANGE * SOUND_RANGE:
		_snd_cand.append([d2, xf.origin, speed])
	var m: Dictionary = models[model]
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


## Where the loose car `id` is against where it should be: Vector3(along, across (+ right), yaw) –
## once per physics step while it is loose (ZERO otherwise); the traffic system carries on from there.
func disturbance(id: int) -> Vector3:
	if not _loose.has(id):
		return Vector3.ZERO
	var st: int = _err_step.get(id, -1)
	if st > int(_err_seen.get(id, -1)):
		_err_seen[id] = st
		return _err.get(id, Vector3.ZERO)
	return Vector3.ZERO


## True once when the car `id` has just been hit (it then waits a moment and drives on gently).
func hit(id: int) -> bool:
	if _hits.has(id):
		_hits.erase(id)
		return true
	return false


func _physics_process(delta: float) -> void:
	if not ok:
		return
	_phys_t += delta
	_step += 1
	# forget cars that left (no longer reported near a player)
	for id in _targets.keys():
		if _phys_t - float(_targets[id][3]) > 0.3:
			_targets.erase(id)
	# keep the bodies on their cars (a loose one until it's back on its lane); free ones go to the
	# nearest new cars
	var free: Array = []
	var far2 := (NEAR_R + 15.0) * (NEAR_R + 15.0)
	for k in POOL:
		var id: int = _owner[k]
		if id >= 0:
			if not _targets.has(id):
				_release(k)
			elif float(_targets[id][4]) > far2 and (not _loose.has(id) or float(_targets[id][4]) > 150.0 * 150.0):
				_release(k)
		if _owner[k] < 0:
			free.append(k)
	if not free.is_empty():
		var cand: Array = []
		for id in _targets:
			if not _body_of.has(id) and float(_targets[id][4]) < NEAR_R * NEAR_R:
				cand.append([float(_targets[id][4]), id])
		cand.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
		for c in cand:
			if free.is_empty():
				break
			_assign(free.pop_back(), int(c[1]))
	var pcars: Array = []
	if world != null:
		for car in world.cars.values():
			if is_instance_valid(car) and car.visible and car is RigidBody3D:
				pcars.append(car)
	for k in POOL:
		var id: int = _owner[k]
		if id < 0:
			continue
		if _loose.has(id):
			_drive_loose(k, id, delta, pcars)
		else:
			_follow(k, id, delta, pcars)


## Where car id should be now: its lane transform, moved on by its speed since it was reported.
func _target(id: int) -> Transform3D:
	var tg: Array = _targets[id]
	var txf: Transform3D = tg[0]
	var fwd := _flat_fwd(txf)
	return Transform3D(txf.basis, txf.origin + fwd * float(tg[1]) * (_phys_t - float(tg[3])))


func _assign(k: int, id: int) -> void:
	var tg: Array = _targets[id]
	var body: RigidBody3D = _bodies[k]
	var m: Dictionary = models[int(tg[2])]
	var sz: Vector3 = m["size"]
	var sh: Array = _shapes[k]
	if not (sh[0] as BoxShape3D).size.is_equal_approx(sz):
		(sh[0] as BoxShape3D).size = sz
		(sh[1] as CollisionShape3D).position = Vector3(0, sz.y * 0.5 + 0.02, 0)
	body.inertia = Vector3(1, 1, 1) * MASS * (sz.x * sz.x + sz.z * sz.z) / 12.0
	# frozen on its lane (no falling in, no drifting): exactly where it's drawn
	body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	body.freeze = true
	body.global_transform = _target(id)
	body.collision_layer = 1
	body.collision_mask = 1 | 2 | 4 | 8
	_owner[k] = id
	_body_of[id] = k


func _release(k: int) -> void:
	var id: int = _owner[k]
	var body: RigidBody3D = _bodies[k]
	body.freeze = true
	body.collision_layer = 0
	body.collision_mask = 0
	body.global_position = Vector3(0, -500.0 - k * 10.0, 0)
	_owner[k] = -1
	_body_of.erase(id)
	_vis.erase(id)
	_err.erase(id)
	_err_step.erase(id)
	_stun.erase(id)
	_prev_v.erase(id)
	_err_seen.erase(id)
	_loose.erase(id)
	_hits.erase(id)


## On its lane: the body moves exactly with the car. A player about to run into it (closing in, or
## pressing against it) turns it loose, so the crash is real physics with the car's own mass.
func _follow(k: int, id: int, delta: float, pcars: Array) -> void:
	var body: RigidBody3D = _bodies[k]
	var xf := _target(id)
	var fwd := _flat_fwd(xf)
	var spd: float = _targets[id][1]
	body.global_transform = xf
	var sz: Vector3 = (_shapes[k][0] as BoxShape3D).size
	var inv := xf.affine_inverse()
	for car in pcars:
		var rb := car as RigidBody3D
		var lp: Vector3 = inv * rb.global_position
		var rel := rb.linear_velocity - fwd * spd
		var closing := -(xf.basis.inverse() * rel).dot(lp.normalized()) if lp.length() > 0.01 else 0.0
		var reach := maxf(closing, 0.0) * delta * 3.0
		if absf(lp.x) < sz.x * 0.5 + 1.1 + reach and absf(lp.z) < sz.z * 0.5 + 2.4 + reach and absf(lp.y) < 2.5 \
				and (closing > 1.0 or (absf(lp.x) < sz.x * 0.5 + 0.95 and absf(lp.z) < sz.z * 0.5 + 2.25)):
			body.freeze = false
			body.linear_velocity = fwd * spd
			body.angular_velocity = Vector3.ZERO
			_loose[id] = 0.0
			_hits[id] = true
			_vis[id] = [xf, xf]
			return


## Loose after a hit: drives back onto its lane like a car – steers towards a point on the lane
## ahead (no sharper than a car can turn), its tyres hold it against sliding sideways, the speed
## follows what the traffic system wants. Once it's back on the lane and nobody leans on it, it
## freezes onto the lane again.
func _drive_loose(k: int, id: int, delta: float, pcars: Array) -> void:
	var body: RigidBody3D = _bodies[k]
	var bxf := body.global_transform
	var v: Array = _vis[id]
	v[0] = v[1]
	v[1] = bxf
	var txf := _target(id)
	var tfwd := _flat_fwd(txf)
	var spd: float = _targets[id][1]
	var bf := _flat_fwd(bxf)
	var br := Vector3(-bf.z, 0, bf.x)
	var lv := body.linear_velocity
	var v_f := lv.dot(bf)
	var v_s := lv.dot(br)
	# hit hard: it slides and spins with skidding tyres for a while (longer the harder the hit)
	var dv: float = (lv - (_prev_v.get(id, lv) as Vector3)).length()
	_prev_v[id] = lv
	if dv > 1.5:
		_stun[id] = maxf(float(_stun.get(id, 0.0)), clampf(dv * 0.4, 1.0, 3.5))
	var stun: float = float(_stun.get(id, 0.0))
	if stun > 0.0:
		_stun[id] = stun - delta
		var grip := MAX_ACC * 0.3
		var a_s0 := clampf(-v_s / 0.5, -grip, grip)
		var a_f0 := clampf(-v_f / 0.8, -3.0, 3.0)
		body.apply_central_force((bf * a_f0 + br * a_s0) * MASS)
		# the spin dies down slowly
		body.apply_torque(Vector3(0, -body.angular_velocity.y * body.inertia.y * 0.6, 0))
		_loose[id] = 0.0
		# the traffic system follows where it slides to
		var rel0 := bxf.origin - txf.origin
		var yaw0 := wrapf(atan2(-tfwd.x, -tfwd.z) - atan2(-bf.x, -bf.z), -PI, PI)
		_err[id] = Vector3(rel0.dot(tfwd), rel0.dot(Vector3(-tfwd.z, 0, tfwd.x)), -yaw0)
		_err_step[id] = _step
		return
	_stun.erase(id)
	var a_s := clampf(-v_s / 0.35, -MAX_ACC, MAX_ACC)
	var a_f := clampf((spd - v_f) * 1.5, -7.0, 3.0)
	body.apply_central_force((bf * a_f + br * a_s) * MASS)
	var look := txf.origin + tfwd * maxf(4.0, absf(v_f) * 0.8 + 3.0)
	var to := look - bxf.origin
	to.y = 0.0
	var yaw_b := atan2(-bf.x, -bf.z)
	var err := wrapf(atan2(-to.x, -to.z) - yaw_b, -PI, PI)
	var max_rate := absf(v_f) / 4.5
	var rate := clampf(err * 2.5, -max_rate, max_rate) * (1.0 if v_f >= 0.0 else -1.0)
	var alpha := clampf((rate - body.angular_velocity.y) / 0.1, -MAX_ALPHA, MAX_ALPHA)
	body.apply_torque(Vector3(0, body.inertia.y * alpha, 0))
	var rel := bxf.origin - txf.origin
	var yaw_err := wrapf(atan2(-tfwd.x, -tfwd.z) - yaw_b, -PI, PI)
	var e := Vector3(rel.dot(tfwd), rel.dot(Vector3(-tfwd.z, 0, tfwd.x)), -yaw_err)
	_err[id] = e
	_err_step[id] = _step
	# back on the lane?
	var leaned := false
	for car in pcars:
		if (car as Node3D).global_position.distance_to(bxf.origin) < 5.5:
			leaned = true
	if absf(e.y) < 0.35 and absf(e.z) < 0.08 and absf(e.x) < 1.0 and not leaned:
		_loose[id] = float(_loose[id]) + delta
		if float(_loose[id]) > 0.4:
			body.freeze = true
			body.global_transform = txf
			_loose.erase(id)
			_vis.erase(id)
			_prev_v.erase(id)
	else:
		_loose[id] = 0.0


static func _flat_fwd(xf: Transform3D) -> Vector3:
	var f := -xf.basis.z
	f.y = 0.0
	return f.normalized() if f.length_squared() > 1e-6 else Vector3.FORWARD


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
	if base.size() > 3 and base[3] != null:
		m.set_shader_parameter("tex", base[3])
		m.set_shader_parameter("textured", 1.0)
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
			var base := [Color(0.05, 0.05, 0.05), 0.0, 0.6, null]
			if mat != null:
				cls = str(mat.resource_name).trim_prefix("md_")
				if mat is BaseMaterial3D:
					var bm := mat as BaseMaterial3D
					base = [bm.albedo_color, bm.metallic, bm.roughness, bm.albedo_texture if cls.begins_with("keep_") else null]
			if not by_class.has(cls):
				by_class[cls] = [PackedVector3Array(), PackedVector3Array(), PackedColorArray(), PackedInt32Array(), base, PackedVector2Array()]
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
			var uv: PackedVector2Array = b[5]
			var src_uv = arr[Mesh.ARRAY_TEX_UV]
			if src_uv is PackedVector2Array and (src_uv as PackedVector2Array).size() == verts.size():
				uv.append_array(src_uv)
			else:
				var zeros := PackedVector2Array()
				zeros.resize(verts.size())
				uv.append_array(zeros)
			b[5] = uv
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
		arr[Mesh.ARRAY_TEX_UV] = b[5]
		arr[Mesh.ARRAY_INDEX] = b[3]
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		classes.append(cls)
		albedo.append(b[4])
	return {"mesh": mesh, "classes": classes, "albedo": albedo, "hubs": hubs, "radius": radius}

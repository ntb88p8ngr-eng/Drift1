extends Camera3D
## Follow camera with several views. The chase view follows the car's velocity partially so the
## drift angle is visible. [V] unlocks the camera (free orbit with the mouse / right stick),
## holding the right mouse button looks around temporarily, [B] looks back.

const MODES := ["Verfolger", "Verfolger weit", "Motorhaube", "Stoßstange", "Cockpit-Dach"]

var car          # car.gd
var mode := 0
var free_look := false
var _look_hold := false
var _free_yaw := 0.0
var _free_pitch := 0.25
var _free_dist := 7.0
var _look_yaw := 0.0
var _look_pitch := 0.0
var _dir := Vector3.FORWARD
var _pos := Vector3.ZERO
var _initialized := false
var _base_fov := 75.0
var _shake := 0.0
var _space_query: PhysicsRayQueryParameters3D


func _ready() -> void:
	current = true
	near = 0.08
	far = 4000.0
	_base_fov = float(Game.settings.get("fov", 75.0))
	fov = _base_fov
	mode = clampi(int(Game.settings.get("camera_mode", 0)), 0, MODES.size() - 1)
	_space_query = PhysicsRayQueryParameters3D.new()
	_space_query.collision_mask = 1


func mode_name() -> String:
	if free_look:
		return "Freie Kamera"
	return MODES[mode]


func set_free_look(on: bool) -> void:
	free_look = on
	if on and car:
		var f: Vector3 = -car.global_transform.basis.z
		_free_yaw = atan2(-f.x, -f.z)
		_free_pitch = 0.3
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _unhandled_input(event: InputEvent) -> void:
	if get_tree().paused:
		return
	var sens := float(Game.settings.get("mouse_sensitivity", 0.25)) * 0.01
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if free_look:
			_free_yaw -= mm.relative.x * sens
			_free_pitch = clampf(_free_pitch + mm.relative.y * sens, -0.35, 1.35)
		elif _look_hold:
			_look_yaw = clampf(_look_yaw - mm.relative.x * sens, -PI, PI)
			_look_pitch = clampf(_look_pitch + mm.relative.y * sens, -0.3, 1.0)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_look_hold = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_free_dist = clampf(_free_dist - 0.6, 3.0, 25.0)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_free_dist = clampf(_free_dist + 0.6, 3.0, 25.0)
	if event.is_action_pressed("camera_next"):
		if free_look:
			set_free_look(false)
		mode = (mode + 1) % MODES.size()
		Game.settings["camera_mode"] = mode
	elif event.is_action_pressed("camera_free"):
		set_free_look(not free_look)


func _process(delta: float) -> void:
	if car == null or not is_instance_valid(car):
		return
	var xf: Transform3D = car.global_transform
	var car_pos := xf.origin
	var up := Vector3.UP
	var heading := -xf.basis.z
	heading.y = 0.0
	if heading.length_squared() < 0.001:
		heading = Vector3.FORWARD
	heading = heading.normalized()
	var vel: Vector3 = car.linear_velocity
	var vflat := Vector3(vel.x, 0, vel.z)
	var spd := vflat.length()

	# gamepad right stick look
	var stick := Vector2(Input.get_action_strength("look_right") - Input.get_action_strength("look_left"),
		Input.get_action_strength("look_down") - Input.get_action_strength("look_up"))
	if free_look:
		_free_yaw -= stick.x * delta * 2.5
		_free_pitch = clampf(_free_pitch + stick.y * delta * 1.5, -0.35, 1.35)
	elif stick.length() > 0.2:
		_look_yaw = -stick.x * PI * 0.9
		_look_pitch = stick.y * 0.5
	elif not _look_hold:
		_look_yaw = lerpf(_look_yaw, 0.0, 1.0 - exp(-delta * 5.0))
		_look_pitch = lerpf(_look_pitch, 0.0, 1.0 - exp(-delta * 5.0))

	var target_pos: Vector3
	var look_target: Vector3
	var smooth_pos := true
	if free_look:
		var off := Vector3(sin(_free_yaw) * cos(_free_pitch), sin(_free_pitch), cos(_free_yaw) * cos(_free_pitch)) * _free_dist
		target_pos = car_pos + Vector3(0, 0.9, 0) + off
		look_target = car_pos + Vector3(0, 0.8, 0)
	elif mode <= 1:
		# chase: blend heading with velocity direction so drifts show their angle
		var d := heading
		if spd > 3.0 and car.forward_speed > 0.0:
			var blend := clampf((spd - 3.0) / 20.0, 0.0, 0.55)
			d = heading.lerp(vflat / spd, blend).normalized()
		elif car.forward_speed < -2.0:
			d = heading
		_dir = _dir.lerp(d, 1.0 - exp(-delta * 4.5)).normalized() if _initialized else d
		var dir := _dir.rotated(Vector3.UP, _look_yaw)
		if Input.is_action_pressed("look_back"):
			dir = -dir
		var dist := 5.8 if mode == 0 else 8.5
		var height := 1.75 if mode == 0 else 2.7
		dist += spd * 0.02
		target_pos = car_pos - dir * dist + up * (height + _look_pitch * 3.0)
		look_target = car_pos + up * 0.95 + dir * 2.5
	else:
		smooth_pos = false
		var local_pos := Vector3(0, 1.08, -0.35)
		if mode == 3:
			local_pos = Vector3(0, 0.5, -2.45)
		elif mode == 4:
			local_pos = Vector3(0, 1.62, 0.2)
		target_pos = xf * local_pos
		var look_dir: Vector3 = (-xf.basis.z).rotated(xf.basis.y, _look_yaw)
		if Input.is_action_pressed("look_back"):
			look_dir = -look_dir
		look_target = target_pos + look_dir * 10.0 + xf.basis.y * (-0.4 - _look_pitch * 4.0)

	# keep the camera out of walls
	if smooth_pos:
		var from := car_pos + Vector3(0, 1.0, 0)
		_space_query.from = from
		_space_query.to = target_pos
		var ex: Array[RID] = [car.get_rid()]
		_space_query.exclude = ex
		var hit := get_world_3d().direct_space_state.intersect_ray(_space_query)
		if not hit.is_empty():
			var hp: Vector3 = hit["position"]
			var hn: Vector3 = hit["normal"]
			target_pos = hp + hn * 0.35
		target_pos.y = maxf(target_pos.y, 0.35)

	if not _initialized or not smooth_pos:
		_pos = target_pos
		_initialized = true
	else:
		_pos = _pos.lerp(target_pos, 1.0 - exp(-delta * (14.0 if free_look else 9.0)))

	# speed / drift shake
	var slip: float = car.total_slip
	_shake = clampf((spd - 35.0) / 40.0, 0.0, 1.0) * 0.02 + clampf(slip / 60.0, 0.0, 0.02)
	var shake_off := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * _shake
	global_position = _pos + shake_off
	if global_position.distance_to(look_target) > 0.01:
		look_at(look_target, Vector3.UP)
	var target_fov := _base_fov + clampf(spd * 0.28, 0.0, 20.0)
	if mode >= 2 and not free_look:
		target_fov += 5.0
	fov = lerpf(fov, target_fov, 1.0 - exp(-delta * 3.0))

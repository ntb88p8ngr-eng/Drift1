extends Camera3D
## A free-flying camera (replays, admin mode): WASD to move, Q/E or Ctrl/Space down/up, right mouse
## button held to look around, Shift faster, mouse wheel changes the speed. Optional smoothing.

var speed := 20.0              # m/s
var look_sensitivity := 0.0025
var smoothing := 0.0           # 0 = direct … 0.95 = very soft (cinematic)
var active := true
var _yaw := 0.0
var _pitch := 0.0
var _vel := Vector3.ZERO
var _looking := false
var _target_yaw := 0.0
var _target_pitch := 0.0


func start_from(xf: Transform3D) -> void:
	global_transform = xf
	var f := -xf.basis.z
	_yaw = atan2(-f.x, -f.z)
	_pitch = asin(clampf(f.y, -1.0, 1.0))
	_target_yaw = _yaw
	_target_pitch = _pitch
	_vel = Vector3.ZERO


func _unhandled_input(event: InputEvent) -> void:
	if not active or not current:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_looking = mb.pressed
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if mb.pressed else Input.MOUSE_MODE_VISIBLE
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			speed = minf(speed * 1.2, 400.0)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			speed = maxf(speed / 1.2, 0.5)
	elif event is InputEventMouseMotion and _looking:
		var mm := event as InputEventMouseMotion
		_target_yaw -= mm.relative.x * look_sensitivity
		_target_pitch = clampf(_target_pitch - mm.relative.y * look_sensitivity, -1.55, 1.55)


func _process(delta: float) -> void:
	if not active or not current:
		return
	# real time, also while the replay is paused or slowed down
	var dt := delta / maxf(Engine.time_scale, 0.01)
	var k := 1.0 - pow(clampf(smoothing, 0.0, 0.97), dt * 60.0)
	_yaw = lerp_angle(_yaw, _target_yaw, k)
	_pitch = lerpf(_pitch, _target_pitch, k)
	var basis := Basis(Vector3.UP, _yaw) * Basis(Vector3.RIGHT, _pitch)
	var mv := Vector3.ZERO
	if Input.is_key_pressed(KEY_W):
		mv.z -= 1
	if Input.is_key_pressed(KEY_S):
		mv.z += 1
	if Input.is_key_pressed(KEY_A):
		mv.x -= 1
	if Input.is_key_pressed(KEY_D):
		mv.x += 1
	if Input.is_key_pressed(KEY_E) or Input.is_key_pressed(KEY_SPACE):
		mv.y += 1
	if Input.is_key_pressed(KEY_Q) or Input.is_key_pressed(KEY_CTRL):
		mv.y -= 1
	var want := (basis * Vector3(mv.x, 0, mv.z) + Vector3(0, mv.y, 0)).normalized() * speed * (4.0 if Input.is_key_pressed(KEY_SHIFT) else 1.0)
	_vel = _vel.lerp(want, k)
	global_transform = Transform3D(basis, global_position + _vel * dt)

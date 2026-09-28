extends Camera3D
## Follow camera with several views. The chase view follows the car's velocity partially so the
## drift angle is visible. [V] unlocks the camera (free orbit with the mouse / right stick),
## holding the right mouse button looks around temporarily, [B] looks back.

const MODES := ["Verfolger", "Verfolger weit", "Motorhaube", "Stoßstange", "Cockpit-Dach"]

const TILT_MIN := -0.2    # rad added to the chase camera's elevation angle
const TILT_MAX := 0.75
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
var _anchor := Vector3.ZERO     # smoothed car position the chase camera hangs on
var _vel_s := Vector3.ZERO      # low-passed car velocity (feed-forward for the anchor)
var _initialized := false
var _base_fov := 75.0
var _zoom := 1.0          # chase distance factor (mouse wheel), saved in the settings
var _tilt := 0.0          # chase elevation (left mouse button + drag up/down), saved in the settings
var _tilt_drag := false
var _space_query: PhysicsRayQueryParameters3D
var _blur_rect: ColorRect
var _blur_mat: ShaderMaterial
var _prev_fwd := Vector3.ZERO
var _swipe := 0.0

## Motion blur like the eye at speed: the centre (where you look) stays sharp, towards the sides the
## picture smears outwards, more the faster you go; quick camera swings smear sideways.
const BLUR_SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float strength = 0.0;   // radial smear (speed)
uniform float swipe = 0.0;      // sideways smear (camera turning), in screen widths
uniform float aspect = 1.7778;
void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 c = uv - 0.5;
	// sharp fovea in the middle, the smear grows towards the edges – wider sideways than up/down
	float e = smoothstep(0.1, 0.62, length(vec2(c.x * aspect * 0.72, c.y * 1.3)));
	vec2 d = c * strength * e * 0.16 + vec2(swipe * (0.3 + 0.7 * e), 0.0);
	vec3 col = vec3(0.0);
	float wsum = 0.0;
	for (int i = 0; i < 12; i++) {
		float t = float(i) / 11.0;
		float w = 1.0 - t * 0.6;
		col += textureLod(screen_tex, uv - d * t, 0.0).rgb * w;
		wsum += w;
	}
	COLOR = vec4(col / wsum, 1.0);
}
"""


func _ready() -> void:
	current = true
	near = 0.08
	far = 4000.0
	_base_fov = float(Game.settings.get("fov", 75.0))
	fov = _base_fov
	mode = clampi(int(Game.settings.get("camera_mode", 0)), 0, MODES.size() - 1)
	_zoom = clampf(float(Game.settings.get("camera_zoom", 1.2)), 0.6, 2.4)
	_tilt = clampf(float(Game.settings.get("camera_tilt", 0.0)), TILT_MIN, TILT_MAX)
	_space_query = PhysicsRayQueryParameters3D.new()
	_space_query.collision_mask = 1
	# below the HUD layers, so only the 3D picture is blurred
	var layer := CanvasLayer.new()
	layer.layer = -5
	add_child(layer)
	_blur_rect = ColorRect.new()
	_blur_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_blur_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = BLUR_SHADER
	_blur_mat = ShaderMaterial.new()
	_blur_mat.shader = sh
	_blur_rect.material = _blur_mat
	_blur_rect.visible = false
	layer.add_child(_blur_rect)


## Motion blur strength from the settings, the car's speed and how fast the view turns.
func _update_blur(delta: float, spd: float) -> void:
	var level := clampi(int(Game.settings.get("motion_blur", 0)), 0, 3)
	var fwd := -global_transform.basis.z
	var turn := 0.0
	if _prev_fwd != Vector3.ZERO and delta > 0.0:
		# signed yaw rate of the view (rad/s)
		var a := Vector2(_prev_fwd.x, _prev_fwd.z)
		var b := Vector2(fwd.x, fwd.z)
		if a.length_squared() > 0.001 and b.length_squared() > 0.001:
			turn = a.angle_to(b) / delta
	_prev_fwd = fwd
	if level == 0:
		_blur_rect.visible = false
		return
	var k: float = [0.0, 0.55, 1.0, 1.6][level]
	var strength := k * clampf((spd - 6.0) / 45.0, 0.0, 1.0)
	_swipe = lerpf(_swipe, clampf(turn * 0.012, -0.03, 0.03) * k, 1.0 - exp(-delta * 12.0))
	var on := strength > 0.01 or absf(_swipe) > 0.0008
	_blur_rect.visible = on
	if on:
		var vs := get_viewport().get_visible_rect().size
		_blur_mat.set_shader_parameter("strength", strength)
		_blur_mat.set_shader_parameter("swipe", _swipe)
		_blur_mat.set_shader_parameter("aspect", vs.x / maxf(vs.y, 1.0))


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
		elif _tilt_drag and mode <= 1:
			# drag down = look down on the car from higher up, drag up = flatter, lower camera
			_tilt = clampf(_tilt + mm.relative.y * sens * 0.8, TILT_MIN, TILT_MAX)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_look_hold = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_LEFT and not free_look:
			_tilt_drag = mb.pressed
			if not mb.pressed:
				Game.settings["camera_tilt"] = _tilt
				Game.save_settings()
		elif mb.pressed and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			var step := -1.0 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0
			if free_look:
				_free_dist = clampf(_free_dist + step * 0.6, 3.0, 25.0)
			else:
				# chase view: the wheel moves the camera closer / further back
				_zoom = clampf(_zoom + step * 0.1, 0.6, 2.4)
				Game.settings["camera_zoom"] = _zoom
				Game.save_settings()
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
	# interpolated transform: the physics runs at 120 Hz, the camera at the display rate
	var xf: Transform3D = car.visual_transform() if car.has_method("visual_transform") else car.global_transform
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
	# "Kamera-Glättung" 0 … 1: how strongly bumps, suspension pitch/heave and surges are filtered
	var smooth := clampf(float(Game.settings.get("camera_smoothing", 0.6)), 0.0, 1.0)
	_zoom = clampf(float(Game.settings.get("camera_zoom", 1.2)), 0.6, 2.4)
	if not _tilt_drag:
		_tilt = clampf(float(Game.settings.get("camera_tilt", 0.0)), TILT_MIN, TILT_MAX)
	if not _initialized:
		_anchor = car_pos
		_vel_s = vel
	# the anchor moves with the (low-passed) car velocity, so it doesn't lag at constant speed, and is
	# pulled onto the car by a soft spring – horizontally firmer, vertically softer (suspension bounce)
	_vel_s = _vel_s.lerp(vel, 1.0 - exp(-delta * lerpf(14.0, 5.0, smooth)))
	_anchor += _vel_s * delta
	var kh := 1.0 - exp(-delta * lerpf(18.0, 6.0, smooth))
	# vertically much softer: crests, dips and bumps at speed must not jerk the view
	var kv := 1.0 - exp(-delta * lerpf(6.0, 1.6, smooth))
	_anchor = Vector3(lerpf(_anchor.x, car_pos.x, kh), lerpf(_anchor.y, car_pos.y, kv), lerpf(_anchor.z, car_pos.z, kh))
	if _anchor.distance_to(car_pos) > 12.0:
		_anchor = car_pos   # reset / teleport

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
		target_pos = _anchor + Vector3(0, 0.9, 0) + off
		look_target = _anchor + Vector3(0, 0.8, 0)
	elif mode <= 1:
		# chase: blend heading with velocity direction so drifts show their angle
		var d := heading
		if spd > 3.0 and car.forward_speed > 0.0:
			var blend := clampf((spd - 3.0) / 20.0, 0.0, 0.55)
			d = heading.lerp(vflat / spd, blend).normalized()
		elif car.forward_speed < -2.0:
			d = heading
		_dir = _dir.lerp(d, 1.0 - exp(-delta * lerpf(6.0, 3.2, smooth))).normalized() if _initialized else d
		var dir := _dir.rotated(Vector3.UP, _look_yaw)
		if Input.is_action_pressed("look_back"):
			dir = -dir
		var dist := (5.8 if mode == 0 else 8.5) * _zoom
		var height := (1.75 if mode == 0 else 2.7) * lerpf(1.0, _zoom, 0.6)
		# tilt: swing the camera up/down around the car, keeping the distance
		var base_ang := atan2(height, dist)
		var ang := clampf(base_ang + _tilt, 0.02, 1.25)
		var rad := sqrt(dist * dist + height * height)
		dist = rad * cos(ang)
		height = rad * sin(ang)
		dist += spd * 0.02
		# follow the smoothed car position only (not its pitch or bounce)
		target_pos = _anchor - dir * dist + up * (height + _look_pitch * 3.0)
		look_target = _anchor + up * 0.95 + dir * 2.5
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
			if hn.y > 0.6:
				# ground (a crest behind the car): lift the camera over it instead of pulling it in
				target_pos.y = maxf(target_pos.y, hp.y + 0.6)
			else:
				target_pos = hp + hn * 0.35
		# never below the car's feet (relative: on the Grüne Hölle the road runs 280 m below y = 0)
		target_pos.y = maxf(target_pos.y, car_pos.y + 0.05)

	if not _initialized or not smooth_pos:
		_pos = target_pos
		_initialized = true
	else:
		# the anchor is already smooth: this only eases wall avoidance and view changes
		var kxz := 1.0 - exp(-delta * (14.0 if free_look else 16.0))
		var ky := 1.0 - exp(-delta * (14.0 if free_look else 7.0))
		_pos = Vector3(lerpf(_pos.x, target_pos.x, kxz), lerpf(_pos.y, target_pos.y, ky), lerpf(_pos.z, target_pos.z, kxz))

	global_position = _pos
	if global_position.distance_to(look_target) > 0.01:
		look_at(look_target, Vector3.UP)
	_base_fov = float(Game.settings.get("fov", 75.0))
	var target_fov := _base_fov + clampf(spd * 0.28, 0.0, 20.0)
	if mode >= 2 and not free_look:
		target_fov += 5.0
	fov = lerpf(fov, target_fov, 1.0 - exp(-delta * 3.0))
	_update_blur(delta, spd)

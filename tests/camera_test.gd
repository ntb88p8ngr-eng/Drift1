extends Node
## Measures chase-camera jitter while the car accelerates flat out and brakes hard.
## Run: godot --headless --fixed-fps 75 --path . res://tests/camera_test.tscn [-- --smooth=0.6]
## Prints the frame-to-frame high-frequency part of the view rotation (deg) and height (cm).

const World = preload("res://scripts/world/world.gd")


func _ready() -> void:
	Game.persist = false
	Game.settings["car"] = "r34"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--smooth="):
			Game.settings["camera_smoothing"] = float(a.substr(9))
	var world := World.new()
	world.setup({"track": "ridge", "mode": "free", "laps": 1, "time_of_day": "day", "weather": "dry", "weather_seed": 3, "online": false})
	add_child(world)
	for f in 10:
		await get_tree().process_frame
	var cam: Camera3D = world.camera
	var fwd: Array = []
	var ys: Array = []
	var pitch: Array = []
	var along: Array = []
	var car = world.local_car
	var phases := {}
	var t := 0.0
	Input.action_press("accelerate")
	while t < 8.0:
		await get_tree().process_frame
		t += get_process_delta_time()
		if t > 5.0 and Input.is_action_pressed("accelerate"):
			Input.action_release("accelerate")
			Input.action_press("brake")
		if t > 0.5:
			fwd.append(-cam.global_transform.basis.z)
			ys.append(cam.global_position.y - world.local_car.global_position.y)
			var vx: Transform3D = car.visual_transform()
			pitch.append(rad_to_deg(asin(clampf((-vx.basis.z).y, -1.0, 1.0))))
			# car position along the view direction, relative to the camera (surging in the image)
			along.append((vx.origin - cam.global_position).dot(-cam.global_transform.basis.z))
			var ph := "throttle" if t <= 5.0 else "brake"
			if not phases.has(ph):
				phases[ph] = fwd.size() - 1
	Input.action_release("brake")
	# angular step per frame, minus its local mean (9 frames) = jitter
	var steps: Array = []
	for i in range(1, fwd.size()):
		steps.append(rad_to_deg((fwd[i - 1] as Vector3).angle_to(fwd[i])))
	print("CAR body pitch jitter %.4f deg/frame, car-to-camera distance jitter %.2f cm/frame" % [_hf_rms(_diff(pitch)), _hf_rms(_diff(along)) * 100.0])
	var b: int = phases.get("brake", pitch.size())
	print("  throttle phase: pitch %.4f, distance %.2f cm | brake phase: pitch %.4f, distance %.2f cm" % [
		_hf_rms(_diff(pitch.slice(0, b))), _hf_rms(_diff(along.slice(0, b))) * 100.0,
		_hf_rms(_diff(pitch.slice(b))), _hf_rms(_diff(along.slice(b))) * 100.0])
	var view_j := _hf_rms(steps)
	var dist_j := _hf_rms(_diff(along)) * 100.0
	print("CAMERA smoothing=%.2f  view jitter %.4f deg/frame  height jitter %.2f cm  (frames %d)" % [
		float(Game.settings.get("camera_smoothing", 0.6)), view_j, _hf_rms(_diff(ys)) * 100.0, fwd.size()])
	# before the interpolation fix: ~9 cm and ~0.01 deg at 75 fps
	print("CAMERA TEST OK" if dist_j < 1.0 and view_j < 0.004 else "CAMERA JITTER TOO HIGH")
	get_tree().quit()


func _diff(a: Array) -> Array:
	var out: Array = []
	for i in range(1, a.size()):
		out.append(float(a[i]) - float(a[i - 1]))
	return out


func _hf_rms(a: Array) -> float:
	var sum := 0.0
	var n := 0
	for i in range(4, a.size() - 4):
		var m := 0.0
		for k in range(-4, 5):
			m += float(a[i + k])
		m /= 9.0
		sum += pow(float(a[i]) - m, 2.0)
		n += 1
	return sqrt(sum / maxf(n, 1))

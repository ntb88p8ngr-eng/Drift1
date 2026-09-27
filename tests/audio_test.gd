extends Node
## Offline render of the synthesized engine voices: prints level statistics and writes WAV files.
## Run: godot --headless --path . res://tests/audio_test.tscn -- <out_dir>

const CarAudio = preload("res://scripts/car/car_audio.gd")
const FakeCar = preload("res://tests/fake_car.gd")


func _ready() -> void:
	var out_dir := "/tmp"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	var specs := {
		"r34": ["i6", 8000.0, 1100.0, 0.45],
		"r34synth": ["i6", 8000.0, 1100.0, 0.45],
		"mustang": ["v8", 7400.0, 800.0, 0.0],
		"m3gt3": ["v8race", 9000.0, 900.0, 0.0],
		"m3gt3synth": ["v8race", 9000.0, 900.0, 0.0],
		"mustang_brutal": ["v8", 7400.0, 800.0, 0.0],
	}
	for cid in specs.keys():
		var sp: Array = specs[cid]
		var fc := FakeCar.new()
		fc.car_id = "r34" if cid.begins_with("r34") else ("m3gt3" if cid.begins_with("m3gt3") else cid.get_slice("_", 0))
		fc.burble = 3 if cid.ends_with("_brutal") else int(Game.get_car(fc.car_id)["burble"])
		fc.redline = sp[1]
		fc.idle_rpm = sp[2]
		fc.turbo_gain = sp[3]
		var au := CarAudio.new()
		au.car = fc
		au.setup_voice(sp[0])
		if cid == "r34" and not au.setup_samples():
			print("AUDIO SAMPLES MISSING")
		if cid == "m3gt3" and not au.setup_samples(CarAudio.M3Data, "m3"):
			print("AUDIO SAMPLES MISSING")
		fc.shifted.connect(au._on_shift)
		fc.blow_off.connect(au._on_blow_off)
		fc.backfire.connect(au._on_backfire)
		var pcm := PackedVector2Array()
		# idle 1 s, rev sweep 3 s with throttle, lift (blow-off) 1 s, overrun 1 s, shift, launch 1 s
		var t := 0.0
		var block := 256
		var total := int(8.0 * CarAudio.MIX_RATE)
		var peak := 0.0
		var sumsq := 0.0
		var lifted := false
		var shifted := false
		while pcm.size() < total:
			t = float(pcm.size()) / CarAudio.MIX_RATE
			if t < 1.0:
				fc.rpm = fc.idle_rpm
				fc.throttle = 0.0
			elif t < 4.0:
				fc.throttle = 1.0
				fc.rpm = lerpf(fc.idle_rpm, fc.redline * 0.97, (t - 1.0) / 3.0)
				fc.boost = clampf((t - 1.8) / 1.5, 0.0, 1.0) if fc.turbo_gain > 0.0 else 0.0
				fc.speed = (t - 1.0) * 12.0
			elif t < 6.0:
				if not lifted:
					lifted = true
					fc.blow_off.emit(fc.boost, true)
					if fc.burble > 0:
						fc.backfire.emit(1.0)
				fc.throttle = 0.0
				fc.boost = move_toward(fc.boost, 0.0, 0.02)
				fc.rpm = lerpf(fc.redline * 0.95, fc.redline * 0.45, (t - 4.0) / 2.0)
			else:
				if not shifted:
					shifted = true
					fc.throttle = 1.0
					fc.shifted.emit(true, 0.5)
				fc.line_lock = t > 6.8
				fc.throttle = 1.0
				fc.speed = 0.0
				fc.rpm = fc.redline * 0.6 if fc.line_lock else lerpf(fc.rpm, fc.redline * 0.7, 0.05)
			var b: PackedVector2Array = au.render(block)
			for s in b:
				peak = maxf(peak, absf(s.x))
				sumsq += s.x * s.x
				if is_nan(s.x):
					print("AUDIO NAN in ", cid)
					get_tree().quit(1)
					return
			pcm.append_array(b)
		print("AUDIO %s: rms %.3f peak %.3f" % [cid, sqrt(sumsq / pcm.size()), peak])
		_write_wav(out_dir.path_join("engine_%s.wav" % cid), pcm)
		au.free()
		fc.free()
	print("AUDIO TEST DONE")
	get_tree().quit(0)


func _write_wav(path: String, pcm: PackedVector2Array) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	var n := pcm.size()
	f.store_buffer("RIFF".to_ascii_buffer())
	f.store_32(36 + n * 2)
	f.store_buffer("WAVEfmt ".to_ascii_buffer())
	f.store_32(16)
	f.store_16(1)
	f.store_16(1)
	f.store_32(int(CarAudio.MIX_RATE))
	f.store_32(int(CarAudio.MIX_RATE) * 2)
	f.store_16(2)
	f.store_16(16)
	f.store_buffer("data".to_ascii_buffer())
	f.store_32(n * 2)
	for s in pcm:
		var v := int(clampf(s.x, -1.0, 1.0) * 32767.0)
		f.store_16(v & 0xFFFF)
	f.close()

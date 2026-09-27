extends Node
## Renders the rain sound offline (light and heavy rain) and writes WAVs; prints level and cost.
## Run: godot --headless --path . res://tests/rain_audio_test.tscn -- <out_dir>

const Atmosphere = preload("res://scripts/world/atmosphere.gd")


func _ready() -> void:
	var out_dir := "/tmp"
	if OS.get_cmdline_user_args().size() > 0:
		out_dir = OS.get_cmdline_user_args()[0]
	var atm := Atmosphere.new()
	for level in [0.4, 1.0]:
		atm.rain = level
		var pcm := PackedVector2Array()
		var t0 := Time.get_ticks_usec()
		while pcm.size() < 22050 * 4:
			pcm.append_array(atm.render_rain(512))
		var cost := float(Time.get_ticks_usec() - t0) / 4.0 / 1000.0
		var sum := 0.0
		var peak := 0.0
		for sm in pcm:
			sum += sm.x * sm.x
			peak = maxf(peak, absf(sm.x))
		print("RAIN level %.1f: rms %.3f peak %.3f, %.1f ms CPU per second of audio" % [level, sqrt(sum / pcm.size()), peak, cost])
		_write_wav(out_dir.path_join("rain_%d.wav" % int(level * 10)), pcm)
	atm.free()
	print("RAIN TEST DONE")
	get_tree().quit()


func _write_wav(path: String, pcm: PackedVector2Array) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	var n := pcm.size()
	f.store_buffer("RIFF".to_ascii_buffer())
	f.store_32(36 + n * 4)
	f.store_buffer("WAVEfmt ".to_ascii_buffer())
	f.store_32(16)
	f.store_16(1)
	f.store_16(2)
	f.store_32(22050)
	f.store_32(22050 * 4)
	f.store_16(4)
	f.store_16(16)
	f.store_buffer("data".to_ascii_buffer())
	f.store_32(n * 4)
	for sm in pcm:
		f.store_16(int(clampf(sm.x, -1.0, 1.0) * 32767.0) & 0xFFFF)
		f.store_16(int(clampf(sm.y, -1.0, 1.0) * 32767.0) & 0xFFFF)
	f.close()

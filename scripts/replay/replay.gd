extends Node
## Replays: while driving, every car's pure state (position, rotation, velocity, steering, revs, lights,
## tyre slip, throttle, boost) and the camera are sampled 30 times a second. Saved, the session is
## rendered again from that data alone – the world is rebuilt, the cars are driven by the samples.
## File (.mdreplay): "MDRP", version, header JSON (track, weather, cars …), zstd-compressed floats.

const MAGIC := "MDRP"
const VERSION := 1
const DIR := "user://replays"
const RATE := 30.0
const MAX_SECONDS := 1800.0
const CAR_FLOATS := 17       # pos 3, rot 4, vel 3, steer, rpm, flags, rear slip, front slip, throttle, boost
const CAM_FLOATS := 8        # pos 3, rot 4, fov

var world
var header := {}
var car_ids: Array = []      # the recorded cars, in order
var data := PackedFloat32Array()   # per sample: time, camera, then every car
var frames := 0
var _t := 0.0
var _acc := 0.0
var recording := true


## Starts recording a world's session (after it is built).
func setup(p_world) -> void:
	world = p_world
	var cfg: Dictionary = world.config
	header = {
		"version": VERSION, "date": Time.get_datetime_string_from_system(false, true),
		"track": world.track.track_id, "map": str(cfg.get("map", "")), "mode": world.mode,
		"time_of_day": str(cfg.get("time_of_day", "day")), "weather": str(cfg.get("weather", "dry")),
		"day_cycle": int(cfg.get("day_cycle", 0)), "weather_seed": int(cfg.get("weather_seed", 0)),
		"storm": bool(cfg.get("storm", false)), "hour": float(world.atmosphere.hour),
		"cars": [], "local": 0,
	}
	for id in world.cars:
		var c = world.cars[id]
		if not is_instance_valid(c):
			continue
		car_ids.append(id)
		if c == world.local_car:
			header["local"] = car_ids.size() - 1
		header["cars"].append({"name": c.player_name, "car": c.car_id, "paint": _paint_info(c), "rims": c.rims_cfg,
			"underglow": c.underglow_cfg if c.underglow_cfg is Dictionary else {}, "burble": c.burble})


func _paint_info(c) -> Dictionary:
	var p: Dictionary = c.paint
	return {"color": (p.get("color", Color.RED) as Color).to_html(false), "metallic": float(p.get("metallic", 0.1)),
		"roughness": float(p.get("roughness", 0.2)), "finish": str(p.get("finish", "gloss"))}


func _physics_process(delta: float) -> void:
	if not recording or world == null or not world.is_loaded:
		return
	_t += delta
	_acc += delta
	if _acc < 1.0 / RATE:
		return
	_acc -= 1.0 / RATE
	if _t > MAX_SECONDS:
		return
	var cam := get_viewport().get_camera_3d()
	data.append(_t)
	if cam:
		_put_xf(cam.global_transform)
		data.append(cam.fov)
	else:
		for i in CAM_FLOATS:
			data.append(0.0)
	for id in car_ids:
		var c = world.cars.get(id)
		if c == null or not is_instance_valid(c):
			for i in CAR_FLOATS:
				data.append(0.0)
			continue
		var s: Array = c.get_net_state(0.0, 0, 0.0)
		var p: Vector3 = s[0]
		var q: Quaternion = s[1]
		var v: Vector3 = s[2]
		data.append_array([p.x, p.y, p.z, q.x, q.y, q.z, q.w, v.x, v.y, v.z, s[3], s[4], float(s[5]), s[9], s[10], s[11], s[12]])
	frames += 1


func _put_xf(xf: Transform3D) -> void:
	var q := xf.basis.get_rotation_quaternion()
	data.append_array([xf.origin.x, xf.origin.y, xf.origin.z, q.x, q.y, q.z, q.w])


func duration() -> float:
	return _t


## Writes the replay; returns its path or "".
func save(name := "") -> String:
	if frames < 2:
		return ""
	DirAccess.make_dir_recursive_absolute(DIR)
	var h := header.duplicate()
	h["frames"] = frames
	h["duration"] = _t
	h["name"] = name if name != "" else "%s – %s" % [Game.track_name(str(h["track"])), str(h["date"]).replace("T", " ").substr(0, 16)]
	var stamp := str(h["date"]).replace(":", "-").replace("T", "_").replace(" ", "_")
	var path := DIR.path_join("%s_%s.mdreplay" % [stamp, h["track"]])
	return path if write_file(path, h, data) else ""


static func write_file(path: String, h: Dictionary, d: PackedFloat32Array) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	var hb := JSON.stringify(h).to_utf8_buffer()
	var raw := d.to_byte_array()
	f.store_buffer(MAGIC.to_utf8_buffer())
	f.store_32(VERSION)
	f.store_32(hb.size())
	f.store_buffer(hb)
	f.store_32(raw.size())
	f.store_buffer(raw.compress(FileAccess.COMPRESSION_ZSTD))
	f.close()
	return true


## [header, data] (data only when `with_data`), or [] when it can't be read.
static func read_file(path: String, with_data := true) -> Array:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null or f.get_buffer(4).get_string_from_utf8() != MAGIC:
		return []
	f.get_32()
	var hn := f.get_32()
	var h = JSON.parse_string(f.get_buffer(hn).get_string_from_utf8())
	if not (h is Dictionary):
		return []
	if not with_data:
		return [h, PackedFloat32Array()]
	var rn := f.get_32()
	var packed := f.get_buffer(f.get_length() - f.get_position())
	return [h, packed.decompress(rn, FileAccess.COMPRESSION_ZSTD).to_float32_array()]


## The saved replays, newest first: [[path, header]].
static func list() -> Array:
	var out: Array = []
	var dir := DirAccess.open(DIR)
	if dir == null:
		return out
	for fn in dir.get_files():
		if fn.ends_with(".mdreplay"):
			var r := read_file(DIR.path_join(fn), false)
			if not r.is_empty():
				out.append([DIR.path_join(fn), r[0]])
	out.sort_custom(func(a, b): return str(a[1].get("date", "")) > str(b[1].get("date", "")))
	return out

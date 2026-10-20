extends Node
## Time attack: alone against the clock. Every lap is recorded (pose, steering, speed, distance along
## the lap); the fastest one is kept per track, course and map (user://ghosts) and drives along as a
## see-through ghost car – the session's previous lap too, if wanted (setting "ghost"). The HUD shows
## how far ahead or behind the best lap you are at the same point of the lap.
## File (.mdghost): "MDGH", version, header JSON (track, layout, map, car, time …), zstd-compressed floats.

const CarBody = preload("res://scripts/car/car_body.gd")

const DIR := "user://ghosts"
const MAGIC := "MDGH"
const VERSION := 1
const RATE := 20.0
const F := 12                 # per sample: lap time, pos 3, rot 4, steer, forward speed, lap distance, flags
const MAX_SECONDS := 1500.0   # (the Grüne Hölle at a crawl)
## Setting "ghost": which ghosts drive along.
const MODES := ["Bestzeit", "Bestzeit + letzte Runde", "Letzte Runde", "Aus"]
const BEST_TINT := Color(1.0, 0.78, 0.25)
const LAST_TINT := Color(0.35, 0.8, 1.0)

var world
var key := ""
var best := {}                # the saved best lap {"header", "data"}, or empty
var last := {}                # the session's previous valid lap
var delta := 0.0              # this lap's time minus the best lap's at the same distance (s)
var delta_valid := false

var _ghosts: Array = []       # Ghost per shown recording
var _rec := PackedFloat32Array()
var _recording := false
var _acc := 0.0
var _ref_dist := PackedFloat32Array()    # the best lap: distance (running maximum) …
var _ref_time := PackedFloat32Array()    # … and its time, for the delta
var _ref_i := 0


## A recording driven as a see-through car.
class Ghost:
	var node: Node3D
	var body: Node3D
	var tag: Label3D
	var mat: ShaderMaterial
	var rec: Dictionary
	var data: PackedFloat32Array
	var n := 0
	var cursor := 0
	var steer := 0.0
	var speed := 0.0
	var spin := 0.0
	var fade := 0.0


func setup(p_world) -> void:
	world = p_world
	key = ghost_key(world.track.track_id, world.track.layout, str(world.config.get("map", "")))
	best = load_ghost(key)
	_set_reference(best)
	_rebuild_ghosts()


static func ghost_key(track_id: String, layout: String, map_path: String) -> String:
	var k := "%s_%s" % [track_id, layout]
	if map_path != "":
		k += "_" + map_path.get_file().get_basename().validate_filename()
	return k


static func ghost_path(k: String) -> String:
	return DIR.path_join(k + ".mdghost")


## The saved best lap's header (time, car, date …) for the menu, or {}.
static func best_info(track_id: String, layout: String, map_path: String) -> Dictionary:
	var g := load_ghost(ghost_key(track_id, layout, map_path), false)
	return g.get("header", {})


static func delete_ghost(track_id: String, layout: String, map_path: String) -> void:
	var p := ghost_path(ghost_key(track_id, layout, map_path))
	if FileAccess.file_exists(p):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


static func load_ghost(k: String, with_data := true) -> Dictionary:
	var f := FileAccess.open(ghost_path(k), FileAccess.READ)
	if f == null or f.get_length() < 16 or f.get_buffer(4).get_string_from_utf8() != MAGIC:
		return {}
	f.get_32()
	var h = JSON.parse_string(f.get_buffer(f.get_32()).get_string_from_utf8())
	if not (h is Dictionary):
		return {}
	if not with_data:
		return {"header": h}
	var rn := f.get_32()
	var d := f.get_buffer(f.get_length() - f.get_position()).decompress(rn, FileAccess.COMPRESSION_ZSTD).to_float32_array()
	if d.size() < F * 2:
		return {}
	return {"header": h, "data": d}


static func save_ghost(k: String, g: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute(DIR)
	var f := FileAccess.open(ghost_path(k), FileAccess.WRITE)
	if f == null:
		return false
	var hb := JSON.stringify(g["header"]).to_utf8_buffer()
	var raw := (g["data"] as PackedFloat32Array).to_byte_array()
	f.store_buffer(MAGIC.to_utf8_buffer())
	f.store_32(VERSION)
	f.store_32(hb.size())
	f.store_buffer(hb)
	f.store_32(raw.size())
	f.store_buffer(raw.compress(FileAccess.COMPRESSION_ZSTD))
	f.close()
	return true


func best_time() -> float:
	return float(best.get("header", {}).get("time", 0.0))


# ---------------------------------------------------------------------------
# Recording
# ---------------------------------------------------------------------------
## Called whenever the lap clock starts again at the line (the old recording is done with).
func start_lap() -> void:
	_rec = PackedFloat32Array()
	_recording = true
	_acc = 1.0 / RATE       # (the first sample right away)
	_ref_i = 0
	for g in _ghosts:
		g.cursor = 0
	_sample(0.0, 0.0)


## A valid lap of `t` seconds: kept as the last lap, saved if it beats the best. Returns the time
## against the best before it (negative = faster), or 0 when there was none.
func lap_finished(t: float) -> float:
	if not _recording or _rec.size() < F * 4:
		return 0.0
	_sample(t, world.track.length)
	var car = world.local_car
	var rec := {"header": {
		"version": VERSION, "time": t, "track": world.track.track_id, "layout": world.track.layout,
		"map": str(world.config.get("map", "")), "car": str(car.car_id), "name": str(car.player_name),
		"date": Time.get_datetime_string_from_system(false, true), "weather": str(world.config.get("weather", "dry")),
	}, "data": _rec}
	_recording = false
	var prev := best_time()
	last = rec
	if prev <= 0.0 or t < prev:
		best = rec
		save_ghost(key, rec)
		_set_reference(best)
	_rebuild_ghosts()
	return t - prev if prev > 0.0 else 0.0


func _physics_process(dt: float) -> void:
	if world == null or not world.is_loaded:
		return
	var lap_t: float = float(world.race_time) - float(world.lap_start)
	if _recording and world.crossed_start:
		_acc += dt
		if _acc >= 1.0 / RATE:
			_acc = fmod(_acc, 1.0 / RATE)
			if lap_t < MAX_SECONDS:
				_sample(lap_t, float(world.progress))
	_update_delta(lap_t)


func _sample(t: float, dist: float) -> void:
	var car = world.local_car
	if car == null or not is_instance_valid(car):
		return
	var xf: Transform3D = car.global_transform
	var q := xf.basis.get_rotation_quaternion()
	var flags := (1 if car.braking_visual else 0) | (2 if car.headlights else 0)
	_rec.append_array([t, xf.origin.x, xf.origin.y, xf.origin.z, q.x, q.y, q.z, q.w,
		float(car.steer_angle), float(car.forward_speed), dist, float(flags)])


# ---------------------------------------------------------------------------
# Delta to the best lap
# ---------------------------------------------------------------------------
func _set_reference(g: Dictionary) -> void:
	_ref_dist = PackedFloat32Array()
	_ref_time = PackedFloat32Array()
	_ref_i = 0
	if g.is_empty():
		return
	var d: PackedFloat32Array = g["data"]
	var hi := -1.0
	for i in d.size() / F:
		# distance as a running maximum: a wobble backwards doesn't turn the curve around
		var di := d[i * F + 10]
		if di > hi:
			hi = di
			_ref_dist.append(di)
			_ref_time.append(d[i * F])


## The best lap's time at `dist` metres into the lap (-1: unknown).
func _ref_time_at(dist: float) -> float:
	var n := _ref_dist.size()
	if n < 2 or dist > _ref_dist[n - 1]:
		return -1.0
	if _ref_i >= n or _ref_dist[_ref_i] > dist:
		_ref_i = maxi(_ref_dist.bsearch(dist) - 1, 0)
	while _ref_i < n - 1 and _ref_dist[_ref_i + 1] < dist:
		_ref_i += 1
	var i := clampi(_ref_i, 0, n - 2)
	var a := _ref_dist[i]
	var b := _ref_dist[i + 1]
	var k := clampf((dist - a) / maxf(b - a, 0.001), 0.0, 1.0)
	return lerpf(_ref_time[i], _ref_time[i + 1], k)


func _update_delta(lap_t: float) -> void:
	delta_valid = false
	if not world.crossed_start or lap_t < 1.0 or world.finished:
		return
	var rt := _ref_time_at(float(world.progress))
	if rt < 0.0:
		return
	var d := lap_t - rt
	# a jump (a reset, a corner cut) shows at once, the small changes glide
	delta = d if absf(d - delta) > 1.5 else lerpf(delta, d, 0.25)
	delta_valid = true


# ---------------------------------------------------------------------------
# Ghost cars
# ---------------------------------------------------------------------------
func _rebuild_ghosts() -> void:
	var mode := clampi(int(Game.settings.get("ghost", 0)), 0, MODES.size() - 1)
	var want: Array = []
	if not best.is_empty() and mode in [0, 1]:
		want.append([best, BEST_TINT, Game.t("BESTZEIT %s") % Game.format_time(best_time())])
	if not last.is_empty() and mode in [1, 2] and not (mode == 1 and is_same(last, best)):
		want.append([last, LAST_TINT, Game.t("LETZTE RUNDE %s") % Game.format_time(float(last["header"]["time"]))])
	# the same recordings stay (their cars aren't built again)
	var keep: Array = []
	for g in _ghosts:
		var still := false
		for w in want:
			if is_same(g.rec, w[0]) and g.tag.text == w[2]:
				still = true
		if still:
			keep.append(g)
		else:
			g.node.queue_free()
	_ghosts = keep
	for w in want:
		var have := false
		for g in _ghosts:
			if is_same(g.rec, w[0]):
				have = true
		if not have:
			_ghosts.append(_make_ghost(w[0], w[1], w[2]))


static var _shader: Shader


static func ghost_shader() -> Shader:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = """
shader_type spatial;
render_mode blend_mix, depth_prepass_alpha, cull_back, unshaded, shadows_disabled;
uniform vec4 tint : source_color = vec4(0.35, 0.8, 1.0, 1.0);
uniform float alpha = 0.4;
void fragment() {
	// bright edges, a faint body: a see-through glowing car
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	ALBEDO = tint.rgb * (0.45 + 1.3 * rim);
	ALPHA = alpha * (0.35 + 0.9 * rim);
}
"""
	return _shader


func _make_ghost(rec: Dictionary, tint: Color, label: String) -> Ghost:
	var g := Ghost.new()
	g.rec = rec
	g.data = rec["data"]
	g.n = g.data.size() / F
	g.node = Node3D.new()
	g.node.name = "Ghost"
	world.add_child(g.node)
	var body := CarBody.new()
	g.node.add_child(body)
	body.build(str(rec["header"].get("car", "r34")), Game.get_paint("red", "", "gloss"), false)
	g.body = body
	g.mat = ShaderMaterial.new()
	g.mat.shader = ghost_shader()
	g.mat.set_shader_parameter("tint", tint)
	g.mat.render_priority = 1
	# no lights, no shadows: only its shape, see-through
	for l in body.find_children("*", "Light3D", true, false):
		l.queue_free()
	for gi in body.find_children("*", "GeometryInstance3D", true, false):
		var geo := gi as GeometryInstance3D
		geo.material_override = g.mat
		geo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for d in body.find_children("*", "Decal", true, false):
		d.queue_free()
	g.tag = Label3D.new()
	g.tag.text = label
	g.tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	g.tag.position = Vector3(0, 2.0, 0)
	g.tag.font_size = 40
	g.tag.outline_size = 10
	g.tag.modulate = tint
	g.node.add_child(g.tag)
	_pose(g, 0.0, 0.0)
	return g


func _process(dt: float) -> void:
	if world == null or not world.is_loaded or _ghosts.is_empty():
		return
	var lap_t: float = float(world.race_time) - float(world.lap_start) if world.crossed_start else 0.0
	var cam := get_viewport().get_camera_3d()
	var car = world.local_car
	for g: Ghost in _ghosts:
		var dur := g.data[(g.n - 1) * F]
		# waiting at the line until the clock runs, gone once its lap is over
		var shown: bool = lap_t <= dur + 0.5 and not world.finished
		_pose(g, minf(lap_t, dur), dt)
		var a := 0.42 if world.crossed_start else 0.22
		# close to the camera or the car it fades almost away (you see where you are going)
		var p: Vector3 = g.node.global_position
		var near := 1e9
		if cam:
			near = cam.global_position.distance_to(p)
		if car and is_instance_valid(car):
			near = minf(near, (car.global_position as Vector3).distance_to(p) + 1.0)
		a *= clampf((near - 3.0) / 9.0, 0.12, 1.0)
		g.fade = move_toward(g.fade, a if shown else 0.0, dt * 2.5)
		g.node.visible = g.fade > 0.01
		g.mat.set_shader_parameter("alpha", g.fade)
		g.tag.modulate.a = clampf(g.fade * 2.0, 0.0, 1.0) * clampf((near - 6.0) / 10.0, 0.0, 1.0)


## Places a ghost at `t` seconds into its lap (interpolated between the samples).
func _pose(g: Ghost, t: float, dt: float) -> void:
	var d := g.data
	if g.cursor >= g.n or d[g.cursor * F] > t:
		g.cursor = 0
	while g.cursor < g.n - 2 and d[(g.cursor + 1) * F] <= t:
		g.cursor += 1
	var i := g.cursor * F
	var j := mini(g.cursor + 1, g.n - 1) * F
	var k := clampf((t - d[i]) / maxf(d[j] - d[i], 0.0001), 0.0, 1.0)
	var p := Vector3(d[i + 1], d[i + 2], d[i + 3]).lerp(Vector3(d[j + 1], d[j + 2], d[j + 3]), k)
	var q := Quaternion(d[i + 4], d[i + 5], d[i + 6], d[i + 7]).normalized().slerp(Quaternion(d[j + 4], d[j + 5], d[j + 6], d[j + 7]).normalized(), k)
	g.node.global_transform = Transform3D(Basis(q), p)
	g.steer = lerpf(d[i + 8], d[j + 8], k)
	g.speed = lerpf(d[i + 9], d[j + 9], k)
	var wr: float = maxf(float(g.body.get("wheel_r")), 0.2)
	g.spin = wrapf(g.spin - g.speed / wr * dt, -TAU, TAU)
	var nodes: Array = g.body.get("wheel_nodes")
	for w in nodes.size():
		if w < 2:
			(nodes[w][0] as Node3D).rotation.y = -g.steer
		(nodes[w][1] as Node3D).rotation.x = g.spin


func _exit_tree() -> void:
	for g in _ghosts:
		if is_instance_valid(g.node):
			g.node.queue_free()
	_ghosts.clear()

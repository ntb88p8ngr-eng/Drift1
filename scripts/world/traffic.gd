extends Node3D
## Optional NPC traffic on the race route: ordinary cars cruising the lap in both lanes at city speed.
## They keep their distance to whatever is in front of them (players, bots, each other) and brake for
## it. Moved every frame (smooth at any frame rate) and drawn by traffic_cars.gd, which also makes the
## ones near the players solid. Offline only – the traffic is not synced over the network.

const LANE := 0.42            # lateral position of the lanes: share of the half width either side
## Density levels (menu "Verkehr"): cars per km of lap.
const DENSITY := [0.0, 6.0, 12.0, 20.0, 30.0]
const GAP := 14.0             # metres they keep to the car in front
const LOOK := 45.0            # how far ahead they look

var world
var track
var render                    # traffic_cars.gd
## {progress, v, v_want, lane, model, paint, half, odo, brake, xf}
var cars: Array = []
var _rng := RandomNumberGenerator.new()


## count: number of cars (spread over the lap, every second one in the left lane)
func setup(p_world, count: int, p_render) -> void:
	world = p_world
	track = world.track
	render = p_render
	_rng.seed = 2468
	if render == null or not render.ok:
		return
	var L: float = track.length
	for k in count:
		var pick: Array = render.pick(_rng)
		# spread over the lap, away from the start grid
		var prog := fposmod(120.0 + L * (k + _rng.randf_range(0.0, 0.5)) / count, L)
		var v_want := _rng.randf_range(11.0, 17.0)       # 40 – 60 km/h
		# two lanes in the driving direction (the race route is one-way): right and left
		var lane := (1.0 if k % 2 == 0 else -1.0) * LANE
		var t := {"progress": prog, "v": v_want, "v_want": v_want, "lane": lane, "model": pick[0], "paint": pick[1],
			"half": render.half_length(int(pick[0])), "odo": _rng.randf() * 100.0, "brake": false}
		t["xf"] = _xf(t)
		cars.append(t)


func _process(delta: float) -> void:
	if world == null or cars.is_empty():
		return
	delta = minf(delta, 0.1)
	var L: float = track.length
	# everything that can be in the way, sorted along the lap: [progress, lateral, speed, half length]
	var obstacles: Array = []
	for id in world.cars:
		var c = world.cars[id]
		if not is_instance_valid(c) or not c.visible:
			continue
		var pr: Array = track.project(c.global_position, int(c.track_hint) if "track_hint" in c else -1)
		var prog := fposmod(float(track.dists[int(pr[0])]) - float(track.start_dist), L)
		obstacles.append([prog, float(pr[2]), maxf(float(c.forward_speed), 0.0), 2.3])
	for t in cars:
		obstacles.append([float(t["progress"]), float(track.half_w) * float(t["lane"]), float(t["v"]), float(t["half"])])
	obstacles.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	var progs := PackedFloat32Array()
	progs.resize(obstacles.size())
	for k in obstacles.size():
		progs[k] = obstacles[k][0]
	var n := obstacles.size()
	for t in cars:
		var prog: float = t["progress"]
		var lane: float = float(track.half_w) * float(t["lane"])
		var want: float = t["v_want"]
		# slower in tight corners
		var i: int = track.index_at(prog + 12.0)
		var k := absf(float(track.curvature[i]))
		if k > 1e-4:
			want = minf(want, sqrt(4.0 / k))
		# keep the distance to anything ahead in (or across) the lane: only the stretch just ahead
		var half_len: float = t["half"]
		var j := progs.bsearch(prog + 0.5)
		for step in n:
			var o: Array = obstacles[(j + step) % n]
			var ahead := fposmod(float(o[0]) - prog, L)
			if ahead > LOOK:
				break
			if ahead < 0.5 or absf(float(o[1]) - lane) > 3.2:
				continue
			# bumper to bumper, 2 m spare
			var gap := ahead - half_len - float(o[3]) - 2.0
			if gap < GAP:
				want = minf(want, float(o[2]) * clampf(gap / GAP, 0.0, 1.0))
		var v: float = t["v"]
		var nv := move_toward(v, want, (6.0 if want < v else 2.0) * delta)
		t["brake"] = nv < v - 0.5 * delta or nv < 0.3
		t["v"] = nv
		t["progress"] = fposmod(prog + nv * delta, L)
		t["odo"] = float(t["odo"]) + nv * delta
		t["xf"] = _xf(t)
		render.add(int(t["model"]), t["xf"], t["paint"], float(t["odo"]), bool(t["brake"]))


func _xf(t: Dictionary) -> Transform3D:
	var prog: float = t["progress"]
	var i: int = track.index_at(prog)
	var n: int = track.sample_count()
	var i2: int = (i + 1) % n
	var f := clampf((prog - fposmod(float(track.dists[i]) - float(track.start_dist), float(track.length))) / float(track.SPACING), 0.0, 1.0)
	var lane: float = float(track.half_w) * float(t["lane"])
	var a: Vector3 = track.edge_point(i, lane)
	var b: Vector3 = track.edge_point(i2, lane)
	var p := a.lerp(b, f) + Vector3(0, float(track.ROAD_Y), 0)
	var fwd: Vector3 = (track.tangents[i] as Vector3).lerp(track.tangents[i2], f).normalized()
	return Transform3D(Basis.looking_at(fwd, Vector3.UP), p)

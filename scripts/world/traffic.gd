extends Node3D
## Optional NPC traffic on the race route: ordinary cars cruising the lap in both lanes (the route
## is one-way). They keep a safe gap to whatever is in front (players, bots, each other), brake and
## pull away gently (the acceleration changes smoothly, no jolts), change lanes to pass a slower car
## or now and then just so, and drive at the speed chosen in the menu. Moved every frame and drawn
## by traffic_cars.gd, which also makes the ones near the players solid: a car you hit is knocked
## aside for real and then steers back into a lane. Offline only – not synced over the network.

const LANE := 0.42            # lane centres: share of the half width either side
## Density levels (menu "Verkehr"): cars per km of lap.
const DENSITY := [0.0, 10.0, 18.0, 28.0, 40.0]
## Speed levels (menu "Verkehrstempo"), km/h.
const SPEEDS := [30.0, 50.0, 70.0, 90.0, 120.0]
const LOOK := 70.0            # how far ahead they look
const HEADWAY := 1.2          # seconds of gap they keep
const MIN_GAP := 2.5          # metres bumper to bumper when stopped
const ACC := 1.9              # gentle pull-away (m/s²)
const BRAKE := 3.0            # comfortable braking
const BRAKE_MAX := 7.5        # an emergency
const JERK := 5.0             # how quickly the acceleration may change (m/s³)
const LAT_W := 1.15           # lane change: spring rate (a change takes ~3.5 s)
const ID_BASE := 0            # ids for traffic_cars.gd (the city's start at 100000)

class TCar:
	var id := 0
	var progress := 0.0
	var v := 0.0
	var a := 0.0
	var v_want := 14.0
	var lane := 1.0           # the lane it wants to be in: +1 right, -1 left
	var lat := 0.0            # where it is across the road (m, + right)
	var lat_v := 0.0
	var think := 0.0          # time until it may consider a lane change
	var shaken := 0.0         # after a knock: waits a moment before driving on
	var model := 0
	var paint := Color.WHITE
	var half := 2.2
	var odo := 0.0
	var brake := false
	var xf := Transform3D.IDENTITY

var world
var track
var render                    # traffic_cars.gd
var cars: Array = []          # TCar
var speed_kmh := 50.0
var stats := {}
var _rng := RandomNumberGenerator.new()
var _lane_lat := 3.0


## count: number of cars (spread over the lap, half of them in each lane); speed_level: SPEEDS index
func setup(p_world, count: int, p_render, speed_level := 1) -> void:
	world = p_world
	track = world.track
	render = p_render
	_rng.seed = 2468
	speed_kmh = float(SPEEDS[clampi(speed_level, 0, SPEEDS.size() - 1)])
	_lane_lat = float(track.half_w) * LANE
	if render == null or not render.ok:
		return
	var L: float = track.length
	for k in count:
		var pick: Array = render.pick(_rng)
		var t := TCar.new()
		t.id = ID_BASE + k
		# spread over the lap, away from the start grid
		t.progress = fposmod(120.0 + L * (k + _rng.randf_range(0.0, 0.5)) / count, L)
		t.v_want = speed_kmh / 3.6 * _rng.randf_range(0.85, 1.1)
		t.v = t.v_want * 0.8
		t.lane = 1.0 if k % 2 == 0 else -1.0
		t.lat = t.lane * _lane_lat
		t.think = _rng.randf_range(2.0, 12.0)
		t.model = pick[0]
		t.paint = pick[1]
		t.half = render.half_length(t.model)
		t.odo = _rng.randf() * 100.0
		t.xf = _xf(t)
		cars.append(t)
	stats["cars"] = cars.size()


func _process(delta: float) -> void:
	if world == null or cars.is_empty():
		return
	delta = minf(delta, 0.05)
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
	for t: TCar in cars:
		obstacles.append([t.progress, t.lat, t.v, t.half])
	obstacles.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	var progs := PackedFloat32Array()
	progs.resize(obstacles.size())
	for k in obstacles.size():
		progs[k] = obstacles[k][0]
	for t: TCar in cars:
		_drive(t, obstacles, progs, delta)
		render.add(t.model, t.xf, t.paint, t.odo, t.brake, t.v, t.id)


func _drive(t: TCar, obstacles: Array, progs: PackedFloat32Array, delta: float) -> void:
	var L: float = track.length
	# knocked by a player (traffic_cars.gd reports where the solid car is against where it should
	# be): carry on from where it now is – the lane spring steers it back into a lane
	var e: Vector3 = render.disturbance(t.id)
	if e != Vector3.ZERO:
		t.progress = fposmod(t.progress + e.x, L)
		t.lat += e.y
		t.lat_v = 0.0
		t.lane = 1.0 if t.lat >= 0.0 else -1.0
		t.v = maxf(t.v + e.x * 2.0, 0.0) * 0.6
		t.a = minf(t.a, 0.0)
		t.shaken = maxf(t.shaken, 1.0)
	var want := t.v_want
	# slower in tight corners
	var k := absf(float(track.curvature[track.index_at(t.progress + 10.0 + t.v)]))
	if k > 1e-4:
		want = minf(want, sqrt(3.5 / k))
	# the one in front: in the lane it is in, and (changing lanes) in the one it is going to
	var gap := 1e9
	var lv := 0.0
	var free_left := true      # the other lane, for a lane change
	var other := -t.lane * _lane_lat
	var mine := t.lane * _lane_lat
	var n := obstacles.size()
	var j := progs.bsearch(t.progress + 0.01)
	for step in n:
		var o: Array = obstacles[(j + step) % n]
		var ahead := fposmod(float(o[0]) - t.progress, L)
		if ahead > LOOK:
			break
		if ahead < 0.01:
			continue
		var ol: float = o[1]
		var g := ahead - t.half - float(o[3])
		if absf(ol - t.lat) < 2.6 or absf(ol - mine) < 2.6:
			if g < gap:
				gap = g
				lv = o[2]
		if absf(ol - other) < 2.6 and g < 30.0 + maxf(t.v - float(o[2]), 0.0) * 3.0:
			free_left = false
	# and the other lane just behind (someone coming up there)
	if free_left:
		for step in range(1, n):
			var o: Array = obstacles[(j - step + n * 4) % n]
			var behind := fposmod(t.progress - float(o[0]), L)
			if behind > 40.0:
				break
			if absf(float(o[1]) - other) < 2.6 and behind < t.half + float(o[3]) + 4.0 + maxf(float(o[2]) - t.v, 0.0) * 3.0:
				free_left = false
				break
	# the intelligent driver model: eases up to its speed, follows at a safe time gap and comes to
	# a smooth stop behind whatever stands in its lane
	var free_road := 1.0 - pow(t.v / maxf(want, 0.5), 4.0)
	var inter := 0.0
	if gap < LOOK:
		var s_star := MIN_GAP + maxf(0.0, t.v * HEADWAY + t.v * (t.v - lv) / (2.0 * sqrt(ACC * BRAKE)))
		inter = pow(s_star / maxf(gap, 0.1), 2.0)
	var a_want := clampf(ACC * (free_road - inter), -BRAKE_MAX, ACC)
	if t.shaken > 0.0:
		t.shaken -= delta
		if t.shaken > 0.4:
			a_want = -BRAKE
	# lane changes: past a slower car, or now and then (when the other lane is clear)
	t.think -= delta
	if t.think <= 0.0 and t.shaken <= 0.0 and absf(t.lat - mine) < 0.4:
		var blocked := gap < 40.0 and lv < t.v_want - 1.5
		if free_left and (blocked or _rng.randf() < 0.12):
			t.lane = -t.lane
			t.think = _rng.randf_range(7.0, 14.0)
		else:
			t.think = _rng.randf_range(1.0, 3.0)
	# across the road: a damped spring to the lane's centre (a smooth S, never a jerk)
	var target := t.lane * _lane_lat
	var lat_a := (target - t.lat) * LAT_W * LAT_W - 2.0 * LAT_W * t.lat_v
	t.lat_v = clampf(t.lat_v + lat_a * delta, -2.2, 2.2)
	t.lat += t.lat_v * delta
	# along: the acceleration eases towards what's needed; firm braking comes at once
	var urgent := a_want < minf(t.a, -2.0) or (gap < MIN_GAP + 3.0 and lv < t.v)
	t.a = move_toward(t.a, a_want, (JERK * 6.0 if urgent else JERK) * delta)
	var nv := maxf(t.v + t.a * delta, 0.0)
	if nv <= 0.0:
		t.a = maxf(t.a, 0.0)
	t.brake = t.a < -0.6 or nv < 0.3
	t.v = nv
	t.progress = fposmod(t.progress + nv * delta, L)
	t.odo += nv * delta
	t.xf = _xf(t)


## Position on the lap: the sample at or before `progress` and the next one (not the nearest – that
## parked every car for half a sample and then jumped it on: the stutter of the old traffic).
func _xf(t: TCar) -> Transform3D:
	var L: float = track.length
	var n: int = track.sample_count()
	var i: int = track.index_at(t.progress)
	var pi := fposmod(float(track.dists[i]) - float(track.start_dist), L)
	var d := wrapf(t.progress - pi, -L * 0.5, L * 0.5)
	if d < 0.0:
		i = (i - 1 + n) % n
		pi = fposmod(float(track.dists[i]) - float(track.start_dist), L)
		d = wrapf(t.progress - pi, -L * 0.5, L * 0.5)
	var i2 := (i + 1) % n
	var seg := wrapf(fposmod(float(track.dists[i2]) - float(track.start_dist), L) - pi, -L * 0.5, L * 0.5)
	var f := clampf(d / maxf(seg, 0.01), 0.0, 1.0)
	var a: Vector3 = track.edge_point(i, t.lat)
	var b: Vector3 = track.edge_point(i2, t.lat)
	var p := a.lerp(b, f) + Vector3(0, float(track.ROAD_Y), 0)
	var fwd: Vector3 = (track.tangents[i] as Vector3).lerp(track.tangents[i2], f)
	fwd.y = 0.0
	fwd = fwd.normalized()
	# turned a little into a lane change
	if t.v > 0.5:
		var right := Vector3(-fwd.z, 0, fwd.x)
		fwd = (fwd + right * (t.lat_v / maxf(t.v, 3.0))).normalized()
	return Transform3D(Basis.looking_at(fwd, Vector3.UP), p)

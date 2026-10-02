extends Node3D
## Optional NPC traffic: ordinary cars cruising the lap in the right-hand lane at city speed. They keep
## their distance to whatever is in front of them (players, bots, each other) and brake for it, and
## they are solid (kinematic bodies: they push a car that sits in their way, a crash doesn't throw
## them off their lane). Offline only – the traffic is not synced over the network.

const Props = preload("res://scripts/world/prop_meshes.gd")

const KINDS := ["car_sedan", "car_sedan", "car_hatch", "car_hatch", "car_kei", "car_van"]
const PAINTS := [Color(0.92, 0.92, 0.9), Color(0.1, 0.1, 0.11), Color(0.55, 0.56, 0.58), Color(0.62, 0.05, 0.05),
	Color(0.08, 0.18, 0.5), Color(0.75, 0.72, 0.62), Color(0.95, 0.75, 0.1), Color(0.15, 0.3, 0.2)]
const LANE := 0.42            # lateral position of the lanes: share of the half width either side
## Density levels (menu "Verkehr"): cars per km of lap.
const DENSITY := [0.0, 6.0, 12.0, 20.0, 30.0]
const GAP := 14.0             # metres they keep to the car in front

var world
var track
var cars: Array = []          # {body, progress, v, v_want, size}
var _rng := RandomNumberGenerator.new()


## count: number of cars (spread over the lap, every second one in the left lane)
func setup(p_world, count: int) -> void:
	world = p_world
	track = world.track
	_rng.seed = 2468
	var L: float = track.length
	var night: float = world.atmosphere.night if world.atmosphere else 0.0
	var tail := TexKit_emissive(Color(1.0, 0.05, 0.03), 0.4 + 2.6 * night)
	var head := TexKit_emissive(Color(1.0, 0.95, 0.85), 0.3 + 3.0 * night)
	for k in count:
		var kind: String = KINDS[_rng.randi() % KINDS.size()]
		var size: Vector3 = Props.CAR_SIZES[kind]
		var body := AnimatableBody3D.new()
		body.name = "Traffic%d" % k
		body.sync_to_physics = true
		body.collision_layer = 1
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		cs.shape = box
		cs.position = Vector3(0, size.y * 0.5, 0)
		body.add_child(cs)
		# the parked-car mesh takes its paint from the MultiMesh custom data
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = Props.get_mesh(kind)
		mm.instance_count = 1
		mm.set_instance_transform(0, Transform3D.IDENTITY)
		var paint: Color = PAINTS[_rng.randi() % PAINTS.size()]
		mm.set_instance_custom_data(0, Color(paint.r, paint.g, paint.b, 1.0))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		body.add_child(mmi)
		# lamps: tail lights at the back (+Z), head lights at the front
		for sx: float in [-1.0, 1.0]:
			var t := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.3, 0.12, 0.05)
			t.mesh = bm
			t.material_override = tail
			t.position = Vector3(sx * (size.x * 0.5 - 0.2), size.y * 0.55, size.z * 0.5 + 0.02)
			body.add_child(t)
			var h := MeshInstance3D.new()
			h.mesh = bm
			h.material_override = head
			h.position = Vector3(sx * (size.x * 0.5 - 0.25), size.y * 0.45, -size.z * 0.5 - 0.02)
			body.add_child(h)
		add_child(body)
		# spread over the lap, away from the start grid
		var prog := fposmod(120.0 + L * (k + _rng.randf_range(0.0, 0.5)) / count, L)
		var v_want := _rng.randf_range(11.0, 17.0)       # 40 – 60 km/h
		# two lanes in the driving direction (the city streets are one-way): right and left
		var lane := (1.0 if k % 2 == 0 else -1.0) * LANE
		cars.append({"body": body, "progress": prog, "v": v_want, "v_want": v_want, "size": size, "lane": lane})
		_place(cars[k])


static func TexKit_emissive(c: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	return m


func _physics_process(delta: float) -> void:
	if world == null or cars.is_empty():
		return
	var L: float = track.length
	# everything that can be in the way: players, bots and the other traffic, as [progress, lateral, speed]
	var obstacles: Array = []
	for id in world.cars:
		var c = world.cars[id]
		if not is_instance_valid(c) or not c.visible:
			continue
		var pr: Array = track.project(c.global_position, int(c.track_hint) if "track_hint" in c else -1)
		var prog := fposmod(float(track.dists[int(pr[0])]) - float(track.start_dist), L)
		obstacles.append([prog, float(pr[2]), maxf(float(c.forward_speed), 0.0)])
	for t in cars:
		obstacles.append([float(t["progress"]), float(track.half_w) * float(t["lane"]), float(t["v"])])
	for t in cars:
		var prog: float = t["progress"]
		var lane: float = float(track.half_w) * float(t["lane"])
		var want: float = t["v_want"]
		# slower in tight corners
		var i: int = track.index_at(prog + 12.0)
		var k := absf(float(track.curvature[i]))
		if k > 1e-4:
			want = minf(want, sqrt(4.0 / k))
		# keep the distance to anything ahead in (or across) the lane
		var half_len: float = float(t["size"].z) * 0.5
		for o in obstacles:
			var ahead := fposmod(float(o[0]) - prog, L)
			if ahead < 0.5 or ahead > 45.0:
				continue
			if absf(float(o[1]) - lane) > 3.2:
				continue
			# bumper to bumper (the other car's half length taken as a typical 2.3 m), 2 m spare
			var gap := ahead - half_len - 2.3 - 2.0
			if gap < GAP:
				want = minf(want, float(o[2]) * clampf(gap / GAP, 0.0, 1.0))
		var v: float = t["v"]
		v = move_toward(v, want, (6.0 if want < v else 2.0) * delta)
		t["v"] = v
		t["progress"] = fposmod(prog + v * delta, L)
		_place(t)


func _place(t: Dictionary) -> void:
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
	var body: AnimatableBody3D = t["body"]
	body.global_transform = Transform3D(Basis.looking_at(fwd, Vector3.UP), p)

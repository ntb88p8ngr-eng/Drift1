extends Node3D
## Camping along the track, 24h-race style: camps behind the barriers with dome tents, caravans,
## pavilions, beer benches, portable toilets, a campfire and a grill with people standing round it,
## string lights between the poles, gravel paths from camp to camp and down to the fence, and groups
## of spectators all along the lap. Everything is instanced (one MultiMesh per kind and chunk); the
## fires flicker, the bulbs and fires light up at night.

const MeshKit = preload("res://scripts/util/mesh_kit.gd")
const Props = preload("res://scripts/world/prop_meshes.gd")
const Crowd = preload("res://scripts/world/crowd.gd")
const Colliders = preload("res://scripts/util/colliders.gd")
const GhPaddock = preload("res://scripts/world/gh_paddock.gd")

const FIRE_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;

varying float h;

void vertex() {
	h = VERTEX.y;
	float id = INSTANCE_CUSTOM.a * 40.0;
	float w = 1.0 + 0.22 * sin(TIME * 11.0 + VERTEX.y * 7.0 + id) + 0.12 * sin(TIME * 17.0 + id * 1.7);
	VERTEX.xz *= w;
	VERTEX.y *= 0.85 + 0.25 * (0.5 + 0.5 * sin(TIME * 7.3 + id * 2.3));
}

void fragment() {
	float k = clamp(h / 0.9, 0.0, 1.0);
	ALBEDO = mix(vec3(1.0, 0.82, 0.32), vec3(1.0, 0.25, 0.04), k) * 1.6;
}
"""

const BULB_SHADER := """
shader_type spatial;
render_mode unshaded, shadows_disabled;

uniform float glow = 0.0;

varying vec3 c;

void vertex() {
	c = INSTANCE_CUSTOM.rgb;
}

void fragment() {
	ALBEDO = mix(c * 0.35, c * 2.2, glow);
}
"""

const TENT_COLS := [Color(0.85, 0.15, 0.1), Color(0.15, 0.35, 0.8), Color(0.2, 0.55, 0.25), Color(0.95, 0.75, 0.15),
	Color(0.9, 0.45, 0.1), Color(0.55, 0.6, 0.3), Color(0.3, 0.32, 0.36), Color(0.75, 0.75, 0.72), Color(0.55, 0.2, 0.6),
	Color(0.1, 0.55, 0.6)]
const SMALL_CLEAR := 9.5      # below the scenery's large-object radius: goes into its fast grid
const BULB_COLS := [Color(1.0, 0.75, 0.35), Color(1.0, 0.3, 0.2), Color(0.3, 0.6, 1.0), Color(0.4, 1.0, 0.4), Color(1.0, 0.9, 0.3)]

var track
var terrain
var scenery
var rng := RandomNumberGenerator.new()
var _meshes := {}            # kind -> [mesh, view range, shadows]
var _sets := {}              # kind -> chunk dictionary
var _bulb_mat: ShaderMaterial
var _lights: Array = []
var _camps: Array = []       # [centre, side, sample index]
var _stats := {}
var paddock: Node3D


func build(p_track, p_terrain, p_scenery, quality: int) -> void:
	track = p_track
	terrain = p_terrain
	scenery = p_scenery
	rng.seed = hash(track.track_id) + 2424
	if track.track_id == "playground" or scenery.tutorial_site != null:
		return        # no room on the pad; the tutorial is a lonely night drive
	_make_meshes()
	if track.track_id == "gruene_hoelle":
		# pit lane, garages, grandstands and the Ferris wheel first: the camps keep clear of them
		paddock = GhPaddock.new()
		paddock.name = "Paddock"
		add_child(paddock)
		await paddock.build(track, terrain, scenery, self)
	var big := bool(track.elevated)
	var n: int = track.sample_count()
	var sp: float = track.SPACING
	# camps: every ~110 m on the long track (a festival), every ~190 m elsewhere (fewer in the docks)
	var step_m: float = 70.0 if big else (260.0 if track.track_id == "harbor" else 140.0)
	if track.track_id == "tokyo":
		step_m = 1e9      # no camping in the city – only the spectators
	step_m *= [1.6, 1.25, 1.0, 0.85][clampi(quality, 0, 3)]
	var step := maxi(int(step_m / sp), 8)
	var i := int(track.start_index) + int(60.0 / sp)
	var placed := 0
	var guard := 0
	while guard < n:
		var idx := i % n
		if placed % 6 == 0:
			await Game.load_tick()
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		if _camp(idx, side) or _camp(idx, -side):
			placed += 1
		i += int(step * rng.randf_range(0.75, 1.25))
		guard += step
	_paths_between_camps()
	_access_points()
	if paddock:
		paddock.link_paths(self)
	# spectators: small groups all round the lap, right behind the barrier
	var sstep := maxi(int((38.0 if big else 30.0) * [1.8, 1.4, 1.0, 0.8][clampi(quality, 0, 3)] / sp), 4)
	for j in range(0, n, sstep):
		if j % (sstep * 40) == 0:
			await Game.load_tick()
		_spectators((j + rng.randi_range(0, sstep - 1)) % n, 1.0 if rng.randf() < 0.5 else -1.0)
	for kind in _sets.keys():
		var m: Array = _meshes[kind]
		scenery._emit_chunks(m[0], _sets[kind], 0.0, float(m[1]), "Fest_" + kind, bool(m[2]))
	print("FESTIVAL: %d camps, %s" % [_camps.size(), str(_stats)])


func set_night(nv: float) -> void:
	if paddock:
		paddock.set_night(nv)
	if _bulb_mat:
		_bulb_mat.set_shader_parameter("glow", clampf(nv * 1.4, 0.0, 1.0))
	for l in _lights:
		(l as Light3D).visible = nv > 0.3
		(l as Light3D).light_energy = 1.6 * nv


func _add(kind: String, xf: Transform3D, custom := Color(1, 1, 1, 1)) -> void:
	if not _sets.has(kind):
		_sets[kind] = {}
	scenery._push(_sets[kind], xf.origin, [xf, custom])
	_stats[kind] = int(_stats.get(kind, 0)) + 1


func _ground(p: Vector3) -> Vector3:
	return Vector3(p.x, terrain.height_at(p.x, p.z), p.z)


func _ok(p: Vector3, road_gap := 4.0) -> bool:
	if terrain.normal_at(p.x, p.z).y < 0.9:
		return false
	return terrain.distance_to_road(p.x, p.z) > float(track.wall_base) + road_gap


func _person(p: Vector3, look_at: Vector3) -> void:
	_person_raw(_ground(p), look_at)


## A person standing exactly at p (stands, roofs), facing look_at.
func _person_raw(p: Vector3, look_at: Vector3) -> void:
	var d := look_at - p
	d.y = 0.0
	if d.length() < 0.01:
		d = Vector3(0, 0, -1)
	var b := Basis.looking_at(d.normalized(), Vector3.UP)
	var sc := rng.randf_range(0.9, 1.08)
	var shirt: Color = Crowd.SHIRTS[rng.randi() % Crowd.SHIRTS.size()]
	_add("person", Transform3D((b * Basis.from_scale(Vector3(sc, sc * rng.randf_range(0.95, 1.06), sc))), p), Color(shirt.r, shirt.g, shirt.b, rng.randf()))


# ---------------------------------------------------------------------------
# Camps
# ---------------------------------------------------------------------------
## One camp behind the barrier at sample i on `side`. False when there's no room. Every element gets
## its own space (caravan + awning + car, tents, pavilion, fire, grill, toilets): nothing overlaps.
func _camp(i: int, side: float) -> bool:
	var big := bool(track.elevated)
	var r := rng.randf_range(15.0, 22.0) if big else rng.randf_range(11.0, 15.0)
	var extra := r + rng.randf_range(6.0, 14.0)
	var c: Vector3 = scenery._roadside(i, extra, side)
	if not scenery.free_at(c, r, 4.0) or not _ok(c, 6.0):
		return false
	# the whole camp area must be fairly flat
	for k in 8:
		var a := TAU * k / 8.0
		var q := c + Vector3(cos(a), 0, sin(a)) * r * 0.85
		if not _ok(q, 3.0) or absf(terrain.height_at(q.x, q.z) - terrain.height_at(c.x, c.z)) > 1.8:
			return false
	c = _ground(c)
	var to_road: Vector3 = -track.rights[i] * side   # from the camp towards the track
	var fz := Vector3(-to_road.x, 0.0, -to_road.z).normalized()
	var frame := Basis(Vector3.UP.cross(fz), Vector3.UP, fz)
	# frame: -Z looks at the track, X along it
	var yaw_to_road := atan2(-to_road.x, -to_road.z)
	var taken: Array = []        # [Vector2 local x/z, radius]
	# a free spot for something of radius `rad` in the local box x0..x1, z0..z1 (null: none)
	var spot := func(rad: float, x0: float, x1: float, z0: float, z1: float):
		for tries in 24:
			var lx := rng.randf_range(x0, x1)
			var lz := rng.randf_range(z0, z1)
			if Vector2(lx, lz).length() > r - rad * 0.6:
				continue
			var ok := true
			for t in taken:
				if (t[0] as Vector2).distance_to(Vector2(lx, lz)) < float(t[1]) + rad + 0.8:
					ok = false
					break
			if not ok:
				continue
			var wp := _ground(c + frame.x * lx + frame.z * lz)
			if not _ok(wp, 3.0):
				continue
			taken.append([Vector2(lx, lz), rad])
			return wp
		return null
	# caravans (each with its awning and a car beside it) towards the back
	var nc := rng.randi_range(4, 7) if big else rng.randi_range(2, 4)
	var first_caravan = null
	for k in nc:
		var p = spot.call(5.0, -r, r, -r * 0.1, r)
		if p == null:
			continue
		var yaw := yaw_to_road + PI * 0.5 + rng.randf_range(-0.35, 0.35) + (PI if rng.randf() < 0.5 else 0.0)
		var cb := Basis(Vector3.UP, yaw)
		var xf := Transform3D(cb, p)
		var tint := Color(1, 1, 1).darkened(rng.randf_range(0.0, 0.15))
		_add("caravan", xf, Color(tint.r, tint.g, tint.b * rng.randf_range(0.9, 1.0), 1))
		Colliders.add_box(self, xf * Transform3D(Basis.IDENTITY, Vector3(0, 1.4, 0)), Vector3(2.3, 2.6, 5.8))
		if rng.randf() < 0.7:
			var awn: Color = TENT_COLS[rng.randi() % TENT_COLS.size()]
			_add("awning", xf, Color(awn.r, awn.g, awn.b, 1))
		# the car on the side away from the awning
		var cp: Vector3 = _ground(p - cb.x * 3.4 + cb.z * rng.randf_range(-0.8, 0.8))
		if _ok(cp, 3.0) and scenery.details:
			scenery.details.add_parked_car(Transform3D(Basis(Vector3.UP, yaw + rng.randf_range(-0.15, 0.15)), cp))
		if first_caravan == null:
			first_caravan = p
	# a pavilion with beer benches, string lights from it to the first caravan
	var gp = spot.call(2.8, -r * 0.5, r * 0.5, -r * 0.6, r * 0.2)
	if gp != null:
		var gcol: Color = TENT_COLS[rng.randi() % TENT_COLS.size()]
		_add("gazebo", Transform3D(Basis(Vector3.UP, yaw_to_road + PI * 0.25), gp), Color(gcol.r, gcol.g, gcol.b, 1))
		_add("beer_set", Transform3D(Basis(Vector3.UP, yaw_to_road + PI * 0.5), gp))
		for k in 4:
			_person(gp + frame.z * (0.75 if k % 2 == 0 else -0.75) + frame.x * (k / 2 - 0.5) * 1.2, gp)
		if first_caravan != null:
			_string_lights(gp + Vector3(0, 2.3, 0), (first_caravan as Vector3) + Vector3(0, 2.5, 0))
	# the campfire with chairs and people round it (towards the track: the view)
	var fp = spot.call(3.0, -r * 0.6, r * 0.6, -r, -r * 0.2)
	if fp != null:
		_add("campfire", Transform3D(Basis(Vector3.UP, rng.randf() * TAU), fp))
		_add("fire", Transform3D(Basis.IDENTITY, fp + Vector3(0, 0.05, 0)), Color(1, 1, 1, rng.randf()))
		var np := rng.randi_range(3, 7)
		for k in np:
			var a := TAU * k / np + rng.randf_range(-0.2, 0.2)
			var pp: Vector3 = fp + Vector3(cos(a), 0, sin(a)) * rng.randf_range(1.6, 2.1)
			if rng.randf() < 0.5:
				_add("chair", Transform3D(Basis.looking_at(Vector3(fp.x - pp.x, 0, fp.z - pp.z).normalized(), Vector3.UP), _ground(pp)),
					Color(TENT_COLS[rng.randi() % TENT_COLS.size()]))
			else:
				_person(pp, fp)
		if _lights.size() < 60:
			var l := OmniLight3D.new()
			l.light_color = Color(1.0, 0.6, 0.3)
			l.omni_range = 9.0
			l.distance_fade_enabled = true
			l.distance_fade_begin = 70.0
			l.distance_fade_length = 25.0
			l.shadow_enabled = false
			add_child(l)
			l.global_position = fp + Vector3(0, 1.0, 0)
			l.visible = false
			_lights.append(l)
	# grill: everybody's grilling
	var bp = spot.call(2.0, -r, r, -r, r)
	if bp != null:
		_add("grill", Transform3D(Basis(Vector3.UP, rng.randf() * TAU), bp))
		_add("fire", Transform3D((Basis.IDENTITY * Basis.from_scale(Vector3(0.45, 0.25, 0.45))), bp + Vector3(0, 0.82, 0)), Color(1, 1, 1, rng.randf()))
		for k in rng.randi_range(2, 5):
			var a := rng.randf_range(0.0, TAU)
			_person(bp + Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.9, 1.5), bp)
	# portable toilets at the edge
	if rng.randf() < 0.6:
		var tp = spot.call(2.2, r * 0.5, r, -r * 0.5, r * 0.5)
		if tp != null:
			for k in rng.randi_range(1, 3):
				_add("toilet", Transform3D(Basis(Vector3.UP, yaw_to_road), (tp as Vector3) + frame.x * (k - 1) * 1.25))
	# dome / tunnel tents in the space that's left
	var nt := rng.randi_range(14, 24) if big else rng.randi_range(6, 12)
	for k in nt:
		var s := rng.randf_range(0.85, 1.3)
		var long := rng.randf_range(1.0, 1.7)
		var p = spot.call(1.2 * s * long, -r, r, -r, r)
		if p == null:
			continue
		var col: Color = TENT_COLS[rng.randi() % TENT_COLS.size()]
		_add("tent", Transform3D((Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3(s, s * rng.randf_range(0.85, 1.05), s * long))), p),
			Color(col.r, col.g, col.b, 1))
	# people walking about
	var walkers := rng.randi_range(5, 12) if big else rng.randi_range(2, 6)
	for k in walkers:
		var wp = spot.call(0.4, -r, r, -r, r)
		if wp != null:
			_person(wp, (wp as Vector3) + Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)))
	# a clearing: the camp plus a margin, and open meadow down to the fence (no trees in between)
	scenery.occupy(c, r + 5.0)
	var front: Vector3 = scenery._roadside(i, 3.0, side)
	for k in 3:
		var q := front.lerp(c, (k + 0.5) / 3.0)
		scenery.occupy(q, minf(r + 2.0, SMALL_CLEAR))
	_camps.append([c, side, i])
	return true


## A few access points per side: an asphalt apron behind the barrier, a gravel path from it to the
## nearest camp (from there the camp-to-camp paths go on). Every ~1.5 km on the long track.
func _access_points() -> void:
	var n: int = track.sample_count()
	var every := int((1500.0 if bool(track.elevated) else 700.0) / float(track.SPACING))
	for side: float in [-1.0, 1.0]:
		var last := -100000
		for camp in _camps:
			if float(camp[1]) != side:
				continue
			var i: int = camp[2]
			if i - last < every:
				continue
			# the apron: 30 m along the barrier, 8 m deep, right behind it
			var ap: Vector3 = scenery._roadside(i, 5.0, side)
			if not _ok(ap, 2.0):
				continue
			ap = _ground(ap)
			var t: Vector3 = Vector3(track.tangents[i].x, 0, track.tangents[i].z).normalized()
			scenery.add_ground_patch(Transform3D(Basis.looking_at(t, Vector3.UP), ap), Vector2(8.0, 30.0), "asphalt")
			scenery.add_path([ap - track.rights[i] * side * -3.0, camp[0]], 3.0, "gravel")
			last = i
			_stats["access"] = int(_stats.get("access", 0)) + 1


## Links the camp network to a place (the fair, the grandstands): a path from the nearest camp.
func link_to_camps(p: Vector3) -> void:
	var best = null
	var bd := 1e9
	for camp in _camps:
		var d := (camp[0] as Vector3).distance_to(p)
		if d < bd:
			bd = d
			best = camp
	if best == null or bd > 400.0:
		return
	var pts: Array = []
	var nseg := maxi(int(bd / 12.0), 2)
	for j in nseg + 1:
		var q := (best[0] as Vector3).lerp(p, float(j) / nseg)
		if terrain.distance_to_road(q.x, q.z) < float(track.wall_base) + 4.0:
			return        # would cross the track: no link
		pts.append(q)
	scenery.add_path(pts, 3.0, "gravel")


## Bulbs hanging in a sagging line between a and b.
func _string_lights(a: Vector3, b: Vector3) -> void:
	var l := a.distance_to(b)
	if l < 2.0 or l > 18.0:
		return
	var nb := int(l / 0.55)
	var col: Color = BULB_COLS[rng.randi() % BULB_COLS.size()]
	var multi := rng.randf() < 0.4
	for k in nb + 1:
		var t := float(k) / nb
		var p := a.lerp(b, t) - Vector3(0, sin(t * PI) * l * 0.06, 0)
		var c: Color = BULB_COLS[k % BULB_COLS.size()] if multi else col
		_add("bulb", Transform3D(Basis.IDENTITY, p), Color(c.r, c.g, c.b, 1))
	# the wire
	var mid := (a + b) * 0.5 - Vector3(0, l * 0.04, 0)
	var dir := b - a
	_add("wire", Transform3D((Basis.looking_at(dir.normalized(), Vector3.UP) * Basis.from_scale(Vector3(1, 1, l))), mid))


## Gravel paths linking neighbouring camps on the same side (where the way is clear of the road).
func _paths_between_camps() -> void:
	for k in _camps.size() - 1:
		var a: Array = _camps[k]
		var b: Array = _camps[k + 1]
		if float(a[1]) != float(b[1]):
			continue
		var pa: Vector3 = a[0]
		var pb: Vector3 = b[0]
		var l := pa.distance_to(pb)
		if l > 260.0:
			continue
		var pts: Array = []
		var ok := true
		var nseg := maxi(int(l / 12.0), 2)
		for j in nseg + 1:
			var q := pa.lerp(pb, float(j) / nseg)
			# bend away from the road where the straight line would come too close
			var tries := 0
			while terrain.distance_to_road(q.x, q.z) < float(track.wall_base) + 5.0 and tries < 6:
				var pr: Array = track.project(q, int(a[2]))
				var away: Vector3 = track.rights[int(pr[0])] * signf(float(pr[2]) if absf(float(pr[2])) > 0.01 else float(a[1]))
				q += away * 4.0
				tries += 1
			if tries >= 6 or terrain.normal_at(q.x, q.z).y < 0.85:
				ok = false
				break
			pts.append(q)
		if ok:
			scenery.add_path(pts, 2.2, "gravel")
			_stats["paths"] = int(_stats.get("paths", 0)) + 1


# ---------------------------------------------------------------------------
# Spectators
# ---------------------------------------------------------------------------
func _spectators(i: int, side: float) -> void:
	var rows := rng.randi_range(1, 3)
	var width := rng.randf_range(4.0, 14.0)
	var base: Vector3 = scenery._roadside(i, 2.6, side)
	if track.samples[i].y > 0.15:
		return        # on the expressway: nobody stands up there
	if track.in_wall_gap(i, side) or track.in_wall_gap((i + 4) % track.sample_count(), side) \
			or track.in_wall_gap((i - 4 + track.sample_count()) % track.sample_count(), side):
		return        # an opening in the barrier (side street, driveway): nobody stands in it
	if not _ok(base, 1.5) or not scenery.free_at(base, 1.0, 1.5):
		return
	var along: Vector3 = track.tangents[i]
	var out: Vector3 = track.rights[i] * side
	var road: Vector3 = track.samples[i]
	var count := 0
	for r in rows:
		var x := -width * 0.5
		while x < width * 0.5:
			if rng.randf() < 0.85:
				var p: Vector3 = base + along * (x + rng.randf_range(-0.2, 0.2)) + out * (r * 0.95 + rng.randf_range(-0.15, 0.15))
				if _ok(p, 1.2):
					_person(p, road + along * rng.randf_range(-15.0, 15.0))
					count += 1
			x += rng.randf_range(0.65, 1.0)
	if count > 0:
		if rng.randf() < 0.35:
			var cp := base + out * (rows * 0.95 + 1.2) + along * rng.randf_range(-width * 0.5, width * 0.5)
			if _ok(cp, 2.0):
				_add("cooler", Transform3D(Basis(Vector3.UP, rng.randf() * TAU), _ground(cp)), Color(TENT_COLS[rng.randi() % TENT_COLS.size()]))
		scenery.occupy(base + out * rows * 0.5, maxf(width * 0.5, 2.0))
		_stats["spectators"] = int(_stats.get("spectators", 0)) + count


# ---------------------------------------------------------------------------
# Meshes
# ---------------------------------------------------------------------------
func _make_meshes() -> void:
	var pm := Props.material()
	var w := Color(1, 1, 1, 1)
	# dome tent (tinted), dark door and a darker groundsheet edge
	var st := MeshKit.new_st()
	Props._vlathe(st, [Vector2(1.15, 0.0), Vector2(1.1, 0.3), Vector2(0.92, 0.68), Vector2(0.58, 0.95), Vector2(0.0, 1.08)], 10, w)
	Props._b(st, Vector3(0, 0.33, -1.06), Vector3(0.55, 0.62, 0.05), Color(0.12, 0.12, 0.13), Vector3(-0.2, 0, 0))
	_meshes["tent"] = [MeshKit.commit(st, pm), 260.0, true]
	# caravan: white body, dark windows, a stripe, wheels, drawbar
	st = MeshKit.new_st()
	var body := Color(0.95, 0.95, 0.93)
	Props._b(st, Vector3(0, 1.45, 0), Vector3(2.2, 2.2, 5.4), body)
	Props._b(st, Vector3(0, 2.6, 0.2), Vector3(2.0, 0.12, 4.6), Color(0.85, 0.85, 0.84))
	Props._b(st, Vector3(0, 1.0, 0), Vector3(2.22, 0.18, 5.42), Color(0.55, 0.15, 0.1))
	for sx: float in [-1.0, 1.0]:
		Props._b(st, Vector3(sx * 1.11, 1.85, -1.2), Vector3(0.03, 0.6, 1.3), Color(0.08, 0.09, 0.1, 0.6))
		Props._b(st, Vector3(sx * 1.11, 1.85, 1.4), Vector3(0.03, 0.6, 0.9), Color(0.08, 0.09, 0.1, 0.6))
		Props._cyl(st, Vector3(sx * 1.05, 0.33, 0.3), Vector3(sx * 1.25, 0.33, 0.3), 0.33, 0.33, Color(0.06, 0.06, 0.06), 10)
	Props._b(st, Vector3(0, 1.85, -2.71), Vector3(1.4, 0.5, 0.03), Color(0.08, 0.09, 0.1, 0.6))
	Props._b(st, Vector3(1.11, 1.3, 0.3), Vector3(0.03, 1.8, 0.65), Color(0.8, 0.8, 0.78))
	Props._b(st, Vector3(0, 0.45, -3.3), Vector3(0.12, 0.1, 1.4), Color(0.2, 0.2, 0.22, 0.5))
	Props._b(st, Vector3(0, 0.25, -3.9), Vector3(0.08, 0.5, 0.08), Color(0.2, 0.2, 0.22, 0.5))
	_meshes["caravan"] = [MeshKit.commit(st, pm), 420.0, true]
	# awning on the caravan's door side (tinted)
	st = MeshKit.new_st()
	Props._b(st, Vector3(2.3, 2.35, 0.3), Vector3(2.4, 0.06, 3.6), w, Vector3(0, 0, -0.12))
	for sz: float in [-1.7, 2.3]:
		Props._b(st, Vector3(3.45, 1.1, sz), Vector3(0.05, 2.2, 0.05), Color(0.7, 0.7, 0.7, 0.5))
	_meshes["awning"] = [MeshKit.commit(st, pm), 260.0, true]
	# pavilion: 3 x 3 m pop-up with a pyramid roof (tinted)
	st = MeshKit.new_st()
	for sx: float in [-1.45, 1.45]:
		for sz: float in [-1.45, 1.45]:
			Props._b(st, Vector3(sx, 1.1, sz), Vector3(0.05, 2.2, 0.05), Color(0.85, 0.85, 0.85, 0.5))
	Props._vlathe(st, [Vector2(2.12, 2.0), Vector2(2.12, 2.2), Vector2(0.0, 2.85)], 4, w)
	_meshes["gazebo"] = [MeshKit.commit(st, pm), 300.0, true]
	# beer table set: table and two benches
	st = MeshKit.new_st()
	Props._b(st, Vector3(0, 0.76, 0), Vector3(2.2, 0.04, 0.5), Props.WOOD)
	Props._b(st, Vector3(0, 0.45, 0.55), Vector3(2.2, 0.04, 0.25), Props.WOOD)
	Props._b(st, Vector3(0, 0.45, -0.55), Vector3(2.2, 0.04, 0.25), Props.WOOD)
	for sx: float in [-0.9, 0.9]:
		Props._b(st, Vector3(sx, 0.38, 0), Vector3(0.04, 0.76, 0.45), Color(0.3, 0.3, 0.32, 0.5))
		Props._b(st, Vector3(sx, 0.22, 0.55), Vector3(0.04, 0.45, 0.2), Color(0.3, 0.3, 0.32, 0.5))
		Props._b(st, Vector3(sx, 0.22, -0.55), Vector3(0.04, 0.45, 0.2), Color(0.3, 0.3, 0.32, 0.5))
	for k in 5:
		Props._cyl(st, Vector3(-0.8 + k * 0.4, 0.78, 0.05 * (k % 2)), Vector3(-0.8 + k * 0.4, 0.98, 0.05 * (k % 2)), 0.035, 0.035,
			Color(0.35, 0.2, 0.05) if k % 2 == 0 else Color(0.1, 0.3, 0.1), 6)
	_meshes["beer_set"] = [MeshKit.commit(st, pm), 160.0, true]
	# campfire: ring of stones and crossed logs
	st = MeshKit.new_st()
	for k in 9:
		var a := TAU * k / 9.0
		Props._b(st, Vector3(cos(a) * 0.65, 0.1, sin(a) * 0.65), Vector3(0.26, 0.2, 0.22), Color(0.45, 0.44, 0.42), Vector3(0, a, 0.2))
	for k in 3:
		var a := TAU * k / 3.0
		Props._b(st, Vector3(cos(a) * 0.15, 0.12, sin(a) * 0.15), Vector3(0.12, 0.12, 0.8), Color(0.25, 0.16, 0.08), Vector3(0.35, a, 0))
	_meshes["campfire"] = [MeshKit.commit(st, pm), 200.0, false]
	# flames: three crossed cones (flickering shader)
	st = MeshKit.new_st()
	for k in 3:
		var a := TAU * k / 3.0
		var o := Vector3(cos(a) * 0.12, 0, sin(a) * 0.12)
		Props._cyl(st, o, o + Vector3(0, 0.85 - k * 0.12, 0), 0.22 - k * 0.03, 0.0, Color(1, 1, 1), 6)
	var fm := ShaderMaterial.new()
	fm.shader = Shader.new()
	fm.shader.code = FIRE_SHADER
	_meshes["fire"] = [MeshKit.commit(st, fm), 320.0, false]
	# kettle grill on three legs
	st = MeshKit.new_st()
	Props._vlathe(st, [Vector2(0.0, 0.55), Vector2(0.3, 0.6), Vector2(0.33, 0.8)], 12, Color(0.08, 0.08, 0.09, 0.7))
	for k in 3:
		var a := TAU * k / 3.0
		Props._b(st, Vector3(cos(a) * 0.22, 0.3, sin(a) * 0.22), Vector3(0.04, 0.62, 0.04), Color(0.3, 0.3, 0.32, 0.5), Vector3(sin(a) * 0.2, 0, -cos(a) * 0.2))
	Props._b(st, Vector3(0, 0.84, 0), Vector3(0.6, 0.02, 0.6), Color(0.6, 0.6, 0.62, 0.4))
	for k in 4:
		Props._b(st, Vector3(-0.18 + k * 0.12, 0.87, 0.05 * (k % 2)), Vector3(0.09, 0.04, 0.2), Color(0.45, 0.2, 0.1))
	_meshes["grill"] = [MeshKit.commit(st, pm), 160.0, true]
	# folding chair (tinted cloth)
	st = MeshKit.new_st()
	Props._b(st, Vector3(0, 0.42, 0), Vector3(0.5, 0.05, 0.45), w)
	Props._b(st, Vector3(0, 0.72, 0.24), Vector3(0.5, 0.6, 0.04), w, Vector3(-0.2, 0, 0))
	for sx: float in [-0.24, 0.24]:
		for sz: float in [-0.2, 0.2]:
			Props._b(st, Vector3(sx, 0.21, sz), Vector3(0.03, 0.42, 0.03), Color(0.3, 0.3, 0.3, 0.5))
	_meshes["chair"] = [MeshKit.commit(st, pm), 120.0, false]
	# portable toilet
	st = MeshKit.new_st()
	Props._b(st, Vector3(0, 1.15, 0), Vector3(1.1, 2.3, 1.1), Color(0.15, 0.35, 0.75))
	Props._b(st, Vector3(0, 2.36, 0), Vector3(1.15, 0.12, 1.15), Color(0.92, 0.92, 0.9))
	Props._b(st, Vector3(0, 1.05, -0.56), Vector3(0.75, 1.9, 0.03), Color(0.12, 0.3, 0.65))
	_meshes["toilet"] = [MeshKit.commit(st, pm), 300.0, true]
	# cool box (tinted)
	st = MeshKit.new_st()
	Props._b(st, Vector3(0, 0.2, 0), Vector3(0.6, 0.4, 0.4), w)
	Props._b(st, Vector3(0, 0.42, 0), Vector3(0.62, 0.06, 0.42), Color(0.95, 0.95, 0.95))
	_meshes["cooler"] = [MeshKit.commit(st, pm), 100.0, false]
	# string-light bulbs and their wire (wire: unit length along -Z)
	st = MeshKit.new_st()
	Props._b(st, Vector3.ZERO, Vector3(0.09, 0.12, 0.09), w)
	_bulb_mat = ShaderMaterial.new()
	_bulb_mat.shader = Shader.new()
	_bulb_mat.shader.code = BULB_SHADER
	_meshes["bulb"] = [MeshKit.commit(st, _bulb_mat), 260.0, false]
	st = MeshKit.new_st()
	Props._b(st, Vector3.ZERO, Vector3(0.015, 0.015, 1.0), Color(0.05, 0.05, 0.05))
	_meshes["wire"] = [MeshKit.commit(st, pm), 120.0, false]
	_meshes["person"] = [Crowd.person_mesh(), 300.0, true]

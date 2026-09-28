extends Node3D
## Party mode: the minigame venues on the map. plan() finds a free, fairly level spot for every venue
## beside the track (before the scenery is placed, so no trees grow there) and levels the ground;
## build() puts up the venues – raised stages the cars are teleported onto when a minigame starts.
## Every venue has its own local frame: x across, z along (start at -z, finish at +z), y = stage top.

const TexKit = preload("res://scripts/util/tex_kit.gd")
const MeshKit = preload("res://scripts/util/mesh_kit.gd")
const Colliders = preload("res://scripts/util/colliders.gd")

## id, half width (x), half length (z), how far the stage stands above the highest ground point
const VENUES := [
	["rlgl", 20.0, 96.0, 0.5],
	["parkour", 22.0, 118.0, 3.0],
	["koth", 30.0, 30.0, 2.5],
	["donut", 24.0, 24.0, 0.5],
]
const KOTH_R := 27.0
const DONUT_R := 21.0
## Offroad parkour: pits (no floor) as [z0, z1] and the planks / bridges crossing them as [x, width]
const PK_PITS := [[-24.0, -14.0], [58.0, 84.0]]
const PK_CHECKPOINTS := [-104.0, -50.0, -8.0, 50.0, 90.0]
const RLGL_START := -82.0
const RLGL_FINISH := 80.0
const PK_FINISH := 108.0

var track: Node3D
var terrain: Node3D
var sites := {}              # id -> {"xf": Transform3D (y = stage top), "hw", "hl"}
var koth_zone: MeshInstance3D
var rlgl_lamps: Array = []   # [red material, green material]
var _labels: Array = []


## Chooses and levels the venue spots. Returns false when the map has no room (party mode then off).
func plan(p_track: Node3D, p_terrain: Node3D) -> bool:
	track = p_track
	terrain = p_terrain
	var ext: Rect2 = terrain.extent().grow(-30.0)
	var clear: float = float(track.wall_base) + 16.0
	var quay_z := float(track.bounds.end.y) + 20.0 if track.track_id == "harbor" else 1e9
	var taken: Array = []    # [Vector2 centre, radius]
	for v in VENUES:
		var id: String = v[0]
		var hw: float = v[1]
		var hl: float = v[2]
		var best := {}
		var best_score := 1e18
		var step := 24.0
		var gx := ext.position.x + hl
		while gx < ext.end.x - hl:
			await Game.load_tick()
			var gz := ext.position.y + hl
			while gz < ext.end.y - hl:
				if terrain.distance_to_road(gx, gz) < clear + hw:
					gz += step
					continue
				for yaw: float in [0.0, PI * 0.5]:
					var b := Basis(Vector3.UP, yaw)
					var score := _fits(Vector3(gx, 0, gz), b, hw, hl, clear, quay_z, taken)
					if score >= 0.0 and score < best_score:
						best_score = score
						best = {"c": Vector3(gx, 0, gz), "b": b}
				gz += step
			gx += step
		if best.is_empty():
			print("PARTY: no room for the %s venue on %s" % [id, track.track_id])
			return false
		var c: Vector3 = best["c"]
		var bb: Basis = best["b"]
		taken.append([Vector2(c.x, c.z), Vector2(hw, hl).length() + 12.0])
		# level the ground along the venue, then the stage stands just above the highest point
		var zz := -hl
		while zz <= hl:
			terrain.flatten(c + bb * Vector3(0, 0, zz), hw + 2.0, 10.0)
			zz += 14.0
		var top := -1e9
		var low := 1e9
		for p in _footprint(c, bb, hw, hl, 6.0):
			var h: float = terrain.height_at(p.x, p.z)
			top = maxf(top, h)
			low = minf(low, h)
		sites[id] = {"xf": Transform3D(bb, Vector3(c.x, top + float(v[3]), c.z)), "hw": hw, "hl": hl, "low": low}
	return true


## Keeps trees, rocks, houses and props off the venues (call before the scenery builds).
func reserve(scenery: Node) -> void:
	for id in sites:
		var s: Dictionary = sites[id]
		var xf: Transform3D = s["xf"]
		var hw: float = s["hw"]
		var hl: float = s["hl"]
		var r := hw + 8.0
		var zz := -hl
		while zz < hl + r * 0.5:
			scenery.occupy(xf * Vector3(0, 0, minf(zz, hl)), r)
			zz += r
		scenery.occupy(xf.origin, 1.0)


## Mean distance to the road (smaller = closer to the track = better), or -1 if it doesn't fit.
func _fits(c: Vector3, b: Basis, hw: float, hl: float, clear: float, quay_z: float, taken: Array) -> float:
	var c2 := Vector2(c.x, c.z)
	var rad := Vector2(hw, hl).length()
	for t in taken:
		if (t[0] as Vector2).distance_to(c2) < float(t[1]) + rad + 6.0:
			return -1.0
	var sum := 0.0
	var n := 0
	var lo := 1e9
	var hi := -1e9
	for p in _footprint(c, b, hw + 4.0, hl + 4.0, 16.0):
		if p.z > quay_z:
			return -1.0
		var d: float = terrain.distance_to_road(p.x, p.z)
		if d < clear:
			return -1.0
		var h: float = terrain.height_at(p.x, p.z)
		lo = minf(lo, h)
		hi = maxf(hi, h)
		if hi - lo > 32.0:
			return -1.0
		sum += d
		n += 1
	# prefer spots near the track and on level ground
	return sum / maxf(n, 1) + (hi - lo) * 6.0


func _footprint(c: Vector3, b: Basis, hw: float, hl: float, step: float) -> Array:
	var out: Array = []
	var nxs := maxi(int(ceil(hw * 2.0 / step)), 1)
	var nzs := maxi(int(ceil(hl * 2.0 / step)), 1)
	for iz in nzs + 1:
		for ix in nxs + 1:
			out.append(c + b * Vector3(-hw + ix * hw * 2.0 / nxs, 0, -hl + iz * hl * 2.0 / nzs))
	return out


# ---------------------------------------------------------------------------
# Venues
# ---------------------------------------------------------------------------
func build() -> void:
	for id in sites:
		var root := Node3D.new()
		root.name = "Venue_" + id
		add_child(root)
		root.global_transform = sites[id]["xf"]
		match id:
			"rlgl":
				_build_rlgl(root)
			"parkour":
				_build_parkour(root)
			"koth":
				_build_koth(root)
			"donut":
				_build_donut(root)


func _mat(c: Color, rough := 0.8, emit := 0.0) -> StandardMaterial3D:
	return TexKit.std(c, rough, 0.0, c, emit)


## Solid block with collision, in venue coordinates.
func _block(root: Node3D, size: Vector3, pos: Vector3, mat: Material, rot := Vector3.ZERO, shadows := true) -> MeshInstance3D:
	var mi := MeshKit.box_node(size, mat, pos, rot)
	if not shadows:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	Colliders.add_box(root, root.global_transform * Transform3D(Basis.from_euler(rot), pos), size)
	return mi


## The stage slab from the top down to the ground (so it never floats on a slope).
func _stage(root: Node3D, id: String, hw: float, z0: float, z1: float, mat: Material) -> void:
	var s: Dictionary = sites[id]
	var depth: float = s["xf"].origin.y - float(s["low"]) + 1.5
	_block(root, Vector3(hw * 2.0, depth, z1 - z0), Vector3(0, -depth * 0.5, (z0 + z1) * 0.5), mat)


func _sign(root: Node3D, text: String, sub: String, pos: Vector3, color: Color, yaw := 0.0) -> void:
	var post_m := _mat(Color(0.12, 0.12, 0.14), 0.6)
	for x: float in [-5.5, 5.5]:
		root.add_child(MeshKit.box_node(Vector3(0.3, 7.0, 0.3), post_m, pos + Basis(Vector3.UP, yaw) * Vector3(x, 3.5, 0)))
	root.add_child(MeshKit.box_node(Vector3(12.5, 2.8, 0.25), _mat(Color(0.06, 0.03, 0.1), 0.5), pos + Vector3(0, 6.2, 0), Vector3(0, yaw, 0)))
	for side: float in [1.0, -1.0]:
		var l := Label3D.new()
		l.text = text
		l.font_size = 150
		l.outline_size = 24
		l.modulate = color
		l.pixel_size = 0.009
		l.position = pos + Basis(Vector3.UP, yaw) * Vector3(0, 6.55, 0.14 * side)
		l.rotation = Vector3(0, yaw + (0.0 if side > 0.0 else PI), 0)
		root.add_child(l)
		var s2 := Label3D.new()
		s2.text = sub
		s2.font_size = 70
		s2.outline_size = 14
		s2.modulate = Color(1, 1, 1, 0.9)
		s2.pixel_size = 0.009
		s2.position = pos + Basis(Vector3.UP, yaw) * Vector3(0, 5.45, 0.14 * side)
		s2.rotation = l.rotation
		root.add_child(s2)


func _line(root: Node3D, z: float, hw: float, a: Color, b: Color) -> void:
	# chequered start / finish line
	var n := int(hw * 2.0 / 1.5)
	for i in n:
		for r in 2:
			var c := a if (i + r) % 2 == 0 else b
			var mi := MeshKit.box_node(Vector3(1.5, 0.02, 0.75), _mat(c, 0.7), Vector3(-hw + 0.75 + i * 1.5, 0.012, z + r * 0.75))
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(mi)


func _rails(root: Node3D, hw: float, z0: float, z1: float, mat: Material) -> void:
	for x: float in [-hw + 0.3, hw - 0.3]:
		_block(root, Vector3(0.6, 1.0, z1 - z0), Vector3(x, 0.5, (z0 + z1) * 0.5), mat)


func _build_rlgl(root: Node3D) -> void:
	var hw: float = sites["rlgl"]["hw"]
	var hl: float = sites["rlgl"]["hl"]
	_stage(root, "rlgl", hw, -hl, hl, _mat(Color(0.2, 0.2, 0.22), 0.85))
	# pink and white lanes
	for i in 6:
		var mi := MeshKit.box_node(Vector3(0.25, 0.02, hl * 2.0 - 8.0), _mat(Color(1.0, 0.35, 0.6), 0.6, 0.4), Vector3(-hw + 4.0 + i * (hw * 2.0 - 8.0) / 5.0, 0.011, 0))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	_rails(root, hw, -hl, hl, _mat(Color(0.9, 0.9, 0.92), 0.5))
	_block(root, Vector3(hw * 2.0, 1.0, 0.6), Vector3(0, 0.5, -hl + 0.3), _mat(Color(0.9, 0.9, 0.92), 0.5))
	_line(root, RLGL_START + 3.5, hw, Color.WHITE, Color(0.1, 0.1, 0.1))
	_line(root, RLGL_FINISH, hw, Color.WHITE, Color(0.1, 0.1, 0.1))
	# the traffic light gantry behind the finish (the "doll")
	var pole_m := _mat(Color(0.1, 0.1, 0.12), 0.5)
	for x: float in [-hw + 2.0, hw - 2.0]:
		_block(root, Vector3(0.6, 11.0, 0.6), Vector3(x, 5.5, hl - 6.0), pole_m)
	root.add_child(MeshKit.box_node(Vector3(hw * 2.0 - 3.0, 0.8, 0.8), pole_m, Vector3(0, 10.6, hl - 6.0)))
	root.add_child(MeshKit.box_node(Vector3(9.0, 4.4, 1.4), _mat(Color(0.05, 0.05, 0.06), 0.4), Vector3(0, 8.0, hl - 6.0)))
	var red := _mat(Color(1.0, 0.1, 0.05), 0.3, 0.0)
	var green := _mat(Color(0.1, 1.0, 0.3), 0.3, 0.0)
	root.add_child(MeshKit.sphere_node(1.5, red, Vector3(-2.3, 8.0, hl - 6.8), Vector3(1, 1, 0.4)))
	root.add_child(MeshKit.sphere_node(1.5, green, Vector3(2.3, 8.0, hl - 6.8), Vector3(1, 1, 0.4)))
	rlgl_lamps = [red, green]
	_sign(root, "ROTES LICHT", "GRÜNES LICHT", Vector3(0, 0, -hl - 6.0), Color(1.0, 0.3, 0.3), PI)
	set_rlgl_light(-1)


## -1 off, 0 red, 1 green
func set_rlgl_light(state: int) -> void:
	if rlgl_lamps.is_empty():
		return
	var red: StandardMaterial3D = rlgl_lamps[0]
	var green: StandardMaterial3D = rlgl_lamps[1]
	red.emission_enabled = true
	green.emission_enabled = true
	red.emission_energy_multiplier = 8.0 if state == 0 else 0.15
	green.emission_energy_multiplier = 8.0 if state == 1 else 0.15


func _build_parkour(root: Node3D) -> void:
	var hw: float = sites["parkour"]["hw"]
	var hl: float = sites["parkour"]["hl"]
	var dirt := _mat(Color(0.42, 0.3, 0.2), 0.95)
	var wood := _mat(Color(0.55, 0.38, 0.2), 0.8)
	var hazard := _mat(Color(1.0, 0.75, 0.05), 0.6, 0.3)
	# the stage in pieces: gaps are the pits
	var edges := [-hl]
	for p in PK_PITS:
		edges.append(p[0])
		edges.append(p[1])
	edges.append(hl)
	for i in range(0, edges.size(), 2):
		_stage(root, "parkour", hw, edges[i], edges[i + 1], dirt)
	_rails(root, hw, -hl, hl, _mat(Color(0.95, 0.4, 0.1), 0.6))
	_block(root, Vector3(hw * 2.0, 1.0, 0.6), Vector3(0, 0.5, -hl + 0.3), wood)
	_line(root, -hl + 6.0, hw, Color.WHITE, Color(0.1, 0.1, 0.1))
	_line(root, PK_FINISH, hw, Color.WHITE, Color(0.1, 0.1, 0.1))
	# 1) slalom through tyre-stack pillars
	var tyre := _mat(Color(0.08, 0.08, 0.09), 0.9)
	for k in 5:
		var x := (-1.0 if k % 2 == 0 else 1.0) * hw * 0.35
		root.add_child(MeshKit.cyl_node(1.4, 1.4, 2.2, tyre, Vector3(x, 1.1, -96.0 + k * 11.0)))
		Colliders.add_box(root, root.global_transform * Transform3D(Basis.IDENTITY, Vector3(x, 1.1, -96.0 + k * 11.0)), Vector3(2.4, 2.2, 2.4))
	# 2) log bumps across the track
	for k in 6:
		var z := -44.0 + k * 3.6
		var log := MeshKit.cyl_node(0.32, 0.32, hw * 2.0 - 1.4, wood, Vector3(0, -0.02, z), Vector3(0, 0, PI * 0.5), 10)
		root.add_child(log)
		Colliders.add_box(root, root.global_transform * Transform3D(Basis.IDENTITY, Vector3(0, 0.12, z)), Vector3(hw * 2.0 - 1.4, 0.34, 0.5))
	# 3) kicker ramp over the first pit, a narrow bridge beside it for the careful
	var pit0: Array = PK_PITS[0]
	var ramp_len := 10.0
	var ramp_h := 2.2
	var ang := atan2(ramp_h, ramp_len)
	var rl := Vector2(ramp_len, ramp_h).length()
	_block(root, Vector3(hw * 1.2, 0.5, rl), Vector3(-hw * 0.3, ramp_h * 0.5 - 0.2, float(pit0[0]) - ramp_len * 0.5), hazard, Vector3(-ang, 0, 0))
	_block(root, Vector3(3.6, 0.5, float(pit0[1]) - float(pit0[0]) + 2.0), Vector3(hw - 4.0, -0.25, (float(pit0[0]) + float(pit0[1])) * 0.5), wood)
	# 4) chicane walls
	for k in 4:
		var side := -1.0 if k % 2 == 0 else 1.0
		_block(root, Vector3(hw * 1.15, 1.2, 0.8), Vector3(side * (hw - hw * 0.575), 0.6, 4.0 + k * 11.0), _mat(Color(0.9, 0.9, 0.92), 0.5))
	# 5) the planks over the long pit
	var pit1: Array = PK_PITS[1]
	var plen := float(pit1[1]) - float(pit1[0]) + 2.0
	var pz := (float(pit1[0]) + float(pit1[1])) * 0.5
	_block(root, Vector3(5.0, 0.5, plen), Vector3(-7.0, -0.25, pz), wood)
	_block(root, Vector3(5.0, 0.5, plen), Vector3(8.0, -0.25, pz), wood)
	# a bump on each plank
	_block(root, Vector3(5.0, 0.6, 3.0), Vector3(-7.0, 0.1, pz), hazard, Vector3(0, 0, 0))
	_block(root, Vector3(5.0, 0.6, 3.0), Vector3(8.0, 0.1, pz + 6.0), hazard)
	# checkpoint arches
	for cz in PK_CHECKPOINTS:
		if cz < -100.0:
			continue
		for x: float in [-hw + 1.0, hw - 1.0]:
			root.add_child(MeshKit.box_node(Vector3(0.4, 5.0, 0.4), hazard, Vector3(x, 2.5, cz)))
		root.add_child(MeshKit.box_node(Vector3(hw * 2.0 - 2.0, 0.4, 0.4), hazard, Vector3(0, 5.0, cz)))
	_sign(root, "OFFROAD-PARKOUR", "Checkpoint-Rennen", Vector3(0, 0, -hl - 6.0), Color(1.0, 0.7, 0.2), PI)


func _build_koth(root: Node3D) -> void:
	var s: Dictionary = sites["koth"]
	var depth: float = s["xf"].origin.y - float(s["low"]) + 1.5
	var cm := CylinderMesh.new()
	cm.top_radius = KOTH_R
	cm.bottom_radius = KOTH_R
	cm.height = depth
	cm.radial_segments = 48
	var mi := MeshKit.mesh_instance(cm, _mat(Color(0.18, 0.12, 0.28), 0.7))
	mi.position = Vector3(0, -depth * 0.5, 0)
	root.add_child(mi)
	var body := StaticBody3D.new()
	body.collision_layer = Colliders.LAYER_WORLD
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = KOTH_R
	shape.height = depth
	cs.shape = shape
	body.add_child(cs)
	body.position = Vector3(0, -depth * 0.5, 0)
	root.add_child(body)
	# glowing edge so you see where the drop is
	var tm := TorusMesh.new()
	tm.inner_radius = KOTH_R - 0.35
	tm.outer_radius = KOTH_R
	tm.rings = 64
	var edge := MeshKit.mesh_instance(tm, _mat(Color(0.7, 0.3, 1.0), 0.4, 3.0), false)
	edge.scale = Vector3(1, 0.3, 1)
	root.add_child(edge)
	# the moving zone
	var zm := CylinderMesh.new()
	zm.top_radius = 6.0
	zm.bottom_radius = 6.0
	zm.height = 3.0
	zm.cap_top = false
	zm.cap_bottom = false
	zm.radial_segments = 40
	var zmat := StandardMaterial3D.new()
	zmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	zmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	zmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	zmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	zmat.albedo_color = Color(1.0, 0.8, 0.1, 0.35)
	koth_zone = MeshKit.mesh_instance(zm, zmat, false)
	koth_zone.position = Vector3(0, 1.5, 0)
	root.add_child(koth_zone)
	var disc := CylinderMesh.new()
	disc.top_radius = 6.0
	disc.bottom_radius = 6.0
	disc.height = 0.02
	disc.radial_segments = 40
	var dm := _mat(Color(1.0, 0.75, 0.1), 0.5, 1.5)
	var dmi := MeshKit.mesh_instance(disc, dm, false)
	dmi.position = Vector3(0, -1.49, 0)
	koth_zone.add_child(dmi)
	_sign(root, "KÖNIG DES HÜGELS", "Halte die Zone!", Vector3(0, -2.5, -KOTH_R - 6.0), Color(1.0, 0.85, 0.2), PI)


func _build_donut(root: Node3D) -> void:
	var hw: float = sites["donut"]["hw"]
	_stage(root, "donut", hw, -hw, hw, _mat(Color(0.14, 0.14, 0.16), 0.8))
	# target rings painted on the pad
	for r: float in [4.0, 9.0, 14.0]:
		var tm := TorusMesh.new()
		tm.inner_radius = r - 0.2
		tm.outer_radius = r
		tm.rings = 48
		var ring := MeshKit.mesh_instance(tm, _mat(Color(1.0, 0.3, 0.7), 0.5, 1.0), false)
		ring.scale = Vector3(1, 0.05, 1)
		ring.position = Vector3(0, 0.01, 0)
		root.add_child(ring)
	# tyre wall around
	var tyre := _mat(Color(0.08, 0.08, 0.09), 0.9)
	var n := 40
	for i in n:
		var a := TAU * i / n
		var p := Vector3(cos(a) * DONUT_R, 0.5, sin(a) * DONUT_R)
		root.add_child(MeshKit.cyl_node(0.55, 0.55, 1.0, tyre, p, Vector3.ZERO, 12))
		Colliders.add_box(root, root.global_transform * Transform3D(Basis(Vector3.UP, -a), p), Vector3(1.1, 1.0, 3.4))
	_sign(root, "DONUT-DUELL", "Dreh dich!", Vector3(0, 0, -hw - 5.0), Color(1.0, 0.4, 0.8), PI)


# ---------------------------------------------------------------------------
# Game helpers (local venue coordinates -> world)
# ---------------------------------------------------------------------------
func xf(id: String) -> Transform3D:
	return sites[id]["xf"]


func to_local_pos(id: String, p: Vector3) -> Vector3:
	return xf(id).affine_inverse() * p


## Start position for grid slot `slot` of `count` cars.
func start_xf(id: String, slot: int, count: int) -> Transform3D:
	var v: Transform3D = xf(id)
	var local: Vector3
	var yaw := 0.0
	match id:
		"rlgl", "parkour":
			var per_row := 6
			var row := slot / per_row
			var in_row := mini(count - row * per_row, per_row)
			var col := slot % per_row
			var z0: float = -float(sites[id]["hl"]) + 14.0
			local = Vector3((col - (in_row - 1) * 0.5) * 5.5, 0.6, z0 - row * 7.0)
		"koth":
			var a := TAU * slot / maxf(count, 1)
			local = Vector3(cos(a), 0, sin(a)) * (KOTH_R - 5.0) + Vector3(0, 0.6, 0)
			yaw = atan2(local.x, local.z)
		"donut":
			var a2 := TAU * slot / maxf(count, 1)
			local = Vector3(cos(a2), 0, sin(a2)) * (6.0 if count > 1 else 0.0) + Vector3(0, 0.6, 0)
			yaw = a2
	# cars look along -z: turn them to face +z (down the course); on the ring they face the centre
	var b := Basis(Vector3.UP, PI) if (id == "rlgl" or id == "parkour") else Basis(Vector3.UP, yaw)
	return Transform3D(v.basis * b, v * local)


## Parkour: respawn at a checkpoint (local z), on the middle of the course.
func checkpoint_xf(z: float) -> Transform3D:
	var v: Transform3D = xf("parkour")
	return Transform3D(v.basis * Basis(Vector3.UP, PI), v * Vector3(0, 0.6, z + 3.0))


## King of the hill: the zone's local centre for step k of a match with this seed.
static func koth_spot(seed_v: int, k: int) -> Vector3:
	if k == 0:
		return Vector3.ZERO
	var r := RandomNumberGenerator.new()
	r.seed = hash([seed_v, k])
	var a := r.randf() * TAU
	var d := r.randf_range(6.0, KOTH_R - 9.0)
	return Vector3(cos(a) * d, 0, sin(a) * d)

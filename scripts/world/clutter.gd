extends RefCounted
## What makes a roadside look used and alive: litter in the gutter and on the verge (cans, bottles,
## paper, bags, cups, bits of tyre), fallen leaves, twigs and pine cones in the forests, clumps of
## grass and wild flowers along the road edge and at the foot of the barriers – dry ones in the
## desert, a few weeds in the city gutters. All small instanced props (details.gd), drawn only close
## by, no shadows.

const Props = preload("res://scripts/world/prop_meshes.gd")

## Emitted in chunks this many times the scenery's (few draw calls); every item fades by its own
## distance (prop_meshes.gd CLUTTER_SHADER).
const CHUNK_FACTOR := 4

## Per map: chance per 2 m of road and side, and the kinds [key, weight].
const RECIPES := {
	"ridge": {"litter": 0.035, "kinds": [["can", 3], ["bottle", 2], ["paper", 2], ["cup", 1], ["bag", 1]],
		"forest": 0.3, "weeds": 0.5, "flowers": 0.25, "dry": 0.1, "wall_weeds": 0.35},
	"gruene_hoelle": {"litter": 0.06, "kinds": [["can", 5], ["cup", 3], ["bottle", 2], ["paper", 2], ["bag", 1], ["tyre_strip", 1]],
		"forest": 0.28, "weeds": 0.45, "flowers": 0.3, "dry": 0.1, "wall_weeds": 0.3},
	"harbor": {"litter": 0.08, "kinds": [["can", 3], ["bottle", 2], ["paper", 3], ["cardboard", 2], ["bag", 2], ["tyre_strip", 1]],
		"forest": 0.0, "weeds": 0.3, "flowers": 0.05, "dry": 0.45, "wall_weeds": 0.4},
	"playground": {"litter": 0.03, "kinds": [["tyre_strip", 4], ["can", 2], ["paper", 1], ["bottle", 1]],
		"forest": 0.0, "weeds": 0.35, "flowers": 0.15, "dry": 0.3, "wall_weeds": 0.2},
	"utah": {"litter": 0.03, "kinds": [["can", 3], ["bottle", 2], ["tyre_strip", 2], ["old_tyre", 1], ["paper", 1]],
		"forest": 0.0, "weeds": 0.35, "flowers": 0.0, "dry": 1.0, "wall_weeds": 0.2},
	"tokyo": {"litter": 0.06, "kinds": [["can", 4], ["bottle", 3], ["paper", 3], ["bag", 2], ["cardboard", 1], ["cup", 1]],
		"forest": 0.0, "weeds": 0.06, "flowers": 0.0, "dry": 0.2, "wall_weeds": 0.0, "city": true},
}

const CAN_TINTS := [Color(0.9, 0.1, 0.1), Color(0.15, 0.3, 0.85), Color(0.15, 0.6, 0.2), Color(0.95, 0.95, 0.95), Color(0.95, 0.75, 0.1), Color(0.2, 0.2, 0.22)]
const RUST := Color(0.6, 0.36, 0.2)

var track
var terrain
var scenery
var details
var rng := RandomNumberGenerator.new()
var stats := {}


func build(p_scenery, id: String) -> void:
	scenery = p_scenery
	track = scenery.track
	terrain = scenery.terrain
	details = scenery.details
	var rc: Dictionary = RECIPES.get(id, RECIPES["ridge"] if not Game.is_desert(id) else RECIPES["utah"])
	if Game.is_desert(id):
		rc = RECIPES["utah"]
	elif Game.is_city(id):
		rc = RECIPES["tokyo"]
	rng.seed = hash(id) + 4242
	for k in Props.CLUTTER:
		details._meshes[k] = [Props.get_mesh(k), Props.CLUTTER_FADE, false, CHUNK_FACTOR]
	for k in Props.WEEDS:
		details._meshes[k] = [Props.get_mesh(k), Props.WEED_FADE, false, CHUNK_FACTOR]
	var city := bool(rc.get("city", false))
	var n: int = track.sample_count()
	var total_w := 0.0
	for e in rc["kinds"]:
		total_w += float(e[1])
	for i in n:
		for side in [-1.0, 1.0]:
			var hw: float = track.hws[i]
			var edge: Vector3 = track.edge_point(i, side * hw)
			var edge_y: float = edge.y + track.ROAD_Y
			# bridges, the playground's crossing pass, the expressway: nothing tumbles off them
			if edge_y - terrain.height_at(edge.x, edge.z) > 0.6 and not city:
				continue
			if rng.randf() < float(rc["litter"]):
				_litter(i, side, hw, rc, total_w, city)
			if rng.randf() < float(rc["weeds"]):
				_weeds(i, side, hw, rc, city)
			if not city and rng.randf() < float(rc["wall_weeds"]):
				_wall_weeds(i, side, hw, rc)
			if rng.randf() < float(rc["forest"]):
				_forest_floor(i, side, hw)


## A point `out` metres from the centre line at sample i: on the asphalt (out < half width), on the
## ramp down from the edge or on the ground beyond it.
func _ground(i: int, side: float, hw: float, out: float) -> Vector3:
	var p: Vector3 = track.edge_point(i, side * out)
	var edge_y: float = track.edge_point(i, side * hw).y + track.ROAD_Y
	if out <= hw:
		p.y = p.y + track.ROAD_Y
		return p
	var g: float = terrain.height_at(p.x, p.z)
	var drop := edge_y - g
	if drop >= track.RAMP_MIN_DROP and drop <= track.RAMP_MAX_DROP:
		g = maxf(g, edge_y - (out - hw) / track.RAMP_SLOPE)
	p.y = g
	return p


func _lying(p: Vector3, scale := 1.0) -> Transform3D:
	var nrm: Vector3 = terrain.normal_at(p.x, p.z) if p.y < terrain.height_at(p.x, p.z) + 0.05 else Vector3.UP
	var b := Basis(Quaternion(Vector3.UP, nrm.normalized())) * Basis(Vector3.UP, rng.randf() * TAU)
	return Transform3D(b.scaled(Vector3.ONE * scale), p + Vector3(0, 0.003, 0))


func _pick(rc: Dictionary, total_w: float) -> String:
	var x := rng.randf() * total_w
	for e in rc["kinds"]:
		x -= float(e[1])
		if x <= 0.0:
			return str(e[0])
	return str(rc["kinds"][0][0])


## Where the verge starts: the road edge, or beyond the kerb where there is one.
func _verge(i: int, hw: float) -> float:
	var n: int = track.sample_count()
	for d in [-2, 0, 2]:
		if track.curb_mask[(i + d + n) % n] != 0:
			return hw + 1.55
	return hw


func _litter(i: int, side: float, hw: float, rc: Dictionary, total_w: float, city: bool) -> void:
	# city: in the gutter by the kerb; elsewhere on the edge of the asphalt or the verge beyond
	var wall: float = track.off_left[i] if side < 0.0 else track.off_right[i]
	var vg := _verge(i, hw)
	var out := hw - rng.randf_range(0.12, 0.5) if city else (vg + rng.randf_range(-0.35, 2.6) if vg == hw else vg + rng.randf_range(0.1, 2.6))
	if not city and wall > hw + 0.5:
		out = minf(out, wall - 0.35)
	var p := _ground(i, side, hw, out)
	var kind := _pick(rc, total_w)
	var tint := Color(1, 1, 1)
	var desert := float(rc.get("dry", 0.0)) >= 1.0
	match kind:
		"can":
			tint = RUST if desert and rng.randf() < 0.6 else CAN_TINTS[rng.randi() % CAN_TINTS.size()]
		"bottle":
			tint = [Color(1, 1, 1), Color(0.55, 0.8, 0.55), Color(0.62, 0.42, 0.22)][rng.randi() % 3]
		"paper":
			tint = [Color(1, 1, 1), Color(0.85, 0.85, 0.82), Color(1.0, 0.85, 0.6), Color(0.7, 0.85, 1.0)][rng.randi() % 4]
		"bag":
			tint = Color(1, 1, 1) if rng.randf() < 0.7 else Color(0.4, 0.45, 0.9)
		"cup":
			tint = Color(1, 1, 1) if rng.randf() < 0.6 else Color(0.95, 0.25, 0.2)
		"cardboard":
			tint = Color(1, 1, 1).darkened(rng.randf_range(0.0, 0.25))
	details.add(kind, _lying(p, rng.randf_range(0.85, 1.15)), tint)
	stats[kind] = int(stats.get(kind, 0)) + 1
	# litter keeps company: another bit close by now and then
	if rng.randf() < 0.3:
		var q := _ground(i, side, hw, out + rng.randf_range(-0.4, 0.4)) + (track.tangents[i] as Vector3) * rng.randf_range(-0.8, 0.8)
		var k2 := _pick(rc, total_w)
		details.add(k2, _lying(q), CAN_TINTS[rng.randi() % CAN_TINTS.size()] if k2 == "can" else Color(1, 1, 1))
		stats[k2] = int(stats.get(k2, 0)) + 1


## Grass tint: a little varied in brightness and warmth.
func _grass_tint(_rc: Dictionary) -> Color:
	return Color(1, 1, 1).lerp(Color(1.25, 1.15, 0.8), rng.randf()).darkened(rng.randf_range(0.0, 0.2))


func _weeds(i: int, side: float, hw: float, rc: Dictionary, city: bool) -> void:
	if city:
		# a weed in the crack between the gutter and the kerb
		var pc := _ground(i, side, hw, hw - 0.06)
		details.add("tuft", Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.4, 0.7)), pc), _grass_tint(rc))
		stats["tuft"] = int(stats.get("tuft", 0)) + 1
		return
	var wall: float = track.off_left[i] if side < 0.0 else track.off_right[i]
	var out := _verge(i, hw) + rng.randf_range(0.05, 0.9)
	if wall > hw + 0.5:
		if out > wall - 0.25:
			return
	var along: Vector3 = track.tangents[i]
	var dry := rng.randf() < float(rc.get("dry", 0.0))
	for c in rng.randi_range(1, 3):
		var p := _ground(i, side, hw, out + rng.randf_range(-0.05, 0.35)) + along * rng.randf_range(-0.7, 0.7)
		var kind := "dry_tuft" if dry else ("flower_tuft" if rng.randf() < float(rc.get("flowers", 0.0)) else "tuft")
		var s := rng.randf_range(0.7, 1.35)
		details.add(kind, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.8, 1.2), s)), p), _grass_tint(rc))
		stats[kind] = int(stats.get(kind, 0)) + 1


## Grass growing up against the foot of the barrier / wall.
func _wall_weeds(i: int, side: float, hw: float, rc: Dictionary) -> void:
	var wall: float = track.off_left[i] if side < 0.0 else track.off_right[i]
	if wall < _verge(i, hw) + 0.4 or wall > hw + 9.0:
		return
	var p := _ground(i, side, hw, wall - rng.randf_range(0.1, 0.3))
	var s := rng.randf_range(0.8, 1.4)
	var kind := "dry_tuft" if rng.randf() < float(rc.get("dry", 0.0)) else "tuft"
	details.add(kind, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s, s)), p), _grass_tint(rc))
	stats[kind] = int(stats.get(kind, 0)) + 1


## Forest floor beyond the verge: leaves blown together, a broken branch, pine cones.
func _forest_floor(i: int, side: float, hw: float) -> void:
	var wall: float = track.off_left[i] if side < 0.0 else track.off_right[i]
	var out := _verge(i, hw) + rng.randf_range(1.5, 7.0)
	if wall > hw + 0.5 and out > wall - 0.3:
		# behind the barrier
		out = wall + rng.randf_range(0.6, 4.0)
	var p := _ground(i, side, hw, out)
	if not scenery.free_at(p, 0.4, 0.0):
		return
	var r := rng.randf()
	var kind := "leaves" if r < 0.55 else ("twigs" if r < 0.8 else "pine_cones")
	var tint := Color(1, 1, 1).darkened(rng.randf_range(0.0, 0.3)) if kind != "leaves" else Color(1, 1, 1).lerp(Color(0.8, 0.9, 0.6), rng.randf() * 0.5)
	details.add(kind, _lying(p, rng.randf_range(0.8, 1.5)), tint)
	stats[kind] = int(stats.get(kind, 0)) + 1


func stats_text() -> String:
	var parts: Array = []
	for k in stats:
		parts.append("%s %d" % [k, stats[k]])
	return ", ".join(parts)

extends Node3D
## A cassette to find on a map: floats over the track like the party coins, but purple – a glowing
## tape (shell, label, window with turning reels) that spins slowly and bobs. Driving through it puts the
## tape into the garage's cabinet (Radio.find_tape) – gone once found.

const MAP_TAPES := {
	"ridge": "night_run", "harbor": "harbor_tape", "tokyo": "tokyo_tape", "utah": "desert_tape",
	"gruene_hoelle": "hell_mix",
}
const PURPLE := Color(0.62, 0.22, 1.0)
const REACH := 2.6

var world      # world.gd
var tape_id := ""
var _spin: Node3D
var _reels: Array[Node3D] = []
var _shell_mat: StandardMaterial3D
var _taken := -1.0             # > 0: the pick-up's pop (seconds since)
var _light: OmniLight3D
var _t := 0.0


## The game's own tapes (res://assets/audio/Kassette<N>) and where they lie: Kassette 1 on Utah, Kassette 2 in
## a side street of Neo Tokyo, the next ones on the other maps by turn (Tokyo: side streets, else the road's edge).
const GAME_TAPE_MAPS := ["utah", "tokyo", "ridge", "harbor", "gruene_hoelle", "tokyo"]

var city_spot := false        # in a side street of the city (not on the race route)
var spot_seed := 0


## The map's tapes still out there (pick-up nodes, maybe none).
static func for_world(w) -> Array:
	var out: Array = []
	var have: Array = Game.settings.get("cassettes", [])
	var track_id := str(w.track.track_id)
	var id: String = MAP_TAPES.get(track_id, "")
	if id != "" and not have.has(id):
		out.append(_make(w, id, false, 0))
	var k := 0
	for gid in Radio.game_tapes():
		var n: int = int(Radio.game_tapes()[gid].get("num", 0))
		if n <= 0 or have.has(gid):
			continue
		var m: String = GAME_TAPE_MAPS[(n - 1) % GAME_TAPE_MAPS.size()]
		if m == track_id:
			out.append(_make(w, gid, Game.is_city(track_id), n))
			k += 1
	return out


static func _make(w, id: String, city: bool, n: int) -> Node3D:
	var p = load("res://scripts/world/cassette_pickup.gd").new()
	p.world = w
	p.tape_id = id
	p.city_spot = city
	p.spot_seed = n
	p.name = "CassettePickup_" + id
	return p


func _ready() -> void:
	_build()
	if world == null or world.track == null:
		return
	var tr = world.track
	if city_spot and _place_in_city():
		return
	# always the same spot on a map: a bit beyond a third of the lap, near the edge of the road
	var n: int = tr.sample_count()
	var r := RandomNumberGenerator.new()
	r.seed = hash(tape_id)
	var idx := int(n * r.randf_range(0.35, 0.6)) % n
	var lat := (1.0 if r.randf() < 0.5 else -1.0) * maxf(float(tr.half_w) - 2.2, 0.0)
	var xf: Transform3D = tr.transform_at(idx, lat, 1.4)
	global_position = xf.origin


## On a street of the city off the race route (60–250 m from it) – a different one for each tape, the
## same every time. The ground found with a ray from above.
func _place_in_city() -> bool:
	var sc = world.get("scenery")
	if sc == null or sc.get("city") == null or sc.city.get("net") == null:
		return false
	var streets: Array = sc.city.net.streets
	var tr = world.track
	var cands: Array = []
	for s in streets:
		var pts: PackedVector2Array = s["pts"]
		for j in range(0, pts.size() - 1):
			var q := pts[j].lerp(pts[j + 1], 0.5)
			var d := 1e9
			for i in range(0, tr.sample_count(), 4):
				var sp: Vector3 = tr.samples[i]
				d = minf(d, Vector2(sp.x, sp.z).distance_to(q))
			if d > 60.0 and d < 250.0:
				cands.append(q)
	if cands.is_empty():
		return false
	var r := RandomNumberGenerator.new()
	r.seed = hash(["city_tape", tape_id])
	# (the tapes of one map well apart: each takes its own share of the candidates)
	var share := cands.size() / 2
	var i0 := (spot_seed % 2) * share
	var q: Vector2 = cands[i0 + r.randi() % maxi(share, 1)] if share > 0 else cands[r.randi() % cands.size()]
	var y := 0.0
	var space: PhysicsDirectSpaceState3D = (world as Node3D).get_world_3d().direct_space_state
	var hit: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(q.x, 400.0, q.y), Vector3(q.x, -100.0, q.y)))
	if not hit.is_empty():
		y = (hit["position"] as Vector3).y
	global_position = Vector3(q.x, y + 1.4, q.y)
	return true


func _build() -> void:
	_spin = Node3D.new()
	add_child(_spin)
	_shell_mat = _glow(Color(PURPLE, 0.7), PURPLE, 1.7)
	var label_mat := _glow(Color(0.86, 0.74, 1.0, 1.0), Color(0.7, 0.5, 1.0), 0.9)
	var dark := _glow(Color(0.16, 0.05, 0.3, 1.0), Color(0.25, 0.08, 0.5), 0.6)
	var hub_mat := _glow(Color(0.97, 0.94, 1.0, 1.0), Color(0.9, 0.8, 1.0), 1.2)
	# the shell (1.7 x 1.08 m – about the coin's size) with its bevelled head at the bottom
	_box(Vector3(1.7, 1.08, 0.2), Vector3.ZERO, _shell_mat)
	_box(Vector3(1.08, 0.2, 0.26), Vector3(0, -0.46, 0), _shell_mat)
	for side: float in [1.0, -1.0]:
		var z := 0.11 * side
		# the label round the window, the window, the two reels in it
		_box(Vector3(1.42, 0.58, 0.012), Vector3(0, 0.14, z), label_mat)
		_box(Vector3(0.86, 0.24, 0.016), Vector3(0, 0.1, z + 0.004 * side), dark)
		_box(Vector3(1.42, 0.05, 0.016), Vector3(0, 0.34, z + 0.004 * side), _glow(Color(1.0, 0.35, 0.8, 1.0), Color(1.0, 0.3, 0.7), 1.4))
		for rx: float in [-0.3, 0.3]:
			var reel := Node3D.new()
			reel.position = Vector3(rx, 0.1, z + 0.012 * side)
			_spin.add_child(reel)
			_reels.append(reel)
			var cm := CylinderMesh.new()
			cm.top_radius = 0.095
			cm.bottom_radius = 0.095
			cm.height = 0.012
			cm.radial_segments = 20
			var hub := MeshInstance3D.new()
			hub.mesh = cm
			hub.material_override = hub_mat
			hub.rotation = Vector3(PI * 0.5, 0, 0)
			hub.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			reel.add_child(hub)
			# the hub's teeth: so the turning shows
			for k in 3:
				var tooth := MeshInstance3D.new()
				var bm := BoxMesh.new()
				bm.size = Vector3(0.03, 0.15, 0.016)
				tooth.mesh = bm
				tooth.material_override = dark
				tooth.position = Vector3(0, 0, 0.004 * side)
				tooth.rotation = Vector3(0, 0, TAU * k / 3.0)
				tooth.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				reel.add_child(tooth)
		# the screw holes and the head's two capstan holes
		for hp: Vector2 in [Vector2(-0.76, 0.46), Vector2(0.76, 0.46), Vector2(-0.76, -0.46), Vector2(0.76, -0.46), Vector2(-0.3, -0.46), Vector2(0.3, -0.46)]:
			_box(Vector3(0.06, 0.06, 0.012), Vector3(hp.x, hp.y, z + (0.03 if absf(hp.x) < 0.5 else 0.0) * side), dark)
		var l := Label3D.new()
		l.text = "♫"
		l.font_size = 64
		l.pixel_size = 0.006
		l.modulate = Color(0.35, 0.1, 0.6, 0.95)
		l.outline_size = 0
		l.position = Vector3(-0.56, 0.26, z + 0.012 * side)
		l.rotation = Vector3(0, 0.0 if side > 0.0 else PI, 0)
		l.no_depth_test = false
		_spin.add_child(l)
	_light = OmniLight3D.new()
	_light.light_color = PURPLE
	_light.light_energy = 1.4
	_light.omni_range = 5.0
	_light.shadow_enabled = false
	add_child(_light)


func _glow(albedo: Color, emission: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	# (only the shell see-through: the label, window and reels on it solid, else they sort wrongly)
	if albedo.a < 0.8:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = albedo
	m.metallic = 0.6
	m.roughness = 0.25
	m.emission_enabled = true
	m.emission = emission
	m.emission_energy_multiplier = energy
	m.rim_enabled = true
	m.rim = 1.0
	return m


func _box(size: Vector3, pos: Vector3, mat) -> MeshInstance3D:
	var bm := BoxMesh.new()
	bm.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_spin.add_child(mi)
	return mi


func _process(delta: float) -> void:
	_t += delta
	_shell_mat.emission_energy_multiplier = 1.4 + 0.6 * sin(_t * 3.0)
	_spin.rotation.y = fmod(_t * 1.6, TAU)
	for r in _reels:
		r.rotation.z -= delta * 4.0
	if _taken >= 0.0:
		# picked up: it jumps, grows and fades out
		_taken += delta
		var k := clampf(_taken / 0.6, 0.0, 1.0)
		_spin.position.y = 0.25 + k * 2.2
		_spin.scale = Vector3.ONE * (1.0 + k * 0.6)
		_shell_mat.albedo_color.a = 0.7 * (1.0 - k)
		_light.light_energy = 1.4 * (1.0 - k)
		_spin.rotation.y = fmod(_t * (1.6 + k * 14.0), TAU)
		if k >= 1.0:
			queue_free()
		return
	_spin.position.y = 0.25 * sin(_t * 2.0)
	var car = world.local_car if world else null
	if car and is_instance_valid(car):
		var d: Vector3 = car.global_position - global_position
		if Vector2(d.x, d.z).length() < REACH and absf(d.y) < 3.0:
			_collect()


func _collect() -> void:
	_taken = 0.0
	if Radio.find_tape(tape_id):
		Radio.click_sound(true)
		if world and world.hud:
			world.hud.show_message("KASSETTE GEFUNDEN", Game.t("„%s“ – liegt jetzt im Schrank in der Garage") % Radio.tape_title(tape_id), PURPLE.lightened(0.3), 3.5)

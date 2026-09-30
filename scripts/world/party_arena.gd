extends Node3D
## Party minigame "Arena-Shootout": the cars shoot at each other inside the walled arena stretch.
## Three hits and you are out for a moment (the shooter scores), then you come back with a short
## shield. Power-up coins pop up: triple shot or rapid fire for a few seconds. Alone (offline, or
## the only one in an online lobby) you fight against bots.
## Online every machine simulates its own shots; the shooter decides hits on the others and tells
## the victim ("hit"), the victim reports its knock-out ("down") so the shooter can count it.
## Messages go through the host (party.gd relays everything with t = "ar").

const MAX_HP := 3
const SHOT_SPEED := 90.0
const SHOT_LIFE := 1.2
const HIT_R := 1.6
const COOLDOWN := 0.42
const RAPID_COOLDOWN := 0.12
const TRIPLE_SPREAD := 0.11
const POWER_TIME := 10.0
const PICKUP_EVERY := 6.0
const PICKUP_MAX := 3
const RESPAWN_TIME := 1.8
const SHIELD_TIME := 2.2
const START_SHIELD := 6.0
const BOT_NAMES := ["Bot Blitz", "Bot Kurbel", "Bot Turbo"]
const LAYER_WORLD := 1
const Car = preload("res://scripts/car/car.gd")

var party: Node
var world: Node3D
var sites: Node3D
var seed_v := 0
var me := 1
var fighters := {}       # id -> state (see _add_fighter); negative ids are bots
var shots: Array = []
var pickups := {}        # k -> {"node", "kind"}
var clock := 0.0
var feed := ""           # last event line for the HUD
var feed_t := 0.0
var frozen := false
var _next_pu := 0
var _mats := {}
var _shot_mesh: SphereMesh
var _rng := RandomNumberGenerator.new()


func setup(p_party: Node, p_world: Node3D, p_sites: Node3D, p_seed: int, ids: Array, my_id: int) -> void:
	party = p_party
	world = p_world
	sites = p_sites
	seed_v = p_seed
	me = my_id
	_rng.seed = hash([p_seed, my_id])
	_shot_mesh = SphereMesh.new()
	_shot_mesh.radius = 0.22
	_shot_mesh.height = 0.44
	_shot_mesh.radial_segments = 10
	_shot_mesh.rings = 5
	for kind in ["normal", "rapid", "triple"]:
		var c: Color = {"normal": Color(1.0, 0.25, 0.1), "rapid": Color(0.2, 0.6, 1.0), "triple": Color(1.0, 0.7, 0.1)}[kind]
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = c
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = 6.0
		_mats[kind] = m
	for id in ids:
		if world.cars.has(id) and is_instance_valid(world.cars[id]):
			_add_fighter(int(id), world.cars[id], false)
	# alone: three bots join
	if ids.size() <= 1:
		for b in BOT_NAMES.size():
			_spawn_bot(-(b + 1), b)
	# everybody is shielded through the countdown and the first seconds
	for id in fighters:
		fighters[id]["shield"] = START_SHIELD


func _add_fighter(id: int, car: Node, bot: bool) -> void:
	fighters[id] = {"car": car, "hp": MAX_HP, "kills": 0, "hits": 0, "cool": 0.0, "power": "", "power_t": 0.0,
		"dead_t": 0.0, "shield": SHIELD_TIME, "bot": bot, "stuck_t": 0.0, "slow_t": 0.0, "think": 0.0,
		"target": 0, "aim_err": 0.0, "shield_node": _shield_node(car)}


func _spawn_bot(id: int, b: int) -> void:
	var car := Car.new()
	var car_ids: Array = Game.CARS.keys()
	car.car_id = str(car_ids[(b + 1) % car_ids.size()])
	car.paint = Game.get_paint(str(Game.PAINTS[(b * 2 + 1) % Game.PAINTS.size()]["id"]))
	car.player_name = BOT_NAMES[b]
	car.is_bot = true
	car.input_enabled = false
	car.track = world.track
	car.skidmarks = world.skidmarks
	car.transmission = "auto"
	car.name = "Bot_%d" % b
	car.ai_fn = _bot_ai.bind(id)
	world.add_child(car)
	var tag := Label3D.new()
	tag.text = car.player_name
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.position = Vector3(0, 2.1, 0)
	tag.font_size = 48
	tag.outline_size = 12
	tag.modulate = Color(1.0, 0.55, 0.45)
	car.add_child(tag)
	car.place(sites.arena_spawn(b + 1 + (4 if b % 2 == 1 else 0)))
	car.arena_kill_y = float(world.track.kill_y)
	car.respawn_fn = func() -> Transform3D: return _spawn_xf()
	_add_fighter(id, car, true)


func is_bot(id: int) -> bool:
	return fighters.has(id) and bool(fighters[id]["bot"])


func bot_name(id: int) -> String:
	if fighters.has(id):
		return str((fighters[id]["car"] as Node).get("player_name"))
	return "Bot"


func score(id: int) -> float:
	if not fighters.has(id):
		return 0.0
	return float(fighters[id]["kills"]) + minf(float(fighters[id]["hits"]), 99.0) * 0.01


func bot_ids() -> Array:
	var out: Array = []
	for id in fighters:
		if bool(fighters[id]["bot"]):
			out.append(id)
	return out


## A free spawn spot: the one furthest from the other cars.
func _spawn_xf() -> Transform3D:
	var best := Transform3D.IDENTITY
	var best_d := -1.0
	for s in 8:
		var xf: Transform3D = sites.arena_spawn(s)
		var d := 1e9
		for id in fighters:
			var c = fighters[id]["car"]
			if is_instance_valid(c):
				d = minf(d, (c as Node3D).global_position.distance_to(xf.origin))
		d += _rng.randf_range(0.0, 6.0)
		if d > best_d:
			best_d = d
			best = xf
	return best


func cleanup() -> void:
	for id in fighters:
		var f: Dictionary = fighters[id]
		if bool(f["bot"]) and is_instance_valid(f["car"]):
			(f["car"] as Node).queue_free()
		elif is_instance_valid(f["shield_node"]):
			(f["shield_node"] as Node).queue_free()
	fighters.clear()


# ---------------------------------------------------------------------------
# Per physics step (called by party.gd while the minigame runs)
# ---------------------------------------------------------------------------
func step(delta: float) -> void:
	clock += delta
	feed_t -= delta
	_spawn_pickups()
	for id in fighters:
		var f: Dictionary = fighters[id]
		var car = f["car"]
		if not is_instance_valid(car):
			continue
		f["cool"] = maxf(float(f["cool"]) - delta, 0.0)
		f["shield"] = maxf(float(f["shield"]) - delta, 0.0)
		if float(f["power_t"]) > 0.0:
			f["power_t"] = float(f["power_t"]) - delta
			if float(f["power_t"]) <= 0.0:
				f["power"] = ""
		var sh: Node3D = f["shield_node"]
		if is_instance_valid(sh):
			sh.visible = float(f["shield"]) > 0.0 and float(f["dead_t"]) <= 0.0
		if int(id) != me and not bool(f["bot"]):
			f["dead_t"] = maxf(float(f["dead_t"]) - delta, 0.0)
			continue
		# local fighters: knocked out -> wait, then back in at a free spot
		if float(f["dead_t"]) > 0.0:
			f["dead_t"] = float(f["dead_t"]) - delta
			if float(f["dead_t"]) <= 0.0:
				f["hp"] = MAX_HP
				f["shield"] = SHIELD_TIME
				(car as Car).place(_spawn_xf())
				if int(id) == me:
					(car as Car).controls_locked = false
			continue
		if frozen:
			continue
		_take_pickups(int(id), f)
		if int(id) == me:
			if Input.is_action_pressed("fire") and float(f["cool"]) <= 0.0:
				fire(int(id))
		else:
			_bot_think(int(id), f, delta)
	_step_shots(delta)


func fire(id: int) -> void:
	var f: Dictionary = fighters[id]
	var car: Car = f["car"]
	var kind: String = f["power"] if str(f["power"]) != "" else "normal"
	f["cool"] = RAPID_COOLDOWN if kind == "rapid" else COOLDOWN
	if bool(f["bot"]):
		f["cool"] = float(f["cool"]) * 1.8 + 0.1
	var xf := car.global_transform
	var fwd := -xf.basis.z
	fwd.y = clampf(fwd.y, -0.08, 0.08)
	fwd = fwd.normalized()
	var origin := xf.origin + fwd * 2.7 + Vector3.UP * 0.75
	var dirs: Array = [fwd]
	if kind == "triple":
		dirs = [fwd.rotated(Vector3.UP, TRIPLE_SPREAD), fwd, fwd.rotated(Vector3.UP, -TRIPLE_SPREAD)]
	var base_v := car.linear_velocity
	base_v.y = 0.0
	for d in dirs:
		_add_shot(origin, (d as Vector3) * SHOT_SPEED + base_v, id, kind, true)
	if id == me and world.online:
		Net.party_to_host({"t": "ar", "k": "shot", "o": origin, "d": dirs, "v": base_v, "kind": kind})


func _add_shot(origin: Vector3, vel: Vector3, owner: int, kind: String, live: bool) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _shot_mesh
	mi.material_override = _mats.get(kind, _mats["normal"])
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	# a stretched glowing tracer along the flight direction
	mi.global_transform = Transform3D(Basis.looking_at(vel.normalized(), Vector3.UP).scaled(Vector3(1, 1, 5.0)), origin)
	shots.append({"node": mi, "pos": origin, "vel": vel, "life": SHOT_LIFE, "owner": owner, "kind": kind, "live": live})


func _step_shots(delta: float) -> void:
	var space := get_world_3d().direct_space_state
	var keep: Array = []
	for s in shots:
		var p0: Vector3 = s["pos"]
		var p1: Vector3 = p0 + (s["vel"] as Vector3) * delta
		s["life"] = float(s["life"]) - delta
		var done := float(s["life"]) <= 0.0
		var q := PhysicsRayQueryParameters3D.create(p0, p1, LAYER_WORLD)
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			p1 = hit["position"]
			_spark(p1, str(s["kind"]))
			done = true
		if bool(s["live"]) and not done:
			var victim := _shot_victim(p0, p1, int(s["owner"]))
			if victim != 0:
				_spark(p1, str(s["kind"]))
				_on_hit(victim, int(s["owner"]), (s["vel"] as Vector3).normalized())
				done = true
		if done:
			(s["node"] as Node).queue_free()
			continue
		s["pos"] = p1
		(s["node"] as Node3D).global_position = p1
		keep.append(s)
	shots = keep


func _shot_victim(p0: Vector3, p1: Vector3, owner: int) -> int:
	for id in fighters:
		if int(id) == owner:
			continue
		var f: Dictionary = fighters[id]
		var car = f["car"]
		if not is_instance_valid(car) or float(f["dead_t"]) > 0.0:
			continue
		var c: Vector3 = (car as Node3D).global_position + Vector3.UP * 0.55
		var seg := p1 - p0
		var t := clampf((c - p0).dot(seg) / maxf(seg.length_squared(), 1e-6), 0.0, 1.0)
		if (p0 + seg * t).distance_to(c) < HIT_R:
			return int(id)
	return 0


## A live shot (ours or our bots') hit `victim`.
func _on_hit(victim: int, by: int, dir: Vector3) -> void:
	if fighters.has(by):
		fighters[by]["hits"] = int(fighters[by]["hits"]) + 1
	if victim == me or is_bot(victim):
		_damage(victim, by, dir)
	elif world.online:
		Net.party_to_host({"t": "ar", "k": "hit", "v": victim, "by": by, "dir": dir})


## Damage on a fighter this machine owns (the local car or a bot).
func _damage(victim: int, by: int, dir: Vector3) -> void:
	var f: Dictionary = fighters[victim]
	if float(f["shield"]) > 0.0 or float(f["dead_t"]) > 0.0 or frozen:
		return
	var car: Car = f["car"]
	car.apply_central_impulse((dir * 0.9 + Vector3.UP * 0.25) * car.mass * 2.2)
	f["hp"] = int(f["hp"]) - 1
	if victim == me:
		world.hud.show_message("TREFFER!", "%d / %d" % [maxi(int(f["hp"]), 0), MAX_HP], _bad(), 0.8)
	if int(f["hp"]) > 0:
		return
	# knocked out
	f["dead_t"] = RESPAWN_TIME
	_boom(car.global_position)
	if victim == me:
		car.controls_locked = true
		world.hud.show_message("ABGESCHOSSEN", "von %s" % _name(by), _bad(), 1.6)
	if fighters.has(by) and (by == me or is_bot(by)):
		_credit(by, victim)
	elif world.online:
		Net.party_to_host({"t": "ar", "k": "down", "v": victim, "by": by})
	_feed("%s  ✖  %s" % [_name(by), _name(victim)])


func _credit(by: int, victim: int) -> void:
	fighters[by]["kills"] = int(fighters[by]["kills"]) + 1
	if by == me:
		world.hud.show_message("ABSCHUSS!", _name(victim), Color(1.0, 0.8, 0.2), 1.4)


func on_msg(from: int, msg: Dictionary) -> void:
	if from == me:
		return
	match str(msg.get("k", "")):
		"shot":
			var o: Vector3 = msg.get("o", Vector3.ZERO)
			var v: Vector3 = msg.get("v", Vector3.ZERO)
			for d in msg.get("d", []):
				_add_shot(o, (d as Vector3) * SHOT_SPEED + v, from, str(msg.get("kind", "normal")), false)
		"hit":
			if int(msg.get("v", 0)) == me and fighters.has(me):
				_damage(me, from, msg.get("dir", Vector3.FORWARD))
		"down":
			var by := int(msg.get("by", 0))
			if by == me and fighters.has(me):
				_credit(me, from)
			_feed("%s  ✖  %s" % [_name(by), _name(int(msg.get("v", from)))])
			if fighters.has(from):
				fighters[from]["dead_t"] = RESPAWN_TIME
				fighters[from]["shield"] = RESPAWN_TIME + SHIELD_TIME
				_boom((fighters[from]["car"] as Node3D).global_position)
		"pu":
			_remove_pickup(int(msg.get("i", -1)))


func _name(id: int) -> String:
	if fighters.has(id) and is_instance_valid(fighters[id]["car"]):
		return str((fighters[id]["car"] as Node).get("player_name"))
	return "?"


func _feed(text: String) -> void:
	feed = text
	feed_t = 3.0


static func _bad() -> Color:
	return Color(1.0, 0.3, 0.25)


# ---------------------------------------------------------------------------
# Power-up coins
# ---------------------------------------------------------------------------
func _spawn_pickups() -> void:
	# coin k appears at k * PICKUP_EVERY + 3 s, at the same spot on every machine
	while clock >= _next_pu * PICKUP_EVERY + 3.0:
		var k := _next_pu
		_next_pu += 1
		if pickups.size() >= PICKUP_MAX:
			continue
		var kind := "triple" if k % 2 == 0 else "rapid"
		var node := _pickup_node(kind)
		add_child(node)
		node.global_transform = sites.arena_pickup(seed_v, k)
		pickups[k] = {"node": node, "kind": kind}
	var t := clock
	for k in pickups:
		var n: Node3D = pickups[k]["node"]
		var spin: Node3D = n.get_node("Spin")
		spin.rotation.y = fmod(t * 2.5 + k, TAU)
		spin.position.y = 0.2 * sin(t * 2.2 + k)


func _pickup_node(kind: String) -> Node3D:
	var col := Color(1.0, 0.6, 0.1) if kind == "triple" else Color(0.2, 0.6, 1.0)
	var root := Node3D.new()
	var spin := Node3D.new()
	spin.name = "Spin"
	root.add_child(spin)
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.metallic = 0.6
	m.roughness = 0.3
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = 1.8
	var disc := CylinderMesh.new()
	disc.top_radius = 0.9
	disc.bottom_radius = 0.9
	disc.height = 0.18
	disc.radial_segments = 32
	var mi := MeshInstance3D.new()
	mi.mesh = disc
	mi.material_override = m
	mi.rotation = Vector3(PI * 0.5, 0, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	spin.add_child(mi)
	for side: float in [1.0, -1.0]:
		var l := Label3D.new()
		l.text = "3×" if kind == "triple" else "⚡"
		l.font_size = 110
		l.pixel_size = 0.008
		l.outline_size = 16
		l.modulate = Color(1, 1, 1)
		l.position = Vector3(0, 0, 0.11 * side)
		l.rotation = Vector3(0, 0.0 if side > 0.0 else PI, 0)
		spin.add_child(l)
	return root


func _take_pickups(id: int, f: Dictionary) -> void:
	var p: Vector3 = (f["car"] as Node3D).global_position
	for k in pickups.keys():
		var n: Node3D = pickups[k]["node"]
		var d := n.global_position - p
		if Vector2(d.x, d.z).length() < 2.6 and absf(d.y) < 3.0:
			f["power"] = pickups[k]["kind"]
			f["power_t"] = POWER_TIME
			if id == me:
				world.hud.show_message("DREIFACH-SCHUSS!" if f["power"] == "triple" else "SCHNELLFEUER!", "%d s" % int(POWER_TIME), Color(0.4, 0.8, 1.0), 1.2)
			_remove_pickup(k)
			if world.online:
				Net.party_to_host({"t": "ar", "k": "pu", "i": k})


func _remove_pickup(k: int) -> void:
	if pickups.has(k):
		(pickups[k]["node"] as Node).queue_free()
		pickups.erase(k)


# ---------------------------------------------------------------------------
# Bots
# ---------------------------------------------------------------------------
func _bot_think(id: int, f: Dictionary, delta: float) -> void:
	var car: Car = f["car"]
	f["think"] = float(f["think"]) - delta
	if float(f["think"]) <= 0.0:
		f["think"] = _rng.randf_range(0.4, 0.8)
		f["aim_err"] = _rng.randf_range(-0.07, 0.07)
		# nearest living rival
		var best := 0
		var best_d := 1e9
		for oid in fighters:
			if int(oid) == id or float(fighters[oid]["dead_t"]) > 0.0 or not is_instance_valid(fighters[oid]["car"]):
				continue
			var d := car.global_position.distance_to((fighters[oid]["car"] as Node3D).global_position)
			if int(oid) == me:
				d *= 0.8    # the player is a bit more interesting than the other bots
			if d < best_d:
				best_d = d
				best = int(oid)
		f["target"] = best
	# stuck against something: back out for a moment
	if car.speed < 1.2 and car.throttle > 0.3 and float(f["stuck_t"]) <= 0.0:
		f["slow_t"] = float(f["slow_t"]) + delta
		if float(f["slow_t"]) > 1.2:
			f["stuck_t"] = _rng.randf_range(0.9, 1.5)
			f["slow_t"] = 0.0
	else:
		f["slow_t"] = 0.0
	f["stuck_t"] = maxf(float(f["stuck_t"]) - delta, 0.0)
	# shoot when the target is in front, near enough and in sight
	var tid := int(f["target"])
	if tid != 0 and fighters.has(tid) and float(f["cool"]) <= 0.0:
		var tp: Vector3 = (fighters[tid]["car"] as Node3D).global_position
		var to := tp - car.global_position
		var fwd := -car.global_transform.basis.z
		if to.length() < 55.0 and absf(Vector2(fwd.x, fwd.z).angle_to(Vector2(to.x, to.z))) < 0.12:
			var q := PhysicsRayQueryParameters3D.create(car.global_position + Vector3.UP * 0.8, tp + Vector3.UP * 0.8, LAYER_WORLD)
			if get_world_3d().direct_space_state.intersect_ray(q).is_empty() and _rng.randf() < 0.5:
				fire(id)


## [throttle, brake, steer, handbrake] for bot `id` (called by its car every physics step).
func _bot_ai(id: int) -> Array:
	if not fighters.has(id):
		return [0.0, 0.0, 0.0, true]
	var f: Dictionary = fighters[id]
	var car: Car = f["car"]
	if frozen or float(f["dead_t"]) > 0.0 or party.state != "play":
		return [0.0, 0.0, 0.0, true]
	var pos := car.global_position
	var fwd := -car.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	# goal: a power-up nearby when it has none, else lead the target a little
	var goal := pos + fwd * 10.0
	var tid := int(f["target"])
	if tid != 0 and fighters.has(tid) and is_instance_valid(fighters[tid]["car"]):
		var tc: Node3D = fighters[tid]["car"]
		var tv: Vector3 = (tc as RigidBody3D).linear_velocity
		goal = tc.global_position + tv * clampf(pos.distance_to(tc.global_position) / SHOT_SPEED, 0.0, 0.6)
	if str(f["power"]) == "":
		for k in pickups:
			var pp: Vector3 = (pickups[k]["node"] as Node3D).global_position
			if pp.distance_to(pos) < 18.0:
				goal = pp
				break
	var to := goal - pos
	to.y = 0.0
	var ang := fwd.signed_angle_to(to.normalized(), Vector3.UP) + float(f["aim_err"])
	var steer := clampf(-ang * 2.2, -1.0, 1.0)
	var thr := 0.8 if absf(ang) < 1.0 else 0.5
	if to.length() < 9.0:
		thr = 0.35
	# walls and blocks ahead: steer to the side with more room
	var space := get_world_3d().direct_space_state
	var eye := pos + Vector3.UP * 0.6
	var ahead := space.intersect_ray(PhysicsRayQueryParameters3D.create(eye, eye + fwd * maxf(7.0, car.speed * 0.7), LAYER_WORLD))
	if not ahead.is_empty():
		var l := space.intersect_ray(PhysicsRayQueryParameters3D.create(eye, eye + fwd.rotated(Vector3.UP, 0.7) * 8.0, LAYER_WORLD))
		var r := space.intersect_ray(PhysicsRayQueryParameters3D.create(eye, eye + fwd.rotated(Vector3.UP, -0.7) * 8.0, LAYER_WORLD))
		steer = 1.0 if l.size() > 0 and r.is_empty() else (-1.0 if r.size() > 0 and l.is_empty() else (1.0 if steer >= 0.0 else -1.0))
		thr = minf(thr, 0.45)
	if float(f["stuck_t"]) > 0.0:
		return [0.0, 1.0, -steer, false]
	return [thr, 0.0, steer, false]


# ---------------------------------------------------------------------------
# Effects
# ---------------------------------------------------------------------------
func _shield_node(car: Node) -> Node3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = Color(0.3, 0.7, 1.0, 0.25)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	var s := SphereMesh.new()
	s.radius = 2.8
	s.height = 3.2
	var mi := MeshInstance3D.new()
	mi.mesh = s
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(0, 0.6, 0)
	mi.visible = false
	car.add_child(mi)
	return mi


func _spark(p: Vector3, kind: String) -> void:
	_flash(p, _mats.get(kind, _mats["normal"]), 0.6, 0.18)


func _boom(p: Vector3) -> void:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = Color(1.0, 0.5, 0.15, 0.8)
	_flash(p + Vector3.UP * 0.8, m, 3.5, 0.5)


func _flash(p: Vector3, mat: Material, size: float, time: float) -> void:
	var s := SphereMesh.new()
	s.radius = 0.5
	s.height = 1.0
	s.radial_segments = 12
	s.rings = 6
	var mi := MeshInstance3D.new()
	mi.mesh = s
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = p
	mi.scale = Vector3.ONE * 0.2
	var tw := create_tween()
	tw.tween_property(mi, "scale", Vector3.ONE * size, time).set_ease(Tween.EASE_OUT)
	tw.tween_callback(mi.queue_free)

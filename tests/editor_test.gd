extends Node
## World editor: reshape the ground, place objects, move and delete a tree, draw a road, add water,
## save – then race on the saved map and check everything is there.
## Run: godot --headless --path . res://tests/editor_test.tscn

const World = preload("res://scripts/world/world.gd")
const MapData = preload("res://scripts/editor/map_data.gd")

const PATH := "user://maps/_editor_test.dmap"


func holder_road(ed) -> Node:
	for c in ed.holder.get_children():
		if c.has_meta("road"):
			return c
	return null


func _ready() -> void:
	Game.persist = false
	var ok := true
	var world := World.new()
	var track := "ridge"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--track="):
			track = a.substr(8)
	world.setup({"track": track, "mode": "editor", "laps": 1, "time_of_day": "day", "weather": "dry",
		"day_cycle": 0, "weather_seed": 3, "online": false, "traffic": 0})
	add_child(world)
	if not world.is_loaded:
		await world.loaded
	var ed = world.editor
	var t = world.terrain
	# a spot well away from the road
	var car_p: Vector3 = world.local_car.global_position
	var hill := Vector3.ZERO
	for a in 64:
		var p := car_p + Vector3(cos(a * 0.4), 0, sin(a * 0.4)) * (60.0 + a * 3.0)
		if t._dist_raw(p.x, p.z) > 60.0 and t.inside(p.x, p.z):
			hill = Vector3(p.x, t.height_at(p.x, p.z), p.z)
			break
	print("EDITOR: hill spot ", hill)
	var h0: float = t.height_at(hill.x, hill.z)
	# raise the ground for a second
	ed.tool = "raise"
	ed.brush_r = 20.0
	ed.brush_s = 8.0
	ed._stroke = true
	ed._stroke_old = {}
	for i in 60:
		ed._brush(hill, 1.0 / 60.0)
	ed._release()
	var h1: float = t.height_at(hill.x, hill.z)
	print("EDITOR: raised %.2f -> %.2f" % [h0, h1])
	ok = ok and h1 > h0 + 5.0
	# physics follows
	await get_tree().physics_frame
	var q := PhysicsRayQueryParameters3D.create(Vector3(hill.x, 500, hill.z), Vector3(hill.x, -500, hill.z), 1)
	var hit: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(q)
	print("EDITOR: collision at %.2f" % float(hit.get("position", Vector3(0, -999, 0)).y))
	ok = ok and not hit.is_empty() and absf(hit["position"].y - h1) < 0.5
	# place a container next to it
	ed.place_asset = "block:container"
	ed._ghost_rot = 0.5
	var obj_p := hill + Vector3(25, 0, 0)
	obj_p.y = t.height_at(obj_p.x, obj_p.z)
	ed._place(obj_p)
	# a tree: move one, delete another
	var keys: Array = ed._spots.keys()
	print("EDITOR: %d scenery spots" % keys.size())
	ok = ok and keys.size() > 100
	var k_move: int = keys[keys.size() / 3]
	var k_del: int = keys[keys.size() / 2]
	var del_orig: String = ed._spots[k_del]["orig"]
	var from: Transform3D = ed._spot_xf(k_move)
	var ed_orig: String = ed._spots[k_move]["orig"]
	for l in ed._spots[k_move]["list"]:
		for r in world.scenery._ranged:
			if r[0].multimesh == l[0]:
				print("EDITOR: moved spot part ", r[0].name, " idx ", l[1], " base ", l[2], " count ", l[0].instance_count, " xf ", l[0].get_instance_transform(l[1]))
	ed._select({"kind": "spot", "id": k_move})
	ed._edit_all(func(x: Transform3D) -> Transform3D: return Transform3D(x.basis.scaled(Vector3.ONE * 2.0), x.origin + Vector3(7, 0, 0)))
	var moved_to: Vector3 = from.origin + Vector3(7, 0, 0)
	ed._select({"kind": "spot", "id": k_del})
	ed._delete()
	# copy a tree and the container, paste them elsewhere: two more placed objects
	ed._select({"kind": "spot", "id": keys[keys.size() / 4]})
	for c in ed.holder.get_children():
		if c.has_meta("asset"):
			ed._toggle({"kind": "node", "node": c})
	ed._copy()
	print("EDITOR: copied %d (selection %d)" % [ed._clip.size(), ed._sel.size()])
	ok = ok and ed._clip.size() == 2
	var paste_at := hill + Vector3(-20, 0, -20)
	ed._mouse = ed.cam.unproject_position(paste_at)
	# a road and water
	ed.road_w = 12.0
	ed.road_flatten = true
	ed._road_pts = [hill + Vector3(-40, 0, 40), hill + Vector3(0, 0, 60), hill + Vector3(40, 0, 40)]
	ed._finish_road()
	var line = load("res://scripts/editor/road_builder.gd").centre_line(world, ed._pts_v3(ed.map.roads[0]["pts"]))
	var worst := 0.0
	var rb = holder_road(ed)
	for i in range(0, line.size(), 4):
		var p: Vector3 = line[i]
		var q2 := PhysicsRayQueryParameters3D.create(Vector3(p.x, 500, p.z), Vector3(p.x, -500, p.z), 1)
		var h2: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(q2)
		var gy: float = t.height_at(p.x, p.z)
		worst = maxf(worst, gy - float(h2.get("position", Vector3.ZERO).y))
		if i % 12 == 0:
			print("EDITOR: road at %s: ground %.2f, ray hits %s at %.2f" % [p, gy, h2.get("collider"), float(h2.get("position", Vector3.ZERO).y)])
	print("EDITOR: ground above the road surface by up to %.2f m" % worst)
	ed._add_water(hill + Vector3(-50, 0, -30))
	ed._focus = hill
	ed._update_cam()
	ed._mouse = ed.cam.unproject_position(hill + Vector3(-20, 0, -20))
	ed._paste()
	ed.map.map_name = "Editor-Test"
	ed.map_path = PATH
	ed._save_copy()
	print("EDITOR: saved %s (%d objects, %d roads, %d water, %d heights, %d edits)" % [PATH, ed.map.objects.size(), ed.map.roads.size(), ed.map.water.size(), ed.map.heights.size(), ed.map.edits.size()])
	ok = ok and FileAccess.file_exists(PATH)
	world.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	# race on it
	var w2 := World.new()
	w2.setup({"track": track, "map": PATH, "mode": "free", "laps": 1, "time_of_day": "day", "weather": "dry",
		"day_cycle": 0, "weather_seed": 3, "online": false, "traffic": 0})
	add_child(w2)
	if not w2.is_loaded:
		await w2.loaded
	var h2: float = w2.terrain.height_at(hill.x, hill.z)
	var mc: Node3D = w2.map_content
	var n_obj := 0
	var n_road := 0
	var n_water := 0
	for c in mc.get_children():
		n_obj += 1 if c.has_meta("asset") else 0
		n_road += 1 if c.has_meta("road") else 0
		n_water += 1 if c.has_meta("water") else 0
	# the moved tree at its new spot, the deleted one gone
	var found_orig := false
	var found_moved := false
	var found_deleted := false
	for r in w2.scenery._ranged:
		var mm: MultiMesh = r[0].multimesh
		var mxf: Transform3D = r[0].global_transform
		for i in mm.instance_count:
			var lx := mm.get_instance_transform(i)
			if absf(lx.basis.determinant()) < 1e-6:
				continue
			var p: Vector3 = mxf * lx.origin
			if p.distance_to(from.origin) < 0.3:
				found_orig = true
			if p.distance_to(moved_to) < 0.3:
				found_moved = true
			if MapData.spot_key(p) == del_orig:
				found_deleted = true
	print("EDITOR: tree moved from %s to %s, original spot still taken %s, edit %s" % [from.origin, moved_to, found_orig, w2.custom_map.edits.get(ed_orig)])
	print("EDITOR: map height %.2f (edited %.2f), %d objects, %d roads, %d water, moved tree %s, deleted tree still there %s" % [h2, h1, n_obj, n_road, n_water, found_moved, found_deleted])
	ok = ok and absf(h2 - h1) < 0.6 and n_obj == 3 and n_road == 1 and n_water == 1 and found_moved and not found_deleted
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	print("EDITOR TEST: %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)

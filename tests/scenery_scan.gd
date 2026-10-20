extends Node
## Looks for scenery placed wrong on every map: things standing in the air (a gap under their
## middle), things sunk out of sight, and things standing on the driving line.
## Needs a renderer (instance data): xvfb-run godot --rendering-driver opengl3 --path .
## res://tests/scenery_scan.tscn [-- utah,ridge]

const World = preload("res://scripts/world/world.gd")
## kinds that stand on the ground (by the chunk label / node name prefix); others (lamp heads,
## banners, birds, signs on poles …) may well be up in the air
const GROUND := ["Trees_hi", "Trees_mid", "Oak", "Bush", "Shrub", "Fern", "Rock", "Stone", "Desert_", "Prop_", "Crowd", "People",
	"Tent", "Camp", "Litter", "Weed", "Tuft", "Flower", "Cactus", "Palm", "Hoodoo", "Boulder"]
## up on posts / stacked / on sills by design
const AIRBORNE := ["Prop_bill", "Prop_sign", "Prop_hay_bale", "Prop_pot_", "Prop_banner"]
const MAX_PER_SET := 4000


func _ready() -> void:
	Game.persist = false
	Game.first_boot = false
	var tracks: Array = ["ridge", "harbor", "playground", "tokyo", "utah", "gruene_hoelle"]
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		tracks = args[0].split(",")
	for tid in tracks:
		var world := World.new()
		world.setup({"track": tid, "mode": "free", "laps": 1, "time_of_day": "day", "weather": "dry",
			"day_cycle": 0, "weather_seed": 3, "online": false, "traffic": 0})
		add_child(world)
		if not world.is_loaded:
			await world.loaded
		for k in 4:
			await get_tree().physics_frame
		var space := world.get_world_3d().direct_space_state
		var tr = world.track
		var floating := {}
		var sunk := {}
		var on_road := {}
		var checked := 0
		for gi in world.find_children("*", "GeometryInstance3D", true, false):
			if not (gi as GeometryInstance3D).is_visible_in_tree():
				continue
			var label := str(gi.get_meta("label", gi.name))
			var ground := false
			for g in GROUND:
				if label.begins_with(g):
					ground = true
					break
			for a in AIRBORNE:
				if label.begins_with(a):
					ground = false
			if not ground:
				continue
			var items: Array = []     # [world AABB]
			if gi is MultiMeshInstance3D:
				var mm: MultiMesh = (gi as MultiMeshInstance3D).multimesh
				if mm == null or mm.mesh == null:
					continue
				var mb := mm.mesh.get_aabb()
				var step := maxi(1, mm.instance_count / MAX_PER_SET)
				for i in range(0, mm.instance_count, step):
					var xf: Transform3D = (gi as Node3D).global_transform * mm.get_instance_transform(i)
					if absf(xf.basis.determinant()) < 1e-9:
						continue
					items.append(xf * mb)
			elif gi is MeshInstance3D and (gi as MeshInstance3D).mesh:
				items.append((gi as Node3D).global_transform * (gi as MeshInstance3D).mesh.get_aabb())
			for b: AABB in items:
				checked += 1
				var c := b.get_center()
				var q := PhysicsRayQueryParameters3D.create(Vector3(c.x, b.position.y + 0.05, c.z), Vector3(c.x, b.position.y - 60.0, c.z), 1)
				var h := space.intersect_ray(q)
				# the terrain (its collision is only built near the car) or a deck / slab above it
				var gy: float = float(world.terrain.height_at(c.x, c.z))
				if not h.is_empty() and float(h["position"].y) > gy - 0.5:
					gy = maxf(gy, float(h["position"].y))
				var gap := b.position.y - gy
				if gap > 0.35:
					_note(floating, label, c, gap)
				if b.end.y < gy - 0.02:
					_note(sunk, label, c, gy - b.end.y)
				var pr: Array = tr.project(c, -1)
				var idx: int = pr[0]
				if absf(float(pr[2])) < float(tr.hws[idx]) - 0.3 and b.position.y < tr.samples[idx].y + 2.0 and not tr.blank:
					_note(on_road, label, c, absf(float(pr[2])))
		print("== %s: %d ground objects checked" % [tid, checked])
		for pair in [["FLOATING", floating], ["SUNK", sunk], ["ON ROAD", on_road]]:
			var d: Dictionary = pair[1]
			for label in d:
				var e: Array = d[label]
				print("  %s %s x%d e.g. %s" % [pair[0], label, e[0], e[1]])
		world.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
	print("SCENERY SCAN DONE")
	get_tree().quit()


func _note(d: Dictionary, label: String, c: Vector3, v: float) -> void:
	var key := label.rstrip("0123456789@").trim_suffix("_")
	if not d.has(key):
		d[key] = [0, []]
	d[key][0] += 1
	if (d[key][1] as Array).size() < 3:
		d[key][1].append("%s (%.2f)" % [c.snapped(Vector3.ONE * 0.1), v])

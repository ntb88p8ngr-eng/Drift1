extends Node
## What the GPU gets per frame, by kind of object: at a few spots round the lap, every drawable node
## within its view range is counted – triangles (mesh x instances), draw calls (node x surfaces),
## and the share drawn again into the sun's shadow map. Needs a renderer (mesh data):
## xvfb-run godot --rendering-driver opengl3 --path . res://tests/render_budget.tscn [-- ridge,utah]

const World = preload("res://scripts/world/world.gd")
const SHADOW_DIST := 150.0      # roughly the sun shadow's reach


func _ready() -> void:
	Game.persist = false
	Game.first_boot = false
	var tracks: Array = ["ridge", "harbor", "playground", "tokyo", "utah", "gruene_hoelle"]
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		tracks = args[0].split(",")
	var tri_cache := {}
	for tid in tracks:
		var world := World.new()
		world.setup({"track": tid, "mode": "free", "laps": 1, "time_of_day": "day", "weather": "dry",
			"day_cycle": 0, "weather_seed": 3, "online": false, "traffic": 2})
		add_child(world)
		if not world.is_loaded:
			await world.loaded
		var tr = world.track
		var n: int = tr.sample_count()
		var by := {}      # label -> [tris, draws, shadow tris]
		var spots := 4
		var gis := world.find_children("*", "GeometryInstance3D", true, false)
		for s in spots:
			var i := int(float(s) / spots * n)
			var cam_pos: Vector3 = tr.samples[i] + Vector3(0, 2.0, 0) - tr.tangents[i] * 6.0
			for g in gis:
				var gi := g as GeometryInstance3D
				if not gi.is_visible_in_tree():
					continue
				var mesh: Mesh = null
				var count := 1
				if gi is MultiMeshInstance3D:
					var mm := (gi as MultiMeshInstance3D).multimesh
					if mm == null or mm.mesh == null:
						continue
					mesh = mm.mesh
					count = mm.visible_instance_count if mm.visible_instance_count >= 0 else mm.instance_count
				elif gi is MeshInstance3D:
					mesh = (gi as MeshInstance3D).mesh
				if mesh == null or count == 0:
					continue
				var aabb := gi.global_transform * gi.get_aabb()
				var d := cam_pos.distance_to(aabb.get_center())
				if gi.visibility_range_end > 0.0 and d > gi.visibility_range_end:
					continue
				if d < gi.visibility_range_begin:
					continue
				var key := mesh.get_instance_id()
				if not tri_cache.has(key):
					var t := 0
					for si in mesh.get_surface_count():
						var arr := mesh.surface_get_arrays(si)
						var idx = arr[Mesh.ARRAY_INDEX]
						t += (idx.size() if idx != null and idx.size() > 0 else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
					tri_cache[key] = [t, mesh.get_surface_count()]
				var tris: int = tri_cache[key][0] * count
				var draws: int = tri_cache[key][1]
				var label := str(gi.get_meta("label", gi.name)).rstrip("0123456789@").trim_suffix("_")
				if not by.has(label):
					by[label] = [0, 0, 0]
				by[label][0] += tris
				by[label][1] += draws
				if gi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and d < SHADOW_DIST:
					by[label][2] += tris
		var rows: Array = []
		var tot := [0, 0, 0]
		for k in by:
			rows.append([k] + by[k])
			for j in 3:
				tot[j] += by[k][j]
		rows.sort_custom(func(a, b): return a[1] + a[3] > b[1] + b[3])
		print("== %s: per frame (mean of %d spots): %.2fM tris + %.2fM in the sun shadow, %d draw calls" % [tid, spots,
			tot[0] / spots / 1e6, tot[2] / spots / 1e6, tot[1] / spots])
		for r in rows.slice(0, 16):
			print("   %-28s %7.0fk tris  %7.0fk shadow  %5d draws" % [r[0], r[1] / spots / 1000.0, r[3] / spots / 1000.0, r[2] / spots])
		world.queue_free()
		for f in 3:
			await get_tree().process_frame
	print("RENDER BUDGET DONE")
	get_tree().quit()

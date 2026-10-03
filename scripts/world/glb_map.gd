extends Node3D
## A map that is an imported model (track def "glb", e.g. Red Mesa – two GLB halves in shared world
## coordinates): the model is drawn as it is and made solid – ground, road, rocks, buildings, tyre
## walls and barrels get trimesh collision; thin overlays (road paint), grass tufts and water don't.

const Colliders = preload("res://scripts/util/colliders.gd")

## mesh name prefixes that stay without collision
const NOT_SOLID := ["paint_", "drygrass", "water", "cactus_lite"]

var stats := {}


func build(track) -> void:
	var t0 := Time.get_ticks_msec()
	for path in track.def["glb"]:
		await Game.load_tick()
		if not ResourceLoader.exists(path):
			push_warning("GLB map part missing: %s" % path)
			continue
		var part := (load(path) as PackedScene).instantiate() as Node3D
		add_child(part)
		for node in part.find_children("*", "MeshInstance3D", true, false):
			var mi := node as MeshInstance3D
			var nm := str(mi.name)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if nm.begins_with("paint_") or nm.begins_with("terrain") or nm.begins_with("earth") \
				else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			var solid := true
			for pre in NOT_SOLID:
				if nm.begins_with(pre):
					solid = false
			if not solid or mi.mesh == null:
				continue
			var shape := mi.mesh.create_trimesh_shape()
			if shape == null:
				continue
			# the model's faces wind the other way round: solid from both sides
			shape.backface_collision = true
			var body := StaticBody3D.new()
			body.collision_layer = Colliders.LAYER_WORLD
			body.collision_mask = 0
			var cs := CollisionShape3D.new()
			cs.shape = shape
			body.add_child(cs)
			mi.add_child(body)
			stats["solid"] = int(stats.get("solid", 0)) + 1
		stats["parts"] = int(stats.get("parts", 0)) + 1
	print("GLB MAP: %s in %d ms" % [str(stats), Time.get_ticks_msec() - t0])

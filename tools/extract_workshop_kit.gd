extends SceneTree
## Cuts props out of the main menu workshop (Midnight_Drift_Garage_Detailed.glb) into small scenes
## for the mechanic workshops on the maps: assets/props/workshop_kit/<name>.scn – one merged mesh per
## material, standing with its bottom centre at the origin, with everything that sits on it (stock on a
## shelf, tools on a bench).
## Run: godot --headless --path . -s tools/extract_workshop_kit.gd

const WorkshopTextures = preload("res://scripts/world/workshop_textures.gd")
const MeshMerge = preload("res://scripts/util/mesh_merge.gd")
const OUT := "res://assets/props/workshop_kit/"
const KIT := ["Rolling_tool_trolley_001", "Rolling_tool_trolley_002", "Radial_car_tyre_stack_002", "Radial_car_tyre_stack_003",
	"Long_side_workbench_001", "Storage_shelving_001", "Red_floor_jack_001", "Welder_with_gas_trolley_001",
	"Vertical_shop_air_compressor_001", "Automotive_tyre_changer_001", "Floorplate_two_post_lift_001", "Rear_tool_wall_002",
	"Workshop_stool_001", "Oil_drain_pan_001", "Shop_bucket_001", "Loose_fluid_crate_001", "Spare_turbocharger_001",
	"Leaning_intercooler_001", "Wall_mounted_wheel_display_001", "Uneven_carton_pile_001", "Open_parts_shipping_box_001",
	"Axle_jack_stand_002", "Loose_car_alloy_wheel_001", "Manual_gearbox_on_floor_001", "Wall_mounted_nitrous_bottle_001",
	"Mountain_poster_001", "Spare_exhaust_section_001", "Paint_mixing_trolley_001", "Bench_vice_001"]


func _init() -> void:
	var g := (load("res://assets/main_menu/Midnight_Drift_Garage_Detailed.glb") as PackedScene).instantiate() as Node3D
	root.add_child(g)
	await process_frame
	print("loaded")
	WorkshopTextures.apply(g)
	print("textured")
	var garage := g.find_child("Garage", true, false)
	var tops: Array = garage.get_children()
	var boxes := {}
	for t in tops:
		boxes[t] = _aabb(t)
	for name in KIT:
		var main := garage.get_node_or_null(NodePath(name)) as Node3D
		if main == null:
			print("missing ", name)
			continue
		var mb: AABB = boxes[main]
		var group: Array = [main]
		for t in tops:
			if t == main or KIT.has(String(t.name)) or (boxes[t] as AABB).size.length() < 0.001:
				continue
			var bt: AABB = boxes[t]
			if bt.size.length() < mb.size.length() and mb.grow(0.12).has_point(bt.get_center()):
				group.append(t)
		print("group ", name, " ", group.size())
		var kit := Node3D.new()
		kit.name = name    # (renamed by hand: the second trolley and tyre stack got a _2)
		var origin := Vector3(mb.get_center().x, mb.position.y, mb.get_center().z)
		for t in group:
			for n in (t as Node).find_children("*", "MeshInstance3D", true, false) + [t]:
				if not (n is MeshInstance3D) or (n as MeshInstance3D).mesh == null:
					continue
				var mi := n as MeshInstance3D
				var c := MeshInstance3D.new()
				c.mesh = mi.mesh
				for s in mi.mesh.get_surface_count():
					c.set_surface_override_material(s, mi.get_active_material(s))
				c.transform = Transform3D(Basis.IDENTITY, -origin) * mi.global_transform
				kit.add_child(c)
		root.add_child(kit)
		MeshMerge.merge(kit, func(_m): return false)
		# only the merged meshes stay, with their own copies of the materials (no tie to the glb)
		for c in kit.get_children():
			if not String(c.name).begins_with("Merged_"):
				kit.remove_child(c)
				c.free()
			else:
				var mi := c as MeshInstance3D
				var am := mi.mesh as ArrayMesh
				for s in am.get_surface_count():
					var m := am.surface_get_material(s)
					if m:
						am.surface_set_material(s, m.duplicate())
				mi.owner = kit
		var ps := PackedScene.new()
		ps.pack(kit)
		var path: String = OUT + String(kit.name).to_lower() + ".scn"
		ResourceSaver.save(ps, path)
		print("saved ", path, "  ", mb.size, "  parts ", group.size())
		kit.queue_free()
	quit()


func _aabb(n: Node) -> AABB:
	var box := AABB()
	var first := true
	for c in n.find_children("*", "MeshInstance3D", true, false) + [n]:
		if c is MeshInstance3D and (c as MeshInstance3D).mesh:
			var bb: AABB = (c as MeshInstance3D).global_transform * (c as MeshInstance3D).get_aabb()
			box = bb if first else box.merge(bb)
			first = false
	return box

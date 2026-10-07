extends Node
## Writes the main menu's garage as it stands in the game (the workshop model with everything the game
## adds: paint booth, tools, pegboards, epoxy floor, the car on the turntable …) to a .glb for
## Blender. Needs a real renderer (mesh data): xvfb-run godot --rendering-driver opengl3 --path .
## res://tests/export_garage.tscn -- --out=export/garage_full.glb [--no-car]


func _ready() -> void:
	Game.persist = false
	Game.first_boot = false
	var out := "export/garage_full.glb"
	var with_car := true
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a == "--no-car":
			with_car = false
	var main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	while main.menu == null or main.showroom == null or not main.showroom.is_built:
		await get_tree().process_frame
	for f in 30:
		await get_tree().process_frame
	var sr: Node3D = main.showroom
	sr.set("auto_spin", false)
	# a copy without what glTF can't hold or Blender doesn't need (particles, 2D screens, helpers)
	var root := Node3D.new()
	root.name = "Garage"
	var dropped := {}
	var kept := 0
	for c in sr.get_children():
		if not with_car and str(c.name).begins_with("Car"):
			continue
		var d = _copy(c, dropped)
		if d:
			root.add_child(d)
	_set_owner(root, root)
	for n in root.find_children("*", "GeometryInstance3D", true, false):
		kept += 1
	print("EXPORT: %d drawable nodes, left out %s" % [kept, dropped])
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_scene(root, state)
	if err == OK:
		err = doc.write_to_filesystem(state, ProjectSettings.globalize_path("res://" + out) if not out.begins_with("/") else out)
	print("EXPORT GARAGE: %s -> %s" % ["OK" if err == OK else "error %d" % err, out])
	root.free()
	get_tree().quit()


## A plain copy of the 3D part of the tree, global transforms baked into local ones.
func _copy(n: Node, dropped: Dictionary) -> Node3D:
	if n is GPUParticles3D or n is CPUParticles3D or n is Label3D or n is Sprite3D or n is Camera3D \
			or n is SubViewport or n is AudioStreamPlayer3D or n is CollisionObject3D and not (n is RigidBody3D or n is StaticBody3D):
		dropped[n.get_class()] = int(dropped.get(n.get_class(), 0)) + 1
		return null
	if not (n is Node3D):
		# (a viewport, a timer … – its 3D children still count)
		var holder := Node3D.new()
		holder.name = n.name
		var any := false
		for c in n.get_children():
			var d = _copy(c, dropped)
			if d:
				holder.add_child(d)
				any = true
		if not any:
			holder.free()
			return null
		return holder
	var src := n as Node3D
	if not src.visible:
		dropped["hidden"] = int(dropped.get("hidden", 0)) + 1
		return null
	var out: Node3D
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		var mi := MeshInstance3D.new()
		mi.mesh = (n as MeshInstance3D).mesh
		mi.material_override = (n as MeshInstance3D).material_override
		for s in (n as MeshInstance3D).get_surface_override_material_count():
			mi.set_surface_override_material(s, (n as MeshInstance3D).get_surface_override_material(s))
		out = mi
	elif n is MultiMeshInstance3D and (n as MultiMeshInstance3D).multimesh:
		# one object per instance – but not the ones the game has hidden (scaled to nothing)
		var src_mm: MultiMesh = (n as MultiMeshInstance3D).multimesh
		out = Node3D.new()
		var count := src_mm.instance_count if src_mm.visible_instance_count < 0 else mini(src_mm.visible_instance_count, src_mm.instance_count)
		for k in count:
			var xf := src_mm.get_instance_transform(k)
			if absf(xf.basis.determinant()) < 1e-9:
				dropped["hidden instances"] = int(dropped.get("hidden instances", 0)) + 1
				continue
			var mi := MeshInstance3D.new()
			mi.name = "%s_%d" % [n.name, k]
			mi.mesh = src_mm.mesh
			mi.material_override = (n as MultiMeshInstance3D).material_override
			mi.transform = xf
			out.add_child(mi)
	elif n is Light3D:
		out = (n as Light3D).duplicate(0)
		for c in out.get_children():
			out.remove_child(c)
			c.free()
	else:
		out = Node3D.new()
	out.name = n.name
	out.transform = src.transform
	for c in n.get_children():
		var d = _copy(c, dropped)
		if d:
			out.add_child(d)
	return out


func _set_owner(n: Node, owner_node: Node) -> void:
	for c in n.get_children():
		c.owner = owner_node
		_set_owner(c, owner_node)

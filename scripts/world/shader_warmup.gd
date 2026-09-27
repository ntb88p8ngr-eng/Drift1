extends Node3D
## Godot 4.3 compiles a render pipeline the first time a material/mesh combination is drawn, which
## freezes the game for up to seconds when e.g. the first nitro flame, a new kind of tree or crate
## splinters appear. Right after loading, this draws one tiny copy of everything the world contains
## (meshes, multimeshes, particles – visible or not) in front of the camera for a few frames, so all
## pipelines are compiled while the intro message is still on screen.

const FRAMES := 4

var _frames := 0


## Collects every drawable under `root` (plus extra meshes) and places tiny copies near `cam`.
func run(root: Node, cam: Camera3D, extra_meshes: Array = []) -> void:
	var seen := {}
	var items: Array = []
	for gi in root.find_children("*", "GeometryInstance3D", true, false):
		if gi is MultiMeshInstance3D:
			var mm: MultiMesh = (gi as MultiMeshInstance3D).multimesh
			if mm == null or mm.mesh == null:
				continue
			var key := "mm_%d_%d" % [mm.mesh.get_rid().get_id(), gi.material_override.get_rid().get_id() if gi.material_override else 0]
			if seen.has(key):
				continue
			seen[key] = true
			var m2 := MultiMesh.new()
			m2.transform_format = MultiMesh.TRANSFORM_3D
			m2.use_custom_data = mm.use_custom_data
			m2.use_colors = mm.use_colors
			m2.mesh = mm.mesh
			m2.instance_count = 1
			m2.set_instance_transform(0, Transform3D.IDENTITY)
			if mm.use_custom_data:
				m2.set_instance_custom_data(0, Color(1, 1, 1, 1))
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = m2
			mmi.material_override = gi.material_override
			items.append(mmi)
		elif gi is MeshInstance3D:
			var mi0 := gi as MeshInstance3D
			if mi0.mesh == null:
				continue
			var key := "mi_%d_%d" % [mi0.mesh.get_rid().get_id(), mi0.material_override.get_rid().get_id() if mi0.material_override else 0]
			if seen.has(key):
				continue
			seen[key] = true
			var mi := MeshInstance3D.new()
			mi.mesh = mi0.mesh
			mi.material_override = mi0.material_override
			for s in mi0.get_surface_override_material_count():
				mi.set_surface_override_material(s, mi0.get_surface_override_material(s))
			items.append(mi)
		elif gi is GPUParticles3D:
			var p0 := gi as GPUParticles3D
			var key := "p_%d_%d" % [p0.process_material.get_rid().get_id() if p0.process_material else 0, p0.draw_pass_1.get_rid().get_id() if p0.draw_pass_1 else 0]
			if seen.has(key):
				continue
			seen[key] = true
			var p := GPUParticles3D.new()
			p.process_material = p0.process_material
			p.draw_pass_1 = p0.draw_pass_1
			p.amount = 4
			p.lifetime = 0.2
			p.emitting = true
			items.append(p)
	for m in extra_meshes:
		var mi := MeshInstance3D.new()
		mi.mesh = m
		items.append(mi)
	# a small grid of tiny objects 1.5 m in front of the camera
	var xf := cam.global_transform
	var n := int(ceil(sqrt(float(items.size()))))
	for i in items.size():
		var node: GeometryInstance3D = items[i]
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(node)
		var gx := (float(i % n) / maxf(n - 1, 1) - 0.5) * 0.6
		var gy := (float(i / n) / maxf(n - 1, 1) - 0.5) * 0.35
		node.global_transform = Transform3D(xf.basis.scaled(Vector3(0.004, 0.004, 0.004)), xf * Vector3(gx, gy, -1.5))
	print("WARMUP: %d pipelines" % items.size())


func _process(_delta: float) -> void:
	_frames += 1
	if _frames > FRAMES:
		queue_free()

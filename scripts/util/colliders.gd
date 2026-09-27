extends RefCounted
## Static collision for buildings and other fixed scenery (layer 1 = world, like the terrain).

const LAYER_WORLD := 1


## A static trimesh body for every MeshInstance3D under `root` (houses, grandstand, gantry …).
static func add_trimesh(root: Node) -> int:
	var n := 0
	var list: Array = root.find_children("*", "MeshInstance3D", true, false)
	if root is MeshInstance3D:
		list.append(root)
	for mi in list:
		var mesh: Mesh = (mi as MeshInstance3D).mesh
		if mesh == null:
			continue
		var shape := mesh.create_trimesh_shape()
		if shape == null:
			continue
		var body := StaticBody3D.new()
		body.collision_layer = LAYER_WORLD
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
		(mi as Node).add_child(body)
		n += 1
	return n


## A static box (centre + basis in `xf`) under `parent`.
static func add_box(parent: Node, xf: Transform3D, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = LAYER_WORLD
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	body.add_child(cs)
	parent.add_child(body)
	body.global_transform = xf
	return body

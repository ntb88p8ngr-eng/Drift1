extends RefCounted
## An imported model as one mesh for instancing: every MeshInstance3D of the scene merged with its
## transform baked in (plus `base`), one surface per material. Cached by path and base.

static var _cache := {}


static func merged(path: String, base := Transform3D.IDENTITY) -> ArrayMesh:
	var key := "%s|%s" % [path, base]
	if _cache.has(key):
		return _cache[key]
	if not ResourceLoader.exists(path):
		return null
	var ps = load(path)
	if not (ps is PackedScene):
		return null
	var root: Node = (ps as PackedScene).instantiate()
	var sts := {}
	_collect(root, base, sts)
	root.free()
	var out := ArrayMesh.new()
	for mat in sts:
		(sts[mat] as SurfaceTool).commit(out)
		out.surface_set_material(out.get_surface_count() - 1, mat)
	_cache[key] = out
	return out


static func _collect(n: Node, xf: Transform3D, sts: Dictionary) -> void:
	var x := xf
	if n is Node3D:
		x = xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		var mi := n as MeshInstance3D
		for si in mi.mesh.get_surface_count():
			var mat = mi.get_surface_override_material(si)
			if mat == null:
				mat = mi.mesh.surface_get_material(si)
			if not sts.has(mat):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				sts[mat] = st
			(sts[mat] as SurfaceTool).append_from(mi.mesh, si, x)
	for c in n.get_children():
		_collect(c, x, sts)

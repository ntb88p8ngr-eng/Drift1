extends RefCounted
## Merges the static meshes of an imported scene into one mesh per material (thousands of small
## parts – bolts, tools, boxes – become a few dozen draw calls). Positions, normals, tangents and
## UVs are carried over; the original nodes stay, without their mesh.


## Merges every MeshInstance3D under `root` for which `keep(mi)` is false into one MeshInstance3D
## per material, added to `root`. Returns the number of meshes merged.
static func merge(root: Node3D, keep: Callable) -> int:
	var groups := {}            # material -> {v, n, t, uv, idx}
	var merged := 0
	var inv := root.global_transform.affine_inverse()
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null or keep.call(mi) or mi.skin != null:
			continue
		var xf: Transform3D = inv * mi.global_transform
		var nxf := Transform3D(xf.basis.inverse().transposed(), Vector3.ZERO)
		var ok := true
		for s in mi.mesh.get_surface_count():
			if mi.mesh.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
				ok = false
		if not ok:
			continue
		for s in mi.mesh.get_surface_count():
			var arr: Array = mi.mesh.surface_get_arrays(s)
			var mat := mi.get_active_material(s)
			if not groups.has(mat):
				groups[mat] = {"v": PackedVector3Array(), "n": PackedVector3Array(), "t": PackedFloat32Array(), "uv": PackedVector2Array(), "i": PackedInt32Array()}
			# (packed arrays are values: taken out, extended and put back)
			var g: Dictionary = groups[mat]
			var gv: PackedVector3Array = g["v"]
			var gn: PackedVector3Array = g["n"]
			var gt: PackedFloat32Array = g["t"]
			var guv: PackedVector2Array = g["uv"]
			var gi: PackedInt32Array = g["i"]
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var base: int = gv.size()
			var count := verts.size()
			gv.append_array(xf * verts)
			var nrm = arr[Mesh.ARRAY_NORMAL]
			if nrm is PackedVector3Array and (nrm as PackedVector3Array).size() == count:
				var nn: PackedVector3Array = nxf * (nrm as PackedVector3Array)
				for k in count:
					nn[k] = nn[k].normalized()
				gn.append_array(nn)
			else:
				var up := PackedVector3Array()
				up.resize(count)
				up.fill(Vector3.UP)
				gn.append_array(up)
			var tan = arr[Mesh.ARRAY_TANGENT]
			var tt := PackedFloat32Array()
			tt.resize(count * 4)
			if tan is PackedFloat32Array and (tan as PackedFloat32Array).size() == count * 4:
				var src: PackedFloat32Array = tan
				for k in count:
					var tv := (xf.basis * Vector3(src[k * 4], src[k * 4 + 1], src[k * 4 + 2])).normalized()
					tt[k * 4] = tv.x
					tt[k * 4 + 1] = tv.y
					tt[k * 4 + 2] = tv.z
					tt[k * 4 + 3] = src[k * 4 + 3] * (1.0 if xf.basis.determinant() >= 0.0 else -1.0)
			else:
				for k in count:
					tt[k * 4] = 1.0
					tt[k * 4 + 3] = 1.0
			gt.append_array(tt)
			var uv = arr[Mesh.ARRAY_TEX_UV]
			if uv is PackedVector2Array and (uv as PackedVector2Array).size() == count:
				guv.append_array(uv)
			else:
				var z := PackedVector2Array()
				z.resize(count)
				guv.append_array(z)
			var idx = arr[Mesh.ARRAY_INDEX]
			var ii := PackedInt32Array()
			if idx is PackedInt32Array and (idx as PackedInt32Array).size() > 0:
				ii = idx
				if xf.basis.determinant() < 0.0:
					# mirrored part: keep the faces pointing outwards
					for k in range(0, ii.size(), 3):
						var tmp := ii[k + 1]
						ii[k + 1] = ii[k + 2]
						ii[k + 2] = tmp
			else:
				ii.resize(count)
				for k in count:
					ii[k] = k
			for k in ii.size():
				ii[k] += base
			gi.append_array(ii)
			g["v"] = gv
			g["n"] = gn
			g["t"] = gt
			g["uv"] = guv
			g["i"] = gi
		# the node stays (lights and other parts may hang under it), only its mesh goes
		mi.mesh = null
		merged += 1
	for mat in groups:
		var g: Dictionary = groups[mat]
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = g["v"]
		arrays[Mesh.ARRAY_NORMAL] = g["n"]
		arrays[Mesh.ARRAY_TANGENT] = g["t"]
		arrays[Mesh.ARRAY_TEX_UV] = g["uv"]
		arrays[Mesh.ARRAY_INDEX] = g["i"]
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		am.surface_set_material(0, mat)
		var out := MeshInstance3D.new()
		out.name = "Merged_%d" % root.get_child_count()
		out.mesh = am
		root.add_child(out)
	return merged

extends RefCounted
## Changing single instances of a MultiMesh that was filled in one go (`mm.buffer = …`, as all the
## scenery chunks are): in Godot 4.3 set_instance_transform() on such a MultiMesh rebuilds its CPU
## copy empty and uploads the whole block of 512 instances around the one changed – its neighbours
## turn invisible (or into garbage). These write into the buffer itself instead.


static func _stride(mm: MultiMesh) -> int:
	return 12 + (4 if mm.use_colors else 0) + (4 if mm.use_custom_data else 0)


static func _put(buf: PackedFloat32Array, j: int, xf: Transform3D) -> void:
	var b := xf.basis
	buf[j] = b.x.x
	buf[j + 1] = b.y.x
	buf[j + 2] = b.z.x
	buf[j + 3] = xf.origin.x
	buf[j + 4] = b.x.y
	buf[j + 5] = b.y.y
	buf[j + 6] = b.z.y
	buf[j + 7] = xf.origin.y
	buf[j + 8] = b.x.z
	buf[j + 9] = b.y.z
	buf[j + 10] = b.z.z
	buf[j + 11] = xf.origin.z


static func get_xf(mm: MultiMesh, i: int) -> Transform3D:
	var buf := mm.buffer
	var j := i * _stride(mm)
	if j + 11 >= buf.size():
		return mm.get_instance_transform(i)
	return Transform3D(Basis(Vector3(buf[j], buf[j + 4], buf[j + 8]), Vector3(buf[j + 1], buf[j + 5], buf[j + 9]),
		Vector3(buf[j + 2], buf[j + 6], buf[j + 10])), Vector3(buf[j + 3], buf[j + 7], buf[j + 11]))


static func set_xf(mm: MultiMesh, i: int, xf: Transform3D) -> void:
	set_many(mm, {i: xf})


## Several instances at once (one upload): {index: Transform3D}.
static func set_many(mm: MultiMesh, xfs: Dictionary) -> void:
	if xfs.is_empty():
		return
	var buf := mm.buffer
	var st := _stride(mm)
	for i in xfs:
		var j := int(i) * st
		if j + 11 < buf.size():
			_put(buf, j, xfs[i])
	mm.buffer = buf


## An instance shrunk to nothing where it stands (removed: nothing left to draw or cast a shadow).
static func hide(mm: MultiMesh, i: int) -> void:
	var xf := get_xf(mm, i)
	set_xf(mm, i, Transform3D(xf.basis.scaled(Vector3.ONE * 0.0001), xf.origin))

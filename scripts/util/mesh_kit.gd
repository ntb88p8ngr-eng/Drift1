extends RefCounted
## Procedural mesh helpers.
## Godot treats clockwise triangles (seen from the viewer) as front faces. Every helper here
## takes an "outward" hint and fixes the winding itself, so callers never have to think about it.


## Emits one triangle with per-vertex normals/uvs, oriented so its front faces `outward`.
static func tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3,
		ua: Vector2, ub: Vector2, uc: Vector2, outward: Vector3, col: Color = Color.WHITE) -> void:
	if (b - a).cross(c - a).dot(outward) > 0.0:
		var tv := b
		b = c
		c = tv
		var tn := nb
		nb = nc
		nc = tn
		var tu := ub
		ub = uc
		uc = tu
	st.set_color(col)
	st.set_normal(na)
	st.set_uv(ua)
	st.add_vertex(a)
	st.set_color(col)
	st.set_normal(nb)
	st.set_uv(ub)
	st.add_vertex(b)
	st.set_color(col)
	st.set_normal(nc)
	st.set_uv(uc)
	st.add_vertex(c)


## Flat quad (a,b,c,d in ring order) facing `outward`.
static func quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, outward: Vector3,
		uv_a := Vector2(0, 0), uv_b := Vector2(1, 0), uv_c := Vector2(1, 1), uv_d := Vector2(0, 1), col: Color = Color.WHITE) -> void:
	var n := outward.normalized()
	tri(st, a, b, c, n, n, n, uv_a, uv_b, uv_c, outward, col)
	tri(st, a, c, d, n, n, n, uv_a, uv_c, uv_d, outward, col)


## Builds a smooth surface from a grid of points.
## rows: Array of PackedVector3Array (all the same length). Row index = "v", column index = "u".
## centers: one interior reference point per row; normals point away from it.
## wrap_u closes each row into a ring (tubes, lofted bodies).
static func grid(st: SurfaceTool, rows: Array, centers: Array, wrap_u: bool, uv_scale := Vector2.ONE,
		col: Color = Color.WHITE, invert := false) -> void:
	var nr := rows.size()
	if nr < 2:
		return
	var nc: int = (rows[0] as PackedVector3Array).size()
	if nc < 2:
		return
	# per-vertex normals from grid neighbours
	var normals: Array = []
	for i in nr:
		var row: PackedVector3Array = rows[i]
		var nrow := PackedVector3Array()
		nrow.resize(nc)
		var center: Vector3 = centers[i]
		for j in nc:
			var jl := j - 1
			var jr := j + 1
			if wrap_u:
				jl = (j - 1 + nc) % nc
				jr = (j + 1) % nc
			else:
				jl = maxi(jl, 0)
				jr = mini(jr, nc - 1)
			var il := maxi(i - 1, 0)
			var ir := mini(i + 1, nr - 1)
			var tu: Vector3 = row[jr] - row[jl]
			var tv: Vector3 = (rows[ir] as PackedVector3Array)[j] - (rows[il] as PackedVector3Array)[j]
			var n := tu.cross(tv)
			var out_dir: Vector3 = row[j] - center
			if n.length_squared() < 1e-10:
				n = out_dir
			n = n.normalized()
			if n.dot(out_dir) < 0.0:
				n = -n
			if invert:
				n = -n
			nrow[j] = n
		normals.append(nrow)
	# u coordinates by arc length along each row, v by arc length along columns (averaged)
	var ucount := nc + 1 if wrap_u else nc
	var v_acc := 0.0
	var v_coords: Array = [0.0]
	for i in range(1, nr):
		var d := 0.0
		var ra: PackedVector3Array = rows[i - 1]
		var rb: PackedVector3Array = rows[i]
		for j in nc:
			d += ra[j].distance_to(rb[j])
		v_acc += d / float(nc)
		v_coords.append(v_acc)
	for i in range(nr - 1):
		var ra: PackedVector3Array = rows[i]
		var rb: PackedVector3Array = rows[i + 1]
		var na: PackedVector3Array = normals[i]
		var nb: PackedVector3Array = normals[i + 1]
		var va: float = v_coords[i] * uv_scale.y
		var vb: float = v_coords[i + 1] * uv_scale.y
		var ca: Vector3 = centers[i]
		var cb: Vector3 = centers[i + 1]
		for j in range(ucount - 1):
			var j2 := (j + 1) % nc
			var u0 := float(j) / float(ucount - 1) * uv_scale.x
			var u1 := float(j + 1) / float(ucount - 1) * uv_scale.x
			var p00: Vector3 = ra[j]
			var p01: Vector3 = ra[j2]
			var p10: Vector3 = rb[j]
			var p11: Vector3 = rb[j2]
			var mid := (p00 + p01 + p10 + p11) * 0.25
			var outward := mid - (ca + cb) * 0.5
			if invert:
				outward = -outward
			tri(st, p00, p10, p11, na[j], nb[j], nb[j2], Vector2(u0, va), Vector2(u0, vb), Vector2(u1, vb), outward, col)
			tri(st, p00, p11, p01, na[j], nb[j2], na[j2], Vector2(u0, va), Vector2(u1, vb), Vector2(u1, va), outward, col)


## Closes a ring of points with a fan (for loft end caps).
static func cap(st: SurfaceTool, ring: PackedVector3Array, center: Vector3, outward: Vector3, col: Color = Color.WHITE) -> void:
	var n := outward.normalized()
	for j in ring.size():
		var a: Vector3 = ring[j]
		var b: Vector3 = ring[(j + 1) % ring.size()]
		tri(st, center, a, b, n, n, n, Vector2(0.5, 0.5), Vector2(0, 0), Vector2(1, 0), outward, col)


## A tapered tube along a polyline, using parallel-transport frames. Returns nothing; writes into st.
static func tube(st: SurfaceTool, points: Array, radii: Array, segments: int, uv_scale := Vector2(1, 1),
		col: Color = Color.WHITE, close_tip := true) -> void:
	var n := points.size()
	if n < 2:
		return
	var rows: Array = []
	var centers: Array = []
	var t0: Vector3 = ((points[1] as Vector3) - (points[0] as Vector3)).normalized()
	var ref := Vector3.UP if absf(t0.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	var normal := t0.cross(ref).normalized()
	var prev_t := t0
	for i in n:
		var p: Vector3 = points[i]
		var t: Vector3
		if i == 0:
			t = t0
		elif i == n - 1:
			t = (p - (points[i - 1] as Vector3)).normalized()
		else:
			t = ((points[i + 1] as Vector3) - (points[i - 1] as Vector3)).normalized()
		# parallel transport the normal
		var axis := prev_t.cross(t)
		if axis.length_squared() > 1e-8:
			var ang := prev_t.angle_to(t)
			normal = normal.rotated(axis.normalized(), ang)
		prev_t = t
		var binormal := t.cross(normal).normalized()
		var r: float = radii[i]
		var ring := PackedVector3Array()
		ring.resize(segments)
		for s in segments:
			var a := TAU * float(s) / float(segments)
			ring[s] = p + (normal * cos(a) + binormal * sin(a)) * r
		rows.append(ring)
		centers.append(p)
	grid(st, rows, centers, true, uv_scale, col)
	if close_tip:
		var last: PackedVector3Array = rows[n - 1]
		var tip_dir: Vector3 = ((points[n - 1] as Vector3) - (points[n - 2] as Vector3)).normalized()
		cap(st, last, (points[n - 1] as Vector3) + tip_dir * float(radii[n - 1]) * 0.6, tip_dir, col)


## Surface of revolution around the X axis. profile: Array of Vector2(x, radius), traversed so that
## the outside lies to the left of the direction of travel (normal = (-dr, dx)).
static func lathe(st: SurfaceTool, profile: Array, segments: int, col: Color = Color.WHITE) -> void:
	var n := profile.size()
	if n < 2:
		return
	var normals2: Array = []
	for i in n:
		var a: Vector2 = profile[maxi(i - 1, 0)]
		var b: Vector2 = profile[mini(i + 1, n - 1)]
		var t := (b - a).normalized()
		normals2.append(Vector2(-t.y, t.x))
	for i in range(n - 1):
		var p0: Vector2 = profile[i]
		var p1: Vector2 = profile[i + 1]
		var n0: Vector2 = normals2[i]
		var n1: Vector2 = normals2[i + 1]
		var seg_n := Vector2(-(p1 - p0).y, (p1 - p0).x)
		for j in segments:
			var a0 := TAU * float(j) / segments
			var a1 := TAU * float(j + 1) / segments
			var c0 := cos(a0)
			var s0 := sin(a0)
			var c1 := cos(a1)
			var s1 := sin(a1)
			var v00 := Vector3(p0.x, p0.y * c0, p0.y * s0)
			var v01 := Vector3(p0.x, p0.y * c1, p0.y * s1)
			var v10 := Vector3(p1.x, p1.y * c0, p1.y * s0)
			var v11 := Vector3(p1.x, p1.y * c1, p1.y * s1)
			var n00 := Vector3(n0.x, n0.y * c0, n0.y * s0)
			var n01 := Vector3(n0.x, n0.y * c1, n0.y * s1)
			var n10 := Vector3(n1.x, n1.y * c0, n1.y * s0)
			var n11 := Vector3(n1.x, n1.y * c1, n1.y * s1)
			var am := (a0 + a1) * 0.5
			var outward := Vector3(seg_n.x, seg_n.y * cos(am), seg_n.y * sin(am))
			var u0 := float(j) / segments
			var u1 := float(j + 1) / segments
			var w0 := float(i) / (n - 1)
			var w1 := float(i + 1) / (n - 1)
			tri(st, v00, v10, v11, n00, n10, n11, Vector2(u0, w0), Vector2(u0, w1), Vector2(u1, w1), outward, col)
			tri(st, v00, v11, v01, n00, n11, n01, Vector2(u0, w0), Vector2(u1, w1), Vector2(u1, w0), outward, col)


## Axis-aligned box (optionally transformed) with flat normals.
static func box(st: SurfaceTool, xf: Transform3D, size: Vector3, col: Color = Color.WHITE, uv_scale := 1.0) -> void:
	var h := size * 0.5
	var c := [
		Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(-h.x, h.y, -h.z),
		Vector3(-h.x, -h.y, h.z), Vector3(h.x, -h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z),
	]
	var faces := [
		[0, 1, 2, 3, Vector3(0, 0, -1), size.x, size.y],
		[5, 4, 7, 6, Vector3(0, 0, 1), size.x, size.y],
		[4, 0, 3, 7, Vector3(-1, 0, 0), size.z, size.y],
		[1, 5, 6, 2, Vector3(1, 0, 0), size.z, size.y],
		[3, 2, 6, 7, Vector3(0, 1, 0), size.x, size.z],
		[4, 5, 1, 0, Vector3(0, -1, 0), size.x, size.z],
	]
	for f in faces:
		var a: Vector3 = xf * (c[f[0]] as Vector3)
		var b: Vector3 = xf * (c[f[1]] as Vector3)
		var cc: Vector3 = xf * (c[f[2]] as Vector3)
		var d: Vector3 = xf * (c[f[3]] as Vector3)
		var nrm: Vector3 = (xf.basis * (f[4] as Vector3)).normalized()
		var w: float = f[5] * uv_scale
		var hh: float = f[6] * uv_scale
		quad(st, a, b, cc, d, nrm, Vector2(0, hh), Vector2(w, hh), Vector2(w, 0), Vector2(0, 0), col)


static func new_st() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


## Commits a SurfaceTool as a new surface of `mesh` (creates the mesh when null).
static func commit(st: SurfaceTool, material: Material, mesh: ArrayMesh = null, tangents := false) -> ArrayMesh:
	if tangents:
		st.generate_tangents()
	st.set_material(material)
	if mesh == null:
		return st.commit()
	return st.commit(mesh)


static func mesh_instance(mesh: Mesh, material: Material = null, shadows := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	if material:
		mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## Convenience: primitive box/cylinder/sphere nodes.
static func box_node(size: Vector3, material: Material, pos := Vector3.ZERO, rot := Vector3.ZERO) -> MeshInstance3D:
	var m := BoxMesh.new()
	m.size = size
	var mi := mesh_instance(m, material)
	mi.position = pos
	mi.rotation = rot
	return mi


static func cyl_node(radius_top: float, radius_bottom: float, height: float, material: Material, pos := Vector3.ZERO,
		rot := Vector3.ZERO, segments := 24) -> MeshInstance3D:
	var m := CylinderMesh.new()
	m.top_radius = radius_top
	m.bottom_radius = radius_bottom
	m.height = height
	m.radial_segments = segments
	m.rings = 1
	var mi := mesh_instance(m, material)
	mi.position = pos
	mi.rotation = rot
	return mi


static func sphere_node(radius: float, material: Material, pos := Vector3.ZERO, scale := Vector3.ONE) -> MeshInstance3D:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0
	m.radial_segments = 24
	m.rings = 12
	var mi := mesh_instance(m, material)
	mi.position = pos
	mi.scale = scale
	return mi

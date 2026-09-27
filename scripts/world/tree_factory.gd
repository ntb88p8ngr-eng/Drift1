extends RefCounted
## Procedurally generated, high-detail trees.
## Every mesh has two surfaces: 0 = bark (tapered, bent branch tubes), 1 = foliage (alpha-tested leaf cards).
## "detail" 1.0 = close-up model (~6-9k triangles), 0.25 = mid-distance LOD (~0.5-1.3k).
## far_tree() builds the cheap far LOD (opaque crown volumes, ~100 triangles); shrub(), fern() and
## rock() fill the undergrowth. Foliage colours can be varied per instance (MultiMesh custom data).

const MeshKit = preload("res://scripts/util/mesh_kit.gd")
const TexKit = preload("res://scripts/util/tex_kit.gd")

static var _mats := {}


static func _material(key: String) -> Material:
	if not _mats.has(key):
		match key:
			"bark":
				_mats[key] = TexKit.bark_material(Color(1.0, 0.95, 0.9))
			"bark_pine":
				_mats[key] = TexKit.bark_material(Color(0.85, 0.7, 0.62))
			"leaf":
				_mats[key] = TexKit.leaf_material("leaf", Color(1.0, 1.0, 1.0))
			"leaf_autumn":
				_mats[key] = TexKit.leaf_material("leaf", Color(1.6, 0.95, 0.45))
			"leaf_oak":
				_mats[key] = TexKit.leaf_material("oak", Color(1.0, 1.0, 1.0))
			"needle":
				_mats[key] = TexKit.leaf_material("needle", Color(1.0, 1.0, 1.0))
			"fern":
				_mats[key] = TexKit.leaf_material("fern", Color(1.0, 1.0, 1.0))
			"far":
				_mats[key] = TexKit.far_tree_material(Color(0.17, 0.3, 0.07))
			"rock":
				_mats[key] = TexKit.rock_material()
	return _mats[key]


# ---------------------------------------------------------------------------
# Broadleaf tree (maple/oak-like)
# ---------------------------------------------------------------------------
static func deciduous(seed_value: int, detail: float, autumn := false) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var bark := MeshKit.new_st()
	var leaves := MeshKit.new_st()
	var height := rng.randf_range(8.0, 11.5)
	var ctx := {
		"rng": rng, "bark": bark, "leaves": leaves, "detail": detail,
		"max_depth": 3 if detail > 0.6 else 2,
		"crown": Vector3(0, height * 0.72, 0),
		"leaf_size": 1.3 if detail > 0.6 else (2.1 if detail > 0.3 else 2.8),
		"leaf_count": 11 if detail > 0.6 else (9 if detail > 0.3 else 5),
	}
	var dir := Vector3(rng.randf_range(-0.07, 0.07), 1.0, rng.randf_range(-0.07, 0.07)).normalized()
	_branch(ctx, Vector3(0, -0.3, 0), dir, height * 0.55, 0.30 * height / 10.0, 0)
	# root flares
	var roots := 5 if detail > 0.6 else 0
	for k in roots:
		var a := TAU * float(k) / float(roots) + rng.randf_range(-0.3, 0.3)
		var out := Vector3(cos(a), 0, sin(a))
		var pts := [Vector3(0, 0.9, 0) + out * 0.05, out * 0.45 + Vector3(0, 0.25, 0), out * 0.9 + Vector3(0, -0.1, 0)]
		MeshKit.tube(bark, pts, [0.16, 0.1, 0.04], 5, Vector2(1, 0.4))
	var mesh := MeshKit.commit(bark, _material("bark"), null, true)
	MeshKit.commit(leaves, _material("leaf_autumn" if autumn else "leaf"), mesh)
	return mesh


static func _branch(ctx: Dictionary, start: Vector3, dir: Vector3, length: float, radius: float, depth: int) -> void:
	var rng: RandomNumberGenerator = ctx["rng"]
	var detail: float = ctx["detail"]
	var max_depth: int = ctx["max_depth"]
	var segs := 7 if depth == 0 else (5 if depth == 1 else 3)
	var ring_base: int = [12, 8, 6, 4][mini(depth, 3)]
	var ring := maxi(3, int(round(ring_base * (0.5 + 0.5 * detail))))
	var pts: Array = [start]
	var radii: Array = [radius]
	var p := start
	var d := dir
	var end_ratio := 0.5 if depth < max_depth else 0.25
	var gnarl: float = ctx.get("gnarl", 1.0)
	var up_bias: float = ctx.get("up_bias", 0.06)
	for s in segs:
		var bend := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.4, 0.5), rng.randf_range(-1, 1)) * (0.1 + depth * 0.07) * gnarl
		d = (d + bend + Vector3.UP * (up_bias if depth > 0 else 0.03)).normalized()
		if depth >= 2:
			d = (d + Vector3.DOWN * 0.05).normalized()
		p = p + d * (length / segs)
		pts.append(p)
		radii.append(radius * lerpf(1.0, end_ratio, float(s + 1) / segs))
	MeshKit.tube(ctx["bark"], pts, radii, ring, Vector2(1.0, 0.3))
	if depth >= max_depth:
		_leaf_cluster(ctx, p, length * 0.55 + 0.7)
		_leaf_cluster(ctx, (pts[segs / 2 + 1] as Vector3), length * 0.35 + 0.5)
		return
	var children: int = [6, 4, 3][mini(depth, 2)]
	if detail < 0.6 and depth == 0:
		children = 7 if detail > 0.3 else 6
	if detail <= 0.3 and depth == 1:
		children = 3
	if depth == 0 and ctx.has("trunk_children"):
		children = int(ctx["trunk_children"])
	var az := rng.randf() * TAU
	for c in children:
		var t := rng.randf_range(float(ctx.get("t_min", 0.38)) if depth == 0 else 0.25, 0.97)
		var fi := t * segs
		var idx := mini(int(fi), segs - 1)
		var frac := fi - idx
		var pt: Vector3 = (pts[idx] as Vector3).lerp(pts[idx + 1], frac)
		var rad := lerpf(float(radii[idx]), float(radii[idx + 1]), frac)
		az += 2.39996 + rng.randf_range(-0.3, 0.3)
		var ref := Vector3.UP if absf(d.y) < 0.95 else Vector3.RIGHT
		var side := d.cross(ref).normalized().rotated(d, az)
		var angle := deg_to_rad(rng.randf_range(float(ctx.get("angle_min", 32.0)), float(ctx.get("angle_max", 58.0))))
		var cdir := (d * cos(angle) + side * sin(angle)).normalized()
		var clen := length * rng.randf_range(0.55, 0.75) * (1.15 - t * 0.45)
		if depth == 0:
			clen *= float(ctx.get("limb_scale", 1.0))
		_branch(ctx, pt, cdir, clen, rad * 0.62, depth + 1)
	if depth == max_depth - 1:
		_leaf_cluster(ctx, p, length * 0.45 + 0.6)


static func _leaf_cluster(ctx: Dictionary, center: Vector3, radius: float) -> void:
	var rng: RandomNumberGenerator = ctx["rng"]
	var st: SurfaceTool = ctx["leaves"]
	var crown: Vector3 = ctx["crown"]
	var count: int = ctx["leaf_count"]
	var size: float = ctx["leaf_size"]
	for k in count:
		var off := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.7, 1.0), rng.randf_range(-1, 1))
		if off.length() > 1.0:
			off = off.normalized() * rng.randf()
		var pos := center + off * radius * 0.8
		var b := Basis.from_euler(Vector3(rng.randf_range(-1.1, 1.1), rng.randf() * TAU, rng.randf_range(-0.5, 0.5)))
		var s := size * rng.randf_range(0.8, 1.2)
		var bx := b.x * s * 0.5
		var by := b.y * s * 0.5
		var nrm := (pos - crown).normalized().lerp(Vector3.UP, 0.25).normalized()
		var col := Color(rng.randf_range(0.8, 1.1), rng.randf_range(0.85, 1.1), rng.randf_range(0.8, 1.0))
		var a := pos - bx - by
		var bb := pos + bx - by
		var c := pos + bx + by
		var dd := pos - bx + by
		MeshKit.tri(st, a, bb, c, nrm, nrm, nrm, Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), b.z, col)
		MeshKit.tri(st, a, c, dd, nrm, nrm, nrm, Vector2(0, 1), Vector2(1, 0), Vector2(0, 0), b.z, col)


# ---------------------------------------------------------------------------
# Oak: short, thick trunk splitting into long, crooked, spreading limbs; broad dark crown
# ---------------------------------------------------------------------------
static func oak(seed_value: int, detail: float) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var bark := MeshKit.new_st()
	var leaves := MeshKit.new_st()
	var trunk := rng.randf_range(4.2, 5.2)
	var ctx := {
		"rng": rng, "bark": bark, "leaves": leaves, "detail": detail,
		"max_depth": 3 if detail > 0.6 else 2,
		"crown": Vector3(0, trunk + 3.2, 0),
		"leaf_size": 1.5 if detail > 0.6 else (2.4 if detail > 0.3 else 3.1),
		"leaf_count": 12 if detail > 0.6 else (10 if detail > 0.3 else 6),
		"trunk_children": 6 if detail > 0.3 else 5,
		"t_min": 0.62, "angle_min": 42.0, "angle_max": 72.0, "limb_scale": 2.1,
		"up_bias": 0.035, "gnarl": 1.7,
	}
	var dir := Vector3(rng.randf_range(-0.05, 0.05), 1.0, rng.randf_range(-0.05, 0.05)).normalized()
	_branch(ctx, Vector3(0, -0.3, 0), dir, trunk, 0.52, 0)
	var roots := 6 if detail > 0.6 else 0
	for k in roots:
		var a := TAU * float(k) / float(roots) + rng.randf_range(-0.3, 0.3)
		var out := Vector3(cos(a), 0, sin(a))
		var pts := [Vector3(0, 1.1, 0) + out * 0.1, out * 0.7 + Vector3(0, 0.3, 0), out * 1.3 + Vector3(0, -0.12, 0)]
		MeshKit.tube(bark, pts, [0.26, 0.15, 0.05], 5, Vector2(1, 0.4))
	var mesh := MeshKit.commit(bark, _material("bark"), null, true)
	MeshKit.commit(leaves, _material("leaf_oak"), mesh)
	return mesh


# ---------------------------------------------------------------------------
# Conifer (pine/cedar-like)
# ---------------------------------------------------------------------------
static func pine(seed_value: int, detail: float) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var bark := MeshKit.new_st()
	var leaves := MeshKit.new_st()
	var height := rng.randf_range(12.0, 18.0)
	var ring := 10 if detail > 0.6 else 5
	# trunk with slight lean/wobble
	var tpts: Array = []
	var trad: Array = []
	var segs := 9
	for s in segs + 1:
		var f := float(s) / segs
		tpts.append(Vector3(sin(f * 3.1 + seed_value) * 0.12 * f, -0.3 + f * height, cos(f * 2.3 + seed_value) * 0.12 * f))
		trad.append(lerpf(0.36, 0.03, pow(f, 0.9)) * (height / 15.0))
	MeshKit.tube(bark, tpts, trad, ring, Vector2(1.0, 0.25))
	var start_h := rng.randf_range(2.0, 3.2)
	var h := start_h
	var whorl := 0
	var per_whorl := 7 if detail > 0.6 else 5
	while h < height - 0.6:
		var frac := (h - start_h) / (height - start_h)
		var blen := lerpf(3.8, 0.55, pow(frac, 0.85)) * rng.randf_range(0.85, 1.15) * (height / 15.0)
		var offset := rng.randf() * TAU
		for k in per_whorl:
			var az := offset + TAU * float(k) / per_whorl + rng.randf_range(-0.25, 0.25)
			var out := Vector3(cos(az), 0, sin(az))
			var droop := rng.randf_range(0.2, 0.45) * (1.0 - frac * 0.5)
			var base := Vector3(0, h, 0)
			var mid := base + out * blen * 0.5 + Vector3(0, -droop * blen * 0.35, 0)
			var tip := base + out * blen + Vector3(0, -droop * blen * 0.25 + 0.12 * blen, 0)
			if detail > 0.6:
				MeshKit.tube(bark, [base, mid, tip], [0.06 * (1.0 - frac) + 0.02, 0.035, 0.012], 4, Vector2(1.0, 0.3))
			_needle_cards(leaves, rng, [base + out * 0.15, mid, tip], blen, detail)
		h += rng.randf_range(0.5, 0.75) * (height / 15.0)
		whorl += 1
	# crown tip
	var top := Vector3(0, height - 0.4, 0)
	for k in 4:
		var az2 := TAU * k / 4.0
		var o := Vector3(cos(az2), 0.8, sin(az2)).normalized()
		_needle_cards(leaves, rng, [top, top + o * 0.5, top + o * 0.9], 0.9, detail)
	var mesh := MeshKit.commit(bark, _material("bark_pine"), null, true)
	MeshKit.commit(leaves, _material("needle"), mesh)
	return mesh


static func _needle_cards(st: SurfaceTool, rng: RandomNumberGenerator, path: Array, blen: float, detail: float) -> void:
	var cards := 3 if detail > 0.6 else 2
	for c in cards:
		var t := float(c) / cards
		var i := mini(int(t * (path.size() - 1)), path.size() - 2)
		var a: Vector3 = path[i]
		var b: Vector3 = path[i + 1]
		var dir := (b - a).normalized()
		var card_len := maxf(blen / cards * 1.75, 0.7)
		var start: Vector3 = a.lerp(b, fposmod(t * (path.size() - 1), 1.0))
		var width := clampf(card_len * 0.85, 0.5, 1.5)
		var side := dir.cross(Vector3.UP)
		if side.length_squared() < 1e-4:
			side = Vector3.RIGHT
		side = side.normalized()
		for rot: float in [0.0, 1.1, -1.1]:
			if detail <= 0.6 and rot < 0.0:
				continue
			var across := side.rotated(dir, rot + rng.randf_range(-0.2, 0.2)) * width * 0.5
			var nrm := (across.cross(dir)).normalized()
			if nrm.y < 0.0:
				nrm = -nrm
			nrm = nrm.lerp((start - Vector3(0, start.y, 0)).normalized(), 0.45).normalized()
			var col := Color(rng.randf_range(0.85, 1.1), rng.randf_range(0.9, 1.1), rng.randf_range(0.85, 1.05))
			var e := start + dir * card_len
			var p0 := start - across
			var p1 := e - across
			var p2 := e + across
			var p3 := start + across
			MeshKit.tri(st, p0, p1, p2, nrm, nrm, nrm, Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector3.UP, col)
			MeshKit.tri(st, p0, p2, p3, nrm, nrm, nrm, Vector2(0, 0), Vector2(1, 1), Vector2(0, 1), Vector3.UP, col)


# ---------------------------------------------------------------------------
# Low bush (used to fill gaps)
# ---------------------------------------------------------------------------
static func bush(seed_value: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var bark := MeshKit.new_st()
	var leaves := MeshKit.new_st()
	var ctx := {"rng": rng, "leaves": leaves, "crown": Vector3(0, 0.6, 0), "leaf_size": 0.9, "leaf_count": 22}
	for k in 4:
		var a := rng.randf() * TAU
		var tip := Vector3(cos(a) * 0.6, rng.randf_range(0.7, 1.3), sin(a) * 0.6)
		MeshKit.tube(bark, [Vector3.ZERO, tip * 0.5, tip], [0.05, 0.03, 0.01], 4)
		_leaf_cluster(ctx, tip, 0.9)
	_leaf_cluster(ctx, Vector3(0, 0.5, 0), 1.0)
	var mesh := MeshKit.commit(bark, _material("bark"), null, true)
	MeshKit.commit(leaves, _material("leaf"), mesh)
	return mesh


# ---------------------------------------------------------------------------
# Far LOD: trunk + opaque, lumpy crown volumes. One mesh holds a conifer AND a broadleaf tree
# (UV.x = 0 / 1); the instance custom alpha picks one (0.75 = conifer, 1.0 = broadleaf), so the
# whole distant forest of a chunk is a single draw call. COLOR.a = 0 marks trunk vertices.
# ---------------------------------------------------------------------------
## Upright card for TexKit.IMPOSTOR_SHADER (10 x 17 m so the culling bounds cover the billboard).
static func impostor_mesh() -> Mesh:
	var q := QuadMesh.new()
	q.size = Vector2(10.0, 17.0)
	q.center_offset = Vector3(0, 8.5, 0)
	q.material = TexKit.impostor_material()
	return q


static func far_forest_mesh(pine_seed: int, leaf_seed: int) -> ArrayMesh:
	var st := MeshKit.new_st()
	_far_pine(st, pine_seed)
	_far_leaf(st, leaf_seed)
	return MeshKit.commit(st, _material("far"))


static func _far_pine(st: SurfaceTool, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var height := rng.randf_range(12.0, 18.0)
	var mark := Vector2(0.0, 0.0)
	_far_trunk(st, height * 0.5, 0.3, mark)
	var base_h := rng.randf_range(2.0, 3.0)
	var layers := 4
	for k in layers:
		var f := float(k) / layers
		var y0 := lerpf(base_h, height * 0.78, f)
		var r := lerpf(3.4, 1.0, f) * (height / 15.0)
		var tip := y0 + lerpf(4.5, 3.2, f) * (height / 15.0)
		_cone(st, Vector3(0, y0, 0), r, tip - y0, 6, rng, Color(0.9 + 0.2 * f, 1.0, 0.9, 1.0), mark, false)
	_cone(st, Vector3(0, height * 0.82, 0), 0.8, height * 0.2, 5, rng, Color(1.1, 1.1, 1.0, 1.0), mark, false)


static func _far_leaf(st: SurfaceTool, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var mark := Vector2(1.0, 0.0)
	var h := rng.randf_range(8.0, 11.5)
	_far_trunk(st, h * 0.55, 0.28, mark)
	var centre := Vector3(0, h * 0.68, 0)
	for k in 3:
		var a := TAU * float(k) / 3.0 + rng.randf_range(-0.4, 0.4)
		var off := Vector3(cos(a) * 1.5, rng.randf_range(-0.5, 1.0), sin(a) * 1.5)
		var rad := Vector3(rng.randf_range(2.7, 3.4), rng.randf_range(2.2, 3.0), rng.randf_range(2.7, 3.4))
		var shade := rng.randf_range(0.85, 1.15)
		_blob(st, centre + off, rad, rng, Color(shade, shade, shade * 0.95, 1.0), centre, mark)


static func _far_trunk(st: SurfaceTool, height: float, radius: float, mark: Vector2) -> void:
	var seg := 4
	for i in seg:
		var a0 := TAU * float(i) / seg
		var a1 := TAU * float(i + 1) / seg
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		var p0 := d0 * radius + Vector3(0, -0.3, 0)
		var p1 := d1 * radius + Vector3(0, -0.3, 0)
		var q0 := d0 * radius * 0.55 + Vector3(0, height, 0)
		var q1 := d1 * radius * 0.55 + Vector3(0, height, 0)
		var col := Color(1, 1, 1, 0)
		MeshKit.tri(st, p0, p1, q1, d0, d1, d1, mark, mark, mark, (d0 + d1), col)
		MeshKit.tri(st, p0, q1, q0, d0, d1, d0, mark, mark, mark, (d0 + d1), col)


## Low-poly lumpy ellipsoid (6 x 4 segments) with normals pointing away from `crown_centre`.
static func _blob(st: SurfaceTool, c: Vector3, r: Vector3, rng: RandomNumberGenerator, col: Color, crown_centre: Vector3, mark := Vector2.ZERO) -> void:
	var seg := 5
	var rings := 3
	var pts: Array = []
	for j in rings + 1:
		var v := float(j) / rings
		var phi := PI * v
		var row: Array = []
		for i in seg:
			var th := TAU * float(i) / seg + (0.5 if j % 2 == 1 else 0.0)
			var n := Vector3(sin(phi) * cos(th), cos(phi), sin(phi) * sin(th))
			var jitter := 1.0 + rng.randf_range(-0.14, 0.14)
			row.append(c + Vector3(n.x * r.x, n.y * r.y, n.z * r.z) * jitter)
		pts.append(row)
	for j in rings:
		for i in seg:
			var i2 := (i + 1) % seg
			var a: Vector3 = pts[j][i]
			var b: Vector3 = pts[j][i2]
			var cc: Vector3 = pts[j + 1][i2]
			var d: Vector3 = pts[j + 1][i]
			var na := (a - crown_centre).normalized()
			var nb := (b - crown_centre).normalized()
			var nc := (cc - crown_centre).normalized()
			var nd := (d - crown_centre).normalized()
			var mid := (a + b + cc + d) * 0.25
			MeshKit.tri(st, a, b, cc, na, nb, nc, mark, mark, mark, mid - c, col)
			MeshKit.tri(st, a, cc, d, na, nc, nd, mark, mark, mark, mid - c, col)


static func _cone(st: SurfaceTool, base: Vector3, radius: float, height: float, seg: int, rng: RandomNumberGenerator, col: Color, mark := Vector2.ZERO, underside := true) -> void:
	var tip := base + Vector3(rng.randf_range(-0.1, 0.1), height, rng.randf_range(-0.1, 0.1))
	var ring: Array = []
	for i in seg:
		var a := TAU * float(i) / seg
		var r := radius * rng.randf_range(0.85, 1.12)
		ring.append(base + Vector3(cos(a) * r, rng.randf_range(-0.35, 0.1), sin(a) * r))
	for i in seg:
		var a: Vector3 = ring[i]
		var b: Vector3 = ring[(i + 1) % seg]
		var na := ((a - base).normalized() + Vector3.UP * 0.6).normalized()
		var nb := ((b - base).normalized() + Vector3.UP * 0.6).normalized()
		var out := ((a + b) * 0.5 - base).normalized() + Vector3.UP * 0.3
		MeshKit.tri(st, a, b, tip, na, nb, Vector3.UP, mark, mark, mark, out, col)
		if not underside:
			continue
		var under := Color(col.r * 0.7, col.g * 0.7, col.b * 0.7, col.a)
		MeshKit.tri(st, a, b, base + Vector3(0, -0.2, 0), Vector3.DOWN, Vector3.DOWN, Vector3.DOWN, mark, mark, mark, Vector3.DOWN, under)


# ---------------------------------------------------------------------------
# Undergrowth
# ---------------------------------------------------------------------------
## Small leafy shrub (0.4 – 0.9 m) made of a few leaf cards.
static func shrub(seed_value: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var bark := MeshKit.new_st()
	var leaves := MeshKit.new_st()
	var ctx := {"rng": rng, "leaves": leaves, "crown": Vector3(0, 0.25, 0), "leaf_size": 0.55, "leaf_count": 9}
	for k in 3:
		var a := rng.randf() * TAU
		var tip := Vector3(cos(a) * 0.25, rng.randf_range(0.35, 0.6), sin(a) * 0.25)
		MeshKit.tube(bark, [Vector3.ZERO, tip], [0.02, 0.008], 3, Vector2.ONE, Color.WHITE, false)
		_leaf_cluster(ctx, tip, 0.4)
	var mesh := MeshKit.commit(bark, _material("bark"))
	MeshKit.commit(leaves, _material("leaf"), mesh)
	return mesh


## Fern: arching fronds (bent strips with a frond texture).
static func fern(seed_value: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var st := MeshKit.new_st()
	var fronds := rng.randi_range(7, 10)
	for k in fronds:
		var a := TAU * float(k) / fronds + rng.randf_range(-0.25, 0.25)
		var dir := Vector3(cos(a), 0, sin(a))
		var side := Vector3(-dir.z, 0, dir.x)
		var length := rng.randf_range(0.7, 1.15)
		var lift := rng.randf_range(0.55, 0.9)
		var segs := 3
		var prev_l := Vector3.ZERO
		var prev_r := Vector3.ZERO
		for s in segs + 1:
			var t := float(s) / segs
			var p := dir * length * t + Vector3.UP * (lift * sin(t * PI * 0.75) * length - 0.35 * t * t * length)
			var w := 0.16 * (1.0 - t * 0.6) * length
			var l := p - side * w
			var r := p + side * w
			if s > 0:
				var n := (Vector3.UP * 0.8 + dir * 0.2).normalized()
				var v0 := float(s - 1) / segs
				var v1 := t
				MeshKit.tri(st, prev_l, prev_r, r, n, n, n, Vector2(0, v0), Vector2(1, v0), Vector2(1, v1), Vector3.UP, Color.WHITE)
				MeshKit.tri(st, prev_l, r, l, n, n, n, Vector2(0, v0), Vector2(1, v1), Vector2(0, v1), Vector3.UP, Color.WHITE)
			prev_l = l
			prev_r = r
	return MeshKit.commit(st, _material("fern"))


## Boulder: displaced, slightly flattened icosphere with a mossy rock material.
static func rock(seed_value: int) -> ArrayMesh:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = 0.9
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 14
	sphere.rings = 7
	var arr := sphere.get_mesh_arrays()
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var squash := Vector3(rng.randf_range(0.9, 1.3), rng.randf_range(0.55, 0.8), rng.randf_range(0.8, 1.1))
	for i in verts.size():
		var v := verts[i]
		var d := 1.0 + noise.get_noise_3dv(v * 1.3) * 0.35 + noise.get_noise_3dv(v * 4.0 + Vector3(9, 9, 9)) * 0.08
		v = v * d * squash
		# flat-ish underside that sinks into the ground
		v.y = maxf(v.y, -0.25)
		verts[i] = v
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = null
	arr[Mesh.ARRAY_TANGENT] = null
	var st := SurfaceTool.new()
	st.create_from_arrays(arr)
	st.generate_normals()
	st.set_material(_material("rock"))
	return st.commit()

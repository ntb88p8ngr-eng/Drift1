extends RefCounted
## Procedurally generated, high-detail trees.
## Every mesh has two surfaces: 0 = bark (tapered, bent branch tubes), 1 = foliage (alpha-tested leaf cards).
## "detail" 1.0 = close-up model (~6-8k triangles), ~0.35 = distant LOD.

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
			"needle":
				_mats[key] = TexKit.leaf_material("needle", Color(1.0, 1.0, 1.0))
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
		"leaf_size": 1.15 if detail > 0.6 else 2.1,
		"leaf_count": 15 if detail > 0.6 else 9,
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
	for s in segs:
		var bend := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.4, 0.5), rng.randf_range(-1, 1)) * (0.1 + depth * 0.07)
		d = (d + bend + Vector3.UP * (0.06 if depth > 0 else 0.03)).normalized()
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
		children = 7
	var az := rng.randf() * TAU
	for c in children:
		var t := rng.randf_range(0.38 if depth == 0 else 0.25, 0.97)
		var fi := t * segs
		var idx := mini(int(fi), segs - 1)
		var frac := fi - idx
		var pt: Vector3 = (pts[idx] as Vector3).lerp(pts[idx + 1], frac)
		var rad := lerpf(float(radii[idx]), float(radii[idx + 1]), frac)
		az += 2.39996 + rng.randf_range(-0.3, 0.3)
		var ref := Vector3.UP if absf(d.y) < 0.95 else Vector3.RIGHT
		var side := d.cross(ref).normalized().rotated(d, az)
		var angle := deg_to_rad(rng.randf_range(32.0, 58.0))
		var cdir := (d * cos(angle) + side * sin(angle)).normalized()
		var clen := length * rng.randf_range(0.55, 0.75) * (1.15 - t * 0.45)
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
		var card_len := maxf(blen / cards * 1.6, 0.6)
		var start: Vector3 = a.lerp(b, fposmod(t * (path.size() - 1), 1.0))
		var width := clampf(card_len * 0.75, 0.45, 1.3)
		var side := dir.cross(Vector3.UP)
		if side.length_squared() < 1e-4:
			side = Vector3.RIGHT
		side = side.normalized()
		for rot in [0.0, 1.1, -1.1]:
			if detail <= 0.6 and rot != 0.0:
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

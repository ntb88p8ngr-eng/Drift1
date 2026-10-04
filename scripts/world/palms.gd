extends Node3D
## Palms by the water (Utah): round the lake between the shore and the ring road, and along both
## river banks. Each palm is real geometry – a curved trunk ringed with leaf scars, a boot of old
## frond stubs under the crown, a dozen and a half arching fronds with leaflet pairs along them
## (green, the lowest ones drying yellow, a couple of dead ones hanging down), a coconut cluster –
## in a few variants, drawn as multimeshes, swaying in the wind. The trunks are solid.

const MeshKit = preload("res://scripts/util/mesh_kit.gd")

const VARIANTS := 4

var track
var terrain
var scenery
var count := 0
var _rng := RandomNumberGenerator.new()
var _spots: Array = []         # [Vector3, yaw, scale, variant]

const SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform float sway = 1.0;
void vertex() {
	// COLOR.a: how much of the wind this vertex gets (0 at the foot, 1 at the frond tips)
	vec3 wp = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float t = TIME * 1.3 + wp.x * 0.07 + wp.z * 0.05;
	float w = COLOR.a * sway;
	VERTEX.x += (sin(t) * 0.12 + sin(t * 2.7) * 0.04) * w;
	VERTEX.z += (cos(t * 0.8) * 0.09) * w;
	VERTEX.y += sin(t * 3.1 + VERTEX.x) * 0.03 * w * w;
}
void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.8;
	SPECULAR = 0.3;
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
}
"""


func build(p_track, p_terrain, p_scenery) -> void:
	track = p_track
	terrain = p_terrain
	scenery = p_scenery
	_rng.seed = 7741
	var water = track.water
	if water == null:
		return
	_lake_shore(water)
	_river_banks(water)
	if _spots.is_empty():
		return
	var mat := ShaderMaterial.new()
	mat.shader = Shader.new()
	mat.shader.code = SHADER
	var by_variant: Array = []
	for v in VARIANTS:
		by_variant.append([])
	for sp in _spots:
		(by_variant[sp[3]] as Array).append(sp)
	for v in VARIANTS:
		var list: Array = by_variant[v]
		if list.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = palm_mesh(1000 + v * 17)
		mm.instance_count = list.size()
		for k in list.size():
			var sp: Array = list[k]
			var b := Basis(Vector3.UP, float(sp[1])).scaled(Vector3.ONE * float(sp[2]))
			mm.set_instance_transform(k, Transform3D(b, sp[0]))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = mat
		mmi.visibility_range_end = 900.0
		add_child(mmi)
	# the trunks: solid poles
	var body := StaticBody3D.new()
	add_child(body)
	for sp in _spots:
		var cs := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = 0.3 * float(sp[2])
		cyl.height = 5.0 * float(sp[2])
		cs.shape = cyl
		cs.position = (sp[0] as Vector3) + Vector3(0, cyl.height * 0.5, 0)
		body.add_child(cs)
	count = _spots.size()
	print("PALMS: %d" % count)


## Between the lake's shore and the ring road, in loose groups.
func _lake_shore(water) -> void:
	var c: Vector2 = water.center
	var deg := 0.0
	while deg < 360.0:
		deg += _rng.randf_range(3.0, 8.0)
		if _rng.randf() < 0.18:
			deg += 10.0          # (a gap now and then)
		var a := deg_to_rad(deg)
		var r_in: float = water.lake_r_at(a) + 2.5
		var r_out: float = water.ring_r - water.ring_w * 0.5 - 2.5
		if r_out <= r_in:
			continue
		var r := _rng.randf_range(r_in, r_out)
		_try(Vector3(c.x + cos(a) * r, 0, c.y + sin(a) * r), water, 1.5)


## Along both rivers, a few metres up the banks on either side.
func _river_banks(water) -> void:
	for river in water.rivers:
		var pts: PackedVector2Array = river["pts"]
		var i := 2
		while i < pts.size() - 1:
			var p: Vector2 = pts[i]
			var dir: Vector2 = (pts[i + 1] - pts[i - 1]).normalized()
			var side := Vector2(-dir.y, dir.x)
			for sgn in [-1.0, 1.0]:
				if _rng.randf() < 0.55:
					var off: float = water.RIVER_W * 0.5 + _rng.randf_range(2.5, 7.0)
					var q: Vector2 = p + side * off * sgn + dir * _rng.randf_range(-3.0, 3.0)
					_try(Vector3(q.x, 0, q.y), water, 1.5)
			i += _rng.randi_range(2, 4)


func _try(p: Vector3, water, margin: float) -> void:
	if water.wet(p.x, p.z, margin):
		return
	if water.ring_band(p.x, p.z, 2.0):
		return
	if terrain.distance_to_road(p.x, p.z) < float(track.half_w) + 5.0:
		return
	if not scenery.free_at(p, 1.6, 0.0):
		return
	scenery.occupy(p, 1.2)
	p.y = terrain.height_at(p.x, p.z) - 0.15
	_spots.append([p, _rng.randf() * TAU, _rng.randf_range(0.8, 1.2), _rng.randi() % VARIANTS])


# ---------------------------------------------------------------------------
# The palm
# ---------------------------------------------------------------------------
## One palm (around 8–11 m), its foot at the origin.
static func palm_mesh(seed_value: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var height := rng.randf_range(7.5, 10.5)
	var lean := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized() * rng.randf_range(0.8, 2.2)
	var spine := func(t: float) -> Vector3:
		# leans out, then turns up again a little towards the crown
		return Vector3(0, t * height, 0) + lean * (t * t * (1.6 - 0.6 * t))
	# trunk: rings of leaf scars (a ridge every 22 cm), a thicker foot
	var rings := int(height / 0.11)
	var sides := 12
	var prev: PackedVector3Array
	var prev_c := Vector3.ZERO
	for k in rings + 1:
		var t := float(k) / rings
		var c: Vector3 = spine.call(t)
		var r := lerpf(0.3, 0.19, t) + 0.16 * pow(1.0 - minf(t * 4.0, 1.0), 2.0)
		var ridge := 1.0 + (0.07 if k % 2 == 0 else -0.02)
		var ring := PackedVector3Array()
		for sdx in sides:
			var a := TAU * sdx / sides
			ring.append(c + Vector3(cos(a), 0, sin(a)) * r * ridge)
		if k > 0:
			var shade := 0.85 + 0.15 * float(k % 2)
			var col := Color(0.42, 0.34, 0.25).lerp(Color(0.55, 0.5, 0.42), rng.randf() * 0.4) * shade
			col.a = t * t * 0.35
			for sdx in sides:
				var j := (sdx + 1) % sides
				var n0 := (prev[sdx] - prev_c).normalized()
				var n1 := (prev[j] - prev_c).normalized()
				_tri(st, prev[sdx], ring[sdx], ring[j], n0, n0, n1, col)
				_tri(st, prev[sdx], ring[j], prev[j], n0, n1, n1, col)
		prev = ring
		prev_c = c
	var top: Vector3 = spine.call(1.0)
	var up: Vector3 = (top - (spine.call(0.95) as Vector3)).normalized()
	# the boot: old frond stubs just under the crown
	for k in 14:
		var a := TAU * k / 14.0 + rng.randf() * 0.3
		var base := top - up * rng.randf_range(0.2, 0.9)
		var out := Vector3(cos(a), 0, sin(a))
		var tip := base + out * rng.randf_range(0.35, 0.6) + Vector3(0, rng.randf_range(-0.15, 0.25), 0)
		_blade(st, base, tip, out, 0.14, 0.06, Color(0.45, 0.36, 0.22, 0.4))
	# coconuts in a cluster under the crown
	for k in rng.randi_range(4, 8):
		var a := rng.randf() * TAU
		var cpos := top - up * 0.35 + Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.22, 0.38) - Vector3(0, rng.randf_range(0.0, 0.25), 0)
		_nut(st, cpos, rng.randf_range(0.11, 0.14), Color(0.35, 0.42, 0.12, 0.45) if rng.randf() < 0.6 else Color(0.45, 0.32, 0.15, 0.45))
	# the fronds
	var fronds := rng.randi_range(16, 20)
	for k in fronds:
		var a := TAU * k / fronds + rng.randf_range(-0.15, 0.15)
		var tier := k % 3
		var dead := rng.randf() < 0.1
		var rise: float = [0.75, 0.35, -0.1][tier] + rng.randf_range(-0.15, 0.15)
		if dead:
			rise = -1.2
		var length := rng.randf_range(3.6, 4.8) * (0.8 if dead else 1.0)
		var green := Color(0.2, 0.42, 0.12).lerp(Color(0.32, 0.5, 0.15), rng.randf())
		if tier == 2 and rng.randf() < 0.45:
			green = green.lerp(Color(0.62, 0.55, 0.22), rng.randf_range(0.3, 0.7))     # drying
		if dead:
			green = Color(0.5, 0.38, 0.2)
		_frond(st, rng, top + up * 0.1, Vector3(cos(a), 0, sin(a)), rise, length, green, dead)
	st.generate_tangents()
	return st.commit()


## A frond: the rachis arches out and droops; leaflet pairs along it, longest in the middle, hanging
## down in a V from the stem.
static func _frond(st: SurfaceTool, rng: RandomNumberGenerator, base: Vector3, out: Vector3, rise: float, length: float, col: Color, dead: bool) -> void:
	var n := 26
	var side := out.cross(Vector3.UP).normalized()
	var pts: Array = []
	for i in n + 1:
		var t := float(i) / n
		# out along the frond, up at first then curving down under its weight
		var y := rise * t * length * 0.6 - (1.7 if not dead else 0.6) * t * t * length * 0.45
		pts.append(base + out * (t * length * (0.95 if not dead else 0.55)) + Vector3(0, y, 0) - (Vector3(0, t * length * 0.7, 0) if dead else Vector3.ZERO))
	# the stem
	for i in n:
		var t := float(i) / n
		var c := col.darkened(0.15)
		c.a = 0.4 + 0.6 * t
		_blade(st, pts[i], pts[i + 1], side, 0.035 * (1.0 - t * 0.7), 0.03 * (1.0 - t * 0.7), c)
	# leaflets
	for i in range(2, n):
		var t := float(i) / n
		var p: Vector3 = pts[i]
		var along: Vector3 = ((pts[i + 1] as Vector3) - (pts[i - 1] as Vector3)).normalized()
		var ln := sin(t * PI) * 0.95 + 0.15
		if dead:
			ln *= 0.6
		for sgn in [-1.0, 1.0]:
			var droop := -0.55 - 0.35 * t + rng.randf_range(-0.1, 0.1)
			var dir: Vector3 = (side * sgn + along * 0.55 + Vector3(0, droop, 0)).normalized()
			if dead:
				dir = (along * 0.8 + side * sgn * 0.3 + Vector3(0, -0.6, 0)).normalized()
			var tip: Vector3 = p + dir * ln
			var c := col.lerp(col.lightened(0.15), rng.randf() * 0.5)
			c.a = 0.55 + 0.45 * t
			_leaflet(st, p, tip, along, 0.055 + 0.03 * sin(t * PI), c)


## A leaflet: a long narrow blade, widest a third of the way out, folded a little along its middle.
static func _leaflet(st: SurfaceTool, a: Vector3, b: Vector3, along: Vector3, w: float, col: Color) -> void:
	var d := (b - a)
	var wv := along.cross(d).normalized()
	if wv.length_squared() < 0.01:
		wv = Vector3.UP
	var flat := d.cross(wv).normalized()
	if flat.y < 0.0:
		flat = -flat
	var m := a + d * 0.35
	var fold := flat * w * 0.25
	var l := m - wv * w * 0.5 - fold
	var r := m + wv * w * 0.5 - fold
	_tri(st, a, l, m + flat * 0.004, flat, flat, flat, col)
	_tri(st, a, m + flat * 0.004, r, flat, flat, flat, col)
	_tri(st, l, b, m + flat * 0.004, flat, flat, flat, col)
	_tri(st, m + flat * 0.004, b, r, flat, flat, flat, col)


## A flat strip from a to b (width w0 at a, w1 at b), facing up-ish.
static func _blade(st: SurfaceTool, a: Vector3, b: Vector3, side: Vector3, w0: float, w1: float, col: Color) -> void:
	var d := (b - a).normalized()
	var s := side - d * side.dot(d)
	if s.length_squared() < 1e-4:
		s = d.cross(Vector3.UP)
	s = s.normalized()
	var nrm := s.cross(d).normalized()
	if nrm.y < 0.0:
		nrm = -nrm
	var a0 := a - s * w0
	var a1 := a + s * w0
	var b0 := b - s * w1
	var b1 := b + s * w1
	_tri(st, a0, b0, b1, nrm, nrm, nrm, col)
	_tri(st, a0, b1, a1, nrm, nrm, nrm, col)


## A coconut: a small faceted ball.
static func _nut(st: SurfaceTool, c: Vector3, r: float, col: Color) -> void:
	var lat := 5
	var lon := 8
	for i in lat:
		var t0 := PI * i / lat
		var t1 := PI * (i + 1) / lat
		for j in lon:
			var p0 := TAU * j / lon
			var p1 := TAU * (j + 1) / lon
			var v00 := Vector3(sin(t0) * cos(p0), cos(t0), sin(t0) * sin(p0))
			var v01 := Vector3(sin(t0) * cos(p1), cos(t0), sin(t0) * sin(p1))
			var v10 := Vector3(sin(t1) * cos(p0), cos(t1), sin(t1) * sin(p0))
			var v11 := Vector3(sin(t1) * cos(p1), cos(t1), sin(t1) * sin(p1))
			_tri(st, c + v00 * r, c + v10 * r, c + v11 * r, v00, v10, v11, col)
			_tri(st, c + v00 * r, c + v11 * r, c + v01 * r, v00, v11, v01, col)


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3, col: Color) -> void:
	st.set_color(col)
	st.set_uv(Vector2.ZERO)
	st.set_normal(na)
	st.add_vertex(a)
	st.set_normal(nb)
	st.add_vertex(b)
	st.set_normal(nc)
	st.add_vertex(c)

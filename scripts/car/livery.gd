extends RefCounted
## Stickers / decals on a car's paint (the paint booth in the main menu builds them, every car shows
## them in the game too). A design is a list of layers – later ones on top:
##   {"shape": id, "color": "#rrggbb", "side": "left"/"right"/"top"/"front"/"rear",
##    "p": -1..1 (along the car: front→rear, across on the front/rear), "h": 0..1 (up; across on top: -1..1),
##    "size": metres, "rot": degrees, "alpha": 0..1, "mirror": bool (also on the opposite side)}
## Each layer is a thin skin on the body's own triangles (not the wheels), wrapped round the panel
## where the straight-in ray from the chosen side lands.

const SIDES := ["left", "right", "top", "front", "rear"]
const SIDE_NAMES := {"left": "Links", "right": "Rechts", "top": "Oben (Haube, Dach)", "front": "Front", "rear": "Heck"}

## The shapes: [id, name] – the basic shapes, a tree, a unicorn, digits, letters, the graffiti pieces.
static func shapes() -> Array:
	var out: Array = [["circle", "Kreis"], ["ring", "Ring"], ["square", "Quadrat"], ["frame", "Rahmen"],
		["triangle", "Dreieck"], ["diamond", "Raute"], ["pentagon", "Fünfeck"], ["hexagon", "Sechseck"],
		["star", "Stern"], ["burst", "Zacken-Stern"], ["heart", "Herz"], ["cross", "Kreuz"], ["arrow", "Pfeil"],
		["chevron", "Winkel"], ["stripe", "Streifen"], ["stripes2", "Doppelstreifen"], ["bolt", "Blitz"],
		["flame", "Flamme"], ["moon", "Mond"], ["checker", "Zielflagge"], ["tree", "Baum"], ["unicorn", "Einhorn"]]
	for c in "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ":
		out.append(["ch_" + c, c])
	for k in range(1, 7):
		if ResourceLoader.exists(graffiti_path(k)):
			out.append(["graffiti_%d" % k, "Graffiti %d" % k])
	return out


static func graffiti_path(k: int) -> String:
	return "res://assets/main_menu/textures/Grafitti (%d).png" % k


const CACHE := "user://decals/"
static var _tex := {}


## The shape's picture (white on transparent; the graffiti in their own colours), null while it has
## not been drawn yet (decal_shapes.gd draws them into user://decals/).
static func texture(id: String) -> Texture2D:
	if _tex.has(id):
		return _tex[id]
	var t: Texture2D = null
	if id.begins_with("graffiti_"):
		var p := graffiti_path(int(id.trim_prefix("graffiti_")))
		if ResourceLoader.exists(p):
			t = load(p)
	elif FileAccess.file_exists(CACHE + id + ".png"):
		var img := Image.load_from_file(CACHE + id + ".png")
		if img:
			img.generate_mipmaps()
			t = ImageTexture.create_from_image(img)
	if t:
		_tex[id] = t
	return t


static func remember(id: String, img: Image) -> void:
	DirAccess.make_dir_recursive_absolute(CACHE)
	img.save_png(CACHE + id + ".png")
	var c := img.duplicate() as Image
	c.generate_mipmaps()
	_tex[id] = ImageTexture.create_from_image(c)


static func new_layer(shape: String, color: Color) -> Dictionary:
	return {"shape": shape, "color": "#" + color.to_html(false), "side": "left", "p": 0.0, "h": 0.5,
		"size": 0.7, "rot": 0.0, "alpha": 1.0, "mirror": true}


## The body's extent in its own space (without the wheels).
static func body_box(body: Node3D) -> AABB:
	var skip := _wheel_set(body)
	var box := AABB()
	var first := true
	var inv := body.global_transform.affine_inverse()
	for n in body.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null or skip.has(mi) or not mi.visible:
			continue
		var bb: AABB = (inv * mi.global_transform) * mi.get_aabb()
		box = bb if first else box.merge(bb)
		first = false
	return box


static func _wheel_set(body: Node3D) -> Dictionary:
	var out := {}
	var wn = body.get("wheel_nodes")
	if wn is Array:
		for w in wn:
			for n in (w[0] as Node3D).find_children("*", "MeshInstance3D", true, false):
				out[n] = true
	return out


## Puts the design on the body (replacing the last one). Every sticker is a thin skin cut out of the
## body's own triangles round the spot it sits on and unrolled from there – so it follows the panel's
## curves like real vinyl instead of being projected flat.
static func apply(body: Node3D, layers: Array) -> void:
	var old := body.get_node_or_null("Livery")
	if old:
		body.remove_child(old)
		old.queue_free()
	if layers.is_empty():
		return
	var surf := surface(body)
	var box: AABB = surf["box"]
	var root := Node3D.new()
	root.name = "Livery"
	body.add_child(root)
	var k := 0
	for l in layers:
		var tex := texture(str(l.get("shape", "")))
		if tex == null:
			continue
		var col := Color.from_string(str(l.get("color", "#ffffff")), Color.WHITE)
		col.a = clampf(float(l.get("alpha", 1.0)), 0.0, 1.0)
		var mat := ShaderMaterial.new()
		mat.shader = _shader()
		mat.set_shader_parameter("tex", tex)
		mat.set_shader_parameter("tint", col)
		mat.render_priority = clampi(k, 0, 120)
		var aspect := float(tex.get_width()) / maxf(float(tex.get_height()), 1.0)
		var s := float(l.get("size", 0.7))
		for pl in placements(l):
			var f := frame(pl[0], pl[1], pl[2], box)
			var hit = ray_surface(surf, f[0], f[1], box.size.length())
			if hit == null:
				continue
			var mesh := sticker_mesh(surf, hit[0], hit[1], f[2], float(pl[3]), s, s / aspect, k)
			if mesh == null:
				continue
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			mi.material_override = mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(mi)
		k += 1


static var _sh: Shader


static func _shader() -> Shader:
	if _sh == null:
		_sh = Shader.new()
		_sh.code = """shader_type spatial;
render_mode cull_disabled, depth_draw_never;
uniform sampler2D tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec4 tint : source_color = vec4(1.0);
void fragment() {
	if (UV.x < 0.0 || UV.x > 1.0 || UV.y < 0.0 || UV.y > 1.0) discard;
	vec4 c = texture(tex, UV) * tint;
	ALBEDO = c.rgb;
	ALPHA = c.a;
	ROUGHNESS = 0.32;
	SPECULAR = 0.5;
}
"""
	return _sh


## Where a layer goes: [[side, p, h, rot], …] – one, or two when mirrored.
static func placements(l: Dictionary) -> Array:
	var side := str(l.get("side", "left"))
	var p := float(l.get("p", 0.0))
	var h := float(l.get("h", 0.5))
	var r := float(l.get("rot", 0.0))
	var out: Array = [[side, p, h, r]]
	if bool(l.get("mirror", false)):
		match side:
			"left":
				out.append(["right", p, h, -r])
			"right":
				out.append(["left", p, h, -r])
			"top":
				out.append(["top", p, -h, -r])
			"front", "rear":
				out.append([side, -p, h, -r])
	return out


# --- the body's surface ----------------------------------------------------------------------------
const CELL := 0.2


## The body's triangles in its own space (no wheels) with a grid to find them fast – built once per
## body: {"v": verts (3 per triangle), "n": vertex normals, "grid": {Vector3i: PackedInt32Array}, "box"}.
static func surface(body: Node3D) -> Dictionary:
	if body.has_meta("livery_surf"):
		return body.get_meta("livery_surf")
	var skip := _wheel_set(body)
	var inv := body.global_transform.affine_inverse()
	var v := PackedVector3Array()
	var nr := PackedVector3Array()
	for n in body.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null or skip.has(mi) or not mi.is_visible_in_tree() or mi.get_parent().name == "Livery":
			continue
		var xf: Transform3D = inv * mi.global_transform
		var nb := xf.basis.inverse().transposed()
		for si in mi.mesh.get_surface_count():
			if mi.mesh.surface_get_primitive_type(si) != Mesh.PRIMITIVE_TRIANGLES:
				continue
			var arr := mi.mesh.surface_get_arrays(si)
			var pos: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var nor = arr[Mesh.ARRAY_NORMAL]
			var idx = arr[Mesh.ARRAY_INDEX]
			var has_n: bool = nor is PackedVector3Array and (nor as PackedVector3Array).size() == pos.size()
			var count: int = (idx as PackedInt32Array).size() if idx is PackedInt32Array and (idx as PackedInt32Array).size() > 0 else pos.size()
			var use_idx: bool = idx is PackedInt32Array and (idx as PackedInt32Array).size() > 0
			for t in range(0, count - 2, 3):
				var ia: int = idx[t] if use_idx else t
				var ib: int = idx[t + 1] if use_idx else t + 1
				var ic: int = idx[t + 2] if use_idx else t + 2
				var a: Vector3 = xf * pos[ia]
				var b: Vector3 = xf * pos[ib]
				var c: Vector3 = xf * pos[ic]
				var fnm := (b - a).cross(c - a)
				if fnm.length_squared() < 1e-14:
					continue
				v.append(a); v.append(b); v.append(c)
				if has_n:
					nr.append((nb * nor[ia]).normalized())
					nr.append((nb * nor[ib]).normalized())
					nr.append((nb * nor[ic]).normalized())
				else:
					var fn := fnm.normalized()
					nr.append(fn); nr.append(fn); nr.append(fn)
	var grid := {}
	var box := AABB()
	for t in v.size() / 3:
		var tb := AABB(v[t * 3], Vector3.ZERO).expand(v[t * 3 + 1]).expand(v[t * 3 + 2])
		box = tb if t == 0 else box.merge(tb)
		var c0 := Vector3i((tb.position / CELL).floor())
		var c1 := Vector3i((tb.end / CELL).floor())
		for x in range(c0.x, c1.x + 1):
			for y in range(c0.y, c1.y + 1):
				for z in range(c0.z, c1.z + 1):
					var key := Vector3i(x, y, z)
					if not grid.has(key):
						grid[key] = PackedInt32Array()
					(grid[key] as PackedInt32Array).append(t)
	var out := {"v": v, "n": nr, "grid": grid, "box": box}
	body.set_meta("livery_surf", out)
	return out


## The first body triangle along a ray (body space): [point, surface normal facing the ray], or null.
static func ray_surface(surf: Dictionary, from: Vector3, dir: Vector3, max_len: float):
	var box: AABB = surf["box"]
	var grid: Dictionary = surf["grid"]
	var v: PackedVector3Array = surf["v"]
	var nr: PackedVector3Array = surf["n"]
	dir = dir.normalized()
	var start = box.grow(0.01).intersects_ray(from, dir)
	if start == null:
		if not box.has_point(from):
			return null
		start = from
	var o: Vector3 = start
	var seen := {}
	var best := INF
	var best_t := -1
	var step := CELL * 0.35
	var d := 0.0
	while d <= max_len:
		var key := Vector3i(((o + dir * d) / CELL).floor())
		if grid.has(key) and not seen.has(key):
			seen[key] = true
			for t in grid[key]:
				var h = Geometry3D.ray_intersects_triangle(from, dir, v[t * 3], v[t * 3 + 1], v[t * 3 + 2])
				if h != null:
					var dist := from.distance_to(h)
					if dist < best:
						best = dist
						best_t = t
		if best_t >= 0 and from.distance_to(o + dir * d) > best + CELL:
			break
		d += step
	if best_t < 0:
		return null
	var p: Vector3 = from + dir * best
	var a := v[best_t * 3]
	var b := v[best_t * 3 + 1]
	var c := v[best_t * 3 + 2]
	var w := _bary(p, a, b, c)
	var n := (nr[best_t * 3] * w.x + nr[best_t * 3 + 1] * w.y + nr[best_t * 3 + 2] * w.z)
	if n.length_squared() < 1e-8:
		n = (b - a).cross(c - a)
	n = n.normalized()
	if n.dot(dir) > 0.0:
		n = -n
	return [p, n]


static func _bary(p: Vector3, a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	var v0 := b - a
	var v1 := c - a
	var v2 := p - a
	var d00 := v0.dot(v0)
	var d01 := v0.dot(v1)
	var d11 := v1.dot(v1)
	var d20 := v2.dot(v0)
	var d21 := v2.dot(v1)
	var den := d00 * d11 - d01 * d01
	if absf(den) < 1e-12:
		return Vector3(1, 0, 0)
	var y := (d11 * d20 - d01 * d21) / den
	var z := (d00 * d21 - d01 * d20) / den
	return Vector3(1.0 - y - z, y, z)


## The sticker as a skin on the body: the triangles round `at` that face the same way, each vertex
## laid out by its distance from `at` (the sticker's centre) so it wraps over curves without
## stretching; a hair above the paint. `up` is the image's up before turning by `rot_deg`.
static func sticker_mesh(surf: Dictionary, at: Vector3, n: Vector3, up: Vector3, rot_deg: float, w: float, h: float, k: int) -> ArrayMesh:
	var v: PackedVector3Array = surf["v"]
	var nr: PackedVector3Array = surf["n"]
	var grid: Dictionary = surf["grid"]
	var u := up - n * n.dot(up)
	if u.length_squared() < 1e-4:
		u = Vector3(0, 0, -1) - n * n.dot(Vector3(0, 0, -1))
	u = u.normalized()
	var r := (-n).cross(u).normalized()
	var rb := Basis(n, deg_to_rad(rot_deg))
	r = rb * r
	u = rb * u
	var rad := 0.5 * sqrt(w * w + h * h) + 0.02
	var c0 := Vector3i(((at - Vector3.ONE * rad) / CELL).floor())
	var c1 := Vector3i(((at + Vector3.ONE * rad) / CELL).floor())
	var seen := {}
	var lift := 0.0015 + 0.0004 * float(k % 8)
	var pv := PackedVector3Array()
	var pn := PackedVector3Array()
	var puv := PackedVector2Array()
	for x in range(c0.x, c1.x + 1):
		for y in range(c0.y, c1.y + 1):
			for z in range(c0.z, c1.z + 1):
				var key := Vector3i(x, y, z)
				if not grid.has(key):
					continue
				for t in grid[key]:
					if seen.has(t):
						continue
					seen[t] = true
					var a := v[t * 3]
					var b := v[t * 3 + 1]
					var c := v[t * 3 + 2]
					var fn := (b - a).cross(c - a).normalized()
					var navg := nr[t * 3] + nr[t * 3 + 1] + nr[t * 3 + 2]
					if fn.dot(navg) < 0.0:
						fn = -fn
					if fn.dot(n) < 0.2:
						continue          # (facing elsewhere: the other side, inner panels)
					var tb := AABB(a, Vector3.ZERO).expand(b).expand(c)
					var q := at.clamp(tb.position, tb.end)
					if q.distance_to(at) > rad:
						continue
					var uvs: Array = []
					var deep := false
					var lo := Vector2(INF, INF)
					var hi := Vector2(-INF, -INF)
					for pt in [a, b, c]:
						var o: Vector3 = pt - at
						var px := o.dot(r)
						var py := o.dot(u)
						var pz := o.dot(n)
						var rho := sqrt(px * px + py * py)
						if pz < -(0.03 + 0.45 * rho):
							deep = true          # (well below the surface here: inside the car)
							break
						if rho > 1e-5:
							var sc := sqrt(rho * rho + pz * pz) / rho
							px *= sc
							py *= sc
						var uv := Vector2(0.5 + px / w, 0.5 - py / h)
						uvs.append(uv)
						lo = lo.min(uv)
						hi = hi.max(uv)
					if deep or hi.x < 0.0 or hi.y < 0.0 or lo.x > 1.0 or lo.y > 1.0:
						continue
					for j in 3:
						var vn := nr[t * 3 + j]
						if vn.dot(fn) < 0.0:
							vn = -vn
						pv.append(v[t * 3 + j] + vn * lift)
						pn.append(vn)
						puv.append(uvs[j])
	if pv.is_empty():
		return null
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = pv
	arr[Mesh.ARRAY_NORMAL] = pn
	arr[Mesh.ARRAY_TEX_UV] = puv
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


## The car's surface under a ray (body space) as [side, p, h]: the side that faces it most and the
## spot on that side whose straight-in ray lands there. null when the ray misses the car.
static func pick_surface(body: Node3D, from: Vector3, dir: Vector3):
	var surf := surface(body)
	var box: AABB = surf["box"]
	var hit = ray_surface(surf, from, dir, from.distance_to(box.get_center()) + box.size.length())
	if hit == null:
		return null
	var p: Vector3 = hit[0]
	var n: Vector3 = hit[1]
	var best := "left"
	var bd := -INF
	for side in SIDES:
		var d: Vector3 = frame(side, 0.0, 0.5, box)[1]
		if -d.dot(n) > bd:
			bd = -d.dot(n)
			best = side
	var fd: Vector3 = frame(best, 0.0, 0.5, box)[1]
	var got = pick(best, box, p - fd * 5.0, fd)
	if not (got is Array):
		return null
	return [best, clampf(float(got[0]), -1.0, 1.0), clampf(float(got[1]), -1.0 if best == "top" else 0.0, 1.0)]


## The surface frame of a side: [origin on the plane, direction into the car, image up, depth].
static func frame(side: String, p: float, h: float, box: AABB) -> Array:
	var a := box.position
	var e := box.end
	var zf := lerpf(a.z, e.z, (p + 1.0) * 0.5)
	var y := lerpf(a.y, e.y, clampf(h, 0.0, 1.0))
	match side:
		"right":
			return [Vector3(e.x + 0.05, y, zf), Vector3(-1, 0, 0), Vector3.UP, box.size.x * 0.4]
		"top":
			return [Vector3(lerpf(a.x, e.x, (h + 1.0) * 0.5), e.y + 0.05, zf), Vector3(0, -1, 0), Vector3(0, 0, -1), box.size.y * 0.8]
		"front":
			return [Vector3(lerpf(e.x, a.x, (p + 1.0) * 0.5), y, a.z - 0.05), Vector3(0, 0, 1), Vector3.UP, box.size.z * 0.25]
		"rear":
			return [Vector3(lerpf(a.x, e.x, (p + 1.0) * 0.5), y, e.z + 0.05), Vector3(0, 0, -1), Vector3.UP, box.size.z * 0.25]
	return [Vector3(a.x - 0.05, y, zf), Vector3(1, 0, 0), Vector3.UP, box.size.x * 0.4]


## The point on a side's plane under a ray (body space) as [p, h], or null.
static func pick(side: String, box: AABB, from: Vector3, dir: Vector3):
	var f := frame(side, 0.0, 0.5, box)
	var n: Vector3 = -(f[1] as Vector3)
	var hit = Plane(n, f[0]).intersects_ray(from, dir)
	if hit == null:
		return null
	var q: Vector3 = hit
	var a := box.position
	var e := box.end
	match side:
		"left", "right":
			return [inverse_lerp(a.z, e.z, q.z) * 2.0 - 1.0, inverse_lerp(a.y, e.y, q.y)]
		"top":
			return [inverse_lerp(a.z, e.z, q.z) * 2.0 - 1.0, inverse_lerp(a.x, e.x, q.x) * 2.0 - 1.0]
		"front":
			return [inverse_lerp(e.x, a.x, q.x) * 2.0 - 1.0, inverse_lerp(a.y, e.y, q.y)]
		"rear":
			return [inverse_lerp(a.x, e.x, q.x) * 2.0 - 1.0, inverse_lerp(a.y, e.y, q.y)]
	return null


## The surface of the car under a ray (body space): [side, p, h] of the nearest side plane it hits
## inside the car's outline, or null.
static func pick_any(box: AABB, from: Vector3, dir: Vector3):
	var best: Variant = null
	var best_d := INF
	for side in SIDES:
		var f := frame(side, 0.0, 0.5, box)
		var d: Vector3 = f[1]
		if d.dot(dir) <= 0.05:
			continue          # (a side facing away from the camera)
		var hit = Plane(-d, f[0]).intersects_ray(from, dir)
		if hit == null:
			continue
		var got: Variant = pick(side, box, from, dir)
		if not (got is Array):
			continue
		var ph: Array = got
		if absf(float(ph[0])) > 1.0 or float(ph[1]) > 1.0 or float(ph[1]) < (-1.0 if side == "top" else 0.0):
			continue
		var dist := from.distance_to(hit as Vector3)
		if dist < best_d:
			best_d = dist
			best = [side, float(ph[0]), float(ph[1])]
	return best


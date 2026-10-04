extends RefCounted
## Stickers / decals on a car's paint (the paint booth in the main menu builds them, every car shows
## them in the game too). A design is a list of layers – later ones on top:
##   {"shape": id, "color": "#rrggbb", "side": "left"/"right"/"top"/"front"/"rear",
##    "p": -1..1 (along the car: front→rear, across on the front/rear), "h": 0..1 (up; across on top: -1..1),
##    "size": metres, "rot": degrees, "alpha": 0..1, "mirror": bool (also on the opposite side)}
## Each layer is a Decal that only touches the car's body (its own render layer, not the wheels or
## the ground), projected onto the chosen side.

const LAYER_BIT := 1 << 19          # render layer 20: the car body for the decals
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


## Puts the design on the body (replacing the last one).
static func apply(body: Node3D, layers: Array) -> void:
	var old := body.get_node_or_null("Livery")
	if old:
		body.remove_child(old)
		old.queue_free()
	if layers.is_empty():
		return
	var skip := _wheel_set(body)
	for n in body.find_children("*", "MeshInstance3D", true, false):
		if not skip.has(n):
			(n as MeshInstance3D).layers |= LAYER_BIT
	var box := body_box(body)
	var root := Node3D.new()
	root.name = "Livery"
	body.add_child(root)
	var k := 0
	for l in layers:
		var tex := texture(str(l.get("shape", "")))
		if tex == null:
			continue
		for d in placements(l, box):
			var dc := Decal.new()
			dc.texture_albedo = tex
			var col := Color.from_string(str(l.get("color", "#ffffff")), Color.WHITE)
			col.a = clampf(float(l.get("alpha", 1.0)), 0.0, 1.0)
			dc.modulate = col
			dc.albedo_mix = 1.0
			dc.normal_fade = 0.3
			dc.upper_fade = 0.05
			dc.lower_fade = 0.05
			dc.cull_mask = LAYER_BIT
			dc.sorting_offset = float(k) * 0.01
			var aspect := float(tex.get_width()) / maxf(float(tex.get_height()), 1.0)
			var s := float(l.get("size", 0.7))
			dc.size = Vector3(s, d[2], s / aspect)
			dc.transform = d[0]
			root.add_child(dc)
		k += 1


## Where a layer goes: [[Transform3D, …, depth], …] in body space – one, or two when mirrored.
static func placements(l: Dictionary, box: AABB) -> Array:
	var side := str(l.get("side", "left"))
	var p := float(l.get("p", 0.0))
	var h := float(l.get("h", 0.5))
	var out: Array = [_place(side, p, h, float(l.get("rot", 0.0)), box)]
	if bool(l.get("mirror", false)):
		match side:
			"left":
				out.append(_place("right", p, h, -float(l.get("rot", 0.0)), box))
			"right":
				out.append(_place("left", p, h, -float(l.get("rot", 0.0)), box))
			"top":
				out.append(_place("top", p, -h, -float(l.get("rot", 0.0)), box))
			"front", "rear":
				out.append(_place(side, -p, h, -float(l.get("rot", 0.0)), box))
	return out


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


static func _place(side: String, p: float, h: float, rot_deg: float, box: AABB) -> Array:
	var f := frame(side, p, h, box)
	var d: Vector3 = f[1]
	var up: Vector3 = f[2]
	var depth: float = f[3]
	# the decal projects along its -Y; its texture lies in X (right) and Z (down) as seen from outside
	var r := d.cross(up).normalized()
	var basis := Basis(r, -d, r.cross(-d))
	basis = Basis(-d, deg_to_rad(rot_deg)) * basis
	var origin: Vector3 = f[0] + d * depth * 0.5
	return [Transform3D(basis, origin), side, depth]


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


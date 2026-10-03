extends RefCounted
## A custom map: one of the tracks plus everything changed in the world editor – reshaped ground,
## moved / scaled / removed scenery, placed objects, new roads, water, and uploaded 3D models (their
## GLB files packed in, compressed). Saved as one compressed file (.dmap): JSON inside zstd.
## apply() puts it all into a freshly built world (in the editor and when racing on the map).

const AssetLib = preload("res://scripts/editor/asset_lib.gd")
const RoadBuilder = preload("res://scripts/editor/road_builder.gd")
const TexKit = preload("res://scripts/util/tex_kit.gd")
const MMUtil = preload("res://scripts/util/mm_util.gd")

const MAGIC := "DMAP"
const VERSION := 1
const MAP_DIR := "user://maps"

var base_track := "ridge"
var map_name := "Meine Karte"
var heights := {}        # terrain vertex index -> height
var edits := {}          # scenery instance key ("x|z" of its original spot, 0.1 m) -> Array (12 floats: new transform) or null (removed)
var objects: Array = []  # {asset, xf: 12 floats}
var roads: Array = []    # {pts: [[x,y,z]...], width, surface, flatten}
var water: Array = []    # {c: [x, z], size: [w, d], level}
var models := {}         # model id -> {name, data: base64 of the zstd-compressed GLB, size}
var nodes := {}          # game objects with a body (props, signs, stacks …) by their original spot (node_key) -> 12 floats or null (removed)


# ---------------------------------------------------------------------------
# Files
# ---------------------------------------------------------------------------
func to_dict() -> Dictionary:
	var hk := PackedInt32Array()
	var hv := PackedFloat32Array()
	for k in heights:
		hk.append(int(k))
		hv.append(float(heights[k]))
	return {"version": VERSION, "base_track": base_track, "name": map_name,
		"height_idx": Marshalls.raw_to_base64(hk.to_byte_array()), "height_val": Marshalls.raw_to_base64(hv.to_byte_array()),
		"edits": edits, "objects": objects, "roads": roads, "water": water, "models": models, "nodes": nodes}


static func from_dict(d: Dictionary):
	var m = load("res://scripts/editor/map_data.gd").new()
	m.base_track = str(d.get("base_track", "ridge"))
	m.map_name = str(d.get("name", "Karte"))
	var hk := Marshalls.base64_to_raw(str(d.get("height_idx", ""))).to_int32_array()
	var hv := Marshalls.base64_to_raw(str(d.get("height_val", ""))).to_float32_array()
	for i in mini(hk.size(), hv.size()):
		m.heights[hk[i]] = hv[i]
	m.edits = d.get("edits", {})
	m.objects = d.get("objects", [])
	m.roads = d.get("roads", [])
	m.water = d.get("water", [])
	m.models = d.get("models", {})
	m.nodes = d.get("nodes", {})
	return m


func save(path: String) -> bool:
	var raw := JSON.stringify(to_dict()).to_utf8_buffer()
	var packed := raw.compress(FileAccess.COMPRESSION_ZSTD)
	if path.begins_with("user://"):
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_buffer(MAGIC.to_utf8_buffer())
	f.store_32(VERSION)
	f.store_32(raw.size())
	f.store_buffer(packed)
	f.close()
	return true


static func load_file(path: String):
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	if f.get_buffer(4).get_string_from_utf8() != MAGIC:
		return null
	f.get_32()
	var size := f.get_32()
	var packed := f.get_buffer(f.get_length() - f.get_position())
	var raw := packed.decompress(size, FileAccess.COMPRESSION_ZSTD)
	var d = JSON.parse_string(raw.get_string_from_utf8())
	if not (d is Dictionary):
		return null
	return from_dict(d)


## The saved maps: [[path, name, base track]].
static func list_maps() -> Array:
	var out: Array = []
	var dir := DirAccess.open(MAP_DIR)
	if dir == null:
		return out
	for fn in dir.get_files():
		if not fn.ends_with(".dmap"):
			continue
		var m = load_file(MAP_DIR.path_join(fn))
		if m:
			out.append([MAP_DIR.path_join(fn), m.map_name, m.base_track])
	return out


static func safe_file_name(s: String) -> String:
	var out := ""
	for ch in s.strip_edges():
		out += ch if (ch.is_valid_identifier() or ch.is_valid_int() or ch == "-") else "_"
	return out if out != "" else "karte"


# ---------------------------------------------------------------------------
# Uploaded models
# ---------------------------------------------------------------------------
## Packs a GLB (bytes) into the map; returns its id ("model:<id>" for placing).
func add_model(file_name: String, bytes: PackedByteArray) -> String:
	var id := "%08x" % (hash(bytes) & 0x7fffffff)
	models[id] = {"name": file_name, "size": bytes.size(),
		"data": Marshalls.raw_to_base64(bytes.compress(FileAccess.COMPRESSION_ZSTD))}
	register_model(id)
	return id


## Builds the template node of a packed model (once), for AssetLib.make("model:<id>").
func register_model(id: String) -> bool:
	if AssetLib.uploaded.has(id):
		return true
	var e: Dictionary = models.get(id, {})
	if e.is_empty():
		return false
	var bytes := Marshalls.base64_to_raw(str(e["data"])).decompress(int(e["size"]), FileAccess.COMPRESSION_ZSTD)
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_buffer(bytes, "", state) != OK:
		return false
	var scene := doc.generate_scene(state)
	if scene == null or not (scene is Node3D):
		return false
	AssetLib.uploaded[id] = scene
	return true


# ---------------------------------------------------------------------------
# Into the world
# ---------------------------------------------------------------------------
## Puts the map into a built world. Returns the node holding the placed things.
func apply(world) -> Node3D:
	var holder := Node3D.new()
	holder.name = "MapContent"
	world.add_child(holder)
	# the ground
	var terrain = world.terrain
	if not heights.is_empty():
		var hs: PackedFloat32Array = terrain.heights
		var lo := Vector2i(1 << 30, 1 << 30)
		var hi := Vector2i(-1, -1)
		for k in heights:
			var idx := int(k)
			if idx < 0 or idx >= hs.size():
				continue
			hs[idx] = float(heights[k])
			var p := Vector2i(idx % int(terrain.nx), idx / int(terrain.nx))
			lo = Vector2i(mini(lo.x, p.x), mini(lo.y, p.y))
			hi = Vector2i(maxi(hi.x, p.x), maxi(hi.y, p.y))
		terrain.heights = hs
		if hi.x >= 0:
			terrain.rebuild_region(lo.x, lo.y, hi.x, hi.y)
			terrain.refresh_collision()
	# scenery copies (pasted in the editor) are built from the scenery's own meshes
	AssetLib.register_scenery(world.scenery)
	# scenery that was moved or removed
	if not edits.is_empty():
		apply_edits(world.scenery, edits)
	if not nodes.is_empty():
		apply_nodes(world, nodes)
	for id in models:
		register_model(str(id))
	for o in objects:
		place_object(holder, str(o["asset"]), arr_to_xf(o["xf"]))
	for r in roads:
		RoadBuilder.build(holder, world, r)
	for w in water:
		add_water(holder, w)
	return holder


## A placed object: its visuals and a solid box around them.
static func place_object(holder: Node3D, asset: String, xf: Transform3D) -> Node3D:
	var n := AssetLib.make(asset)
	if n == null:
		return null
	var body := StaticBody3D.new()
	body.name = "Obj"
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("asset", asset)
	body.add_child(n)
	holder.add_child(body)
	body.global_transform = xf
	var bb := AssetLib.bounds(n)
	if bb.size.length() > 0.05:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = bb.size.max(Vector3(0.05, 0.05, 0.05))
		cs.shape = bs
		cs.position = bb.get_center()
		body.add_child(cs)
	return body


static func add_water(holder: Node3D, w: Dictionary) -> MeshInstance3D:
	var pm := PlaneMesh.new()
	var sz: Array = w.get("size", [40, 40])
	pm.size = Vector2(float(sz[0]), float(sz[1]))
	pm.subdivide_width = 8
	pm.subdivide_depth = 8
	var mi := MeshInstance3D.new()
	mi.name = "Water"
	mi.mesh = pm
	mi.material_override = TexKit.water_material()
	mi.set_meta("water", w)
	holder.add_child(mi)
	var c: Array = w.get("c", [0, 0])
	mi.global_position = Vector3(float(c[0]), float(w.get("level", 0.0)), float(c[1]))
	return mi


## Scenery instances (trees, rocks, props – every LOD of them) moved or removed, found by their
## original spot.
static func apply_edits(scenery, e: Dictionary) -> void:
	for r in scenery._ranged:
		var mmi = r[0]
		if not (mmi is MultiMeshInstance3D) or not is_instance_valid(mmi):
			continue
		var mm: MultiMesh = (mmi as MultiMeshInstance3D).multimesh
		if mm == null:
			continue
		var mxf: Transform3D = (mmi as Node3D).global_transform
		var inv := mxf.affine_inverse()
		var changes := {}
		for i in mm.instance_count:
			var lxf := MMUtil.get_xf(mm, i)
			var key := spot_key(mxf * lxf.origin)
			if not e.has(key):
				continue
			var v = e[key]
			if v == null:
				# removed: shrunk to nothing where it stood
				changes[i] = Transform3D(lxf.basis.scaled(Vector3.ONE * 0.0001), lxf.origin)
			else:
				changes[i] = inv * arr_to_xf(v)
		MMUtil.set_many(mm, changes)


## Game objects with a body, found by where they were built.
static func apply_nodes(world, e: Dictionary) -> void:
	for c in world.find_children("*", "CollisionObject3D", true, false):
		var n := c as Node3D
		var key := node_key(n.global_position)
		if not e.has(key):
			continue
		n.set_meta("edit_orig", key)
		n.set_meta("orig_pos", n.global_position)
		var v = e[key]
		if v == null:
			n.visible = false
			n.process_mode = Node.PROCESS_MODE_DISABLED
		else:
			if n is RigidBody3D:
				(n as RigidBody3D).freeze = true
			n.global_transform = arr_to_xf(v)


static func node_key(p: Vector3) -> String:
	return "%d|%d|%d" % [int(round(p.x * 10.0)), int(round(p.y * 10.0)), int(round(p.z * 10.0))]


static func spot_key(p: Vector3) -> String:
	return "%d|%d" % [int(round(p.x * 10.0)), int(round(p.z * 10.0))]


static func xf_to_arr(xf: Transform3D) -> Array:
	var b := xf.basis
	return [b.x.x, b.x.y, b.x.z, b.y.x, b.y.y, b.y.z, b.z.x, b.z.y, b.z.z, xf.origin.x, xf.origin.y, xf.origin.z]


static func arr_to_xf(a: Array) -> Transform3D:
	return Transform3D(Basis(Vector3(a[0], a[1], a[2]), Vector3(a[3], a[4], a[5]), Vector3(a[6], a[7], a[8])), Vector3(a[9], a[10], a[11]))

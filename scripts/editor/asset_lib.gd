extends RefCounted
## Everything the world editor can place: the game's props, trees and plants, the camp models, the
## traffic cars, simple building blocks, and models the player uploaded (kept in the map file).
## make() returns a Node3D with the visuals; the editor/map adds a collider from its bounds.

const Props = preload("res://scripts/world/prop_meshes.gd")
const TreeFactory = preload("res://scripts/world/tree_factory.gd")
const MeshKit = preload("res://scripts/util/mesh_kit.gd")
const TexKit = preload("res://scripts/util/tex_kit.gd")
const GlbKit = preload("res://scripts/util/glb_kit.gd")

## [id, name, group]
const ASSETS := [
	["tree_pine", "Fichte", "Pflanzen"], ["tree_oak", "Eiche", "Pflanzen"], ["tree_leaf", "Laubbaum", "Pflanzen"],
	["tree_autumn", "Herbstbaum", "Pflanzen"], ["tree_sakura", "Kirschbaum", "Pflanzen"], ["bush", "Busch", "Pflanzen"],
	["shrub", "Strauch", "Pflanzen"], ["fern", "Farn", "Pflanzen"], ["rock", "Fels", "Pflanzen"],
	["prop:tyre_stack", "Reifenstapel", "Strecke"], ["prop:cone", "Pylone", "Strecke"], ["prop:hay_bale", "Strohballen", "Strecke"],
	["prop:banner_tower", "Bannerturm", "Strecke"], ["prop:billboard_frame", "Werbetafel", "Strecke"], ["prop:fence", "Zaun", "Strecke"],
	["prop:bench", "Bank", "Stadt"], ["prop:bin", "Mülleimer", "Stadt"], ["prop:wheelie_bin", "Mülltonne", "Stadt"],
	["prop:post", "Pfosten", "Stadt"], ["prop:bus_shelter", "Bushaltestelle", "Stadt"], ["prop:mailbox", "Briefkasten", "Stadt"],
	["prop:hydrant", "Hydrant", "Stadt"], ["prop:bicycle", "Fahrrad", "Stadt"], ["prop:garden_lamp", "Gartenlampe", "Stadt"],
	["prop:planter", "Pflanzkübel", "Stadt"], ["prop:pot_red", "Blumentopf", "Stadt"],
	["prop:car_sedan", "Limousine (geparkt)", "Autos"], ["prop:car_hatch", "Kompaktwagen (geparkt)", "Autos"],
	["prop:car_kei", "Kei-Car (geparkt)", "Autos"], ["prop:car_van", "Transporter (geparkt)", "Autos"],
	["glb:res://assets/cars/traffic/camry.glb", "Toyota Camry", "Autos"],
	["glb:res://assets/cars/traffic/impreza.glb", "Subaru Impreza", "Autos"],
	["glb:res://assets/cars/traffic/civic.glb", "Honda Civic", "Autos"],
	["glb:res://assets/props/camp/01_sprout_campervan.glb", "Campervan", "Camping"],
	["glb:res://assets/props/camp/02_sundrift_overcab.glb", "Wohnmobil", "Camping"],
	["glb:res://assets/props/camp/03_ridgeline_expedition.glb", "Expeditionsmobil", "Camping"],
	["glb:res://assets/props/camp/04_horizon_coach.glb", "Reisemobil", "Camping"],
	["glb:res://assets/props/camp/01_acorn_teardrop.glb", "Teardrop-Wohnwagen", "Camping"],
	["glb:res://assets/props/camp/02_rambler_retro.glb", "Retro-Wohnwagen", "Camping"],
	["glb:res://assets/props/camp/03_summit_offroad.glb", "Offroad-Wohnwagen", "Camping"],
	["glb:res://assets/props/camp/04_longline_family.glb", "Familien-Wohnwagen", "Camping"],
	["glb:res://assets/props/camp/01_small_a_frame.glb", "Zelt (A-Frame)", "Camping"],
	["glb:res://assets/props/camp/02_medium_dome.glb", "Kuppelzelt", "Camping"],
	["glb:res://assets/props/camp/03_large_family_tunnel.glb", "Tunnelzelt", "Camping"],
	["glb:res://assets/props/camp/04_tiny_wedge_bivy.glb", "Biwakzelt", "Camping"],
	["glb:res://assets/props/camp/05_extra_large_bell.glb", "Glockenzelt", "Camping"],
	["block:box", "Block", "Bausteine"], ["block:wall", "Mauer", "Bausteine"], ["block:ramp", "Rampe", "Bausteine"],
	["block:pillar", "Säule", "Bausteine"], ["block:container", "Container", "Bausteine"], ["block:barrier", "Betonleitwand", "Bausteine"],
	["mark:arrow", "Pfeil geradeaus", "Markierungen"], ["mark:arrow_left", "Pfeil links", "Markierungen"],
	["mark:arrow_right", "Pfeil rechts", "Markierungen"], ["mark:arrow_straight_left", "Pfeil geradeaus + links", "Markierungen"],
	["mark:arrow_straight_right", "Pfeil geradeaus + rechts", "Markierungen"], ["mark:zebra", "Zebrastreifen", "Markierungen"],
	["mark:stop_line", "Haltelinie", "Markierungen"], ["mark:line", "Linie (durchgezogen)", "Markierungen"],
	["mark:line_dashed", "Linie (gestrichelt)", "Markierungen"], ["mark:diamond", "Raute", "Markierungen"],
	["mark:yield", "Haifischzähne (Vorfahrt achten)", "Markierungen"], ["mark:grid_slot", "Startplatz", "Markierungen"],
	["mark:checker", "Start / Ziel (Karo)", "Markierungen"], ["mark:hatch", "Sperrfläche (gelb)", "Markierungen"],
]


## Street markings: flat paint on the road – cars drive over them (no collision for the cars,
## the editor still picks them: own layer).
const MARK_LAYER := 1 << 19


static func is_marking(id: String) -> bool:
	return id.begins_with("mark:")

static var _mesh_cache := {}
## Uploaded models: id -> PackedScene-like generated Node (template), set by the map / editor.
static var uploaded := {}
## Scenery meshes by their MultiMeshInstance name ("Trees_hi", "Prop_bench" …): "scn:<name>#<colour>"
## places a copy of a tree / rock / prop of the track itself (pasted in the editor).
static var scenery_meshes := {}
static var city                # city.gd of the map (copies of its buildings: "cbld:<description>")


static func register_scenery(scenery) -> void:
	if scenery == null:
		return
	for r in scenery._ranged:
		var mmi = r[0]
		if mmi is MultiMeshInstance3D and is_instance_valid(mmi) and (mmi as MultiMeshInstance3D).multimesh:
			var nm := str(mmi.get_meta("label", str(mmi.name)))
			if nm != "" and not nm.begins_with("@") and not scenery_meshes.has(nm):
				scenery_meshes[nm] = (mmi as MultiMeshInstance3D).multimesh.mesh


static func name_of(id: String) -> String:
	if id.begins_with("scn:"):
		return "Kopie " + id.substr(4).split("#")[0]
	for a in ASSETS:
		if a[0] == id:
			return a[1]
	if id.begins_with("model:"):
		return "Modell " + id.substr(6, 8)
	return id


## The visual of asset `id` (no collider), or null.
static func make(id: String) -> Node3D:
	if id.begins_with("cprop:"):
		if city == null or not is_instance_valid(city) or city.lamps == null:
			return null
		return city.lamps.make_prop_node(id.substr(6))
	if id.begins_with("cbld:"):
		if city == null or not is_instance_valid(city):
			return null
		var desc = JSON.parse_string(id.substr(5))
		return city.make_building_node(desc) if desc is Dictionary else null
	if id.begins_with("model:"):
		var tpl = uploaded.get(id.substr(6))
		if tpl == null:
			return null
		return (tpl as Node3D).duplicate()
	if id.begins_with("scn:"):
		var parts := id.substr(4).split("#")
		var sm: Mesh = scenery_meshes.get(parts[0])
		if sm == null:
			return null
		var smm := MultiMesh.new()
		smm.transform_format = MultiMesh.TRANSFORM_3D
		smm.use_custom_data = true
		smm.mesh = sm
		smm.instance_count = 1
		smm.set_instance_transform(0, Transform3D.IDENTITY)
		smm.set_instance_custom_data(0, Color.from_string(parts[1], Color(1, 1, 1, 1)) if parts.size() > 1 else Color(1, 1, 1, 1))
		var sroot := Node3D.new()
		var smmi := MultiMeshInstance3D.new()
		smmi.multimesh = smm
		sroot.add_child(smmi)
		return sroot
	var mesh := mesh_of(id)
	if mesh == null:
		return null
	var root := Node3D.new()
	if id.begins_with("prop:"):
		# the prop shader takes its tint from the instance data: a one-instance MultiMesh
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = mesh
		mm.instance_count = 1
		mm.set_instance_transform(0, Transform3D.IDENTITY)
		mm.set_instance_custom_data(0, Color(1, 1, 1, 1))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		root.add_child(mmi)
	else:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		if id.begins_with("mark:"):
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	return root


static func mesh_of(id: String) -> Mesh:
	if _mesh_cache.has(id):
		return _mesh_cache[id]
	var m: Mesh = null
	if id.begins_with("prop:"):
		m = Props.get_mesh(id.substr(5))
	elif id.begins_with("glb:"):
		m = GlbKit.merged(id.substr(4))
	elif id.begins_with("block:"):
		m = _block(id.substr(6))
	elif id.begins_with("mark:"):
		m = _marking(id.substr(5))
	else:
		match id:
			"tree_pine":
				m = TreeFactory.pine(17, 1.0)
			"tree_oak":
				m = TreeFactory.oak(23, 1.0)
			"tree_leaf":
				m = TreeFactory.deciduous(31, 1.0)
			"tree_autumn":
				m = TreeFactory.deciduous(37, 1.0, true)
			"tree_sakura":
				m = TreeFactory.sakura(41, 1.0)
			"bush":
				m = TreeFactory.bush(43)
			"shrub":
				m = TreeFactory.shrub(47)
			"fern":
				m = TreeFactory.fern(53)
			"rock":
				m = TreeFactory.rock(59)
	_mesh_cache[id] = m
	return m


static func _block(kind: String) -> Mesh:
	var st := MeshKit.new_st()
	var conc := Color(0.62, 0.62, 0.6)
	match kind:
		"box":
			MeshKit.box(st, Transform3D(Basis.IDENTITY, Vector3(0, 1, 0)), Vector3(2, 2, 2), conc)
		"wall":
			MeshKit.box(st, Transform3D(Basis.IDENTITY, Vector3(0, 1.5, 0)), Vector3(8, 3, 0.4), Color(0.7, 0.66, 0.6))
		"pillar":
			MeshKit.box(st, Transform3D(Basis.IDENTITY, Vector3(0, 3, 0)), Vector3(0.8, 6, 0.8), conc)
		"container":
			MeshKit.box(st, Transform3D(Basis.IDENTITY, Vector3(0, 1.3, 0)), Vector3(2.44, 2.59, 6.06), Color(0.1, 0.3, 0.55))
		"barrier":
			MeshKit.box(st, Transform3D(Basis.IDENTITY, Vector3(0, 0.4, 0)), Vector3(0.6, 0.8, 4.0), Color(0.75, 0.75, 0.73))
			MeshKit.box(st, Transform3D(Basis.IDENTITY, Vector3(0, 0.9, 0)), Vector3(0.25, 0.25, 4.0), Color(0.75, 0.75, 0.73))
		"ramp":
			# a wedge 4 m wide, 6 m long, 1.2 m high at its far end (-Z)
			var a := Vector3(-2, 0, 3)
			var b := Vector3(2, 0, 3)
			var c := Vector3(2, 1.2, -3)
			var d := Vector3(-2, 1.2, -3)
			var e := Vector3(2, 0, -3)
			var f := Vector3(-2, 0, -3)
			MeshKit.quad(st, a, b, c, d, Vector3(0, 0.98, -0.2), Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, conc)
			MeshKit.quad(st, f, e, c, d, Vector3(0, 0, -1), Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, conc)
			MeshKit.tri(st, a, f, d, Vector3(-1, 0, 0), Vector3(-1, 0, 0), Vector3(-1, 0, 0), Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector3(-1, 0, 0), conc)
			MeshKit.tri(st, b, e, c, Vector3(1, 0, 0), Vector3(1, 0, 0), Vector3(1, 0, 0), Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector3(1, 0, 0), conc)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.8
	return MeshKit.commit(st, mat)


## A street marking lying on the ground (2 cm up), forward = -Z, white paint (yellow hatching).
static func _marking(kind: String) -> Mesh:
	var st := MeshKit.new_st()
	var y := 0.02
	var white := Color(0.93, 0.93, 0.9)
	var rect := func(x0: float, z0: float, x1: float, z1: float, col: Color) -> void:
		MeshKit.quad(st, Vector3(x0, y, z0), Vector3(x1, y, z0), Vector3(x1, y, z1), Vector3(x0, y, z1), Vector3.UP,
			Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, col)
	var tri := func(a: Vector2, b: Vector2, c: Vector2, col: Color) -> void:
		MeshKit.tri(st, Vector3(a.x, y, a.y), Vector3(b.x, y, b.y), Vector3(c.x, y, c.y), Vector3.UP, Vector3.UP, Vector3.UP,
			Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector3.UP, col)
	# a bar from a to b (2D, x/z), width w
	var bar := func(a: Vector2, b: Vector2, w: float, col: Color) -> void:
		var d := (b - a).normalized()
		var n := Vector2(-d.y, d.x) * w * 0.5
		MeshKit.quad(st, Vector3(a.x + n.x, y, a.y + n.y), Vector3(b.x + n.x, y, b.y + n.y), Vector3(b.x - n.x, y, b.y - n.y), Vector3(a.x - n.x, y, a.y - n.y),
			Vector3.UP, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, col)
	# an arrow head at tip, pointing along dir
	var head := func(tip: Vector2, dir: Vector2, l: float, w: float) -> void:
		var d := dir.normalized()
		var n := Vector2(-d.y, d.x)
		tri.call(tip, tip - d * l + n * w * 0.5, tip - d * l - n * w * 0.5, white)
	match kind:
		"arrow":
			bar.call(Vector2(0, 2.5), Vector2(0, -1.0), 0.3, white)
			head.call(Vector2(0, -2.5), Vector2(0, -1), 1.5, 1.1)
		"arrow_left", "arrow_right":
			var s := -1.0 if kind == "arrow_left" else 1.0
			bar.call(Vector2(0, 2.5), Vector2(0, -0.6), 0.3, white)
			bar.call(Vector2(0, -0.45), Vector2(s * 0.9, -0.45), 0.3, white)
			head.call(Vector2(s * 2.0, -0.45), Vector2(s, 0), 1.1, 1.0)
		"arrow_straight_left", "arrow_straight_right":
			var s2 := -1.0 if kind == "arrow_straight_left" else 1.0
			bar.call(Vector2(0, 2.5), Vector2(0, -1.0), 0.3, white)
			head.call(Vector2(0, -2.5), Vector2(0, -1), 1.5, 1.1)
			bar.call(Vector2(0, 0.6), Vector2(s2 * 0.9, 0.6), 0.3, white)
			head.call(Vector2(s2 * 2.0, 0.6), Vector2(s2, 0), 1.1, 1.0)
		"zebra":
			# 4 m across the road (x), bars 0.5 m wide, 3 m long (z)
			for k in 5:
				var x := -2.0 + 0.25 + k * 0.9
				rect.call(x - 0.25, -1.5, x + 0.25, 1.5, white)
		"stop_line":
			rect.call(-2.0, -0.2, 2.0, 0.2, white)
		"line":
			rect.call(-0.075, -3.0, 0.075, 3.0, white)
		"line_dashed":
			for k in 3:
				var z := -4.5 + k * 3.0
				rect.call(-0.075, z, 0.075, z + 1.5, white)
		"diamond":
			tri.call(Vector2(0, -2.0), Vector2(0.6, 0), Vector2(-0.6, 0), white)
			tri.call(Vector2(0, 2.0), Vector2(-0.6, 0), Vector2(0.6, 0), white)
			tri.call(Vector2(0, -1.6), Vector2(-0.35, 0), Vector2(0.35, 0), Color(0.1, 0.1, 0.11))
			tri.call(Vector2(0, 1.6), Vector2(0.35, 0), Vector2(-0.35, 0), Color(0.1, 0.1, 0.11))
		"yield":
			# a row of triangles across the road, pointing at the cars coming (+Z)
			for k in 6:
				var x2 := -2.25 + k * 0.9
				tri.call(Vector2(x2 - 0.3, -0.3), Vector2(x2 + 0.3, -0.3), Vector2(x2, 0.3), white)
		"grid_slot":
			rect.call(-1.2, -2.6, 1.2, -2.45, white)
			rect.call(-1.2, -2.6, -1.05, 0.0, white)
			rect.call(1.05, -2.6, 1.2, 0.0, white)
		"checker":
			# 8 m across, two rows of squares
			for row in 2:
				for k in 16:
					var dark := (k + row) % 2 == 0
					rect.call(-4.0 + k * 0.5, -0.5 + row * 0.5, -3.5 + k * 0.5, row * 0.5, Color(0.08, 0.08, 0.09) if dark else white)
		"hatch":
			var yel := Color(0.95, 0.75, 0.12)
			rect.call(-2.0, -2.0, 2.0, -1.85, yel)
			rect.call(-2.0, 1.85, 2.0, 2.0, yel)
			rect.call(-2.0, -2.0, -1.85, 2.0, yel)
			rect.call(1.85, -2.0, 2.0, 2.0, yel)
			for k in 5:
				var o := -2.0 + k * 1.0
				bar.call(Vector2(maxf(o, -1.9), -1.9 + maxf(o, -1.9) - o), Vector2(minf(o + 3.8, 1.9), 1.9 - (o + 3.8 - minf(o + 3.8, 1.9))), 0.15, yel)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.7
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return MeshKit.commit(st, mat)


## Bounds of a made asset (its meshes, in its own space).
static func bounds(n: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for c in n.find_children("*", "GeometryInstance3D", true, false):
		var g := c as GeometryInstance3D
		var bb: AABB = g.get_aabb()
		if g is MultiMeshInstance3D and (g as MultiMeshInstance3D).multimesh:
			bb = (g as MultiMeshInstance3D).multimesh.get_aabb()
		var rel := n.global_transform.affine_inverse() * g.global_transform if n.is_inside_tree() else g.transform
		bb = rel * bb
		out = bb if first else out.merge(bb)
		first = false
	return out

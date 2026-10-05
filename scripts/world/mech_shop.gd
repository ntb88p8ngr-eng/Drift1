extends RefCounted
## A mechanic's workshop with a parts shop next door, for every map: a hall with a big open roller
## door (a car fits in), an engine stand with a V8 in the middle of the room, a two-post lift, benches,
## shelves, trolleys and tyres – the props of the main menu workshop (assets/props/workshop_kit) – and
## a shop with a glass front, counter and shelves. Local frame: the front faces -Z (the road).
##   hall x -11 … 3, shop x 3 … 11, z -6 … 6; apron in front down to z -12.

const MeshKit = preload("res://scripts/util/mesh_kit.gd")
const TexKit = preload("res://scripts/util/tex_kit.gd")
const Colliders = preload("res://scripts/util/colliders.gd")
const KIT := "res://assets/props/workshop_kit/"

const HALL_H := 5.2
const SHOP_H := 4.0
const T := 0.25          # wall thickness

var root: Node3D
var _st := {}            # material key -> SurfaceTool
var _mats := {}


func _init() -> void:
	_mats["wall"] = _vc(0.9, 0.0)
	_mats["metal"] = _vc(0.45, 0.6)
	_mats["floor"] = _vc(0.6, 0.0)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.12, 0.16, 0.2, 0.35)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.05
	glass.metallic = 0.4
	_mats["glass"] = glass
	_mats["light"] = TexKit.emissive(Color(1.0, 0.97, 0.9), 2.5)


static func _vc(rough: float, metal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = rough
	m.metallic = metal
	return m


## Builds it under `parent` at `xf` (ground level, front towards -Z).
func build(parent: Node3D, xf: Transform3D) -> Node3D:
	root = Node3D.new()
	root.name = "MechanicShop"
	parent.add_child(root)
	root.global_transform = xf
	var plaster := Color(0.78, 0.76, 0.72)
	var cladding := Color(0.22, 0.24, 0.27)
	var concrete := Color(0.3, 0.3, 0.3)
	# floor, apron
	_box("floor", Vector3(0, -0.05, 0), Vector3(22.4, 0.18, 12.4), concrete, true)
	_box("floor", Vector3(0, -0.06, -9.0), Vector3(22.4, 0.16, 6.0), Color(0.36, 0.36, 0.37), true)
	# yellow lines marking the way in
	for x in [-9.4, -2.6]:
		_box("floor", Vector3(x, 0.03, -9.0), Vector3(0.14, 0.012, 6.0), Color(0.85, 0.7, 0.1), false)
	# the hall: walls round it, the door opening in front
	_wall(Vector3(-11, 0, -6), Vector3(-11, 0, 6), HALL_H, cladding)
	_wall(Vector3(-11, 0, 6), Vector3(3, 0, 6), HALL_H, cladding)
	_wall(Vector3(-11, 0, -6), Vector3(-9.6, 0, -6), HALL_H, cladding)
	_wall(Vector3(-2.4, 0, -6), Vector3(3, 0, -6), HALL_H, cladding)
	_box("wall", Vector3(-6.0, 4.8, -6.0), Vector3(7.2, 0.8, T), cladding, true)
	# the partition to the shop with a door
	_wall(Vector3(3, 0, -6), Vector3(3, 0, 2.6), HALL_H, plaster)
	_wall(Vector3(3, 0, 4.0), Vector3(3, 0, 6), HALL_H, plaster)
	_box("wall", Vector3(3, 3.7, 3.3), Vector3(T, 3.0, 1.4), plaster, true)
	# the shop: walls, a glass front with a door
	_wall(Vector3(3, 0, 6), Vector3(11, 0, 6), SHOP_H, plaster)
	_wall(Vector3(11, 0, -6), Vector3(11, 0, 6), SHOP_H, plaster)
	_box("wall", Vector3(7, 0.3, -6), Vector3(8, 0.6, T), Color(0.3, 0.3, 0.32), false)
	Colliders.add_box(root, root.global_transform * Transform3D(Basis.IDENTITY, Vector3(7.8, 1.5, -6)), Vector3(6.4, 3.0, T))
	_box("wall", Vector3(7, 3.6, -6), Vector3(8.2, 0.8, T + 0.1), Color(0.12, 0.12, 0.14), false)
	_box("glass", Vector3(7.75, 1.9, -6), Vector3(6.5, 2.6, 0.04), Color.WHITE, false)
	_box("glass", Vector3(3.95, 1.55, -6.3), Vector3(1.0, 2.5, 0.04), Color.WHITE, false)      # the door, ajar
	for x in [3.4, 4.5, 5.6, 7.3, 9.0, 10.7]:
		_box("metal", Vector3(x, 1.9, -6), Vector3(0.08, 2.7, 0.12), Color(0.15, 0.15, 0.16), false)
	# roofs with a parapet
	_box("wall", Vector3(-4, HALL_H + 0.12, 0), Vector3(14.6, 0.25, 12.6), Color(0.3, 0.3, 0.3), false)
	_box("wall", Vector3(7, SHOP_H + 0.12, 0), Vector3(8.4, 0.25, 12.6), Color(0.3, 0.3, 0.3), false)
	_box("metal", Vector3(-4, HALL_H + 0.45, -6.2), Vector3(14.6, 0.5, 0.15), Color(0.6, 0.08, 0.08), false)
	# the rolled-up door's drum above the opening, the door frame posts
	_box("metal", Vector3(-6.0, 4.62, -5.55), Vector3(7.4, 0.55, 0.55), Color(0.35, 0.36, 0.38), false)
	for x in [-9.6, -2.4]:
		_box("metal", Vector3(x, 2.2, -5.85), Vector3(0.14, 4.4, 0.2), Color(0.85, 0.65, 0.08), false)
	# ceiling lights
	for z in [-3.0, 0.5, 4.0]:
		for x in [-8.5, -4.5, -0.5]:
			_box("light", Vector3(x, HALL_H - 0.1, z), Vector3(1.6, 0.06, 0.25), Color.WHITE, false)
	for z in [-3.0, 1.0, 4.5]:
		_box("light", Vector3(7, SHOP_H - 0.1, z), Vector3(2.5, 0.06, 0.4), Color.WHITE, false)
	_commit()
	for p in [[Vector3(-6, 4.4, -1), 11.0], [Vector3(-6, 4.4, 3.5), 11.0], [Vector3(7, 3.4, 0), 8.0]]:
		var l := OmniLight3D.new()
		l.position = p[0]
		l.omni_range = p[1]
		l.light_energy = 0.9
		l.light_color = Color(1.0, 0.95, 0.88)
		root.add_child(l)
	_signs()
	_v8_on_stand(Vector3(-5.0, 0, -0.6))
	_props()
	return root


# --- geometry --------------------------------------------------------------------------------------
func _box(key: String, c: Vector3, size: Vector3, col: Color, solid: bool) -> void:
	if not _st.has(key):
		_st[key] = MeshKit.new_st()
	MeshKit.box(_st[key], Transform3D(Basis.IDENTITY, c), size, col)
	if solid:
		Colliders.add_box(root, root.global_transform * Transform3D(Basis.IDENTITY, c), size)


## A straight wall on the ground from a to b (axis-aligned).
func _wall(a: Vector3, b: Vector3, h: float, col: Color) -> void:
	var c := (a + b) * 0.5 + Vector3(0, h * 0.5, 0)
	var size := Vector3(absf(b.x - a.x) + T, h, absf(b.z - a.z) + T)
	_box("wall", c, size, col, true)


func _commit() -> void:
	for key in _st:
		var st: SurfaceTool = _st[key]
		st.generate_normals()
		var mi := MeshKit.mesh_instance(MeshKit.commit(st, _mats[key]))
		mi.visibility_range_end = 900.0
		root.add_child(mi)
	_st.clear()


func _signs() -> void:
	for s in [["MIDNIGHT GARAGE", Vector3(-6.0, HALL_H + 0.45, -6.32), Color(1.0, 0.2, 0.25), 0.012],
			["TUNING · PARTS · SERVICE", Vector3(7.0, 3.6, -6.2), Color(0.3, 0.9, 1.0), 0.0075]]:
		var l := Label3D.new()
		l.text = s[0]
		l.position = s[1]
		l.rotation = Vector3(0, PI, 0)
		l.modulate = s[2]
		l.outline_modulate = Color(0, 0, 0, 0.8)
		l.font_size = 64
		l.outline_size = 10
		l.pixel_size = s[3]
		l.double_sided = false
		root.add_child(l)


# --- the engine on its stand -----------------------------------------------------------------------
## A V8 on a rolling engine stand: block, two banks with heads and red valve covers, intake with the
## throttle body, headers on both sides, oil pan, pulleys and belt at the front, the flywheel bolted to
## the stand's head plate. The crank runs along x.
func _v8_on_stand(at: Vector3) -> void:
	var st := MeshKit.new_st()
	var steel := Color(0.12, 0.13, 0.15)
	var red := Color(0.75, 0.08, 0.06)
	var alu := Color(0.62, 0.63, 0.65)
	var cast := Color(0.32, 0.33, 0.35)
	var y := 0.95                  # crank height
	var o := at
	# stand: an upright on a T foot with castors, the arm and the head plate
	MeshKit.box(st, Transform3D(Basis.IDENTITY, o + Vector3(-0.95, 0.06, 0)), Vector3(0.1, 0.1, 1.1), red)
	MeshKit.box(st, Transform3D(Basis.IDENTITY, o + Vector3(-0.45, 0.06, 0)), Vector3(1.0, 0.1, 0.1), red)
	for p in [Vector3(-0.95, 0.04, 0.5), Vector3(-0.95, 0.04, -0.5), Vector3(0.05, 0.04, 0)]:
		MeshKit.box(st, Transform3D(Basis.IDENTITY, o + p), Vector3(0.09, 0.08, 0.09), steel)
	MeshKit.box(st, Transform3D(Basis.IDENTITY, o + Vector3(-0.9, y * 0.5 + 0.05, 0)), Vector3(0.1, y, 0.1), red)
	MeshKit.box(st, Transform3D(Basis.IDENTITY, o + Vector3(-0.78, y, 0)), Vector3(0.22, 0.12, 0.12), red)
	MeshKit.box(st, Transform3D(Basis.IDENTITY, o + Vector3(-0.66, y, 0)), Vector3(0.03, 0.42, 0.42), steel)
	for a in 4:
		var d := Vector3(0, cos(a * PI * 0.5 + PI * 0.25), sin(a * PI * 0.5 + PI * 0.25)) * 0.2
		MeshKit.box(st, Transform3D(Basis.IDENTITY, o + Vector3(-0.6, y, 0) + d), Vector3(0.12, 0.04, 0.04), steel)
	# flywheel and bellhousing face
	_cyl_x(st, o + Vector3(-0.53, y, 0), 0.19, 0.04, Color(0.4, 0.4, 0.42))
	# the block, banks and heads
	var bx := 0.0
	MeshKit.box(st, Transform3D(Basis.IDENTITY, o + Vector3(bx, y, 0)), Vector3(0.95, 0.36, 0.42), cast)
	MeshKit.box(st, Transform3D(Basis.IDENTITY, o + Vector3(bx, y - 0.27, 0)), Vector3(0.85, 0.18, 0.36), Color(0.1, 0.1, 0.11))   # oil pan
	for side in [-1.0, 1.0]:
		var b := Basis(Vector3.RIGHT, side * 0.78)
		var c: Vector3 = o + Vector3(bx, y + 0.2, side * 0.2)
		MeshKit.box(st, Transform3D(b, c), Vector3(0.92, 0.22, 0.24), cast)               # bank
		MeshKit.box(st, Transform3D(b, c + b * Vector3(0, 0.15, 0)), Vector3(0.94, 0.09, 0.27), alu)        # head
		MeshKit.box(st, Transform3D(b, c + b * Vector3(0, 0.24, 0)), Vector3(0.86, 0.09, 0.22), red)        # valve cover
		for k in 4:
			MeshKit.box(st, Transform3D(b, c + b * Vector3(-0.3 + k * 0.2, 0.29, 0)), Vector3(0.03, 0.02, 0.18), Color(0.9, 0.9, 0.9))
		# headers: four primaries per side down and out into a collector
		for k in 4:
			var px := bx - 0.33 + k * 0.22
			var start: Vector3 = o + Vector3(px, y + 0.18, side * 0.42)
			var pts := [start, start + Vector3(0, -0.08, side * 0.12), o + Vector3(px * 0.5, y - 0.2, side * 0.5), o + Vector3(0.05, y - 0.38, side * 0.42)]
			MeshKit.tube(st, pts, [0.025, 0.025, 0.026, 0.03], 7, Vector2(1, 1), Color(0.55, 0.42, 0.3))
	# intake: the plenum between the banks, runners, throttle body at the front
	MeshKit.box(st, Transform3D(Basis.IDENTITY, o + Vector3(bx, y + 0.42, 0)), Vector3(0.7, 0.14, 0.24), alu)
	for k in 4:
		for side in [-1.0, 1.0]:
			MeshKit.box(st, Transform3D(Basis(Vector3.RIGHT, -side * 0.6), o + Vector3(bx - 0.3 + k * 0.2, y + 0.36, side * 0.13)), Vector3(0.06, 0.05, 0.16), alu)
	_cyl_x(st, o + Vector3(bx + 0.42, y + 0.44, 0), 0.07, 0.1, Color(0.2, 0.2, 0.22))
	# front: timing cover, crank pulley, water pump, alternator and the belt
	MeshKit.box(st, Transform3D(Basis.IDENTITY, o + Vector3(0.5, y + 0.05, 0)), Vector3(0.05, 0.4, 0.3), alu)
	_cyl_x(st, o + Vector3(0.56, y - 0.12, 0), 0.1, 0.05, steel)
	_cyl_x(st, o + Vector3(0.56, y + 0.12, 0), 0.07, 0.05, steel)
	_cyl_x(st, o + Vector3(0.56, y + 0.22, 0.24), 0.06, 0.05, steel)
	_cyl_x(st, o + Vector3(0.6, y + 0.18, 0.24), 0.09, 0.14, alu)                    # alternator
	MeshKit.tube(st, [o + Vector3(0.6, y - 0.22, 0), o + Vector3(0.6, y + 0.02, 0.1), o + Vector3(0.6, y + 0.28, 0.27),
		o + Vector3(0.6, y + 0.19, 0.0), o + Vector3(0.6, y - 0.12, -0.1), o + Vector3(0.6, y - 0.22, 0)], [0.012, 0.012, 0.012, 0.012, 0.012, 0.012], 4, Vector2(1, 1), Color(0.05, 0.05, 0.05))
	st.generate_normals()
	var mi := MeshKit.mesh_instance(MeshKit.commit(st, _mats["metal"]))
	root.add_child(mi)
	Colliders.add_box(root, root.global_transform * Transform3D(Basis.IDENTITY, at + Vector3(-0.2, 0.7, 0)), Vector3(1.7, 1.4, 1.1))


func _cyl_x(st: SurfaceTool, c: Vector3, r: float, len: float, col: Color) -> void:
	MeshKit.tube(st, [c - Vector3(len * 0.5, 0, 0), c + Vector3(len * 0.5, 0, 0)], [r, r], 16, Vector2(1, 1), col)


# --- the props -------------------------------------------------------------------------------------
## A kit prop on the floor at `pos` (local), turned from the way it faced in the menu workshop (`was`)
## to `faces`, with a box to bump into.
func _kit(name: String, pos: Vector3, was := Vector3.BACK, faces := Vector3.BACK, solid := true) -> void:
	var path := KIT + name + ".scn"
	if not ResourceLoader.exists(path):
		return
	var n := (load(path) as PackedScene).instantiate() as Node3D
	var yaw := atan2(faces.x, faces.z) - atan2(was.x, was.z)
	n.transform = Transform3D(Basis(Vector3.UP, yaw), pos)
	root.add_child(n)
	for c in n.get_children():
		if c is MeshInstance3D:
			(c as MeshInstance3D).visibility_range_end = 260.0
	if solid:
		var box := AABB()
		var first := true
		for c in n.get_children():
			if c is MeshInstance3D and (c as MeshInstance3D).mesh:
				var bb: AABB = (c as MeshInstance3D).transform * (c as MeshInstance3D).get_aabb()
				box = bb if first else box.merge(bb)
				first = false
		if not first and box.size.y > 0.3:
			Colliders.add_box(root, root.global_transform * n.transform * Transform3D(Basis.IDENTITY, box.get_center()), box.size)


func _props() -> void:
	var E := Vector3(1, 0, 0)      # facing +x (into the hall from its left wall)
	var W := Vector3(-1, 0, 0)
	var S := Vector3(0, 0, -1)     # facing the front (from the back wall)
	var N := Vector3(0, 0, 1)
	# along the left wall: workbench, tool wall, shelving, wheel display
	_kit("long_side_workbench", Vector3(-10.4, 0, 1.6), W, E)
	_kit("storage_shelving", Vector3(-10.45, 0, 4.4), E, E)
	_kit("wall_mounted_wheel_display", Vector3(-10.6, 2.95, -2.8), E, E, false)
	_kit("wall_mounted_nitrous_bottle", Vector3(-10.6, 1.25, -4.4), E, E, false)
	# the back wall: lift, tool walls, poster, welder
	_kit("floorplate_two_post_lift", Vector3(-5.2, 0, 3.6), N, N)
	_kit("rear_tool_wall", Vector3(-1.4, 1.6, 5.75), N, S, false)
	_kit("rear_tool_wall", Vector3(-9.0, 1.6, 5.75), N, S, false)
	_kit("mountain_poster", Vector3(1.4, 2.7, 5.82), N, S, false)
	_kit("welder_with_gas_trolley", Vector3(1.6, 0, 4.9), S, S)
	# by the partition: compressor, tyre changer, tyres, jack
	_kit("vertical_shop_air_compressor", Vector3(2.3, 0, -0.6), N, W)
	_kit("automotive_tyre_changer", Vector3(2.2, 0, 1.5), N, W)
	_kit("radial_car_tyre_stack", Vector3(2.2, 0, -2.4), N, W)
	_kit("radial_car_tyre_stack_2", Vector3(1.2, 0, -2.6), N, W)
	_kit("radial_car_tyre_stack", Vector3(-10.3, 0, -4.9), N, E)
	_kit("red_floor_jack", Vector3(-2.2, 0, 1.9), N, W)
	# round the engine: trolleys, stool, pan, parts
	_kit("rolling_tool_trolley", Vector3(-3.2, 0, -2.0), N, W)
	_kit("rolling_tool_trolley_2", Vector3(-7.4, 0, 1.4), N, E)
	_kit("workshop_stool", Vector3(-6.4, 0, -1.9), N, N)
	_kit("oil_drain_pan", Vector3(-4.9, 0, -0.6), N, N, false)
	_kit("manual_gearbox_on_floor", Vector3(-7.6, 0, -2.4), N, E)
	_kit("axle_jack_stand", Vector3(-1.4, 0, 3.0), N, N)
	_kit("axle_jack_stand", Vector3(-8.9, 0, 3.0), N, N)
	_kit("shop_bucket", Vector3(0.4, 0, 5.2), N, N)
	_kit("spare_exhaust_section", Vector3(-9.8, 0, -1.8), N, E, false)
	_kit("open_parts_shipping_box", Vector3(-3.4, 0, -4.6), N, W)
	# the shop: counter, shelves, displays
	_box("wall", Vector3(5.6, 0.55, -1.2), Vector3(0.7, 1.1, 3.6), Color(0.14, 0.14, 0.16), true)
	_box("metal", Vector3(5.6, 1.13, -1.2), Vector3(0.82, 0.05, 3.8), Color(0.55, 0.56, 0.58), false)
	_box("metal", Vector3(5.6, 1.33, -2.3), Vector3(0.35, 0.35, 0.3), Color(0.08, 0.08, 0.09), false)    # till
	_commit()
	_kit("spare_turbocharger", Vector3(5.6, 1.16, -0.4), N, W, false)
	_kit("leaning_intercooler", Vector3(5.5, 1.16, 0.2), N, W, false)
	_kit("bench_vice", Vector3(5.6, 1.16, -1.4), N, W, false)
	_kit("storage_shelving", Vector3(10.45, 0, 2.6), E, W)
	_kit("storage_shelving", Vector3(10.45, 0, -1.2), E, W)
	_kit("storage_shelving", Vector3(7.4, 0, 5.4), E, S)
	_kit("wall_mounted_wheel_display", Vector3(10.6, 2.6, -4.2), E, W, false)
	_kit("loose_fluid_crate", Vector3(8.0, 0, -4.4), N, N)
	_kit("uneven_carton_pile", Vector3(9.4, 0, -4.8), N, N)
	_kit("paint_mixing_trolley", Vector3(4.2, 0, 4.6), N, E)

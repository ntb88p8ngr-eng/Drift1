extends RefCounted
## Low-poly meshes for roadside props, built once and cached. All of them use one shader: colours come
## from the vertex colours (alpha < 1 marks metal parts), multiplied by a per-instance tint
## (MultiMesh custom data), plus a little grunge noise. Signs/billboards use SignAtlas.BOARD_SHADER.

const MeshKit = preload("res://scripts/util/mesh_kit.gd")
const TexKit = preload("res://scripts/util/tex_kit.gd")

const PROP_SHADER := """
shader_type spatial;

uniform sampler2D grunge : source_color, filter_linear_mipmap, repeat_enable;
uniform float grunge_amount = 0.35;
uniform float roughness = 0.75;

varying vec3 tint;
varying vec3 wpos;

void vertex() {
	tint = INSTANCE_CUSTOM.rgb;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float g = texture(grunge, wpos.xz * 0.35 + wpos.y * 0.21).r;
	vec3 c = COLOR.rgb * tint;
	ALBEDO = c * mix(1.0, 0.7 + g * 0.6, grunge_amount);
	float metal = clamp((1.0 - COLOR.a) * 2.0, 0.0, 1.0);
	METALLIC = metal * 0.8;
	ROUGHNESS = mix(roughness, 0.38, metal);
}
"""

static var _cache := {}
static var _material: ShaderMaterial

const WOOD := Color(0.47, 0.3, 0.17, 1.0)
const IRON := Color(0.12, 0.12, 0.13, 0.5)
const STEEL := Color(0.62, 0.63, 0.65, 0.5)
const CONCRETE := Color(0.62, 0.61, 0.58, 1.0)
const TERRACOTTA := Color(0.66, 0.33, 0.2, 1.0)
const SOIL := Color(0.2, 0.14, 0.09, 1.0)
const LEAF := Color(0.2, 0.42, 0.12, 1.0)


static func material() -> ShaderMaterial:
	if _material == null:
		var sh := Shader.new()
		sh.code = PROP_SHADER
		_material = ShaderMaterial.new()
		_material.shader = sh
		_material.set_shader_parameter("grunge", TexKit.noise_texture(71, 0.05, false, 256))
	return _material


static func get_mesh(name: String) -> Mesh:
	if not _cache.has(name):
		var st := MeshKit.new_st()
		match name:
			"bench":
				_bench(st)
			"pot_red", "pot_yellow", "pot_purple", "pot_white":
				_flower_pot(st, name)
			"planter":
				_planter(st)
			"bin":
				_bin(st)
			"post":
				_post(st)
			"billboard_frame":
				_billboard_frame(st)
			"bus_shelter":
				_bus_shelter(st)
			"mailbox":
				_mailbox(st)
			"hay_bale":
				_hay_bale(st)
			"cone":
				_traffic_cone(st)
			"tyre_stack":
				_tyre_stack(st)
			"banner_tower":
				_banner_tower(st)
			"car_sedan", "car_hatch", "car_kei", "car_van":
				_parked_car(st, name)
			"bicycle":
				_bicycle(st)
			"wheelie_bin":
				_wheelie_bin(st)
			"garden_lamp":
				_garden_lamp(st)
			"fence":
				_fence(st)
			"hydrant":
				_hydrant(st)
			"barrier":
				_barrier(st)
			"water_barrier":
				_water_barrier(st)
		_cache[name] = MeshKit.commit(st, material())
	return _cache[name]


## Unit board (1 x 1 m, 4 cm thick, centred, front towards +Z) for the atlas shader.
static func board(thickness := 0.04) -> ArrayMesh:
	var key := "board_%.3f" % thickness
	if not _cache.has(key):
		var st := MeshKit.new_st()
		MeshKit.box(st, Transform3D(Basis.IDENTITY, Vector3(0, 0, -thickness * 0.5)), Vector3(1, 1, thickness))
		var arr := st.commit_to_arrays()
		# front face: UV 0..1 across the face (BoxMesh-style UVs from MeshKit.box are per face already)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var nrms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var uvs: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
		for i in verts.size():
			if nrms[i].z > 0.5:
				uvs[i] = Vector2(verts[i].x + 0.5, 0.5 - verts[i].y)
			elif nrms[i].z < -0.5:
				# the back: the same picture, reading the right way round from behind
				uvs[i] = Vector2(0.5 - verts[i].x, 0.5 - verts[i].y)
		arr[Mesh.ARRAY_TEX_UV] = uvs
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		_cache[key] = mesh
	return _cache[key]


static func _b(st: SurfaceTool, pos: Vector3, size: Vector3, col: Color, rot := Vector3.ZERO) -> void:
	MeshKit.box(st, Transform3D(Basis.from_euler(rot), pos), size, col)


static func _cyl(st: SurfaceTool, base: Vector3, top: Vector3, r0: float, r1: float, col: Color, seg := 10) -> void:
	MeshKit.tube(st, [base, top], [r0, r1], seg, Vector2(1, 1), col, false)
	var ring := PackedVector3Array()
	for k in seg:
		var a := TAU * k / float(seg)
		ring.append(top + Vector3(cos(a) * r1, 0, sin(a) * r1))
	MeshKit.cap(st, ring, top, (top - base).normalized(), col)


## Surface of revolution around the Y axis; profile: Array of Vector2(radius, y).
static func _vlathe(st: SurfaceTool, profile: Array, seg: int, col: Color) -> void:
	for i in profile.size() - 1:
		var p0: Vector2 = profile[i]
		var p1: Vector2 = profile[i + 1]
		var d := p1 - p0
		var n2 := Vector2(d.y, -d.x).normalized()
		for j in seg:
			var a0 := TAU * j / float(seg)
			var a1 := TAU * (j + 1) / float(seg)
			var v00 := Vector3(cos(a0) * p0.x, p0.y, sin(a0) * p0.x)
			var v01 := Vector3(cos(a1) * p0.x, p0.y, sin(a1) * p0.x)
			var v10 := Vector3(cos(a0) * p1.x, p1.y, sin(a0) * p1.x)
			var v11 := Vector3(cos(a1) * p1.x, p1.y, sin(a1) * p1.x)
			var am := (a0 + a1) * 0.5
			var nrm := Vector3(cos(am) * n2.x, n2.y, sin(am) * n2.x)
			if p0.x < 0.001:
				MeshKit.tri(st, v00, v10, v11, nrm, nrm, nrm, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, nrm, col)
			elif p1.x < 0.001:
				MeshKit.tri(st, v00, v01, v10, nrm, nrm, nrm, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, nrm, col)
			else:
				MeshKit.quad(st, v00, v01, v11, v10, nrm, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, col)


static func _bench(st: SurfaceTool) -> void:
	# park bench, 1.8 m: cast iron side frames, wooden slats
	for x: float in [-0.75, 0.75]:
		_b(st, Vector3(x, 0.22, 0.12), Vector3(0.06, 0.44, 0.06), IRON)
		_b(st, Vector3(x, 0.22, -0.22), Vector3(0.06, 0.44, 0.06), IRON)
		_b(st, Vector3(x, 0.44, -0.05), Vector3(0.06, 0.05, 0.5), IRON)
		_b(st, Vector3(x, 0.72, 0.22), Vector3(0.06, 0.6, 0.05), IRON, Vector3(-0.2, 0, 0))
		_b(st, Vector3(x, 0.62, -0.15), Vector3(0.05, 0.04, 0.3), IRON)
	for k in 3:
		_b(st, Vector3(0, 0.47, -0.2 + k * 0.13), Vector3(1.8, 0.035, 0.1), WOOD)
	for k in 2:
		_b(st, Vector3(0, 0.66 + k * 0.17, 0.2 + k * 0.035), Vector3(1.8, 0.1, 0.03), WOOD, Vector3(-0.2, 0, 0))


static func _flowers(st: SurfaceTool, centre: Vector3, radius: float, flower: Color, rng: RandomNumberGenerator, count: int) -> void:
	# a dome of leaves with flower heads on top
	for k in count:
		var a := rng.randf() * TAU
		var d := sqrt(rng.randf()) * radius
		var p := centre + Vector3(cos(a) * d, rng.randf_range(0.0, 0.12) + (radius - d) * 0.5, sin(a) * d)
		var s := rng.randf_range(0.06, 0.1)
		_b(st, p, Vector3(s * 1.6, s, s * 1.6), LEAF.darkened(rng.randf_range(0.0, 0.3)), Vector3(0, rng.randf() * TAU, 0))
	for k in count / 2:
		var a := rng.randf() * TAU
		var d := sqrt(rng.randf()) * radius * 0.9
		var p := centre + Vector3(cos(a) * d, 0.1 + (radius - d) * 0.55 + rng.randf_range(0.0, 0.05), sin(a) * d)
		_b(st, p, Vector3(0.07, 0.05, 0.07), flower.lightened(rng.randf_range(0.0, 0.2)), Vector3(0, rng.randf() * TAU, 0))


static func _flower_pot(st: SurfaceTool, name: String) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(name)
	var cols := {"pot_red": Color(0.85, 0.1, 0.12), "pot_yellow": Color(0.95, 0.78, 0.1),
		"pot_purple": Color(0.55, 0.25, 0.8), "pot_white": Color(0.95, 0.95, 0.92)}
	_vlathe(st, [Vector2(0.0, 0.0), Vector2(0.17, 0.0), Vector2(0.24, 0.38), Vector2(0.27, 0.4), Vector2(0.27, 0.44), Vector2(0.22, 0.44)], 12, TERRACOTTA)
	_vlathe(st, [Vector2(0.23, 0.41), Vector2(0.0, 0.41)], 12, SOIL)
	_flowers(st, Vector3(0, 0.44, 0), 0.26, cols[name], rng, 26)


static func _planter(st: SurfaceTool) -> void:
	# long concrete trough with mixed flowers (2 m)
	_b(st, Vector3(0, 0.25, 0), Vector3(2.0, 0.5, 0.6), CONCRETE)
	_b(st, Vector3(0, 0.49, 0), Vector3(1.86, 0.03, 0.46), SOIL)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for k in 4:
		var c: Color = [Color(0.85, 0.1, 0.12), Color(0.95, 0.78, 0.1), Color(0.55, 0.25, 0.8), Color(0.95, 0.5, 0.7)][k]
		_flowers(st, Vector3(-0.7 + k * 0.47, 0.5, 0), 0.24, c, rng, 16)


static func _bin(st: SurfaceTool) -> void:
	var green := Color(0.14, 0.3, 0.2, 0.7)
	_cyl(st, Vector3(0, 0.0, 0), Vector3(0, 0.85, 0), 0.24, 0.25, green, 12)
	_cyl(st, Vector3(0, 0.85, 0), Vector3(0, 0.95, 0), 0.27, 0.2, Color(0.1, 0.1, 0.1, 0.6), 12)
	_b(st, Vector3(0, 0.6, 0.245), Vector3(0.2, 0.12, 0.02), Color(0.9, 0.9, 0.9))


static func _post(st: SurfaceTool) -> void:
	# galvanised sign post, 1 m (scaled in height per instance)
	_cyl(st, Vector3(0, 0, 0), Vector3(0, 1, 0), 0.035, 0.035, STEEL, 8)


static func _billboard_frame(st: SurfaceTool) -> void:
	# frame for an 8 x 4 m board whose lower edge is 3 m up; the board itself sits at z = 0.12
	for x: float in [-2.6, 2.6]:
		_b(st, Vector3(x, 2.5, -0.25), Vector3(0.35, 5.0, 0.35), STEEL)
		_b(st, Vector3(x, 5.0, -0.1), Vector3(0.2, 3.9, 0.12), STEEL)
	for y: float in [3.2, 5.0, 6.8]:
		_b(st, Vector3(0, y, -0.12), Vector3(8.0, 0.12, 0.12), STEEL)
	_b(st, Vector3(0, 2.95, 0.5), Vector3(8.2, 0.06, 1.0), STEEL)        # service walkway
	for k in 4:
		var x := -3.0 + k * 2.0
		_b(st, Vector3(x, 7.25, 0.55), Vector3(0.05, 0.05, 0.9), STEEL)      # lamp arms
		_b(st, Vector3(x, 7.2, 1.0), Vector3(0.45, 0.12, 0.25), IRON)          # lamp heads


static func _bus_shelter(st: SurfaceTool) -> void:
	var frame := Color(0.75, 0.76, 0.78, 0.5)
	for x: float in [-1.6, 1.6]:
		for z: float in [-0.7, 0.6]:
			_b(st, Vector3(x, 1.2, z), Vector3(0.08, 2.4, 0.08), frame)
	_b(st, Vector3(0, 2.45, 0), Vector3(3.6, 0.1, 1.8), Color(0.3, 0.32, 0.35, 0.6))
	_b(st, Vector3(0, 1.25, -0.72), Vector3(3.2, 1.9, 0.03), Color(0.55, 0.62, 0.66, 0.8))   # back pane
	_b(st, Vector3(-1.62, 1.25, 0.0), Vector3(0.03, 1.9, 1.2), Color(0.55, 0.62, 0.66, 0.8))
	_b(st, Vector3(0, 0.45, -0.45), Vector3(2.6, 0.06, 0.4), WOOD)
	_b(st, Vector3(-1.1, 0.22, -0.45), Vector3(0.06, 0.44, 0.35), IRON)
	_b(st, Vector3(1.1, 0.22, -0.45), Vector3(0.06, 0.44, 0.35), IRON)
	_b(st, Vector3(1.0, 1.4, -0.7), Vector3(1.0, 1.3, 0.05), Color(0.95, 0.95, 0.92))        # timetable


static func _mailbox(st: SurfaceTool) -> void:
	_b(st, Vector3(0, 0.5, 0), Vector3(0.08, 1.0, 0.08), IRON)
	_b(st, Vector3(0, 1.1, 0), Vector3(0.36, 0.3, 0.24), Color(0.8, 0.12, 0.1, 0.7))
	_b(st, Vector3(0, 1.1, 0.125), Vector3(0.24, 0.03, 0.01), Color(0.1, 0.1, 0.1))


static func _hay_bale(st: SurfaceTool) -> void:
	var hay := Color(0.78, 0.66, 0.35)
	MeshKit.tube(st, [Vector3(-0.6, 0.65, 0), Vector3(0.6, 0.65, 0)], [0.65, 0.65], 14, Vector2(1, 1), hay, false)
	var ring := PackedVector3Array()
	for k in 14:
		var a := TAU * k / 14.0
		ring.append(Vector3(0.6, 0.65 + sin(a) * 0.65, cos(a) * 0.65))
	MeshKit.cap(st, ring, Vector3(0.6, 0.65, 0), Vector3.RIGHT, hay.darkened(0.15))
	var ring2 := PackedVector3Array()
	for k in 14:
		var a := -TAU * k / 14.0
		ring2.append(Vector3(-0.6, 0.65 + sin(a) * 0.65, cos(a) * 0.65))
	MeshKit.cap(st, ring2, Vector3(-0.6, 0.65, 0), Vector3.LEFT, hay.darkened(0.15))


## Road works A-frame barrier (1.4 m): two striped boards on folding legs, a flasher on top.
static func _barrier(st: SurfaceTool) -> void:
	var white := Color(0.95, 0.95, 0.92)
	var orange := Color(0.95, 0.38, 0.05)
	for z in [-0.25, 0.25]:
		for x in [-0.62, 0.62]:
			_b(st, Vector3(x, 0.5, z), Vector3(0.05, 1.0, 0.05), white, Vector3(-signf(z) * 0.25, 0, 0))
	for y in [0.75, 0.45]:
		for k in 6:
			var c: Color = orange if k % 2 == 0 else white
			_b(st, Vector3(-0.58 + k * 0.233, y, -0.22), Vector3(0.233, 0.2, 0.025), c, Vector3(0, 0, 0.0))
	_b(st, Vector3(-0.55, 1.0, -0.02), Vector3(0.12, 0.12, 0.08), Color(1.0, 0.75, 0.1))


## Water-filled plastic road barrier (1.2 m), red or white in turn along a row.
static func _water_barrier(st: SurfaceTool) -> void:
	var c := Color(0.85, 0.12, 0.1)
	_b(st, Vector3(0, 0.2, 0), Vector3(1.2, 0.4, 0.45), c)
	_b(st, Vector3(0, 0.55, 0), Vector3(1.15, 0.3, 0.32), c)
	_b(st, Vector3(0, 0.75, 0), Vector3(1.1, 0.12, 0.2), c)
	_b(st, Vector3(0, 0.45, 0.23), Vector3(0.6, 0.12, 0.02), Color(0.95, 0.95, 0.95))


static func _traffic_cone(st: SurfaceTool) -> void:
	_b(st, Vector3(0, 0.02, 0), Vector3(0.4, 0.04, 0.4), Color(0.1, 0.1, 0.1))
	_cyl(st, Vector3(0, 0.04, 0), Vector3(0, 0.25, 0), 0.15, 0.1, Color(0.95, 0.4, 0.05), 10)
	_cyl(st, Vector3(0, 0.25, 0), Vector3(0, 0.36, 0), 0.1, 0.075, Color(0.95, 0.95, 0.95), 10)
	_cyl(st, Vector3(0, 0.36, 0), Vector3(0, 0.7, 0), 0.075, 0.02, Color(0.95, 0.4, 0.05), 10)


static func _tyre_stack(st: SurfaceTool) -> void:
	var rubber := Color(0.06, 0.06, 0.065)
	for k in 4:
		var y := 0.12 + k * 0.24
		_vlathe(st, [Vector2(0.18, y - 0.11), Vector2(0.3, y - 0.12), Vector2(0.33, y), Vector2(0.3, y + 0.12), Vector2(0.18, y + 0.11)], 14,
			rubber if k != 2 else Color(0.9, 0.9, 0.9))


static func _banner_tower(st: SurfaceTool) -> void:
	# lattice tower of an overhead banner arch, 7 m
	var s := STEEL
	for x: float in [-0.35, 0.35]:
		for z: float in [-0.35, 0.35]:
			_b(st, Vector3(x, 3.5, z), Vector3(0.08, 7.0, 0.08), s)
	for k in 8:
		var y := 0.4 + k * 0.85
		_b(st, Vector3(0, y, 0.35), Vector3(0.7, 0.05, 0.05), s)
		_b(st, Vector3(0, y, -0.35), Vector3(0.7, 0.05, 0.05), s)
		_b(st, Vector3(0.35, y, 0), Vector3(0.05, 0.05, 0.7), s)
		_b(st, Vector3(-0.35, y, 0), Vector3(0.05, 0.05, 0.7), s)
	_b(st, Vector3(0, 0.1, 0), Vector3(1.2, 0.2, 1.2), CONCRETE)


## Parked cars (front = -Z, ground = y 0). The body is white: the instance tint paints it.
## Sizes: sedan 4.6 m, hatchback 4.0 m, kei car 3.4 m (tall box), van 4.9 m (high roof).
const CAR_SIZES := {"car_sedan": Vector3(1.78, 1.42, 4.6), "car_hatch": Vector3(1.74, 1.48, 4.0),
	"car_kei": Vector3(1.48, 1.68, 3.4), "car_van": Vector3(1.9, 2.0, 4.9)}


static func _parked_car(st: SurfaceTool, name: String) -> void:
	var body := Color(0.92, 0.92, 0.92, 0.7)
	var glass := Color(0.04, 0.05, 0.06, 0.25)
	var dark := Color(0.05, 0.05, 0.05)
	var sz: Vector3 = CAR_SIZES[name]
	var w := sz.x
	var l := sz.z
	var wr := 0.31 if name != "car_kei" else 0.27
	var sill := wr * 1.05
	match name:
		"car_sedan":
			_b(st, Vector3(0, sill + 0.3, 0), Vector3(w, 0.6, l), body)
			_b(st, Vector3(0, sill + 0.83, 0.15), Vector3(w - 0.2, 0.46, 2.3), body)
			_b(st, Vector3(0, sill + 0.83, -1.05), Vector3(w - 0.24, 0.4, 0.22), glass, Vector3(0.55, 0, 0))
			_b(st, Vector3(0, sill + 0.83, 1.35), Vector3(w - 0.24, 0.38, 0.22), glass, Vector3(-0.6, 0, 0))
			_b(st, Vector3(0, sill + 0.86, 0.15), Vector3(w - 0.17, 0.32, 1.9), glass)
		"car_hatch":
			_b(st, Vector3(0, sill + 0.32, 0), Vector3(w, 0.64, l), body)
			_b(st, Vector3(0, sill + 0.86, 0.35), Vector3(w - 0.18, 0.5, 2.3), body)
			_b(st, Vector3(0, sill + 0.86, -0.85), Vector3(w - 0.22, 0.42, 0.22), glass, Vector3(0.55, 0, 0))
			_b(st, Vector3(0, sill + 0.88, 0.35), Vector3(w - 0.15, 0.34, 2.0), glass)
			_b(st, Vector3(0, sill + 0.86, 1.51), Vector3(w - 0.22, 0.4, 0.04), glass)
		"car_kei":
			_b(st, Vector3(0, sill + 0.35, 0), Vector3(w, 0.7, l), body)
			_b(st, Vector3(0, sill + 1.0, 0.25), Vector3(w - 0.08, 0.62, 2.7), body)
			_b(st, Vector3(0, sill + 1.02, 0.25), Vector3(w - 0.05, 0.42, 2.4), glass)
			_b(st, Vector3(0, sill + 1.02, -1.12), Vector3(w - 0.14, 0.44, 0.06), glass, Vector3(0.3, 0, 0))
		"car_van":
			_b(st, Vector3(0, sill + 0.55, 0.25), Vector3(w, 1.1, l - 0.5), body)
			_b(st, Vector3(0, sill + 1.42, 0.45), Vector3(w - 0.06, 0.64, l - 0.9), body)
			_b(st, Vector3(0, sill + 0.4, -l * 0.5 + 0.3), Vector3(w, 0.8, 0.6), body)
			_b(st, Vector3(0, sill + 1.2, -l * 0.5 + 0.72), Vector3(w - 0.1, 0.6, 0.3), glass, Vector3(0.45, 0, 0))
			_b(st, Vector3(0, sill + 1.25, -1.2), Vector3(w + 0.01, 0.45, 1.2), glass)
	# bumpers, lights, mirrors, number plates
	_b(st, Vector3(0, sill + 0.08, -l * 0.5 + 0.02), Vector3(w + 0.02, 0.2, 0.1), dark)
	_b(st, Vector3(0, sill + 0.08, l * 0.5 - 0.02), Vector3(w + 0.02, 0.2, 0.1), dark)
	for s in [-1.0, 1.0]:
		_b(st, Vector3(s * (w * 0.5 - 0.22), sill + 0.42, -l * 0.5 + 0.005), Vector3(0.3, 0.1, 0.02), Color(0.95, 0.95, 0.88, 0.3))
		_b(st, Vector3(s * (w * 0.5 - 0.2), sill + 0.46, l * 0.5 - 0.005), Vector3(0.28, 0.1, 0.02), Color(0.75, 0.05, 0.05))
		_b(st, Vector3(s * (w * 0.5 + 0.06), sill + 0.8, -0.95), Vector3(0.1, 0.08, 0.14), dark)
	_b(st, Vector3(0, sill + 0.2, -l * 0.5 - 0.035), Vector3(0.36, 0.1, 0.01), Color(0.95, 0.95, 0.9))
	_b(st, Vector3(0, sill + 0.3, l * 0.5 + 0.035), Vector3(0.36, 0.1, 0.01), Color(0.95, 0.95, 0.9))
	# wheels with rims
	var ax := l * 0.5 - (0.75 if name != "car_van" else 0.85)
	for z: float in [-ax, ax]:
		for x: float in [-w * 0.5 + 0.12, w * 0.5 - 0.12]:
			var sx := signf(x)
			_cyl(st, Vector3(x - sx * 0.1, wr, z), Vector3(x + sx * 0.1, wr, z), wr, wr, Color(0.05, 0.05, 0.055), 14)
			_cyl(st, Vector3(x + sx * 0.1, wr, z), Vector3(x + sx * 0.105, wr, z), wr * 0.62, wr * 0.62, STEEL, 12)


static func _bicycle(st: SurfaceTool) -> void:
	var frame := Color(0.85, 0.85, 0.85, 0.6)
	var tyre := Color(0.05, 0.05, 0.05)
	for z: float in [-0.52, 0.52]:
		# a real wheel (no solid black disc): the tyre and rim as rings, spokes, the hub
		var c := Vector3(0, 0.34, z)
		var segs := 16
		for k in segs:
			var a0 := TAU * k / segs
			var a1 := TAU * (k + 1) / segs
			var d0 := Vector3(0, sin(a0), cos(a0))
			var d1 := Vector3(0, sin(a1), cos(a1))
			_cyl(st, c + d0 * 0.32, c + d1 * 0.32, 0.028, 0.028, tyre, 5)
			_cyl(st, c + d0 * 0.285, c + d1 * 0.285, 0.01, 0.01, STEEL, 4)
		for k in 8:
			var a := TAU * k / 8.0
			_cyl(st, c, c + Vector3(0, sin(a), cos(a)) * 0.285, 0.004, 0.004, STEEL, 3)
		_cyl(st, Vector3(-0.03, 0.34, z), Vector3(0.03, 0.34, z), 0.03, 0.03, STEEL, 8)
	_cyl(st, Vector3(0, 0.34, 0.52), Vector3(0, 0.62, -0.02), 0.018, 0.018, frame, 6)
	_cyl(st, Vector3(0, 0.34, -0.52), Vector3(0, 0.78, -0.4), 0.018, 0.018, frame, 6)
	_cyl(st, Vector3(0, 0.62, -0.02), Vector3(0, 0.76, -0.38), 0.018, 0.018, frame, 6)
	_cyl(st, Vector3(0, 0.62, -0.02), Vector3(0, 0.34, 0.52), 0.015, 0.015, frame, 6)
	_cyl(st, Vector3(0, 0.62, -0.02), Vector3(0, 0.84, 0.1), 0.015, 0.015, frame, 6)
	_b(st, Vector3(0, 0.87, 0.12), Vector3(0.12, 0.05, 0.24), Color(0.05, 0.05, 0.05))
	_cyl(st, Vector3(0, 0.78, -0.4), Vector3(0, 0.95, -0.43), 0.015, 0.015, frame, 6)
	_b(st, Vector3(0, 0.96, -0.43), Vector3(0.5, 0.025, 0.025), Color(0.1, 0.1, 0.1))
	_b(st, Vector3(0, 0.62, 0.34), Vector3(0.14, 0.02, 0.4), frame)     # rack


static func _wheelie_bin(st: SurfaceTool) -> void:
	var c := Color(0.92, 0.92, 0.92, 0.9)
	_b(st, Vector3(0, 0.5, 0), Vector3(0.58, 0.96, 0.7), c)
	_b(st, Vector3(0, 1.0, -0.02), Vector3(0.62, 0.05, 0.76), c * 0.85, Vector3(-0.06, 0, 0))
	_b(st, Vector3(0, 0.95, 0.38), Vector3(0.5, 0.05, 0.05), Color(0.1, 0.1, 0.1))
	for x: float in [-0.24, 0.24]:
		_cyl(st, Vector3(x - 0.03, 0.1, 0.33), Vector3(x + 0.03, 0.1, 0.33), 0.1, 0.1, Color(0.05, 0.05, 0.05), 10)


static func _garden_lamp(st: SurfaceTool) -> void:
	_cyl(st, Vector3(0, 0, 0), Vector3(0, 0.9, 0), 0.04, 0.035, IRON, 8)
	_b(st, Vector3(0, 0.98, 0), Vector3(0.18, 0.16, 0.18), Color(0.95, 0.9, 0.75))
	_b(st, Vector3(0, 1.08, 0), Vector3(0.24, 0.04, 0.24), IRON)


static func _fence(st: SurfaceTool) -> void:
	# 2 m of picket fence, white (tint for other colours)
	var c := Color(0.95, 0.95, 0.93)
	for x: float in [-1.0, 1.0]:
		_b(st, Vector3(x * 0.98, 0.5, 0), Vector3(0.08, 1.0, 0.08), c)
	for y: float in [0.3, 0.72]:
		_b(st, Vector3(0, y, 0.04), Vector3(2.0, 0.07, 0.03), c)
	for k in 12:
		_b(st, Vector3(-0.9 + k * 0.164, 0.46, 0.07), Vector3(0.08, 0.86, 0.02), c)


static func _hydrant(st: SurfaceTool) -> void:
	var red := Color(0.8, 0.1, 0.08, 0.8)
	_cyl(st, Vector3(0, 0, 0), Vector3(0, 0.08, 0), 0.14, 0.14, red, 10)
	_cyl(st, Vector3(0, 0.08, 0), Vector3(0, 0.62, 0), 0.1, 0.1, red, 10)
	_cyl(st, Vector3(0, 0.62, 0), Vector3(0, 0.72, 0), 0.11, 0.06, red, 10)
	_cyl(st, Vector3(-0.17, 0.45, 0), Vector3(0.17, 0.45, 0), 0.045, 0.045, red, 8)

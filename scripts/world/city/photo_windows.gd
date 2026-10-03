extends Node3D
## Photo windows: on some of the towers a few window bays show a real room (pictures from
## assets/textures/windows/). By day the dark picture; at night some of them switch to the lit one
## (the rest stay dark – nobody home). Pairs are named <room>_day / <room>_night; a single picture
## is used for both.

const DIR := "res://assets/textures/windows/"

const SHADER := """
shader_type spatial;
render_mode diffuse_burley;
uniform sampler2D day_tex : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D night_tex : source_color, filter_linear_mipmap_anisotropic;
uniform float night = 0.0;
varying float lit;
void vertex() {
	lit = INSTANCE_CUSTOM.r;      // 1: the lights go on at night in this one
}
void fragment() {
	vec3 d = texture(day_tex, UV).rgb;
	vec3 n = texture(night_tex, UV).rgb;
	float on = night * lit;
	ALBEDO = mix(d, n * 0.25, on) * mix(1.0, 0.45, night * (1.0 - lit));
	EMISSION = n * on * 1.5;
	ROUGHNESS = 0.12;
	METALLIC = 0.1;
	SPECULAR = 0.6;
}
"""

var _mats: Array = []


## The pictures there are: [[day texture, night texture, aspect w/h], …] (empty if none were uploaded).
static func pictures() -> Array:
	var files := {}
	var dir := DirAccess.open(DIR)
	if dir == null:
		return []
	for f in dir.get_files():
		var name := f.trim_suffix(".import")
		var ext := name.get_extension().to_lower()
		if not ["png", "jpg", "jpeg", "webp"].has(ext):
			continue
		files[name.get_basename()] = DIR + name
	var out: Array = []
	var done := {}
	for base: String in files:
		if done.has(base):
			continue
		var room := base
		for suf in ["_day", "_night", "_dark", "_lit", "_off", "_on"]:
			if base.ends_with(suf):
				room = base.trim_suffix(suf)
		var day = null
		var night = null
		for suf in ["_day", "_dark", "_off"]:
			if files.has(room + suf):
				day = files[room + suf]
				done[room + suf] = true
		for suf in ["_night", "_lit", "_on"]:
			if files.has(room + suf):
				night = files[room + suf]
				done[room + suf] = true
		if day == null and night == null:
			day = files[base]
			night = files[base]
			done[base] = true
		var dt = load(day if day != null else night)
		var nt = load(night if night != null else day)
		if dt is Texture2D and nt is Texture2D:
			out.append([dt, nt, float((dt as Texture2D).get_width()) / maxf((dt as Texture2D).get_height(), 1.0)])
	return out


## spots: [[Transform3D (centre, facing out), Vector2 size, picture index hint, lit 0/1], …]
func build(spots: Array) -> void:
	var pics := pictures()
	if pics.is_empty() or spots.is_empty():
		return
	var sh := Shader.new()
	sh.code = SHADER
	var per: Array = []
	for p in pics:
		var m := ShaderMaterial.new()
		m.shader = sh
		m.set_shader_parameter("day_tex", p[0])
		m.set_shader_parameter("night_tex", p[1])
		_mats.append(m)
		per.append([])
	for s in spots:
		per[int(s[2]) % pics.size()].append(s)
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	for i in per.size():
		var list: Array = per[i]
		if list.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = quad
		mm.instance_count = list.size()
		for k in list.size():
			var xf: Transform3D = list[k][0]
			var size: Vector2 = list[k][1]
			# the picture's own proportions: as wide as the bay, centred in the floor's height
			size.y = minf(size.y, size.x / float(pics[i][2]))
			mm.set_instance_transform(k, Transform3D(xf.basis * Basis.from_scale(Vector3(size.x, size.y, 1.0)), xf.origin))
			mm.set_instance_custom_data(k, Color(float(list[k][3]), 0, 0, 1))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = _mats[i]
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visibility_range_end = 900.0
		add_child(mmi)


func set_night(n: float) -> void:
	for m in _mats:
		(m as ShaderMaterial).set_shader_parameter("night", n)

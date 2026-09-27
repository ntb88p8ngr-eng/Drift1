extends RefCounted
## Sky (custom procedural skybox shader with clouds, sun, moon and stars), sun light with
## dynamic cascaded shadows, fog, tonemapping, glow, SSAO/SSR depending on the quality setting.

const TexKit = preload("res://scripts/util/tex_kit.gd")

const PRESETS := {
	"day": {
		"sun_elev": 58.0, "sun_az": 35.0, "sun_color": Color(1.0, 0.96, 0.88), "sun_energy": 1.35,
		"zenith": Color(0.12, 0.30, 0.66), "horizon": Color(0.62, 0.74, 0.88), "ground": Color(0.22, 0.22, 0.2),
		"clouds": 0.42, "cloud_color": Color(1, 1, 1), "cloud_shade": Color(0.58, 0.62, 0.7),
		"fog": Color(0.66, 0.74, 0.86), "fog_density": 0.0009, "ambient": 0.9, "exposure": 1.0, "stars": 0.0, "night": 0.0,
	},
	"dusk": {
		"sun_elev": 6.0, "sun_az": 240.0, "sun_color": Color(1.0, 0.55, 0.28), "sun_energy": 1.1,
		"zenith": Color(0.10, 0.10, 0.30), "horizon": Color(0.95, 0.45, 0.25), "ground": Color(0.12, 0.08, 0.1),
		"clouds": 0.5, "cloud_color": Color(1.0, 0.62, 0.42), "cloud_shade": Color(0.35, 0.22, 0.35),
		"fog": Color(0.75, 0.45, 0.4), "fog_density": 0.0012, "ambient": 0.7, "exposure": 1.1, "stars": 0.15, "night": 0.45,
	},
	"night": {
		"sun_elev": 35.0, "sun_az": 150.0, "sun_color": Color(0.45, 0.55, 0.85), "sun_energy": 0.12,
		"zenith": Color(0.005, 0.008, 0.025), "horizon": Color(0.04, 0.05, 0.1), "ground": Color(0.01, 0.01, 0.015),
		"clouds": 0.3, "cloud_color": Color(0.08, 0.09, 0.14), "cloud_shade": Color(0.02, 0.02, 0.04),
		"fog": Color(0.03, 0.04, 0.07), "fog_density": 0.0014, "ambient": 0.35, "exposure": 1.0, "stars": 1.0, "night": 1.0,
	},
	"morning": {
		"sun_elev": 14.0, "sun_az": 80.0, "sun_color": Color(1.0, 0.8, 0.6), "sun_energy": 1.0,
		"zenith": Color(0.25, 0.38, 0.6), "horizon": Color(0.85, 0.78, 0.72), "ground": Color(0.3, 0.28, 0.27),
		"clouds": 0.35, "cloud_color": Color(1.0, 0.9, 0.82), "cloud_shade": Color(0.6, 0.6, 0.68),
		"fog": Color(0.8, 0.78, 0.76), "fog_density": 0.0045, "ambient": 0.85, "exposure": 1.0, "stars": 0.0, "night": 0.1,
	},
}


## Adds WorldEnvironment + DirectionalLight3D to `parent`. Returns {"env", "sun", "night"}.
static func build(parent: Node, tod: String, quality: int) -> Dictionary:
	var p: Dictionary = PRESETS.get(tod, PRESETS["dusk"])
	var sky_mat := TexKit.sky_material()
	sky_mat.set_shader_parameter("zenith_color", p["zenith"])
	sky_mat.set_shader_parameter("horizon_color", p["horizon"])
	sky_mat.set_shader_parameter("ground_color", p["ground"])
	sky_mat.set_shader_parameter("sun_color", p["sun_color"])
	sky_mat.set_shader_parameter("cloud_coverage", p["clouds"])
	sky_mat.set_shader_parameter("cloud_color", p["cloud_color"])
	sky_mat.set_shader_parameter("cloud_shade", p["cloud_shade"])
	sky_mat.set_shader_parameter("star_amount", p["stars"])
	sky_mat.set_shader_parameter("moon_amount", 1.0 if tod == "night" else 0.0)
	sky_mat.set_shader_parameter("exposure", 1.0)
	var is_night := tod == "night"
	sky_mat.set_shader_parameter("sun_size", 0.0 if is_night else 0.035)
	sky_mat.set_shader_parameter("sun_glow", 0.1 if is_night else 0.35)

	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	sky.process_mode = Sky.PROCESS_MODE_QUALITY if quality >= 2 else Sky.PROCESS_MODE_INCREMENTAL

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = p["ambient"]
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = p["exposure"]
	env.tonemap_white = 6.0
	env.glow_enabled = quality >= 1
	env.glow_intensity = 0.7
	env.glow_strength = 1.0
	env.glow_bloom = 0.03
	env.glow_hdr_threshold = 1.1
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.ssao_enabled = quality >= 2
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.6
	env.ssr_enabled = quality >= 3
	env.ssr_max_steps = 48
	env.ssil_enabled = false
	env.fog_enabled = true
	env.fog_light_color = p["fog"]
	env.fog_density = p["fog_density"]
	env.fog_aerial_perspective = 0.6
	env.fog_sky_affect = 0.15
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 1.08

	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	parent.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = p["sun_color"]
	sun.light_energy = p["sun_energy"]
	sun.shadow_enabled = true
	sun.shadow_bias = 0.03
	sun.shadow_normal_bias = 1.2
	sun.shadow_blur = 1.2
	sun.light_angular_distance = 0.6
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if quality >= 1 else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = [120.0, 180.0, 260.0, 350.0][clampi(quality, 0, 3)]
	sun.directional_shadow_blend_splits = quality >= 2
	sun.directional_shadow_fade_start = 0.85
	var elev := deg_to_rad(float(p["sun_elev"]))
	var az := deg_to_rad(float(p["sun_az"]))
	sun.rotation = Vector3(-elev, az, 0)
	parent.add_child(sun)
	return {"env": env, "sun": sun, "night": float(p["night"]), "fog": p["fog"]}

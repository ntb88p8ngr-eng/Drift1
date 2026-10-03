extends RefCounted
## The workshop model's (Midnight_Drift_Garage_Detailed.glb) texture files per material, read off the
## glTF: assigned at load time, so the garage is textured even where the model was imported before
## its texture files were there.

const DIR := "res://assets/main_menu/textures/"

const MAP := {
	"Concrete_wall": {"albedo": "Concrete_wall_basecolor.png", "orm": "Concrete_wall_orm.png", "normal": "Concrete_wall_normal.png", "normal_scale": 0.8},
	"Aged_black_steel": {"albedo": "Aged_black_steel_basecolor.png", "orm": "Aged_black_steel_orm.png", "normal": "Aged_black_steel_normal.png", "normal_scale": 0.8},
	"Brushed_alloy": {"albedo": "Brushed_alloy_basecolor.png", "orm": "Brushed_alloy_orm.png", "normal": "Brushed_alloy_normal.png", "normal_scale": 0.8},
	"Worn_crimson_paint": {"albedo": "Worn_crimson_paint_basecolor.png", "orm": "Worn_crimson_paint_orm.png", "normal": "Worn_crimson_paint_normal.png", "normal_scale": 0.8},
	"Tyre_rubber": {"albedo": "Tyre_rubber_basecolor.png", "orm": "Tyre_rubber_orm.png", "normal": "Tyre_rubber_normal.png", "normal_scale": 0.8},
	"Workbench_wood": {"albedo": "Workbench_wood_basecolor.png", "orm": "Workbench_wood_orm.png", "normal": "Workbench_wood_normal.png", "normal_scale": 0.8},
	"Storage_cartons": {"albedo": "Storage_cartons_basecolor.png", "orm": "Storage_cartons_orm.png", "normal": "Storage_cartons_normal.png", "normal_scale": 0.8},
	"Deep_charcoal": {"albedo": "Deep_charcoal_basecolor.png", "orm": "Deep_charcoal_orm.png", "normal": "Finish_plastic_normal.png", "normal_scale": 0.8},
	"Ivory_paint": {"albedo": "Ivory_paint_basecolor.png", "orm": "Ivory_paint_orm.png", "normal": "Finish_paint_normal.png", "normal_scale": 0.8},
	"Neon_red": {"albedo": "Neon_red_basecolor.png", "orm": "Neon_red_orm.png", "normal": "Finish_diffuser_normal.png", "normal_scale": 0.8},
	"Warm_fixture": {"albedo": "Warm_fixture_basecolor.png", "orm": "Warm_fixture_orm.png", "normal": "Finish_diffuser_normal.png", "normal_scale": 0.8},
	"Hazard_stripes": {"albedo": "Hazard_stripes.png", "orm": "Hazard_stripes_orm.png", "normal": "Finish_paper_normal.png", "normal_scale": 0.8},
	"Reference_poster_and_banners": {"albedo": "Reference_Detail_Atlas.png", "orm": "Reference_poster_and_banners_orm.png", "normal": "Finish_fabric_normal.png", "normal_scale": 0.8},
	"Workshop_blue_paint": {"albedo": "Workshop_blue_paint_basecolor.png", "orm": "Workshop_blue_paint_orm.png", "normal": "Finish_paint_normal.png", "normal_scale": 0.8},
	"Safety_yellow_paint": {"albedo": "Safety_yellow_paint_basecolor.png", "orm": "Safety_yellow_paint_orm.png", "normal": "Finish_paint_normal.png", "normal_scale": 0.8},
	"Coolant_bottle_green": {"albedo": "Coolant_bottle_green_basecolor.png", "orm": "Coolant_bottle_green_orm.png", "normal": "Finish_plastic_normal.png", "normal_scale": 0.8},
	"Hand_tool_orange": {"albedo": "Hand_tool_orange_basecolor.png", "orm": "Hand_tool_orange_orm.png", "normal": "Finish_plastic_normal.png", "normal_scale": 0.8},
	"Printed_labels": {"albedo": "Printed_labels_basecolor.png", "orm": "Printed_labels_orm.png", "normal": "Finish_paper_normal.png", "normal_scale": 0.8},
	"Valve_brass": {"albedo": "Valve_brass_basecolor.png", "orm": "Valve_brass_orm.png", "normal": "Finish_machined_normal.png", "normal_scale": 0.8},
	"Dark_oil_stain": {"albedo": "Dark_oil_stain_basecolor.png", "orm": "Dark_oil_stain_orm.png", "normal": "Finish_oil_normal.png", "normal_scale": 0.8},
	"Lift_warning": {"albedo": "Lift_warning.png", "orm": "Lift_warning_orm.png", "normal": "Finish_plastic_normal.png", "normal_scale": 0.8},
	"Turntable_nameplate": {"albedo": "Turntable_nameplate.png", "orm": "Turntable_nameplate_orm.png", "normal": "Finish_plastic_normal.png", "normal_scale": 0.8},
	"Moulded_tyresize_205_55_R16": {"albedo": "Tyre_sidewall_205_55_R16.png", "orm": "Moulded_tyresize_205_55_R16_orm.png", "normal": "Finish_rubber_normal.png", "normal_scale": 0.8},
	"Moulded_tyresize_275_35_R19": {"albedo": "Tyre_sidewall_275_35_R19.png", "orm": "Moulded_tyresize_275_35_R19_orm.png", "normal": "Finish_rubber_normal.png", "normal_scale": 0.8},
	"Moulded_tyresize_235_40_R18": {"albedo": "Tyre_sidewall_235_40_R18.png", "orm": "Moulded_tyresize_235_40_R18_orm.png", "normal": "Finish_rubber_normal.png", "normal_scale": 0.8},
	"Moulded_tyresize_225_45_R17": {"albedo": "Tyre_sidewall_225_45_R17.png", "orm": "Moulded_tyresize_225_45_R17_orm.png", "normal": "Finish_rubber_normal.png", "normal_scale": 0.8},
	"Garage_epoxy_floor": {"albedo": "Garage_epoxy_floor_basecolor.png", "orm": "Garage_epoxy_floor_orm.png", "normal": "Garage_epoxy_floor_normal.png", "normal_scale": 0.8},
	"Garage_wall_plaster": {"albedo": "Garage_wall_plaster_basecolor.png", "orm": "Garage_wall_plaster_orm.png", "normal": "Garage_wall_plaster_normal.png", "normal_scale": 0.8},
	"Garage_ceiling_powdercoat": {"albedo": "Garage_ceiling_powdercoat_basecolor.png", "orm": "Garage_ceiling_powdercoat_orm.png", "normal": "Garage_ceiling_powdercoat_normal.png", "normal_scale": 0.8},
	"Clear_partition_glass": {"albedo": "Clear_partition_glass_basecolor.png", "orm": "Clear_partition_glass_orm.png", "normal": "Finish_glass_normal.png", "normal_scale": 0.8},
	"Booth_enamel": {"albedo": "Booth_enamel_basecolor.png", "orm": "Booth_enamel_orm.png", "normal": "Finish_enamel_normal.png", "normal_scale": 0.8},
	"Honeycomb_LED_diffuser": {"albedo": "Honeycomb_LED_diffuser_basecolor.png", "orm": "Honeycomb_LED_diffuser_orm.png", "normal": "Finish_diffuser_normal.png", "normal_scale": 0.8, "emission": "Honeycomb_LED_diffuser_basecolor.png"},
	"Office_paper_and_keycaps": {"albedo": "Office_paper_and_keycaps_basecolor.png", "orm": "Office_paper_and_keycaps_orm.png", "normal": "Finish_paper_normal.png", "normal_scale": 0.8},
	"Nitrous_cobalt_enamel": {"albedo": "Nitrous_cobalt_enamel_basecolor.png", "orm": "Nitrous_cobalt_enamel_orm.png", "normal": "Finish_enamel_normal.png", "normal_scale": 0.8},
	"Pressure_gauge_face": {"albedo": "Pressure_gauge_face_basecolor.png", "orm": "Pressure_gauge_face_orm.png", "normal": "Finish_paper_normal.png", "normal_scale": 0.8},
	"Pneumatic_brass_fittings": {"albedo": "Pneumatic_brass_fittings_basecolor.png", "orm": "Pneumatic_brass_fittings_orm.png", "normal": "Finish_machined_normal.png", "normal_scale": 0.8},
	"Booth_non_slip_floor": {"albedo": "Booth_non_slip_floor_basecolor.png", "orm": "Booth_non_slip_floor_orm.png", "normal": "Booth_non_slip_floor_normal.png", "normal_scale": 0.8},
	"Office_dark_vinyl": {"albedo": "Office_dark_vinyl_basecolor.png", "orm": "Office_dark_vinyl_orm.png", "normal": "Office_dark_vinyl_normal.png", "normal_scale": 0.8},
	"Nitrous_bottle_label": {"albedo": "Nitrous_bottle_label.png", "orm": "Nitrous_bottle_label_orm.png", "normal": "Finish_paper_normal.png", "normal_scale": 0.8},
	"Compressor_rating_plate": {"albedo": "Compressor_rating_plate.png", "orm": "Compressor_rating_plate_orm.png", "normal": "Finish_plastic_normal.png", "normal_scale": 0.8},
	"Paint_mix_label": {"albedo": "Paint_mix_label.png", "orm": "Paint_mix_label_orm.png", "normal": "Finish_paper_normal.png", "normal_scale": 0.8},
	"Office_PC_screen": {"albedo": "Office_PC_screen.png", "orm": "Office_PC_screen_orm.png", "normal": "Finish_diffuser_normal.png", "normal_scale": 0.8},
	"Wet_forecourt_asphalt": {"albedo": "Wet_forecourt_asphalt_basecolor.png", "orm": "Wet_forecourt_asphalt_orm.png", "normal": "Wet_forecourt_asphalt_normal.png", "normal_scale": 0.8},
	"Rain_streak_translucent": {"albedo": "Rain_streak_translucent_basecolor.png", "orm": "Rain_streak_translucent_orm.png", "normal": "Finish_diffuser_normal.png", "normal_scale": 0.8},
	"Lightning_emission": {"albedo": "Lightning_emission_basecolor.png", "orm": "Lightning_emission_orm.png", "normal": "Finish_diffuser_normal.png", "normal_scale": 0.8},
	"Cast_aluminium": {"albedo": "Cast_aluminium_basecolor.png", "orm": "Cast_aluminium_orm.png", "normal": "Cast_aluminium_normal.png", "normal_scale": 0.8},
	"Engine_cast_iron": {"albedo": "Engine_cast_iron_basecolor.png", "orm": "Engine_cast_iron_orm.png", "normal": "Engine_cast_iron_normal.png", "normal_scale": 0.8},
	"Shop_cloth_weave": {"albedo": "Shop_cloth_weave_basecolor.png", "orm": "Shop_cloth_weave_orm.png", "normal": "Shop_cloth_weave_normal.png", "normal_scale": 0.8},
	"Chair_woven_upholstery": {"albedo": "Chair_woven_upholstery_basecolor.png", "orm": "Chair_woven_upholstery_orm.png", "normal": "Chair_woven_upholstery_normal.png", "normal_scale": 0.8},
	"BMX_saddle_vinyl": {"albedo": "BMX_saddle_vinyl_basecolor.png", "orm": "BMX_saddle_vinyl_orm.png", "normal": "BMX_saddle_vinyl_normal.png", "normal_scale": 0.8},
	"Mug_ceramic_glaze": {"albedo": "Mug_ceramic_glaze_basecolor.png", "orm": "Mug_ceramic_glaze_orm.png", "normal": "Mug_ceramic_glaze_normal.png", "normal_scale": 0.8},
	"Moulded_equipment_plastic": {"albedo": "Moulded_equipment_plastic_basecolor.png", "orm": "Moulded_equipment_plastic_orm.png", "normal": "Moulded_equipment_plastic_normal.png", "normal_scale": 0.8},
	"Compressor_copper_pipe": {"albedo": "Compressor_copper_pipe_basecolor.png", "orm": "Compressor_copper_pipe_orm.png", "normal": "Finish_machined_normal.png", "normal_scale": 0.8},
	"Compressor_calibrated_pressure_dial": {"albedo": "Compressor_calibrated_dial.png", "orm": "Compressor_calibrated_pressure_dial_orm.png", "normal": "Finish_plastic_normal.png", "normal_scale": 0.8},
}


## Gives every material of the model its textures (the ones it is missing).
static func apply(root: Node) -> int:
	var done := {}
	var n := 0
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(s) as BaseMaterial3D
			if mat == null or done.has(mat):
				continue
			done[mat] = true
			var e: Dictionary = MAP.get(mat.resource_name, {})
			if e.is_empty():
				continue
			if mat.albedo_texture == null and e.has("albedo"):
				mat.albedo_texture = _tex(e["albedo"])
			if mat.normal_texture == null and e.has("normal"):
				mat.normal_texture = _tex(e["normal"])
				mat.normal_enabled = mat.normal_texture != null
				mat.normal_scale = float(e.get("normal_scale", 1.0))
			if e.has("orm"):
				var orm := _tex(e["orm"])
				if mat is ORMMaterial3D:
					if (mat as ORMMaterial3D).orm_texture == null:
						(mat as ORMMaterial3D).orm_texture = orm
				else:
					if mat.roughness_texture == null and orm:
						mat.roughness_texture = orm
						mat.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
						mat.metallic_texture = orm
						mat.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE
						mat.ao_texture = orm
						mat.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
						mat.ao_enabled = true
			if e.has("emission") and mat.emission_texture == null:
				mat.emission_texture = _tex(e["emission"])
			n += 1
	return n


static func _tex(file: String) -> Texture2D:
	var p: String = DIR + file
	return load(p) as Texture2D if ResourceLoader.exists(p) else null

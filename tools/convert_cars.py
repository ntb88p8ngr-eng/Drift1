"""Converts the Blend Swap car models into game-ready GLB files for Midnight Drift.

Usage (Blender 4.x, or the `bpy` Python module):
    python3 tools/convert_cars.py <car_id> <source.blend> <output.glb>

What it does:
  * evaluates modifiers (mirror, solidify, curve, array, subdivision capped at one level)
  * drops studio props (floors, cameras, lamps, reference cubes)
  * sorts everything into body / 4 spinning wheels (rim+tyre+disc) / 4 static calipers
  * maps the source materials to a small set of named classes (paint, glass, head_lens, tail, …)
    so the game can swap in its own paint, glass and emissive light materials
  * decimates to a polygon budget, rotates to Godot's forward (-Z), scales to real length,
    puts the ground at y = 0 and the origin between the axles
  * writes <output>.json with wheel positions/radius and light positions for the physics setup
"""
import bpy, bmesh, sys, json, math
from mathutils import Matrix, Vector

# material class -> (base colour, metallic, roughness)
CLASSES = {
    "paint": ((0.62, 0.03, 0.03), 0.1, 0.2),
    "glass": ((0.02, 0.025, 0.03), 0.2, 0.05),
    "black": ((0.02, 0.02, 0.022), 0.0, 0.6),
    "trim": ((0.01, 0.01, 0.012), 0.0, 0.8),
    "grille": ((0.05, 0.05, 0.055), 0.4, 0.5),
    "chrome": ((0.8, 0.8, 0.82), 1.0, 0.12),
    "metal": ((0.35, 0.35, 0.37), 0.9, 0.35),
    "rim": ((0.3, 0.3, 0.32), 0.9, 0.3),
    "tyre": ((0.03, 0.03, 0.032), 0.0, 0.85),
    "disc": ((0.4, 0.4, 0.42), 0.9, 0.4),
    "caliper": ((0.7, 0.05, 0.04), 0.3, 0.35),
    "head_lens": ((0.85, 0.87, 0.9), 0.3, 0.05),
    "head_inner": ((0.6, 0.6, 0.62), 1.0, 0.15),
    "tail": ((0.6, 0.02, 0.02), 0.1, 0.1),
    "indicator": ((0.9, 0.45, 0.02), 0.1, 0.15),
    "red": ((0.7, 0.02, 0.02), 0.2, 0.3),
    "white": ((0.9, 0.9, 0.9), 0.0, 0.4),
    "mirror": ((0.9, 0.9, 0.92), 1.0, 0.02),
    "gold": ((0.62, 0.48, 0.16), 1.0, 0.28),
}

CARS = {
    "r34": {
        "length": 4.60, "subsurf": 1, "body_tris": 110000, "wheel_tris": 7000,
        "exclude": ["Cube", "Cube.001", "Sphere", "Plane", "Plane.001", "Plane.002", "Plane.003", "Plane.012",
                    "Plane.013", "Plane.014", "TunnelV2_4", "Lamp", "Camera"],
        "materials": {
            "Paint.000": "paint", "Paint.001": "paint", "carpaint": "paint",
            "SkylineFloat": "chrome", "FrontSpoiler.Black": "black", "Headlight.Inner": "black",
            "Keyhole": "trim", "Rubber.Trim": "trim", "Grille": "grille", "Material.003": "black",
            "WindowGlass": "glass", "Material.005": "mirror", "HeadlightFlashing": "head_inner",
            "Material.004": "head_inner", "HeadlightGlass": "head_lens", "Indicators": "indicator",
            "Indicators.001": "indicator", "Indicators.bulb": "indicator", "TailLight.Indicator": "indicator",
            "TailLights": "tail", "Reflectors": "tail", "GTR_Logo_metallic": "chrome", "Logo.Metal.001": "chrome",
            "Material.007": "metal", "GTR_Logo_Red": "red", "GTR.Alloy": "rim", "GTR.AlloyLogo": "chrome",
            "GTR.AlloyCap": "rim", "RUBBERTYRE.001": "tyre", "Metal.Floating.on": "disc", "Material.008": "caliper",
            None: "grille",
        },
        "object_class": {"RearDiffuser": "black", "Cylinder": "black", "Intercooler": "grille"},
        "wheel_parts": ["Alloy.GTR", "Plane.008", "Plane.009", "Plane.010", "Plane.011", "BrakeDisc"],
        "caliper_parts": ["Cube.002", "Cube.003", "Cube.004", "Cube.005"],
    },
    "mustang": {
        "length": 4.78, "subsurf": 1, "body_tris": 90000, "wheel_tris": 6000,
        "exclude": ["Plane.003", "Plane.005", "Lamp", "Camera", "Text", "Text.001"],
        "materials": {
            "Car paint": "paint", "Windows": "glass", "Black plastic": "black", "Black": "trim",
            "Orange": "indicator", "Orange.001": "indicator", "chrome": "chrome", "chrome plastic": "chrome",
            "chrome mirror": "mirror", "Glass": "head_lens", "Glass.001": "head_lens", "White": "head_lens",
            "Light": "head_lens", "Red": "tail", "Red 2": "tail", "Red 3": "tail", "Wheel": "rim",
            "Tyre": "tyre", "disk": "disc", "Break": "caliper", None: "chrome",
        },
        "object_class": {},
        "wheel_parts": ["Wheel front R", "Wheel front L", "Wheel back L", "Plane.028", "Plane.031", "Plane.033",
                        "Plane.034", "Circle.002", "Circle.003", "Circle.004", "Circle.005"],
        "caliper_parts": ["Plane.029", "Plane.030", "Plane.032", "Plane.035"],
    },
    "m3gt3": {
        "length": 4.62, "subsurf": 1, "body_tris": 80000, "wheel_tris": 5000,
        "exclude": ["Earth", "Light_Plane", "Lamp", "Lamp.006", "Camera", "CarCam"],
        "materials": {
            "Material": "paint", "plastic": "black", "chrome": "chrome", "Reifen": "tyre", "glass": "glass",
            "Bremsscheibe": "disc", "Chrome_red": "caliper", "Blinker": "tail", "LIght": "head_lens",
            "chrome_matt": "head_inner", None: "black",
        },
        "object_class": {},
        "wheel_parts": ["Felge_FR"],
        "caliper_parts": [],
        "wheel_material_override": {"chrome": "rim"},
    },
    "m3e46": {
        "length": 4.49, "subsurf": 1, "body_tris": 100000, "wheel_tris": 10000, "unsteer": True,
        "part_max_tris": {"LF Tire": 3000, "RF Tire": 3000, "LB Tire": 3000, "RB Tire": 3000, "LF Brake": 800,
                          "Brake Clamp FL": 600},
        "exclude": ["Studio 1 Floor", "Studio 1 Lights", "Studio 2 Background", "Studio 2 Background.001",
                    "Studio 2 Floor", "Studio 3 Floor", "Studio 3 Lights", "Studio 4 Floor", "Studio 5 Light Top",
                    "Grid Lights 1", "Grid Lights 2", "Grid Lights 3", "Grid Lights 4", "Grid Lights Bottom 1",
                    "Grid Lights Bottom 2", "Grid Lights Bottom 3", "Grid Lights Bottom 4", "Plane", "Sphere",
                    "Steering Controller", "Rim Class", "Tire Class", "Brake Class", "Rim Cap Class",
                    "Wheel Nuts Class", "Front Lower Grill Template", "Raw Doors", "Rearlight Glass.001"],
        "materials": {
            "Car Paint": "paint", "Window Glass": "glass", "Black Plastic Trim": "trim", "Blicker Glow": "indicator",
            "Chrome.001": "grille", "Disk Brake": "disc", "Headlight Glass": "head_lens",
            "Headlight Lamps": "head_inner", "Headlight Main Interior": "black", "Hidden Black Material": "black",
            "M3 Logo": "chrome", "Brake Caliper": "caliper", "Chrome": "chrome", "Matte Black": "black",
            "Rearlights Glass Red": "tail", "Rearlights Glass White": "white", "Rim BMW Cap": "chrome",
            "Rims ": "rim", "Shinty Black Grill": "grille", "Super Reflective": "chrome",
            "Tailight Bulb Red": "tail", "Tailight Main Red": "tail", "Tailight Main White": "white",
            "Tires": "tyre", "Titanium Blue Super Reflective": "head_inner", None: "black",
        },
        "object_materials": {"Taillight Bulbs": {"Headlight Lamps": "white"}},
        "object_class": {},
        "wheel_parts": ["LF Tire", "RF Tire", "LB Tire", "RB Tire"],
        "caliper_parts": ["Brake Clamp FL", "LF Suspension", "RF Suspension", "LB Suspension", "RB Suspension"],
    },
    "gallardo": {
        "length": 4.30, "subsurf": 1, "body_tris": 110000, "wheel_tris": 12000, "unsteer": True,
        "part_max_tris": {"Reifen": 4000, "Bremsscheibe": 1200, "Bremsaufnahme": 400, "Bremskoerper": 1500,
                          "Motor": 12000},
        "exclude": ["Earth", "Plane", "Plane.001", "Plane.002", "Plane.003", "Plane.004", "Plane.010", "Plane.011",
                    "Plane.012", "Amatur.002", "Amatur.003", "Hemi", "Point", "Bremsscheibe", "Bremsscheibe.001", "Bremsscheibe.002", "Bremsscheibe.003"],
        "materials": {
            "Lack": "paint", "lack": "paint", "mirrow": "chrome", "Black_Coat": "black", "Black_Metal": "black",
            "Blinker": "indicator", "blinker_glas": "indicator", "Break_Color": "caliper", "Yellow_Break": "caliper",
            "Breakdisk": "disc", "Chrome": "chrome", "Gallardo_logo": "chrome", "glass": "glass",
            "glass_rear": "tail", "Rear_glass": "tail", "emit_red": "tail", "Gold": "metal", "gum": "tyre",
            "guss": "metal", "Kupfer_red": "metal", "leder_black": "black", "leder_yellow": "black",
            "messing": "chrome", "plastic": "trim", "Rim": "rim", "Symbol": "chrome", "Tire": "tyre",
            "Velvet": "black", "Material": "trim", "Antisorp_Chrome": "chrome", "emit_blue": "black", None: "black",
        },
        "object_materials": {"Lampenfassung_front": {"glass": "head_lens", "mirrow": "head_inner", "Rim": "head_inner"},
                             "Motor": {"gum": "black"}, "Exhaust": {"Rim": "chrome"}, "Exhaust.001": {"Rim": "chrome"},
                             "Circle.001": {"Rim": "chrome"}, "Circle.002": {"Rim": "chrome"},
                             "backlight_cube": {"Rim": "chrome"}},
        "object_class": {},
        "wheel_parts": ["Rad_FL", "Rad_FR", "Rad_HL", "Reifen", "Bremse_FL", "Bremse_HL"],
        "caliper_parts": ["Bremskoerper", "Hydraulik"],
    },
    "gt3rsr": {
        "length": 4.43, "subsurf": 1, "body_tris": 90000, "wheel_tris": 6000, "front_pos_y": True,
        "exclude": ["earth", "lightwall.000", "lightwall.001", "lightwall.002"],
        "materials": {
            "Lack": "paint", "Lack_Black": "black", "Lack_red": "red", "chrome": "chrome", "plastic": "trim",
            "carbon": "black", "glas": "glass", "frontglas": "head_lens", "front_light_plane": "head_inner",
            "glas_red_back": "tail", "glas_white": "indicator", "Felgen_Alu_white": "metal",
            "Felgen_Alu_black": "black", "Tire": "tyre", "Kupfer": "disc", "Kohlefaser": "disc", "Messing": "metal",
            "Rost": "grille", "Porsche_Lack_Text": "white", "Porsche_logo_gold": "metal",
            "Porsche_logo_black": "black", "Porsche_logo_red": "red", "plastic_lightgray": "metal",
            "RECARO_sport_darkgray": "black", "RECARO_sport_gray": "black", "RECARO_sport_lightgray": "trim",
            "cord_red": "red", "metal_matt": "metal", None: "black",
        },
        "object_materials": {"Porsche_Frontscheinwerfer": {"glas": "head_lens", "chrome": "head_inner"}},
        "object_class": {},
        "wheel_parts": ["Porsche_wheel"],
        "caliper_parts": [],
        "wheel_material_override": {"Felgen_Alu_white": "rim", "Messing": "caliper"},
    },
    "aventador": {
        "length": 4.78, "subsurf": 1, "body_tris": 60000, "wheel_tris": 5000,
        "exclude": ["Ground", "LightSource", "light_key"],
        "materials": {
            "MattePaint": "paint", "Car Paint": "paint", "Glass": "glass", "MattePlastic": "black", "Grill": "grille",
            "Chrome_Glossy": "metal", "CarbonFibre": "black", "Light": "head_inner", "Trans": "head_lens",
            "Neon Light": "tail", "Logo": "chrome", "Plate": "black", "BrushedMetal": "metal",
            "DiskBrakeTexture": "disc", "Rubber": "tyre", "Red_Paint": "caliper", None: "black",
        },
        "object_materials": {},
        "object_class": {},
        "wheel_parts": ["FrontWheel", "RearWheel"],
        "split_x": ["FrontWheel", "RearWheel"],
        "caliper_parts": [],
        "wheel_material_override": {"BrushedMetal": "rim"},
    },
    "m4f82": {
        "length": 4.67, "subsurf": 1, "body_tris": 100000, "wheel_tris": 6000,
        "exclude": ["Ground", "Duplication_Plane_Tyre", "Duplication_Plane_Tyre_2", "Duplication_Plane_Tyre_3",
                    "Windscreen_for_lattice"],
        "materials": {
            "car_paint": "paint", "Black_mat": "black", "BMWBlack": "black", "BMWBlue": "trim",
            "BMWSilver": "chrome", "BMWWhite": "white", "chrome": "chrome", "chrome_headlight": "chrome",
            "chrome_red": "tail", "glass": "glass", "Interior": "black", "light": "head_inner",
            "Material": "head_inner", "Miror": "mirror", "Piano_Black": "black", "rearlight_red": "tail",
            "Reflectors": "tail", "rim": "rim", "rim.001": "chrome", "rim_screw.001": "metal",
            "Solid_black": "trim", "tailights": "tail", "tire_rubber": "tyre", None: "black",
        },
        "object_materials": {"Main_Body.002": {"glass": "head_lens"}, "Main_Body.014": {"glass": "head_lens"},
                             "Main_Body.012": {"glass": "tail"}},
        "object_class": {},
        "wheel_parts": [],
        "caliper_parts": [],
        "wheel_clone": {"parts": ["Rim", "Tyre", "Rim_cap"], "centre": [0.712, -1.528, 0.363], "radius": 0.45,
                        "targets": [[-0.712, -1.528], [0.712, 1.28], [-0.712, 1.28]]},
    },
}

# NPC traffic cars (city streets): a detailed model for close up and a light one for the distance
TRAFFIC = {
    "camry": {
        "length": 4.80, "subsurf": 1, "body_tris": 14000, "wheel_tris": 900, "unsteer": True,
        "exclude": ["Plane", "Interior.001", "interior_main", "interior_seats front", "interior_seats rear",
                    "Text", "Text.001", "Circle"],
        "materials": {
            "Car Paint (Metallic)": "paint", "Chrome": "chrome", "Chrome.001": "black", "Emit": "head_inner",
            "HL Glass": "head_lens", "Material.001": "head_lens", "Material.002": "chrome", "Material.003": "chrome",
            "Material.004": "black", "Material.005": "glass", "Material.006": "glass", "Material.007": "chrome",
            "Material.008": "trim", "Material.009": "black", "Material.010": "chrome", "Material.011": "chrome",
            "Material.012": "black", "RubberTires": "trim", "aaaa": "tail", "rear lamp glass": "tail",
            "brakeCaliper_brass": "caliper", "brakeCaliper_paint_noText": "caliper", "brakeCaliper_pads": "black",
            "brakeCaliper_steel": "caliper", "brakeDisc_chrome": "disc", "brakeDisc_metal_black": "disc",
            "brakeDisc_steel": "disc", "felga": "rim", "sruba'": "chrome", "opoma ": "tyre", "opona2": "tyre",
            "glass red.001": "tail", "glass.001": "glass", "taillight cheat.001": "tail", "taillights light": "tail",
            None: "black",
        },
        # the "taillights_glass" objects at the front are the headlight units
        "object_materials": {
            "taillights_glass.002": {"glass red.001": "indicator", "glass.001": "head_lens", "taillight cheat.001": "head_inner",
                                     "taillights light": "head_inner"},
            "taillights_glass.003": {"glass red.001": "indicator", "glass.001": "head_lens", "taillight cheat.001": "head_inner",
                                     "taillights light": "head_inner"},
        },
        "object_class": {},
        "wheel_parts": ["Plane.004", "Plane.005", "Plane.007", "Plane.010"],
        "caliper_parts": [],
        "part_max_tris": {"brakeDisc": 1500, "Plane.004": 3000, "Plane.005": 3000, "Plane.007": 3000, "Plane.010": 3000},
        "procedural_wheels": 0.205,
    },
    "impreza": {
        "length": 4.42, "subsurf": 1, "body_tris": 14000, "wheel_tris": 900, "unsteer": True,
        "exclude": ["Plane", "light_cycles_key", "light_cycles_fill", "ground_plane", "subaru_interior",
                    "subaru_interior_steering_wheel"],
        "exclude_parents": ["BACKUP"],
        "materials": {
            "subaru_carpaint": "paint", "black_plast": "black", "black_painted_metal": "black", "chrome_yellow": "gold",
            "chrome_mate": "metal", "wheel_center": "chrome", "break_lights": "tail", "car_light": "head_inner",
            "car_light_orange": "indicator", "chrome": "chrome", "chrome_strip_arch_front": "chrome",
            "expanded_metal": "grille", "glass": "glass", "glass_pure": "head_lens", "licence_plate": "white",
            "lights_back_interior": "chrome", "lights_back_interior_2": "chrome", "lights_back_interior_3": "chrome",
            "mirror": "mirror", "red_glossy": "tail", "rubber": "tyre", "subaru_marks": "black",
            "subaru_sign": "chrome", "subaru_undercarriage": "black", "white_plast": "white", "interior": "black",
            None: "black",
        },
        "object_materials": {"subaru_lights_back": {"glass_pure": "tail"}, "subaru_back_doors": {"glass_pure": "tail"}},
        "object_class": {},
        "wheel_parts": ["subaru_wheel.B.R", "subaru_wheel.B.L", "subaru_wheel.F.R", "subaru_wheel.F.L"],
        "caliper_parts": [],
        "part_max_tris": {"subaru_wheel": 5000, "subaru_wheel_tire": 3000, "subaru_lights_back": 3000, "subaru_back_doors": 4000,
                          "subaru_rearview_mirror": 1500, "subaru_wipers": 800, "subaru_bumper_front": 5000,
                          "subaru_lights_front": 3000},
    },
    "civic": {
        "length": 4.14, "subsurf": 1, "body_tris": 14000, "wheel_tris": 900,
        "exclude": ["Plane", "Plane.001", "Recaro_seats", "Rear_seat_bench", "DashBoard", "Steering_wheel",
                    "Inside_mirror", "TypeR_Logo_front", "Civic_logo", "Roof_antenna"],
        "exclude_parents": ["TypeR_Logo_back"],
        "materials": {
            "Red_paint": "paint", "BlackPLastic": "tyre", "Rim_metal": "rim", "Tyre_Marks": "tyre", "Black_Metal": "black",
            "Black_Plastic": "black", "Black_Plastic_Headlights": "black", "Black_difuse": "black",
            "Brake_Disc.001": "disc", "Brake_disc_metal.001": "disc", "Red_Brake_metal.001": "caliper",
            "Fog_Bulb": "white", "Fog_Glass": "head_lens", "Headlight_metal": "head_inner",
            "Headlight_metal_Hex": "head_inner", "Headlights_Glass": "head_lens", "Honda_logo": "chrome",
            "Lights_glass_headlight": "head_lens", "Mirror": "mirror", "Rear_lights_glass": "tail",
            "Shiny_metal": "chrome", "Shiny_metal_Exhaust": "chrome", "Shiny_metal_red": "tail",
            "Shiny_metal_red_hex": "tail", "Shiny_metal_red_ribbed": "tail", "Shiny_metal_ribbed": "chrome",
            "Side_mirror_blinker_glass": "indicator", "Spoiler_light": "tail", "Underside": "black",
            "Windows": "glass", "Yellow_bulb": "indicator", "type-r": "white", None: "black",
        },
        "object_materials": {"Front_Wipers": {"Tyre_Marks": "trim"}, "Rear_Wiper": {"Tyre_Marks": "trim"}},
        "object_class": {},
        "wheel_parts": ["Eagle_F1"],
        "caliper_parts": ["Brakes"],
        # one object holds all four tyres / all four brakes: cut into the four corners
        "split_quad": ["Eagle_F1", "Brakes"],
        "part_max_tris": {"Eagle_F1": 14000, "Brakes": 3000, "Front_Grille_Mesh": 2500, "UnderTray": 3000,
                          "Stop_lights_inside": 3000, "Headlights_Inside": 3000, "Side_Mirrors": 2000,
                          "Front_Wipers": 800, "Rear_Wiper": 400, "Exhaust": 800, "Fog_lights": 1200},
    },
}
for _k, _cfg in list(TRAFFIC.items()):
    CARS[_k] = _cfg
    CARS[_k] = dict(_cfg, wheel_tris=_cfg.get("wheel_tris_hi", _cfg["wheel_tris"]))
    CARS[_k + "_lo"] = dict(_cfg, body_tris=1800, wheel_tris=200)

WHEELS = ["FL", "FR", "RL", "RR"]


def log(*a):
    print("[convert]", *a, flush=True)


def matches(name, prefixes):
    return any(name == p or name.startswith(p + ".") or name.startswith(p) and p.endswith(" ") for p in prefixes)


def ancestor_matches(ob, prefixes):
    while ob is not None:
        if matches(ob.name, prefixes):
            return True
        ob = ob.parent
    return False


def split_mesh(me, keep_fn):
    """Returns (kept, rest): two meshes with the faces for which keep_fn(face_centre) is true / false."""
    bm = bmesh.new()
    bm.from_mesh(me)
    bm2 = bm.copy()
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if not keep_fn(f.calc_center_median())], context="FACES")
    bmesh.ops.delete(bm2, geom=[f for f in bm2.faces if keep_fn(f.calc_center_median())], context="FACES")
    me2 = me.copy()
    bm.to_mesh(me)
    bm2.to_mesh(me2)
    bm.free()
    bm2.free()
    return me, me2


def _eval_mods(me, mods):
    o = bpy.data.objects.new("_dec", me)
    bpy.context.scene.collection.objects.link(o)
    for kind, opts in mods:
        m = o.modifiers.new(kind.lower(), kind)
        for k, v in opts.items():
            setattr(m, k, v)
    dg = bpy.context.evaluated_depsgraph_get()
    out = bpy.data.meshes.new_from_object(o.evaluated_get(dg), depsgraph=dg)
    bpy.data.objects.remove(o, do_unlink=True)
    return out


def _tris(me):
    return sum(len(p.vertices) - 2 for p in me.polygons)


def decimate_mesh(me, target_tris):
    """Decimates one heavy part on its own (so it does not eat the budget of its neighbours).
    Collapse first; when that gets stuck, dissolve the flat detail (drilled discs, grooves) and collapse again."""
    tris = _tris(me)
    if tris <= target_tris:
        return me
    best = _eval_mods(me, [("DECIMATE", {"ratio": max(target_tris / tris, 0.01), "use_collapse_triangulate": True})])
    if _tris(best) > target_tris * 1.5:
        flat = _eval_mods(me, [("DECIMATE", {"decimate_type": "DISSOLVE", "angle_limit": math.radians(4.0)}),
                               ("TRIANGULATE", {})])
        t2 = _tris(flat)
        if t2 > target_tris:
            flat = _eval_mods(flat, [("DECIMATE", {"ratio": max(target_tris / t2, 0.01), "use_collapse_triangulate": True})])
        if _tris(flat) < _tris(best):
            best = flat
    return best


def proc_wheel(R, W, class_mats, seg=32, spokes=5):
    """A wheel about the X axis at the origin: tyre with rounded shoulders, a five-spoke alloy on both
    faces, dark brake area behind the spokes."""
    bm = bmesh.new()
    rim_r = R * 0.66
    hw = W * 0.5
    def lathe(prof, mat):
        rings = []
        for x, r in prof:
            ring = []
            for k in range(seg):
                a = 2.0 * math.pi * k / seg
                ring.append(bm.verts.new((x, r * math.cos(a), r * math.sin(a))))
            rings.append(ring)
        for i in range(len(rings) - 1):
            for k in range(seg):
                k2 = (k + 1) % seg
                f = bm.faces.new((rings[i][k], rings[i][k2], rings[i + 1][k2], rings[i + 1][k]))
                f.material_index = mat
                f.smooth = True
    # tyre: inner sidewall, shoulders, tread, other side
    lathe([(-hw, rim_r), (-hw, R * 0.86), (-hw + W * 0.08, R * 0.97), (-hw + W * 0.22, R),
           (hw - W * 0.22, R), (hw - W * 0.08, R * 0.97), (hw, R * 0.86), (hw, rim_r)], 0)
    # rim lip and barrel
    lathe([(hw, rim_r), (hw - W * 0.06, rim_r * 0.97), (-hw + W * 0.06, rim_r * 0.97), (-hw, rim_r)], 1)
    for side in (-1.0, 1.0):
        x = side * (hw - W * 0.12)
        # dark disc behind the spokes
        lathe([(x - side * 0.01, 0.0001), (x - side * 0.01, rim_r * 0.96)], 2)
        # hub
        lathe([(x + side * 0.012, 0.0001), (x + side * 0.012, rim_r * 0.2), (x, rim_r * 0.24)], 1)
        # spokes: tapered boxes from the hub to the lip
        for k in range(spokes):
            a = 2.0 * math.pi * k / spokes
            d = Vector((0.0, math.cos(a), math.sin(a)))
            t = Vector((0.0, -math.sin(a), math.cos(a)))
            pts = []
            for rr, wd in ((rim_r * 0.18, rim_r * 0.16), (rim_r * 0.97, rim_r * 0.24)):
                for sx in (0.0, side * 0.018):
                    for st in (-1.0, 1.0):
                        pts.append(Vector((x + sx, 0.0, 0.0)) + d * rr + t * (wd * 0.5 * st))
            v = [bm.verts.new(p) for p in pts]
            quads = [(0, 1, 5, 4), (2, 3, 7, 6), (0, 4, 6, 2), (1, 5, 7, 3), (0, 1, 3, 2), (4, 5, 7, 6)]
            for q in quads:
                f = bm.faces.new([v[i] for i in q])
                f.material_index = 1
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new("procwheel")
    bm.to_mesh(me)
    bm.free()
    for cls in ("tyre", "rim", "black"):
        me.materials.append(class_mats[cls])
    return me


def main():
    car_id, src, out = sys.argv[-3], sys.argv[-2], sys.argv[-1]
    cfg = CARS[car_id]
    bpy.ops.wm.open_mainfile(filepath=src)
    scene = bpy.context.scene
    for ob in scene.objects:
        for m in getattr(ob, "modifiers", []):
            if m.type == "SUBSURF":
                m.levels = min(m.levels, cfg["subsurf"])
                m.render_levels = m.levels
    deps = bpy.context.evaluated_depsgraph_get()

    class_mats = {}
    for cls, (col, met, rough) in CLASSES.items():
        mat = bpy.data.materials.new("md_" + cls)
        mat.use_nodes = True
        bsdf = mat.node_tree.nodes.get("Principled BSDF")
        bsdf.inputs["Base Color"].default_value = (*col, 1.0)
        bsdf.inputs["Metallic"].default_value = met
        bsdf.inputs["Roughness"].default_value = rough
        class_mats[cls] = mat

    parts = []  # dict(kind, mesh, center)
    for ob in list(scene.objects):
        if ob.type not in ("MESH", "CURVE", "FONT", "SURFACE"):
            continue
        if ob.hide_render or ob.name in cfg["exclude"]:
            continue
        if cfg.get("exclude_parents") and ancestor_matches(ob, cfg["exclude_parents"]):
            continue
        if ob.users_collection and all(c.hide_render for c in ob.users_collection):
            continue
        ev = ob.evaluated_get(deps)
        try:
            me = bpy.data.meshes.new_from_object(ev, preserve_all_data_layers=False, depsgraph=deps)
        except Exception as e:  # noqa
            continue
        if me is None or len(me.polygons) == 0:
            continue
        me.transform(ob.matrix_world)
        if ob.matrix_world.determinant() < 0.0:
            # mirrored object: the transform turned the faces inside out
            bm = bmesh.new()
            bm.from_mesh(me)
            bmesh.ops.reverse_faces(bm, faces=bm.faces)
            bm.to_mesh(me)
            bm.free()
        # material classes
        src_names = [m.name if m else None for m in me.materials]
        if not src_names:
            src_names = [None]
        forced = cfg["object_class"].get(ob.name)
        per_obj = cfg.get("object_materials", {}).get(ob.name, {})
        classes = []
        for n in src_names:
            cls = forced or per_obj.get(n) or cfg["materials"].get(n)
            if cls is None and n and "." in n:
                cls = cfg["materials"].get(n.rsplit(".", 1)[0])
            if cls is None:
                cls = cfg["materials"].get(None, "black")
            classes.append(cls)
        kind = "body"
        base = ob.name
        if matches(base, cfg["caliper_parts"]):
            kind = "caliper"
        elif ancestor_matches(ob, cfg["wheel_parts"]):
            kind = "wheel"
        if kind == "wheel" and cfg.get("wheel_material_override"):
            classes = [cfg["wheel_material_override"].get(n, c) for n, c in zip(src_names, classes)]
        # materials.clear() resets the per-face indices, so keep and restore them
        face_idx = [0] * len(me.polygons)
        me.polygons.foreach_get("material_index", face_idx)
        me.materials.clear()
        for c in classes:
            me.materials.append(class_mats[c])
        face_idx = [min(i, len(classes) - 1) for i in face_idx]
        me.polygons.foreach_set("material_index", face_idx)
        for pref, cap in cfg.get("part_max_tris", {}).items():
            if matches(ob.name, [pref]):
                me = decimate_mesh(me, cap)
        parts.append({"name": ob.name, "kind": kind, "mesh": me})
    # objects that hold the wheels of both sides (split at the car's centre line)
    for p in list(parts):
        if p["kind"] == "wheel" and matches(p["name"], cfg.get("split_x", [])):
            a, b = split_mesh(p["mesh"], lambda c: c.x < 0.0)
            p["mesh"] = a
            parts.append({"name": p["name"] + "_r", "kind": "wheel", "mesh": b})
    # objects that hold all four wheels / brakes: cut at the centre line and between the axles
    if cfg.get("split_quad"):
        allb = [p["mesh"] for p in parts if p["kind"] == "body"]
        ys = [v.co.y for me in allb for v in me.vertices]
        y_mid = (min(ys) + max(ys)) * 0.5
        for p in list(parts):
            if matches(p["name"], cfg["split_quad"]):
                left, right = split_mesh(p["mesh"], lambda c: c.x < 0.0)
                fl, rl = split_mesh(left, lambda c: c.y < y_mid)
                fr, rr = split_mesh(right, lambda c: c.y < y_mid)
                p["mesh"] = fl
                for me, suf in ((rl, "_rl"), (fr, "_fr"), (rr, "_rr")):
                    parts.append({"name": p["name"] + suf, "kind": p["kind"], "mesh": me})
    # one modelled wheel copied to the other corners (lost collection instancing in old files)
    wc = cfg.get("wheel_clone")
    if wc:
        c0 = Vector(wc["centre"])
        src = [p for p in parts if matches(p["name"], wc["parts"])]
        for p in src:
            p["kind"] = "wheel"
            # drop stray geometry far from the wheel
            p["mesh"], junk = split_mesh(p["mesh"], lambda c: (c - c0).length < wc["radius"])
        for tx, ty in wc["targets"]:
            turn = (tx < 0.0) != (c0.x < 0.0)
            M = Matrix.Translation(Vector((tx, ty, c0.z))) @ (Matrix.Rotation(math.pi, 4, "Z") if turn else Matrix()) \
                @ Matrix.Translation(-c0)
            for p in src:
                me = p["mesh"].copy()
                me.transform(M)
                parts.append({"name": p["name"] + "_copy", "kind": "wheel", "mesh": me})
    log("parts", len(parts), "body", sum(1 for p in parts if p["kind"] == "body"),
        "wheel", sum(1 for p in parts if p["kind"] == "wheel"), "caliper", sum(1 for p in parts if p["kind"] == "caliper"))

    # split caliper-class faces out of wheel meshes (e.g. BMW)
    extra = []
    for p in parts:
        if p["kind"] != "wheel":
            continue
        me = p["mesh"]
        cal_idx = [i for i, m in enumerate(me.materials) if m and m.name == "md_caliper"]
        if not cal_idx:
            continue
        bm = bmesh.new()
        bm.from_mesh(me)
        bm2 = bm.copy()
        bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.material_index in cal_idx], context="FACES")
        bmesh.ops.delete(bm2, geom=[f for f in bm2.faces if f.material_index not in cal_idx], context="FACES")
        bm.to_mesh(me)
        me2 = me.copy()
        bm2.to_mesh(me2)
        bm.free()
        bm2.free()
        if len(me2.polygons):
            extra.append({"name": p["name"] + "_cal", "kind": "caliper", "mesh": me2})
    parts += extra

    def bbox(meshes):
        mn = Vector((1e9, 1e9, 1e9))
        mx = Vector((-1e9, -1e9, -1e9))
        for me in meshes:
            for v in me.vertices:
                for i in range(3):
                    mn[i] = min(mn[i], v.co[i])
                    mx[i] = max(mx[i], v.co[i])
        return mn, mx

    body_mn, body_mx = bbox([p["mesh"] for p in parts if p["kind"] == "body"])
    scale = cfg["length"] / (body_mx.y - body_mn.y)
    fwd_pos = bool(cfg.get("front_pos_y", False))
    x_mid0 = (body_mn.x + body_mx.x) * 0.5
    # wheel quadrant from each part's centre (front = -Y in all source files)
    for p in parts:
        if p["kind"] == "body":
            continue
        mn, mx = bbox([p["mesh"]])
        c = (mn + mx) * 0.5
        front = (c.y < (body_mn.y + body_mx.y) * 0.5) != fwd_pos
        left_src = c.x < x_mid0
        # after the 180° turn the source -X side becomes the car's right side
        side = ("L" if left_src else "R") if fwd_pos else ("R" if left_src else "L")
        p["slot"] = ("F" if front else "R") + side
    wheel_meshes = {w: [p["mesh"] for p in parts if p["kind"] == "wheel" and p["slot"] == w] for w in WHEELS}
    if cfg.get("unsteer"):
        # wheels modelled steered/toed: turn each one straight about its centre (axle = least-variance axis)
        import numpy as np
        for w, ms in wheel_meshes.items():
            pts = np.array([v.co[:] for me in ms for v in me.vertices])
            c = pts.mean(axis=0)
            ev, evec = np.linalg.eigh(np.cov((pts - c).T))
            ax = evec[:, 0]
            ang = math.atan2(ax[1], ax[0])
            if ang > math.pi / 2:
                ang -= math.pi
            elif ang < -math.pi / 2:
                ang += math.pi
            if abs(ang) < math.radians(0.5):
                continue
            log("unsteer", w, round(math.degrees(ang), 1))
            mn, mx = bbox(ms)
            cc = (mn + mx) * 0.5
            R = Matrix.Translation(cc) @ Matrix.Rotation(-ang, 4, "Z") @ Matrix.Translation(-cc)
            for p in parts:
                if p["kind"] != "body" and p["slot"] == w:
                    p["mesh"].transform(R)

    if cfg.get("procedural_wheels"):
        # the source wheels don't survive the reduction: clean modelled ones at the same place and size
        tyre_w = cfg["procedural_wheels"] / scale
        for w in WHEELS:
            mn, mx = bbox(wheel_meshes[w])
            c = (mn + mx) * 0.5
            r = (mx.z - mn.z) * 0.5
            parts[:] = [p for p in parts if not (p["kind"] == "wheel" and p["slot"] == w)]
            me = proc_wheel(r, tyre_w, class_mats)
            me.transform(Matrix.Translation(c))
            parts.append({"name": "procwheel_" + w, "kind": "wheel", "mesh": me, "slot": w})
        wheel_meshes = {w: [p["mesh"] for p in parts if p["kind"] == "wheel" and p["slot"] == w] for w in WHEELS}

    tyre_mn, tyre_mx = bbox([m for ms in wheel_meshes.values() for m in ms])
    centres = {}
    for w, ms in wheel_meshes.items():
        mn, mx = bbox(ms)
        centres[w] = (mn + mx) * 0.5
    axle_mid_y = (centres["FL"].y + centres["RL"].y) * 0.5
    x_mid = (body_mn.x + body_mx.x) * 0.5
    # G = scale * rotZ(180) * translate(-mid), then lift so the tyres touch y=0
    T = Matrix.Translation(Vector((-x_mid, -axle_mid_y, -tyre_mn.z)))
    G = Matrix.Scale(scale, 4) @ (Matrix() if fwd_pos else Matrix.Rotation(math.pi, 4, "Z")) @ T
    for p in parts:
        p["mesh"].transform(G)

    coll = scene.collection
    for ob in list(scene.objects):
        bpy.data.objects.remove(ob, do_unlink=True)

    def make_object(name, meshes):
        objs = []
        for i, me in enumerate(meshes):
            o = bpy.data.objects.new("%s_%d" % (name, i), me)
            coll.objects.link(o)
            objs.append(o)
        bpy.ops.object.select_all(action="DESELECT")
        for o in objs:
            o.select_set(True)
        bpy.context.view_layer.objects.active = objs[0]
        if len(objs) > 1:
            bpy.ops.object.join()
        o = bpy.context.view_layer.objects.active
        o.name = name
        o.data.name = name
        return o

    def decimate(o, target_tris):
        tris = sum(len(p.vertices) - 2 for p in o.data.polygons)
        if tris <= target_tris:
            return tris
        m = o.modifiers.new("dec", "DECIMATE")
        m.ratio = max(target_tris / tris, 0.02)
        m.use_collapse_triangulate = True
        dg = bpy.context.evaluated_depsgraph_get()
        me2 = bpy.data.meshes.new_from_object(o.evaluated_get(dg), depsgraph=dg)
        o.modifiers.remove(m)
        old = o.data
        o.data = me2
        bpy.data.meshes.remove(old)
        return sum(len(p.vertices) - 2 for p in o.data.polygons)

    def smooth(o, angle_deg=40.0):
        me = o.data
        bm = bmesh.new()
        bm.from_mesh(me)
        bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.0004)
        for f in bm.faces:
            f.smooth = True
        lim = math.radians(angle_deg)
        for e in bm.edges:
            if len(e.link_faces) == 2:
                if e.calc_face_angle(0.0) > lim:
                    e.smooth = False
            else:
                e.smooth = False
        bm.to_mesh(me)
        bm.free()

    meta = {"car": car_id, "wheels": {}, "lights": {}}
    body = make_object("body", [p["mesh"] for p in parts if p["kind"] == "body"])
    log("body tris", decimate(body, cfg["body_tris"]))
    smooth(body)
    finals = [body]
    radius = 0.0
    width = 0.0
    for w in WHEELS:
        ms = [p["mesh"] for p in parts if p["kind"] == "wheel" and p["slot"] == w]
        o = make_object("wheel_" + w.lower(), ms)
        decimate(o, cfg["wheel_tris"])
        smooth(o, 50.0)
        mn, mx = bbox([o.data])
        c = (mn + mx) * 0.5
        o.data.transform(Matrix.Translation(-c))
        o.location = c
        radius = max(radius, (mx.z - mn.z) * 0.5)
        width = max(width, mx.x - mn.x)
        # Godot coordinates: (x, z, -y)
        meta["wheels"][w] = [c.x, c.z, -c.y]
        finals.append(o)
        cms = [p["mesh"] for p in parts if p["kind"] == "caliper" and p["slot"] == w]
        if cms:
            co = make_object("caliper_" + w.lower(), cms)
            decimate(co, 800)
            smooth(co)
            co.data.transform(Matrix.Translation(-c))
            co.location = c
            finals.append(co)
    meta["wheel_radius"] = radius
    meta["wheel_width"] = width
    bmn, bmx = bbox([body.data])
    meta["length"] = bmx.y - bmn.y
    meta["width"] = bmx.x - bmn.x
    meta["height"] = bmx.z
    meta["bottom"] = bmn.z
    # light positions (Godot coordinates) from the classified faces
    for cls in ("head_lens", "tail"):
        pts = {"L": [], "R": []}
        idx = [i for i, m in enumerate(body.data.materials) if m and m.name == "md_" + cls]
        for poly in body.data.polygons:
            if poly.material_index in idx:
                c = poly.center
                pts["L" if c.x < 0 else "R"].append(c.copy())
        for side, arr in pts.items():
            if arr:
                s = Vector((0, 0, 0))
                for v in arr:
                    s += v
                s /= len(arr)
                meta["lights"]["%s_%s" % (cls, side)] = [s.x, s.z, -s.y]
    bpy.ops.object.select_all(action="DESELECT")
    for o in finals:
        o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", use_selection=True, export_yup=True,
                              export_apply=False, export_texcoords=False, export_normals=True,
                              export_materials="EXPORT", export_cameras=False, export_lights=False,
                              export_extras=False, export_animations=False)
    with open(out + ".json", "w") as f:
        json.dump(meta, f, indent=1)
    log("done", out, json.dumps(meta))


main()

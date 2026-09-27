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
}

WHEELS = ["FL", "FR", "RL", "RR"]


def log(*a):
    print("[convert]", *a, flush=True)


def matches(name, prefixes):
    return any(name == p or name.startswith(p + ".") or name.startswith(p) and p.endswith(" ") for p in prefixes)


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
        # material classes
        src_names = [m.name if m else None for m in me.materials]
        if not src_names:
            src_names = [None]
        forced = cfg["object_class"].get(ob.name)
        classes = []
        for n in src_names:
            cls = forced or cfg["materials"].get(n)
            if cls is None:
                cls = cfg["materials"].get(None, "black")
            classes.append(cls)
        kind = "body"
        base = ob.name
        if matches(base, cfg["wheel_parts"]) or (ob.parent and matches(ob.parent.name, cfg["wheel_parts"])):
            kind = "wheel"
        elif matches(base, cfg["caliper_parts"]):
            kind = "caliper"
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
        parts.append({"name": ob.name, "kind": kind, "mesh": me})
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
    # wheel quadrant from each part's centre (front = -Y in all source files)
    for p in parts:
        if p["kind"] == "body":
            continue
        mn, mx = bbox([p["mesh"]])
        c = (mn + mx) * 0.5
        front = c.y < (body_mn.y + body_mx.y) * 0.5
        left_src = c.x < 0.0
        # after the 180° turn the source -X side becomes the car's right side
        side = "R" if left_src else "L"
        p["slot"] = ("F" if front else "R") + side
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
    G = Matrix.Scale(scale, 4) @ Matrix.Rotation(math.pi, 4, "Z") @ T
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

"""Splits the JDM rim pack (realistic_jdm_rim_pack.glb, Sketchfab) into one GLB per wheel for the rim tuning.

Usage (Blender 4.x or the `bpy` module):
    python3 tools/convert_rims.py <rim_pack.glb> <out_dir>

Each wheel (rim, tyre, bolts, textures kept) is centred on its axle, turned so its face looks along +X
(the outside of a right-hand wheel in the game), decimated, and written to <out_dir>/jdm_<n>.glb with
<out_dir>/jdm_<n>.json holding its tyre radius and width (the game scales it to each car's wheels).
"""
import bpy, bmesh, sys, json, math
from mathutils import Matrix, Vector

BUDGET = {"Bolt": 600, "BoltM": 300, "Material.002": 1500, "Material.003": 2500}
RIM_TRIS = 9000


def tris(me):
    return sum(len(p.vertices) - 2 for p in me.polygons)


def decimate(o, target):
    t = tris(o.data)
    if t <= target:
        return
    m = o.modifiers.new("dec", "DECIMATE")
    m.ratio = max(target / t, 0.02)
    m.use_collapse_triangulate = True
    dg = bpy.context.evaluated_depsgraph_get()
    me2 = bpy.data.meshes.new_from_object(o.evaluated_get(dg), depsgraph=dg)
    o.modifiers.remove(m)
    o.data = me2


def main():
    src, out = sys.argv[-2], sys.argv[-1]
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=src)
    groups = {}
    for ob in bpy.data.objects:
        if ob.type != "MESH":
            continue
        n = ob.parent
        while n is not None and not n.name.startswith("Rim"):
            n = n.parent
        if n is not None:
            groups.setdefault(n.name, []).append(ob)
    for gname in sorted(groups):
        idx = int(gname[3:])
        objs = []
        for ob in groups[gname]:
            me = ob.data.copy()
            me.transform(ob.matrix_world)
            o = bpy.data.objects.new(ob.name + "_w", me)
            bpy.context.scene.collection.objects.link(o)
            mat = me.materials[0].name if me.materials else ""
            decimate(o, BUDGET.get(mat, RIM_TRIS))
            objs.append(o)
        import numpy as np
        # the wheels lie at an angle in the pack: the axle is the direction the tyre is thinnest in
        tyre = [o for o in objs if o.data.materials and o.data.materials[0].name.startswith("Material.00")]
        pts = np.array([v.co[:] for o in (tyre or objs) for v in o.data.vertices])
        c = Vector(pts.mean(axis=0))
        ev, evec = np.linalg.eigh(np.cov((pts - pts.mean(axis=0)).T))
        axle = Vector(evec[:, 0]).normalized()
        # the face (where the bolts are) looks out along +X
        bolts = [v.co for o in objs if o.data.materials and o.data.materials[0].name.startswith("Bolt") for v in o.data.vertices]
        if bolts:
            bc = Vector((0, 0, 0))
            for b in bolts:
                bc += b
            bc /= len(bolts)
            if (bc - c).dot(axle) < 0.0:
                axle = -axle
        M = axle.rotation_difference(Vector((1, 0, 0))).to_matrix().to_4x4() @ Matrix.Translation(-c)
        for o in objs:
            o.data.transform(M)
            for p in o.data.polygons:
                p.use_smooth = True
        mn = Vector((1e9, 1e9, 1e9))
        mx = Vector((-1e9, -1e9, -1e9))
        for o in objs:
            for v in o.data.vertices:
                for i in range(3):
                    mn[i] = min(mn[i], v.co[i])
                    mx[i] = max(mx[i], v.co[i])
        radius = max(mx.y - mn.y, mx.z - mn.z) * 0.5
        width = mx.x - mn.x
        bpy.ops.object.select_all(action="DESELECT")
        for o in objs:
            o.select_set(True)
        bpy.context.view_layer.objects.active = objs[0]
        bpy.ops.object.join()
        w = bpy.context.view_layer.objects.active
        w.name = "rim"
        path = "%s/jdm_%d.glb" % (out, idx)
        bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_yup=True,
                                  export_texcoords=True, export_normals=True, export_materials="EXPORT",
                                  export_image_format="JPEG", export_cameras=False, export_lights=False,
                                  export_animations=False)
        with open("%s/jdm_%d.json" % (out, idx), "w") as f:
            json.dump({"radius": radius, "width": width, "tris": tris(w.data)}, f)
        print("[rims]", path, "radius %.3f width %.3f tris %d" % (radius, width, tris(w.data)), flush=True)
        bpy.data.objects.remove(w, do_unlink=True)


main()

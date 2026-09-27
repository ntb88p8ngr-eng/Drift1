"""Converts the garage scene (3ds Max .max) into assets/env/garage.glb for the menu showroom.

Usage (bpy 4.x as a Python module, or Blender's Python):
    python3 tools/convert_garage.py <Garage.max> <textures_dir> <output.glb> <io_scene_max_parent_dir>

The .max parser is the "Import Autodesk MAX" add-on (io_scene_max, GPL, Sebastian Schrand) from
https://github.com/blender/blender-addons-contrib – pass the directory that contains `io_scene_max`.
The add-on itself only imports raw geometry, so this script reads the chunks directly to also get:
  * texture coordinates (Editable Mesh map channel 1, Editable Poly map channel 1)
  * the texture of every node: the .max file only stores 16x16 thumbnails of its bitmaps, which are
    matched against the delivered texture files
It keeps only the garage building (no demo car, lights, cameras, ground plane), puts the floor at
y = 0 and writes a GLB with JPEG textures plus <output>.json with the room bounds.
"""
import sys, os, glob, json, math
import numpy as np
from PIL import Image
import bpy
import bmesh
from mathutils import Matrix, Vector

MAX_FILE, TEX_DIR, OUT, ADDON_DIR = sys.argv[1:5]
sys.path.insert(0, ADDON_DIR)
from io_scene_max import import_max as M  # noqa: E402

# material setup per texture: (roughness, metallic, emission strength, alpha blend)
LOOKS = {
    "Brick_Wall_01_12690": (0.85, 0.0, 0.0, False),
    "Conc_Floor_01_12680": (0.55, 0.0, 0.0, False),
    "Pillars_Conc_Combined_12626": (0.8, 0.0, 0.0, False),
    "Garage_Props_01_12636": (0.6, 0.2, 0.0, False),
    "Garage_Props_01_Unlit_12674": (0.7, 0.0, 0.0, False),
    "Garage_Alpha_Details_01_12576": (0.5, 0.0, 0.0, False),
    "G_Glass_12592": (0.05, 0.0, 0.0, True),
}
# bitmaps whose thumbnail matches nothing (the texture was edited after the scene was saved)
UNMATCHED_POSTER = "Garage_Alpha_Details_01_12576"
UNMATCHED_OTHER = "Garage_Props_01_12636"
# the turntable stands in the middle of the hall (between the pillar rows at x = ±7 m);
# small floor props (work lamps, tool boxes) inside this radius are removed
STAGE_CENTRE = (0.0, 0.5)     # Godot x, z
STAGE_CLEAR_R = 3.9
STAGE_DISC_R = 3.45          # everything low inside the turntable disc goes (cables, decals, lamp bases)


def load_max(fn):
    mf = M.ImportMaxFile(fn)
    M.read_class_data(mf, fn)
    M.read_config(mf, fn)
    M.read_directory(mf, fn)
    M.read_class_directory(mf, fn)
    M.read_video_postqueue(mf, fn)
    M.SCENE_LIST = M.read_chunks(mf, 'Scene', fn + '.Scn.bin', conReader=M.SceneChunk)
    return M.SCENE_LIST[0]


def refs_of(ch):
    try:
        r = M.get_references(ch)
    except Exception:
        r = []
    if not r:
        try:
            d = M.get_reference(ch)
            r = list(d.values()) if d else []
        except Exception:
            r = []
    return [x for x in r if x is not None]


def bitmaps_of(ch, depth=0, seen=None):
    seen = set() if seen is None else seen
    if ch is None or id(ch) in seen or depth > 5:
        return []
    seen.add(id(ch))
    if M.get_guid(ch) == 0x240:
        return [ch]
    out = []
    for r in refs_of(ch):
        out += bitmaps_of(r, depth + 1, seen)
    return out


def thumb(ch):
    for c in getattr(ch, 'children', None) or []:
        d = getattr(c, 'data', None)
        if c.types == 0x4200 and isinstance(d, (bytes, bytearray)) and len(d) == 768:
            return np.frombuffer(d, np.uint8).reshape(16, 16, 3)[..., ::-1].astype(float)   # stored BGR
        r = thumb(c)
        if r is not None:
            return r
    return None


def texture_for(mat, name, previews):
    bms = bitmaps_of(mat)
    if not bms:
        return None
    t = thumb(bms[0])     # first bitmap = base colour
    if t is None:
        return None
    err, best = min((float(np.mean((a - t) ** 2)), k) for k, a in previews.items())
    if err < 60.0:
        return best
    return UNMATCHED_POSTER if name.startswith("Poster") else UNMATCHED_OTHER


def i32s(data, off, n):
    return np.frombuffer(data, '<i4', n, off)


def f32s(data, off, n):
    return np.frombuffer(data, '<f4', n, off)


def editable_mesh(msh):
    poly = msh.get_first(0x08FE)
    vd = poly.get_first(0x0914).data
    nv = int(i32s(vd, 0, 1)[0])
    verts = f32s(vd, 4, nv * 3).reshape(nv, 3)
    fd = poly.get_first(0x0912).data
    nf = int(i32s(fd, 0, 1)[0])
    faces = np.frombuffer(fd, '<u4', nf * 5, 4).reshape(nf, 5)[:, :3].astype(int).tolist()
    uvs = uvf = None
    tv = poly.get_first(0x2394)
    tf = poly.get_first(0x2396)
    if tv is not None and tf is not None:
        nt = int(i32s(tv.data, 0, 1)[0])
        uvs = f32s(tv.data, 4, nt * 3).reshape(nt, 3)[:, :2]
        ntf = int(i32s(tf.data, 0, 1)[0])
        if ntf == nf:
            uvf = i32s(tf.data, 4, ntf * 3).reshape(ntf, 3).tolist()
    return verts, faces, uvs, uvf


def editable_poly(msh):
    poly = msh.get_first(0x08FE)
    coords = faces = None
    chans = []
    cur = None
    for child in poly.children:
        if child.types == 0x0100:
            coords = np.array(M.calc_point(child.data), float).reshape(-1, 3)
        elif child.types == 0x011A:
            faces = [list(p.points) for p in M.calc_point_3d(child)]
        elif child.types == 0x0124:
            cur = [M.get_long(child.data, 0)[0], None, None]
            chans.append(cur)
        elif child.types == 0x0128 and cur is not None:
            cur[1] = np.array(M.calc_point_float(child.data), float).reshape(-1, 3)[:, :2]
        elif child.types == 0x012B and cur is not None:
            cur[2] = M.get_poly_data(child)
    uvs = uvf = None
    for idx, c, p in chans:
        if idx == 1 and c is not None and p is not None and len(p) == len(faces):
            uvs, uvf = c, p
    return coords, faces, uvs, uvf


def geometry(msh):
    uid = M.get_guid(msh)
    if uid in (0x2032, 0x2033):
        msh = refs_of(msh)[-1]
        uid = M.get_guid(msh)
    if uid == M.EDIT_MESH:
        return editable_mesh(msh)
    if uid == M.EDIT_POLY:
        return editable_poly(msh)
    return None


def make_material(tex):
    rough, metal, emit, blend = LOOKS.get(tex, (0.7, 0.0, 0.0, False))
    mat = bpy.data.materials.new(tex)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    if blend:
        bsdf.inputs["Base Color"].default_value = (0.35, 0.42, 0.45, 1.0)
        bsdf.inputs["Alpha"].default_value = 0.25
        mat.blend_method = 'BLEND'
        return mat
    img = bpy.data.images.load(glob.glob(os.path.join(TEX_DIR, "**", tex + "_Diffuse.png"), recursive=True)[0])
    img.name = tex
    node = nt.nodes.new("ShaderNodeTexImage")
    node.image = img
    nt.links.new(node.outputs["Color"], bsdf.inputs["Base Color"])
    return mat


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    previews = {}
    for p in glob.glob(os.path.join(TEX_DIR, "**", "*_Diffuse.png"), recursive=True):
        key = os.path.basename(p).replace("_Diffuse.png", "")
        previews[key] = np.asarray(Image.open(p).convert("RGB").resize((16, 16), Image.BOX)).astype(float)
    root = load_max(MAX_FILE)
    mats = {}
    objs = []
    for chunk in root.children:
        if not (isinstance(chunk, M.SceneChunk) and M.get_guid(chunk) == 0x01 and M.get_super_id(chunk) == 0x01):
            continue
        name = str(chunk.get_first(M.TYP_NAME).data)
        prs, msh, mat, lyr = M.get_matrix_mesh_material(chunk)
        if msh is None or mat is None:
            continue
        tex = texture_for(mat, name, previews)
        if tex is None or tex not in LOOKS:
            continue      # demo car, ground plane, lights …
        geo = geometry(msh)
        if geo is None or geo[0] is None or not geo[1]:
            print("skipped (no geometry):", name, tex, M.get_cls_name(msh), hex(M.get_guid(msh)))
            continue
        verts, faces, uvs, uvf = geo
        me = bpy.data.meshes.new(name)
        me.from_pydata([tuple(v) for v in verts], [], faces)
        if uvs is not None and uvf is not None:
            layer = me.uv_layers.new(name="UVMap")
            li = 0
            for fi, poly in enumerate(me.polygons):
                src = uvf[fi]
                for k in range(poly.loop_total):
                    u = uvs[src[k]] if k < len(src) and src[k] < len(uvs) else (0.0, 0.0)
                    layer.data[poly.loop_start + k].uv = (float(u[0]), float(u[1]))
        else:
            print("no UVs:", name, tex)
        me.validate()
        if tex not in mats:
            mats[tex] = make_material(tex)
        me.materials.append(mats[tex])
        ob = bpy.data.objects.new(name + "_" + tex, me)
        bpy.context.scene.collection.objects.link(ob)
        ob.matrix_world = M.create_matrix(prs) if prs is not None else Matrix.Identity(4)
        objs.append(ob)
        print("node %-22s %-30s faces=%5d uv=%s" % (name, tex, len(faces), uvf is not None))
    # the scene is modelled Y-up: turn it Z-up for Blender (glTF export turns it back to Y-up)
    rot = Matrix.Rotation(math.radians(90.0), 4, 'X')
    for ob in objs:
        ob.matrix_world = rot @ ob.matrix_world
    bpy.context.view_layer.update()
    for ob in objs:
        ob.data.transform(ob.matrix_world)
        ob.matrix_world = Matrix.Identity(4)
        for p in ob.data.polygons:
            p.use_smooth = False
    # bounds; floor = the concrete floor mesh
    def bounds(obs):
        pts = [v.co for o in obs for v in o.data.vertices]
        return Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts))), \
            Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    floor = [o for o in objs if "Conc_Floor" in o.name]
    fmn, fmx = bounds(floor)
    # drop leftovers far outside the building (demo car badge, stray planes)
    for ob in list(objs):
        omn, omx = bounds([ob])
        if omn.x < fmn.x - 12 or omx.x > fmx.x + 12 or omn.y < fmn.y - 12 or omx.y > fmx.y + 12 \
                or omn.z < fmx.z - 3 or omx.z > fmx.z + 14:
            print("dropped (outside the garage):", ob.name)
            objs.remove(ob)
            bpy.data.objects.remove(ob)
    shift = Vector((0.0, 0.0, -fmx.z))
    for ob in objs:
        ob.data.transform(Matrix.Translation(shift))
    # clear the stage: remove loose parts standing on the floor around the turntable
    cx, cy = STAGE_CENTRE[0], -STAGE_CENTRE[1]      # Blender y = -Godot z
    removed = 0
    for ob in objs:
        if "Conc_Floor" in ob.name:
            continue
        bm = bmesh.new()
        bm.from_mesh(ob.data)
        bm.faces.ensure_lookup_table()
        seen = set()
        kill = []
        for f in bm.faces:
            if f.index in seen:
                continue
            island, stack = [], [f]
            seen.add(f.index)
            while stack:
                g = stack.pop()
                island.append(g)
                for e in g.edges:
                    for h in e.link_faces:
                        if h.index not in seen:
                            seen.add(h.index)
                            stack.append(h)
            vs = {v for g in island for v in g.verts}
            xs = [v.co.x for v in vs]
            ys = [v.co.y for v in vs]
            zs = [v.co.z for v in vs]
            near = min(math.hypot(v.co.x - cx, v.co.y - cy) for v in vs)
            small = max(xs) - min(xs) < 2.5 and max(ys) - min(ys) < 2.5
            if small and min(zs) < 0.3 and 0.1 < max(zs) < 2.5 and near < STAGE_CLEAR_R:
                kill += island
        # cables and other low geometry crossing the disc: cut at the disc edge (hidden under the ring)
        killed = set(kill)
        for f in bm.faces:
            if f in killed:
                continue
            c = f.calc_center_median()
            if math.hypot(c.x - cx, c.y - cy) < STAGE_DISC_R and max(v.co.z for v in f.verts) < 1.5:
                kill.append(f)
        if kill:
            removed += len(set(kill))
            bmesh.ops.delete(bm, geom=list(set(kill)), context='FACES')
            bm.to_mesh(ob.data)
        bm.free()
    print("stage cleared: %d faces removed" % removed)
    mn, mx = bounds(objs)
    fmn, fmx = bounds(floor)
    bpy.ops.export_scene.gltf(filepath=OUT, export_format='GLB', export_image_format='JPEG',
                              export_jpeg_quality=88, export_apply=True, export_yup=True)
    # Blender (x, y, z) -> glTF/Godot (x, z, -y)
    info = {
        "floor_min": [fmn.x, fmn.z, -fmx.y], "floor_max": [fmx.x, fmx.z, -fmn.y],
        "min": [mn.x, mn.z, -mx.y], "max": [mx.x, mx.z, -mn.y],
        "stage": [STAGE_CENTRE[0], 0.0, STAGE_CENTRE[1]], "stage_clear_r": STAGE_CLEAR_R,
    }
    with open(os.path.splitext(OUT)[0] + ".json", "w") as f:
        json.dump(info, f, indent=1)
    print("GARAGE", json.dumps(info))


main()

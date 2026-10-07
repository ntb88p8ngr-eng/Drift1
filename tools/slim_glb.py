#!/usr/bin/env python3
"""Slims a .glb exported by Godot for Blender: identical images stored once, opaque images as JPEG
(--jpeg), identical meshes shared by their nodes, the tangents dropped (Blender works them out
itself), the binary buffer repacked with only what is still referenced.

Usage: python3 tools/slim_glb.py in.glb out.glb [--jpeg=90]
"""
import hashlib
import io
import json
import struct
import sys


def main(src, dst, jpeg=0):
    data = open(src, "rb").read()
    jlen, _ = struct.unpack_from("<II", data, 12)
    j = json.loads(data[20:20 + jlen])
    off = 20 + jlen
    blen, _ = struct.unpack_from("<II", data, off)
    buf = data[off + 8: off + 8 + blen]
    bv = j["bufferViews"]
    acc = j["accessors"]

    def view_bytes(i):
        v = bv[i]
        o = v.get("byteOffset", 0)
        return buf[o:o + v["byteLength"]]

    def acc_bytes(i):
        a = acc[i]
        return view_bytes(a["bufferView"]) if "bufferView" in a else b""

    # identical images: one copy
    images = j.get("images", [])
    first = {}
    remap = {}
    keep_imgs = []
    for i, im in enumerate(images):
        key = hashlib.sha1(view_bytes(im["bufferView"])).hexdigest() if "bufferView" in im else im.get("uri", str(i))
        if key not in first:
            first[key] = len(keep_imgs)
            keep_imgs.append(im)
        remap[i] = first[key]
    for t in j.get("textures", []):
        if "source" in t:
            t["source"] = remap[t["source"]]
    j["images"] = keep_imgs

    # no tangents
    for m in j.get("meshes", []):
        for p in m["primitives"]:
            p["attributes"].pop("TANGENT", None)

    # identical meshes (the same tool, bolt, panel placed many times): one mesh, shared
    mesh_first = {}
    mesh_map = {}
    keep_meshes = []
    for i, m in enumerate(j.get("meshes", [])):
        h = hashlib.sha1()
        for p in m["primitives"]:
            for k in sorted(p["attributes"]):
                h.update(k.encode())
                h.update(acc_bytes(p["attributes"][k]))
            if "indices" in p:
                h.update(acc_bytes(p["indices"]))
            h.update(str(p.get("material", -1)).encode())
        key = h.hexdigest()
        if key not in mesh_first:
            mesh_first[key] = len(keep_meshes)
            keep_meshes.append(m)
        mesh_map[i] = mesh_first[key]
    for nd in j.get("nodes", []):
        if "mesh" in nd:
            nd["mesh"] = mesh_map[nd["mesh"]]
    n_meshes = len(j.get("meshes", []))
    j["meshes"] = keep_meshes

    # opaque images as JPEG (much smaller; Blender reads them as they are)
    jpeg_data = {}
    if jpeg:
        from PIL import Image
        for im in keep_imgs:
            if "bufferView" not in im:
                continue
            raw = view_bytes(im["bufferView"])
            pic = Image.open(io.BytesIO(raw))
            if pic.mode in ("RGBA", "LA", "PA") or "transparency" in pic.info:
                rgba = pic.convert("RGBA")
                if rgba.getchannel("A").getextrema()[0] < 255:
                    continue
            o = io.BytesIO()
            pic.convert("RGB").save(o, "JPEG", quality=jpeg)
            if o.tell() < len(raw):
                jpeg_data[im["bufferView"]] = o.getvalue()
                im["mimeType"] = "image/jpeg"

    # what is still referenced
    used_acc = set()
    for m in keep_meshes:
        for p in m["primitives"]:
            used_acc.update(p["attributes"].values())
            if "indices" in p:
                used_acc.add(p["indices"])
            for tg in p.get("targets", []):
                used_acc.update(tg.values())
    for s in j.get("skins", []):
        if "inverseBindMatrices" in s:
            used_acc.add(s["inverseBindMatrices"])
    for a in j.get("animations", []):
        for smp in a["samplers"]:
            used_acc.add(smp["input"])
            used_acc.add(smp["output"])
    acc_map = {}
    new_acc = []
    for i, a in enumerate(acc):
        if i in used_acc:
            acc_map[i] = len(new_acc)
            new_acc.append(a)
    used_views = {a["bufferView"] for a in new_acc if "bufferView" in a} | {im["bufferView"] for im in keep_imgs if "bufferView" in im}

    # repack the buffer
    out = bytearray()
    view_map = {}
    new_views = []
    for i, v in enumerate(bv):
        if i not in used_views:
            continue
        while len(out) % 4:
            out.append(0)
        b = jpeg_data.get(i, view_bytes(i))
        nv = dict(v)
        nv["byteOffset"] = len(out)
        nv["byteLength"] = len(b)
        nv["buffer"] = 0
        out += b
        view_map[i] = len(new_views)
        new_views.append(nv)
    for a in new_acc:
        if "bufferView" in a:
            a["bufferView"] = view_map[a["bufferView"]]
    for im in keep_imgs:
        if "bufferView" in im:
            im["bufferView"] = view_map[im["bufferView"]]
    for m in keep_meshes:
        for p in m["primitives"]:
            p["attributes"] = {k: acc_map[v] for k, v in p["attributes"].items()}
            if "indices" in p:
                p["indices"] = acc_map[p["indices"]]
            if "targets" in p:
                p["targets"] = [{k: acc_map[v] for k, v in tg.items()} for tg in p["targets"]]
    for s in j.get("skins", []):
        if "inverseBindMatrices" in s:
            s["inverseBindMatrices"] = acc_map[s["inverseBindMatrices"]]
    for a in j.get("animations", []):
        for smp in a["samplers"]:
            smp["input"] = acc_map[smp["input"]]
            smp["output"] = acc_map[smp["output"]]
    j["accessors"] = new_acc
    j["bufferViews"] = new_views
    while len(out) % 4:
        out.append(0)
    j["buffers"] = [{"byteLength": len(out)}]
    js = json.dumps(j, separators=(",", ":")).encode()
    while len(js) % 4:
        js += b" "
    total = 12 + 8 + len(js) + 8 + len(out)
    with open(dst, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, total))
        f.write(struct.pack("<II", len(js), 0x4E4F534A))
        f.write(js)
        f.write(struct.pack("<II", len(out), 0x004E4942))
        f.write(out)
    print("images %d -> %d (%d as JPEG), meshes %d -> %d, %.1f MB -> %.1f MB" % (
        len(images), len(keep_imgs), len(jpeg_data), n_meshes, len(keep_meshes), len(data) / 1e6, total / 1e6))


if __name__ == "__main__":
    q = 0
    for arg in sys.argv[3:]:
        if arg.startswith("--jpeg"):
            q = int(arg.split("=")[1]) if "=" in arg else 90
    main(sys.argv[1], sys.argv[2], q)

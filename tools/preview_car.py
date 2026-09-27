"""Renders preview images of an exported car GLB (Cycles, CPU). Usage: python3 preview_car.py car.glb out_prefix"""
import bpy, sys, math
from mathutils import Vector

glb, out = sys.argv[-2], sys.argv[-1]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=glb)
scene = bpy.context.scene
scene.render.engine = "CYCLES"
scene.cycles.device = "CPU"
scene.cycles.samples = 24
scene.cycles.use_denoising = False
scene.render.resolution_x = 800
scene.render.resolution_y = 450
world = bpy.data.worlds.new("w")
world.use_nodes = True
world.node_tree.nodes["Background"].inputs[0].default_value = (0.55, 0.6, 0.7, 1)
world.node_tree.nodes["Background"].inputs[1].default_value = 0.8
scene.world = world
# ground
bpy.ops.mesh.primitive_plane_add(size=30, location=(0, 0, 0))
g = bpy.context.active_object
gm = bpy.data.materials.new("ground")
gm.use_nodes = True
gm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.25, 0.25, 0.27, 1)
g.data.materials.append(gm)
sun = bpy.data.lights.new("sun", "SUN")
sun.energy = 3.5
so = bpy.data.objects.new("sun", sun)
so.rotation_euler = (math.radians(50), 0, math.radians(30))
scene.collection.objects.link(so)
cam = bpy.data.cameras.new("cam")
cam.lens = 40
co = bpy.data.objects.new("cam", cam)
scene.collection.objects.link(co)
scene.camera = co
# glTF import converts back to Blender Z-up: car front is -Y after import (Godot -Z)
views = {
    "front34": Vector((4.5, -6.5, 2.2)),
    "rear34": Vector((-4.8, 6.0, 2.0)),
    "side": Vector((8.5, 0.0, 1.0)),
}
for name, pos in views.items():
    co.location = pos
    d = Vector((0, 0, 0.6)) - pos
    co.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    scene.render.filepath = "%s_%s.png" % (out, name)
    bpy.ops.render.render(write_still=True)
print("PREVIEW DONE")

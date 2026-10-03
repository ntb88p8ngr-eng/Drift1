"""Open this file in Blender's Scripting workspace and run it."""
from pathlib import Path
import bpy

folder=Path(__file__).resolve().parent
bpy.ops.scene.new(type='NEW')
bpy.context.scene.name='Midnight Drift — Detailed Workshop'
bpy.ops.import_scene.gltf(filepath=str(folder/'Midnight_Drift_Garage.glb'))
for obj in list(bpy.context.scene.objects):
    if obj.type=='MESH' and obj.data.users>1:
        obj.data=obj.data.copy()
bpy.context.scene.render.engine='CYCLES'
bpy.context.scene.cycles.samples=64
bpy.ops.wm.save_as_mainfile(filepath=str(folder/'Midnight_Drift_Garage_Detailed.blend'))
print('Imported separate parts, made meshes independent and saved the Blender scene.')

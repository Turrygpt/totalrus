"""Repair the editable archer's skin and export it without changing its clips.

Run with Blender --background --python-exit-code 1 --python tools/repair_archer_skin.py.
"""
import sys
from pathlib import Path

import bpy

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from archer_face_weights import stabilize_face

bpy.ops.wm.open_mainfile(filepath=str(ROOT / 'art/archer.blend'))
rig = bpy.data.objects['ArcherRig']
body = bpy.data.objects['ArcherBody']
stabilize_face(body)
rig.animation_data.action = bpy.data.actions['bow_idle']
if rig.animation_data.action.slots:
    rig.animation_data.action_slot = rig.animation_data.action.slots[0]
bpy.context.scene.frame_set(0)
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT / 'art/archer.blend'))
bpy.ops.object.select_all(action='DESELECT')
for obj in [rig, body]:
    obj.select_set(True)
bpy.context.view_layer.objects.active = rig
bpy.ops.export_scene.gltf(
    filepath=str(ROOT / 'assets/archer.glb'), export_format='GLB', use_selection=True,
    export_animations=True, export_animation_mode='ACTIONS', export_force_sampling=True,
    export_def_bones=False, export_yup=True,
)
print('ARCHER_SKIN_REPAIRED', flush=True)

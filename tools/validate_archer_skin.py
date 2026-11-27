"""Check that animation cannot shear the archer's face, including the beard.

Run with Blender --background --python-exit-code 1 --python tools/validate_archer_skin.py.
Pass -- --before to reproduce the previous defect from the local repair backup.
"""
from pathlib import Path
import sys
import bpy

ROOT = Path(__file__).resolve().parents[1]
source = 'build/archer_before_jaw_fix.blend' if '--before' in sys.argv else 'art/archer.blend'
bpy.ops.wm.open_mainfile(filepath=str(ROOT / source))
rig = bpy.data.objects['ArcherRig']
body = bpy.data.objects['ArcherBody']
head = rig.pose.bones['mixamorig:Head']
minimum = min(v.co.z for v in body.data.vertices)
height = max(v.co.z for v in body.data.vertices) - minimum
# Includes the lowest beard/chin vertices, not just the eyes and forehead.
face = [(v.index, v.co.copy()) for v in body.data.vertices if (v.co.z-minimum)/height >= .84]
assert len(face) > 1500, 'The validation must cover the complete face and helmet'
rest_inverse = head.bone.matrix_local.inverted()
scene = bpy.context.scene
worst = 0.0
samples = 0
for action in bpy.data.actions:
    if not action.name.startswith(('bow_', 'knife_')):
        continue
    rig.animation_data.action = action
    if action.slots:
        rig.animation_data.action_slot = action.slots[0]
    peak = 0.0
    for frame in range(round(action.frame_range.x), round(action.frame_range.y)+1, 3):
        scene.frame_set(frame)
        bpy.context.view_layer.update()
        evaluated = body.evaluated_get(bpy.context.evaluated_depsgraph_get())
        transform = head.matrix @ rest_inverse
        peak = max(peak, max((body.matrix_world.to_3x3() @ (evaluated.data.vertices[i].co-transform@co)).length for i, co in face))
        samples += 1
    worst = max(worst, peak)
    print(f'FACE {action.name}: maximum shear {peak*1000:.4f} mm', flush=True)
print(f'CHECKED {len(face)} face vertices, {samples} poses; worst {worst*1000:.4f} mm', flush=True)
assert worst < .0001, 'Face is being pulled away from the head by other bones'
print('PASS complete face stays rigid in every archer animation', flush=True)

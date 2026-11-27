import bpy,json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
bpy.ops.wm.open_mainfile(filepath=str(ROOT/'art/warrior.blend'))
rig=bpy.data.objects['WarriorRig'];body=bpy.data.objects['WarriorBody'];report={}
for clip in ['combat_spear','pack_idle_sword','pack_guard_sword','spear_pack_attack_1']:
    rig.animation_data.action=bpy.data.actions[clip];bpy.context.scene.frame_set(0);bpy.context.view_layer.update()
    hand=rig.pose.bones['mixamorig:RightHand'].matrix.inverted()
    report[clip]={b.name:{'q':list(b.rotation_quaternion),'head':list(hand@b.head),'tail':list(hand@b.tail)} for b in rig.pose.bones if b.name.startswith('mixamorig:RightHand')}
report['weights']={g.name:sum(1 for v in body.data.vertices for w in v.groups if w.group==g.index and w.weight>.1) for g in body.vertex_groups if 'RightHand' in g.name}
(ROOT/'build/grip_bones.json').write_text(json.dumps(report,indent=2))

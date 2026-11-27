"""Inspect supplied FBX clips without changing the editable warrior."""
import bpy
import json
from pathlib import Path

root = Path(__file__).resolve().parents[1]
pack = root / 'art/source/sword_shield_pack'
report = []
for path in sorted(pack.glob('*.fbx')):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=str(path))
    rig = next(o for o in bpy.context.scene.objects if o.type == 'ARMATURE')
    bones = rig.data.bones
    actions = []
    for action in bpy.data.actions:
        actions.append({'name':action.name, 'frames':list(action.frame_range),
                        'seconds':float(action.frame_range[1]-action.frame_range[0])/bpy.context.scene.render.fps})
    record = {'file':path.name, 'bones':len(bones), 'bone_names':list(bones.keys()),
              'scale':list(rig.scale), 'matrix_world':[list(row) for row in rig.matrix_world],
              'fps':bpy.context.scene.render.fps,'actions':actions,'rest':{}}
    for name in ('Hips','Spine','RightArm','RightForeArm','RightHand','LeftHand','LeftFoot'):
        b=next((b for b in bones if b.name.split(':')[-1]==name),None)
        if b:record['rest'][name]={'head':list(b.head_local),'quat':list(b.matrix_local.to_quaternion())}
    if actions:
        action=rig.animation_data.action
        frame_start,frame_end=action.frame_range
        samples=[]
        for f in (frame_start,(frame_start+frame_end)*.5,frame_end):
            bpy.context.scene.frame_set(int(f),subframe=f%1)
            samples.append({b.name:list(b.head) for b in rig.pose.bones if b.name.split(':')[-1] in ('Hips','RightHand','LeftHand')})
        record['samples']=samples
    report.append(record)
    print('CLIP',path.name,len(bones),actions,flush=True)
(root/'art/animation_pack_report.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
print('PACK_INSPECTED',flush=True)

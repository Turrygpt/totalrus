import bpy, json
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
bpy.ops.wm.open_mainfile(filepath=str(ROOT/'art/warrior.blend'))
rig=bpy.data.objects['WarriorRig']; body=bpy.data.objects['WarriorBody']
result={}
for name in ['motion_combat_spear','pack_attack_2','motion_attack_spear']:
    rig.animation_data.action=bpy.data.actions[name]
    lo,hi=rig.animation_data.action.frame_range
    frames=[]
    for phase in [0,.2,.4,.6,.8,1]:
        f=lo+(hi-lo)*phase; bpy.context.scene.frame_set(int(f),subframe=f%1)
        bpy.context.view_layer.update()
        obj=body.evaluated_get(bpy.context.evaluated_depsgraph_get());mesh=obj.to_mesh()
        coords=[obj.matrix_world@v.co for v in mesh.vertices]
        frames.append({'phase':phase,'size':[max(v[i] for v in coords)-min(v[i] for v in coords) for i in range(3)],'bones':{b.name:{'loc':list(b.location),'scale':list(b.scale),'global_scale':list(b.matrix.to_scale())} for b in rig.pose.bones if b.name in ['mixamorig:Hips','mixamorig:Spine','mixamorig:Spine1','mixamorig:RightArm','mixamorig:LeftUpLeg']}})
        obj.to_mesh_clear()
    result[name]=frames
(ROOT/'build/spear_deformation.json').write_text(json.dumps(result,indent=2))
print('INSPECT_DONE')

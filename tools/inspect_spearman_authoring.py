import bpy, json
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[1]
bpy.ops.wm.open_mainfile(filepath=str(ROOT/'art/warrior.blend'))
rig=bpy.data.objects['WarriorRig']; scene=bpy.context.scene
report={'version':bpy.app.version_string,'rig_world':[list(r) for r in rig.matrix_world], 'objects':[], 'poses':{}}
for o in scene.objects:
    report['objects'].append({'name':o.name,'type':o.type,'hidden':o.hide_get(),'render_hidden':o.hide_render,'scale':list(o.scale),'bbox':[list(o.matrix_world@Vector(v)) for v in o.bound_box], 'constraints':[(c.type,getattr(c,'subtarget','')) for c in o.constraints]})
for name in ['combat_spear','motion_combat_spear','spear_pack_attack_1']:
    rig.animation_data.action=bpy.data.actions[name]; scene.frame_set(0);bpy.context.view_layer.update()
    report['poses'][name]={b.name:{'head':list(b.head),'tail':list(b.tail),'q':list(b.matrix.to_quaternion()),'scale':list(b.scale),'loc':list(b.location),'length':b.bone.length} for b in rig.pose.bones if not any(d in b.name for d in ['Index','Middle','Ring','Pinky','Thumb'])}
(ROOT/'build/spearman_inspect.json').write_text(json.dumps(report,indent=2))
print('AUTHOR_INSPECT_OK',bpy.app.version_string,flush=True)

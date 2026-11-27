"""Measure torso thickness and bone lengths over complete spear attacks."""
import bpy,json,numpy as np
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
bpy.ops.wm.open_mainfile(filepath=str(ROOT/'art/warrior.blend'))
rig=bpy.data.objects['WarriorRig'];body=bpy.data.objects['WarriorBody']
groups={g.index for g in body.vertex_groups if g.name in ['mixamorig:Spine','mixamorig:Spine1','mixamorig:Spine2']}
torso=[v.index for v in body.data.vertices if sum(g.weight for g in v.groups if g.group in groups)>.8]
report={};fails=[]
for clip in ['motion_combat_spear','spear_pack_attack_1','spear_pack_attack_2']:
    rig.animation_data.action=bpy.data.actions[clip];lo,hi=rig.animation_data.action.frame_range
    frames=[]
    for tick in range(int((hi-lo)*2)+1):
        f=lo+tick*.5;bpy.context.scene.frame_set(int(f),subframe=f%1);bpy.context.view_layer.update()
        evaluated=body.evaluated_get(bpy.context.evaluated_depsgraph_get());mesh=evaluated.to_mesh()
        points=np.array([list(evaluated.matrix_world@mesh.vertices[i].co) for i in torso])
        sizes=np.sqrt(np.linalg.eigvalsh(np.cov(points.T)))
        scale_error=max(abs(s-1) for b in rig.pose.bones for s in b.matrix.to_scale())
        ground=min((evaluated.matrix_world@v.co).z for v in mesh.vertices)
        frames.append({'time':f/30,'torso_axes':sizes.tolist(),'scale_error':scale_error,'ground':ground})
        evaluated.to_mesh_clear()
    report[clip]=frames
reference=np.median([f['torso_axes'] for f in report['motion_combat_spear']],axis=0)
for clip,frames in report.items():
    if not clip.startswith('spear_pack'):continue
    ratio=min(min(np.array(f['torso_axes'])/reference) for f in frames)
    scale=max(f['scale_error'] for f in frames)
    ground=max(abs(f['ground']) for f in frames)
    print('DEFORMATION',clip,'minimum torso dimension ratio',ratio,'scale error',scale,'ground error',ground,flush=True)
    if ratio<.82 or scale>.001 or ground>.015:fails.append(clip)
(ROOT/'build/spear_deformation_qa.json').write_text(json.dumps({'clips':report,'failures':fails},indent=2))
if fails:raise RuntimeError('Spear deformation checks failed: '+str(fails))
print('SPEAR_DEFORMATION_PASS',flush=True)

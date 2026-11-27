import bpy,json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
bpy.ops.wm.read_factory_settings(use_empty=True)
source=next((ROOT/'art/source/spear_pack').glob('*.fbx'))
bpy.ops.import_scene.fbx(filepath=str(source))
report={'objects':[], 'actions':[]}
for obj in bpy.data.objects:
    if obj.type=='MESH':report['objects'].append({'name':obj.name,'vertices':len(obj.data.vertices),'triangles':sum(len(p.vertices)-2 for p in obj.data.polygons)})
    if obj.type=='ARMATURE':
        report['rig']={'name':obj.name,'bones':[b.name for b in obj.data.bones],'scale':list(obj.scale)}
for a in bpy.data.actions:report['actions'].append({'name':a.name,'frames':list(a.frame_range)})
(ROOT/'build/downloaded_spear_report.json').write_text(json.dumps(report,indent=2))
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'art/source/spear_pack/source.blend'))
print('SPEAR_PACK_INSPECTED')

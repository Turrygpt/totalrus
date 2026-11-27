"""Render labelled Blender review frames, contact sheet frames and optional GLB."""
import bpy, json, sys, math
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'build/spearman_attacks_10'
bpy.ops.wm.open_mainfile(filepath=str(ROOT/'art/spearman_attacks_10.blend'))
scene=bpy.context.scene;rig=bpy.data.objects['WarriorRig'];camera=scene.camera
manifest=json.loads((OUT/'animation_manifest.json').read_text(encoding='utf-8'))
for track in rig.animation_data.nla_tracks:track.mute=True
scene.render.resolution_x=800;scene.render.resolution_y=720
scene.render.image_settings.file_format='PNG';scene.render.image_settings.color_mode='RGB'
scene.render.engine='BLENDER_WORKBENCH'
shade=scene.display.shading
shade.light='STUDIO';shade.color_type='TEXTURE';shade.show_shadows=False;shade.show_cavity=True
shade.cavity_type='BOTH';shade.curvature_ridge_factor=1.2;shade.curvature_valley_factor=.8
shade.show_specular_highlight=True;shade.background_type='WORLD';scene.world.color=(.055,.07,.09)
scene.display.render_aa='16'
scene.view_settings.view_transform='Standard';scene.view_settings.exposure=1.0
camera.data.ortho_scale=4.1
camera.location=(5.8,-3.7,3.25)
camera.rotation_euler=(Vector((0,-.86,.85))-camera.location).to_track_quat('-Z','Y').to_euler()
if '--gpu' in sys.argv:
    scene.render.engine='CYCLES'
    prefs=bpy.context.preferences.addons['cycles'].preferences
    for backend in ['OPTIX','CUDA']:
        try:
            prefs.compute_device_type=backend;prefs.get_devices()
            devices=[d for d in prefs.devices if d.type!='CPU']
            if devices:
                for d in prefs.devices:d.use=d.type!='CPU'
                scene.cycles.device='GPU';print('RENDER_GPU',[(d.name,d.type) for d in devices],flush=True);break
        except Exception:pass
    scene.cycles.samples=16;scene.cycles.use_denoising=True
    scene.render.use_persistent_data=True
    scene.render.resolution_x=960;scene.render.resolution_y=720
    scene.view_settings.view_transform='AgX';scene.view_settings.exposure=0
if '--realtime' in sys.argv:
    scene.render.engine='CYCLES'
    try:scene.render.engine='BLENDER_EEVEE'
    except TypeError as exc:print(exc);raise
    if hasattr(scene,'eevee') and hasattr(scene.eevee,'taa_render_samples'):scene.eevee.taa_render_samples=16
    scene.render.resolution_x=960;scene.render.resolution_y=720
    scene.view_settings.view_transform='AgX';scene.view_settings.exposure=0
def render(name,frame,path):
    rig.animation_data.action=bpy.data.actions[name];scene.frame_set(frame);bpy.context.view_layer.update()
    scene.render.filepath=str(path);bpy.ops.render.render(write_still=True)
if '--test' in sys.argv:
    render('spear_attack_02_power_lunge',17,OUT/'workbench_test.png')
    if '--realtime' in sys.argv:
        render('spear_attack_02_power_lunge',18,OUT/'realtime_test.png')
        render('spear_attack_02_power_lunge',19,OUT/'realtime_test.png')
    sys.exit(0)
if '--contacts' in sys.argv:
    scene.render.engine='CYCLES';scene.cycles.samples=20
    scene.view_settings.view_transform='AgX'
    for name,entry in manifest['clips'].items():
        if entry['kind']!='attack':continue
        render(name,entry['impact_frames'][-1],OUT/(name+'_contact.png'))
    sys.exit(0)
if '--export' in sys.argv:
    rig.animation_data.action=bpy.data.actions['spear_ready_loop'];scene.frame_set(0)
    for track in list(rig.animation_data.nla_tracks):rig.animation_data.nla_tracks.remove(track)
    bpy.ops.object.select_all(action='DESELECT')
    for obj in [rig,bpy.data.objects['WarriorBody']]:obj.select_set(True)
    bpy.context.view_layer.objects.active=rig
    bpy.ops.export_scene.gltf(filepath=str(OUT/'spearman_attacks_10.glb'),export_format='GLB',use_selection=True,export_animations=True,export_animation_mode='ACTIONS',export_force_sampling=True,export_def_bones=False,export_yup=True)
    print('EXPORTED_RIG_AND_BODY',flush=True)
    sys.exit(0)
frames=OUT/'frames';frames.mkdir(exist_ok=True)
def intro_camera(index):
    phase=max(0,min(1,index/34));phase=phase*phase*(3-2*phase)
    camera.rotation_euler=(Vector((0,-.86,1.05-.20*phase))-camera.location).to_track_quat('-Z','Y').to_euler()
if '--intro-only' in sys.argv:
    for index in range(35):
        intro_camera(index)
        render('spear_guard_enter',min(index,24),frames/('frame_%04d.png'%index))
    print('INTRO_FIXED',flush=True)
    sys.exit(0)
def outro_camera(frame):
    phase=max(0,min(1,frame/24));phase=phase*phase*(3-2*phase)
    camera.rotation_euler=(Vector((0,-.86,.85+.20*phase))-camera.location).to_track_quat('-Z','Y').to_euler()
if '--outro-only' in sys.argv:
    start=sum(e['frames'][1]+11 for e in manifest['clips'].values())-35
    for offset in range(35):
        outro_camera(offset)
        render('spear_guard_exit',min(offset,24),frames/('frame_%04d.png'%(start+offset)))
    print('OUTRO_FIXED',flush=True)
    sys.exit(0)
index=0;captions=[]
ordered=sorted(manifest['clips'].items(),key=lambda item:item[1]['showcase_start'])
for name,entry in ordered:
    start=index/30
    end=entry['frames'][1]
    for frame in range(0,end+1):
        if index<35:intro_camera(index)
        if name=='spear_guard_exit':outro_camera(frame)
        render(name,frame,frames/('frame_%04d.png'%index));index+=1
    for hold in range(10):
        # A brief hold makes the return-to-guard legible.
        import shutil
        if index<35:
            intro_camera(index);render(name,end,frames/('frame_%04d.png'%index))
        else:shutil.copyfile(frames/('frame_%04d.png'%(index-1)),frames/('frame_%04d.png'%index))
        index+=1
    captions.append({'start':start,'end':index/30,'text':entry['label'],'action':name})
(OUT/'preview_captions.json').write_text(json.dumps(captions,ensure_ascii=False,indent=2),encoding='utf-8')
def stamp(t):
    msec=round(t*1000);h=msec//3600000;m=(msec//60000)%60;s=(msec//1000)%60
    return f'{h:02d}:{m:02d}:{s:02d},{msec%1000:03d}'
(OUT/'preview.srt').write_text('\n\n'.join(f'{i+1}\n{stamp(c["start"])} --> {stamp(c["end"])}\n{c["text"]}' for i,c in enumerate(captions))+'\n',encoding='utf-8')
print('PREVIEW_SEQUENCE_READY',index,'FPS',30,flush=True)

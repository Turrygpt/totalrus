"""Merge the validated spear library into the production warrior without replacing old clips.

blender --background --python-exit-code 1 --python tools/integrate_spearman_attacks.py
The review blend is read only. Production inputs are backed up before saving.
"""
import hashlib
import json
import math
import os
import re
import shutil
import struct
from datetime import datetime, timedelta, timezone
from pathlib import Path

import bpy


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'build/spearman_integration'
SOURCE = ROOT / 'art/warrior.blend'
LIBRARY = ROOT / 'art/spearman_attacks_10.blend'
GLB = ROOT / 'assets/warrior.glb'
AUTHOR_MANIFEST = ROOT / 'build/spearman_attacks_10/animation_manifest.json'
COMBAT_DATA = ROOT / 'assets/spear_combat.json'
MANIFEST = ROOT / 'assets/animation_manifest.json'
OUT.mkdir(parents=True, exist_ok=True)
stamp = datetime.now(timezone(timedelta(hours=3))).strftime('%Y%m%d_%H%M%S')
backup = OUT / 'backups' / stamp
backup.mkdir(parents=True, exist_ok=False)


def file_hash(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read_glb(path):
    raw = path.read_bytes()
    magic, version, length = struct.unpack_from('<III', raw)
    assert magic == 0x46546C67 and version == 2 and length == len(raw)
    offset = 12
    document, binary = None, None
    while offset < len(raw):
        size, kind = struct.unpack_from('<II', raw, offset)
        data = raw[offset+8:offset+8+size]
        if kind == 0x4E4F534A:
            document = json.loads(data)
        elif kind == 0x004E4942:
            binary = data
        offset += 8+size
    return document, binary


def accessor_data(gltf, binary, index):
    accessor = gltf['accessors'][index]
    view = gltf['bufferViews'][accessor['bufferView']]
    assert 'sparse' not in accessor
    sizes = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4, 'MAT4': 16}
    types = {5120: 'b', 5121: 'B', 5122: 'h', 5123: 'H', 5125: 'I', 5126: 'f'}
    fmt = '<' + types[accessor['componentType']]*sizes[accessor['type']]
    size = struct.calcsize(fmt)
    stride = view.get('byteStride', size)
    start = view.get('byteOffset', 0)+accessor.get('byteOffset', 0)
    return [struct.unpack_from(fmt, binary, start+i*stride) for i in range(accessor['count'])]


def animation_payloads(path):
    gltf, binary = read_glb(path)
    clips = {}
    for animation in gltf.get('animations', []):
        channels = {}
        for channel in animation['channels']:
            sampler = animation['samplers'][channel['sampler']]
            target = channel['target']
            node = gltf['nodes'][target['node']]['name']
            key = node + '/' + target['path']
            channels[key] = {'interpolation': sampler.get('interpolation', 'LINEAR'),
                             'times': accessor_data(gltf, binary, sampler['input']),
                             'values': accessor_data(gltf, binary, sampler['output'])}
        clips[animation['name']] = channels
    return gltf, clips


def restore_legacy_timestamps(candidate, previous):
    """Keep legacy playback timing when the existing asset used another FPS.

    New Actions keep their native 30 Hz samples. Append independent input
    accessors so an input shared with a new clip is never changed in place.
    """
    current, binary = read_glb(candidate)
    old, old_binary = read_glb(previous)
    old_actions = {animation['name']: animation for animation in old.get('animations', [])}
    cache = {}
    payload = bytearray(binary)
    for animation in current.get('animations', []):
        name = animation['name']
        if name not in old_actions or name in library_names:
            continue
        original = old_actions[name]
        old_channels = {(old['nodes'][c['target']['node']]['name'], c['target']['path']): c
                        for c in original['channels']}
        handled = set()
        for channel in animation['channels']:
            sampler_id = channel['sampler']
            if sampler_id in handled:
                continue
            handled.add(sampler_id)
            key = (current['nodes'][channel['target']['node']]['name'], channel['target']['path'])
            source_channel = old_channels[key]
            source_sampler = original['samplers'][source_channel['sampler']]
            source_index = source_sampler['input']
            if source_index not in cache:
                rows = accessor_data(old, old_binary, source_index)
                values = [row[0] for row in rows]
                packed = struct.pack('<'+'f'*len(values), *values)
                payload.extend(b'\0'*((-len(payload)) % 4))
                view_index = len(current['bufferViews'])
                current['bufferViews'].append({'buffer': 0, 'byteOffset': len(payload), 'byteLength': len(packed)})
                payload.extend(packed)
                cache[source_index] = len(current['accessors'])
                current['accessors'].append({'bufferView': view_index, 'componentType': 5126,
                                             'count': len(values), 'type': 'SCALAR',
                                             'min': [min(values)], 'max': [max(values)]})
            animation['samplers'][sampler_id]['input'] = cache[source_index]
    payload.extend(b'\0'*((-len(payload)) % 4))
    current['buffers'][0]['byteLength'] = len(payload)
    encoded = json.dumps(current, ensure_ascii=False, separators=(',', ':')).encode('utf-8')
    encoded += b' '*((-len(encoded)) % 4)
    length = 12+8+len(encoded)+8+len(payload)
    candidate.write_bytes(struct.pack('<III', 0x46546C67, 2, length)
                          +struct.pack('<II', len(encoded), 0x4E4F534A)+encoded
                          +struct.pack('<II', len(payload), 0x004E4942)+payload)


def curves(action):
    for layer in action.layers:
        for strip in layer.strips:
            for bag in strip.channelbags:
                yield from bag.fcurves


def action_hash(action):
    values = []
    for curve in curves(action):
        values.append((curve.data_path, curve.array_index,
                       [(list(k.co), list(k.handle_left), list(k.handle_right), k.interpolation,
                         k.handle_left_type, k.handle_right_type) for k in curve.keyframe_points]))
    return hashlib.sha256(json.dumps(values, sort_keys=True).encode()).hexdigest()


author = json.loads(AUTHOR_MANIFEST.read_text(encoding='utf-8'))
library_names = set(author['clips'])
assert len(library_names) == 13
assert sum(name.startswith('spear_attack_') for name in library_names) == 10
library_hash_before = file_hash(LIBRARY)
old_gltf, old_exports = animation_payloads(GLB)
backup_manifest = {}
for path in [SOURCE, GLB, MANIFEST, COMBAT_DATA]:
    if path.exists():
        destination = backup / path.name
        shutil.copy2(path, destination)
        backup_manifest[str(path.relative_to(ROOT))] = {'backup': str(destination.relative_to(ROOT)),
                                                      'sha256': file_hash(path)}
(backup / 'backup_manifest.json').write_text(json.dumps(backup_manifest, indent=2), encoding='utf-8')
print('BACKUP', str(backup), flush=True)

bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
rig = bpy.data.objects['WarriorRig']
body = bpy.data.objects['WarriorBody']
scene = bpy.context.scene
source_fps = scene.render.fps
old_actions = {action.name: action_hash(action) for action in bpy.data.actions if action.name not in library_names}
old_active = rig.animation_data.action.name if rig.animation_data and rig.animation_data.action else None
for name in library_names:
    if name in bpy.data.actions:
        bpy.data.actions.remove(bpy.data.actions[name])
with bpy.data.libraries.load(str(LIBRARY), link=False) as (source, destination):
    assert library_names <= set(source.actions)
    destination.actions = sorted(library_names)
assert len(destination.actions) == 13 and all(destination.actions)
slots = {}
native_key_times = []
native_markers = []
for action in destination.actions:
    action.use_fake_user = True
    object_slots = [slot for slot in action.slots if slot.target_id_type == 'OBJECT']
    if len(object_slots) != 1:
        raise RuntimeError('Ambiguous rig slot: '+action.name)
    rig.animation_data.action = action
    rig.animation_data.action_slot = object_slots[0]
    slots[action.name] = object_slots[0].identifier
    frame_scale = source_fps/author['fps']
    action['authored_fps'] = author['fps']
    action['source_scene_fps'] = source_fps
    action['impact_times'] = [frame/author['fps'] for frame in author['clips'][action.name]['impact_frames']]
    for curve in curves(action):
        match = re.match(r'pose\.bones\["([^"]+)"\]', curve.data_path)
        if match and match.group(1) not in rig.pose.bones:
            raise RuntimeError('Missing target bone '+match.group(1))
        for point in curve.keyframe_points:
            native_key_times.append((point, point.co.x, point.handle_left.x, point.handle_right.x))
            point.co.x *= frame_scale
            point.handle_left.x *= frame_scale
            point.handle_right.x *= frame_scale
    for marker in action.pose_markers:
        native_markers.append((marker, marker.frame))
        marker.frame = round(marker.frame*frame_scale)
    scene.frame_set(0)
    bpy.context.view_layer.update()
    if abs(rig.pose.bones['mixamorig:RightArm'].rotation_quaternion.w-1) < 1e-5:
        raise RuntimeError('Appended action did not pose right arm: '+action.name)
assert {name: action_hash(bpy.data.actions[name]) for name in old_actions} == old_actions
source_names = set(bpy.data.actions.keys())
assert set(old_actions) | library_names == source_names
restore = old_active if old_active in bpy.data.actions else 'motion_idle_spear'
rig.animation_data.action = bpy.data.actions[restore]
rig.animation_data.action_slot = bpy.data.actions[restore].slots[0]
scene.frame_set(0)
bpy.context.view_layer.update()
bpy.ops.object.select_all(action='DESELECT')
for obj in [rig, body]:
    obj.select_set(True)
bpy.context.view_layer.objects.active = rig
bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE))

# Export new clips at their authored sample rate without changing the saved
# source scene or the frame timing of any pre-existing Action in that scene.
scene.render.fps = author['fps']
for point, co, left, right in native_key_times:
    point.co.x, point.handle_left.x, point.handle_right.x = co, left, right
for marker, frame in native_markers:
    marker.frame = frame

# The twelve raw imported source takes are retained in the blend. Match the
# existing game export policy by omitting them only from this in-memory export.
omitted_raw = []
for action in list(bpy.data.actions):
    if '|' in action.name:
        omitted_raw.append(action.name)
        bpy.data.actions.remove(action)
candidate = OUT / 'warrior_candidate.glb'
bpy.ops.export_scene.gltf(filepath=str(candidate), export_format='GLB', use_selection=True,
                          export_animations=True, export_animation_mode='ACTIONS',
                          export_force_sampling=True, export_def_bones=False,
                          export_yup=True, export_image_format='AUTO')
restore_legacy_timestamps(candidate, GLB)
new_gltf, new_exports = animation_payloads(candidate)
missing = (set(old_exports) | library_names)-set(new_exports)
if missing:
    raise RuntimeError('Missing exported clips: '+str(sorted(missing)))
assert not any(node.get('name', '').startswith('Reference_') for node in new_gltf['nodes'])
assert all(name in {node.get('name') for node in new_gltf['nodes']} for name in ['GripRight', 'GripLeft', 'SwordBelt'])
old_max_error = 0.0
for name, old_channels in old_exports.items():
    if name in library_names:
        continue
    new_channels = new_exports[name]
    if old_channels.keys() != new_channels.keys():
        raise RuntimeError('Existing channel inventory changed: '+name)
    for key, old in old_channels.items():
        new = new_channels[key]
        if old['interpolation'] != new['interpolation']:
            raise RuntimeError('Existing interpolation changed: '+name+'/'+key)
        for field in ['times', 'values']:
            if len(old[field]) != len(new[field]):
                raise RuntimeError('Existing sample count changed: '+name+'/'+key+'/'+field)
            error = max((abs(a-b) for va, vb in zip(old[field], new[field]) for a, b in zip(va, vb)), default=0)
            old_max_error = max(old_max_error, error)
            if error > 2e-5:
                raise RuntimeError('Existing animation samples changed: '+name+'/'+key+' error='+str(error))
export_report = {}
for name in sorted(library_names):
    channels = new_exports[name]
    duration = max(row[0] for channel in channels.values() for row in channel['times'])
    assert abs(duration-author['clips'][name]['duration']) < 1e-5, (name, duration)
    assert len(channels) > 20, (name, len(channels))
    export_report[name] = {'duration': duration, 'channels': len(channels), 'slot': slots[name]}

attacks = []
spear = bpy.data.objects['spear']
tip_local = max(spear.data.vertices, key=lambda vertex: vertex.co.z).co.copy()
for name in sorted(library_names):
    info = author['clips'][name]
    if info['kind'] != 'attack':
        continue
    targets = []
    for target in info['targets']:
        action = bpy.data.actions[name]
        rig.animation_data.action = action
        rig.animation_data.action_slot = action.slots[0]
        scene.frame_set(target['frame'])
        bpy.context.view_layer.update()
        evaluated_spear = spear.evaluated_get(bpy.context.evaluated_depsgraph_get())
        grip_position = evaluated_spear.matrix_world.translation.copy()
        tip_position = evaluated_spear.matrix_world @ tip_local
        targets.append({'frame': target['frame'], 'time': target['frame']/author['fps'],
                        'zone': target['zone'], 'kind': target['kind'],
                        'position': target['position'], 'feint': target.get('feint', False),
                        'grip_position': list(grip_position), 'tip_position': list(tip_position),
                        'reach': (tip_position-grip_position).length,
                        'actor_reach': math.hypot(tip_position.x, tip_position.y)})
    attacks.append({'clip': name, 'label': info['label'], 'duration': info['duration'],
                    'contacts': [target for target in targets if not target['feint']],
                    'feints': [target for target in targets if target['feint']]})
guard = {}
for role, name in [('ready', 'spear_ready_loop'), ('enter', 'spear_guard_enter'), ('exit', 'spear_guard_exit')]:
    info = author['clips'][name]
    # Godot's enabled name-suffix importer recognizes and removes `_loop`.
    runtime_name = 'spear_ready' if role == 'ready' else name
    guard[role] = {'clip': name, 'source_clip': name, 'imported_clip': runtime_name,
                   'duration': info['duration'], 'loop': info['loop']}
combat = {'version': 1, 'fps': author['fps'], 'attacks': attacks, 'guard': guard,
          'contact_coordinates': {'space': 'Blender world at source actor origin; metres',
                                  'godot_actor_local_conversion': ['-blender_x', 'blender_z', 'blender_y'],
                                  'reach': 'Euclidean grip_position to tip_position distance',
                                  'actor_reach': 'Horizontal distance from source actor origin to tip_position'},
          'shield_profile': {'space': 'Godot defender actor-local; +Y up, -Z forward; metres',
                             'center': [-.309, 1.106, -.367], 'radii': [.349, .386, .115],
                             'front_threshold': .35,
                             'source': 'Authored spear-ready shield mesh bounds'},
          'targeting': dict(author['targeting'], position_space='Blender world calibration, metres',
                            forward='-Y', up='Z'),
          'provenance': {'source_blend': 'art/warrior.blend',
                         'library_blend': 'art/spearman_attacks_10.blend',
                         'library_sha256': library_hash_before,
                         'author_manifest': str(AUTHOR_MANIFEST.relative_to(ROOT)).replace('\\', '/'),
                         'author_manifest_sha256': file_hash(AUTHOR_MANIFEST),
                         'integrator': 'tools/integrate_spearman_attacks.py',
                         'integrated_at': datetime.now(timezone(timedelta(hours=3))).isoformat(),
                         'blender_version': bpy.app.version_string}}
assert len(attacks) == 10 and sum(len(attack['contacts']) for attack in attacks) == 11
assert file_hash(LIBRARY) == library_hash_before
animation_manifest = json.loads(MANIFEST.read_text(encoding='utf-8'))
for name in sorted(library_names):
    info = author['clips'][name]
    animation_manifest[name] = {'duration': info['duration'], 'loop': info['loop'],
                                'source': 'art/spearman_attacks_10.blend',
                                'label': info['label'], 'impact_frames': info['impact_frames']}
os.replace(candidate, GLB)
COMBAT_DATA.write_text(json.dumps(combat, indent=2, ensure_ascii=False)+'\n', encoding='utf-8')
MANIFEST.write_text(json.dumps(animation_manifest, indent=2, ensure_ascii=False)+'\n', encoding='utf-8')
report = {'passed': True, 'backup': str(backup.relative_to(ROOT)),
          'preserved_source_scene_fps': source_fps, 'new_export_sample_fps': author['fps'],
          'preserved_source_actions': sorted(old_actions), 'source_action_count': len(source_names),
          'preserved_export_actions': sorted(set(old_exports)-library_names),
          'export_action_count': len(new_exports), 'existing_export_max_sample_error': old_max_error,
          'source_action_hashes_unchanged': True, 'review_blend_unchanged': True,
          'raw_source_takes_retained_in_blend_not_game_export': omitted_raw,
          'new_clips': export_report, 'contacts': 11, 'feints': 1,
          'warrior_glb_sha256': file_hash(GLB), 'combat_data': str(COMBAT_DATA.relative_to(ROOT))}
(OUT/'integration_report.json').write_text(json.dumps(report, indent=2, ensure_ascii=False)+'\n', encoding='utf-8')
print('SPEAR_INTEGRATION_PASS', len(old_actions), 'preserved source actions;', len(new_exports), 'export actions;',
      'max old sample error', old_max_error, flush=True)

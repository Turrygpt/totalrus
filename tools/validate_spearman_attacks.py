"""Read-only Blender QA for the dedicated spear-and-shield action library.

blender --background --python-exit-code 1 --python tools/validate_spearman_attacks.py
Only build/spearman_attacks_10/validation.json is written; the blend is never saved.
"""
import ast
import json
import math
from pathlib import Path

import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree
from mathutils.geometry import intersect_ray_tri


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / 'build/spearman_attacks_10/validation.json'
SOURCE = ROOT / 'tools/author_spearman_attacks.py'
BLEND = ROOT / 'art/spearman_attacks_10.blend'
POSITION_TOLERANCE = 2e-5  # metres in the original one-metre rig
ROTATION_TOLERANCE = 2e-4  # radians
SCALE_TOLERANCE = 2e-5
FOOT_TOLERANCE = 2e-4


def authored_definitions():
    """Read motion declarations without executing the Blender authoring script."""
    selected = []
    assignments = {'DEFAULT', 'G', 'CLIPS', 'guard_keys', 'carry', 'enter_keys'}
    functions = {'state', 'key', 'interpolate'}
    tree = ast.parse(SOURCE.read_text(encoding='utf-8'), filename=str(SOURCE))
    for node in tree.body:
        if isinstance(node, ast.FunctionDef) and node.name in functions:
            selected.append(node)
        elif isinstance(node, ast.Assign) and any(
                isinstance(target, ast.Name) and target.id in assignments
                for target in node.targets):
            selected.append(node)
    namespace = {}
    exec(compile(ast.Module(body=selected, type_ignores=[]), str(SOURCE), 'exec'), namespace)
    definitions = {
        'spear_ready_loop': {'end': 60, 'keys': namespace['guard_keys'], 'impacts': []},
        'spear_guard_enter': {'end': 24, 'keys': namespace['enter_keys'], 'impacts': []},
        'spear_guard_exit': {'end': 24, 'keys': [(24-f, s) for f, s in reversed(namespace['enter_keys'])], 'impacts': []},
    }
    for clip in namespace['CLIPS']:
        definitions['spear_attack_' + clip['id']] = clip
    return definitions, namespace['interpolate']


def matrix_error(a, b):
    return max(abs(a[row][col]-b[row][col]) for row in range(4) for col in range(4))


def rotation_error(a, b):
    # Absolute dot also handles equivalent q and -q endpoint representations.
    dot = min(1.0, max(0.0, abs(a.normalized().dot(b.normalized()))))
    return 2 * math.acos(dot)


def snapshot(rig):
    return {bone.name: (bone.location.copy(), bone.rotation_quaternion.copy(), bone.scale.copy())
            for bone in rig.pose.bones}


def snapshot_error(actual, reference):
    return {'location': max((actual[n][0]-reference[n][0]).length for n in reference),
            'quaternion': max(min((actual[n][1]-reference[n][1]).magnitude,
                                  (actual[n][1]+reference[n][1]).magnitude) for n in reference),
            'scale': max((actual[n][2]-reference[n][2]).length for n in reference)}


def triangles_cross(a, b):
    """Narrow phase: finite triangle-edge intersections, including coplanar contact."""
    epsilon = 1e-7
    for triangle, edges in [(a, b), (b, a)]:
        for i in range(3):
            start, end = edges[i], edges[(i+1) % 3]
            direction = end-start
            if direction.length_squared < epsilon*epsilon:
                continue
            hit = intersect_ray_tri(*triangle, direction, start, True)
            if hit is not None:
                fraction = (hit-start).dot(direction)/direction.length_squared
                if -epsilon <= fraction <= 1+epsilon:
                    return True
    na = (a[1]-a[0]).cross(a[2]-a[0])
    nb = (b[1]-b[0]).cross(b[2]-b[0])
    if na.length_squared < epsilon*epsilon or nb.length_squared < epsilon*epsilon:
        return False
    na.normalize(); nb.normalize()
    if na.cross(nb).length > epsilon or abs(na.dot(b[0]-a[0])) > epsilon:
        return False
    # Coplanar triangles: project away the dominant normal axis and use SAT.
    drop = max(range(3), key=lambda i: abs(na[i]))
    axes = [i for i in range(3) if i != drop]
    projected = [[Vector((v[axes[0]], v[axes[1]])) for v in tri] for tri in (a, b)]
    for tri in projected:
        for i in range(3):
            edge = tri[(i+1) % 3]-tri[i]
            axis = Vector((-edge.y, edge.x))
            pa = [v.dot(axis) for v in projected[0]]
            pb = [v.dot(axis) for v in projected[1]]
            if max(pa) < min(pb)-epsilon or max(pb) < min(pa)-epsilon:
                return False
    return True


def equipment_collision(names=('spear', 'shield')):
    """Compare evaluated world-space geometry, independent of viewing angle."""
    graph = bpy.context.evaluated_depsgraph_get()
    geometry = []
    for name in names:
        obj = bpy.data.objects[name].evaluated_get(graph)
        mesh = obj.to_mesh()
        mesh.calc_loop_triangles()
        vertices = [obj.matrix_world @ vertex.co for vertex in mesh.vertices]
        triangles = [tuple(triangle.vertices) for triangle in mesh.loop_triangles]
        obj.to_mesh_clear()
        tree = BVHTree.FromPolygons(vertices, triangles, all_triangles=True, epsilon=0)
        geometry.append((vertices, triangles, tree))
    va, ta, tree_a = geometry[0]
    vb, tb, tree_b = geometry[1]
    candidates = tree_a.overlap(tree_b)
    for ai, bi in candidates:
        a = [va[index] for index in ta[ai]]
        b = [vb[index] for index in tb[bi]]
        if triangles_cross(a, b):
            return {'spear_triangle': ai, 'shield_triangle': bi,
                    'spear_triangle_world': [list(v) for v in a],
                    'shield_triangle_world': [list(v) for v in b],
                    'bvh_pairs': len(candidates)}
    return None


definitions, interpolate = authored_definitions()
bpy.ops.wm.open_mainfile(filepath=str(BLEND))
scene = bpy.context.scene
rig = bpy.data.objects['WarriorRig']
manifest = json.loads((ROOT / 'build/spearman_attacks_10/animation_manifest.json').read_text(encoding='utf-8'))
spear = bpy.data.objects['spear']
tip_local = max(spear.data.vertices, key=lambda vertex: vertex.co.z).co.copy()
has_opponent = 'Reference_DefenderShield' in bpy.data.objects
for track in rig.animation_data.nla_tracks:
    track.mute = True

report = {'file': str(BLEND), 'fps': scene.render.fps, 'read_only': True,
          'action_count': len(bpy.data.actions), 'attack_count': 0,
          'tolerances_rig_units': {'position': POSITION_TOLERANCE,
                                   'rotation_radians': ROTATION_TOLERANCE,
                                   'scale': SCALE_TOLERANCE, 'foot': FOOT_TOLERANCE},
          'actions': {}, 'failures': []}


def fail(action, check, detail):
    report['failures'].append({'action': action, 'check': check, 'detail': detail})


names = set(bpy.data.actions.keys())
expected = set(definitions)
if names != expected:
    fail(None, 'action_inventory', {'missing': sorted(expected-names), 'extra': sorted(names-expected)})
report['attack_count'] = sum(name.startswith('spear_attack_') for name in names)
if len(names) != 13 or report['attack_count'] != 10:
    fail(None, 'action_count', {'actions': len(names), 'attacks': report['attack_count']})
if scene.render.fps != 30:
    fail(None, 'fps', scene.render.fps)

world_origin = rig.matrix_world.copy()
common_guard = None
socket_reference = None
action_pose_cache = {}
report['equipment_collision'] = {'method': 'Evaluated world-space triangle BVH plus finite edge/triangle narrow phase',
                                 'scope': 'Spear versus shield, every integer frame in all 13 actions',
                                 'frames_evaluated': 0, 'intersections': []}
report['opponent_targeting'] = {'available': has_opponent, 'tip_local': list(tip_local),
                              'contact_tolerance_metres': .01, 'contacts': [],
                              'opposing_shield_intersections': [],
                              'offcontact_shield_intersections': []}
for name in sorted(expected & names):
    action = bpy.data.actions[name]
    definition = definitions[name]
    rig.animation_data.action = action
    scene.frame_set(0)
    bpy.context.view_layer.update()
    first = snapshot(rig)
    if name.startswith('spear_attack_') and common_guard is None:
        common_guard = first
    if socket_reference is None:
        socket_reference = {socket: rig.pose.bones[socket].parent.matrix.inverted() @ rig.pose.bones[socket].matrix
                            for socket in ['GripRight', 'GripLeft', 'SwordBelt']}
    stats = {'frames_evaluated': definition['end']+1,
             'max_bone_scale_error': 0.0, 'max_nonroot_location_change': 0.0,
             'max_object_root_drift': 0.0, 'max_socket_offset_error': 0.0,
             'max_foot_target_error': {'Left': 0.0, 'Right': 0.0},
             'max_leg_reach_excess': {'Left': 0.0, 'Right': 0.0},
             'max_planted_foot_drift': {'Left': 0.0, 'Right': 0.0},
             'intentional_steps': ['Left'] if name.endswith('02_power_lunge') else
                                  ['Right'] if name.endswith('08_retreat_counter') else
                                  ['Left', 'Right'] if 'guard_enter' in name or 'guard_exit' in name else [],
             'extrema': {}}
    first_feet = {side: rig.pose.bones['mixamorig:'+side+'Foot'].head.copy() for side in ['Left', 'Right']}
    action_pose_cache[name] = []
    target_plan = manifest['clips'][name].get('targets', [])

    def maximum(field, value, frame, bone=None):
        if value > stats[field]:
            stats[field] = value
            stats['extrema'][field] = {'frame': frame, 'bone': bone}

    for frame in range(definition['end']+1):
        scene.frame_set(frame)
        bpy.context.view_layer.update()
        action_pose_cache[name].append(snapshot(rig))
        intersection = equipment_collision()
        report['equipment_collision']['frames_evaluated'] += 1
        if intersection:
            report['equipment_collision']['intersections'].append(dict(action=name, frame=frame, **intersection))
        if has_opponent:
            tip_world = spear.evaluated_get(bpy.context.evaluated_depsgraph_get()).matrix_world @ tip_local
            opponent_intersection = equipment_collision(('spear', 'Reference_DefenderShield'))
            if opponent_intersection:
                permitted = any(t['kind'] == 'shield' and not t.get('feint', False)
                                and abs(t['frame']-frame) <= 2 for t in target_plan)
                evidence = dict(action=name, frame=frame, permitted_contact=permitted,
                                tip_world=list(tip_world), **opponent_intersection)
                report['opponent_targeting']['opposing_shield_intersections'].append(evidence)
                if not permitted:
                    report['opponent_targeting']['offcontact_shield_intersections'].append(evidence)
            for target in target_plan:
                if target['frame'] != frame:
                    continue
                distance = (tip_world-Vector(target['position'])).length
                contact = dict(action=name, frame=frame, zone=target['zone'], kind=target['kind'],
                               feint=target.get('feint', False), target_world=target['position'],
                               tip_world=list(tip_world), distance_metres=distance)
                report['opponent_targeting']['contacts'].append(contact)
                print('CONTACT_QA', name, frame, target['zone'], round(distance, 6), flush=True)
                if not target.get('feint', False) and distance > .01:
                    fail(name, 'tip_misses_declared_target', contact)
                if target.get('feint', False) and distance < .08:
                    fail(name, 'feint_unintended_contact', contact)
        maximum('max_object_root_drift', matrix_error(rig.matrix_world, world_origin), frame)
        for bone in rig.pose.bones:
            maximum('max_bone_scale_error', max(abs(v-1) for v in bone.scale), frame, bone.name)
            if bone.parent:
                maximum('max_nonroot_location_change', (bone.location-first[bone.name][0]).length, frame, bone.name)
            if not all(math.isfinite(v) for row in bone.matrix for v in row):
                fail(name, 'nonfinite_transform', {'frame': frame, 'bone': bone.name})
        for socket, reference in socket_reference.items():
            bone = rig.pose.bones[socket]
            relative = bone.parent.matrix.inverted() @ bone.matrix
            maximum('max_socket_offset_error', matrix_error(relative, reference), frame, socket)
        state = interpolate(definition['keys'], frame)
        for side, origin, field in [('Left', (.105, -.145, .0605), 'lf'),
                                    ('Right', (-.12, .125, .0605), 'rf')]:
            target = Vector(origin) + Vector(state[field])
            foot = rig.pose.bones['mixamorig:'+side+'Foot']
            upper = rig.pose.bones['mixamorig:'+side+'UpLeg']
            lower = rig.pose.bones['mixamorig:'+side+'Leg']
            error = (foot.head-target).length
            stats['max_foot_target_error'][side] = max(stats['max_foot_target_error'][side], error)
            distance = (target-upper.head).length
            max_reach = (upper.bone.length+lower.bone.length)*.985
            min_reach = abs(upper.bone.length-lower.bone.length)+.0001
            excess = max(0.0, distance-max_reach, min_reach-distance)
            stats['max_leg_reach_excess'][side] = max(stats['max_leg_reach_excess'][side], excess)
            if side not in stats['intentional_steps']:
                drift = (foot.head-first_feet[side]).length
                stats['max_planted_foot_drift'][side] = max(stats['max_planted_foot_drift'][side], drift)
    last = snapshot(rig)
    if name.startswith('spear_attack_') or name == 'spear_ready_loop':
        stats['endpoint_location_error'] = max((first[n][0]-last[n][0]).length for n in first)
        stats['endpoint_rotation_error'] = max(rotation_error(first[n][1], last[n][1]) for n in first)
        # Components are more numerically reliable than acos for identical 32-bit quaternions.
        stats['endpoint_quaternion_error'] = max(min((first[n][1]-last[n][1]).magnitude,
                                                     (first[n][1]+last[n][1]).magnitude) for n in first)
        if stats['endpoint_location_error'] > POSITION_TOLERANCE or stats['endpoint_quaternion_error'] > ROTATION_TOLERANCE/2:
            fail(name, 'endpoints_do_not_match', {k: v for k, v in stats.items() if k.startswith('endpoint_')})
    if name.startswith('spear_attack_'):
        stats['common_guard_location_error'] = max((first[n][0]-common_guard[n][0]).length for n in first)
        stats['common_guard_quaternion_error'] = max(min((first[n][1]-common_guard[n][1]).magnitude,
                                                        (first[n][1]+common_guard[n][1]).magnitude) for n in first)
        if stats['common_guard_location_error'] > POSITION_TOLERANCE or stats['common_guard_quaternion_error'] > ROTATION_TOLERANCE/2:
            fail(name, 'common_guard_mismatch', stats['common_guard_quaternion_error'])
    for field, tolerance in [('max_bone_scale_error', SCALE_TOLERANCE),
                              ('max_nonroot_location_change', POSITION_TOLERANCE),
                              ('max_object_root_drift', POSITION_TOLERANCE),
                              ('max_socket_offset_error', POSITION_TOLERANCE)]:
        if stats[field] > tolerance:
            fail(name, field, {'maximum': stats[field], 'at': stats['extrema'].get(field)})
    for field in ['max_foot_target_error', 'max_leg_reach_excess', 'max_planted_foot_drift']:
        for side, value in stats[field].items():
            if value > FOOT_TOLERANCE:
                fail(name, field, {'side': side, 'maximum': value})
    expected_contacts = definition['impacts']
    contacts = [marker.frame for marker in action.pose_markers if marker.name.startswith('CONTACT_')]
    stats['contact_frames'] = sorted(contacts)
    if sorted(contacts) != expected_contacts:
        fail(name, 'contact_markers', {'expected': expected_contacts, 'actual': sorted(contacts)})
    report['actions'][name] = stats
    print('VALIDATED', name, 'feet', stats['max_foot_target_error'], flush=True)

if report['equipment_collision']['intersections']:
    collision_frames = {}
    for entry in report['equipment_collision']['intersections']:
        collision_frames.setdefault(entry['action'], []).append(entry['frame'])
    fail(None, 'spear_shield_geometry_intersection', collision_frames)
if report['opponent_targeting']['offcontact_shield_intersections']:
    collision_frames = {}
    for entry in report['opponent_targeting']['offcontact_shield_intersections']:
        collision_frames.setdefault(entry['action'], []).append(entry['frame'])
    fail(None, 'unintended_opponent_shield_intersection', collision_frames)
    print('OFFCONTACT_OPPONENT_SHIELD', json.dumps(collision_frames), flush=True)

# Validate the actual review timeline after clearing the temporary active Action.
# Every strip frame must reproduce its Action; every gap must hold the preceding
# endpoint. This directly detects any reset into a rest/T-pose between strips.
rig.animation_data.action = None
tracks = list(rig.animation_data.nla_tracks)
review = {'tracks': len(tracks), 'strips': [], 'frames_evaluated': 0,
          'gap_frames_evaluated': 0, 'max_location_error': 0.0,
          'max_quaternion_error': 0.0, 'max_scale_error': 0.0, 'mismatch_frames': []}
report['nla_review'] = review
if len(tracks) != 1:
    fail(None, 'nla_track_count', len(tracks))
else:
    track = tracks[0]
    track.mute = False
    strips = sorted(track.strips, key=lambda s: s.frame_start)
    if len(strips) != 13:
        fail(None, 'nla_strip_count', len(strips))
    for strip in strips:
        review['strips'].append({'action': strip.action.name,
                                 'start': strip.frame_start, 'end': strip.frame_end,
                                 'extrapolation': strip.extrapolation})
        if strip.extrapolation != 'HOLD_FORWARD':
            fail(strip.action.name, 'nla_gap_extrapolation', strip.extrapolation)
    for frame in range(scene.frame_start, scene.frame_end+1):
        preceding = [s for s in strips if s.frame_start <= frame]
        if not preceding:
            fail(None, 'uncovered_nla_frame', frame)
            continue
        strip = preceding[-1]
        local_frame = min(strip.action_frame_end,
                          strip.action_frame_start+(frame-strip.frame_start)/strip.scale)
        if abs(local_frame-round(local_frame)) > .0001:
            fail(strip.action.name, 'fractional_nla_sample', frame)
            continue
        gap = frame > strip.frame_end
        scene.frame_set(frame)
        bpy.context.view_layer.update()
        reference = action_pose_cache[strip.action.name][round(local_frame)]
        errors = snapshot_error(snapshot(rig), reference)
        review['frames_evaluated'] += 1
        review['gap_frames_evaluated'] += int(gap)
        for field, value in errors.items():
            review['max_'+field+'_error'] = max(review['max_'+field+'_error'], value)
        if errors['location'] > POSITION_TOLERANCE or errors['quaternion'] > ROTATION_TOLERANCE/2 or errors['scale'] > SCALE_TOLERANCE:
            review['mismatch_frames'].append({'frame': frame, 'gap': gap,
                                               'action': strip.action.name, 'errors': errors})
    if review['mismatch_frames']:
        fail(None, 'nla_pose_mismatch', {'count': len(review['mismatch_frames']),
                                       'first': review['mismatch_frames'][0]})
    print('NLA_VALIDATED', review['frames_evaluated'], 'GAP_FRAMES', review['gap_frames_evaluated'], flush=True)

report['passed'] = not report['failures']
OUTPUT.parent.mkdir(parents=True, exist_ok=True)
OUTPUT.write_text(json.dumps(report, indent=2, ensure_ascii=False), encoding='utf-8')
print('SPEARMAN_VALIDATION', 'PASS' if report['passed'] else 'FAIL', str(OUTPUT), flush=True)
if report['failures']:
    raise RuntimeError(json.dumps(report['failures'], ensure_ascii=False))

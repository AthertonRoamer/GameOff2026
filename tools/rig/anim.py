"""Night Shift sprite renderer: Mixamo X Bot dressed per role, Palette A, cel-shaded with ink outlines.

Renders three kinds of sprite, all top-down with the character facing up:
  legs_*   bottom layer, rotates to movement direction
  torso_*  top layer, rotates to aim direction (same camera as legs, so they stack exactly)
  downed   full-body sprite that replaces both layers

Usage:  python3 anim.py -- <role|all> [outdir] [state,state,...]
Edit PAL or ROLES and re-run to change colours or gear; every frame re-renders in the new look.
"""
import bpy, math, os, sys
from mathutils import Matrix, Quaternion, Vector

args = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
ROLE_ARG = args[0] if args else 'all'
OUT = args[1] if len(args) > 1 else 'anim'
ONLY = set(args[2].split(',')) if len(args) > 2 else None
HERE = os.path.dirname(os.path.abspath(__file__))
SMOOTH = os.environ.get('SHADE') == 'smooth'   # soft shading for the pixel-art pass
INK = os.environ.get('INK', '1') != '0'         # 3D ink hull; the pixel pass draws its own outline

# ------------------------------------------------------------------ palette A
PAL = dict(
    void='#07090c', shadow='#0c0e12', deep='#151920',
    floor='#1a1f27', line='#222833', wall='#2a313d', walltop='#3a4352', metal='#5a6475',
    g0='#1b2435', g1='#2b3a55', g2='#4a5d80', armor='#3c4a63',
    i0='#0e0f12', i1='#1a1b1f', i2='#34363d', nv='#4be38a',
    flash='#fff3c4', backup='#f2b544', warm='#e07b2a',
    alarm='#e5484d', medic='#c8322f', item='#6fd3e8',
    text='#e7e3d8', muted='#a9a495', accent='#8fb3e0',
)
# character accents that sit outside the 25 environment slots
ACCENT = dict(beanie='#7a3b46', duffel='#3a2f2a', gun='#1d1f24', holster='#151920')
SKIN = {'a': '#c99a76', 'b': '#a87553', 'c': '#8a5a3c', 'd': '#e0b48f'}

GUARD_JACKET = (PAL['g0'], PAL['g1'], PAL['g2'])
GUARD_PANTS = ('#11172a', PAL['g0'], PAL['g1'])
ROLES = {
    'guard': dict(jacket=GUARD_JACKET, pants=GUARD_PANTS, hands=SKIN['b'], head=SKIN['b'], gear='cap', weapon='pistol'),
    'medic': dict(jacket=GUARD_JACKET, pants=GUARD_PANTS, hands=SKIN['a'], head=SKIN['a'], gear='medic', weapon='pistol'),
    'gunner': dict(jacket=GUARD_JACKET, pants=GUARD_PANTS, hands=SKIN['c'], head=SKIN['c'], gear='gunner', weapon='rifle', scale=1.2),
    'electrician': dict(jacket=GUARD_JACKET, pants=GUARD_PANTS, hands='#7a5a3a', head=SKIN['d'], gear='electrician', weapon='pistol'),
    'shade': dict(jacket=('#121a28', '#1f2a3d', '#33445f'), pants=(PAL['shadow'], PAL['deep'], '#1f2a3d'), hands='#2e3138', head=SKIN['a'], gear='hood', weapon='suppressed'),
    'ventrat': dict(jacket=GUARD_JACKET, pants=GUARD_PANTS, hands=SKIN['a'], head=SKIN['a'], gear='beanie', weapon='smg', scale=0.92),
    'intruder': dict(jacket=(PAL['i0'], PAL['i1'], PAL['i2']), pants=(PAL['void'], PAL['i0'], PAL['i1']), hands=PAL['i2'], head=PAL['i1'], gear='nvg', weapon='suppressed'),
}

# name, layer, action, frames, mode, extras
STATES = [
    dict(name='legs_idle', layer='legs', action='idle', n=8, mode='free'),
    dict(name='legs_walk', layer='legs', action='walk', n=12, mode='free', blend=0.6),
    dict(name='legs_run', layer='legs', action='run', n=12, mode='free'),
    dict(name='torso_idle', layer='torso', action='idle', n=8, mode='holster'),
    dict(name='torso_idle_aim', layer='torso', action='idle', n=8, mode='aim'),
    dict(name='torso_walk', layer='torso', action='walk', n=12, mode='holster', blend=0.6),
    dict(name='torso_walk_aim', layer='torso', action='walk', n=12, mode='aim', blend=0.6),
    dict(name='torso_run', layer='torso', action='run', n=12, mode='holster'),
    dict(name='torso_interact', layer='torso', action='idle', n=12, mode='interact'),
    dict(name='downed', layer='full', action='idle', n=8, mode='downed'),
    # a turn on the spot, from a Mixamo clip: a right turn of about 96 degrees that starts and ends in the standing stance, with the body's
    # yaw baked into the frames. The game leaves the legs node alone while the sheet plays, turns it by 96 degrees at the end, and mirrors the sheet for a left turn.
    dict(name='legs_turn', layer='legs', action='turn', n=16, mode='free', clip='Right Turn.fbx', yaw_offset=-6),
]
IDLE_SPINE = Vector((0.0, 0.0, 1.323))


# ------------------------------------------------------------------ materials
def lin(h):
    h = h.lstrip('#')
    c = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    return tuple(x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c) + (1,)


def tone(hexcol, k):
    c = [int(hexcol.lstrip('#')[i:i + 2], 16) for i in (0, 2, 4)]
    c = [int(x * k) for x in c] if k <= 1 else [int(x + (255 - x) * (k - 1)) for x in c]
    return '#%02x%02x%02x' % tuple(min(255, x) for x in c)


LIGHT = Vector((0.42, -0.42, 0.80)).normalized()


def mat(name, col, emit=False):
    """Cel material with three hard bands. col is a hex (bands derived) or (shadow, base, highlight)."""
    m = bpy.data.materials.get(name)
    if m:
        return m
    m = bpy.data.materials.new(name)
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new('ShaderNodeOutputMaterial')
    em = nt.nodes.new('ShaderNodeEmission')
    nt.links.new(em.outputs[0], out.inputs['Surface'])
    if emit:
        em.inputs['Color'].default_value = lin(col)
        return m
    sh, base, hi = col if isinstance(col, tuple) else (tone(col, 0.62), col, tone(col, 1.22))
    geo = nt.nodes.new('ShaderNodeNewGeometry')
    dot = nt.nodes.new('ShaderNodeVectorMath')
    dot.operation = 'DOT_PRODUCT'
    dot.inputs[1].default_value = LIGHT
    nt.links.new(geo.outputs['Normal'], dot.inputs[0])
    ramp = nt.nodes.new('ShaderNodeValToRGB')
    els = ramp.color_ramp.elements
    if SMOOTH:  # soft gradient; the pixel pass quantises it into palette bands
        ramp.color_ramp.interpolation = 'LINEAR'
        els[0].position, els[0].color = 0.0, lin(sh)
        els[1].position, els[1].color = 0.5, lin(base)
        els.new(1.0).color = lin(hi)
    else:
        ramp.color_ramp.interpolation = 'CONSTANT'
        els[0].position, els[0].color = 0.0, lin(sh)
        els[1].position, els[1].color = 0.38, lin(base)
        els.new(0.9).color = lin(hi)
    nt.links.new(dot.outputs['Value'], ramp.inputs['Fac'])
    nt.links.new(ramp.outputs['Color'], em.inputs['Color'])
    return m


def clear():
    m = bpy.data.materials.get('clear')
    if m:
        return m
    m = bpy.data.materials.new('clear')
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new('ShaderNodeOutputMaterial')
    tr = nt.nodes.new('ShaderNodeBsdfTransparent')
    nt.links.new(tr.outputs[0], out.inputs['Surface'])
    return m


def ink():
    """Inverted-hull outline: only hull faces behind the model render, as an ink rim."""
    m = bpy.data.materials.get('ink')
    if m:
        return m
    m = bpy.data.materials.new('ink')
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new('ShaderNodeOutputMaterial')
    geo = nt.nodes.new('ShaderNodeNewGeometry')
    em = nt.nodes.new('ShaderNodeEmission')
    em.inputs['Color'].default_value = lin(PAL['void'])
    tr = nt.nodes.new('ShaderNodeBsdfTransparent')
    mix = nt.nodes.new('ShaderNodeMixShader')
    nt.links.new(geo.outputs['Backfacing'], mix.inputs['Fac'])
    nt.links.new(em.outputs[0], mix.inputs[1])
    nt.links.new(tr.outputs[0], mix.inputs[2])
    nt.links.new(mix.outputs[0], out.inputs['Surface'])
    return m


def outline(obj, world_t, offset, even=True):
    sc = obj.matrix_world.to_scale()
    mod = obj.modifiers.new('ink', 'SOLIDIFY')
    mod.thickness = -world_t / max(sc.x, 1e-6)
    mod.offset = -1
    mod.use_flip_normals = True
    mod.use_even_offset = even
    mod.use_rim = False
    mod.material_offset = offset
    mod.material_offset_rim = offset


# ------------------------------------------------------------------ body regions
REGIONS = ['jacket', 'pants', 'hands', 'head']


def region_of(group):
    g = group.replace('mixamorig:', '')
    if 'Hand' in g:
        return 'hands'
    if g.startswith(('Head', 'Neck', 'LeftEye', 'RightEye')):
        return 'head'
    if g.startswith(('LeftUpLeg', 'RightUpLeg', 'LeftLeg', 'RightLeg', 'LeftFoot', 'RightFoot', 'LeftToe', 'RightToe', 'Hips')):
        return 'pants'
    return 'jacket'


def paint_regions(obj, cfg, with_ink, force=None):
    me = obj.data
    names = {g.index: g.name for g in obj.vertex_groups}
    me.materials.clear()
    for r in REGIONS:
        me.materials.append(mat(f"{cfg['_role']}_{r}", cfg[r]))
    if with_ink:
        for r in REGIONS:
            me.materials.append(ink())
    for poly in me.polygons:
        acc = {}
        for vi in poly.vertices:
            for g in me.vertices[vi].groups:
                k = region_of(names[g.group])
                acc[k] = acc.get(k, 0) + g.weight
        if force:
            poly.material_index = REGIONS.index(force)
            continue
        poly.material_index = REGIONS.index(max(acc, key=acc.get)) if acc else 0


# ------------------------------------------------------------------ props
PROPS = []  # (object, tag)


def prim(kind, loc, size, m, tag, rot=(0, 0, 0)):
    if kind == 'cube':
        bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=rot)
    elif kind == 'sphere':
        bpy.ops.mesh.primitive_uv_sphere_add(radius=1, location=loc, rotation=rot, segments=32, ring_count=16)
    else:
        bpy.ops.mesh.primitive_cylinder_add(radius=1, depth=1, location=loc, rotation=rot, vertices=32)
    o = bpy.context.active_object
    o.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    o.data.materials.append(m)
    o.data.materials.append(ink())
    bpy.ops.object.shade_smooth()
    PROPS.append((o, tag))
    return o


def wpos(arm, bone):
    return arm.matrix_world @ arm.pose.bones['mixamorig:' + bone].head


def attach(arm, o, bone):
    bpy.context.view_layer.update()
    mw = o.matrix_world.copy()
    o.parent = arm
    o.parent_type = 'BONE'
    o.parent_bone = 'mixamorig:' + bone
    bpy.context.view_layer.update()
    o.matrix_world = mw


# ------------------------------------------------------------------ posing
def aim_bone(arm, bone, child, goal):
    """Rotate a bone so the real segment from its head to its child's head points at goal."""
    pb = arm.pose.bones['mixamorig:' + bone]
    M = arm.matrix_world @ pb.matrix
    head_w = M.to_translation()
    cur = (wpos(arm, child) - head_w).normalized()
    q = cur.rotation_difference((goal - head_w).normalized())
    rest = M.copy()
    rest.translation = (0, 0, 0)
    newM = q.to_matrix().to_4x4() @ rest
    newM.translation = head_w
    pb.matrix = arm.matrix_world.inverted() @ newM
    bpy.context.view_layer.update()


def pose_arms(arm, targets, pole, hand_dir):
    """Two-bone solve per arm, then lock the wrist so the fist points along hand_dir."""
    for side, t in targets.items():
        sgn = 1 if side == 'Left' else -1
        S = wpos(arm, f'{side}Arm')
        E0, H0 = wpos(arm, f'{side}ForeArm'), wpos(arm, f'{side}Hand')
        L1, L2 = (E0 - S).length, (H0 - E0).length
        T = Vector(t)
        d = min(max((T - S).length, abs(L1 - L2) + 1e-3), (L1 + L2) * 0.999)
        dr = (T - S).normalized()
        T = S + dr * d
        a = (L1 * L1 - L2 * L2 + d * d) / (2 * d)
        h = math.sqrt(max(L1 * L1 - a * a, 0))
        P = Vector(pole(sgn))
        pp = (P - dr * P.dot(dr)).normalized()
        E = S + dr * a + pp * h
        aim_bone(arm, f'{side}Arm', f'{side}ForeArm', E)
        aim_bone(arm, f'{side}ForeArm', f'{side}Hand', T)
        aim_bone(arm, f'{side}Hand', f'{side}HandMiddle1', T + Vector(hand_dir(sgn)))


def fingers_to_fists(arm):
    for pb in arm.pose.bones:
        n = pb.name.replace('mixamorig:', '')
        if 'Hand' in n and n[-1] == '1':
            pb.scale = (0.05, 0.05, 0.05)  # fingers tuck away; a fist sphere sits on the hand
    bpy.context.view_layer.update()


def recenter(arm):
    """Cancel the clip's root offset so hips stay on the sprite's pivot."""
    bpy.context.view_layer.update()
    h = wpos(arm, 'Hips')
    arm.location.x -= h.x
    arm.location.y -= h.y
    bpy.context.view_layer.update()


# ------------------------------------------------------------------ retargeting
# The body is a human avatar (readyplayer.me.glb, A-pose rest); the motion comes from the
# Mixamo clips inside Xbot.glb (T-pose rest). Each frame, every bone of the body copies
# the clip's world-space rotation change, measured against a matched T-pose reference.
CHAINS = [('LeftShoulder', 'LeftArm'), ('LeftArm', 'LeftForeArm'), ('LeftForeArm', 'LeftHand'),
          ('RightShoulder', 'RightArm'), ('RightArm', 'RightForeArm'), ('RightForeArm', 'RightHand'),
          ('LeftUpLeg', 'LeftLeg'), ('LeftLeg', 'LeftFoot'), ('RightUpLeg', 'RightLeg'), ('RightLeg', 'RightFoot')]


def match_rest(src, tgt):
    """Pose the body into the clip rig's T-pose; return each bone's world rotation there."""
    Ms = src.matrix_world
    for b, c in CHAINS:
        d = (Ms @ src.data.bones['mixamorig:' + c].head_local) - (Ms @ src.data.bones['mixamorig:' + b].head_local)
        aim_bone(tgt, b, c, wpos(tgt, b) + d.normalized())
    ref = {pb.name: (tgt.matrix_world @ pb.matrix).to_quaternion() for pb in tgt.pose.bones}
    for pb in tgt.pose.bones:
        pb.matrix_basis.identity()
    bpy.context.view_layer.update()
    return ref


def retarget(src, tgt, ref):
    bpy.context.view_layer.update()
    Ms, Mt = src.matrix_world, tgt.matrix_world
    sh_rest = (Ms @ src.data.bones['mixamorig:Hips'].matrix_local).to_translation()
    sh_pose = (Ms @ src.pose.bones['mixamorig:Hips'].matrix).to_translation()
    th_rest = (Mt @ tgt.data.bones['mixamorig:Hips'].matrix_local).to_translation()
    ratio = th_rest.z / sh_rest.z
    scl = Mt.to_scale()
    S = Matrix.Diagonal((scl.x, scl.y, scl.z, 1))
    pose = {}
    for b in tgt.data.bones:  # parents come before children
        if b.name in src.pose.bones:
            sb = src.data.bones[b.name]
            delta = (Ms @ src.pose.bones[b.name].matrix).to_quaternion() @ (Ms @ sb.matrix_local).to_quaternion().inverted()
        else:
            delta = None
        if b.parent is None:
            head_w = th_rest + (sh_pose - sh_rest) * ratio
            rot_w = (delta if delta else Quaternion()) @ ref[b.name]
        else:
            par_pose = pose[b.parent.name]
            par_rest = Mt @ b.parent.matrix_local
            head_w = (par_pose @ par_rest.inverted() @ (Mt @ b.matrix_local)).to_translation()
            if delta is None:
                delta = par_pose.to_quaternion() @ ref[b.parent.name].inverted()
            rot_w = delta @ ref[b.name]
        pose[b.name] = Matrix.Translation(head_w) @ rot_w.to_matrix().to_4x4() @ S
    inv = Mt.inverted()
    for b in tgt.data.bones:
        A = inv @ pose[b.name]
        if b.parent is None:
            basis = b.matrix_local.inverted() @ A
        else:
            rest_rel = b.parent.matrix_local.inverted() @ b.matrix_local
            basis = rest_rel.inverted() @ (inv @ pose[b.parent.name]).inverted() @ A
        tgt.pose.bones[b.name].matrix_basis = basis
    bpy.context.view_layer.update()


def lateral_angle(a):
    """Which way an armature's left-right axis points in the world (radians), from its rest pose."""
    M = a.matrix_world
    v = (M @ a.data.bones['mixamorig:LeftUpLeg'].head_local) - (M @ a.data.bones['mixamorig:RightUpLeg'].head_local)
    return math.atan2(v.y, v.x)


def smooth(x):
    x = max(0.0, min(1.0, x))
    return x * x * (3 - 2 * x)


# ------------------------------------------------------------------ build one role
def build(role):
    cfg = dict(ROLES[role], _role=role)
    PROPS.clear()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    # motion source: the Mixamo clips in Xbot.glb (its mannequin mesh is discarded)
    bpy.ops.import_scene.gltf(filepath=os.path.join(HERE, 'Xbot.glb'))
    src = [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]
    for o in list(bpy.data.objects):
        if o.type == 'MESH':
            bpy.data.objects.remove(o)
    src.hide_render = True
    # extra Mixamo clips (FBX, Without Skin, In Place) each bring their own armature; turn it to face the same way as the Xbot's
    clip_src = {}
    for fname in sorted({s['clip'] for s in STATES if s.get('clip')}):
        before_clip = set(bpy.data.objects)
        bpy.ops.import_scene.fbx(filepath=os.path.join(HERE, 'clips', fname))
        carm = [o for o in bpy.data.objects if o not in before_clip and o.type == 'ARMATURE'][0]
        carm.hide_render = True
        carm.rotation_mode = 'XYZ'
        bpy.context.view_layer.update()
        print('lateral xbot=%.1f clip=%.1f' % (math.degrees(lateral_angle(src)), math.degrees(lateral_angle(carm))), flush=True)
        carm.rotation_euler.z += lateral_angle(src) - lateral_angle(carm)
        bpy.context.view_layer.update()
        print('lateral after=%.1f' % math.degrees(lateral_angle(carm)), flush=True)
        clip_src[fname] = [carm, carm.animation_data.action, None]
    # body: a human avatar with separate shirt / trousers / shoes meshes
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(HERE, 'readyplayer.me.glb'))
    new = [o for o in bpy.data.objects if o not in before]
    arm = [o for o in new if o.type == 'ARMATURE'][0]
    for o in new:
        if o.name.startswith('Icosphere') or any(k in o.name for k in ('Teeth', 'Eye', 'Beard', 'Headwear')):
            bpy.data.objects.remove(o)
    for b in arm.data.bones:
        if not b.name.startswith('mixamorig:'):
            b.name = 'mixamorig:' + b.name
    arm.rotation_mode = 'XYZ'
    k = cfg.get('scale', 1.0)
    arm.scale = (k, k, k)
    sc = bpy.context.scene
    acts = bpy.data.actions
    src.animation_data.action = None
    for pb in src.pose.bones:
        pb.matrix_basis.identity()
    bpy.context.view_layer.update()
    REF = match_rest(src, arm)
    for entry in clip_src.values():
        entry[0].animation_data.action = None
        for pb in entry[0].pose.bones:
            pb.matrix_basis.identity()
        bpy.context.view_layer.update()
        entry[2] = match_rest(entry[0], arm)
        entry[0].animation_data.action = entry[1]
    src.animation_data.action = acts['idle']
    sc.frame_set(1)
    retarget(src, arm, REF)
    recenter(arm)
    BODY = [o for o in bpy.data.objects if o.type == 'MESH' and o.parent == arm]
    for o in BODY:
        force = None
        if 'Outfit_Top' in o.name:
            force = 'jacket'
        elif 'Outfit_Bottom' in o.name or 'Footwear' in o.name:
            force = 'pants'
        elif 'Wolf3D_Head' in o.name:
            force = 'head'
        paint_regions(o, cfg, True, force)
    idle_rot = {pb.name: pb.rotation_quaternion.copy() for pb in arm.pose.bones}
    idle_loc = {pb.name: pb.location.copy() for pb in arm.pose.bones}
    fingers_to_fists(arm)

    spine_ref = wpos(arm, 'Spine2')
    shz = wpos(arm, 'LeftArm').z
    w = cfg['weapon']
    if w == 'rifle':
        aim_t = {'Left': Vector((-0.02, -0.58, shz - 0.10)), 'Right': Vector((-0.09, -0.28, shz - 0.07))}
        aim_dir = lambda s: (0.0, -0.1, 0.0)
    else:
        aim_t = {'Left': Vector((0.035, -0.4, shz - 0.13)), 'Right': Vector((-0.035, -0.4, shz - 0.13))}
        aim_dir = lambda s: (-s * 0.03, -0.1, 0.0)
    aim_pole = lambda s: (s * 1.0, 0.3, -0.45)
    pose_arms(arm, aim_t, aim_pole, aim_dir)

    head, top = wpos(arm, 'Head'), wpos(arm, 'HeadTop_End')
    hk = (top - head).length / 0.177  # gear was sized for the mannequin head
    hc = (head + top) / 2 + Vector((0, 0, 0.035 * hk))
    spine = wpos(arm, 'Spine2')
    hips = wpos(arm, 'Hips')
    lsh, rsh = wpos(arm, 'LeftArm'), wpos(arm, 'RightArm')
    gun = mat('gun', (ACCENT['gun'], ACCENT['gun'], PAL['metal']))
    navy = mat('navydark', (PAL['void'], PAL['g0'], PAL['g1']))

    # ---- weapon in hand (aim only) ----
    gz = shz - 0.1
    if w == 'pistol':
        prim('cube', (0, -0.47, gz), (0.035, 0.17, 0.05), gun, 'hand')
    elif w == 'suppressed':
        prim('cube', (0, -0.46, gz), (0.035, 0.15, 0.05), gun, 'hand')
        prim('cyl', (0, -0.6, gz + 0.01), (0.018, 0.018, 0.14), mat('supp', PAL['i2']), 'hand', rot=(math.pi / 2, 0, 0))
    elif w == 'smg':
        prim('cube', (0, -0.5, gz), (0.05, 0.3, 0.07), gun, 'hand')
        prim('cube', (0, -0.45, gz - 0.07), (0.025, 0.04, 0.12), gun, 'hand')
    elif w == 'rifle':
        prim('cube', (-0.06, -0.45, shz - 0.03), (0.055, 0.85, 0.08), gun, 'hand')
        prim('cube', (-0.06, -0.62, shz - 0.03), (0.07, 0.25, 0.1), mat('hg', PAL['i2']), 'hand')
    hand_items = [(o, o.location.copy()) for o, t in PROPS if t == 'hand']

    # ---- holstered weapon ----
    n0 = len(PROPS)
    if w in ('pistol', 'suppressed'):
        prim('cube', (hips.x - 0.2, hips.y - 0.01, hips.z + 0.04), (0.06, 0.14, 0.1), mat('holster', ACCENT['holster']), 'holster')
        prim('cube', (hips.x - 0.2, hips.y - 0.07, hips.z + 0.12), (0.035, 0.05, 0.05), gun, 'holster')
        for o, _ in PROPS[n0:]:
            attach(arm, o, 'Hips')
    else:
        length = 0.75 if w == 'rifle' else 0.34
        lift = 0.16 if cfg['gear'] == 'gunner' else 0.08
        prim('cube', (spine.x, spine.y + 0.2, spine.z + lift), (0.055, length, 0.07), gun, 'holster', rot=(0, 0, math.radians(32)))
        for o, _ in PROPS[n0:]:
            attach(arm, o, 'Spine2')

    # ---- role gear ----
    n0 = len(PROPS)
    g = cfg['gear']
    if g == 'cap':
        prim('sphere', hc + Vector((0, 0.01, 0.01)), (0.108, 0.115, 0.08), navy, 'gear')
        prim('cyl', hc + Vector((0, -0.11, 0.0)), (0.08, 0.07, 0.008), mat('brim', (PAL['void'], PAL['deep'], PAL['g0'])), 'gear', rot=(math.radians(-12), 0, 0))
        prim('sphere', hc + Vector((0, -0.075, 0.07)), (0.016, 0.01, 0.016), mat('badge', PAL['backup']), 'gear')
    elif g == 'medic':
        white = mat('medwhite', (tone(PAL['text'], 0.78), PAL['text'], '#fbf9f3'))
        red = mat('medred', PAL['medic'])
        prim('sphere', hc + Vector((0, 0.005, 0.02)), (0.122, 0.132, 0.1), mat('medhelm', (PAL['g0'], PAL['g1'], PAL['g2'])), 'gear')
        prim('cyl', hc + Vector((0, 0.005, -0.02)), (0.13, 0.14, 0.012), mat('medhelmrim', (PAL['void'], PAL['g0'], PAL['g1'])), 'gear')
        prim('cube', spine + Vector((0, 0.17, -0.05)), (0.3, 0.12, 0.3), white, 'gear')
        prim('cube', spine + Vector((0, 0.17, 0.103)), (0.05, 0.16, 0.012), red, 'gear')
        prim('cube', spine + Vector((0, 0.17, 0.107)), (0.16, 0.05, 0.012), red, 'gear')
    elif g == 'gunner':
        armor = mat('armor', (PAL['g0'], PAL['armor'], PAL['g2']))
        prim('sphere', hc, (0.12, 0.13, 0.11), armor, 'gear')
        prim('cube', hc + Vector((0, -0.11, 0.06)), (0.07, 0.03, 0.035), navy, 'gear')
        prim('cube', spine + Vector((0, -0.1, 0.0)), (0.3, 0.08, 0.32), armor, 'gear')
        for s in (lsh, rsh):
            prim('sphere', s + Vector((0.02 if s.x > 0 else -0.02, 0.01, 0.04)), (0.075, 0.085, 0.04), armor, 'gear')
        prim('cube', spine + Vector((0, 0.17, -0.05)), (0.28, 0.14, 0.3), mat('ammo', (PAL['wall'], PAL['metal'], tone(PAL['metal'], 1.25))), 'gear')
    elif g == 'electrician':
        prim('sphere', hc + Vector((0, 0, 0.04)), (0.12, 0.13, 0.1), mat('hardhat', PAL['backup']), 'gear')
        prim('cyl', hc + Vector((0, -0.01, 0.0)), (0.16, 0.17, 0.012), mat('hatbrim', tone(PAL['backup'], 0.85)), 'gear')
        prim('cyl', spine + Vector((0, 0.18, -0.02)), (0.13, 0.13, 0.14), mat('spool', PAL['warm']), 'gear', rot=(0, math.pi / 2, 0))
        prim('cyl', spine + Vector((0, 0.18, -0.02)), (0.05, 0.05, 0.2), mat('hub', PAL['wall']), 'gear', rot=(0, math.pi / 2, 0))
        for x in (-0.07, 0.07):
            prim('cube', spine + Vector((x, 0.1, 0.03)), (0.025, 0.02, 0.2), mat('reflect', PAL['flash'], emit=True), 'gear')
    elif g == 'hood':
        prim('sphere', hc + Vector((0, 0.025, 0.01)), (0.13, 0.15, 0.12), mat('hood', ('#121a28', '#26324a', '#3a4a66')), 'gear')
    elif g == 'beanie':
        prim('sphere', hc + Vector((0, 0.005, 0.035)), (0.113, 0.12, 0.085), mat('beanie', ACCENT['beanie']), 'gear')
        prim('cube', hc + Vector((0, -0.1, 0.05)), (0.04, 0.03, 0.025), mat('lamp', PAL['text']), 'gear')
        prim('cyl', hc + Vector((0, -0.118, 0.05)), (0.01, 0.01, 0.01), mat('lampglow', PAL['flash'], emit=True), 'gear', rot=(math.pi / 2, 0, 0))
    elif g == 'nvg':
        prim('sphere', hc + Vector((0, 0.005, 0.01)), (0.115, 0.125, 0.11), mat('balaclava', (PAL['i0'], PAL['i1'], PAL['i2'])), 'gear')
        prim('cube', hc + Vector((0, -0.1, 0.04)), (0.1, 0.05, 0.04), mat('nvgbody', PAL['i2']), 'gear')
        for x in (-0.03, 0.03):
            prim('cyl', hc + Vector((x, -0.135, 0.04)), (0.017, 0.017, 0.03), mat('nvglens', PAL['nv'], emit=True), 'gear', rot=(math.pi / 2, 0, 0))
        prim('cube', spine + Vector((0, 0.17, -0.06)), (0.36, 0.15, 0.2), mat('duffel', ACCENT['duffel']), 'gear')
    for o, _ in PROPS[n0:]:
        on_head = o.matrix_world.translation.z > lsh.z + 0.08
        if on_head:
            o.location = hc + (o.location - hc) * hk
            o.scale = (hk, hk, hk)
        attach(arm, o, 'Head' if on_head else 'Spine2')

    # ---- fists ----
    for side in ('Left', 'Right'):
        p = (wpos(arm, f'{side}Hand') + wpos(arm, f'{side}HandMiddle1')) / 2
        o = prim('sphere', p, (0.045, 0.05, 0.04), mat(f"{role}_hands", cfg['hands']), 'fist')
        attach(arm, o, f'{side}Hand')

    # ---- outlines ----
    if INK:
        for o in BODY:
            outline(o, 0.007, len(REGIONS), even=False)  # even offset spikes on the tucked fingers
        for o, _ in PROPS:
            outline(o, 0.006, 1)

    # ---- camera / render settings ----
    cam = bpy.data.cameras.new('cam')
    cam.type = 'ORTHO'
    co = bpy.data.objects.new('cam', cam)
    sc.collection.objects.link(co)
    sc.camera = co
    co.rotation_euler = (0, 0, math.pi)
    sc.render.engine = 'CYCLES'
    sc.cycles.samples, sc.cycles.device = 8, 'CPU'
    sc.cycles.transparent_max_bounces = 64  # hidden layers stack many transparent surfaces
    sc.view_settings.view_transform = 'Standard'
    sc.render.film_transparent = True

    region_mats = {r: mat(f"{role}_{r}", cfg[r]) for r in REGIONS}
    layered_scale = 2.0 if w == 'rifle' else 1.45
    PPU = 256 / 1.45  # every role and every sheet shares this pixels-per-metre

    def set_layer(layer, mode):
        for i, r in enumerate(REGIONS):
            vis = layer == 'full' or (layer == 'legs') == (r == 'pants')
            for o in BODY:
                o.data.materials[i] = region_mats[r] if vis else clear()
                # the fists carry their own outline; the tucked-away fingers would leave ink slivers
                o.data.materials[len(REGIONS) + i] = ink() if vis and r != 'hands' else clear()
        for o, tag in PROPS:
            show = layer != 'legs'
            if tag == 'hand':
                show = show and mode == 'aim'
            elif tag == 'holster':
                show = show and mode != 'aim'
            o.hide_render = not show

    os.makedirs(os.path.join(OUT, role), exist_ok=True)
    meta = {}
    for st in STATES:
        if ONLY and st['name'] not in ONLY:
            continue
        set_layer(st['layer'], st['mode'])
        clip = st.get('clip')
        sx, rx = (clip_src[clip][0], clip_src[clip][2]) if clip else (src, REF)
        act = clip_src[clip][1] if clip else acts[st['action']]
        r0, r1 = act.frame_range
        n = st['n']
        full = st['layer'] == 'full'
        if full:
            cam.ortho_scale = 2.9 if w == 'rifle' else 2.6
        else:
            cam.ortho_scale = layered_scale
        sc.render.resolution_x = sc.render.resolution_y = int(round(cam.ortho_scale * PPU))
        if st['mode'] == 'fall':
            co.location = (0, -0.8 * st['dir'], 6)
        elif st['mode'] == 'downed':
            co.location = (0, -0.85, 6)
        else:
            co.location = (0, -0.12, 6)
        for i in range(n):
            arm.rotation_euler = (0, 0, 0)
            arm.location = (0, 0, 0)
            sx.animation_data.action = act
            sc.frame_set(int(round(r0 + (r1 - r0) * i / (n - 1 if clip else n))))  # a clip plays once, so its last frame is the last sample
            retarget(sx, arm, rx)
            if st.get('blend'):
                b = st['blend']
                for pb in arm.pose.bones:
                    pb.rotation_quaternion = idle_rot[pb.name].slerp(pb.rotation_quaternion, b)
                    pb.location = idle_loc[pb.name].lerp(pb.location, b)
            fingers_to_fists(arm)
            mode = st['mode']
            if mode in ('downed', 'fall'):
                p = 1.0 if mode == 'downed' else i / (n - 1)
                dr = st.get('dir', 1)
                if mode == 'fall':
                    if p < 0.7:
                        ang = 90 * (p / 0.7) ** 2
                    else:
                        ang = 90 - 7 * math.sin(math.pi * (p - 0.7) / 0.3)
                else:
                    ang = 90
                arm.rotation_euler = (math.radians(ang) * dr, 0, 0)
                bpy.context.view_layer.update()
                Ls, Rs = wpos(arm, 'LeftArm'), wpos(arm, 'RightArm')
                fwd = Vector((0, -dr, 0))
                if dr > 0:   # face down: one arm reaching past the head, one by the hip
                    goal = {'Left': Ls + fwd * 0.42 + Vector((0.12, 0, 0)), 'Right': Rs - fwd * 0.3 + Vector((-0.18, 0, 0))}
                    pole = lambda s: (s * 1.0, 0.0, 1.0)
                else:        # face up: arms flung out
                    goal = {'Left': Ls + Vector((0.42, 0, 0)) + fwd * 0.15, 'Right': Rs + Vector((-0.4, 0, 0)) - fwd * 0.1}
                    pole = lambda s: (s * 0.3, 0.0, 1.0)
                w8 = 1.0 if mode == 'downed' else smooth((p - 0.25) / 0.6)
                if w8 > 0:
                    for k in goal:
                        goal[k] = wpos(arm, f'{k}Hand').lerp(Vector((goal[k].x, goal[k].y, 0.06)), w8)
                    pose_arms(arm, goal, pole, lambda s: tuple(fwd * 0.1))
            else:
                recenter(arm)
                if st.get('yaw_offset'):  # turn the whole body about the hips, so a clip that starts a few degrees off square starts square
                    arm.rotation_euler = (0, 0, math.radians(st['yaw_offset']))
                    bpy.context.view_layer.update()
                    recenter(arm)
                dl =wpos(arm, 'Spine2') - spine_ref
                if mode == 'aim':
                    pose_arms(arm, {k: v + dl for k, v in aim_t.items()}, aim_pole, aim_dir)
                    for o, loc in hand_items:
                        o.location = loc + dl
                elif mode == 'interact':
                    t = 2 * math.pi * i / n
                    tg = {'Left': Vector((0.1, -0.27 + 0.02 * math.sin(t), shz - 0.38 + 0.02 * math.cos(t))) + dl,
                          'Right': Vector((-0.1, -0.27 - 0.02 * math.sin(t), shz - 0.38 - 0.02 * math.cos(t))) + dl}
                    pose_arms(arm, tg, lambda s: (s * 1.0, 0.2, -0.8), lambda s: (0.0, -0.1, -0.03))
            bpy.context.view_layer.update()
            sc.render.filepath = os.path.join(OUT, role, f"{st['name']}_{i:02d}.png")
            bpy.ops.render.render(write_still=True)
        # where the character's position sits inside this sprite (pixels from top-left)
        res = sc.render.resolution_x
        ppu = res / cam.ortho_scale
        meta[st['name']] = dict(frames=n, size=res, pivot=[res / 2, res / 2 - co.location.y * ppu], px_per_m=round(ppu, 2))
        print('done', role, st['name'], flush=True)
    import json
    json.dump(meta, open(os.path.join(OUT, role, 'sprites.json'), 'w'), indent=1)


if __name__ == '__main__':
    for r in (ROLES if ROLE_ARG == 'all' else ROLE_ARG.split(',')):
        build(r)

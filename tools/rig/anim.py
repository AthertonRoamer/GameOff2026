"""Night Shift sprite renderer: Mixamo X Bot dressed per role, Palette A, cel-shaded with ink outlines.

Renders three kinds of sprite, all top-down with the character facing up:
  legs_*   bottom layer, rotates to movement direction
  torso_*  top layer, rotates to aim direction (same camera as legs, so they stack exactly)
  death_*  full-body sprite of a fall, which replaces both layers

Usage:  python3 anim.py -- <role|all> [outdir] [state,state,...]
Edit PAL or ROLES and re-run to change colours or gear; every frame re-renders in the new look.
"""
import bpy, math, os, sys
from mathutils import Matrix, Quaternion, Vector

args = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
ROLE_ARG = args[0] if args else 'all'
OUT = args[1] if len(args) > 1 else 'anim'
ONLY = set(args[2].split(',')) if len(args) > 2 else None
ASSETS = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'assets')  # the models and the Mixamo clips
SMOOTH = os.environ.get('SHADE') == 'smooth'   # soft shading for the pixel-art pass
SHOULDERS = os.environ.get('SHOULDERS') == '1'  # no pictures: only write where the shoulders are in every frame (shoulders.json), for the game's shoulder lamp
SHOULDER_POS = {}
HEAD_POS = {}
INK = os.environ.get('INK', '1') != '0'         # 3D ink hull; the pixel pass draws its own outline
FRONT = os.environ.get('FRONT') == '1'          # not the sprite sheets: whole-body stills seen from the front (front_idle, front_aim), for the role reveal. Use with the state names as the third argument
FRONT_FLAT = 0.75                               # in those stills the helmets, hoods and hats are this much as tall (a little lower: from the front they looked stretched)
FRONT_HAT = 0.78                                # and this much as big (they were sized for the view from above)
FRONT_HAT_BY_GEAR = dict(gunner=0.71, hood=0.71, electrician=0.71, nvg=0.71) #the helmets and hoods are narrower still, and sit a little lower on the head
FRONT_HAT_DROP = 0.012
FRONT_SMILE = -0.3                             # the head's mouthSmile shape key: below 0 is the corners of the mouth down, a stern calm face

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

# The states rendered by hand-made recipes, named as the sheets are in the game (game/player/skin/<role>/): <layer>_<what>. The gait cycles are Mixamo clips from the
# locomotion pack, all timed so the lead foot comes down at the same point of the cycle, so any two of them can be switched or blended at the same frame.
STATES = [
    dict(name='legs_idle', layer='legs', action='idle', n=8, mode='free'),
    dict(name='torso_idle', layer='torso', action='idle', n=8, mode='holster'),
    dict(name='torso_idle_aim', layer='torso', action='idle', n=8, mode='aim'),
    dict(name='torso_draw', layer='torso', action='idle', n=8, mode='draw'),
    # a turn on the spot, from a Mixamo clip (Right Turn.fbx, which is no longer in clips/): a right turn of about 96 degrees that starts and ends in the standing
    # stance, with the body's yaw baked into the frames. The game leaves the legs node alone while the sheet plays, turns it by 96 degrees at the end, and mirrors the
    # sheet for a left turn.
    dict(name='legs_turn', layer='legs', action='turn', n=16, mode='free', clip='Right Turn.fbx', yaw_offset=-6),
    dict(name='legs_walk', layer='legs', action='pack_walk', n=12, mode='free', clip='locomotion_pack/walking.fbx', loop=True, yaw_offset=7, blend=0.6),
    dict(name='legs_run', layer='legs', action='pack_run', n=12, mode='free', clip='locomotion_pack/running.fbx', loop=True, yaw_offset=5),
    dict(name='torso_walk', layer='torso', action='pack_walk', n=12, mode='holster', clip='locomotion_pack/walking.fbx', loop=True, yaw_offset=7, blend=0.6),
    dict(name='torso_run', layer='torso', action='pack_run', n=12, mode='holster', clip='locomotion_pack/running.fbx', loop=True, yaw_offset=5),
    # FRONT=1 only: the whole body seen from the front (the camera is moved in build), standing relaxed, and with the gun up turned a little towards the camera
    dict(name='front_idle', layer='full', action='idle', n=1, mode='holster', front=True),
    dict(name='front_aim', layer='full', action='idle', n=1, mode='aim', front=True, yaw_offset=-58),
    dict(name='front_hero', layer='full', action='idle', n=1, mode='hero', front=True),   # each role doing its job (hero_pose); keep it last, it adds the things they hold
]

# ------------------------------------------------------------------ the locomotion kit: clips blended on the skeleton
# Every gait clip is sampled so its left foot is at its highest (mid swing) at LIFT of the cycle, and clips can be blended pose by pose ('mix'
# states): the in-between cycles and the starts and stops are then drawn from real blended poses, not faded in the game.
# lift: where in the clip's own cycle its left foot is highest (measured with clip_lift.py). Lift timing is the same whichever way the clip travels, unlike which foot is furthest ahead. yaw_legs / yaw_torso: degrees to turn the
# body about the hips so the sheet starts square (legs: the hips and travel; torso: the shoulders). damp: pull the pose towards the idle pose (a gentler stride).
LIFT = 0.90
CLIPSPEC = {
    'walk': dict(clip='locomotion_pack/walking.fbx', lift=0.90, yaw_legs=7, yaw_torso=7, damp=0.6),
    'run': dict(clip='locomotion_pack/running.fbx', lift=0.90, yaw_legs=5, yaw_torso=5),
    'strafe': dict(clip='locomotion_pack/right strafe walking.fbx', lift=0.90, yaw_legs=0, yaw_torso=6), #yaw_torso 47 would square the shoulders, but the head looks 41 degrees off them: 6 squares the head (clip_head.py)
    'strafe_run': dict(clip='locomotion_pack/right strafe.fbx', lift=0.95, yaw_legs=0, yaw_torso=3), #53 would square the shoulders; the head looks 50 degrees off them
    # the legs for moving sideways: a shuffle made with IK (see shuffle_pose), not a clip: the feet slide in turn on their own side of the body
    'shuffle': dict(shuffle=dict(c=0.20, a=0.12, lift=0.05)),
    'shuffle_run': dict(shuffle=dict(c=0.19, a=0.17, lift=0.09)),
    # the same two strafes as the mirror image, timed half a cycle later: what the sheet looks like when the game flips it for the other side (a mirror lifts the other foot).
    # Used to blend one side into the other (see _flip)
    'strafe_l': dict(clip='locomotion_pack/right strafe walking.fbx', lift=0.40, yaw_legs=0, yaw_torso=6, mirror=True),
    'strafe_run_l': dict(clip='locomotion_pack/right strafe.fbx', lift=0.45, yaw_legs=0, yaw_torso=3, mirror=True),
    'back': dict(clip='Walking Backwards (1).fbx', lift=0.07, yaw_legs=3, yaw_torso=3),
    # the death clips (one shot, not a cycle: 'once' samples them from their first frame to their last, without the footfall alignment the cycles use)
    'death_front': dict(clip='Death From The Front.fbx', lift=0.0, yaw_legs=55, yaw_torso=55, once=True), #the whole clip faces 55 degrees off forward
    'death_right': dict(clip='Death From Right.fbx', lift=0.0, yaw_legs=55, yaw_torso=55, once=True), #the whole clip faces 55 degrees off forward
    'death_back': dict(clip='Death From The Back.fbx', lift=0.0, yaw_legs=55, yaw_torso=55, once=True), #the whole clip faces 55 degrees off forward
    # a backwards run: there is no such clip, so it is the backwards walk with its swing pushed beyond the original (damp above 1 goes past the clip's own
    # pose, away from the idle pose): longer strides and bigger arms, played at the run's pace
    'back_run': dict(clip='Walking Backwards (1).fbx', lift=0.07, yaw_legs=3, yaw_torso=3, damp=1.6),
    # typing at a console: a 16 second clip of a seated typist. upper: only the spine, head and arms are taken (the seated hips and legs would drag the standing body
    # down), so the legs stay as they stand. window: the cycle is this stretch of the clip (start, length, as fractions of it), its last part fading into the stretch
    # before the start (xfade, as a fraction of the cycle) so the loop joins up
    'typing': dict(clip='Typing.fbx', lift=0.90, yaw_legs=0, yaw_torso=0, upper=True, window=(0.30, 0.09), xfade=0.35),
    # reloading a rifle (3.3 s, standing): the left hand goes to the hip for a magazine and brings it up to the rifle. upper: the legs stay as they stand. once: played from the
    # start to `end` of the clip (its last part is only the aim again). 'aim' is the aimed pose itself (the gun up, see build): the reload starts and ends on it
    'reload': dict(clip='Reloading.fbx', lift=0.0, yaw_legs=0, yaw_torso=0, upper=True, once=True),
    'aim': dict(aim=True),
}
RELOAD_END = 0.80  #how much of the clip the reload uses
RELOAD_FRAMES = 20
RELOAD_LEAD = 3     #frames at either end that blend between the aimed pose and the clip, so the sheet starts and ends exactly on the aim

UPPER_BONES = ('Spine', 'Neck', 'Head', 'LeftShoulder', 'LeftArm', 'LeftForeArm', 'LeftHand', 'RightShoulder', 'RightArm', 'RightForeArm', 'RightHand')  # (by prefix: Spine1, the fingers)


def _is_upper(bone):
    return bone.replace('mixamorig:', '').startswith(UPPER_BONES)


def _cycle(name, layer, mode, parts, **extra):
    """A looping 12 frame cycle that is a blend of clips: parts = [(clip name, weight)]."""
    return dict(name=name, layer=layer, action='mix', n=12, mode=mode, loop=True, mix=lambda i, n, parts=parts: [(c, i / n, w) for c, w in parts], **extra)


def _flip(name, comp, quarter, n=6):
    """The upper body going from a sideways cycle to its mirror image (a strafe to the left after one to the right), starting from the sheet frame `quarter`*3
    of 12. Frame i is a blend of the right hand cycle and its mirror image, one cycle frame further on each time, ending wholly on the mirror image: the
    torso sways across instead of jumping to the other side. The mirror image is the cycle that the game shows once it flips the sheet."""
    def sample(i, n, comp=comp, quarter=quarter):
        u = (quarter * 3 + 1 + i) / 12.0
        s = smooth((i + 1) / float(n))
        return [(comp, u, 1.0 - s), (comp + '_l', u, s)]
    return dict(name=name, layer='torso', action='mix', n=n, mode='holster', loop=False, mix=sample)


TRANSITION_GAITS = {'walk': 'walk', 'run': 'run', 'side_walk': 'strafe', 'side_run': 'strafe_run', 'back': 'back', 'back_run': 'back_run', 'typing': 'typing'}  # the game's gait -> the clip it is made from (typing is the upper body only: see _typing)
TRANSITION_LEGS = {'side_walk': 'shuffle', 'side_run': 'shuffle_run'}  # the legs move sideways as a shuffle (shuffle_pose), not with the strafe clips
# which gaits the game goes between directly (both ways): speed changes and direction changes
TRANSITION_EDGES = [('walk', 'run'), ('side_walk', 'side_run'), ('back', 'back_run'), ('walk', 'side_walk'), ('run', 'side_run'), ('back', 'side_walk'),
    ('back_run', 'side_run'), ('walk', 'back'), ('run', 'back_run')]


def _transition(layer, a, b, f0, n=6):
    """From gait a to gait b (either may be 'idle'), starting where a is at sheet frame f0 of 12: frame i blends a and b one cycle frame further on each time,
    and the last is wholly b at frame f0 + n (the game carries on from the next one). From idle, b starts at its first frame. Named <layer>_tr_<a>_<b>_<f0>."""
    def sample(i, n, a=a, b=b, f0=f0):
        u = (f0 + 1 + i) / 12.0
        s = smooth((i + 1) / float(n))
        comp = lambda g: TRANSITION_LEGS.get(g, TRANSITION_GAITS[g]) if layer == 'legs' else TRANSITION_GAITS[g]
        parts = [('idle', 0.0, 1.0 - s) if a == 'idle' else (comp(a), u, 1.0 - s)]
        parts.append(('idle', 0.0, s) if b == 'idle' else (comp(b), u, s))
        return parts
    wide = any(g in ('side_walk', 'side_run', 'back_run') for g in (a, b)) and layer == 'legs'
    return dict(name=f'{layer}_tr_{a}_{b}_{f0}', layer=layer, action='mix', n=n, mode='free' if layer == 'legs' else 'holster', loop=False, mix=sample, **(dict(ortho=2.0) if wide else {}))


def _transitions():
    """Between idle and every gait (the upper body and the legs), and between the gaits next to each other (the upper body only: the legs' sheets are turned
    in the game to run along the movement, so they are not blended). Starting from idle is one sheet; from a gait, from two points of the stride."""
    states = []
    for layer in ('torso', 'legs'):
        for gait in TRANSITION_GAITS:
            if gait == 'typing':
                continue
            states.append(_transition(layer, 'idle', gait, 0))
            for f0 in (0, 6):
                states.append(_transition(layer, gait, 'idle', f0))
    for a, b in TRANSITION_EDGES:
        for f0 in (0, 6):
            states.append(_transition('torso', a, b, f0))
            states.append(_transition('torso', b, a, f0))
    return states


def _death(name, parts, n=18, lead=3, u_end=0.8, ortho=3.8):
    """A death from a clip (or a blend of clips), full body, seen from above. It starts on the idle pose and blends into the clip over the first `lead` frames
    (so it starts exactly where the standing character is), then plays the clip through to its last frame, where the body lies. The clip's own movement is kept (keep_travel): the body falls away from the spot the feet stood on, which is the sprite's pivot."""
    def sample(i, n, parts=parts, lead=lead):
        u = i / (n - 1) * u_end #the clips are 3 seconds, most of it the body lying still: only the fall and the settling are used
        idle_weight = max(0.0, 1.0 - i / float(lead)) if lead > 0 else 0.0
        out = [('idle', 0.0, idle_weight)] if idle_weight > 0.0 else []
        out += [(c, u, w * (1.0 - idle_weight)) for c, w in parts]
        return out
    return dict(name=name, layer='full', action='mix', n=n, mode='holster', loop=False, mix=sample, ortho=ortho, keep_travel=True) #ortho: the width of the frame in metres; the body travels up to a metre and a half from the spot


def _gaits():
    """The rest of the gait cycles, blends of the clips above on the skeleton (the upper body at the same frames as the legs, so arms and legs swing together)."""
    wide = dict(ortho=2.0) #the sideways steps and the backwards run reach nearly a metre, wider than the 1.45 m frame
    states = [
        _cycle('legs_side_walk', 'legs', 'free', [('shuffle', 1.0)], **wide), #sideways, a step to the right (the game mirrors it for the left)
        _cycle('legs_side_run', 'legs', 'free', [('shuffle_run', 1.0)], **wide),
        _cycle('legs_back', 'legs', 'free', [('back', 1.0)]),
        _cycle('legs_back_run', 'legs', 'free', [('back_run', 1.0)], **wide),
        _cycle('torso_side_walk', 'torso', 'holster', [('strafe', 1.0)]),
        _cycle('torso_side_run', 'torso', 'holster', [('strafe_run', 1.0)]),
        _cycle('torso_back', 'torso', 'holster', [('back', 1.0)]),
        _cycle('torso_back_run', 'torso', 'holster', [('back_run', 1.0)]),
    ]
    for kind, comp in (('walk', 'strafe'), ('run', 'strafe_run')):  # from one side to the other, from four points of the stride
        for quarter in range(4):
            states.append(_flip(f'torso_flip_{kind}_{quarter}', comp, quarter))
    return states


def _deaths():
    """A death for each direction the shot came from, relative to the way the character faces: from the front, from the right (the clip's own side; the game
    mirrors it for the left), from the back, and between them blends of the two clips either side."""
    states = []
    for angle_name, parts in (('front', [('death_front', 1.0)]), ('front_right', [('death_front', 1.0), ('death_right', 1.0)]), ('right', [('death_right', 1.0)]),
            ('back_right', [('death_right', 1.0), ('death_back', 1.0)]), ('back', [('death_back', 1.0)])):
        states.append(_death('death_%s' % angle_name, parts, ortho=4.8 if angle_name == 'back' else 3.8)) #the back death travels furthest
    return states


IDLE_SPINE =Vector((0.0, 0.0, 1.323))


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


def slab(points, y, depth, m, tag='gear'):
    """a flat piece cut to an outline: points are (x, z) in the world, the front face is at y and it is `depth` thick towards the back. Used for the vest, which is not a block"""
    import bmesh
    n = len(points)
    verts = [(x, y, z) for x, z in points] + [(x, y + depth, z) for x, z in points]
    faces = [list(range(n)), list(range(2 * n - 1, n - 1, -1))] + [[i, (i + 1) % n, n + (i + 1) % n, n + i] for i in range(n)]
    me = bpy.data.meshes.new('slab')
    me.from_pydata(verts, [], faces)
    me.update()
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new('slab', me)
    bpy.context.scene.collection.objects.link(o)
    me.materials.append(m)
    me.materials.append(ink())
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


def pose_legs(arm, targets, knee_dir):
    """Two-bone solve per leg: the foot goes to targets[side] (world), the knee bends towards knee_dir, and the foot points the way the character faces (-y)."""
    for side, T in targets.items():
        S = wpos(arm, f'{side}UpLeg')
        E0, F0 = wpos(arm, f'{side}Leg'), wpos(arm, f'{side}Foot')
        L1, L2 = (E0 - S).length, (F0 - E0).length
        T = Vector(T)
        d = min(max((T - S).length, abs(L1 - L2) + 1e-3), (L1 + L2) * 0.999)
        dr = (T - S).normalized()
        T = S + dr * d
        a = (L1 * L1 - L2 * L2 + d * d) / (2 * d)
        h = math.sqrt(max(L1 * L1 - a * a, 0))
        P = Vector(knee_dir)
        pp = (P - dr * P.dot(dr)).normalized()
        E = S + dr * a + pp * h
        aim_bone(arm, f'{side}UpLeg', f'{side}Leg', E)
        aim_bone(arm, f'{side}Leg', f'{side}Foot', T)
        aim_bone(arm, f'{side}Foot', f'{side}ToeBase', T + Vector((0.0, -0.14, -0.03)))


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


_SIDE = Matrix(((-1.0, 0.0, 0.0), (0.0, 1.0, 0.0), (0.0, 0.0, 1.0))) #reflects across the character's centre line (the character faces along y)


def _mirrored(name):
    if 'Left' in name:
        return name.replace('Left', 'Right')
    if 'Right' in name:
        return name.replace('Right', 'Left')
    return name


def _reflect(q):
    """A world space rotation as it looks in a mirror held along the character's centre line."""
    return (_SIDE @ q.to_matrix() @ _SIDE).to_quaternion()


def retarget(src, tgt, ref, mirror=False):
    """Poses tgt like src. mirror: as src's mirror image (its left side doing what its right side does, and the other way round)."""
    bpy.context.view_layer.update()
    Ms, Mt = src.matrix_world, tgt.matrix_world
    sh_rest = (Ms @ src.data.bones['mixamorig:Hips'].matrix_local).to_translation()
    sh_pose = (Ms @ src.pose.bones['mixamorig:Hips'].matrix).to_translation()
    if mirror:
        sh_pose = sh_rest + Vector((-(sh_pose.x - sh_rest.x), sh_pose.y - sh_rest.y, sh_pose.z - sh_rest.z))
    th_rest = (Mt @ tgt.data.bones['mixamorig:Hips'].matrix_local).to_translation()
    ratio = th_rest.z / sh_rest.z
    scl = Mt.to_scale()
    S = Matrix.Diagonal((scl.x, scl.y, scl.z, 1))
    pose = {}
    for b in tgt.data.bones:  # parents come before children
        sname = _mirrored(b.name) if mirror else b.name
        if sname in src.pose.bones:
            sb = src.data.bones[sname]
            delta = (Ms @ src.pose.bones[sname].matrix).to_quaternion() @ (Ms @ sb.matrix_local).to_quaternion().inverted()
            if mirror:
                delta = _reflect(delta)
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


def _toward(a, b, f):
    """The rotation f of the way from a to b; past b (f above 1) it carries on the same way, so the swing grows."""
    if f <= 1.0:
        return a.slerp(b, f)
    delta = a.inverted() @ b
    axis, angle = delta.to_axis_angle()
    return a @ Quaternion(axis, angle * f)


def _typing():
    """Typing at a console (the upper body only: the legs keep their idle sheet): a loop, and the blends into it from idle and back out of it from two points of
    the loop. Played while a player uses a control panel."""
    return [_cycle('torso_typing', 'torso', 'holster', [('typing', 1.0)]), _transition('torso', 'idle', 'typing', 0), _transition('torso', 'typing', 'idle', 0),
        _transition('torso', 'typing', 'idle', 6)]


def _reload():
    """Reloading with the gun up, the upper body only: it starts and ends on the aimed pose (torso_idle_aim) and plays the clip between. The game plays the sheet at
    the speed that makes it last as long as the reload does. The rifle follows the right hand as the clip moves it; for a pistol the hands are worked out again in build()
    from the clip's (see reload_arms)."""
    def sample(i, n):
        u = i / (n - 1.0) * RELOAD_END
        edge = min(i, n - 1 - i)
        aim = smooth(1.0 - edge / float(RELOAD_LEAD)) if edge < RELOAD_LEAD else 0.0
        return [('aim', 0.0, aim), ('reload', u, 1.0 - aim)] if aim > 0.0 else [('reload', u, 1.0)]
    return [dict(name='torso_reload', layer='torso', action='mix', n=RELOAD_FRAMES, mode='reload', loop=False, mix=sample)]


STATES += _transitions()
STATES += _gaits() + _deaths() + _typing() + _reload() #(after smooth, which the transition states use when they are rendered)


# ------------------------------------------------------------------ role gear
# What each role wears, built from primitives (cubes, spheres, cylinders) and attached to the head or the chest bones by build(). `c` holds the head centre (hc), the
# chest (spine), the hips, both shoulders and k, the role's build (1.2 for the broad gunner): what sits on the body is sized by k, what sits on the head is scaled with the head.
ACCENT.update(olive='#4a5a35', olive_dark='#2f3a22', leather='#6b4f33', maroon_dark='#4f2530')


def V(*a):
    return Vector(a)


def side(s):
    return 1.0 if s.x > 0 else -1.0


def strap(a, b, width, m):
    """a flat strap lying from point a to point b"""
    d = b - a
    o = prim('cube', (a + b) / 2, (width, d.length, 0.012), m, 'gear')
    o.rotation_euler = (0, 0, math.atan2(-d.x, d.y))
    return o


def rod(a, b, radius, m, tag='gear'):
    """a thin cylinder from point a to point b"""
    d = b - a
    return prim('cyl', (a + b) / 2, (radius, radius, d.length), m, tag, rot=(math.pi / 2, 0, math.atan2(-d.x, d.y)))


def helmet(hc, skull, band, rx, ry, rz, skirt=0.075, peak=0.0):
    """a simple helmet, like a half helmet: a low dome on straight sides with a flared lip all round (and, with peak, a short peak in front). It reads the same from above
    and lying on its side, which a plain sphere does not (it looks like a mushroom)"""
    prim('sphere', hc + V(0, 0.01, 0.025), (rx, ry, rz), skull, 'gear')
    prim('cyl', hc + V(0, 0.01, -0.012), (rx * 0.99, ry * 0.99, skirt), skull, 'gear')
    prim('cyl', hc + V(0, 0.01, -0.012 - skirt / 2.0 - 0.0005), (rx * 1.06, ry * 1.06, 0.012), band, 'gear') #(the lip is on the bottom edge of the sides, however tall they are)
    if peak:
        prim('sphere', hc + V(0, 0.01 - ry, -0.046), (rx * 0.75, peak, 0.01), band, 'gear', rot=(math.radians(-6), 0, 0))


def chin_strap(hc, rx, m):
    """a chin strap: a strap down each side of the head from the helmet's lip, and a cup under the chin (tagged 'head' so they turn with the head, below the shoulders' height too)"""
    if FRONT: #seen from the front the straps and the cup run across the face
        return
    for x in (-1.0, 1.0):
        rod(hc + V(x * rx * 0.97, 0.01, -0.05), hc + V(x * 0.058, -0.045, -0.118), 0.008, m, 'head')
    prim('cube', hc + V(0, -0.05, -0.124), (0.116, 0.034, 0.014), m, 'head')


def gear_cap(c):  # the guard: as it always was
    hc = c['hc']
    prim('sphere', hc + Vector((0, 0.01, 0.01)), (0.108, 0.115, 0.08), mat('navydark', (PAL['void'], PAL['g0'], PAL['g1'])), 'gear')
    prim('cyl', hc + Vector((0, -0.11, 0.0)), (0.08, 0.07, 0.008), mat('brim', (PAL['void'], PAL['deep'], PAL['g0'])), 'gear', rot=(math.radians(-12), 0, 0))
    prim('sphere', hc + Vector((0, -0.075, 0.07)), (0.016, 0.01, 0.016), mat('badge', PAL['backup']), 'gear')


def gear_medic(c):
    hc, spine, lsh = c['hc'], c['spine'], c['lsh']
    white = mat('medwhite', (tone(PAL['text'], 0.78), PAL['text'], '#fbf9f3'))
    grey = mat('medgrey', (tone(PAL['text'], 0.55), tone(PAL['text'], 0.72), tone(PAL['text'], 0.85)))
    red = mat('medred', PAL['medic'])
    gear_cap(c)                                                                                           # the guard's cap
    if not FRONT: #(from the front it floats off the shoulder: the chest badge says medic)
        prim('cube', lsh + V(0.03 * side(lsh), 0.0, 0.058), (0.05, 0.05, 0.008), white, 'gear')            # a shoulder patch
        prim('cube', lsh + V(0.03 * side(lsh), 0.0, 0.064), (0.028, 0.009, 0.006), red, 'gear')
        prim('cube', lsh + V(0.03 * side(lsh), 0.0, 0.064), (0.009, 0.028, 0.006), red, 'gear')
    prim('cube', spine + V(0, 0.19, -0.05), (0.3, 0.16, 0.3), white, 'gear')                              # the medkit pack
    prim('cube', spine + V(0, 0.208, 0.103), (0.036, 0.1, 0.012), red, 'gear')                            # the cross, in the middle of the part of the lid that shows behind him
    prim('cube', spine + V(0, 0.208, 0.107), (0.1, 0.036, 0.012), red, 'gear')
    prim('cube', spine + V(0, 0.14, 0.1), (0.3, 0.01, 0.01), grey, 'gear')                                # a seam across its lid
    if FRONT: #a little badge on the chest, seen from the front: a white disc with the red cross
        badge = spine + V(0.085, -0.152, 0.035)
        prim('cyl', badge, (0.034, 0.034, 0.008), white, 'gear', rot=(math.pi / 2, 0, 0))
        prim('cube', badge + V(0, -0.006, 0), (0.038, 0.006, 0.011), red, 'gear')
        prim('cube', badge + V(0, -0.006, 0), (0.011, 0.006, 0.038), red, 'gear')


def gear_gunner(c):
    hc, spine, lsh, rsh, k = c['hc'], c['spine'], c['lsh'], c['rsh'], c['k']
    armor = mat('armor', (PAL['g0'], PAL['armor'], PAL['g2']))
    armor_hi = mat('armorhi', (PAL['g1'], PAL['g2'], tone(PAL['g2'], 1.3)))
    navy = mat('navydark', (PAL['void'], PAL['g0'], PAL['g1']))
    olive = mat('olive', (ACCENT['olive_dark'], ACCENT['olive'], tone(ACCENT['olive'], 1.35)))
    flat = FRONT_FLAT if FRONT else 1.0 #(from the front: a lower helmet, a little wider so it covers the forehead, and no mount on its front)
    helmet(hc, armor, navy, 0.112 if FRONT else 0.104, 0.128 if FRONT else 0.113, 0.07 * flat, skirt=0.07 * flat)                    # the helmet: a low dome on straight sides with a flared lip all round (no bill)
    for x in (-0.027, 0.027):                                                                              # two rails along the top
        prim('cube', hc + V(x, 0.01, 0.025 + 0.07 * flat - 0.003), (0.012, 0.14, 0.012), navy, 'gear')
    if not FRONT:
        prim('cube', hc + V(0, -0.1, 0.04), (0.07, 0.03, 0.036), navy, 'gear')                             # the night vision mount, on the front of the dome
    for x in (() if FRONT else (-1.0, 1.0)):                                                              # a rivet on each side
        prim('sphere', hc + V(0.104 * x, 0.01, 0.02), (0.011, 0.011, 0.011), armor_hi, 'gear')
    chin_strap(hc, 0.104, navy)                                                                            # and a chin strap
    prim('cube', spine + V(0, -0.03, 0.04) * k, V(0.34, 0.16, 0.12) * k, armor, 'gear')                    # the plate carrier over the chest
    prim('cube', spine + V(0, -0.05, 0.1) * k, V(0.22, 0.09, 0.02) * k, armor_hi, 'gear')                  # and its plate
    for x in (-0.07, 0.0, 0.07):                                                                           # a row of pouches below it
        if not FRONT: #(from the front they are a row of black blocks, which read as a mess)
            prim('cube', spine + V(x, -0.115, 0.07) * k, V(0.055, 0.04, 0.04) * k, navy, 'gear')
    if FRONT: #a plate carrier vest seen from the front: shoulder straps with a lighter edge, a rounded chest panel with a raised plate, side panels that wrap round the ribs, a waist band with two magazine pouches
        for sx in (-1.0, 1.0):
            a = spine + V(0.075 * sx, -0.185, 0.085) * k
            b = spine + V(0.135 * sx, -0.165, 0.155) * k
            d = b - a
            for width, m, dy in ((0.05, navy, 0.0), (0.012, armor_hi, -0.006)):
                o = prim('cube', (a + b) / 2 + V(0, dy, 0), (width * k, 0.016, math.hypot(d.x, d.z)), m, 'gear')
                o.rotation_euler = (0, math.atan2(d.x, d.z), 0)
        def pts(*xz): #(a shape in metres from the middle of the chest: x across, z up, as the vest is cut)
            return [(spine.x + x * k, spine.z + z * k) for x, z in xz]
        slab(pts((-0.10, 0.105), (0.10, 0.105), (0.145, 0.03), (0.15, -0.07), (0.125, -0.125), (-0.125, -0.125), (-0.15, -0.07), (-0.145, 0.03)), spine.y - 0.185 * k, 0.045, armor, 'gear')   # the vest: narrow at the shoulders, wide at the ribs, cut in at the waist
        slab(pts((-0.075, 0.085), (0.075, 0.085), (0.095, 0.02), (0.095, -0.04), (-0.095, -0.04), (-0.095, 0.02)), spine.y - 0.1875 * k - 0.012, 0.012, armor_hi, 'gear')          # the front plate in it
        slab(pts((-0.14, -0.055), (0.14, -0.055), (0.145, -0.085), (-0.145, -0.085)), spine.y - 0.1875 * k - 0.006, 0.01, navy, 'gear')                                           # the cummerbund across the ribs
        for x in (-0.055, 0.055):
            slab(pts((x - 0.032, -0.095), (x + 0.032, -0.095), (x + 0.032, -0.138), (x - 0.032, -0.138)), spine.y - 0.1875 * k - 0.014, 0.014, armor_hi, 'gear')                    # a magazine pouch each side
    for x in (-1.0, 1.0):                                                                                  # side panels (the cummerbund)
        prim('cube', spine + V(0.19 * x, 0.0, 0.05) * k, V(0.04, 0.17, 0.07) * k, navy, 'gear')
    prim('sphere', spine + V(0, 0.07, 0.07) * k, V(0.13, 0.06, 0.05) * k, armor_hi, 'gear')                # a neck guard behind the helmet
    arm = c['arm']
    for sd, s in (('Left', lsh), ('Right', rsh)):                                                          # shoulder armour: two plates riding on each upper arm, just out from the joint
        p = s + (wpos(arm, f'{sd}ForeArm') - s) * 0.2
        for i in range(3):                                                                                 # three overlapping plates, each trimmed with a dark edge
            z = (0.046 + 0.017 * i + (0.014 if FRONT else 0.0)) * k #(from the front the pads sit a little higher, so the jacket's shoulder does not come through them)
            q = p + (wpos(arm, f'{sd}ForeArm') - s) * 0.07 * i
            o = prim('sphere', q + V(0, -0.04 if FRONT else 0.0, z), V(0.08 - 0.012 * i, 0.092 - 0.013 * i, 0.028 * (0.6 if FRONT else 1.0)) * k, armor_hi if i == 2 else armor, 'bone')
            attach(arm, o, f'{sd}Arm')
        strap(s + V(0, 0, 0.1 * k), spine + V(0, 0.08, 0.06) * k, 0.045 * k, navy)                          # the carrier's shoulder strap, over to the back panel
    prim('cube', spine + V(0, 0.09, 0.05) * k, V(0.3, 0.07, 0.1) * k, navy, 'gear')                         # the carrier's back panel
    prim('cube', spine + V(0, 0.2, -0.05) * k, V(0.3, 0.15, 0.26) * k, olive, 'gear')                      # the ammo box
    prim('cube', spine + V(0, 0.2, 0.09) * k, V(0.3, 0.012, 0.01) * k, navy, 'gear')                       # its lid seam


def gear_electrician(c):
    hc, spine, lsh, rsh = c['hc'], c['spine'], c['lsh'], c['rsh']
    hat = mat('hardhat', PAL['backup'])
    stripe = mat('reflect', PAL['flash'], emit=True)
    if FRONT: #from the front: the shade's hat in yellow (a flat dome on straight sides, no brim)
        yellow = mat('hardhat_front', (tone(PAL['backup'], 0.7), PAL['backup'], tone(PAL['backup'], 1.2)))
        yellow_seam = mat('hardhat_seam', (tone(PAL['backup'], 0.55), tone(PAL['backup'], 0.8), tone(PAL['backup'], 1.0)))
        helmet(hc, yellow, yellow_seam, 0.112, 0.128, 0.078 * FRONT_FLAT, skirt=0.075 * FRONT_FLAT)
        prim('cube', hc + V(0, 0.01, 0.025 + 0.078 * FRONT_FLAT + 0.002), (0.009, 0.18, 0.009), yellow_seam, 'gear')
    wire = mat('wire', (tone(PAL['warm'], 0.8), PAL['warm'], tone(PAL['warm'], 1.3)))
    leather = mat('leather', (tone(ACCENT['leather'], 0.6), ACCENT['leather'], tone(ACCENT['leather'], 1.3)))
    if not FRONT:
        prim('sphere', hc + V(0, 0, 0.035), (0.106, 0.115, 0.088), hat, 'gear')                           # the hard hat
        prim('cyl', hc + V(0, -0.01, 0.0), (0.14, 0.15, 0.011), mat('hatbrim', tone(PAL['backup'], 0.85)), 'gear')
        for x in (-0.035, 0.035):                                                                         # two ribs over the top
            prim('cube', hc + V(x, 0.0, 0.118), (0.011, 0.16, 0.011), mat('hatrib', tone(PAL['backup'], 0.9)), 'gear')
    sp = spine + V(0, 0.2, -0.05)
    plate = mat('reelplate', (PAL['void'], PAL['deep'], PAL['wall']))
    prim('cube', sp + V(0, -0.02, 0.0), (0.3, 0.1, 0.2), plate, 'gear')                                    # a frame the reel is carried in
    prim('cyl', sp + V(0, 0.01, 0.1), (0.135, 0.135, 0.03), mat('spool', PAL['warm']), 'gear')            # the cable reel, seen from above
    prim('cyl', sp + V(0, 0.01, 0.112), (0.1, 0.1, 0.034), mat('spoolwound', (tone(PAL['warm'], 0.8), tone(PAL['warm'], 1.1), tone(PAL['warm'], 1.35))), 'gear')  # the cable wound on it
    prim('cyl', sp + V(0, 0.01, 0.125), (0.042, 0.042, 0.04), mat('hub', PAL['wall']), 'gear')            # its hub
    prim('cyl', sp + V(0, 0.01, 0.146), (0.014, 0.014, 0.01), mat('hubdot', PAL['metal']), 'gear')
    for x in (-0.07, 0.07):                                                                               # reflective stripes
        prim('cube', spine + V(x, 0.1, 0.03), (0.025, 0.02, 0.2), stripe, 'gear')
    for s in (lsh, rsh):                                                                                  # tool pouches at the sides
        prim('cube', spine + V(0.24 * side(s), 0.1, -0.03), (0.06, 0.1, 0.08), leather, 'gear')


def gear_hood(c):
    hc = c['hc']
    cloth = mat('hood', ('#121a28', '#26324a', '#3a4a66'))
    seam = mat('hoodseam', ('#1f2b42', '#34445f', '#4d6285'))
    flat = FRONT_FLAT if FRONT else 1.0 #(from the front: a little lower, or it looks stretched)
    helmet(hc, cloth, seam, 0.112, 0.128, 0.078 * flat, skirt=0.075 * flat)                                # the hood: a snug dome on straight sides, its hem flaring a little
    prim('cube', hc + V(0, 0.01, 0.025 + 0.078 * flat + 0.002), (0.009, 0.18, 0.009), seam, 'gear')        # the seam over the top
    chin_strap(hc, 0.112, mat('hoodstrap', ('#0a0f18', '#161f30', '#26324a')))                             # a chin strap


def gear_beanie(c):
    """the vent rat: a snug helmet in the shade's shape, but cut close to the head, with no flared lip (it has to slide through vents), a chin strap and a flat headlamp"""
    hc = c['hc']
    shell = mat('beanie', ACCENT['beanie'])
    seam = mat('beanierib', (tone(ACCENT['beanie'], 0.6), tone(ACCENT['beanie'], 0.8), ACCENT['beanie']))
    dark = mat('beaniedark', (PAL['void'], PAL['deep'], PAL['wall']))
    tall = FRONT_FLAT if FRONT else 1.0 #(from the front: a little lower, or it looks stretched)
    prim('sphere', hc + V(0, 0.01, 0.022), (0.1, 0.103, 0.07 * tall), shell, 'gear')                       # the dome
    prim('cyl', hc + V(0, 0.01, -0.012), (0.0995, 0.1025, 0.07 * tall), shell, 'gear')                     # straight sides down over the ears
    prim('cyl', hc + V(0, 0.01, -0.012 - 0.035 * tall - 0.0005), (0.1015, 0.1045, 0.006), seam, 'gear')    # a thin edge, flush with the bottom of the sides
    prim('cube', hc + V(0, 0.01, 0.022 + 0.07 * tall), (0.008, 0.15, 0.008), seam, 'gear')                 # the seam over the top
    prim('cyl', hc + V(0, 0.01, 0.03), (0.1015, 0.1045, 0.008), dark, 'gear')                              # the lamp's strap, as thin as can be
    prim('cube', hc + V(0, -0.0925, 0.03), (0.056, 0.01, 0.036), dark, 'gear')                             # the mounting plate, flat on the front
    prim('cyl', hc + V(0, -0.1, 0.03), (0.024, 0.024, 0.014), mat('lamp', (PAL['wall'], PAL['metal'], tone(PAL['metal'], 1.3))), 'gear', rot=(math.pi / 2, 0, 0))  # the lamp's housing, a short drum
    prim('cyl', hc + V(0, -0.1075, 0.03), (0.027, 0.027, 0.004), dark, 'gear', rot=(math.pi / 2, 0, 0))    # its bezel
    prim('cyl', hc + V(0, -0.1105, 0.03), (0.02, 0.02, 0.004), mat('lampglow', PAL['flash'], emit=True), 'gear', rot=(math.pi / 2, 0, 0))  # the lens
    prim('cyl', hc + V(0, -0.113, 0.03), (0.008, 0.008, 0.003), mat('lampcore', PAL['text'], emit=True), 'gear', rot=(math.pi / 2, 0, 0))  # and its bright centre
    prim('cube', hc + V(0, -0.1, 0.0525), (0.012, 0.012, 0.01), dark, 'gear')                            # the switch on top
    for x in (-1.0, 1.0):                                                                                  # clamp bolts at each side of the plate
        prim('cyl', hc + V(0.027 * x, -0.0985, 0.03), (0.004, 0.004, 0.006), mat('lampbolt', PAL['metal']), 'gear', rot=(math.pi / 2, 0, 0))
    chin_strap(hc, 0.1, dark)                                                                              # a chin strap



def gear_nvg(c):
    hc, spine = c['hc'], c['spine']
    body = mat('nvgbody', PAL['i2'])
    cloth = mat('balaclava', (PAL['i0'], PAL['i1'], PAL['i2']))
    ez, ex, ey, tube = 0.04, 0.03, 0.0, 0.04 #how high the goggles sit, how far apart the tubes are, how far the tubes stand out, how long they are
    if FRONT: #from the front: the shade's hat in black (a flat dome on straight sides), and the goggles down on the eyes, wider apart and standing out less
        helmet(hc, cloth, mat('balaclava_seam', (PAL['void'], PAL['i0'], PAL['i1'])), 0.112, 0.128, 0.078 * FRONT_FLAT, skirt=0.075 * FRONT_FLAT)
        ez, ex, ey, tube = -0.052, 0.042, 0.02, 0.026
    else:
        prim('sphere', hc + V(0, 0.005, 0.01), (0.115, 0.125, 0.11), cloth, 'gear')
    prim('cube', hc + V(0, -0.1, ez), (0.1 + (ex - 0.03) * 2.0, 0.05, 0.04), body, 'gear')                # the goggles
    for x in (-ex, ex):
        prim('cyl', hc + V(x, -0.135 + ey, ez), (0.019, 0.019, tube), body, 'gear', rot=(math.pi / 2, 0, 0))   # the tubes
        prim('cyl', hc + V(x, -0.158 + ey + (0.0055 if FRONT else 0.0), ez), (0.014, 0.014, 0.008), mat('nvglens', PAL['nv'], emit=True), 'gear', rot=(math.pi / 2, 0, 0))
    bag = spine + V(0, 0.17, -0.06)
    prim('cube', bag, (0.36, 0.15, 0.2), mat('duffel', ACCENT['duffel']), 'gear')                          # the duffel
    for x in (-0.09, 0.09):
        prim('cube', bag + V(x, 0, 0.102), (0.03, 0.155, 0.012), mat('nvgstrap', PAL['i0']), 'gear')      # its straps


GEAR = dict(cap=gear_cap, medic=gear_medic, gunner=gear_gunner, electrician=gear_electrician, hood=gear_hood, beanie=gear_beanie, nvg=gear_nvg)


# ------------------------------------------------------------------ hero poses (FRONT=1, state front_hero)
# Each role doing its job, for the role reveal: the body is posed from the idle stance with IK (the hands to a place beside the shoulders, the feet kept where they
# stand when the hips come down), the thing they work with is made in their hands and tied to a hand, and the whole figure is then turned a little.
# turn: degrees about the hips. drop: how far the hips come down (a crouch). left / right: where each wrist goes, (x, y, z above the shoulders), in metres on a body of
# scale 1; x is positive to the character's left (the right of the picture), y negative is towards the camera. *_dir: which way that fist points
HERO = {
    'guard': dict(turn=-14, drop=0.0, left=(0.27, -0.30, -0.27), right=(-0.29, -0.13, -0.47), left_dir=(0.03, -0.1, 0.0), right_dir=(0.0, -0.07, -0.07)),
    'gunner': dict(turn=-16, drop=0.0, left=(0.13, -0.31, -0.14), right=(-0.15, -0.29, -0.37), left_dir=(-0.02, -0.06, 0.07), right_dir=(0.07, -0.06, 0.03)),
    'shade': dict(turn=-18, drop=0.0, left=(0.29, -0.07, -0.54), right=(-0.05, -0.23, -0.1), left_dir=(0.0, -0.02, -0.1), right_dir=(0.04, 0.0, 0.1)),
    'medic': dict(turn=12, drop=0.0, left=(0.30, -0.24, -0.38), right=(-0.28, -0.25, -0.10), left_dir=(0.0, -0.04, -0.09), right_dir=(0.01, -0.03, 0.09)),
    'electrician': dict(turn=-12, drop=0.0, left=(0.15, -0.35, -0.30), right=(-0.15, -0.35, -0.30), left_dir=(-0.06, -0.07, 0.0), right_dir=(0.06, -0.07, 0.0)),
    'ventrat': dict(turn=-16, drop=0.34, left=(0.33, -0.27, -0.30), right=(-0.24, -0.28, -0.46), left_dir=(0.04, -0.09, 0.0), right_dir=(0.0, -0.05, -0.09)),
    'intruder': dict(turn=16, drop=0.07, left=(0.21, -0.36, -0.22), right=(-0.28, -0.19, -0.03), left_dir=(-0.02, -0.1, 0.02), right_dir=(0.0, -0.01, 0.1)),
}


def bar(a, b, width, thick, m, round_=False):
    """a bar (a box, or with round_ a rod) from point a to point b, whatever the direction"""
    d = b - a
    rot = d.to_track_quat('Z', 'Y').to_euler()
    size = (width / 2.0, width / 2.0, d.length) if round_ else (width, thick, d.length)
    return prim('cyl' if round_ else 'cube', (a + b) / 2, size, m, 'hero', rot=rot)


def ball(at, radius, m):
    return prim('sphere', at, (radius, radius, radius), m, 'hero')


def gem(at, r, h, m):
    """an eight sided cut stone"""
    verts = [at + V(r, 0, 0), at + V(0, r, 0), at + V(-r, 0, 0), at + V(0, -r, 0), at + V(0, 0, h), at + V(0, 0, -h)]
    faces = [(i, (i + 1) % 4, 4) for i in range(4)] + [((i + 1) % 4, i, 5) for i in range(4)]
    me = bpy.data.meshes.new('gem')
    me.from_pydata(verts, [], faces)
    me.update()
    o = bpy.data.objects.new('gem', me)
    bpy.context.scene.collection.objects.link(o)
    me.materials.append(m)
    me.materials.append(ink())
    PROPS.append((o, 'hero'))
    return o


def hero_pose(role, arm, k, holster_gun):
    h = HERO[role]
    bpy.context.view_layer.update()
    if h['drop']:  # a crouch: the hips come down and the legs are worked out again so the feet stay where they stood, each knee out to its own side
        feet = {s: wpos(arm, f'{s}Foot').copy() for s in ('Left', 'Right')}
        arm.location.z -= h['drop'] * k
        bpy.context.view_layer.update()
        for s, sx in (('Left', 1.0), ('Right', -1.0)):
            pose_legs(arm, {s: feet[s] + V(0.04 * sx, 0, 0)}, (0.45 * sx, -1.0, 0.1))
    shz = wpos(arm, 'LeftArm').z

    def at(p):
        return V(p[0] * k, p[1] * k, shz + p[2] * k)
    pose_arms(arm, {'Left': at(h['left']), 'Right': at(h['right'])}, lambda s: (s * 1.0, 0.3, -0.45), lambda s: h['left_dir'] if s > 0 else h['right_dir'])
    bpy.context.view_layer.update()
    hand = {s: ((wpos(arm, f'{s}Hand') + wpos(arm, f'{s}HandMiddle1')) / 2).copy() for s in ('Left', 'Right')}
    left, right = hand['Left'], hand['Right']
    head, top = wpos(arm, 'Head'), wpos(arm, 'HeadTop_End')
    hc = (head + top) / 2 + V(0, 0, 0.035 * (top - head).length / 0.177)
    steel = mat('hero_steel', (PAL['wall'], PAL['metal'], tone(PAL['metal'], 1.45)))
    dark = mat('hero_dark', ('#101216', '#22262e', '#3d434f'))
    black = mat('hero_black', ('#07090c', '#14161a', '#2a2e36'))
    white = mat('hero_white', (tone(PAL['text'], 0.75), PAL['text'], '#fbf9f3'))
    red = mat('hero_red', PAL['medic'])
    n0 = len(PROPS)
    held = []  # (side, first prop index, end index): what each hand carries

    def carry(side_name, start):
        held.append((side_name, start, len(PROPS)))

    def pistol(grip, along, suppressed):
        along = along.normalized()
        bar(grip - along * 0.02, grip + along * 0.17, 0.036, 0.046, mat('hero_gunmetal', ('#353b47', '#626c7e', '#98a1b3')))  # the slide (lighter than the real one, or it is lost against the uniform)
        bar(grip - along * 0.01, grip + along * 0.02 + V(0, 0.03, -0.075), 0.036, 0.04, black)  # the grip under the fist
        bar(grip + along * 0.158, grip + along * 0.182, 0.026, 0.03, black)          # the muzzle
        if suppressed:
            bar(grip + along * 0.17, grip + along * 0.32, 0.048, 0.048, black, round_=True)

    if role == 'guard':  # on watch: a torch held out, the pistol low
        s = len(PROPS)
        aim = V(1.0, -0.22, 0.08).normalized()  # out to the side, so the length of the torch shows
        bar(left - aim * 0.07, left + aim * 0.13, 0.052, 0.052, dark, round_=True)
        bar(left + aim * 0.13, left + aim * 0.19, 0.082, 0.082, steel, round_=True)
        bar(left + aim * 0.19, left + aim * 0.196, 0.07, 0.07, mat('hero_lamp', PAL['flash'], emit=True), round_=True)
        carry('Left', s)
        s = len(PROPS)
        pistol(right + V(0, -0.045, -0.02), V(-0.5, -0.3, -0.8), False)
        carry('Right', s)
        holster_gun.hide_render = True
    elif role == 'gunner':  # the shotgun held across the chest
        s = len(PROPS)
        u = (left - right).normalized()
        out = V(0, -0.06, 0)
        wood = mat('hero_wood', ('#241a14', '#3d2d22', '#5a4433'))
        bar(right + out - u * 0.34 * k, right + out - u * 0.06, 0.1, 0.055, wood)          # the stock
        bar(right + out - u * 0.07, left + out + u * 0.03, 0.095, 0.06, dark)              # the receiver
        bar(left + out + u * 0.02, left + out + u * 0.42 * k, 0.046, 0.046, steel, round_=True)   # the barrel
        side_v = u.cross(V(0, -1, 0)).normalized()
        side_v = side_v if side_v.z < 0 else -side_v
        bar(left + out + u * 0.03 + side_v * 0.045, left + out + u * 0.33 * k + side_v * 0.045, 0.036, 0.036, dark, round_=True)  # the tube magazine under it
        bar(left + out - u * 0.06 + side_v * 0.04, left + out + u * 0.13 + side_v * 0.04, 0.07, 0.07, wood, round_=True)          # the pump, in the front hand
        carry('Right', s)
        for o, tag in PROPS:
            if tag == 'holster':
                o.hide_render = True
    elif role == 'shade':  # a finger to the lips, the suppressed pistol held down
        s = len(PROPS)
        lips = hc + V(0.008, -0.114, -0.178)
        skin = mat(f'{role}_hands', ROLES[role]['hands'])
        base = right + V(0.012, -0.012, 0.03)
        bar(base, lips + V(0, -0.012, 0.022), 0.025, 0.025, skin, round_=True)
        ball(lips + V(0, -0.012, 0.022), 0.012, skin)
        carry('Right', s)
        s = len(PROPS)
        pistol(left + V(0, -0.035, -0.03), V(0.08, -0.18, -1.0), True)
        carry('Left', s)
        holster_gun.hide_render = True
    elif role == 'medic':  # the medical case in one hand, an injector ready in the other
        s = len(PROPS)
        c = left + V(0.0, -0.035, -0.17)
        prim('cube', c, (0.27, 0.11, 0.2), white, 'hero')
        prim('cube', c + V(0, -0.06, 0), (0.12, 0.01, 0.038), red, 'hero')
        prim('cube', c + V(0, -0.06, 0), (0.038, 0.01, 0.12), red, 'hero')
        for x in (-0.05, 0.05):
            bar(c + V(x, 0, 0.1), c + V(x, 0, 0.16), 0.018, 0.018, dark, round_=True)
        bar(c + V(-0.058, 0, 0.162), c + V(0.058, 0, 0.162), 0.026, 0.026, dark, round_=True)
        carry('Left', s)
        s = len(PROPS)
        g = right + V(0, -0.045, 0.0)
        up = V(-0.12, -0.12, 1.0).normalized()
        bar(g - up * 0.05, g + up * 0.15, 0.052, 0.052, white, round_=True)
        bar(g + up * 0.035, g + up * 0.125, 0.056, 0.056, mat('hero_serum', '#6fd3e8', emit=True), round_=True)
        bar(g + up * 0.15, g + up * 0.165, 0.062, 0.062, steel, round_=True)
        bar(g + up * 0.165, g + up * 0.25, 0.009, 0.009, steel, round_=True)
        bar(g - up * 0.09, g - up * 0.05, 0.03, 0.03, red, round_=True)
        carry('Right', s)
    elif role == 'electrician':  # a battery held out in both hands
        s = len(PROPS)
        c = (left + right) / 2 + V(0, -0.03, 0.025)
        w = max((left - right).length - 0.07, 0.2)
        prim('cube', c, (w, 0.14, 0.18), dark, 'hero')
        prim('cube', c + V(0, 0, 0.1), (w + 0.012, 0.152, 0.026), mat('hero_band', PAL['backup']), 'hero')
        for x, m in ((-0.3, red), (0.3, steel)):
            bar(c + V(x * w, 0, 0.11), c + V(x * w, 0, 0.165), 0.042, 0.042, m, round_=True)
        charge = mat('hero_charge', PAL['nv'], emit=True)
        prim('cube', c + V(0, -0.072, -0.008), (w * 0.74, 0.006, 0.07), black, 'hero')
        for i in range(4):
            prim('cube', c + V((i - 1.5) * w * 0.165, -0.077, -0.008), (w * 0.125, 0.006, 0.048), charge, 'hero')
        carry('Right', s)
    elif role == 'ventrat':  # crouched, the cover of a vent pulled off and held beside them
        s = len(PROPS)
        c = left + V(0.13, -0.025, -0.02)
        side_len = 0.40
        prim('cube', c + V(0, 0.02, 0), (side_len - 0.04, 0.012, side_len - 0.04), black, 'hero')
        for sx, sz, wx, wz in ((0, 0.5, 1.0, 0.0), (0, -0.5, 1.0, 0.0), (0.5, 0, 0.0, 1.0), (-0.5, 0, 0.0, 1.0)):
            prim('cube', c + V(sx * (side_len - 0.035), 0, sz * (side_len - 0.035)), (side_len if wx else 0.036, 0.03, side_len if wz else 0.036), steel, 'hero')
        for i in range(5):
            prim('cube', c + V(0, -0.004, (i - 2) * 0.062), (side_len - 0.06, 0.022, 0.026), steel, 'hero', rot=(math.radians(28), 0, 0))
        for sx in (-1.0, 1.0):
            for sz in (-1.0, 1.0):
                ball(c + V(sx * 0.18, -0.018, sz * 0.18), 0.011, dark)
        carry('Left', s)
    elif role == 'intruder':  # the artifact taken, the suppressed pistol raised
        s = len(PROPS)
        c = left + V(0.0, -0.03, 0.14)
        gem(c, 0.075, 0.11, mat('hero_relic', ('#2b7f96', '#6fd3e8', '#d6f6ff')))
        gem(c, 0.034, 0.05, mat('hero_relic_core', '#e8fbff', emit=True))
        for dx, dz in ((-0.12, 0.07), (0.12, 0.04), (-0.095, -0.075), (0.1, -0.09), (0.02, 0.165)):
            gem(c + V(dx, 0, dz), 0.011, 0.019, mat('hero_spark', '#a8ecfa', emit=True))
        carry('Left', s)
        s = len(PROPS)
        pistol(right + V(0.0, -0.045, 0.035), V(0.03, -0.12, 1.0), True)
        carry('Right', s)
        holster_gun.hide_render = True
    if INK:
        for o, _ in PROPS[n0:]:
            if 'spark' not in o.data.materials[0].name:
                outline(o, 0.006, 1, even=False)
    for side_name, first, end in held:
        for o, _ in PROPS[first:end]:
            attach(arm, o, f'{side_name}Hand')
    arm.rotation_euler = (0, 0, math.radians(h['turn']))  # the whole figure, and what it holds, turned a little
    bpy.context.view_layer.update()


# ------------------------------------------------------------------ build one role
def build(role):
    cfg = dict(ROLES[role], _role=role)
    PROPS.clear()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    # motion source: the Mixamo clips in Xbot.glb (its mannequin mesh is discarded)
    bpy.ops.import_scene.gltf(filepath=os.path.join(ASSETS, 'Xbot.glb'))
    src = [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]
    for o in list(bpy.data.objects):
        if o.type == 'MESH':
            bpy.data.objects.remove(o)
    src.hide_render = True
    # extra Mixamo clips (FBX, Without Skin, In Place) each bring their own armature; turn it to face the same way as the Xbot's
    clip_src = {}
    needed = set()
    for s in STATES:
        if ONLY and not any(s['name'] == o or (o.endswith('*') and s['name'].startswith(o[:-1])) for o in ONLY):
            continue
        if s.get('clip'):
            needed.add(s['clip'])
        if s.get('mix'):
            needed.update(CLIPSPEC[c]['clip'] for c, _, _ in s['mix'](0, s['n']) if c != 'idle' and 'clip' in CLIPSPEC[c])
    for fname in sorted(needed): #only the clips of the states being rendered
        before_clip = set(bpy.data.objects)
        bpy.ops.import_scene.fbx(filepath=os.path.join(ASSETS, 'clips', fname))
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
    bpy.ops.import_scene.gltf(filepath=os.path.join(ASSETS, 'readyplayer.me.glb'))
    new = [o for o in bpy.data.objects if o not in before]
    arm = [o for o in new if o.type == 'ARMATURE'][0]
    for o in new:
        if o.name.startswith('Icosphere') or any(k in o.name for k in ('Teeth', 'Eye', 'Beard', 'Headwear')):
            bpy.data.objects.remove(o)
    for b in arm.data.bones:
        if not b.name.startswith('mixamorig:'):
            b.name = 'mixamorig:' + b.name
    arm.rotation_mode = 'XYZ'
    k = ROLE_K = cfg.get('scale', 1.0)
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
    if FRONT: #a sterner, calmer face: the mouth's smile shape key pushed the other way, the mouth shut
        for o in BODY:
            keys = o.data.shape_keys
            if 'Head' in o.name and keys:
                if 'mouthSmile' in keys.key_blocks:
                    keys.key_blocks['mouthSmile'].slider_min = -1.0
                    keys.key_blocks['mouthSmile'].value = FRONT_SMILE
                if 'mouthOpen' in keys.key_blocks:
                    keys.key_blocks['mouthOpen'].value = 0.0
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
    aim_rot = {pb.name: pb.rotation_quaternion.copy() for pb in arm.pose.bones}  #the aimed pose itself, for the reload to start and end on
    aim_loc = {pb.name: pb.location.copy() for pb in arm.pose.bones}
    bpy.context.view_layer.update()
    aim_hand = (arm.matrix_world @ arm.pose.bones['mixamorig:RightHand'].matrix).copy() #where the gun is held: what the gun in the hands follows in the reload

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
    bpy.context.view_layer.update()
    hand_rel = [(o, aim_hand.inverted() @ o.matrix_world, o.matrix_world.copy()) for o, t in PROPS if t == 'hand'] #(prop, its place against the right hand, its place at the aim)

    # ---- holstered weapon ----
    n0 = len(PROPS)
    if w in ('pistol', 'suppressed'):
        prim('cube', (hips.x - 0.2, hips.y - 0.01, hips.z + 0.04), (0.06, 0.14, 0.1), mat('holster', ACCENT['holster']), 'holster')
        prim('cube', (hips.x - 0.2, hips.y - 0.07, hips.z + 0.12), (0.035, 0.05, 0.05), gun, 'holster')
        holster_gun = PROPS[n0 + 1][0] #(the nub of the gun showing in the holster: the draw state moves the hand to it)
        for o, _ in PROPS[n0:]:
            attach(arm, o, 'Hips')
    else:
        length = 0.75 if w == 'rifle' else 0.34
        lift = 0.16 if cfg['gear'] == 'gunner' else 0.08
        prim('cube', (spine.x, spine.y + 0.2, spine.z + lift), (0.055, length, 0.07), gun, 'holster', rot=(0, 0, math.radians(32)))
        holster_gun = PROPS[n0][0]
        for o, _ in PROPS[n0:]:
            attach(arm, o, 'Spine2')

    # ---- role gear ----
    n0 = len(PROPS)
    ctx = dict(hc=hc, spine=spine, hips=hips, lsh=lsh, rsh=rsh, k=ROLE_K, arm=arm)
    GEAR[cfg['gear']](ctx)
    for o, tag in PROPS[n0:]:
        if tag == 'bone':
            continue #(already on its bone)
        on_head = tag == 'head' or o.matrix_world.translation.z > lsh.z + 0.08
        if on_head:
            #(seen from the front the caps are smaller: they were sized for the view from above. The helmets and hoods have to stay as wide as the head, so they are only made flatter)
            hat_k = hk * (FRONT_HAT_BY_GEAR.get(cfg['gear'], FRONT_HAT) if FRONT else 1.0)
            o.location = hc + (o.location - hc) * hat_k
            if FRONT and cfg['gear'] in FRONT_HAT_BY_GEAR:
                o.location.z -= FRONT_HAT_DROP
            o.scale = (hat_k, hat_k, hat_k)
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
                show = show and mode in ('aim', 'reload')
            elif tag == 'holster':
                show = show and mode not in ('aim', 'reload')
            o.hide_render = not show

    foot_rest = {}

    def shuffle_pose(u, p):
        """A sideways shuffle made on the legs with IK (no clip): the feet stay on their own side of the body and slide in turn, like a step and close. u: where in
        the cycle (the left foot is highest at LIFT, like every other gait), p: dict(c=how far each foot is from the middle, a=how far it travels from there,
        lift=how high it comes off the ground). The character moves to its right (-x), so a planted foot goes the other way (+x) relative to the hips."""
        for pb in arm.pose.bones:
            pb.rotation_quaternion = idle_rot[pb.name]
            pb.location = idle_loc[pb.name]
        bpy.context.view_layer.update()
        if not foot_rest:
            for side in ('Left', 'Right'):
                foot_rest[side] = wpos(arm, f'{side}Foot').copy()
        targets = {}
        for side, centre, phase0 in (('Left', p['c'], (LIFT - 0.25) % 1.0), ('Right', -p['c'], (LIFT + 0.25) % 1.0)):
            q = (u - phase0) % 1.0  # 0..0.5 the foot is in the air (highest in the middle), 0.5..1 planted
            if q < 0.5:
                t = smooth(q / 0.5)
                dx = centre + p['a'] - 2 * p['a'] * t
                dz = p['lift'] * math.sin(math.pi * q / 0.5)
            else:
                dx = centre - p['a'] + 2 * p['a'] * ((q - 0.5) / 0.5)
                dz = 0.0
            r = foot_rest[side]
            targets[side] = Vector((dx, r.y, r.z + dz))
        pose_legs(arm, targets, (0.0, -1.0, 0.1))
        return ({pb.name: pb.rotation_quaternion.copy() for pb in arm.pose.bones}, {pb.name: pb.location.copy() for pb in arm.pose.bones})

    def clip_pose(spec, sample, mirrored=False):
        """The skeleton posed like a clip at `sample` (0 to 1 through it): (rotations, locations) by bone."""
        carm, cact, crest = clip_src[spec['clip']]
        a0, a1 = cact.frame_range
        carm.animation_data.action = cact
        sc.frame_set(int(round(a0 + (a1 - a0) * min(max(sample, 0.0), 1.0))))
        retarget(carm, arm, crest, mirrored)
        rot = {pb.name: pb.rotation_quaternion.copy() for pb in arm.pose.bones}
        loc = {pb.name: pb.location.copy() for pb in arm.pose.bones}
        if spec.get('upper'):  # the rest of the body stays as it stands
            for k in rot:
                if not _is_upper(k):
                    rot[k], loc[k] = idle_rot[k].copy(), idle_loc[k].copy()
        return rot, loc

    def mix_pose(parts, layer):
        """Poses the body as a blend of clips (parts: [(clip name or 'idle', where in its cycle, weight)]); returns the yaw to square the blend up."""
        acc_rot = acc_loc = None
        total = yaw = 0.0
        for comp, u, weight in parts:
            if weight <= 0.0:
                continue
            if comp == 'idle':
                rot, loc, y = idle_rot, idle_loc, 0.0
            elif comp == 'aim':
                rot, loc, y = aim_rot, aim_loc, 0.0
            elif 'shuffle' in CLIPSPEC[comp]:
                rot, loc = shuffle_pose(u, CLIPSPEC[comp]['shuffle'])
                y = 0.0
            else:
                spec = CLIPSPEC[comp]
                mirrored = spec.get('mirror', False)
                if spec.get('window'):  # a stretch of a long clip played as a loop: the end of the cycle fades into the stretch before its start, so it joins up
                    start, span = spec['window']
                    uu = u % 1.0
                    fade = spec.get('xfade', 0.3)
                    w = smooth((uu - (1.0 - fade)) / fade)
                    rot, loc = clip_pose(spec, start + span * uu)
                    if w > 0.0:
                        rot2, loc2 = clip_pose(spec, start + span * (uu - 1.0))
                        rot = {k: rot[k].slerp(rot2[k], w) for k in rot}
                        loc = {k: loc[k].lerp(loc2[k], w) for k in loc}
                else:
                    sample = min(max(u, 0.0), 1.0) if spec.get('once') else (u + spec['lift'] - LIFT) % 1.0 #a death plays once from its first frame to its last
                    rot, loc = clip_pose(spec, sample, mirrored)
                if spec.get('damp'):  # below 1: part of the way from the idle pose; above 1: past the clip's own pose, away from the idle pose
                    rot = {k: _toward(idle_rot[k], v, spec['damp']) for k, v in rot.items()}
                    loc = {k: idle_loc[k] + (v - idle_loc[k]) * spec['damp'] for k, v in loc.items()}
                y = spec['yaw_torso' if layer == 'torso' else 'yaw_legs'] * (-1.0 if mirrored else 1.0)
            if acc_rot is None:
                acc_rot, acc_loc, total, yaw = {k: v.copy() for k, v in rot.items()}, {k: v.copy() for k, v in loc.items()}, weight, y * weight
            else:
                t = weight / (total + weight)
                acc_rot = {k: acc_rot[k].slerp(rot[k], t) for k in acc_rot}
                acc_loc = {k: acc_loc[k].lerp(loc[k], t) for k in acc_loc}
                total += weight
                yaw += y * weight
        for pb in arm.pose.bones:
            pb.rotation_quaternion = acc_rot[pb.name]
            pb.location = acc_loc[pb.name]
        bpy.context.view_layer.update()
        return yaw / total

    # ---- the reload ----
    # The clip is a rifle reload and a rifle's hands are where the clip has them. A pistol is held further in, one hand wrapped round the other: its hands are the clip's own movement
    # (measured against the chest, from where they start) added to the pistol's aimed positions, each axis by RELOAD_HANDS' gain, with the arms worked out again by IK. The magazine hand
    # (the left) keeps most of the movement, to the hip and back up to the grip; the gun hand keeps a little (the pistol tips towards the chest as the magazine goes in).
    reload_ref = {}
    RELOAD_HANDS = {'Left': (1.0, 0.8, 0.8), 'Right': (0.3, 0.3, 0.4)}

    def reload_arms(st, i, n, dl):
        bpy.context.view_layer.update()
        if w != 'rifle':
            aim_weight = sum(wt for c, _, wt in st['mix'](i, n) if c == 'aim')
            chest = wpos(arm, 'Spine2')
            goals = {}
            for s in ('Left', 'Right'):
                off = (wpos(arm, f'{s}Hand') - chest) - reload_ref[s]
                g = RELOAD_HANDS[s]
                goals[s] = aim_t[s] + dl + Vector((off.x * g[0], off.y * g[1], off.z * g[2])) * (1.0 - aim_weight)
            pose_arms(arm, goals, aim_pole, aim_dir)
            bpy.context.view_layer.update()
        hand = arm.matrix_world @ arm.pose.bones['mixamorig:RightHand'].matrix
        for o, rel, _ in hand_rel: #the gun goes where the right hand goes
            o.matrix_world = hand @ rel

    os.makedirs(os.path.join(OUT, role), exist_ok=True)
    meta = {}
    for st in STATES:
        if bool(st.get('front')) != FRONT: #the front stills are for FRONT=1 only, and the sheets are not rendered then
            continue
        if ONLY and not any(st['name'] == o or (o.endswith('*') and st['name'].startswith(o[:-1])) for o in ONLY):
            continue
        set_layer(st['layer'], st['mode'])
        if st['mode'] == 'reload' and w != 'rifle':  # where the clip has the hands as it starts
            arm.rotation_euler, arm.location, arm.scale = (0, 0, 0), (0, 0, 0), (ROLE_K,) * 3
            mix_pose([('reload', 0.0, 1.0)], 'torso')
            reload_ref.update({s: wpos(arm, f'{s}Hand') - wpos(arm, 'Spine2') for s in ('Left', 'Right')})
        clip = st.get('clip')
        sx, rx = (clip_src[clip][0], clip_src[clip][2]) if clip else (src, REF)
        act = clip_src[clip][1] if clip else (None if st.get('mix') else acts[st['action']])
        r0, r1 = act.frame_range if act else (0, 0)
        n = st['n']
        full = st['layer'] == 'full'
        if full:
            cam.ortho_scale = st.get('ortho', 2.9 if w == 'rifle' else 2.6)
        else:
            cam.ortho_scale = st.get('ortho', layered_scale)
        sc.render.resolution_x = sc.render.resolution_y = int(round(cam.ortho_scale * PPU))
        co.location = (0, -0.12, 6)
        if st.get('front'): #seen from the front: the character faces -y, so the camera stands at -y and looks along +y (the sheets' camera looks down)
            co.rotation_euler = (math.pi / 2, 0, 0)
            co.location = (0, -5.0, 1.0 * ROLE_K)
            cam.ortho_scale = 2.3 * ROLE_K
            sc.render.resolution_x, sc.render.resolution_y = 640, 960
        else:
            co.rotation_euler = (0, 0, math.pi)
        travel_base = None
        for i in range(n):
            arm.rotation_euler = (0, 0, 0)
            arm.location = (0, 0, 0)
            kk = 1.0 if st['layer'] == 'legs' else ROLE_K #the legs are the guard's, whatever the role's build: only the body above them is bigger or smaller
            arm.scale = (kk, kk, kk)
            if st.get('mix'):
                yaw_deg = mix_pose(st['mix'](i, n), st['layer'])
            else:
                sx.animation_data.action = act
                u = i / (n - 1 if clip and not st.get('loop') else n)  # a clip that plays once ends on its last frame; a looping one stops a frame short of its start
                if st.get('phase'):  # start part way through a looping clip, to line its footfalls up with the other gait cycles
                    u = (u + st['phase']) % 1.0
                sc.frame_set(int(round(r0 + (r1 - r0) * u)))
                retarget(sx, arm, rx)
                if st.get('blend'):
                    b = st['blend']
                    for pb in arm.pose.bones:
                        pb.rotation_quaternion = idle_rot[pb.name].slerp(pb.rotation_quaternion, b)
                        pb.location = idle_loc[pb.name].lerp(pb.location, b)
                yaw_deg = st.get('yaw_offset', 0)
            fingers_to_fists(arm)
            mode = st['mode']
            if st.get('keep_travel'):
                # the clip's own movement stays (a fall carries the body away from where the feet stood): only where the standing pose has its hips is taken
                # as the pivot, once, from the first frame, and the same shift is applied to every frame
                bpy.context.view_layer.update()
                if travel_base is None:
                    travel_base = (wpos(arm, 'Hips').x, wpos(arm, 'Hips').y)
                arm.location.x -= travel_base[0]
                arm.location.y -= travel_base[1]
                bpy.context.view_layer.update()
            else:
                recenter(arm)
            if yaw_deg:  # turn the whole body about the hips, so a clip that starts a few degrees off square starts square
                arm.rotation_euler = (0, 0, math.radians(yaw_deg))
                bpy.context.view_layer.update()
                if not st.get('keep_travel'):
                    recenter(arm)
            dl =wpos(arm, 'Spine2') - spine_ref
            if mode == 'aim':
                pose_arms(arm, {k: v + dl for k, v in aim_t.items()}, aim_pole, aim_dir)
                for o, loc in hand_items:
                    o.location = loc + dl
            elif mode == 'draw':
                # drawing the gun: the right hand goes to the holster and takes the gun (first 40%), brings it up to the aim while the left hand comes across to meet it
                t = i / (n - 1.0)
                p1 = smooth(t / 0.4)
                p2 = smooth((t - 0.4) / 0.5)
                pl = smooth((t - 0.3) / 0.6)
                bpy.context.view_layer.update()
                grip = holster_gun.matrix_world.translation.copy()
                rest = {s: wpos(arm, f'{s}Hand').copy() for s in ('Left', 'Right')}
                elbow_out = {}
                for s in ('Left', 'Right'):
                    sh, el, ha = wpos(arm, f'{s}Arm'), wpos(arm, f'{s}ForeArm'), wpos(arm, f'{s}Hand')
                    mid = (sh + ha) / 2
                    v = el - mid
                    elbow_out[s] = (v - (ha - sh).normalized() * v.dot((ha - sh).normalized())).normalized() #which way the elbow points at rest
                aim_r, aim_l = aim_t['Right'] + dl, aim_t['Left'] + dl
                goals = {'Right': rest['Right'].lerp(grip, p1).lerp(aim_r, p2), 'Left': rest['Left'].lerp(aim_l, pl)}
                blend = {'Right': max(p1 * 0.6, p2), 'Left': pl}
                for s in ('Right', 'Left'):
                    pole_now = elbow_out[s].lerp(Vector(aim_pole(1 if s == 'Left' else -1)).normalized(), blend[s])
                    pose_arms(arm, {s: goals[s]}, lambda sg, P=pole_now: P, aim_dir)
                for o, loc in hand_items: #the gun is in the holster until the hand lifts it out
                    o.hide_render = not p2 > 0.0
                    o.location = grip.lerp(loc + dl, p2)
                holster_gun.hide_render = p2 > 0.0
            elif mode == 'reload':
                reload_arms(st, i, n, dl)
            elif mode == 'hero':
                hero_pose(role, arm, ROLE_K, holster_gun)
            bpy.context.view_layer.update()
            if SHOULDERS:  # offsets from the sprite's pivot, in sprite pixels (x right, y down), for the left and right shoulder joints
                k = sc.render.resolution_x / cam.ortho_scale
                lsh_w, rsh_w = wpos(arm, 'LeftArm'), wpos(arm, 'RightArm')
                SHOULDER_POS.setdefault(st['name'], []).append([round(-lsh_w.x * k, 1), round(lsh_w.y * k, 1), round(-rsh_w.x * k, 1), round(rsh_w.y * k, 1)])
                hd_w = wpos(arm, 'Head')
                HEAD_POS.setdefault(st['name'], []).append([round(-hd_w.x * k, 1), round(hd_w.y * k, 1)]) #(same convention: from the pivot, in sheet pixels, x right, y down)
                continue
            sc.render.filepath = os.path.join(OUT, role, f"{st['name']}_{i:02d}.png")
            bpy.ops.render.render(write_still=True)
        if st['mode'] == 'reload':
            for o, _, home in hand_rel: #the gun is back where it was held, for the states after this one
                o.matrix_world = home
        # where the character's position sits inside this sprite (pixels from top-left)
        res = sc.render.resolution_x
        ppu = res / cam.ortho_scale
        meta[st['name']] = dict(frames=n, size=res, pivot=[res / 2, res / 2 - co.location.y * ppu], px_per_m=round(ppu, 2))
        print('done', role, st['name'], flush=True)
    import json
    if SHOULDERS:
        json.dump(SHOULDER_POS, open(os.path.join(OUT, role, 'shoulders.json'), 'w'))
        json.dump(HEAD_POS, open(os.path.join(OUT, role, 'heads.json'), 'w'))
    else:
        json.dump(meta, open(os.path.join(OUT, role, 'sprites.json'), 'w'), indent=1)


if __name__ == '__main__':
    for r in (ROLES if ROLE_ARG == 'all' else ROLE_ARG.split(',')):
        build(r)

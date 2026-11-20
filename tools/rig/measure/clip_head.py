import bpy, os, sys, math

# usage: python clip_head.py -- <clips folder> <file> [<file> ...]
# For each clip: which way the head faces compared with the shoulders (degrees; positive = the head looks to the character's left), averaged over the
# cycle. A sheet squared up on the shoulders has its head off by this much, so its yaw_torso in anim.py needs this correction for the head to point
# where the aim is. The head's forward axis is taken as the one that points the way a plain walk faces.
folder = sys.argv[sys.argv.index('--') + 1]
names = sys.argv[sys.argv.index('--') + 2:]


def ang(v):
    return math.degrees(math.atan2(v.y, v.x))


def wrap(a):
    return (a + 180.0) % 360.0 - 180.0


for fn in names:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=os.path.join(folder, fn))
    arm = [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]
    act = bpy.data.actions[0]
    arm.animation_data.action = act
    sc = bpy.context.scene
    r0, r1 = int(act.frame_range[0]), int(act.frame_range[1])
    offsets = []
    for f in range(r0, r1):
        sc.frame_set(f)
        bpy.context.view_layer.update()
        left = arm.matrix_world @ arm.pose.bones['mixamorig:LeftArm'].head
        right = arm.matrix_world @ arm.pose.bones['mixamorig:RightArm'].head
        shoulders_facing = ang(left - right) - 90.0 #the character faces along y: its left minus right points along x
        head = (arm.matrix_world @ arm.pose.bones['mixamorig:Head'].matrix).to_3x3()
        top = (arm.matrix_world @ arm.pose.bones['mixamorig:HeadTop_End'].head) - (arm.matrix_world @ arm.pose.bones['mixamorig:Head'].head)
        # the head's forward axis: the one of its local axes (not the one along the bone) that is most horizontal and points forward for a plain walk (-Y in the world)
        best = None
        for col in (0, 2):
            for sign in (1, -1):
                v = head.col[col] * sign
                v.z = 0.0
                if v.length > 0.3:
                    cand = (col, sign)
                    best = cand if best is None else best
        offsets.append((head.col[0].copy(), head.col[1].copy(), head.col[2].copy(), shoulders_facing))
    # report the head's three axes (horizontal part) relative to the shoulders, so the forward one can be picked by comparing with a walk
    mean = []
    for k in range(3):
        a = sum(wrap(ang(o[k]) - o[3]) for o in offsets) / len(offsets)
        mean.append(a)
    print('INFO %-26s head axis X %5.0f  axis Y(along bone) %5.0f  axis Z %5.0f   (each relative to where the shoulders face)' % (fn, mean[0], mean[1], mean[2]))

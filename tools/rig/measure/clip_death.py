import bpy, os, sys, math

# usage: python clip_death.py -- <clips folder> <file> [<file> ...]
# For a death clip: how long it is, how far the hips travel, which way the body points at the start and at the end, and how it ends up lying (face up or down).
folder = sys.argv[sys.argv.index('--') + 1]
names = sys.argv[sys.argv.index('--') + 2:]


def ang(v):
    return math.degrees(math.atan2(v.y, v.x))


for fn in names:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=os.path.join(folder, fn))
    arm = [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]
    act = bpy.data.actions[0]
    arm.animation_data.action = act
    sc = bpy.context.scene
    r0, r1 = int(act.frame_range[0]), int(act.frame_range[1])

    def P(b):
        return arm.matrix_world @ arm.pose.bones['mixamorig:' + b].head

    rows = []
    for f in (r0, r0 + (r1 - r0) // 4, (r0 + r1) // 2, r0 + 3 * (r1 - r0) // 4, r1):
        sc.frame_set(f)
        bpy.context.view_layer.update()
        hips, head, left, right, spine = P('Hips'), P('Head'), P('LeftArm'), P('RightArm'), P('Spine2')
        facing = ang(left - right) - 90.0  # which way the chest faces (a character facing -y has its left minus right along +x)
        up_z = (arm.matrix_world.to_3x3() @ arm.pose.bones['mixamorig:Spine2'].matrix.to_3x3().col[2]).z  # the spine's local z: forward on a standing mixamo body
        head_off = head - hips
        rows.append('f%-3d hips (%.2f,%.2f,%.2f) head-hips (%.2f,%.2f,%.2f) chest faces %4.0f deg' % (f, hips.x, hips.y, hips.z, head_off.x, head_off.y, head_off.z, facing))
    sc.frame_set(r1)
    bpy.context.view_layer.update()
    head_off = P('Head') - P('Hips')
    belly = (arm.matrix_world.to_3x3() @ arm.pose.bones['mixamorig:Spine2'].matrix.to_3x3().col[2])
    print('INFO %s: %d frames at %d fps (%.2f s)  final head direction %.0f deg, length along the ground %.2f m, belly vector z %.2f (%s)' % (
        fn, r1 - r0, sc.render.fps, (r1 - r0) / sc.render.fps, ang(head_off), math.hypot(head_off.x, head_off.y), belly.z, 'face down' if belly.z < -0.3 else ('face up' if belly.z > 0.3 else 'on its side')))
    for r in rows:
        print('INFO     ' + r)

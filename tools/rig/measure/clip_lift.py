import bpy, os, sys
folder = sys.argv[sys.argv.index('--') + 1]
names = sys.argv[sys.argv.index('--') + 2:]
for fn in names:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=os.path.join(folder, fn))
    arm = [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]
    act = bpy.data.actions[0]; arm.animation_data.action = act
    sc = bpy.context.scene
    r0, r1 = int(act.frame_range[0]), int(act.frame_range[1])
    n = r1 - r0
    def z(b): return (arm.matrix_world @ arm.pose.bones['mixamorig:' + b].head).z
    L = []; R = []
    for f in range(r0, r1):
        sc.frame_set(f); bpy.context.view_layer.update()
        L.append(z('LeftFoot')); R.append(z('RightFoot'))
    kl = max(range(n), key=lambda i: L[i]); kr = max(range(n), key=lambda i: R[i])
    print('INFO %-26s cycle %d  left foot highest at %.2f, right foot highest at %.2f (lift range left %.2f..%.2f)' % (fn, n, kl / n, kr / n, min(L), max(L)))

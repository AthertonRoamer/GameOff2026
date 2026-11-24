import bpy, os, sys, math
# usage: python clip_reload.py -- <clips folder> <file>
# A clip's length, and where the hands are over its length (metres, relative to the hips; x right of the character is -x, y forward is -y), for the upper body work.
folder, fn = sys.argv[sys.argv.index('--') + 1:][:2]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=os.path.join(folder, fn))
arm = [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]
act = bpy.data.actions[0]
arm.animation_data.action = act
sc = bpy.context.scene
r0, r1 = int(act.frame_range[0]), int(act.frame_range[1])
print('INFO %s: frames %d-%d at %d fps (%.2f s), %d bones, action %s' % (fn, r0, r1, sc.render.fps, (r1 - r0) / sc.render.fps, len(arm.pose.bones), act.name))
def P(b):
    return arm.matrix_world @ arm.pose.bones['mixamorig:' + b].head
for f in range(r0, r1 + 1, max(1, (r1 - r0) // 16)):
    sc.frame_set(f)
    bpy.context.view_layer.update()
    h = P('Hips'); l = P('LeftHand') - h; r = P('RightHand') - h; hd = P('Head') - h; sp = P('Spine2') - h
    print('f%-4d hips(%.2f,%.2f,%.2f) L(%.2f,%.2f,%.2f) R(%.2f,%.2f,%.2f) head(%.2f,%.2f,%.2f) spine2(%.2f,%.2f,%.2f)' % ((f,) + tuple(h) + tuple(l) + tuple(r) + tuple(hd) + tuple(sp)))

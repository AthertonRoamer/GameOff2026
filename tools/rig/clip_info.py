import bpy, os, math, sys
name = sys.argv[sys.argv.index('--')+1]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=os.path.join(os.path.dirname(os.path.abspath(__file__)), 'clips', name))
arm=[o for o in bpy.data.objects if o.type=='ARMATURE'][0]
act=bpy.data.actions[0]; arm.animation_data.action=act
sc=bpy.context.scene
def p(n): return arm.matrix_world @ arm.pose.bones['mixamorig:'+n].head
r0,r1=int(act.frame_range[0]),int(act.frame_range[1])
sh=[];pv=[];hd=[]
for f in range(r0,r1):
    sc.frame_set(f); bpy.context.view_layer.update()
    a=p('LeftArm')-p('RightArm'); b=p('LeftUpLeg')-p('RightUpLeg')
    sh.append(math.degrees(math.atan2(a.y,a.x))); pv.append(math.degrees(math.atan2(b.y,b.x)))
    # head forward: bone y axis? use neck->head vs nose not available; use head matrix -Y?
print('MEAN shoulders', round(sum(sh)/len(sh)), 'range', round(min(sh)), round(max(sh)), 'pelvis mean', round(sum(pv)/len(pv)), round(min(pv)), round(max(pv)))

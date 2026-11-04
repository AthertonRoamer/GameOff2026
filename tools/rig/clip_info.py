import bpy, os, math, sys
name = sys.argv[sys.argv.index('--')+1]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=os.path.join(os.path.dirname(os.path.abspath(__file__)), 'clips', name))
arm=[o for o in bpy.data.objects if o.type=='ARMATURE'][0]
act=bpy.data.actions[0]; arm.animation_data.action=act
sc=bpy.context.scene
print('ACT', name, act.frame_range[:], 'fps', sc.render.fps)
def p(n): return arm.matrix_world @ arm.pose.bones['mixamorig:'+n].head
r0,r1=int(act.frame_range[0]),int(act.frame_range[1])
rows=[]
for f in range(r0,r1+1,max(1,(r1-r0)//8)):
    sc.frame_set(f); bpy.context.view_layer.update()
    h=p('Hips'); L=p('LeftFoot'); R=p('RightFoot')
    line=p('LeftUpLeg')-p('RightUpLeg')
    print('F',f,'hips',tuple(round(x,2) for x in h),'L',tuple(round(x-y,2) for x,y in zip(L,h))[:2],'R',tuple(round(x-y,2) for x,y in zip(R,h))[:2],'pelvis',round(math.degrees(math.atan2(line.y,line.x))))
sc.frame_set(r0); bpy.context.view_layer.update(); a=p('Hips'); la=p('LeftFoot')-a
sc.frame_set(r1); bpy.context.view_layer.update(); b=p('Hips'); lb=p('LeftFoot')-b
print('LOOP hips drift', tuple(round(x-y,3) for x,y in zip(b,a)), 'left foot rel diff', tuple(round(x-y,3) for x,y in zip(lb,la)))

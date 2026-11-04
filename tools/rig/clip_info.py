import bpy, os, math
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=os.path.join(os.path.dirname(os.path.abspath(__file__)), 'clips', 'Right Turn.fbx'))
arm=[o for o in bpy.data.objects if o.type=='ARMATURE'][0]
act=bpy.data.actions[0]; arm.animation_data.action=act
print('ACT', act.name, act.frame_range[:], 'fps', bpy.context.scene.render.fps)
sc=bpy.context.scene
def p(n): return arm.matrix_world @ arm.pose.bones['mixamorig:'+n].head
r0,r1=int(act.frame_range[0]),int(act.frame_range[1])
for f in list(range(r0,r1+1,max(1,(r1-r0)//14)))+[r1]:
    sc.frame_set(f); bpy.context.view_layer.update()
    h=p('Hips'); L=p('LeftToeBase'); R=p('RightToeBase')
    ang=lambda v: round(math.degrees(math.atan2(v.y-h.y, v.x-h.x)),0)
    line=p('LeftUpLeg')-p('RightUpLeg'); sh=p('LeftArm')-p('RightArm')
    print('F',f,'L',ang(L),round(L.z,2),'R',ang(R),round(R.z,2),'pelvis',round(math.degrees(math.atan2(line.y,line.x))),'shoulders',round(math.degrees(math.atan2(sh.y,sh.x))),'hips',tuple(round(x,2) for x in h[:2]))

import bpy, sys
src, out = sys.argv[-2], sys.argv[-1]
bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
sc.sequence_editor_create()
st = sc.sequence_editor.strips.new_sound("s", src, 1, 1)
sc.frame_start = 1
sc.frame_end = int(st.frame_final_end)
bpy.ops.sound.mixdown(filepath=out, container='WAV', codec='PCM', format='S16', mixrate=44100, accuracy=1024)
print("DONE", out)

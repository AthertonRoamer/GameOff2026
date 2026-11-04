from PIL import Image
src="C:/Users/yello/Documents/GitHub/GameOff2026/tools/rig/out/guard"
a=Image.open(f"{src}/legs_idle_00.png").convert("RGBA"); b=Image.open(f"{src}/legs_turn_00.png").convert("RGBA")
c=Image.open(f"{src}/legs_turn_15.png").convert("RGBA").rotate(96, center=(128,149.2))
sheet=Image.new("RGBA",(256*3,256),(200,200,200,255))
for i,im in enumerate((a,b,c)): sheet.alpha_composite(im,(i*256,0))
sheet.convert("RGB").save("C:/Users/yello/Documents/GitHub/GameOff2026/docs/night_shift/turn_compare.png")

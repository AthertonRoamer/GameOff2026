"""Lays the front views from `FRONT=1 anim.py` out as one picture: a column per role, relaxed on top and with the weapon up below.

    venv\\Scripts\\python.exe front_sheet.py <folder holding <role>/front_idle_00.png ...> <output.png>

Each role was rendered with a camera scaled to its own build (anim.py ROLES 'scale'), so here every picture is scaled back by it and set on the same floor line: the
gunner stands taller than the guard and the ventrat shorter, as in the game.
"""
import os
import sys
from PIL import Image, ImageDraw, ImageFont

ROLES = [  # (anim.py role, name shown, colour, build scale)
    ("guard", "GUARD", "#c9d2da", 1.0),
    ("gunner", "GUNNER", "#ff9a3c", 1.2),
    ("shade", "SHADE", "#b48be0", 1.0),
    ("medic", "MEDIC", "#ff8cc4", 1.0),
    ("electrician", "TECHNICIAN", "#f2e45c", 1.0),
    ("ventrat", "VENTRAT", "#7fa8f5", 0.92),
    ("intruder", "INFILTRATOR", "#ff5a5a", 1.0),
]
POSES = ["front_idle", "front_aim"]
CELL_W, CELL_H = 330, 520
FLOOR = 470  # the floor line inside a cell
BACKGROUND = (26, 31, 39)


def main(folder, output, poses=None):
    poses = poses or POSES
    font = ImageFont.truetype("C:/Windows/Fonts/segoeui.ttf", 22) if os.path.exists("C:/Windows/Fonts/segoeui.ttf") else ImageFont.load_default()
    sheet = Image.new("RGB", (CELL_W * len(ROLES), CELL_H * len(poses) + 50), BACKGROUND)
    draw = ImageDraw.Draw(sheet)
    for col, (role, name, colour, k) in enumerate(ROLES):
        w = draw.textlength(name, font=font)
        draw.text((col * CELL_W + (CELL_W - w) / 2, 14), name, fill=colour, font=font)
        for row, pose in enumerate(poses):
            path = os.path.join(folder, role, pose + "_00.png")
            if not os.path.exists(path):
                continue
            picture = Image.open(path).convert("RGBA")  # 640 x 960, the character's feet 0.435 of the height below the middle
            scale = 0.5 * k  # to the cell: half size, and back to the role's own build
            picture = picture.resize((int(picture.width * scale), int(picture.height * scale)), Image.LANCZOS)
            feet = int(picture.height / 2 + picture.height * 0.435)  # (the camera is on the build's own height / 2.3, so the feet are always this far down)
            x = col * CELL_W + (CELL_W - picture.width) // 2
            y = 50 + row * CELL_H + FLOOR - feet
            sheet.paste(picture, (x, y), picture)
    sheet.save(output)
    print("saved", output, sheet.size)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2], sys.argv[3].split(",") if len(sys.argv) > 3 else None)

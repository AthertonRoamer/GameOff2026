"""Makes the role reveal's portraits from the front views (`FRONT=1 anim.py -- <role> <folder> front_idle`).

    venv\\Scripts\\python.exe portraits.py <folder holding <role>/front_idle_00.png ...> ..\\..\\game\\roles\\portraits

Every portrait is the same size with the same floor line, so the roles keep their own heights on screen (see front_sheet.py).
"""
import os
import sys
from PIL import Image

ROLES = [  # (anim.py role, the game's role file, build scale)
    ("guard", "guard", 1.0),
    ("gunner", "gunner", 1.2),
    ("shade", "shade", 1.0),
    ("medic", "medic", 1.0),
    ("electrician", "technician", 1.0),
    ("ventrat", "ventrat", 0.92),
    ("intruder", "infiltrator", 1.0),
]
CANVAS = (440, 1000)  # in the pixels of a picture scaled back to its build
FLOOR = 985           # the floor line on it
SIZE = (264, 600)     # saved at: twice and more what the reveal shows


def main(folder, out):
    os.makedirs(out, exist_ok=True)
    for role, name, k in ROLES:
        picture = Image.open(os.path.join(folder, role, "front_idle_00.png")).convert("RGBA")
        picture = picture.resize((round(picture.width * k), round(picture.height * k)), Image.LANCZOS)
        feet = int(picture.height / 2 + picture.height * 0.435)
        canvas = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
        canvas.paste(picture, ((CANVAS[0] - picture.width) // 2, FLOOR - feet))
        canvas.resize(SIZE, Image.LANCZOS).save(os.path.join(out, name + ".png"))
        print("saved", name, "top of the figure at", canvas.getbbox()[1], "bottom", canvas.getbbox()[3])


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])

"""Generates the facility's banded light textures (a round lamp light and the flashlight cone). The floors, walls, doors and props are
no longer drawn here: they are 3D pieces photographed from above by night_shift/environment/render/env_render.gd.
Run from the repository root:  py -3 tools/art/make_facility_art.py     Output: night_shift/environment/art/ (light_radial.png, light_cone.png)
The light textures have four flat brightness steps, the same hard banding as the characters' cel shading."""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from pixel_canvas import Canvas

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "night_shift", "environment", "art")


def radial_light(size=256, bands=4):
    c = Canvas(size, size)
    cx = cy = (size - 1) / 2.0
    for y in range(size):
        for x in range(size):
            d = math.hypot(x - cx, y - cy) / (size / 2.0)
            level = 0
            if d < 1.0:
                level = int(255 * (1.0 - math.floor(d * bands) / bands))
            c.set(x, y, (level, level, level, 255))
    return c


def cone_light(width=512, height=256, half_angle=28.0, bands=4):
    """A flashlight beam pointing right from the left-middle edge. Use it with the light's offset set to (width / 2, 0)."""
    c = Canvas(width, height)
    cy = (height - 1) / 2.0
    for y in range(height):
        for x in range(width):
            d = math.hypot(x, y - cy) / width
            ang = abs(math.degrees(math.atan2(y - cy, x + 0.001)))
            level = 0
            if d < 1.0 and ang <= half_angle:
                core = 1.0 if ang <= half_angle * 0.55 else 0.55
                level = int(255 * core * (1.0 - math.floor(d * bands) / bands))
            c.set(x, y, (level, level, level, 255))
    return c


def main():
    os.makedirs(OUT, exist_ok=True)
    radial_light().save(os.path.join(OUT, "light_radial.png"))
    cone_light().save(os.path.join(OUT, "light_cone.png"))
    print("wrote the light textures to", os.path.abspath(OUT))


if __name__ == "__main__":
    main()

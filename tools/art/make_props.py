"""Draws the top-down map furnishing (drums, crates, pallets, racking...) as PNG sprites plus a preview sheet.

Run:  python tools/art/make_props.py <output folder>
Light comes from the top left. Every sprite is tinted toward the game's night navy at the end so it sits with the walls and floors.
Scale: about 220 px to the metre, the same as the guard sprites.
"""
import math
import random
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

S = 3  # supersampling
NAVY = np.array([22.0, 32.0, 60.0])
GRAIN = 0.0  # surface speckle: off, a cel look wants clean bands of tone (1.0 gives the smooth sprites their dirt)


def new(w, h):
    return Image.new("RGBA", (int(w * S), int(h * S)), (0, 0, 0, 0))


def mask_of(img):
    return Image.new("L", img.size, 0)


def lin_grad(size, c1, c2, ang=135.0):
    w, h = size
    ys, xs = np.mgrid[0:h, 0:w].astype(np.float32)
    a = math.radians(ang)
    d = (xs - w / 2) * math.cos(a) + (ys - h / 2) * math.sin(a)
    d = (d - d.min()) / (d.max() - d.min() + 1e-9)
    return np.array(c1, np.float32) * (1 - d)[..., None] + np.array(c2, np.float32) * d[..., None]


def rad_grad(size, centre, radius, c_in, c_out, power=1.0):
    w, h = size
    ys, xs = np.mgrid[0:h, 0:w].astype(np.float32)
    d = np.sqrt((xs - centre[0] * S) ** 2 + (ys - centre[1] * S) ** 2) / (radius * S)
    d = np.clip(d, 0, 1) ** power
    return np.array(c_in, np.float32) * (1 - d)[..., None] + np.array(c_out, np.float32) * d[..., None]


def noise(size, scale, amp, seed=0):
    rng = np.random.RandomState(seed)
    w, h = size
    small = rng.rand(max(2, int(h / scale)), max(2, int(w / scale))).astype(np.float32)
    im = Image.fromarray((small * 255).astype(np.uint8)).resize((w, h), Image.BICUBIC)
    return ((np.asarray(im, np.float32) / 255.0) - 0.5) * 2 * amp


def composite(img, mask, rgb):
    arr = np.zeros((img.size[1], img.size[0], 4), np.uint8)
    arr[..., :3] = np.clip(rgb, 0, 255).astype(np.uint8)
    arr[..., 3] = np.asarray(mask)
    img.alpha_composite(Image.fromarray(arr, "RGBA"))


def shift(mask, dx, dy):
    return ImageChops.offset(mask, int(dx * S), int(dy * S))


def bevel(img, mask, k=2.5, hi=0.45, lo=0.5):
    """Light on the top left edge of a shape, shade on the bottom right."""
    light = ImageChops.subtract(mask, shift(mask, k, k)).filter(ImageFilter.GaussianBlur(S * 0.6))
    dark = ImageChops.subtract(mask, shift(mask, -k, -k)).filter(ImageFilter.GaussianBlur(S * 0.6))
    layer = Image.new("RGBA", img.size, (255, 255, 255, 0))
    layer.putalpha(light.point(lambda v: int(v * hi)))
    img.alpha_composite(layer)
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    layer.putalpha(dark.point(lambda v: int(v * lo)))
    img.alpha_composite(layer)


def shape(img, kind, box, c1, c2, ang=135.0, r=0, bev=2.5, grain=0.0, seed=1, hi=0.45, lo=0.5, rot=0.0):
    """Fill a shape (rect or ellipse; box in px) with a gradient, grain and bevel."""
    grain *= GRAIN
    m = mask_of(img)
    d = ImageDraw.Draw(m)
    b = [v * S for v in box]
    if rot != 0.0:
        cx, cy = (b[0] + b[2]) / 2, (b[1] + b[3]) / 2
        w, h = b[2] - b[0], b[3] - b[1]
        pts = []
        for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
            x, y = sx * w / 2, sy * h / 2
            a = math.radians(rot)
            pts.append((cx + x * math.cos(a) - y * math.sin(a), cy + x * math.sin(a) + y * math.cos(a)))
        d.polygon(pts, fill=255)
    elif kind == "ellipse":
        d.ellipse(b, fill=255)
    else:
        d.rounded_rectangle(b, radius=r * S, fill=255)
    rgb = lin_grad(img.size, c1, c2, ang)
    if grain:
        rgb = rgb + noise(img.size, 3 * S, grain, seed)[..., None] * 255 * 0.5
        rgb = rgb + noise(img.size, 14 * S, grain, seed + 7)[..., None] * 255 * 0.5
    composite(img, m, rgb)
    if bev:
        bevel(img, m, bev, hi, lo)
    return m


def text(img, cx, cy, s, size, colour, rot=0.0, bold=True):
    """Stencil text centred on (cx, cy)."""
    try:
        font = ImageFont.truetype("arialbd.ttf" if bold else "arial.ttf", int(size * S))
    except OSError:
        font = ImageFont.load_default()
    tw = int(ImageDraw.Draw(Image.new("L", (1, 1))).textlength(s, font=font)) + 8
    th = int(size * S * 1.5)
    layer = Image.new("RGBA", (tw, th), (0, 0, 0, 0))
    ImageDraw.Draw(layer).text((4, th * 0.1), s, fill=colour + (235,), font=font)
    if rot:
        layer = layer.rotate(rot, expand=True, resample=Image.BICUBIC)
    img.alpha_composite(layer, (int(cx * S - layer.size[0] / 2), int(cy * S - layer.size[1] / 2)))


def poly(img, pts, fill=None, outline=None, width=1.5):
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(layer).polygon([(x * S, y * S) for x, y in pts], fill=fill, outline=outline, width=int(width * S))
    img.alpha_composite(layer)


def hazard_band(img, box, colour_a=(150, 156, 166), colour_b=(24, 24, 26), step=14):
    """Diagonal warning stripes inside a box."""
    x0, y0, x1, y1 = box
    m = mask_of(img)
    ImageDraw.Draw(m).rectangle([x0 * S, y0 * S, x1 * S, y1 * S], fill=255)
    layer = Image.new("RGBA", img.size, colour_a + (255,))
    d = ImageDraw.Draw(layer)
    k = x0 - (y1 - y0)
    while k < x1 + (y1 - y0):
        d.polygon([(k * S, y1 * S), ((k + step / 2) * S, y1 * S), ((k + step / 2 + (y1 - y0)) * S, y0 * S), ((k + (y1 - y0)) * S, y0 * S)], fill=colour_b + (255,))
        k += step
    layer.putalpha(m)
    img.alpha_composite(layer)


def disc(img, cx, cy, r, c_in, c_out, bev=2.0, power=1.0, hi=0.45, lo=0.5, grain=0.0, seed=1, centre=None):
    m = mask_of(img)
    ImageDraw.Draw(m).ellipse([(cx - r) * S, (cy - r) * S, (cx + r) * S, (cy + r) * S], fill=255)
    grain *= GRAIN
    cc = centre if centre else (cx - r * 0.3, cy - r * 0.3)
    rgb = rad_grad(img.size, cc, r * 1.45, c_in, c_out, power)
    if grain:
        rgb = rgb + noise(img.size, 3 * S, grain, seed)[..., None] * 255 * 0.5
    composite(img, m, rgb)
    if bev:
        bevel(img, m, bev, hi, lo)
    return m


def line(img, pts, width, colour, alpha=255):
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(layer).line([(x * S, y * S) for x, y in pts], fill=colour + (alpha,), width=int(width * S))
    img.alpha_composite(layer)


def dot(img, cx, cy, r, colour, alpha=255):
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(layer).ellipse([(cx - r) * S, (cy - r) * S, (cx + r) * S, (cy + r) * S], fill=colour + (alpha,))
    img.alpha_composite(layer)


def drop_shadow(img, strength=150, offset=(7, 9), blur=7):
    a = img.split()[3]
    sh = shift(a, offset[0], offset[1]).filter(ImageFilter.GaussianBlur(blur * S))
    layer = Image.new("RGBA", img.size, (4, 6, 14, 0))
    layer.putalpha(sh.point(lambda v: int(v * strength / 255)))
    out = Image.new("RGBA", img.size, (0, 0, 0, 0))
    out.alpha_composite(layer)
    out.alpha_composite(img)
    return out


def finish(img, tint=0.2, dim=0.9, shadow=False):
    """Tint to the night palette, add the shadow and bring down to the final size."""
    arr = np.asarray(img, np.float32).copy()
    rgb = arr[..., :3] * (1 - tint) + NAVY * tint
    arr[..., :3] = rgb * dim
    img = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")
    if shadow:
        img = drop_shadow(img)
    return img.resize((img.size[0] // S, img.size[1] // S), Image.LANCZOS)


def rot_image(img, deg):
    return img.rotate(deg, resample=Image.BICUBIC, expand=False)


# ---------------------------------------------------------------- props

def barrel(colour, label=None, size=150, seed=1):
    """A steel drum seen from above: rolled rim, flat lid with two bungs, and the grooves pressed into it."""
    pad = 22
    img = new(size + pad * 2, size + pad * 2)
    c = size / 2 + pad
    r = size / 2
    hi = tuple(min(255, v * 1.28) for v in colour)
    lo = tuple(v * 0.55 for v in colour)
    disc(img, c, c, r, hi, lo, bev=3, power=1.4, grain=0.07, seed=seed)  # outer rolled rim
    disc(img, c + 1.5, c + 1.5, r * 0.88, tuple(v * 0.62 for v in colour), tuple(v * 0.95 for v in colour), bev=0, power=1.0)  # the dark groove inside the rim
    disc(img, c, c, r * 0.82, tuple(min(255, v * 1.15) for v in colour), tuple(v * 0.78 for v in colour), bev=3, power=1.1, grain=0.07, seed=seed + 3)  # lid
    for k, a in ((0.64, 0.5), (0.46, 0.35)):  # grooves
        layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
        ImageDraw.Draw(layer).ellipse([(c - r * k) * S, (c - r * k) * S, (c + r * k) * S, (c + r * k) * S], outline=tuple(int(v * 0.45) for v in colour) + (int(255 * a),), width=int(2.2 * S))
        img.alpha_composite(layer)
        layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
        ImageDraw.Draw(layer).arc([(c - r * k + 2) * S, (c - r * k + 2) * S, (c + r * k + 2) * S, (c + r * k + 2) * S], 200, 290, fill=(255, 255, 255, 70), width=int(1.6 * S))
        img.alpha_composite(layer)
    for ang, rr in ((-38, 0.58), (140, 0.5)):  # bungs: a hexagon plug in a round flange
        bx, by = c + math.cos(math.radians(ang)) * r * rr, c + math.sin(math.radians(ang)) * r * rr
        disc(img, bx, by, r * 0.15, (205, 205, 205), (95, 98, 104), bev=1.5)
        disc(img, bx, by, r * 0.09, (120, 122, 128), (60, 62, 68), bev=1.0)
        dot(img, bx - 1, by - 1, r * 0.03, (210, 210, 215), 200)
    lx, ly = c - r * 0.12, c + r * 0.14
    if label == "flame":  # red drum: a flammable diamond with a flame
        poly(img, [(lx, ly - 24), (lx + 24, ly), (lx, ly + 24), (lx - 24, ly)], fill=(235, 235, 232, 245), outline=(20, 20, 22, 255), width=2)
        poly(img, [(lx, ly - 14), (lx + 9, ly - 1), (lx + 7, ly + 9), (lx, ly + 13), (lx - 7, ly + 9), (lx - 9, ly + 1), (lx - 3, ly - 3), (lx - 2, ly - 9)], fill=(200, 40, 30, 255))
        poly(img, [(lx, ly + 1), (lx + 4, ly + 8), (lx, ly + 11), (lx - 4, ly + 8)], fill=(250, 200, 60, 255))
    elif label == "oil":  # yellow drum: a black band and OIL
        lx, ly = c + r * 0.1, c + r * 0.22
        hazard_band(img, (c - r * 0.5, ly - 22, c + r * 0.5, ly - 10), (150, 156, 166), (24, 24, 26), 9)
        text(img, lx, ly + 6, "OIL", 20, (28, 28, 30))
    elif label == "waste":  # rust drum: a green band and a recycle arrow circle
        disc(img, lx, ly, 17, (236, 236, 230), (190, 190, 184), bev=0.8)
        for k in range(3):
            a0 = k * 120 + 20
            layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
            ImageDraw.Draw(layer).arc([(lx - 11) * S, (ly - 11) * S, (lx + 11) * S, (ly + 11) * S], a0, a0 + 85, fill=(40, 120, 60, 255), width=int(3.4 * S))
            img.alpha_composite(layer)
    elif isinstance(label, tuple):  # the first version's plain diamond
        poly(img, [(lx, ly - 13), (lx + 13, ly), (lx, ly + 13), (lx - 13, ly)], fill=label + (230,))
        poly(img, [(lx, ly - 7), (lx + 7, ly), (lx, ly + 7), (lx - 7, ly)], outline=(20, 20, 20, 230), width=1.6)
    return finish(img)


def plastic_drum(colour=(56, 78, 110), size=150):
    """A blue plastic drum with a steel clamp ring (lug and bolt) round the lid."""
    pad = 22
    img = new(size + pad * 2, size + pad * 2)
    c = size / 2 + pad
    r = size / 2
    disc(img, c, c, r, tuple(min(255, v * 1.3) for v in colour), tuple(v * 0.6 for v in colour), bev=3, power=1.3, grain=0.05)
    for k in (0.9, 0.78):  # the ribs
        layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
        ImageDraw.Draw(layer).ellipse([(c - r * k) * S, (c - r * k) * S, (c + r * k) * S, (c + r * k) * S], outline=(0, 0, 0, 90), width=int(2 * S))
        img.alpha_composite(layer)
    disc(img, c, c, r * 0.8, tuple(min(255, v * 1.2) for v in colour), tuple(v * 0.8 for v in colour), bev=2.5, power=1.1, grain=0.05)
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))  # steel clamp band
    ImageDraw.Draw(layer).ellipse([(c - r * 0.86) * S, (c - r * 0.86) * S, (c + r * 0.86) * S, (c + r * 0.86) * S], outline=(150, 154, 162, 255), width=int(5 * S))
    img.alpha_composite(layer)
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(layer).arc([(c - r * 0.86) * S, (c - r * 0.86) * S, (c + r * 0.86) * S, (c + r * 0.86) * S], 190, 280, fill=(235, 238, 245, 200), width=int(2 * S))
    img.alpha_composite(layer)
    shape(img, "rect", (c + r * 0.76, c - 7, c + r * 0.98, c + 7), (160, 164, 172), (90, 94, 102), bev=1.5, r=2)  # the lug
    dot(img, c + r * 0.87, c, 3.2, (60, 62, 68))
    disc(img, c - r * 0.3, c - r * 0.25, r * 0.16, tuple(v * 0.9 for v in colour), tuple(v * 0.55 for v in colour), bev=1.5)  # screw cap
    disc(img, c - r * 0.3, c - r * 0.25, r * 0.08, (230, 230, 232), (150, 150, 156), bev=0.8)
    disc(img, c + r * 0.25, c + r * 0.3, r * 0.1, tuple(v * 0.9 for v in colour), tuple(v * 0.55 for v in colour), bev=1.2)
    return finish(img)


def wood_crate(size=210, seed=3):
    """A wooden shipping crate: plank top, a frame of battens round it, a diagonal brace and nails."""
    pad = 22
    img = new(size + pad * 2, size + pad * 2)
    rng = random.Random(seed)
    o = pad
    shape(img, "rect", (o, o, o + size, o + size), (120, 84, 52), (96, 64, 38), r=3, bev=3)
    n = 6
    ph = size / n
    for i in range(n):  # planks across the top
        t = rng.uniform(-14, 14)
        base = (150 + t, 106 + t, 66 + t)
        shape(img, "rect", (o + 4, o + i * ph + 2, o + size - 4, o + (i + 1) * ph - 1), base, tuple(v * 0.82 for v in base), ang=90, bev=1.5, grain=0.18, seed=seed + i, r=1)
        for _ in range(3):  # grain streaks
            gy = o + i * ph + rng.uniform(5, ph - 5)
            gx = o + rng.uniform(8, size * 0.5)
            line(img, [(gx, gy), (gx + rng.uniform(30, 90), gy + rng.uniform(-1.2, 1.2))], 1.2, (70, 44, 24), 70)
    bw = 20
    frame = [(o, o, o + size, o + bw), (o, o + size - bw, o + size, o + size), (o, o, o + bw, o + size), (o + size - bw, o, o + size, o + size)]
    for i, f in enumerate(frame):  # battens
        shape(img, "rect", f, (168, 122, 78), (128, 88, 52), ang=45, bev=2.5, grain=0.16, seed=seed + 20 + i, r=2)
    a, b = bw, size - bw  # diagonal brace
    layer = new(size + pad * 2, size + pad * 2)
    m = mask_of(layer)
    ang = math.atan2(1, 1)
    hw = 11
    p0 = (o + a, o + a)
    p1 = (o + b, o + b)
    nx, ny = -math.sin(ang) * hw, math.cos(ang) * hw
    ImageDraw.Draw(m).polygon([((p0[0] + nx) * S, (p0[1] + ny) * S), ((p1[0] + nx) * S, (p1[1] + ny) * S), ((p1[0] - nx) * S, (p1[1] - ny) * S), ((p0[0] - nx) * S, (p0[1] - ny) * S)], fill=255)
    composite(img, m, lin_grad(img.size, (172, 126, 82), (126, 86, 50), 45) + noise(img.size, 3 * S, 0.1, 5)[..., None] * 90)
    bevel(img, m, 2.5)
    for cx, cy in ((o + bw / 2, o + bw / 2), (o + size - bw / 2, o + bw / 2), (o + bw / 2, o + size - bw / 2), (o + size - bw / 2, o + size - bw / 2), (o + size / 2, o + size / 2)):
        dot(img, cx + 1, cy + 1.2, 2.8, (30, 20, 12), 160)
        dot(img, cx, cy, 2.6, (150, 150, 156))
        dot(img, cx - 0.7, cy - 0.7, 1, (240, 240, 245))
    return finish(img)


def cardboard(w=170, h=120, seed=4, tape=True, label=True):
    """A taped cardboard box seen from above: flaps meet along the middle, tape over the seam, a shipping label."""
    pad = 20
    img = new(w + pad * 2, h + pad * 2)
    o = pad
    shape(img, "rect", (o, o, o + w, o + h), (206, 160, 100), (172, 126, 74), r=4, bev=3.2, grain=0.1, seed=seed)
    line(img, [(o + 4, o + h / 2), (o + w - 4, o + h / 2)], 1.8, (110, 76, 38), 170)  # flaps meet
    line(img, [(o + 4, o + h / 2 + 2), (o + w - 4, o + h / 2 + 2)], 1.2, (240, 205, 150), 120)
    for x in (o + 3, o + w - 3):  # flap ends
        line(img, [(x, o + 4), (x, o + h - 4)], 1.2, (120, 82, 44), 90)
    if tape:
        shape(img, "rect", (o + w * 0.4, o, o + w * 0.4 + 24, o + h), (214, 170, 112), (188, 142, 88), ang=0, bev=1.2, r=1, grain=0.05, seed=seed + 5)
        line(img, [(o + w * 0.4 + 5, o + 3), (o + w * 0.4 + 5, o + h - 3)], 1.2, (255, 235, 200), 130)
    if label:
        shape(img, "rect", (o + w * 0.64, o + h * 0.12, o + w * 0.9, o + h * 0.42), (236, 236, 232), (206, 206, 202), r=1, bev=1)
        for i in range(3):
            line(img, [(o + w * 0.67, o + h * (0.19 + i * 0.07)), (o + w * (0.72 + 0.12 * (i % 2 == 0)), o + h * (0.19 + i * 0.07))], 1.4, (50, 50, 60), 190)
    return finish(img)


def box_stack(seed=7):
    """Two boxes, one set on the other a little crooked, so a stack reads as a stack."""
    pad = 10
    base = Image.new("RGBA", (260, 240), (0, 0, 0, 0))
    b1 = cardboard(190, 130, seed=seed)
    b2 = rot_image(cardboard(140, 100, seed=seed + 1, label=False), 9)
    base.alpha_composite(b1, (20, 40))
    base.alpha_composite(b2, (62, 34))
    return base


def pallet(size=210, seed=5, boards=7):
    """A wooden pallet: seven top boards with the stringers showing dark between them, nails at the ends."""
    pad = 22
    img = new(size + pad * 2, size + pad * 2)
    rng = random.Random(seed)
    o = pad
    shape(img, "rect", (o, o, o + size, o + size), (40, 28, 18), (30, 20, 12), bev=0, r=2)
    bh = (size - (boards - 1) * 7) / boards
    for i in range(boards):
        y0 = o + i * (bh + 7)
        t = rng.uniform(-16, 14)
        base = (176 + t, 132 + t, 84 + t)
        shape(img, "rect", (o, y0, o + size, y0 + bh), base, tuple(v * 0.8 for v in base), ang=90, bev=2, r=1, grain=0.2, seed=seed + i)
        for _ in range(3):
            gx = o + rng.uniform(5, size * 0.5)
            gy = y0 + rng.uniform(3, bh - 3)
            line(img, [(gx, gy), (gx + rng.uniform(30, 100), gy + rng.uniform(-1, 1))], 1.1, (92, 62, 34), 80)
        for nx in (o + 16, o + size / 2, o + size - 16):
            dot(img, nx + 0.8, y0 + bh / 2 + 1, 2.3, (30, 20, 12), 150)
            dot(img, nx, y0 + bh / 2, 2.1, (140, 140, 146))
    return finish(img)


def tire(size=150):
    """A tyre lying flat: tread blocks round the edge, the sidewall, and a steel wheel inside."""
    pad = 22
    img = new(size + pad * 2, size + pad * 2)
    c = size / 2 + pad
    r = size / 2
    disc(img, c, c, r, (50, 50, 54), (14, 14, 17), bev=3, power=1.5, grain=0.06)
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    for i in range(44):  # tread blocks
        a = i / 44 * math.tau
        d.line([((c + math.cos(a) * r * 0.9) * S, (c + math.sin(a) * r * 0.9) * S), ((c + math.cos(a) * r * 0.99) * S, (c + math.sin(a) * r * 0.99) * S)], fill=(0, 0, 0, 200), width=int(2.4 * S))
    img.alpha_composite(layer)
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(layer).arc([(c - r * 0.97) * S, (c - r * 0.97) * S, (c + r * 0.97) * S, (c + r * 0.97) * S], 190, 280, fill=(180, 184, 196, 70), width=int(3 * S))
    img.alpha_composite(layer)
    disc(img, c, c, r * 0.68, (36, 36, 40), (20, 20, 23), bev=2, power=1.2)
    disc(img, c, c, r * 0.5, (170, 174, 182), (74, 78, 86), bev=2.5, power=1.1)
    disc(img, c, c, r * 0.36, (126, 130, 138), (58, 62, 70), bev=1.5, power=1.0)
    for i in range(5):  # wheel nuts
        a = i / 5 * math.tau - 1.2
        disc(img, c + math.cos(a) * r * 0.22, c + math.sin(a) * r * 0.22, 4.2, (210, 212, 218), (80, 82, 90), bev=0.8)
    disc(img, c, c, r * 0.1, (200, 202, 208), (90, 92, 98), bev=1)
    return finish(img)


def gas_cylinder(colour=(66, 128, 84), size=70):
    """A gas bottle standing up, so you see its domed shoulder, a collar and the valve with its outlet."""
    pad = 20
    img = new(size + pad * 2, size + pad * 2)
    c = size / 2 + pad
    r = size / 2
    disc(img, c, c, r, tuple(min(255, v * 1.35) for v in colour), tuple(v * 0.5 for v in colour), bev=2.5, power=1.1, centre=(c - r * 0.35, c - r * 0.35))
    disc(img, c, c, r * 0.62, (190, 194, 202), (80, 84, 92), bev=2, power=1.0)  # collar
    disc(img, c, c, r * 0.44, (120, 124, 132), (50, 52, 58), bev=1.5)
    shape(img, "rect", (c - r * 0.3, c - r * 0.72, c + r * 0.3, c - r * 0.3), (176, 178, 184), (90, 92, 100), bev=1.5, r=2)  # valve body
    shape(img, "rect", (c + r * 0.1, c - r * 0.12, c + r * 0.9, c + r * 0.08), (176, 178, 184), (90, 92, 100), bev=1.2, r=2)  # outlet
    disc(img, c, c, r * 0.18, (190, 192, 198), (90, 92, 100), bev=1)
    return finish(img)


def keg(size=130):
    """A steel beer keg: bright, with two rolled rims and a spear fitting in the middle."""
    pad = 22
    img = new(size + pad * 2, size + pad * 2)
    c = size / 2 + pad
    r = size / 2
    disc(img, c, c, r, (214, 218, 226), (84, 88, 98), bev=3, power=1.1, centre=(c - r * 0.35, c - r * 0.35))
    disc(img, c, c, r * 0.9, (110, 114, 124), (60, 64, 72), bev=0, power=1.0)
    disc(img, c, c, r * 0.82, (200, 204, 212), (96, 100, 110), bev=2.5, power=1.1, centre=(c - r * 0.3, c - r * 0.3))
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(layer).ellipse([(c - r * 0.58) * S, (c - r * 0.58) * S, (c + r * 0.58) * S, (c + r * 0.58) * S], outline=(70, 74, 84, 200), width=int(2.4 * S))
    img.alpha_composite(layer)
    disc(img, c, c, r * 0.3, (230, 234, 240), (100, 104, 114), bev=2)
    disc(img, c, c, r * 0.16, (90, 94, 104), (40, 42, 48), bev=1.2)
    return finish(img)


def pallet_jack(seed=9):
    """A hand pallet truck seen from above: two forks, the pump body, and the handle laid back."""
    pad = 20
    w, h = 330, 150
    img = new(w + pad * 2, h + pad * 2)
    o = pad
    for fy in (o + 12, o + h - 52):  # forks
        shape(img, "rect", (o + 90, fy, o + w, fy + 40), (96, 106, 122), (60, 68, 82), ang=90, bev=2.5, r=7, grain=0.06, seed=seed)
        shape(img, "rect", (o + w - 40, fy + 8, o + w - 4, fy + 32), (60, 68, 82), (44, 50, 62), bev=1.5, r=6)
        line(img, [(o + 110, fy + 6), (o + w - 10, fy + 6)], 1.6, (170, 182, 200), 110)
    shape(img, "rect", (o + 76, o + 8, o + 118, o + h - 8), (84, 94, 110), (52, 58, 72), bev=3, r=8, grain=0.08, seed=seed + 1)  # the cross member
    shape(img, "rect", (o + 62, o + h / 2 - 34, o + 104, o + h / 2 + 34), (60, 64, 72), (30, 32, 38), bev=2.5, r=7)  # pump housing
    shape(img, "rect", (o + 6, o + h / 2 - 6, o + 66, o + h / 2 + 6), (92, 96, 106), (50, 54, 62), bev=1.5, r=3)  # the tiller
    shape(img, "rect", (o + 6, o + h / 2 - 28, o + 22, o + h / 2 + 28), (28, 28, 32), (12, 12, 14), bev=1.8, r=6)  # the grip
    dot(img, o + 14, o + h / 2 - 14, 3.2, (200, 40, 40))
    dot(img, o + 14, o + h / 2 + 14, 3.2, (60, 170, 80))
    return finish(img)


def black_tote(w=200, h=140):
    """A black plastic tote with a pair of grab handles at the ends."""
    pad = 20
    img = new(w + pad * 2, h + pad * 2)
    o = pad
    shape(img, "rect", (o, o, o + w, o + h), (58, 60, 66), (26, 27, 31), r=14, bev=3.5, grain=0.05)
    shape(img, "rect", (o + 12, o + 12, o + w - 12, o + h - 12), (40, 42, 47), (22, 23, 27), r=9, bev=2.5)
    for x0 in (o + 4, o + w - 14):
        shape(img, "rect", (x0, o + h * 0.3, x0 + 10, o + h * 0.7), (24, 25, 28), (12, 12, 14), r=4, bev=1.5)
    for i in range(5):  # ribs on the lid
        line(img, [(o + 24 + i * (w - 48) / 4, o + 18), (o + 24 + i * (w - 48) / 4, o + h - 18)], 1.8, (14, 14, 16), 160)
        line(img, [(o + 25 + i * (w - 48) / 4, o + 18), (o + 25 + i * (w - 48) / 4, o + h - 18)], 1.2, (150, 154, 166), 55)
    return finish(img)


def metal_cabinet(w=170, h=110):
    """A steel storage chest (a grey lid with a hazard roundel, side latches)."""
    pad = 20
    img = new(w + pad * 2, h + pad * 2)
    o = pad
    shape(img, "rect", (o, o, o + w, o + h), (110, 118, 130), (62, 68, 80), r=5, bev=3.5, grain=0.06)
    shape(img, "rect", (o + 8, o + 8, o + w - 8, o + h - 8), (96, 104, 116), (66, 72, 84), r=3, bev=2.5)
    for i in range(3):
        line(img, [(o + 16, o + 24 + i * 30), (o + w - 16, o + 24 + i * 30)], 2.2, (40, 44, 54), 150)
        line(img, [(o + 16, o + 25.5 + i * 30), (o + w - 16, o + 25.5 + i * 30)], 1.2, (190, 200, 214), 70)
    disc(img, o + w / 2, o + h / 2, 17, (170, 176, 186), (96, 102, 114), bev=1.5)
    layer = new(w + pad * 2, h + pad * 2)
    ImageDraw.Draw(layer).polygon([((o + w / 2) * S, (o + h / 2 - 10) * S), ((o + w / 2 + 9) * S, (o + h / 2 + 7) * S), ((o + w / 2 - 9) * S, (o + h / 2 + 7) * S)], outline=(30, 30, 30, 255), width=int(2 * S))
    img.alpha_composite(layer)
    for x in (o + 14, o + w - 22):
        shape(img, "rect", (x, o + h - 4, x + 8, o + h + 6), (150, 154, 164), (80, 84, 94), bev=1, r=1)
    return finish(img)


def rack(units=2, seed=11):
    """Steel racking seen from above: blue uprights at the corners, orange beams front and back, boxes sitting on the top shelf."""
    pad = 24
    w, h = 260 * units // 1, 120
    w = 230 * units
    img = new(w + pad * 2, h + pad * 2)
    rng = random.Random(seed)
    o = pad
    shape(img, "rect", (o, o, o + w, o + h), (52, 58, 70), (36, 40, 50), r=2, bev=2)  # decking
    for i in range(units * 8):
        line(img, [(o + 2 + i * (w - 4) / (units * 8), o + 6), (o + 2 + i * (w - 4) / (units * 8), o + h - 6)], 1.2, (24, 26, 32), 120)
    x = o + 14
    boxes = []
    while x < o + w - 70:  # boxes
        bw = rng.uniform(50, 96)
        bh = rng.uniform(54, 92)
        by = o + 14 + rng.uniform(0, h - 28 - bh)
        boxes.append((x, by, min(bw, o + w - 20 - x), bh))
        x += bw + rng.uniform(4, 24)
    for bx, by, bw, bh in boxes:
        shape(img, "rect", (bx, by, bx + bw, by + bh), (208, 162, 102), (170, 124, 72), r=3, bev=2.5, grain=0.1, seed=int(bx), rot=rng.uniform(-3, 3))
        line(img, [(bx + bw * 0.5, by + 3), (bx + bw * 0.5, by + bh - 3)], 1.4, (118, 82, 42), 140)
        shape(img, "rect", (bx + bw * 0.5 - 7, by, bx + bw * 0.5 + 7, by + bh), (216, 172, 114), (188, 144, 90), ang=0, bev=0.8, r=1)
    for yy in (o, o + h - 11):  # orange beams
        shape(img, "rect", (o - 2, yy, o + w + 2, yy + 11), (112, 124, 142), (66, 74, 90), ang=90, bev=2, r=2, grain=0.04)
        line(img, [(o + 2, yy + 3), (o + w - 2, yy + 3)], 1.2, (176, 188, 206), 120)
    for i in range(units + 1):  # blue uprights
        ux = o - 6 + i * (w / units)
        for uy in (o - 6, o + h - 10):
            shape(img, "rect", (ux, uy, ux + 17, uy + 17), (64, 108, 178), (28, 52, 100), bev=2.5, r=2)
            shape(img, "rect", (ux + 4, uy + 4, ux + 13, uy + 13), (30, 56, 106), (18, 34, 70), bev=1, r=1)
            dot(img, ux + 8.5, uy + 8.5, 1.6, (170, 190, 220))
    return finish(img)


def vent_duct(w=300, h=60):
    """A grey sheet-metal duct run with a louvre grille and flanges."""
    pad = 18
    img = new(w + pad * 2, h + pad * 2)
    o = pad
    shape(img, "rect", (o, o, o + w, o + h), (110, 116, 126), (62, 68, 78), ang=90, r=3, bev=3, grain=0.05)
    for x in (o + 4, o + w - 14, o + w * 0.5 - 5):
        shape(img, "rect", (x, o - 3, x + 10, o + h + 3), (140, 146, 156), (78, 84, 94), ang=0, r=1, bev=1.8)
    for i in range(9):
        line(img, [(o + 40 + i * 12, o + 10), (o + 40 + i * 12, o + h - 10)], 2.2, (34, 38, 46), 190)
        line(img, [(o + 41.5 + i * 12, o + 10), (o + 41.5 + i * 12, o + h - 10)], 1.0, (180, 188, 200), 80)
    return finish(img)


def oil_drum_group():
    """Three drums pushed together, the way they are found against a wall."""
    sheet = Image.new("RGBA", (360, 330), (0, 0, 0, 0))
    a = barrel((66, 78, 98), (205, 205, 200), seed=21)
    b = barrel((92, 100, 70), None, seed=22)
    c = barrel((60, 80, 112), None, seed=23)
    sheet.alpha_composite(a, (-10, 10))
    sheet.alpha_composite(b, (116, 0))
    sheet.alpha_composite(c, (60, 140))
    return sheet


# ---------------------------------------------------------------- the first version of the props, kept: the sheet is built from it unless USE_V2
USE_V2 = False
_v1 = {n: globals()[n] for n in ("wood_crate", "cardboard", "gas_cylinder", "rack", "metal_cabinet", "black_tote")}

# ---------------------------------------------------------------- clearer versions (these replace the ones above)

def _wood_planks(img, rng, box, n, vertical=False, seed=0, light=(176, 128, 80), knots=True):
    """Planks with fine grain streaks, a few knots and dark gaps between them."""
    x0, y0, x1, y1 = box
    ph = ((x1 - x0) if vertical else (y1 - y0)) / n
    for i in range(n):
        t = rng.uniform(-12, 12)
        base = tuple(v + t for v in light)
        b = (x0 + i * ph, y0, x0 + (i + 1) * ph - 1.5, y1) if vertical else (x0, y0 + i * ph, x1, y0 + (i + 1) * ph - 1.5)
        shape(img, "rect", b, base, tuple(v * 0.84 for v in base), ang=0 if vertical else 90, bev=1.6, r=1, grain=0.12, seed=seed + i)
        for _ in range(7):  # streaks
            if vertical:
                gx = b[0] + rng.uniform(2, ph - 3)
                gy = rng.uniform(y0 + 3, y1 - 30)
                line(img, [(gx, gy), (gx + rng.uniform(-1, 1), gy + rng.uniform(25, 80))], 0.9, (84, 54, 28), 95)
            else:
                gy = b[1] + rng.uniform(2, ph - 3)
                gx = rng.uniform(x0 + 3, x1 - 30)
                line(img, [(gx, gy), (gx + rng.uniform(25, 80), gy + rng.uniform(-1, 1))], 0.9, (84, 54, 28), 95)
        if knots and rng.random() < 0.5:
            kx, ky = (b[0] + ph / 2, rng.uniform(y0 + 20, y1 - 20)) if vertical else (rng.uniform(x0 + 20, x1 - 20), b[1] + ph / 2)
            dot(img, kx, ky, ph * 0.2, (88, 56, 30), 220)
            dot(img, kx, ky, ph * 0.1, (60, 36, 18), 230)


def wood_crate(size=210, seed=3):
    """A wooden shipping crate: plank top, a batten frame, a diagonal brace, nails and stencilled FRAGILE and arrows."""
    pad = 22
    img = new(size + pad * 2, size + pad * 2)
    rng = random.Random(seed)
    o = pad
    shape(img, "rect", (o, o, o + size, o + size), (60, 40, 24), (40, 26, 14), r=3, bev=3)
    _wood_planks(img, rng, (o + 3, o + 3, o + size - 3, o + size - 3), 6, seed=seed)
    text(img, o + size * 0.34, o + size * 0.8, "FRAGILE", 22, (186, 36, 30))
    text(img, o + size * 0.7, o + size * 0.3, "THIS SIDE", 15, (40, 30, 22))
    text(img, o + size * 0.7, o + size * 0.4, "UP", 15, (40, 30, 22))
    bw = 22
    for i, f in enumerate([(o, o, o + size, o + bw), (o, o + size - bw, o + size, o + size), (o, o, o + bw, o + size), (o + size - bw, o, o + size, o + size)]):
        shape(img, "rect", f, (190, 142, 92), (140, 98, 58), ang=45, bev=3, grain=0.12, seed=seed + 20 + i, r=2)
    hw, ang = 12, math.atan2(1, 1)
    p0, p1 = (o + bw, o + bw), (o + size - bw, o + size - bw)
    nx, ny = -math.sin(ang) * hw, math.cos(ang) * hw
    m = mask_of(img)
    ImageDraw.Draw(m).polygon([((p0[0] + nx) * S, (p0[1] + ny) * S), ((p1[0] + nx) * S, (p1[1] + ny) * S), ((p1[0] - nx) * S, (p1[1] - ny) * S), ((p0[0] - nx) * S, (p0[1] - ny) * S)], fill=255)
    composite(img, m, lin_grad(img.size, (196, 148, 96), (140, 98, 58), 45))
    bevel(img, m, 3, 0.5, 0.6)
    for cx, cy in ((o + bw / 2, o + bw / 2), (o + size - bw / 2, o + bw / 2), (o + bw / 2, o + size - bw / 2), (o + size - bw / 2, o + size - bw / 2), (o + size * 0.3, o + size * 0.3), (o + size * 0.7, o + size * 0.7)):
        dot(img, cx + 1, cy + 1.2, 3, (30, 20, 12), 170)
        dot(img, cx, cy, 2.8, (170, 172, 178))
        dot(img, cx - 0.8, cy - 0.8, 1.1, (250, 250, 252))
    return finish(img)


def cardboard(w=170, h=120, seed=4, tape=True, label=True):
    """A cardboard box: flaps meeting at the middle, brown tape over the seam, a label, an up arrow and a glass symbol."""
    pad = 20
    img = new(w + pad * 2, h + pad * 2)
    o = pad
    shape(img, "rect", (o, o, o + w, o + h), (222, 176, 112), (184, 136, 80), r=4, bev=3.5, grain=0.08, seed=seed)
    line(img, [(o + 3, o + h / 2), (o + w - 3, o + h / 2)], 2.2, (120, 84, 44), 190)
    line(img, [(o + 3, o + h / 2 + 2.2), (o + w - 3, o + h / 2 + 2.2)], 1.3, (250, 220, 170), 140)
    for x in (o + 4, o + w - 4):
        line(img, [(x, o + 5), (x, o + h - 5)], 1.4, (126, 88, 48), 110)
    if tape:
        shape(img, "rect", (o + w * 0.42, o, o + w * 0.42 + 26, o + h), (170, 118, 66), (140, 96, 50), ang=0, bev=1.5, r=1)
        line(img, [(o + w * 0.42 + 5, o + 3), (o + w * 0.42 + 5, o + h - 3)], 1.3, (230, 190, 140), 120)
    if label:
        shape(img, "rect", (o + w * 0.64, o + h * 0.1, o + w * 0.92, o + h * 0.4), (244, 244, 240), (214, 214, 208), r=1, bev=1)
        for i in range(3):
            line(img, [(o + w * 0.67, o + h * (0.17 + i * 0.07)), (o + w * (0.7 + 0.1 * (i % 2 == 0)), o + h * (0.17 + i * 0.07))], 1.4, (40, 40, 50), 210)
        for k in range(12):
            line(img, [(o + w * (0.8 + k * 0.009), o + h * 0.31), (o + w * (0.8 + k * 0.009), o + h * 0.37)], 1 + (k % 3 == 0), (30, 30, 36), 220)  # barcode
        text(img, o + w * 0.16, o + h * 0.2, "â†‘â†‘", 26, (150, 40, 34))
        text(img, o + w * 0.22, o + h * 0.8, "FRAGILE", 14, (150, 40, 34))
    return finish(img)


def gas_cylinder(colour=(66, 128, 84), size=96):
    """A gas bottle standing up: a coloured shoulder dome, a steel collar and a brass valve with a hand wheel and an outlet."""
    pad = 22
    img = new(size + pad * 2, size + pad * 2)
    c = size / 2 + pad
    r = size / 2
    disc(img, c, c, r, tuple(min(255, v * 1.5) for v in colour), tuple(v * 0.42 for v in colour), bev=3, power=1.0, centre=(c - r * 0.4, c - r * 0.4))
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(layer).ellipse([(c - r * 0.8) * S, (c - r * 0.8) * S, (c + r * 0.8) * S, (c + r * 0.8) * S], outline=(0, 0, 0, 60), width=int(2 * S))
    img.alpha_composite(layer)
    disc(img, c, c, r * 0.5, (224, 228, 236), (88, 92, 102), bev=2.5, power=1.0)  # steel collar
    disc(img, c, c, r * 0.36, (150, 154, 164), (60, 64, 72), bev=2)
    shape(img, "rect", (c, c - r * 0.1, c + r * 0.95, c + r * 0.1), (176, 178, 184), (90, 92, 100), ang=90, bev=2, r=3)  # outlet
    shape(img, "rect", (c + r * 0.82, c - r * 0.18, c + r * 0.98, c + r * 0.18), (190, 192, 198), (90, 92, 100), bev=1.5, r=2)
    disc(img, c, c, r * 0.24, (190, 192, 198), (90, 92, 100), bev=1.5)  # valve body
    for a in (0, 90, 180, 270):  # hand wheel spokes
        line(img, [(c, c), (c + math.cos(math.radians(a + 45)) * r * 0.2, c + math.sin(math.radians(a + 45)) * r * 0.2)], 2, (120, 86, 24))
    dot(img, c, c, r * 0.07, (230, 40, 30))
    return finish(img)


def rack(units=2, seed=11):
    """Steel racking from above: wire decking, heavy orange beams, blue uprights with base plates, and stock (boxes, a drum, a crate) on the shelf."""
    pad = 24
    w, h = 250 * units, 136
    img = new(w + pad * 2, h + pad * 2)
    rng = random.Random(seed)
    o = pad
    shape(img, "rect", (o, o, o + w, o + h), (88, 96, 110), (56, 62, 74), r=2, bev=2)
    for i in range(0, w, 9):  # wire decking
        line(img, [(o + i, o + 2), (o + i, o + h - 2)], 1.1, (34, 38, 46), 190)
    for j in range(0, h, 9):
        line(img, [(o + 2, o + j), (o + w - 2, o + j)], 1.1, (34, 38, 46), 190)
    x = o + 22
    k = 0
    while x < o + w - 60:
        kind = rng.choice(["box", "box", "box", "drum", "crate"])
        if kind == "drum":
            rr = rng.uniform(26, 32)
            cy = o + h / 2 + rng.uniform(-8, 8)
            drum_c = rng.choice([(66, 78, 98), (92, 100, 70), (60, 80, 112)])
            dot(img, x + rr + 5, cy + 6, rr, (0, 0, 0), 90)
            disc(img, x + rr, cy, rr, tuple(min(255, v * 1.3) for v in drum_c), tuple(v * 0.55 for v in drum_c), bev=2.5, power=1.3)
            disc(img, x + rr, cy, rr * 0.8, tuple(min(255, v * 1.12) for v in drum_c), tuple(v * 0.8 for v in drum_c), bev=2, power=1.1)
            disc(img, x + rr * 1.3, cy - rr * 0.3, rr * 0.16, (205, 205, 205), (95, 98, 104), bev=1)
            x += rr * 2 + rng.uniform(10, 22)
        else:
            bw, bh = rng.uniform(56, 100), rng.uniform(58, 100)
            by = o + 18 + rng.uniform(0, h - 36 - bh)
            rot = rng.uniform(-3, 3)
            col = ((222, 176, 112), (184, 136, 80)) if kind == "box" else ((190, 142, 92), (140, 98, 58))
            poly(img, [(x + 5, by + 6), (x + bw + 5, by + 6), (x + bw + 5, by + bh + 6), (x + 5, by + bh + 6)], fill=(0, 0, 0, 90))
            shape(img, "rect", (x, by, x + bw, by + bh), col[0], col[1], r=3, bev=3, grain=0.08, seed=int(x), rot=rot)
            if kind == "box":
                line(img, [(x + 4, by + bh / 2), (x + bw - 4, by + bh / 2)], 1.8, (120, 84, 44), 170)
                shape(img, "rect", (x + bw / 2 - 8, by, x + bw / 2 + 8, by + bh), (170, 118, 66), (140, 96, 50), ang=0, bev=1, r=1)
            else:
                for i in range(3):
                    line(img, [(x + 4, by + (i + 1) * bh / 4), (x + bw - 4, by + (i + 1) * bh / 4)], 1.8, (86, 56, 30), 190)
                line(img, [(x + 4, by + 4), (x + bw - 4, by + bh - 4)], 3, (120, 82, 48), 220)
            x += bw + rng.uniform(8, 22)
    for yy in (o - 2, o + h - 12):  # orange beams
        shape(img, "rect", (o - 4, yy, o + w + 4, yy + 14), (112, 124, 142), (66, 74, 90), ang=90, bev=2.5, r=2, grain=0.03)
        line(img, [(o, yy + 3.5), (o + w, yy + 3.5)], 1.6, (176, 188, 206), 170)
        line(img, [(o, yy + 11), (o + w, yy + 11)], 1.2, (90, 40, 10), 150)
    for i in range(units + 1):  # blue uprights
        ux = o - 9 + i * (w / units)
        for uy in (o - 9, o + h - 12):
            shape(img, "rect", (ux, uy, ux + 22, uy + 22), (84, 132, 210), (34, 62, 122), bev=3, r=2)
            shape(img, "rect", (ux + 5, uy + 5, ux + 17, uy + 17), (34, 62, 122), (20, 38, 78), bev=1.5, r=1)
            dot(img, ux + 11, uy + 11, 2.2, (190, 210, 240))
    return finish(img)


def metal_cabinet(w=170, h=110):
    """A steel footlocker: ridged lid, hazard stripes along one edge, two latches and a hasp."""
    pad = 20
    img = new(w + pad * 2, h + pad * 2)
    o = pad
    shape(img, "rect", (o, o, o + w, o + h), (126, 136, 150), (70, 78, 92), r=5, bev=4, grain=0.04)
    shape(img, "rect", (o + 8, o + 8, o + w - 8, o + h - 22), (112, 122, 136), (78, 86, 100), r=3, bev=2.5)
    for i in range(4):
        line(img, [(o + 18, o + 20 + i * 14), (o + w - 18, o + 20 + i * 14)], 2.4, (42, 46, 56), 170)
        line(img, [(o + 18, o + 21.8 + i * 14), (o + w - 18, o + 21.8 + i * 14)], 1.2, (200, 208, 222), 90)
    hazard_band(img, (o + 8, o + h - 18, o + w - 8, o + h - 8))
    for x in (o + w * 0.25, o + w * 0.75):  # latches
        shape(img, "rect", (x - 9, o + h - 30, x + 9, o + h - 18), (210, 214, 222), (110, 116, 128), bev=1.5, r=2)
        dot(img, x, o + h - 24, 2, (50, 54, 62))
    return finish(img)


def black_tote(w=200, h=140):
    """A black plastic tote: a rim, a recessed lid with ribs, handles at both ends and two yellow clips."""
    pad = 20
    img = new(w + pad * 2, h + pad * 2)
    o = pad
    shape(img, "rect", (o, o, o + w, o + h), (84, 88, 98), (36, 38, 44), r=14, bev=4, grain=0.04)
    shape(img, "rect", (o + 12, o + 12, o + w - 12, o + h - 12), (50, 53, 60), (30, 32, 36), r=9, bev=3)
    for i in range(6):
        line(img, [(o + 26 + i * (w - 52) / 5, o + 20), (o + 26 + i * (w - 52) / 5, o + h - 20)], 2, (16, 17, 20), 190)
        line(img, [(o + 27.4 + i * (w - 52) / 5, o + 20), (o + 27.4 + i * (w - 52) / 5, o + h - 20)], 1.2, (170, 176, 190), 70)
    for x0 in (o + 3, o + w - 15):
        shape(img, "rect", (x0, o + h * 0.28, x0 + 12, o + h * 0.72), (22, 23, 26), (10, 10, 12), r=5, bev=2)
    for y in (o + h * 0.18, o + h * 0.82):
        shape(img, "rect", (o + w - 6, y - 8, o + w + 4, y + 8), (150, 156, 168), (80, 86, 98), r=2, bev=1.5)
        shape(img, "rect", (o - 4, y - 8, o + 6, y + 8), (150, 156, 168), (80, 86, 98), r=2, bev=1.5)
    return finish(img)


if not USE_V2:
    globals().update(_v1)


# ---------------------------------------------------------------- the cel look of the characters

INK = np.array([7, 9, 12], np.float32)  # the characters' ink colour (Palette.VOID)
PALETTE_WALL = np.array([42, 49, 61], np.float32)  # Palette.WALL
PROP_SATURATION = 0.92
PROP_VALUE = 0.9
PALETTE_PULL = 0.05
GAME_PPM = 176.0 / 220.0  # the sprites are drawn at 220 px per metre, the cel sheets are 176


def cel(img, ink_px=1, levels=(0.5, 0.8, 1.0, 1.2), cuts=(0.62, 0.9, 1.1), ref_sigma=7):
    """Turn a shaded sprite into the characters' look: hard bands of tone (deep, shade, base, light) instead of smooth gradients, a 1 px ink outline,
    and a soft shadow on the floor. The bands are cut from the sprite's own shading, so the light still comes from the top left."""
    w, h = img.size
    img = img.resize((round(w * GAME_PPM), round(h * GAME_PPM)), Image.LANCZOS)
    a = np.asarray(img, np.float32)
    alpha = a[..., 3] / 255.0
    body = (alpha > 0.5)  # the shadow built into the sprite is dropped: it is redrawn below
    rgb = a[..., :3]
    lum = rgb @ np.array([0.299, 0.587, 0.114], np.float32) + 1e-3
    lum = np.asarray(Image.fromarray(np.clip(lum, 0, 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.0)), np.float32) + 1e-3  # no jagged band edges
    weight = body.astype(np.float32)
    pm = Image.fromarray((weight * 255).astype(np.uint8))
    pl = Image.fromarray(np.clip(lum * weight, 0, 255).astype(np.uint8))
    blur_w = np.asarray(pm.filter(ImageFilter.GaussianBlur(ref_sigma)), np.float32) / 255.0 + 1e-4
    blur_l = np.asarray(pl.filter(ImageFilter.GaussianBlur(ref_sigma)), np.float32) / blur_w  # the local average tone
    ref = np.maximum(blur_l, 1.0)
    ratio = lum / ref
    level = np.where(ratio < cuts[0], levels[0], np.where(ratio < cuts[1], levels[1], np.where(ratio < cuts[2], levels[2], levels[3])))
    out = rgb / lum[..., None] * (ref * level)[..., None]
    # less cartoony, and in the game's palette (game/ui/palette.gd): colours are muted and darkened, then pulled toward the walls' steel
    grey = (out @ np.array([0.299, 0.587, 0.114], np.float32))[..., None]
    out = (grey + (out - grey) * PROP_SATURATION) * PROP_VALUE
    out = out * (1 - PALETTE_PULL) + PALETTE_WALL * PALETTE_PULL
    out = np.clip(out, 0, 255)
    res = np.zeros_like(a)
    res[..., :3] = out
    res[..., 3] = np.where(body, 255, 0)
    body_img = Image.fromarray(res.astype(np.uint8), "RGBA")
    # ink outline: the silhouette grown by ink_px
    sil = Image.fromarray((body * 255).astype(np.uint8))
    grown = sil.filter(ImageFilter.MaxFilter(2 * ink_px + 1))
    ink_only = ImageChops.subtract(grown, sil)
    ink_layer = Image.new("RGBA", img.size, tuple(int(v) for v in INK) + (0,))
    ink_layer.putalpha(grown)
    final = Image.new("RGBA", img.size, (0, 0, 0, 0))
    # soft floor shadow, down and to the right, away from the light
    sh = ImageChops.offset(grown, 5, 7).filter(ImageFilter.GaussianBlur(4))
    shadow = Image.new("RGBA", img.size, (3, 5, 10, 0))
    shadow.putalpha(sh.point(lambda v: int(v * 0.6)))
    final.alpha_composite(shadow)
    final.alpha_composite(ink_layer)
    final.alpha_composite(body_img)
    # the ink also cuts between deep bands and lit ones where the shading steps sharply, as it does between a character's limbs and torso
    return final


# ---------------------------------------------------------------- sheet

def main(out_dir):
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    props = {
        "barrel_red": barrel((66, 78, 98), (205, 205, 200), seed=1),
        "barrel_yellow": barrel((92, 100, 70), None, seed=2),
        "barrel_rust": barrel((122, 84, 60), None, seed=3),
        "barrel_plastic": plastic_drum(),
        "crate_wood": wood_crate(),
        "box_cardboard": cardboard(),
        "box_stack": box_stack(),
        "pallet": pallet(),
        "tire": tire(),
        "gas_cylinder_green": gas_cylinder((84, 98, 70)),
        "gas_cylinder_silver": gas_cylinder((150, 156, 166)),
        "keg": keg(),
        "pallet_jack": pallet_jack(),
        "tote_black": black_tote(),
        "chest_steel": metal_cabinet(),
        "rack_double": rack(2),
        "duct": vent_duct(),
        "drum_group": oil_drum_group(),
    }
    flat = dict(props)
    props = {name: cel(im) for name, im in props.items()}
    for name, im in props.items():
        im.save(out / f"{name}.png")
    for name, im in flat.items():  # the smooth versions, for comparison
        drop_shadow(im.resize((im.size[0] * S, im.size[1] * S))) if False else None
        im.save(out / f"smooth_{name}.png")

    # preview: the props lying on a floor like the game's, plus a guard's silhouette for scale
    W, H = 1700, 1080
    sheet = Image.new("RGBA", (W, H), (34, 36, 31, 255))  # the game's floor (#22241f)
    d = ImageDraw.Draw(sheet)
    for x in range(0, W, 44):
        d.line([(x, 0), (x, H)], fill=(38, 40, 35, 255), width=1)
    for y in range(0, H, 44):
        d.line([(0, y), (W, y)], fill=(38, 40, 35, 255), width=1)
    try:
        font = ImageFont.truetype("arial.ttf", 22)
    except OSError:
        font = ImageFont.load_default()
    layout = [
        ("barrel_red", 40, 30, "Steel drum"), ("barrel_yellow", 230, 30, "Steel drum"), ("barrel_rust", 420, 30, "Old drum"), ("barrel_plastic", 610, 30, "Plastic drum"),
        ("keg", 800, 40, "Keg"), ("tire", 960, 36, "Tyre"), ("gas_cylinder_green", 1140, 50, "Gas bottle"), ("gas_cylinder_silver", 1260, 50, "Gas bottle"),
        ("tote_black", 1400, 50, "Tote"),
        ("crate_wood", 40, 250, "Wooden crate"), ("pallet", 300, 250, "Pallet"), ("box_cardboard", 560, 270, "Cardboard box"), ("box_stack", 780, 250, "Stacked boxes"),
        ("chest_steel", 1060, 270, "Steel chest"), ("duct", 1290, 290, "Air duct"),
        ("rack_double", 40, 560, "Racking with stock"), ("pallet_jack", 580, 560, "Pallet jack"), ("drum_group", 960, 530, "Drums against a wall"),
    ]
    for name, x, y, label in layout:
        im = props[name]
        sheet.alpha_composite(im, (x, y))
        tw = d.textlength(label, font=font)
        d.text((x + (im.size[0] - tw) / 2, y + im.size[1] + 4), label, fill=(150, 168, 205, 255), font=font)
    guard = Image.open(Path(__file__).resolve().parents[2] / "game/player/skin/guard/torso_idle.png").convert("RGBA").crop((60, 90, 190, 185))
    sheet.alpha_composite(guard, (1500, 640))
    d.text((1480, 760), "Guard (for scale)", fill=(150, 168, 205, 255), font=font)
    sheet.convert("RGB").save(out / "_preview_sheet.png")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "props_out")

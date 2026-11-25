"""Draws a contact sheet of every furniture sprite (the front-facing-north ones) on the game's floor colour: python tools/art/furniture_sheet.py <out.png>"""
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ART = Path(__file__).resolve().parents[2] / "game/furniture/art"
names = sorted(p.stem for p in ART.glob("*.png") if not p.stem.endswith(("_e", "_s", "_w")))
cols, cell = 6, 300
rows = (len(names) + cols - 1) // cols
sheet = Image.new("RGBA", (cols * cell, rows * (cell // 2 + 30)), (34, 36, 31, 255))
d = ImageDraw.Draw(sheet)
font = ImageFont.truetype("arial.ttf", 16)
for i, n in enumerate(names):
    im = Image.open(ART / f"{n}.png").convert("RGBA")
    im = im.resize((im.size[0] * 2, im.size[1] * 2), Image.NEAREST) if im.size[0] < 120 else im
    x, y = (i % cols) * cell, (i // cols) * (cell // 2 + 30)
    sheet.alpha_composite(im, (x + (cell - im.size[0]) // 2, y + (cell // 2 - im.size[1]) // 2 + 6))
    d.text((x + 8, y + cell // 2 + 6), n, fill=(150, 168, 205, 255), font=font)
sheet.convert("RGB").save(sys.argv[1])

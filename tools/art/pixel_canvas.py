"""Tiny RGBA pixel canvas that writes PNG files, so the art generators need nothing but the standard library.
Palette A, Backup Power, comes from the Night Shift sprite kit (index page, "Palette A" section)."""
import struct
import zlib

PAL = {
    "void": "#07090c", "shadow": "#0c0e12", "deep": "#151920",
    "floor": "#1a1f27", "tile": "#222833", "wall": "#2a313d", "wall_top": "#3a4352", "metal": "#5a6475",
    "uniform": "#2b3a55", "uniform_light": "#4a5d80",
    "flashlight": "#fff3c4", "backup": "#f2b544", "warm": "#e07b2a",
    "alarm": "#e5484d", "medic": "#c8322f", "item": "#6fd3e8", "night_vision": "#4be38a",
    "text": "#e7e3d8", "muted": "#a9a495", "accent": "#8fb3e0",
}


def rgb(name_or_hex):
    h = PAL.get(name_or_hex, name_or_hex).lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), 255)


class Canvas:
    def __init__(self, width, height, fill=None):
        self.w, self.h = width, height
        self.px = [rgb(fill) if fill else (0, 0, 0, 0)] * (width * height)

    def set(self, x, y, color):
        if 0 <= x < self.w and 0 <= y < self.h:
            self.px[y * self.w + x] = color if isinstance(color, tuple) else rgb(color)

    def get(self, x, y):
        return self.px[y * self.w + x]

    def rect(self, x, y, w, h, color):
        for yy in range(y, y + h):
            for xx in range(x, x + w):
                self.set(xx, yy, color)

    def outline(self, x, y, w, h, color):
        for xx in range(x, x + w):
            self.set(xx, y, color)
            self.set(xx, y + h - 1, color)
        for yy in range(y, y + h):
            self.set(x, yy, color)
            self.set(x + w - 1, yy, color)

    def blit(self, other, ox, oy):
        for yy in range(other.h):
            for xx in range(other.w):
                p = other.px[yy * other.w + xx]
                if p[3] > 0:
                    self.set(ox + xx, oy + yy, p)

    def crop(self, x, y, w, h):
        out = Canvas(w, h)
        for yy in range(h):
            for xx in range(w):
                out.px[yy * w + xx] = self.px[(y + yy) * self.w + (x + xx)]
        return out

    def rotated_cw(self):
        out = Canvas(self.h, self.w)
        for yy in range(self.h):
            for xx in range(self.w):
                out.px[xx * out.w + (self.h - 1 - yy)] = self.px[yy * self.w + xx]
        return out

    def save(self, path):
        raw = bytearray()
        for yy in range(self.h):
            raw.append(0)
            for xx in range(self.w):
                raw.extend(self.px[yy * self.w + xx])

        def chunk(tag, data):
            body = tag + data
            return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

        png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", self.w, self.h, 8, 6, 0, 0, 0))
        png += chunk(b"IDAT", zlib.compress(bytes(raw), 9)) + chunk(b"IEND", b"")
        with open(path, "wb") as f:
            f.write(png)


class Rng:
    """Small deterministic generator so regenerating the art never changes a pixel by accident."""

    def __init__(self, seed):
        self.s = seed & 0x7FFFFFFF or 1

    def next(self):
        self.s = (self.s * 1103515245 + 12345) & 0x7FFFFFFF
        return self.s >> 8

    def below(self, n):
        return self.next() % n

    def chance(self, percent):
        return self.below(100) < percent

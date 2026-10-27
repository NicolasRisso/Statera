"""Generates the Statera app icon (assets/icon/statera.png and statera.ico).

A rounded indigo square with a white balance scale ("statera" is Latin for scales).
Pure Python (no Pillow): shapes are rasterised with 4x4 supersampling.
"""
import math
import os
import struct
import sys
import zlib

SIZE = 256
SS = 4  # supersampling factor per axis


def inside(x, y):
    """Returns (r, g, b, a) in 0..1 for a point in a 0..1 square, or None."""
    # Rounded-square background.
    r = 0.2
    cx = min(max(x, r), 1 - r)
    cy = min(max(y, r), 1 - r)
    if (x - cx) ** 2 + (y - cy) ** 2 > r * r:
        return None
    t = (x + y) / 2  # diagonal gradient #4F5BD5 -> #7C8CFF
    bg = (0x4F + (0x7C - 0x4F) * t, 0x5B + (0x8C - 0x5B) * t, 0xD5 + (0xFF - 0xD5) * t)
    white = False
    # Post, base and beam.
    if abs(x - 0.5) < 0.025 and 0.24 < y < 0.78:
        white = True
    if abs(y - 0.79) < 0.025 and abs(x - 0.5) < 0.17:
        white = True
    if abs(y - 0.30) < 0.022 and abs(x - 0.5) < 0.30:
        white = True
    if (x - 0.5) ** 2 + (y - 0.22) ** 2 < 0.045 ** 2:
        white = True
    # Hanging strings and pans on both sides.
    for px in (0.24, 0.76):
        for side in (-1, 1):
            # String from the beam end down to the pan rim.
            ax, ay, bx, by = px, 0.31, px + side * 0.10, 0.58
            dx, dy = bx - ax, by - ay
            u = ((x - ax) * dx + (y - ay) * dy) / (dx * dx + dy * dy)
            if 0 <= u <= 1:
                qx, qy = ax + u * dx, ay + u * dy
                if math.hypot(x - qx, y - qy) < 0.011:
                    white = True
        # Pan: lower half-disc.
        if y >= 0.58 and (x - px) ** 2 + ((y - 0.58) / 0.7) ** 2 < 0.13 ** 2:
            white = True
    return (1.0, 1.0, 1.0, 1.0) if white else (bg[0] / 255, bg[1] / 255, bg[2] / 255, 1.0)


def render(size):
    rows = []
    for py in range(size):
        row = bytearray([0])  # PNG filter type 0
        for px in range(size):
            acc = [0.0, 0.0, 0.0, 0.0]
            for sy in range(SS):
                for sx in range(SS):
                    c = inside((px + (sx + 0.5) / SS) / size, (py + (sy + 0.5) / SS) / size)
                    if c:
                        for i in range(3):
                            acc[i] += c[i] * c[3]
                        acc[3] += c[3]
            n = SS * SS
            a = acc[3] / n
            rgb = [int(round(255 * acc[i] / acc[3])) if acc[3] else 0 for i in range(3)]
            row += bytes(rgb + [int(round(255 * a))])
        rows.append(bytes(row))
    return b"".join(rows)


def png(size, raw):
    def chunk(kind, data):
        c = struct.pack(">I", len(data)) + kind + data
        return c + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)
    header = struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")


def ico(images):
    """ICO container with PNG-encoded entries (supported since Windows Vista)."""
    out = struct.pack("<HHH", 0, 1, len(images))
    offset = 6 + 16 * len(images)
    body = b""
    for size, data in images:
        s = 0 if size >= 256 else size
        out += struct.pack("<BBBBHHII", s, s, 0, 0, 1, 32, len(data), offset + len(body))
        body += data
    return out + body


def main():
    out_dir = sys.argv[1] if len(sys.argv) > 1 else os.path.join("assets", "icon")
    os.makedirs(out_dir, exist_ok=True)
    images = []
    for size in (256, 48, 32, 16):
        data = png(size, render(size))
        images.append((size, data))
        if size == 256:
            with open(os.path.join(out_dir, "statera.png"), "wb") as f:
                f.write(data)
    with open(os.path.join(out_dir, "statera.ico"), "wb") as f:
        f.write(ico(images))
    print("icon written to", out_dir)


if __name__ == "__main__":
    main()

"""Generate privacy-browser app icons (stdlib only)."""
from __future__ import annotations

import math
import struct
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def _chunk(tag: bytes, data: bytes) -> bytes:
    return struct.pack(">I", len(data)) + tag + data + struct.pack(
        ">I", zlib.crc32(tag + data) & 0xFFFFFFFF
    )


def write_png(path: Path, w: int, h: int, rgba: bytes) -> None:
    raw = b""
    row = w * 4
    for y in range(h):
        raw += b"\x00" + rgba[y * row : (y + 1) * row]
    compressed = zlib.compress(raw, 9)
    png = b"\x89PNG\r\n\x1a\n"
    png += _chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
    png += _chunk(b"IDAT", compressed)
    png += _chunk(b"IEND", b"")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(png)


def lerp(a: float, b: float, t: float) -> float:
    return a + (b - a) * t


def clamp(v: int) -> int:
    return 0 if v < 0 else 255 if v > 255 else v


def point_in_rounded_rect(x: float, y: float, size: float, radius: float) -> float:
    """Return coverage 0..1 for rounded square [0,size)."""
    if x < 0 or y < 0 or x >= size or y >= size:
        return 0.0
    # distance to edge inside
    dx = min(x + 0.5, size - (x + 0.5))
    dy = min(y + 0.5, size - (y + 0.5))
    if dx >= radius or dy >= radius:
        return 1.0
    ox = radius - dx
    oy = radius - dy
    dist = math.hypot(ox, oy)
    if dist <= radius - 0.6:
        return 1.0
    if dist >= radius + 0.6:
        return 0.0
    return max(0.0, min(1.0, (radius + 0.6 - dist) / 1.2))


def in_shield(nx: float, ny: float) -> bool:
    """Normalized 0..1 coords; classic shield silhouette."""
    # outer shield
    if ny < 0.18 or ny > 0.84:
        return False
    if ny <= 0.30:
        # flat top with slight dome
        half = 0.30
        return abs(nx - 0.5) <= half and ny >= 0.18
    if ny <= 0.62:
        half = 0.30
        return abs(nx - 0.5) <= half
    # taper to point
    t = (ny - 0.62) / (0.84 - 0.62)
    half = 0.30 * (1.0 - t)
    return abs(nx - 0.5) <= half + 0.01


def gen_icon(size: int) -> bytes:
    px = bytearray(size * size * 4)
    radius = size * 0.2237  # iOS-ish continuous corner
    for y in range(size):
        for x in range(size):
            a = point_in_rounded_rect(x, y, size, radius)
            t = (x + y) / (2 * max(size - 1, 1))
            # gradient #5AC8FA -> #0A84FF
            cr = int(lerp(0x5A, 0x0A, t))
            cg = int(lerp(0xC8, 0x84, t))
            cb = int(lerp(0xFA, 0xFF, t))

            nx = (x + 0.5) / size
            ny = (y + 0.5) / size
            if a > 0 and in_shield(nx, ny):
                # white shield body
                cr, cg, cb = 255, 255, 255
                # blue check: short stroke + long stroke
                # vertical-ish long bar
                # simplified: small lock circle + body
                # draw a simple padlock silhouette in blue
                # shackle arc
                scx, scy, sr = 0.5, 0.40, 0.09
                dist_c = math.hypot(nx - scx, ny - scy)
                if 0.34 <= ny <= 0.42 and abs(nx - 0.5) <= 0.10:
                    if dist_c >= sr * 0.75 and dist_c <= sr * 1.15 and ny <= scy + 0.02:
                        cr, cg, cb = 0x0A, 0x84, 0xFF
                # lock body
                if 0.42 <= ny <= 0.62 and abs(nx - 0.5) <= 0.12:
                    cr, cg, cb = 0x0A, 0x84, 0xFF
                # keyhole
                if 0.48 <= ny <= 0.56 and abs(nx - 0.5) <= 0.03:
                    cr, cg, cb = 255, 255, 255

            i = (y * size + x) * 4
            px[i] = clamp(cr)
            px[i + 1] = clamp(cg)
            px[i + 2] = clamp(cb)
            px[i + 3] = int(255 * a)
    return bytes(px)


def main() -> None:
    ios_dir = ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
    ios_sizes = {
        "Icon-App-20x20@1x.png": 20,
        "Icon-App-20x20@2x.png": 40,
        "Icon-App-20x20@3x.png": 60,
        "Icon-App-29x29@1x.png": 29,
        "Icon-App-29x29@2x.png": 58,
        "Icon-App-29x29@3x.png": 87,
        "Icon-App-40x40@1x.png": 40,
        "Icon-App-40x40@2x.png": 80,
        "Icon-App-40x40@3x.png": 120,
        "Icon-App-60x60@2x.png": 120,
        "Icon-App-60x60@3x.png": 180,
        "Icon-App-76x76@1x.png": 76,
        "Icon-App-76x76@2x.png": 152,
        "Icon-App-83.5x83.5@2x.png": 167,
        "Icon-App-1024x1024@1x.png": 1024,
    }
    for name, s in ios_sizes.items():
        write_png(ios_dir / name, s, s, gen_icon(s))

    android = {
        "mipmap-mdpi": 48,
        "mipmap-hdpi": 72,
        "mipmap-xhdpi": 96,
        "mipmap-xxhdpi": 144,
        "mipmap-xxxhdpi": 192,
    }
    for folder, s in android.items():
        write_png(
            ROOT / f"android/app/src/main/res/{folder}/ic_launcher.png",
            s,
            s,
            gen_icon(s),
        )
    print("ok icons", len(ios_sizes), "+", len(android))


if __name__ == "__main__":
    main()

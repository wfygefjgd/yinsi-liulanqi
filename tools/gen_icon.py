"""Generate circular ring app icons (stdlib only)."""
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


def clamp(v: int) -> int:
    return 0 if v < 0 else 255 if v > 255 else v


def gen_icon(size: int) -> bytes:
    """Transparent square, soft blue circular ring (iOS will still mask, looks round)."""
    px = bytearray(size * size * 4)
    cx = cy = (size - 1) / 2.0
    outer = size * 0.42
    inner = size * 0.28
    edge = 0.9  # soft anti-alias band in px

    for y in range(size):
        for x in range(size):
            dx = (x + 0.5) - cx
            dy = (y + 0.5) - cy
            d = math.hypot(dx, dy)

            # ring coverage with soft edges
            a = 0.0
            if d <= outer + edge and d >= inner - edge:
                # outer falloff
                if d > outer:
                    a = max(0.0, 1.0 - (d - outer) / edge)
                elif d < inner:
                    a = max(0.0, 1.0 - (inner - d) / edge)
                else:
                    a = 1.0
                # slight thickness highlight
                mid = (inner + outer) / 2.0
                ring_t = 1.0 - abs(d - mid) / max((outer - inner) / 2.0, 1e-6)
                ring_t = max(0.0, min(1.0, ring_t))

                # gradient by angle: cyan -> blue
                ang = (math.atan2(dy, dx) + math.pi) / (2 * math.pi)  # 0..1
                # #5AC8FA -> #0A84FF
                cr = int(0x5A + (0x0A - 0x5A) * ang)
                cg = int(0xC8 + (0x84 - 0xC8) * ang)
                cb = int(0xFA + (0xFF - 0xFA) * ang)
                # brighter on outer rim
                boost = 0.85 + 0.15 * ring_t
                cr = clamp(int(cr * boost))
                cg = clamp(int(cg * boost))
                cb = clamp(int(cb * boost))
            else:
                cr = cg = cb = 0
                a = 0.0

            # subtle center glow (very soft) for depth, still circular
            if d < inner - edge:
                glow = max(0.0, 1.0 - d / max(inner, 1e-6)) * 0.12
                cr, cg, cb = 0x0A, 0x84, 0xFF
                a = glow

            i = (y * size + x) * 4
            px[i] = cr
            px[i + 1] = cg
            px[i + 2] = cb
            px[i + 3] = clamp(int(255 * a))
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
    print("ok circular ring icons")


if __name__ == "__main__":
    main()

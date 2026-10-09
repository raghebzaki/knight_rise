#!/usr/bin/env python3
"""Generates the tray icons under assets/branding/tray/ from splash_mark.png.

macOS: tray_icon_template.png (36x36), a black glyph on transparent taken from
the mark's alpha (template images are tinted by the OS). tray_manager loads the
asset bytes and draws them at 18 pt, so 36 px keeps Retina menu bars sharp.
Windows: tray_icon.ico with 16/24/32/48 px full-colour PNG entries.

Usage: python3 tool/gen_tray_icons.py   (requires Pillow)
"""
import io
import struct
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "assets/branding/splash_mark.png"
OUT = ROOT / "assets/branding/tray"


def square(img: Image.Image, size: int) -> Image.Image:
    """Crops to the visible mark, centres it on a transparent square with ~6% padding."""
    bbox = img.getchannel("A").point(lambda a: 255 if a > 8 else 0).getbbox()
    img = img.crop(bbox)
    side = max(img.size)
    canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    canvas.paste(img, ((side - img.width) // 2, (side - img.height) // 2))
    inner = round(size * 0.88)
    canvas = canvas.resize((inner, inner), Image.LANCZOS)
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    out.paste(canvas, ((size - inner) // 2, (size - inner) // 2))
    return out


def template(img: Image.Image, size: int) -> Image.Image:
    glyph = square(img, size)
    black = Image.new("RGBA", glyph.size, (0, 0, 0, 255))
    black.putalpha(glyph.getchannel("A"))
    return black


def write_ico(frames: list[Image.Image], path: Path) -> None:
    blobs = []
    for f in frames:
        buf = io.BytesIO()
        f.save(buf, "PNG")
        blobs.append(buf.getvalue())
    header = struct.pack("<HHH", 0, 1, len(frames))
    offset = 6 + 16 * len(frames)
    entries = b""
    for f, blob in zip(frames, blobs):
        w = f.width if f.width < 256 else 0
        entries += struct.pack("<BBBBHHII", w, w, 0, 0, 1, 32, len(blob), offset)
        offset += len(blob)
    path.write_bytes(header + entries + b"".join(blobs))


def main() -> None:
    src = Image.open(SRC).convert("RGBA")
    OUT.mkdir(parents=True, exist_ok=True)
    template(src, 36).save(OUT / "tray_icon_template.png")
    write_ico([square(src, s) for s in (16, 24, 32, 48)], OUT / "tray_icon.ico")


if __name__ == "__main__":
    main()

"""Regenerates the branding PNGs in assets/branding/ from the logo artwork.

The source (assets/branding/knight_rise_logo.jpeg) is a mockup photo: the
shield is composited over a blurred desk scene, so it is *extracted*, not
cropped. Steps: the bright rim/helmet/bolt close the shield outline at luma
60 (measured: lower thresholds leak into the laptop edge behind it), the
interior is filled, the cyan halo above the rim is cut along the rim's top
edge, and the bolt above the rim keeps a soft luma-based alpha.

Usage (Pillow, NumPy and SciPy in an isolated venv):
    python3 -m venv /tmp/kr-venv && /tmp/kr-venv/bin/pip install pillow numpy scipy
    /tmp/kr-venv/bin/python -I tool/branding/generate_branding.py
then:
    dart run flutter_launcher_icons
    git checkout ios/Runner.xcodeproj/project.pbxproj
    dart run flutter_native_splash:create
    git checkout ios/Runner/Info.plist
    flutter test --tags golden --update-goldens   # splash goldens
"""
import os
import numpy as np
from PIL import Image, ImageFilter
from scipy import ndimage as ndi

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, 'assets', 'branding')
SRC = os.path.join(OUT, 'knight_rise_logo.jpeg')

# --- 1. Extract the shield ---------------------------------------------

from PIL import Image, ImageFilter
from scipy import ndimage as ndi

img = Image.open(SRC).convert('RGB')
x0, y0, x1, y1 = 1060, 250, 1760, 960
c = np.asarray(img.crop((x0, y0, x1, y1))).astype(np.float32)
r, g, b = c[..., 0], c[..., 1], c[..., 2]
luma = 0.2126 * r + 0.7152 * g + 0.0722 * b
sat = c.max(-1) - c.min(-1)
H, W = luma.shape
yy, xx = np.mgrid[0:H, 0:W]

# 1. Shield body: threshold 60 closes the rim; fill; largest component.
f = ndi.binary_fill_holes(ndi.binary_closing(luma > 60, np.ones((9, 9)), iterations=2))
lab, n = ndi.label(f)
body = lab == (np.argmax(ndi.sum(f, lab, range(1, n + 1))) + 1)

# 2. Rim top edge per column (silver = bright, low saturation), upper half only.
rim = (luma > 130) & (sat < 70) & (yy < H * 0.45)
cols = np.arange(W)
top = np.full(W, np.nan)
for x in cols:
    ys = np.nonzero(rim[:, x])[0]
    if ys.size: top[x] = ys.min()
ok = ~np.isnan(top)
top = np.interp(cols, cols[ok], top[ok])
top = ndi.median_filter(top, size=15)
above = yy < (top[None, :] - 1)

# 3. Bolt above the rim: bright and clearly blue/cyan; soft alpha ramp from luma.
bolt_core = (luma > 115) & (b > r + 40) & above
bolt_core = ndi.binary_opening(bolt_core, np.ones((2, 2)))
lab2, n2 = ndi.label(bolt_core)
if n2:
    bolt_core = lab2 == (np.argmax(ndi.sum(bolt_core, lab2, range(1, n2 + 1))) + 1)
bolt_zone = ndi.binary_dilation(bolt_core, iterations=3) & above
bolt_alpha = np.clip((luma - 70) / 60, 0, 1) * bolt_zone

body_alpha = (body & ~above).astype(np.float32)
body_alpha = np.asarray(Image.fromarray((body_alpha * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.9))) / 255.0
alpha = np.maximum(body_alpha, bolt_alpha)


# --- 2. Generate the PNGs ----------------------------------------------
rgb = c
bolt = bolt_zone & (luma > 90)
BG = (0x0A, 0x10, 0x20)  # KnightPalette.midnight.background
CYAN = np.array([0x33, 0xD6, 0xFF], np.float32)

ys, xs = np.nonzero(alpha > 0.02)
x0, y0, x1, y1 = xs.min(), ys.min(), xs.max() + 1, ys.max() + 1
luma = 0.2126 * rgb[..., 0] + 0.7152 * rgb[..., 1] + 0.0722 * rgb[..., 2]

def layer(a):  # RGBA image of the mark with alpha a (cropped to the mark)
    return Image.fromarray(np.dstack([rgb, a * 255])[y0:y1, x0:x1].astype(np.uint8))

mark = layer(alpha)

# Crest glow: the bolt (plus the helmet's brightest blue), blurred, tinted cyan.
crest = (bolt | ((luma > 140) & (rgb[..., 2] > rgb[..., 0] + 60))).astype(np.float32)
pad = 60
g = np.zeros((crest.shape[0] + 2 * pad, crest.shape[1] + 2 * pad), np.float32); g[pad:-pad, pad:-pad] = crest
gimg = Image.fromarray((g * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(18))
ga = np.asarray(gimg).astype(np.float32) / 255.0
ga = np.clip(ga * 1.6, 0, 1)
glow = np.dstack([np.broadcast_to(CYAN, ga.shape + (3,)), ga * 255])
glow = Image.fromarray(glow[y0:y1 + 2 * pad, x0:x1 + 2 * pad].astype(np.uint8))  # same frame as mark + pad

def place(canvas, img, height, cy=0.5, extra=0, glow_img=None, glow_strength=0.55):
    s = height / img.height
    w, h = round(img.width * s), round(img.height * s)
    cx, cyy = canvas.width // 2, round(canvas.height * cy)
    if glow_img is not None:
        gw, gh = round(glow_img.width * s), round(glow_img.height * s)
        gl = glow_img.resize((gw, gh), Image.LANCZOS)
        a = np.asarray(gl).astype(np.float32); a[..., 3] *= glow_strength
        gl = Image.fromarray(a.astype(np.uint8))
        canvas.alpha_composite(gl, (cx - gw // 2, cyy - gh // 2))
    canvas.alpha_composite(img.resize((w, h), Image.LANCZOS), (cx - w // 2, cyy - h // 2))
    return canvas

def solid(size): return Image.new('RGBA', (size, size), BG + (255,))
def clear(size): return Image.new('RGBA', (size, size), (0, 0, 0, 0))

# Launcher / iOS icon: opaque, mark ~70 % of the height.
place(solid(1024), mark, 700, glow_img=glow).convert('RGB').save(OUT + '/app_icon.png')
# Adaptive foreground: transparent, inside the 66 % safe zone (≈ 600 px tall at 1024).
place(clear(1024), mark, 560, glow_img=glow, glow_strength=0.4).save(OUT + '/app_icon_foreground.png')
# Monochrome (themed icons): white where the mark is bright (rim, helmet, bolt).
mono_a = alpha * np.clip((luma - 55) / 70, 0, 1)
mono = Image.fromarray(np.dstack([np.full(alpha.shape + (3,), 255, np.float32), mono_a * 255])[y0:y1, x0:x1].astype(np.uint8))
place(clear(1024), mono, 560).save(OUT + '/app_icon_monochrome.png')
# Splash centre (pre-Android 12, iOS): opaque, mark ~62 % of the height.
place(solid(1024), mark, 640, glow_img=glow).convert('RGB').save(OUT + '/splash_center.png')
# Android 12+: 1152 canvas, mark inside the central 768 px circle.
place(solid(1152), mark, 560, glow_img=glow).convert('RGB').save(OUT + '/splash_center_android12.png')
# In-app animated splash layers (transparent, native resolution, same frame).
mark.save(OUT + '/splash_mark.png')
glow.save(OUT + '/splash_crest_glow.png')
print('mark', mark.size, 'glow', glow.size, 'pad', pad)

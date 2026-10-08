# Branding

All app branding comes from one source: `knight_rise_logo.jpeg` (a mockup
photo of the logo over a desk scene). The shield is **extracted** from it, not
cropped, by `tool/branding/generate_branding.py` (see its header for the
method and how to run it). Background colour: `#0A0F1D`.

| File | Size | Used for |
| --- | --- | --- |
| `knight_rise_logo.jpeg` | 2816 × 1536 | Source artwork |
| `app_icon.png` | 1024², opaque | iOS icon, Android legacy mipmaps (`flutter_launcher_icons.yaml`) |
| `app_icon_foreground.png` | 1024², transparent | Android adaptive foreground (shield inside the 66 % safe zone; generated with inset 0) |
| `app_icon_monochrome.png` | 1024², transparent | Android 13 themed icon (white, bright parts only, so the helmet stays readable) |
| `splash_center.png` | 1024², opaque | Native splash before Android 12 and on iOS (`flutter_native_splash.yaml`) |
| `splash_center_android12.png` | 1152², opaque | Android 12+ SplashScreen API (shield inside the 768 px circle) |
| `splash_mark.png` | 526 × 618, transparent | In-app `AnimatedSplash` shield (bundled asset) |
| `splash_crest_glow.png` | 646 × 738, transparent | In-app crest glow, same frame as the mark padded by 60 px (bundled asset) |

Only the two `splash_*` layers are bundled in the app (`pubspec.yaml`).

**For the final store release,** ask the designer for the original vector or
a transparent PNG of the logo and re-run the generator from that: the mockup
JPEG is ~520 px tall around the shield, enough for these sizes but with JPEG
softness at 1024 px.

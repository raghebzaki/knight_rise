# Branding artwork (you provide)

Drop these files here, then run the generators (see `docs/RELEASE.md`). All
PNGs are sRGB. Background colour everywhere: Midnight `#0A1020`.

| File | Size | Notes |
| --- | --- | --- |
| `app_icon.png` | 1024 × 1024 | Full icon, opaque, for Android legacy mipmaps and the Play listing (Play needs a 512 × 512 export too). |
| `app_icon_foreground.png` | 1024 × 1024, transparent | Adaptive-icon foreground. Keep the mark inside the centre 66 % (the safe zone); the rest may be masked. |
| `app_icon_monochrome.png` | 1024 × 1024, transparent | Single-colour (white) silhouette of the mark for Android 13 themed icons, same safe zone. |
| `app_icon_ios.png` | 1024 × 1024, opaque | iOS App Store / home screen icon. No transparency, no rounded corners (iOS masks it). |
| `splash_icon.png` | 768 × 768, transparent | Centred on the splash before Android 12 and on iOS; shown at 1/4 size (192 pt). |
| `splash_icon_android12.png` | 1152 × 1152, transparent | Android 12+ splash: content must fit the centre circle of 768 px diameter (2/3). |

Until then the app ships placeholder vectors (a cyan shield) in
`android/app/src/main/res/drawable/` so builds look on-brand.

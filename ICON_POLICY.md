# Icon transparency and platform policy

## User-approved source

`assets/brand/AmitarGalleryPlayer_UserProvided.png` is the exact uploaded 1600×1600 RGBA image. It is preserved byte-for-byte. The transparent outside area and partially transparent edge pixels are part of the file and must not be flattened, cropped, blurred, recolored or filled by the branding generator. The dark navy shapes inside the artwork are opaque pixels already present in the uploaded file; they are intentionally retained because erasing them would alter the supplied design.

## Default color icon outputs

The following outputs are resized from the complete square source canvas and retain the alpha channel: `assets/AmitarGalleryPlayer.png` (exact source copy), `assets/icons/app-icon-1024.png`, `icon-*.png`, `android-adaptive-foreground.png`, `linux-*.png`, the Windows multi-resolution ICO, and the presentation PNG. The app header and About page render the source logo with `BoxFit.contain`; no gradient or shadow tile is placed behind the image.

Android's adaptive background layer (`android-adaptive-background.png`) is fully transparent. Its foreground is the supplied RGBA artwork. The optional Android 13 monochrome icon is a separate luminance/alpha derivative, because themed launcher icons are inherently monochrome; it is not substituted for the color icon.

## iOS store constraint

The ordinary iOS App Store icon must be opaque. `ios-app-store-1024.png` is therefore a separate platform-specific export with a solid navy background (`#070A19`) only in pixels that were transparent in the source. This file is not used as the in-app logo and does not replace the original RGBA image. The `ios-dark-transparent-1024.png` output preserves the supplied transparency for iOS 18+ dark appearance. If Apple changes its submission rules, update this platform-specific export only; never modify the master artwork.

## Poster

The poster itself has a designed background. The transparent artwork is alpha-composited over the poster's glass panel at poster-generation time. That poster backdrop is not part of any icon PNG/ICO.

## Regeneration

```bash
python3 -m pip install -r tool/requirements-branding.txt
python3 tool/generate_brand_assets.py
python3 -m unittest discover -s tool -p 'test_*.py' -v
```

See `README.md`, `README.fa.md` and `VALIDATION_REPORT.md` for the release and validation boundaries.

`presentation/AmitarGalleryPlayer_Icon_Transparency_Preview.png` is only a checkerboard demonstration of the original alpha channel. It is not included in any launcher or store icon configuration.

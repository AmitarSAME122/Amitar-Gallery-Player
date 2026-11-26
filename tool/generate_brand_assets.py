#!/usr/bin/env python3
"""Generate all AmitarGalleryPlayer brand assets from the user-approved source image.

Requirements (tooling only): Pillow with libraqm support and ReportLab.
Run from the repository root:
  python3 tool/generate_brand_assets.py
"""
from __future__ import annotations

import argparse
import sys
import shutil
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont, features
import numpy as np
from reportlab.lib.units import mm
from reportlab.pdfgen import canvas

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets/brand/AmitarGalleryPlayer_UserProvided.png"
ICON_DIR = ROOT / "assets/icons"
PRESENTATION = ROOT / "presentation"
APP_LOGO = ROOT / "assets/AmitarGalleryPlayer.png"

CANVAS = 1024
POSTER_W = 3508  # A3 landscape? no: portrait page width at 300 dpi (297 mm)
POSTER_H = 4961  # A3 portrait page height at 300 dpi (420 mm)
DPI = 300

FA_REG = "/usr/share/fonts/truetype/noto/NotoSansArabic-Regular.ttf"
FA_MED = "/usr/share/fonts/truetype/noto/NotoSansArabic-Medium.ttf"
FA_BOLD = "/usr/share/fonts/truetype/noto/NotoSansArabic-Bold.ttf"
EN_REG = "/usr/share/fonts/truetype/lato/Lato-Regular.ttf"
EN_BOLD = "/usr/share/fonts/truetype/lato/Lato-Bold.ttf"

NAVY = (7, 10, 25)
PANEL = (15, 23, 48)
CYAN = (57, 219, 255)
BLUE = (53, 126, 255)
VIOLET = (132, 91, 255)
MAGENTA = (224, 66, 235)
WHITE = (245, 249, 255)
MUTED = (173, 190, 220)


def require_raqm() -> None:
    if not features.check("raqm"):
        raise RuntimeError(
            "Pillow was built without libraqm. Install Pillow with libraqm/HarfBuzz/FriBidi support "
            "to render correct Persian shaping and right-to-left text."
        )


def font(path: str, size: int) -> ImageFont.FreeTypeFont:
    if not Path(path).is_file():
        raise FileNotFoundError(f"Required font is missing: {path}")
    return ImageFont.truetype(path, size=size, layout_engine=ImageFont.Layout.RAQM)


def make_icon(source: Image.Image, size: int = CANVAS) -> Image.Image:
    """Resize the supplied artwork without cropping, recoloring, compositing or adding a backdrop.

    The source PNG is RGBA. Its transparent pixels and semi-transparent edge pixels
    are part of the approved artwork and must remain transparent in every derived
    color icon. The opaque iOS App Store export is produced separately because
    Apple's store pipeline does not accept alpha-channel app icons.
    """
    rgba = source.convert("RGBA")
    if rgba.width != rgba.height:
        raise ValueError(
            f"The approved app icon must be square; got {rgba.width}x{rgba.height}. "
            "No crop or letterbox is applied automatically."
        )
    if rgba.size == (size, size):
        return rgba.copy()
    return rgba.resize((size, size), Image.Resampling.LANCZOS)


def save_icons(icon: Image.Image, source_path: Path) -> None:
    """Save color icons with original alpha; generate only platform-mandated variants."""
    ICON_DIR.mkdir(parents=True, exist_ok=True)
    PRESENTATION.mkdir(parents=True, exist_ok=True)

    # Preserve the user-provided source image byte-for-byte as the in-app logo.
    if source_path.suffix.lower() == ".png":
        shutil.copyfile(source_path, APP_LOGO)
    else:
        icon.save(APP_LOGO, format="PNG", optimize=True)

    sizes = [16, 32, 48, 64, 128, 192, 256, 512, 1024]
    for size in sizes:
        out = icon.resize((size, size), Image.Resampling.LANCZOS)
        out.save(ICON_DIR / f"icon-{size}.png", optimize=True)
    icon.save(ICON_DIR / "app-icon-1024.png", format="PNG", optimize=True)
    icon.save(PRESENTATION / "AmitarGalleryPlayer_Icon_1024.png", format="PNG", optimize=True)

    # Android adaptive foreground is the exact supplied artwork at launcher size.
    icon.save(ICON_DIR / "android-adaptive-foreground.png", format="PNG", optimize=True)
    # Transparent background layer: Android's launcher mask must not receive a
    # designer-added color, gradient, blur, or shadow behind the supplied image.
    Image.new("RGBA", icon.size, (0, 0, 0, 0)).save(
        ICON_DIR / "android-adaptive-background.png", format="PNG", optimize=True
    )

    # Android 13 themed icon is an optional, platform-specific monochrome variant.
    # It is derived from the supplied image's own alpha and luminance, not from a
    # generated background. The primary color icon remains unchanged.
    rgba = np.asarray(icon.convert("RGBA"), dtype=np.float32)
    rgb = rgba[..., :3]
    source_alpha = rgba[..., 3] / 255.0
    luminance = (0.2126 * rgb[..., 0] + 0.7152 * rgb[..., 1] + 0.0722 * rgb[..., 2]) / 255.0
    mono_alpha = np.clip(source_alpha * np.power(luminance, 0.72), 0.0, 1.0)
    mono = np.empty((icon.height, icon.width, 4), dtype=np.uint8)
    mono[..., :3] = 255
    mono[..., 3] = np.round(mono_alpha * 255).astype(np.uint8)
    Image.fromarray(mono, "RGBA").save(
        ICON_DIR / "android-adaptive-monochrome.png", format="PNG", optimize=True
    )

    # iOS App Store requires an opaque primary app icon. This is a separate,
    # explicitly named platform export; the transparent master remains untouched.
    ios_backdrop = Image.new("RGBA", icon.size, (*NAVY, 255))
    ios_store = Image.alpha_composite(ios_backdrop, icon)
    ios_store.convert("RGB").save(
        ICON_DIR / "ios-app-store-1024.png", format="PNG", optimize=True
    )
    # iOS 18+ dark appearance can use Apple's transparent dark icon asset.
    icon.save(ICON_DIR / "ios-dark-transparent-1024.png", format="PNG", optimize=True)

    for size in (256, 512):
        icon.resize((size, size), Image.Resampling.LANCZOS).save(
            ICON_DIR / f"linux-{size}.png", format="PNG", optimize=True
        )

    ico_sizes = [(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)]
    icon.save(ICON_DIR / "app-icon.ico", format="ICO", sizes=ico_sizes)
    icon.save(PRESENTATION / "AmitarGalleryPlayer_Icon.ico", format="ICO", sizes=ico_sizes)


def save_transparency_preview(icon: Image.Image) -> None:
    """Save a checkerboard proof of alpha; this preview is never used as an app icon."""
    size = 1024
    sample = icon.resize((size, size), Image.Resampling.LANCZOS).convert("RGBA")
    cell = 64
    board = Image.new("RGB", (size, size), (232, 235, 241))
    draw = ImageDraw.Draw(board)
    for y in range(0, size, cell):
        for x in range(0, size, cell):
            if ((x // cell) + (y // cell)) % 2:
                draw.rectangle((x, y, x + cell - 1, y + cell - 1), fill=(190, 198, 211))
    Image.alpha_composite(board.convert("RGBA"), sample).convert("RGB").save(
        PRESENTATION / "AmitarGalleryPlayer_Icon_Transparency_Preview.png",
        format="PNG", optimize=True,
    )


def gradient_background(size: tuple[int, int]) -> Image.Image:
    w, h = size
    top = np.array([6, 10, 25], dtype=np.float32)
    mid = np.array([12, 20, 48], dtype=np.float32)
    bottom = np.array([7, 9, 25], dtype=np.float32)
    ys = np.linspace(0, 1, h, dtype=np.float32)
    data = np.empty((h, w, 3), dtype=np.uint8)
    for y, t in enumerate(ys):
        if t < .56:
            p = t / .56
            c = top * (1 - p) + mid * p
        else:
            p = (t - .56) / .44
            c = mid * (1 - p) + bottom * p
        data[y, :, :] = c.astype(np.uint8)
    img = Image.fromarray(data, "RGB").convert("RGBA")

    # Broad diffused cyan/blue/magenta blooms under all surfaces.
    glow = Image.new("RGBA", size, (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.ellipse((w * .02, h * .03, w * .60, h * .37), fill=(0, 167, 255, 44))
    gd.ellipse((w * .46, h * .16, w * 1.02, h * .60), fill=(142, 46, 255, 46))
    gd.ellipse((w * .20, h * .54, w * .78, h * .98), fill=(10, 107, 255, 36))
    glow = glow.filter(ImageFilter.GaussianBlur(150))
    img = Image.alpha_composite(img, glow)

    # Fine technical grid, intentionally restrained for print clarity.
    grid = Image.new("RGBA", size, (0, 0, 0, 0))
    gd = ImageDraw.Draw(grid)
    step = 116
    for x in range(0, w, step):
        gd.line((x, 0, x, h), fill=(125, 175, 255, 9), width=2)
    for y in range(0, h, step):
        gd.line((0, y, w, y), fill=(125, 175, 255, 8), width=2)
    img = Image.alpha_composite(img, grid)
    return img


def glass_card(img: Image.Image, box: tuple[int, int, int, int], radius: int = 54,
               fill=(18, 31, 62, 176), outline=(107, 163, 255, 120), glow=(30, 146, 255, 60)) -> None:
    """Draw a glass surface using local layers to keep high-DPI rendering efficient."""
    x1, y1, x2, y2 = box
    pad = 64
    left = max(0, x1 - pad)
    top = max(0, y1 - pad)
    right = min(img.width, x2 + pad)
    bottom = min(img.height, y2 + pad)
    local_box = (x1 - left, y1 - top, x2 - left, y2 - top)
    lx1, ly1, lx2, ly2 = local_box
    local_size = (right - left, bottom - top)

    shadow = Image.new("RGBA", local_size, (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    sd.rounded_rectangle((lx1, ly1 + 18, lx2, ly2 + 18), radius=radius, fill=(0, 0, 0, 112))
    shadow = shadow.filter(ImageFilter.GaussianBlur(30))
    img.alpha_composite(shadow, (left, top))

    glow_layer = Image.new("RGBA", local_size, (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow_layer)
    gd.rounded_rectangle(local_box, radius=radius, outline=glow, width=13)
    glow_layer = glow_layer.filter(ImageFilter.GaussianBlur(22))
    img.alpha_composite(glow_layer, (left, top))

    overlay = Image.new("RGBA", local_size, (0, 0, 0, 0))
    od = ImageDraw.Draw(overlay)
    od.rounded_rectangle(local_box, radius=radius, fill=fill, outline=outline, width=3)
    od.line((lx1 + radius, ly1 + 4, lx2 - radius, ly1 + 4), fill=(230, 245, 255, 74), width=3)
    img.alpha_composite(overlay, (left, top))


def fa_text(draw: ImageDraw.ImageDraw, xy: tuple[int, int], text: str, fnt: ImageFont.FreeTypeFont,
            fill=WHITE, anchor="rt", stroke_width=0, stroke_fill=(0, 0, 0, 0)) -> None:
    draw.text(xy, text, font=fnt, fill=fill, anchor=anchor, direction="rtl", language="fa",
              stroke_width=stroke_width, stroke_fill=stroke_fill)


def en_text(draw: ImageDraw.ImageDraw, xy: tuple[int, int], text: str, fnt: ImageFont.FreeTypeFont,
            fill=WHITE, anchor="lt") -> None:
    draw.text(xy, text, font=fnt, fill=fill, anchor=anchor, direction="ltr", language="en")


def draw_pill(img: Image.Image, x: int, y: int, text: str, *, is_fa: bool = True,
              fill=(34, 58, 104, 180), border=(90, 158, 255, 170), text_color=WHITE,
              fnt=None, pad_x=34, height=94) -> int:
    draw = ImageDraw.Draw(img)
    if fnt is None:
        fnt = font(FA_MED if is_fa else EN_BOLD, 39)
    b = draw.textbbox((0, 0), text, font=fnt,
                      direction="rtl" if is_fa else "ltr", language="fa" if is_fa else "en")
    tw = b[2] - b[0]
    width = tw + pad_x * 2
    draw.rounded_rectangle((x, y, x + width, y + height), radius=height // 2,
                           fill=fill, outline=border, width=3)
    anchor = "mt" if is_fa else "mt"
    draw.text((x + width / 2, y + height / 2), text, font=fnt, fill=text_color,
              anchor="mm", direction="rtl" if is_fa else "ltr", language="fa" if is_fa else "en")
    return width


def draw_feature_card(img: Image.Image, box: tuple[int, int, int, int], number: str,
                      title: str, line1: str, line2: str, accent: tuple[int, int, int]) -> None:
    x1, y1, x2, y2 = box
    glass_card(img, box, radius=44, fill=(16, 29, 58, 188), outline=(112, 155, 232, 112),
               glow=(*accent, 42))
    d = ImageDraw.Draw(img)
    # Numeric marker and small illuminated bar; avoid unsupported icon glyphs.
    d.rounded_rectangle((x1 + 40, y1 + 38, x1 + 166, y1 + 164), radius=32,
                        fill=(*accent, 58), outline=(*accent, 200), width=3)
    en_text(d, (x1 + 103, y1 + 72), number, font(EN_BOLD, 48), WHITE, anchor="mt")
    d.rounded_rectangle((x2 - 98, y1 + 62, x2 - 74, y1 + 150), radius=12,
                        fill=(*accent, 230))
    fa_text(d, (x2 - 140, y1 + 48), title, font(FA_BOLD, 55), WHITE)
    fa_text(d, (x2 - 140, y1 + 235), line1, font(FA_REG, 39), MUTED)
    fa_text(d, (x2 - 140, y1 + 305), line2, font(FA_REG, 39), MUTED)


def create_poster(icon: Image.Image, preview_path: Path, poster_path: Path, pdf_path: Path) -> None:
    require_raqm()
    w, h = POSTER_W, POSTER_H
    img = gradient_background((w, h))
    d = ImageDraw.Draw(img)

    # Outer frame.
    d.rounded_rectangle((76, 76, w - 76, h - 76), radius=82,
                        outline=(120, 169, 255, 100), width=4)

    # Header strip.
    logo_small = icon.resize((270, 270), Image.Resampling.LANCZOS)
    img.alpha_composite(logo_small.convert("RGBA"), (142, 120))
    en_text(d, (455, 148), "AmitarGalleryPlayer", font(EN_BOLD, 58), (160, 198, 245))
    en_text(d, (455, 225), "One Library. Every Screen. Every Moment.", font(EN_REG, 42), MUTED)
    draw_pill(img, w - 660, 170, "VERSION 1.0.0", is_fa=False,
              fill=(114, 71, 240, 205), border=(195, 164, 255, 220), fnt=font(EN_BOLD, 37), height=92)

    # Hero surface.
    hero = (130, 500, w - 130, 2045)
    glass_card(img, hero, radius=76, fill=(13, 23, 51, 202), outline=(101, 160, 255, 135),
               glow=(16, 171, 255, 64))
    d = ImageDraw.Draw(img)

    # Large user-approved RGBA artwork; transparent pixels reveal only the poster surface beneath it.
    hero_icon = icon.resize((1310, 1310), Image.Resampling.LANCZOS)
    # Soft glow behind icon.
    glow = Image.new("RGBA", (1450, 1450), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.ellipse((35, 35, 1415, 1415), fill=(17, 112, 255, 80))
    glow = glow.filter(ImageFilter.GaussianBlur(88))
    img.alpha_composite(glow, (125, 555))
    img.alpha_composite(hero_icon.convert("RGBA"), (195, 625))

    # Hero copy at right.
    fa_text(d, (w - 280, 720), "نسخهٔ نخست، انتشار متن‌باز", font(FA_MED, 44), (94, 220, 255))
    fa_text(d, (w - 280, 900), "تمام رسانه‌های شما،", font(FA_BOLD, 110), WHITE)
    fa_text(d, (w - 280, 1050), "در یک تجربهٔ یکپارچه", font(FA_BOLD, 110), WHITE)
    fa_text(d, (w - 280, 1280), "گالری و پخش‌کنندهٔ چندرسانه‌ای", font(FA_MED, 58), (215, 229, 255))
    fa_text(d, (w - 280, 1380), "برای موبایل، دسکتاپ و وب؛ با فارسی به‌عنوان زبان پیش‌فرض.", font(FA_REG, 43), MUTED)

    # Hero badges.
    pill_y = 1560
    widths = []
    x = w - 300
    # Right-to-left row, positions are computed from measured widths.
    badge_specs = [
        ("فارسی", True, (0, 150, 205, 190), (66, 221, 255, 210)),
        ("ENGLISH", False, (44, 76, 160, 190), (104, 164, 255, 210)),
        ("OPEN SOURCE", False, (95, 48, 161, 190), (208, 139, 255, 210)),
    ]
    for label, is_fa, fill, border in badge_specs:
        fnt = font((FA_MED if is_fa else EN_BOLD), 36)
        measured = d.textbbox((0, 0), label, font=fnt,
                              direction="rtl" if is_fa else "ltr", language="fa" if is_fa else "en")
        width = measured[2] - measured[0] + 60
        widths.append((label, width, is_fa, fill, border))
    cursor = w - 270
    for label, width, is_fa, fill, border in widths:
        cursor -= width
        draw_pill(img, cursor, pill_y, label, is_fa=is_fa, fill=fill, border=border,
                  fnt=font((FA_MED if is_fa else EN_BOLD), 36), height=86, pad_x=30)
        cursor -= 26

    # Platform coverage band.
    fa_text(d, (w - 180, 2180), "یک کتابخانه، شش بستر", font(FA_BOLD, 72), WHITE)
    en_text(d, (180, 2210), "CROSS-PLATFORM BY DESIGN", font(EN_BOLD, 34), (130, 190, 255))
    platform_y = 2320
    labels = ["ANDROID", "iOS", "WINDOWS", "macOS", "LINUX", "WEB"]
    gap = 22
    pill_width = (w - 2 * 155 - gap * 5) // 6
    for i, label in enumerate(labels):
        x = 155 + i * (pill_width + gap)
        color = [CYAN, BLUE, VIOLET, MAGENTA, CYAN, BLUE][i]
        d.rounded_rectangle((x, platform_y, x + pill_width, platform_y + 154), radius=34,
                            fill=(24, 43, 82, 178), outline=(*color, 170), width=3)
        d.ellipse((x + 36, platform_y + 58, x + 72, platform_y + 94), fill=(*color, 255))
        en_text(d, (x + 100, platform_y + 48), label, font(EN_BOLD, 40), WHITE)

    # Feature grid: six independent, non-overlapping surfaces.
    fa_text(d, (w - 180, 2630), "ابزارهای اصلی", font(FA_BOLD, 72), WHITE)
    en_text(d, (180, 2670), "BUILT FOR YOUR MEDIA", font(EN_BOLD, 34), (130, 190, 255))
    margin = 155
    gap_x = 46
    card_w = (w - margin * 2 - gap_x * 2) // 3
    card_h = 635
    y1 = 2790
    y2 = 3485
    cards = [
        ("01", "گالری هوشمند", "نمای شبکه‌ای و فهرستی، آلبوم‌ها،", "جست‌وجو، فیلتر و مرتب‌سازی.", CYAN),
        ("02", "پخش‌کنندهٔ چندرسانه‌ای", "کنترل صدا و سرعت، صف مستقل،", "تکرار و تنظیمات زیرنویس.", BLUE),
        ("03", "کتابخانهٔ پایدار", "ذخیره‌سازی محلی، علاقه‌مندی‌ها،", "تاریخچه و مدیریت موارد حذف‌شده.", VIOLET),
        ("04", "فارسی و انگلیسی", "فارسی به‌صورت پیش‌فرض و راست‌چین،", "چیدمان چپ‌چین برای زبان انگلیسی.", MAGENTA),
        ("05", "رابط تطبیقی", "پوستهٔ روشن، تاریک و سیستم؛", "پنل‌های شیشه‌ای و چیدمان واکنش‌گرا.", CYAN),
        ("06", "فرمت‌های رسانه", "خواندن و پخش وابسته به موتور،", "کدک‌ها و قابلیت‌های میزبان.", BLUE),
    ]
    # Position cards right-to-left for Persian reading order.
    for index, (num, title, line1, line2, accent) in enumerate(cards):
        row = index // 3
        col_rtl = index % 3
        x = w - margin - card_w - col_rtl * (card_w + gap_x)
        y = y1 if row == 0 else y2
        draw_feature_card(img, (x, y, x + card_w, y + card_h), num, title, line1, line2, accent)

    # Technology foundation strip.
    tech_y = 4215
    glass_card(img, (145, tech_y, w - 145, tech_y + 370), radius=52,
               fill=(12, 21, 46, 188), outline=(106, 148, 219, 110), glow=(140, 70, 240, 36))
    d = ImageDraw.Draw(img)
    fa_text(d, (w - 220, tech_y + 54), "پایهٔ فنی", font(FA_BOLD, 54), WHITE)
    techs = ["FLUTTER", "MEDIA_KIT", "PHOTO_MANAGER", "HIVE CE"]
    tx = 190
    for i, t in enumerate(techs):
        pillw = draw_pill(img, tx, tech_y + 190, t, is_fa=False,
                          fill=(28, 48, 91, 180), border=(90, 154, 255, 120),
                          fnt=font(EN_BOLD, 31), height=80, pad_x=32)
        tx += pillw + 24

    # Footer: honest platform/media caveat + author/copyright.
    fa_text(d, (w - 165, 4660), "قابلیت‌های رسانه و دسترسی فایل، تابع مجوزها و امکانات سیستم‌عامل و مرورگر میزبان است.",
            font(FA_REG, 34), (163, 183, 216))
    d.line((150, 4785, w - 150, 4785), fill=(117, 154, 219, 100), width=3)
    en_text(d, (165, 4840), "AMITARGALLERYPLAYER  •  OPEN SOURCE  •  VERSION 1.0.0", font(EN_BOLD, 28), (135, 163, 203))
    fa_text(d, (w - 165, 4825), "ساخته‌شده توسط سید امیر محمد امامی", font(FA_MED, 32), (211, 225, 249))

    # Convert to RGB and save a high-resolution print master.
    final = img.convert("RGB")
    preview = final.resize((900, round(900 * h / w)), Image.Resampling.LANCZOS)
    preview.save(preview_path, optimize=False, compress_level=6)
    final.save(poster_path, format="PNG", dpi=(DPI, DPI), optimize=False, compress_level=6)

    # Exact A3 portrait physical page; the image is rasterized at 300 DPI.
    pdf = canvas.Canvas(str(pdf_path), pagesize=(297 * mm, 420 * mm), pageCompression=1)
    pdf.setTitle("AmitarGalleryPlayer 1.0.0 - Persian A3 Release Poster")
    pdf.setAuthor("Seyed Amir Mohammad Emami")
    pdf.setSubject("Open-source cross-platform media gallery and player")
    pdf.drawImage(str(poster_path), 0, 0, width=297 * mm, height=420 * mm, preserveAspectRatio=False, mask="auto")
    pdf.showPage()
    pdf.save()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=SOURCE, help="Approved source logo PNG")
    args = parser.parse_args()
    require_raqm()
    if not args.source.is_file():
        raise FileNotFoundError(f"Approved source image not found: {args.source}")
    if args.source.suffix.lower() != ".png":
        raise ValueError("The approved source image must be a PNG so its alpha channel can be preserved.")
    source = Image.open(args.source).convert("RGBA")

    icon = make_icon(source)
    save_icons(icon, args.source.resolve())
    save_transparency_preview(icon)
    create_poster(
        icon,
        PRESENTATION / "AmitarGalleryPlayer_Poster_FA_Preview.png",
        PRESENTATION / "AmitarGalleryPlayer_Poster_FA_A3_300dpi.png",
        PRESENTATION / "AmitarGalleryPlayer_Poster_FA_A3.pdf",
    )
    print("Brand assets generated from:", args.source)
    print("Icon:", ICON_DIR / "app-icon-1024.png")
    print("Poster:", PRESENTATION / "AmitarGalleryPlayer_Poster_FA_A3.pdf")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, ValueError) as exc:
        print(f"BRANDING GENERATION FAILED: {exc}", file=sys.stderr)
        raise SystemExit(1)

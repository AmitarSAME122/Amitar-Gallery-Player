#!/usr/bin/env python3
"""Verify that each generated Flutter host contains the configured app icon."""
from __future__ import annotations

import argparse
import json
import struct
import xml.etree.ElementTree as ET
import zlib
from pathlib import Path, PurePosixPath

ROOT = Path(__file__).resolve().parents[1]
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"


class IconValidationError(RuntimeError):
    """Raised when a required source or platform icon is absent or invalid."""


def require_file(root: Path, relative: str) -> Path:
    path = root / relative
    if not path.is_file() or path.stat().st_size == 0:
        raise IconValidationError(f"Missing or empty icon resource: {relative}")
    return path


def verify_png(path: Path, label: str) -> tuple[int, int]:
    """Check PNG signature, chunk bounds, CRCs, dimensions and terminal chunks."""
    data = path.read_bytes()
    if len(data) < 45 or data[:8] != PNG_SIGNATURE:
        raise IconValidationError(f"{label} is not a valid PNG: {path}")
    offset = 8
    width = height = 0
    saw_ihdr = saw_idat = saw_iend = False
    while offset + 12 <= len(data):
        length = struct.unpack(">I", data[offset:offset + 4])[0]
        chunk_type = data[offset + 4:offset + 8]
        chunk_end = offset + 12 + length
        if chunk_end > len(data):
            raise IconValidationError(f"{label} contains a truncated PNG chunk: {path}")
        chunk_payload = data[offset + 8:offset + 8 + length]
        expected_crc = struct.unpack(">I", data[offset + 8 + length:chunk_end])[0]
        actual_crc = zlib.crc32(chunk_type + chunk_payload) & 0xFFFFFFFF
        if expected_crc != actual_crc:
            raise IconValidationError(f"{label} contains a PNG CRC mismatch: {path}")
        if not saw_ihdr:
            if chunk_type != b"IHDR" or length != 13:
                raise IconValidationError(f"{label} has no valid leading IHDR chunk: {path}")
            width, height = struct.unpack(">II", chunk_payload[:8])
            saw_ihdr = True
        elif chunk_type == b"IHDR":
            raise IconValidationError(f"{label} contains a duplicate IHDR chunk: {path}")
        if chunk_type == b"IDAT":
            saw_idat = True
        if chunk_type == b"IEND":
            if length != 0:
                raise IconValidationError(f"{label} has an invalid IEND chunk: {path}")
            saw_iend = True
            offset = chunk_end
            break
        offset = chunk_end
    if not (saw_ihdr and saw_idat and saw_iend) or offset != len(data):
        raise IconValidationError(f"{label} is missing required PNG chunks or has trailing data: {path}")
    if width < 1 or height < 1 or width != height:
        raise IconValidationError(f"{label} must be a non-empty square PNG: {path} ({width}x{height})")
    return width, height


def verify_ico(path: Path, label: str) -> set[int]:
    data = path.read_bytes()
    if len(data) < 22:
        raise IconValidationError(f"{label} is too small to be a valid ICO: {path}")
    reserved, image_type, count = struct.unpack("<HHH", data[:6])
    if reserved != 0 or image_type != 1 or count < 1 or len(data) < 6 + count * 16:
        raise IconValidationError(f"{label} has an invalid ICO header: {path}")
    dimensions: set[int] = set()
    for index in range(count):
        entry = data[6 + index * 16:22 + index * 16]
        width = entry[0] or 256
        height = entry[1] or 256
        payload_size, payload_offset = struct.unpack("<II", entry[8:16])
        if width != height or payload_size < 1 or payload_offset < 6 + count * 16 or payload_offset + payload_size > len(data):
            raise IconValidationError(f"{label} contains an invalid image directory entry: {path}")
        dimensions.add(width)
    return dimensions


def verify_asset_catalog(root: Path, relative: str, label: str) -> tuple[int, set[int]]:
    catalog = require_file(root, f"{relative}/Contents.json")
    try:
        data = json.loads(catalog.read_text(encoding="utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise IconValidationError(f"{label} Contents.json is not valid JSON: {error}") from error
    entries = data.get("images")
    if not isinstance(entries, list) or not entries:
        raise IconValidationError(f"{label} icon catalog has no image entries.")
    checked = 0
    dimensions: set[int] = set()
    for entry in entries:
        if not isinstance(entry, dict):
            continue
        filename = entry.get("filename")
        if not filename:
            continue  # Xcode's universal idiom entries may deliberately omit a filename.
        image = require_file(root, f"{relative}/{filename}")
        width, height = verify_png(image, f"{label} icon")
        dimensions.add(width)
        checked += 1
    if checked == 0:
        raise IconValidationError(f"{label} icon catalog does not reference any image files.")
    if 1024 not in dimensions:
        raise IconValidationError(f"{label} icon catalog has no 1024x1024 image for high-resolution distribution.")
    return checked, dimensions


def verify_android_resource(root: Path, reference: str, label: str) -> int:
    """Resolve an Android drawable/mipmap/color reference to a generated resource."""
    if not reference.startswith("@") or "/" not in reference:
        raise IconValidationError(f"{label} uses an unsupported Android resource reference: {reference!r}")
    resource_type, name = reference[1:].split("/", 1)
    if resource_type == "color":
        values_root = root / "android/app/src/main/res"
        for colors_file in values_root.glob("values*/colors.xml"):
            try:
                tree = ET.parse(colors_file)
            except (ET.ParseError, OSError):
                continue
            if any(node.tag == "color" and node.attrib.get("name") == name for node in tree.getroot()):
                return 1
        raise IconValidationError(f"{label} refers to missing Android color resource {reference}.")
    if resource_type not in {"mipmap", "drawable"}:
        raise IconValidationError(f"{label} uses unsupported Android resource type {resource_type!r}.")
    res_root = root / "android/app/src/main/res"
    matches = sorted(
        path for folder in res_root.glob(f"{resource_type}*")
        for path in folder.glob(f"{name}.*") if path.is_file()
    )
    if not matches:
        raise IconValidationError(f"{label} refers to missing Android resource {reference}.")
    for resource in matches:
        if resource.suffix.lower() == ".png":
            verify_png(resource, f"{label} Android layer")
        elif resource.stat().st_size == 0:
            raise IconValidationError(f"{label} references an empty Android resource: {resource}")
    return len(matches)


def verify_platform_icons(root: Path = ROOT) -> dict[str, int]:
    """Validate source assets and generated launcher resources for all six targets."""
    source_pngs = (
        "assets/icons/app-icon-1024.png",
        "assets/icons/ios-app-store-1024.png",
        "assets/icons/ios-dark-transparent-1024.png",
        "assets/icons/android-adaptive-foreground.png",
        "assets/icons/android-adaptive-background.png",
        "assets/icons/android-adaptive-monochrome.png",
        "assets/icons/linux-256.png",
        "assets/icons/linux-512.png",
    )
    for relative in source_pngs:
        verify_png(require_file(root, relative), "Source brand asset")
    verify_ico(require_file(root, "assets/icons/app-icon.ico"), "Source Windows ICO")

    result: dict[str, int] = {}

    # Android legacy density icons and adaptive icon declaration.
    android_res = root / "android/app/src/main/res"
    densities = ("mdpi", "hdpi", "xhdpi", "xxhdpi", "xxxhdpi")
    for density in densities:
        path = android_res / f"mipmap-{density}/ic_launcher.png"
        verify_png(require_file(root, str(path.relative_to(root))), "Android launcher icon")
    manifest_path = require_file(root, "android/app/src/main/AndroidManifest.xml")
    try:
        android_manifest = ET.parse(manifest_path).getroot()
    except (ET.ParseError, OSError) as error:
        raise IconValidationError(f"Android manifest is not valid XML: {error}") from error
    android_ns = "{http://schemas.android.com/apk/res/android}"
    application = android_manifest.find("application")
    if application is None:
        raise IconValidationError("Android manifest has no application element.")
    launcher_reference = application.attrib.get(android_ns + "icon", "")
    if launcher_reference != "@mipmap/ic_launcher":
        raise IconValidationError("Android application icon must reference @mipmap/ic_launcher.")

    adaptive = require_file(root, "android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml")
    try:
        adaptive_root = ET.parse(adaptive).getroot()
    except (ET.ParseError, OSError) as error:
        raise IconValidationError(f"Android adaptive icon is not valid XML: {error}") from error
    if not adaptive_root.tag.endswith("adaptive-icon"):
        raise IconValidationError("Android launcher XML root must be adaptive-icon.")
    layers = {child.tag.rsplit("}", 1)[-1]: child for child in adaptive_root}
    if not {"foreground", "background", "monochrome"}.issubset(layers):
        raise IconValidationError("Android adaptive icon must declare foreground, background and monochrome layers.")
    checked_layers = 0
    for layer_name in ("foreground", "background", "monochrome"):
        reference = layers[layer_name].attrib.get(android_ns + "drawable", "")
        checked_layers += verify_android_resource(root, reference, f"Android {layer_name}")
    result["Android"] = len(densities) + 1 + checked_layers

    # iOS and macOS use Xcode asset catalogs; validate every referenced image.
    ios_count, _ = verify_asset_catalog(
        root, "ios/Runner/Assets.xcassets/AppIcon.appiconset", "iOS"
    )
    macos_count, _ = verify_asset_catalog(
        root, "macos/Runner/Assets.xcassets/AppIcon.appiconset", "macOS"
    )
    result["iOS"] = ios_count
    result["macOS"] = macos_count

    # Windows runner icon is embedded into the executable by the native template.
    windows_icon = require_file(root, "windows/runner/resources/app_icon.ico")
    windows_sizes = verify_ico(windows_icon, "Windows runner icon")
    if 256 not in windows_sizes:
        raise IconValidationError("Windows runner ICO has no 256x256 image frame.")
    result["Windows"] = len(windows_sizes)

    # Linux Flutter runner icon is also copied by bootstrap_platforms.py.
    linux_icon = require_file(root, "linux/runner/resources/app_icon.png")
    verify_png(linux_icon, "Linux runner icon")
    result["Linux"] = 1

    # Web PWA icons are declared in the manifest; verify all references and sizes.
    manifest_path = require_file(root, "web/manifest.json")
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise IconValidationError(f"Web manifest is not valid JSON: {error}") from error
    web_icons = manifest.get("icons")
    if not isinstance(web_icons, list) or not web_icons:
        raise IconValidationError("Web manifest contains no PWA icon declarations.")
    found_sizes: set[str] = set()
    for item in web_icons:
        if not isinstance(item, dict) or not item.get("src"):
            continue
        icon_rel = PurePosixPath(str(item["src"]).replace("\\", "/"))
        if icon_rel.is_absolute() or any(part in {"", ".", ".."} for part in icon_rel.parts):
            raise IconValidationError(f"Web manifest contains an unsafe icon path: {item['src']!r}")
        relative = "web/" + icon_rel.as_posix()
        icon = require_file(root, relative)
        width, height = verify_png(icon, "Web PWA icon")
        size = str(item.get("sizes", ""))
        declared_sizes = set(size.split())
        if f"{width}x{height}" not in declared_sizes and "any" not in declared_sizes:
            raise IconValidationError(
                f"Web icon dimensions ({width}x{height}) do not match manifest sizes {size!r}."
            )
        found_sizes.update(declared_sizes)
    if not any("192x192" in size for size in found_sizes):
        raise IconValidationError("Web PWA manifest has no 192x192 icon.")
    if not any("512x512" in size for size in found_sizes):
        raise IconValidationError("Web PWA manifest has no 512x512 icon.")
    verify_png(require_file(root, "web/favicon.png"), "Web favicon")
    result["Web"] = len(web_icons) + 1

    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT, help="Flutter project root (defaults to this repository).")
    args = parser.parse_args()
    try:
        result = verify_platform_icons(args.root.resolve())
    except (OSError, IconValidationError) as error:
        parser.exit(1, f"ICON VALIDATION FAILED: {error}\n")
    print("All platform launcher icons are present and structurally valid:")
    for platform, count in result.items():
        print(f"  {platform}: {count} checked resources")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

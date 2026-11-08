#!/usr/bin/env python3
"""Validate, build and package AmitarGalleryPlayer for one native host at a time."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import platform
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
import zipfile
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DIST = ROOT / "dist"
ENTRYPOINT = "lib/AmitarGalleryPlayer.dart"
GRADLE_WRAPPER_SHA256 = "ad16bca46cb71bb5887c546860d93992aeee35c1fdaf4a242b0a612375d937e0"
def read_app_version() -> str:
    pubspec = ROOT / "pubspec.yaml"
    match = re.search(r"(?m)^version:\s*['\"]?(\d+\.\d+\.\d+)\+\d+['\"]?\s*$", pubspec.read_text(encoding="utf-8"))
    if not match:
        raise RuntimeError("pubspec.yaml must declare a semantic version with a build number, e.g. 1.0.0+1.")
    return match.group(1)


APP_VERSION = read_app_version()
TARGETS = {"android", "web", "linux", "windows", "macos", "ios"}


def run(command: list[str], *, cwd: Path = ROOT) -> None:
    print("+", " ".join(str(value) for value in command), flush=True)
    subprocess.run([str(value) for value in command], cwd=cwd, check=True)


def verify_zip(path: Path) -> None:
    with zipfile.ZipFile(path) as archive:
        if not archive.infolist():
            raise RuntimeError(f"Archive is empty: {path}")
        damaged = archive.testzip()
        if damaged is not None:
            raise RuntimeError(f"ZIP integrity check failed at {damaged}: {path}")


def zip_tree(source: Path, output: Path, root_name: str) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=8) as archive:
        for path in sorted(source.rglob("*")):
            if path.is_file():
                archive.write(path, Path(root_name) / path.relative_to(source))
    verify_zip(output)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def require_host(target: str) -> None:
    host = platform.system().lower()
    if target == "windows" and host != "windows":
        raise RuntimeError("Windows desktop builds must run on a Windows host with Visual Studio C++ build tools.")
    if target in {"macos", "ios"} and host != "darwin":
        raise RuntimeError(f"{target} builds must run on macOS with Xcode installed.")
    if target == "linux" and host != "linux":
        raise RuntimeError("Linux desktop builds must run on Linux with Flutter's GTK/Clang/CMake/Ninja build dependencies.")


def flutter_build(target: str, *args: str) -> None:
    run(["flutter", "build", target, *args, "--target", ENTRYPOINT])


def create_deb(source: Path) -> Path | None:
    """Create a conventional Debian package when dpkg-deb is available."""
    dpkg_deb = shutil.which("dpkg-deb")
    if not dpkg_deb:
        return None

    machine = platform.machine().lower()
    architecture = {
        "x86_64": "amd64",
        "amd64": "amd64",
        "aarch64": "arm64",
        "arm64": "arm64",
        "i386": "i386",
        "i686": "i386",
    }.get(machine)
    if architecture is None:
        print(f"Skipping .deb: unsupported Debian architecture mapping for {machine!r}.")
        return None

    with tempfile.TemporaryDirectory(prefix="amitar-deb-") as temp_dir:
        package_root = Path(temp_dir) / "package"
        app_root = package_root / "opt/amitar-gallery-player"
        control = package_root / "DEBIAN"
        desktop = package_root / "usr/share/applications"
        icon_256_dir = package_root / "usr/share/icons/hicolor/256x256/apps"
        icon_512_dir = package_root / "usr/share/icons/hicolor/512x512/apps"
        metainfo = package_root / "usr/share/metainfo"
        app_root.mkdir(parents=True)
        control.mkdir(parents=True)
        desktop.mkdir(parents=True)
        icon_256_dir.mkdir(parents=True)
        icon_512_dir.mkdir(parents=True)
        metainfo.mkdir(parents=True)
        shutil.copytree(source, app_root, dirs_exist_ok=True)
        icon_256 = ROOT / "assets/icons/linux-256.png"
        icon_512 = ROOT / "assets/icons/linux-512.png"
        if not icon_256.is_file() or not icon_512.is_file():
            raise FileNotFoundError("Linux DEB requires both assets/icons/linux-256.png and linux-512.png.")
        shutil.copy2(icon_256, icon_256_dir / "amitar-gallery-player.png")
        shutil.copy2(icon_512, icon_512_dir / "amitar-gallery-player.png")
        (desktop / "amitar-gallery-player.desktop").write_text(
            "[Desktop Entry]\n"
            "Version=1.0\n"
            "Type=Application\n"
            "Name=AmitarGalleryPlayer\n"
            "Name[fa]=آمیتار گالری پلیر\n"
            "GenericName=Media Player\n"
            "GenericName[fa]=پخش‌کننده رسانه\n"
            "Comment=Media library, gallery and player\n"
            "Comment[fa]=مدیریت کتابخانه و پخش رسانه\n"
            "Exec=/opt/amitar-gallery-player/amitar_gallery_player\n"
            "Icon=amitar-gallery-player\n"
            "Terminal=false\n"
            "StartupWMClass=amitar_gallery_player\n"
            "Categories=AudioVideo;Player;Audio;Video;\n",
            encoding="utf-8",
        )
        (metainfo / "com.amitar.AmitarGalleryPlayer.metainfo.xml").write_text(
            "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
            "<component type=\"desktop-application\">\n"
            "  <id>com.amitar.AmitarGalleryPlayer</id>\n"
            "  <name>AmitarGalleryPlayer</name>\n"
            "  <summary>Cross-platform media gallery and player</summary>\n"
            "  <metadata_license>CC0-1.0</metadata_license>\n"
            "  <project_license>MIT</project_license>\n"
            "  <description><p>Manage and play authorized photos, videos and audio files.</p></description>\n"
            "  <launchable type=\"desktop-id\">amitar-gallery-player.desktop</launchable>\n"
            "</component>\n",
            encoding="utf-8",
        )
        (control / "control").write_text(
            "Package: amitar-gallery-player\n"
            f"Version: {APP_VERSION}\n"
            f"Architecture: {architecture}\n"
            "Section: sound\n"
            "Priority: optional\n"
            "Maintainer: AmitarGalleryPlayer Maintainers\n"
            "Depends: libgtk-3-0 | libgtk-3-0t64, libmpv2 | libmpv1\n"
            "Description: Cross-platform media library, gallery and player\n"
            " A media organizer and playback application built with Flutter.\n",
            encoding="utf-8",
        )
        output = DIST / f"AmitarGalleryPlayer-Linux-{architecture}.deb"
        run([dpkg_deb, "--build", "--root-owner-group", str(package_root), str(output)])
    if not output.is_file() or output.stat().st_size <= 0:
        raise RuntimeError("dpkg-deb did not produce a non-empty package.")
    return output


def windows_installer(source: Path) -> Path | None:
    compiler = shutil.which("ISCC") or shutil.which("iscc")
    if compiler is None:
        fallback = Path(r"C:\Program Files (x86)\Inno Setup 6\ISCC.exe")
        if fallback.is_file():
            compiler = str(fallback)
    if compiler is None:
        print("Inno Setup not found; the verified portable Windows ZIP will still be produced.")
        return None
    output = DIST / "AmitarGalleryPlayer-Setup-Windows.exe"
    script = ROOT / "tool/installer/AmitarGalleryPlayer.iss"
    run([
        compiler,
        f'/DBuildRoot="{source}"',
        f'/DAppVersion="{APP_VERSION}"',
        f'/DOutputDir="{DIST}"',
        f'/DProjectRoot="{ROOT}"',
        str(script),
    ])
    if not output.is_file() or output.stat().st_size <= 0:
        raise RuntimeError("Inno Setup completed without producing the Windows installer.")
    return output


def extract_flutter_android_java_major(doctor_output: str) -> int | None:
    """Return the Java major version reported by `flutter doctor -v`."""
    for line in doctor_output.splitlines():
        if "Java version" not in line:
            continue
        match = re.search(r"\b(?:build\s+)?(\d+)\.\d+", line, flags=re.IGNORECASE)
        if match:
            return int(match.group(1))
    return None


def verify_android_java_runtime() -> None:
    """Fail early with an actionable message when Flutter selects the wrong JDK."""
    result = subprocess.run(
        ["flutter", "doctor", "-v"],
        cwd=ROOT,
        check=False,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    output = f"{result.stdout or ''}\n{result.stderr or ''}"
    major = extract_flutter_android_java_major(output)
    if major is None:
        raise RuntimeError(
            "Could not determine the Java runtime selected by Flutter. Run `flutter doctor -v` "
            "and confirm that the Android toolchain reports Java 17."
        )
    if major != 17:
        raise RuntimeError(
            f"Flutter is using Java {major}, but this project pins Android Gradle Plugin 8.13.2 "
            "and Gradle 8.14.6 to JDK 17. On Windows run "
            "`tool\\setup_android_jdk_windows.bat -InstallIfMissing`; then verify with "
            "`flutter doctor -v`. Do not upgrade Gradle to 9.x just to run Java 25 without "
            "migrating and testing the complete Flutter/AGP/Kotlin plugin stack."
        )
    if result.returncode != 0:
        print(
            "WARNING: `flutter doctor -v` reported other environment issues; Java 17 was detected. "
            "Review the doctor output before building.",
            file=sys.stderr,
        )


def verify_android_gradle_wrapper() -> None:
    wrapper = ROOT / "android/gradle/wrapper/gradle-wrapper.jar"
    if not wrapper.is_file():
        raise RuntimeError(
            "The verified Gradle Wrapper JAR is missing. Run "
            "`python tool/bootstrap_platforms.py` before an Android build."
        )
    actual = sha256(wrapper)
    if actual != GRADLE_WRAPPER_SHA256:
        raise RuntimeError(
            "Gradle Wrapper JAR SHA-256 mismatch. Run "
            "`python tool/bootstrap_platforms.py` to fetch and verify the official Gradle 8.14.6 wrapper."
        )


def build_target(target: str) -> list[Path]:
    require_host(target)
    if target == "android":
        verify_android_java_runtime()
        verify_android_gradle_wrapper()
        flutter_build("apk", "--release", "--split-per-abi")
        flutter_build("appbundle", "--release")
        apk_dir = ROOT / "build/app/outputs/flutter-apk"
        aab_dir = ROOT / "build/app/outputs/bundle/release"
        outputs = sorted(apk_dir.glob("*.apk")) + sorted(aab_dir.glob("*.aab"))
        apks = sorted(apk_dir.glob("*.apk"))
        if not apks or not aab_dir.is_dir() or not sorted(aab_dir.glob("*.aab")):
            raise FileNotFoundError("Android build did not produce at least one APK and one AAB.")
        direct: list[Path] = []
        for item in outputs:
            destination = DIST / item.name
            shutil.copy2(item, destination)
            direct.append(destination)
        archive = DIST / "AmitarGalleryPlayer-Android-packages.zip"
        with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED, compresslevel=8) as bundle:
            for item in direct:
                bundle.write(item, Path("Android") / item.name)
        verify_zip(archive)
        return [*direct, archive]

    if target == "web":
        flutter_build("web", "--release")
        source = ROOT / "build/web"
        if not (source / "index.html").is_file():
            raise FileNotFoundError("Web build did not produce build/web/index.html.")
        output = DIST / "AmitarGalleryPlayer-Web.zip"
        zip_tree(source, output, "AmitarGalleryPlayer-Web")
        return [output]

    if target == "linux":
        flutter_build("linux", "--release")
        candidates = [ROOT / "build/linux/x64/release/bundle", ROOT / "build/linux/arm64/release/bundle"]
        source = next((item for item in candidates if item.is_dir()), None)
        if source is None or not any(source.iterdir()):
            raise FileNotFoundError("Linux release bundle was not found or is empty under build/linux.")
        architecture = source.parent.parent.name
        tar_output = DIST / f"AmitarGalleryPlayer-Linux-{architecture}.tar.gz"
        with tarfile.open(tar_output, "w:gz") as archive:
            archive.add(source, arcname="AmitarGalleryPlayer")
        with tarfile.open(tar_output, "r:gz") as archive:
            members = archive.getmembers()
            if not members or not any(item.isfile() for item in members):
                raise RuntimeError(f"Linux tarball is empty or contains no files: {tar_output}")
        deb_output = create_deb(source)
        return [tar_output, *([deb_output] if deb_output else [])]

    if target == "windows":
        flutter_build("windows", "--release")
        candidates = [
            ROOT / "build/windows/x64/runner/Release",
            ROOT / "build/windows/runner/Release",
            ROOT / "build/windows/arm64/runner/Release",
        ]
        source = next((item for item in candidates if item.is_dir()), None)
        if source is None or not any(source.iterdir()):
            raise FileNotFoundError("Windows release folder was not found or is empty.")
        portable = DIST / "AmitarGalleryPlayer-Windows-portable.zip"
        zip_tree(source, portable, "AmitarGalleryPlayer")
        installer = windows_installer(source)
        return [portable, *([installer] if installer else [])]

    if target in {"macos", "ios"}:
        if target == "macos":
            flutter_build("macos", "--release")
            search_root = ROOT / "build/macos/Build/Products/Release"
            label = "macOS-unsigned"
        else:
            export_options = os.environ.get("AMITAR_IOS_EXPORT_OPTIONS_PLIST", "").strip()
            if export_options:
                export_plist = Path(export_options).expanduser()
                if not export_plist.is_absolute():
                    export_plist = ROOT / export_plist
                if not export_plist.is_file():
                    raise FileNotFoundError(
                        "AMITAR_IOS_EXPORT_OPTIONS_PLIST points to a missing file: "
                        f"{export_plist}"
                    )
                flutter_build(
                    "ipa", "--release", f"--export-options-plist={export_plist}"
                )
                ipa_files = sorted((ROOT / "build/ios/ipa").glob("*.ipa"))
                if not ipa_files:
                    raise FileNotFoundError(
                        "Signed iOS build completed without producing build/ios/ipa/*.ipa. "
                        "Check Xcode signing identities, provisioning profiles and export options."
                    )
                outputs: list[Path] = []
                for ipa in ipa_files:
                    destination = DIST / ipa.name
                    shutil.copy2(ipa, destination)
                    verify_zip(destination)
                    outputs.append(destination)
                return outputs
            flutter_build("ios", "--release", "--no-codesign")
            search_root = ROOT / "build/ios/iphoneos"
            label = "iOS-unsigned"
        apps = sorted(search_root.glob("*.app")) if search_root.exists() else []
        if not apps:
            raise FileNotFoundError(f"{label} .app bundle not found under {search_root}.")
        if shutil.which("ditto") is None:
            raise RuntimeError("The macOS ditto utility is required to package Apple .app bundles.")
        outputs: list[Path] = []
        for app in apps:
            zip_output = DIST / f"AmitarGalleryPlayer-{label}.zip"
            run(["ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", str(app), str(zip_output)])
            verify_zip(zip_output)
            outputs.append(zip_output)
            if target == "macos":
                dmg_output = DIST / "AmitarGalleryPlayer-macOS-unsigned.dmg"
                run([
                    "hdiutil", "create", "-volname", "AmitarGalleryPlayer",
                    "-srcfolder", str(app), "-ov", "-format", "UDZO", str(dmg_output),
                ])
                if not dmg_output.is_file() or dmg_output.stat().st_size <= 0:
                    raise RuntimeError("hdiutil did not produce a non-empty macOS disk image.")
                outputs.append(dmg_output)
        return outputs

    raise ValueError(f"Unknown target: {target}")


def artifact_notes(artifact_files: list[Path]) -> list[str]:
    """Describe only artifact types that are actually present in the output directory."""
    artifact_names = {item.name for item in artifact_files}
    notes: list[str] = []
    if any(name.endswith(".apk") for name in artifact_names):
        notes.append("Android APKs are direct QA/install packages; production publishing needs the publisher's own upload/release signing configuration.")
    if any(name.endswith(".aab") for name in artifact_names):
        notes.append("Android AAB is a store-upload bundle and cannot be installed directly as an APK.")
    if any(name.endswith(".exe") for name in artifact_names):
        notes.append("Windows Setup EXE is not Authenticode-signed unless the publisher signs it separately.")
    elif any("Windows-portable" in name for name in artifact_names):
        notes.append("Windows portable ZIP is unsigned and can be run after extraction on a compatible Windows host.")
    if any(name.endswith(".deb") for name in artifact_names):
        notes.append("Linux .deb declares runtime dependencies; validate installation on each target distribution.")
    if any("Linux-" in name and name.endswith(".tar.gz") for name in artifact_names):
        notes.append("Linux TAR.GZ is a portable bundle and depends on compatible host runtime libraries.")
    if any(name.endswith(".dmg") or "macOS-unsigned" in name for name in artifact_names):
        notes.append("macOS DMG/APP outputs are unsigned and not notarized unless a separate publisher signing workflow is configured.")
    if any(name.endswith(".ipa") for name in artifact_names):
        notes.append("An iOS IPA was exported using publisher-provided Xcode export options; verify its signing identity and provisioning profile before distribution.")
    elif any("iOS-unsigned" in name for name in artifact_names):
        notes.append("iOS output is an unsigned .app archive, not an installable IPA; Apple signing and provisioning are required for device installation and distribution.")
    if any("Web.zip" in name for name in artifact_names):
        notes.append("Web output is a static site bundle; serve it from HTTPS for secure browser APIs where required.")
    return notes


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("target", choices=sorted(TARGETS | {"all"}), nargs="?", default="all")
    parser.add_argument("--skip-bootstrap", action="store_true", help="Do not generate/check native and web host folders.")
    parser.add_argument("--skip-checks", action="store_true", help="Skip dependency resolution, formatting, analysis and tests.")
    parser.add_argument("--keep-dist", action="store_true", help="Keep artifacts created by earlier build.py calls in dist/.")
    args = parser.parse_args()

    if shutil.which("flutter") is None:
        print("ERROR: Flutter SDK not found in PATH. Install Flutter 3.47.9 or newer stable.", file=sys.stderr)
        return 2
    entrypoint = ROOT / ENTRYPOINT
    if not entrypoint.is_file():
        print(f"ERROR: Flutter app entrypoint missing: {ENTRYPOINT}", file=sys.stderr)
        return 2
    if DIST.exists() and not args.keep_dist:
        shutil.rmtree(DIST)
    DIST.mkdir(parents=True, exist_ok=True)

    if not args.skip_bootstrap:
        run([sys.executable, "tool/bootstrap_platforms.py"])
    if not args.skip_checks:
        run(["flutter", "pub", "get"])
        run(["dart", "format", "lib", "test"])
        run(["flutter", "analyze"])
        run(["flutter", "test", "--reporter", "expanded"])

    run(["dart", "run", "flutter_launcher_icons"])
    run([sys.executable, "tool/verify_platform_icons.py"])

    if args.target == "all":
        host = platform.system().lower()
        selected = ["android", "web"]
        if host == "linux":
            selected.append("linux")
        elif host == "windows":
            selected.append("windows")
        elif host == "darwin":
            selected.extend(["macos", "ios"])
        else:
            raise RuntimeError(f"Unsupported build host: {host}")
    else:
        selected = [args.target]

    outputs: list[Path] = []
    for target in selected:
        outputs.extend(build_target(target))

    flutter_version = subprocess.run(
        ["flutter", "--version"], cwd=ROOT, check=True, capture_output=True, text=True
    ).stdout.splitlines()[0]
    artifact_files = sorted(
        item for item in DIST.iterdir()
        if item.is_file() and item.name not in {"BUILD-MANIFEST.json", "SHA256SUMS.txt"}
    )
    notes = artifact_notes(artifact_files)

    manifest = {
        "application": "AmitarGalleryPlayer",
        "version": APP_VERSION,
        "entrypoint": ENTRYPOINT,
        "built_at_utc": datetime.now(timezone.utc).isoformat(),
        "host": platform.platform(),
        "python": platform.python_version(),
        "flutter": flutter_version,
        "artifacts": [
            {"file": item.name, "bytes": item.stat().st_size, "sha256": sha256(item)}
            for item in artifact_files
        ],
        "notes": notes,
    }
    (DIST / "BUILD-MANIFEST.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    sums = "".join(
        f"{sha256(item)}  {item.name}\n"
        for item in artifact_files
    )
    (DIST / "SHA256SUMS.txt").write_text(sums, encoding="utf-8")
    print("\nBuild artifacts:")
    for item in outputs:
        print(f"  {item.relative_to(ROOT)} ({item.stat().st_size:,} bytes; SHA-256 {sha256(item)})")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (subprocess.CalledProcessError, OSError, RuntimeError, ValueError) as error:
        print(f"BUILD FAILED: {error}", file=sys.stderr)
        raise SystemExit(1)

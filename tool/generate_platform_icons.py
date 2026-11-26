#!/usr/bin/env python3
"""Generate launcher icons, then normalize Android adaptive-icon resource links.

Run only after Flutter host scaffolding and `flutter pub get` have completed.
"""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

from flutter_command import sdk_command
from bootstrap_platforms import configure_linux_icon

ROOT = Path(__file__).resolve().parents[1]
ANDROID_ADAPTIVE_ICON = '''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background" />
    <foreground android:drawable="@drawable/ic_launcher_foreground" />
    <monochrome android:drawable="@drawable/ic_launcher_monochrome" />
</adaptive-icon>
'''


def require_scaffold() -> None:
    required = (
        "android/app/src/main/res",
        "ios/Runner/Assets.xcassets/AppIcon.appiconset",
        "macos/Runner/Assets.xcassets/AppIcon.appiconset",
        "web",
        "windows/runner/resources",
        "linux/runner",
    )
    missing = [item for item in required if not (ROOT / item).is_dir()]
    if missing:
        rendered = ", ".join(missing)
        raise RuntimeError(
            "Flutter platform scaffolding is incomplete; missing: " + rendered + ".\n"
            "Run `python tool/bootstrap_platforms.py` from the project root first, "
            "then `flutter pub get`, and run this icon generator again."
        )


def normalize_android_adaptive_icon() -> None:
    """Write deterministic references matching the configured launcher layers."""
    required = (
        "android/app/src/main/res/values/colors.xml",
        "android/app/src/main/res/drawable-nodpi/ic_launcher_foreground.png",
        "android/app/src/main/res/drawable-nodpi/ic_launcher_monochrome.png",
    )
    missing = [item for item in required if not (ROOT / item).is_file()]
    if missing:
        raise RuntimeError(
            "Android launcher icon generation did not produce required resources: "
            + ", ".join(missing)
        )

    adaptive = ROOT / "android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml"
    adaptive.parent.mkdir(parents=True, exist_ok=True)
    existing = adaptive.read_text(encoding="utf-8") if adaptive.is_file() else None
    if existing != ANDROID_ADAPTIVE_ICON:
        adaptive.write_text(ANDROID_ADAPTIVE_ICON, encoding="utf-8", newline="\n")


def main() -> int:
    try:
        require_scaffold()
        command = sdk_command("dart", "run", "flutter_launcher_icons")
        print("+", " ".join(command), flush=True)
        subprocess.run(command, cwd=ROOT, check=True)
        normalize_android_adaptive_icon()
        # Keep this stage self-sufficient if bootstrap previously generated
        # Linux folders but was interrupted before its final configuration.
        configure_linux_icon()
    except (OSError, RuntimeError, subprocess.CalledProcessError, ValueError) as error:
        print(f"PLATFORM ICON GENERATION FAILED: {error}", file=sys.stderr)
        return 1

    print("Platform icons generated; Android adaptive resource links normalized.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

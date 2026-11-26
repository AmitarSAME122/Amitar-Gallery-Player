# Final validation report — AmitarGalleryPlayer Windows/bootstrap follow-up

## Input evidence addressed

The latest Windows PowerShell run confirmed that Flutter host generation now launches successfully through the bundled Dart SDK and `flutter_tools.snapshot`. It then exposed three follow-up issues:

1. Bootstrap attempted to fetch the Gradle 8.14.6 Wrapper JAR from `raw.githubusercontent.com`, where the user's connection was reset.
2. The bootstrap aborted before configuring the generated Linux GTK runner, leaving `linux/runner/resources/app_icon.png` absent during icon verification.
3. The Python checksum test ran before the manifest had been regenerated after Flutter changed `analysis_options.yaml` during `flutter pub get`.

The same log confirmed `flutter analyze --fatal-infos` reported no issues and all eight Dart tests passed.

## Changes in this revision

- Changed the Wrapper source to Gradle's official standalone endpoint: `https://services.gradle.org/distributions/gradle-8.14.6-wrapper.jar`.
- Kept the official published SHA-256 (`ad16bca46cb71bb5887c546860d93992aeee35c1fdaf4a242b0a612375d937e0`) mandatory. An existing mismatched file is never used or silently replaced.
- Made local host bootstrap tolerant of Wrapper network unavailability: host generation, Linux icon setup and unrelated targets can complete. Android builds remain blocked until the official Wrapper is downloaded and verified.
- Added `--require-gradle-wrapper` for Android/`all` builds and CI, ensuring those builds fail closed when the Wrapper is missing. Web-only bootstrap does not require the Android Wrapper.
- Moved Linux runner icon configuration before the optional Wrapper download and invoked it again from the icon generator, making recovery idempotent after partial bootstrap.
- Reordered documented PowerShell quality steps so `flutter pub get`, icon generation, Dart fixes and formatting are followed by SHA-256 manifest refresh before Python tests.
- Documented the real launch command using `--target lib/AmitarGalleryPlayer.dart`; a Dart file path by itself and a `main = ...` assignment are not PowerShell launch commands.
- Added an optional PowerShell download-and-SHA-256 verification fallback for environments where Python HTTPS access is restricted but PowerShell access is available.

## Validation performed for this package

- `python -m py_compile tool/*.py`: passed.
- `python tool/validate_source_contracts.py`: passed.
- `python tool/check_release_version.py`: passed.
- `python -m unittest discover -s tool -p 'test_*.py' -v`: **104 tests passed, 3 skipped**.
  - The skipped tests require a Windows environment or a Git working tree not available in this source-archive validation environment.
- Source SHA-256 manifest: regenerated and validated against every listed file.
- Platform-icon validation logic: unit tests passed for all six platforms, Android adaptive resource layers, Windows ICO and Web manifest references.
- ZIP archive: integrity-tested with no corrupt entries.

## Validation boundary

The Flutter SDK and the user's Windows host are not available in this package-validation environment. The user's own log establishes that `flutter analyze --fatal-infos` completed with `No issues found` and `flutter test` completed with all eight tests passing. This package does **not** claim that Android, Web or Windows release builds were run here. Android build still requires successful retrieval and SHA-256 verification of the official Gradle Wrapper JAR, supported JDK/Android SDK and accepted licenses. Windows desktop additionally requires Visual Studio C++ build tools. iOS/macOS builds require macOS/Xcode.

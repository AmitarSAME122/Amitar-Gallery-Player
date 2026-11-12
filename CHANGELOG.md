# Changelog

## 1.0.0 — GitHub initial release

- Set the public release identity to `1.0.0+1` across Dart, pubspec, Windows installer and build validation.
- Standardized the main application source at `lib/AmitarGalleryPlayer.dart` and pass it explicitly to every Flutter build.
- Added platform icon sources: Android adaptive foreground and monochrome variants, iOS/macOS/Windows/Web icon source sizes, ICO and Linux PNG artwork.
- Added a Persian A3 presentation poster in PDF and 300-DPI PNG formats.
- Added cross-platform build orchestration for Android, Web, Linux, Windows, macOS and iOS validation.
- Repaired the Flutter Android Gradle plugin wiring, pinned JDK 17 / AGP 8.13.2 / Kotlin Gradle Plugin 2.4.21, upgraded to Gradle 8.14.6, and pinned official distribution and Wrapper JAR SHA-256 values.
- Replaced the Android placeholder package ID with `com.amitar.amitar_gallery_player` and added optional publisher-keystore signing without committing secrets.
- Corrected the application entrypoint across build scripts, version checks, tests and documentation; removed machine-specific SDK paths and generated caches from source delivery.
- Added Linux DEB metadata with GTK and libmpv runtime dependencies, Linux app icon and AppStream metadata.
- Added Windows Inno Setup configuration with the branded setup icon.
- Added optional publisher-configured iOS IPA export; unsigned APP archive remains the default validation output.
- Added per-runner manifests and SHA-256 verification, plus automated GitHub Release attachment for `v*` tags.
- Added Persian-first/English documentation, dependency-role notes, media-format boundaries, security guidance and GitHub contribution templates.
- Kept the single media playback stack; no overlapping second playback engine or redundant storage layer was added.
- Moved Kotlin `compilerOptions` to the project-level `kotlin {}` DSL required by the Kotlin Gradle Plugin; kept Java/Kotlin bytecode targets aligned at JVM 17.
- Added mandatory structural icon verification for Android adaptive layers and manifest references, iOS/macOS asset catalogs, Windows multi-resolution ICO, Linux GTK window resources and Web PWA manifest sizes.
- Wired the Linux GTK window to load its branded PNG relative to the installed executable; DEB now installs 256/512 hicolor icons and localized Persian/English desktop-launcher metadata.
- Expanded packaging regression tests to inspect the actual DEB archive contents and reject missing icon files or launcher references.
- Preserved existing gallery, albums, player, queue, trash, settings, localization and animated glass UI implementation.

### Validation boundary

Python build-tool tests and packaging checks can run without Flutter. Dart formatting, Flutter analysis/tests, native compilation, actual installer execution, codec playback and device/browser integration still require the corresponding SDK and runtime environment. See `VALIDATION_REPORT.md`.


## 1.0.0+1 - Brand identity refresh

- Replaced the application icon source with the user-approved `AmitarGalleryPlayer.png` artwork.
- Regenerated all square icon sizes, Android adaptive/monochrome artwork, Linux icons, and the Windows multi-resolution ICO from one source.
- Rebuilt the Persian A3 release poster with a Fluent/glass visual system and 300 DPI print master.
- Added a reproducible branding-asset generator and optional tool requirements.
- Kept the application semantic version at 1.0.0 for the initial GitHub release line.


### Transparent icon correction

- Removed the previous icon-generation step that cropped the uploaded image, converted it to RGB, blurred it, and composited a navy backdrop.
- Preserved the user-uploaded RGBA PNG byte-for-byte as the in-app brand image.
- Regenerated color launcher icons, Android adaptive foreground, Linux icons and Windows ICO with alpha transparency intact.
- Made the Android adaptive background layer fully transparent and removed the decorative gradient tile behind the app logo in the UI.
- Added a separate opaque iOS App Store icon only because Apple's store icon validation requires an opaque primary icon; retained the original transparent artwork for the iOS dark-transparent variant.
- Rebuilt the A3 poster with the transparent artwork composited over the poster design, not baked into the icon file.


### Dependency and Android scoped-URI compatibility correction

- Removed the incompatible direct `cross_file ^0.4.0` constraint. `file_picker` continues to use its supported `cross_file 0.3.x` API transitively, avoiding a Pub solver conflict without forcing a package override.
- Replaced app-side `XFile 0.4` file-system calls with the existing `universal_io` abstraction.
- Added an Android `ContentResolver` bridge for legacy `content://` library entries. It copies in 64 KiB chunks to an app-cache file, enforces a per-operation byte ceiling, runs away from the UI thread, and is cleaned up by the Dart caller.
- Kept the native file picker, mobile staged imports, persisted local file paths and existing gallery/player behavior; no second file-picker or media playback dependency was introduced.

### Final source and runtime-safety audit

- Capped native device-library and selected-folder scans at 20,000 items per operation and made the truncation state explicit.
- Added per-operation in-memory budgets for generated thumbnails and image previews during device scans, folder scans and multi-file imports.
- Hardened persisted media metadata parsing against malformed types, missing identifiers, negative sizes/play counts and out-of-range year/track values.
- Made mobile picker imports stream into app-private storage and remove staged files when an import fails before ownership is committed to the library.
- Preserved mixed import outcomes instead of replacing failure details with a success status.
- Guarded ChangeNotifier notifications during asynchronous player disposal.
- Centralized media-extension classification; HLS/DASH playlist extensions are classified as video and unknown formats remain explicitly unknown.
- Pinned GitHub Actions to verified patch release tags and added monthly Dependabot checks for Pub packages and Actions.
- Expanded Dart regression tests for extension normalization, playlist classification and malformed persisted records.

- Added a deterministic source SHA-256 manifest generator and regression check so the checked-in checksum file cannot silently become stale.

### Flutter Analyze blocker correction — CI run e334188

- Replaced all app-side uses of `XFile.fileSystem` and `XFile.scopedStorage`, which were incompatible with the `cross_file 0.3.5+5` version selected by `file_picker 13.3.2`.
- Removed the unnecessary direct `cross_file` dependency and retained the compatible transitive package selected by `file_picker`.
- Removed the unnecessary `dart:typed_data` import while preserving `Uint8List` access through Flutter services.
- Kept the required `AmitarGalleryPlayer.dart` filename with a file-scoped analyzer suppression rather than renaming the project entrypoint.
- Migrated the queue UI to `ReorderableListView.onReorderItem` and corrected the reorder index handling.
- Added bounded Android `ContentResolver` compatibility for persisted `content://` references.
- Updated this report against the actual CI output: 62 Python tooling tests passed; the remaining 16 Analyzer findings were 13 obsolete XFile API calls and 3 informational lints.

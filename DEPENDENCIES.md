# Dependency roles

The dependency graph intentionally uses one package for each responsibility where possible. Adding a second player, a second database or a second file-selection layer would create overlapping behavior.

| Package | Responsibility | Why it is not duplicated |
|---|---|---|
| `media_kit` | Playback engine/controller API | Single player state and playback API. |
| `media_kit_video` | Flutter video surface and controls integration | UI integration for the same playback engine, not a second engine. |
| `media_kit_libs_video` | Native media runtime/codec bundle for supported native targets | Provides the native libraries used by `media_kit`; no separate audio bundle is added. |
| `photo_manager` | User-authorized Android/iOS/macOS media-library access and asset operations | Covers native Photos/MediaStore use; it is not used for desktop folder crawling or Web. |
| `file_picker` | Native/browser file, folder and save dialogs | Single user-mediated picker layer across targets. |
| `cross_file` | Cross-platform file abstraction used with picker results | Common file abstraction rather than a competing picker. |
| `universal_io` | Cross-platform filesystem API where `dart:io` would not compile for Web | Used behind platform checks; browser permissions remain authoritative. |
| `path` | Portable path operations | Path manipulation only. |
| `path_provider` | App-specific directories on platforms that expose them | Does not replace user-selected file access. |
| `media_metadata` | Embedded media metadata read/write on supported native platforms | Metadata layer, not playback or library scanning. |
| `image` | Raster decoding, resizing and thumbnail encoding | Image processing, separate from SVG rendering. |
| `flutter_svg` | SVG vector rendering | SVG-specific, not a general raster decoder. |
| `hive_ce` + `hive_ce_flutter` | Durable library/album/trash records | One local record store. |
| `shared_preferences` | Small settings such as locale/theme | Not used as a media-record database. |
| `flutter_launcher_icons` (dev) | Generates platform launcher icon files | Build-time tooling; not a runtime dependency. |
| `flutter_lints` (dev) | Static lint rules | Development-only quality tooling. |

Dependency constraints live in `pubspec.yaml`. The GitHub Actions quality job resolves `pubspec.lock` and distributes that same generated lockfile to all native jobs in a workflow run. The project does not commit a hand-authored or fabricated dependency lock.

Before adding a package, document its unique responsibility, target support, license, maintenance status and whether an existing dependency already covers the same behavior.

# Third-party notices

The AmitarGalleryPlayer application source is distributed under the MIT License in `LICENSE`.

Third-party Flutter/Dart packages and native libraries are separate works. Their copyright, license and redistribution requirements remain in force and are not replaced by the application's MIT license.

Direct dependencies and development tools are declared in `pubspec.yaml`. The dependency resolver also selects transitive Dart packages and platform-native components. Before redistributing a binary, generate and review the complete dependency/license inventory from the resolved `pubspec.lock` and the platform build output. Preserve required notices in the release package.

In particular:

- `media_kit`, its platform implementations, bundled native codec components and system `libmpv` are separate from the application's own source license.
- Native codec and container support can involve independent patent, copyright and distribution considerations in some jurisdictions.
- The Linux DEB declares a system `libmpv` runtime dependency rather than claiming to relicense that library.
- No proprietary font is bundled in this source package. UI text uses platform font fallback.

This file is a notice, not legal advice. A publisher should perform a license and codec-distribution review for the exact resolved dependencies and target jurisdiction before commercial redistribution.

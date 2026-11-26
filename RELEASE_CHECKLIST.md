# Release checklist

## Before creating a tag

- [ ] Confirm `pubspec.yaml`, `appVersion` and Inno Setup are all `1.0.0`.
- [ ] Run `python3 tool/check_release_version.py`.
- [ ] Run Python tooling tests and all Flutter quality checks.
- [ ] Resolve dependencies and keep the generated `pubspec.lock` with the tested build.
- [ ] Run the native build on each target runner and verify installation/runtime behavior.
- [ ] Confirm Android release signing, Windows Authenticode, Apple Developer ID/notarization and iOS provisioning are configured where distribution requires them.
- [ ] Review all transitive package, native codec and patent/license obligations.
- [ ] Verify the poster, icons, README, changelog and support matrix.
- [ ] Confirm the original RGBA source remains byte-identical and transparent color icons were generated without cropping or a new background.
- [ ] Confirm the Android adaptive background is fully transparent and the iOS App Store opaque exception is documented.
- [ ] Confirm the A3 poster PDF and 300 DPI PNG match and contain no missing Persian glyphs or clipped content.

## Publish

- [ ] Push the reviewed source branch.
- [ ] Create and push the matching annotated tag, e.g. `v1.0.0`.
- [ ] Confirm all GitHub Actions platform jobs passed.
- [ ] Confirm the release contains expected Android, Windows, Linux, macOS, Web and iOS validation artifacts.
- [ ] Verify `SHA256SUMS.txt` and runner-specific checksum manifests.
- [ ] Ensure the release labels unsigned/unsigned-notarized artifacts correctly.

Do not describe a platform binary as production-ready until its native build and target-device/browser acceptance tests are complete.

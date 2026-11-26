# Media support and platform boundaries

A file extension identifies a likely container or media family; it does not prove that the file is valid or that the active decoder supports its codecs. The app classifies images, video, audio and unknown extensions separately and only attempts playback when the user opens an item.

## Playback backends

| Platform | Playback backend | Practical boundary |
|---|---|---|
| Android | `media_kit` / native libmpv bundle | Depends on ABI, decoder bundle, Android version and device codec/hardware support. |
| iOS | `media_kit` native playback | Apple sandbox, supported APIs, codec and device constraints apply. |
| macOS | `media_kit` / libmpv | Depends on the packaged runtime, architecture and macOS version. |
| Windows | `media_kit` / libmpv | Depends on packaged native runtime, architecture and Windows version. |
| Linux | `media_kit` / system libmpv | `libmpv` runtime library must be installed; build requires `libmpv-dev` and `mpv` on Ubuntu/Debian per upstream guidance. |
| Web | HTML media elements/browser decoders | Browser and OS codec matrix applies; support is narrower than native libmpv. |

## File selection and library scanning

| Feature | Android | iOS | macOS | Windows | Linux | Web |
|---|---:|---:|---:|---:|---:|---:|
| User-mediated file picker | Yes | Yes | Yes | Yes | Yes | Yes, browser-mediated |
| Direct system Photos/media library scan | Yes, with permission | Yes, with permission | Yes, with permission | No | No | No |
| Recursive user-selected folder scan | No | No | Yes | Yes | Yes | No unrestricted recursive disk scan |
| App-private imported media | Yes | Yes | Platform sandbox rules | User-selected locations | User-selected locations | Browser-managed storage/downloads |

## Image formats

Image preview uses Flutter/native image decoders and the `image` package for additional raster decoding and thumbnails. SVG is handled separately by `flutter_svg`. Whether an image can be decoded depends on the codec implementation, file validity and memory constraints. Extremely large files may be rejected or shown using a bounded preview rather than loaded fully into RAM.

## Metadata

Embedded metadata read/write is provided through `media_metadata` only where the plugin, OS and media format support the requested operation. Metadata write is not available in the Web build. Unsupported fields or containers can be left unchanged; metadata editing is not a guarantee that every metadata standard or vendor extension is writable.

## Why “all formats on all platforms” is not a valid guarantee

- A container such as MP4 or MKV can contain many different audio/video codecs.
- OS decoder availability varies by version, installed components, patents/licensing and hardware.
- The Web build cannot replace the codecs that the browser exposes.
- Media can be damaged, encrypted, incomplete or use unsupported profiles even when the extension looks familiar.
- Some codec distributions are subject to independent license and redistribution terms.

For these reasons, the product reports unknown media types conservatively and the release does not claim universal compatibility. Test the actual media sample and target device/browser before promising support.

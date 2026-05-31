# native_video_editor

Native video editing for Flutter without FFmpeg.

`native_video_editor` exposes a small Dart API that sends edit requests to the
platform video stack:

* Android: AndroidX Media3 Transformer
* iOS: AVFoundation

The first release focuses on a unified native processing pipeline that can apply
multiple edits in one export.

## Features

| Feature | Android | iOS |
| --- | --- | --- |
| Trim start/end time | Yes | Yes |
| Normalized crop | Yes | Yes |
| Resize / scale output | Yes | Yes |
| Rotate 0, 90, 180, or 270 degrees | Yes | Yes |
| Mute audio | Yes | Yes |

## Installation

Add the package to your `pubspec.yaml`:

```yaml
dependencies:
  native_video_editor: ^0.0.1
```

Then run:

```sh
flutter pub get
```

## Platform Requirements

### Android

* Minimum SDK: 23
* Native backend: AndroidX Media3 Transformer
* The app must provide local file paths that Android can read and write.

### iOS

* Minimum deployment target: iOS 13.0
* Native backend: AVFoundation
* The app must provide sandbox-accessible local file paths.

## Basic Usage

```dart
import 'package:native_video_editor/native_video_editor.dart';

final outputPath = await NativeVideoEditor.processVideo(
  VideoEditRequest(
    inputPath: inputPath,
    outputPath: outputPath,
    trimStart: const Duration(seconds: 1),
    trimEnd: const Duration(seconds: 8),
    cropRect: const VideoCropRect(
      left: 0.1,
      top: 0.1,
      width: 0.8,
      height: 0.8,
    ),
    targetWidth: 720,
    targetHeight: 720,
    rotationDegrees: 90,
    muteAudio: true,
  ),
);
```

## Request Options

### Trimming

Use `trimStart` and `trimEnd` to export only part of a video:

```dart
VideoEditRequest(
  inputPath: inputPath,
  outputPath: outputPath,
  trimStart: const Duration(seconds: 3),
  trimEnd: const Duration(seconds: 12),
);
```

### Cropping

`VideoCropRect` uses normalized values from `0.0` to `1.0` relative to the
oriented source frame.

```dart
const crop = VideoCropRect(
  left: 0.1,
  top: 0.1,
  width: 0.8,
  height: 0.8,
);
```

This keeps the center 80% of the source frame.

### Resizing

Set both `targetWidth` and `targetHeight` to resize the export:

```dart
VideoEditRequest(
  inputPath: inputPath,
  outputPath: outputPath,
  targetWidth: 1280,
  targetHeight: 720,
);
```

Both dimensions must be positive even numbers because many platform encoders
reject odd output sizes.

### Rotation

`rotationDegrees` is clockwise and must be one of:

* `0`
* `90`
* `180`
* `270`

### Muting Audio

Set `muteAudio` to `true` to export the video without an audio track:

```dart
VideoEditRequest(
  inputPath: inputPath,
  outputPath: outputPath,
  muteAudio: true,
);
```

## File Path Notes

The plugin expects local file paths. It does not request storage permissions or
copy files for you.

In a real app, a common flow is:

1. Let the user pick or record a video.
2. Copy that video into your app sandbox or cache directory.
3. Build an output path in a writable cache/documents directory.
4. Call `NativeVideoEditor.processVideo`.

`inputPath` and `outputPath` must be different files. Existing output files are
replaced.

## Example App

This package includes a runnable example project:

```sh
cd example
flutter pub get
flutter run
```

The example applies trimming, cropping, resizing, rotation, and audio muting in
one request.

## Limitations

* Only Android and iOS are supported.
* Unsupported source codecs can fail if the platform encoder/decoder cannot
  process them.
* Long videos can take time to export because processing is done by the native
  platform stack.
* Watermarks, text overlays, speed adjustment, and transcoding controls are
  planned for later phases.

## Troubleshooting

### The export fails immediately

Check that the input file exists, the output directory is writable, and the input
and output paths are different.

### The output size is rejected

Use even values for `targetWidth` and `targetHeight`, such as `720x1280` or
`1280x720`.

### The source video cannot be decoded

Try a common MP4/H.264 source first. The plugin relies on Media3 and AVFoundation
codec support rather than FFmpeg.

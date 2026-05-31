# native_video_editor

A Flutter plugin for native video edits without FFmpeg.

Phase 1 supports:

* Video trimming with start and end times.
* Normalized spatial cropping.
* Scaling/resizing to a target resolution.
* Rotation by `0`, `90`, `180`, or `270` degrees.
* Muting audio.

Android uses AndroidX Media3 Transformer. iOS uses AVFoundation.

## Platform requirements and limitations

* Android requires `minSdkVersion 23` and uses Media3 Transformer `1.10.1`.
* iOS requires iOS 13.0 or newer.
* `inputPath` and `outputPath` must be different files. Existing output files are replaced.
* The caller must provide app-accessible local file paths. On mobile, copy picker/gallery results into your app sandbox before processing.
* `targetWidth` and `targetHeight` must be provided together and must be positive even numbers for encoder compatibility.
* `rotationDegrees` is clockwise and must be one of `0`, `90`, `180`, or `270`.
* Native exporters support platform codecs/containers available to Media3 Transformer and AVFoundation; unsupported source codecs can still fail at export time.

## Usage

```dart
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

`VideoCropRect` values are normalized from `0.0` to `1.0` relative to the
source frame. For example, `left: 0.1, top: 0.1, width: 0.8, height: 0.8`
keeps the center 80% of the frame.

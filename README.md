# native_video_editor

Native video editing for Flutter without FFmpeg.

`native_video_editor` exposes a small Dart API that sends edit requests to the
platform video stack:

* Android: AndroidX Media3 Transformer
* iOS: AVFoundation
* macOS: AVFoundation
* Windows: Windows Media Editing (`Windows.Media.Editing.MediaComposition`)

The first release focuses on a unified native processing pipeline that can apply
multiple edits in one export.

## Platform Support

The table below describes functionality in the current implementation. Native
media processing depends on the codecs available on the device. Web and Linux
are not currently supported.

The composition features are new and require device validation before a release.
An implemented backend does not guarantee every codec or encoder setting works
on every device.

| Functionality | Android | iOS | macOS | Windows |
| --- | --- | --- | --- | --- |
| Edit video (`processVideo`) | Yes | Yes | Yes | Yes |
| Trim start/end time | Yes | Yes | Yes | Yes |
| Normalized crop | Yes | Yes | Yes | Yes |
| Resize / scale output | Yes | Yes | Yes | Yes |
| Rotate 0, 90, 180, or 270 degrees | Yes | Yes | Yes | Yes |
| Speed adjustment (0.25x–4.0x) | Yes | Yes | Yes | No |
| Mute audio | Yes | Yes | Yes | Yes |
| Compose image + audio (`composeImageWithAudio`) | Yes | Yes | Yes | Yes |
| Add / replace audio (`mergeAudioIntoVideo`) | Yes | Yes | Yes | Yes |
| Extract JPEG / PNG thumbnail (`extractThumbnail`) | Yes | Yes | Yes | Yes |
| Media information (`getMediaInfo`) | Yes | Yes | Yes | Yes |
| Compression / bitrate / frame rate (`compressVideo`) | Yes | Yes | Yes | Yes |
| Join videos (`joinVideos`) | Yes | Yes | Yes | Yes |
| Batch thumbnails (`extractThumbnails`) | Yes | Yes | Yes | Yes |
| Audio volume, delay, trimming and looping (`composeVideo`) | Yes | Yes | Yes | Yes |
| Image watermarks (`VideoOverlay.image`) | Yes | Yes | Yes | Yes |
| Fit: contain / cover / stretch (`VideoFit`) | Yes | Yes | Yes | Yes |
| Horizontal / vertical flipping (`VideoClip`) | Yes | Yes | Yes | Yes |
| Timed text captions (`VideoOverlay.text`) | Yes | Yes | Yes | Yes |
| Image slideshow (`createSlideshow`) | Yes | Yes | Yes | Yes |
| Picture-in-picture (`VideoOverlay.video`) | Yes | Yes | Yes | Yes |
| Composition progress and cancellation | Yes | Yes | Yes | Yes |
| Progress: video editing | Yes | Yes | Yes | Yes |
| Progress: image + audio composition | Yes | Yes | Yes | Yes |
| Progress: audio merging | Yes | Yes | Yes | Yes |
| Cancel video editing (`cancelProcessVideo`) | Yes | Yes | Yes | Yes |
| Cancel image + audio composition (`cancelProcessVideo`) | Yes | Yes | Yes | Yes |
| Cancel audio merging (`cancelProcessVideo`) | Yes | Yes | Yes | Yes |

On Windows, `speedMultiplier` in `processVideo` is currently ignored. New
compositions encode H.264 video and AAC audio in MP4. Bitrates are requests to the
native encoder, not exact output file-size guarantees. Android's video frame-rate
setting caps the output rate; it does not synthesize missing source frames.

## Installation

Add the package to your `pubspec.yaml`:

```yaml
dependencies:
  native_video_editor: ^0.4.1
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

### iOS & macOS

* Minimum iOS deployment target: 13.0
* Minimum macOS deployment target: 10.15
* Native backend: AVFoundation
* The app must provide sandbox-accessible local file paths.

### Windows

* Minimum OS version: Windows 10 (version 1809+ / build 17763+)
* Native backend: C++/WinRT (`Windows.Media.Editing.MediaComposition`)
* The app must provide valid local file system paths.

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
    speedMultiplier: 1.25,
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

### Speed Adjustment

Use `speedMultiplier` to slow down or speed up the exported video:

```dart
VideoEditRequest(
  inputPath: inputPath,
  outputPath: outputPath,
  speedMultiplier: 1.5,
);
```

Values greater than `1.0` make the output faster. Values less than `1.0` make
the output slower. Supported values are from `0.25` to `4.0`.

## Progress Reporting & Cancellation

Pass an `onProgress` callback to receive real-time export progress updates (`0.0` to `1.0`). To cancel an ongoing export, call `NativeVideoEditor.cancelProcessVideo`:

```dart
final resultPath = await NativeVideoEditor.processVideo(
  request,
  onProgress: (progress) {
    print('Export progress: ${(progress * 100).toStringAsFixed(1)}%');
  },
);

// Cancel from another UI handler:
await NativeVideoEditor.cancelProcessVideo(outputPath);
```

## Image + Audio Composition

Compose a still image (PNG or JPEG) and an audio track into a video frame:

```dart
final outputPath = await NativeVideoEditor.composeImageWithAudio(
  ImageVideoComposeRequest(
    imagePath: imagePath,
    audioPath: audioPath,
    outputPath: outputPath,
    targetWidth: 1080,
    targetHeight: 1920,
    audioDurationMs: 15000, // Optional cap in ms
    frameRate: 30,
  ),
  onProgress: (progress) => print('Composing: $progress'),
);
```

## Audio Merging into Video

Inject or replace background audio in an existing video:

```dart
final outputPath = await NativeVideoEditor.mergeAudioIntoVideo(
  AudioMergeRequest(
    inputVideoPath: videoPath,
    audioPath: audioPath,
    outputPath: outputPath,
    replaceExistingAudio: true, // Set false to mix streams
  ),
  onProgress: (progress) => print('Merging: $progress'),
);
```

## Thumbnail Extraction

Extract a thumbnail frame to a JPEG or PNG file:

```dart
final thumbnailPath = await NativeVideoEditor.extractThumbnail(
  VideoThumbnailRequest(
    inputPath: inputPath,
    outputPath: thumbnailPath,
    position: const Duration(seconds: 2),
    quality: 92,
  ),
);
```

Use `.jpg`, `.jpeg`, or `.png` in `outputPath` to choose the image format.

## Composition, Compression and Inspection

The export helpers below share the native composition backend. Metadata and
thumbnail APIs use native readers. The existing `processVideo` API remains
available for trim/crop/rotation/speed edits.

```dart
final info = await NativeVideoEditor.getMediaInfo(videoPath);
print('${info.width}x${info.height}, ${info.duration}, ${info.videoCodec}');

const settings = VideoExportSettings(
  width: 1280,
  height: 720,
  frameRate: 30,
  videoBitrate: 2000000, // bits per second
  audioBitrate: 128000,
);

await NativeVideoEditor.compressVideo(
  inputPath: videoPath,
  outputPath: compressedPath,
  settings: settings,
  fit: VideoFit.cover,
  flipHorizontal: true,
);

await NativeVideoEditor.joinVideos(
  inputPaths: [firstVideoPath, secondVideoPath],
  outputPath: joinedPath,
  settings: settings,
);

await NativeVideoEditor.createSlideshow(
  imagePaths: [firstImagePath, secondImagePath],
  imageDuration: const Duration(seconds: 3),
  outputPath: slideshowPath,
  settings: settings,
  audioTracks: [CompositionAudioTrack(musicPath, loop: true, volume: 0.3)],
);

final thumbnails = await NativeVideoEditor.extractThumbnails(
  inputPath: videoPath,
  positions: [Duration.zero, const Duration(seconds: 2)],
  outputPaths: [firstThumbnailPath, secondThumbnailPath],
);
```

Metadata fields that the native platform cannot determine are nullable. Codec
names use each platform's naming, and width/height describe encoded dimensions
before `rotationDegrees` is applied. Thumbnail batches run sequentially; if a
later extraction fails, earlier output files remain available.
`info.audioTracks` lists the available audio streams with codec, channel count,
sample rate, bitrate and language when the platform reports them. Track indices
follow native source ordering and can differ between platforms.

For preset settings, use `const VideoExportSettings.low()` (640×360, 24 FPS,
800 kbps video), `.medium()` (1280×720, 30 FPS, 2 Mbps), or `.high()`
(1920×1080, 30 FPS, 8 Mbps). Presets control resolution and bitrate; they do not
guarantee a particular perceptual quality or final file size.

### Watermarks, Captions, Audio and Picture-in-Picture

```dart
await NativeVideoEditor.composeVideo(
  VideoCompositionRequest(
    outputPath: outputPath,
    settings: settings,
    clips: [
      VideoClip.video(videoPath, volume: 0.5, fit: VideoFit.contain),
      VideoClip.image(imagePath, duration: const Duration(seconds: 3)),
    ],
    audioTracks: [
      CompositionAudioTrack(
        musicPath,
        start: const Duration(seconds: 1), // delay on the output timeline
        trimStart: const Duration(seconds: 2), // skip source audio intro
        duration: const Duration(seconds: 5), // source segment to loop
        volume: 0.25,
        loop: true,
      ),
    ],
    overlays: [
      VideoOverlay.image(
        logoPath,
        rect: const VideoCropRect(left: 0.02, top: 0.02, width: 0.2, height: 0.2),
        opacity: 0.8,
      ),
      VideoOverlay.text(
        'My caption',
        rect: const VideoCropRect(left: 0.05, top: 0.8, width: 0.9, height: 0.15),
        fontSize: 40, // pixels in the final output canvas
        start: const Duration(seconds: 1),
        duration: const Duration(seconds: 3),
        color: 0xFFFFFFFF, // ARGB
      ),
      VideoOverlay.video(
        insetVideoPath,
        rect: const VideoCropRect(left: 0.65, top: 0.05, width: 0.3, height: 0.3),
        start: const Duration(seconds: 2),
        duration: const Duration(seconds: 4),
      ),
    ],
  ),
  onProgress: (progress) => print('Export: $progress'),
);
// From another handler:
// await NativeVideoEditor.cancelProcessVideo(outputPath);
```

Clips play sequentially. Their combined duration determines the output length;
overlays and background audio never extend it. Video clips/overlays are capped at
their remaining source duration. Image clips require a positive duration.
Overlay rectangles are normalized relative to the final canvas, with a top-left
origin. Later overlays appear above earlier ones. Picture-in-picture video is
silent; use an audio track when additional audio is needed.

`contain` preserves aspect ratio with empty space, `cover` crops to fill, and
`stretch` fills without preserving aspect ratio. Captions are rendered into
transparent PNGs with Flutter's fonts, wrap to their rectangle, and clip any
overflow. Text rendering requires an initialized Flutter engine. There is no
automatic speech transcription or subtitle-file parser.

### Native Integration Checks

The example includes a test that generates its own images/audio and verifies
actual native exports, metadata, dimensions, duration, watermarks and thumbnails:

```sh
cd example
flutter pub get
flutter test integration_test/composition_integration_test.dart -d <device-id>
```

Run it on each target platform before publishing. Mocked Dart unit tests alone
cannot validate native codecs or rendered output.

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

This package includes a runnable, full-featured interactive UI video editor example:

```sh
cd example
flutter pub get
flutter run
```

The example features:
- Interactive timeline trimming slider
- Visual cropping overlay box with aspect ratio control
- Live video player preview
- Real-time export progress tracking and cancellation modal
- Full support for image+audio video composition and audio merging tools

## Limitations

* Unsupported source codecs can fail if the platform encoder/decoder cannot
  process them.
* Long videos can take time to export because processing is done by the native
  platform stack.
* Advanced filters, transitions, reverse playback, Web and Linux backends are not implemented.
* Apple image timelines currently create temporary video clips before final encoding;
  long slideshows need additional temporary disk space.
* Windows video crops and flips use a temporary transcode before composition;
  these operations need additional time and disk space.
* Native encoders may adjust requested bitrates or reject unsupported dimensions.

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

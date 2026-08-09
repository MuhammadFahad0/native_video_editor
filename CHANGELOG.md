## 0.4.0

* Add desktop platform support for macOS (AVFoundation) and Windows (`Windows.Media.Editing.MediaComposition`).
* Fix Windows C++ native rendering compilation, thread apartment initialization, and precise trimming rendering API usage.
* Update example app with desktop video player support (`video_player_win`).

## 0.3.0

* Add `composeImageWithAudio` API to compose a still image (PNG/JPEG) and audio track into an MP4 video.
* Add `mergeAudioIntoVideo` API to replace or inject custom background audio into an existing video.
* Add progress reporting (`onProgress` callback) and cancellation (`cancelProcessVideo`) support across native operations.
* Overhaul the example app into a full interactive UI video editor with timeline trimming, crop overlays, audio merging, and image-video composition tools.

## 0.2.1

* Add GitHub Actions CI/CD workflows for automated pub.dev releases.
* Code formatting and static analysis improvements.

## 0.2.0

* Add video export progress reporting callback support (`onProgress` parameter in `processVideo`).
* Add video export cancellation support (`cancelProcessVideo` method).
* Upgrade Android compile SDK and target SDK to 36 for SDK 36 compatibility.
* Update example app with interactive progress tracking and cancellation controls.

## 0.1.0

* Add video speed adjustment with `speedMultiplier`.
* Add native thumbnail extraction.
* Improve the example with file picking and sandbox output paths.
* Add Dart API validation tests.

## 0.0.2

* Add recognized MIT license metadata.
* Improve README, package topics, issue tracker, and public API documentation.
* Exclude local tool/cache artifacts from published archives.

## 0.0.1

* Initial Phase 1 native processing pipeline.
* Adds trimming, normalized cropping, resizing, 90-degree rotation, and audio muting.

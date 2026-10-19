# native_video_editor example

This is a runnable Flutter example app for the `native_video_editor` plugin.

## Run

From the plugin root:

```sh
cd example
flutter pub get
flutter run
```

The app uses a native file picker, writes output files to the app cache
directory, and shows the extracted thumbnail in the UI. The sample operation
trims, crops, resizes, rotates, speeds up, and mutes the input video.

## Notes

Open **More video tools** from the toolbar to try media information,
compression, joining clips, slideshows, audio volume/delay/looping, fit modes,
flipping, image watermarks, captions, picture-in-picture and batch thumbnails.
This screen is available before selecting a video in the main editor.

The native smoke test generates images and audio without downloaded fixtures:

```sh
flutter test integration_test/composition_integration_test.dart -d <device-id>
```

Use `windows`, `macos`, or a connected Android/iOS device ID. The test checks
actual exported files; the package's ordinary unit tests use mocked channels.

The example has Android, iOS, macOS and Windows runner projects:

* `android/`
* `ios/`
* `macos/`
* `windows/`

On a physical mobile device, use a path that the app can access. In a production
sample, this should be paired with a picker/copy-to-sandbox flow.

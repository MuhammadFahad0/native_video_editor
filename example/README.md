# native_video_editor example

This is a runnable Flutter example app for the `native_video_editor` plugin.

## Run

From the plugin root:

```sh
cd example
flutter pub get
flutter run
```

The app asks for an input video path and writes a processed MP4 to the app temp
directory. The sample operation trims, crops, resizes, rotates, and mutes the
input video.

## Notes

The example has full Android and iOS runner projects:

* `android/`
* `ios/`

On a physical mobile device, use a path that the app can access. In a production
sample, this should be paired with a picker/copy-to-sandbox flow.

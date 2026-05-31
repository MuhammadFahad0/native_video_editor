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

The example has full Android and iOS runner projects:

* `android/`
* `ios/`

On a physical mobile device, use a path that the app can access. In a production
sample, this should be paired with a picker/copy-to-sandbox flow.

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:native_video_editor/native_video_editor.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  runApp(const ExampleApp());
}

class ExampleApp extends StatefulWidget {
  const ExampleApp({super.key});

  @override
  State<ExampleApp> createState() => _ExampleAppState();
}

class _ExampleAppState extends State<ExampleApp> {
  String? _inputPath;
  String? _outputPath;
  String? _thumbnailPath;
  String _status = 'Pick a video to begin.';
  bool _isBusy = false;

  Future<void> _pickVideo() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.video);
    final path = result?.files.single.path;

    if (path == null) {
      setState(() => _status = 'No video selected.');
      return;
    }

    setState(() {
      _inputPath = path;
      _outputPath = null;
      _thumbnailPath = null;
      _status = 'Selected: $path';
    });
  }

  Future<void> _process() async {
    final inputPath = _inputPath;
    if (inputPath == null) {
      setState(() => _status = 'Pick a video first.');
      return;
    }

    setState(() {
      _isBusy = true;
      _status = 'Processing video...';
    });

    try {
      final outputPath = await _newCachePath('native_video_editor_output.mp4');
      final result = await NativeVideoEditor.processVideo(
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

      setState(() {
        _outputPath = result;
        _status = 'Video output: $result';
      });
    } catch (error) {
      setState(() => _status = 'Video processing failed: $error');
    } finally {
      setState(() => _isBusy = false);
    }
  }

  Future<void> _extractThumbnail() async {
    final inputPath = _inputPath;
    if (inputPath == null) {
      setState(() => _status = 'Pick a video first.');
      return;
    }

    setState(() {
      _isBusy = true;
      _status = 'Extracting thumbnail...';
    });

    try {
      final outputPath = await _newCachePath('native_video_editor_thumb.jpg');
      final result = await NativeVideoEditor.extractThumbnail(
        VideoThumbnailRequest(
          inputPath: inputPath,
          outputPath: outputPath,
          position: const Duration(seconds: 2),
          quality: 92,
        ),
      );

      setState(() {
        _thumbnailPath = result;
        _status = 'Thumbnail output: $result';
      });
    } catch (error) {
      setState(() => _status = 'Thumbnail extraction failed: $error');
    } finally {
      setState(() => _isBusy = false);
    }
  }

  Future<String> _newCachePath(String fileName) async {
    final directory = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return '${directory.path}${Platform.pathSeparator}$timestamp-$fileName';
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Native Video Editor')),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton.icon(
                onPressed: _isBusy ? null : _pickVideo,
                icon: const Icon(Icons.video_file),
                label: const Text('Pick Video'),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _isBusy ? null : _process,
                child: const Text('Run Native Edit'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _isBusy ? null : _extractThumbnail,
                child: const Text('Extract Thumbnail'),
              ),
              const SizedBox(height: 16),
              if (_isBusy) const LinearProgressIndicator(),
              const SizedBox(height: 16),
              Text(_status),
              if (_inputPath != null) ...[
                const SizedBox(height: 12),
                Text('Input: $_inputPath'),
              ],
              if (_outputPath != null) ...[
                const SizedBox(height: 12),
                Text('Edited video: $_outputPath'),
              ],
              if (_thumbnailPath != null) ...[
                const SizedBox(height: 12),
                Text('Thumbnail: $_thumbnailPath'),
                const SizedBox(height: 8),
                Image.file(File(_thumbnailPath!), height: 160),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

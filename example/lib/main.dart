import 'dart:io';

import 'package:flutter/material.dart';
import 'package:native_video_editor/native_video_editor.dart';

void main() {
  runApp(const ExampleApp());
}

class ExampleApp extends StatefulWidget {
  const ExampleApp({super.key});

  @override
  State<ExampleApp> createState() => _ExampleAppState();
}

class _ExampleAppState extends State<ExampleApp> {
  final _inputController = TextEditingController();
  String? _status;

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  Future<void> _process() async {
    final inputPath = _inputController.text.trim();
    if (inputPath.isEmpty) {
      setState(() => _status = 'Enter an input video path first.');
      return;
    }

    final outputPath =
        '${Directory.systemTemp.path}${Platform.pathSeparator}native_video_editor_phase1.mp4';

    setState(() => _status = 'Processing...');

    try {
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
          muteAudio: true,
        ),
      );

      setState(() => _status = 'Output: $result');
    } catch (error) {
      setState(() => _status = 'Failed: $error');
    }
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
              TextField(
                controller: _inputController,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Input video path',
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _process,
                child: const Text('Run Phase 1 Edit'),
              ),
              const SizedBox(height: 12),
              Text(_status ?? 'Ready.'),
            ],
          ),
        ),
      ),
    );
  }
}

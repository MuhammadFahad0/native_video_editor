import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:native_video_editor/native_video_editor.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

enum _Tool { inspect, compress, join, slideshow, overlays, thumbnails }

/// Interactive examples of the package's composition and inspection APIs.
class AdvancedToolsScreen extends StatefulWidget {
  const AdvancedToolsScreen({super.key});
  @override
  State<AdvancedToolsScreen> createState() => _AdvancedToolsScreenState();
}

class _AdvancedToolsScreenState extends State<AdvancedToolsScreen> {
  _Tool _tool = _Tool.inspect;
  List<String> _videos = [], _images = [];
  String? _music, _activePath;
  VideoPlayerController? _player;
  final _caption = TextEditingController();
  final _bitrate = TextEditingController(text: '2000000');
  final _fps = TextEditingController(text: '30');
  final _offset = TextEditingController(text: '0');
  VideoFit _fit = VideoFit.contain;
  bool _flipX = false, _flipY = false, _loop = true, _busy = false;
  double _volume = .3, _originalVolume = 1, _progress = 0;
  String _status = 'Choose a tool and select its source files.';

  @override
  void dispose() {
    _player?.dispose();
    for (final controller in [_caption, _bitrate, _fps, _offset]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _pick(String kind) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: kind != 'music',
    );
    if (result == null || !mounted) return;
    final paths = result.files.map((f) => f.path).whereType<String>().toList();
    setState(() {
      if (kind == 'videos') {
        _videos = paths;
      } else if (kind == 'images') {
        _images = paths;
      } else {
        _music = paths.firstOrNull;
      }
    });
  }

  Future<void> _run() async {
    setState(() {
      _busy = true;
      _progress = 0;
      _status = 'Working…';
    });
    try {
      final directory = await getTemporaryDirectory();
      final prefix =
          '${directory.path}${Platform.pathSeparator}${DateTime.now().microsecondsSinceEpoch}';
      final output = '$prefix.mp4';
      final settings = VideoExportSettings(
        width: 1280,
        height: 720,
        frameRate: int.parse(_fps.text),
        videoBitrate: int.parse(_bitrate.text),
      );
      void progress(double value) {
        if (mounted) setState(() => _progress = value);
      }

      String video() {
        if (_videos.isEmpty) throw ArgumentError('Select a video first.');
        return _videos.first;
      }

      final audio = _music == null
          ? <CompositionAudioTrack>[]
          : [
              CompositionAudioTrack(
                _music!,
                volume: _volume,
                loop: _loop,
                start: Duration(milliseconds: int.parse(_offset.text)),
              ),
            ];
      String? result;
      _activePath = output;
      switch (_tool) {
        case _Tool.inspect:
          final info = await NativeVideoEditor.getMediaInfo(video());
          if (mounted) {
            setState(
              () => _status =
                  '${info.width} × ${info.height} • '
                  '${info.duration.inMilliseconds / 1000}s • ${info.frameRate ?? "unknown"} FPS\n'
                  'Video: ${info.videoCodec ?? "unknown"} • Audio: ${info.audioCodec ?? info.hasAudio}\n'
                  'Bitrate: ${info.bitrate ?? "unknown"} • Rotation: ${info.rotationDegrees}°',
            );
          }
        case _Tool.compress:
          result = await NativeVideoEditor.compressVideo(
            inputPath: video(),
            outputPath: output,
            settings: settings,
            fit: _fit,
            flipHorizontal: _flipX,
            flipVertical: _flipY,
            onProgress: progress,
          );
        case _Tool.join:
          result = await NativeVideoEditor.joinVideos(
            inputPaths: _videos,
            outputPath: output,
            settings: settings,
            fit: _fit,
            onProgress: progress,
          );
        case _Tool.slideshow:
          result = await NativeVideoEditor.createSlideshow(
            imagePaths: _images,
            outputPath: output,
            settings: settings,
            fit: _fit,
            audioTracks: audio,
            onProgress: progress,
          );
        case _Tool.overlays:
          result = await NativeVideoEditor.composeVideo(
            VideoCompositionRequest(
              outputPath: output,
              settings: settings,
              clips: [
                VideoClip.video(
                  video(),
                  volume: _originalVolume,
                  fit: _fit,
                  flipHorizontal: _flipX,
                  flipVertical: _flipY,
                ),
              ],
              audioTracks: audio,
              overlays: [
                if (_images.isNotEmpty)
                  VideoOverlay.image(
                    _images.first,
                    rect: const VideoCropRect(
                      left: .02,
                      top: .02,
                      width: .2,
                      height: .2,
                    ),
                    opacity: .8,
                  ),
                if (_caption.text.isNotEmpty)
                  VideoOverlay.text(
                    _caption.text,
                    rect: const VideoCropRect(
                      left: .05,
                      top: .8,
                      width: .9,
                      height: .15,
                    ),
                    fontSize: 40,
                  ),
                if (_videos.length > 1)
                  VideoOverlay.video(
                    _videos[1],
                    rect: const VideoCropRect(
                      left: .65,
                      top: .05,
                      width: .3,
                      height: .3,
                    ),
                  ),
              ],
            ),
            onProgress: progress,
          );
        case _Tool.thumbnails:
          final source = video();
          final info = await NativeVideoEditor.getMediaInfo(source);
          final paths = await NativeVideoEditor.extractThumbnails(
            inputPath: source,
            positions: List.generate(
              5,
              (i) =>
                  Duration(milliseconds: info.duration.inMilliseconds * i ~/ 5),
            ),
            outputPaths: List.generate(5, (i) => '$prefix-$i.jpg'),
            onProgress: progress,
          );
          if (mounted) {
            setState(() => _status = 'Thumbnails:\n${paths.join("\n")}');
          }
      }
      if (result != null) {
        await _player?.dispose();
        final player = VideoPlayerController.file(File(result));
        await player.initialize();
        if (!mounted) {
          await player.dispose();
          return;
        }
        setState(() {
          _player = player;
          _status = 'Export complete:\n$result';
        });
        await player.setLooping(true);
        await player.play();
      }
    } catch (error) {
      if (mounted) setState(() => _status = 'Failed: $error');
    } finally {
      _activePath = null;
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('More video tools')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        DropdownButton<_Tool>(
          value: _tool,
          isExpanded: true,
          items: const [
            DropdownMenuItem(
              value: _Tool.inspect,
              child: Text('Media information'),
            ),
            DropdownMenuItem(
              value: _Tool.compress,
              child: Text('Compress and flip'),
            ),
            DropdownMenuItem(value: _Tool.join, child: Text('Join videos')),
            DropdownMenuItem(
              value: _Tool.slideshow,
              child: Text('Image slideshow'),
            ),
            DropdownMenuItem(
              value: _Tool.overlays,
              child: Text('Watermark, captions and picture-in-picture'),
            ),
            DropdownMenuItem(
              value: _Tool.thumbnails,
              child: Text('Timeline thumbnails'),
            ),
          ],
          onChanged: _busy ? null : (value) => setState(() => _tool = value!),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: _busy ? null : () => _pick('videos'),
          child: Text('Select videos (${_videos.length})'),
        ),
        OutlinedButton(
          onPressed: _busy ? null : () => _pick('images'),
          child: Text('Select images (${_images.length})'),
        ),
        OutlinedButton(
          onPressed: _busy ? null : () => _pick('music'),
          child: Text(
            _music == null ? 'Select background audio' : 'Audio selected',
          ),
        ),
        const Text(
          'For overlays, the first video is the background, the second is picture-in-picture, and the first image is the watermark.',
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _caption,
          enabled: !_busy,
          decoration: const InputDecoration(labelText: 'Caption'),
        ),
        TextField(
          controller: _bitrate,
          enabled: !_busy,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Video bitrate (bits/sec), output 1280 × 720',
          ),
        ),
        TextField(
          controller: _fps,
          enabled: !_busy,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Frame rate'),
        ),
        DropdownButton<VideoFit>(
          value: _fit,
          items: VideoFit.values
              .map((fit) => DropdownMenuItem(value: fit, child: Text(fit.name)))
              .toList(),
          onChanged: _busy ? null : (fit) => setState(() => _fit = fit!),
        ),
        SwitchListTile(
          title: const Text('Flip horizontally'),
          value: _flipX,
          onChanged: _busy ? null : (v) => setState(() => _flipX = v),
        ),
        SwitchListTile(
          title: const Text('Flip vertically'),
          value: _flipY,
          onChanged: _busy ? null : (v) => setState(() => _flipY = v),
        ),
        Text('Original audio volume: ${(_originalVolume * 100).round()}%'),
        Slider(
          value: _originalVolume,
          onChanged: _busy ? null : (v) => setState(() => _originalVolume = v),
        ),
        Text('Music volume: ${(_volume * 100).round()}%'),
        Slider(
          value: _volume,
          onChanged: _busy ? null : (v) => setState(() => _volume = v),
        ),
        TextField(
          controller: _offset,
          enabled: !_busy,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Music delay (milliseconds)',
          ),
        ),
        SwitchListTile(
          title: const Text('Loop background audio'),
          value: _loop,
          onChanged: _busy ? null : (v) => setState(() => _loop = v),
        ),
        if (_busy) ...[
          LinearProgressIndicator(value: _progress > 0 ? _progress : null),
          if (_tool != _Tool.inspect && _tool != _Tool.thumbnails)
            TextButton(
              onPressed: () async {
                final path = _activePath;
                if (path != null) {
                  await NativeVideoEditor.cancelProcessVideo(path);
                }
              },
              child: const Text('Cancel'),
            ),
        ],
        FilledButton(
          onPressed: _busy ? null : _run,
          child: const Text('Run tool'),
        ),
        const SizedBox(height: 12),
        SelectableText(_status),
        if (_player != null && _player!.value.isInitialized)
          AspectRatio(
            aspectRatio: _player!.value.aspectRatio,
            child: VideoPlayer(_player!),
          ),
      ],
    ),
  );
}

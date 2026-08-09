import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:native_video_editor/native_video_editor.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

/// A standalone tab screen that demonstrates [NativeVideoEditor.composeImageWithAudio]
/// and [NativeVideoEditor.mergeAudioIntoVideo].
class ComposeScreen extends StatefulWidget {
  const ComposeScreen({super.key});

  @override
  State<ComposeScreen> createState() => _ComposeScreenState();
}

class _ComposeScreenState extends State<ComposeScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TabBar(
          controller: _tabController,
          indicatorColor: Colors.tealAccent,
          labelColor: Colors.tealAccent,
          unselectedLabelColor: Colors.white54,
          tabs: const [
            Tab(icon: Icon(Icons.image_rounded), text: 'Image → Video'),
            Tab(icon: Icon(Icons.music_note_rounded), text: 'Add Audio'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: const [_ImageComposePane(), _AudioMergePane()],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Pane 1 — composeImageWithAudio
// ─────────────────────────────────────────────────────────────────────────────

class _ImageComposePane extends StatefulWidget {
  const _ImageComposePane();

  @override
  State<_ImageComposePane> createState() => _ImageComposePaneState();
}

class _ImageComposePaneState extends State<_ImageComposePane> {
  String? _imagePath;
  String? _audioPath;
  String? _outputPath;
  VideoPlayerController? _outputController;

  bool _isProcessing = false;
  double _progress = 0;
  String _status = 'Pick an image and an audio file to compose a video.';

  String? _selectedResolution = '1080x1920';

  @override
  void dispose() {
    _outputController?.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    final path = result?.files.single.path;
    if (path == null) return;
    setState(() {
      _imagePath = path;
      _status = 'Image selected.';
    });
  }

  Future<void> _pickAudio() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.audio);
    final path = result?.files.single.path;
    if (path == null) return;
    setState(() {
      _audioPath = path;
      _status = 'Audio selected.';
    });
  }

  Future<String> _getCachePath(String name) async {
    final dir = await getTemporaryDirectory();
    final ts = DateTime.now().millisecondsSinceEpoch;
    return '${dir.path}${Platform.pathSeparator}$ts-$name';
  }

  Future<void> _compose() async {
    final imagePath = _imagePath;
    final audioPath = _audioPath;
    if (imagePath == null || audioPath == null) {
      setState(
        () => _status = 'Please select both an image and an audio file.',
      );
      return;
    }

    final outputPath = await _getCachePath('composed.mp4');
    final parts = _selectedResolution!.split('x');
    final w = int.parse(parts[0]);
    final h = int.parse(parts[1]);

    setState(() {
      _isProcessing = true;
      _progress = 0;
      _status = 'Composing…';
    });

    try {
      final result = await NativeVideoEditor.composeImageWithAudio(
        ImageVideoComposeRequest(
          imagePath: imagePath,
          audioPath: audioPath,
          outputPath: outputPath,
          targetWidth: w,
          targetHeight: h,
        ),
        onProgress: (p) {
          if (!mounted) return;
          setState(() {
            _progress = p;
            _status = 'Composing: ${(p * 100).toStringAsFixed(0)}%';
          });
        },
      );

      await _outputController?.dispose();
      final ctrl = VideoPlayerController.file(File(result));
      await ctrl.initialize();
      ctrl.setLooping(true);

      setState(() {
        _outputPath = result;
        _outputController = ctrl;
        _status = 'Done! Tap ▶ to play.';
      });
      ctrl.play();
    } catch (e) {
      setState(() => _status = 'Error: $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header ──────────────────────────────────────────────────────
          _SectionHeader(
            icon: Icons.image_rounded,
            title: 'composeImageWithAudio',
            color: Colors.tealAccent,
          ),
          const SizedBox(height: 4),
          const Text(
            'Turns a still image + audio file into an MP4 video.',
            style: TextStyle(color: Colors.white54, fontSize: 13),
          ),
          const SizedBox(height: 16),

          // ── Pick buttons ─────────────────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: _PickCard(
                  icon: Icons.photo_library_rounded,
                  label: _imagePath != null
                      ? File(_imagePath!).uri.pathSegments.last
                      : 'Pick Image',
                  color: Colors.tealAccent,
                  onTap: _isProcessing ? null : _pickImage,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _PickCard(
                  icon: Icons.audio_file_rounded,
                  label: _audioPath != null
                      ? File(_audioPath!).uri.pathSegments.last
                      : 'Pick Audio',
                  color: Colors.tealAccent,
                  onTap: _isProcessing ? null : _pickAudio,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ── Resolution picker ────────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Output Resolution',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              DropdownButton<String>(
                value: _selectedResolution,
                items: const [
                  DropdownMenuItem(
                    value: '1080x1920',
                    child: Text('1080×1920 (9:16)'),
                  ),
                  DropdownMenuItem(
                    value: '1080x1080',
                    child: Text('1080×1080 (1:1)'),
                  ),
                  DropdownMenuItem(
                    value: '1920x1080',
                    child: Text('1920×1080 (16:9)'),
                  ),
                  DropdownMenuItem(
                    value: '720x1280',
                    child: Text('720×1280 (9:16 HD)'),
                  ),
                ],
                onChanged: _isProcessing
                    ? null
                    : (v) => setState(() => _selectedResolution = v),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ── Compose button ───────────────────────────────────────────────
          FilledButton.icon(
            onPressed:
                (_isProcessing || _imagePath == null || _audioPath == null)
                ? null
                : _compose,
            icon: const Icon(Icons.movie_creation_outlined),
            label: const Text('Compose to Video'),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.tealAccent,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
          const SizedBox(height: 12),

          // ── Progress + status ────────────────────────────────────────────
          if (_isProcessing)
            LinearProgressIndicator(
              value: _progress > 0 ? _progress : null,
              color: Colors.tealAccent,
              backgroundColor: Colors.white10,
            ),
          const SizedBox(height: 8),
          Text(
            _status,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 12),

          // ── Output preview ───────────────────────────────────────────────
          if (_outputController != null) ...[
            const Divider(),
            const Text(
              'Output Preview',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AspectRatio(
                aspectRatio: _outputController!.value.aspectRatio > 0
                    ? _outputController!.value.aspectRatio
                    : 9 / 16,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    VideoPlayer(_outputController!),
                    FloatingActionButton.small(
                      heroTag: 'compose_play',
                      backgroundColor: Colors.black54,
                      onPressed: () {
                        setState(() {
                          _outputController!.value.isPlaying
                              ? _outputController!.pause()
                              : _outputController!.play();
                        });
                      },
                      child: Icon(
                        _outputController!.value.isPlaying
                            ? Icons.pause
                            : Icons.play_arrow,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            SelectableText(
              'Output: $_outputPath',
              style: const TextStyle(fontSize: 11, color: Colors.white38),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Pane 2 — mergeAudioIntoVideo
// ─────────────────────────────────────────────────────────────────────────────

class _AudioMergePane extends StatefulWidget {
  const _AudioMergePane();

  @override
  State<_AudioMergePane> createState() => _AudioMergePaneState();
}

class _AudioMergePaneState extends State<_AudioMergePane> {
  static const _supportedVideoExtensions = <String>{
    '3gp',
    'avi',
    'm4v',
    'mkv',
    'mov',
    'mp4',
    'mpeg',
    'mpg',
    'ts',
    'webm',
  };

  String? _videoPath;
  String? _audioPath;
  String? _outputPath;
  VideoPlayerController? _outputController;

  bool _isProcessing = false;
  double _progress = 0;
  bool _replaceExistingAudio = true;
  String _status = 'Pick a video and an audio file to merge.';

  @override
  void dispose() {
    _outputController?.dispose();
    super.dispose();
  }

  Future<void> _pickVideo() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: _supportedVideoExtensions.toList(),
    );
    final pickedFile = result?.files.single;
    final path = pickedFile?.path;
    if (path == null) return;
    final ext = (pickedFile?.extension ?? '').toLowerCase();
    if (!_supportedVideoExtensions.contains(ext)) {
      setState(() => _status = 'Unsupported file. Please pick a video.');
      return;
    }
    setState(() {
      _videoPath = path;
      _status = 'Video selected.';
    });
  }

  Future<void> _pickAudio() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.audio);
    final path = result?.files.single.path;
    if (path == null) return;
    setState(() {
      _audioPath = path;
      _status = 'Audio selected.';
    });
  }

  Future<String> _getCachePath(String name) async {
    final dir = await getTemporaryDirectory();
    final ts = DateTime.now().millisecondsSinceEpoch;
    return '${dir.path}${Platform.pathSeparator}$ts-$name';
  }

  Future<void> _merge() async {
    final videoPath = _videoPath;
    final audioPath = _audioPath;
    if (videoPath == null || audioPath == null) {
      setState(() => _status = 'Please select both a video and an audio file.');
      return;
    }

    final outputPath = await _getCachePath('merged.mp4');

    setState(() {
      _isProcessing = true;
      _progress = 0;
      _status = 'Merging…';
    });

    try {
      final result = await NativeVideoEditor.mergeAudioIntoVideo(
        AudioMergeRequest(
          inputVideoPath: videoPath,
          audioPath: audioPath,
          outputPath: outputPath,
          replaceExistingAudio: _replaceExistingAudio,
        ),
        onProgress: (p) {
          if (!mounted) return;
          setState(() {
            _progress = p;
            _status = 'Merging: ${(p * 100).toStringAsFixed(0)}%';
          });
        },
      );

      await _outputController?.dispose();
      final ctrl = VideoPlayerController.file(File(result));
      await ctrl.initialize();
      ctrl.setLooping(true);

      setState(() {
        _outputPath = result;
        _outputController = ctrl;
        _status = 'Done! Tap ▶ to play.';
      });
      ctrl.play();
    } catch (e) {
      setState(() => _status = 'Error: $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header ──────────────────────────────────────────────────────
          _SectionHeader(
            icon: Icons.music_video_rounded,
            title: 'mergeAudioIntoVideo',
            color: Colors.purpleAccent,
          ),
          const SizedBox(height: 4),
          const Text(
            'Injects a new audio track into an existing video file.',
            style: TextStyle(color: Colors.white54, fontSize: 13),
          ),
          const SizedBox(height: 16),

          // ── Pick buttons ─────────────────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: _PickCard(
                  icon: Icons.video_file_rounded,
                  label: _videoPath != null
                      ? File(_videoPath!).uri.pathSegments.last
                      : 'Pick Video',
                  color: Colors.purpleAccent,
                  onTap: _isProcessing ? null : _pickVideo,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _PickCard(
                  icon: Icons.audio_file_rounded,
                  label: _audioPath != null
                      ? File(_audioPath!).uri.pathSegments.last
                      : 'Pick Audio',
                  color: Colors.purpleAccent,
                  onTap: _isProcessing ? null : _pickAudio,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ── Replace audio switch ─────────────────────────────────────────
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Replace existing audio'),
            subtitle: const Text(
              'Strip original audio before injecting new track',
              style: TextStyle(fontSize: 12),
            ),
            value: _replaceExistingAudio,
            activeTrackColor: Colors.purpleAccent,
            onChanged: _isProcessing
                ? null
                : (v) => setState(() => _replaceExistingAudio = v),
          ),
          const SizedBox(height: 8),

          // ── Merge button ─────────────────────────────────────────────────
          FilledButton.icon(
            onPressed:
                (_isProcessing || _videoPath == null || _audioPath == null)
                ? null
                : _merge,
            icon: const Icon(Icons.merge_type_rounded),
            label: const Text('Merge Audio into Video'),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.purpleAccent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
          const SizedBox(height: 12),

          // ── Progress + status ────────────────────────────────────────────
          if (_isProcessing)
            LinearProgressIndicator(
              value: _progress > 0 ? _progress : null,
              color: Colors.purpleAccent,
              backgroundColor: Colors.white10,
            ),
          const SizedBox(height: 8),
          Text(
            _status,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 12),

          // ── Output preview ───────────────────────────────────────────────
          if (_outputController != null) ...[
            const Divider(),
            const Text(
              'Output Preview',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AspectRatio(
                aspectRatio: _outputController!.value.aspectRatio > 0
                    ? _outputController!.value.aspectRatio
                    : 16 / 9,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    VideoPlayer(_outputController!),
                    FloatingActionButton.small(
                      heroTag: 'merge_play',
                      backgroundColor: Colors.black54,
                      onPressed: () {
                        setState(() {
                          _outputController!.value.isPlaying
                              ? _outputController!.pause()
                              : _outputController!.play();
                        });
                      },
                      child: Icon(
                        _outputController!.value.isPlaying
                            ? Icons.pause
                            : Icons.play_arrow,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            SelectableText(
              'Output: $_outputPath',
              style: const TextStyle(fontSize: 11, color: Colors.white38),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared small widgets
// ─────────────────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.color,
  });

  final IconData icon;
  final String title;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            color: color,
            fontSize: 15,
            fontWeight: FontWeight.bold,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }
}

class _PickCard extends StatelessWidget {
  const _PickCard({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: onTap != null ? Colors.white : Colors.white38,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

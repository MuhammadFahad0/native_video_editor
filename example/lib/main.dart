import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:native_video_editor/native_video_editor.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import 'widgets/compose_screen.dart';
import 'widgets/interactive_crop_overlay.dart';
import 'widgets/timeline_trim_slider.dart';

void main() {
  runApp(const NativeVideoEditorExampleApp());
}

class NativeVideoEditorExampleApp extends StatelessWidget {
  const NativeVideoEditorExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Native Video Editor',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F0F1A),
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurpleAccent,
          brightness: Brightness.dark,
          surface: const Color(0xFF181828),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF141424),
          elevation: 0,
        ),
      ),
      home: const VideoEditorHomeScreen(),
    );
  }
}

class VideoEditorHomeScreen extends StatefulWidget {
  const VideoEditorHomeScreen({super.key});

  @override
  State<VideoEditorHomeScreen> createState() => _VideoEditorHomeScreenState();
}

class _VideoEditorHomeScreenState extends State<VideoEditorHomeScreen>
    with SingleTickerProviderStateMixin {
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

  String? _inputPath;
  String? _outputPath;
  String? _thumbnailPath;
  String? _activeExportPath;

  VideoPlayerController? _inputController;
  VideoPlayerController? _outputController;

  Duration _videoDuration = Duration.zero;
  Duration _trimStart = Duration.zero;
  Duration _trimEnd = Duration.zero;
  Duration _currentPosition = Duration.zero;

  VideoCropRect _cropRect = const VideoCropRect(
    left: 0.0,
    top: 0.0,
    width: 1.0,
    height: 1.0,
  );
  bool _showCropOverlay = true;

  int _rotationDegrees = 0;
  double _speedMultiplier = 1.0;
  bool _muteAudio = false;

  int? _targetWidth;
  int? _targetHeight;

  bool _isProcessing = false;
  double _exportProgress = 0.0;
  DateTime? _exportStartTime;
  Duration? _estimatedTimeRemaining;
  String _statusMessage = 'Pick a video file to begin editing.';

  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _inputController?.dispose();
    _outputController?.dispose();
    _tabController.dispose();
    super.dispose();
  }

  /// Returns a [VideoPlayerController] that works for both plain filesystem
  /// paths and Android content:// URIs returned by FilePicker / system picker.
  VideoPlayerController _makeController(String path) {
    if (path.startsWith('content://')) {
      return VideoPlayerController.contentUri(Uri.parse(path));
    }
    return VideoPlayerController.file(File(path));
  }

  /// Ensures the native plugin receives a usable path.
  /// For content:// URIs, the native Android layer's parseUri() helper
  /// resolves them correctly via ContentResolver, so we pass them as-is.
  Future<String> _resolveInputPath(String path) async {
    return path;
  }

  Future<void> _pickVideo() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        // FileType.custom with allowedExtensions has a Windows bug where the
        // native IFileOpenDialog silently returns null after file selection.
        // Use FileType.any and validate the extension in Dart instead.
        type: FileType.any,
        allowMultiple: false,
        withData: false,
        withReadStream: false,
      );
      final pickedFile = result?.files.firstOrNull;
      final path = pickedFile?.path;

      // Show explicit feedback for every case instead of silent returns.
      if (result == null) {
        // User cancelled the picker — that's fine, do nothing.
        return;
      }
      if (path == null || path.isEmpty) {
        // file_picker returned a result but path is null — this is a bug.
        setState(() {
          _statusMessage =
              'Could not get file path. '
              'Try moving the file out of a system or protected folder.';
        });
        return;
      }

      // Some Android document providers do not honor the requested MIME or
      // extension filter. Reject their non-video results before ExoPlayer tries
      // to parse them and reports an opaque UnrecognizedInputFormatException.
      final extension = (pickedFile?.extension ?? '').toLowerCase();
      if (!_supportedVideoExtensions.contains(extension)) {
        if (mounted) {
          setState(() {
            _statusMessage =
                'Unsupported file "${pickedFile?.name}". Please select a video.';
          });
        }
        return;
      }

      // For plain file paths, validate that the file exists and is non-empty.
      // For content:// URIs we skip this check and let the controller handle it.
      if (!path.startsWith('content://')) {
        final file = File(path);
        if (!await file.exists() || (await file.length()) == 0) {
          setState(() {
            _statusMessage = 'Selected file is empty or invalid.';
          });
          return;
        }
      }

      // Show loading feedback immediately so the user knows something is happening.
      if (mounted) {
        setState(() {
          _statusMessage = 'Loading video, please wait…';
          _isProcessing = true;
        });
      }

      await _inputController?.dispose();
      await _outputController?.dispose();

      final controller = _makeController(path);

      // On Windows, VideoPlayerController.initialize() can hang indefinitely
      // when the codec is missing (HEVC, VP9, some MKV/WebM variants).
      // Guard with a timeout so we show a clear error instead of freezing.
      try {
        await controller.initialize().timeout(
          const Duration(seconds: 15),
          onTimeout: () {
            controller.dispose();
            throw Exception(
              'Timed out loading video. On Windows, make sure the required '
              'codec is installed (e.g. "HEVC Video Extensions" from the '
              'Microsoft Store), or convert the file to H.264 MP4 first.',
            );
          },
        );
      } catch (initErr) {
        if (mounted) {
          setState(() {
            _isProcessing = false;
            _statusMessage = 'Failed to load video: $initErr';
          });
        }
        return;
      }

      final duration = controller.value.duration;

      setState(() {
        _inputPath = path;
        _outputPath = null;
        _thumbnailPath = null;
        _outputController = null;
        _inputController = controller;
        _videoDuration = duration;
        _trimStart = Duration.zero;
        _trimEnd = duration;
        _currentPosition = Duration.zero;
        _cropRect = const VideoCropRect(
          left: 0.0,
          top: 0.0,
          width: 1.0,
          height: 1.0,
        );
        _rotationDegrees = 0;
        _speedMultiplier = 1.0;
        _muteAudio = false;
        _targetWidth = null;
        _targetHeight = null;
        _isProcessing = false;
        _statusMessage =
            'Video loaded: ${controller.value.size.width.toInt()}x${controller.value.size.height.toInt()}';
      });

      controller.addListener(() {
        if (mounted && controller.value.isPlaying) {
          setState(() {
            _currentPosition = controller.value.position;
          });
        }
      });

      controller.setLooping(true);
      controller.play();
    } catch (e) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _statusMessage = 'Failed to load video: $e';
        });
      }
    }
  }

  void _seekTo(Duration position) {
    _inputController?.seekTo(position);
    setState(() {
      _currentPosition = position;
    });
  }

  void _setAspectPreset(double aspect) {
    if (aspect == 0) {
      // Full / Free
      setState(() {
        _cropRect = const VideoCropRect(left: 0, top: 0, width: 1, height: 1);
      });
      return;
    }

    final videoAspect = _inputController?.value.aspectRatio ?? 1.0;
    double newWidth = 1.0;
    double newHeight = 1.0;

    if (aspect > videoAspect) {
      newHeight = videoAspect / aspect;
    } else {
      newWidth = aspect / videoAspect;
    }

    newWidth = newWidth.clamp(0.2, 1.0);
    newHeight = newHeight.clamp(0.2, 1.0);

    final left = (1.0 - newWidth) / 2;
    final top = (1.0 - newHeight) / 2;

    setState(() {
      _cropRect = VideoCropRect(
        left: double.parse(left.toStringAsFixed(3)),
        top: double.parse(top.toStringAsFixed(3)),
        width: double.parse(newWidth.toStringAsFixed(3)),
        height: double.parse(newHeight.toStringAsFixed(3)),
      );
    });
  }

  Future<void> _processVideo() async {
    final rawInputPath = _inputPath;
    if (rawInputPath == null) return;

    // Resolve content:// URIs to a real filesystem path for the native plugin.
    final inputPath = await _resolveInputPath(rawInputPath);

    final outputPath = await _getCachePath('edited_export.mp4');

    setState(() {
      _isProcessing = true;
      _exportProgress = 0.0;
      _exportStartTime = DateTime.now();
      _estimatedTimeRemaining = null;
      _activeExportPath = outputPath;
      _statusMessage = 'Exporting native video edits...';
    });

    _inputController?.pause();

    try {
      final request = VideoEditRequest(
        inputPath: inputPath,
        outputPath: outputPath,
        trimStart: _trimStart > Duration.zero ? _trimStart : null,
        trimEnd: _trimEnd < _videoDuration ? _trimEnd : null,
        cropRect:
            (_cropRect.left == 0 &&
                _cropRect.top == 0 &&
                _cropRect.width == 1 &&
                _cropRect.height == 1)
            ? null
            : _cropRect,
        targetWidth: _targetWidth,
        targetHeight: _targetHeight,
        rotationDegrees: _rotationDegrees,
        speedMultiplier: _speedMultiplier,
        muteAudio: _muteAudio,
      );

      final resultPath = await NativeVideoEditor.processVideo(
        request,
        onProgress: (progress) {
          if (!mounted) return;
          final now = DateTime.now();
          final elapsed = now.difference(_exportStartTime!);
          Duration? eta;
          if (progress > 0.05) {
            final totalEstMs = elapsed.inMilliseconds / progress;
            final remainingMs = totalEstMs - elapsed.inMilliseconds;
            eta = Duration(milliseconds: remainingMs.round());
          }

          setState(() {
            _exportProgress = progress;
            _estimatedTimeRemaining = eta;
            _statusMessage =
                'Exporting: ${(progress * 100).toStringAsFixed(0)}%';
          });
        },
      );

      await _outputController?.dispose();
      final outController = VideoPlayerController.file(File(resultPath));
      await outController.initialize();
      outController.setLooping(true);

      setState(() {
        _outputPath = resultPath;
        _outputController = outController;
        _statusMessage = 'Export complete!';
        _tabController.animateTo(2); // Switch to Output Tab
      });

      outController.play();
    } catch (error) {
      if (mounted) {
        setState(() {
          _statusMessage = 'Export failed: $error';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _activeExportPath = null;
        });
      }
    }
  }

  Future<void> _cancelExport() async {
    final path = _activeExportPath;
    if (path == null) return;
    try {
      await NativeVideoEditor.cancelProcessVideo(path);
      setState(() {
        _statusMessage = 'Export cancelled by user.';
      });
    } catch (e) {
      setState(() {
        _statusMessage = 'Cancellation error: $e';
      });
    }
  }

  Future<void> _extractThumbnail() async {
    final inputPath = _inputPath;
    if (inputPath == null) return;

    final outputPath = await _getCachePath('thumbnail.jpg');
    try {
      final result = await NativeVideoEditor.extractThumbnail(
        VideoThumbnailRequest(
          inputPath: inputPath,
          outputPath: outputPath,
          position: _currentPosition,
          quality: 90,
        ),
      );

      setState(() {
        _thumbnailPath = result;
        _statusMessage =
            'Extracted thumbnail at ${_currentPosition.inSeconds}s';
      });
    } catch (e) {
      setState(() {
        _statusMessage = 'Thumbnail extraction failed: $e';
      });
    }
  }

  Future<String> _getCachePath(String fileName) async {
    final dir = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return '${dir.path}${Platform.pathSeparator}$timestamp-$fileName';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.video_library_rounded, color: Colors.deepPurpleAccent),
            SizedBox(width: 8),
            Text(
              'Native Video Editor',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.folder_open),
            tooltip: 'Pick Video',
            onPressed: _isProcessing ? null : _pickVideo,
          ),
        ],
        bottom: _inputController != null
            ? TabBar(
                controller: _tabController,
                indicatorColor: Colors.deepPurpleAccent,
                isScrollable: true,
                tabs: const [
                  Tab(icon: Icon(Icons.crop_rotate), text: 'Canvas & Crop'),
                  Tab(icon: Icon(Icons.tune), text: 'Trim & Adjust'),
                  Tab(
                    icon: Icon(Icons.video_collection),
                    text: 'Result Preview',
                  ),
                  Tab(icon: Icon(Icons.add_to_photos_rounded), text: 'Compose'),
                ],
              )
            : null,
      ),
      body: _inputController == null
          ? _buildEmptyState()
          : Column(
              children: [
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildCanvasTab(),
                      _buildControlsTab(),
                      _buildResultTab(),
                      const ComposeScreen(),
                    ],
                  ),
                ),
                if (_isProcessing) _buildExportBanner(),
                _buildBottomActionBar(),
              ],
            ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.deepPurpleAccent.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.video_call_rounded,
                size: 64,
                color: Colors.deepPurpleAccent,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'No Video Selected',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Pick a video file from your device to edit natively with AVFoundation & Media3 Transformer.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _pickVideo,
              icon: const Icon(Icons.add_circle_outline),
              label: const Text('Select Video File'),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.deepPurpleAccent,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCanvasTab() {
    final controller = _inputController!;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Video Preview Container with Crop Overlay
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Container(
              color: Colors.black,
              constraints: const BoxConstraints(maxHeight: 360),
              child: AspectRatio(
                aspectRatio: controller.value.aspectRatio > 0
                    ? controller.value.aspectRatio
                    : 16 / 9,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    VideoPlayer(controller),
                    if (_showCropOverlay)
                      InteractiveCropOverlay(
                        cropRect: _cropRect,
                        onChanged: (rect) {
                          setState(() {
                            _cropRect = rect;
                          });
                        },
                      ),
                    // Floating Play/Pause Button
                    Positioned(
                      bottom: 12,
                      right: 12,
                      child: FloatingActionButton.small(
                        heroTag: 'play_pause',
                        backgroundColor: Colors.black54,
                        onPressed: () {
                          setState(() {
                            controller.value.isPlaying
                                ? controller.pause()
                                : controller.play();
                          });
                        },
                        child: Icon(
                          controller.value.isPlaying
                              ? Icons.pause
                              : Icons.play_arrow,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Aspect Ratio Presets
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Crop Presets',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              Switch(
                value: _showCropOverlay,
                activeTrackColor: Colors.deepPurpleAccent,
                onChanged: (v) => setState(() => _showCropOverlay = v),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildAspectChip('Free', 0.0),
                _buildAspectChip('1:1 Square', 1.0),
                _buildAspectChip('16:9 Landscape', 16 / 9),
                _buildAspectChip('9:16 Portrait', 9 / 16),
                _buildAspectChip('4:5 Social', 4 / 5),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAspectChip(String label, double ratio) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: false,
        selectedColor: Colors.deepPurpleAccent,
        onSelected: (_) => _setAspectPreset(ratio),
      ),
    );
  }

  Widget _buildControlsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timeline Trim Slider
          const Text(
            'Trim Selection',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 8),
          TimelineTrimSlider(
            duration: _videoDuration,
            trimStart: _trimStart,
            trimEnd: _trimEnd,
            currentPosition: _currentPosition,
            onTrimChanged: (start, end) {
              setState(() {
                _trimStart = start;
                _trimEnd = end;
              });
            },
            onSeek: _seekTo,
          ),
          const SizedBox(height: 20),

          // Rotation Selection
          const Text(
            'Rotation',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [0, 90, 180, 270].map((deg) {
              final selected = _rotationDegrees == deg;
              return ChoiceChip(
                label: Text('$deg°'),
                selected: selected,
                selectedColor: Colors.deepPurpleAccent,
                onSelected: (_) => setState(() => _rotationDegrees = deg),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),

          // Playback Speed Multiplier
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Speed Multiplier',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              Text(
                '${_speedMultiplier.toStringAsFixed(2)}x',
                style: const TextStyle(
                  color: Colors.deepPurpleAccent,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          Slider(
            value: _speedMultiplier,
            min: 0.25,
            max: 4.0,
            divisions: 15,
            activeColor: Colors.deepPurpleAccent,
            onChanged: (v) => setState(() => _speedMultiplier = v),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [0.5, 1.0, 1.5, 2.0].map((s) {
              return OutlinedButton(
                onPressed: () => setState(() => _speedMultiplier = s),
                child: Text('${s}x'),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),

          // Mute Switch
          SwitchListTile(
            title: const Text('Mute Audio'),
            subtitle: const Text('Remove audio track from exported video'),
            value: _muteAudio,
            activeTrackColor: Colors.deepPurpleAccent,
            onChanged: (v) => setState(() => _muteAudio = v),
          ),
          const SizedBox(height: 12),

          // Target Resolution Selection
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Target Output Size',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              DropdownButton<String>(
                value: _targetWidth == null
                    ? 'Original'
                    : '${_targetWidth}x$_targetHeight',
                items: const [
                  DropdownMenuItem(
                    value: 'Original',
                    child: Text('Original Resolution'),
                  ),
                  DropdownMenuItem(
                    value: '720x720',
                    child: Text('720 x 720 (Square)'),
                  ),
                  DropdownMenuItem(
                    value: '1280x720',
                    child: Text('1280 x 720 (720p HD)'),
                  ),
                  DropdownMenuItem(
                    value: '1920x1080',
                    child: Text('1920 x 1080 (1080p Full HD)'),
                  ),
                  DropdownMenuItem(
                    value: '480x480',
                    child: Text('480 x 480 (SD)'),
                  ),
                ],
                onChanged: (value) {
                  setState(() {
                    if (value == 'Original' || value == null) {
                      _targetWidth = null;
                      _targetHeight = null;
                    } else {
                      final parts = value.split('x');
                      _targetWidth = int.parse(parts[0]);
                      _targetHeight = int.parse(parts[1]);
                    }
                  });
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildResultTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_outputController != null) ...[
            const Text(
              'Exported Video Preview',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Container(
                color: Colors.black,
                constraints: const BoxConstraints(maxHeight: 280),
                child: AspectRatio(
                  aspectRatio: _outputController!.value.aspectRatio > 0
                      ? _outputController!.value.aspectRatio
                      : 16 / 9,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      VideoPlayer(_outputController!),
                      FloatingActionButton.small(
                        heroTag: 'output_play_pause',
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
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            SelectableText('File Path: $_outputPath'),
            const Divider(height: 32),
          ] else ...[
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No export generated yet. Configure options and tap "Export Video".',
                  style: TextStyle(color: Colors.white54),
                ),
              ),
            ),
          ],

          // Thumbnail Extraction Section
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Thumbnail Extractor',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              FilledButton.icon(
                onPressed: _isProcessing ? null : _extractThumbnail,
                icon: const Icon(Icons.image),
                label: const Text('Extract Frame'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_thumbnailPath != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(
                File(_thumbnailPath!),
                height: 180,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: 4),
            SelectableText('Thumbnail Path: $_thumbnailPath'),
          ],
        ],
      ),
    );
  }

  Widget _buildExportBanner() {
    final etaText = _estimatedTimeRemaining != null
        ? 'ETA: ${(_estimatedTimeRemaining!.inMilliseconds / 1000).toStringAsFixed(1)}s'
        : 'Estimating...';

    return Container(
      color: const Color(0xFF1E1E2C),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Exporting... ${(_exportProgress * 100).toStringAsFixed(0)}%',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                etaText,
                style: const TextStyle(color: Colors.deepPurpleAccent),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: _exportProgress > 0 ? _exportProgress : null,
            color: Colors.deepPurpleAccent,
            backgroundColor: Colors.white10,
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _cancelExport,
            icon: const Icon(Icons.cancel, color: Colors.redAccent),
            label: const Text(
              'Cancel Export',
              style: TextStyle(color: Colors.redAccent),
            ),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomActionBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: const Color(0xFF141424),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: Text(
                _statusMessage,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: Colors.white70),
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              onPressed: (_inputPath == null || _isProcessing)
                  ? null
                  : _processVideo,
              icon: const Icon(Icons.movie_creation_outlined),
              label: const Text('Export Video'),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.deepPurpleAccent,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

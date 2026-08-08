import 'package:flutter/material.dart';

/// Interactive dual-thumb range slider for trimming video start and end durations.
class TimelineTrimSlider extends StatelessWidget {
  const TimelineTrimSlider({
    super.key,
    required this.duration,
    required this.trimStart,
    required this.trimEnd,
    required this.currentPosition,
    required this.onTrimChanged,
    required this.onSeek,
  });

  final Duration duration;
  final Duration trimStart;
  final Duration trimEnd;
  final Duration currentPosition;
  final void Function(Duration start, Duration end) onTrimChanged;
  final ValueChanged<Duration> onSeek;

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    final millis = (duration.inMilliseconds.remainder(1000) ~/ 100).toString();
    return '$minutes:$seconds.$millis';
  }

  @override
  Widget build(BuildContext context) {
    final maxMs = duration.inMilliseconds.toDouble();
    if (maxMs <= 0) return const SizedBox();

    final startMs = trimStart.inMilliseconds.toDouble().clamp(0.0, maxMs);
    final endMs = trimEnd.inMilliseconds.toDouble().clamp(
      startMs + 100.0,
      maxMs,
    );
    final trimmedLength = trimEnd - trimStart;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2C),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildTimeChip(
                label: 'Start',
                time: _formatDuration(trimStart),
                color: Colors.deepPurpleAccent,
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.deepPurpleAccent.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Duration: ${(trimmedLength.inMilliseconds / 1000).toStringAsFixed(1)}s',
                  style: const TextStyle(
                    color: Colors.deepPurpleAccent,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
              _buildTimeChip(
                label: 'End',
                time: _formatDuration(trimEnd),
                color: Colors.purpleAccent,
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Custom Trim Slider Container
          Stack(
            alignment: Alignment.center,
            children: [
              RangeSlider(
                values: RangeValues(startMs, endMs),
                min: 0.0,
                max: maxMs,
                activeColor: Colors.deepPurpleAccent,
                inactiveColor: Colors.white10,
                onChanged: (RangeValues values) {
                  final newStart = Duration(milliseconds: values.start.round());
                  final newEnd = Duration(milliseconds: values.end.round());
                  onTrimChanged(newStart, newEnd);
                },
                onChangeStart: (values) {
                  onSeek(Duration(milliseconds: values.start.round()));
                },
                onChangeEnd: (values) {
                  onSeek(Duration(milliseconds: values.start.round()));
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTimeChip({
    required String label,
    required String time,
    required Color color,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            color: Colors.white38,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          time,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.bold,
            fontFamily: 'monospace',
            fontSize: 14,
          ),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:native_video_editor/native_video_editor.dart';

/// A visual crop overlay with interactive corner handles and grid lines.
class InteractiveCropOverlay extends StatefulWidget {
  const InteractiveCropOverlay({
    super.key,
    required this.cropRect,
    required this.onChanged,
  });

  final VideoCropRect cropRect;
  final ValueChanged<VideoCropRect> onChanged;

  @override
  State<InteractiveCropOverlay> createState() => _InteractiveCropOverlayState();
}

enum _DragHandle { topLeft, topRight, bottomLeft, bottomRight, center }

class _InteractiveCropOverlayState extends State<InteractiveCropOverlay> {
  _DragHandle? _activeHandle;

  void _onPanStart(
    DragStartDetails details,
    BoxConstraints constraints,
    _DragHandle handle,
  ) {
    setState(() {
      _activeHandle = handle;
    });
  }

  void _onPanUpdate(DragUpdateDetails details, BoxConstraints constraints) {
    final dx = details.delta.dx / constraints.maxWidth;
    final dy = details.delta.dy / constraints.maxHeight;

    double left = widget.cropRect.left;
    double top = widget.cropRect.top;
    double width = widget.cropRect.width;
    double height = widget.cropRect.height;

    const minSize = 0.15; // Minimum 15% width/height

    switch (_activeHandle) {
      case _DragHandle.topLeft:
        final newLeft = (left + dx).clamp(0.0, left + width - minSize);
        final newTop = (top + dy).clamp(0.0, top + height - minSize);
        width += left - newLeft;
        height += top - newTop;
        left = newLeft;
        top = newTop;
        break;

      case _DragHandle.topRight:
        final newRight = (left + width + dx).clamp(left + minSize, 1.0);
        final newTop = (top + dy).clamp(0.0, top + height - minSize);
        width = newRight - left;
        height += top - newTop;
        top = newTop;
        break;

      case _DragHandle.bottomLeft:
        final newLeft = (left + dx).clamp(0.0, left + width - minSize);
        final newBottom = (top + height + dy).clamp(top + minSize, 1.0);
        width += left - newLeft;
        left = newLeft;
        height = newBottom - top;
        break;

      case _DragHandle.bottomRight:
        final newRight = (left + width + dx).clamp(left + minSize, 1.0);
        final newBottom = (top + height + dy).clamp(top + minSize, 1.0);
        width = newRight - left;
        height = newBottom - top;
        break;

      case _DragHandle.center:
        left = (left + dx).clamp(0.0, 1.0 - width);
        top = (top + dy).clamp(0.0, 1.0 - height);
        break;

      case null:
        return;
    }

    widget.onChanged(
      VideoCropRect(
        left: double.parse(left.toStringAsFixed(3)),
        top: double.parse(top.toStringAsFixed(3)),
        width: double.parse(width.toStringAsFixed(3)),
        height: double.parse(height.toStringAsFixed(3)),
      ),
    );
  }

  void _onPanEnd(DragEndDetails details) {
    setState(() {
      _activeHandle = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cropLeft = widget.cropRect.left * constraints.maxWidth;
        final cropTop = widget.cropRect.top * constraints.maxHeight;
        final cropWidth = widget.cropRect.width * constraints.maxWidth;
        final cropHeight = widget.cropRect.height * constraints.maxHeight;

        return Stack(
          children: [
            // Dimmed background outside crop area
            CustomPaint(
              size: Size(constraints.maxWidth, constraints.maxHeight),
              painter: _DimmedOverlayPainter(
                cropRect: Rect.fromLTWH(
                  cropLeft,
                  cropTop,
                  cropWidth,
                  cropHeight,
                ),
              ),
            ),

            // Draggable Crop Box Container
            Positioned(
              left: cropLeft,
              top: cropTop,
              width: cropWidth,
              height: cropHeight,
              child: GestureDetector(
                onPanStart: (d) =>
                    _onPanStart(d, constraints, _DragHandle.center),
                onPanUpdate: (d) => _onPanUpdate(d, constraints),
                onPanEnd: _onPanEnd,
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white, width: 2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Stack(
                    children: [
                      // Rule of thirds grid lines
                      _buildGridLines(),

                      // Center Drag Icon Hint
                      const Center(
                        child: Icon(
                          Icons.open_with,
                          color: Colors.white70,
                          size: 24,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Corner Handles
            _buildHandle(_DragHandle.topLeft, cropLeft, cropTop, constraints),
            _buildHandle(
              _DragHandle.topRight,
              cropLeft + cropWidth,
              cropTop,
              constraints,
            ),
            _buildHandle(
              _DragHandle.bottomLeft,
              cropLeft,
              cropTop + cropHeight,
              constraints,
            ),
            _buildHandle(
              _DragHandle.bottomRight,
              cropLeft + cropWidth,
              cropTop + cropHeight,
              constraints,
            ),
          ],
        );
      },
    );
  }

  Widget _buildGridLines() {
    return Column(
      children: [
        Expanded(
          child: Container(
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Colors.white30, width: 0.8),
              ),
            ),
          ),
        ),
        Expanded(
          child: Container(
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Colors.white30, width: 0.8),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    decoration: const BoxDecoration(
                      border: Border(
                        right: BorderSide(color: Colors.white30, width: 0.8),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Container(
                    decoration: const BoxDecoration(
                      border: Border(
                        right: BorderSide(color: Colors.white30, width: 0.8),
                      ),
                    ),
                  ),
                ),
                const Expanded(child: SizedBox()),
              ],
            ),
          ),
        ),
        const Expanded(child: SizedBox()),
      ],
    );
  }

  Widget _buildHandle(
    _DragHandle handle,
    double x,
    double y,
    BoxConstraints constraints,
  ) {
    const handleSize = 28.0;
    return Positioned(
      left: x - handleSize / 2,
      top: y - handleSize / 2,
      child: GestureDetector(
        onPanStart: (d) => _onPanStart(d, constraints, handle),
        onPanUpdate: (d) => _onPanUpdate(d, constraints),
        onPanEnd: _onPanEnd,
        child: Container(
          width: handleSize,
          height: handleSize,
          decoration: BoxDecoration(
            color: Colors.deepPurpleAccent,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: const [
              BoxShadow(
                color: Colors.black45,
                blurRadius: 4,
                offset: Offset(0, 2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DimmedOverlayPainter extends CustomPainter {
  _DimmedOverlayPainter({required this.cropRect});

  final Rect cropRect;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black.withValues(alpha: 0.55);

    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRect(cropRect);

    path.fillType = PathFillType.evenOdd;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _DimmedOverlayPainter oldDelegate) {
    return oldDelegate.cropRect != cropRect;
  }
}

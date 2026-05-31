/// A normalized crop rectangle for the source video frame.
///
/// Values are expressed from `0.0` to `1.0` relative to the source frame after
/// orientation is applied. For example, `left: 0.1`, `top: 0.1`,
/// `width: 0.8`, and `height: 0.8` keeps the center 80% of the frame.
class VideoCropRect {
  /// Creates a normalized crop rectangle.
  const VideoCropRect({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  /// The normalized distance from the left edge of the source frame.
  final double left;

  /// The normalized distance from the top edge of the source frame.
  final double top;

  /// The normalized width of the crop rectangle.
  final double width;

  /// The normalized height of the crop rectangle.
  final double height;

  /// Converts this crop rectangle to the method-channel payload.
  Map<String, Object?> toMap() => <String, Object?>{
    'left': left,
    'top': top,
    'width': width,
    'height': height,
  };

  /// Throws an [ArgumentError] if the crop rectangle is outside the frame.
  void validate() {
    final values = <String, double>{
      'left': left,
      'top': top,
      'width': width,
      'height': height,
    };

    for (final entry in values.entries) {
      if (entry.value.isNaN || entry.value.isInfinite) {
        throw ArgumentError.value(entry.value, entry.key, 'Must be finite.');
      }
    }

    if (left < 0 || top < 0 || width <= 0 || height <= 0) {
      throw ArgumentError(
        'Crop values must be normalized, positive, and start at 0.0 or greater.',
      );
    }

    if (left + width > 1.0 || top + height > 1.0) {
      throw ArgumentError(
        'Crop rectangle must stay inside the normalized frame.',
      );
    }
  }
}

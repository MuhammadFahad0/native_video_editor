class VideoCropRect {
  const VideoCropRect({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final double left;
  final double top;
  final double width;
  final double height;

  Map<String, Object?> toMap() => <String, Object?>{
    'left': left,
    'top': top,
    'width': width,
    'height': height,
  };

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

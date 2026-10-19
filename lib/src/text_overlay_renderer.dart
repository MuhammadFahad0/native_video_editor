import 'dart:ui' as ui;

/// Rasterize captions once using Flutter's fonts, for identical native overlays.
Future<void> renderTextOverlays(Map<String, Object?> payload) async {
  final settings = payload['settings'] as Map<String, Object?>;
  for (final overlay in payload['overlays'] as List<Map<String, Object?>>) {
    if (overlay['type'] != 'text') continue;
    final rect = overlay['rect'] as Map<String, Object?>;
    final width = ((settings['width'] as int) * (rect['width'] as double))
        .round()
        .clamp(1, 8192);
    final height = ((settings['height'] as int) * (rect['height'] as double))
        .round()
        .clamp(1, 8192);
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawColor(
      ui.Color(overlay['backgroundColor'] as int),
      ui.BlendMode.src,
    );
    final builder =
        ui.ParagraphBuilder(
            ui.ParagraphStyle(textDirection: ui.TextDirection.ltr),
          )
          ..pushStyle(
            ui.TextStyle(
              color: ui.Color(overlay['color'] as int),
              fontSize: overlay['fontSize'] as double,
            ),
          )
          ..addText(overlay['text'] as String);
    final paragraph = builder.build()
      ..layout(ui.ParagraphConstraints(width: width.toDouble()));
    canvas.drawParagraph(paragraph, ui.Offset.zero);
    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) throw StateError('Unable to render caption.');
      overlay['imageBytes'] = bytes.buffer.asUint8List(
        bytes.offsetInBytes,
        bytes.lengthInBytes,
      );
      overlay['type'] = 'image';
      overlay['fit'] = 'stretch';
    } finally {
      image.dispose();
      picture.dispose();
      paragraph.dispose();
    }
  }
}

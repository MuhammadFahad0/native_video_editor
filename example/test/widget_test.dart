// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';

import 'package:native_video_editor_example/main.dart';

void main() {
  testWidgets('advanced tools are accessible before picking a video', (
    tester,
  ) async {
    await tester.pumpWidget(const NativeVideoEditorExampleApp());
    await tester.tap(find.byTooltip('More video tools'));
    await tester.pumpAndSettle();
    expect(find.text('More video tools'), findsOneWidget);
    expect(find.text('Media information'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Run tool'),
      300,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('Run tool'), findsOneWidget);
  });

  testWidgets('shows the video picker on startup', (tester) async {
    await tester.pumpWidget(const NativeVideoEditorExampleApp());

    expect(find.text('Select Video File'), findsOneWidget);
    expect(find.text('No Video Selected'), findsOneWidget);
  });
}

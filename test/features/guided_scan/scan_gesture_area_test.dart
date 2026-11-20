import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marketgoz/features/guided_scan/guided_scan_screen.dart';

void main() {
  Widget host(VoidCallback onRestart, VoidCallback onButton) => MaterialApp(
        home: Scaffold(
          body: Stack(
            fit: StackFit.expand,
            children: [
              ScanGestureArea(
                onRestart: onRestart,
                child: const ColoredBox(color: Colors.black),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: ElevatedButton(
                  onPressed: onButton,
                  child: const Text('FENERİ AÇ'),
                ),
              ),
            ],
          ),
        ),
      );

  testWidgets('screen-reader tap on the restart node triggers restart',
      (tester) async {
    final handle = tester.ensureSemantics();
    var restarts = 0, buttons = 0;
    await tester.pumpWidget(host(() => restarts++, () => buttons++));

    final restart = find.bySemanticsLabel('Taramayı yeniden başlat');
    expect(restart, findsOneWidget);
    final node = tester.getSemantics(restart);
    expect(node.hasFlag(SemanticsFlag.isButton), isTrue);
    expect(node.getSemanticsData().hint, isNotEmpty);

    tester.semantics.tap(find.semantics.byLabel('Taramayı yeniden başlat'));
    await tester.pump();
    expect(restarts, 1);
    expect(buttons, 0);

    // The other button is its own node and still works.
    final torch = find.bySemanticsLabel('FENERİ AÇ');
    expect(torch, findsOneWidget);
    tester.semantics.tap(find.semantics.byLabel('FENERİ AÇ'));
    await tester.pump();
    expect(buttons, 1);
    expect(restarts, 1);
    handle.dispose();
  });

  testWidgets('raw double tap still restarts for non-screen-reader users',
      (tester) async {
    var restarts = 0;
    await tester.pumpWidget(host(() => restarts++, () {}));
    final p = tester.getCenter(find.byType(ColoredBox).first);
    await tester.tapAt(p);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(p);
    await tester.pumpAndSettle();
    expect(restarts, 1);
  });
}

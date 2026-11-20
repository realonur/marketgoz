import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marketgoz/app/app.dart';
import 'package:marketgoz/features/guided_scan/guided_scan_screen.dart';

void main() {
  test('app opens straight into the guided scan screen', () {
    final app = const MarketGozApp().build(_FakeContext());
    expect(app, isA<MaterialApp>());
    expect((app as MaterialApp).home, isA<GuidedScanScreen>());
  });
}

class _FakeContext extends Fake implements BuildContext {}

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:marketgoz/features/guided_scan/product_name_lookup.dart';

void main() {
  test('local hit skips the network', () async {
    var remoteCalled = false;
    final l = ProductNameLookup(
      local: (_) async => 'Pınar Süt',
      remote: (_) async {
        remoteCalled = true;
        return 'X';
      },
    );
    expect(await l.lookup('1'), 'Pınar Süt');
    expect(remoteCalled, isFalse);
  });

  test('falls back to remote', () async {
    final l = ProductNameLookup(
      local: (_) async => null,
      remote: (_) async => 'Ülker - Çikolata',
    );
    expect(await l.lookup('1'), 'Ülker - Çikolata');
  });

  test('offline / error / timeout fail silently', () async {
    expect(
        await ProductNameLookup(
          local: (_) async => throw StateError('x'),
          remote: (_) async => throw Exception('offline'),
        ).lookup('1'),
        isNull);
    expect(
        await ProductNameLookup(
          local: (_) async => null,
          remote: (_) => Completer<String?>().future,
          remoteTimeout: const Duration(milliseconds: 20),
        ).lookup('1'),
        isNull);
  });
}

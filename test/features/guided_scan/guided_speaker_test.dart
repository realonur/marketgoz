import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:marketgoz/features/guided_scan/guided_speaker.dart';

class FakeSink implements SpeechSink {
  final log = <String>[];
  final completers = <Completer<void>>[];

  @override
  Future<void> stop() async => log.add('stop');

  @override
  Future<void> speak(String text) {
    log.add('say:$text');
    final c = Completer<void>();
    completers.add(c);
    return c.future;
  }

  void finishLast() => completers.last.complete();
}

Future<void> pump() => Future<void>.delayed(Duration.zero);

void main() {
  test('a new prompt stops the current one, then speaks', () async {
    final s = FakeSink();
    final sp = GuidedSpeaker(s);
    sp.coach('bir');
    await pump();
    sp.coach('iki');
    await pump();
    expect(s.log, ['stop', 'say:bir', 'stop', 'say:iki']);
  });

  test('rapid prompts do not pile up: only the latest is spoken', () async {
    final s = FakeSink();
    final sp = GuidedSpeaker(s);
    sp.coach('a');
    sp.coach('b');
    sp.coach('c');
    await pump();
    expect(s.log.where((l) => l.startsWith('say:')), ['say:c']);
  });

  test('found interrupts, blocks coaching, and defers the product name',
      () async {
    final s = FakeSink();
    final sp = GuidedSpeaker(s);
    sp.coach('ilerle');
    await pump();
    final f = sp.found('Son kullanma tarihi 15 Mart');
    await pump();
    expect(s.log.last, 'say:Son kullanma tarihi 15 Mart');
    expect(sp.foundActive, isTrue);

    sp.coach('sola kaydır');
    sp.productName('Ürün: Süt');
    await pump();
    expect(s.log.where((l) => l.contains('sola')), isEmpty);
    expect(s.log.where((l) => l.contains('Süt')), isEmpty);

    s.finishLast();
    await f;
    expect(s.log.last, 'say:Ürün: Süt');
    expect(sp.foundActive, isFalse);
  });

  test('product name before found is spoken immediately', () async {
    final s = FakeSink();
    final sp = GuidedSpeaker(s);
    sp.productName('Ürün: Süt');
    await pump();
    expect(s.log, ['stop', 'say:Ürün: Süt']);
  });

  test('stop() cancels a pending found state', () async {
    final s = FakeSink();
    final sp = GuidedSpeaker(s);
    unawaited(sp.found('x'));
    await pump();
    await sp.stop();
    expect(sp.foundActive, isFalse);
    sp.coach('y');
    await pump();
    expect(s.log.last, 'say:y');
  });

  test('intro protects itself from coaching, but only briefly', () async {
    final s = FakeSink();
    final sp = GuidedSpeaker(s);
    unawaited(sp.intro('merhaba', maxProtect: const Duration(milliseconds: 30)));
    await pump();
    sp.coach('hemen');
    await pump();
    expect(s.log.where((l) => l.contains('hemen')), isEmpty);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    sp.coach('sonra');
    await pump();
    expect(s.log.last, 'say:sonra');
  });
}

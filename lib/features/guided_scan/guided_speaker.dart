/// Speech policy for the guided scan.
///
///  * A new coaching prompt interrupts the one being spoken (stop, then speak).
///  * The found result always interrupts and is spoken in full: nothing else
///    interrupts it, coaching prompts are dropped while it plays, and a product
///    name that arrives meanwhile is queued until it finishes.
///  * The short intro is also protected, but only briefly.
library;

import 'dart:async';

import '../../core/services/tts_service.dart';

/// The two TTS operations the policy needs (lets tests use a fake).
abstract class SpeechSink {
  Future<void> stop();

  /// Completes when the utterance has finished.
  Future<void> speak(String text);
}

class TtsSpeechSink implements SpeechSink {
  TtsSpeechSink(this._tts);
  final TTSService _tts;

  @override
  Future<void> stop() => _tts.stop();

  @override
  Future<void> speak(String text) => _tts.speak(text);
}

class GuidedSpeaker {
  GuidedSpeaker(this._tts);

  final SpeechSink _tts;

  int _gen = 0;
  bool _foundActive = false;
  bool _introActive = false;
  String? _pendingName;

  bool get foundActive => _foundActive;

  /// Continuous coaching prompt. Dropped while the intro or result is playing.
  void coach(String text) {
    if (_foundActive || _introActive) return;
    _interrupting(text);
  }

  /// "Ürün: X". Never cuts a result announcement; queued behind it instead.
  void productName(String text) {
    if (_foundActive || _introActive) {
      _pendingName = text;
      return;
    }
    _interrupting(text);
  }

  /// Short spoken introduction; coaching waits at most [maxProtect].
  Future<void> intro(String text,
      {Duration maxProtect = const Duration(seconds: 5)}) async {
    final gen = ++_gen;
    _introActive = true;
    try {
      await _tts.stop();
      if (gen != _gen) return;
      await Future.any<void>([
        _tts.speak(text),
        Future<void>.delayed(maxProtect),
      ]);
    } finally {
      if (gen == _gen) {
        _introActive = false;
        _flushPending();
      }
    }
  }

  /// The date result: interrupts everything and is spoken fully.
  Future<void> found(String text,
      {Duration maxDuration = const Duration(seconds: 30)}) async {
    final gen = ++_gen;
    _foundActive = true;
    _introActive = false;
    try {
      await _tts.stop();
      if (gen != _gen) return;
      await Future.any<void>([
        _tts.speak(text),
        Future<void>.delayed(maxDuration),
      ]);
    } finally {
      if (gen == _gen) {
        _foundActive = false;
        _flushPending();
      }
    }
  }

  /// Cancels everything (restart, background, dispose).
  Future<void> stop() async {
    _gen++;
    _foundActive = false;
    _introActive = false;
    _pendingName = null;
    await _tts.stop();
  }

  void _flushPending() {
    final name = _pendingName;
    _pendingName = null;
    if (name != null) unawaited(_tts.speak(name));
  }

  void _interrupting(String text) {
    final gen = ++_gen;
    unawaited(() async {
      await _tts.stop();
      if (gen != _gen) return;
      await _tts.speak(text);
    }());
  }
}

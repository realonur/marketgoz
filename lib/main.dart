import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'app/app.dart';
import 'core/services/tts_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Portrait only: the guidance engine's left/right/up/down coaching assumes
  // an upright portrait camera image.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  final ttsService = TTSService();
  await ttsService.initialize();

  runApp(
    MultiProvider(
      providers: [
        Provider<TTSService>.value(value: ttsService),
      ],
      child: const MarketGozApp(),
    ),
  );
}

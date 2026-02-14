// lib/services/tts_service.dart
import 'package:flutter_tts/flutter_tts.dart';

class TtsService {
  static final TtsService _instance = TtsService._internal();
  final FlutterTts _tts = FlutterTts();

  factory TtsService() => _instance;

  TtsService._internal() {
    _initializeTts();
  }

  void _initializeTts() {
    _tts.setLanguage("en-US");
    _tts.setSpeechRate(0.45); // Slow enough for clarity
    _tts.setPitch(1.0);
    _tts.setVolume(1.0);
    _tts.awaitSpeakCompletion(true);
  }

  Future<void> speak(String text) async {
    if (text.trim().isEmpty) return;
    await _tts.stop(); // Stop previous speech if still running
    await _tts.speak(text);
  }

  Future<void> stop() async {
    await _tts.stop();
  }

  void dispose() {
    _tts.stop();
  }
}

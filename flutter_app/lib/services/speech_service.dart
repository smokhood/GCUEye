// lib/services/speech_service.dart
import 'package:speech_to_text/speech_to_text.dart';

class SpeechService {
  static final SpeechService _instance = SpeechService._internal();
  factory SpeechService() => _instance;

  SpeechService._internal();

  final SpeechToText _speech = SpeechToText();
  bool _isInitialized = false;
  String _selectedLocaleId = "en_US";

  bool get isListening => _speech.isListening;
  String _lastResult = '';
  String get lastResult => _lastResult;

  Function(String)? _onResult;
  Function()? _onSpeechStart;
  Function()? _onSpeechEnd;

  /// Initialize speech recognition and select the best locale.
  Future<bool> initialize() async {
    if (!_isInitialized) {
      _isInitialized = await _speech.initialize(
        onStatus: (status) {
          if (status == 'done' || status == 'notListening') {
            _onSpeechEnd?.call();
          }
        },
        onError: (error) {
          // Optionally, handle error reporting/logging here.
          print('Speech recognition error: ${error.errorMsg}');
          _onSpeechEnd?.call();
        },
      );
      if (_isInitialized) {
        // Choose the best-matching locale (default to en_US)
        final locales = await _speech.locales();
        // Try to prefer en_US, else fallback to first available
        _selectedLocaleId = locales.firstWhere(
          (l) => l.localeId.startsWith('en'),
          orElse: () => locales.first,
        ).localeId;
      }
    }
    return _isInitialized;
  }

  /// Start listening for speech input.
  /// onResult: called with the recognized words (partial and final)
  /// onSpeechStart: called when speech recognition actually starts
  /// onSpeechEnd: called when finished or cancelled
  Future<void> startListening({
    required Function(String) onResult,
    Function()? onSpeechStart,
    Function()? onSpeechEnd,
    String? localeId,
    bool partialResults = true,
    Duration pauseFor = const Duration(seconds: 4),
  }) async {
    final available = await initialize();
    if (!available) {
      print('Speech recognition not available or permission denied.');
      onSpeechEnd?.call();
      return;
    }

    _onResult = onResult;
    _onSpeechStart = onSpeechStart;
    _onSpeechEnd = onSpeechEnd;
    _lastResult = '';

    _speech.listen(
      onResult: (result) {
        _lastResult = result.recognizedWords.trim();
        _onResult?.call(_lastResult);
      },
      localeId: localeId ?? _selectedLocaleId,
      listenMode: ListenMode.dictation,
      partialResults: partialResults,
      pauseFor: pauseFor,
    );

    _onSpeechStart?.call();
  }

  /// Stop listening for speech input.
  Future<void> stopListening() async {
    if (_speech.isListening) {
      await _speech.stop();
      _onSpeechEnd?.call();
    }
  }

  /// Cancel listening (discard result).
  Future<void> cancel() async {
    if (_speech.isListening) {
      await _speech.cancel();
      _onSpeechEnd?.call();
    }
  }

  /// Reset internal state and callbacks.
  void reset() {
    _lastResult = '';
    _onResult = null;
    _onSpeechStart = null;
    _onSpeechEnd = null;
  }

  /// Dispose and clean up.
  void dispose() {
    cancel();
    reset();
  }
}
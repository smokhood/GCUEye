import 'dart:async';
import 'package:flutter/material.dart';
import 'package:string_similarity/string_similarity.dart';
import '../services/tts_service.dart';
import '../services/speech_service.dart';

class LocationVoiceSearchService {
  final TtsService tts;
  final SpeechService speech;

  LocationVoiceSearchService({TtsService? ttsService, SpeechService? speechService})
      : tts = ttsService ?? TtsService(),
        speech = speechService ?? SpeechService();

  /// Starts the voice location search dialog.
  /// [context]: BuildContext for dialogs.
  /// [nodeNames]: List of all location node names.
  /// [onFound]: Called with the selected node name, or null if cancelled.
  /// [searchFor]: 'start' or 'destination'
  Future<void> searchLocation({
    required BuildContext context,
    required List<String> nodeNames,
    required Function(String? nodeName) onFound,
    String searchFor = 'destination',
  }) async {
    int attempts = 0;
    const int maxAttempts = 3;
    while (attempts < maxAttempts) {
      await tts.speak(
        "Voice search activated. Please say the $searchFor location you want.",
      );

      // Listen for user speech
      String? userSpeech = await _getSpokenLocation(context);
      if (userSpeech == null || userSpeech.isEmpty) {
        await tts.speak("I didn't catch that. Please repeat the $searchFor location.");
        attempts++;
        continue;
      }

      // Confirm what was heard
      await tts.speak("I heard: $userSpeech. Is this correct? Say yes or no.");
      bool? heardConfirmed = await _confirmGeneric(context);
      if (heardConfirmed == null) {
        await tts.speak("No response. Cancelling search.");
        onFound(null);
        return;
      }
      if (!heardConfirmed) {
        await tts.speak("Let's try again. Please say the $searchFor location.");
        attempts++;
        continue;
      }

      // Try for exact & prefix match first (case insensitive)
      final normalizedUser = _normalize(userSpeech);
      String? exactMatch = nodeNames.firstWhere(
        (n) => _normalize(n) == normalizedUser,
        orElse: () => '',
      );
      if (exactMatch.isNotEmpty) {
        await tts.speak("$exactMatch selected as your $searchFor location.");
        onFound(exactMatch);
        return;
      }
      String? prefixMatch = nodeNames.firstWhere(
        (n) => _normalize(n).startsWith(normalizedUser),
        orElse: () => '',
      );
      if (prefixMatch.isNotEmpty) {
        await tts.speak("$prefixMatch selected as your $searchFor location.");
        onFound(prefixMatch);
        return;
      }

      // Fuzzy match against all node names with higher threshold
      List<_LocationMatch> matches = _fuzzyMatch(userSpeech, nodeNames, minScore: 0.6);

      if (matches.isEmpty) {
        await tts.speak("Sorry, I couldn't find any location similar to what you said. Please try again.");
        attempts++;
        continue;
      }

      // If two very close, offer both as disambiguation
      if (matches.length >= 2 && (matches[0].score - matches[1].score < 0.07)) {
        await tts.speak(
            "Did you mean ${matches[0].name} or ${matches[1].name}? Please say your choice.");
        String? choice = await _getSpokenLocation(context);
        if (choice != null &&
            _normalize(choice) == _normalize(matches[0].name)) {
          await tts.speak(
              "${matches[0].name} selected as your $searchFor location.");
          onFound(matches[0].name);
          return;
        } else if (choice != null &&
            _normalize(choice) == _normalize(matches[1].name)) {
          await tts.speak(
              "${matches[1].name} selected as your $searchFor location.");
          onFound(matches[1].name);
          return;
        } else {
          await tts.speak("No valid choice recognized. Let's try again.");
          attempts++;
          continue;
        }
      }

      // Only try top 2 matches above threshold
      for (final match in matches.take(2)) {
        bool? confirmed = await _confirmMatch(context, match.name, searchFor);
        if (confirmed == true) {
          await tts.speak("${match.name} selected as your $searchFor location.");
          onFound(match.name);
          return;
        }
      }

      // No match confirmed
      await tts.speak("No matching locations confirmed. Let's try again.");
      attempts++;
    }

    await tts.speak("Voice search cancelled.");
    onFound(null);
  }

  Future<String?> _getSpokenLocation(BuildContext context) async {
    final completer = Completer<String?>();
    speech.startListening(
      onResult: (result) {
        if (result.isNotEmpty && !completer.isCompleted) {
          completer.complete(result);
          speech.stopListening();
        }
      },
      onSpeechStart: () {},
      onSpeechEnd: () {
        if (!completer.isCompleted) completer.complete(null);
      },
    );
    return completer.future;
  }

  /// Returns a list of best fuzzy matches, sorted by similarity (best first)
  List<_LocationMatch> _fuzzyMatch(String query, List<String> nodeNames, {double minScore = 0.6}) {
    final matches = <_LocationMatch>[];
    for (final name in nodeNames) {
      final score = StringSimilarity.compareTwoStrings(
        _normalize(query),
        _normalize(name),
      );
      if (score >= minScore) { // Raised threshold
        matches.add(_LocationMatch(name: name, score: score));
      }
    }
    matches.sort((a, b) => b.score.compareTo(a.score));
    return matches;
  }

  /// Speak the candidate and ask for yes/no. Returns true if confirmed, false if not, null if cancelled.
  Future<bool?> _confirmMatch(BuildContext context, String candidate, String searchFor) async {
    await tts.speak("Did you mean $candidate as your $searchFor location? Say yes or no.");

    final completer = Completer<bool?>();
    speech.startListening(
      onResult: (result) {
        String answer = result.toLowerCase().trim();
        if (answer.contains("yes")) {
          if (!completer.isCompleted) completer.complete(true);
          speech.stopListening();
        } else if (answer.contains("no")) {
          if (!completer.isCompleted) completer.complete(false);
          speech.stopListening();
        }
      },
      onSpeechEnd: () {
        if (!completer.isCompleted) completer.complete(null);
      },
    );
    return completer.future;
  }

  /// Ask for yes/no and return bool. Used to confirm what was heard.
  Future<bool?> _confirmGeneric(BuildContext context) async {
    final completer = Completer<bool?>();
    speech.startListening(
      onResult: (result) {
        String answer = result.toLowerCase().trim();
        if (answer.contains("yes")) {
          if (!completer.isCompleted) completer.complete(true);
          speech.stopListening();
        } else if (answer.contains("no")) {
          if (!completer.isCompleted) completer.complete(false);
          speech.stopListening();
        }
      },
      onSpeechEnd: () {
        if (!completer.isCompleted) completer.complete(null);
      },
    );
    return completer.future;
  }

  /// Normalize strings for comparison (lowercase, numbers replaced, etc.)
  String _normalize(String s) {
    s = s.toLowerCase().trim();
    // Replace number words with digits (e.g., "two"->"2")
    final numberWords = {
      'zero': '0',
      'one': '1',
      'two': '2',
      'three': '3',
      'four': '4',
      'five': '5',
      'six': '6',
      'seven': '7',
      'eight': '8',
      'nine': '9',
      'ten': '10',
    };
    numberWords.forEach((word, digit) {
      s = s.replaceAll(word, digit);
    });
    // Common speech-to-text mistakes for numbers
    s = s.replaceAll(RegExp(r'\bfour\b'), '4');
    s = s.replaceAll(RegExp(r'\bfor\b'), '4');
    s = s.replaceAll(RegExp(r'\btwo\b'), '2');
    s = s.replaceAll(RegExp(r'\bto\b'), '2');
    s = s.replaceAll(RegExp(r'\btoo\b'), '2');
    return s;
  }
}

class _LocationMatch {
  final String name;
  final double score;
  _LocationMatch({required this.name, required this.score});
}
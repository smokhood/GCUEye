import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibration/vibration.dart';
import 'package:intl/intl.dart';

import '../services/tts_service.dart';
import '../services/speech_service.dart';
import '../widgets/listening_overlay.dart';

class TwoFingerTapGestureRecognizer extends OneSequenceGestureRecognizer {
  VoidCallback? onTwoFingerTap;
  int _pointers = 0;

  @override
  void addPointer(PointerEvent event) {
    startTrackingPointer(event.pointer);
    _pointers++;
    if (_pointers == 2 && event is PointerDownEvent) {
      onTwoFingerTap?.call();
    }
  }

  @override
  String get debugDescription => 'twoFingerTap';

  @override
  void didStopTrackingLastPointer(int pointer) {
    _pointers = 0;
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerUpEvent || event is PointerCancelEvent) {
      _pointers--;
    }
  }

  @override
  void rejectGesture(int pointer) {
    stopTrackingPointer(pointer);
    _pointers = 0;
  }
}

class ReminderPage extends StatefulWidget {
  @override
  _ReminderPageState createState() => _ReminderPageState();
}

class _ReminderPageState extends State<ReminderPage> {
  final TtsService _tts = TtsService();
  final SpeechService _speech = SpeechService();

  int _selectedSection = 0; // 0: Custom, 1: Class, 2: Prayer
  int _selectedIndexCustom = 0;
  int _selectedIndexClass = 0;
  int _selectedIndexPrayer = 0;
  int _tapCount = 0;
  Timer? _tapTimer;
  bool _isListening = false;
  bool _firstInstructionSpoken = false;
  Timer? _reminderTimer;

  double _verticalDragStart = 0.0;

  List<Map<String, String>> _customReminders = [];
  List<Map<String, String>> _classReminders = [];
  List<Map<String, String>> _prayerReminders = [];

  String _recognizedText = '';

  Set<String> _announcedCustomReminders = {};
  Set<String> _announcedClassReminders = {};
  Set<String> _announcedPrayerReminders = {};

  @override
  void initState() {
    super.initState();
    _tts.stop();
    _loadAllReminders();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future.delayed(const Duration(milliseconds: 500));
      _announceWelcome();
    });
    _startReminderChecker();
  }

  @override
  void dispose() {
    _tts.dispose();
    _speech.dispose();
    _reminderTimer?.cancel();
    _tapTimer?.cancel();
    super.dispose();
  }

  Future<void> _announceWelcome() async {
    await _tts.speak(
      "Welcome to the reminders page. You are in your reminders section. "
      "Swipe left or right to switch sections. "
      "Long press to add a reminder. "
      "Swipe up or down to move between reminders. "
      "Double tap to edit, triple tap to delete. "
      "Two-finger tap will read all reminders in the section. "
      "Triple tap anywhere will repeat these instructions. "
      "Class and prayer reminders are managed automatically."
    );
  }

  Future<void> _announceSection() async {
    String sectionName = _getSectionName(_selectedSection);
    String guide = "";
    if (_selectedSection == 0) {
      guide =
          "Your reminders section. Long press to add a reminder. Swipe up or down to move between reminders. Double tap to edit. Triple tap to delete. Two-finger tap to read all.";
    } else if (_selectedSection == 1) {
      guide =
          "Class reminders section. These come from your class schedule. Swipe up or down to move. Two-finger tap to read all.";
    } else {
      guide =
          "Prayer reminders section. Swipe up or down to move. Two-finger tap to read all.";
    }
    await _tts.speak("You are now in $sectionName. $guide");
  }

  String _getSectionName(int section) {
    switch (section) {
      case 0:
        return "your reminders";
      case 1:
        return "class reminders";
      case 2:
      default:
        return "prayer reminders";
    }
  }

  Future<void> _loadAllReminders() async {
    final prefs = await SharedPreferences.getInstance();

    // Custom Reminders
    final keys = prefs.getKeys().where((k) => k.startsWith('reminder_')).toList();
    final loaded = <Map<String, String>>[];
    for (var key in keys) {
      final msg = prefs.getString(key);
      final time = key.replaceFirst('reminder_', '');
      if (msg != null) loaded.add({'time': time, 'message': msg});
    }
    loaded.sort((a, b) => (a['time'] ?? '').compareTo(b['time'] ?? ''));
    _customReminders = loaded;

    // Class Reminders: read from class_schedule
    final classJson = prefs.getString('class_schedule');
    _classReminders = [];
    if (classJson != null) {
      final Map<String, dynamic> decoded = jsonDecode(classJson);
      final today = DateTime.now();
      final todayName = [
        "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"
      ][today.weekday - 1];
      final List todayClasses = decoded[todayName] ?? [];
      for (final item in todayClasses) {
        if (item is Map) {
          _classReminders.add({
            'time': item['time'] ?? '',
            'message': item['subject'] ?? '',
          });
        }
      }
      _classReminders.sort((a, b) => (a['time'] ?? '').compareTo(b['time'] ?? ''));
    }

    // Prayer Reminders (static)
    _prayerReminders = [
      {'time': '05:00', 'message': 'Fajr prayer'},
      {'time': '13:00', 'message': 'Dhuhur prayer'},
      {'time': '16:30', 'message': 'Asr prayer'},
      {'time': '19:10', 'message': 'Maghrib prayer'},
      {'time': '21:00', 'message': 'Isha prayer'},
    ];

    _announcedCustomReminders.clear();
    _announcedClassReminders.clear();
    _announcedPrayerReminders.clear();

    setState(() {});
  }

  void _startReminderChecker() {
    _reminderTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      final now = DateTime.now();

      // Custom reminders
      for (var reminder in _customReminders) {
        final time = reminder['time'];
        final message = reminder['message'];
        if (time != null && message != null) {
          final reminderTime = DateTime.tryParse(time);
          if (reminderTime != null &&
              (now.difference(reminderTime).inSeconds).abs() < 30 &&
              !_announcedCustomReminders.contains(time)) {
            await _tts.speak("Reminder: $message");
            if (await Vibration.hasVibrator() ?? false) Vibration.vibrate(duration: 1000);
            _announcedCustomReminders.add(time);
          }
        }
      }

      // Class reminders
      for (int i = 0; i < _classReminders.length; i++) {
        final reminder = _classReminders[i];
        final time = reminder['time'];
        final message = reminder['message'];
        if (time != null && message != null && time.length >= 4) {
          final parts = time.split(":");
          if (parts.length == 2) {
            final scheduled = DateTime(now.year, now.month, now.day,
                int.tryParse(parts[0]) ?? 0, int.tryParse(parts[1]) ?? 0);
            final uniqueId = "${now.year}-${now.month}-${now.day}-$time-$message";
            if ((now.difference(scheduled).inSeconds).abs() < 30 &&
                !_announcedClassReminders.contains(uniqueId)) {
              await _tts.speak("Class: $message at ${time.replaceAll(":", " ")}");
              if (await Vibration.hasVibrator() ?? false) Vibration.vibrate(duration: 1000);
              _announcedClassReminders.add(uniqueId);
            }
          }
        }
      }

      // Prayer reminders
      for (int i = 0; i < _prayerReminders.length; i++) {
        final reminder = _prayerReminders[i];
        final time = reminder['time'];
        final message = reminder['message'];
        if (time != null && message != null && time.length >= 4) {
          final parts = time.split(":");
          if (parts.length == 2) {
            final scheduled = DateTime(now.year, now.month, now.day,
                int.tryParse(parts[0]) ?? 0, int.tryParse(parts[1]) ?? 0);
            final uniqueId = "${now.year}-${now.month}-${now.day}-$time-$message";
            if ((now.difference(scheduled).inSeconds).abs() < 30 &&
                !_announcedPrayerReminders.contains(uniqueId)) {
              await _tts.speak("Prayer time: $message at ${time.replaceAll(":", " ")}");
              if (await Vibration.hasVibrator() ?? false) Vibration.vibrate(duration: 1000);
              _announcedPrayerReminders.add(uniqueId);
            }
          }
        }
      }
    });
  }

  Future<void> _saveReminder(String message, DateTime time) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('reminder_${time.toIso8601String()}', message);
    setState(() {
      _customReminders.add({'time': time.toIso8601String(), 'message': message});
      _customReminders.sort((a, b) => (a['time'] ?? '').compareTo(b['time'] ?? ''));
    });
  }

  Future<void> _saveAllCustomReminders() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => k.startsWith('reminder_')).toList();
    for (final key in keys) {
      await prefs.remove(key);
    }
    for (var r in _customReminders) {
      if (r['time'] != null && r['message'] != null) {
        await prefs.setString('reminder_${r['time']}', r['message']!);
      }
    }
  }

  void _onTwoFingerTap() async {
    if (_selectedSection == 0 && _customReminders.isNotEmpty) {
      await _tts.speak("Your reminders:");
      for (final r in _customReminders) {
        await _tts.speak("Reminder: ${r['message']} at ${r['time']?.substring(11,16)}.");
        await Future.delayed(const Duration(milliseconds: 300));
      }
    } else if (_selectedSection == 1 && _classReminders.isNotEmpty) {
      await _tts.speak("Today's class reminders:");
      for (final r in _classReminders) {
        await _tts.speak("Class: ${r['message']} at ${r['time']}.");
        await Future.delayed(const Duration(milliseconds: 300));
      }
    } else if (_selectedSection == 2 && _prayerReminders.isNotEmpty) {
      await _tts.speak("Prayer reminders:");
      for (final r in _prayerReminders) {
        await _tts.speak("Prayer: ${r['message']} at ${r['time']}.");
        await Future.delayed(const Duration(milliseconds: 300));
      }
    }
  }

  // --- SPEECH HANDLING: Make reminders page speech handling match the working schedule page! ---
  void _onLongPressStart(LongPressStartDetails details) async {
    if (_selectedSection != 0) {
      await _tts.speak("You can only add a reminder in your reminders section.");
      return;
    }
    setState(() {
      _isListening = true;
      _recognizedText = '';
    });
    if (!_firstInstructionSpoken) {
      await _tts.speak("Say something like remind me to call mom at 10 A M.");
      _firstInstructionSpoken = true;
    }
    await _speech.startListening(
      onResult: (text) {
        _recognizedText = text;
      },
      onSpeechStart: () async {},
      onSpeechEnd: () async {
        setState(() => _isListening = false);
        await _processReminderInput();
      },
    );
  }

  void _onLongPressEnd(LongPressEndDetails details) async {
    await _speech.stopListening();
    setState(() => _isListening = false);
    // Do not process here, let onSpeechEnd handle it
  }

  Future<void> _processReminderInput() async {
    final input = _recognizedText.toLowerCase().trim();
    print("DEBUG: Recognized speech input: '$input'");
    if (input.isEmpty) {
      await _tts.speak("Sorry, I didn't catch anything. Please long press and try again.");
      return;
    }

    // Try relative time: "in N minutes/hours"
    final relPattern = RegExp(r'in (\d+) (minute|minutes|hour|hours)');
    final relMatch = relPattern.firstMatch(input);
    DateTime? dt;
    if (relMatch != null) {
      final num = int.tryParse(relMatch.group(1) ?? '');
      final unit = relMatch.group(2);
      if (num != null) {
        if (unit!.contains('hour')) {
          dt = DateTime.now().add(Duration(hours: num));
        } else {
          dt = DateTime.now().add(Duration(minutes: num));
        }
        print("DEBUG: Parsed as relative time: $dt");
      }
    }

    // Try "tomorrow at HH(:mm)?"
    if (dt == null) {
      final tomorrowPattern = RegExp(r'tomorrow(?: at)? (\d{1,2})(?::(\d{2}))?\s*(am|pm)?');
      final match = tomorrowPattern.firstMatch(input);
      if (match != null) {
        int hour = int.parse(match.group(1)!);
        int minute = int.tryParse(match.group(2) ?? '0') ?? 0;
        String? ampm = match.group(3);
        if (ampm != null) {
          if (ampm.contains('pm') && hour != 12) hour += 12;
          if (ampm.contains('am') && hour == 12) hour = 0;
        }
        dt = DateTime.now().add(const Duration(days: 1));
        dt = DateTime(dt.year, dt.month, dt.day, hour, minute);
        print("DEBUG: Parsed as tomorrow: $dt");
      }
    }

    // Try "at HH(:mm)?(am|pm)?"
    if (dt == null) {
      final timePattern = RegExp(r'at (\d{1,2})(?::(\d{2}))?\s*(am|pm)?');
      final match = timePattern.firstMatch(input);
      if (match != null) {
        int hour = int.parse(match.group(1)!);
        int minute = int.tryParse(match.group(2) ?? '0') ?? 0;
        String? ampm = match.group(3);
        if (ampm != null) {
          if (ampm.contains('pm') && hour != 12) hour += 12;
          if (ampm.contains('am') && hour == 12) hour = 0;
        }
        DateTime now = DateTime.now();
        dt = DateTime(now.year, now.month, now.day, hour, minute);
        if (dt.isBefore(now)) dt = dt.add(const Duration(days: 1));
        print("DEBUG: Parsed as at time: $dt");
      }
    }

    // Try "at HH:MM" 24-hour
    if (dt == null) {
      final time24Pattern = RegExp(r'at (\d{2}):(\d{2})');
      final match = time24Pattern.firstMatch(input);
      if (match != null) {
        int hour = int.parse(match.group(1)!);
        int minute = int.tryParse(match.group(2) ?? '0') ?? 0;
        DateTime now = DateTime.now();
        dt = DateTime(now.year, now.month, now.day, hour, minute);
        if (dt.isBefore(now)) dt = dt.add(const Duration(days: 1));
        print("DEBUG: Parsed as at 24-hour: $dt");
      }
    }

    if (dt == null) {
      print("DEBUG: No time parsed from input.");
      await _tts.speak("Sorry, I couldn't find a time in your reminder. Please try again.");
      return;
    }

    // Remove time phrases from the input for message
    String msg = input
        .replaceAll(RegExp(r'in \d+ (minute|minutes|hour|hours)'), '')
        .replaceAll(RegExp(r'tomorrow(?: at)? \d{1,2}(?::\d{2})?\s*(am|pm)?'), '')
        .replaceAll(RegExp(r'at \d{1,2}(?::\d{2})?\s*(am|pm)?'), '')
        .replaceAll(RegExp(r'at \d{2}:\d{2}'), '')
        .replaceAll(RegExp(r'remind( me)?( to)?', caseSensitive: false), '')
        .trim();
    if (msg.isEmpty) msg = "Reminder";

    print("DEBUG: Parsed reminder message: '$msg', time: $dt");

    await _saveReminder(msg, dt);
    final readableTime = DateFormat('yyyy-MM-dd HH:mm').format(dt);
    await _tts.speak("Reminder set for $msg at $readableTime. "
        "To add more reminders, long press again. To switch section, swipe left or right.");

    if (await Vibration.hasVibrator() ?? false) {
      Vibration.vibrate(duration: 1000);
    }
  }

  void _onTap() {
    _tapCount++;
    _tapTimer?.cancel();
    _tapTimer = Timer(const Duration(milliseconds: 400), () {
      if (_tapCount == 2) {
        _onDoubleTapEdit();
      } else if (_tapCount == 3) {
        _onTripleTapDelete();
      }
      _tapCount = 0;
    });
  }

  Future<void> _onDoubleTapEdit() async {
    if (_selectedSection == 0 && _customReminders.isNotEmpty) {
      final idx = _selectedIndexCustom;
      final reminder = _customReminders[idx];
      final ctrl = TextEditingController(text: reminder['message']);
      final timeCtrl = TextEditingController(
          text: reminder['time']?.substring(11, 16) ?? "");
      await _tts.speak("Editing reminder. Change the message or time, then save.");
      final result = await showDialog<Map<String, String>>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: Colors.deepPurple[900]?.withOpacity(0.98),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Text("Edit Reminder",
              style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: ctrl,
                style: const TextStyle(color: Colors.white, fontSize: 18),
                decoration: const InputDecoration(
                    labelText: "Message",
                    labelStyle: TextStyle(color: Colors.amberAccent)),
              ),
              TextField(
                controller: timeCtrl,
                style: const TextStyle(color: Colors.white, fontSize: 18),
                decoration: const InputDecoration(
                    labelText: "Time (HH:mm)",
                    labelStyle: TextStyle(color: Colors.amberAccent)),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text("Cancel", style: TextStyle(color: Colors.amberAccent))),
            ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
                onPressed: () {
                  reminder['message'] = ctrl.text.trim();
                  final now = DateTime.now();
                  final timeParts = timeCtrl.text.split(":");
                  if (timeParts.length == 2) {
                    final dt = DateTime(now.year, now.month, now.day,
                        int.tryParse(timeParts[0]) ?? 0, int.tryParse(timeParts[1]) ?? 0);
                    reminder['time'] = dt.toIso8601String();
                  }
                  Navigator.of(ctx).pop(reminder);
                },
                child: const Text("Save", style: TextStyle(color: Colors.deepPurple))),
          ],
        ),
      );
      if (result != null) {
        setState(() => _customReminders[idx] = result);
        _customReminders.sort((a, b) => (a['time'] ?? '').compareTo(b['time'] ?? ''));
        await _saveAllCustomReminders();
        await _tts.speak("Reminder updated. Swipe up or down to review other reminders.");
      }
    } else {
      await _tts.speak("You can only edit reminders in your reminders section.");
    }
  }

  Future<void> _onTripleTapDelete() async {
    if (_selectedSection == 0 && _customReminders.isNotEmpty) {
      final idx = _selectedIndexCustom;
      final reminder = _customReminders[idx];
      await _tts.speak("Delete reminder for ${reminder['message']}? Say yes or no.");
      String answer = '';
      await _speech.startListening(
        onResult: (text) => answer = text.toLowerCase(),
      );
      await Future.delayed(const Duration(seconds: 3));
      _speech.stopListening();
      if (answer.contains('yes')) {
        setState(() {
          _customReminders.removeAt(idx);
          if (_selectedIndexCustom > 0) _selectedIndexCustom--;
        });
        await _saveAllCustomReminders();
        await _tts.speak("Reminder deleted. Swipe up or down to review others.");
      } else {
        await _tts.speak("Cancelled. Your reminder was not deleted.");
      }
    } else {
      await _tts.speak("You can only delete reminders in your reminders section.");
    }
  }

  void _onSwipeUp() {
    if (_selectedSection == 0 && _customReminders.isNotEmpty) {
      setState(() => _selectedIndexCustom =
          (_selectedIndexCustom + 1) % _customReminders.length);
      _tts.speak("Reminder: ${_customReminders[_selectedIndexCustom]['message']} at ${_customReminders[_selectedIndexCustom]['time']?.substring(11, 16)}.");
    } else if (_selectedSection == 1 && _classReminders.isNotEmpty) {
      setState(() => _selectedIndexClass =
          (_selectedIndexClass + 1) % _classReminders.length);
      final r = _classReminders[_selectedIndexClass];
      _tts.speak("Class: ${r['message']} at ${r['time']}.");
    } else if (_selectedSection == 2 && _prayerReminders.isNotEmpty) {
      setState(() => _selectedIndexPrayer =
          (_selectedIndexPrayer + 1) % _prayerReminders.length);
      final r = _prayerReminders[_selectedIndexPrayer];
      _tts.speak("Prayer: ${r['message']} at ${r['time']}.");
    }
  }

  void _onSwipeDown() {
    if (_selectedSection == 0 && _customReminders.isNotEmpty) {
      setState(() => _selectedIndexCustom =
          (_selectedIndexCustom - 1 + _customReminders.length) %
              _customReminders.length);
      _tts.speak("Reminder: ${_customReminders[_selectedIndexCustom]['message']} at ${_customReminders[_selectedIndexCustom]['time']?.substring(11, 16)}.");
    } else if (_selectedSection == 1 && _classReminders.isNotEmpty) {
      setState(() => _selectedIndexClass =
          (_selectedIndexClass - 1 + _classReminders.length) %
              _classReminders.length);
      final r = _classReminders[_selectedIndexClass];
      _tts.speak("Class: ${r['message']} at ${r['time']}.");
    } else if (_selectedSection == 2 && _prayerReminders.isNotEmpty) {
      setState(() => _selectedIndexPrayer =
          (_selectedIndexPrayer - 1 + _prayerReminders.length) %
              _prayerReminders.length);
      final r = _prayerReminders[_selectedIndexPrayer];
      _tts.speak("Prayer: ${r['message']} at ${r['time']}.");
    }
  }

  void _onVerticalDragStart(DragStartDetails details) {
    _verticalDragStart = details.localPosition.dy;
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    double drag = details.localPosition.dy - _verticalDragStart;
    if (drag.abs() > 30) {
      if (drag < 0) {
        _onSwipeUp();
      } else {
        _onSwipeDown();
      }
      _verticalDragStart = details.localPosition.dy;
    }
  }

  void _onHorizontalDragEnd(DragEndDetails details) async {
    if (details.primaryVelocity == null) return;
    if (details.primaryVelocity! < 0) {
      setState(() => _selectedSection = (_selectedSection + 1) % 3);
    } else {
      setState(() => _selectedSection = (_selectedSection - 1 + 3) % 3);
    }
    await _announceSection();
  }

  Widget _buildSectionTitle(String title, bool selected) => Container(
        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 18),
        margin: const EdgeInsets.only(right: 8),
        decoration: BoxDecoration(
          color: selected ? Colors.amber : Colors.deepPurple[700],
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          title,
          style: TextStyle(
              color: selected ? Colors.deepPurple[900] : Colors.amber,
              fontWeight: FontWeight.bold,
              fontSize: 18),
        ),
      );

  @override
  Widget build(BuildContext context) {
    Widget sectionList;
    if (_selectedSection == 0) {
      sectionList = Expanded(
        child: ListView.builder(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 24),
          itemCount: _customReminders.length,
          itemBuilder: (context, idx) {
            final r = _customReminders[idx];
            final isSelected = idx == _selectedIndexCustom;
            final time = r['time']?.substring(11, 16) ?? '';
            return AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: isSelected ? Colors.amber : Colors.deepPurple[900]?.withOpacity(0.7),
                borderRadius: BorderRadius.circular(18),
                border: isSelected ? Border.all(color: Colors.deepPurple, width: 2) : null,
              ),
              child: Row(
                children: [
                  Icon(Icons.alarm, color: isSelected ? Colors.deepPurple[900] : Colors.amber, size: 24),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      "$time - ${r['message']}",
                      style: TextStyle(
                        color: isSelected ? Colors.deepPurple[900] : Colors.amber,
                        fontWeight: FontWeight.bold,
                        fontSize: 19,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      );
    } else if (_selectedSection == 1) {
      sectionList = Expanded(
        child: ListView.builder(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 24),
          itemCount: _classReminders.length,
          itemBuilder: (context, idx) {
            final r = _classReminders[idx];
            final isSelected = idx == _selectedIndexClass;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: isSelected ? Colors.amber : Colors.deepPurple[700]?.withOpacity(0.7),
                borderRadius: BorderRadius.circular(18),
                border: isSelected ? Border.all(color: Colors.deepPurple, width: 2) : null,
              ),
              child: Row(
                children: [
                  Icon(Icons.school, color: isSelected ? Colors.deepPurple[900] : Colors.amber, size: 24),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      "${r['time']} - ${r['message']}",
                      style: TextStyle(
                        color: isSelected ? Colors.deepPurple[900] : Colors.amber,
                        fontWeight: FontWeight.bold,
                        fontSize: 19,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      );
    } else {
      sectionList = Expanded(
        child: ListView.builder(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 24),
          itemCount: _prayerReminders.length,
          itemBuilder: (context, idx) {
            final r = _prayerReminders[idx];
            final isSelected = idx == _selectedIndexPrayer;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: isSelected ? Colors.amber : Colors.deepPurple[900]?.withOpacity(0.7),
                borderRadius: BorderRadius.circular(18),
                border: isSelected ? Border.all(color: Colors.deepPurple, width: 2) : null,
              ),
              child: Row(
                children: [
                  Icon(Icons.mosque, color: isSelected ? Colors.deepPurple[900] : Colors.amber, size: 24),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      "${r['time']} - ${r['message']}",
                      style: TextStyle(
                        color: isSelected ? Colors.deepPurple[900] : Colors.amber,
                        fontWeight: FontWeight.bold,
                        fontSize: 19,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text("Reminders"),
        backgroundColor: Colors.deepPurpleAccent,
      ),
      body: Stack(
        children: [
          RawGestureDetector(
            gestures: {
              TwoFingerTapGestureRecognizer:
                  GestureRecognizerFactoryWithHandlers<TwoFingerTapGestureRecognizer>(
                () => TwoFingerTapGestureRecognizer(),
                (TwoFingerTapGestureRecognizer instance) {
                  instance.onTwoFingerTap = _onTwoFingerTap;
                },
              ),
            },
            child: GestureDetector(
              onLongPressStart: _onLongPressStart,
              onLongPressEnd: _onLongPressEnd,
              onTap: _onTap,
              onHorizontalDragEnd: _onHorizontalDragEnd,
              onVerticalDragStart: _onVerticalDragStart,
              onVerticalDragUpdate: _onVerticalDragUpdate,
              behavior: HitTestBehavior.opaque,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 14.0, bottom: 6),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.start,
                        children: [
                          _buildSectionTitle("Your Reminders", _selectedSection == 0),
                          _buildSectionTitle("Class Reminders", _selectedSection == 1),
                          _buildSectionTitle("Prayer Reminders", _selectedSection == 2),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4),
                    child: Text(
                      "Gestures: Swipe left or right to switch section. Long press to add. Double tap to edit, triple tap to delete (custom only). Swipe up/down to move. Two-finger tap to read all. Triple tap for help.",
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  sectionList,
                ],
              ),
            ),
          ),
          ListeningOverlay(isListening: _isListening),
        ],
      ),
      floatingActionButton: null,
    );
  }
}
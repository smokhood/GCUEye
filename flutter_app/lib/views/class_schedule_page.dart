import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibration/vibration.dart';
import 'package:flutter/gestures.dart';

import '../services/tts_service.dart';
import '../services/speech_service.dart';
import '../widgets/listening_overlay.dart';

class ClassScheduleItem {
  String subject;
  String time;

  ClassScheduleItem({required this.subject, required this.time});

  Map<String, dynamic> toJson() => {
        'subject': subject,
        'time': time,
      };

  factory ClassScheduleItem.fromJson(Map<String, dynamic> json) =>
      ClassScheduleItem(subject: json['subject'], time: json['time']);
}

class TwoFingerTapGestureRecognizer extends OneSequenceGestureRecognizer {
  Function()? onTwoFingerTap;
  int _pointerCount = 0;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    _pointerCount++;
    startTrackingPointer(event.pointer);
    if (_pointerCount == 2) {
      onTwoFingerTap?.call();
    }
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerUpEvent || event is PointerCancelEvent) {
      stopTrackingPointer(event.pointer);
    }
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    _pointerCount = 0;
  }

  @override
  String get debugDescription => 'twoFingerTap';
}

class ClassSchedulePage extends StatefulWidget {
  @override
  State<ClassSchedulePage> createState() => _ClassSchedulePageState();
}

class _ClassSchedulePageState extends State<ClassSchedulePage> {
  final TtsService _tts = TtsService();
  final SpeechService _speech = SpeechService();

  bool _isListening = false;
  bool _firstTimeInstructionSpoken = false;

  final List<String> _days = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday'
  ];
  int _currentDayIndex = DateTime.now().weekday - 1;

  Map<String, List<ClassScheduleItem>> _schedule = {
    'Monday': [],
    'Tuesday': [],
    'Wednesday': [],
    'Thursday': [],
    'Friday': [],
  };

  int _selectedClassIndex = 0;
  String _recognizedText = '';

  Timer? _tapTimer;
  int _tapCount = 0;

  @override
  void initState() {
    super.initState();
    // --- Speech overlap fix: Stop any previous TTS immediately when entering this page ---
    _tts.stop();
    if (_currentDayIndex < 0 || _currentDayIndex > 4) _currentDayIndex = 0;
    _loadSchedule().then((_) => _announceTodayOnStart());
  }

  Future<void> _saveSchedule() async {
    final prefs = await SharedPreferences.getInstance();
    final data = _schedule.map(
      (day, list) =>
          MapEntry(day, list.map((e) => e.toJson()).toList(growable: false)),
    );
    await prefs.setString('class_schedule', jsonEncode(data));
  }

  Future<void> _loadSchedule() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString('class_schedule');
    if (jsonString == null) return;
    final Map<String, dynamic> decoded = jsonDecode(jsonString);
    setState(() {
      _schedule = decoded.map((day, items) => MapEntry(
          day,
          (items as List)
              .map((e) => ClassScheduleItem.fromJson(e))
              .toList(growable: true)));
    });
  }

  Future<void> _announceTodayOnStart() async {
    final today = _days[_currentDayIndex];
    final classes = _schedule[today]!;
    if (classes.isEmpty) {
      await _tts.speak(
          "Welcome to class schedule. No classes found for $today. Long press with one finger to add by speech, or tap with two fingers to add with keyboard.");
    } else {
      await _tts.speak(
          "Welcome to class schedule. Today is $today. You have ${classes.length} classes. Swipe up or down to hear your classes. Long press with one finger to add by speech. Tap with two fingers to add or edit with keyboard. Triple tap to delete. Double tap to edit.");
      await Future.delayed(const Duration(milliseconds: 700));
      await _announceCurrentClass();
    }
  }

  Future<void> _announceCurrentClass() async {
    final today = _days[_currentDayIndex];
    final classes = _schedule[today]!;
    if (classes.isEmpty) {
      await _tts.speak("No classes for $today.");
      return;
    }
    if (_selectedClassIndex < 0 || _selectedClassIndex >= classes.length) {
      _selectedClassIndex = 0;
    }
    final item = classes[_selectedClassIndex];
    await _tts.speak(
        "Class ${_selectedClassIndex + 1}: ${item.subject} at ${item.time.replaceAll(":", " ")}");
  }

  Future<void> _announceAllClasses() async {
    final today = _days[_currentDayIndex];
    final classes = _schedule[today]!;
    if (classes.isEmpty) {
      await _tts.speak("No classes for $today.");
      return;
    }
    await _tts.speak("Classes for $today:");
    for (int i = 0; i < classes.length; i++) {
      final item = classes[i];
      await _tts.speak(
          "Class ${i + 1}: ${item.subject} at ${item.time.replaceAll(":", " ")}");
      await Future.delayed(const Duration(milliseconds: 350));
    }
  }

  Future<void> _onLongPressStart(LongPressStartDetails details) async {
    setState(() {
      _isListening = true;
      _recognizedText = '';
    });
    if (await Vibration.hasVibrator() ?? false) {
      Vibration.vibrate(duration: 100);
    }
    if (!_firstTimeInstructionSpoken) {
      await _tts.speak(
          "Please say the subject and time, for example: Math at 10 A M.");
      _firstTimeInstructionSpoken = true;
    }
    await _speech.startListening(
      onResult: (text) => _recognizedText = text,
      onSpeechStart: () async {
        if (await Vibration.hasVibrator() ?? false) {
          Vibration.vibrate(duration: 100);
        }
      },
      onSpeechEnd: () async {
        setState(() => _isListening = false);
        if (await Vibration.hasVibrator() ?? false) {
          Vibration.vibrate(duration: 150);
        }
      },
    );
  }

  Future<void> _onLongPressEnd(LongPressEndDetails details) async {
    await _speech.stopListening();
    setState(() => _isListening = false);
    if (await Vibration.hasVibrator() ?? false) {
      Vibration.vibrate(duration: 150);
    }
    print('Recognized: $_recognizedText');
    final input = _recognizedText.toLowerCase().trim();
    if (input.isEmpty) {
      await _tts.speak("No speech detected.");
      return;
    }
    final classItem = _parseClassInput(input);
    if (classItem != null) {
      final today = _days[_currentDayIndex];
      setState(() {
        _schedule[today]!.add(classItem);
        _selectedClassIndex = _schedule[today]!.length - 1;
      });
      await _saveSchedule();
      await _tts.speak(
          "Added ${classItem.subject} at ${classItem.time.replaceAll(":", " ")} for $today.");
      if (await Vibration.hasVibrator() ?? false) Vibration.vibrate(duration: 700);
    } else {
      await _tts.speak("Sorry, I couldn't understand. Please try again.");
    }
  }

  // Improved time parsing for speech input
  ClassScheduleItem? _parseClassInput(String input) {
    input = input.toLowerCase();
    // Accepts e.g. "math at 10 30", "english at 2 pm", "science at 14:20", "history at 11"
    final timePattern = RegExp(r'at\s+(\d{1,2})(?::?(\d{2}))?\s*(a\.?m\.?|p\.?m\.?)?');
    final match = timePattern.firstMatch(input);
    if (match == null) return null;

    int hour = int.tryParse(match.group(1) ?? '') ?? 0;
    int minute = int.tryParse(match.group(2) ?? '0') ?? 0;
    String? ampm = match.group(3)?.replaceAll('.', '');

    if (ampm != null) {
      if (ampm.contains('pm') && hour != 12) hour += 12;
      if (ampm.contains('am') && hour == 12) hour = 0;
    }

    String subject = input
        .replaceAll(timePattern, '')
        .replaceAll("at", '')
        .replaceAll("class", '')
        .replaceAll("remind me", '')
        .trim();

    if (subject.isEmpty) subject = "Class";
    String timeStr = "${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}";

    return ClassScheduleItem(subject: subject, time: timeStr);
  }

  Future<void> _onTripleTapDelete() async {
    final today = _days[_currentDayIndex];
    final classes = _schedule[today]!;
    if (classes.isEmpty) {
      await _tts.speak("No classes to delete.");
      return;
    }
    final item = classes[_selectedClassIndex];
    await _tts.speak(
        "Are you sure you want to delete ${item.subject} at ${item.time.replaceAll(":", " ")}? Say yes or no.");
    String answer = '';
    await _speech.startListening(
      onResult: (text) => answer = text.toLowerCase(),
      onSpeechStart: () async {
        if (await Vibration.hasVibrator() ?? false) {
          Vibration.vibrate(duration: 100);
        }
      },
      onSpeechEnd: () async {
        setState(() => _isListening = false);
        if (await Vibration.hasVibrator() ?? false) {
          Vibration.vibrate(duration: 150);
        }
      },
    );
    await _speech.stopListening();
    setState(() => _isListening = false);
    if (answer.contains('yes')) {
      setState(() {
        classes.removeAt(_selectedClassIndex);
        if (_selectedClassIndex > 0) _selectedClassIndex--;
      });
      await _saveSchedule();
      await _tts.speak("Deleted the class. ${classes.isEmpty ? "No more classes for $today." : ""}");
      if (await Vibration.hasVibrator() ?? false) Vibration.vibrate(duration: 700);
    } else {
      await _tts.speak("Cancelled.");
    }
  }

  // Double tap: edit (not repeat)
  void _onDoubleTapRepeat() async {
    final today = _days[_currentDayIndex];
    final classes = _schedule[today]!;
    if (classes.isEmpty) return;
    final editingClass = classes[_selectedClassIndex];
    await showDialog(
      context: context,
      builder: (context) => _ManualClassDialog(
        editing: editingClass,
        onSave: (subject, time) async {
          setState(() {
            editingClass.subject = subject;
            editingClass.time = time;
          });
          await _tts.speak("Class updated.");
          await _saveSchedule();
        },
      ),
    );
  }

  // Two-finger tap: always add new
  void _onTwoFingerKeyboardTap() async {
    final today = _days[_currentDayIndex];
    final classes = _schedule[today]!;
    await showDialog(
      context: context,
      builder: (context) => _ManualClassDialog(
        editing: null, // Always add new
        onSave: (subject, time) async {
          final newItem = ClassScheduleItem(subject: subject, time: time);
          setState(() {
            classes.add(newItem);
            _selectedClassIndex = classes.length - 1;
          });
          await _tts.speak("Class added.");
          await _saveSchedule();
        },
      ),
    );
  }

  // Robust tap handler for double/triple tap
  void _onTap() {
    _tapCount++;
    _tapTimer?.cancel();
    _tapTimer = Timer(const Duration(milliseconds: 350), () {
      if (_tapCount == 2) {
        _onDoubleTapRepeat();
      } else if (_tapCount == 3) {
        _onTripleTapDelete();
      }
      _tapCount = 0;
    });
  }

  void _onVerticalDragEnd(DragEndDetails details) async {
    final today = _days[_currentDayIndex];
    final classes = _schedule[today]!;
    if (classes.isEmpty) {
      await _tts.speak("No classes for $today.");
      return;
    }
    if (details.primaryVelocity == null) return;
    if (details.primaryVelocity! < 0) {
      if (_selectedClassIndex < classes.length - 1) {
        setState(() => _selectedClassIndex++);
      } else {
        setState(() => _selectedClassIndex = 0);
      }
      await _announceCurrentClass();
    } else if (details.primaryVelocity! > 0) {
      if (_selectedClassIndex > 0) {
        setState(() => _selectedClassIndex--);
      } else {
        setState(() => _selectedClassIndex = classes.length - 1);
      }
      await _announceCurrentClass();
    }
  }

  void _onHorizontalDragEnd(DragEndDetails details) async {
    if (details.primaryVelocity == null) return;
    if (details.primaryVelocity! < 0) {
      if (_currentDayIndex < _days.length - 1) {
        setState(() {
          _currentDayIndex++;
          _selectedClassIndex = 0;
        });
        await _tts.speak("Now showing ${_days[_currentDayIndex]}");
        await _announceCurrentClass();
      }
    } else if (details.primaryVelocity! > 0) {
      if (_currentDayIndex > 0) {
        setState(() {
          _currentDayIndex--;
          _selectedClassIndex = 0;
        });
        await _tts.speak("Now showing ${_days[_currentDayIndex]}");
        await _announceCurrentClass();
      }
    }
  }

  void _onTwoFingerReadAll() async {
    await _announceAllClasses();
  }

  @override
  Widget build(BuildContext context) {
    final today = _days[_currentDayIndex];
    final classes = _schedule[today]!;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text("Class Schedule"),
        centerTitle: true,
        backgroundColor: Colors.deepPurple[900]?.withOpacity(0.9),
        elevation: 8,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(30)),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.volume_up),
            onPressed: _announceCurrentClass,
            tooltip: "Repeat current class",
          ),
          IconButton(
            icon: const Icon(Icons.list),
            onPressed: _announceAllClasses,
            tooltip: "Read all classes for this day",
          ),
        ],
      ),
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF2e003e), Color(0xFF23074d), Color(0xFFcc5333)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          RawGestureDetector(
            gestures: {
              TwoFingerTapGestureRecognizer:
                  GestureRecognizerFactoryWithHandlers<TwoFingerTapGestureRecognizer>(
                () => TwoFingerTapGestureRecognizer(),
                (TwoFingerTapGestureRecognizer instance) {
                  instance.onTwoFingerTap = _onTwoFingerKeyboardTap;
                },
              ),
            },
            behavior: HitTestBehavior.opaque,
            child: GestureDetector(
              onLongPressStart: _onLongPressStart,
              onLongPressEnd: _onLongPressEnd,
              onTap: _onTap,
              onVerticalDragEnd: _onVerticalDragEnd,
              onHorizontalDragEnd: _onHorizontalDragEnd,
              onSecondaryTap: _onTwoFingerReadAll,
              behavior: HitTestBehavior.opaque,
              child: SafeArea(
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(18),
                      margin: const EdgeInsets.symmetric(
                          vertical: 6, horizontal: 16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        color: Colors.deepPurple[700]?.withOpacity(0.85),
                        boxShadow: [
                          BoxShadow(
                            color: (Colors.deepPurple[900] ?? Colors.black)
                                .withOpacity(0.2),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          )
                        ],
                      ),
                      child: Center(
                        child: Text(
                          today,
                          style: const TextStyle(
                            color: Colors.amber,
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 2,
                          ),
                        ),
                      ),
                    ),
                    if (classes.isEmpty)
                      Expanded(
                        child: Center(
                          child: Text(
                            "No classes for $today.\nLong press with one finger to add by speech.\nTap with two fingers to add with keyboard.",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 20,
                            ),
                          ),
                        ),
                      )
                    else
                      Expanded(
                        child: ListView.builder(
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: classes.length,
                          itemBuilder: (_, idx) {
                            final item = classes[idx];
                            final isSelected = idx == _selectedClassIndex;
                            return AnimatedContainer(
                              duration: const Duration(milliseconds: 400),
                              curve: Curves.easeOutCubic,
                              decoration: BoxDecoration(
                                gradient: isSelected
                                    ? const LinearGradient(
                                        colors: [
                                          Color(0xFF4e54c8),
                                          Color(0xFF8f94fb),
                                          Color(0xFFfccb90),
                                        ],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      )
                                    : null,
                                color: isSelected
                                    ? null
                                    : Colors.deepPurple[400]?.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(18),
                                boxShadow: isSelected
                                    ? [
                                        BoxShadow(
                                          color: Colors.amber.withOpacity(0.2),
                                          blurRadius: 18,
                                          offset: const Offset(0, 7),
                                        ),
                                      ]
                                    : [],
                                border: isSelected
                                    ? Border.all(
                                        color: Colors.amberAccent, width: 2)
                                    : null,
                              ),
                              margin: const EdgeInsets.symmetric(
                                  horizontal: 26, vertical: 12),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 20, vertical: 22),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.subject,
                                    style: TextStyle(
                                      color: isSelected
                                          ? Colors.deepPurple[900]
                                          : Colors.amberAccent,
                                      fontSize: 23,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        "Time: ${item.time}",
                                        style: TextStyle(
                                          color: isSelected
                                              ? Colors.deepPurple[800]
                                              : Colors.white70,
                                          fontSize: 18,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      if (isSelected)
                                        Icon(Icons.keyboard,
                                            color: Colors.deepPurple[900],
                                            size: 24)
                                    ],
                                  ),
                                  if (isSelected)
                                    Padding(
                                      padding:
                                          const EdgeInsets.only(top: 8.0),
                                      child: Text(
                                        "Double tap to edit. Triple tap to delete. Long press with one finger to add by speech. Tap with two fingers to add with keyboard.",
                                        style: TextStyle(
                                          color: Colors.deepPurple[900],
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    Container(
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Text(
                        "Swipe up/down: next/prev class. Swipe left/right: change day.\nLong press with one finger: add by speech. Tap with two fingers: add with keyboard.\nDouble tap: edit. Triple tap: delete. Two-finger tap: read all.",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.amber.withOpacity(0.7),
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          ListeningOverlay(isListening: _isListening),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _tapTimer?.cancel();
    _tts.dispose();
    _speech.dispose();
    super.dispose();
  }
}

class _ManualClassDialog extends StatefulWidget {
  final ClassScheduleItem? editing;
  final Future<void> Function(String subject, String time) onSave;

  const _ManualClassDialog({this.editing, required this.onSave});

  @override
  State<_ManualClassDialog> createState() => _ManualClassDialogState();
}

class _ManualClassDialogState extends State<_ManualClassDialog> {
  late TextEditingController _subjectController;
  late TextEditingController _timeController;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _subjectController =
        TextEditingController(text: widget.editing?.subject ?? '');
    _timeController =
        TextEditingController(text: widget.editing?.time ?? '');
  }

  @override
  void dispose() {
    _subjectController.dispose();
    _timeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.deepPurple[900]?.withOpacity(0.98),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Text(
        widget.editing != null
            ? "Edit Class"
            : "Add Class",
        style: TextStyle(
            color: Colors.amberAccent,
            fontWeight: FontWeight.bold,
            fontSize: 22),
      ),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _subjectController,
              style: const TextStyle(color: Colors.white, fontSize: 18),
              decoration: InputDecoration(
                labelText: "Subject",
                labelStyle: TextStyle(color: Colors.amber[200]),
                enabledBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.amber),
                ),
                focusedBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.amber, width: 2),
                ),
              ),
              textInputAction: TextInputAction.next,
              validator: (val) =>
                  val == null || val.trim().isEmpty ? "Subject required" : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _timeController,
              style: const TextStyle(color: Colors.white, fontSize: 18),
              decoration: InputDecoration(
                labelText: "Time (hh:mm)",
                labelStyle: TextStyle(color: Colors.amber[200]),
                enabledBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.amber),
                ),
                focusedBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.amber, width: 2),
                ),
                hintText: "e.g. 09:30 or 14:00",
                hintStyle: const TextStyle(color: Colors.white38),
              ),
              keyboardType: TextInputType.datetime,
              validator: (val) {
                if (val == null || val.trim().isEmpty) {
                  return "Time required";
                }
                final timePattern = RegExp(r'^\d{2}:\d{2}$');
                if (!timePattern.hasMatch(val.trim())) {
                  return "Format: hh:mm";
                }
                return null;
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          child: const Text("Cancel",
              style: TextStyle(color: Colors.amberAccent, fontSize: 16)),
          onPressed: () => Navigator.of(context).pop(),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.amber,
            foregroundColor: Colors.deepPurple[900],
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          ),
          child: Text(widget.editing != null ? "Save" : "Add",
              style: const TextStyle(fontWeight: FontWeight.bold)),
          onPressed: () async {
            if (_formKey.currentState!.validate()) {
              await widget.onSave(
                  _subjectController.text.trim(), _timeController.text.trim());
              Navigator.of(context).pop();
            }
          },
        ),
      ],
    );
  }
}
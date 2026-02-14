import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'sos_contact_setup.dart';
import 'calibration_check_page.dart';
import '../services/step_detection_service.dart';

class SettingsPage extends StatefulWidget {
  @override
  _SettingsPageState createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late FlutterTts _flutterTts;
  double _ttsSpeed = 0.5;
  double _ttsPitch = 1.0;
  bool _voiceInstructions = true;
  bool _vibrationEnabled = true;
  StepDetectionUserMode _stepDetectionUserMode = StepDetectionUserMode.automatic;

  int _currentIndex = 0;

  late List<_SettingItem> _settingItems;

  @override
  void initState() {
    super.initState();
    // --- Speech overlap fix: Stop any previous TTS immediately when entering this page ---
    _flutterTts = FlutterTts();
    _flutterTts.stop();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _ttsSpeed = prefs.getDouble('tts_speed') ?? 0.5;
    _ttsPitch = prefs.getDouble('tts_pitch') ?? 1.0;
    _voiceInstructions = prefs.getBool('voice_instructions') ?? true;
    _vibrationEnabled = prefs.getBool('vibration_enabled') ?? true;

    // Load step detection mode
    String? mode = prefs.getString('step_detection_mode');
    if (mode == 'manual') {
      _stepDetectionUserMode = StepDetectionUserMode.manual;
    } else {
      _stepDetectionUserMode = StepDetectionUserMode.automatic;
    }

    _initSettingItems();
    _speakCurrentSetting();
    setState(() {});
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setDouble('tts_speed', _ttsSpeed);
    prefs.setDouble('tts_pitch', _ttsPitch);
    prefs.setBool('voice_instructions', _voiceInstructions);
    prefs.setBool('vibration_enabled', _vibrationEnabled);
    // Save step detection mode
    String value = _stepDetectionUserMode == StepDetectionUserMode.manual ? 'manual' : 'automatic';
    prefs.setString('step_detection_mode', value);
  }

  void _initSettingItems() {
    _settingItems = [
      _SettingItem(
        title: () => "TTS Speed: ${_ttsSpeed.toStringAsFixed(1)}",
        explanation: () => "Text to speech speed is $_ttsSpeed. Tap right to increase, left to decrease.",
        onTapRight: () {
          setState(() {
            _ttsSpeed = (_ttsSpeed + 0.1).clamp(0.1, 1.0);
          });
          _flutterTts.setSpeechRate(_ttsSpeed);
          _saveSettings();
          _speakCurrentSetting();
        },
        onTapLeft: () {
          setState(() {
            _ttsSpeed = (_ttsSpeed - 0.1).clamp(0.1, 1.0);
          });
          _flutterTts.setSpeechRate(_ttsSpeed);
          _saveSettings();
          _speakCurrentSetting();
        },
      ),
      _SettingItem(
        title: () => "TTS Pitch: ${_ttsPitch.toStringAsFixed(1)}",
        explanation: () => "Text to speech pitch is $_ttsPitch. Tap right to increase, left to decrease.",
        onTapRight: () {
          setState(() {
            _ttsPitch = (_ttsPitch + 0.1).clamp(0.5, 2.0);
          });
          _flutterTts.setPitch(_ttsPitch);
          _saveSettings();
          _speakCurrentSetting();
        },
        onTapLeft: () {
          setState(() {
            _ttsPitch = (_ttsPitch - 0.1).clamp(0.5, 2.0);
          });
          _flutterTts.setPitch(_ttsPitch);
          _saveSettings();
          _speakCurrentSetting();
        },
      ),
      _SettingItem(
        title: () => "Step Detection Mode: ${_stepDetectionUserMode == StepDetectionUserMode.manual ? "Manual" : "Automatic"}",
        explanation: () => _stepDetectionUserMode == StepDetectionUserMode.manual
            ? "Step detection is manual. Tap to switch to automatic."
            : "Step detection is automatic. Tap to switch to manual.",
        onTapRight: _toggleStepDetectionMode,
        onTapLeft: _toggleStepDetectionMode,
      ),
      _SettingItem(
        title: () => "Voice Instructions: ${_voiceInstructions ? 'On' : 'Off'}",
        explanation: () => "Voice instructions are ${_voiceInstructions ? 'enabled' : 'disabled'}. Tap to toggle.",
        onTapRight: _toggleVoiceInstructions,
        onTapLeft: _toggleVoiceInstructions,
      ),
      _SettingItem(
        title: () => "Vibration Feedback: ${_vibrationEnabled ? 'On' : 'Off'}",
        explanation: () => "Vibration feedback is ${_vibrationEnabled ? 'enabled' : 'disabled'}. Tap to toggle.",
        onTapRight: _toggleVibration,
        onTapLeft: _toggleVibration,
      ),
      _SettingItem(
        title: () => "Check/Adjust Step Calibration",
        explanation: () => "Check or update your step calibration for more accurate navigation.",
        onTapRight: _openCalibrationCheck,
        onTapLeft: _openCalibrationCheck,
      ),
      _SettingItem(
        title: () => "SOS Contacts Setup",
        explanation: () => "Set your emergency contacts used for SOS messages.",
        onTapRight: _openSOSSetup,
        onTapLeft: _openSOSSetup,
      ),
      _SettingItem(
        title: () => "Reset All Settings",
        explanation: () => "Tap to reset all settings to default.",
        onTapRight: _resetSettings,
        onTapLeft: _resetSettings,
      ),
    ];
  }

  void _toggleStepDetectionMode() async {
    setState(() {
      _stepDetectionUserMode = _stepDetectionUserMode == StepDetectionUserMode.manual
          ? StepDetectionUserMode.automatic
          : StepDetectionUserMode.manual;
    });
    await StepDetectionService().saveUserMode(_stepDetectionUserMode);
    _saveSettings();
    _speakCurrentSetting();
  }

  void _toggleVoiceInstructions() {
    setState(() {
      _voiceInstructions = !_voiceInstructions;
    });
    _saveSettings();
    _speakCurrentSetting();
  }

  void _toggleVibration() {
    setState(() {
      _vibrationEnabled = !_vibrationEnabled;
    });
    _saveSettings();
    _speakCurrentSetting();
  }

  void _resetSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    setState(() {
      _ttsSpeed = 0.5;
      _ttsPitch = 1.0;
      _voiceInstructions = true;
      _vibrationEnabled = true;
      _stepDetectionUserMode = StepDetectionUserMode.automatic;
    });
    await StepDetectionService().saveUserMode(StepDetectionUserMode.automatic);
    _saveSettings();
    _flutterTts.speak("All settings reset to default.");
    _initSettingItems();
    _currentIndex = 0;
  }

  void _openSOSSetup() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => SosContactSetupPage()),
    );
  }

  void _openCalibrationCheck() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CalibrationCheckPage()),
    ).then((_) => _loadSettings());
  }

  void _speakCurrentSetting() {
    _flutterTts.speak(_settingItems[_currentIndex].title());
  }

  void _speakExplanation() {
    _flutterTts.speak(_settingItems[_currentIndex].explanation());
  }

  void _goToNextSetting() {
    if (_currentIndex < _settingItems.length - 1) {
      setState(() => _currentIndex++);
      _speakCurrentSetting();
    }
  }

  void _goToPreviousSetting() {
    if (_currentIndex > 0) {
      setState(() => _currentIndex--);
      _speakCurrentSetting();
    }
  }

  void _handleTapDown(TapDownDetails details, BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final dx = details.globalPosition.dx;

    if (dx > screenWidth / 2) {
      _settingItems[_currentIndex].onTapRight();
    } else {
      _settingItems[_currentIndex].onTapLeft();
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = _settingItems[_currentIndex];

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text("Settings"),
        backgroundColor: Colors.deepPurple,
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragEnd: (details) {
          if (details.primaryVelocity != null && details.primaryVelocity! < 0) {
            _goToNextSetting(); // swipe left
          } else if (details.primaryVelocity != null &&
              details.primaryVelocity! > 0) {
            _goToPreviousSetting(); // swipe right
          }
        },
        onTapDown: (details) => _handleTapDown(details, context),
        onLongPress: _speakExplanation,
        child: Center(
          child: Container(
            padding: EdgeInsets.all(20),
            margin: EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.grey[850],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              current.title(),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 22, color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingItem {
  final String Function() title;
  final String Function() explanation;
  final VoidCallback onTapRight;
  final VoidCallback onTapLeft;

  _SettingItem({
    required this.title,
    required this.explanation,
    required this.onTapRight,
    required this.onTapLeft,
  });
}
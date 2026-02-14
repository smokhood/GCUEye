import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:pedometer/pedometer.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_tts/flutter_tts.dart';

enum StepMode { hardware, accelerometer, manual }
enum StepDetectionUserMode { automatic, manual }

class StepDetectionService {
  static final StepDetectionService _instance = StepDetectionService._internal();
  factory StepDetectionService() => _instance;
  StepDetectionService._internal();

  StepMode _mode = StepMode.manual;
  StepMode get mode => _mode;

  StepDetectionUserMode _userMode = StepDetectionUserMode.automatic;
  StepDetectionUserMode get userMode => _userMode;

  int? _hardwareStartSteps;
  int? _hardwareLastSteps;
  double _accelStepProgress = 0.0;
  StreamSubscription<StepCount>? _hardwareSub;
  StreamSubscription? _accelSub;

  int _stepsTaken = 0;
  int get stepsTaken => _stepsTaken;
  set stepsTaken(int value) => _stepsTaken = value;

  double _calibrationFactor = 1.0;
  double get calibrationFactor => _calibrationFactor;

  String? _lastCalibrationDate;
  String? get lastCalibrationDate => _lastCalibrationDate;

  void Function()? onStep;
  void Function(String error)? onError;
  void Function(StepMode mode)? onModeChanged;

  final FlutterTts _tts = FlutterTts();

  Future<void> loadSettings() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? userModeString = prefs.getString('step_detection_mode');
    if (userModeString == 'manual') {
      _userMode = StepDetectionUserMode.manual;
    } else {
      _userMode = StepDetectionUserMode.automatic;
    }
    _calibrationFactor = prefs.getDouble('step_calibration_factor') ?? 1.0;
    _lastCalibrationDate = prefs.getString('step_calibration_date');
  }

  Future<void> saveUserMode(StepDetectionUserMode mode) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String value = mode == StepDetectionUserMode.manual ? 'manual' : 'automatic';
    await prefs.setString('step_detection_mode', value);
    _userMode = mode;
  }

  Future<void> saveCalibration(double factor) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    final now = DateTime.now().toIso8601String();
    await prefs.setDouble('step_calibration_factor', factor);
    await prefs.setString('step_calibration_date', now);
    _calibrationFactor = factor;
    _lastCalibrationDate = now;
  }

  Future<void> resetCalibration() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove('step_calibration_factor');
    await prefs.remove('step_calibration_date');
    _calibrationFactor = 1.0;
    _lastCalibrationDate = null;
  }

  double applyCalibration(double logicalSteps) => logicalSteps * _calibrationFactor;

  /// Start step detection according to user setting
  /// [speakMode] controls whether to announce mode changes (for accessibility guidance).
  Future<void> startStepDetection({bool speakMode = true}) async {
    await loadSettings();
    _stepsTaken = 0;
    if (_userMode == StepDetectionUserMode.manual) {
      _mode = StepMode.manual;
      _hardwareSub?.cancel();
      _accelSub?.cancel();
      onModeChanged?.call(_mode);
      if (speakMode) await _tts.speak("Step detection set to manual. Tap the screen to advance each step.");
      return;
    } else {
      // Try hardware, then accelerometer, else manual
      if (await _testHardwareStepCounter()) {
        _mode = StepMode.hardware;
        _hardwareStartSteps = null;
        _hardwareLastSteps = null;
        _hardwareSub?.cancel();
        _hardwareSub = Pedometer.stepCountStream.listen((event) {
          if (_hardwareStartSteps == null) {
            _hardwareStartSteps = event.steps;
            _hardwareLastSteps = event.steps;
            return;
          }
          int stepDiff = event.steps - (_hardwareLastSteps ?? event.steps);
          _hardwareLastSteps = event.steps;
          _stepsTaken += stepDiff;
          if (stepDiff > 0) onStep?.call();
        }, onError: (err) {
          onError?.call("Step sensor error, switching to accelerometer fallback.");
          _startAccelerometerFallback(speakMode: speakMode);
        });
        onModeChanged?.call(_mode);
        if (speakMode) await _tts.speak("Step detection set to automatic. Steps will be detected automatically.");
        return;
      } else {
        await _startAccelerometerFallback(speakMode: speakMode);
      }
    }
  }

  Future<void> _startAccelerometerFallback({bool speakMode = true}) async {
    _mode = StepMode.accelerometer;
    _accelStepProgress = 0.0;
    _accelSub?.cancel();
    double lastZ = 0;
    int lastDirection = 0;
    _accelSub = accelerometerEvents.listen((event) {
      double z = event.z;
      int direction = z > lastZ ? 1 : -1;
      if (lastDirection != 0 && direction != lastDirection && z.abs() > 1.2) {
        _accelStepProgress += 0.5;
        if (_accelStepProgress >= 1.0) {
          _accelStepProgress = 0.0;
          _stepsTaken += 1;
          onStep?.call();
        }
      }
      lastZ = z;
      lastDirection = direction;
    }, onError: (err) {
      onError?.call("Accelerometer error, switching to manual.");
      _mode = StepMode.manual;
      onModeChanged?.call(_mode);
      if (speakMode) _tts.speak("Automatic step detection unavailable. Please tap the screen to advance each step.");
    });
    onModeChanged?.call(_mode);
    if (speakMode) await _tts.speak("Step detection set to automatic. Using accelerometer fallback for step detection.");
  }

  Future<bool> _testHardwareStepCounter() async {
    final completer = Completer<bool>();
    StreamSubscription<StepCount>? sub;
    bool gotEvent = false;
    sub = Pedometer.stepCountStream.listen(
      (event) {
        gotEvent = true;
        sub?.cancel();
        completer.complete(true);
      },
      onError: (e) {
        sub?.cancel();
        completer.complete(false);
      },
    );
    Future.delayed(const Duration(seconds: 2), () {
      if (!gotEvent && !completer.isCompleted) {
        sub?.cancel();
        completer.complete(false);
      }
    });
    return completer.future;
  }

  void incrementStep() {
    _stepsTaken += 1;
    onStep?.call();
  }

  void stop() {
    _hardwareSub?.cancel();
    _accelSub?.cancel();
    _stepsTaken = 0;
    _hardwareStartSteps = null;
    _hardwareLastSteps = null;
    _accelStepProgress = 0.0;
  }
}
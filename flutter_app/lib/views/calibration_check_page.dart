import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../services/step_detection_service.dart';

class CalibrationCheckPage extends StatefulWidget {
  @override
  _CalibrationCheckPageState createState() => _CalibrationCheckPageState();
}

class _CalibrationCheckPageState extends State<CalibrationCheckPage> {
  final FlutterTts _tts = FlutterTts();
  int _detectedSteps = 0;
  bool _isCalibrating = false;
  bool _awaitingConfirm = false;
  double? _newFactor;
  String? _lastCalibrationDate;
  double? _oldFactor;
  Timer? _calibTimeout;

  @override
  void nitStaite() {
    super.initState();
    _loadCalibrationInfo();
    // Provide initial guidance
    Future.delayed(
      Duration(milliseconds: 300),
      () => _tts.speak(
        "Step calibration check. Long press anywhere on the screen to start. "
        "After walking 10 steps, long press again to confirm calibration. "
        "The detected step count will be shown in large text on the screen."
      ),
    );
  }

  Future<void> _loadCalibrationInfo() async {
    await StepDetectionService().loadSettings();
    setState(() {
      _oldFactor = StepDetectionService().calibrationFactor;
      _lastCalibrationDate = StepDetectionService().lastCalibrationDate;
    });
  }

  Future<void> _startCalibration() async {
    setState(() {
      _isCalibrating = true;
      _awaitingConfirm = false;
      _detectedSteps = 0;
      _newFactor = null;
    });
    await StepDetectionService().startStepDetection();
    StepDetectionService().stepsTaken = 0;
    StepDetectionService().onStep = () {
      setState(() {
        _detectedSteps = StepDetectionService().stepsTaken;
      });
      if (_detectedSteps > 0 && _detectedSteps % 2 == 0) {
        _tts.speak("Detected steps: $_detectedSteps.");
      }
    };
    await _tts.speak(
      "Calibration check started. Walk 10 steps at your normal pace. "
      "When finished, long press again anywhere to confirm calibration."
    );
    _calibTimeout?.cancel();
    _calibTimeout = Timer(const Duration(seconds: 35), () {
      if (_isCalibrating) {
        _tts.speak("Calibration timed out. Please try again.");
        setState(() {
          _isCalibrating = false;
          _awaitingConfirm = false;
        });
      }
    });
  }

  Future<void> _confirmCalibration() async {
    _calibTimeout?.cancel();
    final userSteps = StepDetectionService().stepsTaken;
    if (userSteps < 3) {
      await _tts.speak(
        "Too few steps detected. Please walk at least 5 steps for calibration."
      );
      return;
    }
    final factor = userSteps / 10.0;
    await StepDetectionService().saveCalibration(factor);
    setState(() {
      _isCalibrating = false;
      _awaitingConfirm = false;
      _newFactor = factor;
      _oldFactor = factor;
      _lastCalibrationDate = StepDetectionService().lastCalibrationDate;
    });
    await _tts.speak(
      "Calibration complete! Your new step factor is ${factor.toStringAsFixed(2)}. "
      "This will improve navigation accuracy."
    );
  }

  void _handleLongPress() {
    if (!_isCalibrating) {
      _startCalibration();
    } else if (!_awaitingConfirm) {
      setState(() {
        _awaitingConfirm = true;
      });
      _tts.speak(
        "Long press again to confirm calibration, or continue walking if you have not finished 10 steps."
      );
      // Give the user a chance to continue walking if they pressed by mistake.
      // No need for Timer here, user can long press again anytime.
    } else {
      _confirmCalibration();
    }
  }

  @override
  void dispose() {
    _calibTimeout?.cancel();
    _tts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final neonBlue = Color(0xFF00F6FF);
    final neonGreen = Color(0xFF39FF14);
    final neonYellow = Color(0xFFFFE347);
    final neonPink = Color(0xFFF500A1);

    return Scaffold(
      appBar: AppBar(
        title: Text("Check Step Calibration"),
        backgroundColor: Colors.deepPurple,
      ),
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPress: _handleLongPress,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28.0, vertical: 14),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.directions_walk, size: 50, color: neonYellow),
                Text(
                  "Current Factor: ${_oldFactor?.toStringAsFixed(2) ?? "--"}",
                  style: TextStyle(color: neonBlue, fontSize: 20, fontWeight: FontWeight.bold),
                ),
                if (_lastCalibrationDate != null)
                  Text(
                    "Last Calibrated: ${_lastCalibrationDate!.split('T').first}",
                    style: TextStyle(color: neonYellow, fontSize: 13),
                  ),
                const SizedBox(height: 36),
                if (!_isCalibrating)
                  Column(
                    children: [
                      Icon(Icons.touch_app, size: 40, color: neonPink),
                      Text(
                        "Long press anywhere\nto start calibration check.",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: neonPink, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                if (_isCalibrating)
                  Column(
                    children: [
                      Text(
                        "Walk 10 steps at your normal pace.",
                        style: TextStyle(color: neonYellow, fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 24),
                      Container(
                        padding: EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: neonBlue.withOpacity(0.13),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          "$_detectedSteps",
                          style: TextStyle(
                            color: neonGreen,
                            fontSize: 72,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 2,
                            shadows: [Shadow(color: neonGreen.withOpacity(0.7), blurRadius: 26)],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      if (!_awaitingConfirm)
                        Text(
                          "Long press again when finished.",
                          style: TextStyle(color: neonPink, fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      if (_awaitingConfirm)
                        Text(
                          "Long press again to confirm calibration.",
                          style: TextStyle(color: neonPink, fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                    ],
                  ),
                if (_newFactor != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 32.0),
                    child: Text(
                      "Calibration complete!\nNew step factor: ${_newFactor!.toStringAsFixed(2)}",
                      style: TextStyle(color: neonGreen, fontSize: 18, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
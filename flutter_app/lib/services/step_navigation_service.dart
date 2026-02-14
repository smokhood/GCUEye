import 'dart:async';
import 'package:flutter_tts/flutter_tts.dart';
import '../helpers/navigation_graph.dart';
import '../helpers/csv_building_map_loader.dart';
import '../helpers/navigation_instruction_generator.dart';
import 'step_detection_service.dart';

class StepInstruction {
  final String fromNode;
  final String targetNode;
  StepInstruction({required this.fromNode, required this.targetNode});
}

class StepNavigationService {
  static final StepNavigationService _instance = StepNavigationService._internal();
  factory StepNavigationService() => _instance;
  StepNavigationService._internal();

  final FlutterTts _flutterTts = FlutterTts();
  NavigationGraph? _graph;
  List<String> _path = [];
  int _currentEdgeIndex = 0;
  bool _isInitialized = false;
  bool _isPaused = false;

  void Function(String nextNode)? onNextInstruction;

  final StepDetectionService _stepDetection = StepDetectionService();
  StepDetectionService get stepDetection => _stepDetection;

  StepInstruction get currentInstruction {
    if (_path.length < 2 || _currentEdgeIndex >= _path.length - 1) {
      return StepInstruction(fromNode: '', targetNode: '');
    }
    return StepInstruction(
      fromNode: _path[_currentEdgeIndex],
      targetNode: _path[_currentEdgeIndex + 1],
    );
  }

  int get currentEdgeIndex => _currentEdgeIndex;
  List<String> get currentPath => _path;
  bool get isPaused => _isPaused;

  Future<void> start(List<String> path) async {
    _graph = await CsvBuildingMapLoader.loadGraph();
    _path = path;
    _currentEdgeIndex = 0;
    _isInitialized = true;
    _isPaused = false;

    _stepDetection.startStepDetection();
    _stepDetection.onStep = () {
      if (_isPaused) return;
      _checkProgress();
    };
    _stepDetection.onError = (msg) async {
      await _flutterTts.speak(msg);
    };

    if (_path.length < 2) {
      await _flutterTts.speak("Invalid path.");
      return;
    }

    final from = _path[0];
    final to = _path[1];
    final edge = _graph!.getEdge(from, to);
    if (edge != null) {
      final instruction = NavigationInstructionGenerator.generateFromEdge(edge, previousNode: null);
      await _flutterTts.speak(instruction);
    }
  }

  void _checkProgress() {
    if (!_isInitialized || _graph == null || _currentEdgeIndex >= _path.length - 1) return;

    final from = _path[_currentEdgeIndex];
    final to = _path[_currentEdgeIndex + 1];
    final edge = _graph!.getEdge(from, to);
    if (edge == null) return;
    final logicalSteps = edge.distance;
    final calibratedSteps = _stepDetection.applyCalibration(logicalSteps);

    if (_stepDetection.stepsTaken >= calibratedSteps) {
      _currentEdgeIndex++;
      _stepDetection.stepsTaken = 0;
      if (_currentEdgeIndex < _path.length - 1) {
        final nextTo = _path[_currentEdgeIndex + 1];
        onNextInstruction?.call(nextTo);
      } else {
        onNextInstruction?.call("done");
        stop();
      }
    }
  }

  void moveToNextInstruction() {
    if (!_isInitialized || _currentEdgeIndex >= _path.length - 1) return;

    final from = _path[_currentEdgeIndex];
    final to = _path[_currentEdgeIndex + 1];
    final prev = (_currentEdgeIndex > 0) ? _path[_currentEdgeIndex - 1] : null;

    final edge = _graph!.getEdge(from, to);
    if (edge != null) {
      final instruction = NavigationInstructionGenerator.generateFromEdge(edge, previousNode: prev);
      _flutterTts.speak(instruction);
    }

    _currentEdgeIndex++;
    _stepDetection.stepsTaken = 0;

    if (_currentEdgeIndex < _path.length - 1) {
      final nextTo = _path[_currentEdgeIndex + 1];
      onNextInstruction?.call(nextTo);
    } else {
      onNextInstruction?.call("done");
      stop();
    }
  }

  String? getPreviousNode() {
    if (_currentEdgeIndex == 0 || _path.length < 2) return null;
    return _path[_currentEdgeIndex - 1];
  }

  void pause() {
    _isPaused = true;
  }

  void resume() {
    _isPaused = false;
  }

  void cancel() {
    _stepDetection.stop();
    _isInitialized = false;
    _isPaused = false;
    _path = [];
    _currentEdgeIndex = 0;
  }

  void stop() {
    cancel();
  }

  void manualStep() {
    _stepDetection.incrementStep();
  }

  Future<void> calibrateStepLength(Function onComplete) async {
    await _flutterTts.speak("Step calibration. Please walk 10 steps at your normal pace. Tap the screen once you finish.");
    _stepDetection.stepsTaken = 0;
    _stepDetection.startStepDetection();
    await Future.delayed(const Duration(seconds: 10));
    await completeCalibration(onComplete);
  }

  Future<void> completeCalibration(Function onComplete) async {
    int endSteps = _stepDetection.stepsTaken;
    double factor = endSteps / 10.0;
    await _stepDetection.saveCalibration(factor);
    await _flutterTts.speak("Calibration saved. Your step factor is $factor. Navigation will now be more accurate.");
    onComplete();
  }
}
import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:vibration/vibration.dart';

import '../services/api_service.dart';
import '../services/tts_service.dart';
import '../widgets/bounding_box.dart';

class CameraView extends StatefulWidget {
  @override
  _CameraViewState createState() => _CameraViewState();
}

class _CameraViewState extends State<CameraView> {
  CameraController? _controller;
  final TtsService _tts = TtsService();

  bool _isDetecting = false;
  Timer? _timer;
  List<dynamic> _detections = [];

  final double imageWidth = 640.0;
  final Set<String> hapticClasses = {
    'door', 'car', 'vehicle', 'dog', 'bike', 'truck', 'obstacle', 'bag', 'box',
  };
  final Set<String> recentAnnouncements = {};

  bool _noDetectionAnnounced = false;

  @override
  void initState() {
    super.initState();
    // --- Speech overlap fix: Stop any previous TTS immediately when entering this page ---
    _tts.stop();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        await _tts.speak("No camera found.");
        return;
      }

      final camera = cameras.first;
      _controller = CameraController(camera, ResolutionPreset.high);

      await _controller!.initialize();
      if (mounted) {
        setState(() {});
        _startDetectionLoop();
      }
    } catch (e) {
      print("Camera error: $e");
      await _tts.speak("Failed to initialize camera.");
    }
  }

  void _startDetectionLoop() {
    _timer = Timer.periodic(Duration(seconds: 2), (_) async {
      if (!mounted || _isDetecting || !_controller!.value.isInitialized) return;

      _isDetecting = true;

      try {
        final image = await _controller!.takePicture();
        final bytes = await File(image.path).readAsBytes();
        final detections = await ApiService.detectObjects(bytes);

        if (!mounted) return;

        setState(() {
          _detections = detections;
        });

        if (detections.isEmpty) {
          if (!_noDetectionAnnounced) {
            _noDetectionAnnounced = true;
            await _announceNoDetection();
          }
        } else {
          _noDetectionAnnounced = false;

          final importantClasses = ['person', 'stair', 'pothole', 'electric pole'];
          final priority = detections.where((d) =>
              importantClasses.contains(d['class'].toLowerCase())).toList();
          final toAnnounce = priority.isNotEmpty ? priority : detections;

          for (final det in toAnnounce) {
            final label = det['class'];
            final bbox = List<double>.from(det['bbox']);
            await _announceObject(label, bbox);
          }
        }
      } catch (e) {
        print("Detection failed: $e");
      }

      _isDetecting = false;
    });
  }

  Future<void> _announceObject(String label, List<double> bbox) async {
    final direction = _getDirectionFromBbox(bbox);
    final key = "$label:$direction";
    if (recentAnnouncements.contains(key)) return;

    recentAnnouncements.add(key);
    if (recentAnnouncements.length > 10) {
      recentAnnouncements.remove(recentAnnouncements.first);
    }

    final message = "$label $direction";
    await _tts.speak(message);

    if (hapticClasses.contains(label.toLowerCase())) {
      if (await Vibration.hasVibrator() ?? false) {
        Vibration.vibrate(duration: 75);
      }
    }
  }

  String _getDirectionFromBbox(List<double> bbox) {
    final x1 = bbox[0];
    final x2 = bbox[2];
    final centerX = (x1 + x2) / 2;

    if (centerX < imageWidth / 3) {
      return "on your left";
    } else if (centerX > 2 * imageWidth / 3) {
      return "on your right";
    } else {
      return "ahead";
    }
  }

  Future<void> _announceNoDetection() async {
    await _tts.speak("No obstacles detected");

    if (await Vibration.hasVibrator() ?? false) {
      Vibration.vibrate(duration: 30);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _timer?.cancel();
    _tts.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null || !_controller!.value.isInitialized) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final previewSize = _controller!.value.previewSize!;
    final aspectRatio = previewSize.height / previewSize.width;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: AspectRatio(
          aspectRatio: aspectRatio,
          child: Stack(
            fit: StackFit.expand,
            children: [
              CameraPreview(_controller!),
              BoundingBox(
                detections: _detections,
                previewWidth: previewSize.height,
                previewHeight: previewSize.width,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
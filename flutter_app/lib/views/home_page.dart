import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'camera_view.dart';
import 'sos_page.dart';
import 'reminder_page.dart';
import 'class_schedule_page.dart';
import 'settings_page.dart';
import 'vr_navigation_page.dart';

class HomePage extends StatefulWidget {
  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  late FlutterTts _flutterTts;
  int _currentPage = 0;

  late AnimationController _spiralController;
  late double _rotation;

  int _lastSpokenPage = -1;

  final List<Map<String, dynamic>> _features = [
    {
      "title": "Indoor VR Navigation",
      "icon": "assets/icons/vr.png",
      "widget": VRNavigationPage(),
      "description": "Double tap to navigate virtually using voice and gestures",
      "color": Color(0xFF7C3AED)
    },
    {
      "title": "Camera Detection",
      "icon": "assets/icons/camera.png",
      "widget": CameraView(),
      "description": "Double tap to start object detection",
      "color": Color(0xFF4F46E5)
    },
    {
      "title": "Class Schedule",
      "icon": "assets/icons/schedule.png",
      "widget": ClassSchedulePage(),
      "description": "Double tap to check your weekly class schedule",
      "color": Color(0xFF1E40AF)
    },
    {
      "title": "Reminders",
      "icon": "assets/icons/reminder.png",
      "widget": ReminderPage(),
      "description": "Double tap to set class reminders by voice",
      "color": Color(0xFF6366F1)
    },
    {
      "title": "SOS Help",
      "icon": "assets/icons/sos.png",
      "widget": SosPage(),
      "description": "Double tap to send SOS messages",
      "color": Color(0xFFDC2626)
    },
    {
      "title": "Settings",
      "icon": "assets/icons/settings.png",
      "widget": SettingsPage(),
      "description": "Double tap to configure app settings",
      "color": Color(0xFF059669)
    },
  ];

  @override
  void initState() {
    super.initState();
    _flutterTts = FlutterTts();
    _rotation = _currentPage * 1.0;
    _spiralController = AnimationController(
      vsync: this,
      duration: Duration(seconds: 8),
    )..repeat();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _speakInstructionsAndPage(_currentPage);
    });
  }

  Future<void> _speakInstructionsAndPage(int page) async {
    await _flutterTts.stop();
    await _flutterTts.speak(
      "${_features[page]['title']}. ${_features[page]['description']}. "
      "Swipe up, down, right or left for more options. Double tap to open."
    );
    _lastSpokenPage = page;
  }

  Future<void> _speakBoundary(bool atStart) async {
    await _flutterTts.stop();
    if (atStart) {
      await _flutterTts.speak("You are at the first option. Swipe down, right, or left for more features.");
    } else {
      await _flutterTts.speak("You are at the last option. Swipe up, right, or left for earlier features.");
    }
  }

  void _handleDoubleTap() async {
    await _flutterTts.stop();
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => _features[_currentPage]['widget']),
    );
    // On return, speak the active page again
    await _speakInstructionsAndPage(_currentPage);
  }

  @override
  void dispose() {
    _flutterTts.stop();
    _spiralController.dispose();
    super.dispose();
  }

  void _onDirectionSwipe(int delta) async {
    _rotation += delta;
    if (_rotation < 0) {
      _rotation = 0;
      await _speakBoundary(true);
    } else if (_rotation > _features.length - 1) {
      _rotation = (_features.length - 1).toDouble();
      await _speakBoundary(false);
    }
    setState(() {
      _currentPage = _rotation.round();
    });
    if (_currentPage != _lastSpokenPage) {
      _speakInstructionsAndPage(_currentPage);
    }
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    setState(() {
      _rotation -= details.primaryDelta! / 80.0;
      if (_rotation < 0) _rotation = 0;
      if (_rotation > _features.length - 1) _rotation = (_features.length - 1).toDouble();
      _currentPage = _rotation.round();
    });
    if (_currentPage != _lastSpokenPage) {
      _speakInstructionsAndPage(_currentPage);
    }
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    setState(() {
      _rotation += details.primaryDelta! < 0 ? -1 : 1;
      if (_rotation < 0) _rotation = 0;
      if (_rotation > _features.length - 1) _rotation = (_features.length - 1).toDouble();
      _currentPage = _rotation.round();
    });
    if (_currentPage != _lastSpokenPage) {
      _speakInstructionsAndPage(_currentPage);
    }
  }

  double _spiralY(int i, double rotation, double spiralScale) {
    return (i - rotation) * 78.0 * spiralScale;
  }

  double _spiralX(int i, double rotation, double spiralTightness, double spiralScale) {
    final angle = (i - rotation) * pi / 2.2;
    return sin(angle) * spiralTightness * 2.9 * spiralScale;
  }

  double _spiralZ(int i, double rotation, double spiralTightness) {
    final angle = (i - rotation) * pi / 2.2;
    return cos(angle) * spiralTightness * 2.4;
  }

  @override
  Widget build(BuildContext context) {
    final cardCount = _features.length;
    final spiralTightness = 25.0;
    final spiralScale = 1.05;
    final size = MediaQuery.of(context).size;

    return GestureDetector(
      onDoubleTap: _handleDoubleTap,
      onVerticalDragUpdate: _onVerticalDragUpdate,
      onHorizontalDragUpdate: _onHorizontalDragUpdate,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            // Vibrant blurred background
            Positioned.fill(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.asset(
                    'assets/bg.jpg',
                    fit: BoxFit.cover,
                  ),
                  Container(
                    decoration: BoxDecoration(
                      gradient: SweepGradient(
                        colors: [
                          Colors.purple.withOpacity(0.11),
                          Colors.blue.withOpacity(0.09),
                          Colors.red.withOpacity(0.10),
                          Colors.purple.withOpacity(0.11),
                        ],
                        stops: [0.1, 0.4, 0.8, 1.0],
                        center: Alignment(0.0, -0.3),
                        startAngle: 0.0,
                        endAngle: 6.28,
                      ),
                    ),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: Alignment(0.0, -0.45),
                        radius: 1.1,
                        colors: [
                          Colors.black.withOpacity(0.78),
                          Colors.transparent
                        ],
                        stops: [0, 1.0],
                      ),
                    ),
                  ),
                  BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                    child: Container(color: Colors.transparent),
                  ),
                ],
              ),
            ),
            // 3D Spiral icons with next-level effects
            AnimatedBuilder(
              animation: _spiralController,
              builder: (context, _) {
                final idleBob = sin(_spiralController.value * 2 * pi) * 9.0;
                final idleRoll = cos(_spiralController.value * 2 * pi) * 0.14;
                final idleGlow = 0.7 + sin(_spiralController.value * 2 * pi) * 0.2;
                final indices = List.generate(cardCount, (i) => i);
                indices.sort((a, b) {
                  final za = _spiralZ(a, _rotation, spiralTightness);
                  final zb = _spiralZ(b, _rotation, spiralTightness);
                  return za.compareTo(zb);
                });

                return Stack(
                  children: [
                    for (final i in indices)
                      _buildSpiralIcon(
                        i,
                        _rotation,
                        idleBob,
                        idleRoll,
                        idleGlow,
                        context,
                        spiralTightness,
                        spiralScale,
                      ),
                  ],
                );
              },
            ),
            // Front icon text & description
            Positioned(
              top: size.height / 2 + 125,
              left: 0,
              right: 0,
              child: AnimatedSwitcher(
                duration: Duration(milliseconds: 400),
                child: Column(
                  key: ValueKey(_currentPage),
                  children: [
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 25, vertical: 9),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.60),
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                            color: _features[_currentPage]['color'].withOpacity(0.19),
                            blurRadius: 16,
                          )
                        ],
                      ),
                      child: Text(
                        _features[_currentPage]['title'],
                        style: TextStyle(
                          fontSize: 25,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.9,
                        ),
                      ),
                    ),
                    SizedBox(height: 13),
                    Container(
                      width: 310,
                      padding: EdgeInsets.symmetric(horizontal: 13, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.41),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: Text(
                        _features[_currentPage]['description'],
                        style: TextStyle(fontSize: 16, color: Colors.white70),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    SizedBox(height: 18),
                    Text(
                      _currentPage == 0
                          ? "First option. Swipe down, right, or left for more."
                          : _currentPage == _features.length - 1
                              ? "Last option. Swipe up, right, or left for previous."
                              : "Swipe up, down, right or left for more options.",
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 15,
                        fontWeight: FontWeight.w400,
                        letterSpacing: 0.2,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      "Double tap to open.",
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSpiralIcon(
    int i,
    double rotation,
    double idleBob,
    double idleRoll,
    double idleGlow,
    BuildContext context,
    double spiralTightness,
    double spiralScale,
  ) {
    final feature = _features[i];
    final isFront = i == _currentPage;
    final size = MediaQuery.of(context).size;

    final x = _spiralX(i, rotation, spiralTightness, spiralScale) + size.width / 2;
    final y = _spiralY(i, rotation, spiralScale) + size.height / 2 + idleBob;
    final z = _spiralZ(i, rotation, spiralTightness);

    final scale = lerpDouble(0.72, 1.28, 0.5 + z / 62.0) ?? 1.0;
    final iconSize = isFront ? 120.0 : 72.0 + 24 * (scale - 0.7);

    final glowColor = feature['color'] as Color;

    final ringGlow = isFront
        ? [
            BoxShadow(
              color: glowColor.withOpacity(0.36 * idleGlow),
              blurRadius: 36 + 18 * idleGlow,
              spreadRadius: 4 + 2 * idleGlow,
            ),
            BoxShadow(
              color: glowColor.withOpacity(0.23 * idleGlow),
              blurRadius: 90,
              spreadRadius: 18,
            ),
          ]
        : [
            BoxShadow(
              color: Colors.black.withOpacity(0.32),
              blurRadius: 12,
              spreadRadius: 0,
              offset: Offset(0, 4),
            )
          ];

    Widget glassReflection() {
      return Positioned(
        top: iconSize * 0.18,
        left: iconSize * 0.12,
        right: iconSize * 0.12,
        child: IgnorePointer(
          child: Container(
            height: iconSize * 0.20,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(iconSize * 0.2),
              gradient: LinearGradient(
                colors: [
                  Colors.white.withOpacity(0.22),
                  Colors.white.withOpacity(0.08),
                  Colors.transparent,
                ],
                stops: [0.0, 0.7, 1.0],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
        ),
      );
    }

    Widget iconImage() {
      Widget img = Image.asset(
        feature['icon'],
        width: iconSize,
        height: iconSize,
        fit: BoxFit.contain,
      );
      if (!isFront && (scale < 0.8)) {
        img = ImageFiltered(
          imageFilter: ImageFilter.blur(
            sigmaX: 2.5 * (1.0 - scale),
            sigmaY: 2.5 * (1.0 - scale),
          ),
          child: img,
        );
      }
      return img;
    }

    final double opacity = isFront
        ? 1.0
        : lerpDouble(0.38, 0.8, (scale - 0.7) / (1.28 - 0.7))!.clamp(0.32, 0.88);

    return Positioned(
      left: x - iconSize / 2,
      top: y - iconSize / 2,
      child: IgnorePointer(
        ignoring: !isFront,
        child: Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..scale(scale)
            ..rotateZ(idleRoll * (isFront ? 1.0 : 0.7))
            ..setEntry(3, 2, 0.0018)
            ..rotateX(0.20),
          child: Opacity(
            opacity: opacity,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: iconSize + 28,
                  height: iconSize + 28,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: ringGlow,
                  ),
                ),
                if (isFront)
                  Container(
                    width: iconSize + 13,
                    height: iconSize + 13,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: glowColor.withOpacity(0.80),
                        width: 4.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: glowColor.withOpacity(0.33 * idleGlow),
                          blurRadius: 28,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                  ),
                if (isFront) glassReflection(),
                iconImage(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
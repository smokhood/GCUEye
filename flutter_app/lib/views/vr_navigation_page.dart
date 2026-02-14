import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import '../services/tts_service.dart';
import '../services/step_navigation_service.dart';
import '../helpers/navigation_instruction_generator.dart';
import '../helpers/navigation_graph.dart';
import '../helpers/csv_building_map_loader.dart';
import '../services/step_detection_service.dart';
import '../services/location_voice_search_service.dart';

class VRNavigationPage extends StatefulWidget {
  @override
  _VRNavigationPageState createState() => _VRNavigationPageState();
}

class _VRNavigationPageState extends State<VRNavigationPage> {
  final TtsService _tts = TtsService();
  final StepNavigationService _stepNav = StepNavigationService();
  late LocationVoiceSearchService _voiceSearch;

  late NavigationGraph _graph;
  List<String> _nodes = [];
  int _selectionIndex = 0;
  String? _startNode;
  String? _endNode;
  bool _selectingStart = true;
  int _tapCount = 0;
  Timer? _tapTimer;
  bool _isNavigating = false;
  bool _awaitingCancel = false;
  bool _isCalibrating = false;
  bool _navigatingInitialized = false;
  bool _searchActive = false;

  static const neonBlue = Color(0xFF00F6FF);
  static const neonPink = Color(0xFFF500A1);
  static const neonGreen = Color(0xFF39FF14);
  static const neonYellow = Color(0xFFFFE347);

  StepMode _stepMode = StepMode.manual;
  double _calibrationFactor = 1.0;
  bool _stepDetectionInitialized = false;

  // --- Two-finger long press workaround ---
  int _pointerCount = 0;
  Timer? _twoFingerTimer;

  @override
  void initState() {
    super.initState();
    // --- Speech overlap fix: Stop any previous TTS immediately when entering this page ---
    _tts.stop();
    _voiceSearch = LocationVoiceSearchService();
    _initializeNavigation();
  }

  Future<void> _initializeNavigation() async {
    try {
      _graph = await CsvBuildingMapLoader.loadGraph();
      setState(() {
        _nodes = _graph.getAllNodeNames();
      });

      StepDetectionService().onModeChanged = (mode) {
        setState(() {
          _stepMode = mode;
          _stepDetectionInitialized = true;
        });
      };
      await StepDetectionService().loadSettings();
      await StepDetectionService().startStepDetection(speakMode: false);

      setState(() {
        _calibrationFactor = StepDetectionService().calibrationFactor;
        _stepDetectionInitialized = true;
      });

      Future.delayed(const Duration(milliseconds: 600), () {
        if (_nodes.isEmpty) {
          _tts.speak("No locations found in the map.");
        } else {
          _speakCurrentGuidance();
        }
      });
    } catch (e, st) {
      print('Navigation data load error: $e\n$st');
      _tts.speak("Error loading navigation data.");
    }
  }

  void _speakCurrentGuidance() {
    if (_isNavigating) return;
    if (_selectingStart || _startNode == null) {
      _tts.speak("Swipe to select start location. Triple tap to select, or swipe down to search by voice.");
    } else if (_endNode == null) {
      _tts.speak("Swipe to select destination. Triple tap to select, or swipe down to search by voice.");
    } else {
      _tts.speak("Long press to start navigation, or swipe down to search by voice.");
    }
  }

  void _onSwipeRight() {
    if (_isNavigating || _nodes.isEmpty || _isCalibrating || _searchActive) return;
    setState(() {
      _selectionIndex = (_selectionIndex + 1) % _nodes.length;
    });
    _tts.speak(_nodes[_selectionIndex]);
  }

  void _onSwipeLeft() {
    if (_isNavigating || _nodes.isEmpty || _isCalibrating || _searchActive) return;
    setState(() {
      _selectionIndex = (_selectionIndex - 1 + _nodes.length) % _nodes.length;
    });
    _tts.speak(_nodes[_selectionIndex]);
  }

  void _onTripleTap() {
    if (_isNavigating || _isCalibrating || _searchActive) return;
    final selected = _nodes[_selectionIndex];
    if (_selectingStart) {
      _startNode = selected;
      setState(() {
        _selectingStart = false;
      });
      _tts.speak("Start point selected: $selected. Swipe to select destination. Triple tap to select, or swipe down to search by voice.");
    } else {
      _endNode = selected;
      _tts.speak("Destination selected: $selected. Long press to start navigation, or swipe down to search by voice.");
      setState(() {});
    }
  }

  void _onDoubleTap() {
    if (!_isNavigating || _isCalibrating || _searchActive) return;
    if (_stepNav.isPaused) {
      _stepNav.resume();
      _tts.speak("Resuming navigation.");
    } else {
      _stepNav.pause();
      _tts.speak("Navigation paused.");
    }
  }

  void _onLongPress() async {
    if (_isCalibrating) {
      _onCalibrationConfirm();
      return;
    }
    if (_searchActive) return;
    if (_isNavigating) {
      _speakInstruction();
      return;
    }
    if (_startNode == null || _endNode == null) {
      _tts.speak("Please select both start and destination.");
      return;
    }
    final path = _graph.shortestPath(_startNode!, _endNode!);
    if (path.isEmpty) {
      _tts.speak("No path found from $_startNode to $_endNode.");
      return;
    }

    setState(() {
      _isNavigating = true;
      _navigatingInitialized = true;
    });

    await StepDetectionService().startStepDetection(speakMode: true);

    await _tts.speak(
        "Navigation started. Walk to advance. If unavailable, tap the screen to advance. Long press to repeat the current instruction. Two finger long press to cancel.");

    // Set up onNextInstruction callback for UI and TTS sync
    _stepNav.onNextInstruction = (nextNode) {
      if (nextNode == "done") {
        _tts.speak(
            NavigationInstructionGenerator.generateFinalInstruction(_endNode!));
        setState(() {
          _isNavigating = false;
          _startNode = _endNode;
          _selectingStart = false;
          _endNode = null;
          _navigatingInitialized = false;
        });
        Future.delayed(const Duration(seconds: 1), () {
          _speakCurrentGuidance();
        });
      } else {
        setState(() {}); // update UI immediately
        _speakInstruction();
      }
    };

    await _stepNav.start(path);
    setState(() {});
    // Trigger the very first instruction via the callback, not directly here
    _stepNav.moveToNextInstruction();
  }

  void _onTwoFingerLongPress() {
    if (_isNavigating && !_awaitingCancel) {
      setState(() => _awaitingCancel = true);
      _tts.speak(
          "Navigation cancelled. Please select start and destination again.");
      setState(() {
        _isNavigating = false;
        _startNode = null;
        _endNode = null;
        _selectingStart = true;
        _navigatingInitialized = false;
      });
      _stepNav.cancel();
      Future.delayed(const Duration(milliseconds: 1200), () {
        setState(() => _awaitingCancel = false);
        _speakCurrentGuidance();
      });
    }
  }

  void _speakInstruction() {
    if (!_navigatingInitialized) return;
    final step = _stepNav.currentInstruction;
    final previous = _stepNav.getPreviousNode();
    final instruction = NavigationInstructionGenerator.generate(
      _graph,
      step.fromNode,
      step.targetNode,
      previousNode: previous,
    );
    _tts.speak(instruction);
  }

  IconData _getDirectionIcon() {
    final route = _stepNav.currentPath;
    final idx = _stepNav.currentEdgeIndex;
    if (!_isNavigating || !_navigatingInitialized || route.length < 2 || idx >= route.length - 1) {
      return Icons.flag;
    }
    final from = route[idx];
    final to = route[idx + 1];
    final edge = _graph.getEdge(from, to);
    final dir = (edge?.direction.toLowerCase() ?? '');
    if (dir.contains('left')) return Icons.arrow_back;
    if (dir.contains('right')) return Icons.arrow_forward;
    if (dir.contains('forward') || dir.contains('straight'))
      return Icons.arrow_upward;
    if (dir.contains('backward') || dir.contains('down'))
      return Icons.arrow_downward;
    return Icons.directions_walk;
  }

  String _getCurrentInstructionText() {
    final route = _stepNav.currentPath;
    final idx = _stepNav.currentEdgeIndex;
    if (!_isNavigating || !_navigatingInitialized || route.length < 2 || idx >= route.length - 1) {
      return "";
    }
    final from = route[idx];
    final to = route[idx + 1];
    final previous = idx > 0 ? route[idx - 1] : null;
    return NavigationInstructionGenerator.generate(
      _graph,
      from,
      to,
      previousNode: previous,
    );
  }

  // --- Calibration logic ---

  int _calibrationSteps = 0;
  Timer? _calibrationTimer;

  void _startCalibration() async {
    if (_isNavigating || _isCalibrating || _searchActive) return;
    setState(() {
      _isCalibrating = true;
      _calibrationSteps = 0;
    });
    await _tts.speak(
        "Step calibration. When ready, walk 10 steps at your normal pace. Long press to confirm when finished.");
    await StepDetectionService().startStepDetection(speakMode: true);
    StepDetectionService().stepsTaken = 0;
    StepDetectionService().onStep = () {
      setState(() {
        _calibrationSteps = StepDetectionService().stepsTaken;
      });
    };
  }

  void _onCalibrationConfirm() async {
    _calibrationTimer?.cancel();
    int userSteps = StepDetectionService().stepsTaken;
    double factor = userSteps / 10.0;
    await StepDetectionService().saveCalibration(factor);
    setState(() {
      _calibrationFactor = factor;
      _isCalibrating = false;
    });
    _tts.speak(
        "Calibration complete. Your step factor is $factor. Navigation will now be more accurate.");
    StepDetectionService().onModeChanged?.call(StepDetectionService().mode);
  }

  // --- Voice Search integration ---

  Future<void> _triggerVoiceSearchForCurrent() async {
    if (_isNavigating || _isCalibrating || _searchActive) return;
    setState(() {
      _searchActive = true;
    });
    final isSelectingStart = _selectingStart || _startNode == null;
    await _voiceSearch.searchLocation(
      context: context,
      nodeNames: _nodes,
      onFound: (selectedNode) {
        if (selectedNode != null) {
          setState(() {
            if (isSelectingStart) {
              _startNode = selectedNode;
              _selectingStart = false;
              _selectionIndex = _nodes.indexOf(selectedNode);
              _tts.speak("Start location set to $selectedNode. Now select your destination.");
            } else {
              _endNode = selectedNode;
              _selectionIndex = _nodes.indexOf(selectedNode);
              _tts.speak("Destination set to $selectedNode. Long press to start navigation.");
            }
          });
        } else {
          if (isSelectingStart) {
            _tts.speak("Start location search cancelled. Swipe to select or try again.");
          } else {
            _tts.speak("Destination search cancelled. Swipe to select or try again.");
          }
        }
        setState(() {
          _searchActive = false;
        });
      },
      searchFor: isSelectingStart ? 'start' : 'destination',
    );
  }

  @override
  void dispose() {
    _tts.dispose();
    _stepNav.cancel();
    _tapTimer?.cancel();
    _calibrationTimer?.cancel();
    _twoFingerTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool highlightGreen =
        _selectingStart || (_startNode != null && !_selectingStart);
    final String stageText = _isCalibrating
        ? "CALIBRATING STEPS"
        : _isNavigating
            ? "NAVIGATING"
            : _selectingStart
                ? "SELECT START LOCATION"
                : "SELECT DESTINATION";
    final nodeColor = highlightGreen ? neonGreen : neonPink;

    final route = _stepNav.currentPath;
    final idx = _stepNav.currentEdgeIndex;

    return Listener(
      onPointerDown: (event) {
        _pointerCount++;
        if (_pointerCount == 2 && !_isCalibrating && !_searchActive) {
          _twoFingerTimer = Timer(const Duration(milliseconds: 600), () {
            _onTwoFingerLongPress();
          });
        }
      },
      onPointerUp: (event) {
        _pointerCount = 0;
        _twoFingerTimer?.cancel();
      },
      child: GestureDetector(
        // --- NO onScaleStart here! ---
        onHorizontalDragEnd: (details) {
          if (details.primaryVelocity != null && !_isCalibrating && !_searchActive) {
            if (details.primaryVelocity! < 0) {
              _onSwipeRight();
            } else if (details.primaryVelocity! > 0) {
              _onSwipeLeft();
            }
          }
        },
        // Swipe down to trigger voice search (for both start and destination context)
        onVerticalDragEnd: (details) {
          // Downward swipe (positive velocity)
          if (details.primaryVelocity != null && details.primaryVelocity! > 0 &&
              !_isCalibrating && !_searchActive) {
            _triggerVoiceSearchForCurrent();
          }
        },
        onTap: () async {
          if (_isCalibrating || _searchActive) return;
          if (_isNavigating && _navigatingInitialized && StepDetectionService().mode == StepMode.manual) {
            _stepNav.moveToNextInstruction();
            setState(() {});
            // Do NOT call _speakInstruction() here, let onNextInstruction handle TTS after navigation state changes!
            return;
          }
          _tapCount++;
          _tapTimer ??= Timer(const Duration(milliseconds: 500), () {
            if (_tapCount == 2) {
              _onDoubleTap();
            } else if (_tapCount >= 3) {
              _onTripleTap();
            }
            _tapCount = 0;
            _tapTimer = null;
          });
        },
        onLongPress: _onLongPress,
        child: Scaffold(
          body: Stack(
            children: [
              SizedBox.expand(
                child: Image.asset(
                  'assets/space_bg.jpeg',
                  fit: BoxFit.cover,
                ),
              ),
              Container(color: Colors.black.withOpacity(0.45)),
              if (_searchActive)
                _buildVoiceSearchOverlay(),
              SafeArea(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          vertical: 10.0, horizontal: 14),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                          child: Container(
                            color: Colors.black.withOpacity(0.15),
                            padding: const EdgeInsets.symmetric(
                                vertical: 7, horizontal: 15),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    stageText,
                                    style: TextStyle(
                                      color: neonPink,
                                      fontSize: 19,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 2,
                                      shadows: [
                                        Shadow(
                                            color: neonPink, blurRadius: 18)
                                      ],
                                    ),
                                  ),
                                ),
                                if (!_isNavigating && !_isCalibrating && !_searchActive)
                                  IconButton(
                                    icon: Icon(Icons.directions_walk,
                                        color: neonBlue, size: 27),
                                    tooltip: 'Calibrate Steps',
                                    onPressed: _startCalibration,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          vertical: 6.0, horizontal: 12.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            "Step Mode: ",
                            style: TextStyle(
                              color: neonYellow,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            _isCalibrating
                                ? "Calibrating"
                                : _stepMode == StepMode.hardware
                                    ? "Automatic"
                                    : _stepMode == StepMode.accelerometer
                                        ? "Accelerometer"
                                        : "Manual",
                            style: TextStyle(
                              color: neonBlue,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (!_isCalibrating)
                            Padding(
                              padding: const EdgeInsets.only(left: 20),
                              child: Text(
                                "Calibration: ${_calibrationFactor.toStringAsFixed(2)}",
                                style: TextStyle(
                                  color: neonYellow,
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Center(
                        child: _isCalibrating
                            ? _buildCalibrationUI()
                            : _isNavigating && _navigatingInitialized
                                ? Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Container(
                                        margin:
                                            const EdgeInsets.only(bottom: 12),
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          boxShadow: [
                                            BoxShadow(
                                              color:
                                                  neonYellow.withOpacity(0.7),
                                              blurRadius: 40,
                                              spreadRadius: 16,
                                            ),
                                          ],
                                        ),
                                        child: Icon(
                                          _getDirectionIcon(),
                                          color: neonYellow,
                                          size: 100,
                                        ),
                                      ),
                                      Padding(
                                        padding:
                                            const EdgeInsets.symmetric(
                                                vertical: 10.0,
                                                horizontal: 16),
                                        child: ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(18),
                                          child: BackdropFilter(
                                            filter: ImageFilter.blur(
                                                sigmaX: 10, sigmaY: 10),
                                            child: Container(
                                              color: Colors.black
                                                  .withOpacity(0.45),
                                              padding:
                                                  const EdgeInsets.all(16),
                                              child: Text(
                                                _getCurrentInstructionText(),
                                                textAlign: TextAlign.center,
                                                style: TextStyle(
                                                  color: neonBlue,
                                                  fontSize: 26,
                                                  fontWeight:
                                                      FontWeight.w700,
                                                  letterSpacing: 1.2,
                                                  shadows: [
                                                    Shadow(
                                                      color: neonBlue
                                                          .withOpacity(0.5),
                                                      blurRadius: 25,
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        child: ListView.builder(
                                          shrinkWrap: true,
                                          itemCount: route.length,
                                          itemBuilder: (context, i) {
                                            return Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      vertical: 6,
                                                      horizontal: 24),
                                              child: Container(
                                                decoration: BoxDecoration(
                                                  color: i == idx
                                                      ? neonBlue
                                                          .withOpacity(0.19)
                                                      : Colors.black
                                                          .withOpacity(0.18),
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          12),
                                                  border: i == idx
                                                      ? Border.all(
                                                          color: neonBlue,
                                                          width: 2)
                                                      : Border.all(
                                                          color: Colors
                                                              .transparent),
                                                  boxShadow: i == idx
                                                      ? [
                                                          BoxShadow(
                                                            color: neonBlue
                                                                .withOpacity(
                                                                    0.25),
                                                            blurRadius: 16,
                                                            spreadRadius: 7,
                                                          ),
                                                        ]
                                                      : [],
                                                ),
                                                child: Row(
                                                  children: [
                                                    Icon(
                                                      i == idx
                                                          ? Icons
                                                              .radio_button_checked
                                                          : Icons
                                                              .radio_button_unchecked,
                                                      color: i == idx
                                                          ? neonBlue
                                                          : neonPink
                                                              .withOpacity(
                                                                  0.7),
                                                      size: 22,
                                                    ),
                                                    const SizedBox(
                                                        width: 12),
                                                    Text(
                                                      route[i],
                                                      style: TextStyle(
                                                        color: i == idx
                                                            ? neonBlue
                                                            : neonPink
                                                                .withOpacity(
                                                                    0.7),
                                                        fontWeight: i == idx
                                                            ? FontWeight.bold
                                                            : FontWeight.w600,
                                                        fontSize: 21,
                                                        letterSpacing: 1.1,
                                                        shadows: i == idx
                                                            ? [
                                                                Shadow(
                                                                    color: neonBlue
                                                                        .withOpacity(
                                                                            0.7),
                                                                    blurRadius:
                                                                        18)
                                                              ]
                                                            : [],
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        "Two-finger long press to cancel navigation.",
                                        style: TextStyle(
                                          color:
                                              neonPink.withOpacity(0.9),
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          shadows: [
                                            Shadow(
                                              color: neonPink
                                                  .withOpacity(0.6),
                                              blurRadius: 18,
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                    ],
                                  )
                                : Column(
                                    mainAxisAlignment:
                                        MainAxisAlignment.center,
                                    children: [
                                      Center(
                                        child: Text(
                                          _nodes.isEmpty
                                              ? "Loading..."
                                              : _nodes[_selectionIndex],
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            color: nodeColor,
                                            fontSize: 48,
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: 2,
                                            shadows: [
                                              Shadow(
                                                color: nodeColor
                                                    .withOpacity(0.7),
                                                blurRadius: 60,
                                              ),
                                              Shadow(
                                                color: Colors.black
                                                    .withOpacity(0.8),
                                                blurRadius: 10,
                                                offset: Offset(0, 2),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      if (_startNode != null)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                              top: 18.0),
                                          child: Text(
                                            "Current: $_startNode",
                                            style: TextStyle(
                                              color: neonBlue
                                                  .withOpacity(0.90),
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                              shadows: [
                                                Shadow(
                                                  color: neonBlue
                                                      .withOpacity(0.3),
                                                  blurRadius: 12,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      if (_endNode != null &&
                                          !_selectingStart)
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(top: 8.0),
                                          child: Text(
                                            "Destination selected: $_endNode",
                                            style: TextStyle(
                                              color: neonPink,
                                              fontSize: 18,
                                              fontWeight: FontWeight.w700,
                                              shadows: [
                                                Shadow(
                                                  color: neonPink
                                                      .withOpacity(0.4),
                                                  blurRadius: 12,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      const SizedBox(height: 30),
                                      Align(
                                        alignment: Alignment.bottomCenter,
                                        child: Padding(
                                          padding:
                                              const EdgeInsets.symmetric(
                                                  horizontal: 24.0),
                                          child: ClipRRect(
                                            borderRadius:
                                                BorderRadius.circular(18),
                                            child: BackdropFilter(
                                              filter: ImageFilter.blur(
                                                  sigmaX: 12, sigmaY: 12),
                                              child: Container(
                                                color: Colors.black
                                                    .withOpacity(0.21),
                                                padding:
                                                    const EdgeInsets.all(12),
                                                child: Text(
                                                  _selectingStart
                                                      ? "Swipe to choose start location. Triple tap to select, or swipe down to search by voice."
                                                      : (_endNode == null
                                                          ? "Swipe to choose destination. Triple tap to select, or swipe down to search by voice."
                                                          : "Long press to start navigation, or swipe down to search by voice."),
                                                  textAlign: TextAlign.center,
                                                  style: TextStyle(
                                                    color: neonYellow
                                                        .withOpacity(0.97),
                                                    fontSize: 18,
                                                    fontWeight: FontWeight.bold,
                                                    letterSpacing: 1.3,
                                                    shadows: [
                                                      Shadow(
                                                        color: neonYellow
                                                            .withOpacity(
                                                                0.7),
                                                        blurRadius: 18,
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCalibrationUI() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.directions_walk, size: 80, color: neonYellow),
        const SizedBox(height: 26),
        Text(
          "Step Calibration",
          style: TextStyle(
            color: neonBlue,
            fontSize: 32,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.1,
            shadows: [
              Shadow(
                color: neonBlue.withOpacity(0.8),
                blurRadius: 18,
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Text(
          "Walk 10 steps at your normal pace.",
          style: TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          "Detected steps: $_calibrationSteps",
          style: TextStyle(
            color: neonGreen,
            fontSize: 28,
            fontWeight: FontWeight.w900,
            shadows: [
              Shadow(
                color: neonGreen.withOpacity(0.7),
                blurRadius: 26,
              ),
            ],
          ),
        ),
        const SizedBox(height: 30),
        Container(
          padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: neonPink.withOpacity(0.21),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            "Long press to confirm when you finish walking.",
            style: TextStyle(
              color: neonPink,
              fontSize: 18,
              fontWeight: FontWeight.bold,
              shadows: [
                Shadow(
                  color: neonPink.withOpacity(0.4),
                  blurRadius: 14,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildVoiceSearchOverlay() {
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: false,
        child: Container(
          color: Colors.black.withOpacity(0.75),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.mic, color: neonBlue, size: 80),
                SizedBox(height: 30),
                Text(
                  "Voice search active...",
                  style: TextStyle(
                    color: neonBlue,
                    fontSize: 27,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.1,
                    shadows: [
                      Shadow(
                        color: neonBlue.withOpacity(0.8),
                        blurRadius: 20,
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 20),
                Text(
                  "Please say your location.",
                  style: TextStyle(
                    color: neonYellow,
                    fontSize: 21,
                    fontWeight: FontWeight.w700,
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
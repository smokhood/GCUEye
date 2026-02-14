import 'package:flutter/material.dart';
import '../services/tts_service.dart';
import '../services/speech_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/listening_overlay.dart';

class SosContactSetupPage extends StatefulWidget {
  @override
  _SosContactSetupPageState createState() => _SosContactSetupPageState();
}

class _SosContactSetupPageState extends State<SosContactSetupPage> {
  final TtsService _tts = TtsService();
  final SpeechService _speech = SpeechService();
  final TextEditingController _manualController = TextEditingController();

  bool _isListening = false;
  bool _firstInstructionSpoken = false;
  List<String> _contacts = [];
  int _selectedIndex = -1;
  String _recognizedText = '';

  @override
  void initState() {
    super.initState();
    _loadContacts();
    _tts.speak(
      "Welcome to SOS contact setup. Hold your finger on screen and say a number to add. Or type it. Double tap to delete. Swipe to select.",
    );
  }

  Future<void> _loadContacts() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _contacts = prefs.getStringList('sos_contacts') ?? [];
    });
  }

  Future<void> _saveContacts() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('sos_contacts', _contacts);
  }

  void _addContact(String input) async {
    final cleaned = input.replaceAll(RegExp(r'[^\d+]'), '');
    if (RegExp(r'^\+?\d{10,15}$').hasMatch(cleaned)) {
      setState(() {
        _contacts.add(cleaned);
        _selectedIndex = _contacts.length - 1;
      });
      await _saveContacts();
      await _tts.speak("Contact $cleaned added.");
    } else {
      await _tts.speak("That is not a valid number.");
    }
  }

  void _onLongPressStart(LongPressStartDetails _) async {
    setState(() => _isListening = true);

    if (!_firstInstructionSpoken) {
      await _tts.speak("Listening. Say number like plus nine two three one...");
      _firstInstructionSpoken = true;
    }

    _recognizedText = '';

    await _speech.startListening(
      onResult: (text) {
        setState(() {
          _recognizedText = text.replaceAll(RegExp(r'\s+'), '');
        });
      },
      onSpeechStart: () => setState(() => _isListening = true),
      onSpeechEnd: () => setState(() => _isListening = false),
    );
  }

  void _onLongPressEnd(LongPressEndDetails _) async {
    await _speech.stopListening();
    setState(() => _isListening = false);

    if (_recognizedText.isEmpty) {
      await _tts.speak("No speech detected.");
      return;
    }

    _addContact(_recognizedText);
  }

  void _deleteSelectedContact() async {
    if (_selectedIndex >= 0 && _selectedIndex < _contacts.length) {
      final deleted = _contacts[_selectedIndex];
      setState(() {
        _contacts.removeAt(_selectedIndex);
        if (_selectedIndex > 0) _selectedIndex--;
      });
      await _saveContacts();
      _tts.speak("Contact $deleted deleted.");
    } else {
      _tts.speak("No contact selected to delete.");
    }
  }

  void _moveSelection(bool forward) {
    if (_contacts.isEmpty) return;
    setState(() {
      _selectedIndex = forward
          ? (_selectedIndex + 1) % _contacts.length
          : (_selectedIndex - 1 + _contacts.length) % _contacts.length;
    });
    _tts.speak("Selected contact: ${_contacts[_selectedIndex]}");
  }

  @override
  void dispose() {
    _speech.stopListening();
    _tts.dispose();
    _manualController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text("SOS Contacts"),
        backgroundColor: Colors.deepPurple,
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(12, 16, 12, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _manualController,
                        keyboardType: TextInputType.phone,
                        style: TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: "Enter phone number",
                          hintStyle: TextStyle(color: Colors.white54),
                          filled: true,
                          fillColor: Colors.grey[850],
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    SizedBox(width: 10),
                    ElevatedButton(
                      onPressed: () {
                        _addContact(_manualController.text);
                        _manualController.clear();
                      },
                      child: Text("Add"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepPurple,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onLongPressStart: _onLongPressStart,
                  onLongPressEnd: _onLongPressEnd,
                  onDoubleTap: _deleteSelectedContact,
                  onHorizontalDragEnd: (details) {
                    if (details.primaryVelocity != null) {
                      _moveSelection(details.primaryVelocity! < 0);
                    }
                  },
                  child: ListView.builder(
                    itemCount: _contacts.length,
                    itemBuilder: (_, index) {
                      final contact = _contacts[index];
                      final selected = index == _selectedIndex;
                      return Container(
                        margin:
                            EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        padding: EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: selected
                              ? Colors.deepPurpleAccent
                              : Colors.grey[850],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          contact,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight:
                                selected ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
          ListeningOverlay(isListening: _isListening),
        ],
      ),
    );
  }
}

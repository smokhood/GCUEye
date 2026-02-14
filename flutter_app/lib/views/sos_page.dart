import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:telephony/telephony.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

class SosPage extends StatefulWidget {
  @override
  _SosPageState createState() => _SosPageState();
}

class _SosPageState extends State<SosPage> {
  late FlutterTts _flutterTts;
  final Telephony telephony = Telephony.instance;

  List<String> emergencyContacts = [];
  bool _permissionGranted = false;

  @override
  void initState() {
    super.initState();
    _flutterTts = FlutterTts();
    // --- Speech overlap fix: Stop any previous TTS immediately when entering this page ---
    _flutterTts.stop();
    _speakInstructions();
    requestSmsPermission();
    _loadContacts();
  }

  void _speakInstructions() {
    _flutterTts.speak(
      "Long press to send SOS message. Double tap to call your emergency contact.",
    );
  }

  void requestSmsPermission() async {
    final bool? result = await telephony.requestSmsPermissions;
    if (result != null && result) {
      setState(() {
        _permissionGranted = true;
      });
    } else {
      _flutterTts.speak("SMS permission denied. Please allow it in settings.");
    }
  }

  void _loadContacts() async {
    final prefs = await SharedPreferences.getInstance();
    final savedContacts = prefs.getStringList('sos_contacts') ?? [];
    setState(() {
      emergencyContacts = savedContacts;
    });
  }

  void sendSOSMessages() async {
    if (!_permissionGranted) {
      _flutterTts.speak("Cannot send SOS. SMS permission not granted.");
      return;
    }

    if (emergencyContacts.isEmpty) {
      _flutterTts.speak("No emergency contacts found. Please set them in settings.");
      return;
    }

    for (var contact in emergencyContacts) {
      await telephony.sendSms(
        to: contact,
        message: "This is an SOS alert from Blind Vision. I need immediate help.",
      );
    }

    _flutterTts.speak("SOS message sent to emergency contacts.");
  }

  void makeSOSCall(String phoneNumber) async {
    final Uri callUri = Uri(scheme: 'tel', path: phoneNumber);

    try {
      if (!await launchUrl(
        callUri,
        mode: LaunchMode.externalApplication,
      )) {
        _flutterTts.speak("Unable to initiate call.");
      }
    } catch (e) {
      _flutterTts.speak("Error while trying to make the call.");
      print('Call error: $e');
    }
  }

  @override
  void dispose() {
    _flutterTts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("SOS Help"),
        backgroundColor: Colors.redAccent,
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPress: sendSOSMessages,
        onDoubleTap: () {
          if (emergencyContacts.isNotEmpty) {
            makeSOSCall(emergencyContacts.first);
          } else {
            _flutterTts.speak("No emergency contacts to call.");
          }
        },
        child: Container(
          width: double.infinity,
          height: double.infinity,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.warning_amber_rounded,
                    size: 100, color: Colors.redAccent),
                SizedBox(height: 20),
                Text(
                  "Long press to send SOS\nDouble tap to call",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.grey[700],
                    fontSize: 18,
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
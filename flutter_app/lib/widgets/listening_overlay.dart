import 'package:flutter/material.dart';

class ListeningOverlay extends StatelessWidget {
  final bool isListening;

  const ListeningOverlay({super.key, required this.isListening});

  @override
  Widget build(BuildContext context) {
    if (!isListening) return SizedBox.shrink();
    return Container(
      color: Colors.black.withOpacity(0.6),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.mic, size: 80, color: Colors.white),
            SizedBox(height: 10),
            Text(
              "Listening...",
              style: TextStyle(color: Colors.white, fontSize: 24),
            ),
          ],
        ),
      ),
    );
  }
}

// lib/services/api_service.dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

class ApiService {
  static const String _url = "http://10.253.58.43:8000/predict"; // Replace with your server IP

  static Future<List<dynamic>> detectObjects(Uint8List imageBytes) async {
    try {
      var request = http.MultipartRequest('POST', Uri.parse(_url));
      request.files.add(http.MultipartFile.fromBytes(
        'image',
        imageBytes,
        filename: 'frame.jpg',
      ));

      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic> && decoded.containsKey('detections')) {
          return decoded['detections'];
        } else {
          print("Unexpected response structure: $decoded");
          return [];
        }
      } else {
        print("Server error: ${response.statusCode}");
        return [];
      }
    } catch (e) {
      print("API error: $e");
      return [];
    }
  }
}

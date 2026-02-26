import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

class ApiService {
  static const String baseUrl = 'http://10.16.168.73:5000';

  Future<Map<String, dynamic>> registerVoice(String username, String audioPath) async {
    try {
      var request = http.MultipartRequest('POST', Uri.parse('$baseUrl/register_voice'));
      request.fields['username'] = username;

      if (audioPath.isNotEmpty && await File(audioPath).exists()) {
        request.files.add(await http.MultipartFile.fromPath(
          'audio',
          audioPath,
          contentType: MediaType('audio', 'aac'),
        ));
      } else {
        return {'error': 'Audio file not found'};
      }

      var response = await request.send();
      var responseBody = await response.stream.bytesToString();
      return json.decode(responseBody);
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> loginVoice(String username, String audioPath) async {
    try {
      var request = http.MultipartRequest('POST', Uri.parse('$baseUrl/login_voice'));
      request.fields['username'] = username;

      if (audioPath.isNotEmpty && await File(audioPath).exists()) {
        request.files.add(await http.MultipartFile.fromPath(
          'audio',
          audioPath,
          contentType: MediaType('audio', 'aac'),
        ));
      } else {
        return {'error': 'Audio file not found'};
      }

      var response = await request.send();
      var responseBody = await response.stream.bytesToString();
      return json.decode(responseBody);
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> processCameraFrame(List<int> imageBytes) async {
    try {
      var uri = Uri.parse('$baseUrl/process_frame');

      var request = http.MultipartRequest('POST', uri);
      request.files.add(
        http.MultipartFile.fromBytes(
          'frame',
          imageBytes,
          filename: 'frame.jpg',
          contentType: MediaType('image', 'jpeg'),
        ),
      );

      var response = await request.send();
      var responseBody = await response.stream.bytesToString();

      return json.decode(responseBody);
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> processVoiceCommand(String text, {String? username}) async {
    try {
      var request = http.MultipartRequest('POST', Uri.parse('$baseUrl/voice_command'));
      request.fields['text'] = text;
      if (username != null) {
        request.fields['username'] = username;
      }

      var response = await request.send();
      var responseBody = await response.stream.bytesToString();

      return json.decode(responseBody);
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> getCurrentTime() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/get_time'));

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        return {'error': 'Server responded with status ${response.statusCode}'};
      }
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  // ==================== ЗАМЕТКИ ====================

  Future<Map<String, dynamic>> addNote({
    required String username,
    required String noteText,
    String? remindAt,
  }) async {
    try {
      var request = http.MultipartRequest('POST', Uri.parse('$baseUrl/add_note'));
      request.fields['username'] = username;
      request.fields['note_text'] = noteText;
      if (remindAt != null) {
        request.fields['remind_at'] = remindAt;
      }

      var response = await request.send();
      var responseBody = await response.stream.bytesToString();

      return json.decode(responseBody);
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> getNotes(String username) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/get_notes?username=$username'),
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        return {'error': 'Server responded with status ${response.statusCode}'};
      }
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> updateNote({
    required int noteId,
    String? noteText,
    String? remindAt,
  }) async {
    try {
      var request = http.MultipartRequest('POST', Uri.parse('$baseUrl/update_note'));
      request.fields['note_id'] = noteId.toString();
      if (noteText != null) {
        request.fields['note_text'] = noteText;
      }
      if (remindAt != null) {
        request.fields['remind_at'] = remindAt;
      }

      var response = await request.send();
      var responseBody = await response.stream.bytesToString();

      return json.decode(responseBody);
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> deleteNote(int noteId) async {
    try {
      var request = http.MultipartRequest('POST', Uri.parse('$baseUrl/delete_note'));
      request.fields['note_id'] = noteId.toString();

      var response = await request.send();
      var responseBody = await response.stream.bytesToString();

      return json.decode(responseBody);
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> completeNote(int noteId) async {
    try {
      var request = http.MultipartRequest('POST', Uri.parse('$baseUrl/complete_note'));
      request.fields['note_id'] = noteId.toString();

      var response = await request.send();
      var responseBody = await response.stream.bytesToString();

      return json.decode(responseBody);
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> checkReminders(String username) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/check_reminders?username=$username'),
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        return {'error': 'Server responded with status ${response.statusCode}'};
      }
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> testConnection() async {
    try {
      final response = await http.get(Uri.parse(baseUrl));

      if (response.statusCode == 200) {
        return {'status': 'ok'};
      } else {
        return {'error': 'Server responded with status ${response.statusCode}'};
      }
    } catch (e) {
      return {'error': e.toString()};
    }
  }
}
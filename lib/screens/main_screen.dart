import 'package:flutter/material.dart';
import '../services/audio_service.dart';
import '../services/api_service.dart';

class MainScreen extends StatelessWidget {
  final SimpleAudioService audioService;
  final ApiService apiService;
  final String username;

  const MainScreen({
    super.key,
    required this.audioService,
    required this.apiService,
    required this.username,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Главный экран ($username)'),
      ),
      body: Center(
        child: Text('Добро пожаловать, $username!'),
      ),
    );
  }
}

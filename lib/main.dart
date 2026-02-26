import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'services/audio_service.dart';
import 'services/api_service.dart';
import 'screens/login_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ЗАГРУЖАЕМ .ENV ФАЙЛ
  try {
    await dotenv.load(fileName: ".env");
    print('✅ .env файл загружен');
  } catch (e) {
    print('⚠️ .env файл не найден: $e');
  }

  final audioService = SimpleAudioService();
  await audioService.initialize();

  runApp(BlindAssistantApp(audioService: audioService));
}

class BlindAssistantApp extends StatelessWidget {
  final SimpleAudioService audioService;
  final ApiService apiService = ApiService();

  BlindAssistantApp({super.key, required this.audioService});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Помощник для слабовидящих',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: VoiceLoginScreen(
        audioService: audioService,
        apiService: apiService,
      ),
    );
  }
}
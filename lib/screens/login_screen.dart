import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_sound/flutter_sound.dart';
import '../services/audio_service.dart';
import '../services/api_service.dart';
import 'camera_screen.dart';

class VoiceLoginScreen extends StatefulWidget {
  final SimpleAudioService audioService;
  final ApiService apiService;

  const VoiceLoginScreen({
    Key? key,
    required this.audioService,
    required this.apiService,
  }) : super(key: key);

  @override
  _VoiceLoginScreenState createState() => _VoiceLoginScreenState();
}

class _VoiceLoginScreenState extends State<VoiceLoginScreen> {
  FlutterSoundRecorder? _recorder;
  bool _isRecording = false;
  String? _currentUsername;
  String _status = 'Готов к работе';
  bool _isWaitingResponse = false;

  @override
  void initState() {
    super.initState();
    _initRecorder();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startVoiceInterface();
    });
  }

  Future<void> _initRecorder() async {
    _recorder = FlutterSoundRecorder();
    await _recorder!.openRecorder();
  }

  Future<void> _startVoiceInterface() async {
    await _speakWithDelay("Добро пожаловать в голосовой помощник.");
    await _speakWithDelay("Для начала работы скажите: регистрация или вход");

    await _waitForCommand();
  }

  Future<void> _speakWithDelay(String text) async {
    setState(() => _status = text);
    await widget.audioService.speak(text);
    await Future.delayed(const Duration(seconds: 1));
  }

  Future<void> _waitForCommand() async {
    setState(() => _isWaitingResponse = true);

    await _speakWithDelay("Слушаю вашу команду...");

    String? command = await widget.audioService.listen();

    setState(() => _isWaitingResponse = false);

    if (command == null || command.isEmpty) {
      await _speakWithDelay("Я не расслышал команду. Пожалуйста, повторите.");
      return _waitForCommand();
    }

    command = command.toLowerCase();
    await _speakWithDelay("Вы сказали: $command");

    if (command.contains("регистрация") || command.contains("зарегистрироваться")) {
      await _handleRegistration();
    } else if (command.contains("вход") || command.contains("войти")) {
      await _handleLogin();
    } else if (command.contains("помощь") || command.contains("команды")) {
      await _showHelp();
    } else {
      await _speakWithDelay("Неизвестная команда. Доступные команды: регистрация, вход.");
      return _waitForCommand();
    }
  }

  Future<void> _showHelp() async {
    await _speakWithDelay("Доступные команды:");
    await _speakWithDelay("Регистрация - создать новый аккаунт");
    await _speakWithDelay("Вход - войти в существующий аккаунт");
    await _waitForCommand();
  }

  Future<String?> _recordVoiceSample() async {
    try {
      Directory tempDir = Directory.systemTemp;
      String path = '${tempDir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.aac';

      await _recorder!.startRecorder(
        toFile: path,
        codec: Codec.aacADTS,
      );

      setState(() {
        _isRecording = true;
        _status = 'Запись голоса... Говорите сейчас';
      });

      await widget.audioService.speak("Записываю ваш голос. Произнесите любую фразу после сигнала");
      await Future.delayed(const Duration(seconds: 1));
      await widget.audioService.speak("Говорите");

      await Future.delayed(const Duration(seconds: 4));

      await _recorder!.stopRecorder();
      setState(() {
        _isRecording = false;
        _status = 'Запись завершена';
      });

      if (await File(path).exists()) {
        await widget.audioService.speak("Запись сохранена");
        return path;
      } else {
        await widget.audioService.speak("Ошибка сохранения записи");
        return null;
      }
    } catch (e) {
      print("Recording error: $e");
      setState(() => _isRecording = false);
      await widget.audioService.speak("Ошибка записи голоса");
      return null;
    }
  }

  Future<void> _handleRegistration() async {
    await _speakWithDelay("Начинаем процесс регистрации.");

    String? username = await _getUsername("регистрации");
    if (username == null) return;

    _currentUsername = username;
    setState(() {});

    await _speakWithDelay("Вы сказали имя: $username. Верно? Скажите да или нет");

    String? confirmation = await widget.audioService.listen();
    if (confirmation == null || !confirmation.toLowerCase().contains("да")) {
      await _speakWithDelay("Попробуем еще раз.");
      return _handleRegistration();
    }

    await _speakWithDelay("Теперь запишем ваш голосовой пароль.");
    await _speakWithDelay("Произнесите любую фразу, которую будете использовать для входа.");

    String? voicePath = await _recordVoiceSample();
    if (voicePath == null) {
      await _speakWithDelay("Не удалось записать голос. Попробуйте снова.");
      return _handleRegistration();
    }

    await _speakWithDelay("Сохранить эту запись? Скажите да или нет");

    String? saveConfirm = await widget.audioService.listen();
    if (saveConfirm == null || !saveConfirm.toLowerCase().contains("да")) {
      await _speakWithDelay("Перезаписываем голосовой пароль.");
      return _handleRegistration();
    }

    await _speakWithDelay("Регистрирую ваш голосовой профиль...");

    var response = await widget.apiService.registerVoice(username, voicePath);

    try {
      if (await File(voicePath).exists()) {
        await File(voicePath).delete();
      }
    } catch (e) {
      print("Error deleting temp file: $e");
    }

    if (response.containsKey('error')) {
      await _speakWithDelay("Ошибка регистрации: ${response['error']}");
      await _speakWithDelay("Попробуйте еще раз.");
      return _startVoiceInterface();
    } else {
      await _speakWithDelay("Регистрация успешна! Добро пожаловать, $username!");
      await _speakWithDelay("Переход к камере...");

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => CameraTestScreen(
            audioService: widget.audioService,
            apiService: widget.apiService,
            username: username,
          ),
        ),
      );
    }
  }

  Future<void> _handleLogin() async {
    await _speakWithDelay("Начинаем процесс входа.");

    String? username = await _getUsername("входа");
    if (username == null) return;

    _currentUsername = username;
    setState(() {});

    await _speakWithDelay("Произнесите ваш голосовой пароль для проверки.");

    String? voicePath = await _recordVoiceSample();
    if (voicePath == null) {
      await _speakWithDelay("Не удалось записать голос. Попробуйте снова.");
      return _handleLogin();
    }

    await _speakWithDelay("Проверяю ваш голос...");

    var response = await widget.apiService.loginVoice(username, voicePath);

    try {
      if (await File(voicePath).exists()) {
        await File(voicePath).delete();
      }
    } catch (e) {
      print("Error deleting temp file: $e");
    }

    if (response.containsKey('error')) {
      await _speakWithDelay("Ошибка входа: ${response['error']}");
      await _speakWithDelay("Попробуйте еще раз.");
      return _startVoiceInterface();
    } else if (response['status'] == 'success') {
      double similarity = response['similarity'] ?? 0.0;
      await _speakWithDelay("Вход успешен! Сходство голоса: ${(similarity * 100).toStringAsFixed(0)} процентов");
      await _speakWithDelay("Добро пожаловать, $username!");
      await _speakWithDelay("Переход к камере...");

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => CameraTestScreen(
            audioService: widget.audioService,
            apiService: widget.apiService,
            username: username,
          ),
        ),
      );
    } else {
      await _speakWithDelay("Голос не распознан. Попробуйте еще раз.");
      return _startVoiceInterface();
    }
  }

  Future<String?> _getUsername(String process) async {
    await _speakWithDelay("Скажите ваше имя пользователя для $process");

    int attempts = 0;
    while (attempts < 3) {
      String? username = await widget.audioService.listen();

      if (username != null && username.isNotEmpty) {
        await _speakWithDelay("Вы сказали: $username");
        return username;
      } else {
        attempts++;
        if (attempts < 3) {
          await _speakWithDelay("Не расслышал имя. Пожалуйста, повторите.");
        }
      }
    }

    await _speakWithDelay("Не удалось распознать имя. Возврат в главное меню.");
    await _startVoiceInterface();
    return null;
  }

  @override
  void dispose() {
    _recorder?.closeRecorder();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              color: Colors.blue[900],
              child: Row(
                children: [
                  Icon(
                    _isRecording ? Icons.mic : Icons.record_voice_over,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _status,
                      style: const TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      width: _isRecording ? 120 : 100,
                      height: _isRecording ? 120 : 100,
                      decoration: BoxDecoration(
                        color: _isRecording ? Colors.red : Colors.blue,
                        shape: BoxShape.circle,
                        boxShadow: [
                          if (_isRecording)
                            BoxShadow(
                              color: Colors.red.withOpacity(0.5),
                              blurRadius: 20,
                              spreadRadius: 5,
                            ),
                        ],
                      ),
                      child: Icon(
                        _isRecording ? Icons.mic : Icons.voice_over_off,
                        size: 50,
                        color: Colors.white,
                      ),
                    ),

                    const SizedBox(height: 30),

                    if (_currentUsername != null)
                      Text(
                        'Пользователь: $_currentUsername',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),

                    const SizedBox(height: 20),

                    if (_isWaitingResponse)
                      Column(
                        children: [
                          const CircularProgressIndicator(color: Colors.white),
                          const SizedBox(height: 10),
                          Text(
                            'Слушаю...',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.8),
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),

                    const SizedBox(height: 40),

                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 20),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text(
                        'Используйте голосовые команды:\n"регистрация", "вход"',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
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
    );
  }
}
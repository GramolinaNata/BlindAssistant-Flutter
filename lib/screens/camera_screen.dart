import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:blindddd/services/audio_service.dart';
import 'package:blindddd/services/api_service.dart';
import 'package:blindddd/screens/notes_screen.dart';
import 'package:blindddd/screens/deaf_screen.dart';
import 'package:http/http.dart' as http;

class CameraTestScreen extends StatefulWidget {
  final SimpleAudioService audioService;
  final ApiService apiService;
  final String? username;

  const CameraTestScreen({
    super.key,
    required this.audioService,
    required this.apiService,
    this.username,
  });

  @override
  _CameraTestScreenState createState() => _CameraTestScreenState();
}

class _CameraTestScreenState extends State<CameraTestScreen> {
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  bool _isCameraReady = false;
  bool _isProcessing = false;
  bool _isListening = false;
  String _statusMessage = 'Инициализация...';
  Uint8List? _annotatedFrame;

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    await widget.audioService.initialize();

    String welcomeMessage = widget.username != null
        ? "Добро пожаловать, ${widget.username}! "
        "Перед тобой экран с тремя кнопками: "
        "слева - сканирование окружения, "
        "в центре - чтение текста или номеров, "
        "справа - голосовые команды."
        : "Добро пожаловать в помощник для слабовидящих";

    widget.audioService.speak(welcomeMessage);

    await _testServerConnection();
    await _initializeCamera();
  }

  Future<void> _testServerConnection() async {
    setState(() => _statusMessage = 'Проверка сервера...');
    var result = await widget.apiService.testConnection();

    if (result.containsKey('error')) {
      setState(() => _statusMessage = 'Ошибка сервера');
      widget.audioService.speak("Ошибка подключения к серверу");
    } else {
      setState(() => _statusMessage = 'Сервер подключен');
      widget.audioService.speak("Сервер готов");
    }
  }

  Future<void> _initializeCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras == null || _cameras!.isEmpty) {
        setState(() => _statusMessage = 'Камеры не найдены');
        widget.audioService.speak("Камеры не найдены");
        return;
      }

      _cameraController = CameraController(
        _cameras!.first,
        ResolutionPreset.high,
        enableAudio: false,
      );

      await _cameraController!.initialize();

      if (mounted) {
        setState(() {
          _isCameraReady = true;
          _statusMessage = 'Камера готова';
        });
      }
    } catch (e) {
      setState(() => _statusMessage = 'Ошибка камеры: $e');
      widget.audioService.speak("Ошибка настройки камеры");
    }
  }

  Future<void> _captureAndProcessFrame() async {
    if (!_isCameraReady || _cameraController == null || !_cameraController!.value.isInitialized) {
      widget.audioService.speak("Камера не готова");
      return;
    }

    if (_isProcessing) {
      widget.audioService.speak("Подождите, идет обработка");
      return;
    }

    setState(() {
      _isProcessing = true;
      _statusMessage = 'Анализирую...';
    });

    try {
      widget.audioService.speak("Сканирую");

      XFile image = await _cameraController!.takePicture();
      List<int> imageBytes = await image.readAsBytes();

      var result = await widget.apiService.processCameraFrame(imageBytes);

      if (result.containsKey('description')) {
        String description = result['description'];

        if (result.containsKey('annotated_frame')) {
          String base64Image = result['annotated_frame'];
          setState(() {
            _annotatedFrame = base64Decode(base64Image);
          });
        }

        widget.audioService.speak(description);
        setState(() => _statusMessage = description);
      } else {
        String error = result['error'] ?? 'Неизвестная ошибка';
        widget.audioService.speak("Ошибка: $error");
        setState(() => _statusMessage = 'Ошибка: $error');
      }

      await File(image.path).delete();
    } catch (e) {
      print("Ошибка: $e");
      widget.audioService.speak("Ошибка обработки");
      setState(() => _statusMessage = 'Ошибка: $e');
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  Future<void> _listenForVoiceCommand() async {
    if (_isListening || _isProcessing) {
      widget.audioService.speak("Подождите");
      return;
    }

    setState(() {
      _isListening = true;
      _statusMessage = 'Слушаю команду...';
    });

    widget.audioService.speak("Слушаю");
    await Future.delayed(const Duration(milliseconds: 1500));

    try {
      // ИСПОЛЬЗУЕМ НОВЫЙ МЕТОД С GPT
      Map<String, dynamic>? result = await widget.audioService.listenWithGpt(timeoutSeconds: 8);

      print("=== РЕЗУЛЬТАТ РАСПОЗНАВАНИЯ ===");
      print("Результат: $result");

      if (result != null && result['success'] == true) {
        String rawText = result['raw_text'] ?? '';
        String correctedText = result['corrected_text'] ?? '';
        String? command = result['command'];
        double confidence = result['confidence'] ?? 0.0;
        bool improvedByGpt = result['improved_by_gpt'] ?? false;

        print("Сырой текст: '$rawText'");
        print("Исправленный: '$correctedText'");
        print("Команда: $command");
        print("Уверенность: ${(confidence * 100).toInt()}%");
        print("Улучшено GPT: $improvedByGpt");

        // Сообщаем пользователю если GPT улучшил
        if (improvedByGpt && rawText != correctedText) {
          await widget.audioService.speak("Я понял: $correctedText");
          await Future.delayed(const Duration(milliseconds: 800));
        }

        if (command != null) {
          await _executeCommand(command, correctedText, confidence);
        } else {
          widget.audioService.speak(
              "Команда не распознана. Вы сказали: $correctedText. "
                  "Доступные команды: время, сканировать, заметка, выйти"
          );
          setState(() => _statusMessage = 'Не распознано: $correctedText');
        }
      } else {
        String error = result?['error'] ?? 'Неизвестная ошибка';
        widget.audioService.speak("Не удалось распознать команду. Попробуйте еще раз");
        setState(() => _statusMessage = 'Ошибка: $error');
      }
    } catch (e) {
      print("ОШИБКА голосовой команды: $e");
      widget.audioService.speak("Произошла ошибка распознавания");
      setState(() => _statusMessage = 'Ошибка: $e');
    } finally {
      setState(() => _isListening = false);
    }
  }

  Future<void> _executeCommand(String command, String text, double confidence) async {
    print("Выполнение команды: $command");

    switch (command) {
      case 'время':
        var timeResult = await widget.apiService.getCurrentTime();
        if (timeResult.containsKey('time')) {
          String timeText = timeResult['time'];
          widget.audioService.speak(timeText);
          setState(() => _statusMessage = timeText);
        } else {
          widget.audioService.speak("Не удалось получить время");
          setState(() => _statusMessage = 'Ошибка получения времени');
        }
        break;

      case 'сканировать':
        widget.audioService.speak("Начинаю сканирование окружения");
        await Future.delayed(const Duration(milliseconds: 800));
        await _captureAndProcessFrame();
        break;

      case 'заметка':
        widget.audioService.speak("Переход к заметкам");
        await Future.delayed(const Duration(milliseconds: 800));

        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => NotesScreen(
              audioService: widget.audioService,
              apiService: widget.apiService,
              username: widget.username!,
            ),
          ),
        );
        break;

      case 'выйти':
        widget.audioService.speak("Выхожу из приложения");
        await Future.delayed(const Duration(milliseconds: 1500));
        Navigator.pop(context);
        break;

      default:
        widget.audioService.speak("Неизвестная команда: $text");
    }
  }

  // ================== OCR - ЧТЕНИЕ ТЕКСТА ==================

  Future<void> _readTextOrNumber() async {
    if (!_isCameraReady || _cameraController == null || !_cameraController!.value.isInitialized) {
      widget.audioService.speak("Камера не готова");
      return;
    }

    if (_isProcessing) {
      widget.audioService.speak("Подождите");
      return;
    }

    setState(() {
      _isProcessing = true;
      _statusMessage = 'Читаю текст...';
    });

    try {
      widget.audioService.speak("Делаю фото");

      XFile image = await _cameraController!.takePicture();
      List<int> imageBytes = await image.readAsBytes();
      String base64Image = base64Encode(imageBytes);

      widget.audioService.speak("Анализирую");

      // Отправляем в GPT Vision
      String extractedText = await _extractTextWithGPT(base64Image);

      if (extractedText.isNotEmpty && extractedText != 'Текст не найден') {
        widget.audioService.speak("Прочитанный текст: $extractedText");
        setState(() => _statusMessage = extractedText);
      } else {
        widget.audioService.speak("Текст не найден");
        setState(() => _statusMessage = 'Текст не найден');
      }

      await File(image.path).delete();
    } catch (e) {
      print('Ошибка OCR: $e');
      widget.audioService.speak("Ошибка чтения текста");
      setState(() => _statusMessage = 'Ошибка: $e');
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  Future<String> _extractTextWithGPT(String base64Image) async {
    try {
      final apiKey = widget.audioService.gptService.apiKey;
      if (apiKey == null || apiKey.isEmpty) {
        return 'Сервис недоступен';
      }

      final response = await http.post(
        Uri.parse('https://api.openai.com/v1/chat/completions'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode({
          'model': 'gpt-4o-mini',
          'messages': [
            {
              'role': 'user',
              'content': [
                {
                  'type': 'text',
                  'text': 'Прочитай весь текст и все номера телефонов на этом изображении. '
                      'Верни ТОЛЬКО текст и номера, которые видишь, без комментариев. '
                      'Если есть номер телефона - обязательно скажи его. '
                      'Если текста нет, скажи "Текст не найден".'
                },
                {
                  'type': 'image_url',
                  'image_url': {
                    'url': 'data:image/jpeg;base64,$base64Image'
                  }
                }
              ]
            }
          ],
          'max_tokens': 500,
        }),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        String text = data['choices'][0]['message']['content'];
        print('✅ OCR результат: $text');
        return text;
      } else {
        return 'Ошибка сервиса';
      }
    } catch (e) {
      print('❌ OCR error: $e');
      return 'Ошибка: $e';
    }
  }

  Future<void> _showGptStats() async {
    final stats = widget.audioService.getGptStats();

    final message = '''
GPT Статистика:
Всего запросов: ${stats['total_requests']}
Из кэша: ${stats['cache_hits']}
Через GPT: ${stats['gpt_calls']}
Попадания в кэш: ${stats['cache_hit_rate']}%

Потрачено: \$${stats['total_cost']}
Сэкономлено: \$${stats['money_saved']}
    ''';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('📊 GPT Статистика'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () async {
              await widget.audioService.resetGptStats();
              Navigator.pop(context);
              widget.audioService.speak("Статистика сброшена");
            },
            child: const Text('Сбросить'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteImageFile(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      print("Ошибка удаления файла: $e");
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(
          widget.username != null
              ? '👁️ ${widget.username}'
              : '👁️ Помощник для слабовидящих',
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        actions: [
          // Кнопка режима для глухонемых
          IconButton(
            icon: const Icon(Icons.chat_bubble_outline, color: Colors.white),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => DeafScreen(
                    gptService: widget.audioService.gptService,
                    apiService: widget.apiService,
                    username: widget.username,
                  ),
                ),
              );
            },
            tooltip: 'Текстовый режим',
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            flex: 4,
            child: Container(
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.blue.withOpacity(0.2),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Stack(
                  children: [
                    _annotatedFrame != null
                        ? Image.memory(
                      _annotatedFrame!,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: double.infinity,
                    )
                        : (_isCameraReady && _cameraController != null
                        ? CameraPreview(_cameraController!)
                        : Container(
                      color: Colors.grey[900],
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (!_isCameraReady)
                              const CircularProgressIndicator(
                                color: Colors.blue,
                                strokeWidth: 3,
                              ),
                            const SizedBox(height: 16),
                            Text(
                              _isCameraReady ? 'Камера готова' : 'Загрузка камеры...',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )),

                    if (_isProcessing)
                      Container(
                        color: Colors.black54,
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircularProgressIndicator(
                                  color: Colors.blue,
                                  strokeWidth: 4,
                                ),
                                SizedBox(height: 12),
                                Text(
                                  'Анализирую...',
                                  style: TextStyle(
                                    color: Colors.black87,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                    if (_isListening)
                      Positioned(
                        top: 16,
                        left: 16,
                        right: 16,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                          decoration: BoxDecoration(
                            color: Colors.green,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.green.withOpacity(0.4),
                                blurRadius: 10,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.mic, color: Colors.white, size: 24),
                              SizedBox(width: 12),
                              Text(
                                'Слушаю команду...',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),

          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[900],
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              _statusMessage,
              style: TextStyle(
                fontSize: 14,
                color: _statusMessage.contains('Ошибка')
                    ? Colors.red[400]
                    : Colors.green[400],
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),

          const SizedBox(height: 16),

          Expanded(
            flex: 2,
            child: Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      // Кнопка сканирования
                      Expanded(
                        child: Semantics(
                          label: "Кнопка сканирования окружения",
                          child: Container(
                            height: 70,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.blue.withOpacity(0.3),
                                  blurRadius: 10,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                            child: ElevatedButton(
                              onPressed: _isProcessing || _isListening ? null : _captureAndProcessFrame,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                elevation: 0,
                              ),
                              child: const Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.camera_alt, size: 28),
                                  SizedBox(height: 4),
                                  Text(
                                    'Сканировать',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(width: 8),

                      // Кнопка чтения текста (OCR)
                      Expanded(
                        child: Semantics(
                          label: "Кнопка чтения текста и номеров",
                          child: Container(
                            height: 70,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.orange.withOpacity(0.3),
                                  blurRadius: 10,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                            child: ElevatedButton(
                              onPressed: _isProcessing || _isListening ? null : _readTextOrNumber,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.orange,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                elevation: 0,
                              ),
                              child: const Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.text_fields, size: 28),
                                  SizedBox(height: 4),
                                  Text(
                                    'Прочитать',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(width: 8),

                      // Кнопка голосовых команд
                      Expanded(
                        child: Semantics(
                          label: "Кнопка голосовых команд",
                          child: Container(
                            height: 70,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.green.withOpacity(0.3),
                                  blurRadius: 10,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                            child: ElevatedButton(
                              onPressed: _isProcessing || _isListening ? null : _listenForVoiceCommand,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                elevation: 0,
                              ),
                              child: const Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.mic, size: 28),
                                  SizedBox(height: 4),
                                  Text(
                                    'Голос',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey[800],
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '💬 Голосовые команды:',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.white70,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          '• "Сканировать" - анализ окружения\n'
                              '• "Прочитать" - чтение текста/номеров\n'
                              '• "Время" - текущее время\n'
                              '• "Заметка" - перейти к заметкам\n'
                              '• "Выйти" - выход',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white60,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
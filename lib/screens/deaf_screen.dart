import 'package:flutter/material.dart';
import 'dart:async';
import 'package:blindddd/services/gpt_service.dart';
import 'package:blindddd/services/api_service.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

class DeafScreen extends StatefulWidget {
  final GptService gptService;
  final ApiService apiService;
  final String? username;

  const DeafScreen({
    super.key,
    required this.gptService,
    required this.apiService,
    this.username,
  });

  @override
  _DeafScreenState createState() => _DeafScreenState();
}

class _DeafScreenState extends State<DeafScreen> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final stt.SpeechToText _speech = stt.SpeechToText();

  bool _isProcessing = false;
  List<Map<String, dynamic>> _conversation = [];

  // Субтитры
  bool _subtitlesEnabled = false;
  bool _isListeningForSubtitles = false;
  String _currentSubtitle = '';

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    await _initializeSpeechRecognition();
    _addSystemMessage('👋 Привет! Я ваш текстовый помощник.');
    _addSystemMessage('💬 Пишите команды или вопросы:\n• время\n• заметки\n• субтитры\n• помощь');
  }

  Future<void> _initializeSpeechRecognition() async {
    try {
      await _speech.initialize();
    } catch (e) {
      print('⚠️ Speech недоступен: $e');
    }
  }

  void _addSystemMessage(String text) {
    setState(() {
      _conversation.add({'type': 'system', 'text': text, 'time': DateTime.now()});
    });
    _scrollToBottom();
  }

  void _addUserMessage(String text) {
    setState(() {
      _conversation.add({'type': 'user', 'text': text, 'time': DateTime.now()});
    });
    _scrollToBottom();
  }

  void _addAssistantMessage(String text) {
    setState(() {
      _conversation.add({'type': 'assistant', 'text': text, 'time': DateTime.now()});
    });
    _scrollToBottom();
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ================== СУБТИТРЫ ==================

  void _toggleSubtitles() {
    setState(() => _subtitlesEnabled = !_subtitlesEnabled);

    if (_subtitlesEnabled) {
      _addSystemMessage('📺 Субтитры включены!');
      _startSubtitles();
    } else {
      _addSystemMessage('📺 Субтитры выключены');
      _stopSubtitles();
    }
  }

  void _startSubtitles() async {
    if (!await _speech.initialize()) {
      _addSystemMessage('⚠️ Микрофон недоступен');
      setState(() => _subtitlesEnabled = false);
      return;
    }
    _listenForSubtitles();
  }

  void _listenForSubtitles() {
    if (!_subtitlesEnabled) return;

    setState(() => _isListeningForSubtitles = true);

    _speech.listen(
      localeId: 'ru_RU',
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 3),
      onResult: (result) {
        setState(() => _currentSubtitle = result.recognizedWords);

        if (result.finalResult && _subtitlesEnabled) {
          Future.delayed(const Duration(milliseconds: 500), () {
            if (_subtitlesEnabled) _listenForSubtitles();
          });
        }
      },
    );
  }

  void _stopSubtitles() {
    _speech.stop();
    setState(() {
      _isListeningForSubtitles = false;
      _currentSubtitle = '';
    });
  }

  // ================== ОБРАБОТКА КОМАНД ==================

  Future<void> _processUserInput(String text) async {
    if (text.trim().isEmpty) return;

    _addUserMessage(text);
    _textController.clear();

    setState(() => _isProcessing = true);

    try {
      final gptResult = await widget.gptService.improveRecognition(text);

      if (gptResult['success'] == true) {
        final command = gptResult['command'];
        final correctedText = gptResult['corrected_text'];

        if (command != null) {
          await _executeCommand(command, correctedText);
        } else {
          String lowerText = correctedText.toLowerCase();

          if (lowerText.contains('субтитр')) {
            _toggleSubtitles();
          } else {
            await _chatWithGPT(correctedText);
          }
        }
      } else {
        _addAssistantMessage('Не понял. Попробуйте: "время", "субтитры", "помощь"');
      }
    } catch (e) {
      _addAssistantMessage('Ошибка обработки');
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  Future<void> _executeCommand(String command, String text) async {
    switch (command) {
      case 'время':
        await _getTime();
        break;

      case 'выйти':
        _addAssistantMessage('До свидания! 👋');
        await Future.delayed(const Duration(milliseconds: 1000));
        Navigator.pop(context);
        break;

      default:
        await _chatWithGPT(text);
    }
  }

  Future<void> _getTime() async {
    try {
      var result = await widget.apiService.getCurrentTime();
      if (result.containsKey('time')) {
        _addAssistantMessage('🕐 ${result['time']}');
      } else {
        _addAssistantMessage('❌ Ошибка');
      }
    } catch (e) {
      _addAssistantMessage('❌ Ошибка');
    }
  }

  Future<void> _chatWithGPT(String text) async {
    if (text.contains('помощь') || text.contains('что ты умеешь')) {
      _addAssistantMessage(
          '🤖 Я текстовый помощник!\n\n'
              '🕐 "время" - текущее время\n'
              '📺 "субтитры" - живые субтитры\n'
              '💬 Пишите любые вопросы!'
      );
    } else {
      _addAssistantMessage('💬 Понял: "$text"\n\nДоступны: время, субтитры, помощь');
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _speech.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('🤟 Текстовый режим', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white)),
        backgroundColor: Colors.purple[900],
        elevation: 0,
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(_subtitlesEnabled ? Icons.subtitles : Icons.subtitles_outlined, color: _subtitlesEnabled ? Colors.yellow : Colors.white),
            onPressed: _toggleSubtitles,
            tooltip: 'Субтитры',
          ),
        ],
      ),
      body: Column(
        children: [
          // Субтитры (без камеры)
          if (_subtitlesEnabled)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              margin: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.purple[800],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.yellow, width: 2),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.mic, color: _isListeningForSubtitles ? Colors.red : Colors.white),
                      const SizedBox(width: 8),
                      Text(
                        _isListeningForSubtitles ? 'СЛУШАЮ' : 'СУБТИТРЫ',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _currentSubtitle.isEmpty ? 'Говорите что-то...' : _currentSubtitle,
                    style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),

          // Чат
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.grey[900],
                borderRadius: const BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20)),
              ),
              child: _conversation.isEmpty
                  ? const Center(child: Text('Напишите сообщение...', style: TextStyle(color: Colors.white60, fontSize: 16)))
                  : ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.all(16),
                itemCount: _conversation.length,
                itemBuilder: (context, index) {
                  final msg = _conversation[index];
                  final isUser = msg['type'] == 'user';
                  final isSystem = msg['type'] == 'system';

                  return Align(
                    alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: isUser ? Colors.blue[700] : isSystem ? Colors.purple[800] : Colors.grey[800],
                        borderRadius: BorderRadius.circular(16),
                      ),
                      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                      child: Text(msg['text'], style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.4)),
                    ),
                  );
                },
              ),
            ),
          ),

          // Ввод
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[850],
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, -2))],
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _textController,
                    enabled: !_isProcessing,
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                    decoration: InputDecoration(
                      hintText: 'Напишите команду...',
                      hintStyle: TextStyle(color: Colors.grey[600]),
                      filled: true,
                      fillColor: Colors.grey[800],
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(25), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    ),
                    onSubmitted: (text) => _processUserInput(text),
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  decoration: const BoxDecoration(color: Colors.purple, shape: BoxShape.circle),
                  child: IconButton(
                    icon: _isProcessing
                        ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Icon(Icons.send, color: Colors.white),
                    onPressed: _isProcessing ? null : () => _processUserInput(_textController.text),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
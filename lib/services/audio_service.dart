import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'gpt_service.dart';

class SimpleAudioService {
  final FlutterTts _tts = FlutterTts();
  final stt.SpeechToText _speech = stt.SpeechToText();
  final GptService gptService = GptService(); // ПУБЛИЧНЫЙ доступ
  bool _isListening = false;

  Future<void> initialize() async {
    await _tts.setLanguage('ru-RU');
    await _tts.setSpeechRate(0.5);
    await _tts.setPitch(1.0);
    await _tts.setVolume(1.0);

    // Инициализируем GPT
    await gptService.initialize();
  }

  Future<void> speak(String text) async {
    await _tts.awaitSpeakCompletion(true);
    await _tts.speak(text);
  }

  /// УЛУЧШЕННЫЙ МЕТОД - Слушает ДОЛЬШЕ и использует ТОЛЬКО GPT результат
  Future<Map<String, dynamic>?> listenWithGpt({int timeoutSeconds = 30}) async {
    if (_isListening) return null;

    bool available = await _speech.initialize(
      onStatus: (status) {
        _isListening = status == 'listening';
        print('🎤 Статус: $status');
      },
      onError: (error) {
        _isListening = false;
        print('❌ Ошибка: $error');
      },
    );

    if (!available) {
      print('❌ Распознавание речи недоступно');
      return {
        'success': false,
        'error': 'speech_not_available',
      };
    }

    String? recognizedText;
    String? lastRecognizedText;
    bool isCompleted = false;
    int unchangedCount = 0;

    await _speech.listen(
      localeId: 'ru_RU',
      listenMode: stt.ListenMode.confirmation, // Ждём подтверждения
      pauseFor: const Duration(seconds: 5), // Ждём 5 секунд паузы
      onResult: (result) {
        recognizedText = result.recognizedWords;

        // Проверяем изменился ли текст
        if (recognizedText == lastRecognizedText) {
          unchangedCount++;
        } else {
          unchangedCount = 0;
          lastRecognizedText = recognizedText;
        }

        print('🎯 Распознано: "$recognizedText" (final: ${result.finalResult})');

        // Останавливаем только если:
        // 1. Текст не меняется уже 6 секунд (12 проверок по 500мс)
        // 2. И результат финальный
        if (unchangedCount >= 12 && result.finalResult && recognizedText != null && recognizedText!.isNotEmpty) {
          if (!isCompleted && _isListening) {
            _speech.stop();
            isCompleted = true;
            print('✅ Автостоп - текст стабилизировался');
          }
        }
      },
    );

    print('⏳ Ожидание речи (макс: ${timeoutSeconds}с)');

    int waited = 0;
    int maxWait = timeoutSeconds * 2; // 2 проверки в секунду

    while (_isListening && waited < maxWait) {
      await Future.delayed(const Duration(milliseconds: 500));
      waited++;

      // Увеличенное время ожидания - минимум 8 секунд
      if (recognizedText != null && recognizedText!.isNotEmpty && waited > 16) {
        // Проверяем что текст не меняется
        if (unchangedCount >= 10) {
          print('✅ Получен стабильный текст, остановка');
          break;
        }
      }

      if (waited >= maxWait) {
        print('⏰ Принудительная остановка по таймауту');
        break;
      }
    }

    if (_isListening) {
      await _speech.stop();
    }

    _isListening = false;

    // Берём последний распознанный текст
    final finalText = recognizedText ?? lastRecognizedText;
    print('📝 Итоговый результат Speech-to-Text: "$finalText"');

    // Если ничего не распознано
    if (finalText == null || finalText.isEmpty) {
      print('❌ Речь не обнаружена');
      return {
        'success': false,
        'error': 'no_speech',
        'message': 'Речь не распознана'
      };
    }

    // ВСЕГДА отправляем в GPT для улучшения
    print('🤖 Отправка для улучшения...');
    final improvedResult = await gptService.improveRecognition(finalText);

    if (improvedResult['success'] == true) {
      // ИСПОЛЬЗУЕМ ТОЛЬКО ИСПРАВЛЕННЫЙ ТЕКСТ ОТ GPT
      final correctedText = improvedResult['corrected_text'];
      final command = improvedResult['command'];

      print('✅ результат:');
      print('   Сырой: "$finalText"');
      print('   Исправлен: "$correctedText"');
      print('   Команда: $command');

      return {
        'success': true,
        'raw_text': finalText,
        'corrected_text': correctedText, // ЭТО ГЛАВНОЕ - используем везде!
        'command': command,
        'confidence': improvedResult['confidence'],
        'improved_by_gpt': improvedResult['improved_by_gpt'] ?? false,
        'source': improvedResult['source'],
      };
    } else {
      // Если GPT не сработал - возвращаем оригинал
      print('⚠️ не сработал, используем оригинал');
      return {
        'success': true,
        'raw_text': finalText,
        'corrected_text': finalText,
        'command': null,
        'confidence': 0.3,
        'improved_by_gpt': false,
        'error': improvedResult['error'],
      };
    }
  }

  /// СТАРЫЙ МЕТОД - теперь всегда возвращает исправленный GPT текст
  Future<String?> listen({int timeoutSeconds = 30}) async {
    final result = await listenWithGpt(timeoutSeconds: timeoutSeconds);
    // Возвращаем ИСПРАВЛЕННЫЙ текст, а не сырой!
    return result?['corrected_text'];
  }

  /// Получить статистику GPT
  Map<String, dynamic> getGptStats() {
    return gptService.getStats();
  }

  /// Проверка доступности GPT
  bool isGptAvailable() {
    return gptService.isAvailable;
  }

  /// Сбросить статистику
  Future<void> resetGptStats() async {
    await gptService.resetStats();
  }

  void stopListening() {
    if (_isListening) {
      _speech.stop();
      _isListening = false;
      print('🛑 Ручная остановка');
    }
  }
}
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';

class GptService {
  String? _apiKey;
  bool _isAvailable = false;

  // Публичный геттер для API ключа (для OCR)
  String? get apiKey => _apiKey;

  // Статистика
  int _totalRequests = 0;
  int _cacheHits = 0;
  int _gptCalls = 0;
  double _totalCost = 0.0;

  // Кэш команд
  final Map<String, Map<String, dynamic>> _commandCache = {
    'сканировать': {'command': 'сканировать', 'confidence': 1.0},
    'скан': {'command': 'сканировать', 'confidence': 0.95},
    'сканируй': {'command': 'сканировать', 'confidence': 1.0},
    'что вижу': {'command': 'сканировать', 'confidence': 0.9},
    'что впереди': {'command': 'сканировать', 'confidence': 0.9},
    'скана': {'command': 'сканировать', 'confidence': 0.85},
    'сканой': {'command': 'сканировать', 'confidence': 0.85},

    'время': {'command': 'время', 'confidence': 1.0},
    'который час': {'command': 'время', 'confidence': 1.0},
    'сколько времени': {'command': 'время', 'confidence': 1.0},
    'времени': {'command': 'время', 'confidence': 0.9},
    'час': {'command': 'время', 'confidence': 0.85},

    'заметка': {'command': 'заметка', 'confidence': 1.0},
    'заметки': {'command': 'заметка', 'confidence': 1.0},
    'записать': {'command': 'заметка', 'confidence': 0.9},
    'напоминание': {'command': 'заметка', 'confidence': 0.9},
    'запиши': {'command': 'заметка', 'confidence': 0.9},
    'заметку': {'command': 'заметка', 'confidence': 0.95},

    'выйти': {'command': 'выйти', 'confidence': 1.0},
    'выход': {'command': 'выйти', 'confidence': 1.0},
    'закрыть': {'command': 'выйти', 'confidence': 0.9},
    'выйди': {'command': 'выйти', 'confidence': 0.95},
  };

  Future<void> initialize() async {
    try {
      await dotenv.load(fileName: ".env");
      _apiKey = dotenv.env['OPENAI_API_KEY'];

      if (_apiKey != null && _apiKey!.isNotEmpty && _apiKey != 'your-key-here') {
        _isAvailable = true;
        print('✅ GPT-4 Mini доступен');
      } else {
        _isAvailable = false;
        print('⚠️ GPT-4 Mini недоступен (работает локальный режим)');
      }

      await _loadStats();
    } catch (e) {
      print('⚠️ Не удалось загрузить .env файл: $e');
      _isAvailable = false;
    }
  }

  bool get isAvailable => _isAvailable;

  /// Главный метод - улучшение распознавания
  Future<Map<String, dynamic>> improveRecognition(String recognizedText) async {
    _totalRequests++;
    await _saveStats();

    // 1. Проверяем точный кэш
    final cached = _checkExactCache(recognizedText);
    if (cached != null) {
      _cacheHits++;
      await _saveStats();
      print('💰 Точное совпадение в кэше! Экономия: \$0.0001');

      return {
        'success': true,
        'command': cached['command'],
        'corrected_text': recognizedText,
        'confidence': cached['confidence'],
        'source': 'cache',
        'improved_by_gpt': false,
      };
    }

    // 2. Локальная эвристика (быстро и бесплатно)
    final localResult = _localRecognition(recognizedText);
    if (localResult != null && localResult['confidence'] >= 0.75) {
      print('💰 Локальное распознавание! Экономия: \$0.0001');

      return {
        'success': true,
        'command': localResult['command'],
        'corrected_text': recognizedText,
        'confidence': localResult['confidence'],
        'source': 'local',
        'improved_by_gpt': false,
      };
    }

    // 3. Только если неуверены - используем GPT
    if (_isAvailable) {
      return await _callGPT(recognizedText);
    } else {
      // Если GPT недоступен - возвращаем лучшее локальное совпадение
      if (localResult != null) {
        return {
          'success': true,
          'command': localResult['command'],
          'corrected_text': recognizedText,
          'confidence': localResult['confidence'],
          'source': 'local_fallback',
          'improved_by_gpt': false,
          'note': 'GPT недоступен, использовано локальное распознавание'
        };
      }

      return {
        'success': false,
        'error': 'GPT недоступен и локальное распознавание не сработало',
        'raw_text': recognizedText,
      };
    }
  }

  /// Проверка точного совпадения в кэше
  Map<String, dynamic>? _checkExactCache(String text) {
    final normalized = text.toLowerCase().trim();

    // Точное совпадение
    if (_commandCache.containsKey(normalized)) {
      return _commandCache[normalized];
    }

    // Частичное совпадение
    for (var entry in _commandCache.entries) {
      if (normalized.contains(entry.key) || entry.key.contains(normalized)) {
        return entry.value;
      }
    }

    return null;
  }

  /// Локальное распознавание по ключевым словам
  Map<String, dynamic>? _localRecognition(String text) {
    final lower = text.toLowerCase().trim();

    // Ключевые слова
    final scanKeywords = ['скан', 'смотр', 'вижу', 'впереди', 'анализ', 'камер'];
    final timeKeywords = ['час', 'время', 'времени'];
    final noteKeywords = ['замет', 'запис', 'напомин'];
    final exitKeywords = ['выйт', 'выход', 'закр', 'стоп'];

    // Проверяем каждую категорию
    if (scanKeywords.any((k) => lower.contains(k))) {
      return {'command': 'сканировать', 'confidence': 0.80};
    }

    if (timeKeywords.any((k) => lower.contains(k))) {
      return {'command': 'время', 'confidence': 0.85};
    }

    if (noteKeywords.any((k) => lower.contains(k))) {
      return {'command': 'заметка', 'confidence': 0.80};
    }

    if (exitKeywords.any((k) => lower.contains(k))) {
      return {'command': 'выйти', 'confidence': 0.85};
    }

    return null;
  }

  /// Вызов GPT API
  Future<Map<String, dynamic>> _callGPT(String text) async {
    _gptCalls++;
    print('💸 GPT запрос #$_gptCalls');

    try {
      final response = await http.post(
        Uri.parse('https://api.openai.com/v1/chat/completions'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_apiKey',
        },
        body: jsonEncode({
          'model': 'gpt-4o-mini',
          'messages': [
            {
              'role': 'system',
              'content': '''Ты помощник для слепых людей в Казахстане. Определи команду из распознанной речи.

Команды: сканировать, время, заметка, выйти

Верни ТОЛЬКО JSON:
{"command": "команда или null", "corrected_text": "исправленный текст", "confidence": 0-1}

Примеры:
"скан руй" → {"command": "сканировать", "corrected_text": "сканируй", "confidence": 0.9}
"капой час" → {"command": "время", "corrected_text": "который час", "confidence": 0.85}
"запищать" → {"command": "заметка", "corrected_text": "записать", "confidence": 0.9}'''
            },
            {'role': 'user', 'content': text}
          ],
          'temperature': 0.3,
          'max_tokens': 100,
          'response_format': {'type': 'json_object'}
        }),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final content = data['choices'][0]['message']['content'];
        final result = jsonDecode(content);

        // Подсчет стоимости
        final usage = data['usage'];
        final inputTokens = usage['prompt_tokens'];
        final outputTokens = usage['completion_tokens'];
        final cost = (inputTokens * 0.150 + outputTokens * 0.600) / 1000000;

        _totalCost += cost;
        await _saveStats();

        print('💰 Стоимость: \$${cost.toStringAsFixed(6)}');

        // Добавляем в кэш если уверенность высокая
        if (result['confidence'] >= 0.8 && result['command'] != null) {
          _commandCache[text.toLowerCase().trim()] = {
            'command': result['command'],
            'confidence': result['confidence'],
          };
        }

        return {
          'success': true,
          'command': result['command'],
          'corrected_text': result['corrected_text'],
          'confidence': result['confidence'] ?? 0.0,
          'source': 'gpt',
          'improved_by_gpt': true,
          'cost': cost,
        };
      } else {
        print('❌ GPT API error: ${response.statusCode}');
        return {
          'success': false,
          'error': 'GPT недоступен',
          'status_code': response.statusCode,
        };
      }
    } catch (e) {
      print('❌ GPT ошибка: $e');
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  /// Получить статистику
  Map<String, dynamic> getStats() {
    final cacheHitRate = _totalRequests > 0
        ? (_cacheHits / _totalRequests * 100)
        : 0.0;

    final moneySaved = _cacheHits * 0.0001;

    return {
      'total_requests': _totalRequests,
      'cache_hits': _cacheHits,
      'gpt_calls': _gptCalls,
      'cache_hit_rate': cacheHitRate.toStringAsFixed(1),
      'total_cost': _totalCost.toStringAsFixed(4),
      'money_saved': moneySaved.toStringAsFixed(4),
      'avg_cost_per_request': _totalRequests > 0
          ? (_totalCost / _totalRequests).toStringAsFixed(6)
          : '0.000000',
    };
  }

  /// Сохранить статистику
  Future<void> _saveStats() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('gpt_total_requests', _totalRequests);
      await prefs.setInt('gpt_cache_hits', _cacheHits);
      await prefs.setInt('gpt_calls', _gptCalls);
      await prefs.setDouble('gpt_total_cost', _totalCost);
    } catch (e) {
      print('Ошибка сохранения статистики: $e');
    }
  }

  /// Загрузить статистику
  Future<void> _loadStats() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _totalRequests = prefs.getInt('gpt_total_requests') ?? 0;
      _cacheHits = prefs.getInt('gpt_cache_hits') ?? 0;
      _gptCalls = prefs.getInt('gpt_calls') ?? 0;
      _totalCost = prefs.getDouble('gpt_total_cost') ?? 0.0;
    } catch (e) {
      print('Ошибка загрузки статистики: $e');
    }
  }

  /// Сбросить статистику
  Future<void> resetStats() async {
    _totalRequests = 0;
    _cacheHits = 0;
    _gptCalls = 0;
    _totalCost = 0.0;
    await _saveStats();
  }
}
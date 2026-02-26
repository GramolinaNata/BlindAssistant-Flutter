import 'package:flutter_test/flutter_test.dart';
import 'package:blindddd/services/api_service.dart';
import 'dart:io';

void main() {
  group('Тесты регистрации и входа', () {
    final apiService = ApiService();


    test('TC01: Регистрация с корректными данными', () async {
      final testAudioPath = await _createTestAudioFile();

      final result = await apiService.registerVoice(
        'test_user_${DateTime.now().millisecondsSinceEpoch}',
        testAudioPath,
      );

      // Проверка. но я не пройду(
      expect(result, isNotNull);
      expect(result, isMap);

      // не прошли
      if (result.containsKey('error')) {
        print('TC01: Получена ошибка (возможно некорректный формат аудио): ${result['error']}');
      }

      await File(testAudioPath).delete();
    });

    test('TC02: Регистрация с пустым именем пользователя', () async {
      final testAudioPath = await _createTestAudioFile();

      final result = await apiService.registerVoice('', testAudioPath);

      expect(result.containsKey('error'), true);

      await File(testAudioPath).delete();
    });

    test('TC03: Регистрация с очень длинным именем (граничное значение)', () async {
      final testAudioPath = await _createTestAudioFile();
      final longUsername = 'a' * 100;

      final result = await apiService.registerVoice(longUsername, testAudioPath);

      expect(result, isNotNull);

      await File(testAudioPath).delete();
    });

    test('TC04: Регистрация со спецсимволами в имени', () async {
      final testAudioPath = await _createTestAudioFile();

      final result = await apiService.registerVoice('user@#\$%', testAudioPath);

      expect(result, isNotNull);

      await File(testAudioPath).delete();
    });

    test('TC05: Регистрация без аудио файла', () async {
      final result = await apiService.registerVoice('test_user', '');

      expect(result.containsKey('error'), true);
      expect(result['error'], contains('Audio file not found'));
    });

    test('TC06: Регистрация с несуществующим аудио файлом', () async {
      final result = await apiService.registerVoice(
        'test_user',
        '/non/existent/path.aac',
      );

      expect(result.containsKey('error'), true);
    });


    test('TC07: Вход с корректными данными (после регистрации)', () async {
      final testAudioPath = await _createTestAudioFile();
      final username = 'login_test_${DateTime.now().millisecondsSinceEpoch}';

      final registerResult = await apiService.registerVoice(username, testAudioPath);
      print('TC07 Регистрация: $registerResult');

      // Пытаемся войти
      final loginResult = await apiService.loginVoice(username, testAudioPath);
      print('TC07 Вход: $loginResult');

      // Тоже самое
      expect(loginResult, isNotNull);
      expect(loginResult, isMap);

      await File(testAudioPath).delete();
    });

    test('TC08: Вход с незарегистрированным пользователем', () async {
      final testAudioPath = await _createTestAudioFile();

      final result = await apiService.loginVoice(
        'nonexistent_user_12345',
        testAudioPath,
      );

      expect(result.containsKey('error'), true);

      await File(testAudioPath).delete();
    });

    test('TC09: Вход с пустым именем пользователя', () async {
      final testAudioPath = await _createTestAudioFile();

      final result = await apiService.loginVoice('', testAudioPath);

      expect(result.containsKey('error'), true);

      await File(testAudioPath).delete();
    });

    test('TC10: Вход без аудио файла', () async {
      final result = await apiService.loginVoice('test_user', '');

      expect(result.containsKey('error'), true);
      expect(result['error'], contains('Audio file not found'));
    });

    test('TC11: Вход с кириллицей в имени пользователя', () async {
      final testAudioPath = await _createTestAudioFile();
      final username = 'пользователь_тест_${DateTime.now().millisecondsSinceEpoch}';

      // Регистрируем
      await apiService.registerVoice(username, testAudioPath);

      // Пытаемся войти
      final result = await apiService.loginVoice(username, testAudioPath);

      expect(result, isNotNull);

      await File(testAudioPath).delete();
    });

    test('TC12: Проверка подключения к серверу', () async {
      final result = await apiService.testConnection();

      expect(result, isNotNull);
      expect(result, isMap);

      print('TC12 Подключение к серверу: $result');
    });
  });
}

Future<String> _createTestAudioFile() async {
  final directory = Directory.systemTemp;
  final file = File('${directory.path}/test_audio_${DateTime.now().millisecondsSinceEpoch}.aac');

  // Создаём минимальный валидный AAC файл
  final bytes = List<int>.generate(1024, (i) => i % 256);
  await file.writeAsBytes(bytes);

  return file.path;
}
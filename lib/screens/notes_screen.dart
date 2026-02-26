import 'package:flutter/material.dart';
import 'package:blindddd/services/audio_service.dart';
import 'package:blindddd/services/api_service.dart';
import 'dart:async';

class NotesScreen extends StatefulWidget {
  final SimpleAudioService audioService;
  final ApiService apiService;
  final String username;

  const NotesScreen({
    super.key,
    required this.audioService,
    required this.apiService,
    required this.username,
  });

  @override
  _NotesScreenState createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  List<Map<String, dynamic>> _notes = [];
  bool _isLoading = false;
  bool _isListening = false;
  String _statusMessage = 'Загрузка заметок...';
  Timer? _reminderCheckTimer;

  @override
  void initState() {
    super.initState();
    _initializeNotesScreen();
    _startReminderChecker();
  }

  Future<void> _initializeNotesScreen() async {
    await widget.audioService.speak("Режим заметок активирован");
    await Future.delayed(const Duration(milliseconds: 1000));
    await _loadNotes();
    await widget.audioService.speak(
        "У вас ${_notes.length} заметок. "
            "Скажите: добавить заметку, чтобы создать новую. "
            "Или назовите номер заметки для управления."
    );
  }

  void _startReminderChecker() {
    _reminderCheckTimer = Timer.periodic(
      const Duration(seconds: 30),
          (timer) => _checkReminders(),
    );
  }

  Future<void> _checkReminders() async {
    try {
      var result = await widget.apiService.checkReminders(widget.username);

      if (result['status'] == 'success' && result['reminders'] != null) {
        List reminders = result['reminders'];
        DateTime now = DateTime.now();

        for (var reminder in reminders) {
          String noteText = reminder['note_text'];
          int noteId = reminder['id'];
          String remindAtStr = reminder['remind_at'];

          try {
            DateTime remindTime = DateTime.parse(remindAtStr);
            Duration difference = now.difference(remindTime);

            if (difference.isNegative || difference.inMinutes > 1) {
              continue;
            }

            await widget.audioService.speak(
                "Напоминание! $noteText. "
                    "Скажите 'выполнено' чтобы отметить заметку как выполненную"
            );

            await widget.apiService.completeNote(noteId);
            await _loadNotes();
          } catch (e) {
            print("Ошибка парсинга времени: $e");
          }
        }
      }
    } catch (e) {
      print("Ошибка проверки напоминаний: $e");
    }
  }

  Future<void> _loadNotes() async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'Загрузка заметок...';
    });

    try {
      var result = await widget.apiService.getNotes(widget.username);

      if (result['status'] == 'success') {
        setState(() {
          _notes = List<Map<String, dynamic>>.from(result['notes'] ?? []);
          _statusMessage = 'Заметок: ${_notes.length}';
        });
      } else {
        setState(() => _statusMessage = 'Ошибка загрузки');
        widget.audioService.speak("Ошибка загрузки заметок");
      }
    } catch (e) {
      print("Ошибка загрузки заметок: $e");
      setState(() => _statusMessage = 'Ошибка: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  /// УНИВЕРСАЛЬНЫЙ МЕТОД ДЛЯ ПРОСЛУШИВАНИЯ - всегда использует GPT
  Future<String?> _listenSmart({int timeoutSeconds = 25}) async {
    Map<String, dynamic>? result = await widget.audioService.listenWithGpt(
      timeoutSeconds: timeoutSeconds,
    );

    if (result != null && result['success'] == true) {
      // Возвращаем ТОЛЬКО исправленный GPT текст
      return result['corrected_text'];
    }

    return null;
  }

  Future<void> _listenForNoteCommand() async {
    if (_isListening) {
      widget.audioService.speak("Подождите, я все еще слушаю");
      return;
    }

    setState(() {
      _isListening = true;
      _statusMessage = 'Слушаю команду...';
    });

    await widget.audioService.speak("Слушаю вашу команду");
    await Future.delayed(const Duration(milliseconds: 1500));

    try {
      String? command = await _listenSmart();

      if (command != null && command.isNotEmpty) {
        await _processNoteCommand(command.toLowerCase().trim());
      } else {
        await widget.audioService.speak("Не услышал команду. Попробуйте еще раз");
      }
    } catch (e) {
      print("Ошибка команды: $e");
      await widget.audioService.speak("Ошибка обработки команды");
    } finally {
      setState(() => _isListening = false);
    }
  }

  Future<void> _processNoteCommand(String text) async {
    if (text.contains('добавить') || text.contains('создать') || text.contains('новая') ||
        text.contains('заметка') || text.contains('записать')) {
      await _createNewNoteWithReminder();
    }
    else if (text.contains('удалить') || text.contains('удали')) {
      await _handleDeleteNote();
    }
    else if (text.contains('изменить') || text.contains('редактировать')) {
      await _handleEditNote();
    }
    else if (text.contains('прочитать') || text.contains('список') || text.contains('озвучь') ||
        text.contains('покажи') || text.contains('читать')) {
      await _readAllNotes();
    }
    else if (text.contains('выполнен') || text.contains('сделано') || text.contains('готово') ||
        text.contains('заверши')) {
      await _handleCompleteNote();
    }
    else if (text.contains('назад') || text.contains('выход') || text.contains('вернуться') ||
        text.contains('главный')) {
      await widget.audioService.speak("Возврат на главный экран");
      await Future.delayed(const Duration(milliseconds: 1000));
      Navigator.pop(context);
    }
    else if (text.contains('обновить') || text.contains('обнови')) {
      await _loadNotes();
      await widget.audioService.speak("Список обновлен. Заметок: ${_notes.length}");
    }
    else {
      await widget.audioService.speak(
          "Команда не распознана. Доступные команды: добавить заметку, прочитать заметки, удалить заметку, изменить заметку, назад"
      );
    }
  }

  Future<void> _createNewNoteWithReminder() async {
    await widget.audioService.speak("Создание новой заметки. Скажите текст заметки");
    await Future.delayed(const Duration(milliseconds: 1000));

    String? noteText = await _listenSmart(timeoutSeconds: 30);

    if (noteText == null || noteText.isEmpty) {
      await widget.audioService.speak("Текст заметки не распознан. Попробуйте еще раз");
      return;
    }

    await widget.audioService.speak("Вы сказали: $noteText. Верно? Скажите да или нет");
    String? confirmation = await _listenSmart(timeoutSeconds: 15);

    if (confirmation == null || !confirmation.toLowerCase().contains('да')) {
      await widget.audioService.speak("Создание заметки отменено");
      return;
    }

    await widget.audioService.speak("Нужно ли напоминание? Скажите да или нет");
    String? needReminder = await _listenSmart(timeoutSeconds: 15);

    String? remindAt;
    if (needReminder != null && needReminder.toLowerCase().contains('да')) {
      remindAt = await _askForReminderTime();
    }

    setState(() => _isLoading = true);

    var result = await widget.apiService.addNote(
      username: widget.username,
      noteText: noteText,
      remindAt: remindAt,
    );

    setState(() => _isLoading = false);

    if (result['status'] == 'success') {
      await widget.audioService.speak("Заметка создана успешно");
      await _loadNotes();
    } else {
      await widget.audioService.speak("Ошибка создания заметки");
    }
  }

  Future<String?> _askForReminderTime() async {
    try {
      await widget.audioService.speak("На какое время установить напоминание? Скажите сначала часы, от 0 до 23");
      await Future.delayed(const Duration(milliseconds: 2000));

      String? hoursText = await _listenSmart(timeoutSeconds: 20);

      if (hoursText == null || hoursText.isEmpty) {
        await widget.audioService.speak("Часы не распознаны, напоминание не установлено");
        return null;
      }

      int? hours = _parseNumberFromText(hoursText);

      if (hours == null || hours < 0 || hours > 23) {
        await widget.audioService.speak("Некорректные часы, напоминание не установлено");
        return null;
      }

      await widget.audioService.speak("Часы установлены на $hours. Теперь скажите минуты, от 0 до 59");
      await Future.delayed(const Duration(milliseconds: 2000));

      String? minutesText = await _listenSmart(timeoutSeconds: 20);

      if (minutesText == null || minutesText.isEmpty) {
        await widget.audioService.speak("Минуты не распознаны, напоминание не установлено");
        return null;
      }

      int? minutes = _parseNumberFromText(minutesText);

      if (minutes == null || minutes < 0 || minutes > 59) {
        await widget.audioService.speak("Некорректные минуты, напоминание не установлено");
        return null;
      }

      DateTime now = DateTime.now();
      DateTime remindTime = DateTime(now.year, now.month, now.day, hours, minutes);

      if (remindTime.isBefore(now)) {
        remindTime = remindTime.add(const Duration(days: 1));
      }

      await widget.audioService.speak("Напоминание установлено на $hours часов $minutes минут");

      return _formatDateTime(remindTime);
    } catch (e) {
      print("❌ Ошибка установки напоминания: $e");
      await widget.audioService.speak("Ошибка установки напоминания");
      return null;
    }
  }

  int? _parseNumberFromText(String text) {
    final numbers = {
      'ноль': 0, 'нуль': 0, 'один': 1, 'одна': 1, 'два': 2, 'две': 2,
      'три': 3, 'четыре': 4, 'пять': 5, 'шесть': 6, 'семь': 7,
      'восемь': 8, 'девять': 9, 'десять': 10, 'одиннадцать': 11,
      'двенадцать': 12, 'тринадцать': 13, 'четырнадцать': 14,
      'пятнадцать': 15, 'шестнадцать': 16, 'семнадцать': 17,
      'восемнадцать': 18, 'девятнадцать': 19, 'двадцать': 20,
      'двадцать один': 21, 'двадцать два': 22, 'двадцать три': 23,
      'двадцать четыре': 24, 'двадцать пять': 25, 'двадцать шесть': 26,
      'двадцать семь': 27, 'двадцать восемь': 28, 'двадцать девять': 29,
      'тридцать': 30, 'тридцать один': 31, 'тридцать два': 32,
      'тридцать три': 33, 'тридцать четыре': 34, 'тридцать пять': 35,
      'тридцать шесть': 36, 'тридцать семь': 37, 'тридцать восемь': 38,
      'тридцать девять': 39, 'сорок': 40, 'сорок один': 41, 'сорок два': 42,
      'сорок три': 43, 'сорок четыре': 44, 'сорок пять': 45, 'сорок шесть': 46,
      'сорок семь': 47, 'сорок восемь': 48, 'сорок девять': 49,
      'пятьдесят': 50, 'пятьдесят один': 51, 'пятьдесят два': 52,
      'пятьдесят три': 53, 'пятьдесят четыре': 54, 'пятьдесят пять': 55,
      'пятьдесят шесть': 56, 'пятьдесят семь': 57, 'пятьдесят восемь': 58,
      'пятьдесят девять': 59
    };

    text = text.toLowerCase().trim();
    text = text.replaceAll(RegExp(r'\b(часов|час|минут|минуты|минута)\b'), '').trim();

    for (var entry in numbers.entries) {
      if (text == entry.key) {
        return entry.value;
      }
    }

    for (var entry in numbers.entries) {
      if (text.contains(entry.key)) {
        return entry.value;
      }
    }

    RegExp regExp = RegExp(r'\d+');
    var match = regExp.firstMatch(text);
    if (match != null) {
      return int.tryParse(match.group(0)!);
    }

    return null;
  }

  String _formatDateTime(DateTime dt) {
    return "${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} "
        "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:00";
  }

  Future<void> _readAllNotes() async {
    if (_notes.isEmpty) {
      await widget.audioService.speak("У вас нет заметок");
      return;
    }

    await widget.audioService.speak("Читаю ваши заметки");

    for (int i = 0; i < _notes.length; i++) {
      var note = _notes[i];
      String noteText = note['note_text'] ?? 'Без текста';
      String remindInfo = note['remind_at'] != null
          ? "Напоминание установлено"
          : "Без напоминания";

      await widget.audioService.speak("Заметка ${i + 1}. $noteText. $remindInfo");
      await Future.delayed(const Duration(milliseconds: 1000));
    }

    await widget.audioService.speak("Всего ${_notes.length} заметок");
  }

  Future<void> _handleDeleteNote() async {
    if (_notes.isEmpty) {
      await widget.audioService.speak("У вас нет заметок для удаления");
      return;
    }

    await widget.audioService.speak("Какую заметку удалить? Скажите номер заметки от 1 до ${_notes.length}");

    String? noteNumberText = await _listenSmart(timeoutSeconds: 20);

    if (noteNumberText == null || noteNumberText.isEmpty) {
      await widget.audioService.speak("Номер заметки не распознан");
      return;
    }

    int? noteIndex = _parseNumberFromText(noteNumberText);

    if (noteIndex == null || noteIndex < 1 || noteIndex > _notes.length) {
      await widget.audioService.speak("Некорректный номер заметки. У вас всего ${_notes.length} заметок");
      return;
    }

    var note = _notes[noteIndex - 1];
    int noteId = note['id'];

    await widget.audioService.speak("Удалить заметку номер $noteIndex: ${note['note_text']}? Скажите да или нет");

    String? confirmation = await _listenSmart(timeoutSeconds: 15);

    if (confirmation == null || !confirmation.toLowerCase().contains('да')) {
      await widget.audioService.speak("Удаление отменено");
      return;
    }

    setState(() => _isLoading = true);

    var result = await widget.apiService.deleteNote(noteId);

    setState(() => _isLoading = false);

    if (result['status'] == 'success') {
      await widget.audioService.speak("Заметка удалена");
      await _loadNotes();
    } else {
      await widget.audioService.speak("Ошибка удаления");
    }
  }

  Future<void> _handleEditNote() async {
    if (_notes.isEmpty) {
      await widget.audioService.speak("У вас нет заметок для редактирования");
      return;
    }

    await widget.audioService.speak("Какую заметку изменить? Скажите номер заметки от 1 до ${_notes.length}");

    String? noteNumberText = await _listenSmart(timeoutSeconds: 20);

    if (noteNumberText == null || noteNumberText.isEmpty) {
      await widget.audioService.speak("Номер заметки не распознан");
      return;
    }

    int? noteIndex = _parseNumberFromText(noteNumberText);

    if (noteIndex == null || noteIndex < 1 || noteIndex > _notes.length) {
      await widget.audioService.speak("Некорректный номер заметки. У вас всего ${_notes.length} заметок");
      return;
    }

    var note = _notes[noteIndex - 1];
    int noteId = note['id'];

    await widget.audioService.speak("Текущий текст заметки номер $noteIndex: ${note['note_text']}");
    await widget.audioService.speak("Скажите новый текст заметки");

    String? newText = await _listenSmart(timeoutSeconds: 30);

    if (newText == null || newText.isEmpty) {
      await widget.audioService.speak("Текст не распознан");
      return;
    }

    setState(() => _isLoading = true);

    var result = await widget.apiService.updateNote(
      noteId: noteId,
      noteText: newText,
    );

    setState(() => _isLoading = false);

    if (result['status'] == 'success') {
      await widget.audioService.speak("Заметка обновлена");
      await _loadNotes();
    } else {
      await widget.audioService.speak("Ошибка обновления");
    }
  }

  Future<void> _handleCompleteNote() async {
    if (_notes.isEmpty) {
      await widget.audioService.speak("У вас нет заметок для отметки");
      return;
    }

    await widget.audioService.speak("Какую заметку отметить как выполненную? Скажите номер заметки от 1 до ${_notes.length}");

    String? noteNumberText = await _listenSmart(timeoutSeconds: 20);

    if (noteNumberText == null || noteNumberText.isEmpty) {
      await widget.audioService.speak("Номер заметки не распознан");
      return;
    }

    int? noteIndex = _parseNumberFromText(noteNumberText);

    if (noteIndex == null || noteIndex < 1 || noteIndex > _notes.length) {
      await widget.audioService.speak("Некорректный номер заметки. У вас всего ${_notes.length} заметок");
      return;
    }

    var note = _notes[noteIndex - 1];
    int noteId = note['id'];

    setState(() => _isLoading = true);

    var result = await widget.apiService.completeNote(noteId);

    setState(() => _isLoading = false);

    if (result['status'] == 'success') {
      await widget.audioService.speak("Заметка отмечена как выполненная");
      await _loadNotes();
    } else {
      await widget.audioService.speak("Ошибка");
    }
  }

  @override
  void dispose() {
    _reminderCheckTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(
          '📝 Заметки (${widget.username})',
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: Semantics(
          label: "Кнопка назад",
          child: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
        ),
      ),
      body: Column(
        children: [
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[900],
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                if (_isLoading)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: Colors.blue,
                      strokeWidth: 2,
                    ),
                  ),
                if (_isLoading) const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _statusMessage,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.white70,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(
              child: CircularProgressIndicator(color: Colors.blue),
            )
                : _notes.isEmpty
                ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.note_alt_outlined,
                    size: 80,
                    color: Colors.grey[700],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Нет заметок',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Скажите "добавить заметку"',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[700],
                    ),
                  ),
                ],
              ),
            )
                : ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _notes.length,
              itemBuilder: (context, index) {
                var note = _notes[index];
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey[900],
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.blue,
                      child: Text(
                        '${index + 1}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    title: Text(
                      note['note_text'] ?? 'Без текста',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    subtitle: note['remind_at'] != null
                        ? Text(
                      '🔔 ${note['remind_at']}',
                      style: TextStyle(
                        color: Colors.orange[300],
                        fontSize: 12,
                      ),
                    )
                        : null,
                    trailing: Icon(
                      Icons.arrow_forward_ios,
                      color: Colors.grey[600],
                      size: 16,
                    ),
                  ),
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Semantics(
                  label: "Кнопка голосовых команд для заметок",
                  child: Container(
                    width: double.infinity,
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
                      onPressed: _isListening ? null : _listenForNoteCommand,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                      ),
                      child: _isListening
                          ? const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          ),
                          SizedBox(width: 12),
                          Text(
                            'Слушаю...',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      )
                          : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.mic, size: 24),
                          SizedBox(width: 8),
                          Text(
                            'Голосовая команда',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[800],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '💬 Команды:',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.white70,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        '• "Добавить заметку" - создать\n'
                            '• "Прочитать заметки" - озвучить все\n'
                            '• "Удалить заметку" - удалить\n'
                            '• "Изменить заметку" - редактировать\n'
                            '• "Выполнена заметка" - отметить\n'
                            '• "Назад" - вернуться',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.white60,
                          height: 1.3,
                        ),
                      ),
                    ],
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
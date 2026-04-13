import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/api_service.dart';

class SubtitlesScreen extends StatefulWidget {
  final ApiService apiService;
  final String username;

  const SubtitlesScreen({
    super.key,
    required this.apiService,
    required this.username,
  });

  @override
  State<SubtitlesScreen> createState() => _SubtitlesScreenState();
}

class _SubtitlesScreenState extends State<SubtitlesScreen> {
  final FlutterSoundRecorder _recorder = FlutterSoundRecorder();
  bool _isRunning = false;
  bool _isRecording = false;
  bool _isProcessing = false;

  final List<_SubtitleEntry> _subtitles = [];
  final ScrollController _scrollController = ScrollController();

  static const int _chunkSeconds = 4;
  Timer? _chunkTimer;
  String? _currentChunkPath;

  @override
  void initState() {
    super.initState();
    _initRecorder();
  }

  Future<void> _initRecorder() async {
    await Permission.microphone.request();
    await _recorder.openRecorder();
  }

  @override
  void dispose() {
    _stop();
    _recorder.closeRecorder();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (_isRunning) return;
    setState(() => _isRunning = true);
    _scheduleNextChunk();
  }

  void _stop() {
    _chunkTimer?.cancel();
    _chunkTimer = null;
    if (_isRecording) {
      _recorder.stopRecorder().catchError((_) => '');
      _isRecording = false;
    }
    if (mounted) setState(() { _isRunning = false; _isRecording = false; });
  }

  void _scheduleNextChunk() {
    if (!_isRunning) return;
    _startRecordingChunk();
    _chunkTimer = Timer(
      const Duration(seconds: _chunkSeconds),
          () => _stopChunkAndSend(sendAfter: true),
    );
  }

  Future<void> _startRecordingChunk() async {
    try {
      final dir = await getTemporaryDirectory();
      _currentChunkPath =
      '${dir.path}/chunk_${DateTime.now().millisecondsSinceEpoch}.aac';
      await _recorder.startRecorder(
        toFile: _currentChunkPath,
        codec: Codec.aacADTS,
      );
      if (mounted) setState(() => _isRecording = true);
    } catch (e) {
      debugPrint('❌ Ошибка старта записи: $e');
    }
  }

  Future<void> _stopChunkAndSend({required bool sendAfter}) async {
    try {
      await _recorder.stopRecorder();
      if (mounted) setState(() => _isRecording = false);
      if (sendAfter && _currentChunkPath != null) {
        final path = _currentChunkPath!;
        _currentChunkPath = null;
        await _sendChunk(path);
      }
    } catch (e) {
      debugPrint('❌ Ошибка остановки: $e');
    } finally {
      if (sendAfter && _isRunning) _scheduleNextChunk();
    }
  }

  Future<void> _sendChunk(String path) async {
    if (mounted) setState(() => _isProcessing = true);
    try {
      final result = await widget.apiService.transcribeAudio(path);
      final text = result['text'] as String? ?? '';
      if (text.isNotEmpty) {
        final lang = result['language'] as String? ?? 'ru';
        if (mounted) {
          setState(() {
            _subtitles.add(_SubtitleEntry(
              text: text,
              lang: lang,
              time: DateTime.now(),
            ));
            if (_subtitles.length > 50) _subtitles.removeAt(0);
          });
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_scrollController.hasClients) {
              _scrollController.animateTo(
                _scrollController.position.maxScrollExtent,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
              );
            }
          });
        }
      }
    } catch (e) {
      debugPrint('❌ Ошибка отправки: $e');
    } finally {
      try { File(path).deleteSync(); } catch (_) {}
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Субтитры'),
        actions: [
          if (_isProcessing)
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.yellow,
                ),
              ),
            ),
          if (_isRecording)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.fiber_manual_record, color: Colors.red, size: 14),
                  SizedBox(width: 4),
                  Text('REC',
                      style: TextStyle(color: Colors.red, fontSize: 13)),
                ],
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _subtitles.isEmpty
                ? Center(
              child: Text(
                _isRunning
                    ? 'Слушаю...\nНачните говорить'
                    : 'Нажмите кнопку\nдля начала',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 22,
                  height: 1.6,
                ),
              ),
            )
                : ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(
                  horizontal: 20, vertical: 16),
              itemCount: _subtitles.length,
              itemBuilder: (context, i) {
                final entry = _subtitles[i];
                final isLast = i == _subtitles.length - 1;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    entry.text,
                    style: TextStyle(
                      color: isLast ? Colors.white : Colors.white60,
                      fontSize: isLast ? 28 : 20,
                      fontWeight: isLast
                          ? FontWeight.w500
                          : FontWeight.normal,
                      height: 1.4,
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(32),
            child: GestureDetector(
              onTap: _isRunning ? _stop : _start,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _isRunning ? Colors.red : Colors.white,
                ),
                child: Icon(
                  _isRunning ? Icons.stop : Icons.mic,
                  size: 36,
                  color: _isRunning ? Colors.white : Colors.black,
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: _subtitles.isNotEmpty
          ? FloatingActionButton.small(
        onPressed: () => setState(() => _subtitles.clear()),
        backgroundColor: Colors.white24,
        child: const Icon(Icons.clear_all, color: Colors.white),
      )
          : null,
    );
  }
}

class _SubtitleEntry {
  final String text;
  final String lang;
  final DateTime time;

  _SubtitleEntry({
    required this.text,
    required this.lang,
    required this.time,
  });
}
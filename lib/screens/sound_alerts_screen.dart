import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/api_service.dart';

class SoundAlertsScreen extends StatefulWidget {
  final ApiService apiService;
  final String username;

  const SoundAlertsScreen({
    super.key,
    required this.apiService,
    required this.username,
  });

  @override
  State<SoundAlertsScreen> createState() => _SoundAlertsScreenState();
}

class _SoundAlertsScreenState extends State<SoundAlertsScreen>
    with TickerProviderStateMixin {
  final FlutterSoundRecorder _recorder = FlutterSoundRecorder();
  bool _isMonitoring = false;
  bool _isRecording = false;

  final List<_AlertEntry> _alertHistory = [];
  _AlertEntry? _currentAlert;
  Timer? _chunkTimer;
  Timer? _alertClearTimer;
  String? _chunkPath;

  static const int _chunkSeconds = 3;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _initRecorder();
  }

  Future<void> _initRecorder() async {
    await Permission.microphone.request();
    await _recorder.openRecorder();
  }

  @override
  void dispose() {
    _stopMonitoring();
    _recorder.closeRecorder();
    _pulseController.dispose();
    _chunkTimer?.cancel();
    _alertClearTimer?.cancel();
    super.dispose();
  }

  void _startMonitoring() {
    setState(() => _isMonitoring = true);
    _recordAndSend();
  }

  void _stopMonitoring() {
    _chunkTimer?.cancel();
    _chunkTimer = null;
    if (_isRecording) {
      _recorder.stopRecorder().catchError((_) => '');
      _isRecording = false;
    }
    if (mounted) setState(() => _isMonitoring = false);
  }

  Future<void> _recordAndSend() async {
    if (!_isMonitoring) return;
    try {
      final dir = await getTemporaryDirectory();
      _chunkPath =
      '${dir.path}/alert_${DateTime.now().millisecondsSinceEpoch}.aac';
      await _recorder.startRecorder(
        toFile: _chunkPath,
        codec: Codec.aacADTS,
      );
      if (mounted) setState(() => _isRecording = true);

      _chunkTimer = Timer(const Duration(seconds: _chunkSeconds), () async {
        try {
          await _recorder.stopRecorder();
          if (mounted) setState(() => _isRecording = false);
          if (_chunkPath != null) {
            final path = _chunkPath!;
            _chunkPath = null;
            await _processChunk(path);
          }
        } catch (_) {}
        if (_isMonitoring) _recordAndSend();
      });
    } catch (e) {
      debugPrint('❌ Ошибка записи: $e');
      if (_isMonitoring) {
        await Future.delayed(const Duration(seconds: 1));
        _recordAndSend();
      }
    }
  }

  Future<void> _processChunk(String path) async {
    try {
      final result = await widget.apiService.classifySound(path);
      final alerts = (result['alerts'] as List?)?.cast<Map>() ?? [];
      if (alerts.isNotEmpty) {
        final top = alerts.first;
        final level = top['level'] as String? ?? 'info';
        final name = top['name'] as String? ?? 'Звук';
        final entry = _AlertEntry(
          name: name,
          level: level,
          time: DateTime.now(),
          icon: _iconForLevel(level),
          color: _colorForLevel(level),
        );
        if (mounted) {
          setState(() {
            _currentAlert = entry;
            _alertHistory.insert(0, entry);
            if (_alertHistory.length > 30) _alertHistory.removeLast();
          });
          if (level == 'danger') {
            HapticFeedback.heavyImpact();
            await Future.delayed(const Duration(milliseconds: 200));
            HapticFeedback.heavyImpact();
            await Future.delayed(const Duration(milliseconds: 200));
            HapticFeedback.heavyImpact();
          } else if (level == 'warning') {
            HapticFeedback.mediumImpact();
          } else {
            HapticFeedback.lightImpact();
          }
          _alertClearTimer?.cancel();
          _alertClearTimer = Timer(
            const Duration(seconds: 4),
                () {
              if (mounted) setState(() => _currentAlert = null);
            },
          );
        }
      }
    } catch (e) {
      debugPrint('❌ Ошибка classify: $e');
    } finally {
      try { File(path).deleteSync(); } catch (_) {}
    }
  }

  Color _colorForLevel(String level) {
    switch (level) {
      case 'danger':
        return Colors.red;
      case 'warning':
        return Colors.orange;
      default:
        return Colors.blue;
    }
  }

  IconData _iconForLevel(String level) {
    switch (level) {
      case 'danger':
        return Icons.warning_rounded;
      case 'warning':
        return Icons.notifications_active;
      default:
        return Icons.info_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A0A),
        foregroundColor: Colors.white,
        title: const Text('Звуковые алерты'),
        actions: [
          if (_isMonitoring)
            Padding(
              padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedBuilder(
                    animation: _pulseAnim,
                    builder: (_, __) => Transform.scale(
                      scale: _isRecording ? _pulseAnim.value : 1.0,
                      child: const Icon(Icons.fiber_manual_record,
                          color: Colors.green, size: 12),
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Text('СЛУШАЮ',
                      style: TextStyle(
                          color: Colors.green,
                          fontSize: 12,
                          letterSpacing: 1)),
                ],
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: _currentAlert != null
                ? _buildAlertBanner(_currentAlert!)
                : const SizedBox(key: ValueKey('empty')),
          ),
          if (_currentAlert == null)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                _isMonitoring
                    ? 'Мониторинг активен\nЯ сообщу о важных звуках'
                    : 'Включите мониторинг\nчтобы отслеживать звуки вокруг',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 18,
                  height: 1.6,
                ),
              ),
            ),
          Expanded(
            child: _alertHistory.isEmpty
                ? const SizedBox()
                : ListView.builder(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 8),
              itemCount: _alertHistory.length,
              itemBuilder: (ctx, i) =>
                  _buildHistoryTile(_alertHistory[i]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(32),
            child: GestureDetector(
              onTap:
              _isMonitoring ? _stopMonitoring : _startMonitoring,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _isMonitoring ? Colors.red : Colors.green,
                ),
                child: Icon(
                  _isMonitoring ? Icons.stop : Icons.hearing,
                  size: 40,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAlertBanner(_AlertEntry alert) {
    return AnimatedBuilder(
      key: ValueKey(alert.time),
      animation: _pulseAnim,
      builder: (_, __) => Transform.scale(
        scale: alert.level == 'danger' ? _pulseAnim.value : 1.0,
        child: Container(
          width: double.infinity,
          margin: const EdgeInsets.all(16),
          padding:
          const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          decoration: BoxDecoration(
            color: alert.color.withValues(alpha: 0.15),
            border: Border.all(color: alert.color, width: 2),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Icon(alert.icon, color: alert.color, size: 48),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  alert.name,
                  style: TextStyle(
                    color: alert.color,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    height: 1.2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHistoryTile(_AlertEntry alert) {
    final timeStr =
        '${alert.time.hour.toString().padLeft(2, '0')}:${alert.time.minute.toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(alert.icon,
              color: alert.color.withValues(alpha: 0.7), size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              alert.name,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.75),
                fontSize: 15,
              ),
            ),
          ),
          Text(
            timeStr,
            style: const TextStyle(color: Colors.white38, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _AlertEntry {
  final String name;
  final String level;
  final DateTime time;
  final IconData icon;
  final Color color;

  _AlertEntry({
    required this.name,
    required this.level,
    required this.time,
    required this.icon,
    required this.color,
  });
}
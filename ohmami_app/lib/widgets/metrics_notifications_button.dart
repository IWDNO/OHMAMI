import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../services/connection_service.dart';

/// Кнопка уведомлений по системным метрикам.
/// Показывает бейдж с количеством важных предупреждений
/// (например, высокая загрузка CPU/памяти, низкий заряд батареи).
class MetricsNotificationsButton extends StatefulWidget {
  const MetricsNotificationsButton({super.key});

  @override
  State<MetricsNotificationsButton> createState() =>
      _MetricsNotificationsButtonState();
}

class _MetricsNotificationsButtonState
    extends State<MetricsNotificationsButton> {
  final ConnectionService _connectionService = ConnectionService();
  StreamSubscription? _wsSubscription;

  /// Список последних важных уведомлений.
  final List<String> _alerts = [];

  /// Чтобы не дублировать уведомления при постоянном превышении порога.
  bool _cpuHigh = false;
  bool _memHigh = false;
  bool _gpuHigh = false;
  bool _batteryLow = false;

  @override
  void initState() {
    super.initState();
    _wsSubscription =
        _connectionService.wsMessages.stream.listen(_handleWsMessage);
  }

  @override
  void dispose() {
    _wsSubscription?.cancel();
    super.dispose();
  }

  void _handleWsMessage(String message) {
    try {
      final decoded = json.decode(message);
      if (decoded is! Map || decoded['type'] != 'metrics') return;

      final payload = decoded['payload'];
      if (payload is! Map) return;

      final metrics = Map<String, dynamic>.from(payload);
      _processMetrics(metrics);
    } catch (_) {
      // игнорируем невалидные сообщения
    }
  }

  void _processMetrics(Map<String, dynamic> m) {
    final cpu = _section(m, 'cpu');
    final mem = _section(m, 'memory');
    final gpu = _section(m, 'gpu');
    final bat = _section(m, 'battery');

    final cpuUsage = _toPercent(cpu['usage_percent']);
    final memUsage = _toPercent(
      mem['usage_percent'] ??
          (100 *
              _safeDouble(mem['used_mb']) /
              (_safeDouble(mem['total_mb']) == 0
                  ? 1
                  : _safeDouble(mem['total_mb']))),
    );
    final gpuUsage = _toPercent(gpu['usage_percent']);
    final batPercent = _toPercent(bat['charge_percent']);
    final hasBattery = bat['is_present'] == true;

    final newAlerts = <String>[];

    // Примеры простых правил — при желании можно вынести пороги в константы.
    final cpuHighNow = cpuUsage > 50;
    if (cpuHighNow && !_cpuHigh) {
      newAlerts.add('Высокая загрузка CPU: ${cpuUsage.toStringAsFixed(1)}%');
    }

    final memHighNow = memUsage > 80;
    if (memHighNow && !_memHigh) {
      newAlerts.add('Высокая загрузка памяти: ${memUsage.toStringAsFixed(1)}%');
    }

    final gpuHighNow = gpuUsage > 80;
    if (gpuHighNow && !_gpuHigh) {
      newAlerts.add('Высокая загрузка GPU: ${gpuUsage.toStringAsFixed(1)}%');
    }

    final batteryLowNow = hasBattery && batPercent > 0 && batPercent < 20;
    if (batteryLowNow && !_batteryLow) {
      newAlerts.add(
          'Низкий заряд батареи: ${batPercent.toStringAsFixed(1)}% осталось');
    }

    if (newAlerts.isEmpty) {
      // обновляем флаги, но без новых уведомлений
      _cpuHigh = cpuHighNow;
      _memHigh = memHighNow;
      _gpuHigh = gpuHighNow;
      _batteryLow = batteryLowNow;
      return;
    }

    setState(() {
      _cpuHigh = cpuHighNow;
      _memHigh = memHighNow;
      _gpuHigh = gpuHighNow;
      _batteryLow = batteryLowNow;

      _alerts.insertAll(0, newAlerts);
      const maxAlerts = 20;
      if (_alerts.length > maxAlerts) {
        _alerts.removeRange(maxAlerts, _alerts.length);
      }
    });
  }

  Map<String, dynamic> _section(Map<String, dynamic> src, String key) {
    final section = src[key];
    if (section is Map) return Map<String, dynamic>.from(section);
    return const {};
  }

  double _toPercent(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble().clamp(0, 100);
    final parsed = num.tryParse(v.toString());
    return (parsed ?? 0).toDouble().clamp(0, 100);
  }

  double _safeDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return (num.tryParse(v.toString()) ?? 0).toDouble();
  }

  void _openAlertsDialog() {
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Уведомления о нагрузке'),
          content: _alerts.isEmpty
              ? const Text('Сейчас нет важных уведомлений.')
              : SizedBox(
                  width: double.maxFinite,
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _alerts.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      return ListTile(
                        dense: true,
                        leading: const Icon(Icons.warning_amber_rounded,
                            color: Colors.orange),
                        title: Text(
                          _alerts[index],
                          style: const TextStyle(fontSize: 14),
                        ),
                      );
                    },
                  ),
                ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Закрыть'),
            ),
            if (_alerts.isNotEmpty)
              TextButton(
                onPressed: () {
                  setState(() {
                    _alerts.clear();
                  });
                  Navigator.of(context).pop();
                },
                child: const Text('Очистить'),
              ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasAlerts = _alerts.isNotEmpty;

    return IconButton(
      onPressed: _openAlertsDialog,
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          const Icon(
            Icons.notifications_none,
            color: Colors.white,
          ),
          if (hasAlerts)
            Positioned(
              right: -2,
              top: -2,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
                constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                child: Center(
                  child: Text(
                    _alerts.length > 9 ? '9+' : _alerts.length.toString(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      tooltip: 'Уведомления о метриках',
    );
  }
}



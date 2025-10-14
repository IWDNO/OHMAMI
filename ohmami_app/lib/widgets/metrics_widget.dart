import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import '../services/connection_service.dart';

class MetricsWidget extends StatefulWidget {
  const MetricsWidget({super.key});

  @override
  State<MetricsWidget> createState() => _MetricsWidgetState();
}

class _MetricsWidgetState extends State<MetricsWidget> {
  final ConnectionService _connectionService = ConnectionService();
  StreamSubscription? _wsSubscription;

  Map<String, dynamic>? _metrics;

  @override
  void initState() {
    super.initState();

    _wsSubscription = _connectionService.wsMessages.stream.listen((message) {
      if (!mounted) return;
      try {
        final decoded = json.decode(message);
        if (decoded is Map && decoded['type'] == 'metrics') {
          setState(() {
            _metrics = Map<String, dynamic>.from(decoded['payload'] ?? {});
          });
        }
      } catch (_) {
        // ignore non-json or non-metrics messages
      }
    });
  }

  @override
  void dispose() {
    _wsSubscription?.cancel();
    super.dispose();
  }

  

  // ---------- helpers ----------
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

  String _fmtPercent(dynamic v) {
    return "${_toPercent(v).toStringAsFixed(1)}%";
  }

  String _fmtBytes(dynamic v) {
    final bytes = _safeDouble(v);
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var size = bytes;
    var unit = 0;
    while (size >= 1024 && unit < units.length - 1) {
      size /= 1024;
      unit++;
    }
    return "${size.toStringAsFixed(1)} ${units[unit]}";
  }

  String _fmtRate(dynamic v) {
    return "${_fmtBytes(v)}/s";
  }

  double _mbToBytes(dynamic mb) => _safeDouble(mb) * 1024 * 1024;

  Map<String, dynamic> _section(String key) {
    final m = _metrics ?? const {};
    final section = m[key];
    if (section is Map) return Map<String, dynamic>.from(section);
    return const {};
  }

  // ---------- UI parts ----------
  Widget _metricBar({
    required String title,
    required String subtitle,
    required double percent, // 0..100
    required Color color,
    IconData? icon,
  }) {
    final p = (percent / 100).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (icon != null) Icon(icon, size: 18, color: color),
            if (icon != null) const SizedBox(width: 6),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              _fmtPercent(percent),
              style: TextStyle(fontSize: 13, color: Colors.grey[700]),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: p,
            minHeight: 8,
            backgroundColor: color.withOpacity(0.15),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final cpu = _section('cpu');         // usage_percent, name, cores_*
    final gpu = _section('gpu');         // usage_percent, memory_*_mb, temperature_c
    final mem = _section('memory');      // total_mb, used_mb, usage_percent
    final net = _section('network');     // bytes_sent_per_sec, bytes_received_per_sec
    final sys = _section('system');      // uptime_hours, os, machine_name
    final bat = _section('battery');     // is_present, charge_percent, status, time_remaining_minutes

    // CPU
    final cpuUsage = _toPercent(cpu['usage_percent']);
    final cpuSubtitle = [
      if (cpu['name'] != null) cpu['name'].toString(),
      if (cpu['cores_physical'] != null && cpu['cores_logical'] != null)
        "Cores: ${cpu['cores_physical']}/${cpu['cores_logical']}",
      if (cpu['current_clock_mhz'] != null) "${cpu['current_clock_mhz']} MHz",
      if (cpu['temperature_c'] != null) "${cpu['temperature_c']} °C",
    ].where((e) => e.isNotEmpty).join(' • ');

    // GPU
    final gpuUsage = _toPercent(gpu['usage_percent']);
    final gpuMemUsed = _mbToBytes(gpu['memory_used_mb']);
    final gpuMemTotal = _mbToBytes(gpu['memory_total_mb']);
    final gpuMemSubtitle = "${_fmtBytes(gpuMemUsed)} / ${_fmtBytes(gpuMemTotal)}"
        "${gpu['temperature_c'] != null ? ' • ${gpu['temperature_c']} °C' : ''}"
        "${gpu['name'] != null ? ' • ${gpu['name']}' : ''}";

    // Memory
    final memUsage = _toPercent(
      mem['usage_percent'] ??
      (100 * _safeDouble(mem['used_mb']) / (_safeDouble(mem['total_mb']) == 0 ? 1 : _safeDouble(mem['total_mb']))),
    );
    final memUsed = _mbToBytes(mem['used_mb']);
    final memTotal = _mbToBytes(mem['total_mb']);

    // Network
    final netUp = net['bytes_sent_per_sec'];
    final netDown = net['bytes_received_per_sec'];

    // Battery
    final hasBattery = bat['is_present'] == true;
    final batPercent = _toPercent(bat['charge_percent']);
    final batSubtitle = hasBattery
        ? [
            if (bat['status'] != null) bat['status'].toString(),
            if (bat['time_remaining_minutes'] != null) "${bat['time_remaining_minutes']} min",
          ].where((e) => e.isNotEmpty).join(' • ')
        : "Battery not present";

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Системные метрики',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),          
              ],
            ),
            const SizedBox(height: 8),

            _metricBar(
              title: 'CPU',
              subtitle: cpuSubtitle.isEmpty ? 'Использование: ${_fmtPercent(cpuUsage)}' : cpuSubtitle,
              percent: cpuUsage,
              color: Colors.orange,
              icon: Icons.memory,
            ),
            const SizedBox(height: 14),

            _metricBar(
              title: 'GPU',
              subtitle: gpuMemTotal > 0 ? 'Память: $gpuMemSubtitle' : (gpu['name']?.toString() ?? '—'),
              percent: gpuUsage,
              color: Colors.teal,
              icon: Icons.games,
            ),
            const SizedBox(height: 14),

            _metricBar(
              title: 'Память',
              subtitle: 'Исп: ${_fmtBytes(memUsed)} / ${_fmtBytes(memTotal)}',
              percent: memUsage,
              color: Colors.blue,
              icon: Icons.storage,
            ),
            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(
                  child: _netTile(
                    title: 'Сеть ↑',
                    value: _fmtRate(netUp),
                    color: Colors.purple,
                    icon: Icons.upload,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _netTile(
                    title: 'Сеть ↓',
                    value: _fmtRate(netDown),
                    color: Colors.purple,
                    icon: Icons.download,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // System and Battery rows
            Row(
              children: [
                Expanded(
                  child: _infoTile(
                    title: 'Система',
                    lines: [
                      if (sys['os'] != null) sys['os'].toString(),
                      if (sys['machine_name'] != null) sys['machine_name'].toString(),
                      if (sys['uptime_hours'] != null) "Uptime: ${sys['uptime_hours']} h",
                    ],
                    icon: Icons.computer,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _infoTile(
                    title: 'Батарея',
                    lines: hasBattery
                        ? [
                            "Заряд: ${_fmtPercent(batPercent)}",
                            if (batSubtitle.isNotEmpty) batSubtitle,
                          ]
                        : ["Отсутствует"],
                    icon: Icons.battery_6_bar,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _netTile({
    required String title,
    required String value,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: color.withOpacity(0.06),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            value,
            style: TextStyle(fontSize: 13, color: Colors.grey[800]),
          ),
        ],
      ),
    );
  }

  Widget _infoTile({
    required String title,
    required List<String> lines,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: Colors.grey.withOpacity(0.06),
        border: Border.all(color: Colors.grey.withOpacity(0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Colors.grey[800]),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                ...lines.map((l) => Text(
                      l,
                      style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
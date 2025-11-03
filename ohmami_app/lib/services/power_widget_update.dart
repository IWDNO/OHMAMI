import 'dart:convert';
import 'package:home_widget/home_widget.dart';
import '../services/connection_service.dart';

class PowerHomeWidget {
  static const String androidProvider = 'your.package.name.PowerWidgetProvider';

  static Future<void> setStatus(String text) async {
    await HomeWidget.saveWidgetData<String>('power_status', text);
    await HomeWidget.updateWidget(name: 'PowerWidgetProvider', iOSName: 'PowerWidget');
  }

  static Future<void> handleBackgroundUri(Uri? uri) async {
    if (uri == null) return;
    // uri: homewidget://POWER/<action>
    final action = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : '';
    if (action.isEmpty) return;

    try {
      final baseUrl = await HomeWidget.getWidgetData<String>('base_url', defaultValue: null);
      if (baseUrl == null || baseUrl.isEmpty) {
        await setStatus('Base URL не задан');
        return;
      }

      final conn = ConnectionService();
      conn.setApiUrl(baseUrl);

      String endpoint;
      switch (action) {
        case 'sleep': endpoint = '/sleep'; break;
        case 'hibernate': endpoint = '/hibernate'; break;
        case 'restart': endpoint = '/restart'; break;
        case 'shutdown': endpoint = '/shutdown'; break;
        default:
          await setStatus('Неизвестное действие');
          return;
      }

      final resp = await conn.request('GET', endpoint);
      if (resp.statusCode == 200) {
        final data = json.decode(resp.body);
        final ok = (data is Map && data['status'] == 'ok');
        await setStatus(ok ? (data['message']?.toString() ?? 'OK') : (data['message']?.toString() ?? 'Ошибка'));
      } else {
        await setStatus('HTTP ${resp.statusCode}');
      }
    } catch (e) {
      await setStatus('Ошибка: $e');
    }
  }
}
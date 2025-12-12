import 'package:flutter/material.dart';
import 'package:ohmami_app/widgets/metrics_widget.dart';
import 'package:ohmami_app/widgets/power_widget.dart';

class SystemScreen extends StatelessWidget {
  const SystemScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Система'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Media Control Widget
            MetricsWidget(),
            
            SizedBox(height: 16),
            
            // Volume Control Widget
            PowerWidget(),
            
            // Добавьте другие виджеты здесь, если нужно
          ],
        ),
      ),
    );
  }
}

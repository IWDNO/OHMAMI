import 'package:flutter/material.dart';
import 'package:ohmami_app/widgets/app_widget.dart';

class AppScreen extends StatelessWidget {
  const AppScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('System Control'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [

            AppLauncherWidget(),
            
            SizedBox(height: 16),
            

          ],
        ),
      ),
    );
  }
}

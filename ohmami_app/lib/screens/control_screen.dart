import 'package:flutter/material.dart';
import '../widgets/media_widget.dart';
import '../widgets/volume_widget.dart';
import '../widgets/file_browser_widget.dart';

class ControlScreen extends StatelessWidget {
  const ControlScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Media Control'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: const Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Media Control Widget
            // MediaWidget(),
            
            SizedBox(height: 16),

            // VolumeWidget(),

            SizedBox(height: 16),
            
            // Volume Control Widget
            Expanded(
              child: FileBrowserWidget(),
            ),
          ],
        ),
      ),
    );
  }
}

class ControlScreen2 extends StatelessWidget {
  const ControlScreen2({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Media Control'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: const Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Media Control Widget
            MediaWidget(),
            
            SizedBox(height: 16),

            VolumeWidget(),

            SizedBox(height: 16),
            
            // Volume Control Widget
            // Expanded(
            //   child: FileBrowserWidget(),
            // ),
          ],
        ),
      ),
    );
  }
}

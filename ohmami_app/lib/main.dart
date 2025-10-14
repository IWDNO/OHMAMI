import 'package:flutter/material.dart';
import 'package:ohmami_app/widgets/dummy_widget.dart';
import 'package:ohmami_app/widgets/metrics_widget.dart';

import './widgets/connection_widget.dart';
import './widgets/volume_widget.dart';
import './widgets/media_widget.dart';
import './screens/control_screen.dart';



void main() => runApp(App());


class App extends StatefulWidget {
  const App({super.key});

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  int _currentIndex = 0;

  final List<Widget> _pages = const [
    ConnectionWidget(),
    ControlScreen(),
    // DummyWidget(),
   MetricsWidget(),
  ];

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OHMAMI!',
      home: Scaffold(
        body: IndexedStack(
          index: _currentIndex,
          children: _pages,
        ),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) {
            setState(() {
              _currentIndex = index;
            });
          },
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.wifi_tethering), // Более подходящая иконка для подключения
              label: 'Connection',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.play_circle_outline),
              label: 'Media',
            ),
            // BottomNavigationBarItem(
            //   icon: Icon(Icons.document_scanner),
            //   label: 'None',
            // ),
            BottomNavigationBarItem(
              icon: Icon(Icons.manage_accounts_sharp),
              label: 'metric',
            ),
          ],
        ),
      ),
    );
  }
}

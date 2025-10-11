import 'package:flutter/material.dart';

import './widgets/connection_widget.dart';
import './widgets/dummy_widget.dart';

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
    DummyWidget(),
  ];

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OHMAMI!',
      home: Scaffold(
        appBar: AppBar(
          title: const Text('OHMAMI!'),
        ),
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
              icon: Icon(Icons.private_connectivity_outlined),
              label: 'Connection',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.star),
              label: 'Dummy',
            ),
          ],
        ),
      ),
    );
  }
}
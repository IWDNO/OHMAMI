import 'package:flutter/material.dart';
import 'services/connection_service.dart';
import 'package:ohmami_app/screens/system_screen.dart';
import 'package:ohmami_app/widgets/dummy_widget.dart';
import 'package:ohmami_app/widgets/stream_widget.dart';


import './widgets/connection_widget.dart';
import './screens/control_screen.dart';



void main() => runApp(App());


class App extends StatefulWidget {
  const App({super.key});

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> with WidgetsBindingObserver {
  int _currentIndex = 0;

  final List<Widget> _pages = const [
    ConnectionWidget(),
    StreamWidget(),
    // DummyWidget(),
    SystemScreen(),
    ControlScreen2(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ConnectionService().ensureConnected();
    }
  }

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
          selectedItemColor: Colors.blue,
          unselectedItemColor: Colors.grey,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.wifi_tethering),
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
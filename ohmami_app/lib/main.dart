import 'package:flutter/material.dart';
import 'package:ohmami_app/screens/app_screen.dart';
import 'package:ohmami_app/screens/docs_screen.dart';
import 'package:ohmami_app/widgets/stream_widget.dart';
import 'services/connection_service.dart';
import 'package:ohmami_app/screens/system_screen.dart';
import 'package:ohmami_app/screens/blocked_sites_screen.dart';

import './widgets/connection_widget.dart';
import './screens/control_screen.dart';
import './screens/home_screen.dart';



void main() => runApp(App());


class App extends StatefulWidget {
  const App({super.key});

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> with WidgetsBindingObserver {
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
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
      ),
      home: const ConnectionWidget(),
      routes: {
        '/home': (context) => const HomeScreen(),
        '/connection': (context) => const ConnectionWidget(),
        '/control': (context) => const ControlScreen(),
        '/media': (context) => const ControlScreen2(),
        '/system': (context) => const SystemScreen(),
        '/apps': (context) => const AppScreen(),
        '/stream':(context) => const StreamWidget(),
        '/docs': (context) => const DocsScreen(),
        '/blocked-sites': (context) => const BlockedSitesScreen(),
      },
    );
  }
}
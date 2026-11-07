import 'package:flutter/material.dart';

import 'browser/browser_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const CalmIgApp());
}

class CalmIgApp extends StatelessWidget {
  const CalmIgApp({super.key, this.home});

  /// Overrides the first screen (tests).
  final Widget? home;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '清醒IG',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.teal),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.teal,
        brightness: Brightness.dark,
      ),
      home: home ?? const BrowserPage(),
    );
  }
}

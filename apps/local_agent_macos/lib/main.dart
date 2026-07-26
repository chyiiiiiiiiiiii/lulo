import 'package:flutter/material.dart';

void main() {
  runApp(const LocalAgentApp());
}

/// The intentional empty shell used to establish the macOS build baseline.
class LocalAgentApp extends StatelessWidget {
  /// Creates the application shell.
  const LocalAgentApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'Flutter Local Agent',
      home: Scaffold(body: Center(child: Text('Flutter Local Agent'))),
    );
  }
}

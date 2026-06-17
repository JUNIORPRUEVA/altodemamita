import 'package:flutter/material.dart';

import 'app/app_shell.dart';
import 'app/app_theme.dart';

void main() {
  runApp(const OwnerApp());
}

class OwnerApp extends StatelessWidget {
  const OwnerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Sistema Solares Owner',
      theme: appTheme,
      home: const AppShell(),
    );
  }
}

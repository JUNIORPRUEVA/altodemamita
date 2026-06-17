import 'package:flutter/material.dart';

// Placeholder for app shell (drawer / bottom nav)
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: child);
  }
}

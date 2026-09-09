import 'package:flutter/material.dart';

typedef DesktopDetailBuilder = Widget Function();

class DesktopDetailScope extends InheritedWidget {
  const DesktopDetailScope({
    super.key,
    required this.open,
    required this.close,
    required this.enabled,
    required super.child,
  });

  final void Function(DesktopDetailBuilder builder) open;
  final VoidCallback close;
  final bool enabled;

  static DesktopDetailScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<DesktopDetailScope>();
  }

  static bool openIfAvailable(
    BuildContext context,
    DesktopDetailBuilder builder,
  ) {
    final scope = maybeOf(context);
    if (scope == null || !scope.enabled) return false;
    scope.open(builder);
    return true;
  }

  @override
  bool updateShouldNotify(DesktopDetailScope oldWidget) {
    return enabled != oldWidget.enabled ||
        open != oldWidget.open ||
        close != oldWidget.close;
  }
}

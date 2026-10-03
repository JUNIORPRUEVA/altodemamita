import 'package:flutter/material.dart';

class ShellLayoutScope extends InheritedWidget {
  const ShellLayoutScope({super.key, required super.child});

  static bool isActive(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<ShellLayoutScope>() !=
        null;
  }

  @override
  bool updateShouldNotify(covariant InheritedWidget oldWidget) => false;
}

class BaseLayout extends StatelessWidget {
  final String title;
  final Widget child;
  final bool showPageTitle;
  final double? appBarToolbarHeight;
  final bool centerTitle;
  final EdgeInsetsGeometry contentPadding;

  const BaseLayout({
    super.key,
    required this.title,
    required this.child,
    this.showPageTitle = true,
    this.appBarToolbarHeight,
    this.centerTitle = true,
    this.contentPadding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) {
    final inShell = ShellLayoutScope.isActive(context);
    final paddedChild = Padding(padding: contentPadding, child: child);

    if (inShell) {
      return SizedBox.expand(child: paddedChild);
    }

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // El titulo ya se muestra en el AppBar de esta misma pantalla: no se
        // repite dentro del cuerpo (evita el efecto de "dos appbar").
        Expanded(child: paddedChild),
      ],
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        centerTitle: centerTitle,
        toolbarHeight: appBarToolbarHeight,
      ),
      body: content,
    );
  }
}

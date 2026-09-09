import 'package:flutter/material.dart';

import '../app/responsive.dart';

class OwnerDesktopPageFrame extends StatelessWidget {
  const OwnerDesktopPageFrame({
    super.key,
    required this.child,
    this.maxWidth = 1180,
    this.mobileHorizontalPadding = 16,
  });

  final Widget child;
  final double maxWidth;
  final double mobileHorizontalPadding;

  @override
  Widget build(BuildContext context) {
    if (!Responsive.isDesktop(context)) {
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: mobileHorizontalPadding),
        child: child,
      );
    }

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: child,
        ),
      ),
    );
  }
}

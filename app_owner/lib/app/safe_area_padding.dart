import 'dart:math' as math;

import 'package:flutter/material.dart';

double mobileSafeBottomPadding(BuildContext context, {double base = 24}) {
  final media = MediaQuery.of(context);
  final safeBottom = math.max(media.padding.bottom, media.viewPadding.bottom);
  return base + safeBottom;
}

EdgeInsets safeScrollPadding(
  BuildContext context, {
  double left = 16,
  double top = 16,
  double right = 16,
  double bottom = 24,
}) {
  return EdgeInsets.fromLTRB(
    left,
    top,
    right,
    mobileSafeBottomPadding(context, base: bottom),
  );
}

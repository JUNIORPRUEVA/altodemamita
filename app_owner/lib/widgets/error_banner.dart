import 'package:flutter/material.dart';

import '../app/app_colors.dart';
import '../core/error_messages.dart';

class ErrorBanner extends StatelessWidget {
  const ErrorBanner({super.key, required this.error});

  final Object? error;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF7F6),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFF2D3CF), width: 0.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.info_outline_rounded,
                size: 18,
                color: Color(0xFFB3261E),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  friendlyErrorMessage(error),
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 1.25,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

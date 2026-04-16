import 'package:flutter/material.dart';

import 'feature_page_scaffold.dart';

class ModulePlaceholderPage extends StatelessWidget {
  const ModulePlaceholderPage({
    super.key,
    required this.title,
    required this.description,
    this.nextSteps = const [],
  });

  final String title;
  final String description;
  final List<String> nextSteps;

  @override
  Widget build(BuildContext context) {
    return FeaturePageScaffold(
      title: title,
      subtitle: 'Módulo preparado para la siguiente fase.',
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(description),
              if (nextSteps.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  'Pendiente en la siguiente iteración',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                for (final item in nextSteps)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text('• $item'),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

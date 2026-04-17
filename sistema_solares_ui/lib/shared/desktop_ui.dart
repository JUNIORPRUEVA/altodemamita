import 'package:flutter/material.dart';

const _desktopInk = Color(0xFF0D2640);
const _desktopMuted = Color(0xFF6A7684);
const _desktopOutline = Color(0xFFE4EAF2);
const _desktopSurface = Colors.white;

class DesktopPageScaffold extends StatelessWidget {
  const DesktopPageScaffold({
    super.key,
    required this.title,
    this.subtitle,
    this.toolbar,
    this.child,
  });

  final String title;
  final String? subtitle;
  final Widget? toolbar;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 760;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style:
                    (compact
                            ? Theme.of(context).textTheme.titleLarge
                            : Theme.of(context).textTheme.headlineSmall)
                        ?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: _desktopInk,
                        ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle!,
                  style: TextStyle(
                    color: _desktopMuted,
                    fontSize: compact ? 12 : 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (toolbar != null) ...[toolbar!, SizedBox(height: compact ? 12 : 16)],
        Expanded(child: child ?? const SizedBox.shrink()),
      ],
    );
  }
}

class DesktopSurface extends StatelessWidget {
  const DesktopSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.radius = 20,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 760;

    return Container(
      decoration: BoxDecoration(
        color: _desktopSurface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: _desktopOutline),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D000000),
            blurRadius: 20,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: compact ? const EdgeInsets.all(16) : padding,
        child: child,
      ),
    );
  }
}

class DesktopToolbar extends StatelessWidget {
  const DesktopToolbar({
    super.key,
    required this.searchField,
    this.actions = const [],
    this.compactActions = const [],
  });

  final Widget searchField;
  final List<Widget> actions;
  final List<Widget> compactActions;

  @override
  Widget build(BuildContext context) {
    final veryCompact = constraintsFor(context) < 560;

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 900;
        final rowActions = compact ? compactActions : actions;

        if (compact) {
          return Padding(
            padding: EdgeInsets.symmetric(
              horizontal: veryCompact ? 12 : 16,
              vertical: 12,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                searchField,
                if (rowActions.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  ...rowActions.map(
                    (action) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: SizedBox(width: double.infinity, child: action),
                    ),
                  ),
                ],
              ],
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Expanded(child: searchField),
              if (rowActions.isNotEmpty) ...[
                const SizedBox(width: 16),
                Wrap(spacing: 8, runSpacing: 8, children: rowActions),
              ],
            ],
          ),
        );
      },
    );
  }

  double constraintsFor(BuildContext context) =>
      MediaQuery.sizeOf(context).width;
}

class DesktopSearchField extends StatelessWidget {
  const DesktopSearchField({
    super.key,
    required this.controller,
    required this.hintText,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      child: TextField(
        controller: controller,
        style: const TextStyle(fontSize: 14, color: _desktopInk),
        onSubmitted: onSubmitted,
        decoration: InputDecoration(
          hintText: hintText,
          prefixIcon: const Icon(Icons.search, size: 18),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
        ),
      ),
    );
  }
}

class DesktopEmptyState extends StatelessWidget {
  const DesktopEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F3F9),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: const Color(0xFFD8E0EB)),
                ),
                child: Icon(icon, size: 36, color: _desktopInk),
              ),
              const SizedBox(height: 18),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: _desktopInk,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  color: _desktopMuted,
                  height: 1.45,
                ),
              ),
              if (action != null) ...[const SizedBox(height: 20), action!],
            ],
          ),
        ),
      ),
    );
  }
}

class DesktopModuleList extends StatelessWidget {
  const DesktopModuleList({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _desktopSurface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _desktopOutline),
      ),
      child: ListView.separated(
        padding: EdgeInsets.zero,
        itemCount: children.length,
        separatorBuilder: (_, _) =>
            const Divider(height: 1, indent: 72, endIndent: 16),
        itemBuilder: (context, index) => children[index],
      ),
    );
  }
}

class DesktopPlainSection extends StatelessWidget {
  const DesktopPlainSection({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
  });

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 760;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            compact ? 0 : 4,
            0,
            compact ? 0 : 4,
            compact ? 12 : 14,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: compact ? 18 : 20,
                    fontWeight: FontWeight.w700,
                    color: _desktopInk,
                  ),
                ),
              ),
              ...(trailing != null ? <Widget>[trailing!] : const <Widget>[]),
            ],
          ),
        ),
        child,
      ],
    );
  }
}

class DesktopListRow extends StatelessWidget {
  const DesktopListRow({
    super.key,
    required this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.height = 72,
  });

  final Widget leading;
  final Widget title;
  final Widget? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final double height;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 760;
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: compact ? height + 10 : height,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 14 : 18,
            vertical: compact ? 8 : 0,
          ),
          child: compact
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        leading,
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              title,
                              if (subtitle != null) ...[
                                const SizedBox(height: 4),
                                subtitle!,
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (trailing != null) ...[
                      const SizedBox(height: 10),
                      Align(alignment: Alignment.centerLeft, child: trailing!),
                    ],
                  ],
                )
              : Row(
                  children: [
                    leading,
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          title,
                          if (subtitle != null) ...[
                            const SizedBox(height: 2),
                            subtitle!,
                          ],
                        ],
                      ),
                    ),
                    if (trailing != null) ...[
                      const SizedBox(width: 10),
                      trailing!,
                    ],
                  ],
                ),
        ),
      ),
    );
  }
}

class DesktopFieldToolbar extends StatelessWidget {
  const DesktopFieldToolbar({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 760;

    if (compact) {
      return child;
    }

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFAFBFC),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _desktopOutline),
      ),
      child: child,
    );
  }
}

class DesktopDataListSection extends StatelessWidget {
  const DesktopDataListSection({
    super.key,
    required this.title,
    required this.children,
    this.trailing,
  });

  final String title;
  final List<Widget> children;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return DesktopPlainSection(
      title: title,
      trailing: trailing,
      child: DesktopModuleList(children: children),
    );
  }
}

class DesktopInfoStrip extends StatelessWidget {
  const DesktopInfoStrip({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 760;

    if (compact) {
      return child;
    }

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFAFBFC),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _desktopOutline),
      ),
      child: Padding(padding: const EdgeInsets.all(20), child: child),
    );
  }
}

class DesktopStackedStat extends StatelessWidget {
  const DesktopStackedStat({
    super.key,
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 150),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _desktopSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _desktopOutline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: _desktopMuted)),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              color: _desktopInk,
            ),
          ),
        ],
      ),
    );
  }
}

class DesktopTag extends StatelessWidget {
  const DesktopTag({
    super.key,
    required this.label,
    required this.background,
    this.foreground = const Color(0xFF223048),
  });

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 760;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 12 : 10,
        vertical: compact ? 8 : 6,
      ),
      decoration: BoxDecoration(
        color: background,
        border: Border.all(color: foreground.withValues(alpha: 0.16)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foreground,
          fontWeight: FontWeight.w700,
          fontSize: compact ? 13 : 12,
        ),
      ),
    );
  }
}

class DesktopMetricStrip extends StatelessWidget {
  const DesktopMetricStrip({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 760;
    return Wrap(
      spacing: compact ? 10 : 14,
      runSpacing: compact ? 10 : 14,
      children: children,
    );
  }
}

class DesktopCompactSurface extends StatelessWidget {
  const DesktopCompactSurface({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _desktopSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _desktopOutline),
      ),
      child: child,
    );
  }
}

class DesktopTableCard extends StatelessWidget {
  const DesktopTableCard({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
  });

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return DesktopSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: _desktopInk,
                  ),
                ),
              ),
              ...(trailing != null ? <Widget>[trailing!] : const <Widget>[]),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class DesktopMetricCard extends StatelessWidget {
  const DesktopMetricCard({
    super.key,
    required this.title,
    required this.value,
    required this.color,
  });

  final String title;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 760;
    final compactWidth = (MediaQuery.sizeOf(context).width - 56)
        .clamp(220.0, 420.0)
        .toDouble();

    return Container(
      width: compact ? compactWidth : null,
      constraints: compact
          ? null
          : const BoxConstraints(minWidth: 210, maxWidth: 260),
      decoration: BoxDecoration(
        color: _desktopSurface,
        borderRadius: BorderRadius.circular(compact ? 18 : 20),
        border: Border.all(color: _desktopOutline),
      ),
      child: Padding(
        padding: EdgeInsets.all(compact ? 14 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(height: 14),
            Text(title, style: const TextStyle(color: _desktopMuted)),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: compact ? 22 : 24,
                fontWeight: FontWeight.w800,
                color: _desktopInk,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class DesktopPageError extends StatelessWidget {
  const DesktopPageError({
    super.key,
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 760;

    return Center(
      child: DesktopSurface(
        radius: compact ? 18 : 20,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline,
                size: 40,
                color: Color(0xFFA53F2B),
              ),
              const SizedBox(height: 16),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: _desktopInk),
              ),
              const SizedBox(height: 16),
              FilledButton(onPressed: onRetry, child: const Text('Reintentar')),
            ],
          ),
        ),
      ),
    );
  }
}

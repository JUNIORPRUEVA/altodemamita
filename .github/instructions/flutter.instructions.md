---
description: "Use when editing Flutter/Dart code in this repository (screens, widgets, state, models, routing, platform folders, tests). Covers the real Flutter commands, state/data rules, UI quality gates, and build constraints of this project."
applyTo: "app_local/**", "app_owner/**"
---

# Flutter rules

Installed because this repository contains Flutter code at `app_local`.

## Commands (verify before use — they are the project's real commands)

| Action | Command | Working directory |
| --- | --- | --- |
| Dependencies | `flutter pub get` | `app_local` |
| Static analysis | `flutter analyze` | `app_local` |
| Tests | `flutter test` | `app_local` |
| Scoped test | `flutter test test/<path>_test.dart` | `app_local` |
| Build | `TODO (verify: command for the real target)` | `app_local` |

Never invent an alternative command. If a command in this table is wrong for this project, fix the table.

## Architecture rules

- Keep UI, state, and data separated. Business logic does not live inside widgets.
- The state layer is the single source of truth for screen data. Do not keep per-screen copies of server data and do not "fix" a state problem with a forced rebuild.
- Dynamic data comes from the backend. No hardcoded catalog, pricing, company, or user data in the client.
- Models: keep the project's serialization approach consistent. Changing a JSON key or a field type requires checking the backend contract **and** data persisted/cached on devices (old builds and caches must keep parsing, or the change must be reported as breaking).
- Preserve the routing, navigation, and auth/session behavior unless the task explicitly changes them.

## UI quality gates

- Reuse the project's design system, shared widgets, and theme tokens. No arbitrary spacing, radius, color, or font sizes.
- Check: overflow, truncation, contrast, touch target size, responsive behavior, real text length, loading / error / empty states.
- Hide sections that are irrelevant to the current state; do not sacrifice usability for decoration.
- Do not change business logic during a visual redesign unless requested.
- Keep user-facing text in the product's existing language and tone.

## Performance

- Avoid unnecessary rebuilds and heavy work inside `build()`.
- Keep long lists efficient (lazy building, keys, const where possible).
- Do not add an image/asset pipeline change without measuring its effect.

## Tests

- Widget/unit tests live where the project already puts them. Add tests next to the change when the behavior is testable without hardware.
- Responsive/layout tests: use the project's existing technique; do not assume a surface-size API works in this Flutter version — verify.
- Never point the app at production data for validation. Prefer local/dev/UAT targets.
- Hardware-dependent behavior (printer, drawer, scale, scanner) cannot be closed with automated tests alone.

## Gotchas

- Do not delete `.dart_tool`, run `flutter clean`, or bump dependency versions unless a real corruption or incompatibility has been proven and reported.
- After a dependency change, run `flutter pub get` and re-run analysis and tests.
- Do not commit debug prints, temporary logs, or commented-out UI experiments.

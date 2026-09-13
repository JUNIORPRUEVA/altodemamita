# SISTEMASOLARES PWA / Mobile Responsive

Status: PHASE 0 (AUDIT) COMPLETE. PHASE 1 (RESPONSIVE FOUNDATION) IMPLEMENTED LOCALLY.

This document does NOT claim that Flutter Web or the PWA is working. Web
enablement is blocked behind an explicit architecture decision; see
"Bloqueos y decision pendiente".

Production was not touched. `app_owner` was not touched. No backend, database,
schema, business rule, or API contract was changed.

## Scope Boundary

| Area | Status |
| --- | --- |
| `app_local` Windows | REGRESSION CRITICAL - must keep working unchanged |
| `app_local` responsive foundation | IMPLEMENTED LOCALLY (additive) |
| `app_local` Flutter Web | NOT ENABLED / NOT TESTED |
| PWA manifest / service worker | NOT IMPLEMENTED |
| `app_owner` | NOT TOUCHED |
| `backend/` | NOT TOUCHED |
| Production | NOT TOUCHED |

## Measured Baseline

Environment:

- Flutter 3.41.6 stable, Dart 3.11.4, `environment.sdk: ^3.10.1`
- `enable-web: (Not set)`, `enable-windows-desktop: true`
- Devices available: Windows desktop, Android emulator, Chrome, Edge

Commands run before any change:

```text
flutter analyze   -> No issues found!
flutter test      -> 473 passed, 9 failed (PRE-EXISTING, see below)
```

The 9 pre-existing failures are all sync download/cursor/conflict tests and are
NOT caused by this phase:

```text
sync_download_does_not_redownload_same_batch_test.dart
sync_download_does_not_redownload_same_batch_test.dart (tombstones before active)
sales_offline_sync_flow_test.dart (edita venta offline)
sales_offline_sync_flow_test.dart (borra venta offline)
sync_download_uses_scope_cursors_test.dart
sync_full_download_rehydrates_missing_sales_test.dart
sync_queue_conflict_recovery_download_test.dart
sync_queue_sales_conflict_blocks_dependent_installments_test.dart
tombstone_download_ignores_advanced_cursor_when_force_full_test.dart
```

Any later phase must be compared against this exact baseline.

### 1. Estado actual

```text
WEB READY: NO
```

`app_local` is a SQLite-first Windows application. Its operational data source
is the local `sistema_solares.db`. Flutter Web has never been enabled for this
project.

### 2. Flutter Web

```text
ENABLED: NO
CURRENT BUILD: NOT POSSIBLE (no web/ directory, no web platform registered)
```

`app_local/web/` does not exist and is not listed as an enabled platform
(`android`, `windows` only).

### 3. Dependencias y APIs incompatibles con Web

| dependency / API | usage | platform | risk | recommended strategy |
| --- | --- | --- | --- | --- |
| `sqflite_common_ffi` / `databaseFactoryFfi` | `app_database.dart`, `cloud_foundation_databases.dart`, backup agents, migration tool | Windows/Android/desktop only | ALTO | Abstraction + `sqflite_common_ffi_web` (IndexedDB-backed SQLite) behind a conditional import, so repository code is unchanged |
| `sqlite3_flutter_libs` | native sqlite3 bundling | native only | ALTO | Keep for native. Web needs the `sqlite3.wasm` asset served by `sqflite_common_ffi_web`. `sqlite3` is pinned to `3.2.0` via `dependency_overrides`; the web package must be verified against that pin |
| `dart:io` `HttpClient` | `cloud_api_client.dart`, `backend_http_client.dart`, `sync_api_client.dart`, `auth_service.dart`, `initial_cloud_upload_service.dart` | Web incompatible | ALTO | Conditional import producing an `http.Client`; keep `IOClient`/`HttpClient` on native so Windows behavior is byte-identical |
| `dart:io` `Platform.environment` | `app_paths.dart` (constructed in `main()`) | Web incompatible | ALTO | Conditional import: Windows/desktop paths vs. web in-memory storage |
| `dart:io` (all uses) | 174 references across 34 files | Web incompatible | ALTO | See the specific rows below |
| `dart:io` `File` / `Directory` | backup, professional backup, restore, validators, loggers, `app_database`, `lot_repair_service`, `company_info_page`, `sync_diagnostics_logger` | Web incompatible | ALTO | Feature-level abstraction. Backup/restore is meaningless in a browser: disable + hide, do not emulate |
| `dart:io` `InternetAddress.lookup` | `clients_page.dart`, `sales_page.dart` (connectivity probe) | Web incompatible | MEDIO | Replace with an API/`connectivity_plus` based probe behind an abstraction |
| `dart:io` `SocketException` | error mapping (`friendly_error_messages.dart`, controllers) | Web incompatible (type reference) | MEDIO | Conditional import for the exception type mapping |
| `printing` / `PrinterRepository` (`Printing.listPrinters`, `Printing.info`) | `printer_repository.dart`, `printers_page.dart`, `printer_form_dialog.dart` | Printing supports web, printer listing does not | MEDIO | Keep `Printing.layoutPdf` (works on web); guard printer discovery so it degrades cleanly |
| `pdf` | receipt/pagare/amortization builders | WEB COMPATIBLE | BAJO | No change |
| `file_picker` | `company_info_page.dart` (logo) | WEB COMPATIBLE | BAJO | No change |
| `flutter_secure_storage` | `sensitive_storage.dart` | WEB COMPATIBLE | BAJO | Already abstracted behind `SensitiveStorage` |
| `shared_preferences` | settings, device id, shell prefs | WEB COMPATIBLE | BAJO | No change |
| `connectivity_plus` | `app_shell.dart`, list pages | WEB COMPATIBLE | BAJO | No change |
| `socket_io_client` | `realtime_sync_service.dart` | WEB COMPATIBLE | MEDIO | Verify transport behavior under browser WebSocket |
| `path`, `crypto`, `bcrypt`, `archive`, `provider`, `intl`, `http` | general | WEB COMPATIBLE | BAJO | No change |
| `Platform.isWindows` | `app_shell.dart`, `app_paths.dart`, `disk_detection_service.dart` | Web incompatible | MEDIO | Already partially guarded; route through `defaultTargetPlatform`/`kIsWeb` helpers |
| `Process.run` (`explorer`, `powershell`, `fsutil`, `open`, `xdg-open`) | `disk_detection_service.dart` | Windows/desktop only | MEDIO | Feature-level: backup disk helpers are desktop-only by design |

### 4. Arquitectura responsive actual

```text
PARTIAL / POOR
```

Evidence:

- `LayoutBuilder` used in 29 places, `MediaQuery.*` in 8, `SafeArea` in 5.
- No centralized breakpoint system. 66 `maxWidth`/`minWidth`-style literals.
- 92 hard-coded 3-4 digit `width:` literals, mostly fixed table columns.
- No `DataTable`/`PaginatedDataTable` usage; tables are hand-built `Row`s with
  fixed-width columns (`installments_flat_table.dart` is the clearest example).
- Only 2 `kIsWeb` occurrences, both about Windows-only desktop behaviors.
- Desktop shell is a hand-rolled sidebar (96 collapsed / 288 expanded) in
  `app_shell.dart` (1955 lines).

There is no accidental global scaling (`Transform.scale` / `FittedBox`) to undo.

### 5. Número real de pantallas

```text
TOTAL ROUTES:       0 named routes (6 Navigator.push* call sites, all imperative)
TOTAL SCREENS:      17 *_page.dart + 15 dialogs/sheets
MOBILE READY:       0
NEEDS ADAPTATION:   32
```

Screens and their sizes (lines):

```text
3055  features/sales/presentation/sale_form_dialog.dart
2657  features/payments/presentation/payments_page.dart
1955  app/navigation/app_shell.dart
1515  features/settings/presentation/documentation_page.dart
1261  features/sales/presentation/sale_detail_dialog.dart
1171  features/settings/presentation/users_screen.dart
1165  features/backup/presentation/backup_page.dart
1160  features/sales/presentation/sales_page.dart
1099  features/payments/presentation/payment_history_fullscreen.dart
 960  features/dashboard/presentation/dashboard_page.dart
 954  features/payments/presentation/receipt/receipt_view.dart
 936  features/payments/presentation/payment_form_dialog.dart
 783  features/auth/presentation/login_screen.dart
 742  shared/widgets/recovery_experience.dart
 684  features/payments/presentation/reports/client_pagare_pdf_builder.dart
 666  features/global_search/presentation/search_result_dialog.dart
 618  features/installments/presentation/installments_page.dart
 598  features/sales/presentation/documents/sale_documents_dialog.dart
 573  features/settings/presentation/settings_page.dart
 567  features/global_search/presentation/global_search_page.dart
 545  features/sales/presentation/sellers_page.dart
 531  features/clients/presentation/clients_page.dart
 521  features/backup/presentation/backup_controller.dart
 509  features/payments/presentation/reports/client_pagare_dialog.dart
 496  features/settings/presentation/printers_page.dart
 491  features/payments/presentation/receipt/receipt_dialog.dart
 485  features/lots/presentation/lots_page.dart
 473  features/settings/presentation/company_info_page.dart
 447  features/settings/presentation/users_page.dart
 444  features/payments/presentation/receipt/receipt_pdf_builder.dart
 432  features/auth/presentation/auth_provider.dart
 412  features/auth/presentation/bootstrap_admin_screen.dart
 402  features/auth/presentation/profile_screen.dart
 400  features/auth/presentation/admin_override_prompt.dart
 375  features/sales/presentation/seller_detail_dialog.dart
 372  features/sales/presentation/sales_controller.dart
 357  features/sales/presentation/documents/sale_initial_receipt_pdf_builder.dart
 350  features/settings/presentation/financial_params_page.dart
 342  features/payments/presentation/payments_controller.dart
 337  features/sales/presentation/documents/sale_amortization_pdf_builder.dart
 333  features/payments/presentation/payment_annul_dialog.dart
 330  features/settings/presentation/printer_form_dialog.dart
 268  features/sales/presentation/widgets/installments_flat_table.dart
 246  features/lots/presentation/lot_form_dialog.dart
 188  shared/widgets/dangerous_action_confirm_dialog.dart
 152  features/settings/presentation/user_form_dialog.dart
 147  features/clients/presentation/client_form_dialog.dart
 142  shared/widgets/module_list_states.dart
 135  features/sales/presentation/seller_form_dialog.dart
 133  features/installments/presentation/installments_controller.dart
 102  features/backup/presentation/backup_lifecycle_observer.dart
  90  features/clients/presentation/clients_controller.dart
  81  app/navigation/app_module.dart
  75  app/navigation/sync_visual_state.dart
  63  features/lots/presentation/lots_controller.dart
  61  shared/widgets/base_layout.dart
  49  shared/widgets/feature_page_scaffold.dart
  45  features/payments/presentation/receipt/receipt_controller.dart
  44  shared/widgets/module_placeholder_page.dart
  24  features/settings/presentation/backup_page.dart
  15  features/sales/presentation/sellers_controller.dart
```

Navigation is a fixed module list, not routes:

```text
AppModule: dashboard, sales, globalSearch, clients, lots, payments,
           installments, sellers, settings
Sidebar primary: Resumen, Ventas, Buscador, Pagos
Sidebar administration: Clientes, Solares, Cuotas, Vendedores
```

### 6. Riesgos para Windows

1. Any `pubspec.yaml` dependency change re-resolves the whole graph. The
   existing `dependency_overrides: sqlite3: ^3.2.0` plus
   `sqlite3_flutter_libs 0.5.42` is the exact combination that produces the
   Windows native `sqlite3.dll` used by the shipping app. Adding a web SQLite
   package can perturb that resolution. HIGH.
2. Enabling the web platform (`flutter create --platforms=web .`) adds
   `web/` but must not touch `windows/`. Must be verified after running.
3. Replacing `dart:io HttpClient` with `package:http` in the shared network
   layer would change Windows connection/TLS behavior
   (`badCertificateCallback`, timeouts). Conditional imports are mandatory;
   a straight replacement is a NO-GO.
4. `AppPaths` is constructed in `main()` before `runApp`. Making it
   platform-conditional must not change Windows path computation
   (`LOCALAPPDATA\SistemaSolares\...`, `D:\FULLPOS_BACKUPS`).
5. Touch points that are Windows-regression critical and must not be
   restructured: `app_shell.dart`, `base_layout.dart`, `app_database.dart`,
   `backend_http_client.dart`, `sync_service.dart`, `sync_queue_service.dart`,
   and all 168 existing test files.

### 7. Riesgos para PWA

1. `dart:io` is used in 34 files (174 references) for filesystem, process, and
   network. The app cannot boot on web until `AppPaths` and the network layer
   are abstracted.
2. The local SQLite database is the operational store. Without a web store
   there is no data layer in the browser at all.
3. Backup, professional backup, restore, disk detection, and printer discovery
   have no browser equivalent. They must be hidden/disabled on web, not faked.
4. Backend CORS is currently `app.use(cors({ origin: true, credentials: true }))`
   in `backend/src/app.ts:18`, which reflects any origin while allowing
   credentials. Acceptable for local development, NOT acceptable for a public
   PWA. An environment allowlist is required before any PWA deployment.
5. The backend also has documented gaps (sync routes not mounted with
   `authGuard`/`syncGuard`; local app calls `/auth/refresh` which the backend
   does not define). A browser client makes these gaps externally reachable.
6. Nothing secret may be embedded in the web bundle. Everything compiled into
   Flutter Web is inspectable by the user.

### 8. Estrategia recomendada

Non-negotiable rule: the desktop branch must remain literally the existing
widget tree. New code is additive and selected by width.

```text
lib/core/responsive/           <- implemented in this phase
  app_breakpoints.dart         centralized thresholds + predicates
  responsive_layout.dart       ResponsiveLayout / ResponsiveBuilder / ContentBox
  responsive_page.dart         page padding / form container / card grid
  responsive_dialog.dart       responsive dialog + sheet + confirm
  responsive_table.dart        table-vs-cards strategy + record card

lib/app/navigation/
  mobile_navigation_shell.dart <- implemented in this phase (not yet wired)
```

Breakpoints (`AppBreakpoints`), derived from the real desktop sidebar widths so
that >= 1024 keeps the existing desktop layout:

```text
mobileCompact  < 360
mobile         360 - 599
tablet         600 - 1023
desktop        1024 - 1439
wideDesktop    >= 1440

isMobile  -> < 600
isTablet  -> 600 - 1023
isDesktop -> >= 1024   (desktop branch = existing implementation)
```

Screen pattern:

```dart
ResponsiveLayout(
  desktop: (_) => const ExistingDesktopScreen(), // unchanged
  mobile: (_) => const MobileOptimizedScreen(),
)
```

Data layer decision (BLOCKING, requires explicit authorization):

```text
Option A: sqflite_common_ffi_web (IndexedDB-backed SQLite WASM)
          -> reuses ALL existing repositories and services unchanged
          -> highest reuse, matches "mismos servicios"
          -> requires pubspec change (Windows risk, see 6.1)

Option B: API-only web data layer
          -> PWA becomes an online-first client of the backend
          -> no offline/outbox parity in the first iteration
          -> large new code surface, diverges from the shared-services goal
```

Option A is recommended, but it must not be started until the `sqlite3`
resolution is verified to keep Windows on the same native DLL.

### 9. Archivos que habría que modificar (phases 2-4, not yet started)

```text
app_local/pubspec.yaml                     (web deps - Windows risk)
app_local/web/**                           (new platform folder)
app_local/lib/main.dart                    (bootstrap guards)
app_local/lib/core/resilience/app_paths.dart
app_local/lib/core/database/app_database.dart
app_local/lib/core/cloud_foundation/cloud_foundation_databases.dart
app_local/lib/core/network/backend_http_client.dart
app_local/lib/core/cloud_foundation/cloud_api_client.dart
app_local/lib/services/sync/sync_api_client.dart
app_local/lib/services/sync/sync_service.dart
app_local/lib/services/sync/sync_queue_service.dart
app_local/lib/services/sync/initial_cloud_upload_service.dart
app_local/lib/features/auth/data/auth_service.dart
app_local/lib/core/resilience/friendly_error_messages.dart
app_local/lib/core/resilience/incident_logger.dart
app_local/lib/core/diagnostics/sync_diagnostics_logger.dart
app_local/lib/core/system/system_config_service.dart
app_local/lib/app/navigation/app_shell.dart
app_local/lib/shared/widgets/base_layout.dart
app_local/lib/features/**/presentation/**_page.dart
app_local/lib/features/**/presentation/**_dialog.dart
app_local/lib/features/backup/**           (desktop-only features)
app_local/lib/features/settings/presentation/printers_page.dart
app_local/lib/services/professional_backup/**
backend/src/app.ts                          (CORS allowlist - separate approval)
```

### 10. Archivos que NO deben tocarse

```text
backend/prisma/schema.prisma               (no schema change)
backend/src/routes/**, backend/src/services/**  (no logic/contract change)
app_local/lib/core/database/database_schema.dart   (no schema change)
app_local/lib/features/**/data/*_repository.dart   (no business rule change)
app_local/lib/repositories/**                      (no sync contract change)
app_owner/**                               (explicitly out of scope)
business_site/**
dist_release/**
release_artifacts/**
docs/** historical folders (docs/sync, docs/audit)  (history only)
```

## Phase 1 Implemented (additive only)

New files, no existing file modified:

```text
app_local/lib/core/responsive/app_breakpoints.dart
app_local/lib/core/responsive/responsive_layout.dart
app_local/lib/core/responsive/responsive_page.dart
app_local/lib/core/responsive/responsive_dialog.dart
app_local/lib/core/responsive/responsive_table.dart
app_local/lib/app/navigation/mobile_navigation_shell.dart
app_local/test/helpers/responsive_test_harness.dart
app_local/test/app_breakpoints_test.dart
app_local/test/responsive_layout_test.dart
app_local/test/responsive_dialog_test.dart
app_local/test/responsive_table_test.dart
app_local/test/mobile_navigation_shell_test.dart
```

Properties of this phase:

- Nothing is wired into any existing screen yet, so the desktop widget tree is
  unchanged. `ResponsiveLayout` returns the `desktop` builder for
  `>= 1024`, which is the existing implementation.
- `MobileNavigationShell` is not yet used by `app_shell.dart`; it will be wired
  in a later phase behind `AppBreakpoints.usesCompactNavigation`.
- No `pubspec.yaml` change. No web platform. No dependency change.
- No backend, database, business rule, or API contract change.

Tests cover: breakpoint classification and exhaustiveness across all required
widths (320/360/375/390/412/430/768/1024/1366/1920), desktop branch selection,
content width clamping, page padding, form width, card grid columns,
table-vs-cards strategy, record cards, dialog mode selection (centered dialog
vs full screen vs bottom sheet), keyboard insets, iOS safe areas, and
overflow-freedom on every required width.

### Phase 1 Verification (measured)

```text
flutter analyze                          -> No issues found!
flutter test (full suite)                -> 534 passed / 7 failed
existing failures before Phase 1         -> 473 passed / 9 failed
new responsive tests                     -> 57 passed / 0 failed
flutter build windows --release          -> Built build\windows\x64\runner\Release\sistema_solares.exe
```

The 7 remaining failures are the same pre-existing sync suite failures listed
above (the count fluctuates between 7 and 9 because those tests are timing
sensitive; the failing files are the same set). No new failure was introduced.

WINDOWS VISUAL REGRESSION: PASS (no existing file was modified)
WINDOWS FUNCTIONAL REGRESSION: PASS (Windows release build succeeds, analyzer
clean, full suite at or better than baseline)

Backend: NOT CHANGED
Database: NOT CHANGED
Production: NOT TOUCHED

## Bloqueos y decision pendiente

There is no blocker for further *additive* responsive UI work.

There IS a blocking architecture decision before any Web/PWA step:

```text
DECISION REQUIRED: web data layer (Option A vs Option B)
REASON: Option A requires a pubspec/dependency change that can perturb the
        Windows native sqlite3 resolution.
STATUS: WAITING FOR EXPLICIT AUTHORIZATION
```

Nothing Web-related should be started until that decision is made and the
Windows build is re-verified afterwards.

## Next Safe Step

1. Wire `MobileNavigationShell` into `app_shell.dart` behind
   `AppBreakpoints.usesCompactNavigation`, with the desktop branch untouched.
2. Adapt the core screens in priority order (dashboard, lots, clients, sales,
   payments, installments) using `ResponsiveLayout` + `ResponsiveTableSwitch`.
3. Re-run `flutter analyze`, the full `flutter test` suite, and a Windows build
   before declaring any screen PASS.
4. Only after that, request the web data layer decision.

## Phase 2 Implemented - PWA visual polish: sales screen + bottom navigation

Scope: COMPACT LAYOUT ONLY (`< 1024 px`). The desktop layout (`>= 1024`) is not
modified, so the Windows screen keeps its existing design.

Files touched:

```text
app_local/lib/app/navigation/mobile_navigation_shell.dart   (bottom bar redesigned)
app_local/lib/app/navigation/app_shell.dart                 (Ventas = prominent)
app_local/lib/features/sales/presentation/sales_page.dart   (compact AppBar + card)
app_local/lib/features/sales/presentation/widgets/sale_mobile_amounts_row.dart (new)
app_local/lib/core/utils/dominican_formatters.dart          (formatRdMoney helper)
app_local/test/mobile_navigation_shell_test.dart
app_local/test/sale_mobile_amounts_row_test.dart            (new)
app_local/test/widget_test.dart                             (test view size fix)
```

Design rules implemented:

| Requested behavior | Implementation |
| --- | --- |
| Smaller, squarer search field | `height 40`, `borderRadius 8`, `fill #F6F8FB`, `maxWidth 320`, AppBar `toolbarHeight 60` |
| Magnifier inside the field | `prefixIcon` (tappable) + `textInputAction: search`; the external search button was removed |
| List not so bold | mobile card weights reduced `w900/w800 -> w700`; softened colors (`#1F2937`, `#6B7A90`) |
| Active module highlighted | active destination gets a soft rounded background, primary color and bold label |
| Elegant bar, bigger middle icon | white surface + top border + soft shadow; the `prominent` destination (Ventas) renders as a 44 px gradient circle with border and shadow |
| Amounts never truncated | amounts are measured with `TextPainter`; the row reserves the exact width and `FittedBox(scaleDown)` prevents clipping. When `Precio` and `Pend.` do not both fit, only `Pend.` is shown |

`MobileNavigationItem.prominent` is the explicit marker for the highlighted
destination, so the layout does not depend on position/index.

### Phase 2 Verification (measured)

```text
flutter analyze                -> No issues found!
flutter test (full suite)      -> 563 passed / 7 failed
pre-Phase-2 baseline           -> 563 passed / 7 failed (minus the 3 new tests)
new tests                      -> 3 (sale_mobile_amounts_row_test)
flutter build web --release    -> Built build\web
```

The 7 remaining failures are the same pre-existing timing-sensitive sync
download/cursor/conflict tests documented in Phase 1. No new failure was
introduced.

`test/widget_test.dart` was failing before this phase because
`tester.binding.setSurfaceSize()` does not change the real test view size in
this Flutter version: the shell ran at the default 800x600 (compact) surface
while the test expected the desktop shell. It now uses
`test/helpers/responsive_test_harness.dart` (`useTestSize`), which changes
`tester.view.physicalSize` + `devicePixelRatio` and honours the test intent.

WINDOWS VISUAL REGRESSION: PASS (only the `< 1024` branch changed)
WINDOWS FUNCTIONAL REGRESSION: PASS (analyzer clean, suite at baseline)

Backend: NOT CHANGED
Database: NOT CHANGED
Production: NOT TOUCHED
Release artifacts: NOT PUBLISHED

### Risks

- A narrow Windows window (`< 1024 px`) also uses the compact layout, so it
  now shows the redesigned bar and sales card. This is the existing
  breakpoint contract from Phase 1, not a new regression.
- `SaleMobileAmountsRow` measures text with `TextPainter`; system font scaling
  is absorbed by `FittedBox(scaleDown)` instead of truncation.
- The bottom bar height (66 px) has slack for the default text scale. Extremely
  large accessibility text scales should be re-checked visually on device.

### GO / NO-GO

```text
Sales screen (compact/PWA) visual polish  -> GO
Bottom navigation redesign                -> GO
Other compact screens restyle             -> PENDING (same recipe, next phase)
Windows desktop redesign                   -> OUT OF SCOPE / NOT TOUCHED
```

## Detalle de venta como PAGINA completa (PWA / compacto)

Problema reportado: al tocar una venta en la lista, el detalle se abría como
modal y el contenido no cabía en pantalla (se rompía el layout), con demora
percibida antes de ver algo.

Solución implementada:

```text
app_local/lib/features/sales/presentation/sale_detail_page.dart   (nueva pagina)
app_local/lib/features/sales/presentation/sales_page.dart         (enrutado)
app_local/lib/features/sales/presentation/sale_detail_dialog.dart (helper de impresion publico)
```

- El detalle se abre como PANTALLA COMPLETA (`MaterialPageRoute`) en la PWA
  (`kIsWeb`) y en el layout compacto (`< 1024 px`).
- Se abre de inmediato con estado de carga (spinner + nombre de cliente y
  solar) y el detalle se resuelve dentro de la página: ya no hay espera sin
  feedback.
- Contenido ordenado por secciones: identidad (cliente/solar/estado),
  Cliente y solar, Condiciones de venta, Resumen financiero (2 columnas en
  mobile, 3 en >= 600 px), Plan de pagos y Acciones.
- Los dos accesos principales: `Ver cuotas` y `Ver pagos`.
- Los montos NUNCA se recortan (`FittedBox(scaleDown)`), las filas usan
  `Expanded` y la grilla usa `LayoutBuilder`, por lo que no hay desbordes de
  320 px a 834 px.
- NO se muestran identificadores técnicos (ID local, sync ID, UUID).
- Estado de error recuperable (Reintentar) sin detalles técnicos.

Alcance / compatibilidad:

| Plataforma | Detalle |
| --- | --- |
| PWA (web), cualquier ancho | Página completa |
| Windows (app nativa) `>= 1024` | Modal existente, SIN cambios |
| Windows (app nativa) `< 1024` | Página completa (layout compacto) |

Verificación medida:

```text
flutter analyze                 -> No issues found!
flutter test (suite completa)   -> 581 passed / 7 failed (los 7 sync preexistentes)
test/sale_detail_page_test.dart -> 18 passed (secciones, 2 botones, sin IDs,
                                   formato RD$/dd-MM-yyyy, carga, error+reintento,
                                   cierre tras eliminar, overflow 320..834)
flutter build web --release     -> Built build\web
flutter build windows --release -> Built build\windows\x64\runner\Release\sistema_solares.exe
```

Riesgos:

- El modal de escritorio (`SaleDetailDialog`) mantiene sus campos ID local /
  Sync ID, porque Windows no se modifica en esta fase. Si se quiere ocultarlos
  también en Windows, debe aprobarse como fase aparte.
- `sale_detail_dialog.dart` conserva el modal además de exponer
  `printSaleDocument`, para no romper el flujo de escritorio.

```text
Detalle de venta como pagina (PWA/compacto)  -> GO
Windows desktop regression                   -> GO (sin cambios, compila)
```

## P0: Cuotas / Pagos sin overflow + navegacion instantanea

Problemas reportados: la pantalla "Cuotas amortizadas" se rompia (franja de
overflow), el footer de totales no cabia, y "Ver pagos" tardaba en abrir porque
la consulta se resolvia ANTES de navegar.

Cambios:

```text
lib/features/sales/presentation/widgets/installments_flat_table.dart
lib/features/sales/presentation/sale_detail_dialog.dart
lib/features/payments/presentation/payment_history_fullscreen.dart
```

- `InstallmentsFlatTable`: en compacto (`< 1024 px`) la tabla conserva su ancho
  natural de columnas (936 px) dentro de un `Scrollbar` + `SingleChildScrollView`
  HORIZONTAL, con el listado vertical independiente. En escritorio (`>= 1024`)
  se conserva EXACTAMENTE el layout anterior (columnas fijas + última columna
  `Expanded`, sin scroll horizontal).
- `_FullscreenTotalsFooter` (Cuotas) y `_HistoryTotalsFooter` (Pagos): en
  compacto los totales se recorren con scroll horizontal (ningún monto se
  recorta); en escritorio mantienen la fila original con `Spacer`.
- `openSalePaymentsHistory` ahora NAVEGA DE INMEDIATO: se agrego
  `openSalePaymentHistoryById` + `_SalePaymentHistoryLoaderPage`, que empuja la
  ruta en el tap y resuelve `fetchSaleContext` DENTRO de la pantalla (spinner
  con boton de volver y estado de error con reintento). Antes se hacia
  `await fetchSaleContext(...)` y solo despues `Navigator.push`.
- `openInstallmentsFullscreen` no cambia: ya empujaba la ruta de inmediato con
  los datos que la venta ya tenia en memoria (no re-consulta nada).

Tests agregados (`test/installments_and_history_compact_test.dart`, 20):

```text
Cuotas: sin overflow 320/360/375/390/412/430/768
Cuotas: scroll horizontal real (la columna SALDO FINAL se desplaza)
Cuotas: scroll vertical independiente sigue funcionando
Cuotas: en 1024 NO hay scroll horizontal (escritorio intacto, ancho fluido)
Ver cuotas: la pantalla aparece sin esperar carga
Ver pagos: la ruta aparece ANTES de terminar la consulta (gate abierto)
Pagos: historial sin overflow 320..768 y totales legibles
Pagos: error de carga recuperable y sin detalles tecnicos
```

Verificacion medida:

```text
flutter analyze                 -> No issues found!
flutter test (suite completa)   -> 600 passed / 8 failed (sync preexistentes)
targeted mobile tests           -> 52 passed
flutter build web --release     -> Built build\web
flutter build windows --release -> Built build\windows\x64\runner\Release\sistema_solares.exe
```

Pendiente (NO incluido en esta fase):

- Los modulos Clientes, Solares, Pagos (lista), Cuotas (lista), Vendedores y
  Usuarios siguen usando su layout anterior dentro del layout compacto. Hoy
  `responsive_shell_overflow_test` los recorre pero a 800x600 (porque
  `setSurfaceSize` no cambia la vista real), por lo que la validacion a
  320/360/375/390/412/430 de esos modulos sigue PENDIENTE.

## Patron Ventas aplicado a TODOS los modulos (PWA / compacto)

Objetivo: que la PWA se vea uniforme. Todos los modulos usan el mismo lenguaje
visual de Ventas (busqueda compacta con lupa dentro, tarjetas con borde fino y
radio 12, chips suaves, menu `⋮` para acciones secundarias, detalle a pantalla
completa sin identificadores tecnicos).

Componentes compartidos nuevos:

```text
lib/shared/mobile/mobile_ui.dart       (tokens, tarjeta, avatar, chip de estado,
                                        fila de entidad, menu ⋮, estados y refresh)
lib/shared/mobile/mobile_screens.dart  (MobileSearchRow, MobileModuleListView,
                                        MobileDetailScaffold, MobileSection,
                                        MobileInfoRow, acciones y estados de detalle)
```

Vistas mobile por modulo (nuevas, SOLO layout compacto):

```text
lib/features/clients/presentation/clients_mobile.dart
lib/features/lots/presentation/lots_mobile.dart
lib/features/sales/presentation/sellers_mobile.dart
lib/features/installments/presentation/installments_mobile.dart
lib/features/payments/presentation/payments_mobile.dart
```

Cada pagina conserva su layout de escritorio intacto: el branch compacto se
eligio con `AppBreakpoints.usesCompactNavigation(context)` y en `>= 1024 px` se
devuelve exactamente el widget anterior (`BaseLayout`).

| Modulo | Lista compacta | Detalle compacto |
| --- | --- | --- |
| Ventas | ya existente (patron maestro) | pagina completa (`sale_detail_page.dart`) |
| Clientes | avatar + nombre + documento + telefono | Detalle de cliente (datos + registro + acciones) |
| Solares | icono + codigo + area + precio + estado | Detalle de solar (datos + resumen + acciones) |
| Vendedores | avatar + nombre + documento + telefono | Detalle de vendedor (datos + registro + acciones) |
| Cuotas | resumen (financiado/pagado/pendiente + atraso) + lista de cuotas | Detalle de cuota (datos + resumen financiero) |
| Pagos | lista de ventas con cobro pendiente + FAB Registrar pago | historial de pagos a pantalla completa (carga dentro) |

Notas de alcance:

- Cuotas en mobile se muestra como LISTA legible; la tabla con columnas sigue
  disponible en "Cuotas amortizadas" con scroll horizontal intencional.
- En Pagos, tocar una venta abre el historial con `openSalePaymentHistoryById`
  (navegacion inmediata) y el FAB llama al flujo real de registro de pago.
- En los modulos sin filtros reales no se muestra el icono de filtro (no se
  inventan filtros).
- El detalle compacto de Clientes/Solares/Vendedores ofrece Editar/Eliminar;
  si el usuario cancela la confirmacion de borrado, vuelve a la lista.

Tests agregados (`test/mobile_modules_test.dart`, 42):

```text
Clientes/Solares/Vendedores/Cuotas/Pagos: sin desbordes 320/360/375/390/412/430
Contenido visible por modulo (nombre, documento, telefono, codigo, area,
  precio, estado, cuota, vence, monto, pendiente)
Detalles a pantalla completa sin IDs tecnicos y sin modal
Pagos: la lista abre el historial de la venta tocada
Estados: skeleton de carga y vacio confirmado
```

Verificacion medida:

```text
flutter analyze                 -> No issues found!
flutter test (suite completa)   -> 642 passed / 8 failed (sync preexistentes)
test/mobile_modules_test.dart   -> 42 passed
flutter build web --release     -> Built build\web
flutter build windows --release -> Built build\windows\x64\runner\Release\sistema_solares.exe
```

Pendiente de una fase posterior:

- Resumen (dashboard) y Usuarios no se rediseñaron en esta fase.
- El detalle de venta mantiene sus widgets privados equivalentes a los
  compartidos; unificar cuando se toque ese archivo.
- `responsive_shell_overflow_test` sigue corriendo a 800x600 (limitacion de
  `setSurfaceSize`); migrar a `useTestSize` para validar los anchos reales.

## Ajustes de navegacion y pantallas (pedido del operador)

- **Ventas ahora usa el AppBar del shell** con el nombre "Ventas", igual que el
  resto de los modulos. El buscador (con la lupa dentro) y el icono de filtros
  pasaron al cuerpo de la pantalla (`_SalesMobileSearchBar`). Se elimino
  `hideAppBar` para el modulo de ventas.
- **Drawer → Usuarios**: la opcion "Usuarios" abre DIRECTAMENTE la pantalla de
  usuarios (antes abria Configuracion). Esa pantalla tiene lista + detalle
  compactos estilo Ventas (`lib/features/settings/presentation/users_mobile.dart`):
  avatar, nombre, correo, chips de rol/estado, menu `⋮`
  (Editar / Activar-Desactivar / Eliminar), FAB "Nuevo usuario" y codigo de
  recuperacion como acceso secundario.
- **Configuracion en compacto** (`settings_mobile.dart`): lista compacta, sin
  una tarjeta por opcion, alineada a la izquierda y con texto minimo. Se
  ocultaron **Impresoras** y **Respaldo** porque son herramientas de escritorio
  (impresion local y copias a disco) que no aplican en la PWA. Quedan: Empresa,
  Usuarios (admin), Financiero y Documentacion.
- **Mi perfil / Mi cuenta**: se corrigio el efecto de "dos appbar" y la
  duplicacion de texto. Causa raiz: `BaseLayout` dibujaba el titulo tambien
  dentro del cuerpo cuando la pantalla se abre como ruta (no dentro del shell),
  repitiendo el titulo del AppBar. Ahora el titulo se muestra una sola vez, lo
  que beneficia a todas las pantallas que se abren como ruta (Usuarios,
  Documentacion, Empresa, Financiero, Respaldo, Impresoras). Ademas el perfil ya
  no repite Nombre/Correo (estan en la tarjeta de identidad): ahora muestra Rol,
  Estado, Telefono y ultimo cambio de contrasena.

Verificacion medida:

```text
flutter analyze                 -> No issues found!
flutter test (suite completa)   -> 643 passed / 7 failed (sync preexistentes)
flutter build web --release     -> Built build\web
flutter build windows --release -> Built build\windows\x64\runner\Release\sistema_solares.exe
```

## Buscador (Búsqueda Global) en PWA / compacto

Diagnostico previo (lo que estaba mal en movil):

1. El buscador superior era una `Card` con `Padding(20)` y, por debajo de
   980 px, apilaba `TextField` + `Wrap` de botones "Buscar"/"Limpiar": dos
   bloques grandes en vez de una sola linea.
2. La lista de resultados usaba `Card` con `Padding(16)` y un bloque interno
   con `surfaceContainerHighest`; los montos se formateaban con
   `toStringAsFixed(2)` (sin separador de miles: `RD$951537.38`).
3. El detalle se abria con `showDialog` → `Dialog` con
   `maxWidth: 960, maxHeight: 760`. En un telefono el `Dialog` se reduce al
   ancho disponible menos `insetPadding` (~40 px por lado), quedando como una
   **columna angosta flotante**.
4. Dentro del detalle se pintaba `'Venta ID: ${sale['id']}'` y, si faltaban
   datos de manzana/solar, `'Solar #$solarId'`: identificadores internos
   visibles para el cliente.

Cambios aplicados:

- Nuevo `lib/features/global_search/presentation/global_search_mobile.dart`:
  - `GlobalSearchMobileView`: buscador superior de **una sola linea** con la
    lupa **dentro** del campo (`MobileSearchRow`) y la accion de limpiar como
    sufijo alineado; lista de resultados en tarjetas ligeras (avatar, nombre,
    cedula/ubicacion, monto pendiente con separador de miles) y menu `⋮` con
    las acciones secundarias.
  - `SearchResultDetailPage`: detalle a **pantalla completa** por
    `Navigator.push` (`MobileDetailScaffold` = `[←] Detalle [⋮]` + scroll
    vertical). El Buscador es el punto UNICO donde se ve todo lo relacionado
    al cliente/solar, asi que el detalle lista **todas las cuotas** y
    **todos los pagos** en la misma pantalla (sin botones intermedios),
    agrupado en secciones: *Datos de contacto* / *Datos del solar* /
    *Venta* / *Plan de cuotas (N)* / *Pagos registrados (N)* / *Accesos*.
  - Cada fila de cuota muestra numero, vencimiento, monto, capital/interes
    cuando aplica y el chip de estado (Pagada / Parcial / Vencida /
    Pendiente, los mismos helpers que el modulo Cuotas). Cada fila de pago
    muestra concepto, fecha + hora, metodo, ano cuando aplica, referencia y
    monto. Ambas secciones abren con una franja de totales
    (`_DetailStats`): *Pagadas*, *Total del plan*, *Cobrado* y
    *Total recibido*.
  - Sin repeticion de datos: el nombre y la cedula (o el codigo del solar)
    viven solo en la tarjeta de identidad; el monto pendiente agregado solo
    en el chip del encabezado; el solar por fila solo cuando hay mas de una
    venta. Se eliminaron las filas duplicadas (`Nombre`, `Cedula`,
    `Saldo pendiente`, `Cuotas`) y la antigua seccion *Resumen*.
  - Accesos como filas completas (`MobileDetailActionTile`):
    **Ver ventas**, **Ver cuotas**, **Ver pagos**, **Ver cliente**,
    **Ver solar** (seccion *Accesos*, ademas del menu `⋮`).
  - Navegacion **instantanea**: el detalle recibe el resultado ya cargado y se
    empuja sin `await`; los accesos cierran el detalle y delegan
    en los modulos (que cargan dentro de su propia pantalla).
- `global_search_page.dart`: rama compacta que devuelve
  `GlobalSearchMobileView`; en escritorio (>=1024 px) no cambia nada.
  `_openDetail` empuja la pagina en compacto y conserva el dialogo en
  escritorio. Se agrego el estado `_searchFailed` para poder mostrar
  "No pudimos completar la busqueda" + Reintentar.
- Sin identificadores tecnicos: se elimino `'Venta ID: ...'` (ahora
  "Venta N de M"), el fallback `'Solar #id'` y la referencia de pago solo se
  muestra cuando existe. Se aplico tambien al dialogo de escritorio (bug
  compartido).
- Montos con separador de miles en toda la vista (`formatRdMoney`):
  `RD$951,537.38`, nunca `RD$951537.38`.

Verificacion medida:

```text
flutter analyze                         -> No issues found!
flutter test test/global_search_mobile_test.dart -> 37 passed
flutter test (suite completa)           -> 682 passed / 7 failed
                                           (sync preexistentes; el 8vo fallo
                                            es flaky de
                                            sales_offline_sync_flow_test, que
                                            pasa al ejecutarse aislado)
flutter build web --release             -> Built build\web
flutter build windows --release         -> Built build\windows\x64\runner\Release\sistema_solares.exe
```

Cobertura de las pruebas nuevas (`test/global_search_mobile_test.dart`):

- buscador superior en una sola linea, lupa dentro del campo y limpiar alineado;
- estados sin consulta / sin resultados / error con Reintentar;
- lista ordenada con cedula y monto pendiente con separador de miles;
- el detalle abre como pantalla completa (`Dialog` ausente, ocupa el viewport);
- la navegacion ocurre antes de cualquier carga (2 frames, sin `pumpAndSettle`);
- scroll vertical real; secciones claras; montos/fechas correctos;
- **se listan TODAS las cuotas** (120 verificadas una por una) y todos los
  pagos con concepto/fecha/metodo/monto, sin abrir otro modulo;
- **sin repeticion**: nombre, cedula y monto pendiente aparecen una sola vez;
- ausencia de IDs tecnicos;
- los accesos navegan con el `saleId` correcto;
- sin desbordes a 320/360/375/390/412/430/768 (incluye plan de 120 cuotas);
- escritorio a 1024/1280 no usa la navegacion compacta.

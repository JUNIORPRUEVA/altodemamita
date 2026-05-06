import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/resilience/friendly_error_messages.dart';
import '../../../settings/data/company_repository.dart';
import '../../../settings/data/printer_repository.dart';
import '../../../settings/domain/company_info.dart';
import '../../../settings/domain/printer_config.dart';
import '../../domain/sale_detail.dart';
import 'sale_amortization_pdf_builder.dart';
import 'sale_initial_receipt_pdf_builder.dart';

enum SaleDocumentType { initialReceipt, amortization }

class SaleDocumentsDialog {
  static Future<void> show(
    BuildContext context, {
    required SaleDetail detail,
    SaleDocumentType initialType = SaleDocumentType.initialReceipt,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          _SaleDocumentsDialogContent(detail: detail, initialType: initialType),
    );
  }

  static Future<SaleDocumentType?> chooseType(
    BuildContext context, {
    required String title,
  }) {
    return showDialog<SaleDocumentType>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.receipt_long_outlined),
              title: const Text('Recibo'),
              onTap: () => Navigator.of(
                dialogContext,
              ).pop(SaleDocumentType.initialReceipt),
            ),
            ListTile(
              leading: const Icon(Icons.table_chart_outlined),
              title: const Text('Tabla de amortizacion'),
              onTap: () => Navigator.of(
                dialogContext,
              ).pop(SaleDocumentType.amortization),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
  }

  static Future<void> printQuick(
    BuildContext context, {
    required SaleDetail detail,
    required SaleDocumentType type,
  }) async {
    try {
      final runtimeData = await _SaleDocumentRuntimeData.load();
      final bytes = await _buildDocumentBytes(
        detail: detail,
        company: runtimeData.company,
        type: type,
      );
      final fileName = _buildFileName(detail, type);

      if (runtimeData.defaultPrinter != null &&
          runtimeData.defaultPrinter!.hasSystemSelection) {
        final printerRepository = PrinterRepository();
        final systemPrinter = await printerRepository.resolvePrinter(
          runtimeData.defaultPrinter!,
        );
        if (systemPrinter != null) {
          await Printing.directPrintPdf(
            printer: systemPrinter,
            onLayout: (_) async => bytes,
            name: fileName,
            usePrinterSettings: false,
          );
          return;
        }
      }

      await Printing.layoutPdf(onLayout: (_) async => bytes);
    } catch (error) {
      FriendlyErrorMessages.forOperation(
        'imprimir el documento',
        error,
        module: 'ventas',
      );
    }
  }

  static Future<void> exportQuick(
    BuildContext context, {
    required SaleDetail detail,
    required SaleDocumentType type,
  }) async {
    try {
      final runtimeData = await _SaleDocumentRuntimeData.load();
      final bytes = await _buildDocumentBytes(
        detail: detail,
        company: runtimeData.company,
        type: type,
      );
      await Printing.sharePdf(
        bytes: bytes,
        filename: _buildFileName(detail, type),
      );
    } catch (error) {
      FriendlyErrorMessages.forOperation(
        'exportar el documento',
        error,
        module: 'ventas',
      );
    }
  }
}

class _SaleDocumentRuntimeData {
  const _SaleDocumentRuntimeData({
    required this.company,
    required this.defaultPrinter,
  });

  final CompanyInfo company;
  final PrinterConfig? defaultPrinter;

  static Future<_SaleDocumentRuntimeData> load() async {
    final database = await AppDatabase.instance.database;
    final company = await CompanyRepository(database).getCompanyInfo();
    final defaultPrinter = await PrinterRepository().getDefaultPrinter();
    return _SaleDocumentRuntimeData(
      company:
          company ?? CompanyInfo.empty().copyWith(nombre: 'Sistema de Solares'),
      defaultPrinter: defaultPrinter,
    );
  }
}

String _buildFileName(SaleDetail detail, SaleDocumentType type) {
  final saleId = detail.sale.id ?? 0;
  return switch (type) {
    SaleDocumentType.initialReceipt => 'Recibo-Inicial-Venta-$saleId.pdf',
    SaleDocumentType.amortization => 'Tabla-Amortizacion-Venta-$saleId.pdf',
  };
}

Future<Uint8List> _buildDocumentBytes({
  required SaleDetail detail,
  required CompanyInfo company,
  required SaleDocumentType type,
}) {
  return switch (type) {
    SaleDocumentType.initialReceipt => SaleInitialReceiptPdfBuilder.build(
      detail: detail,
      company: company,
      pageFormat: SaleInitialReceiptPdfBuilder.pageFormat.landscape,
    ),
    SaleDocumentType.amortization => SaleAmortizationPdfBuilder.build(
      detail: detail,
      company: company,
      pageFormat: SaleAmortizationPdfBuilder.pageFormat,
    ),
  };
}

class _SaleDocumentsDialogContent extends StatefulWidget {
  const _SaleDocumentsDialogContent({
    required this.detail,
    required this.initialType,
  });

  final SaleDetail detail;
  final SaleDocumentType initialType;

  @override
  State<_SaleDocumentsDialogContent> createState() =>
      _SaleDocumentsDialogContentState();
}

class _SaleDocumentsDialogContentState
    extends State<_SaleDocumentsDialogContent> {
  late final PrinterRepository _printerRepository;
  late SaleDocumentType _selectedType;

  final Map<String, Future<Uint8List>> _documentCache =
      <String, Future<Uint8List>>{};

  CompanyInfo _company = CompanyInfo.empty().copyWith(
    nombre: 'Sistema de Solares',
  );
  PrinterConfig? _defaultPrinter;
  bool _loadingData = true;

  @override
  void initState() {
    super.initState();
    _selectedType = widget.initialType;
    _printerRepository = PrinterRepository();
    _loadDialogData();
  }

  Future<void> _loadDialogData() async {
    try {
      final database = await AppDatabase.instance.database;
      final company = await CompanyRepository(database).getCompanyInfo();
      final defaultPrinter = await _printerRepository.getDefaultPrinter();

      if (!mounted) {
        return;
      }

      setState(() {
        _company = company ?? _company;
        _defaultPrinter = defaultPrinter;
        _loadingData = false;
      });
      _warmUpCurrentDocument();
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loadingData = false;
      });
      _warmUpCurrentDocument();
    }
  }

  PdfPageFormat get _documentPageFormat {
    return switch (_selectedType) {
      SaleDocumentType.initialReceipt =>
        SaleInitialReceiptPdfBuilder.pageFormat,
      SaleDocumentType.amortization => SaleAmortizationPdfBuilder.pageFormat,
    };
  }

  Map<String, PdfPageFormat> get _previewFormats {
    return switch (_selectedType) {
      SaleDocumentType.initialReceipt => {
        'Carta horizontal': PdfPageFormat.letter.landscape,
        'Carta vertical': PdfPageFormat.letter.portrait,
      },
      SaleDocumentType.amortization => {
        'A4 vertical': PdfPageFormat.a4.portrait,
        'A4 horizontal': PdfPageFormat.a4.landscape,
      },
    };
  }

  String get _fileName {
    final saleId = widget.detail.sale.id ?? 0;
    return switch (_selectedType) {
      SaleDocumentType.initialReceipt => 'Recibo-Inicial-Venta-$saleId.pdf',
      SaleDocumentType.amortization => 'Tabla-Amortizacion-Venta-$saleId.pdf',
    };
  }

  double get _dialogWidth {
    return switch (_selectedType) {
      SaleDocumentType.initialReceipt => 1180,
      SaleDocumentType.amortization => 1030,
    };
  }

  double get _dialogHeight {
    return switch (_selectedType) {
      SaleDocumentType.initialReceipt => 820,
      SaleDocumentType.amortization => 900,
    };
  }

  double get _previewMaxPageWidth {
    return switch (_selectedType) {
      SaleDocumentType.initialReceipt => 1080,
      SaleDocumentType.amortization => 760,
    };
  }

  EdgeInsets get _previewPadding {
    return switch (_selectedType) {
      SaleDocumentType.initialReceipt => const EdgeInsets.symmetric(
        horizontal: 12,
      ),
      SaleDocumentType.amortization => const EdgeInsets.symmetric(
        horizontal: 26,
      ),
    };
  }

  Future<Uint8List> _buildDocumentBytes({PdfPageFormat? pageFormat}) {
    final resolvedPageFormat = pageFormat ?? _documentPageFormat;
    final cacheKey =
        '${_selectedType.name}-${resolvedPageFormat.width}x${resolvedPageFormat.height}';

    final cachedFuture = _documentCache[cacheKey];
    if (cachedFuture != null) {
      return cachedFuture;
    }

    final generatedFuture = Future<Uint8List>(() {
      return switch (_selectedType) {
        SaleDocumentType.initialReceipt => SaleInitialReceiptPdfBuilder.build(
          detail: widget.detail,
          company: _company,
          pageFormat: resolvedPageFormat.landscape,
        ),
        SaleDocumentType.amortization => SaleAmortizationPdfBuilder.build(
          detail: widget.detail,
          company: _company,
          pageFormat: resolvedPageFormat,
        ),
      };
    });

    final guardedFuture = generatedFuture.catchError((Object error) {
      _documentCache.remove(cacheKey);
      throw error;
    });

    _documentCache[cacheKey] = guardedFuture;
    return guardedFuture;
  }

  Future<Uint8List> _buildPreviewBytes(PdfPageFormat format) async {
    final previewFormat = _selectedType == SaleDocumentType.initialReceipt
        ? format.landscape
        : format;

    try {
      return await _buildDocumentBytes(pageFormat: previewFormat);
    } catch (error) {
      return _buildPdfPreviewError(
        pageFormat: previewFormat,
        title: 'No se pudo renderizar el PDF',
        detail: error,
      );
    }
  }

  void _warmUpCurrentDocument() {
    if (_loadingData) {
      return;
    }
    unawaited(
      _buildDocumentBytes(
        pageFormat: _documentPageFormat,
      ).catchError((Object _) => Uint8List(0)),
    );
  }

  void _changeDocumentType(SaleDocumentType type) {
    if (_selectedType == type) {
      return;
    }

    setState(() {
      _selectedType = type;
    });
    _warmUpCurrentDocument();
  }

  Future<void> _printNow() async {
    try {
      final bytes = await _buildDocumentBytes(pageFormat: _documentPageFormat);
      final defaultPrinter = _defaultPrinter;

      if (defaultPrinter != null && defaultPrinter.hasSystemSelection) {
        final systemPrinter = await _printerRepository.resolvePrinter(
          defaultPrinter,
        );
        if (systemPrinter != null) {
          await Printing.directPrintPdf(
            printer: systemPrinter,
            onLayout: (_) async => bytes,
            name: _fileName,
            usePrinterSettings: false,
          );
          return;
        }
      }

      await Printing.layoutPdf(onLayout: (_) async => bytes);
    } catch (error) {
      if (!mounted) {
        return;
      }
      FriendlyErrorMessages.forOperation(
        'imprimir el documento',
        error,
        module: 'ventas',
      );
    }
  }

  Future<void> _exportPdf() async {
    try {
      final bytes = await _buildDocumentBytes(pageFormat: _documentPageFormat);
      await Printing.sharePdf(bytes: bytes, filename: _fileName);
    } catch (error) {
      if (!mounted) {
        return;
      }
      FriendlyErrorMessages.forOperation(
        'exportar el documento',
        error,
        module: 'ventas',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: _dialogWidth,
        height: _dialogHeight,
        child: Column(
          children: [
            _DialogHeader(
              saleId: widget.detail.sale.id ?? 0,
              onClose: () => Navigator.of(context).pop(),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: SegmentedButton<SaleDocumentType>(
                      segments: const [
                        ButtonSegment<SaleDocumentType>(
                          value: SaleDocumentType.initialReceipt,
                          icon: Icon(Icons.receipt_long_outlined),
                          label: Text('Recibo inicial'),
                        ),
                        ButtonSegment<SaleDocumentType>(
                          value: SaleDocumentType.amortization,
                          icon: Icon(Icons.table_chart_outlined),
                          label: Text('Tabla amortizacion'),
                        ),
                      ],
                      selected: {_selectedType},
                      onSelectionChanged: (selection) {
                        _changeDocumentType(selection.first);
                      },
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Chip(
                      label: Text(
                        _selectedType == SaleDocumentType.amortization
                            ? 'PDF de tabla amortizada'
                            : 'PDF de recibo inicial',
                      ),
                    ),
                    if (_loadingData)
                      const Chip(label: Text('Cargando empresa e impresora...'))
                    else if ((_defaultPrinter?.nombre ?? '').isNotEmpty)
                      Chip(label: Text('Impresora: ${_defaultPrinter!.nombre}'))
                    else
                      const Chip(label: Text('Sin impresora predeterminada')),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Padding(
                padding: _previewPadding,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFD9E0E8)),
                  ),
                  child: _loadingData
                      ? const Center(child: CircularProgressIndicator())
                      : ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: PdfPreview(
                            key: ValueKey(
                              'sale-document-preview-${_selectedType.name}-${_documentPageFormat.width}x${_documentPageFormat.height}',
                            ),
                            initialPageFormat: _documentPageFormat,
                            pageFormats: _previewFormats,
                            maxPageWidth: _previewMaxPageWidth,
                            canChangePageFormat: true,
                            canChangeOrientation: true,
                            canDebug: false,
                            allowPrinting: false,
                            allowSharing: false,
                            pdfFileName: _fileName,
                            build: _buildPreviewBytes,
                          ),
                        ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _loadingData ? null : _exportPdf,
                    icon: const Icon(Icons.save_alt_outlined),
                    label: const Text('Exportar PDF'),
                  ),
                  FilledButton.icon(
                    onPressed: _loadingData ? null : _printNow,
                    icon: const Icon(Icons.print_outlined),
                    label: Text(
                      (_defaultPrinter?.nombre ?? '').isNotEmpty
                          ? 'Imprimir rapido'
                          : 'Imprimir',
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cerrar'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<Uint8List> _buildPdfPreviewError({
  required PdfPageFormat pageFormat,
  required String title,
  required Object detail,
}) async {
  final doc = pw.Document();
  final cleanDetail = detail.toString().replaceAll(RegExp(r'\s+'), ' ');

  doc.addPage(
    pw.Page(
      pageFormat: pageFormat,
      margin: const pw.EdgeInsets.all(32),
      build: (_) => pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.all(22),
        decoration: pw.BoxDecoration(
          color: PdfColor.fromHex('#FFF8E8'),
          border: pw.Border.all(color: PdfColor.fromHex('#D69E2E'), width: 1),
          borderRadius: pw.BorderRadius.circular(12),
        ),
        child: pw.Column(
          mainAxisSize: pw.MainAxisSize.min,
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              title,
              style: pw.TextStyle(
                fontSize: 18,
                fontWeight: pw.FontWeight.bold,
                color: PdfColor.fromHex('#744210'),
              ),
            ),
            pw.SizedBox(height: 10),
            pw.Text(
              'El visor evito mostrar una pantalla roja. Revisa los datos del documento o intenta exportarlo nuevamente.',
              style: pw.TextStyle(
                fontSize: 10.5,
                color: PdfColor.fromHex('#3A2A12'),
              ),
            ),
            pw.SizedBox(height: 14),
            pw.Text(
              cleanDetail.length > 260
                  ? '${cleanDetail.substring(0, 260)}...'
                  : cleanDetail,
              style: pw.TextStyle(
                fontSize: 8.5,
                color: PdfColor.fromHex('#6B4E16'),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  return doc.save();
}

class _DialogHeader extends StatelessWidget {
  const _DialogHeader({required this.saleId, required this.onClose});

  final int saleId;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: theme.colorScheme.primary,
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Documentos de Venta #$saleId',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onPrimary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          IconButton(
            onPressed: onClose,
            icon: Icon(Icons.close, color: theme.colorScheme.onPrimary),
          ),
        ],
      ),
    );
  }
}

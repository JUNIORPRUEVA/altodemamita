import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../../../../core/resilience/friendly_error_messages.dart';
import '../../data/receipt_repository.dart';
import '../../domain/receipt.dart';
import '../../../settings/data/printer_repository.dart';
import '../../../settings/domain/printer_config.dart';
import 'receipt_controller.dart';
import 'receipt_pdf_builder.dart';
import 'receipt_view.dart';
import '../../../../shared/widgets/recovery_experience.dart';

final Map<String, PdfPageFormat> _receiptPageFormats = {
  'Carta horizontal': PdfPageFormat.letter.landscape,
  'Carta vertical': PdfPageFormat.letter.portrait,
};

class ReceiptDialog {
  static Future<void> show(
    BuildContext context, {
    required int paymentId,
    required ReceiptRepository receiptRepository,
    bool autoPrint = false,
  }) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ReceiptDialogContent(
        paymentId: paymentId,
        receiptRepository: receiptRepository,
        autoPrint: autoPrint,
      ),
    );
  }

  static Future<void> printQuick(
    BuildContext context, {
    required int paymentId,
    required ReceiptRepository receiptRepository,
  }) async {
    try {
      final receipt = await receiptRepository.fetchReceiptByPaymentId(
        paymentId,
      );
      if (receipt == null) {
        throw StateError(
          'No se pudo preparar el ticket del pago seleccionado.',
        );
      }

      await Printing.layoutPdf(
        name: 'Recibo-${receipt.receiptNumber}',
        format: PdfPageFormat.letter.landscape,
        usePrinterSettings: true,
        onLayout: (format) =>
            ReceiptPdfBuilder.build(receipt, pageFormat: format),
      );
    } catch (error) {
      FriendlyErrorMessages.forOperation(
        'imprimir el ticket',
        error,
        module: 'pagos',
      );
    }
  }
}

class _ReceiptDialogContent extends StatefulWidget {
  const _ReceiptDialogContent({
    required this.paymentId,
    required this.receiptRepository,
    required this.autoPrint,
  });

  final int paymentId;
  final ReceiptRepository receiptRepository;
  final bool autoPrint;

  @override
  State<_ReceiptDialogContent> createState() => _ReceiptDialogContentState();
}

class _ReceiptDialogContentState extends State<_ReceiptDialogContent> {
  late final ReceiptController _controller;
  late final PrinterRepository _printerRepository;
  PrinterConfig? _defaultPrinterConfig;
  bool _loadingPrinterConfig = true;
  late String _selectedPageFormatLabel;

  @override
  void initState() {
    super.initState();
    _controller = ReceiptController(
      receiptRepository: widget.receiptRepository,
    );
    _printerRepository = PrinterRepository();
    _selectedPageFormatLabel = _receiptPageFormats.keys.first;
    _controller.loadReceipt(widget.paymentId);
    _loadDefaultPrinter();

    if (widget.autoPrint) {
      Future<void>.delayed(const Duration(milliseconds: 500), _printNow);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadDefaultPrinter() async {
    final defaultPrinter = await _printerRepository.getDefaultPrinter();
    if (!mounted) {
      return;
    }
    setState(() {
      _defaultPrinterConfig = defaultPrinter;
      _loadingPrinterConfig = false;
      if (defaultPrinter?.defaultOrientation == 'portrait') {
        _selectedPageFormatLabel = 'Carta vertical';
      }
    });
  }

  PdfPageFormat get _selectedPageFormat {
    return _receiptPageFormats[_selectedPageFormatLabel] ??
        PdfPageFormat.letter.landscape;
  }

  Future<void> _printNow() async {
    final Receipt? receipt = _controller.receipt;
    if (receipt == null || !mounted) {
      return;
    }

    try {
      if (_loadingPrinterConfig && _defaultPrinterConfig == null) {
        final loadedPrinter = await _printerRepository.getDefaultPrinter();
        if (mounted) {
          setState(() {
            _defaultPrinterConfig = loadedPrinter;
            _loadingPrinterConfig = false;
            if (loadedPrinter?.defaultOrientation == 'portrait') {
              _selectedPageFormatLabel = 'Carta vertical';
            }
          });
        }
      }

      await Printing.layoutPdf(
        name: 'Recibo-${receipt.receiptNumber}',
        format: _selectedPageFormat,
        usePrinterSettings: true,
        onLayout: (format) =>
            ReceiptPdfBuilder.build(receipt, pageFormat: format),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      FriendlyErrorMessages.forOperation(
        'imprimir el recibo',
        error,
        module: 'pagos',
      );
    }
  }

  Future<void> _exportPdf() async {
    final Receipt? receipt = _controller.receipt;
    if (receipt == null || !mounted) {
      return;
    }

    try {
      final bytes = await ReceiptPdfBuilder.build(
        receipt,
        pageFormat: _selectedPageFormat,
      );
      await Printing.sharePdf(
        bytes: bytes,
        filename: 'Recibo-${receipt.receiptNumber}.pdf',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      FriendlyErrorMessages.forOperation(
        'exportar el recibo',
        error,
        module: 'pagos',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      clipBehavior: Clip.antiAlias,
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final double width = constraints.maxWidth.clamp(360.0, 1480.0);
          final double height = constraints.maxHeight.clamp(420.0, 1040.0);
          final bool isWide = width >= 980;

          return ConstrainedBox(
            constraints: BoxConstraints(maxWidth: width, maxHeight: height),
            child: ListenableBuilder(
              listenable: _controller,
              builder: (context, _) {
                if (_controller.isLoading) {
                  return const SizedBox(
                    width: 920,
                    height: 620,
                    child: Center(child: CircularProgressIndicator()),
                  );
                }

                final Receipt? receipt = _controller.receipt;
                if (receipt == null) {
                  final failure = _controller.loadError;
                  return SizedBox(
                    width: 720,
                    height: 420,
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 520),
                        child: InlineRecoveryCard(
                          title:
                              failure?.title ?? 'No pudimos preparar el recibo',
                          message:
                              failure?.message ??
                              'El recibo no está disponible en este momento.',
                          details:
                              failure?.details ??
                              'La vista se mantuvo en un estado seguro para que pueda cerrar esta ventana o volver a intentarlo.',
                          suggestions:
                              failure?.suggestions ??
                              const [
                                'Cierre esta ventana y vuelva a abrir el recibo.',
                              ],
                        ),
                      ),
                    ),
                  );
                }

                return SizedBox(
                  width: width,
                  height: height,
                  child: Column(
                    children: [
                      _DialogHeader(
                        receiptNumber: receipt.receiptNumber,
                        isWide: isWide,
                      ),
                      Expanded(
                        child: Container(
                          width: double.infinity,
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Color(0xFFF7F9FC), Color(0xFFF0F4F8)],
                            ),
                          ),
                          padding: EdgeInsets.fromLTRB(
                            isWide ? 8 : 6,
                            isWide ? 8 : 6,
                            isWide ? 8 : 6,
                            isWide ? 6 : 4,
                          ),
                          child: LayoutBuilder(
                            builder: (context, viewport) {
                              final availableWidth = viewport.maxWidth;
                              final availableHeight = viewport.maxHeight;
                              final framePadding = isWide ? 4.0 : 3.0;
                              final innerWidth = math.max(
                                0,
                                availableWidth - (framePadding * 2),
                              );
                              final innerHeight = math.max(
                                0,
                                availableHeight - (framePadding * 2),
                              );
                              final previewScale = math.min(
                                innerWidth / ReceiptView.documentWidth,
                                innerHeight / ReceiptView.documentHeight,
                              );

                              return Center(
                                child: Container(
                                  width: availableWidth,
                                  height: availableHeight,
                                  decoration: BoxDecoration(
                                    color: const Color(0x47FFFFFF),
                                    borderRadius: BorderRadius.circular(24),
                                    border: Border.all(
                                      color: const Color(0xFFD7E0EA),
                                    ),
                                    boxShadow: const [
                                      BoxShadow(
                                        color: Color(0x14000000),
                                        blurRadius: 28,
                                        offset: Offset(0, 12),
                                      ),
                                    ],
                                  ),
                                  padding: EdgeInsets.all(framePadding),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(18),
                                    child: ClipRect(
                                      child: OverflowBox(
                                        alignment: Alignment.center,
                                        minWidth: 0,
                                        minHeight: 0,
                                        maxWidth: double.infinity,
                                        maxHeight: double.infinity,
                                        child: Transform.scale(
                                          scale: previewScale,
                                          alignment: Alignment.center,
                                          child: SizedBox(
                                            width: ReceiptView.documentWidth,
                                            height: ReceiptView.documentHeight,
                                            child: ReceiptView(
                                              receipt: receipt,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      _DialogActions(
                        onExport: _exportPdf,
                        onPrint: _printNow,
                        selectedPageFormatLabel: _selectedPageFormatLabel,
                        onChangePageFormat: (label) {
                          setState(() {
                            _selectedPageFormatLabel = label;
                          });
                        },
                        defaultPrinterName: _defaultPrinterConfig?.nombre,
                        loadingPrinterConfig: _loadingPrinterConfig,
                      ),
                    ],
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _DialogHeader extends StatelessWidget {
  const _DialogHeader({required this.receiptNumber, required this.isWide});

  final String receiptNumber;
  final bool isWide;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 20, 16, 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFD7E0EA))),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFEAF0FB),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.receipt_long_rounded,
              color: Color(0xFF2D5AA6),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Recibo de pago',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: const Color(0xFF162534),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  isWide
                      ? 'Documento #$receiptNumber listo para impresion o exportacion horizontal.'
                      : 'Documento #$receiptNumber listo para vista previa, impresion y PDF.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF607080),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close, color: Color(0xFF243546)),
          ),
        ],
      ),
    );
  }
}

class _DialogActions extends StatelessWidget {
  const _DialogActions({
    required this.onExport,
    required this.onPrint,
    required this.selectedPageFormatLabel,
    required this.onChangePageFormat,
    required this.defaultPrinterName,
    required this.loadingPrinterConfig,
  });

  final Future<void> Function() onExport;
  final Future<void> Function() onPrint;
  final String selectedPageFormatLabel;
  final ValueChanged<String> onChangePageFormat;
  final String? defaultPrinterName;
  final bool loadingPrinterConfig;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFD7E0EA))),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        runSpacing: 10,
        spacing: 12,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              DropdownButton<String>(
                value: selectedPageFormatLabel,
                items: _receiptPageFormats.keys
                    .map(
                      (label) => DropdownMenuItem<String>(
                        value: label,
                        child: Text(label),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) {
                    onChangePageFormat(value);
                  }
                },
              ),
              if (loadingPrinterConfig)
                const Chip(label: Text('Cargando impresora...'))
              else if ((defaultPrinterName ?? '').isNotEmpty)
                Chip(label: Text('Impresora: $defaultPrinterName'))
              else
                const Chip(label: Text('Sin impresora predeterminada')),
            ],
          ),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cerrar'),
              ),
              TextButton.icon(
                onPressed: onExport,
                icon: const Icon(Icons.save_alt_outlined),
                label: const Text('Exportar PDF'),
              ),
              FilledButton.icon(
                onPressed: onPrint,
                icon: const Icon(Icons.print_outlined),
                label: const Text('Imprimir'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

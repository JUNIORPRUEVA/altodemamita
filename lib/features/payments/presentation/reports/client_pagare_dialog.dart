import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/resilience/friendly_error_messages.dart';
import '../../../settings/data/company_repository.dart';
import '../../../settings/data/printer_repository.dart';
import '../../../settings/domain/company_info.dart';
import '../../../settings/domain/printer_config.dart';
import '../../domain/client_pagare_report.dart';
import 'client_pagare_pdf_builder.dart';

class ClientPagareDialog {
  static Future<void> show(
    BuildContext context, {
    required ClientPagareReport report,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ClientPagareDialogContent(report: report),
    );
  }

  static Future<void> printQuick(
    BuildContext context, {
    required ClientPagareReport report,
  }) async {
    try {
      final db = await AppDatabase.instance.database;
      final company =
          await CompanyRepository(db).getCompanyInfo() ??
          CompanyInfo.empty().copyWith(nombre: 'Sistema de Solares');
      final printerRepository = PrinterRepository();
      final defaultPrinter = await printerRepository.getDefaultPrinter();
      final bytes = await ClientPagarePdfBuilder.build(
        report: report,
        company: company,
      );

      if (defaultPrinter != null && defaultPrinter.hasSystemSelection) {
        final systemPrinter = await printerRepository.resolvePrinter(
          defaultPrinter,
        );
        if (systemPrinter != null) {
          await Printing.directPrintPdf(
            printer: systemPrinter,
            onLayout: (_) async => bytes,
            name: 'Pagares-Cliente-${report.clientId}',
            usePrinterSettings: true,
          );
          return;
        }
      }

      await Printing.layoutPdf(onLayout: (_) async => bytes);
    } catch (error) {
      FriendlyErrorMessages.forOperation(
        'imprimir la lista de pagos',
        error,
        module: 'reportes',
      );
    }
  }
}

class _ClientPagareDialogContent extends StatefulWidget {
  const _ClientPagareDialogContent({required this.report});

  final ClientPagareReport report;

  @override
  State<_ClientPagareDialogContent> createState() =>
      _ClientPagareDialogContentState();
}

class _ClientPagareDialogContentState
    extends State<_ClientPagareDialogContent> {
  late final PrinterRepository _printerRepository;

  final Map<String, Future<Uint8List>> _documentCache =
      <String, Future<Uint8List>>{};

  PrinterConfig? _defaultPrinter;
  CompanyInfo _company = CompanyInfo.empty().copyWith(
    nombre: 'Sistema de Solares',
  );
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _printerRepository = PrinterRepository();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final db = await AppDatabase.instance.database;
      final company = await CompanyRepository(db).getCompanyInfo();
      final printer = await _printerRepository.getDefaultPrinter();
      if (!mounted) {
        return;
      }
      setState(() {
        _company = company ?? _company;
        _defaultPrinter = printer;
        _loading = false;
      });
      _warmUpDocument();
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
      });
      _warmUpDocument();
    }
  }

  Future<Uint8List> _buildBytes() {
    const cacheKey = 'client-pagare-a4';
    return _documentCache.putIfAbsent(
      cacheKey,
      () => ClientPagarePdfBuilder.build(
        report: widget.report,
        company: _company,
      ),
    );
  }

  void _warmUpDocument() {
    if (_loading) {
      return;
    }
    _buildBytes();
  }

  Future<void> _printNow() async {
    try {
      final bytes = await _buildBytes();
      final defaultPrinter = _defaultPrinter;
      if (defaultPrinter != null && defaultPrinter.hasSystemSelection) {
        final systemPrinter = await _printerRepository.resolvePrinter(
          defaultPrinter,
        );
        if (systemPrinter != null) {
          await Printing.directPrintPdf(
            printer: systemPrinter,
            onLayout: (_) async => bytes,
            name: 'Pagares-Cliente-${widget.report.clientId}',
            usePrinterSettings: true,
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
        'imprimir la lista de pagos',
        error,
        module: 'reportes',
      );
    }
  }

  Future<void> _exportPdf() async {
    try {
      final bytes = await _buildBytes();
      await Printing.sharePdf(
        bytes: bytes,
        filename: 'Pagares-Cliente-${widget.report.clientId}.pdf',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      FriendlyErrorMessages.forOperation(
        'exportar la lista de pagos',
        error,
        module: 'reportes',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth.clamp(420.0, 1320.0);
          final height = constraints.maxHeight.clamp(520.0, 980.0);

          return SizedBox(
            width: width,
            height: height,
            child: Column(
              children: [
                _DialogHeader(
                  clientName: widget.report.clientName,
                  totalItems: widget.report.items.length,
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
                    padding: const EdgeInsets.all(12),
                    child: LayoutBuilder(
                      builder: (context, viewport) {
                        const previewFramePadding = 6.0;
                        const previewPageMargin = EdgeInsets.all(6);
                        final pageAspectRatio =
                            PdfPageFormat.a4.width / PdfPageFormat.a4.height;
                        final usableWidth = math.max(
                          0.0,
                          viewport.maxWidth - (previewFramePadding * 2),
                        );
                        final usableHeight = math.max(
                          0.0,
                          viewport.maxHeight - (previewFramePadding * 2),
                        );
                        final maxPageWidth = math.max(
                          280.0,
                          math.min(
                            usableWidth,
                            math.max(0.0, usableHeight - 12) * pageAspectRatio,
                          ),
                        );

                        return DecoratedBox(
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FBFD),
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(color: const Color(0xFFD9E0E8)),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x12000000),
                                blurRadius: 22,
                                offset: Offset(0, 10),
                              ),
                            ],
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(previewFramePadding),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: ColoredBox(
                                color: const Color(0xFFF4F7FB),
                                child: _loading
                                    ? const Center(
                                        child: Padding(
                                          padding: EdgeInsets.all(48),
                                          child: CircularProgressIndicator(),
                                        ),
                                      )
                                    : PdfPreview(
                                        key: ValueKey(
                                          'client-pagare-preview-${widget.report.clientId}-${widget.report.items.length}',
                                        ),
                                        initialPageFormat:
                                            ClientPagarePdfBuilder.pageFormat,
                                        pageFormats: const {
                                          'A4 vertical': PdfPageFormat.a4,
                                        },
                                        maxPageWidth: maxPageWidth,
                                        useActions: false,
                                        padding: EdgeInsets.zero,
                                        previewPageMargin: previewPageMargin,
                                        scrollViewDecoration:
                                            const BoxDecoration(
                                              color: Color(0xFFF4F7FB),
                                            ),
                                        pdfPreviewPageDecoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          border: Border.all(
                                            color: const Color(0xFFD7E0EA),
                                          ),
                                          boxShadow: const [
                                            BoxShadow(
                                              color: Color(0x14000000),
                                              blurRadius: 12,
                                              offset: Offset(0, 4),
                                            ),
                                          ],
                                        ),
                                        canChangePageFormat: false,
                                        canChangeOrientation: false,
                                        canDebug: false,
                                        allowPrinting: false,
                                        allowSharing: false,
                                        pdfFileName:
                                            'Pagares-Cliente-${widget.report.clientId}.pdf',
                                        build: (_) => _buildBytes(),
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
                  defaultPrinterName: _defaultPrinter?.nombre,
                  loading: _loading,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _DialogHeader extends StatelessWidget {
  const _DialogHeader({required this.clientName, required this.totalItems});

  final String clientName;
  final int totalItems;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 16, 16, 14),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFD7E0EA))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFFEAF0FB),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.list_alt_rounded, color: Color(0xFF2D5AA6)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Lista de pagos',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF172433),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${clientName.trim().isEmpty ? 'Cliente' : clientName} · $totalItems registro(s) · formato vertical listo para PDF e impresion.',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF667788),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
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
    required this.defaultPrinterName,
    required this.loading,
  });

  final Future<void> Function() onExport;
  final Future<void> Function() onPrint;
  final String? defaultPrinterName;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFD7E0EA))),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        runSpacing: 10,
        spacing: 10,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              const Chip(label: Text('Formato A4 vertical')),
              if (loading)
                const Chip(label: Text('Cargando empresa e impresora...'))
              else if ((defaultPrinterName ?? '').trim().isNotEmpty)
                Chip(label: Text('Impresora: ${defaultPrinterName!.trim()}'))
              else
                const Chip(label: Text('Sin impresora predeterminada')),
            ],
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cerrar'),
              ),
              OutlinedButton.icon(
                onPressed: loading ? null : () => onExport(),
                icon: const Icon(Icons.download_rounded),
                label: const Text('Exportar PDF'),
              ),
              FilledButton.icon(
                onPressed: loading ? null : () => onPrint(),
                icon: const Icon(Icons.print_rounded),
                label: Text(
                  (defaultPrinterName ?? '').trim().isNotEmpty
                      ? 'Imprimir rapido'
                      : 'Imprimir',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

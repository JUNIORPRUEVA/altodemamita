import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../../shared/pdf/financial_pdf_theme.dart';
import '../../../settings/domain/company_info.dart';
import '../../domain/sale_calculator.dart';
import '../../domain/sale_detail.dart';

class SaleAmortizationPdfBuilder {
  /// La tabla de amortización siempre se imprime en A4 vertical.
  static PdfPageFormat get pageFormat => PdfPageFormat.a4.portrait;

  static Future<Uint8List> build({
    required SaleDetail detail,
    required CompanyInfo company,
    PdfPageFormat? pageFormat,
  }) async {
    final format = pageFormat ?? SaleAmortizationPdfBuilder.pageFormat;
    final fonts = await FinancialPdfTheme.loadFonts();
    final logo = FinancialPdfTheme.decodeLogo(company.logoBytesBase64);
    final table = _ComputedTable.fromDetail(detail);
    final doc = pw.Document(theme: fonts.theme);

    doc.addPage(
      pw.MultiPage(
        pageFormat: format,
        margin: const pw.EdgeInsets.fromLTRB(22, 18, 22, 20),
        header: (context) => _header(context, company, logo, detail),
        footer: _footer,
        build: (_) => [
          _summary(detail, table),
          pw.SizedBox(height: 12),
          _scheduleTable(table),
          pw.SizedBox(height: 12),
          _totals(table),
        ],
      ),
    );

    return doc.save();
  }

  static pw.Widget _header(
    pw.Context context,
    CompanyInfo company,
    pw.MemoryImage? logo,
    SaleDetail detail,
  ) {
    if (context.pageNumber > 1) {
      return pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 9),
        padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: pw.BoxDecoration(
          color: FinancialPdfTheme.surface,
          border: pw.Border.all(color: FinancialPdfTheme.line, width: 0.7),
          borderRadius: pw.BorderRadius.circular(7),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'Tabla de amortización | Venta #${detail.sale.id ?? '-'} | ${FinancialPdfTheme.dash(detail.clientName)}',
              maxLines: 1,
              style: FinancialPdfTheme.text(size: 8.2, bold: true),
            ),
            pw.Text(
              'Página ${context.pageNumber}',
              style: FinancialPdfTheme.text(
                size: 7.6,
                color: FinancialPdfTheme.muted,
              ),
            ),
          ],
        ),
      );
    }

    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 12),
      child: FinancialPdfTheme.documentHeader(
        companyName: company.nombre.trim().isEmpty
            ? 'Sistema de Solares'
            : company.nombre.trim(),
        phone: company.telefono,
        address: company.direccion,
        logo: logo,
        documentTitle: 'Tabla de amortización',
        subtitle: 'Plan de pagos proyectado para la venta seleccionada',
        metaItems: [
          PdfMetaItem('Venta', '#${detail.sale.id ?? '-'}'),
          PdfMetaItem('Cliente', FinancialPdfTheme.dash(detail.clientName)),
          PdfMetaItem(
            'Cuotas',
            '${detail.activeInstallmentCount}',
            emphasis: true,
          ),
        ],
      ),
    );
  }

  static pw.Widget _footer(pw.Context context) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 8),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'Documento financiero generado por Sistema Solares',
            style: FinancialPdfTheme.text(
              size: 7,
              color: FinancialPdfTheme.muted,
            ),
          ),
          pw.Text(
            'Página ${context.pageNumber} de ${context.pagesCount}',
            style: FinancialPdfTheme.text(
              size: 7,
              color: FinancialPdfTheme.muted,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _summary(SaleDetail detail, _ComputedTable table) {
    final sale = detail.sale;
    final firstInstallment = detail.installments.isEmpty
        ? null
        : detail.installments.first;
    final estimatedInstallment =
        firstInstallment?.totalAmount ??
        (sale.installmentCount > 0
            ? sale.financedBalance / sale.installmentCount
            : 0.0);

    return FinancialPdfTheme.card(
      title: 'Resumen de la venta',
      child: FinancialPdfTheme.fieldGrid([
        PdfField('Cliente', FinancialPdfTheme.dash(detail.clientName)),
        PdfField('Solar', FinancialPdfTheme.dash(detail.lotDisplayCode)),
        PdfField('Fecha venta', FinancialPdfTheme.shortDate(sale.saleDate)),
        PdfField('Precio solar', FinancialPdfTheme.money(sale.salePrice)),
        PdfField(
          'Inicial pagado',
          FinancialPdfTheme.money(sale.paidInitialPayment),
        ),
        PdfField(
          'Saldo financiado',
          FinancialPdfTheme.money(sale.financedBalance),
          emphasis: true,
        ),
        PdfField(
          'Interés mensual',
          '${sale.monthlyInterest.toStringAsFixed(2)}%',
        ),
        PdfField(
          'Cuota estimada',
          FinancialPdfTheme.money(estimatedInstallment),
          emphasis: true,
        ),
        PdfField('Total capital', FinancialPdfTheme.money(table.totalCapital)),
        PdfField('Total interés', FinancialPdfTheme.money(table.totalInterest)),
        PdfField(
          'Total a pagar',
          FinancialPdfTheme.money(table.totalAmount),
          emphasis: true,
        ),
        PdfField('Cuotas activas', '${detail.activeInstallmentCount}'),
      ], columns: 4),
    );
  }

  static pw.Widget _scheduleTable(_ComputedTable table) {
    return pw.TableHelper.fromTextArray(
      headers: const [
        'Cuota',
        'Vence',
        'Capital',
        'Interés',
        'Total',
        'Balance',
      ],
      data: table.rows,
      border: pw.TableBorder(
        top: pw.BorderSide(color: FinancialPdfTheme.line, width: 0.7),
        bottom: pw.BorderSide(color: FinancialPdfTheme.line, width: 0.7),
        left: pw.BorderSide(color: FinancialPdfTheme.line, width: 0.7),
        right: pw.BorderSide(color: FinancialPdfTheme.line, width: 0.7),
        horizontalInside: pw.BorderSide(
          color: FinancialPdfTheme.softLine,
          width: 0.35,
        ),
      ),
      headerDecoration: pw.BoxDecoration(color: FinancialPdfTheme.greenDark),
      headerStyle: FinancialPdfTheme.text(
        size: 7.7,
        bold: true,
        color: PdfColors.white,
      ),
      headerAlignment: pw.Alignment.center,
      cellStyle: FinancialPdfTheme.text(size: 7.7),
      oddCellStyle: FinancialPdfTheme.text(size: 7.7),
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4.4),
      rowDecoration: pw.BoxDecoration(color: FinancialPdfTheme.surface),
      oddRowDecoration: pw.BoxDecoration(color: PdfColors.white),
      cellAlignments: const {
        0: pw.Alignment.center,
        1: pw.Alignment.center,
        2: pw.Alignment.centerRight,
        3: pw.Alignment.centerRight,
        4: pw.Alignment.centerRight,
        5: pw.Alignment.centerRight,
      },
      columnWidths: const {
        0: pw.FixedColumnWidth(36),
        1: pw.FixedColumnWidth(58),
        2: pw.FlexColumnWidth(1.05),
        3: pw.FlexColumnWidth(1.05),
        4: pw.FlexColumnWidth(1.05),
        5: pw.FlexColumnWidth(1.18),
      },
    );
  }

  static pw.Widget _totals(_ComputedTable table) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: pw.BoxDecoration(
        color: FinancialPdfTheme.softGreen,
        border: pw.Border.all(color: PdfColor.fromHex('#CDE8DA'), width: 0.8),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Row(
        children: [
          pw.Expanded(
            child: _totalItem(
              'Capital',
              FinancialPdfTheme.money(table.totalCapital),
            ),
          ),
          _divider(),
          pw.Expanded(
            child: _totalItem(
              'Interés',
              FinancialPdfTheme.money(table.totalInterest),
            ),
          ),
          _divider(),
          pw.Expanded(
            child: _totalItem(
              'Total plan',
              FinancialPdfTheme.money(table.totalAmount),
              emphasis: true,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _divider() {
    return pw.Container(width: 0.7, height: 28, color: FinancialPdfTheme.line);
  }

  static pw.Widget _totalItem(
    String label,
    String value, {
    bool emphasis = false,
  }) {
    return pw.Column(
      children: [
        pw.Text(
          label.toUpperCase(),
          style: FinancialPdfTheme.text(
            size: 7.2,
            bold: true,
            color: FinancialPdfTheme.muted,
          ),
        ),
        pw.SizedBox(height: 3),
        pw.Text(
          value,
          style: FinancialPdfTheme.text(
            size: emphasis ? 10.6 : 9,
            bold: true,
            color: emphasis
                ? FinancialPdfTheme.greenDark
                : FinancialPdfTheme.ink,
          ),
        ),
      ],
    );
  }
}

class _ComputedTable {
  const _ComputedTable({
    required this.rows,
    required this.totalCapital,
    required this.totalInterest,
    required this.totalAmount,
  });

  final List<List<String>> rows;
  final double totalCapital;
  final double totalInterest;
  final double totalAmount;

  factory _ComputedTable.fromDetail(SaleDetail detail) {
    final sale = detail.sale;
    final schedule = SaleCalculator.generateSchedule(
      financedBalance: sale.financedBalance,
      monthlyInterest: sale.monthlyInterest,
      installmentCount: sale.installmentCount,
    );

    double totalCapital = 0;
    double totalInterest = 0;
    double totalAmount = 0;
    double balance = sale.financedBalance;
    DateTime cursor = sale.saleDate;
    final rows = <List<String>>[];

    for (var index = 0; index < schedule.length; index++) {
      final item = schedule[index];
      cursor = DateTime(cursor.year, cursor.month + 1, cursor.day);
      balance -= item.capitalPayment;
      if (balance < 0) {
        balance = 0;
      }
      totalCapital += item.capitalPayment;
      totalInterest += item.interestPayment;
      totalAmount += item.totalPayment;

      rows.add([
        '${index + 1}',
        FinancialPdfTheme.shortDate(cursor),
        FinancialPdfTheme.money(item.capitalPayment),
        FinancialPdfTheme.money(item.interestPayment),
        FinancialPdfTheme.money(item.totalPayment),
        FinancialPdfTheme.money(balance),
      ]);
    }

    return _ComputedTable(
      rows: rows,
      totalCapital: totalCapital,
      totalInterest: totalInterest,
      totalAmount: totalAmount,
    );
  }
}

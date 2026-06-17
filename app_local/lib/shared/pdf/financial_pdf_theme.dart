import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/utils/dominican_formatters.dart';

class FinancialPdfFonts {
  const FinancialPdfFonts({required this.base, required this.bold});

  final pw.Font base;
  final pw.Font bold;

  pw.ThemeData get theme => pw.ThemeData.withFont(base: base, bold: bold);
}

class FinancialPdfTheme {
  const FinancialPdfTheme._();

  static final PdfColor ink = PdfColor.fromHex('#1F2933');
  static final PdfColor muted = PdfColor.fromHex('#667085');
  static final PdfColor softText = PdfColor.fromHex('#8A95A3');
  static final PdfColor line = PdfColor.fromHex('#D8DEE6');
  static final PdfColor softLine = PdfColor.fromHex('#EBEFF3');
  static final PdfColor paper = PdfColors.white;
  static final PdfColor surface = PdfColor.fromHex('#F7F9FA');
  static final PdfColor softGreen = PdfColor.fromHex('#EAF6F0');
  static final PdfColor green = PdfColor.fromHex('#147A5B');
  static final PdfColor greenDark = PdfColor.fromHex('#0F513C');
  static final PdfColor warning = PdfColor.fromHex('#A15C07');
  static final PdfColor warningSoft = PdfColor.fromHex('#FFF4E5');

  static Future<FinancialPdfFonts> loadFonts() async {
    final baseData = await rootBundle.load('assets/fonts/NotoSans-Regular.ttf');
    final boldData = await rootBundle.load('assets/fonts/NotoSans-Bold.ttf');
    return FinancialPdfFonts(
      base: pw.Font.ttf(baseData),
      bold: pw.Font.ttf(boldData),
    );
  }

  static pw.MemoryImage? decodeLogo(String? base64Logo) {
    final value = base64Logo?.trim();
    if (value == null || value.isEmpty) {
      return null;
    }
    try {
      return pw.MemoryImage(base64Decode(value));
    } catch (_) {
      return null;
    }
  }

  static String dash(String? value) {
    final clean = value?.trim() ?? '';
    return clean.isEmpty ? '-' : clean;
  }

  static String money(num value) => 'RD\$ ${formatRdCurrency(value)}';

  static String shortDate(DateTime value) {
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    return '$day/$month/${value.year}';
  }

  static pw.TextStyle text({
    double size = 9,
    PdfColor? color,
    bool bold = false,
    double? letterSpacing,
    double? lineSpacing,
  }) {
    return pw.TextStyle(
      fontSize: size,
      color: color ?? ink,
      fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
      letterSpacing: letterSpacing,
      lineSpacing: lineSpacing,
    );
  }

  static pw.Widget documentHeader({
    required String companyName,
    required String documentTitle,
    required List<PdfMetaItem> metaItems,
    String? phone,
    String? address,
    pw.MemoryImage? logo,
    String? subtitle,
    bool compact = false,
  }) {
    final headerPadding = compact
        ? const pw.EdgeInsets.fromLTRB(11, 9, 11, 9)
        : const pw.EdgeInsets.fromLTRB(14, 12, 14, 12);
    final logoSize = compact ? 38.0 : 48.0;

    return pw.Container(
      width: double.infinity,
      padding: headerPadding,
      decoration: pw.BoxDecoration(
        color: paper,
        border: pw.Border.all(color: line, width: 0.8),
        borderRadius: pw.BorderRadius.circular(10),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Container(
            width: logoSize,
            height: logoSize,
            padding: const pw.EdgeInsets.all(4),
            decoration: pw.BoxDecoration(
              color: surface,
              border: pw.Border.all(color: softLine, width: 0.8),
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: logo != null
                ? pw.Image(logo, fit: pw.BoxFit.contain)
                : pw.Center(
                    child: pw.Text(
                      'SS',
                      style: text(size: 11, bold: true, color: greenDark),
                    ),
                  ),
          ),
          pw.SizedBox(width: 12),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  dash(companyName),
                  maxLines: 2,
                  style: text(size: compact ? 12.5 : 14.5, bold: true),
                ),
                if ((subtitle ?? '').trim().isNotEmpty) ...[
                  pw.SizedBox(height: 3),
                  pw.Text(
                    subtitle!.trim(),
                    style: text(size: 8.2, color: muted, lineSpacing: 1.2),
                  ),
                ],
                if ((phone ?? '').trim().isNotEmpty ||
                    (address ?? '').trim().isNotEmpty) ...[
                  pw.SizedBox(height: 4),
                  pw.Text(
                    [phone, address]
                        .map((item) => item?.trim() ?? '')
                        .where((item) => item.isNotEmpty)
                        .join('  |  '),
                    maxLines: 2,
                    style: text(size: 8, color: softText, lineSpacing: 1.2),
                  ),
                ],
              ],
            ),
          ),
          pw.SizedBox(width: 12),
          pw.Container(
            width: compact ? 150 : 176,
            padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            decoration: pw.BoxDecoration(
              color: softGreen,
              border: pw.Border.all(color: PdfColor.fromHex('#CDE8DA')),
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  documentTitle.toUpperCase(),
                  maxLines: 2,
                  style: text(
                    size: compact ? 8.2 : 8.8,
                    bold: true,
                    color: greenDark,
                    letterSpacing: 0.7,
                  ),
                ),
                pw.SizedBox(height: 6),
                ...metaItems.map(
                  (item) => pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 3),
                    child: pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.SizedBox(
                          width: 54,
                          child: pw.Text(
                            item.label.toUpperCase(),
                            style: text(size: 6.6, color: muted, bold: true),
                          ),
                        ),
                        pw.Expanded(
                          child: pw.Text(
                            item.value,
                            textAlign: pw.TextAlign.right,
                            maxLines: 2,
                            style: text(
                              size: item.emphasis ? 9.2 : 7.6,
                              bold: true,
                              color: item.emphasis ? greenDark : ink,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget sectionTitle(String title) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
      decoration: pw.BoxDecoration(
        color: softGreen,
        borderRadius: pw.BorderRadius.circular(5),
      ),
      child: pw.Text(
        title.toUpperCase(),
        style: text(
          size: 7.2,
          bold: true,
          color: greenDark,
          letterSpacing: 0.35,
        ),
      ),
    );
  }

  static pw.Widget card({required String title, required pw.Widget child}) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: paper,
        border: pw.Border.all(color: line, width: 0.75),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [sectionTitle(title), pw.SizedBox(height: 7), child],
      ),
    );
  }

  static pw.Widget fieldGrid(List<PdfField> fields, {required int columns}) {
    final items = List<PdfField>.from(fields);
    while (items.length % columns != 0) {
      items.add(const PdfField('', ''));
    }

    return pw.Table(
      border: pw.TableBorder(
        top: pw.BorderSide(color: line, width: 0.7),
        bottom: pw.BorderSide(color: line, width: 0.7),
        left: pw.BorderSide(color: line, width: 0.7),
        right: pw.BorderSide(color: line, width: 0.7),
        horizontalInside: pw.BorderSide(color: softLine, width: 0.45),
        verticalInside: pw.BorderSide(color: softLine, width: 0.45),
      ),
      children: [
        for (var index = 0; index < items.length; index += columns)
          pw.TableRow(
            verticalAlignment: pw.TableCellVerticalAlignment.top,
            children: [
              for (var column = 0; column < columns; column++)
                _fieldCell(items[index + column]),
            ],
          ),
      ],
    );
  }

  static pw.Widget _fieldCell(PdfField field) {
    if (field.label.isEmpty) {
      return pw.SizedBox(height: 34);
    }
    return pw.Container(
      constraints: const pw.BoxConstraints(minHeight: 34),
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            field.label.toUpperCase(),
            maxLines: 1,
            style: text(size: 6.8, bold: true, color: muted),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            field.value,
            maxLines: field.maxLines,
            style: text(
              size: field.emphasis ? 9.4 : 8.3,
              bold: true,
              color: field.emphasis ? greenDark : ink,
              lineSpacing: 1.15,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget keyValue(
    String label,
    String value, {
    bool emphasis = false,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 5),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 112,
            child: pw.Text(
              label,
              style: text(size: 8, bold: true, color: muted),
            ),
          ),
          pw.Expanded(
            child: pw.Text(
              value,
              textAlign: pw.TextAlign.right,
              style: text(
                size: emphasis ? 9.2 : 8.2,
                bold: true,
                color: emphasis ? greenDark : ink,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget signatureLine(String label, {String? name}) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Container(height: 0.75, color: ink),
        pw.SizedBox(height: 5),
        if ((name ?? '').trim().isNotEmpty) ...[
          pw.Text(
            name!.trim(),
            textAlign: pw.TextAlign.center,
            maxLines: 1,
            style: text(size: 8.6, bold: true),
          ),
          pw.SizedBox(height: 2),
        ],
        pw.Text(
          label.toUpperCase(),
          textAlign: pw.TextAlign.center,
          style: text(size: 7, bold: true, color: muted),
        ),
      ],
    );
  }
}

class PdfMetaItem {
  const PdfMetaItem(this.label, this.value, {this.emphasis = false});

  final String label;
  final String value;
  final bool emphasis;
}

class PdfField {
  const PdfField(
    this.label,
    this.value, {
    this.emphasis = false,
    this.maxLines = 2,
  });

  final String label;
  final String value;
  final bool emphasis;
  final int maxLines;
}

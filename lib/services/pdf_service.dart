import 'dart:typed_data';

import 'package:barcode/barcode.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../core/format.dart';
import '../data/models.dart';
import 'currency_service.dart';
import 'session.dart';

/// توليد ملفات PDF: الفاتورة (حراري أو A4)، كشف حساب الزبون، ملصقات الباركود.
class PdfService {
  PdfService._();

  static pw.Font? _regular;
  static pw.Font? _bold;

  static Future<pw.ThemeData> _theme() async {
    _regular ??= pw.Font.ttf(await rootBundle.load('assets/fonts/IBMPlexSansArabic-Regular.ttf'));
    _bold ??= pw.Font.ttf(await rootBundle.load('assets/fonts/IBMPlexSansArabic-Bold.ttf'));
    return pw.ThemeData.withFont(base: _regular, bold: _bold);
  }

  static const _navy = PdfColor.fromInt(0xFF0A192F);
  static const _emerald = PdfColor.fromInt(0xFF059669);
  static const _coral = PdfColor.fromInt(0xFFF43F5E);
  static const _grey = PdfColor.fromInt(0xFF64748B);

  /// [widthMm]: 58 أو 80 للطابعة الحرارية، أو null لـ A4.
  static Future<Uint8List> invoice(Sale sale, {double? widthMm = 80}) async {
    final theme = await _theme();
    final shop = Session.shop;
    final cur = CurrencyService.byCode(sale.currency);
    String m(double base) {
      final v = sale.rate == 0 ? base : base / sale.rate;
      return '${Fmt.money(v)} ${cur.symbol}';
    }

    final roll = widthMm != null;
    final format = roll
        ? PdfPageFormat(widthMm * PdfPageFormat.mm, double.infinity, marginAll: 3 * PdfPageFormat.mm)
        : PdfPageFormat.a4.copyWith(
            marginLeft: 36, marginRight: 36, marginTop: 36, marginBottom: 36);
    final fs = roll ? (widthMm < 70 ? 8.0 : 9.5) : 11.0;

    pw.Widget row(String a, String b, {bool bold = false, PdfColor? color}) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(a, style: pw.TextStyle(fontSize: fs, fontWeight: bold ? pw.FontWeight.bold : null)),
            pw.Text(b, style: pw.TextStyle(fontSize: fs, fontWeight: bold ? pw.FontWeight.bold : null, color: color)),
          ],
        );

    final doc = pw.Document(theme: theme);
    doc.addPage(pw.Page(
      pageFormat: format,
      textDirection: pw.TextDirection.rtl,
      build: (ctx) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Container(
            padding: const pw.EdgeInsets.all(6),
            color: roll ? null : _navy,
            child: pw.Column(children: [
              pw.Text(shop?.name ?? 'فورتكس',
                  style: pw.TextStyle(
                      fontSize: fs + 5, fontWeight: pw.FontWeight.bold, color: roll ? PdfColors.black : PdfColors.white)),
              if ((shop?.phone ?? '').isNotEmpty)
                pw.Text('جوال: ${shop!.phone}',
                    style: pw.TextStyle(fontSize: fs, color: roll ? PdfColors.black : PdfColors.white)),
              if ((shop?.address ?? '').isNotEmpty)
                pw.Text(shop!.address!, style: pw.TextStyle(fontSize: fs, color: roll ? PdfColors.black : PdfColors.white)),
            ]),
          ),
          pw.SizedBox(height: 4),
          pw.Center(
              child: pw.Text(sale.isReturn ? 'فاتورة مرتجع #${sale.number}' : 'فاتورة بيع #${sale.number}',
                  style: pw.TextStyle(fontSize: fs + 2, fontWeight: pw.FontWeight.bold))),
          row('التاريخ', Fmt.dateTime(sale.createdAt)),
          if (sale.customerName != null) row('الزبون', sale.customerName!),
          if (sale.userName != null) row('الكاشير', sale.userName!),
          pw.Divider(thickness: 0.6),
          pw.Table(
            columnWidths: roll
                ? {0: const pw.FlexColumnWidth(3), 1: const pw.FlexColumnWidth(1.2), 2: const pw.FlexColumnWidth(1.8)}
                : {
                    0: const pw.FlexColumnWidth(4),
                    1: const pw.FlexColumnWidth(1.4),
                    2: const pw.FlexColumnWidth(1.8),
                    3: const pw.FlexColumnWidth(2)
                  },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: 0.5))),
                children: [
                  _cell('الصنف', fs, bold: true),
                  _cell('الكمية', fs, bold: true),
                  if (!roll) _cell('السعر', fs, bold: true),
                  _cell('المجموع', fs, bold: true),
                ],
              ),
              for (final l in sale.lines)
                pw.TableRow(children: [
                  _cell(roll ? '${l.name}\n${m(l.price)}' : l.name, fs),
                  _cell('${Fmt.qty(l.qty)} ${l.unitName}', fs),
                  if (!roll) _cell(m(l.price), fs),
                  _cell(m(l.total), fs),
                ]),
            ],
          ),
          pw.Divider(thickness: 0.6),
          row('المجموع', m(sale.subtotal)),
          if (sale.discount > 0) row('الخصم', m(sale.discount)),
          row('الإجمالي', m(sale.total), bold: true),
          if (!sale.isReturn) ...[
            row('المدفوع', m(sale.paid), color: _emerald),
            if (sale.remaining > 0) row('المتبقي (دين)', m(sale.remaining), bold: true, color: _coral),
            if (sale.dueDate != null && sale.remaining > 0) row('تاريخ الاستحقاق', Fmt.date(sale.dueDate!)),
          ],
          row('الحالة', sale.statusLabel, color: sale.status == 'paid' ? _emerald : null),
          if (!cur.isBase) row('سعر الصرف', '1 ${cur.symbol} = ${Fmt.money(sale.rate)} ${CurrencyService.base.symbol}'),
          pw.SizedBox(height: 6),
          pw.Center(
            child: pw.BarcodeWidget(
              barcode: Barcode.code128(),
              data: 'VX${sale.number}',
              width: roll ? widthMm * 2 : 160,
              height: 30,
              drawText: false,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Center(
              child: pw.Text(shop?.footer?.isNotEmpty == true ? shop!.footer! : 'شكراً لزيارتكم',
                  style: pw.TextStyle(fontSize: fs, color: _grey))),
          pw.Center(child: pw.Text('فورتكس للمحاسبة', style: pw.TextStyle(fontSize: fs - 2, color: _grey))),
        ],
      ),
    ));
    return doc.save();
  }

  static pw.Widget _cell(String t, double fs, {bool bold = false}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2, horizontal: 1),
        child: pw.Text(t, style: pw.TextStyle(fontSize: fs, fontWeight: bold ? pw.FontWeight.bold : null)),
      );

  /// كشف حساب زبون.
  static Future<Uint8List> statement(Customer c, List<LedgerEntry> entries, PartyBalance b) async {
    final theme = await _theme();
    final doc = pw.Document(theme: theme);
    var running = 0.0;
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      textDirection: pw.TextDirection.rtl,
      margin: const pw.EdgeInsets.all(32),
      build: (ctx) => [
        pw.Container(
          padding: const pw.EdgeInsets.all(12),
          color: _navy,
          child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            pw.Text(Session.shop?.name ?? '',
                style: pw.TextStyle(color: PdfColors.white, fontSize: 16, fontWeight: pw.FontWeight.bold)),
            pw.Text('كشف حساب', style: const pw.TextStyle(color: PdfColors.white, fontSize: 14)),
          ]),
        ),
        pw.SizedBox(height: 10),
        pw.Text('الزبون: ${c.name}   ${c.phone ?? ''}', style: const pw.TextStyle(fontSize: 12)),
        pw.Text('تاريخ الكشف: ${Fmt.date(DateTime.now())}', style: const pw.TextStyle(fontSize: 11, color: _grey)),
        pw.SizedBox(height: 10),
        pw.TableHelper.fromTextArray(
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 10),
          headerDecoration: const pw.BoxDecoration(color: _navy),
          cellStyle: const pw.TextStyle(fontSize: 10),
          cellAlignment: pw.Alignment.centerRight,
          headers: ['التاريخ', 'البيان', 'عليه', 'دفع', 'الرصيد'],
          data: [
            for (final e in entries)
              () {
                running += e.debit - e.credit;
                return [
                  Fmt.date(e.createdAt),
                  '${e.kindLabel}${e.note == null ? '' : ' - ${e.note}'}',
                  e.debit > 0 ? money(e.debit) : '',
                  e.credit > 0 ? money(e.credit) : '',
                  money(running),
                ];
              }(),
          ],
        ),
        pw.SizedBox(height: 12),
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text('الرصيد المستحق: ${money(b.balance)}', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
          if (b.isOverdue)
            pw.Text('منه متأخر: ${money(b.overdue)}',
                style: pw.TextStyle(fontSize: 13, color: _coral, fontWeight: pw.FontWeight.bold)),
        ]),
      ],
    ));
    return doc.save();
  }

  /// ملصقات باركود: [copies] لكل صنف. [labelW]/[labelH] بالملم.
  static Future<Uint8List> labels(List<(Item, String barcode, double price, int copies)> list,
      {double labelW = 50, double labelH = 30, bool showPrice = true}) async {
    final theme = await _theme();
    final doc = pw.Document(theme: theme);
    final format = PdfPageFormat(labelW * PdfPageFormat.mm, labelH * PdfPageFormat.mm, marginAll: 1.5 * PdfPageFormat.mm);
    for (final (item, code, price, copies) in list) {
      final bc = code.length == 13 && RegExp(r'^\d+$').hasMatch(code) ? Barcode.ean13() : Barcode.code128();
      for (var i = 0; i < copies; i++) {
        doc.addPage(pw.Page(
          pageFormat: format,
          textDirection: pw.TextDirection.rtl,
          build: (ctx) => pw.Column(
            mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
            children: [
              pw.Text(item.name,
                  maxLines: 1, style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold), overflow: pw.TextOverflow.clip),
              pw.Expanded(child: pw.BarcodeWidget(barcode: bc, data: code, textStyle: const pw.TextStyle(fontSize: 7))),
              if (showPrice) pw.Text(money(price), style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
            ],
          ),
        ));
      }
    }
    return doc.save();
  }
}

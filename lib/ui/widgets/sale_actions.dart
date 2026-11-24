import 'package:material_ui/material_ui.dart';
import 'package:printing/printing.dart';

import '../../data/models.dart';
import '../../services/debts_service.dart';
import '../../services/pdf_service.dart';
import '../../services/printer_service.dart';
import '../../services/whatsapp_service.dart';
import 'common.dart';

/// إجراءات الفاتورة: طباعة حرارية، واتساب، مشاركة PDF، طباعة عادية.
class SaleActions {
  SaleActions._();

  static Future<void> thermal(BuildContext context, Sale s) async {
    try {
      final width = await PrinterService.paperWidth();
      final pdf = await PdfService.invoice(s, widthMm: width.toDouble());
      await PrinterService.printPdf(pdf);
      if (context.mounted) toast(context, 'تمت الطباعة ✓');
    } catch (e) {
      if (context.mounted) toast(context, '$e'.replaceFirst('Exception: ', ''), error: true);
    }
  }

  static Future<void> whatsappText(BuildContext context, Sale s) async {
    String? phone;
    if (s.customerId != null) phone = (await DebtsService.customer(s.customerId!))?.contactNumber;
    if (!context.mounted) return;
    if (phone == null || phone.isEmpty) {
      phone = await askText(context, 'رقم واتساب الزبون', hint: '059xxxxxxx');
      if (phone == null || phone.isEmpty) return;
    }
    await WhatsappService.openChat(phone, WhatsappService.invoiceText(s));
  }

  static Future<void> sharePdf(BuildContext context, Sale s) async {
    final pdf = await PdfService.invoice(s, widthMm: 80);
    await WhatsappService.sharePdf(pdf, 'invoice-${s.number}.pdf', text: 'فاتورة #${s.number}');
  }

  static Future<void> printA4(BuildContext context, Sale s) async {
    await Printing.layoutPdf(onLayout: (_) => PdfService.invoice(s, widthMm: null), name: 'invoice-${s.number}');
  }

  static Widget buttons(BuildContext context, Sale s) => Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.center,
        children: [
          FilledButton.icon(
            onPressed: () => thermal(context, s),
            icon: const Icon(Icons.print_outlined),
            label: const Text('طباعة حرارية'),
          ),
          ElevatedButton.icon(
            onPressed: () => whatsappText(context, s),
            icon: const Icon(Icons.chat),
            label: const Text('واتساب'),
          ),
          OutlinedButton.icon(
            onPressed: () => sharePdf(context, s),
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: const Text('مشاركة PDF'),
          ),
          OutlinedButton.icon(
            onPressed: () => printA4(context, s),
            icon: const Icon(Icons.description_outlined),
            label: const Text('طباعة A4'),
          ),
        ],
      );
}

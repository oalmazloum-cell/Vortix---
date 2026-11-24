import 'dart:typed_data';

import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:image/image.dart' as img;
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:printing/printing.dart';

import '../data/db.dart';

/// الطباعة الحرارية عبر البلوتوث (58 / 80 ملم).
///
/// العربية لا تدعمها معظم الطابعات الحرارية كنص، لذلك نرسم الفاتورة PDF
/// بخط عربي ثم نحولها لصورة ونرسلها للطابعة كصورة نقطية (Raster) — فتظهر
/// الحروف العربية متصلة وصحيحة على أي طابعة ESC/POS.
class PrinterService {
  PrinterService._();

  static Future<String?> savedAddress() => AppDb.I.getSetting('printer_address');
  static Future<String?> savedName() => AppDb.I.getSetting('printer_name');
  static Future<int> paperWidth() async => int.tryParse(await AppDb.I.getSetting('printer_width') ?? '') ?? 80;

  static Future<void> savePrinter(String address, String name, int width) async {
    final db = AppDb.I;
    await db.setSetting('printer_address', address, sync: false);
    await db.setSetting('printer_name', name, sync: false);
    await db.setSetting('printer_width', '$width', sync: false);
  }

  static Future<List<BluetoothInfo>> pairedPrinters() async {
    if (!await PrintBluetoothThermal.isPermissionBluetoothGranted) return [];
    return PrintBluetoothThermal.pairedBluetooths;
  }

  static Future<bool> _ensureConnected() async {
    if (await PrintBluetoothThermal.connectionStatus) return true;
    final addr = await savedAddress();
    if (addr == null) return false;
    return PrintBluetoothThermal.connect(macPrinterAddress: addr);
  }

  /// يطبع ملف PDF (فاتورة بعرض الورق) على الطابعة الحرارية.
  static Future<void> printPdf(Uint8List pdf) async {
    if (!await _ensureConnected()) {
      throw Exception('الطابعة غير متصلة. اختر الطابعة من الإعدادات وتأكد أن البلوتوث يعمل');
    }
    final width = await paperWidth();
    final dots = width == 58 ? 384 : 576; // عرض رأس الطباعة بالنقاط
    final profile = await CapabilityProfile.load();
    final gen = Generator(width == 58 ? PaperSize.mm58 : PaperSize.mm80, profile);
    final bytes = <int>[...gen.reset()];
    await for (final page in Printing.raster(pdf, dpi: 203)) {
      var image = img.Image.fromBytes(
          width: page.width, height: page.height, bytes: page.pixels.buffer, numChannels: 4, order: img.ChannelOrder.rgba);
      if (image.width != dots) image = img.copyResize(image, width: dots);
      image = img.grayscale(image);
      // نقسم الصورة لشرائح حتى لا يمتلئ مخزن الطابعة
      const slice = 240;
      for (var y = 0; y < image.height; y += slice) {
        final h = (y + slice > image.height) ? image.height - y : slice;
        bytes.addAll(gen.imageRaster(img.copyCrop(image, x: 0, y: y, width: image.width, height: h)));
      }
    }
    bytes
      ..addAll(gen.feed(3))
      ..addAll(gen.cut());
    final ok = await PrintBluetoothThermal.writeBytes(bytes);
    if (!ok) throw Exception('تعذر إرسال البيانات للطابعة');
  }
}

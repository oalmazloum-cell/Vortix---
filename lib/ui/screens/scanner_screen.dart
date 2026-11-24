import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/theme.dart';

/// نتيجة معالجة مسح متتالي: رسالة تظهر للمستخدم ونجاحها.
class ScanFeedback {
  ScanFeedback(this.message, {this.ok = true});
  final String message;
  final bool ok;
}

/// يفتح الماسح لقراءة باركود واحد ويعيده.
Future<String?> scanBarcode(BuildContext context, {String title = 'امسح الباركود'}) =>
    Navigator.push<String>(context, MaterialPageRoute(builder: (_) => ScannerScreen(title: title)));

/// ماسح الباركود المتطور:
/// - صوت واهتزاز عند القراءة.
/// - وضع "مسح متتالي" يضيف صنفاً بعد صنف بدون إغلاق الكاميرا.
/// - فلاش، تبديل الكاميرا، إدخال يدوي، ومنع القراءة المكررة السريعة.
class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key, this.title = 'امسح الباركود', this.onContinuous});

  final String title;

  /// إن وُجد، يعمل الماسح بوضع المسح المتتالي ويستدعي هذه الدالة لكل باركود.
  final Future<ScanFeedback> Function(String code)? onContinuous;

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  final _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    detectionTimeoutMs: 400,
    formats: const [
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
      BarcodeFormat.upcA,
      BarcodeFormat.upcE,
      BarcodeFormat.code128,
      BarcodeFormat.code39,
      BarcodeFormat.code93,
      BarcodeFormat.itf2of5,
      BarcodeFormat.codabar,
      BarcodeFormat.qrCode,
      BarcodeFormat.dataMatrix,
    ],
  );

  String? _lastCode;
  DateTime _lastAt = DateTime(2000);
  bool _busy = false;
  int _count = 0;
  ScanFeedback? _feedback;
  bool _torch = false;

  bool get _continuous => widget.onContinuous != null;

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_busy) return;
    final code = capture.barcodes.map((b) => b.rawValue).whereType<String>().firstOrNull;
    if (code == null || code.isEmpty) return;
    final now = DateTime.now();
    if (code == _lastCode && now.difference(_lastAt) < const Duration(milliseconds: 1800)) return;
    _lastCode = code;
    _lastAt = now;
    _busy = true;
    HapticFeedback.mediumImpact();
    SystemSound.play(SystemSoundType.click);
    if (!_continuous) {
      if (mounted) Navigator.pop(context, code);
      return;
    }
    final fb = await widget.onContinuous!(code);
    if (!fb.ok) HapticFeedback.heavyImpact();
    if (mounted) {
      setState(() {
        _feedback = fb;
        if (fb.ok) _count++;
      });
    }
    _busy = false;
  }

  Future<void> _manual() async {
    final ctrl = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('إدخال الباركود يدوياً'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(hintText: 'رقم الباركود'),
          onSubmitted: (v) => Navigator.pop(c, v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(c, ctrl.text.trim()), child: const Text('موافق')),
        ],
      ),
    );
    if (code == null || code.isEmpty || !mounted) return;
    if (!_continuous) {
      Navigator.pop(context, code);
    } else {
      final fb = await widget.onContinuous!(code);
      setState(() {
        _feedback = fb;
        if (fb.ok) _count++;
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final window = Rect.fromCenter(
        center: Offset(size.width / 2, size.height * 0.38), width: size.width * 0.8, height: size.width * 0.5);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            tooltip: 'الفلاش',
            icon: Icon(_torch ? Icons.flash_on : Icons.flash_off),
            onPressed: () async {
              await _controller.toggleTorch();
              setState(() => _torch = !_torch);
            },
          ),
          IconButton(tooltip: 'تبديل الكاميرا', icon: const Icon(Icons.cameraswitch_outlined), onPressed: () => _controller.switchCamera()),
        ],
      ),
      body: Stack(children: [
        MobileScanner(
          controller: _controller,
          onDetect: _onDetect,
          scanWindow: window,
          errorBuilder: (c, e) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'تعذر تشغيل الكاميرا. تأكد من منح التطبيق صلاحية الكاميرا.\n(${e.errorCode.name})',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ),
        ),
        // تعتيم خارج نافذة المسح + إطار
        IgnorePointer(child: CustomPaint(size: Size.infinite, painter: _WindowPainter(window))),
        Positioned(
          top: window.bottom + 16,
          left: 24,
          right: 24,
          child: Column(children: [
            Text(_continuous ? 'وضع المسح المتتالي — امسح الأصناف واحداً تلو الآخر' : 'وجّه الكاميرا نحو الباركود',
                textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 15)),
            if (_feedback != null) ...[
              const SizedBox(height: 14),
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: _feedback!.ok ? VColors.emerald : VColors.coral,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(_feedback!.message,
                    textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              ),
            ],
          ]),
        ),
        Positioned(
          bottom: 24,
          left: 16,
          right: 16,
          child: SafeArea(
            child: Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white54)),
                  onPressed: _manual,
                  icon: const Icon(Icons.keyboard_outlined),
                  label: const Text('إدخال يدوي'),
                ),
              ),
              if (_continuous) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.check),
                    label: Text('تم ($_count)'),
                  ),
                ),
              ],
            ]),
          ),
        ),
      ]),
    );
  }
}

class _WindowPainter extends CustomPainter {
  _WindowPainter(this.window);
  final Rect window;

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(window, const Radius.circular(16));
    final path = Path()
      ..addRect(Offset.zero & size)
      ..addRRect(r)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(path, Paint()..color = Colors.black.withValues(alpha: 0.55));
    canvas.drawRRect(
        r,
        Paint()
          ..color = VColors.blueBright
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3);
    // خط المسح
    canvas.drawLine(Offset(window.left + 16, window.center.dy), Offset(window.right - 16, window.center.dy),
        Paint()
          ..color = VColors.blueBright.withValues(alpha: 0.7)
          ..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(covariant _WindowPainter old) => old.window != window;
}

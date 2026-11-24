import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/config.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../services/session.dart';
import '../../services/subscription_service.dart';
import '../../services/whatsapp_service.dart';
import '../../state/app_state.dart';
import '../widgets/common.dart';

/// الاشتراك: الفترة التجريبية وتفعيل الاشتراك بكود.
class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});
  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  final _code = TextEditingController();
  bool _busy = false;

  Future<void> _activate() async {
    setState(() => _busy = true);
    final ok = await SubscriptionService.activate(Session.shop?.phone ?? '', _code.text);
    await AppState.I.refreshSub();
    if (!mounted) return;
    setState(() => _busy = false);
    toast(context, ok ? 'تم تفعيل الاشتراك بنجاح ✓' : 'الكود غير صحيح أو منتهي', error: !ok);
  }

  @override
  Widget build(BuildContext context) {
    final sub = context.watch<AppState>().sub;
    return Scaffold(
      appBar: AppBar(title: const Text('الاشتراك')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        VCard(
          child: Column(children: [
            Icon(
              sub?.state == SubState.active ? Icons.verified : Icons.hourglass_bottom_rounded,
              size: 52,
              color: switch (sub?.state) {
                SubState.active => VColors.emerald,
                SubState.expired => VColors.coral,
                _ => VColors.blue,
              },
            ),
            const SizedBox(height: 10),
            Text(
              switch (sub?.state) {
                SubState.active => 'الاشتراك مفعّل',
                SubState.expired => 'انتهت الفترة التجريبية',
                _ => 'الفترة التجريبية المجانية',
              },
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            if (sub != null)
              Text(
                sub.state == SubState.expired
                    ? 'بياناتك كلها محفوظة. فعّل الاشتراك لمتابعة البيع.'
                    : 'متبقي ${sub.daysLeft} يوم • حتى ${Fmt.date(sub.until)}',
                textAlign: TextAlign.center,
              ),
          ]),
        ),
        const SizedBox(height: 16),
        VCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('كيف أفعّل الاشتراك؟', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 8),
            Text('1. اضغط "طلب التفعيل" وأرسل الرسالة على واتساب.\n'
                '2. بعد الدفع يصلك كود التفعيل.\n'
                '3. أدخل الكود هنا — يعمل حتى بدون إنترنت.\n\n'
                'التجربة المجانية: ${AppConfig.trialDays} أيام بكل المزايا.'),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: WhatsappService.requestActivation,
              icon: const Icon(Icons.chat_outlined),
              label: const Text('طلب التفعيل عبر واتساب'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _code,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(labelText: 'كود التفعيل', hintText: 'YYYYMMDD-XXXXXXXX', prefixIcon: Icon(Icons.key)),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _busy ? null : _activate,
              icon: const Icon(Icons.workspace_premium_outlined),
              label: const Text('تفعيل الاشتراك'),
            ),
          ]),
        ),
      ]),
    );
  }
}

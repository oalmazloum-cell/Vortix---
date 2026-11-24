import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/config.dart';
import '../../core/theme.dart';
import '../../services/backup_service.dart';
import '../../services/demo_service.dart';
import '../../services/session.dart';
import '../../services/sync_service.dart';
import '../../state/app_state.dart';
import '../widgets/brand.dart';
import '../widgets/common.dart';
import 'lock_screen.dart';
import 'shell.dart';

/// شاشة البداية والدخول: "محل جديد" أو "عندي حساب" في صفحة واحدة.
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  bool _newShop = true;
  bool _busy = false;

  final _newForm = GlobalKey<FormState>();
  final _loginForm = GlobalKey<FormState>();
  final _shop = TextEditingController();
  final _owner = TextEditingController();
  final _phone = TextEditingController();
  final _whats = TextEditingController();
  final _code = TextEditingController();
  final _loginPhone = TextEditingController();
  final _loginPass = TextEditingController();
  bool _showCode = false;

  Future<void> _create() async {
    if (!_newForm.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await Session.createShop(
        shopName: _shop.text.trim(),
        ownerName: _owner.text.trim(),
        phone: _phone.text.trim(),
        whatsapp: _whats.text.trim().isEmpty ? null : _whats.text.trim(),
        ownerCode: _code.text.trim(),
      );
      // إنشاء الحساب السحابي في الخلفية (لا يعطّل البدء بدون إنترنت).
      SyncService.registerShop(_phone.text.trim(), _code.text.trim());
      await AppState.I.load();
      SyncService.start();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const Shell()), (_) => false);
    } catch (e) {
      if (mounted) toast(context, 'تعذر إنشاء المحل: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// معاينة الويب: محل تجريبي جاهز بالبيانات.
  Future<void> _demo() async {
    setState(() => _busy = true);
    try {
      await DemoService.seed();
      await AppState.I.load();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const Shell()), (_) => false);
    } catch (e) {
      if (mounted) toast(context, 'تعذر تجهيز البيانات التجريبية: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _login() async {
    if (!_loginForm.currentState!.validate()) return;
    if (!AppConfig.cloudEnabled) {
      final ok = await confirm(context, 'الاسترجاع من ملف',
          'المزامنة السحابية غير مفعلة في هذه النسخة. هل تريد استرجاع محلك من ملف نسخة احتياطية (vortex-*.json)؟',
          ok: 'اختيار الملف');
      if (ok) await _restoreFile();
      return;
    }
    setState(() => _busy = true);
    try {
      await SyncService.loginAndRestore(_loginPhone.text.trim(), _loginPass.text.trim());
      await _finishRestore(_loginPass.text.trim());
    } catch (e) {
      if (mounted) {
        toast(context, 'تعذر الدخول: تأكد من رقم الجوال وكلمة السر ومن اتصال الإنترنت', error: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restoreFile() async {
    final files = await FilePicker.pickFiles(type: FileType.any);
    if (files.isEmpty || files.first.path == null) return;
    setState(() => _busy = true);
    try {
      await BackupService.restoreFromFile(File(files.first.path!));
      await _finishRestore(_loginPass.text.trim());
    } catch (e) {
      if (mounted) toast(context, 'فشل الاسترجاع: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _finishRestore(String password) async {
    await AppState.I.load();
    final owner = await Session.owner();
    if (owner != null && password.isNotEmpty) await Session.login(owner, password);
    SyncService.start();
    if (!mounted) return;
    toast(context, 'تم استرجاع بيانات المحل بنجاح ✓');
    Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => Session.user == null ? const LockScreen() : const Shell()), (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(children: [
        ListView(
          padding: EdgeInsets.zero,
          children: [
            _header(context),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
              child: Column(children: [
                Row(children: [
                  Expanded(
                    child: _OptionTile(
                      icon: Icons.storefront_outlined,
                      title: 'محل جديد',
                      selected: _newShop,
                      onTap: () => setState(() => _newShop = true),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _OptionTile(
                      icon: Icons.login_rounded,
                      title: 'عندي حساب',
                      selected: !_newShop,
                      onTap: () => setState(() => _newShop = false),
                    ),
                  ),
                ]),
                if (kIsWeb) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _demo,
                    icon: const Icon(Icons.play_circle_outline),
                    label: const Text('جرّب ببيانات تجريبية (رمز المالك 123456)'),
                  ),
                ],
                const SizedBox(height: 16),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: _newShop ? _newShopCard() : _loginCard(),
                ),
              ]),
            ),
          ],
        ),
        if (_busy)
          Container(
            color: Colors.black26,
            child: const Center(child: CircularProgressIndicator(color: Colors.white)),
          ),
      ]),
    );
  }

  Widget _header(BuildContext context) => Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(20, MediaQuery.paddingOf(context).top + 32, 20, 28),
        decoration: const BoxDecoration(
          color: VColors.navy,
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
        ),
        child: Column(children: [
          const VortexLogo(size: 64),
          const SizedBox(height: 16),
          const Text('فورتكس للمحاسبة',
              style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          const Text('بيع، مخزون، ديون، وحسابات محلك كلها من جوالك',
              textAlign: TextAlign.center, style: TextStyle(color: Colors.white70, fontSize: 15)),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white12),
            ),
            child: const Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 6,
              children: [
                _Feature(Icons.wifi_off_rounded, 'يعمل بدون نت'),
                Text('•', style: TextStyle(color: Colors.white38)),
                _Feature(Icons.card_giftcard_rounded, 'مجاني لست أيام'),
                Text('•', style: TextStyle(color: Colors.white38)),
                _Feature(Icons.verified_user_outlined, 'بياناتك محفوظة'),
              ],
            ),
          ),
        ]),
      );

  Widget _newShopCard() => VCard(
        key: const ValueKey('new'),
        padding: const EdgeInsets.all(18),
        child: Form(
          key: _newForm,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('محل جديد', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('أنشئ حساب محلك في دقيقة واحدة وبتبلش تبيع',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 18),
            VField(controller: _shop, label: 'اسم المحل', icon: Icons.store_outlined, validator: requiredValidator, textInputAction: TextInputAction.next),
            VField(controller: _owner, label: 'اسم صاحب المحل', icon: Icons.person_outline, validator: requiredValidator, textInputAction: TextInputAction.next),
            VField(
              controller: _phone,
              label: 'رقم الجوال',
              icon: Icons.phone_iphone,
              keyboard: TextInputType.phone,
              textInputAction: TextInputAction.next,
              validator: (v) => (v == null || v.replaceAll(RegExp(r'\D'), '').length < 9) ? 'أدخل رقم جوال صحيح' : null,
            ),
            VField(controller: _whats, label: 'رقم الواتس (اختياري)', icon: Icons.chat_outlined, keyboard: TextInputType.phone, textInputAction: TextInputAction.next),
            VField(
              controller: _code,
              label: 'رمز المالك السري',
              icon: Icons.lock_outline,
              keyboard: TextInputType.number,
              obscure: !_showCode,
              helper: 'يحمي الأرباح والتعديلات لما يشتغل العامل على الجهاز',
              suffix: IconButton(
                icon: Icon(_showCode ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _showCode = !_showCode),
              ),
              validator: (v) => (v == null || v.trim().length < 6) ? 'الرمز 6 أرقام على الأقل' : null,
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _busy ? null : _create,
              icon: const Icon(Icons.rocket_launch_outlined),
              label: const Text('ابدأ الآن مجاناً'),
            ),
          ]),
        ),
      );

  Widget _loginCard() => VCard(
        key: const ValueKey('login'),
        padding: const EdgeInsets.all(18),
        child: Form(
          key: _loginForm,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('عندي حساب', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('أهلاً فيك من جديد، أدخل برقم جوال المحل وكلمة السر وبترجع كل بياناتك على هذا الجهاز',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 18),
            VField(
              controller: _loginPhone,
              label: 'رقم جوال المحل',
              icon: Icons.phone_iphone,
              keyboard: TextInputType.phone,
              validator: requiredValidator,
              textInputAction: TextInputAction.next,
            ),
            VField(
              controller: _loginPass,
              label: 'كلمة السر (رمز المالك)',
              icon: Icons.lock_outline,
              obscure: true,
              keyboard: TextInputType.number,
              validator: requiredValidator,
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: _busy ? null : _login,
              icon: const Icon(Icons.cloud_download_outlined),
              label: const Text('الدخول واسترجاع المحل'),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _busy ? null : _restoreFile,
              icon: const Icon(Icons.folder_open_outlined),
              label: const Text('استرجاع من ملف نسخة احتياطية'),
            ),
          ]),
        ),
      );
}

class _Feature extends StatelessWidget {
  const _Feature(this.icon, this.text);
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: VColors.blueBright, size: 16),
        const SizedBox(width: 4),
        Text(text, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
      ]);
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({required this.icon, required this.title, required this.selected, required this.onTap});
  final IconData icon;
  final String title;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: selected ? VColors.blue : Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected ? VColors.blue : Theme.of(context).colorScheme.outline),
          boxShadow: selected ? [BoxShadow(color: VColors.blue.withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 4))] : null,
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Column(children: [
              Icon(icon, size: 30, color: selected ? Colors.white : VColors.blue),
              const SizedBox(height: 8),
              Text(title,
                  style: TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 15, color: selected ? Colors.white : Theme.of(context).colorScheme.onSurface)),
            ]),
          ),
        ),
      );
}

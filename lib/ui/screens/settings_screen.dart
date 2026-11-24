import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../../core/config.dart';
import '../../core/format.dart';
import '../../data/db.dart';
import '../../services/backup_service.dart';
import '../../services/currency_service.dart';
import '../../services/device_services.dart';
import '../../services/printer_service.dart';
import '../../services/session.dart';
import '../../services/sync_service.dart';
import '../../state/app_state.dart';
import '../widgets/common.dart';
import 'lock_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _editShop(BuildContext context) async {
    if (!await requireOwner(context)) return;
    final s = Session.shop!;
    final name = TextEditingController(text: s.name);
    final owner = TextEditingController(text: s.ownerName);
    final phone = TextEditingController(text: s.phone);
    final whats = TextEditingController(text: s.whatsapp);
    final address = TextEditingController(text: s.address);
    final footer = TextEditingController(text: s.footer);
    if (!context.mounted) return;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (c) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(c).bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('بيانات المحل', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            VField(controller: name, label: 'اسم المحل', icon: Icons.store_outlined),
            VField(controller: owner, label: 'اسم صاحب المحل', icon: Icons.person_outline),
            VField(controller: phone, label: 'رقم الجوال', icon: Icons.phone_outlined, keyboard: TextInputType.phone),
            VField(controller: whats, label: 'رقم الواتس', icon: Icons.chat_outlined, keyboard: TextInputType.phone),
            VField(controller: address, label: 'العنوان (يظهر على الفاتورة)', icon: Icons.place_outlined),
            VField(controller: footer, label: 'تذييل الفاتورة', icon: Icons.short_text),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('حفظ')),
          ]),
        ),
      ),
    );
    if (ok != true) return;
    await Session.saveShop(
      name: name.text.trim(),
      ownerName: owner.text.trim(),
      phone: s.phone, // رقم الحساب السحابي لا يتغير من هنا
      whatsapp: whats.text.trim(),
      address: address.text.trim(),
      footer: footer.text.trim(),
    );
    AppState.I.bump();
  }

  Future<void> _rates(BuildContext context) async {
    if (!await requireOwner(context, reason: 'تعديل أسعار الصرف يحتاج رمز المالك')) return;
    if (!context.mounted) return;
    await showModalBottomSheet(
      context: context,
      builder: (c) => SafeArea(
        child: StatefulBuilder(
          builder: (c, set) => ListView(shrinkWrap: true, padding: const EdgeInsets.all(8), children: [
            ListTile(
              title: const Text('العملات وسعر الصرف', style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text('العملة الأساسية: ${CurrencyService.base.name}'),
            ),
            for (final cur in CurrencyService.all.where((x) => !x.isBase))
              ListTile(
                title: Text('${cur.name} (${cur.symbol})'),
                subtitle: Text('1 ${cur.symbol} = ${Fmt.money(cur.rate)} ${CurrencyService.base.symbol}'),
                trailing: const Icon(Icons.edit_outlined),
                onTap: () async {
                  final v = await askNumber(c, 'سعر ${cur.name} اليوم', initial: cur.rate, suffix: CurrencyService.base.symbol);
                  if (v == null || v <= 0) return;
                  await CurrencyService.setRate(cur.code, v);
                  AppState.I.bump();
                  set(() {});
                },
              ),
          ]),
        ),
      ),
    );
  }

  Future<void> _printer(BuildContext context) async {
    final printers = await PrinterService.pairedPrinters();
    if (!context.mounted) return;
    if (printers.isEmpty) {
      toast(context, 'لا توجد طابعات مقترنة. اقرن الطابعة من إعدادات البلوتوث في الجوال أولاً', error: true);
      return;
    }
    var width = await PrinterService.paperWidth();
    if (!context.mounted) return;
    await showModalBottomSheet(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => SafeArea(
          child: ListView(shrinkWrap: true, children: [
            ListTile(
              title: const Text('عرض الورق'),
              trailing: SegmentedButton<int>(
                segments: const [ButtonSegment(value: 58, label: Text('58 ملم')), ButtonSegment(value: 80, label: Text('80 ملم'))],
                selected: {width},
                onSelectionChanged: (s) => set(() => width = s.first),
              ),
            ),
            for (final pr in printers)
              ListTile(
                leading: const Icon(Icons.print_outlined),
                title: Text(pr.name),
                subtitle: Text(pr.macAdress),
                onTap: () async {
                  await PrinterService.savePrinter(pr.macAdress, pr.name, width);
                  if (c.mounted) Navigator.pop(c);
                  AppState.I.bump();
                },
              ),
          ]),
        ),
      ),
    );
  }

  Future<void> _backupNow(BuildContext context) async {
    final f = await BackupService.createBackup(label: 'manual');
    await SharePlus.instance.share(ShareParams(files: [XFile(f.path)], text: 'نسخة احتياطية - فورتكس'));
  }

  Future<void> _restore(BuildContext context, File file) async {
    if (!await requireOwner(context, reason: 'الاسترجاع يستبدل كل البيانات الحالية')) return;
    if (!context.mounted) return;
    final ok = await confirm(context, 'استرجاع نسخة', 'سيتم استبدال كل بيانات هذا الجهاز بالنسخة: ${p.basename(file.path)}',
        danger: true, ok: 'استرجاع');
    if (!ok) return;
    try {
      await BackupService.createBackup(label: 'before-restore');
      await BackupService.restoreFromFile(file);
      await SyncService.enqueueAll();
      await AppState.I.reloadAll();
      Session.user = null;
      if (!context.mounted) return;
      Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LockScreen()), (_) => false);
    } catch (e) {
      if (context.mounted) toast(context, 'فشل الاسترجاع: $e', error: true);
    }
  }

  Future<void> _restoreList(BuildContext context) async {
    final files = await BackupService.listBackups();
    if (!context.mounted) return;
    final f = await showModalBottomSheet<File>(
      context: context,
      builder: (c) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          ListTile(
            leading: const Icon(Icons.folder_open),
            title: const Text('اختيار ملف من الجهاز...'),
            onTap: () async {
              final picked = await FilePicker.pickFiles(type: FileType.any);
              if (picked.isNotEmpty && picked.first.path != null && c.mounted) Navigator.pop(c, File(picked.first.path!));
            },
          ),
          const Divider(),
          for (final f in files.take(20))
            ListTile(
              leading: const Icon(Icons.history),
              title: Text(p.basename(f.path), style: const TextStyle(fontSize: 13)),
              subtitle: Text(Fmt.dateTime(f.lastModifiedSync())),
              onTap: () => Navigator.pop(c, f),
            ),
        ]),
      ),
    );
    if (f != null && context.mounted) await _restore(context, f);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppState.I;
    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات')),
      body: DataBuilder(
        load: () async => (
          await PrinterService.savedName(),
          await BiometricService.available(),
          await BiometricService.enabled(),
          await AppDb.I.getSetting('last_backup'),
          AppConfig.cloudEnabled ? await SyncService.pendingCount() : 0,
          await AppDb.I.getSetting('default_due_days'),
        ),
        builder: (context, d) {
          final (printer, bioAvail, bioOn, lastBackup, pending, dueDays) = d;
          return ListView(padding: const EdgeInsets.all(16), children: [
            const SectionTitle('المحل'),
            VCard(
              padding: EdgeInsets.zero,
              child: Column(children: [
                ListTile(
                  leading: const Icon(Icons.store_outlined),
                  title: Text(Session.shop?.name ?? ''),
                  subtitle: Text('${Session.shop?.ownerName ?? ''} • ${Session.shop?.phone ?? ''}'),
                  trailing: const Icon(Icons.edit_outlined),
                  onTap: () => _editShop(context),
                ),
                ListTile(
                  leading: const Icon(Icons.currency_exchange),
                  title: const Text('العملات وأسعار الصرف'),
                  subtitle: Text(CurrencyService.all.where((c) => !c.isBase).map((c) => '${c.symbol} ${Fmt.money(c.rate)}').join('  •  ')),
                  onTap: () => _rates(context),
                ),
                ListTile(
                  leading: const Icon(Icons.event_repeat_outlined),
                  title: const Text('مدة استحقاق الدين الافتراضية'),
                  trailing: Text('${dueDays ?? 30} يوم'),
                  onTap: () async {
                    final v = await askNumber(context, 'عدد الأيام', initial: double.tryParse(dueDays ?? '30'));
                    if (v == null || v <= 0) return;
                    await AppDb.I.setSetting('default_due_days', '${v.toInt()}');
                    app.bump();
                  },
                ),
              ]),
            ),
            const SectionTitle('المظهر والأمان'),
            VCard(
              padding: EdgeInsets.zero,
              child: Column(children: [
                ListTile(
                  leading: const Icon(Icons.dark_mode_outlined),
                  title: const Text('الوضع'),
                  trailing: SegmentedButton<ThemeMode>(
                    segments: const [
                      ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode_outlined)),
                      ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode_outlined)),
                      ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.brightness_auto_outlined)),
                    ],
                    selected: {app.themeMode},
                    showSelectedIcon: false,
                    onSelectionChanged: (s) => app.setTheme(s.first),
                  ),
                ),
                if (Session.isOwner)
                  SwitchListTile(
                    secondary: const Icon(Icons.fingerprint),
                    title: const Text('القفل بالبصمة أو الوجه للمالك'),
                    subtitle: Text(bioAvail ? 'افتح التطبيق بدون إدخال الرمز' : 'غير متاح على هذا الجهاز'),
                    value: bioOn,
                    onChanged: !bioAvail
                        ? null
                        : (v) async {
                            if (v && !await BiometricService.authenticate('تفعيل الدخول بالبصمة')) return;
                            await BiometricService.setEnabled(v);
                            app.bump();
                          },
                  ),
              ]),
            ),
            const SectionTitle('الطباعة'),
            VCard(
              padding: EdgeInsets.zero,
              child: ListTile(
                leading: const Icon(Icons.print_outlined),
                title: const Text('الطابعة الحرارية (بلوتوث)'),
                subtitle: Text(printer ?? 'لم تُحدد'),
                trailing: const Icon(Icons.chevron_left),
                onTap: () => _printer(context),
              ),
            ),
            const SectionTitle('النسخ الاحتياطي والمزامنة'),
            VCard(
              padding: EdgeInsets.zero,
              child: Column(children: [
                ListTile(
                  leading: const Icon(Icons.backup_outlined),
                  title: const Text('نسخة احتياطية الآن ومشاركتها'),
                  subtitle: Text(lastBackup == null
                      ? 'نسخة تلقائية يومية مفعّلة'
                      : 'آخر نسخة: ${Fmt.dateTimeMs(int.parse(lastBackup))} • تلقائياً كل يوم'),
                  onTap: () => _backupNow(context),
                ),
                ListTile(
                  leading: const Icon(Icons.settings_backup_restore),
                  title: const Text('استرجاع نسخة احتياطية'),
                  onTap: () => _restoreList(context),
                ),
                ValueListenableBuilder(
                  valueListenable: SyncService.state,
                  builder: (c, s, _) => ListTile(
                    leading: const Icon(Icons.cloud_sync_outlined),
                    title: const Text('المزامنة السحابية'),
                    subtitle: Text(!AppConfig.cloudEnabled
                        ? 'غير مفعّلة (أضف بيانات Supabase عند البناء)'
                        : '${switch (s) {
                            SyncState.syncing => 'جاري المزامنة...',
                            SyncState.offline => 'بدون إنترنت',
                            SyncState.error => 'خطأ: ${SyncService.lastError ?? ''}',
                            _ => SyncService.signedIn ? 'متصل' : 'بانتظار إنشاء الحساب السحابي',
                          }} • بانتظار الرفع: $pending'),
                    trailing: AppConfig.cloudEnabled ? const Icon(Icons.sync) : null,
                    onTap: AppConfig.cloudEnabled
                        ? () async {
                            await SyncService.syncNow();
                            app.bump();
                          }
                        : null,
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 24),
            Center(
              child: Text('${AppConfig.appName} • الإصدار 1.0.0',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ),
          ]);
        },
      ),
    );
  }
}

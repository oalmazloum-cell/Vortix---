import 'package:material_ui/material_ui.dart';

import '../../data/models.dart';
import '../../services/session.dart';
import '../../services/sync_service.dart';
import '../../state/app_state.dart';
import '../widgets/common.dart';

/// العمال والصلاحيات (للمالك فقط).
class WorkersScreen extends StatelessWidget {
  const WorkersScreen({super.key});

  static const defaultPerms = {Perm.sellOnCredit, Perm.manageDebts, Perm.stockCount};

  Future<void> _edit(BuildContext context, {AppUser? u}) async {
    final name = TextEditingController(text: u?.name);
    final pin = TextEditingController();
    final perms = {...(u?.perms ?? defaultPerms)};
    var active = u?.active ?? true;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(c).bottom),
          child: SizedBox(
            height: MediaQuery.sizeOf(c).height * 0.85,
            child: ListView(padding: const EdgeInsets.all(16), children: [
              Text(u == null ? 'عامل جديد' : 'تعديل ${u.name}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              VField(controller: name, label: 'اسم العامل', icon: Icons.badge_outlined),
              VField(
                controller: pin,
                label: u == null ? 'رمز دخول العامل (4 أرقام أو أكثر)' : 'رمز جديد (اتركه فارغاً لعدم التغيير)',
                icon: Icons.pin_outlined,
                keyboard: TextInputType.number,
                obscure: true,
              ),
              SwitchListTile(title: const Text('الحساب فعّال'), value: active, onChanged: (v) => set(() => active = v)),
              const Divider(),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('الصلاحيات', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
              const Text('العامل يبيع دائماً. أي عملية غير مسموحة له ستطلب رمز المالك.', style: TextStyle(fontSize: 12)),
              for (final p in Perm.values)
                CheckboxListTile(
                  value: perms.contains(p),
                  title: Text(p.label),
                  onChanged: (v) => set(() => v! ? perms.add(p) : perms.remove(p)),
                ),
              const SizedBox(height: 12),
              FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('حفظ')),
            ]),
          ),
        ),
      ),
    );
    if (ok != true || name.text.trim().isEmpty) return;
    if (u == null && pin.text.trim().length < 4) {
      if (context.mounted) toast(context, 'رمز العامل 4 أرقام على الأقل', error: true);
      return;
    }
    await Session.saveWorker(id: u?.id, name: name.text.trim(), pin: pin.text.trim(), perms: perms, active: active);
    AppState.I.bump();
  }

  Future<void> _changeOwnerCode(BuildContext context) async {
    final code = await askText(context, 'رمز المالك الجديد (6 أرقام على الأقل)');
    if (code == null || code.length < 6) {
      if (code != null && context.mounted) toast(context, 'الرمز قصير', error: true);
      return;
    }
    await Session.changeOwnerCode(code);
    await SyncService.updatePassword(code);
    AppState.I.bump();
    if (context.mounted) toast(context, 'تم تغيير رمز المالك — استخدمه أيضاً لاسترجاع المحل على جهاز جديد');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('العمال والصلاحيات')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(context),
        icon: const Icon(Icons.person_add_alt),
        label: const Text('إضافة عامل'),
      ),
      body: DataBuilder<List<AppUser>>(
        load: () => Session.users(),
        builder: (c, users) => ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 96), children: [
          for (final u in users)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: VCard(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                onTap: u.isOwner ? () => _changeOwnerCode(context) : () => _edit(context, u: u),
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(child: Icon(u.isOwner ? Icons.workspace_premium_outlined : Icons.badge_outlined)),
                  title: Text(u.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(u.isOwner
                      ? 'المالك — كل الصلاحيات (اضغط لتغيير الرمز)'
                      : (u.perms.isEmpty ? 'بيع فقط' : u.perms.map((p) => p.label).join('، '))),
                  trailing: u.isOwner
                      ? null
                      : (u.active ? const StatusChip.good('فعّال') : const StatusChip.neutral('موقوف')),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

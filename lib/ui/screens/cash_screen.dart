import 'package:material_ui/material_ui.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../services/cash_service.dart';
import '../../services/currency_service.dart';
import '../../services/session.dart';
import '../../state/app_state.dart';
import '../widgets/common.dart';

/// الصندوق اليومي: فتح/إقفال الوردية ومطابقة النقد، والمصاريف.
class CashScreen extends StatelessWidget {
  const CashScreen({super.key});

  Future<(Shift?, CashSummary?, List<Map<String, Object?>>, List<Shift>)> _load() async {
    final s = await CashService.currentShift();
    final now = DateTime.now();
    return (
      s,
      s == null ? null : await CashService.summary(s),
      await CashService.expenses(from: startOfDay(now), to: endOfDay(now)),
      await CashService.history(limit: 20),
    );
  }

  Future<void> _open(BuildContext context) async {
    final v = await askNumber(context, 'الرصيد الافتتاحي في الدرج', initial: 0, suffix: CurrencyService.base.symbol);
    if (v == null) return;
    await CashService.openShift(v);
    AppState.I.bump();
  }

  Future<void> _close(BuildContext context, Shift s, CashSummary sm) async {
    final actual = await askNumber(context, 'عدّ النقد الفعلي في الدرج', suffix: CurrencyService.base.symbol,
        hint: 'المتوقع ${Fmt.money(sm.expected)}');
    if (actual == null || !context.mounted) return;
    final note = await askText(context, 'ملاحظة الإقفال (اختياري)');
    final diff = await CashService.closeShift(s, actual, note: note);
    AppState.I.bump();
    if (!context.mounted) return;
    await showDialog(
      context: context,
      builder: (c) => AlertDialog(
        icon: Icon(diff.abs() < 0.01 ? Icons.check_circle : Icons.error_outline,
            color: diff < -0.009 ? VColors.coral : VColors.emerald, size: 48),
        title: const Text('تم إقفال الصندوق'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          KeyValueRow('المتوقع', money(sm.expected)),
          KeyValueRow('الفعلي', money(actual)),
          KeyValueRow(diff < -0.009 ? 'عجز' : (diff > 0.009 ? 'زيادة' : 'مطابق'), money(diff.abs()),
              bold: true, color: diff < -0.009 ? VColors.coral : VColors.emerald),
        ]),
        actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('حسناً'))],
      ),
    );
  }

  Future<void> _expense(BuildContext context) async {
    if (!Session.can(Perm.expenses) && !await requireOwner(context, reason: 'تسجيل المصاريف يحتاج صلاحية')) return;
    if (!context.mounted) return;
    var cat = CashService.expenseCategories.first;
    final amount = TextEditingController();
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('مصروف جديد'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
              initialValue: cat,
              decoration: const InputDecoration(labelText: 'البند'),
              items: [for (final x in CashService.expenseCategories) DropdownMenuItem(value: x, child: Text(x))],
              onChanged: (v) => set(() => cat = v!),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: amount,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: 'المبلغ', suffixText: CurrencyService.base.symbol),
            ),
            TextField(controller: note, decoration: const InputDecoration(labelText: 'ملاحظة')),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('حفظ')),
          ],
        ),
      ),
    );
    if (ok != true || Fmt.parse(amount.text) <= 0) return;
    await CashService.addExpense(cat, Fmt.parse(amount.text), note: note.text.trim().isEmpty ? null : note.text.trim());
    AppState.I.bump();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الصندوق اليومي')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _expense(context),
        icon: const Icon(Icons.remove_circle_outline),
        label: const Text('مصروف'),
      ),
      body: DataBuilder(
        load: _load,
        builder: (context, data) {
          final (shift, sm, expenses, history) = data;
          return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 96), children: [
            if (shift == null)
              VCard(
                child: Column(children: [
                  const Icon(Icons.lock_outline, size: 42),
                  const SizedBox(height: 8),
                  const Text('الصندوق مغلق', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  const Text('افتح الوردية بالرصيد الموجود في الدرج. (تُفتح تلقائياً برصيد صفر عند أول بيع)',
                      textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  FilledButton.icon(onPressed: () => _open(context), icon: const Icon(Icons.lock_open), label: const Text('فتح الصندوق')),
                ]),
              )
            else ...[
              VCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    const Icon(Icons.lock_open, color: VColors.blue),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('وردية مفتوحة منذ ${Fmt.dateTime(shift.openedAt)}',
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ]),
                  Text('فتحها: ${shift.userName ?? '-'}', style: const TextStyle(fontSize: 12)),
                  const Divider(height: 24),
                  KeyValueRow('الرصيد الافتتاحي', money(sm!.opening)),
                  KeyValueRow('+ مبيعات نقدية', money(sm.cashSales), color: VColors.emerald),
                  KeyValueRow('+ تحصيل ديون', money(sm.debtCollections), color: VColors.emerald),
                  KeyValueRow('- مرتجعات نقدية', money(sm.refunds)),
                  KeyValueRow('- مشتريات مدفوعة', money(sm.purchasesPaid)),
                  KeyValueRow('- دفعات للموردين', money(sm.supplierPayments)),
                  KeyValueRow('- مصاريف', money(sm.expenses)),
                  const Divider(height: 20),
                  KeyValueRow('المتوقع في الدرج', money(sm.expected), bold: true),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: () => _close(context, shift, sm),
                    icon: const Icon(Icons.lock_outline),
                    label: const Text('إقفال الصندوق ومطابقة النقد'),
                  ),
                ]),
              ),
            ],
            const SectionTitle('مصاريف اليوم'),
            if (expenses.isEmpty) const Text('لا توجد مصاريف اليوم'),
            for (final e in expenses)
              ListTile(
                leading: const Icon(Icons.receipt_outlined),
                title: Text('${e['category']}${e['note'] != null ? ' • ${e['note']}' : ''}'),
                subtitle: Text('${Fmt.time(DateTime.fromMillisecondsSinceEpoch(e['created_at'] as int))} • ${e['user_name'] ?? ''}'),
                trailing: Text(money((e['amount'] as num).toDouble()), style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            const SectionTitle('الورديات السابقة'),
            for (final s in history.where((s) => !s.isOpen))
              ListTile(
                title: Text('${Fmt.dateTime(s.openedAt)} ← ${Fmt.time(s.closedAt!)}'),
                subtitle: Text('${s.userName ?? ''} • متوقع ${money(s.expected ?? 0)} • فعلي ${money(s.actual ?? 0)}'),
                trailing: (s.diff ?? 0).abs() < 0.01
                    ? const StatusChip.good('مطابق')
                    : (s.diff! < 0 ? StatusChip.alert('عجز ${money(-s.diff!)}') : StatusChip.info('زيادة ${money(s.diff!)}')),
              ),
          ]);
        },
      ),
    );
  }
}

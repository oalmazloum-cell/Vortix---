import 'package:material_ui/material_ui.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/db.dart';
import '../../data/models.dart';
import '../../services/currency_service.dart';
import '../../services/debts_service.dart';
import '../../services/pdf_service.dart';
import '../../services/session.dart';
import '../../services/whatsapp_service.dart';
import '../../state/app_state.dart';
import '../widgets/common.dart';
import 'sales_history_screen.dart';

/// الزبائن والديون.
class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key});
  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  final _search = TextEditingController();
  String _q = '';
  bool _debtorsOnly = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'add_customer',
        onPressed: () => editCustomer(context),
        icon: const Icon(Icons.person_add_alt),
        label: const Text('إضافة زبون'),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: SearchBarV(
            controller: _search,
            hint: 'ابحث بالاسم أو الجوال',
            onChanged: (v) => setState(() => _q = v),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(children: [
            FilterChip(
              label: const Text('عليهم ديون فقط'),
              selected: _debtorsOnly,
              onSelected: (v) => setState(() => _debtorsOnly = v),
            ),
          ]),
        ),
        Expanded(
          child: DataBuilder<List<(Customer, PartyBalance)>>(
            deps: [_q, _debtorsOnly],
            load: () => DebtsService.customersWithBalances(search: _q, onlyDebtors: _debtorsOnly),
            builder: (c, rows) {
              if (rows.isEmpty) return const EmptyState(icon: Icons.people_outline, text: 'لا يوجد زبائن');
              final total = rows.fold<double>(0, (s, r) => s + (r.$2.balance > 0 ? r.$2.balance : 0));
              final overdue = rows.fold<double>(0, (s, r) => s + r.$2.overdue);
              return ListView(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
                children: [
                  Row(children: [
                    Expanded(child: StatCard(title: 'إجمالي الديون', value: money(total), icon: Icons.account_balance_outlined)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: StatCard(
                        title: 'المتأخر',
                        value: overdue > 0 ? money(overdue) : 'لا يوجد',
                        icon: Icons.warning_amber_rounded,
                        color: overdue > 0 ? VColors.coral : null,
                      ),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  for (final (cu, b) in rows)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: VCard(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        onTap: () => Navigator.push(c, MaterialPageRoute(builder: (_) => CustomerDetailScreen(customerId: cu.id))),
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            backgroundColor: b.isOverdue ? VColors.coral.withValues(alpha: 0.15) : null,
                            child: Icon(Icons.person_outline, color: b.isOverdue ? VColors.coral : null),
                          ),
                          title: Text(cu.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text(cu.phone ?? ''),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(money(b.balance),
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700, color: b.isOverdue ? VColors.coral : null, fontSize: 15)),
                              if (b.isOverdue)
                                StatusChip.alert('متأخر ${money(b.overdue)}')
                              else if (b.balance <= 0.009)
                                const StatusChip.good('مسدد'),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ]),
    );
  }
}

Future<void> editCustomer(BuildContext context, {Customer? customer}) async {
  final name = TextEditingController(text: customer?.name);
  final phone = TextEditingController(text: customer?.phone);
  final whats = TextEditingController(text: customer?.whatsapp);
  final limit = TextEditingController(text: (customer?.creditLimit ?? 0) > 0 ? Fmt.money(customer!.creditLimit) : '');
  final opening = TextEditingController();
  final note = TextEditingController(text: customer?.note);
  final form = GlobalKey<FormState>();
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (c) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(c).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: form,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(customer == null ? 'زبون جديد' : 'تعديل الزبون', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            VField(controller: name, label: 'الاسم', icon: Icons.person_outline, validator: requiredValidator),
            VField(controller: phone, label: 'رقم الجوال', icon: Icons.phone_outlined, keyboard: TextInputType.phone),
            VField(controller: whats, label: 'رقم الواتس (إن كان مختلفاً)', icon: Icons.chat_outlined, keyboard: TextInputType.phone),
            VField(controller: limit, label: 'سقف الدين (اختياري)', icon: Icons.speed_outlined, keyboard: TextInputType.number),
            if (customer == null)
              VField(controller: opening, label: 'دين سابق عليه (اختياري)', icon: Icons.history, keyboard: TextInputType.number),
            VField(controller: note, label: 'ملاحظات', icon: Icons.notes),
            FilledButton(
              onPressed: () {
                if (form.currentState!.validate()) Navigator.pop(c, true);
              },
              child: const Text('حفظ'),
            ),
          ]),
        ),
      ),
    ),
  );
  if (ok != true) return;
  final cu = Customer(
    id: customer?.id ?? newId(),
    name: name.text.trim(),
    phone: phone.text.trim(),
    whatsapp: whats.text.trim().isEmpty ? phone.text.trim() : whats.text.trim(),
    note: note.text.trim(),
    creditLimit: Fmt.parse(limit.text),
  );
  await DebtsService.saveCustomer(cu, isNew: customer == null, openingDebt: Fmt.parse(opening.text));
  AppState.I.bump();
}

class CustomerDetailScreen extends StatelessWidget {
  const CustomerDetailScreen({super.key, required this.customerId});
  final String customerId;

  Future<(Customer, PartyBalance, List<LedgerEntry>)?> _load() async {
    final c = await DebtsService.customer(customerId);
    if (c == null) return null;
    final entries = await DebtsService.entries('customer', c.id);
    return (c, DebtsService.computeBalance(entries), entries);
  }

  Future<void> _pay(BuildContext context, Customer c, PartyBalance b) async {
    if (!Session.can(Perm.manageDebts) && !await requireOwner(context, reason: 'تسجيل الدفعات يحتاج صلاحية')) return;
    if (!context.mounted) return;
    var currency = CurrencyService.base.code;
    final amount = TextEditingController(text: b.balance > 0 ? Fmt.money(b.balance).replaceAll(',', '') : '');
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text('دفعة من ${c.name}'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: amount,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'المبلغ',
                suffix: DropdownButton<String>(
                  value: currency,
                  underline: const SizedBox(),
                  items: [for (final x in CurrencyService.all) DropdownMenuItem(value: x.code, child: Text(x.symbol))],
                  onChanged: (v) => set(() => currency = v!),
                ),
              ),
            ),
            TextField(controller: note, decoration: const InputDecoration(labelText: 'ملاحظة')),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تسجيل الدفعة')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final cur = CurrencyService.byCode(currency);
    await DebtsService.receivePayment(c, cur.toBase(Fmt.parse(amount.text)),
        note: note.text.trim().isEmpty ? null : note.text.trim(), currency: cur.code, rate: cur.rate);
    AppState.I.bump();
    if (context.mounted) toast(context, 'تم تسجيل الدفعة ✓');
  }

  Future<void> _manualDebt(BuildContext context, Customer c) async {
    if (!await requireOwner(context, reason: 'تسجيل دين يدوي يحتاج رمز المالك')) return;
    if (!context.mounted) return;
    final v = await askNumber(context, 'مبلغ الدين', suffix: CurrencyService.base.symbol);
    if (v == null || v <= 0) return;
    await DebtsService.addManualDebt(c, v, note: 'دين يدوي');
    AppState.I.bump();
  }

  @override
  Widget build(BuildContext context) {
    return DataBuilder<(Customer, PartyBalance, List<LedgerEntry>)?>(
      load: _load,
      builder: (context, data) {
        if (data == null) return const Scaffold(body: EmptyState(icon: Icons.person_off, text: 'الزبون غير موجود'));
        final (c, b, entries) = data;
        var running = 0.0;
        final withRunning = [
          for (final e in entries) (e, running += e.debit - e.credit),
        ].reversed.toList();
        return Scaffold(
          appBar: AppBar(
            title: Text(c.name),
            actions: [
              IconButton(icon: const Icon(Icons.edit_outlined), onPressed: () => editCustomer(context, customer: c)),
              PopupMenuButton<String>(
                onSelected: (v) async {
                  if (v == 'debt') await _manualDebt(context, c);
                  if (v == 'sales' && context.mounted) {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => SalesHistoryScreen(customerId: c.id)));
                  }
                  if (v == 'delete' && context.mounted) {
                    if (b.balance.abs() > 0.009) {
                      toast(context, 'لا يمكن حذف زبون عليه رصيد', error: true);
                      return;
                    }
                    if (!Session.can(Perm.deleteRecords) && !await requireOwner(context)) return;
                    if (!context.mounted) return;
                    if (await confirm(context, 'حذف الزبون', 'حذف ${c.name}؟', danger: true)) {
                      await DebtsService.deleteCustomer(c);
                      AppState.I.bump();
                      if (context.mounted) Navigator.pop(context);
                    }
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'sales', child: Text('فواتير الزبون')),
                  PopupMenuItem(value: 'debt', child: Text('تسجيل دين يدوي')),
                  PopupMenuItem(value: 'delete', child: Text('حذف الزبون')),
                ],
              ),
            ],
          ),
          body: ListView(padding: const EdgeInsets.all(16), children: [
            VCard(
              child: Column(children: [
                Text('الرصيد المستحق', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                const SizedBox(height: 4),
                Text(money(b.balance),
                    style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700, color: b.isOverdue ? VColors.coral : null)),
                const SizedBox(height: 6),
                if (b.isOverdue)
                  StatusChip.alert(
                      'متأخر ${money(b.overdue)}${b.oldestDue != null ? ' منذ ${Fmt.date(b.oldestDue!)}' : ''}')
                else if (b.balance <= 0.009)
                  const StatusChip.good('مسدد بالكامل'),
                if (c.creditLimit > 0) ...[
                  const SizedBox(height: 6),
                  Text('سقف الدين: ${money(c.creditLimit)}', style: const TextStyle(fontSize: 12)),
                ],
              ]),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _pay(context, c, b),
                  icon: const Icon(Icons.payments_outlined),
                  label: const Text('تسجيل دفعة'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: b.balance <= 0.009
                      ? null
                      : () async {
                          if (!await WhatsappService.sendDebtReminder(c, b) && context.mounted) {
                            toast(context, 'لا يوجد رقم جوال لهذا الزبون', error: true);
                          }
                        },
                  icon: const Icon(Icons.chat_outlined),
                  label: const Text('تذكير واتساب'),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () async {
                final pdf = await PdfService.statement(c, entries, b);
                await WhatsappService.sharePdf(pdf, 'statement-${c.name}.pdf',
                    text: WhatsappService.debtReminderText(c, b));
              },
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: const Text('إرسال كشف الحساب PDF'),
            ),
            const SectionTitle('الحركات'),
            if (entries.isEmpty) const EmptyState(icon: Icons.receipt_outlined, text: 'لا توجد حركات'),
            for (final (e, bal) in withRunning)
              VCard(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(e.credit > 0 ? Icons.south_west : Icons.north_east,
                      color: e.credit > 0 ? VColors.emerald : VColors.blue),
                  title: Text('${e.kindLabel}${e.note != null ? ' • ${e.note}' : ''}', style: const TextStyle(fontSize: 14)),
                  subtitle: Text(
                    '${Fmt.dateTime(e.createdAt)}${e.dueDate != null && e.debit > 0 ? ' • يستحق ${Fmt.date(e.dueDate!)}' : ''}',
                    style: TextStyle(
                      fontSize: 12,
                      color: e.dueDate != null && e.debit > 0 && e.dueDate!.isBefore(DateTime.now()) && b.isOverdue
                          ? VColors.coral
                          : null,
                    ),
                  ),
                  trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text(e.credit > 0 ? '- ${money(e.credit)}' : '+ ${money(e.debit)}',
                        style: TextStyle(fontWeight: FontWeight.w700, color: e.credit > 0 ? VColors.emerald : null)),
                    Text('الرصيد ${money(bal)}', style: const TextStyle(fontSize: 11)),
                  ]),
                ),
              ),
          ]),
        );
      },
    );
  }
}

import 'package:material_ui/material_ui.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../services/currency_service.dart';
import '../../services/debts_service.dart';
import '../../services/inventory_service.dart';
import '../../services/purchase_service.dart';
import '../../state/app_state.dart';
import '../widgets/common.dart';
import '../widgets/pickers.dart';
import 'item_editor_screen.dart';
import 'scanner_screen.dart';

/// المشتريات والموردون.
class PurchasesScreen extends StatelessWidget {
  const PurchasesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('المشتريات والموردون'),
          bottom: const TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white60,
            indicatorColor: VColors.blueBright,
            tabs: [Tab(text: 'فواتير الشراء'), Tab(text: 'الموردون')],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PurchaseEditorScreen())),
          icon: const Icon(Icons.add),
          label: const Text('فاتورة شراء'),
        ),
        body: const TabBarView(children: [_PurchaseList(), _SupplierList()]),
      ),
    );
  }
}

class _PurchaseList extends StatelessWidget {
  const _PurchaseList();
  @override
  Widget build(BuildContext context) => DataBuilder<List<Map<String, Object?>>>(
        load: () => PurchaseService.list(),
        builder: (c, rows) => rows.isEmpty
            ? const EmptyState(icon: Icons.local_shipping_outlined, text: 'لا توجد فواتير شراء بعد')
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(0, 8, 0, 96),
                itemCount: rows.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (c, i) {
                  final r = rows[i];
                  final total = (r['total'] as num).toDouble();
                  final paid = (r['paid'] as num).toDouble();
                  return ListTile(
                    title: Text('#${r['number']} • ${r['supplier_name'] ?? 'بدون مورد'}'),
                    subtitle: Text(Fmt.dateTimeMs(r['created_at'] as int)),
                    trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text(money(total), style: const TextStyle(fontWeight: FontWeight.w700)),
                      paid >= total ? const StatusChip.good('مدفوع') : StatusChip.info('باقي ${money(total - paid)}'),
                    ]),
                    onTap: () => _showLines(context, r),
                  );
                },
              ),
      );

  Future<void> _showLines(BuildContext context, Map<String, Object?> p) async {
    final lines = await PurchaseService.lines('${p['id']}');
    if (!context.mounted) return;
    showModalBottomSheet(
      context: context,
      builder: (c) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          ListTile(title: Text('فاتورة شراء #${p['number']}', style: const TextStyle(fontWeight: FontWeight.w700))),
          for (final l in lines)
            ListTile(
              title: Text('${l['name']}'),
              subtitle: Text('${Fmt.qty(l['qty'] as num)} ${l['unit_name']} × ${money((l['cost'] as num).toDouble())}'),
              trailing: Text(money((l['total'] as num).toDouble())),
            ),
        ]),
      ),
    );
  }
}

class _SupplierList extends StatelessWidget {
  const _SupplierList();
  @override
  Widget build(BuildContext context) => DataBuilder<List<(Supplier, PartyBalance)>>(
        load: DebtsService.suppliersWithBalances,
        builder: (c, rows) => rows.isEmpty
            ? const EmptyState(icon: Icons.local_shipping_outlined, text: 'لا يوجد موردون بعد')
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(0, 8, 0, 96),
                itemCount: rows.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (c, i) {
                  final (s, b) = rows[i];
                  return ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.local_shipping_outlined)),
                    title: Text(s.name),
                    subtitle: Text(s.phone ?? ''),
                    trailing: b.balance > 0.009
                        ? Text('له علينا ${money(b.balance)}', style: const TextStyle(fontWeight: FontWeight.w700))
                        : const StatusChip.good('مسدد'),
                    onTap: () async {
                      final amount = await askNumber(context, 'دفعة للمورد ${s.name}',
                          initial: b.balance > 0 ? b.balance : null, suffix: CurrencyService.base.symbol);
                      if (amount == null || amount <= 0) return;
                      await DebtsService.paySupplier(s, amount);
                      AppState.I.bump();
                      if (context.mounted) toast(context, 'تم تسجيل الدفعة');
                    },
                  );
                },
              ),
      );
}

/// فاتورة شراء من المورد.
class PurchaseEditorScreen extends StatefulWidget {
  const PurchaseEditorScreen({super.key});
  @override
  State<PurchaseEditorScreen> createState() => _PurchaseEditorScreenState();
}

class _PurchaseEditorScreenState extends State<PurchaseEditorScreen> {
  Supplier? _supplier;
  final List<PurchaseLine> _lines = [];
  String _currency = CurrencyService.base.code;
  final _paid = TextEditingController();
  final _note = TextEditingController();
  bool _paidFull = true;
  bool _saving = false;

  Currency get _cur => CurrencyService.byCode(_currency);
  double get _total => _lines.fold(0.0, (s, l) => s + l.total);

  void _addItem(Item it, {ItemUnit? unit}) {
    setState(() {
      final ex = _lines.where((l) => l.item.id == it.id && l.unit?.id == unit?.id).firstOrNull;
      if (ex != null) {
        ex.qty += 1;
      } else {
        _lines.insert(0, PurchaseLine(item: it, unit: unit, cost: it.cost * (unit?.factor ?? 1)));
      }
    });
  }

  Future<void> _scan() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ScannerScreen(
          title: 'مسح أصناف فاتورة الشراء',
          onContinuous: (code) async {
            final hit = await InventoryService.findByBarcode(code);
            if (hit == null) return ScanFeedback('الباركود $code غير مسجل — أضفه من شاشة الأصناف', ok: false);
            _addItem(hit.item, unit: hit.unit);
            return ScanFeedback('✓ ${hit.item.name}');
          },
        ),
      ),
    );
  }

  Future<void> _pick() async {
    final it = await pickItem(context);
    if (it != null) _addItem(it);
  }

  Future<void> _newItem() async {
    final id = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => const ItemEditorScreen()));
    if (id == null) return;
    final it = await InventoryService.byId(id);
    if (it != null) _addItem(it);
  }

  Future<void> _editLine(PurchaseLine l) async {
    final q = TextEditingController(text: Fmt.qty(l.qty).replaceAll(',', ''));
    final c = TextEditingController(text: Fmt.money(_cur.fromBase(l.cost)).replaceAll(',', ''));
    DateTime? exp = l.expiry;
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(l.item.name),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            if (l.item.units.isNotEmpty)
              DropdownButtonFormField<String>(
                initialValue: l.unit?.id ?? '',
                decoration: const InputDecoration(labelText: 'الوحدة'),
                items: [
                  DropdownMenuItem(value: '', child: Text(l.item.unit)),
                  for (final u in l.item.units) DropdownMenuItem(value: u.id, child: Text('${u.name} (${Fmt.qty(u.factor)})')),
                ],
                onChanged: (v) => l.unit = l.item.units.where((u) => u.id == v).firstOrNull,
              ),
            const SizedBox(height: 10),
            TextField(controller: q, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'الكمية')),
            const SizedBox(height: 10),
            TextField(
                controller: c,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: 'تكلفة الوحدة', suffixText: _cur.symbol)),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('تاريخ الانتهاء'),
              subtitle: Text(exp == null ? 'بدون' : Fmt.date(exp!)),
              onTap: () async {
                final d = await showDatePicker(
                    context: ctx,
                    initialDate: DateTime.now().add(const Duration(days: 180)),
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 3650)));
                if (d != null) set(() => exp = d);
              },
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, 'del'), child: const Text('حذف', style: TextStyle(color: VColors.coral))),
            FilledButton(onPressed: () => Navigator.pop(ctx, 'ok'), child: const Text('حفظ')),
          ],
        ),
      ),
    );
    setState(() {
      if (r == 'del') _lines.remove(l);
      if (r == 'ok') {
        l.qty = Fmt.parse(q.text);
        l.cost = _cur.toBase(Fmt.parse(c.text));
        l.expiry = exp;
      }
    });
  }

  Future<void> _save() async {
    if (_lines.isEmpty) return;
    setState(() => _saving = true);
    try {
      await PurchaseService.save(
        lines: _lines.where((l) => l.qty > 0).toList(),
        supplier: _supplier,
        currency: _currency,
        rate: _cur.rate,
        paid: _paidFull ? _total : _cur.toBase(Fmt.parse(_paid.text)),
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      );
      AppState.I.bump();
      if (mounted) {
        toast(context, 'تم حفظ فاتورة الشراء وتحديث المخزون والتكلفة');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) toast(context, '$e'.replaceFirst('Exception: ', ''), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('فاتورة شراء جديدة')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        VCard(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          onTap: () async {
            final s = await pickSupplier(context);
            if (s != null) setState(() => _supplier = s);
          },
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.local_shipping_outlined),
            title: Text(_supplier?.name ?? 'اختر المورد'),
            trailing: const Icon(Icons.chevron_left),
          ),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: FilledButton.icon(onPressed: _scan, icon: const Icon(Icons.qr_code_scanner), label: const Text('مسح الباركود')),
          ),
          const SizedBox(width: 8),
          Expanded(child: OutlinedButton.icon(onPressed: _pick, icon: const Icon(Icons.search), label: const Text('اختيار صنف'))),
          IconButton(tooltip: 'صنف جديد', onPressed: _newItem, icon: const Icon(Icons.add_box_outlined)),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          const Text('العملة:'),
          const SizedBox(width: 8),
          DropdownButton<String>(
            value: _currency,
            items: [for (final c in CurrencyService.all) DropdownMenuItem(value: c.code, child: Text(c.name))],
            onChanged: (v) => setState(() => _currency = v!),
          ),
        ]),
        if (_lines.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('امسح الأصناف الواردة أو اخترها من القائمة', textAlign: TextAlign.center),
          ),
        for (final l in _lines)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              onTap: () => _editLine(l),
              title: Text(l.item.name),
              subtitle: Text(
                  '${Fmt.qty(l.qty)} ${l.unitName} × ${CurrencyService.format(l.cost, _currency)}${l.expiry != null ? ' • ينتهي ${Fmt.date(l.expiry!)}' : ''}'),
              trailing: Text(CurrencyService.format(l.total, _currency), style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        const SizedBox(height: 8),
        SwitchListTile(
          title: const Text('مدفوعة بالكامل'),
          value: _paidFull,
          onChanged: (v) => setState(() => _paidFull = v),
        ),
        if (!_paidFull)
          VField(
              controller: _paid,
              label: 'المدفوع للمورد (${_cur.symbol}) — الباقي يُسجل ديناً عليك',
              keyboard: const TextInputType.numberWithOptions(decimal: true)),
        VField(controller: _note, label: 'ملاحظة'),
        VCard(child: KeyValueRow('إجمالي الفاتورة', CurrencyService.format(_total, _currency), bold: true)),
        const SizedBox(height: 12),
        SizedBox(
          height: 52,
          child: FilledButton.icon(
            onPressed: _saving || _lines.isEmpty ? null : _save,
            icon: const Icon(Icons.save_outlined),
            label: const Text('حفظ فاتورة الشراء'),
          ),
        ),
      ]),
    );
  }
}


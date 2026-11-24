import 'package:material_ui/material_ui.dart';

import '../../core/format.dart';
import '../../data/db.dart';
import '../../data/models.dart';
import '../../services/currency_service.dart';
import '../../services/debts_service.dart';
import '../../services/inventory_service.dart';
import '../../state/app_state.dart';
import 'common.dart';

/// اختيار زبون (مع إمكانية إضافة زبون جديد سريعاً).
Future<Customer?> pickCustomer(BuildContext context) => showModalBottomSheet<Customer>(
      context: context,
      isScrollControlled: true,
      builder: (c) => const _PickerSheet(kind: 'customer'),
    );

Future<Supplier?> pickSupplier(BuildContext context) => showModalBottomSheet<Supplier>(
      context: context,
      isScrollControlled: true,
      builder: (c) => const _PickerSheet(kind: 'supplier'),
    );

Future<Item?> pickItem(BuildContext context) => showModalBottomSheet<Item>(
      context: context,
      isScrollControlled: true,
      builder: (c) => const _PickerSheet(kind: 'item'),
    );

class _PickerSheet extends StatefulWidget {
  const _PickerSheet({required this.kind});
  final String kind;
  @override
  State<_PickerSheet> createState() => _PickerSheetState();
}

class _PickerSheetState extends State<_PickerSheet> {
  final _q = TextEditingController();
  List<Object> _rows = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final q = _q.text.trim();
    List<Object> rows;
    switch (widget.kind) {
      case 'customer':
        rows = await DebtsService.customers(search: q);
      case 'supplier':
        rows = (await DebtsService.suppliers()).where((s) => q.isEmpty || s.name.contains(q)).toList();
      default:
        rows = await InventoryService.items(search: q, withUnits: true);
    }
    if (mounted) setState(() => _rows = rows);
  }

  Future<void> _addNew() async {
    final name = await askText(context, widget.kind == 'customer' ? 'اسم الزبون الجديد' : 'اسم المورد الجديد',
        initial: _q.text.trim());
    if (name == null || name.isEmpty || !mounted) return;
    String? phone = await askText(context, 'رقم الجوال (اختياري)');
    if (widget.kind == 'customer') {
      final c = Customer(id: newId(), name: name, phone: phone, whatsapp: phone);
      await DebtsService.saveCustomer(c, isNew: true);
      AppState.I.bump();
      if (mounted) Navigator.pop(context, c);
    } else {
      final s = Supplier(id: newId(), name: name, phone: phone);
      await DebtsService.saveSupplier(s, isNew: true);
      AppState.I.bump();
      if (mounted) Navigator.pop(context, s);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = switch (widget.kind) { 'customer' => 'اختر الزبون', 'supplier' => 'اختر المورد', _ => 'اختر الصنف' };
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.8,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: Column(children: [
          ListTile(
            title: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            trailing: widget.kind == 'item'
                ? null
                : FilledButton.icon(onPressed: _addNew, icon: const Icon(Icons.add), label: const Text('جديد')),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _q,
              autofocus: true,
              onChanged: (_) => _load(),
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'بحث'),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _rows.isEmpty
                ? const EmptyState(icon: Icons.search_off, text: 'لا توجد نتائج')
                : ListView.separated(
                    itemCount: _rows.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (c, i) {
                      final r = _rows[i];
                      return switch (r) {
                        Customer cu => ListTile(
                            leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                            title: Text(cu.name),
                            subtitle: cu.phone == null ? null : Text(cu.phone!),
                            onTap: () => Navigator.pop(context, cu),
                          ),
                        Supplier s => ListTile(
                            leading: const CircleAvatar(child: Icon(Icons.local_shipping_outlined)),
                            title: Text(s.name),
                            subtitle: s.phone == null ? null : Text(s.phone!),
                            onTap: () => Navigator.pop(context, s),
                          ),
                        Item it => ListTile(
                            title: Text(it.name),
                            subtitle: Text('المتوفر: ${Fmt.qty(it.qty)} ${it.unit} • ${it.barcode ?? ''}'),
                            trailing: Text(money(it.retail)),
                            onTap: () => Navigator.pop(context, it),
                          ),
                        _ => const SizedBox.shrink(),
                      };
                    },
                  ),
          ),
        ]),
      ),
    );
  }
}

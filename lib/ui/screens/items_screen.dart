import 'package:material_ui/material_ui.dart';

import '../../core/config.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../services/currency_service.dart';
import '../../services/device_services.dart';
import '../../services/inventory_service.dart';
import '../../services/session.dart';
import '../../state/app_state.dart';
import '../widgets/common.dart';
import 'item_editor_screen.dart';
import 'scanner_screen.dart';
import 'shell.dart';
import 'stock_count_screen.dart';

/// إدارة المخزون والأصناف.
class ItemsScreen extends StatefulWidget {
  const ItemsScreen({super.key});

  @override
  State<ItemsScreen> createState() => _ItemsScreenState();
}

class _ItemsScreenState extends State<ItemsScreen> {
  final _search = TextEditingController();
  String _filter = 'all';
  String _query = '';

  Future<void> _open({Item? item, String? barcode}) async {
    if (!Session.can(Perm.editItems) && !await requireOwner(context, reason: 'إضافة وتعديل الأصناف يحتاج رمز المالك')) {
      return;
    }
    if (!mounted) return;
    await Navigator.push(
        context, MaterialPageRoute(builder: (_) => ItemEditorScreen(item: item, initialBarcode: barcode)));
  }

  Future<void> _scan() async {
    final code = await scanBarcode(context);
    if (code == null || !mounted) return;
    final hit = await InventoryService.findByBarcode(code);
    if (hit != null) {
      await _open(item: hit.item);
    } else {
      await _open(barcode: code);
    }
  }

  Future<void> _voice() async {
    final ok = await VoiceService.listen((t, isFinal) {
      _search.text = t;
      setState(() => _query = t);
    });
    if (!ok && mounted) toast(context, 'البحث الصوتي غير متاح', error: true);
  }

  Future<void> _menu(Item it) async {
    final a = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(title: Text(it.name, style: const TextStyle(fontWeight: FontWeight.w700))),
          ListTile(leading: const Icon(Icons.edit_outlined), title: const Text('تعديل'), onTap: () => Navigator.pop(c, 'edit')),
          ListTile(
              leading: const Icon(Icons.exposure_outlined), title: const Text('تعديل الكمية'), onTap: () => Navigator.pop(c, 'qty')),
          ListTile(
            leading: Icon(it.favorite ? Icons.star : Icons.star_border),
            title: Text(it.favorite ? 'إزالة من البيع السريع' : 'إضافة للبيع السريع'),
            onTap: () => Navigator.pop(c, 'fav'),
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline, color: VColors.coral),
            title: const Text('حذف'),
            onTap: () => Navigator.pop(c, 'del'),
          ),
        ]),
      ),
    );
    if (!mounted || a == null) return;
    switch (a) {
      case 'edit':
        await _open(item: it);
      case 'qty':
        if (!Session.isOwner && !await requireOwner(context, reason: 'تعديل الكمية يدوياً يحتاج رمز المالك')) return;
        if (!mounted) return;
        final q = await askNumber(context, 'الكمية الفعلية لـ ${it.name}', initial: it.qty, suffix: it.unit);
        if (q == null) return;
        await InventoryService.adjust(it, q, 'تعديل يدوي');
        AppState.I.bump();
      case 'fav':
        await InventoryService.toggleFavorite(it);
        AppState.I.bump();
      case 'del':
        if (!Session.can(Perm.deleteRecords) && !await requireOwner(context)) return;
        if (!mounted) return;
        if (await confirm(context, 'حذف صنف', 'حذف "${it.name}"؟ تبقى فواتيره السابقة محفوظة.', danger: true, ok: 'حذف')) {
          await InventoryService.delete(it);
          AppState.I.bump();
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final canCost = Session.can(Perm.viewProfits);
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'add_item',
        onPressed: () => _open(),
        icon: const Icon(Icons.add),
        label: const Text('إضافة منتج'),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: SearchBarV(
            controller: _search,
            onChanged: (v) => setState(() => _query = v),
            onVoice: _voice,
            onScan: _scan,
          ),
        ),
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            children: [
              for (final (k, label) in [
                ('all', 'الكل'),
                ('low', 'ناقص'),
                ('out', 'نفد'),
                ('expiry', 'الصلاحية'),
                ('fav', 'البيع السريع'),
              ])
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 8),
                  child: ChoiceChip(
                    label: Text(label),
                    selected: _filter == k,
                    selectedColor: VColors.blue,
                    labelStyle: TextStyle(color: _filter == k ? Colors.white : null),
                    onSelected: (_) => setState(() => _filter = k),
                  ),
                ),
              ActionChip(
                avatar: const Icon(Icons.fact_check_outlined, size: 18),
                label: const Text('جرد سريع'),
                onPressed: () => Shell.open(context, const StockCountScreen()),
              ),
            ],
          ),
        ),
        Expanded(
          child: DataBuilder<(List<Item>, double)>(
            deps: [_filter, _query],
            load: () async => (await InventoryService.items(search: _query, filter: _filter), await InventoryService.stockValue()),
            builder: (c, data) {
              final (items, value) = data;
              if (items.isEmpty) {
                return EmptyState(
                  icon: Icons.inventory_2_outlined,
                  text: _query.isEmpty && _filter == 'all' ? 'لا توجد أصناف بعد' : 'لا توجد أصناف مطابقة',
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
                itemCount: items.length + 1,
                itemBuilder: (c, i) {
                  if (i == 0) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        '${items.length} صنف${canCost ? ' • قيمة المخزون بالتكلفة: ${money(value)}' : ''}',
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
                      ),
                    );
                  }
                  final it = items[i - 1];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: VCard(
                      padding: const EdgeInsets.all(12),
                      onTap: () => _menu(it),
                      child: Row(children: [
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              if (it.favorite) const Icon(Icons.star_rounded, color: VColors.blue, size: 16),
                              Expanded(
                                child: Text(it.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                              ),
                            ]),
                            const SizedBox(height: 4),
                            Text(
                              'مفرق ${money(it.retail)}${it.wholesale > 0 ? ' • جملة ${money(it.wholesale)}' : ''}'
                              '${canCost ? ' • تكلفة ${money(it.cost)}' : ''}',
                              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                            ),
                            if (it.barcode != null)
                              Text(it.barcode!,
                                  style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                          ]),
                        ),
                        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                          Text('${Fmt.qty(it.qty)} ${it.unit}', style: const TextStyle(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 4),
                          _status(it),
                        ]),
                      ]),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ]),
    );
  }

  Widget _status(Item it) {
    if (it.isExpired) return const StatusChip.alert('منتهي الصلاحية');
    if (it.isOut) return const StatusChip.alert('نفد');
    if (it.isLow) return const StatusChip.alert('ناقص');
    if (it.isExpiringWithin(AppConfig.expiryWarnDays)) return StatusChip.alert('ينتهي ${Fmt.date(it.expiry!)}');
    return const StatusChip.good('متاح');
  }
}

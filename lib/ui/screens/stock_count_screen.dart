import 'package:material_ui/material_ui.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../services/currency_service.dart';
import '../../services/inventory_service.dart';
import '../../services/session.dart';
import '../../state/app_state.dart';
import '../widgets/common.dart';
import '../widgets/pickers.dart';
import 'scanner_screen.dart';

/// الجرد السريع: امسح الرف بالباركود فيظهر الفرق بين الفعلي والمسجّل.
class StockCountScreen extends StatefulWidget {
  const StockCountScreen({super.key});

  @override
  State<StockCountScreen> createState() => _StockCountScreenState();
}

class _StockCountScreenState extends State<StockCountScreen> {
  final Map<String, (Item, double)> _counted = {};
  bool _saving = false;

  void _inc(Item item, double by) {
    setState(() {
      final cur = _counted[item.id];
      _counted[item.id] = (item, (cur?.$2 ?? 0) + by);
    });
  }

  Future<void> _scan() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ScannerScreen(
          title: 'الجرد بالمسح المتتالي',
          onContinuous: (code) async {
            final hit = await InventoryService.findByBarcode(code);
            if (hit == null) return ScanFeedback('الباركود $code غير مسجل', ok: false);
            final by = hit.unit?.factor ?? 1;
            _inc(hit.item, by);
            return ScanFeedback('${hit.item.name}: ${Fmt.qty(_counted[hit.item.id]!.$2)} ${hit.item.unit}');
          },
        ),
      ),
    );
  }

  Future<void> _addManual() async {
    final it = await pickItem(context);
    if (it == null || !mounted) return;
    final q = await askNumber(context, 'الكمية الفعلية لـ ${it.name}', suffix: it.unit);
    if (q == null) return;
    setState(() => _counted[it.id] = (it, q));
  }

  Future<void> _save() async {
    if (_counted.isEmpty) return;
    final ok = await confirm(context, 'حفظ الجرد',
        'سيتم تعديل كميات ${_counted.length} صنف لتطابق العدّ الفعلي. الأصناف التي لم تُمسح لن تتغير.');
    if (!ok) return;
    setState(() => _saving = true);
    final diff = await InventoryService.saveCount({for (final e in _counted.values) e.$1: e.$2});
    AppState.I.bump();
    if (!mounted) return;
    toast(context, 'تم حفظ الجرد${Session.can(Perm.viewProfits) ? ' • قيمة الفرق ${money(diff)}' : ''}');
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final rows = _counted.values.toList();
    final showCost = Session.can(Perm.viewProfits);
    final diffValue = rows.fold<double>(0, (s, r) => s + (r.$2 - r.$1.qty) * r.$1.cost);
    return Scaffold(
      appBar: AppBar(title: const Text('الجرد السريع')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _scan,
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('ابدأ المسح'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(onPressed: _addManual, icon: const Icon(Icons.add), label: const Text('إضافة يدوي')),
            ),
          ]),
        ),
        Expanded(
          child: rows.isEmpty
              ? const EmptyState(
                  icon: Icons.fact_check_outlined,
                  text: 'امسح باركود كل قطعة على الرف، أو أضف الكمية يدوياً.\nكل مسحة تزيد العدّ بمقدار الوحدة الممسوحة.',
                )
              : ListView.separated(
                  itemCount: rows.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (c, i) {
                    final (it, q) = rows[i];
                    final diff = q - it.qty;
                    return ListTile(
                      title: Text(it.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text('المسجّل: ${Fmt.qty(it.qty)} • الفعلي: ${Fmt.qty(q)} ${it.unit}'),
                      trailing: diff.abs() < 0.0001
                          ? const StatusChip.good('مطابق')
                          : StatusChip.alert('${diff > 0 ? '+' : ''}${Fmt.qty(diff)}'),
                      onTap: () async {
                        final nq = await askNumber(context, 'الكمية الفعلية', initial: q, suffix: it.unit);
                        if (nq != null) setState(() => _counted[it.id] = (it, nq));
                      },
                      onLongPress: () => setState(() => _counted.remove(it.id)),
                    );
                  },
                ),
        ),
        if (rows.isNotEmpty)
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(children: [
                if (showCost)
                  KeyValueRow('قيمة الفرق بالتكلفة', money(diffValue),
                      color: diffValue < 0 ? VColors.coral : null, bold: true),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: const Icon(Icons.save_outlined),
                    label: Text('حفظ الجرد (${rows.length} صنف)'),
                  ),
                ),
              ]),
            ),
          ),
      ]),
    );
  }
}

import 'package:material_ui/material_ui.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../services/currency_service.dart';
import '../../services/sales_service.dart';
import '../../services/session.dart';
import '../../state/app_state.dart';
import '../widgets/common.dart';
import '../widgets/sale_actions.dart';

/// سجل المبيعات والمرتجعات.
class SalesHistoryScreen extends StatefulWidget {
  const SalesHistoryScreen({super.key, this.customerId});
  final String? customerId;

  @override
  State<SalesHistoryScreen> createState() => _SalesHistoryScreenState();
}

class _SalesHistoryScreenState extends State<SalesHistoryScreen> {
  DateTimeRange? _range;
  String? _kind;
  String _q = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('سجل المبيعات'),
        actions: [
          IconButton(
            icon: const Icon(Icons.date_range_outlined),
            onPressed: () async {
              final r = await showDateRangePicker(
                context: context,
                firstDate: DateTime(2024),
                lastDate: DateTime.now(),
                initialDateRange: _range,
              );
              setState(() => _range = r);
            },
          ),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: TextField(
            onChanged: (v) => setState(() => _q = v),
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'رقم الفاتورة أو اسم الزبون'),
          ),
        ),
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            children: [
              for (final (k, l) in [(null, 'الكل'), ('sale', 'مبيعات'), ('return', 'مرتجعات')])
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 8),
                  child: ChoiceChip(label: Text(l), selected: _kind == k, onSelected: (_) => setState(() => _kind = k)),
                ),
              if (_range != null)
                InputChip(
                  label: Text('${Fmt.date(_range!.start)} - ${Fmt.date(_range!.end)}'),
                  onDeleted: () => setState(() => _range = null),
                ),
            ],
          ),
        ),
        Expanded(
          child: DataBuilder<List<Sale>>(
            deps: [_range, _kind, _q],
            load: () => SalesService.list(
              from: _range == null ? null : startOfDay(_range!.start),
              to: _range == null ? null : endOfDay(_range!.end),
              kind: _kind,
              customerId: widget.customerId,
              search: _q,
            ),
            builder: (c, sales) {
              if (sales.isEmpty) return const EmptyState(icon: Icons.receipt_long_outlined, text: 'لا توجد فواتير');
              return ListView.separated(
                itemCount: sales.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (c, i) {
                  final s = sales[i];
                  return ListTile(
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SaleDetailScreen(saleId: s.id))),
                    leading: CircleAvatar(
                      backgroundColor: s.isReturn ? null : VColors.blue.withValues(alpha: 0.12),
                      child: Icon(s.isReturn ? Icons.undo : Icons.receipt_outlined, color: s.isReturn ? null : VColors.blue),
                    ),
                    title: Text('${s.isReturn ? 'مرتجع' : 'فاتورة'} #${s.number}${s.customerName != null ? ' • ${s.customerName}' : ''}'),
                    subtitle: Text('${Fmt.dateTime(s.createdAt)} • ${s.userName ?? ''}'),
                    trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text(CurrencyService.format(s.total, s.currency), style: const TextStyle(fontWeight: FontWeight.w700)),
                      _statusChip(s),
                    ]),
                  );
                },
              );
            },
          ),
        ),
      ]),
    );
  }
}

Widget _statusChip(Sale s) => switch (s.status) {
      'paid' => const StatusChip.good('مدفوع'),
      'refund' => const StatusChip.neutral('مرتجع'),
      _ => StatusChip.info(s.statusLabel),
    };

class SaleDetailScreen extends StatelessWidget {
  const SaleDetailScreen({super.key, required this.saleId});
  final String saleId;

  Future<void> _return(BuildContext context, Sale s) async {
    if (!Session.can(Perm.returns) && !await requireOwner(context, reason: 'المرتجعات تحتاج رمز المالك')) return;
    if (!context.mounted) return;
    final already = await SalesService.returnedQty(s.id);
    if (!context.mounted) return;
    final qty = <String, double>{};
    var mode = (s.customerId != null && s.remaining > 0) ? 'debt' : 'cash';
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('مرتجع من الفاتورة', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              for (final l in s.lines)
                () {
                  final max = l.qty - (already[l.id] ?? 0);
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(l.name),
                    subtitle: Text('المباع ${Fmt.qty(l.qty)} • المتاح للإرجاع ${Fmt.qty(max)} ${l.unitName}'),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: (qty[l.id] ?? 0) <= 0 ? null : () => set(() => qty[l.id] = (qty[l.id] ?? 0) - 1),
                      ),
                      Text(Fmt.qty(qty[l.id] ?? 0), style: const TextStyle(fontWeight: FontWeight.w700)),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline),
                        onPressed: (qty[l.id] ?? 0) + 1 > max ? null : () => set(() => qty[l.id] = (qty[l.id] ?? 0) + 1),
                      ),
                    ]),
                  );
                }(),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: [
                  const ButtonSegment(value: 'cash', label: Text('استرداد نقدي')),
                  ButtonSegment(value: 'debt', label: const Text('خصم من الدين'), enabled: s.customerId != null),
                ],
                selected: {mode},
                onSelectionChanged: (v) => set(() => mode = v.first),
              ),
              const SizedBox(height: 12),
              FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('تأكيد المرتجع')),
            ]),
          ),
        ),
      ),
    );
    if (ok != true) return;
    try {
      final r = await SalesService.returnSale(s, qty, refundMode: mode);
      AppState.I.bump();
      if (context.mounted) toast(context, 'تم المرتجع #${r.number} بقيمة ${CurrencyService.format(r.total, r.currency)}');
    } on SaleException catch (e) {
      if (context.mounted) toast(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DataBuilder<Sale?>(
      load: () => SalesService.byId(saleId),
      builder: (context, s) {
        if (s == null) return const Scaffold(body: EmptyState(icon: Icons.error_outline, text: 'الفاتورة غير موجودة'));
        String m(double v) => CurrencyService.format(v, s.currency);
        final canProfit = Session.can(Perm.viewProfits);
        return Scaffold(
          appBar: AppBar(title: Text('${s.isReturn ? 'مرتجع' : 'فاتورة'} #${s.number}')),
          body: ListView(padding: const EdgeInsets.all(16), children: [
            VCard(
              child: Column(children: [
                KeyValueRow('التاريخ', Fmt.dateTime(s.createdAt)),
                if (s.customerName != null) KeyValueRow('الزبون', s.customerName!),
                KeyValueRow('الكاشير', s.userName ?? '-'),
                KeyValueRow('نوع السعر', s.priceMode == 'wholesale' ? 'جملة' : 'مفرق'),
                Row(children: [const Expanded(child: Text('الحالة')), _statusChip(s)]),
              ]),
            ),
            const SizedBox(height: 12),
            VCard(
              padding: const EdgeInsets.all(8),
              child: Column(children: [
                for (final l in s.lines)
                  ListTile(
                    dense: true,
                    title: Text(l.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text('${Fmt.qty(l.qty)} ${l.unitName} × ${m(l.price)}'),
                    trailing: Text(m(l.total), style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
              ]),
            ),
            const SizedBox(height: 12),
            VCard(
              child: Column(children: [
                KeyValueRow('المجموع', m(s.subtotal)),
                if (s.discount > 0) KeyValueRow('الخصم', m(s.discount)),
                KeyValueRow('الإجمالي', m(s.total), bold: true),
                if (!s.isReturn) KeyValueRow('المدفوع', m(s.paid), color: VColors.emerald),
                if (!s.isReturn && s.remaining > 0) KeyValueRow('المتبقي (دين)', m(s.remaining)),
                if (s.dueDate != null && s.remaining > 0) KeyValueRow('الاستحقاق', Fmt.date(s.dueDate!)),
                if (canProfit && !s.isReturn) KeyValueRow('ربح الفاتورة', money(s.profit), color: VColors.emerald, bold: true),
                if (s.note != null) KeyValueRow('ملاحظة', s.note!),
              ]),
            ),
            const SizedBox(height: 16),
            SaleActions.buttons(context, s),
            if (!s.isReturn) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => _return(context, s),
                icon: const Icon(Icons.undo),
                label: const Text('تسجيل مرتجع'),
              ),
            ],
          ]),
        );
      },
    );
  }
}

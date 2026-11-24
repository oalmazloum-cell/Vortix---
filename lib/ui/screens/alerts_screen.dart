import 'package:material_ui/material_ui.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../services/currency_service.dart';
import '../../services/debts_service.dart';
import '../../services/inventory_service.dart';
import '../../services/whatsapp_service.dart';
import '../widgets/common.dart';
import 'customers_screen.dart';

/// التنبيهات: نقص المخزون، انتهاء الصلاحية، الديون المتأخرة.
class AlertsScreen extends StatelessWidget {
  const AlertsScreen({super.key});

  Future<(List<Item>, List<Item>, List<(Customer, PartyBalance)>)> _load() async => (
        await InventoryService.lowStock(),
        await InventoryService.expiring(),
        (await DebtsService.customersWithBalances(onlyDebtors: true)).where((r) => r.$2.isOverdue).toList(),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('التنبيهات')),
      body: DataBuilder(
        load: _load,
        builder: (context, data) {
          final (low, exp, overdue) = data;
          if (low.isEmpty && exp.isEmpty && overdue.isEmpty) {
            return const EmptyState(icon: Icons.verified_outlined, text: 'لا توجد تنبيهات — كل شيء تمام 👌');
          }
          return ListView(padding: const EdgeInsets.all(16), children: [
            if (overdue.isNotEmpty) ...[
              SectionTitle('ديون متأخرة (${overdue.length})'),
              for (final (c, b) in overdue)
                VCard(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CustomerDetailScreen(customerId: c.id))),
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.warning_amber_rounded, color: VColors.coral),
                    title: Text(c.name),
                    subtitle: Text('متأخر ${money(b.overdue)} منذ ${b.oldestDue == null ? '-' : Fmt.date(b.oldestDue!)}',
                        style: const TextStyle(color: VColors.coral)),
                    trailing: IconButton(
                      tooltip: 'تذكير واتساب',
                      icon: const Icon(Icons.chat_outlined),
                      onPressed: () => WhatsappService.sendDebtReminder(c, b),
                    ),
                  ),
                ),
            ],
            if (low.isNotEmpty) ...[
              SectionTitle('نقص في المخزون (${low.length})'),
              for (final i in low)
                ListTile(
                  leading: const Icon(Icons.inventory_outlined, color: VColors.coral),
                  title: Text(i.name),
                  subtitle: Text('الحد الأدنى ${Fmt.qty(i.minQty)} ${i.unit}'),
                  trailing: StatusChip.alert('${Fmt.qty(i.qty)} ${i.unit}'),
                ),
            ],
            if (exp.isNotEmpty) ...[
              SectionTitle('الصلاحية (${exp.length})'),
              for (final i in exp)
                ListTile(
                  leading: const Icon(Icons.event_busy_outlined, color: VColors.coral),
                  title: Text(i.name),
                  subtitle: Text('الكمية ${Fmt.qty(i.qty)} ${i.unit}'),
                  trailing: StatusChip.alert(i.isExpired ? 'منتهي ${Fmt.date(i.expiry!)}' : 'ينتهي ${Fmt.date(i.expiry!)}'),
                ),
            ],
          ]);
        },
      ),
    );
  }
}

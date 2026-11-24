import 'package:material_ui/material_ui.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../services/audit_service.dart';
import '../widgets/common.dart';

/// سجل العمليات (لا يُمحى) مع التحقق من سلامة السلسلة.
class AuditScreen extends StatefulWidget {
  const AuditScreen({super.key});
  @override
  State<AuditScreen> createState() => _AuditScreenState();
}

class _AuditScreenState extends State<AuditScreen> {
  String _q = '';

  Future<void> _verify() async {
    final broken = await AuditService.verify();
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        icon: Icon(broken == 0 ? Icons.verified : Icons.gpp_bad_outlined,
            color: broken == 0 ? VColors.emerald : VColors.coral, size: 48),
        title: Text(broken == 0 ? 'السجل سليم' : 'تحذير: السجل تم العبث به'),
        content: Text(broken == 0
            ? 'تم التحقق من سلسلة التجزئة لكل العمليات ولم يُكتشف أي تعديل أو حذف.'
            : 'يوجد $broken سجل لا تطابق تجزئته السلسلة — قد يكون الملف عُدّل خارج التطبيق.'),
        actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('حسناً'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('سجل العمليات'),
        actions: [IconButton(tooltip: 'التحقق من السلامة', icon: const Icon(Icons.verified_user_outlined), onPressed: _verify)],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            onChanged: (v) => setState(() => _q = v),
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'بحث في العمليات'),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text('هذا السجل لا يمكن تعديله أو حذفه، ويوثّق كل عملية بيع وحذف وتعديل وخصم.',
              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ),
        Expanded(
          child: DataBuilder<List<AuditEntry>>(
            deps: [_q],
            load: () => AuditService.list(query: _q),
            builder: (c, rows) => ListView.separated(
              itemCount: rows.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (c, i) {
                final e = rows[i];
                final sensitive = e.action.contains('حذف') || e.action.contains('فاشلة') || e.action.contains('تعديل');
                return ListTile(
                  dense: true,
                  leading: Icon(_icon(e.action), color: sensitive ? VColors.coral : VColors.blue),
                  title: Text('${e.action} • ${e.userName ?? '-'}', style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('${Fmt.dateTime(e.createdAt)}${e.details != null ? '\n${e.details}' : ''}'),
                  isThreeLine: e.details != null,
                );
              },
            ),
          ),
        ),
      ]),
    );
  }

  IconData _icon(String a) {
    if (a.contains('بيع')) return Icons.point_of_sale;
    if (a.contains('مرتجع')) return Icons.undo;
    if (a.contains('حذف')) return Icons.delete_outline;
    if (a.contains('دخول') || a.contains('خروج')) return Icons.login;
    if (a.contains('دفعة')) return Icons.payments_outlined;
    if (a.contains('صندوق')) return Icons.account_balance_wallet_outlined;
    return Icons.edit_note;
  }
}

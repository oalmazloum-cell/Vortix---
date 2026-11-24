import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../services/session.dart';
import '../../state/app_state.dart';

bool isDark(BuildContext c) => Theme.of(c).brightness == Brightness.dark;

/// بطاقة بيضاء نقية بحواف ناعمة وظل خفيف.
class VCard extends StatelessWidget {
  const VCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.onTap, this.color});
  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final dark = isDark(context);
    return Container(
      decoration: BoxDecoration(
        color: color ?? (dark ? VColors.darkCard : VColors.card),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: dark ? VColors.darkBorder : VColors.border.withValues(alpha: 0.7)),
        boxShadow: dark
            ? null
            : [BoxShadow(color: const Color(0xFF0F172A).withValues(alpha: 0.05), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// بطاقة إحصائية للوحة التحكم.
class StatCard extends StatelessWidget {
  const StatCard({super.key, required this.title, required this.value, required this.icon, this.color, this.subtitle, this.onTap});
  final String title;
  final String value;
  final IconData icon;
  final Color? color;
  final String? subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = color ?? (isDark(context) ? VColors.darkText : VColors.navy);
    return VCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: c.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, size: 20, color: c),
            ),
            const SizedBox(width: 8),
            Expanded(
                child: Text(title,
                    style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    overflow: TextOverflow.ellipsis)),
          ]),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: c)),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(subtitle!, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ],
      ),
    );
  }
}

/// شبكة بعمودين ارتفاعها حسب المحتوى (بدلاً من نسبة عرض/ارتفاع ثابتة).
class TwoColumnGrid extends StatelessWidget {
  const TwoColumnGrid({super.key, required this.children, this.columns = 2, this.spacing = 12});
  final List<Widget> children;
  final int columns;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i += columns) {
      final slice = children.sublist(i, i + columns > children.length ? children.length : i + columns);
      rows.add(IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (var j = 0; j < columns; j++) ...[
            if (j > 0) SizedBox(width: spacing),
            Expanded(child: j < slice.length ? slice[j] : const SizedBox()),
          ],
        ]),
      ));
      if (i + columns < children.length) rows.add(SizedBox(height: spacing));
    }
    return Column(children: rows);
  }
}

/// شارة حالة: أخضر زمردي للمدفوع/المتاح، أحمر مرجاني للمتأخر/الناقص.
class StatusChip extends StatelessWidget {
  const StatusChip(this.label, {super.key, required this.kind});
  const StatusChip.good(this.label, {super.key}) : kind = StatusKind.good;
  const StatusChip.alert(this.label, {super.key}) : kind = StatusKind.alert;
  const StatusChip.neutral(this.label, {super.key}) : kind = StatusKind.neutral;
  const StatusChip.info(this.label, {super.key}) : kind = StatusKind.info;

  final String label;
  final StatusKind kind;

  @override
  Widget build(BuildContext context) {
    final c = switch (kind) {
      StatusKind.good => VColors.emerald,
      StatusKind.alert => VColors.coral,
      StatusKind.info => VColors.blue,
      StatusKind.neutral => Theme.of(context).colorScheme.onSurfaceVariant,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w700)),
    );
  }
}

enum StatusKind { good, alert, neutral, info }

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 18, 4, 10),
        child: Row(children: [
          Expanded(child: Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
          ?trailing,
        ]),
      );
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.text, this.action});
  final IconData icon;
  final String text;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 56, color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ]),
        ),
      );
}

/// يعيد بناء الشاشة بعد كل تعديل على البيانات.
class DataBuilder<T> extends StatefulWidget {
  const DataBuilder({super.key, required this.load, required this.builder, this.deps = const []});
  final Future<T> Function() load;
  final Widget Function(BuildContext, T) builder;
  final List<Object?> deps;

  @override
  State<DataBuilder<T>> createState() => _DataBuilderState<T>();
}

class _DataBuilderState<T> extends State<DataBuilder<T>> {
  late Future<T> _future;
  int _version = -1;
  List<Object?> _deps = const [];
  T? _last;

  void _reload() {
    _version = AppState.I.version;
    _deps = List.of(widget.deps);
    _future = widget.load().then((v) => _last = v);
  }

  @override
  void initState() {
    super.initState();
    _reload();
    AppState.I.addListener(_onApp);
  }

  void _onApp() {
    if (AppState.I.version != _version && mounted) setState(_reload);
  }

  @override
  void didUpdateWidget(covariant DataBuilder<T> old) {
    super.didUpdateWidget(old);
    if (!_listEq(_deps, widget.deps)) _reload();
  }

  bool _listEq(List a, List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  void dispose() {
    AppState.I.removeListener(_onApp);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<T>(
        future: _future,
        builder: (c, s) {
          if (s.hasError) {
            return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('خطأ: ${s.error}')));
          }
          final data = s.hasData ? s.data as T : _last;
          if (data == null) return const Center(child: CircularProgressIndicator());
          return widget.builder(c, data);
        },
      );
}

// ============================================================ حوارات

void toast(BuildContext context, String msg, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? VColors.coral : VColors.navy,
      duration: Duration(seconds: error ? 4 : 2),
    ));
}

Future<bool> confirm(BuildContext context, String title, String message, {String ok = 'تأكيد', bool danger = false}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
        FilledButton(
          style: danger ? FilledButton.styleFrom(backgroundColor: VColors.coral) : null,
          onPressed: () => Navigator.pop(c, true),
          child: Text(ok),
        ),
      ],
    ),
  );
  return r ?? false;
}

/// يطلب رمز المالك السري لحماية الأرباح والتعديلات الحساسة.
/// إذا كان المستخدم الحالي هو المالك، يمر مباشرة.
Future<bool> requireOwner(BuildContext context, {String reason = 'هذه العملية تحتاج رمز المالك'}) async {
  if (Session.isOwner) return true;
  final ctrl = TextEditingController();
  String? error;
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => AlertDialog(
        title: const Row(children: [Icon(Icons.lock_outline, color: VColors.navy), SizedBox(width: 8), Text('رمز المالك')]),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(reason),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            autofocus: true,
            obscureText: true,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: 'الرمز السري', errorText: error),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
          FilledButton(
            onPressed: () async {
              if (await Session.verifyOwnerCode(ctrl.text)) {
                if (c.mounted) Navigator.pop(c, true);
              } else {
                set(() => error = 'الرمز غير صحيح');
              }
            },
            child: const Text('تأكيد'),
          ),
        ],
      ),
    ),
  );
  return ok ?? false;
}

/// إدخال رقم سريع.
Future<double?> askNumber(BuildContext context, String title, {double? initial, String? hint, String? suffix}) async {
  final ctrl = TextEditingController(text: initial == null ? '' : Fmt.qty(initial).replaceAll(',', ''));
  final r = await showDialog<double>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9٠-٩.٫,]'))],
        decoration: InputDecoration(hintText: hint, suffixText: suffix),
        onSubmitted: (v) => Navigator.pop(c, Fmt.parse(v)),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('إلغاء')),
        FilledButton(onPressed: () => Navigator.pop(c, Fmt.parse(ctrl.text)), child: const Text('حفظ')),
      ],
    ),
  );
  return r;
}

Future<String?> askText(BuildContext context, String title, {String? initial, String? hint}) async {
  final ctrl = TextEditingController(text: initial ?? '');
  return showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: TextField(controller: ctrl, autofocus: true, decoration: InputDecoration(hintText: hint)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('إلغاء')),
        FilledButton(onPressed: () => Navigator.pop(c, ctrl.text.trim()), child: const Text('حفظ')),
      ],
    ),
  );
}

/// حقل نصي بتصميم موحد.
class VField extends StatelessWidget {
  const VField({
    super.key,
    required this.controller,
    required this.label,
    this.icon,
    this.keyboard,
    this.obscure = false,
    this.helper,
    this.validator,
    this.suffix,
    this.maxLines = 1,
    this.onChanged,
    this.textInputAction,
  });

  final TextEditingController controller;
  final String label;
  final IconData? icon;
  final TextInputType? keyboard;
  final bool obscure;
  final String? helper;
  final String? Function(String?)? validator;
  final Widget? suffix;
  final int maxLines;
  final ValueChanged<String>? onChanged;
  final TextInputAction? textInputAction;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextFormField(
          controller: controller,
          keyboardType: keyboard,
          obscureText: obscure,
          validator: validator,
          maxLines: maxLines,
          onChanged: onChanged,
          textInputAction: textInputAction,
          decoration: InputDecoration(
            labelText: label,
            prefixIcon: icon == null ? null : Icon(icon),
            helperText: helper,
            helperMaxLines: 2,
            suffixIcon: suffix,
          ),
        ),
      );
}

String? requiredValidator(String? v) => (v == null || v.trim().isEmpty) ? 'هذا الحقل مطلوب' : null;

/// شريط بحث مع زر البحث الصوتي وزر مسح الباركود.
class SearchBarV extends StatelessWidget {
  const SearchBarV({super.key, required this.controller, required this.onChanged, this.onVoice, this.onScan, this.hint = 'ابحث بالاسم أو الباركود'});
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback? onVoice;
  final VoidCallback? onScan;
  final String hint;

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        onChanged: onChanged,
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: const Icon(Icons.search),
          suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
            if (controller.text.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () {
                  controller.clear();
                  onChanged('');
                },
              ),
            if (onVoice != null) IconButton(tooltip: 'بحث صوتي', icon: const Icon(Icons.mic_none), onPressed: onVoice),
            if (onScan != null)
              IconButton(
                tooltip: 'مسح الباركود',
                icon: const Icon(Icons.qr_code_scanner, color: VColors.blue),
                onPressed: onScan,
              ),
          ]),
        ),
      );
}

class KeyValueRow extends StatelessWidget {
  const KeyValueRow(this.k, this.v, {super.key, this.color, this.bold = false});
  final String k;
  final String v;
  final Color? color;
  final bool bold;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Expanded(child: Text(k, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))),
          Text(v, style: TextStyle(fontWeight: bold ? FontWeight.w700 : FontWeight.w500, color: color, fontSize: bold ? 16 : 14)),
        ]),
      );
}

import 'package:barcode_widget/barcode_widget.dart';
import 'package:material_ui/material_ui.dart';
import 'package:printing/printing.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/db.dart';
import '../../data/models.dart';
import '../../services/currency_service.dart';
import '../../services/inventory_service.dart';
import '../../services/pdf_service.dart';
import '../../services/printer_service.dart';
import '../../services/session.dart';
import '../../state/app_state.dart';
import '../widgets/common.dart';
import 'scanner_screen.dart';

/// إضافة/تعديل صنف: أسعار المفرق والجملة، وحدات متعددة، باركود (مسح أو توليد)،
/// حد أدنى، تاريخ انتهاء، وطباعة ملصقات.
class ItemEditorScreen extends StatefulWidget {
  const ItemEditorScreen({super.key, this.item, this.initialBarcode});
  final Item? item;
  final String? initialBarcode;

  @override
  State<ItemEditorScreen> createState() => _ItemEditorScreenState();
}

class _UnitRow {
  _UnitRow(this.unit)
      : name = TextEditingController(text: unit.name),
        factor = TextEditingController(text: Fmt.qty(unit.factor).replaceAll(',', '')),
        barcode = TextEditingController(text: unit.barcode ?? ''),
        retail = TextEditingController(text: unit.retail == 0 ? '' : _n(unit.retail)),
        wholesale = TextEditingController(text: unit.wholesale == 0 ? '' : _n(unit.wholesale));
  final ItemUnit unit;
  final TextEditingController name, factor, barcode, retail, wholesale;
}

String _n(double v) => Fmt.money(v).replaceAll(',', '');

class _ItemEditorScreenState extends State<ItemEditorScreen> {
  final _form = GlobalKey<FormState>();
  late final Item _item;
  late final bool _isNew;
  late final TextEditingController _name, _barcode, _category, _unit, _cost, _retail, _wholesale, _qty, _min;
  DateTime? _expiry;
  bool _track = true;
  bool _fav = false;
  final List<_UnitRow> _units = [];
  List<String> _categories = [];
  bool _saving = false;

  bool get _canPrice => _isNew || Session.can(Perm.editPrices);
  bool get _canCost => Session.can(Perm.viewProfits);

  @override
  void initState() {
    super.initState();
    _isNew = widget.item == null;
    _item = widget.item ?? Item(id: newId(), name: '');
    _name = TextEditingController(text: _item.name);
    _barcode = TextEditingController(text: widget.initialBarcode ?? _item.barcode ?? '');
    _category = TextEditingController(text: _item.category ?? '');
    _unit = TextEditingController(text: _item.unit);
    _cost = TextEditingController(text: _item.cost == 0 ? '' : _n(_item.cost));
    _retail = TextEditingController(text: _item.retail == 0 ? '' : _n(_item.retail));
    _wholesale = TextEditingController(text: _item.wholesale == 0 ? '' : _n(_item.wholesale));
    _qty = TextEditingController();
    _min = TextEditingController(text: _item.minQty == 0 ? '' : Fmt.qty(_item.minQty));
    _expiry = _item.expiry;
    _track = _item.trackStock;
    _fav = _item.favorite;
    _units.addAll(_item.units.map(_UnitRow.new));
    InventoryService.categories().then((c) => setState(() => _categories = c));
  }

  Future<void> _scanInto(TextEditingController c) async {
    final code = await scanBarcode(context);
    if (code != null) setState(() => c.text = code);
  }

  Future<void> _generate(TextEditingController c) async {
    final code = await InventoryService.generateInternalBarcode();
    setState(() => c.text = code);
  }

  void _addUnit() {
    setState(() => _units.add(_UnitRow(ItemUnit(id: newId(), itemId: _item.id, name: 'كرتونة', factor: 12))));
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final codes = [_barcode.text.trim(), ..._units.map((u) => u.barcode.text.trim())].where((c) => c.isNotEmpty).toList();
    if (codes.toSet().length != codes.length) {
      toast(context, 'يوجد باركود مكرر بين الوحدات', error: true);
      return;
    }
    for (final c in codes) {
      if (await InventoryService.barcodeTaken(c, exceptItemId: _item.id)) {
        if (mounted) toast(context, 'الباركود $c مستخدم لصنف آخر', error: true);
        return;
      }
    }
    setState(() => _saving = true);
    _item
      ..name = _name.text.trim()
      ..barcode = _barcode.text.trim()
      ..category = _category.text.trim().isEmpty ? null : _category.text.trim()
      ..unit = _unit.text.trim().isEmpty ? 'حبة' : _unit.text.trim()
      ..cost = _canCost ? Fmt.parse(_cost.text) : _item.cost
      ..retail = Fmt.parse(_retail.text)
      ..wholesale = Fmt.parse(_wholesale.text)
      ..minQty = Fmt.parse(_min.text)
      ..expiry = _expiry
      ..trackStock = _track
      ..favorite = _fav
      ..units = [
        for (final u in _units)
          if (u.name.text.trim().isNotEmpty && Fmt.parse(u.factor.text) > 0)
            ItemUnit(
              id: u.unit.id,
              itemId: _item.id,
              name: u.name.text.trim(),
              factor: Fmt.parse(u.factor.text),
              barcode: u.barcode.text.trim(),
              retail: Fmt.parse(u.retail.text),
              wholesale: Fmt.parse(u.wholesale.text),
            ),
      ];
    try {
      final id = await InventoryService.save(_item, isNew: _isNew, openingQty: _isNew ? Fmt.parse(_qty.text) : null);
      AppState.I.bump();
      if (mounted) Navigator.pop(context, id);
    } catch (e) {
      if (mounted) toast(context, 'تعذر الحفظ: $e', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _printLabels() async {
    final code = _barcode.text.trim();
    if (code.isEmpty) {
      toast(context, 'أضف باركوداً أولاً (امسحه أو ولّد باركوداً داخلياً)', error: true);
      return;
    }
    final copies = await askNumber(context, 'عدد الملصقات', initial: 1);
    if (copies == null || copies <= 0 || !mounted) return;
    final item = Item(id: _item.id, name: _name.text.trim(), unit: _unit.text);
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
              leading: const Icon(Icons.print_outlined),
              title: const Text('طابعة ملصقات / عادية (PDF)'),
              onTap: () => Navigator.pop(c, 'pdf')),
          ListTile(
              leading: const Icon(Icons.receipt_outlined),
              title: const Text('الطابعة الحرارية (بلوتوث)'),
              onTap: () => Navigator.pop(c, 'thermal')),
        ]),
      ),
    );
    if (choice == null) return;
    final width = choice == 'thermal' ? (await PrinterService.paperWidth()).toDouble() - 8 : 50.0;
    final pdf = await PdfService.labels([(item, code, Fmt.parse(_retail.text), copies.toInt())],
        labelW: width, labelH: 30);
    try {
      if (choice == 'pdf') {
        await Printing.layoutPdf(onLayout: (_) async => pdf, name: 'labels');
      } else {
        await PrinterService.printPdf(pdf);
      }
    } catch (e) {
      if (mounted) toast(context, '$e'.replaceFirst('Exception: ', ''), error: true);
    }
  }

  Widget _barcodeField(TextEditingController c, {String label = 'الباركود'}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextFormField(
          controller: c,
          keyboardType: TextInputType.number,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: label,
            prefixIcon: const Icon(Icons.qr_code_2),
            suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                tooltip: 'مسح الباركود',
                icon: const Icon(Icons.qr_code_scanner, color: VColors.blue),
                onPressed: () => _scanInto(c),
              ),
              IconButton(tooltip: 'توليد باركود داخلي', icon: const Icon(Icons.auto_awesome_outlined), onPressed: () => _generate(c)),
            ]),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final base = CurrencyService.base.symbol;
    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? 'إضافة منتج' : 'تعديل ${_item.name}'),
        actions: [IconButton(tooltip: 'طباعة ملصقات', icon: const Icon(Icons.label_outline), onPressed: _printLabels)],
      ),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          VCard(
            child: Column(children: [
              VField(controller: _name, label: 'اسم الصنف', icon: Icons.label_outline, validator: requiredValidator),
              _barcodeField(_barcode),
              if (_barcode.text.trim().length >= 4)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Container(
                    color: Colors.white,
                    padding: const EdgeInsets.all(8),
                    child: BarcodeWidget(
                      barcode: _barcode.text.trim().length == 13 && RegExp(r'^\d+$').hasMatch(_barcode.text.trim())
                          ? Barcode.ean13()
                          : Barcode.code128(),
                      data: _barcode.text.trim(),
                      height: 60,
                      errorBuilder: (c, e) => const Text('باركود غير صالح للعرض', style: TextStyle(color: Colors.black)),
                    ),
                  ),
                ),
              Autocomplete<String>(
                initialValue: TextEditingValue(text: _category.text),
                optionsBuilder: (v) => _categories.where((c) => c.contains(v.text)),
                onSelected: (v) => _category.text = v,
                fieldViewBuilder: (c, ctrl, focus, submit) {
                  ctrl.addListener(() => _category.text = ctrl.text);
                  return TextField(
                    controller: ctrl,
                    focusNode: focus,
                    decoration: const InputDecoration(labelText: 'التصنيف (اختياري)', prefixIcon: Icon(Icons.category_outlined)),
                  );
                },
              ),
              const SizedBox(height: 12),
              VField(controller: _unit, label: 'الوحدة الأساسية (حبة، كيلو، علبة...)', icon: Icons.straighten),
            ]),
          ),
          const SectionTitle('الأسعار'),
          VCard(
            child: Column(children: [
              if (_canCost)
                VField(
                    controller: _cost,
                    label: 'سعر التكلفة (الشراء)',
                    icon: Icons.shopping_bag_outlined,
                    keyboard: const TextInputType.numberWithOptions(decimal: true),
                    suffix: Padding(padding: const EdgeInsets.all(14), child: Text(base))),
              TextFormField(
                controller: _retail,
                enabled: _canPrice,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: (v) => Fmt.parse(v ?? '') <= 0 ? 'أدخل سعر البيع' : null,
                decoration: InputDecoration(
                  labelText: 'سعر المفرق',
                  prefixIcon: const Icon(Icons.sell_outlined),
                  suffixText: base,
                  helperText: _canPrice ? null : 'تعديل الأسعار يحتاج صلاحية',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _wholesale,
                enabled: _canPrice,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                    labelText: 'سعر الجملة (اختياري)', prefixIcon: const Icon(Icons.local_offer_outlined), suffixText: base),
              ),
            ]),
          ),
          const SectionTitle('المخزون والتنبيهات'),
          VCard(
            child: Column(children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('تتبع الكمية في المخزون'),
                value: _track,
                onChanged: (v) => setState(() => _track = v),
              ),
              if (_isNew && _track)
                VField(
                    controller: _qty,
                    label: 'الكمية الحالية (افتتاحي)',
                    icon: Icons.inventory_outlined,
                    keyboard: const TextInputType.numberWithOptions(decimal: true)),
              if (!_isNew && _track)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: KeyValueRow('الكمية الحالية', '${Fmt.qty(_item.qty)} ${_item.unit}', bold: true),
                ),
              if (_track)
                VField(
                  controller: _min,
                  label: 'الحد الأدنى (تنبيه عند النقص)',
                  icon: Icons.notification_important_outlined,
                  keyboard: const TextInputType.numberWithOptions(decimal: true),
                ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_busy_outlined),
                title: const Text('تاريخ انتهاء الصلاحية'),
                subtitle: Text(_expiry == null ? 'لا يوجد' : Fmt.date(_expiry!)),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (_expiry != null) IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _expiry = null)),
                  const Icon(Icons.calendar_month_outlined),
                ]),
                onTap: () async {
                  final d = await showDatePicker(
                    context: context,
                    initialDate: _expiry ?? DateTime.now().add(const Duration(days: 180)),
                    firstDate: DateTime.now().subtract(const Duration(days: 365)),
                    lastDate: DateTime.now().add(const Duration(days: 3650)),
                  );
                  if (d != null) setState(() => _expiry = d);
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('إظهار في شاشة البيع السريع'),
                value: _fav,
                onChanged: (v) => setState(() => _fav = v),
              ),
            ]),
          ),
          SectionTitle('الوحدات الإضافية',
              trailing: TextButton.icon(onPressed: _addUnit, icon: const Icon(Icons.add), label: const Text('إضافة وحدة'))),
          if (_units.isEmpty)
            Text('مثال: كرتونة = 24 ${_unit.text}، بسعر وباركود خاص بها.',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          for (final u in _units)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: VCard(
                child: Column(children: [
                  Row(children: [
                    Expanded(child: VField(controller: u.name, label: 'اسم الوحدة')),
                    const SizedBox(width: 8),
                    Expanded(
                      child: VField(
                        controller: u.factor,
                        label: 'تحتوي (${_unit.text})',
                        keyboard: const TextInputType.numberWithOptions(decimal: true),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: VColors.coral),
                      onPressed: () => setState(() => _units.remove(u)),
                    ),
                  ]),
                  _barcodeField(u.barcode, label: 'باركود الوحدة (اختياري)'),
                  Row(children: [
                    Expanded(
                      child: VField(
                          controller: u.retail,
                          label: 'سعر المفرق',
                          keyboard: const TextInputType.numberWithOptions(decimal: true)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: VField(
                          controller: u.wholesale,
                          label: 'سعر الجملة',
                          keyboard: const TextInputType.numberWithOptions(decimal: true)),
                    ),
                  ]),
                ]),
              ),
            ),
          const SizedBox(height: 16),
          SizedBox(
            height: 52,
            child: FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.save_outlined),
              label: Text(_isNew ? 'إضافة المنتج' : 'حفظ التعديلات'),
            ),
          ),
          const SizedBox(height: 24),
        ]),
      ),
    );
  }
}

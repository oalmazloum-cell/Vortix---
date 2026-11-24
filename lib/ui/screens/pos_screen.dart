import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../services/currency_service.dart';
import '../../services/debts_service.dart';
import '../../services/device_services.dart';
import '../../services/inventory_service.dart';
import '../../services/sales_service.dart';
import '../../services/session.dart';
import '../../services/subscription_service.dart';
import '../../state/app_state.dart';
import '../widgets/common.dart';
import '../widgets/pickers.dart';
import '../widgets/sale_actions.dart';
import 'item_editor_screen.dart';
import 'scanner_screen.dart';
import 'shell.dart';
import 'subscription_screen.dart';

/// نقطة البيع (الكاشير) مع شاشة البيع السريع.
class PosScreen extends StatefulWidget {
  const PosScreen({super.key});

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  final List<CartLine> _cart = [];
  PriceMode _mode = PriceMode.retail;
  String _currency = CurrencyService.base.code;
  List<Item> _results = [];
  bool _listening = false;
  bool _cartExpanded = true;

  double get _total => _cart.fold(0.0, (s, l) => s + l.total);
  int get _count => _cart.fold(0, (s, l) => s + (l.qty == l.qty.roundToDouble() ? l.qty.toInt() : 1));

  Currency get _cur => CurrencyService.byCode(_currency);

  // ------------------------------------------------------------ السلة

  void _add(Item item, {ItemUnit? unit, double qty = 1}) {
    HapticFeedback.selectionClick();
    setState(() {
      final existing = _cart.where((l) => l.item.id == item.id && l.unit?.id == unit?.id).firstOrNull;
      if (existing != null) {
        existing.qty += qty;
        _cart
          ..remove(existing)
          ..insert(0, existing);
      } else {
        _cart.insert(0, CartLine(item: item, unit: unit, qty: qty, price: CartLine.priceFor(item, unit, _mode)));
      }
    });
    if (item.trackStock && item.qty - _inCart(item) < 0) {
      toast(context, 'تنبيه: الكمية المتوفرة من ${item.name} غير كافية (${Fmt.qty(item.qty)})', error: true);
    }
  }

  double _inCart(Item item) => _cart.where((l) => l.item.id == item.id).fold(0.0, (s, l) => s + l.baseQty);

  void _setMode(PriceMode m) {
    setState(() {
      _mode = m;
      for (final l in _cart) {
        l.price = CartLine.priceFor(l.item, l.unit, m);
      }
    });
  }

  /// يعالج نص البحث أو باركود من قارئ خارجي (يكتب الرقم ثم Enter).
  Future<bool> _addByCode(String code) async {
    final hit = await InventoryService.findByBarcode(code);
    if (hit == null) return false;
    _add(hit.item, unit: hit.unit);
    return true;
  }

  Future<void> _onSubmit(String v) async {
    if (v.trim().isEmpty) return;
    if (await _addByCode(v)) {
      _search.clear();
      setState(() => _results = []);
    } else if (_results.length == 1) {
      _pickUnitAndAdd(_results.first);
      _search.clear();
      setState(() => _results = []);
    } else if (RegExp(r'^\d{6,}$').hasMatch(Fmt.normalizeDigits(v.trim()))) {
      await _unknownBarcode(v.trim());
    }
    _searchFocus.requestFocus();
  }

  Future<void> _onSearch(String v) async {
    if (v.trim().isEmpty) {
      setState(() => _results = []);
      return;
    }
    final r = await InventoryService.items(search: v, withUnits: true);
    if (mounted && _search.text == v) setState(() => _results = r.take(30).toList());
  }

  Future<void> _unknownBarcode(String code) async {
    if (!Session.can(Perm.editItems)) {
      toast(context, 'الباركود $code غير مسجل', error: true);
      return;
    }
    final add = await confirm(context, 'باركود غير مسجل', 'الباركود $code غير موجود. هل تريد إضافة صنف جديد به؟',
        ok: 'إضافة صنف');
    if (!add || !mounted) return;
    final id = await Navigator.push<String>(
        context, MaterialPageRoute(builder: (_) => ItemEditorScreen(initialBarcode: code)));
    if (id != null) {
      final item = await InventoryService.byId(id);
      if (item != null) _add(item);
    }
  }

  Future<void> _scanOnce() async {
    final code = await scanBarcode(context, title: 'امسح باركود الصنف');
    if (code == null || !mounted) return;
    if (!await _addByCode(code)) await _unknownBarcode(code);
  }

  Future<void> _scanContinuous() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ScannerScreen(
          title: 'مسح متتالي للبيع',
          onContinuous: (code) async {
            final hit = await InventoryService.findByBarcode(code);
            if (hit == null) return ScanFeedback('الباركود $code غير مسجل', ok: false);
            _add(hit.item, unit: hit.unit);
            return ScanFeedback('✓ ${hit.item.name} — المجموع ${CurrencyService.format(_total, _currency)}');
          },
        ),
      ),
    );
  }

  Future<void> _voice() async {
    if (_listening) {
      await VoiceService.stop();
      setState(() => _listening = false);
      return;
    }
    setState(() => _listening = true);
    final ok = await VoiceService.listen((text, isFinal) {
      _search.text = text;
      _onSearch(text);
      if (isFinal && mounted) setState(() => _listening = false);
    });
    if (!ok && mounted) {
      setState(() => _listening = false);
      toast(context, 'البحث الصوتي غير متاح على هذا الجهاز', error: true);
    }
  }

  Future<void> _pickUnitAndAdd(Item item) async {
    if (item.units.isEmpty) {
      _add(item);
      return;
    }
    final unit = await showModalBottomSheet<Object>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(title: Text(item.name, style: const TextStyle(fontWeight: FontWeight.w700))),
          ListTile(
            leading: const Icon(Icons.looks_one_outlined),
            title: Text(item.unit),
            trailing: Text(CurrencyService.format(CartLine.priceFor(item, null, _mode), _currency)),
            onTap: () => Navigator.pop(c, 'base'),
          ),
          for (final u in item.units)
            ListTile(
              leading: const Icon(Icons.all_inbox_outlined),
              title: Text('${u.name} (${Fmt.qty(u.factor)} ${item.unit})'),
              trailing: Text(CurrencyService.format(CartLine.priceFor(item, u, _mode), _currency)),
              onTap: () => Navigator.pop(c, u),
            ),
        ]),
      ),
    );
    if (unit == null) return;
    _add(item, unit: unit is ItemUnit ? unit : null);
  }

  Future<void> _editLine(CartLine l) async {
    final qtyCtrl = TextEditingController(text: Fmt.qty(l.qty).replaceAll(',', ''));
    final priceCtrl = TextEditingController(text: Fmt.money(_cur.fromBase(l.price)).replaceAll(',', ''));
    final canPrice = Session.can(Perm.editPrices);
    final result = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(l.item.name),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: qtyCtrl,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: 'الكمية', suffixText: l.unitName),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: priceCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'سعر الوحدة',
              suffixText: _cur.symbol,
              helperText: canPrice ? null : 'تعديل السعر يحتاج رمز المالك',
            ),
          ),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, 'delete'),
            child: const Text('حذف من السلة', style: TextStyle(color: VColors.coral)),
          ),
          FilledButton(onPressed: () => Navigator.pop(c, 'ok'), child: const Text('حفظ')),
        ],
      ),
    );
    if (result == 'delete') {
      setState(() => _cart.remove(l));
    } else if (result == 'ok') {
      final q = Fmt.parse(qtyCtrl.text);
      final p = _cur.toBase(Fmt.parse(priceCtrl.text));
      if ((p - l.price).abs() > 0.001) {
        if (!canPrice && !(mounted && await requireOwner(context, reason: 'تعديل سعر البيع يحتاج رمز المالك'))) return;
      }
      setState(() {
        if (q > 0) l.qty = q;
        if (p >= 0) l.price = p;
      });
    }
  }

  // ------------------------------------------------------------ إتمام البيع

  Future<void> _checkout() async {
    if (_cart.isEmpty) return;
    final sub = AppState.I.sub ?? await SubscriptionService.status();
    if (sub.state == SubState.expired) {
      if (!mounted) return;
      final go = await confirm(context, 'انتهت الفترة التجريبية',
          'انتهت التجربة المجانية. فعّل الاشتراك لمتابعة البيع — بياناتك كلها محفوظة.', ok: 'تفعيل الاشتراك');
      if (go && mounted) Shell.open(context, const SubscriptionScreen());
      return;
    }
    if (!mounted) return;
    final sale = await showModalBottomSheet<Sale>(
      context: context,
      isScrollControlled: true,
      builder: (c) => _CheckoutSheet(cart: _cart, mode: _mode, currency: _cur),
    );
    if (sale == null || !mounted) return;
    setState(() => _cart.clear());
    AppState.I.bump();
    _showDone(sale);
  }

  void _showDone(Sale s) {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        icon: const Icon(Icons.check_circle, color: VColors.emerald, size: 56),
        title: Text('تم البيع — فاتورة #${s.number}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(CurrencyService.format(s.total, s.currency),
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: VColors.emerald)),
          const SizedBox(height: 6),
          s.status == 'paid' ? const StatusChip.good('مدفوع') : StatusChip.info(s.statusLabel),
          if (s.remaining > 0) ...[
            const SizedBox(height: 6),
            Text('دين على ${s.customerName}: ${CurrencyService.format(s.remaining, s.currency)}'),
          ],
          const SizedBox(height: 16),
          SaleActions.buttons(c, s),
        ]),
        actions: [
          FilledButton(onPressed: () => Navigator.pop(c), child: const Text('بيع جديد')),
        ],
      ),
    );
  }

  // ------------------------------------------------------------ الواجهة

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Container(
        color: Theme.of(context).colorScheme.surface,
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        child: Column(children: [
          Row(children: [
            Expanded(
              child: TextField(
                controller: _search,
                focusNode: _searchFocus,
                onChanged: _onSearch,
                onSubmitted: _onSubmit,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: _listening ? 'تكلم الآن...' : 'ابحث بالاسم أو امسح الباركود',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: IconButton(
                    tooltip: 'بحث صوتي',
                    icon: Icon(_listening ? Icons.mic : Icons.mic_none, color: _listening ? VColors.blue : null),
                    onPressed: _voice,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 52,
              child: FilledButton(
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14)),
                onPressed: _scanOnce,
                onLongPress: _scanContinuous,
                child: const Icon(Icons.qr_code_scanner),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            SegmentedButton<PriceMode>(
              segments: const [
                ButtonSegment(value: PriceMode.retail, label: Text('مفرق')),
                ButtonSegment(value: PriceMode.wholesale, label: Text('جملة')),
              ],
              selected: {_mode},
              showSelectedIcon: false,
              onSelectionChanged: (s) => _setMode(s.first),
              style: ButtonStyle(visualDensity: VisualDensity.compact),
            ),
            const Spacer(),
            IconButton(
              tooltip: 'مسح متتالي',
              onPressed: _scanContinuous,
              icon: const Icon(Icons.burst_mode_outlined, color: VColors.blue),
            ),
            DropdownButton<String>(
              value: _currency,
              underline: const SizedBox(),
              selectedItemBuilder: (_) => [
                for (final c in CurrencyService.all)
                  Center(child: Text(c.symbol, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
              ],
              items: [
                for (final c in CurrencyService.all) DropdownMenuItem(value: c.code, child: Text('${c.symbol} ${c.name}')),
              ],
              onChanged: (v) => setState(() => _currency = v!),
            ),
          ]),
        ]),
      ),
      Expanded(child: _search.text.isEmpty ? _quickGrid() : _resultsList()),
      if (_cart.isNotEmpty) _cartPanel(),
      _bottomBar(),
    ]);
  }

  Widget _quickGrid() => DataBuilder<List<Item>>(
        load: () => InventoryService.quickItems(limit: 30),
        builder: (c, items) {
          if (items.isEmpty) {
            return EmptyState(
              icon: Icons.inventory_2_outlined,
              text: 'لا توجد أصناف بعد. أضف أصنافك لتظهر هنا للبيع السريع.',
              action: FilledButton.icon(
                onPressed: () => ShellState.of(context)?.goTab(2),
                icon: const Icon(Icons.add),
                label: const Text('إضافة منتج'),
              ),
            );
          }
          return GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 130,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 0.95,
            ),
            itemCount: items.length,
            itemBuilder: (c, i) {
              final it = items[i];
              final inCart = _inCart(it);
              return VCard(
                padding: const EdgeInsets.all(10),
                onTap: () => _add(it),
                child: GestureDetector(
                  onLongPress: () => _pickUnitAndAdd(it),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      if (it.favorite) const Icon(Icons.star_rounded, size: 16, color: VColors.blue),
                      const Spacer(),
                      if (inCart > 0)
                        CircleAvatar(
                          radius: 11,
                          backgroundColor: VColors.blue,
                          child: Text(Fmt.qty(inCart), style: const TextStyle(color: Colors.white, fontSize: 10)),
                        ),
                    ]),
                    const Spacer(),
                    Text(it.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(CurrencyService.format(CartLine.priceFor(it, null, _mode), _currency),
                        style: const TextStyle(color: VColors.blue, fontWeight: FontWeight.w700, fontSize: 13)),
                    if (it.isOut)
                      const Text('نفد', style: TextStyle(color: VColors.coral, fontSize: 11, fontWeight: FontWeight.w700)),
                  ]),
                ),
              );
            },
          );
        },
      );

  Widget _resultsList() {
    if (_results.isEmpty) {
      return EmptyState(icon: Icons.search_off, text: 'لا توجد نتائج لـ "${_search.text}"');
    }
    return ListView.separated(
      itemCount: _results.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (c, i) {
        final it = _results[i];
        return ListTile(
          title: Text(it.name, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text('${it.barcode ?? ''}  •  المتوفر: ${Fmt.qty(it.qty)} ${it.unit}'),
          trailing: Text(CurrencyService.format(CartLine.priceFor(it, null, _mode), _currency),
              style: const TextStyle(fontWeight: FontWeight.w700, color: VColors.blue)),
          onTap: () {
            _pickUnitAndAdd(it);
            _search.clear();
            setState(() => _results = []);
          },
        );
      },
    );
  }

  Widget _cartPanel() {
    final maxH = MediaQuery.sizeOf(context).height * 0.34;
    return Material(
      color: Theme.of(context).colorScheme.surface,
      elevation: 6,
      shadowColor: Colors.black26,
      shape: Border(top: BorderSide(color: Theme.of(context).colorScheme.outline)),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        InkWell(
          onTap: () => setState(() => _cartExpanded = !_cartExpanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(children: [
              const Icon(Icons.shopping_cart_outlined, size: 20),
              const SizedBox(width: 8),
              Text('السلة (${_cart.length} صنف)', style: const TextStyle(fontWeight: FontWeight.w700)),
              const Spacer(),
              TextButton(
                onPressed: () async {
                  if (await confirm(context, 'تفريغ السلة', 'حذف كل الأصناف من السلة؟', danger: true)) {
                    setState(() => _cart.clear());
                  }
                },
                child: const Text('تفريغ'),
              ),
              Icon(_cartExpanded ? Icons.expand_more : Icons.expand_less),
            ]),
          ),
        ),
        if (_cartExpanded)
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxH),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _cart.length,
              itemBuilder: (c, i) {
                final l = _cart[i];
                return ListTile(
                  dense: true,
                  onTap: () => _editLine(l),
                  title: Text(l.item.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('${CurrencyService.format(l.price, _currency)} / ${l.unitName}'),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: () => setState(() {
                        if (l.qty > 1) {
                          l.qty -= 1;
                        } else {
                          _cart.removeAt(i);
                        }
                      }),
                    ),
                    Text(Fmt.qty(l.qty), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.add_circle_outline, color: VColors.blue),
                      onPressed: () => setState(() => l.qty += 1),
                    ),
                    SizedBox(
                      width: 78,
                      child: Text(CurrencyService.format(l.total, _currency),
                          textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ]),
                );
              },
            ),
          ),
      ]),
    );
  }

  Widget _bottomBar() => Container(
        color: Theme.of(context).colorScheme.surface,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text('الإجمالي ($_count قطعة)', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
              FittedBox(
                child: Text(CurrencyService.format(_total, _currency),
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
              ),
            ]),
          ),
          SizedBox(
            height: 54,
            child: FilledButton.icon(
              onPressed: _cart.isEmpty ? null : _checkout,
              icon: const Icon(Icons.task_alt),
              label: const Text('إتمام البيع', style: TextStyle(fontSize: 17)),
            ),
          ),
        ]),
      );
}

/// نافذة إتمام البيع: الزبون، الخصم، المدفوع، الدين وتاريخ الاستحقاق.
class _CheckoutSheet extends StatefulWidget {
  const _CheckoutSheet({required this.cart, required this.mode, required this.currency});
  final List<CartLine> cart;
  final PriceMode mode;
  final Currency currency;

  @override
  State<_CheckoutSheet> createState() => _CheckoutSheetState();
}

class _CheckoutSheetState extends State<_CheckoutSheet> {
  Customer? _customer;
  PartyBalance? _balance;
  final _discount = TextEditingController();
  final _paid = TextEditingController();
  final _note = TextEditingController();
  bool _credit = false;
  DateTime? _due;
  bool _busy = false;

  Currency get cur => widget.currency;
  double get _subtotal => widget.cart.fold(0.0, (s, l) => s + l.total);
  double get _discountBase => cur.toBase(Fmt.parse(_discount.text));
  double get _totalBase => _subtotal - _discountBase;
  double get _paidBase => _credit ? cur.toBase(Fmt.parse(_paid.text)) : _totalBase;
  double get _remaining => (_totalBase - _paidBase).clamp(0, double.infinity);

  @override
  void initState() {
    super.initState();
    DebtsService.defaultDueDate().then((d) => setState(() => _due = DateTime.fromMillisecondsSinceEpoch(d)));
  }

  Future<void> _pickCustomer() async {
    final c = await pickCustomer(context);
    if (c == null) return;
    final b = await DebtsService.balance('customer', c.id);
    setState(() {
      _customer = c;
      _balance = b;
    });
  }

  Future<void> _confirm() async {
    if (_discountBase > 0 && !Session.can(Perm.giveDiscount)) {
      if (!await requireOwner(context, reason: 'إعطاء خصم يحتاج رمز المالك')) return;
    }
    if (_remaining > 0) {
      if (!Session.can(Perm.sellOnCredit) && !(mounted && await requireOwner(context, reason: 'البيع بالدين يحتاج رمز المالك'))) {
        return;
      }
      if (_customer == null) {
        if (mounted) toast(context, 'اختر الزبون لتسجيل الدين', error: true);
        return;
      }
      final limit = _customer!.creditLimit;
      if (limit > 0 && (_balance?.balance ?? 0) + _remaining > limit && mounted) {
        final go = await confirm(context, 'تجاوز سقف الدين',
            'سيتجاوز رصيد ${_customer!.name} سقف الدين المسموح (${money(limit)}). متابعة؟');
        if (!go) return;
      }
    }
    setState(() => _busy = true);
    try {
      final sale = await SalesService.checkout(
        cart: widget.cart,
        priceMode: widget.mode,
        customer: _customer,
        currency: cur.code,
        rate: cur.rate,
        discount: _discountBase,
        paid: _paidBase,
        dueDate: _due,
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      );
      if (mounted) Navigator.pop(context, sale);
    } on SaleException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    } catch (e) {
      if (mounted) toast(context, 'تعذر إتمام البيع: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    String f(double base) => CurrencyService.format(base, cur.code);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Center(
              child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey, borderRadius: BorderRadius.circular(2))),
            ),
            const SizedBox(height: 12),
            const Text('إتمام البيع', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            VCard(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              onTap: _pickCustomer,
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.person_outline),
                title: Text(_customer?.name ?? 'زبون نقدي (اختياري)'),
                subtitle: _balance == null
                    ? null
                    : Text(
                        'رصيده الحالي: ${money(_balance!.balance)}${_balance!.isOverdue ? ' • متأخر ${money(_balance!.overdue)}' : ''}',
                        style: TextStyle(color: _balance!.isOverdue ? VColors.coral : null),
                      ),
                trailing: _customer == null
                    ? const Icon(Icons.chevron_left)
                    : IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _customer = _balance = null)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _discount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(labelText: 'خصم', suffixText: cur.symbol, prefixIcon: const Icon(Icons.discount_outlined)),
            ),
            const SizedBox(height: 12),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('مدفوع بالكامل'), icon: Icon(Icons.payments_outlined)),
                ButtonSegment(value: true, label: Text('آجل / جزئي'), icon: Icon(Icons.schedule)),
              ],
              selected: {_credit},
              onSelectionChanged: (s) => setState(() {
                _credit = s.first;
                if (_credit && _paid.text.isEmpty) _paid.text = '0';
              }),
            ),
            if (_credit) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _paid,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(labelText: 'المبلغ المدفوع الآن', suffixText: cur.symbol),
              ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_outlined),
                title: const Text('تاريخ استحقاق الدين'),
                trailing: Text(_due == null ? '-' : Fmt.date(_due!), style: const TextStyle(fontWeight: FontWeight.w700)),
                onTap: () async {
                  final d = await showDatePicker(
                    context: context,
                    initialDate: _due ?? DateTime.now(),
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 730)),
                  );
                  if (d != null) setState(() => _due = d);
                },
              ),
            ],
            TextField(controller: _note, decoration: const InputDecoration(labelText: 'ملاحظة (اختياري)')),
            const SizedBox(height: 12),
            VCard(
              child: Column(children: [
                KeyValueRow('المجموع', f(_subtotal)),
                if (_discountBase > 0) KeyValueRow('الخصم', f(_discountBase)),
                KeyValueRow('الإجمالي', f(_totalBase), bold: true),
                KeyValueRow('المدفوع', f(_paidBase.clamp(0, _totalBase)), color: VColors.emerald),
                if (_remaining > 0) KeyValueRow('المتبقي (دين)', f(_remaining), color: VColors.blue, bold: true),
              ]),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 54,
              child: FilledButton.icon(
                onPressed: _busy ? null : _confirm,
                icon: _busy
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.task_alt),
                label: const Text('تأكيد إتمام البيع', style: TextStyle(fontSize: 17)),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

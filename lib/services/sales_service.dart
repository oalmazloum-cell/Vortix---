import '../core/format.dart';
import '../data/db.dart';
import '../data/models.dart';
import 'audit_service.dart';
import 'cash_service.dart';
import 'debts_service.dart';
import 'inventory_service.dart';
import 'session.dart';

class SaleException implements Exception {
  SaleException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// نقطة البيع: إتمام البيع، المرتجعات، وسجل الفواتير.
class SalesService {
  SalesService._();

  static AppDb get _db => AppDb.I;

  /// إتمام البيع. كل المبالغ بالعملة الأساسية.
  static Future<Sale> checkout({
    required List<CartLine> cart,
    required PriceMode priceMode,
    Customer? customer,
    required String currency,
    required double rate,
    double discount = 0,
    required double paid,
    DateTime? dueDate,
    String? note,
  }) async {
    if (cart.isEmpty) throw SaleException('السلة فارغة');
    final subtotal = Fmt.round2(cart.fold(0.0, (s, l) => s + l.total));
    final total = Fmt.round2(subtotal - discount);
    if (total < 0) throw SaleException('الخصم أكبر من قيمة الفاتورة');
    final paidClamped = Fmt.round2(paid.clamp(0, total).toDouble());
    final remaining = Fmt.round2(total - paidClamped);
    if (remaining > 0 && customer == null) {
      throw SaleException('اختر زبوناً لتسجيل المبلغ المتبقي كدين');
    }
    final status = remaining <= 0 ? 'paid' : (paidClamped > 0 ? 'partial' : 'credit');
    final cost = Fmt.round2(cart.fold(0.0, (s, l) => s + l.cost));
    final shift = await CashService.ensureShift();
    final id = newId();
    int? due;
    if (remaining > 0) due = dueDate?.millisecondsSinceEpoch ?? await DebtsService.defaultDueDate();

    await _db.tx((t) async {
      final number = await _db.nextNumber('sale', tx: t);
      await _db.put(
          'sales',
          {
            'id': id,
            'number': number,
            'kind': 'sale',
            'created_at': nowMs(),
            'customer_id': customer?.id,
            'customer_name': customer?.name,
            'price_mode': priceMode.name,
            'currency': currency,
            'rate': rate,
            'subtotal': subtotal,
            'discount': discount,
            'total': total,
            'cost': cost,
            'paid': paidClamped,
            'status': status,
            'due_date': due,
            'user_id': Session.user?.id,
            'user_name': Session.user?.name,
            'shift_id': shift.id,
            'note': note,
          },
          tx: t);
      for (final l in cart) {
        await _db.put(
            'sale_lines',
            {
              'id': newId(),
              'sale_id': id,
              'item_id': l.item.id,
              'name': l.item.name,
              'unit_name': l.unitName,
              'factor': l.factor,
              'qty': l.qty,
              'price': l.price,
              'cost': l.item.cost * l.factor,
              'total': Fmt.round2(l.total),
            },
            tx: t);
        if (l.item.trackStock) {
          await InventoryService.move(t, l.item.id, -l.baseQty, 'sale', ref: id);
        }
      }
      if (remaining > 0) {
        await DebtsService.addEntry(t,
            partyType: 'customer',
            partyId: customer!.id,
            kind: 'sale',
            refId: id,
            debit: remaining,
            dueDate: due,
            currency: currency,
            rate: rate,
            note: 'فاتورة #$number',
            shiftId: shift.id);
      }
      final priceChanged = cart.where((l) => (l.price - CartLine.priceFor(l.item, l.unit, priceMode)).abs() > 0.001);
      await AuditService.log('بيع', entity: 'sale', entityId: id,
          details: 'فاتورة #$number • ${Fmt.money(total)} • ${Sale.statusLabels[status]}'
              '${discount > 0 ? ' • خصم ${Fmt.money(discount)}' : ''}'
              '${customer != null ? ' • ${customer.name}' : ''}'
              '${priceChanged.isNotEmpty ? ' • تعديل سعر: ${priceChanged.map((l) => l.item.name).join('، ')}' : ''}',
          tx: t);
    });
    return (await byId(id))!;
  }

  /// كميات مُرجعة سابقاً لكل سطر من فاتورة.
  static Future<Map<String, double>> returnedQty(String saleId) async {
    final rows = await _db.query('''
      SELECT l.ref_line_id AS ref, SUM(l.qty) AS q FROM sale_lines l
      JOIN sales s ON s.id = l.sale_id WHERE s.kind = 'return' AND s.ref_id = ? GROUP BY l.ref_line_id''', [saleId]);
    return {for (final r in rows) '${r['ref']}': (r['q'] as num).toDouble()};
  }

  /// مرتجع: [qtyByLine] = {معرف السطر: الكمية المرجعة}.
  /// [refundMode]: 'cash' استرداد نقدي، 'debt' خصم من دين الزبون.
  static Future<Sale> returnSale(Sale original, Map<String, double> qtyByLine, {required String refundMode, String? note}) async {
    final already = await returnedQty(original.id);
    final ratio = original.subtotal == 0 ? 1.0 : original.total / original.subtotal;
    final lines = <(SaleLine, double)>[];
    for (final l in original.lines) {
      final q = qtyByLine[l.id] ?? 0;
      if (q <= 0) continue;
      final max = l.qty - (already[l.id] ?? 0);
      if (q > max + 0.0001) throw SaleException('كمية المرتجع لـ ${l.name} أكبر من المتبقي (${Fmt.qty(max)})');
      lines.add((l, q));
    }
    if (lines.isEmpty) throw SaleException('حدد كمية للإرجاع');
    if (refundMode == 'debt' && original.customerId == null) {
      throw SaleException('الفاتورة بدون زبون، اختر استرداداً نقدياً');
    }
    final subtotal = Fmt.round2(lines.fold(0.0, (s, e) => s + e.$1.price * e.$2));
    final total = Fmt.round2(subtotal * ratio);
    final cost = Fmt.round2(lines.fold(0.0, (s, e) => s + e.$1.cost * e.$2));
    final shift = await CashService.ensureShift();
    final id = newId();

    await _db.tx((t) async {
      final number = await _db.nextNumber('return', tx: t);
      await _db.put(
          'sales',
          {
            'id': id,
            'number': number,
            'kind': 'return',
            'created_at': nowMs(),
            'customer_id': original.customerId,
            'customer_name': original.customerName,
            'price_mode': original.priceMode,
            'currency': original.currency,
            'rate': original.rate,
            'subtotal': subtotal,
            'discount': Fmt.round2(subtotal - total),
            'total': total,
            'cost': cost,
            'paid': refundMode == 'cash' ? total : 0,
            'status': 'refund',
            'user_id': Session.user?.id,
            'user_name': Session.user?.name,
            'shift_id': shift.id,
            'ref_id': original.id,
            'refund_mode': refundMode,
            'note': note,
          },
          tx: t);
      for (final (l, q) in lines) {
        await _db.put(
            'sale_lines',
            {
              'id': newId(),
              'sale_id': id,
              'item_id': l.itemId,
              'name': l.name,
              'unit_name': l.unitName,
              'factor': l.factor,
              'qty': q,
              'price': l.price,
              'cost': l.cost,
              'total': Fmt.round2(l.price * q),
              'ref_line_id': l.id,
            },
            tx: t);
        if (l.itemId != null) {
          final item = await t.query('items', columns: ['track_stock'], where: 'id = ?', whereArgs: [l.itemId]);
          if (item.isNotEmpty && item.first['track_stock'] == 1) {
            await InventoryService.move(t, l.itemId!, q * l.factor, 'return', ref: id);
          }
        }
      }
      if (refundMode == 'debt') {
        await DebtsService.addEntry(t,
            partyType: 'customer',
            partyId: original.customerId!,
            kind: 'return',
            refId: id,
            credit: total,
            note: 'مرتجع #$number من فاتورة #${original.number}',
            shiftId: shift.id);
      }
      await AuditService.log('مرتجع', entity: 'sale', entityId: id,
          details: 'مرتجع #$number من فاتورة #${original.number} • ${Fmt.money(total)} • '
              '${refundMode == 'cash' ? 'نقداً' : 'خصم من الدين'}',
          tx: t);
    });
    return (await byId(id))!;
  }

  static Future<Sale?> byId(String id) async {
    final r = await _db.first('SELECT * FROM sales WHERE id = ?', [id]);
    if (r == null) return null;
    final lines = await _db.query('SELECT * FROM sale_lines WHERE sale_id = ? ORDER BY rowid', [id]);
    return Sale.fromRow(r, lines.map(SaleLine.fromRow).toList());
  }

  static Future<List<Sale>> list({int? from, int? to, String? customerId, String? kind, String? status, String? search, int limit = 200}) async {
    final where = <String>['1 = 1'];
    final args = <Object?>[];
    if (from != null) {
      where.add('created_at >= ?');
      args.add(from);
    }
    if (to != null) {
      where.add('created_at <= ?');
      args.add(to);
    }
    if (customerId != null) {
      where.add('customer_id = ?');
      args.add(customerId);
    }
    if (kind != null) {
      where.add('kind = ?');
      args.add(kind);
    }
    if (status != null) {
      where.add('status = ?');
      args.add(status);
    }
    if (search != null && search.trim().isNotEmpty) {
      where.add('(CAST(number AS TEXT) = ? OR customer_name LIKE ?)');
      args.addAll([Fmt.normalizeDigits(search.trim()), '%${search.trim()}%']);
    }
    final rows = await _db.query(
        'SELECT * FROM sales WHERE ${where.join(' AND ')} ORDER BY created_at DESC LIMIT $limit', args);
    return rows.map((r) => Sale.fromRow(r)).toList();
  }
}

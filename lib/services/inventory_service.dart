import 'package:sqflite/sqflite.dart';

import '../core/config.dart';
import '../core/format.dart';
import '../data/db.dart';
import '../data/models.dart';
import 'audit_service.dart';
import 'session.dart';

/// نتيجة البحث بالباركود: الصنف والوحدة المطابقة (إن كان الباركود لوحدة فرعية).
class BarcodeHit {
  BarcodeHit(this.item, this.unit);
  final Item item;
  final ItemUnit? unit;
}

class InventoryService {
  InventoryService._();

  static AppDb get _db => AppDb.I;

  // ------------------------------------------------------------ قراءة

  static Future<List<Item>> items({String? search, String? category, bool withUnits = false, String filter = 'all'}) async {
    final where = <String>['deleted = 0'];
    final args = <Object?>[];
    if (search != null && search.trim().isNotEmpty) {
      final q = normalizeArabic(search);
      where.add('(name_norm LIKE ? OR barcode = ? OR id IN (SELECT item_id FROM item_units WHERE barcode = ? AND deleted = 0))');
      args.addAll(['%$q%', search.trim(), search.trim()]);
    }
    if (category != null && category.isNotEmpty) {
      where.add('category = ?');
      args.add(category);
    }
    switch (filter) {
      case 'low':
        where.add('track_stock = 1 AND min_qty > 0 AND qty <= min_qty');
      case 'out':
        where.add('track_stock = 1 AND qty <= 0');
      case 'expiry':
        where.add('expiry IS NOT NULL AND expiry <= ?');
        args.add(DateTime.now().add(const Duration(days: AppConfig.expiryWarnDays)).millisecondsSinceEpoch);
      case 'fav':
        where.add('favorite = 1');
    }
    final rows = await _db.query('SELECT * FROM items WHERE ${where.join(' AND ')} ORDER BY name', args);
    final list = rows.map(Item.fromRow).toList();
    if (withUnits) {
      for (final i in list) {
        i.units = await units(i.id);
      }
    }
    return list;
  }

  static Future<Item?> byId(String id) async {
    final r = await _db.first('SELECT * FROM items WHERE id = ?', [id]);
    if (r == null) return null;
    return Item.fromRow(r)..units = await units(id);
  }

  static Future<List<ItemUnit>> units(String itemId) async {
    final rows = await _db.query('SELECT * FROM item_units WHERE item_id = ? AND deleted = 0 ORDER BY factor', [itemId]);
    return rows.map(ItemUnit.fromRow).toList();
  }

  /// يبحث عن الباركود في الأصناف ثم في الوحدات الفرعية.
  static Future<BarcodeHit?> findByBarcode(String code) async {
    final c = Fmt.normalizeDigits(code.trim());
    if (c.isEmpty) return null;
    final r = await _db.first('SELECT * FROM items WHERE barcode = ? AND deleted = 0 LIMIT 1', [c]);
    if (r != null) {
      final item = Item.fromRow(r)..units = await units('${r['id']}');
      return BarcodeHit(item, null);
    }
    final u = await _db.first('SELECT * FROM item_units WHERE barcode = ? AND deleted = 0 LIMIT 1', [c]);
    if (u != null) {
      final item = await byId('${u['item_id']}');
      if (item == null) return null;
      return BarcodeHit(item, item.units.firstWhere((x) => x.id == u['id']));
    }
    return null;
  }

  static Future<List<String>> categories() async {
    final rows = await _db.query(
        "SELECT DISTINCT category FROM items WHERE deleted = 0 AND category IS NOT NULL AND category != '' ORDER BY category");
    return rows.map((r) => '${r['category']}').toList();
  }

  /// الأصناف الأكثر مبيعاً (لشاشة البيع السريع)، مع المفضلة أولاً.
  static Future<List<Item>> quickItems({int limit = 24}) async {
    final rows = await _db.query('''
      SELECT i.*, COALESCE(s.sold, 0) AS sold FROM items i
      LEFT JOIN (SELECT item_id, SUM(qty * factor) AS sold FROM sale_lines
                 WHERE sale_id IN (SELECT id FROM sales WHERE kind = 'sale' AND created_at > ?)
                 GROUP BY item_id) s ON s.item_id = i.id
      WHERE i.deleted = 0
      ORDER BY i.favorite DESC, sold DESC, i.name LIMIT ?''',
        [DateTime.now().subtract(const Duration(days: 60)).millisecondsSinceEpoch, limit]);
    final list = rows.map(Item.fromRow).toList();
    for (final i in list) {
      i.units = await units(i.id);
    }
    return list;
  }

  static Future<bool> barcodeTaken(String code, {String? exceptItemId}) async {
    if (code.trim().isEmpty) return false;
    final a = await _db.first(
        'SELECT id FROM items WHERE barcode = ? AND deleted = 0 AND id != ?', [code, exceptItemId ?? '']);
    final b = await _db.first(
        'SELECT id FROM item_units WHERE barcode = ? AND deleted = 0 AND item_id != ?', [code, exceptItemId ?? '']);
    return a != null || b != null;
  }

  // ------------------------------------------------------------ كتابة

  static Future<String> save(Item item, {bool isNew = false, double? openingQty}) async {
    final old = isNew ? null : await byId(item.id);
    await _db.tx((t) async {
      final row = <String, Object?>{
        'id': item.id,
        'name': item.name.trim(),
        'name_norm': normalizeArabic(item.name),
        'barcode': (item.barcode?.trim().isEmpty ?? true) ? null : item.barcode!.trim(),
        'category': item.category,
        'unit': item.unit,
        'cost': item.cost,
        'retail': item.retail,
        'wholesale': item.wholesale,
        'qty': old?.qty ?? 0,
        'min_qty': item.minQty,
        'expiry': item.expiry?.millisecondsSinceEpoch,
        'favorite': item.favorite ? 1 : 0,
        'track_stock': item.trackStock ? 1 : 0,
        'created_at': nowMs(),
        'deleted': 0,
      };
      if (old != null) {
        final createdAt = await t.query('items', columns: ['created_at'], where: 'id = ?', whereArgs: [item.id]);
        row['created_at'] = createdAt.first['created_at'];
      }
      await _db.put('items', row, tx: t);

      // الوحدات: احذف (منطقياً) ما أُزيل وأضف/حدّث الباقي.
      final keep = item.units.map((u) => u.id).toSet();
      for (final u in old?.units ?? <ItemUnit>[]) {
        if (!keep.contains(u.id)) await _db.patch('item_units', u.id, {'deleted': 1}, tx: t);
      }
      for (final u in item.units) {
        await _db.put('item_units', u.toRow(), tx: t);
      }

      if (isNew && (openingQty ?? 0) != 0) {
        await _move(t, item.id, openingQty!, 'opening');
      }

      final changes = <String>[];
      if (old == null) {
        changes.add('سعر ${item.retail}');
      } else {
        if (old.retail != item.retail) changes.add('سعر المفرق ${old.retail} ← ${item.retail}');
        if (old.wholesale != item.wholesale) changes.add('سعر الجملة ${old.wholesale} ← ${item.wholesale}');
        if (old.cost != item.cost) changes.add('التكلفة ${old.cost} ← ${item.cost}');
        if (old.name != item.name) changes.add('الاسم ${old.name} ← ${item.name}');
      }
      await AuditService.log(isNew ? 'إضافة صنف' : 'تعديل صنف',
          entity: 'item', entityId: item.id, details: '${item.name} ${changes.join(' • ')}', tx: t);
    });
    return item.id;
  }

  static Future<void> delete(Item item) async {
    await _db.patch('items', item.id, {'deleted': 1});
    await AuditService.log('حذف صنف', entity: 'item', entityId: item.id, details: item.name);
  }

  static Future<void> toggleFavorite(Item item) async {
    await _db.patch('items', item.id, {'favorite': item.favorite ? 0 : 1});
  }

  /// حركة مخزون داخل معاملة: تعدّل الكمية وتسجّل الحركة.
  static Future<void> _move(DatabaseExecutor t, String itemId, double qty, String reason, {String? ref, String? note}) async {
    await t.rawUpdate('UPDATE items SET qty = qty + ?, updated_at = ? WHERE id = ?', [qty, nowMs(), itemId]);
    final full = await t.query('items', where: 'id = ?', whereArgs: [itemId]);
    if (full.isNotEmpty) {
      // نسجل الصف الكامل للمزامنة
      await AppDb.I.put('items', full.first, tx: t);
    }
    await AppDb.I.put(
        'stock_moves',
        {
          'id': newId(),
          'item_id': itemId,
          'created_at': nowMs(),
          'qty': qty,
          'reason': reason,
          'ref_id': ref,
          'user_id': Session.user?.id,
          'note': note,
        },
        tx: t);
  }

  static Future<void> move(DatabaseExecutor t, String itemId, double qty, String reason, {String? ref, String? note}) =>
      _move(t, itemId, qty, reason, ref: ref, note: note);

  /// تعديل كمية يدوي (يتطلب صلاحية).
  static Future<void> adjust(Item item, double newQty, String note) async {
    final diff = newQty - item.qty;
    if (diff == 0) return;
    await _db.tx((t) async {
      await _move(t, item.id, diff, 'adjust', note: note);
      await AuditService.log('تعديل كمية', entity: 'item', entityId: item.id,
          details: '${item.name}: ${Fmt.qty(item.qty)} ← ${Fmt.qty(newQty)} ($note)', tx: t);
    });
  }

  /// حفظ جرد: {الصنف: الكمية الفعلية}. يعيد قيمة الفرق بالتكلفة.
  static Future<double> saveCount(Map<Item, double> counted, {String? note}) async {
    var diffValue = 0.0;
    var changed = 0;
    final countId = newId();
    await _db.tx((t) async {
      for (final e in counted.entries) {
        final fresh = await t.query('items', where: 'id = ?', whereArgs: [e.key.id]);
        final current = (fresh.first['qty'] as num).toDouble();
        final diff = e.value - current;
        if (diff.abs() < 0.0001) continue;
        changed++;
        diffValue += diff * e.key.cost;
        await _move(t, e.key.id, diff, 'count', ref: countId,
            note: 'جرد: ${Fmt.qty(current)} ← ${Fmt.qty(e.value)}');
      }
      await _db.put(
          'stock_counts',
          {
            'id': countId,
            'created_at': nowMs(),
            'user_id': Session.user?.id,
            'user_name': Session.user?.name,
            'items_count': counted.length,
            'diff_value': diffValue,
            'note': note,
          },
          tx: t);
      await AuditService.log('حفظ جرد', entity: 'stock_count', entityId: countId,
          details: 'أصناف: ${counted.length} • تغيّر: $changed • قيمة الفرق: ${Fmt.money(diffValue)}', tx: t);
    });
    return diffValue;
  }

  // ------------------------------------------------------------ التنبيهات

  static Future<List<Item>> lowStock() => items(filter: 'low');
  static Future<List<Item>> expiring() => items(filter: 'expiry');

  static Future<double> stockValue() =>
      _db.scalar('SELECT COALESCE(SUM(qty * cost), 0) FROM items WHERE deleted = 0 AND track_stock = 1 AND qty > 0');

  // ------------------------------------------------------------ الباركود الداخلي

  /// يولد باركود EAN-13 داخلي فريد يبدأ بـ 200.
  static Future<String> generateInternalBarcode() async {
    final n = await _db.nextNumber('internal_barcode');
    var seq = n;
    while (true) {
      final body = '${AppConfig.internalBarcodePrefix}${seq.toString().padLeft(9, '0')}';
      final code = body + ean13Checksum(body).toString();
      if (!await barcodeTaken(code)) return code;
      seq = await _db.nextNumber('internal_barcode');
    }
  }

  static int ean13Checksum(String twelve) {
    var sum = 0;
    for (var i = 0; i < 12; i++) {
      final d = int.parse(twelve[i]);
      sum += i.isEven ? d : d * 3;
    }
    return (10 - sum % 10) % 10;
  }
}

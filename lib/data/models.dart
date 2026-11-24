import 'dart:convert';

double _d(Object? v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
int? _i(Object? v) => v is num ? v.toInt() : (v == null ? null : int.tryParse('$v'));

// ============================================================ المستخدمون

enum Role { owner, worker }

/// صلاحيات العامل. المالك يملك كل الصلاحيات دائماً.
enum Perm {
  viewProfits('رؤية الأرباح والتكلفة'),
  viewReports('رؤية التقارير'),
  editItems('إضافة وتعديل الأصناف'),
  editPrices('تعديل الأسعار'),
  giveDiscount('إعطاء خصم'),
  sellOnCredit('البيع بالدين (آجل)'),
  returns('تنفيذ المرتجعات'),
  manageDebts('تسجيل دفعات الزبائن'),
  purchases('فواتير الشراء'),
  stockCount('الجرد'),
  expenses('تسجيل المصاريف'),
  deleteRecords('الحذف');

  const Perm(this.label);
  final String label;
}

class AppUser {
  AppUser({
    required this.id,
    required this.name,
    required this.role,
    required this.pinHash,
    required this.perms,
    this.active = true,
  });

  final String id;
  final String name;
  final Role role;
  final String pinHash;
  final Set<Perm> perms;
  final bool active;

  bool get isOwner => role == Role.owner;
  bool can(Perm p) => isOwner || perms.contains(p);

  factory AppUser.fromRow(Map<String, Object?> r) {
    final list = (jsonDecode('${r['perms'] ?? '[]'}') as List).cast<String>();
    return AppUser(
      id: '${r['id']}',
      name: '${r['name']}',
      role: r['role'] == 'owner' ? Role.owner : Role.worker,
      pinHash: '${r['pin_hash']}',
      perms: Perm.values.where((p) => list.contains(p.name)).toSet(),
      active: (r['active'] as int? ?? 1) == 1,
    );
  }
}

// ============================================================ العملات

class Currency {
  Currency({required this.code, required this.name, required this.symbol, required this.rate, this.isBase = false});

  final String code;
  final String name;
  final String symbol;

  /// قيمة وحدة واحدة من هذه العملة بالعملة الأساسية.
  final double rate;
  final bool isBase;

  /// تحويل مبلغ بالعملة الأساسية إلى هذه العملة.
  double fromBase(double base) => rate == 0 ? base : base / rate;
  double toBase(double amount) => amount * rate;

  factory Currency.fromRow(Map<String, Object?> r) => Currency(
        code: '${r['id']}',
        name: '${r['name']}',
        symbol: '${r['symbol']}',
        rate: _d(r['rate']),
        isBase: r['is_base'] == 1,
      );
}

// ============================================================ الأصناف

class ItemUnit {
  ItemUnit({
    required this.id,
    required this.itemId,
    required this.name,
    required this.factor,
    this.barcode,
    this.retail = 0,
    this.wholesale = 0,
  });

  final String id;
  final String itemId;
  String name;

  /// عدد الوحدات الأساسية في هذه الوحدة (مثلاً كرتونة = 24 حبة).
  double factor;
  String? barcode;
  double retail;
  double wholesale;

  factory ItemUnit.fromRow(Map<String, Object?> r) => ItemUnit(
        id: '${r['id']}',
        itemId: '${r['item_id']}',
        name: '${r['name']}',
        factor: _d(r['factor']),
        barcode: r['barcode'] as String?,
        retail: _d(r['retail']),
        wholesale: _d(r['wholesale']),
      );

  Map<String, Object?> toRow() => {
        'id': id,
        'item_id': itemId,
        'name': name,
        'factor': factor,
        'barcode': (barcode?.isEmpty ?? true) ? null : barcode,
        'retail': retail,
        'wholesale': wholesale,
        'deleted': 0,
      };
}

class Item {
  Item({
    required this.id,
    required this.name,
    this.barcode,
    this.category,
    this.unit = 'حبة',
    this.cost = 0,
    this.retail = 0,
    this.wholesale = 0,
    this.qty = 0,
    this.minQty = 0,
    this.expiry,
    this.favorite = false,
    this.trackStock = true,
    List<ItemUnit>? units,
  }) : units = units ?? [];

  final String id;
  String name;
  String? barcode;
  String? category;
  String unit;

  /// متوسط تكلفة الوحدة الأساسية.
  double cost;
  double retail;
  double wholesale;
  double qty;
  double minQty;
  DateTime? expiry;
  bool favorite;
  bool trackStock;
  List<ItemUnit> units;

  bool get isLow => trackStock && minQty > 0 && qty <= minQty;
  bool get isOut => trackStock && qty <= 0;
  bool get isExpired => expiry != null && expiry!.isBefore(DateTime.now());
  bool isExpiringWithin(int days) =>
      expiry != null && !isExpired && expiry!.isBefore(DateTime.now().add(Duration(days: days)));

  factory Item.fromRow(Map<String, Object?> r) => Item(
        id: '${r['id']}',
        name: '${r['name']}',
        barcode: r['barcode'] as String?,
        category: r['category'] as String?,
        unit: '${r['unit'] ?? 'حبة'}',
        cost: _d(r['cost']),
        retail: _d(r['retail']),
        wholesale: _d(r['wholesale']),
        qty: _d(r['qty']),
        minQty: _d(r['min_qty']),
        expiry: _i(r['expiry']) == null ? null : DateTime.fromMillisecondsSinceEpoch(_i(r['expiry'])!),
        favorite: r['favorite'] == 1,
        trackStock: (r['track_stock'] ?? 1) == 1,
      );
}

// ============================================================ الزبائن والموردون

class Customer {
  Customer({required this.id, required this.name, this.phone, this.whatsapp, this.note, this.creditLimit = 0});

  final String id;
  String name;
  String? phone;
  String? whatsapp;
  String? note;
  double creditLimit;

  String? get contactNumber => (whatsapp?.isNotEmpty ?? false) ? whatsapp : phone;

  factory Customer.fromRow(Map<String, Object?> r) => Customer(
        id: '${r['id']}',
        name: '${r['name']}',
        phone: r['phone'] as String?,
        whatsapp: r['whatsapp'] as String?,
        note: r['note'] as String?,
        creditLimit: _d(r['credit_limit']),
      );
}

class Supplier {
  Supplier({required this.id, required this.name, this.phone, this.note});
  final String id;
  String name;
  String? phone;
  String? note;

  factory Supplier.fromRow(Map<String, Object?> r) =>
      Supplier(id: '${r['id']}', name: '${r['name']}', phone: r['phone'] as String?, note: r['note'] as String?);
}

/// ملخص رصيد زبون أو مورد.
class PartyBalance {
  PartyBalance({required this.balance, required this.overdue, this.oldestDue});
  final double balance;
  final double overdue;
  final DateTime? oldestDue;
  bool get isOverdue => overdue > 0.009;
}

class LedgerEntry {
  LedgerEntry({
    required this.id,
    required this.createdAt,
    required this.kind,
    required this.debit,
    required this.credit,
    this.refId,
    this.dueDate,
    this.note,
    this.userName,
  });

  final String id;
  final DateTime createdAt;
  final String kind;
  final double debit;
  final double credit;
  final String? refId;
  final DateTime? dueDate;
  final String? note;
  final String? userName;

  static const kindLabels = {
    'sale': 'فاتورة بيع آجل',
    'payment': 'دفعة',
    'return': 'مرتجع',
    'purchase': 'فاتورة شراء',
    'opening': 'رصيد افتتاحي',
    'adjust': 'تسوية',
  };
  String get kindLabel => kindLabels[kind] ?? kind;

  factory LedgerEntry.fromRow(Map<String, Object?> r) => LedgerEntry(
        id: '${r['id']}',
        createdAt: DateTime.fromMillisecondsSinceEpoch(_i(r['created_at'])!),
        kind: '${r['kind']}',
        debit: _d(r['debit']),
        credit: _d(r['credit']),
        refId: r['ref_id'] as String?,
        dueDate: _i(r['due_date']) == null ? null : DateTime.fromMillisecondsSinceEpoch(_i(r['due_date'])!),
        note: r['note'] as String?,
        userName: r['user_name'] as String?,
      );
}

// ============================================================ البيع

enum PriceMode { retail, wholesale }

class CartLine {
  CartLine({required this.item, this.unit, this.qty = 1, required this.price});

  final Item item;

  /// null = الوحدة الأساسية.
  ItemUnit? unit;
  double qty;

  /// سعر الوحدة المختارة بالعملة الأساسية.
  double price;

  double get factor => unit?.factor ?? 1;
  String get unitName => unit?.name ?? item.unit;
  double get total => price * qty;
  double get baseQty => qty * factor;
  double get cost => item.cost * factor * qty;

  static double priceFor(Item item, ItemUnit? unit, PriceMode mode) {
    if (unit == null) {
      return mode == PriceMode.wholesale && item.wholesale > 0 ? item.wholesale : item.retail;
    }
    final r = unit.retail > 0 ? unit.retail : item.retail * unit.factor;
    final w = unit.wholesale > 0 ? unit.wholesale : (item.wholesale > 0 ? item.wholesale * unit.factor : r);
    return mode == PriceMode.wholesale ? w : r;
  }
}

class Sale {
  Sale({
    required this.id,
    required this.number,
    required this.kind,
    required this.createdAt,
    this.customerId,
    this.customerName,
    required this.priceMode,
    required this.currency,
    required this.rate,
    required this.subtotal,
    required this.discount,
    required this.total,
    required this.cost,
    required this.paid,
    required this.status,
    this.dueDate,
    this.userName,
    this.refId,
    this.note,
    this.lines = const [],
  });

  final String id;
  final int number;
  final String kind;
  final DateTime createdAt;
  final String? customerId;
  final String? customerName;
  final String priceMode;
  final String currency;
  final double rate;
  final double subtotal;
  final double discount;
  final double total;
  final double cost;
  final double paid;
  final String status;
  final DateTime? dueDate;
  final String? userName;
  final String? refId;
  final String? note;
  final List<SaleLine> lines;

  bool get isReturn => kind == 'return';
  double get remaining => (total - paid).clamp(0, double.infinity);
  double get profit => total - cost;

  static const statusLabels = {'paid': 'مدفوع', 'partial': 'مدفوع جزئياً', 'credit': 'آجل (دين)', 'refund': 'مرتجع'};
  String get statusLabel => statusLabels[status] ?? status;

  factory Sale.fromRow(Map<String, Object?> r, [List<SaleLine> lines = const []]) => Sale(
        id: '${r['id']}',
        number: _i(r['number']) ?? 0,
        kind: '${r['kind']}',
        createdAt: DateTime.fromMillisecondsSinceEpoch(_i(r['created_at'])!),
        customerId: r['customer_id'] as String?,
        customerName: r['customer_name'] as String?,
        priceMode: '${r['price_mode']}',
        currency: '${r['currency']}',
        rate: _d(r['rate']),
        subtotal: _d(r['subtotal']),
        discount: _d(r['discount']),
        total: _d(r['total']),
        cost: _d(r['cost']),
        paid: _d(r['paid']),
        status: '${r['status']}',
        dueDate: _i(r['due_date']) == null ? null : DateTime.fromMillisecondsSinceEpoch(_i(r['due_date'])!),
        userName: r['user_name'] as String?,
        refId: r['ref_id'] as String?,
        note: r['note'] as String?,
        lines: lines,
      );
}

class SaleLine {
  SaleLine({
    required this.id,
    required this.itemId,
    required this.name,
    required this.unitName,
    required this.factor,
    required this.qty,
    required this.price,
    required this.cost,
    required this.total,
  });

  final String id;
  final String? itemId;
  final String name;
  final String unitName;
  final double factor;
  final double qty;
  final double price;
  final double cost;
  final double total;

  factory SaleLine.fromRow(Map<String, Object?> r) => SaleLine(
        id: '${r['id']}',
        itemId: r['item_id'] as String?,
        name: '${r['name']}',
        unitName: '${r['unit_name'] ?? ''}',
        factor: _d(r['factor']),
        qty: _d(r['qty']),
        price: _d(r['price']),
        cost: _d(r['cost']),
        total: _d(r['total']),
      );
}

// ============================================================ الشراء

class PurchaseLine {
  PurchaseLine({required this.item, this.unit, this.qty = 1, required this.cost, this.expiry});
  final Item item;
  ItemUnit? unit;
  double qty;

  /// تكلفة الوحدة المختارة بالعملة الأساسية.
  double cost;
  DateTime? expiry;

  double get factor => unit?.factor ?? 1;
  String get unitName => unit?.name ?? item.unit;
  double get total => cost * qty;
}

// ============================================================ الصندوق

class Shift {
  Shift({
    required this.id,
    required this.userName,
    required this.openedAt,
    required this.opening,
    this.closedAt,
    this.expected,
    this.actual,
    this.diff,
    this.note,
  });

  final String id;
  final String? userName;
  final DateTime openedAt;
  final double opening;
  final DateTime? closedAt;
  final double? expected;
  final double? actual;
  final double? diff;
  final String? note;

  bool get isOpen => closedAt == null;

  factory Shift.fromRow(Map<String, Object?> r) => Shift(
        id: '${r['id']}',
        userName: r['user_name'] as String?,
        openedAt: DateTime.fromMillisecondsSinceEpoch(_i(r['opened_at'])!),
        opening: _d(r['opening']),
        closedAt: _i(r['closed_at']) == null ? null : DateTime.fromMillisecondsSinceEpoch(_i(r['closed_at'])!),
        expected: r['expected'] == null ? null : _d(r['expected']),
        actual: r['actual'] == null ? null : _d(r['actual']),
        diff: r['diff'] == null ? null : _d(r['diff']),
        note: r['note'] as String?,
      );
}

/// تفاصيل حركة النقد في وردية.
class CashSummary {
  CashSummary({
    required this.opening,
    required this.cashSales,
    required this.refunds,
    required this.debtCollections,
    required this.purchasesPaid,
    required this.supplierPayments,
    required this.expenses,
  });

  final double opening;
  final double cashSales;
  final double refunds;
  final double debtCollections;
  final double purchasesPaid;
  final double supplierPayments;
  final double expenses;

  double get expected =>
      opening + cashSales - refunds + debtCollections - purchasesPaid - supplierPayments - expenses;
}

// ============================================================ السجل

class AuditEntry {
  AuditEntry({
    required this.seq,
    required this.createdAt,
    required this.userName,
    required this.action,
    this.entity,
    this.details,
    required this.hash,
    required this.deviceId,
  });

  final int seq;
  final DateTime createdAt;
  final String? userName;
  final String action;
  final String? entity;
  final String? details;
  final String hash;
  final String deviceId;

  factory AuditEntry.fromRow(Map<String, Object?> r) => AuditEntry(
        seq: _i(r['seq']) ?? 0,
        createdAt: DateTime.fromMillisecondsSinceEpoch(_i(r['created_at'])!),
        userName: r['user_name'] as String?,
        action: '${r['action']}',
        entity: r['entity'] as String?,
        details: r['details'] as String?,
        hash: '${r['hash']}',
        deviceId: '${r['device_id']}',
      );
}

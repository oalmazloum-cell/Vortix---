/// مخطط قاعدة بيانات فورتكس.
///
/// المبالغ كلها مخزّنة بالعملة الأساسية للمحل، مع حفظ عملة الفاتورة وسعر
/// الصرف وقت العملية للعرض والطباعة. الكميات بالوحدة الأساسية للصنف.
class Schema {
  Schema._();

  static const version = 1;

  /// الجداول التي تُرفع للسحابة.
  static const synced = {
    'users',
    'currencies',
    'items',
    'item_units',
    'customers',
    'suppliers',
    'sales',
    'sale_lines',
    'purchases',
    'purchase_lines',
    'ledger',
    'expenses',
    'stock_moves',
    'stock_counts',
    'shifts',
    'audit_log',
  };

  /// إعدادات خاصة بهذا الجهاز فقط ولا تُزامَن.
  static const localSettings = {
    'device_id',
    'theme',
    'biometric',
    'printer_address',
    'printer_name',
    'printer_width',
    'last_backup',
    'last_pull',
    'last_push',
    'notif_last',
    'session_phone',
  };

  static const create = <String>[
    '''CREATE TABLE settings(
      key TEXT PRIMARY KEY, value TEXT, updated_at INTEGER)''',
    '''CREATE TABLE users(
      id TEXT PRIMARY KEY, name TEXT NOT NULL, role TEXT NOT NULL,
      pin_hash TEXT NOT NULL, perms TEXT NOT NULL DEFAULT '[]',
      active INTEGER NOT NULL DEFAULT 1, created_at INTEGER, updated_at INTEGER)''',
    '''CREATE TABLE currencies(
      id TEXT PRIMARY KEY, name TEXT NOT NULL, symbol TEXT NOT NULL,
      rate REAL NOT NULL DEFAULT 1, is_base INTEGER NOT NULL DEFAULT 0,
      active INTEGER NOT NULL DEFAULT 1, updated_at INTEGER)''',
    '''CREATE TABLE items(
      id TEXT PRIMARY KEY, name TEXT NOT NULL, name_norm TEXT, barcode TEXT,
      category TEXT, unit TEXT NOT NULL DEFAULT 'حبة',
      cost REAL NOT NULL DEFAULT 0, retail REAL NOT NULL DEFAULT 0,
      wholesale REAL NOT NULL DEFAULT 0, qty REAL NOT NULL DEFAULT 0,
      min_qty REAL NOT NULL DEFAULT 0, expiry INTEGER, favorite INTEGER NOT NULL DEFAULT 0,
      track_stock INTEGER NOT NULL DEFAULT 1, created_at INTEGER, updated_at INTEGER,
      deleted INTEGER NOT NULL DEFAULT 0)''',
    'CREATE INDEX idx_items_barcode ON items(barcode)',
    'CREATE INDEX idx_items_name ON items(name_norm)',
    '''CREATE TABLE item_units(
      id TEXT PRIMARY KEY, item_id TEXT NOT NULL, name TEXT NOT NULL,
      factor REAL NOT NULL, barcode TEXT, retail REAL NOT NULL DEFAULT 0,
      wholesale REAL NOT NULL DEFAULT 0, updated_at INTEGER, deleted INTEGER NOT NULL DEFAULT 0)''',
    'CREATE INDEX idx_units_item ON item_units(item_id)',
    'CREATE INDEX idx_units_barcode ON item_units(barcode)',
    '''CREATE TABLE customers(
      id TEXT PRIMARY KEY, name TEXT NOT NULL, phone TEXT, whatsapp TEXT, note TEXT,
      credit_limit REAL NOT NULL DEFAULT 0, created_at INTEGER, updated_at INTEGER,
      deleted INTEGER NOT NULL DEFAULT 0)''',
    '''CREATE TABLE suppliers(
      id TEXT PRIMARY KEY, name TEXT NOT NULL, phone TEXT, note TEXT,
      created_at INTEGER, updated_at INTEGER, deleted INTEGER NOT NULL DEFAULT 0)''',
    '''CREATE TABLE sales(
      id TEXT PRIMARY KEY, number INTEGER NOT NULL, kind TEXT NOT NULL DEFAULT 'sale',
      created_at INTEGER NOT NULL, customer_id TEXT, customer_name TEXT,
      price_mode TEXT NOT NULL DEFAULT 'retail', currency TEXT NOT NULL, rate REAL NOT NULL DEFAULT 1,
      subtotal REAL NOT NULL, discount REAL NOT NULL DEFAULT 0, total REAL NOT NULL,
      cost REAL NOT NULL DEFAULT 0, paid REAL NOT NULL DEFAULT 0, status TEXT NOT NULL,
      due_date INTEGER, user_id TEXT, user_name TEXT, shift_id TEXT, ref_id TEXT,
      refund_mode TEXT, note TEXT, updated_at INTEGER)''',
    'CREATE INDEX idx_sales_date ON sales(created_at)',
    'CREATE INDEX idx_sales_customer ON sales(customer_id)',
    '''CREATE TABLE sale_lines(
      id TEXT PRIMARY KEY, sale_id TEXT NOT NULL, item_id TEXT, name TEXT NOT NULL,
      unit_name TEXT, factor REAL NOT NULL DEFAULT 1, qty REAL NOT NULL,
      price REAL NOT NULL, cost REAL NOT NULL DEFAULT 0, total REAL NOT NULL, ref_line_id TEXT,
      updated_at INTEGER)''',
    'CREATE INDEX idx_lines_sale ON sale_lines(sale_id)',
    'CREATE INDEX idx_lines_item ON sale_lines(item_id)',
    '''CREATE TABLE purchases(
      id TEXT PRIMARY KEY, number INTEGER NOT NULL, created_at INTEGER NOT NULL,
      supplier_id TEXT, supplier_name TEXT, currency TEXT NOT NULL, rate REAL NOT NULL DEFAULT 1,
      total REAL NOT NULL, paid REAL NOT NULL DEFAULT 0, user_id TEXT, user_name TEXT,
      shift_id TEXT, note TEXT, updated_at INTEGER)''',
    '''CREATE TABLE purchase_lines(
      id TEXT PRIMARY KEY, purchase_id TEXT NOT NULL, item_id TEXT, name TEXT NOT NULL,
      unit_name TEXT, factor REAL NOT NULL DEFAULT 1, qty REAL NOT NULL,
      cost REAL NOT NULL, total REAL NOT NULL, expiry INTEGER, updated_at INTEGER)''',
    'CREATE INDEX idx_plines_purchase ON purchase_lines(purchase_id)',
    // دفتر الزبائن والموردين: للزبون المدين = عليه، الدائن = دفع.
    // للمورد: الدائن = علينا له، المدين = دفعنا له.
    '''CREATE TABLE ledger(
      id TEXT PRIMARY KEY, party_type TEXT NOT NULL, party_id TEXT NOT NULL,
      created_at INTEGER NOT NULL, kind TEXT NOT NULL, ref_id TEXT,
      debit REAL NOT NULL DEFAULT 0, credit REAL NOT NULL DEFAULT 0, due_date INTEGER,
      currency TEXT, rate REAL NOT NULL DEFAULT 1, note TEXT, user_id TEXT, user_name TEXT,
      shift_id TEXT, updated_at INTEGER)''',
    'CREATE INDEX idx_ledger_party ON ledger(party_type, party_id)',
    '''CREATE TABLE expenses(
      id TEXT PRIMARY KEY, created_at INTEGER NOT NULL, category TEXT NOT NULL,
      amount REAL NOT NULL, note TEXT, user_id TEXT, user_name TEXT, shift_id TEXT, updated_at INTEGER)''',
    '''CREATE TABLE stock_moves(
      id TEXT PRIMARY KEY, item_id TEXT NOT NULL, created_at INTEGER NOT NULL,
      qty REAL NOT NULL, reason TEXT NOT NULL, ref_id TEXT, user_id TEXT, note TEXT, updated_at INTEGER)''',
    'CREATE INDEX idx_moves_item ON stock_moves(item_id)',
    '''CREATE TABLE stock_counts(
      id TEXT PRIMARY KEY, created_at INTEGER NOT NULL, user_id TEXT, user_name TEXT,
      items_count INTEGER NOT NULL, diff_value REAL NOT NULL, note TEXT, updated_at INTEGER)''',
    '''CREATE TABLE shifts(
      id TEXT PRIMARY KEY, user_id TEXT, user_name TEXT, opened_at INTEGER NOT NULL,
      opening REAL NOT NULL DEFAULT 0, closed_at INTEGER, expected REAL, actual REAL,
      diff REAL, note TEXT, updated_at INTEGER)''',
    // سجل العمليات: سلسلة تجزئة (Hash chain) + منع التعديل والحذف على مستوى القاعدة.
    '''CREATE TABLE audit_log(
      seq INTEGER PRIMARY KEY AUTOINCREMENT, id TEXT UNIQUE NOT NULL, device_id TEXT NOT NULL,
      created_at INTEGER NOT NULL, user_id TEXT, user_name TEXT, action TEXT NOT NULL,
      entity TEXT, entity_id TEXT, details TEXT, prev_hash TEXT NOT NULL, hash TEXT NOT NULL,
      updated_at INTEGER)''',
    '''CREATE TRIGGER audit_no_update BEFORE UPDATE ON audit_log
      BEGIN SELECT RAISE(ABORT, 'audit log is append-only'); END''',
    '''CREATE TRIGGER audit_no_delete BEFORE DELETE ON audit_log
      BEGIN SELECT RAISE(ABORT, 'audit log is append-only'); END''',
    '''CREATE TABLE sync_queue(
      seq INTEGER PRIMARY KEY AUTOINCREMENT, tbl TEXT NOT NULL, row_id TEXT NOT NULL,
      op TEXT NOT NULL, data TEXT NOT NULL, created_at INTEGER NOT NULL)''',
  ];

  /// ترحيلات الإصدارات القادمة: {رقم الإصدار: [أوامر SQL]}.
  static const migrations = <int, List<String>>{};
}

import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../core/format.dart';
import '../data/db.dart';
import '../data/models.dart';
import 'audit_service.dart';

/// بيانات المحل.
class ShopInfo {
  ShopInfo({
    required this.name,
    required this.ownerName,
    required this.phone,
    this.whatsapp,
    this.address,
    required this.createdAt,
    this.footer,
  });

  final String name;
  final String ownerName;
  final String phone;
  final String? whatsapp;
  final String? address;
  final DateTime createdAt;
  final String? footer;
}

/// الجلسة الحالية: المستخدم المسجّل وبيانات المحل.
class Session {
  Session._();

  static AppUser? user;
  static ShopInfo? shop;

  static bool get isOwner => user?.isOwner ?? false;
  static bool can(Perm p) => user?.can(p) ?? false;

  static String hashPin(String userId, String pin) =>
      sha256.convert(utf8.encode('vortex|$userId|${Fmt.normalizeDigits(pin.trim())}')).toString();

  static Future<bool> hasShop() async => (await AppDb.I.getSetting('shop_name')) != null;

  static Future<ShopInfo?> loadShop() async {
    final db = AppDb.I;
    final name = await db.getSetting('shop_name');
    if (name == null) return shop = null;
    return shop = ShopInfo(
      name: name,
      ownerName: await db.getSetting('owner_name') ?? '',
      phone: await db.getSetting('shop_phone') ?? '',
      whatsapp: await db.getSetting('shop_whatsapp'),
      address: await db.getSetting('shop_address'),
      footer: await db.getSetting('invoice_footer'),
      createdAt: DateTime.fromMillisecondsSinceEpoch(int.tryParse(await db.getSetting('created_at') ?? '') ?? nowMs()),
    );
  }

  static Future<void> saveShop({
    required String name,
    required String ownerName,
    required String phone,
    String? whatsapp,
    String? address,
    String? footer,
  }) async {
    final db = AppDb.I;
    await db.setSetting('shop_name', name);
    await db.setSetting('owner_name', ownerName);
    await db.setSetting('shop_phone', phone);
    await db.setSetting('shop_whatsapp', whatsapp);
    await db.setSetting('shop_address', address);
    await db.setSetting('invoice_footer', footer);
    await loadShop();
  }

  /// إنشاء محل جديد مع حساب المالك والعملات الافتراضية.
  static Future<AppUser> createShop({
    required String shopName,
    required String ownerName,
    required String phone,
    String? whatsapp,
    required String ownerCode,
  }) async {
    final db = AppDb.I;
    final now = nowMs();
    final ownerId = newId();
    await db.setSetting('created_at', '$now');
    await db.setSetting('trial_start', '$now');
    await saveShop(name: shopName, ownerName: ownerName, phone: phone, whatsapp: whatsapp);
    await db.put('users', {
      'id': ownerId,
      'name': ownerName,
      'role': 'owner',
      'pin_hash': hashPin(ownerId, ownerCode),
      'perms': '[]',
      'active': 1,
      'created_at': now,
    });
    final currencies = [
      {'id': 'ILS', 'name': 'شيكل', 'symbol': '₪', 'rate': 1.0, 'is_base': 1},
      {'id': 'USD', 'name': 'دولار', 'symbol': '\$', 'rate': 3.7, 'is_base': 0},
      {'id': 'JOD', 'name': 'دينار', 'symbol': 'د.أ', 'rate': 5.2, 'is_base': 0},
    ];
    for (final c in currencies) {
      await db.put('currencies', {...c, 'active': 1});
    }
    await db.setSetting('base_currency', 'ILS');
    await db.setSetting('default_due_days', '30');
    final owner = (await users()).firstWhere((u) => u.id == ownerId);
    user = owner;
    await AuditService.log('إنشاء المحل', entity: 'shop', details: shopName, user: owner);
    return owner;
  }

  static Future<List<AppUser>> users({bool activeOnly = false}) async {
    final rows = await AppDb.I.query(
        'SELECT * FROM users ${activeOnly ? 'WHERE active = 1' : ''} ORDER BY role DESC, name');
    return rows.map(AppUser.fromRow).toList();
  }

  static Future<AppUser?> owner() async {
    final list = await users();
    for (final u in list) {
      if (u.isOwner) return u;
    }
    return null;
  }

  /// تحقق من رمز مستخدم وتسجيل دخوله.
  static Future<bool> login(AppUser u, String pin) async {
    if (hashPin(u.id, pin) != u.pinHash) {
      await AuditService.log('محاولة دخول فاشلة', entity: 'user', entityId: u.id, details: u.name, user: u);
      return false;
    }
    user = u;
    await AuditService.log('تسجيل دخول', entity: 'user', entityId: u.id, details: u.name);
    return true;
  }

  static Future<void> loginBiometric(AppUser u) async {
    user = u;
    await AuditService.log('تسجيل دخول بالبصمة', entity: 'user', entityId: u.id, details: u.name);
  }

  /// يتحقق من رمز المالك (لحماية العمليات الحساسة).
  static Future<bool> verifyOwnerCode(String code) async {
    final o = await owner();
    return o != null && hashPin(o.id, code) == o.pinHash;
  }

  static Future<void> logout() async {
    if (user != null) await AuditService.log('تسجيل خروج', entity: 'user', entityId: user!.id);
    user = null;
  }

  static Future<void> saveWorker({String? id, required String name, String? pin, required Set<Perm> perms, bool active = true}) async {
    final db = AppDb.I;
    final uid = id ?? newId();
    final existing = await db.first('SELECT * FROM users WHERE id = ?', [uid]);
    await db.put('users', {
      'id': uid,
      'name': name,
      'role': 'worker',
      'pin_hash': (pin != null && pin.isNotEmpty) ? hashPin(uid, pin) : existing?['pin_hash'] ?? '',
      'perms': jsonEncode(perms.map((p) => p.name).toList()),
      'active': active ? 1 : 0,
      'created_at': existing?['created_at'] ?? nowMs(),
    });
    await AuditService.log(id == null ? 'إضافة عامل' : 'تعديل عامل',
        entity: 'user', entityId: uid, details: '$name • ${perms.map((p) => p.label).join('، ')}');
  }

  static Future<void> changeOwnerCode(String newCode) async {
    final o = await owner();
    if (o == null) return;
    await AppDb.I.patch('users', o.id, {'pin_hash': hashPin(o.id, newCode)});
    await AuditService.log('تغيير رمز المالك', entity: 'user', entityId: o.id);
  }
}

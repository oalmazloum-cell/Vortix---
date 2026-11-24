import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart' show DatabaseExecutor;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config.dart';
import '../core/format.dart';
import '../data/db.dart';
import '../data/schema.dart';
import 'subscription_service.dart';

enum SyncState { disabled, idle, syncing, offline, error }

/// المزامنة الذكية في الخلفية (Offline-First).
///
/// - كل تعديل محلي يدخل طابور `sync_queue` (Outbox).
/// - عند توفر الإنترنت: يُرفع الطابور على دفعات، ثم تُسحب تغييرات الأجهزة
///   الأخرى منذ آخر سحب (مؤشر `synced_at` من الخادم، فلا تأثير لفروق الساعة).
/// - التعارض: آخر تعديل يفوز (updated_at)، أما كميات المخزون فتُعاد حسابها
///   من حركات المخزون، والأرصدة تُحسب من الدفتر، فلا يضيع بيع من أي جهاز.
class SyncService {
  SyncService._();

  static final state = ValueNotifier<SyncState>(SyncState.disabled);
  static final lastSync = ValueNotifier<DateTime?>(null);
  static String? lastError;

  static Timer? _timer;
  static Timer? _debounce;
  static StreamSubscription? _conn;
  static bool _running = false;
  static bool _initialized = false;

  static const table = 'vortex_records';

  static SupabaseClient? get _client => _initialized ? Supabase.instance.client : null;

  static Future<void> init() async {
    if (!AppConfig.cloudEnabled || _initialized) return;
    try {
      await Supabase.initialize(url: AppConfig.supabaseUrl, publishableKey: AppConfig.supabaseAnonKey);
      _initialized = true;
      state.value = SyncState.idle;
    } catch (e) {
      lastError = '$e';
      state.value = SyncState.error;
    }
  }

  static bool get signedIn => _client?.auth.currentUser != null;

  static String emailFor(String phone) => 'shop${SubscriptionService.normalizePhone(phone)}@vortex-shop.app';

  // ------------------------------------------------------------ الحساب السحابي

  /// إنشاء الحساب السحابي للمحل (إن فشل لعدم وجود إنترنت يُعاد لاحقاً).
  static Future<void> registerShop(String phone, String password) async {
    if (!_initialized) return;
    final db = AppDb.I;
    try {
      final res = await _client!.auth.signUp(email: emailFor(phone), password: password);
      if (res.session == null) {
        await _client!.auth.signInWithPassword(email: emailFor(phone), password: password);
      }
      await db.setSetting('pending_signup', null, sync: false);
      unawaited(syncNow());
    } catch (e) {
      // نحتفظ بطلب التسجيل لنعيد المحاولة عند توفر الإنترنت.
      await db.setSetting('pending_signup', jsonEncode({'phone': phone, 'pw': password}), sync: false);
      lastError = '$e';
    }
  }

  static Future<void> _retryPendingSignup() async {
    final p = await AppDb.I.getSetting('pending_signup');
    if (p == null) return;
    final m = jsonDecode(p) as Map;
    await registerShop('${m['phone']}', '${m['pw']}');
  }

  /// تسجيل الدخول واسترجاع كل بيانات المحل من السحابة إلى هذا الجهاز.
  static Future<void> loginAndRestore(String phone, String password, {void Function(int)? onProgress}) async {
    if (!_initialized) throw Exception('المزامنة السحابية غير مفعّلة في هذه النسخة');
    await _client!.auth.signInWithPassword(email: emailFor(phone), password: password);
    await AppDb.wipe();
    final db = await AppDb.open();
    await _pullAll(db, onProgress: onProgress);
    await db.setSetting('session_phone', phone, sync: false);
  }

  static Future<void> updatePassword(String newPassword) async {
    if (!signedIn) return;
    try {
      await _client!.auth.updateUser(UserAttributes(password: newPassword));
    } catch (_) {}
  }

  static Future<void> signOut() async {
    if (signedIn) await _client!.auth.signOut();
  }

  // ------------------------------------------------------------ التشغيل في الخلفية

  static void start() {
    if (!_initialized) return;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 3), (_) => syncNow());
    _conn?.cancel();
    _conn = Connectivity().onConnectivityChanged.listen((r) {
      if (r.any((x) => x != ConnectivityResult.none)) syncNow();
    });
    syncNow();
  }

  static void stop() {
    _timer?.cancel();
    _conn?.cancel();
  }

  /// يُستدعى بعد كل تعديل محلي: مزامنة بعد ثوانٍ (تجميع التعديلات).
  static void schedule() {
    if (!_initialized) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 8), syncNow);
  }

  static Future<void> syncNow() async {
    if (!_initialized || _running || !AppDb.isOpen) return;
    final conn = await Connectivity().checkConnectivity();
    if (conn.every((c) => c == ConnectivityResult.none)) {
      state.value = SyncState.offline;
      return;
    }
    _running = true;
    state.value = SyncState.syncing;
    try {
      await _retryPendingSignup();
      if (!signedIn) {
        state.value = SyncState.idle;
        return;
      }
      await _push(AppDb.I);
      await _pull(AppDb.I);
      lastSync.value = DateTime.now();
      lastError = null;
      state.value = SyncState.idle;
    } catch (e) {
      lastError = '$e';
      state.value = SyncState.error;
    } finally {
      _running = false;
    }
  }

  static Future<int> pendingCount() async => (await AppDb.I.scalar('SELECT COUNT(*) FROM sync_queue')).toInt();

  /// يضع كل البيانات المحلية في الطابور (بعد استرجاع ملف محلي مثلاً).
  static Future<void> enqueueAll() async {
    final db = AppDb.I;
    for (final t in Schema.synced) {
      final rows = await db.query('SELECT * FROM $t');
      for (final r in rows) {
        final data = Map<String, Object?>.from(r)..remove('seq');
        await db.db.insert('sync_queue', {
          'tbl': t,
          'row_id': '${r['id']}',
          'op': 'upsert',
          'data': jsonEncode(data),
          'created_at': nowMs(),
        });
      }
    }
    final settings = await db.query('SELECT * FROM settings');
    for (final s in settings) {
      if (Schema.localSettings.contains(s['key']) || '${s['key']}'.startsWith('pending')) continue;
      await db.db.insert('sync_queue', {
        'tbl': 'settings',
        'row_id': '${s['key']}',
        'op': 'upsert',
        'data': jsonEncode(s),
        'created_at': nowMs(),
      });
    }
  }

  static Future<void> _push(AppDb db) async {
    final uid = _client!.auth.currentUser!.id;
    while (true) {
      final batch = await db.query('SELECT * FROM sync_queue ORDER BY seq LIMIT 300');
      if (batch.isEmpty) break;
      // آخر نسخة لكل صف فقط
      final latest = <String, Map<String, Object?>>{};
      for (final q in batch) {
        latest['${q['tbl']}|${q['row_id']}'] = q;
      }
      final records = latest.values.map((q) {
        final data = jsonDecode('${q['data']}') as Map<String, dynamic>;
        return {
          'shop_id': uid,
          'tbl': q['tbl'],
          'row_id': q['row_id'],
          'data': data,
          'updated_at': data['updated_at'] ?? q['created_at'],
        };
      }).toList();
      await _client!.from(table).upsert(records, onConflict: 'shop_id,tbl,row_id');
      final maxSeq = batch.last['seq'];
      await db.db.delete('sync_queue', where: 'seq <= ?', whereArgs: [maxSeq]);
      await db.setSetting('last_push', '${nowMs()}', sync: false);
    }
  }

  static Future<void> _pull(AppDb db) async {
    var cursor = await db.getSetting('last_pull') ?? '1970-01-01T00:00:00Z';
    final touchedItems = <String>{};
    while (true) {
      final rows = await _client!
          .from(table)
          .select('tbl,row_id,data,updated_at,synced_at')
          .gt('synced_at', cursor)
          .order('synced_at')
          .limit(1000);
      if (rows.isEmpty) break;
      await _apply(db, rows, touchedItems);
      cursor = '${rows.last['synced_at']}';
      await db.setSetting('last_pull', cursor, sync: false);
      if (rows.length < 1000) break;
    }
    await _recomputeStock(db, touchedItems);
  }

  static Future<void> _pullAll(AppDb db, {void Function(int)? onProgress}) async {
    await db.setSetting('last_pull', null, sync: false);
    var cursor = '1970-01-01T00:00:00Z';
    var count = 0;
    final touched = <String>{};
    while (true) {
      final rows = await _client!
          .from(table)
          .select('tbl,row_id,data,updated_at,synced_at')
          .gt('synced_at', cursor)
          .order('synced_at')
          .limit(1000);
      if (rows.isEmpty) break;
      await _apply(db, rows, touched);
      count += rows.length;
      onProgress?.call(count);
      cursor = '${rows.last['synced_at']}';
      if (rows.length < 1000) break;
    }
    await db.setSetting('last_pull', cursor, sync: false);
    await _recomputeStock(db, touched);
  }

  static Future<void> _apply(AppDb db, List<Map<String, dynamic>> rows, Set<String> touchedItems) async {
    db.suspendOutbox = true;
    try {
      // سجل العمليات بالترتيب الزمني ليحافظ على تسلسل السلسلة.
      rows.sort((a, b) {
        if (a['tbl'] == 'audit_log' && b['tbl'] == 'audit_log') {
          return ((a['data']['created_at'] ?? 0) as num).compareTo((b['data']['created_at'] ?? 0) as num);
        }
        return 0;
      });
      await db.tx((t) async {
        for (final r in rows) {
          final tbl = '${r['tbl']}';
          final data = Map<String, Object?>.from(r['data'] as Map);
          if (tbl == 'settings') {
            if (Schema.localSettings.contains(data['key'])) continue;
            await t.rawInsert('INSERT OR REPLACE INTO settings(key, value, updated_at) VALUES(?,?,?)',
                [data['key'], data['value'], data['updated_at']]);
            continue;
          }
          if (!Schema.synced.contains(tbl)) continue;
          if (tbl == 'audit_log') {
            data.remove('seq');
            await t.rawInsert(
                'INSERT OR IGNORE INTO audit_log(${data.keys.join(',')}) VALUES(${List.filled(data.length, '?').join(',')})',
                data.values.toList());
            continue;
          }
          final local = await t.query(tbl, columns: ['updated_at'], where: 'id = ?', whereArgs: [data['id']]);
          final localTs = local.isEmpty ? -1 : ((local.first['updated_at'] as num?) ?? 0);
          final remoteTs = (data['updated_at'] as num?) ?? 0;
          if (local.isEmpty || remoteTs >= localTs) {
            final cols = await _columns(t, tbl);
            data.removeWhere((k, _) => !cols.contains(k));
            await t.rawInsert(
                'INSERT OR REPLACE INTO $tbl(${data.keys.join(',')}) VALUES(${List.filled(data.length, '?').join(',')})',
                data.values.toList());
          }
          if (tbl == 'stock_moves') touchedItems.add('${data['item_id']}');
        }
      });
    } finally {
      db.suspendOutbox = false;
    }
  }

  static final _colCache = <String, Set<String>>{};
  static Future<Set<String>> _columns(DatabaseExecutor t, String tbl) async {
    final c = _colCache[tbl];
    if (c != null) return c;
    final info = await t.rawQuery('PRAGMA table_info($tbl)');
    return _colCache[tbl] = info.map((r) => '${r['name']}').toSet();
  }

  /// الكمية الحقيقية = مجموع حركات المخزون (يحل تعارض البيع من جهازين).
  static Future<void> _recomputeStock(AppDb db, Set<String> itemIds) async {
    if (itemIds.isEmpty) return;
    db.suspendOutbox = true;
    try {
      for (final id in itemIds) {
        await db.db.rawUpdate(
            'UPDATE items SET qty = (SELECT COALESCE(SUM(qty), 0) FROM stock_moves WHERE item_id = ?) WHERE id = ?',
            [id, id]);
      }
    } finally {
      db.suspendOutbox = false;
    }
  }
}

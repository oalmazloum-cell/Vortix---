import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../core/format.dart';
import 'schema.dart';

const _uuid = Uuid();
String newId() => _uuid.v4();

/// غلاف قاعدة البيانات المحلية (SQLite).
///
/// كل عملية كتابة على جدول قابل للمزامنة تُسجَّل تلقائياً في طابور
/// [sync_queue] (Outbox) لترسلها خدمة المزامنة عند توفر الإنترنت.
class AppDb {
  AppDb._(this.db);

  final Database db;
  static AppDb? _instance;
  static AppDb get I {
    final i = _instance;
    if (i == null) throw StateError('Database not opened');
    return i;
  }

  static bool get isOpen => _instance != null;

  /// يُستدعى بعد فتح قاعدة بيانات جديدة (لمسح الذاكرة المؤقتة للخدمات).
  static void Function()? onOpen;

  /// إيقاف تسجيل المزامنة مؤقتاً (أثناء سحب البيانات من السحابة).
  bool suspendOutbox = false;

  static const fileName = 'vortex.db';

  static Future<String> defaultPath() async => p.join(await getDatabasesPath(), fileName);

  static Future<AppDb> open({String? path, DatabaseFactory? factory}) async {
    final f = factory ?? databaseFactory;
    final dbPath = path ?? await defaultPath();
    final database = await f.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: Schema.version,
        onConfigure: (d) async => d.execute('PRAGMA foreign_keys = OFF'),
        onCreate: (d, v) async {
          for (final s in Schema.create) {
            await d.execute(s);
          }
        },
        onUpgrade: (d, from, to) async {
          for (var v = from + 1; v <= to; v++) {
            for (final s in Schema.migrations[v] ?? const <String>[]) {
              await d.execute(s);
            }
          }
        },
      ),
    );
    _instance = AppDb._(database);
    onOpen?.call();
    return _instance!;
  }

  static Future<void> close() async {
    await _instance?.db.close();
    _instance = null;
  }

  /// يحذف قاعدة البيانات بالكامل (يُستخدم قبل الاسترجاع الكامل).
  static Future<void> wipe({String? path, DatabaseFactory? factory}) async {
    final f = factory ?? databaseFactory;
    await close();
    await f.deleteDatabase(path ?? await defaultPath());
  }

  // ---------------------------------------------------------------- قراءة

  Future<List<Map<String, Object?>>> query(String sql, [List<Object?> args = const []]) =>
      db.rawQuery(sql, args);

  Future<Map<String, Object?>?> first(String sql, [List<Object?> args = const []]) async {
    final r = await db.rawQuery(sql, args);
    return r.isEmpty ? null : r.first;
  }

  Future<double> scalar(String sql, [List<Object?> args = const []]) async {
    final r = await db.rawQuery(sql, args);
    if (r.isEmpty) return 0;
    final v = r.first.values.first;
    return v is num ? v.toDouble() : 0;
  }

  // ---------------------------------------------------------------- كتابة

  /// إدراج أو استبدال صف مع تسجيله للمزامنة.
  Future<void> put(String table, Map<String, Object?> row, {DatabaseExecutor? tx}) async {
    final ex = tx ?? db;
    final data = Map<String, Object?>.from(row);
    data['updated_at'] = nowMs();
    await ex.insert(table, data, conflictAlgorithm: ConflictAlgorithm.replace);
    await _outbox(ex, table, data['id'].toString(), 'upsert', data);
  }

  /// تعديل حقول محددة لصف موجود.
  Future<void> patch(String table, String id, Map<String, Object?> fields, {DatabaseExecutor? tx}) async {
    final ex = tx ?? db;
    final data = Map<String, Object?>.from(fields)..['updated_at'] = nowMs();
    await ex.update(table, data, where: 'id = ?', whereArgs: [id]);
    final full = await ex.query(table, where: 'id = ?', whereArgs: [id]);
    if (full.isNotEmpty) await _outbox(ex, table, id, 'upsert', full.first);
  }

  Future<void> _outbox(DatabaseExecutor ex, String table, String id, String op, Map<String, Object?> data) async {
    if (suspendOutbox || !Schema.synced.contains(table)) return;
    await ex.insert('sync_queue', {
      'tbl': table,
      'row_id': id,
      'op': op,
      'data': jsonEncode(data),
      'created_at': nowMs(),
    });
  }

  Future<T> tx<T>(Future<T> Function(Transaction t) action) => db.transaction(action);

  // ---------------------------------------------------------------- إعدادات

  Future<String?> getSetting(String key) async {
    final r = await db.query('settings', where: 'key = ?', whereArgs: [key]);
    return r.isEmpty ? null : r.first['value'] as String?;
  }

  Future<void> setSetting(String key, String? value, {bool sync = true}) async {
    await db.insert('settings', {'key': key, 'value': value, 'updated_at': nowMs()},
        conflictAlgorithm: ConflictAlgorithm.replace);
    if (sync && !suspendOutbox && !Schema.localSettings.contains(key)) {
      await db.insert('sync_queue', {
        'tbl': 'settings',
        'row_id': key,
        'op': 'upsert',
        'data': jsonEncode({'key': key, 'value': value, 'updated_at': nowMs()}),
        'created_at': nowMs(),
      });
    }
  }

  /// رقم تسلسلي (للفواتير وغيرها) مخزّن في الإعدادات.
  Future<int> nextNumber(String counter, {DatabaseExecutor? tx}) async {
    final ex = tx ?? db;
    final key = 'counter_$counter';
    final r = await ex.query('settings', where: 'key = ?', whereArgs: [key]);
    final n = (r.isEmpty ? 0 : int.tryParse('${r.first['value']}') ?? 0) + 1;
    await ex.insert('settings', {'key': key, 'value': '$n', 'updated_at': nowMs()},
        conflictAlgorithm: ConflictAlgorithm.replace);
    return n;
  }
}

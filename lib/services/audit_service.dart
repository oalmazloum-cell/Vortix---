import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';

import '../core/format.dart';
import '../data/db.dart';
import '../data/models.dart';
import 'session.dart';

/// سجل عمليات لا يُمحى.
///
/// - كل سجل يحمل تجزئة SHA-256 للسجل السابق (سلسلة)، فأي تلاعب بالملف
///   يكسر السلسلة ويظهر في [verify].
/// - قاعدة البيانات نفسها ترفض UPDATE و DELETE على الجدول (Triggers).
class AuditService {
  AuditService._();

  static const genesis = '0000000000000000';

  static String? _device;

  /// معرّف هذا الجهاز (يُقرأ عبر نفس المعاملة لتجنب تعليق قاعدة البيانات).
  static Future<String> deviceId([DatabaseExecutor? ex]) async {
    if (_device != null) return _device!;
    final e = ex ?? AppDb.I.db;
    final r = await e.query('settings', where: 'key = ?', whereArgs: ['device_id']);
    var id = r.isEmpty ? null : r.first['value'] as String?;
    if (id == null) {
      id = newId();
      await e.insert('settings', {'key': 'device_id', 'value': id, 'updated_at': nowMs()},
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    return _device = id;
  }

  static void resetCache() => _device = null;

  static String computeHash({
    required String prev,
    required int createdAt,
    required String? userId,
    required String action,
    required String? entity,
    required String? entityId,
    required String? details,
  }) {
    final payload = [prev, createdAt, userId ?? '', action, entity ?? '', entityId ?? '', details ?? ''].join('|');
    return sha256.convert(utf8.encode(payload)).toString();
  }

  static Future<void> log(String action,
      {String? entity, String? entityId, String? details, DatabaseExecutor? tx, AppUser? user}) async {
    final db = AppDb.I;
    final ex = tx ?? db.db;
    final device = await deviceId(ex);
    final u = user ?? Session.user;
    final last = await ex.rawQuery(
        'SELECT hash FROM audit_log WHERE device_id = ? ORDER BY seq DESC LIMIT 1', [device]);
    final prev = last.isEmpty ? genesis : '${last.first['hash']}';
    final ts = nowMs();
    final hash = computeHash(
        prev: prev, createdAt: ts, userId: u?.id, action: action, entity: entity, entityId: entityId, details: details);
    final row = <String, Object?>{
      'id': newId(),
      'device_id': device,
      'created_at': ts,
      'user_id': u?.id,
      'user_name': u?.name,
      'action': action,
      'entity': entity,
      'entity_id': entityId,
      'details': details,
      'prev_hash': prev,
      'hash': hash,
      'updated_at': ts,
    };
    await ex.insert('audit_log', row);
    if (!db.suspendOutbox) {
      await ex.insert('sync_queue', {
        'tbl': 'audit_log',
        'row_id': row['id'],
        'op': 'insert',
        'data': jsonEncode(row),
        'created_at': ts,
      });
    }
  }

  static Future<List<AuditEntry>> list({int limit = 300, String? query}) async {
    final where = (query == null || query.isEmpty) ? '' : 'WHERE action LIKE ? OR details LIKE ? OR user_name LIKE ?';
    final args = (query == null || query.isEmpty) ? <Object?>[] : ['%$query%', '%$query%', '%$query%'];
    final rows = await AppDb.I.query('SELECT * FROM audit_log $where ORDER BY created_at DESC LIMIT $limit', args);
    return rows.map(AuditEntry.fromRow).toList();
  }

  /// يتحقق من سلامة السلسلة لكل جهاز. يعيد عدد السجلات التالفة (0 = سليم).
  static Future<int> verify() async {
    final rows = await AppDb.I.query('SELECT * FROM audit_log ORDER BY device_id, created_at, seq');
    final lastByDevice = <String, String>{};
    var broken = 0;
    for (final r in rows) {
      final dev = '${r['device_id']}';
      final expectedPrev = lastByDevice[dev] ?? genesis;
      final h = computeHash(
        prev: '${r['prev_hash']}',
        createdAt: r['created_at'] as int,
        userId: r['user_id'] as String?,
        action: '${r['action']}',
        entity: r['entity'] as String?,
        entityId: r['entity_id'] as String?,
        details: r['details'] as String?,
      );
      if (r['prev_hash'] != expectedPrev || h != r['hash']) broken++;
      lastByDevice[dev] = '${r['hash']}';
    }
    return broken;
  }
}

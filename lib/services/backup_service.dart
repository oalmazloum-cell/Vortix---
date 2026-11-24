import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/config.dart';
import '../core/format.dart';
import '../data/db.dart';
import '../data/schema.dart';
import 'audit_service.dart';

/// النسخ الاحتياطي المحلي (ملف JSON) — تلقائي يومياً + يدوي + استرجاع.
class BackupService {
  BackupService._();

  static const tables = ['settings', ...Schema.synced];

  static Future<Directory> backupDir() async {
    final dir = Directory(p.join((await getApplicationDocumentsDirectory()).path, 'backups'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static Future<Map<String, Object?>> exportData() async {
    final db = AppDb.I;
    final data = <String, Object?>{
      'app': 'vortex',
      'format': 1,
      'schema': Schema.version,
      'created_at': nowMs(),
    };
    for (final t in tables) {
      data[t] = await db.query('SELECT * FROM $t');
    }
    return data;
  }

  /// ينشئ نسخة في مجلد النسخ ويعيد مسار الملف.
  static Future<File> createBackup({String label = 'auto'}) async {
    final dir = await backupDir();
    final n = DateTime.now();
    final stamp = '${n.year}${_pad2(n.month)}${_pad2(n.day)}-${_pad2(n.hour)}${_pad2(n.minute)}';
    final file = File(p.join(dir.path, 'vortex-$label-$stamp.json'));
    await file.writeAsString(jsonEncode(await exportData()));
    await AppDb.I.setSetting('last_backup', '${nowMs()}', sync: false);
    await _prune(dir);
    return file;
  }

  static String _pad2(int v) => v.toString().padLeft(2, '0');

  static Future<void> _prune(Directory dir) async {
    final files = (await dir.list().toList()).whereType<File>().where((f) => f.path.contains('vortex-auto')).toList()
      ..sort((a, b) => b.path.compareTo(a.path));
    for (final f in files.skip(AppConfig.keepBackups)) {
      await f.delete();
    }
  }

  /// نسخة تلقائية مرة كل 24 ساعة (تُستدعى عند فتح التطبيق والعودة إليه).
  static Future<bool> autoBackupIfDue() async {
    if (!AppDb.isOpen) return false;
    final last = int.tryParse(await AppDb.I.getSetting('last_backup') ?? '') ?? 0;
    if (nowMs() - last < const Duration(hours: 24).inMilliseconds) return false;
    if (await AppDb.I.getSetting('shop_name') == null) return false;
    await createBackup();
    return true;
  }

  static Future<List<File>> listBackups() async {
    final dir = await backupDir();
    final files = (await dir.list().toList()).whereType<File>().where((f) => f.path.endsWith('.json')).toList()
      ..sort((a, b) => b.path.compareTo(a.path));
    return files;
  }

  /// استرجاع كامل من ملف (يستبدل كل البيانات الحالية).
  static Future<void> restoreFromFile(File file) async {
    final data = jsonDecode(await file.readAsString()) as Map<String, Object?>;
    if (data['app'] != 'vortex') throw const FormatException('الملف ليس نسخة احتياطية من فورتكس');
    await restoreData(data);
  }

  static Future<void> restoreData(Map<String, Object?> data, {String? dbPath}) async {
    final keepDevice = AppDb.isOpen ? await AppDb.I.getSetting('device_id') : null;
    await AppDb.wipe(path: dbPath);
    final db = await AppDb.open(path: dbPath);
    db.suspendOutbox = true;
    try {
      await db.tx((t) async {
        for (final table in tables) {
          final rows = (data[table] as List?) ?? const [];
          final sorted = table == 'audit_log'
              ? (rows.cast<Map>().toList()..sort((a, b) => ((a['seq'] ?? 0) as num).compareTo((b['seq'] ?? 0) as num)))
              : rows.cast<Map>();
          for (final r in sorted) {
            final row = Map<String, Object?>.from(r);
            if (table == 'audit_log') row.remove('seq');
            if (table == 'settings' && Schema.localSettings.contains(row['key'])) continue;
            await t.insert(table, row);
          }
        }
      });
      if (keepDevice != null) await db.setSetting('device_id', keepDevice, sync: false);
      await db.setSetting('last_backup', '${nowMs()}', sync: false);
    } finally {
      db.suspendOutbox = false;
    }
    await AuditService.log('استرجاع نسخة احتياطية', entity: 'backup');
  }
}

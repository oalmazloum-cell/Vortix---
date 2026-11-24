import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

/// نسخة الويب (للمعاينة): قاعدة SQLite تعمل بـ WebAssembly وتُحفظ في المتصفح.
void configurePlatform() {
  databaseFactory = databaseFactoryFfiWebNoWebWorker;
}

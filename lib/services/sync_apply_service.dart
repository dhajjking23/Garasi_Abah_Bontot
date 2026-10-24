import 'package:sqflite/sqflite.dart';

/// Menerapkan data tabel yang diambil dari Master (lewat GET /table/{name})
/// ke database SQLite LOKAL di HP Partner.
///
/// SENGAJA memakai `Database`/`Batch` mentah (BUKAN lewat repository yang
/// ada), karena semua repository dijaga oleh requireWriteAccess() yang
/// menolak VIEWER. Sync adalah operasi SISTEM (replikasi read-only),
/// bukan aksi tulis manual oleh user — jadi memang harus melewati guard
/// tersebut. Guard di repository tetap 100% aktif untuk mencegah VIEWER
/// menulis lewat UI aplikasi seperti biasa.
///
/// Strategi: MIRROR PENUH per tabel (DELETE semua baris lokal lalu INSERT
/// ulang semua baris dari Master), bukan apply delta per baris — karena
/// payload di sync_log sengaja NULL (lihat catatan di database_helper.dart
/// soal keterbatasan json_object() di SQLite Android). Untuk skala data
/// bengkel motor (ratusan-ribuan baris), pendekatan ini jauh lebih
/// sederhana & tidak mungkin salah terap dibanding rekonsiliasi delta
/// per-baris, dengan trade-off transfer data sedikit lebih besar per sync
/// (yang wajar untuk sync manual/berkala pada jaringan WiFi lokal).
class SyncApplyService {
  /// Terapkan beberapa tabel sekaligus dalam SATU transaksi atomik — kalau
  /// ada satu tabel gagal, semua tabel batal diterapkan (tidak ada state
  /// setengah-sinkron yang bisa bikin data lokal tidak konsisten).
  Future<void> applyFullMirror(
    Database db,
    Map<String, List<Map<String, dynamic>>> tablesData,
  ) async {
    if (tablesData.isEmpty) return;

    // FK harus dimatikan SEBELUM transaksi dimulai — SQLite tidak
    // mengizinkan mengubah PRAGMA foreign_keys di tengah transaksi aktif.
    // Perlu karena kita mirror tabel independen satu-satu (DELETE+INSERT)
    // tanpa memperhatikan urutan dependency FK antar tabel.
    await db.execute('PRAGMA foreign_keys = OFF');
    try {
      await db.transaction((txn) async {
        for (final entry in tablesData.entries) {
          final table = entry.key;
          final rows = entry.value;

          await txn.delete(table);
          if (rows.isEmpty) continue;

          final batch = txn.batch();
          for (final row in rows) {
            batch.insert(
              table,
              Map<String, dynamic>.from(row),
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
          await batch.commit(noResult: true);
        }
      });
    } finally {
      await db.execute('PRAGMA foreign_keys = ON');
    }
  }
}

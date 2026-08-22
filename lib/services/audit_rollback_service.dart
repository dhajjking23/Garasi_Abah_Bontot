import 'package:sqflite/sqflite.dart';
import '../repositories/motor_repository.dart';
import '../repositories/penjualan_repository.dart';
import '../repositories/pengeluaran_repository.dart';
import '../repositories/pemasukan_repository.dart';
import '../repositories/kasbon_repository.dart';
import '../repositories/dana_talang_repository.dart';
import '../repositories/saldo_repository.dart';
import '../core/security/write_guard.dart';

/// Menghapus satu baris audit_log SEKALIGUS transaksi yang masih
/// terkait dengannya (jika transaksinya masih ada), dengan rollback
/// penuh ke Cash/Saldo Bank/Modal — sesuai spesifikasi V3 #13.
///
/// Cara kerja: baca tabel & record_id dari log yang dipilih, lalu
/// panggil method "hapus" milik repository yang sesuai (method yang
/// SAMA dipakai tombol hapus di layar masing-masing), yang sudah punya
/// logika rollback lengkap. Setelah itu, baris log yang diklik user
/// juga dihapus dari daftar.
class AuditRollbackService {
  final Database db;

  AuditRollbackService(this.db);

  /// Tabel yang bisa di-cascade-rollback lewat penghapusan log.
  static const Set<String> _tabelBisaDihapus = {
    'motor',
    'motor_cost',
    'penjualan',
    'pengeluaran',
    'pemasukan',
    'kasbon',
    'dana_talang',
    'mutasi_antar_saldo',
  };

  Future<void> hapusLogDanRollback(int logId) async {
    requireWriteAccess();
    final logResult =
        await db.query('audit_log', where: 'id = ?', whereArgs: [logId]);
    if (logResult.isEmpty) return;

    final tabel = logResult.first['tabel'] as String;
    final recordId = logResult.first['record_id'] as int?;

    if (recordId != null && _tabelBisaDihapus.contains(tabel)) {
      try {
        switch (tabel) {
          case 'motor':
            await MotorRepository(db).hapusMotor(recordId);
            break;
          case 'motor_cost':
            await MotorRepository(db).hapusBiaya(recordId);
            break;
          case 'penjualan':
            await PenjualanRepository(db).hapusPenjualan(recordId);
            break;
          case 'pengeluaran':
            await PengeluaranRepository(db).hapusPengeluaran(recordId);
            break;
          case 'pemasukan':
            await PemasukanRepository(db).hapusPemasukan(recordId);
            break;
          case 'kasbon':
            await KasbonRepository(db).hapusKasbon(recordId);
            break;
          case 'dana_talang':
            await DanaTalangRepository(db).hapusDanaTalang(recordId);
            break;
          case 'mutasi_antar_saldo':
            await SaldoRepository(db).hapusMutasiAntarSaldo(recordId);
            break;
        }
      } on StateError catch (e) {
        // Transaksi terkait tidak bisa dihapus lewat jalur ini (mis.
        // pemasukan dari penjualan motor — harus lewat menu Penjualan).
        // Batalkan seluruh operasi (log TIDAK dihapus) supaya user sadar
        // dan menghapus dari menu yang benar agar saldo tetap aman.
        throw StateError(
            '${e.message} Hapus transaksinya lewat menu terkait, log tidak dihapus.');
      } catch (_) {
        // Record sudah tidak ada (mungkin sudah dihapus manual
        // sebelumnya) — lanjut hapus log saja, tidak fatal.
      }
    }

    await db.delete('audit_log', where: 'id = ?', whereArgs: [logId]);
  }
}

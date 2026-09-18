import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../core/security/write_guard.dart';
import '../models/karyawan_model.dart';
import 'audit_log_repository.dart';

/// V5.9.5 — Repository untuk tabel `karyawan`. Tabel ini SUDAH ADA sejak
/// awal (diseed dari `AppConstants.karyawanDefault`) tapi sebelumnya
/// TIDAK PERNAH benar-benar dipakai — semua dropdown karyawan di seluruh
/// app (Kasbon, Dana Talang, Gajihan) langsung memakai daftar nama
/// statis. Repository ini mengaktifkan tabel tsb untuk satu tujuan
/// spesifik: menyimpan Gaji Pokok STANDAR per karyawan supaya
/// GajihanScreen bisa auto-fill (bukan input manual tiap kali), sambil
/// tetap bisa diedit per-transaksi.
class KaryawanRepository {
  final Database db;

  KaryawanRepository(this.db);

  /// Ambil data karyawan by nama. Kalau baris belum ada (mis. karyawan
  /// baru yang belum pernah disentuh tabel ini), buat baris default
  /// (gaji_pokok 0) secara transparan supaya caller selalu dapat objek
  /// valid tanpa perlu cek null berulang.
  Future<KaryawanModel> getOrCreateByNama(String nama) async {
    final result =
        await db.query('karyawan', where: 'nama = ?', whereArgs: [nama]);
    if (result.isNotEmpty) {
      return KaryawanModel.fromMap(result.first);
    }
    final now = DateTime.now();
    final baru = KaryawanModel(nama: nama, createdAt: now);
    final id = await db.insert('karyawan', baru.toMap());
    return baru.copyWith(id: id);
  }

  Future<List<KaryawanModel>> getAll() async {
    final result = await db.query('karyawan', orderBy: 'nama ASC');
    return result.map((e) => KaryawanModel.fromMap(e)).toList();
  }

  /// Set/update Gaji Pokok STANDAR untuk karyawan (dipakai auto-fill).
  /// TIDAK menyentuh cash/bank sama sekali — murni data master.
  Future<KaryawanModel> setGajiPokokStandar(
      String nama, double gajiPokok) async {
    requireWriteAccess();
    final lama = await getOrCreateByNama(nama);
    final baru = lama.copyWith(gajiPokok: gajiPokok);
    await db.update('karyawan', baru.toMap(),
        where: 'id = ?', whereArgs: [baru.id]);
    final auditLog = AuditLogRepository(db);
    await auditLog.catatUpdate(
      'karyawan',
      baru.id!,
      jsonEncode(lama.toMap()),
      jsonEncode(baru.toMap()),
      keterangan: 'Update gaji pokok standar $nama',
    );
    return baru;
  }
}

import 'package:sqflite/sqflite.dart';
import '../core/constants/app_constants.dart';
import '../models/kategori_custom_model.dart';
import '../core/security/write_guard.dart';

/// Menyimpan jenis transaksi (kategori) buatan user untuk Pemasukan,
/// Pengeluaran, dan Biaya Motor. Sekali dibuat, kategori ini permanen
/// dan selalu muncul di pilihan berikutnya — ini BUKAN nilai transaksi,
/// hanya daftar nama jenis yang bisa dipilih.
class KategoriRepository {
  final Database db;

  KategoriRepository(this.db);

  List<String> _daftarBawaan(String tipe) {
    switch (tipe) {
      case AppConstants.kategoriTipePemasukan:
        return AppConstants.kategoriPemasukan;
      case AppConstants.kategoriTipePengeluaran:
        return AppConstants.kategoriPengeluaran;
      case AppConstants.kategoriTipeMotorCost:
        return AppConstants.kategoriMotorCost;
      default:
        return const [];
    }
  }

  /// Daftar lengkap = kategori bawaan aplikasi + kategori custom yang
  /// sudah pernah dibuat user, tanpa duplikat.
  Future<List<String>> getDaftarLengkap(String tipe) async {
    final bawaan = _daftarBawaan(tipe);
    final result = await db.query(
      'kategori_custom',
      where: 'tipe = ?',
      whereArgs: [tipe],
      orderBy: 'nama ASC',
    );
    final custom = result.map((e) => e['nama'] as String).toList();
    final gabungan = [...bawaan];
    for (final c in custom) {
      if (!gabungan.any((k) => k.toLowerCase() == c.toLowerCase())) {
        gabungan.add(c);
      }
    }
    return gabungan;
  }

  /// Tambah kategori baru. Menolak jika nama sudah ada (bawaan atau
  /// custom), tidak case-sensitive, supaya tidak ada duplikat seperti
  /// "servis" vs "Servis".
  Future<String> tambahKategori(String tipe, String nama) async {
    requireWriteAccess();
    final namaBersih = nama.trim();
    if (namaBersih.isEmpty) {
      throw ArgumentError('Nama jenis transaksi tidak boleh kosong');
    }
    final daftarSekarang = await getDaftarLengkap(tipe);
    if (daftarSekarang.any((k) => k.toLowerCase() == namaBersih.toLowerCase())) {
      throw StateError('Jenis transaksi "$namaBersih" sudah ada');
    }

    final model = KategoriCustomModel(
      tipe: tipe,
      nama: namaBersih,
      createdAt: DateTime.now(),
    );
    await db.insert('kategori_custom', model.toMap());
    return namaBersih;
  }

  Future<void> hapusKategori(String tipe, String nama) async {
    requireWriteAccess();
    await db.delete('kategori_custom',
        where: 'tipe = ? AND nama = ?', whereArgs: [tipe, nama]);
  }
}

import 'package:sqflite/sqflite.dart';

/// V5.8 — satu baris detail biaya transfer, dari sumber manapun.
class BiayaTransferDetailItem {
  final DateTime tanggal;
  final String sumber; // Pengeluaran / Motor / Biaya Motor / Dana Talang / Kasbon / Manual
  final String keterangan;
  final double nominal;

  BiayaTransferDetailItem({
    required this.tanggal,
    required this.sumber,
    required this.keterangan,
    required this.nominal,
  });
}

/// V5.8 — pelengkap dari perbaikan "Total Biaya Transfer Gabungan" (V5.7):
/// dulu totalnya sudah benar tapi TIDAK ADA rincian per transaksi. Service
/// ini mengumpulkan baris detail dari 5 sumber yang benar-benar memotong
/// biaya transfer (kolom biaya_admin_transfer / biaya_admin), supaya tiap
/// rupiah di "Total Gabungan" bisa ditelusuri asalnya — sesuai prinsip
/// audit "setiap rupiah harus punya posisi/asal yang jelas".
class BiayaTransferDetailService {
  final Database db;
  BiayaTransferDetailService(this.db);

  Future<List<BiayaTransferDetailItem>> getDetail({int? periodeId}) async {
    final hasil = <BiayaTransferDetailItem>[];

    // 1) Pengeluaran (biaya_admin > 0)
    final pengeluaran = await db.rawQuery('''
      SELECT tanggal, kategori, keterangan, biaya_admin FROM pengeluaran
      WHERE biaya_admin > 0 ${periodeId != null ? "AND periode_id = ?" : ""}
    ''', periodeId != null ? [periodeId] : []);
    for (final r in pengeluaran) {
      hasil.add(BiayaTransferDetailItem(
        tanggal: DateTime.parse(r['tanggal'] as String),
        sumber: 'Pengeluaran',
        keterangan: '${r['kategori']}'
            '${(r['keterangan'] as String?)?.isNotEmpty == true ? " - ${r['keterangan']}" : ""}',
        nominal: (r['biaya_admin'] as num).toDouble(),
      ));
    }

    // 2) Motor (beli motor via transfer)
    final motor = await db.rawQuery('''
      SELECT tanggal_masuk, merk, tipe, plat_nomor, biaya_admin_transfer FROM motor
      WHERE biaya_admin_transfer > 0 ${periodeId != null ? "AND periode_id = ?" : ""}
    ''', periodeId != null ? [periodeId] : []);
    for (final r in motor) {
      final plat = r['plat_nomor'] as String?;
      hasil.add(BiayaTransferDetailItem(
        tanggal: DateTime.parse(r['tanggal_masuk'] as String),
        sumber: 'Beli Motor',
        keterangan:
            'Beli ${r['merk']} ${r['tipe']}${plat?.isNotEmpty == true ? " ($plat)" : ""}',
        nominal: (r['biaya_admin_transfer'] as num).toDouble(),
      ));
    }

    // 3) Biaya Motor (motor_cost, join motor untuk nama unit)
    final motorCost = await db.rawQuery('''
      SELECT mc.tanggal, mc.kategori, mc.keterangan, mc.biaya_admin_transfer,
             m.merk, m.tipe, m.plat_nomor
      FROM motor_cost mc
      JOIN motor m ON mc.motor_id = m.id
      WHERE mc.biaya_admin_transfer > 0
      ${periodeId != null ? "AND m.periode_id = ?" : ""}
    ''', periodeId != null ? [periodeId] : []);
    for (final r in motorCost) {
      final plat = r['plat_nomor'] as String?;
      hasil.add(BiayaTransferDetailItem(
        tanggal: DateTime.parse(r['tanggal'] as String),
        sumber: 'Biaya Motor',
        keterangan: '${r['kategori']} - ${r['merk']} ${r['tipe']}'
            '${plat?.isNotEmpty == true ? " ($plat)" : ""}'
            '${(r['keterangan'] as String?)?.isNotEmpty == true ? " - ${r['keterangan']}" : ""}',
        nominal: (r['biaya_admin_transfer'] as num).toDouble(),
      ));
    }

    // 4) Dana Talang
    final danaTalang = await db.rawQuery('''
      SELECT tanggal, nama_partner, jenis, keterangan, biaya_admin_transfer FROM dana_talang
      WHERE biaya_admin_transfer > 0 ${periodeId != null ? "AND periode_id = ?" : ""}
    ''', periodeId != null ? [periodeId] : []);
    for (final r in danaTalang) {
      final jenis = r['jenis'] == 'SAYA_MENALANGI' ? 'Menalangi' : 'Menerima Talangan';
      hasil.add(BiayaTransferDetailItem(
        tanggal: DateTime.parse(r['tanggal'] as String),
        sumber: 'Dana Talang',
        keterangan: '$jenis - ${r['nama_partner']}'
            '${(r['keterangan'] as String?)?.isNotEmpty == true ? " - ${r['keterangan']}" : ""}',
        nominal: (r['biaya_admin_transfer'] as num).toDouble(),
      ));
    }

    // 5) Kasbon (kasbon TIDAK punya periode_id, jadi selalu ditampilkan
    // apa adanya (global) supaya konsisten dengan total gabungan di
    // dashboard_service.dart yang juga menjumlahkan kasbon secara global
    // terlepas dari filter periode).
    final kasbon = await db.rawQuery('''
      SELECT tanggal, nama_karyawan, keterangan, biaya_admin_transfer FROM kasbon
      WHERE biaya_admin_transfer > 0
    ''');
    for (final r in kasbon) {
      hasil.add(BiayaTransferDetailItem(
        tanggal: DateTime.parse(r['tanggal'] as String),
        sumber: 'Kasbon',
        keterangan: 'Kasbon - ${r['nama_karyawan']}'
            '${(r['keterangan'] as String?)?.isNotEmpty == true ? " - ${r['keterangan']}" : ""}',
        nominal: (r['biaya_admin_transfer'] as num).toDouble(),
      ));
    }

    hasil.sort((a, b) => b.tanggal.compareTo(a.tanggal));
    return hasil;
  }
}

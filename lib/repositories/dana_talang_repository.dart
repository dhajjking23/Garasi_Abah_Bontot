import 'package:sqflite/sqflite.dart';
import 'dart:convert';
import '../core/constants/app_constants.dart';
import '../models/dana_talang_model.dart';
import '../models/dana_talang_pembayaran_model.dart';
import 'audit_log_repository.dart';
import 'saldo_repository.dart';
import '../core/security/write_guard.dart';

/// Repository Dana Talang Partner.
///
/// KONSEP: Dana Talang BUKAN pengeluaran/pemasukan biasa.
/// - SAYA_MENALANGI (kita beri uang ke partner): cash/bank turun,
///   Piutang bertambah.
/// - SAYA_MENERIMA (partner beri uang ke kita): cash/bank naik,
///   Hutang bertambah.
/// Pembayaran kembali membalik arah kas dari transaksi awal dan
/// mengurangi piutang/hutang sampai status jadi LUNAS.
class DanaTalangRepository {
  final Database db;

  DanaTalangRepository(this.db);

  void _validasiSplit(String metode, double cash, double transfer, double total) {
    if (metode == AppConstants.metodeCampuran) {
      final jumlah = cash + transfer;
      if ((jumlah - total).abs() > 0.5) {
        throw ArgumentError(
            'Cash + Transfer (Rp${jumlah.toStringAsFixed(0)}) harus sama dengan nominal (Rp${total.toStringAsFixed(0)})');
      }
    }
  }

  (double cash, double transfer) _hitungSplit(
      String metode, double cash, double transfer, double total) {
    switch (metode) {
      case AppConstants.metodeTransfer:
        return (0, total);
      case AppConstants.metodeCampuran:
        _validasiSplit(metode, cash, transfer, total);
        return (cash, transfer);
      case AppConstants.metodeCash:
      default:
        return (total, 0);
    }
  }

  /// Catat dana talang baru. [jenis] SAYA_MENALANGI atau SAYA_MENERIMA.
  /// [bentukTalangan] hanya relevan untuk SAYA_MENERIMA: TUNAI (partner
  /// benar-benar kasih cash/transfer -> Cash/Bank saya bertambah) atau
  /// NON_TUNAI (partner membayarkan sesuatu atas nama saya -> Cash/Bank
  /// saya TIDAK berubah, hanya hutang yang tercatat).
  Future<DanaTalangModel> tambahDanaTalang({
    required String namaPartner,
    required DateTime tanggal,
    required String jenis,
    required double nominal,
    String metodePembayaran = AppConstants.metodeCash,
    double cashDibayar = 0,
    double transferDibayar = 0,
    String? jenisTransfer,
    String bentukTalangan = AppConstants.bentukTalanganTunai,
    String? keterangan,
    int? periodeId,
  }) async {
    requireWriteAccess();
    return db.transaction<DanaTalangModel>((txn) async {
      final isMenalangi = jenis == AppConstants.danaTalangSayaMenalangi;
      // Non-tunai hanya berlaku untuk SAYA_MENERIMA. Untuk SAYA_MENALANGI
      // (atau jika bentuk TUNAI), tetap hitung split cash/transfer.
      final isNonTunai =
          !isMenalangi && bentukTalangan == AppConstants.bentukTalanganNonTunai;

      final (cash, transfer) = isNonTunai
          ? (0.0, 0.0)
          : _hitungSplit(metodePembayaran, cashDibayar, transferDibayar, nominal);

      final now = DateTime.now();
      var model = DanaTalangModel(
        namaPartner: namaPartner,
        tanggal: tanggal,
        jenis: jenis,
        nominal: nominal,
        metodePembayaran: isNonTunai ? AppConstants.metodeCash : metodePembayaran,
        cashTerpakai: cash,
        transferTerpakai: transfer,
        jenisTransfer: (isMenalangi && transfer > 0) ? jenisTransfer : null,
        bentukTalangan: isMenalangi ? AppConstants.bentukTalanganTunai : bentukTalangan,
        status: AppConstants.statusDanaTalangBelumLunas,
        totalDibayarKembali: 0,
        keterangan: keterangan,
        periodeId: periodeId,
        createdAt: now,
        updatedAt: now,
      );
      final id = await txn.insert('dana_talang', model.toMap());
      var saved = model.copyWith(id: id);

      final auditLog = AuditLogRepository(txn);
      await auditLog.catatCreate(
        'dana_talang',
        id,
        jsonEncode(saved.toMap()),
        keterangan:
            '${isMenalangi ? "Menalangi" : "Menerima talangan dari"} $namaPartner'
            '${isNonTunai ? " (non-tunai — dibayarkan atas nama saya)" : ""}',
      );

      // NON_TUNAI: tidak ada uang yang benar-benar masuk ke Cash/Bank
      // saya, jadi TIDAK dicatat sebagai mutasi kas — hanya hutangnya
      // yang tercatat di tabel dana_talang. Baru saat bayarKembali,
      // Cash/Bank saya akan berkurang seperti biasa.
      if (!isNonTunai) {
        final saldoRepo = SaldoRepository(txn);
        final biayaAdmin = await saldoRepo.bayarCampuran(
          cash: cash,
          transfer: transfer,
          tipe: isMenalangi ? AppConstants.cashFlowKeluar : AppConstants.cashFlowMasuk,
          referensi: isMenalangi
              ? AppConstants.cashFlowRefDanaTalangBeri
              : AppConstants.cashFlowRefDanaTalangTerima,
          referensiId: id,
          keterangan:
              '${isMenalangi ? "Dana talang ke" : "Dana talang dari"} $namaPartner',
          tanggal: tanggal,
          jenisTransfer: isMenalangi ? jenisTransfer : null,
        );
        if (biayaAdmin > 0) {
          saved = saved.copyWith(biayaAdminTransfer: biayaAdmin);
          await txn.update('dana_talang', saved.toMap(),
              where: 'id = ?', whereArgs: [id]);
        }
      }

      return saved;
    });
  }

  /// Edit dana talang. Nominal hanya boleh diubah jika BELUM ada
  /// pembayaran kembali (total_dibayar_kembali == 0) supaya rollback
  /// kas tetap sederhana & akurat.
  Future<DanaTalangModel> editDanaTalang({
    required int id,
    required String namaPartner,
    required DateTime tanggal,
    required double nominalBaru,
    String metodePembayaranBaru = AppConstants.metodeCash,
    double cashDibayarBaru = 0,
    double transferDibayarBaru = 0,
    String? jenisTransferBaru,
    String? keterangan,
  }) async {
    requireWriteAccess();
    return db.transaction<DanaTalangModel>((txn) async {
      final result =
          await txn.query('dana_talang', where: 'id = ?', whereArgs: [id]);
      if (result.isEmpty) throw ArgumentError('Dana talang tidak ditemukan');
      final lama = DanaTalangModel.fromMap(result.first);

      if (lama.status == AppConstants.statusDanaTalangBatal) {
        throw StateError('Dana talang yang sudah dibatalkan tidak bisa diedit.');
      }
      if (lama.totalDibayarKembali > 0 && nominalBaru != lama.nominal) {
        throw StateError(
            'Nominal tidak bisa diubah karena sudah ada pembayaran kembali. Hapus riwayat pembayaran dulu.');
      }

      final saldoRepo = SaldoRepository(txn);
      final auditLog = AuditLogRepository(txn);
      final isMenalangi = lama.jenis == AppConstants.danaTalangSayaMenalangi;
      final isNonTunai = lama.isNonTunai;

      // Balik efek kas awal yang lama (no-op otomatis jika non-tunai,
      // karena cashTerpakai/transferTerpakai sudah 0 sejak awal), juga
      // balik biaya admin transfer lama jika ada.
      if (!isNonTunai) {
        await saldoRepo.bayarCampuran(
          cash: lama.cashTerpakai,
          transfer: lama.transferTerpakai,
          tipe: isMenalangi ? AppConstants.cashFlowMasuk : AppConstants.cashFlowKeluar,
          referensi: isMenalangi
              ? AppConstants.cashFlowRefDanaTalangBeri
              : AppConstants.cashFlowRefDanaTalangTerima,
          referensiId: id,
          keterangan: 'Koreksi dana talang $namaPartner (nilai lama dibatalkan)',
        );
        if (isMenalangi && lama.biayaAdminTransfer > 0) {
          await saldoRepo.mutasiBank(
            nominal: lama.biayaAdminTransfer,
            tipe: AppConstants.cashFlowMasuk,
            referensi: AppConstants.cashFlowRefAdminTransfer,
            referensiId: id,
            keterangan: 'Koreksi admin transfer dana talang (nilai lama dibatalkan)',
          );
        }
      }

      final (cash, transfer) = isNonTunai
          ? (0.0, 0.0)
          : _hitungSplit(
              metodePembayaranBaru, cashDibayarBaru, transferDibayarBaru, nominalBaru);

      var baru = lama.copyWith(
        namaPartner: namaPartner,
        tanggal: tanggal,
        nominal: nominalBaru,
        metodePembayaran: isNonTunai ? lama.metodePembayaran : metodePembayaranBaru,
        cashTerpakai: cash,
        transferTerpakai: transfer,
        jenisTransfer: (isMenalangi && transfer > 0) ? jenisTransferBaru : null,
        biayaAdminTransfer: 0,
        keterangan: keterangan,
        status: lama.totalDibayarKembali >= nominalBaru && nominalBaru > 0
            ? AppConstants.statusDanaTalangLunas
            : (lama.totalDibayarKembali > 0
                ? AppConstants.statusDanaTalangSebagianLunas
                : AppConstants.statusDanaTalangBelumLunas),
        updatedAt: DateTime.now(),
      );
      await txn.update('dana_talang', baru.toMap(),
          where: 'id = ?', whereArgs: [id]);
      await auditLog.catatUpdate(
        'dana_talang',
        id,
        jsonEncode(lama.toMap()),
        jsonEncode(baru.toMap()),
        keterangan: 'Edit dana talang $namaPartner',
      );

      if (!isNonTunai) {
        final biayaAdmin = await saldoRepo.bayarCampuran(
          cash: cash,
          transfer: transfer,
          tipe: isMenalangi ? AppConstants.cashFlowKeluar : AppConstants.cashFlowMasuk,
          referensi: isMenalangi
              ? AppConstants.cashFlowRefDanaTalangBeri
              : AppConstants.cashFlowRefDanaTalangTerima,
          referensiId: id,
          keterangan:
              '${isMenalangi ? "Dana talang ke" : "Dana talang dari"} $namaPartner (setelah edit)',
          tanggal: tanggal,
          jenisTransfer: isMenalangi ? jenisTransferBaru : null,
        );
        if (biayaAdmin > 0) {
          baru = baru.copyWith(biayaAdminTransfer: biayaAdmin);
          await txn.update('dana_talang', baru.toMap(),
              where: 'id = ?', whereArgs: [id]);
        }
      }

      return baru;
    });
  }

  /// Bayar kembali (cicilan/pelunasan). Untuk SAYA_MENALANGI, partner
  /// membayar kembali ke kita -> cash/bank kita bertambah. Untuk
  /// SAYA_MENERIMA, kita membayar kembali ke partner -> cash/bank kita
  /// berkurang.
  Future<DanaTalangModel> bayarKembali({
    required int danaTalangId,
    required DateTime tanggal,
    required double nominal,
    String metodePembayaran = AppConstants.metodeCash,
    double cashDibayar = 0,
    double transferDibayar = 0,
    String? jenisTransfer,
    String? keterangan,
  }) async {
    requireWriteAccess();
    return db.transaction<DanaTalangModel>((txn) async {
      final result = await txn
          .query('dana_talang', where: 'id = ?', whereArgs: [danaTalangId]);
      if (result.isEmpty) throw ArgumentError('Dana talang tidak ditemukan');
      final talang = DanaTalangModel.fromMap(result.first);

      if (!talang.isAktif) {
        throw StateError('Dana talang ini sudah lunas/dibatalkan.');
      }
      if (nominal > talang.sisa) {
        throw ArgumentError(
            'Nominal pembayaran (Rp${nominal.toStringAsFixed(0)}) melebihi sisa (Rp${talang.sisa.toStringAsFixed(0)})');
      }

      final (cash, transfer) =
          _hitungSplit(metodePembayaran, cashDibayar, transferDibayar, nominal);

      final isMenalangi = talang.jenis == AppConstants.danaTalangSayaMenalangi;
      final now = DateTime.now();
      var pembayaran = DanaTalangPembayaranModel(
        danaTalangId: danaTalangId,
        tanggal: tanggal,
        nominal: nominal,
        metodePembayaran: metodePembayaran,
        cashTerpakai: cash,
        transferTerpakai: transfer,
        jenisTransfer: (!isMenalangi && transfer > 0) ? jenisTransfer : null,
        keterangan: keterangan,
        createdAt: now,
      );
      final pembayaranId =
          await txn.insert('dana_talang_pembayaran', pembayaran.toMap());
      pembayaran = pembayaran.copyWith(id: pembayaranId);

      final auditLog = AuditLogRepository(txn);
      await auditLog.catatCreate(
        'dana_talang_pembayaran',
        pembayaranId,
        jsonEncode(pembayaran.toMap()),
        keterangan: 'Pembayaran kembali dana talang ${talang.namaPartner}',
      );

      final totalBaru = talang.totalDibayarKembali + nominal;
      final statusBaru = totalBaru >= talang.nominal
          ? AppConstants.statusDanaTalangLunas
          : AppConstants.statusDanaTalangSebagianLunas;

      final talangBaru = talang.copyWith(
        totalDibayarKembali: totalBaru,
        status: statusBaru,
        updatedAt: now,
      );
      await txn.update('dana_talang', talangBaru.toMap(),
          where: 'id = ?', whereArgs: [danaTalangId]);
      await auditLog.catatUpdate(
        'dana_talang',
        danaTalangId,
        jsonEncode(talang.toMap()),
        jsonEncode(talangBaru.toMap()),
        keterangan: 'Status -> $statusBaru',
      );

      final saldoRepo = SaldoRepository(txn);
      // Menalangi: pembayaran kembali dari partner -> cash/bank kita naik.
      // Menerima: kita bayar balik ke partner -> cash/bank kita turun.
      final biayaAdmin = await saldoRepo.bayarCampuran(
        cash: cash,
        transfer: transfer,
        tipe: isMenalangi ? AppConstants.cashFlowMasuk : AppConstants.cashFlowKeluar,
        referensi: AppConstants.cashFlowRefDanaTalangBayar,
        referensiId: pembayaranId,
        keterangan: 'Pembayaran kembali dana talang ${talang.namaPartner}',
        tanggal: tanggal,
        jenisTransfer: !isMenalangi ? jenisTransfer : null,
      );
      if (biayaAdmin > 0) {
        pembayaran = pembayaran.copyWith(biayaAdminTransfer: biayaAdmin);
        await txn.update('dana_talang_pembayaran', pembayaran.toMap(),
            where: 'id = ?', whereArgs: [pembayaranId]);
      }

      return talangBaru;
    });
  }

  /// Edit HANYA tanggal transaksi dana talang utama.
  Future<void> editTanggalDanaTalang(int id, DateTime tanggalBaru) async {
    requireWriteAccess();
    return db.transaction<void>((txn) async {
      final result =
          await txn.query('dana_talang', where: 'id = ?', whereArgs: [id]);
      if (result.isEmpty) throw ArgumentError('Dana talang tidak ditemukan');
      final lama = DanaTalangModel.fromMap(result.first);
      final auditLog = AuditLogRepository(txn);

      await txn.update(
        'dana_talang',
        {
          'tanggal': tanggalBaru.toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      await auditLog.catatUpdate(
        'dana_talang',
        id,
        jsonEncode({'tanggal': lama.tanggal.toIso8601String()}),
        jsonEncode({'tanggal': tanggalBaru.toIso8601String()}),
        keterangan: 'Mengubah tanggal dana talang ${lama.namaPartner}: dari '
            '${lama.tanggal.toIso8601String().split("T").first} menjadi '
            '${tanggalBaru.toIso8601String().split("T").first}',
      );
    });
  }

  /// Edit HANYA tanggal riwayat pembayaran kembali dana talang.
  Future<void> editTanggalPembayaran(int pembayaranId, DateTime tanggalBaru) async {
    requireWriteAccess();
    return db.transaction<void>((txn) async {
      final result = await txn.query('dana_talang_pembayaran',
          where: 'id = ?', whereArgs: [pembayaranId]);
      if (result.isEmpty) throw ArgumentError('Pembayaran tidak ditemukan');
      final lama = DanaTalangPembayaranModel.fromMap(result.first);
      final auditLog = AuditLogRepository(txn);

      await txn.update(
        'dana_talang_pembayaran',
        {'tanggal': tanggalBaru.toIso8601String()},
        where: 'id = ?',
        whereArgs: [pembayaranId],
      );
      await auditLog.catatUpdate(
        'dana_talang_pembayaran',
        pembayaranId,
        jsonEncode({'tanggal': lama.tanggal.toIso8601String()}),
        jsonEncode({'tanggal': tanggalBaru.toIso8601String()}),
        keterangan: 'Mengubah tanggal pembayaran dana talang #${lama.danaTalangId}: dari '
            '${lama.tanggal.toIso8601String().split("T").first} menjadi '
            '${tanggalBaru.toIso8601String().split("T").first}',
      );
    });
  }

  /// Batalkan dana talang (status -> BATAL). Hanya boleh jika BELUM ada
  /// pembayaran kembali sama sekali — membalik efek kas awal.
  Future<DanaTalangModel> batalkanDanaTalang(int id, {String? alasan}) async {
    requireWriteAccess();
    return db.transaction<DanaTalangModel>((txn) async {
      final result =
          await txn.query('dana_talang', where: 'id = ?', whereArgs: [id]);
      if (result.isEmpty) throw ArgumentError('Dana talang tidak ditemukan');
      final talang = DanaTalangModel.fromMap(result.first);

      if (talang.totalDibayarKembali > 0) {
        throw StateError(
            'Tidak bisa dibatalkan karena sudah ada pembayaran kembali. Hapus saja transaksinya.');
      }
      if (!talang.isAktif) {
        throw StateError('Dana talang ini sudah lunas/dibatalkan.');
      }

      final saldoRepo = SaldoRepository(txn);
      final auditLog = AuditLogRepository(txn);
      final isMenalangi = talang.jenis == AppConstants.danaTalangSayaMenalangi;

      await saldoRepo.bayarCampuran(
        cash: talang.cashTerpakai,
        transfer: talang.transferTerpakai,
        tipe: isMenalangi ? AppConstants.cashFlowMasuk : AppConstants.cashFlowKeluar,
        referensi: isMenalangi
            ? AppConstants.cashFlowRefDanaTalangBeri
            : AppConstants.cashFlowRefDanaTalangTerima,
        referensiId: id,
        keterangan: 'Batal dana talang ${talang.namaPartner}',
      );
      if (isMenalangi && talang.biayaAdminTransfer > 0) {
        await saldoRepo.mutasiBank(
          nominal: talang.biayaAdminTransfer,
          tipe: AppConstants.cashFlowMasuk,
          referensi: AppConstants.cashFlowRefAdminTransfer,
          referensiId: id,
          keterangan: 'Batal admin transfer dana talang ${talang.namaPartner}',
        );
      }

      final baru = talang.copyWith(
        status: AppConstants.statusDanaTalangBatal,
        updatedAt: DateTime.now(),
      );
      await txn.update('dana_talang', baru.toMap(),
          where: 'id = ?', whereArgs: [id]);
      await auditLog.catatUpdate(
        'dana_talang',
        id,
        jsonEncode(talang.toMap()),
        jsonEncode(baru.toMap()),
        keterangan: alasan ?? 'Dibatalkan',
      );

      return baru;
    });
  }

  /// HAPUS dana talang beserta seluruh riwayat pembayarannya. Rollback
  /// penuh: semua pembayaran kembali dibalik, lalu transaksi awal
  /// dibalik, baru baris dihapus (cascade menghapus dana_talang_pembayaran).
  Future<void> hapusDanaTalang(int id) async {
    requireWriteAccess();
    return db.transaction<void>((txn) async {
      final result =
          await txn.query('dana_talang', where: 'id = ?', whereArgs: [id]);
      if (result.isEmpty) return;
      final talang = DanaTalangModel.fromMap(result.first);

      final saldoRepo = SaldoRepository(txn);
      final auditLog = AuditLogRepository(txn);
      final isMenalangi = talang.jenis == AppConstants.danaTalangSayaMenalangi;

      // 1) Balik semua pembayaran kembali.
      final pembayaranList = await txn.query('dana_talang_pembayaran',
          where: 'dana_talang_id = ?', whereArgs: [id]);
      for (final p in pembayaranList) {
        final bayar = DanaTalangPembayaranModel.fromMap(p);
        await saldoRepo.bayarCampuran(
          cash: bayar.cashTerpakai,
          transfer: bayar.transferTerpakai,
          tipe:
              isMenalangi ? AppConstants.cashFlowKeluar : AppConstants.cashFlowMasuk,
          referensi: AppConstants.cashFlowRefDanaTalangBayar,
          referensiId: bayar.id,
          keterangan: 'Rollback hapus dana talang ${talang.namaPartner}',
        );
        if (!isMenalangi && bayar.biayaAdminTransfer > 0) {
          await saldoRepo.mutasiBank(
            nominal: bayar.biayaAdminTransfer,
            tipe: AppConstants.cashFlowMasuk,
            referensi: AppConstants.cashFlowRefAdminTransfer,
            referensiId: bayar.id,
            keterangan: 'Rollback hapus admin transfer pembayaran dana talang ${talang.namaPartner}',
          );
        }
      }

      // 2) Balik transaksi awal (jika belum dibatalkan sebelumnya).
      if (talang.status != AppConstants.statusDanaTalangBatal) {
        await saldoRepo.bayarCampuran(
          cash: talang.cashTerpakai,
          transfer: talang.transferTerpakai,
          tipe:
              isMenalangi ? AppConstants.cashFlowMasuk : AppConstants.cashFlowKeluar,
          referensi: isMenalangi
              ? AppConstants.cashFlowRefDanaTalangBeri
              : AppConstants.cashFlowRefDanaTalangTerima,
          referensiId: id,
          keterangan: 'Rollback hapus dana talang ${talang.namaPartner}',
        );
        if (isMenalangi && talang.biayaAdminTransfer > 0) {
          await saldoRepo.mutasiBank(
            nominal: talang.biayaAdminTransfer,
            tipe: AppConstants.cashFlowMasuk,
            referensi: AppConstants.cashFlowRefAdminTransfer,
            referensiId: id,
            keterangan: 'Rollback hapus admin transfer dana talang ${talang.namaPartner}',
          );
        }
      }

      // 3) Hapus (cascade menghapus dana_talang_pembayaran).
      await txn.delete('dana_talang', where: 'id = ?', whereArgs: [id]);
      await auditLog.catatDelete(
        'dana_talang',
        id,
        jsonEncode(talang.toMap()),
        keterangan: 'Hapus dana talang ${talang.namaPartner} — saldo dikembalikan',
      );
    });
  }

  Future<List<DanaTalangModel>> getAll({String? jenis, String? status}) async {
    final whereClauses = <String>[];
    final whereArgs = <Object?>[];
    if (jenis != null) {
      whereClauses.add('jenis = ?');
      whereArgs.add(jenis);
    }
    if (status != null) {
      whereClauses.add('status = ?');
      whereArgs.add(status);
    }
    final result = await db.query(
      'dana_talang',
      where: whereClauses.isEmpty ? null : whereClauses.join(' AND '),
      whereArgs: whereArgs.isEmpty ? null : whereArgs,
      orderBy: 'tanggal DESC',
    );
    return result.map((e) => DanaTalangModel.fromMap(e)).toList();
  }

  Future<List<DanaTalangPembayaranModel>> getRiwayatPembayaran(
      int danaTalangId) async {
    final result = await db.query(
      'dana_talang_pembayaran',
      where: 'dana_talang_id = ?',
      whereArgs: [danaTalangId],
      orderBy: 'tanggal DESC',
    );
    return result.map((e) => DanaTalangPembayaranModel.fromMap(e)).toList();
  }

  /// Total Piutang Partner (dana yang kita talangi & belum kembali).
  Future<double> getTotalPiutangPartner() async {
    final result = await db.rawQuery('''
      SELECT nominal, total_dibayar_kembali FROM dana_talang
      WHERE jenis = ? AND status NOT IN (?, ?)
    ''', [
      AppConstants.danaTalangSayaMenalangi,
      AppConstants.statusDanaTalangLunas,
      AppConstants.statusDanaTalangBatal,
    ]);
    double total = 0;
    for (final row in result) {
      total += (row['nominal'] as num).toDouble() -
          (row['total_dibayar_kembali'] as num).toDouble();
    }
    return total;
  }

  /// Total Hutang Partner (talangan partner ke kita & belum kita bayar).
  Future<double> getTotalHutangPartner() async {
    final result = await db.rawQuery('''
      SELECT nominal, total_dibayar_kembali FROM dana_talang
      WHERE jenis = ? AND status NOT IN (?, ?)
    ''', [
      AppConstants.danaTalangSayaMenerima,
      AppConstants.statusDanaTalangLunas,
      AppConstants.statusDanaTalangBatal,
    ]);
    double total = 0;
    for (final row in result) {
      total += (row['nominal'] as num).toDouble() -
          (row['total_dibayar_kembali'] as num).toDouble();
    }
    return total;
  }
}

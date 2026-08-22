import 'package:sqflite/sqflite.dart';
import 'dart:convert';
import '../core/constants/app_constants.dart';
import '../core/payment/transfer_fee_calculator.dart';
import '../models/kasbon_model.dart';
import 'audit_log_repository.dart';
import 'saldo_repository.dart';
import '../core/security/write_guard.dart';

/// Repository kasbon karyawan.
///
/// KONSEP PENTING: Kasbon adalah PIUTANG karyawan, bukan kerugian usaha.
/// - Saat kasbon diambil: cash berkurang, piutang karyawan bertambah.
/// - Saat kasbon dibayar/lunas: cash bertambah, piutang berkurang.
/// - Kasbon TIDAK mengurangi laba bersih periode (lihat PengeluaranRepository
///   yang hanya menjumlahkan kategori 'Pengeluaran Lain').
class KasbonRepository {
  final Database db;

  KasbonRepository(this.db);

  Future<KasbonModel> ambilKasbon({
    required String namaKaryawan,
    required DateTime tanggal,
    required double jumlah,
    String sumber = AppConstants.sumberCash,
    String? jenisTransfer,
    String? keterangan,
  }) async {
    requireWriteAccess();
    return db.transaction<KasbonModel>((txn) async {
      final auditLog = AuditLogRepository(txn);
      final saldoRepo = SaldoRepository(txn);
      final now = DateTime.now();

      final biayaAdmin = sumber == AppConstants.sumberBank
          ? TransferFeeCalculator.hitung(jenisTransfer)
          : 0.0;

      final kasbon = KasbonModel(
        namaKaryawan: namaKaryawan,
        tanggal: tanggal,
        jumlah: jumlah,
        sumber: sumber,
        jenisTransfer: sumber == AppConstants.sumberBank ? jenisTransfer : null,
        biayaAdminTransfer: biayaAdmin,
        status: AppConstants.statusKasbonBelumLunas,
        keterangan: keterangan,
        createdAt: now,
        updatedAt: now,
      );
      final id = await txn.insert('kasbon', kasbon.toMap());
      final saved = KasbonModel.fromMap({...kasbon.toMap(), 'id': id});

      await auditLog.catatCreate('kasbon', id, jsonEncode(saved.toMap()),
          keterangan: 'Kasbon $namaKaryawan ($sumber)');

      // Cash/Bank berkurang (piutang bertambah, dicatat sebagai referensi KASBON)
      if (sumber == AppConstants.sumberBank) {
        await saldoRepo.mutasiBank(
          nominal: jumlah,
          tipe: AppConstants.cashFlowKeluar,
          referensi: AppConstants.cashFlowRefKasbonAmbil,
          referensiId: id,
          keterangan: 'Kasbon $namaKaryawan',
          tanggal: tanggal,
        );
        if (biayaAdmin > 0) {
          await saldoRepo.mutasiBank(
            nominal: biayaAdmin,
            tipe: AppConstants.cashFlowKeluar,
            referensi: AppConstants.cashFlowRefAdminTransfer,
            referensiId: id,
            keterangan: 'Admin transfer - Kasbon $namaKaryawan',
            tanggal: tanggal,
          );
        }
      } else {
        await saldoRepo.mutasiCash(
          nominal: jumlah,
          tipe: AppConstants.cashFlowKeluar,
          referensi: AppConstants.cashFlowRefKasbonAmbil,
          referensiId: id,
          keterangan: 'Kasbon $namaKaryawan',
          tanggal: tanggal,
        );
      }

      return saved;
    });
  }

  Future<KasbonModel> bayarKasbon(int kasbonId, {DateTime? tanggalLunas}) async {
    requireWriteAccess();
    return db.transaction<KasbonModel>((txn) async {
      final auditLog = AuditLogRepository(txn);
      final saldoRepo = SaldoRepository(txn);

      final result =
          await txn.query('kasbon', where: 'id = ?', whereArgs: [kasbonId]);
      if (result.isEmpty) throw ArgumentError('Data kasbon tidak ditemukan');
      final kasbonLama = KasbonModel.fromMap(result.first);

      if (kasbonLama.isLunas) {
        throw StateError('Kasbon ini sudah lunas.');
      }

      final now = DateTime.now();
      final kasbonBaru = kasbonLama.copyWith(
        status: AppConstants.statusKasbonLunas,
        tanggalLunas: tanggalLunas ?? now,
        updatedAt: now,
      );
      await txn.update('kasbon', kasbonBaru.toMap(),
          where: 'id = ?', whereArgs: [kasbonId]);

      await auditLog.catatUpdate(
        'kasbon',
        kasbonId,
        jsonEncode(kasbonLama.toMap()),
        jsonEncode(kasbonBaru.toMap()),
        keterangan: 'Pelunasan kasbon ${kasbonLama.namaKaryawan}',
      );

      // Cash/Bank bertambah kembali (piutang lunas), sesuai sumber
      // dana asal kasbon diambil.
      if (kasbonLama.sumber == AppConstants.sumberBank) {
        await saldoRepo.mutasiBank(
          nominal: kasbonLama.jumlah,
          tipe: AppConstants.cashFlowMasuk,
          referensi: AppConstants.cashFlowRefKasbonBayar,
          referensiId: kasbonId,
          keterangan: 'Pelunasan kasbon ${kasbonLama.namaKaryawan}',
          tanggal: tanggalLunas,
        );
      } else {
        await saldoRepo.mutasiCash(
          nominal: kasbonLama.jumlah,
          tipe: AppConstants.cashFlowMasuk,
          referensi: AppConstants.cashFlowRefKasbonBayar,
          referensiId: kasbonId,
          keterangan: 'Pelunasan kasbon ${kasbonLama.namaKaryawan}',
          tanggal: tanggalLunas,
        );
      }

      return kasbonBaru;
    });
  }

  /// Edit jumlah/keterangan kasbon. Hanya boleh selagi BELUM LUNAS (agar
  /// rollback saldo tetap sederhana & akurat).
  Future<KasbonModel> editKasbon({
    required int kasbonId,
    required String namaKaryawan,
    required DateTime tanggal,
    required double jumlahBaru,
    String? sumber,
    String? jenisTransfer,
    String? keterangan,
  }) async {
    requireWriteAccess();
    return db.transaction<KasbonModel>((txn) async {
      final result =
          await txn.query('kasbon', where: 'id = ?', whereArgs: [kasbonId]);
      if (result.isEmpty) throw ArgumentError('Data kasbon tidak ditemukan');
      final lama = KasbonModel.fromMap(result.first);
      if (lama.isLunas) {
        throw StateError('Kasbon yang sudah lunas tidak bisa diedit.');
      }

      final saldoRepo = SaldoRepository(txn);
      final auditLog = AuditLogRepository(txn);
      final sumberBaru = sumber ?? lama.sumber;

      // Balik efek cash/bank lama sesuai sumber asalnya (termasuk biaya
      // admin transfer lama, jika ada — kasbon lama dianggap batal total).
      if (lama.sumber == AppConstants.sumberBank) {
        await saldoRepo.mutasiBank(
          nominal: lama.jumlah,
          tipe: AppConstants.cashFlowMasuk,
          referensi: AppConstants.cashFlowRefKasbonAmbil,
          referensiId: kasbonId,
          keterangan: 'Koreksi kasbon ${lama.namaKaryawan} (nilai lama dibatalkan)',
        );
        if (lama.biayaAdminTransfer > 0) {
          await saldoRepo.mutasiBank(
            nominal: lama.biayaAdminTransfer,
            tipe: AppConstants.cashFlowMasuk,
            referensi: AppConstants.cashFlowRefAdminTransfer,
            referensiId: kasbonId,
            keterangan: 'Koreksi admin transfer kasbon (nilai lama dibatalkan)',
          );
        }
      } else {
        await saldoRepo.mutasiCash(
          nominal: lama.jumlah,
          tipe: AppConstants.cashFlowMasuk,
          referensi: AppConstants.cashFlowRefKasbonAmbil,
          referensiId: kasbonId,
          keterangan: 'Koreksi kasbon ${lama.namaKaryawan} (nilai lama dibatalkan)',
        );
      }

      final biayaAdminBaru = sumberBaru == AppConstants.sumberBank
          ? TransferFeeCalculator.hitung(jenisTransfer)
          : 0.0;

      final baru = lama.copyWith(
        namaKaryawan: namaKaryawan,
        tanggal: tanggal,
        jumlah: jumlahBaru,
        sumber: sumberBaru,
        jenisTransfer: sumberBaru == AppConstants.sumberBank ? jenisTransfer : null,
        biayaAdminTransfer: biayaAdminBaru,
        keterangan: keterangan,
        updatedAt: DateTime.now(),
      );
      await txn.update('kasbon', baru.toMap(),
          where: 'id = ?', whereArgs: [kasbonId]);
      await auditLog.catatUpdate(
        'kasbon',
        kasbonId,
        jsonEncode(lama.toMap()),
        jsonEncode(baru.toMap()),
        keterangan: 'Edit kasbon $namaKaryawan',
      );

      if (sumberBaru == AppConstants.sumberBank) {
        await saldoRepo.mutasiBank(
          nominal: jumlahBaru,
          tipe: AppConstants.cashFlowKeluar,
          referensi: AppConstants.cashFlowRefKasbonAmbil,
          referensiId: kasbonId,
          keterangan: 'Kasbon $namaKaryawan (setelah edit)',
          tanggal: tanggal,
        );
        if (biayaAdminBaru > 0) {
          await saldoRepo.mutasiBank(
            nominal: biayaAdminBaru,
            tipe: AppConstants.cashFlowKeluar,
            referensi: AppConstants.cashFlowRefAdminTransfer,
            referensiId: kasbonId,
            keterangan: 'Admin transfer - Kasbon $namaKaryawan (setelah edit)',
            tanggal: tanggal,
          );
        }
      } else {
        await saldoRepo.mutasiCash(
          nominal: jumlahBaru,
          tipe: AppConstants.cashFlowKeluar,
          referensi: AppConstants.cashFlowRefKasbonAmbil,
          referensiId: kasbonId,
          keterangan: 'Kasbon $namaKaryawan (setelah edit)',
          tanggal: tanggal,
        );
      }

      return baru;
    });
  }

  /// HAPUS kasbon (Sistem Hapus Transaksi). Jika BELUM LUNAS, cash/bank
  /// dikembalikan sesuai sumber asalnya (piutang batal). Jika sudah
  /// LUNAS, efek bersih sudah nol (ambil -jumlah, bayar +jumlah), jadi
  /// tidak perlu rollback — cukup hapus baris & catat di audit log.
  Future<void> hapusKasbon(int kasbonId) async {
    requireWriteAccess();
    return db.transaction<void>((txn) async {
      final result =
          await txn.query('kasbon', where: 'id = ?', whereArgs: [kasbonId]);
      if (result.isEmpty) return;
      final kasbon = KasbonModel.fromMap(result.first);

      final saldoRepo = SaldoRepository(txn);
      final auditLog = AuditLogRepository(txn);

      if (!kasbon.isLunas) {
        if (kasbon.sumber == AppConstants.sumberBank) {
          await saldoRepo.mutasiBank(
            nominal: kasbon.jumlah,
            tipe: AppConstants.cashFlowMasuk,
            referensi: AppConstants.cashFlowRefKasbonAmbil,
            referensiId: kasbonId,
            keterangan: 'Rollback hapus kasbon ${kasbon.namaKaryawan}',
          );
          if (kasbon.biayaAdminTransfer > 0) {
            await saldoRepo.mutasiBank(
              nominal: kasbon.biayaAdminTransfer,
              tipe: AppConstants.cashFlowMasuk,
              referensi: AppConstants.cashFlowRefAdminTransfer,
              referensiId: kasbonId,
              keterangan: 'Rollback hapus admin transfer kasbon',
            );
          }
        } else {
          await saldoRepo.mutasiCash(
            nominal: kasbon.jumlah,
            tipe: AppConstants.cashFlowMasuk,
            referensi: AppConstants.cashFlowRefKasbonAmbil,
            referensiId: kasbonId,
            keterangan: 'Rollback hapus kasbon ${kasbon.namaKaryawan}',
          );
        }
      }

      await txn.delete('kasbon', where: 'id = ?', whereArgs: [kasbonId]);
      await auditLog.catatDelete(
        'kasbon',
        kasbonId,
        jsonEncode(kasbon.toMap()),
        keterangan: 'Hapus kasbon ${kasbon.namaKaryawan}'
            '${kasbon.isLunas ? "" : " — cash dikembalikan"}',
      );
    });
  }

  Future<List<KasbonModel>> getAll({String? namaKaryawan, String? status}) async {
    final whereClauses = <String>[];
    final whereArgs = <Object?>[];
    if (namaKaryawan != null) {
      whereClauses.add('nama_karyawan = ?');
      whereArgs.add(namaKaryawan);
    }
    if (status != null) {
      whereClauses.add('status = ?');
      whereArgs.add(status);
    }
    final result = await db.query(
      'kasbon',
      where: whereClauses.isEmpty ? null : whereClauses.join(' AND '),
      whereArgs: whereArgs.isEmpty ? null : whereArgs,
      orderBy: 'tanggal DESC',
    );
    return result.map((e) => KasbonModel.fromMap(e)).toList();
  }

  /// Total piutang kasbon yang belum lunas (untuk Dashboard).
  Future<double> getTotalPiutangBelumLunas() async {
    final result = await db.rawQuery('''
      SELECT COALESCE(SUM(jumlah), 0) as total FROM kasbon
      WHERE status = ?
    ''', [AppConstants.statusKasbonBelumLunas]);
    return (result.first['total'] as num).toDouble();
  }

  Future<Map<String, double>> getPiutangPerKaryawan() async {
    final result = await db.rawQuery('''
      SELECT nama_karyawan, COALESCE(SUM(jumlah), 0) as total
      FROM kasbon WHERE status = ?
      GROUP BY nama_karyawan
    ''', [AppConstants.statusKasbonBelumLunas]);

    final map = <String, double>{};
    for (final row in result) {
      map[row['nama_karyawan'] as String] = (row['total'] as num).toDouble();
    }
    return map;
  }
}

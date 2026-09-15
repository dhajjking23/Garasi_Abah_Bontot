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
    return db.transaction<KasbonModel>(
        (txn) => bayarKasbonInTxn(txn, kasbonId, tanggalLunas: tanggalLunas));
  }

  /// V5.9.2 — sama persis dengan [bayarKasbon], TAPI menerima [txn] dari
  /// luar. Dipakai `GajihanRepository.prosesGajihan()` supaya pelunasan
  /// kasbon jadi bagian dari SATU transaction gabungan gaji+kasbon+dana
  /// talang (all-or-nothing), bukan transaction terpisah sendiri-sendiri.
  Future<KasbonModel> bayarKasbonInTxn(
      DatabaseExecutor txn, int kasbonId, {DateTime? tanggalLunas}) async {
    requireWriteAccess();
    final auditLog = AuditLogRepository(txn);
    final saldoRepo = SaldoRepository(txn);

    final result =
        await txn.query('kasbon', where: 'id = ?', whereArgs: [kasbonId]);
    if (result.isEmpty) throw ArgumentError('Data kasbon tidak ditemukan');
    final kasbonLama = KasbonModel.fromMap(result.first);

    if (kasbonLama.isLunas) {
      throw StateError('Kasbon ini sudah lunas.');
    }

    // Lunasi SISA yang belum dibayar (mendukung kasbon yang sudah
    // sebagian dicicil sebelumnya lewat bayarSebagianKasbon()).
    final sisaDilunasi = kasbonLama.sisa;
    final now = DateTime.now();
    final kasbonBaru = kasbonLama.copyWith(
      status: AppConstants.statusKasbonLunas,
      totalDibayar: kasbonLama.jumlah,
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
      keterangan: 'Pelunasan kasbon ${kasbonLama.namaKaryawan}'
          '${kasbonLama.totalDibayar > 0 ? " (sisa setelah cicilan sebelumnya)" : ""}',
    );

    // Cash/Bank bertambah kembali HANYA sebesar sisa yang benar-benar
    // dilunasi sekarang (kalau sudah pernah dicicil, cicilan itu sudah
    // menambah cash/bank duluan di bayarSebagianKasbon() -- kalau di
    // sini dipakai kasbonLama.jumlah penuh lagi, cash akan double count).
    if (sisaDilunasi > 0) {
      if (kasbonLama.sumber == AppConstants.sumberBank) {
        await saldoRepo.mutasiBank(
          nominal: sisaDilunasi,
          tipe: AppConstants.cashFlowMasuk,
          referensi: AppConstants.cashFlowRefKasbonBayar,
          referensiId: kasbonId,
          keterangan: 'Pelunasan kasbon ${kasbonLama.namaKaryawan}',
          tanggal: tanggalLunas,
        );
      } else {
        await saldoRepo.mutasiCash(
          nominal: sisaDilunasi,
          tipe: AppConstants.cashFlowMasuk,
          referensi: AppConstants.cashFlowRefKasbonBayar,
          referensiId: kasbonId,
          keterangan: 'Pelunasan kasbon ${kasbonLama.namaKaryawan}',
          tanggal: tanggalLunas,
        );
      }
    }

    return kasbonBaru;
  }

  /// V5.9.2 — PARTIAL REPAYMENT (cicilan). Mendukung pelunasan bertahap,
  /// mengikuti pola yang sama dengan `DanaTalangRepository.bayarKembali()`.
  /// Cash/Bank BENAR-BENAR bertambah sejumlah [nominal] (piutang
  /// perusahaan ke karyawan berkurang), sesuai `sumber` ASLI kasbon
  /// diambil (konsisten dengan bayarKasbon()).
  Future<KasbonModel> bayarSebagianKasbon({
    required int kasbonId,
    required double nominal,
    DateTime? tanggal,
  }) async {
    requireWriteAccess();
    return db.transaction<KasbonModel>((txn) async {
      final result =
          await txn.query('kasbon', where: 'id = ?', whereArgs: [kasbonId]);
      if (result.isEmpty) throw ArgumentError('Data kasbon tidak ditemukan');
      final kasbon = KasbonModel.fromMap(result.first);

      if (!kasbon.isAktif) {
        throw StateError('Kasbon ini sudah lunas.');
      }
      if (nominal <= 0) {
        throw ArgumentError('Nominal pembayaran harus lebih dari 0');
      }
      if (nominal > kasbon.sisa + 0.5) {
        throw ArgumentError(
            'Nominal pembayaran (Rp${nominal.toStringAsFixed(0)}) melebihi sisa (Rp${kasbon.sisa.toStringAsFixed(0)})');
      }

      final now = DateTime.now();
      final totalDibayarBaru = kasbon.totalDibayar + nominal;
      final lunasPenuh = (kasbon.jumlah - totalDibayarBaru) <= 0.5;
      final kasbonBaru = kasbon.copyWith(
        totalDibayar: totalDibayarBaru,
        status: lunasPenuh
            ? AppConstants.statusKasbonLunas
            : AppConstants.statusKasbonSebagianLunas,
        tanggalLunas: lunasPenuh ? (tanggal ?? now) : null,
        updatedAt: now,
      );
      await txn.update('kasbon', kasbonBaru.toMap(),
          where: 'id = ?', whereArgs: [kasbonId]);

      final auditLog = AuditLogRepository(txn);
      await auditLog.catatUpdate(
        'kasbon',
        kasbonId,
        jsonEncode(kasbon.toMap()),
        jsonEncode(kasbonBaru.toMap()),
        keterangan:
            'Cicilan kasbon ${kasbon.namaKaryawan} Rp${nominal.toStringAsFixed(0)}',
      );

      final saldoRepo = SaldoRepository(txn);
      if (kasbon.sumber == AppConstants.sumberBank) {
        await saldoRepo.mutasiBank(
          nominal: nominal,
          tipe: AppConstants.cashFlowMasuk,
          referensi: AppConstants.cashFlowRefKasbonBayar,
          referensiId: kasbonId,
          keterangan: 'Cicilan kasbon ${kasbon.namaKaryawan}',
          tanggal: tanggal,
        );
      } else {
        await saldoRepo.mutasiCash(
          nominal: nominal,
          tipe: AppConstants.cashFlowMasuk,
          referensi: AppConstants.cashFlowRefKasbonBayar,
          referensiId: kasbonId,
          keterangan: 'Cicilan kasbon ${kasbon.namaKaryawan}',
          tanggal: tanggal,
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
      if (lama.totalDibayar > 0) {
        throw StateError(
            'Kasbon yang sudah ada cicilan tidak bisa diedit nominalnya. Hapus saja transaksinya (akan rollback otomatis).');
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
        // V5.9.2 — reverse HANYA sisa outstanding, bukan jumlah penuh:
        // kalau sudah ada cicilan (total_dibayar > 0), sebagian cash
        // SUDAH kembali lewat bayarSebagianKasbon(). Reverse jumlah
        // penuh di sini akan double-count bagian yang sudah dicicil.
        final sisaBelumKembali = kasbon.sisa;
        if (kasbon.sumber == AppConstants.sumberBank) {
          if (sisaBelumKembali > 0) {
            await saldoRepo.mutasiBank(
              nominal: sisaBelumKembali,
              tipe: AppConstants.cashFlowMasuk,
              referensi: AppConstants.cashFlowRefKasbonAmbil,
              referensiId: kasbonId,
              keterangan: 'Rollback hapus kasbon ${kasbon.namaKaryawan}',
            );
          }
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
          if (sisaBelumKembali > 0) {
            await saldoRepo.mutasiCash(
              nominal: sisaBelumKembali,
              tipe: AppConstants.cashFlowMasuk,
              referensi: AppConstants.cashFlowRefKasbonAmbil,
              referensiId: kasbonId,
              keterangan: 'Rollback hapus kasbon ${kasbon.namaKaryawan}',
            );
          }
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

  /// V5.9.4 — [includeArchived] default false: kasbon yang sudah
  /// diarsipkan (lunas & periode baru sudah dibuka, lihat
  /// `PeriodeRepository.buatPeriodeCarryForward`) TIDAK ikut tampil di
  /// daftar aktif secara default, supaya daftar tidak menumpuk. Data
  /// TETAP ada di database — set true untuk melihat semuanya termasuk
  /// arsip (mis. untuk layar riwayat/audit).
  Future<List<KasbonModel>> getAll({
    String? namaKaryawan,
    String? status,
    bool includeArchived = false,
  }) async {
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
    if (!includeArchived) {
      whereClauses.add('is_archived = 0');
    }
    final result = await db.query(
      'kasbon',
      where: whereClauses.isEmpty ? null : whereClauses.join(' AND '),
      whereArgs: whereArgs.isEmpty ? null : whereArgs,
      orderBy: 'tanggal DESC',
    );
    return result.map((e) => KasbonModel.fromMap(e)).toList();
  }

  /// Total piutang kasbon yang belum lunas (untuk Dashboard). V5.9.2:
  /// dikurangi total_dibayar (cicilan), dan menyertakan status
  /// SEBAGIAN_LUNAS (bukan cuma BELUM_LUNAS) — kalau tidak, kasbon yang
  /// sedang dicicil akan "hilang" dari total piutang meski masih ada
  /// sisa outstanding.
  Future<double> getTotalPiutangBelumLunas() async {
    final result = await db.rawQuery('''
      SELECT jumlah, total_dibayar FROM kasbon
      WHERE status IN (?, ?)
    ''', [
      AppConstants.statusKasbonBelumLunas,
      AppConstants.statusKasbonSebagianLunas,
    ]);
    double total = 0;
    for (final row in result) {
      total += (row['jumlah'] as num).toDouble() -
          ((row['total_dibayar'] as num?)?.toDouble() ?? 0);
    }
    return total;
  }

  Future<Map<String, double>> getPiutangPerKaryawan() async {
    final result = await db.rawQuery('''
      SELECT nama_karyawan, jumlah, total_dibayar
      FROM kasbon WHERE status IN (?, ?)
    ''', [
      AppConstants.statusKasbonBelumLunas,
      AppConstants.statusKasbonSebagianLunas,
    ]);

    final map = <String, double>{};
    for (final row in result) {
      final nama = row['nama_karyawan'] as String;
      final sisa = (row['jumlah'] as num).toDouble() -
          ((row['total_dibayar'] as num?)?.toDouble() ?? 0);
      map[nama] = (map[nama] ?? 0) + sisa;
    }
    return map;
  }
}

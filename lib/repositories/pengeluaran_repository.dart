import 'package:sqflite/sqflite.dart';
import 'dart:convert';
import '../core/constants/app_constants.dart';
import '../core/payment/transfer_fee_calculator.dart';
import '../models/pengeluaran_model.dart';
import 'audit_log_repository.dart';
import 'saldo_repository.dart';
import '../core/security/write_guard.dart';

/// Repository pengeluaran umum (BUKAN untuk kasbon — kasbon punya
/// repository & logika piutang tersendiri di KasbonRepository, karena
/// kasbon bukan kerugian melainkan piutang karyawan).
///
/// Pengeluaran via TRANSFER bisa dikenai Biaya Administrasi Bank
/// (Gratis/BI FAST Rp2.500/Realtime Rp6.500). Biaya admin dicatat
/// TERPISAH dari nominal barang/jasa di cash_flow (referensi
/// ADMINISTRASI_BANK) supaya laporan "Pengeluaran per Kategori" tidak
/// mencampur nilai barang dengan biaya bank.
class PengeluaranRepository {
  final Database db;

  PengeluaranRepository(this.db);

  /// Delegasi ke kalkulator global (V4.2.1) — dipertahankan sebagai
  /// method di sini untuk kompatibilitas kode/UI lama yang sudah
  /// memanggil `pengeluaranRepo.hitungBiayaAdmin(...)`.
  double hitungBiayaAdmin(String? jenisTransfer) =>
      TransferFeeCalculator.hitung(jenisTransfer);

  Future<PengeluaranModel> tambahPengeluaran({
    required DateTime tanggal,
    required String kategori,
    required double nominal,
    String? keterangan,
    String sumber = AppConstants.sumberCash,
    String? jenisTransfer,
    int? periodeId,
    int? referensiId,
  }) async {
    requireWriteAccess();
    return db.transaction<PengeluaranModel>((txn) async {
      final auditLog = AuditLogRepository(txn);
      final saldoRepo = SaldoRepository(txn);
      final now = DateTime.now();

      final biayaAdmin =
          sumber == AppConstants.sumberBank ? hitungBiayaAdmin(jenisTransfer) : 0.0;

      final pengeluaran = PengeluaranModel(
        tanggal: tanggal,
        kategori: kategori,
        nominal: nominal,
        keterangan: keterangan,
        sumber: sumber,
        jenisTransfer: sumber == AppConstants.sumberBank ? jenisTransfer : null,
        biayaAdmin: biayaAdmin,
        referensiId: referensiId,
        periodeId: periodeId,
        createdAt: now,
      );
      final id = await txn.insert('pengeluaran', pengeluaran.toMap());
      final saved =
          PengeluaranModel.fromMap({...pengeluaran.toMap(), 'id': id});

      await auditLog.catatCreate(
          'pengeluaran', id, jsonEncode(saved.toMap()));

      if (sumber == AppConstants.sumberBank) {
        await saldoRepo.mutasiBank(
          nominal: nominal,
          tipe: AppConstants.cashFlowKeluar,
          referensi: AppConstants.cashFlowRefPengeluaran,
          referensiId: id,
          keterangan: keterangan ?? kategori,
          tanggal: tanggal,
        );
        if (biayaAdmin > 0) {
          await saldoRepo.mutasiBank(
            nominal: biayaAdmin,
            tipe: AppConstants.cashFlowKeluar,
            referensi: AppConstants.cashFlowRefAdminTransfer,
            referensiId: id,
            keterangan: 'Admin transfer - $kategori',
            tanggal: tanggal,
          );
        }
      } else {
        await saldoRepo.mutasiCash(
          nominal: nominal,
          tipe: AppConstants.cashFlowKeluar,
          referensi: AppConstants.cashFlowRefPengeluaran,
          referensiId: id,
          keterangan: keterangan ?? kategori,
          tanggal: tanggal,
        );
      }

      return saved;
    });
  }

  /// Edit pengeluaran (nominal/kategori/sumber/jenis transfer). Efek
  /// kas lama (nominal + admin) dibalik dulu, lalu efek baru diterapkan.
  Future<PengeluaranModel> editPengeluaran({
    required int id,
    required DateTime tanggal,
    required String kategori,
    required double nominal,
    String? keterangan,
    String sumber = AppConstants.sumberCash,
    String? jenisTransfer,
  }) async {
    requireWriteAccess();
    return db.transaction<PengeluaranModel>((txn) async {
      final result =
          await txn.query('pengeluaran', where: 'id = ?', whereArgs: [id]);
      if (result.isEmpty) throw ArgumentError('Pengeluaran tidak ditemukan');
      final lama = PengeluaranModel.fromMap(result.first);

      final saldoRepo = SaldoRepository(txn);
      final auditLog = AuditLogRepository(txn);

      // Balik efek kas lama
      if (lama.sumber == AppConstants.sumberBank) {
        await saldoRepo.mutasiBank(
          nominal: lama.nominal,
          tipe: AppConstants.cashFlowMasuk,
          referensi: AppConstants.cashFlowRefPengeluaran,
          referensiId: id,
          keterangan: 'Koreksi pengeluaran (nilai lama dibatalkan)',
        );
        if (lama.biayaAdmin > 0) {
          await saldoRepo.mutasiBank(
            nominal: lama.biayaAdmin,
            tipe: AppConstants.cashFlowMasuk,
            referensi: AppConstants.cashFlowRefAdminTransfer,
            referensiId: id,
            keterangan: 'Koreksi admin transfer (nilai lama dibatalkan)',
          );
        }
      } else {
        await saldoRepo.mutasiCash(
          nominal: lama.nominal,
          tipe: AppConstants.cashFlowMasuk,
          referensi: AppConstants.cashFlowRefPengeluaran,
          referensiId: id,
          keterangan: 'Koreksi pengeluaran (nilai lama dibatalkan)',
        );
      }

      final biayaAdminBaru =
          sumber == AppConstants.sumberBank ? hitungBiayaAdmin(jenisTransfer) : 0.0;

      final baru = PengeluaranModel(
        id: id,
        tanggal: tanggal,
        kategori: kategori,
        nominal: nominal,
        keterangan: keterangan,
        sumber: sumber,
        jenisTransfer: sumber == AppConstants.sumberBank ? jenisTransfer : null,
        biayaAdmin: biayaAdminBaru,
        referensiId: lama.referensiId,
        periodeId: lama.periodeId,
        createdAt: lama.createdAt,
        updatedAt: DateTime.now(),
      );
      await txn.update('pengeluaran', baru.toMap(),
          where: 'id = ?', whereArgs: [id]);
      await auditLog.catatUpdate(
        'pengeluaran',
        id,
        jsonEncode(lama.toMap()),
        jsonEncode(baru.toMap()),
        keterangan: tanggal != lama.tanggal
            ? 'Edit pengeluaran $kategori — tanggal diubah dari '
                '${lama.tanggal.toIso8601String().split("T").first} menjadi '
                '${tanggal.toIso8601String().split("T").first}'
            : 'Edit pengeluaran $kategori',
      );

      if (sumber == AppConstants.sumberBank) {
        await saldoRepo.mutasiBank(
          nominal: nominal,
          tipe: AppConstants.cashFlowKeluar,
          referensi: AppConstants.cashFlowRefPengeluaran,
          referensiId: id,
          keterangan: keterangan ?? kategori,
          tanggal: tanggal,
        );
        if (biayaAdminBaru > 0) {
          await saldoRepo.mutasiBank(
            nominal: biayaAdminBaru,
            tipe: AppConstants.cashFlowKeluar,
            referensi: AppConstants.cashFlowRefAdminTransfer,
            referensiId: id,
            keterangan: 'Admin transfer - $kategori',
            tanggal: tanggal,
          );
        }
      } else {
        await saldoRepo.mutasiCash(
          nominal: nominal,
          tipe: AppConstants.cashFlowKeluar,
          referensi: AppConstants.cashFlowRefPengeluaran,
          referensiId: id,
          keterangan: keterangan ?? kategori,
          tanggal: tanggal,
        );
      }

      return baru;
    });
  }

  /// HAPUS pengeluaran (Sistem Hapus Transaksi). Cash/Bank dikembalikan
  /// termasuk biaya admin bila ada.
  Future<void> hapusPengeluaran(int id) async {
    requireWriteAccess();
    return db.transaction<void>((txn) async {
      final result =
          await txn.query('pengeluaran', where: 'id = ?', whereArgs: [id]);
      if (result.isEmpty) return;
      final pengeluaran = PengeluaranModel.fromMap(result.first);

      final saldoRepo = SaldoRepository(txn);
      final auditLog = AuditLogRepository(txn);

      if (pengeluaran.sumber == AppConstants.sumberBank) {
        await saldoRepo.mutasiBank(
          nominal: pengeluaran.nominal,
          tipe: AppConstants.cashFlowMasuk,
          referensi: AppConstants.cashFlowRefPengeluaran,
          referensiId: id,
          keterangan: 'Rollback hapus pengeluaran ${pengeluaran.kategori}',
        );
        if (pengeluaran.biayaAdmin > 0) {
          await saldoRepo.mutasiBank(
            nominal: pengeluaran.biayaAdmin,
            tipe: AppConstants.cashFlowMasuk,
            referensi: AppConstants.cashFlowRefAdminTransfer,
            referensiId: id,
            keterangan: 'Rollback hapus admin transfer',
          );
        }
      } else {
        await saldoRepo.mutasiCash(
          nominal: pengeluaran.nominal,
          tipe: AppConstants.cashFlowMasuk,
          referensi: AppConstants.cashFlowRefPengeluaran,
          referensiId: id,
          keterangan: 'Rollback hapus pengeluaran ${pengeluaran.kategori}',
        );
      }

      await txn.delete('pengeluaran', where: 'id = ?', whereArgs: [id]);
      await auditLog.catatDelete(
        'pengeluaran',
        id,
        jsonEncode(pengeluaran.toMap()),
        keterangan:
            'Hapus pengeluaran ${pengeluaran.kategori} — saldo dikembalikan',
      );
    });
  }

  Future<List<PengeluaranModel>> getAll(
      {int? periodeId, String? kategori}) async {
    final whereClauses = <String>[];
    final whereArgs = <Object?>[];
    if (periodeId != null) {
      whereClauses.add('periode_id = ?');
      whereArgs.add(periodeId);
    }
    if (kategori != null) {
      whereClauses.add('kategori = ?');
      whereArgs.add(kategori);
    }
    final result = await db.query(
      'pengeluaran',
      where: whereClauses.isEmpty ? null : whereClauses.join(' AND '),
      whereArgs: whereArgs.isEmpty ? null : whereArgs,
      orderBy: 'tanggal DESC',
    );
    return result.map((e) => PengeluaranModel.fromMap(e)).toList();
  }

  /// Total pengeluaran "Pengeluaran Lain" saja (dipakai untuk hitung laba
  /// bersih periode — Kasbon TIDAK mengurangi laba karena itu piutang).
  Future<double> getTotalPengeluaranLain({int? periodeId}) async {
    final result = await db.rawQuery('''
      SELECT COALESCE(SUM(nominal), 0) as total FROM pengeluaran
      WHERE kategori = 'Pengeluaran Lain'
      ${periodeId != null ? "AND periode_id = ?" : ""}
    ''', periodeId != null ? [periodeId] : []);
    return (result.first['total'] as num).toDouble();
  }

  /// Total biaya Administrasi Bank dalam suatu periode (dipisah dari
  /// pengeluaran barang/jasa sesuai spesifikasi poin #9).
  Future<double> getTotalAdministrasiBank({int? periodeId}) async {
    final result = await db.rawQuery('''
      SELECT COALESCE(SUM(biaya_admin), 0) as total FROM pengeluaran
      WHERE biaya_admin > 0
      ${periodeId != null ? "AND periode_id = ?" : ""}
    ''', periodeId != null ? [periodeId] : []);
    return (result.first['total'] as num).toDouble();
  }
}

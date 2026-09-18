import 'package:sqflite/sqflite.dart';
import 'dart:convert';
import '../models/biaya_transfer_manual_model.dart';
import 'audit_log_repository.dart';
import '../core/security/write_guard.dart';

/// Repository untuk menu "Biaya Transfer" (V3.1 Patch #4).
///
/// Biaya transfer manual TIDAK memotong Cash/Saldo Bank (murni catatan
/// biaya untuk keperluan laporan), berbeda dari biaya_admin otomatis di
/// tabel pengeluaran yang memang memotong uang keluar transaksi. Kedua
/// sumber ini digabung saat menghitung Total Biaya Transfer Periode
/// (lihat DashboardService / LaporanService).
class BiayaTransferManualRepository {
  final Database db;

  BiayaTransferManualRepository(this.db);

  Future<BiayaTransferManualModel> tambah({
    required DateTime tanggal,
    required String namaTujuan,
    String? keterangan,
    required double nominal,
    int? periodeId,
  }) async {
    requireWriteAccess();
    return db.transaction<BiayaTransferManualModel>((txn) async {
      final now = DateTime.now();
      final model = BiayaTransferManualModel(
        tanggal: tanggal,
        namaTujuan: namaTujuan,
        keterangan: keterangan,
        nominal: nominal,
        periodeId: periodeId,
        createdAt: now,
        updatedAt: now,
      );
      final id = await txn.insert('biaya_transfer_manual', model.toMap());
      final saved =
          BiayaTransferManualModel.fromMap({...model.toMap(), 'id': id});

      final auditLog = AuditLogRepository(txn);
      await auditLog.catatCreate(
        'biaya_transfer_manual',
        id,
        jsonEncode(saved.toMap()),
        keterangan: 'Biaya transfer manual ke $namaTujuan',
      );

      return saved;
    });
  }

  Future<BiayaTransferManualModel> edit({
    required int id,
    required DateTime tanggal,
    required String namaTujuan,
    String? keterangan,
    required double nominal,
  }) async {
    requireWriteAccess();
    return db.transaction<BiayaTransferManualModel>((txn) async {
      final result = await txn.query('biaya_transfer_manual',
          where: 'id = ?', whereArgs: [id]);
      if (result.isEmpty) {
        throw ArgumentError('Biaya transfer tidak ditemukan');
      }
      final lama = BiayaTransferManualModel.fromMap(result.first);

      final baru = lama.copyWith(
        tanggal: tanggal,
        namaTujuan: namaTujuan,
        keterangan: keterangan,
        nominal: nominal,
        updatedAt: DateTime.now(),
      );
      await txn.update('biaya_transfer_manual', baru.toMap(),
          where: 'id = ?', whereArgs: [id]);

      final auditLog = AuditLogRepository(txn);
      await auditLog.catatUpdate(
        'biaya_transfer_manual',
        id,
        jsonEncode(lama.toMap()),
        jsonEncode(baru.toMap()),
        keterangan: 'Edit biaya transfer manual ke $namaTujuan',
      );

      return baru;
    });
  }

  Future<void> hapus(int id) async {
    requireWriteAccess();
    return db.transaction<void>((txn) async {
      final result = await txn.query('biaya_transfer_manual',
          where: 'id = ?', whereArgs: [id]);
      if (result.isEmpty) return;
      final model = BiayaTransferManualModel.fromMap(result.first);

      await txn.delete('biaya_transfer_manual', where: 'id = ?', whereArgs: [id]);

      final auditLog = AuditLogRepository(txn);
      await auditLog.catatDelete(
        'biaya_transfer_manual',
        id,
        jsonEncode(model.toMap()),
        keterangan: 'Hapus biaya transfer manual ke ${model.namaTujuan}',
      );
    });
  }

  Future<List<BiayaTransferManualModel>> getAll({int? periodeId}) async {
    final result = await db.query(
      'biaya_transfer_manual',
      where: periodeId != null ? 'periode_id = ?' : null,
      whereArgs: periodeId != null ? [periodeId] : null,
      orderBy: 'tanggal DESC, id DESC',
    );
    return result.map((e) => BiayaTransferManualModel.fromMap(e)).toList();
  }

  /// Total biaya transfer manual, opsional dibatasi periode.
  Future<double> getTotal({int? periodeId}) async {
    final result = await db.rawQuery(
      'SELECT COALESCE(SUM(nominal), 0) as total FROM biaya_transfer_manual'
      '${periodeId != null ? " WHERE periode_id = ?" : ""}',
      periodeId != null ? [periodeId] : [],
    );
    return (result.first['total'] as num).toDouble();
  }
}

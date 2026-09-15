import 'package:sqflite/sqflite.dart';
import '../core/constants/app_constants.dart';
import '../models/audit_log_model.dart';
import '../core/security/write_guard.dart';

/// Repository untuk audit_log. Setiap repository transaksi (motor,
/// penjualan, pemasukan, dll) wajib memanggil `catat()` setiap kali
/// melakukan create/update/delete agar histori perubahan bisa dilacak.
class AuditLogRepository {
  final DatabaseExecutor db;

  AuditLogRepository(this.db);

  Future<void> catat({
    required String tabel,
    int? recordId,
    required String aksi,
    String? dataLama,
    String? dataBaru,
    String? keterangan,
  }) async {
    requireWriteAccess();
    final log = AuditLogModel(
      tabel: tabel,
      recordId: recordId,
      aksi: aksi,
      dataLama: dataLama,
      dataBaru: dataBaru,
      keterangan: keterangan,
      createdAt: DateTime.now(),
    );
    await db.insert('audit_log', log.toMap());
  }

  Future<void> catatCreate(String tabel, int recordId, String dataBaru,
      {String? keterangan}) {
    return catat(
      tabel: tabel,
      recordId: recordId,
      aksi: AppConstants.auditCreate,
      dataBaru: dataBaru,
      keterangan: keterangan,
    );
  }

  Future<void> catatUpdate(
      String tabel, int recordId, String dataLama, String dataBaru,
      {String? keterangan}) {
    return catat(
      tabel: tabel,
      recordId: recordId,
      aksi: AppConstants.auditUpdate,
      dataLama: dataLama,
      dataBaru: dataBaru,
      keterangan: keterangan,
    );
  }

  Future<void> catatDelete(String tabel, int recordId, String dataLama,
      {String? keterangan}) {
    return catat(
      tabel: tabel,
      recordId: recordId,
      aksi: AppConstants.auditDelete,
      dataLama: dataLama,
      keterangan: keterangan,
    );
  }

  Future<List<AuditLogModel>> getAll({String? tabel, int limit = 200}) async {
    final result = await db.query(
      'audit_log',
      where: tabel != null ? 'tabel = ?' : null,
      whereArgs: tabel != null ? [tabel] : null,
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return result.map((e) => AuditLogModel.fromMap(e)).toList();
  }
}

import 'package:sqflite/sqflite.dart';
import '../models/closing_snapshot_model.dart';

/// V5.9 — CRUD murni untuk closing_snapshot. TIDAK ADA logika lock/guard
/// apa pun di sini — hanya simpan & baca "foto" hasil kalkulasi. Insert-
/// only by design (tidak ada update/delete) karena setiap closing/
/// rekalkulasi adalah REVISI baru (closing_number berikutnya), bukan
/// menimpa yang lama — supaya histori closing tetap utuh dan bisa
/// dibandingkan (persis seperti contoh "Closing #001, #002, #003" di
/// spesifikasi).
class ClosingSnapshotRepository {
  final Database db;
  ClosingSnapshotRepository(this.db);

  Future<ClosingSnapshotModel> simpan(ClosingSnapshotModel snapshot) async {
    final id = await db.insert('closing_snapshot', snapshot.toMap());
    return ClosingSnapshotModel.fromMap({...snapshot.toMap(), 'id': id});
  }

  Future<List<ClosingSnapshotModel>> getRiwayat({int? periodeId}) async {
    final rows = await db.query(
      'closing_snapshot',
      where: periodeId != null ? 'periode_id = ?' : null,
      whereArgs: periodeId != null ? [periodeId] : null,
      orderBy: 'created_at DESC',
    );
    return rows.map(ClosingSnapshotModel.fromMap).toList();
  }

  /// Closing terakhir untuk suatu periode (null kalau belum pernah closing).
  Future<ClosingSnapshotModel?> getTerakhir(int periodeId) async {
    final rows = await db.query(
      'closing_snapshot',
      where: 'periode_id = ?',
      whereArgs: [periodeId],
      orderBy: 'closing_number DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : ClosingSnapshotModel.fromMap(rows.first);
  }

  /// Nomor closing berikutnya untuk periode ini (1 kalau belum pernah).
  Future<int> getNomorBerikutnya(int periodeId) async {
    final terakhir = await getTerakhir(periodeId);
    return (terakhir?.closingNumber ?? 0) + 1;
  }
}

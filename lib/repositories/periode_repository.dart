import 'package:sqflite/sqflite.dart';
import 'dart:convert';
import '../core/constants/app_constants.dart';
import '../models/periode_model.dart';
import 'audit_log_repository.dart';
import 'saldo_repository.dart';
import '../core/security/write_guard.dart';

class PeriodeRepository {
  final Database db;
  late final AuditLogRepository _auditLog;

  PeriodeRepository(this.db) {
    _auditLog = AuditLogRepository(db);
  }

  /// Membuat periode baru. [modalAwalCash] & [modalAwalBank] adalah
  /// modal awal pembukuan (BUKAN cashflow — nilai ini disimpan sebagai
  /// snapshot immutable di kolom periode.modal_awal_cash/bank untuk
  /// dasar perhitungan "Laba berdasarkan perubahan modal", dan TIDAK
  /// akan berubah walau ada transaksi selama periode berjalan).
  ///
  /// Modal yang diinput di sini JUGA otomatis menyuntik saldo Cash &
  /// Saldo Bank operasional sebesar nominal yang sama (karena modal
  /// awal secara fisik berarti ada uang cash/saldo bank sejumlah itu di
  /// tangan saat periode dimulai) — inilah perbaikan dari bug lama di
  /// mana Modal sudah diisi tapi Cash/Saldo tetap tampil 0.
  Future<PeriodeModel> buatPeriode({
    required String namaPeriode,
    required DateTime tanggalMulai,
    double modalAwalCash = 0,
    double modalAwalBank = 0,
  }) async {
    requireWriteAccess();
    final aktif = await getPeriodeAktif();
    if (aktif != null) {
      throw StateError(
        'Masih ada periode aktif ("${aktif.namaPeriode}"). '
        'Tutup buku periode tersebut terlebih dahulu sebelum membuat periode baru.',
      );
    }

    return db.transaction<PeriodeModel>((txn) async {
      final now = DateTime.now();
      final periode = PeriodeModel(
        namaPeriode: namaPeriode,
        tanggalMulai: tanggalMulai,
        status: AppConstants.statusPeriodeAktif,
        modalAwalCash: modalAwalCash,
        modalAwalBank: modalAwalBank,
        createdAt: now,
        updatedAt: now,
      );
      final id = await txn.insert('periode', periode.toMap());
      final saved = periode.copyWith(id: id);
      final auditLog = AuditLogRepository(txn);
      await auditLog.catatCreate('periode', id, jsonEncode(saved.toMap()));

      if (modalAwalCash > 0 || modalAwalBank > 0) {
        final saldoRepo = SaldoRepository(txn);
        await saldoRepo.suntikModalAwalPeriode(
          cash: modalAwalCash,
          bank: modalAwalBank,
          keterangan: 'Modal awal periode "$namaPeriode"',
        );
      }

      return saved;
    });
  }

  Future<PeriodeModel?> getPeriodeAktif() async {
    final result = await db.query(
      'periode',
      where: 'status = ?',
      whereArgs: [AppConstants.statusPeriodeAktif],
      limit: 1,
    );
    if (result.isEmpty) return null;
    return PeriodeModel.fromMap(result.first);
  }

  Future<PeriodeModel?> getById(int id) async {
    final result = await db.query('periode', where: 'id = ?', whereArgs: [id]);
    if (result.isEmpty) return null;
    return PeriodeModel.fromMap(result.first);
  }

  Future<List<PeriodeModel>> getAll() async {
    final result = await db.query('periode', orderBy: 'tanggal_mulai DESC');
    return result.map((e) => PeriodeModel.fromMap(e)).toList();
  }

  /// Menutup buku periode. Tidak menghitung laba di sini — perhitungan
  /// & pembagian laba dilakukan oleh PembagianLabaService lalu hasilnya
  /// disimpan terpisah di tabel pembagian_laba.
  Future<PeriodeModel> tutupPeriode(int periodeId, {DateTime? tanggalSelesai}) async {
    requireWriteAccess();
    final periode = await getById(periodeId);
    if (periode == null) throw ArgumentError('Periode tidak ditemukan');
    if (!periode.isAktif) {
      throw StateError('Periode ini sudah ditutup sebelumnya.');
    }

    final dataLama = jsonEncode(periode.toMap());
    final updated = periode.copyWith(
      status: AppConstants.statusPeriodeTutup,
      tanggalSelesai: tanggalSelesai ?? DateTime.now(),
      updatedAt: DateTime.now(),
    );
    await db.update('periode', updated.toMap(),
        where: 'id = ?', whereArgs: [periodeId]);
    await _auditLog.catatUpdate(
      'periode',
      periodeId,
      dataLama,
      jsonEncode(updated.toMap()),
      keterangan: 'Tutup buku periode',
    );
    return updated;
  }

  /// Membuka kembali periode yang sudah ditutup (koreksi transaksi,
  /// dsb). Hanya boleh jika TIDAK ada periode lain yang sedang aktif —
  /// aturan "satu periode aktif" tetap dijaga.
  Future<PeriodeModel> bukaPeriode(int periodeId) async {
    requireWriteAccess();
    final periode = await getById(periodeId);
    if (periode == null) throw ArgumentError('Periode tidak ditemukan');
    if (periode.isAktif) {
      throw StateError('Periode ini sudah aktif.');
    }
    final aktifSekarang = await getPeriodeAktif();
    if (aktifSekarang != null) {
      throw StateError(
        'Tidak bisa membuka periode ini karena periode "${aktifSekarang.namaPeriode}" '
        'sedang aktif. Tutup buku periode tersebut terlebih dahulu.',
      );
    }

    final dataLama = jsonEncode(periode.toMap());
    final updated = PeriodeModel(
      id: periode.id,
      namaPeriode: periode.namaPeriode,
      tanggalMulai: periode.tanggalMulai,
      tanggalSelesai: null,
      status: AppConstants.statusPeriodeAktif,
      modalAwalCash: periode.modalAwalCash,
      modalAwalBank: periode.modalAwalBank,
      createdAt: periode.createdAt,
      updatedAt: DateTime.now(),
    );
    await db.update('periode', updated.toMap(),
        where: 'id = ?', whereArgs: [periodeId]);
    await _auditLog.catatUpdate(
      'periode',
      periodeId,
      dataLama,
      jsonEncode(updated.toMap()),
      keterangan: 'Buka kembali periode untuk koreksi',
    );
    return updated;
  }
}

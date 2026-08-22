import 'package:sqflite/sqflite.dart';
import 'dart:convert';
import '../core/constants/app_constants.dart';
import '../models/pemasukan_model.dart';
import 'audit_log_repository.dart';
import 'saldo_repository.dart';
import '../core/security/write_guard.dart';

/// Repository pemasukan manual (di luar penjualan motor otomatis).
/// Kategori 'Tambah Modal' juga menambah modal_cash di tabel saldo
/// (lihat SaldoRepository.tambahModal) — SELALU dianggap CASH karena
/// modal yang disetor dicatat sebagai kas fisik yang masuk usaha.
class PemasukanRepository {
  final Database db;

  static const String kategoriTambahModal = 'Tambah Modal';

  PemasukanRepository(this.db);

  Future<PemasukanModel> tambahPemasukan({
    required DateTime tanggal,
    required String kategori,
    required double nominal,
    String? keterangan,
    String sumber = AppConstants.sumberCash,
    double cashMasuk = 0,
    double bankMasuk = 0,
    int? periodeId,
  }) async {
    requireWriteAccess();
    return db.transaction<PemasukanModel>((txn) async {
      final auditLog = AuditLogRepository(txn);
      final saldoRepo = SaldoRepository(txn);
      final now = DateTime.now();
      final isTambahModal = kategori == kategoriTambahModal;
      final sumberFinal = isTambahModal ? AppConstants.sumberCash : sumber;

      double cash;
      double bank;
      if (isTambahModal) {
        cash = nominal;
        bank = 0;
      } else {
        switch (sumberFinal) {
          case AppConstants.sumberBank:
            cash = 0;
            bank = nominal;
            break;
          case AppConstants.sumberCampuran:
            if ((cashMasuk + bankMasuk - nominal).abs() > 0.5) {
              throw ArgumentError(
                  'Cash + Bank (Rp${(cashMasuk + bankMasuk).toStringAsFixed(0)}) harus sama dengan nominal (Rp${nominal.toStringAsFixed(0)})');
            }
            cash = cashMasuk;
            bank = bankMasuk;
            break;
          case AppConstants.sumberCash:
          default:
            cash = nominal;
            bank = 0;
        }
      }

      final pemasukan = PemasukanModel(
        tanggal: tanggal,
        kategori: kategori,
        nominal: nominal,
        keterangan: keterangan,
        sumber: sumberFinal,
        cashMasuk: cash,
        bankMasuk: bank,
        periodeId: periodeId,
        createdAt: now,
      );
      final id = await txn.insert('pemasukan', pemasukan.toMap());
      final saved = PemasukanModel.fromMap({...pemasukan.toMap(), 'id': id});

      await auditLog.catatCreate('pemasukan', id, jsonEncode(saved.toMap()));

      if (isTambahModal) {
        await saldoRepo.tambahModal(nominal, keterangan: keterangan);
      } else {
        await saldoRepo.bayarCampuran(
          cash: cash,
          transfer: bank,
          tipe: AppConstants.cashFlowMasuk,
          referensi: AppConstants.cashFlowRefPemasukan,
          referensiId: id,
          keterangan: keterangan ?? kategori,
          tanggal: tanggal,
        );
      }

      return saved;
    });
  }

  /// Edit pemasukan manual. TIDAK berlaku untuk pemasukan otomatis dari
  /// penjualan motor (edit lewat PenjualanRepository.editPenjualan) —
  /// dicegah oleh UI (kategori 'Penjualan Motor' tidak ditampilkan di
  /// sini).
  Future<PemasukanModel> editPemasukan({
    required int id,
    required DateTime tanggal,
    required String kategori,
    required double nominal,
    String? keterangan,
    String sumber = AppConstants.sumberCash,
    double cashMasuk = 0,
    double bankMasuk = 0,
  }) async {
    requireWriteAccess();
    return db.transaction<PemasukanModel>((txn) async {
      final result =
          await txn.query('pemasukan', where: 'id = ?', whereArgs: [id]);
      if (result.isEmpty) throw ArgumentError('Pemasukan tidak ditemukan');
      final lama = PemasukanModel.fromMap(result.first);

      final saldoRepo = SaldoRepository(txn);
      final auditLog = AuditLogRepository(txn);
      final lamaAdalahModal = lama.kategori == kategoriTambahModal;
      final baruAdalahModal = kategori == kategoriTambahModal;

      // Balik efek lama
      if (lamaAdalahModal) {
        await saldoRepo.ubahModal(
          jenis: AppConstants.modalJenisCash,
          aksi: AppConstants.modalAksiKurang,
          nominal: lama.nominal,
          keterangan: 'Koreksi Tambah Modal (nilai lama dibatalkan)',
        );
        await saldoRepo.mutasiCash(
          nominal: lama.nominal,
          tipe: AppConstants.cashFlowKeluar,
          referensi: AppConstants.cashFlowRefPemasukan,
          referensiId: id,
          keterangan: 'Koreksi Tambah Modal (nilai lama dibatalkan)',
        );
      } else {
        await saldoRepo.bayarCampuran(
          cash: lama.cashMasuk,
          transfer: lama.bankMasuk,
          tipe: AppConstants.cashFlowKeluar,
          referensi: AppConstants.cashFlowRefPemasukan,
          referensiId: id,
          keterangan: 'Koreksi pemasukan (nilai lama dibatalkan)',
        );
      }

      final sumberFinal = baruAdalahModal ? AppConstants.sumberCash : sumber;
      double cash;
      double bank;
      if (baruAdalahModal) {
        cash = nominal;
        bank = 0;
      } else {
        switch (sumberFinal) {
          case AppConstants.sumberBank:
            cash = 0;
            bank = nominal;
            break;
          case AppConstants.sumberCampuran:
            if ((cashMasuk + bankMasuk - nominal).abs() > 0.5) {
              throw ArgumentError(
                  'Cash + Bank (Rp${(cashMasuk + bankMasuk).toStringAsFixed(0)}) harus sama dengan nominal (Rp${nominal.toStringAsFixed(0)})');
            }
            cash = cashMasuk;
            bank = bankMasuk;
            break;
          case AppConstants.sumberCash:
          default:
            cash = nominal;
            bank = 0;
        }
      }

      final baru = PemasukanModel(
        id: id,
        tanggal: tanggal,
        kategori: kategori,
        nominal: nominal,
        keterangan: keterangan,
        sumber: sumberFinal,
        cashMasuk: cash,
        bankMasuk: bank,
        referensiId: lama.referensiId,
        periodeId: lama.periodeId,
        createdAt: lama.createdAt,
        updatedAt: DateTime.now(),
      );
      await txn.update('pemasukan', baru.toMap(),
          where: 'id = ?', whereArgs: [id]);
      await auditLog.catatUpdate(
        'pemasukan',
        id,
        jsonEncode(lama.toMap()),
        jsonEncode(baru.toMap()),
        keterangan: tanggal != lama.tanggal
            ? 'Edit pemasukan $kategori — tanggal diubah dari '
                '${lama.tanggal.toIso8601String().split("T").first} menjadi '
                '${tanggal.toIso8601String().split("T").first}'
            : 'Edit pemasukan $kategori',
      );

      // Terapkan efek baru
      if (baruAdalahModal) {
        await saldoRepo.tambahModal(nominal, keterangan: keterangan);
      } else {
        await saldoRepo.bayarCampuran(
          cash: cash,
          transfer: bank,
          tipe: AppConstants.cashFlowMasuk,
          referensi: AppConstants.cashFlowRefPemasukan,
          referensiId: id,
          keterangan: keterangan ?? kategori,
          tanggal: tanggal,
        );
      }

      return baru;
    });
  }

  /// HAPUS pemasukan manual. Kategori 'Penjualan Motor' TIDAK boleh
  /// dihapus dari sini — harus lewat PenjualanRepository.hapusPenjualan
  /// supaya status motor & modal ikut ter-rollback dengan benar.
  Future<void> hapusPemasukan(int id) async {
    requireWriteAccess();
    return db.transaction<void>((txn) async {
      final result =
          await txn.query('pemasukan', where: 'id = ?', whereArgs: [id]);
      if (result.isEmpty) return;
      final pemasukan = PemasukanModel.fromMap(result.first);

      if (pemasukan.kategori == 'Penjualan Motor') {
        throw StateError(
            'Pemasukan dari penjualan motor harus dihapus lewat menu Penjualan.');
      }

      final saldoRepo = SaldoRepository(txn);
      final auditLog = AuditLogRepository(txn);

      if (pemasukan.kategori == kategoriTambahModal) {
        await saldoRepo.ubahModal(
          jenis: AppConstants.modalJenisCash,
          aksi: AppConstants.modalAksiKurang,
          nominal: pemasukan.nominal,
          keterangan: 'Rollback hapus Tambah Modal',
        );
        await saldoRepo.mutasiCash(
          nominal: pemasukan.nominal,
          tipe: AppConstants.cashFlowKeluar,
          referensi: AppConstants.cashFlowRefPemasukan,
          referensiId: id,
          keterangan: 'Rollback hapus Tambah Modal',
        );
      } else {
        await saldoRepo.bayarCampuran(
          cash: pemasukan.cashMasuk,
          transfer: pemasukan.bankMasuk,
          tipe: AppConstants.cashFlowKeluar,
          referensi: AppConstants.cashFlowRefPemasukan,
          referensiId: id,
          keterangan: 'Rollback hapus pemasukan ${pemasukan.kategori}',
        );
      }

      await txn.delete('pemasukan', where: 'id = ?', whereArgs: [id]);
      await auditLog.catatDelete(
        'pemasukan',
        id,
        jsonEncode(pemasukan.toMap()),
        keterangan:
            'Hapus pemasukan ${pemasukan.kategori} — saldo dikembalikan',
      );
    });
  }

  Future<List<PemasukanModel>> getAll({int? periodeId, String? kategori}) async {
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
      'pemasukan',
      where: whereClauses.isEmpty ? null : whereClauses.join(' AND '),
      whereArgs: whereArgs.isEmpty ? null : whereArgs,
      orderBy: 'tanggal DESC',
    );
    return result.map((e) => PemasukanModel.fromMap(e)).toList();
  }

  Future<double> getTotalByKategori(String kategori, {int? periodeId}) async {
    final result = await db.rawQuery('''
      SELECT COALESCE(SUM(nominal), 0) as total FROM pemasukan
      WHERE kategori = ? ${periodeId != null ? "AND periode_id = ?" : ""}
    ''', periodeId != null ? [kategori, periodeId] : [kategori]);
    return (result.first['total'] as num).toDouble();
  }
}

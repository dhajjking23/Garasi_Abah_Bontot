import 'package:sqflite/sqflite.dart';
import 'dart:convert';
import '../core/constants/app_constants.dart';
import '../models/motor_model.dart';
import '../models/penjualan_model.dart';
import '../models/penjualan_pembayaran_model.dart';
import '../models/pemasukan_model.dart';
import 'audit_log_repository.dart';
import 'saldo_repository.dart';
import '../core/security/write_guard.dart';

/// Repository penjualan motor.
///
/// ATURAN CALO (wajib dipatuhi, jangan diubah tanpa instruksi eksplisit):
/// - Jika penjual == 'Calo': motor tetap TERJUAL, laba tetap dihitung
///   dan tetap masuk laba bersih periode, TAPI bonus_eligible = false
///   sehingga Calo tidak ikut pembagian hadiah penjualan 10%.
/// - Fee/komisi calo TIDAK dicatat di sistem manapun (dianggap transaksi
///   di luar perusahaan, murni urusan antara penjual unit dan si calo).
class PenjualanRepository {
  final Database db;

  PenjualanRepository(this.db);

  void _validasiSplitPembayaran(
      String metode, double cash, double transfer, double total) {
    if (metode == AppConstants.metodeCampuran) {
      final jumlah = cash + transfer;
      if ((jumlah - total).abs() > 0.5) {
        throw ArgumentError(
            'Cash + Transfer (Rp${jumlah.toStringAsFixed(0)}) harus sama dengan harga jual (Rp${total.toStringAsFixed(0)})');
      }
    }
  }

  Future<PenjualanModel> jualMotor({
    required int motorId,
    required DateTime tanggalJual,
    required double hargaJual,
    required String penjual,
    String metodePembayaran = AppConstants.metodeCash,
    double cashDiterima = 0,
    double transferDiterima = 0,
    /// Jumlah yang BENAR-BENAR dibayar saat transaksi (DP). Default =
    /// hargaJual (lunas penuh, perilaku lama). Jika lebih kecil dari
    /// hargaJual, penjualan berstatus BELUM_LUNAS dan sisanya bisa
    /// dicicil lewat [bayarPiutangPenjualan].
    double? jumlahDibayarSekarang,
    int? periodeId,
  }) async {
    requireWriteAccess();
    return db.transaction<PenjualanModel>((txn) async {
      final auditLog = AuditLogRepository(txn);
      final saldoRepo = SaldoRepository(txn);

      final motorResult =
          await txn.query('motor', where: 'id = ?', whereArgs: [motorId]);
      if (motorResult.isEmpty) {
        throw ArgumentError('Motor tidak ditemukan');
      }
      final motor = MotorModel.fromMap(motorResult.first);

      if (motor.isTerjual) {
        throw StateError('Motor ${motor.kodeMotor} sudah terjual sebelumnya.');
      }

      final modalMotor = motor.totalModal;
      final laba = hargaJual - modalMotor;
      final dibayarSekarang = jumlahDibayarSekarang ?? hargaJual;
      if (dibayarSekarang <= 0 || dibayarSekarang > hargaJual) {
        throw ArgumentError(
            'Jumlah dibayar sekarang harus antara 0 dan harga jual');
      }

      // Aturan Calo: bonus_eligible = false, laba & status tetap normal.
      final bonusEligible = penjual != AppConstants.penjualCalo;

      double cash;
      double transfer;
      switch (metodePembayaran) {
        case AppConstants.metodeTransfer:
          cash = 0;
          transfer = dibayarSekarang;
          break;
        case AppConstants.metodeCampuran:
          _validasiSplitPembayaran(
              metodePembayaran, cashDiterima, transferDiterima, dibayarSekarang);
          cash = cashDiterima;
          transfer = transferDiterima;
          break;
        case AppConstants.metodeCash:
        default:
          cash = dibayarSekarang;
          transfer = 0;
      }

      final statusPembayaran = dibayarSekarang >= hargaJual
          ? AppConstants.statusPembayaranLunas
          : AppConstants.statusPembayaranBelumLunas;

      final now = DateTime.now();
      final penjualan = PenjualanModel(
        motorId: motorId,
        tanggalJual: tanggalJual,
        hargaJual: hargaJual,
        modalMotor: modalMotor,
        laba: laba,
        penjual: penjual,
        bonusEligible: bonusEligible,
        metodePembayaran: metodePembayaran,
        cashDiterima: cash,
        transferDiterima: transfer,
        statusPembayaran: statusPembayaran,
        periodeId: periodeId,
        createdAt: now,
      );

      final penjualanId = await txn.insert('penjualan', penjualan.toMap());
      final saved = PenjualanModel.fromMap({
        ...penjualan.toMap(),
        'id': penjualanId,
      });

      await auditLog.catatCreate(
        'penjualan',
        penjualanId,
        jsonEncode(saved.toMap()),
        keterangan: 'Jual ${motor.kodeMotor} oleh $penjual ($metodePembayaran)'
            '${statusPembayaran == AppConstants.statusPembayaranBelumLunas ? " - DP Rp${dibayarSekarang.toStringAsFixed(0)} dari Rp${hargaJual.toStringAsFixed(0)}" : ""}'
            '${bonusEligible ? "" : " (CALO - tidak dapat bonus)"}',
      );

      // Update status motor -> TERJUAL (status motor & status pembayaran
      // adalah dua hal berbeda: motor tetap TERJUAL meski piutang belum
      // lunas, supaya tidak bisa dijual dobel).
      final motorLamaMap = motor.toMap();
      await txn.update(
        'motor',
        {
          'status': AppConstants.statusMotorTerjual,
          'updated_at': now.toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [motorId],
      );
      await auditLog.catatUpdate(
        'motor',
        motorId,
        jsonEncode(motorLamaMap),
        jsonEncode({...motorLamaMap, 'status': AppConstants.statusMotorTerjual}),
        keterangan: 'Status motor -> TERJUAL',
      );

      // Catat pemasukan otomatis SEBESAR yang benar-benar diterima
      // sekarang (bukan harga jual penuh jika baru DP).
      final pemasukan = PemasukanModel(
        tanggal: tanggalJual,
        kategori: 'Penjualan Motor',
        nominal: dibayarSekarang,
        keterangan: 'Penjualan ${motor.kodeMotor} - ${motor.namaLengkap}'
            '${statusPembayaran == AppConstants.statusPembayaranBelumLunas ? " (DP)" : ""}',
        sumber: metodePembayaran == AppConstants.metodeTransfer
            ? AppConstants.sumberBank
            : AppConstants.sumberCash,
        referensiId: penjualanId,
        periodeId: periodeId,
        createdAt: now,
      );
      final pemasukanId = await txn.insert('pemasukan', pemasukan.toMap());
      await auditLog.catatCreate(
        'pemasukan',
        pemasukanId,
        jsonEncode(pemasukan.toMap()),
      );

      // Tambah cash/bank sejumlah yang benar-benar dibayar sekarang.
      await saldoRepo.bayarCampuran(
        cash: cash,
        transfer: transfer,
        tipe: AppConstants.cashFlowMasuk,
        referensi: AppConstants.cashFlowRefPenjualan,
        referensiId: penjualanId,
        keterangan: 'Penjualan ${motor.kodeMotor} oleh $penjual',
        tanggal: tanggalJual,
      );

      return saved;
    });
  }

  /// Bayar cicilan/pelunasan piutang penjualan (DP -> lunas bertahap).
  Future<PenjualanModel> bayarPiutangPenjualan({
    required int penjualanId,
    required DateTime tanggal,
    required double nominal,
    String metodePembayaran = AppConstants.metodeCash,
    double cashDibayar = 0,
    double transferDibayar = 0,
    String? keterangan,
  }) async {
    requireWriteAccess();
    return db.transaction<PenjualanModel>((txn) async {
      final result = await txn
          .query('penjualan', where: 'id = ?', whereArgs: [penjualanId]);
      if (result.isEmpty) throw ArgumentError('Penjualan tidak ditemukan');
      final penjualan = PenjualanModel.fromMap(result.first);

      if (penjualan.isLunas) {
        throw StateError('Penjualan ini sudah lunas.');
      }
      if (nominal > penjualan.sisaPembayaran) {
        throw ArgumentError(
            'Nominal (Rp${nominal.toStringAsFixed(0)}) melebihi sisa piutang (Rp${penjualan.sisaPembayaran.toStringAsFixed(0)})');
      }

      double cash;
      double transfer;
      switch (metodePembayaran) {
        case AppConstants.metodeTransfer:
          cash = 0;
          transfer = nominal;
          break;
        case AppConstants.metodeCampuran:
          _validasiSplitPembayaran(metodePembayaran, cashDibayar, transferDibayar, nominal);
          cash = cashDibayar;
          transfer = transferDibayar;
          break;
        case AppConstants.metodeCash:
        default:
          cash = nominal;
          transfer = 0;
      }

      final now = DateTime.now();
      final pembayaran = PenjualanPembayaranModel(
        penjualanId: penjualanId,
        tanggal: tanggal,
        nominal: nominal,
        metodePembayaran: metodePembayaran,
        cashTerpakai: cash,
        transferTerpakai: transfer,
        keterangan: keterangan,
        createdAt: now,
      );
      final pembayaranId =
          await txn.insert('penjualan_pembayaran', pembayaran.toMap());

      final auditLog = AuditLogRepository(txn);
      await auditLog.catatCreate(
        'penjualan_pembayaran',
        pembayaranId,
        jsonEncode(pembayaran.toMap()),
        keterangan: 'Cicilan penjualan #$penjualanId',
      );

      final cashBaru = penjualan.cashDiterima + cash;
      final transferBaru = penjualan.transferDiterima + transfer;
      final totalBaru = cashBaru + transferBaru;
      final statusBaru = totalBaru >= penjualan.hargaJual
          ? AppConstants.statusPembayaranLunas
          : AppConstants.statusPembayaranBelumLunas;

      final penjualanBaru = penjualan.copyWith(
        cashDiterima: cashBaru,
        transferDiterima: transferBaru,
        statusPembayaran: statusBaru,
      );
      await txn.update('penjualan', penjualanBaru.toMap(),
          where: 'id = ?', whereArgs: [penjualanId]);
      await auditLog.catatUpdate(
        'penjualan',
        penjualanId,
        jsonEncode(penjualan.toMap()),
        jsonEncode(penjualanBaru.toMap()),
        keterangan: 'Status pembayaran -> $statusBaru',
      );

      final saldoRepo = SaldoRepository(txn);
      await saldoRepo.bayarCampuran(
        cash: cash,
        transfer: transfer,
        tipe: AppConstants.cashFlowMasuk,
        referensi: AppConstants.cashFlowRefPenjualanCicilan,
        referensiId: pembayaranId,
        keterangan: 'Cicilan penjualan #$penjualanId',
        tanggal: tanggal,
      );

      return penjualanBaru;
    });
  }

  /// Edit HANYA tanggal cicilan/pelunasan DP (penjualan_pembayaran).
  Future<void> editTanggalPembayaran(int pembayaranId, DateTime tanggalBaru) async {
    requireWriteAccess();
    return db.transaction<void>((txn) async {
      final result = await txn.query('penjualan_pembayaran',
          where: 'id = ?', whereArgs: [pembayaranId]);
      if (result.isEmpty) throw ArgumentError('Pembayaran tidak ditemukan');
      final lama = PenjualanPembayaranModel.fromMap(result.first);
      final auditLog = AuditLogRepository(txn);

      await txn.update(
        'penjualan_pembayaran',
        {'tanggal': tanggalBaru.toIso8601String()},
        where: 'id = ?',
        whereArgs: [pembayaranId],
      );
      await auditLog.catatUpdate(
        'penjualan_pembayaran',
        pembayaranId,
        jsonEncode({'tanggal': lama.tanggal.toIso8601String()}),
        jsonEncode({'tanggal': tanggalBaru.toIso8601String()}),
        keterangan: 'Mengubah tanggal cicilan/pelunasan penjualan #${lama.penjualanId}: dari '
            '${lama.tanggal.toIso8601String().split("T").first} menjadi '
            '${tanggalBaru.toIso8601String().split("T").first}',
      );
    });
  }

  Future<List<PenjualanPembayaranModel>> getRiwayatPembayaran(
      int penjualanId) async {
    final result = await db.query(
      'penjualan_pembayaran',
      where: 'penjualan_id = ?',
      whereArgs: [penjualanId],
      orderBy: 'tanggal DESC',
    );
    return result.map((e) => PenjualanPembayaranModel.fromMap(e)).toList();
  }

  /// Edit data penjualan (harga jual, penjual, metode pembayaran).
  /// Rollback efek kas lama, hitung ulang laba, terapkan efek kas baru.
  Future<PenjualanModel> editPenjualan({
    required int penjualanId,
    required double hargaJualBaru,
    required String penjualBaru,
    required String metodePembayaranBaru,
    double cashDiterimaBaru = 0,
    double transferDiterimaBaru = 0,
    DateTime? tanggalJualBaru,
  }) async {
    requireWriteAccess();
    return db.transaction<PenjualanModel>((txn) async {
      final result = await txn
          .query('penjualan', where: 'id = ?', whereArgs: [penjualanId]);
      if (result.isEmpty) throw ArgumentError('Penjualan tidak ditemukan');
      final lama = PenjualanModel.fromMap(result.first);

      final adaCicilan = Sqflite.firstIntValue(await txn.rawQuery(
              'SELECT COUNT(*) FROM penjualan_pembayaran WHERE penjualan_id = ?',
              [penjualanId])) ??
          0;
      if (adaCicilan > 0) {
        throw StateError(
            'Penjualan ini sudah punya riwayat cicilan. Hapus riwayat cicilan dulu sebelum mengedit.');
      }

      final motorResult = await txn
          .query('motor', where: 'id = ?', whereArgs: [lama.motorId]);
      final motor = MotorModel.fromMap(motorResult.first);

      final saldoRepo = SaldoRepository(txn);
      final auditLog = AuditLogRepository(txn);

      // Balik efek kas lama
      await saldoRepo.bayarCampuran(
        cash: lama.cashDiterima,
        transfer: lama.transferDiterima,
        tipe: AppConstants.cashFlowKeluar,
        referensi: AppConstants.cashFlowRefPenjualan,
        referensiId: penjualanId,
        keterangan: 'Koreksi penjualan ${motor.kodeMotor} (nilai lama dibatalkan)',
      );

      final labaBaru = hargaJualBaru - lama.modalMotor;
      final bonusEligibleBaru = penjualBaru != AppConstants.penjualCalo;

      double cash;
      double transfer;
      switch (metodePembayaranBaru) {
        case AppConstants.metodeTransfer:
          cash = 0;
          transfer = hargaJualBaru;
          break;
        case AppConstants.metodeCampuran:
          _validasiSplitPembayaran(metodePembayaranBaru, cashDiterimaBaru,
              transferDiterimaBaru, hargaJualBaru);
          cash = cashDiterimaBaru;
          transfer = transferDiterimaBaru;
          break;
        case AppConstants.metodeCash:
        default:
          cash = hargaJualBaru;
          transfer = 0;
      }

      final tanggalBaru = tanggalJualBaru ?? lama.tanggalJual;

      final baru = PenjualanModel(
        id: lama.id,
        motorId: lama.motorId,
        tanggalJual: tanggalBaru,
        hargaJual: hargaJualBaru,
        modalMotor: lama.modalMotor,
        laba: labaBaru,
        penjual: penjualBaru,
        bonusEligible: bonusEligibleBaru,
        metodePembayaran: metodePembayaranBaru,
        cashDiterima: cash,
        transferDiterima: transfer,
        statusPembayaran: AppConstants.statusPembayaranLunas,
        periodeId: lama.periodeId,
        createdAt: lama.createdAt,
      );

      await txn.update('penjualan', baru.toMap(),
          where: 'id = ?', whereArgs: [penjualanId]);
      await auditLog.catatUpdate(
        'penjualan',
        penjualanId,
        jsonEncode(lama.toMap()),
        jsonEncode(baru.toMap()),
        keterangan: tanggalBaru != lama.tanggalJual
            ? 'Edit penjualan ${motor.kodeMotor} — tanggal diubah dari '
                '${lama.tanggalJual.toIso8601String().split("T").first} menjadi '
                '${tanggalBaru.toIso8601String().split("T").first}'
            : 'Edit penjualan ${motor.kodeMotor}',
      );

      // Sinkronkan pemasukan otomatis terkait
      await txn.update(
        'pemasukan',
        {
          'nominal': hargaJualBaru,
          'sumber': metodePembayaranBaru == AppConstants.metodeTransfer
              ? AppConstants.sumberBank
              : AppConstants.sumberCash,
          'tanggal': tanggalBaru.toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'kategori = ? AND referensi_id = ?',
        whereArgs: ['Penjualan Motor', penjualanId],
      );

      await saldoRepo.bayarCampuran(
        cash: cash,
        transfer: transfer,
        tipe: AppConstants.cashFlowMasuk,
        referensi: AppConstants.cashFlowRefPenjualan,
        referensiId: penjualanId,
        keterangan: 'Penjualan ${motor.kodeMotor} (setelah edit)',
        tanggal: tanggalBaru,
      );

      return baru;
    });
  }

  /// Edit HANYA tanggal transaksi penjualan (tanpa mengubah nominal/metode).
  /// Dipakai untuk koreksi tanggal cepat dari layar riwayat.
  Future<void> editTanggalPenjualan(int penjualanId, DateTime tanggalBaru) async {
    requireWriteAccess();
    return db.transaction<void>((txn) async {
      final result = await txn
          .query('penjualan', where: 'id = ?', whereArgs: [penjualanId]);
      if (result.isEmpty) throw ArgumentError('Penjualan tidak ditemukan');
      final lama = PenjualanModel.fromMap(result.first);
      final auditLog = AuditLogRepository(txn);

      await txn.update(
        'penjualan',
        {'tanggal_jual': tanggalBaru.toIso8601String()},
        where: 'id = ?',
        whereArgs: [penjualanId],
      );
      await txn.update(
        'pemasukan',
        {
          'tanggal': tanggalBaru.toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'kategori = ? AND referensi_id = ?',
        whereArgs: ['Penjualan Motor', penjualanId],
      );
      await auditLog.catatUpdate(
        'penjualan',
        penjualanId,
        jsonEncode({'tanggal_jual': lama.tanggalJual.toIso8601String()}),
        jsonEncode({'tanggal_jual': tanggalBaru.toIso8601String()}),
        keterangan: 'Mengubah tanggal transaksi penjualan: dari '
            '${lama.tanggalJual.toIso8601String().split("T").first} menjadi '
            '${tanggalBaru.toIso8601String().split("T").first}',
      );
    });
  }

  /// HAPUS penjualan (Sistem Hapus Transaksi). Rollback: cash/bank
  /// dikembalikan, pemasukan otomatis dihapus, dan status motor
  /// dikembalikan ke TERSEDIA.
  Future<void> hapusPenjualan(int penjualanId) async {
    requireWriteAccess();
    return db.transaction<void>((txn) async {
      final result = await txn
          .query('penjualan', where: 'id = ?', whereArgs: [penjualanId]);
      if (result.isEmpty) return;
      final penjualan = PenjualanModel.fromMap(result.first);

      final saldoRepo = SaldoRepository(txn);
      final auditLog = AuditLogRepository(txn);

      final motorResult = await txn
          .query('motor', where: 'id = ?', whereArgs: [penjualan.motorId]);
      final motorKode = motorResult.isNotEmpty
          ? MotorModel.fromMap(motorResult.first).kodeMotor
          : 'motor';

      await saldoRepo.bayarCampuran(
        cash: penjualan.cashDiterima,
        transfer: penjualan.transferDiterima,
        tipe: AppConstants.cashFlowKeluar,
        referensi: AppConstants.cashFlowRefPenjualan,
        referensiId: penjualanId,
        keterangan: 'Rollback hapus penjualan $motorKode',
      );

      await txn.delete('pemasukan',
          where: 'kategori = ? AND referensi_id = ?',
          whereArgs: ['Penjualan Motor', penjualanId]);

      await txn.update(
        'motor',
        {
          'status': AppConstants.statusMotorTersedia,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [penjualan.motorId],
      );

      await txn.delete('penjualan', where: 'id = ?', whereArgs: [penjualanId]);
      await auditLog.catatDelete(
        'penjualan',
        penjualanId,
        jsonEncode(penjualan.toMap()),
        keterangan:
            'Hapus penjualan $motorKode — saldo dikembalikan, status motor -> TERSEDIA',
      );
    });
  }

  Future<PenjualanModel?> getById(int id) async {
    final result = await db.query('penjualan', where: 'id = ?', whereArgs: [id]);
    if (result.isEmpty) return null;
    return PenjualanModel.fromMap(result.first);
  }

  /// Daftar penjualan yang masih ada piutang (DP belum lunas).
  Future<List<PenjualanModel>> getPenjualanBelumLunas() async {
    final result = await db.query(
      'penjualan',
      where: 'status_pembayaran = ?',
      whereArgs: [AppConstants.statusPembayaranBelumLunas],
      orderBy: 'tanggal_jual DESC',
    );
    return result.map((e) => PenjualanModel.fromMap(e)).toList();
  }

  /// Total piutang penjualan (DP) yang masih outstanding — dipakai
  /// Dashboard & Laporan.
  Future<double> getTotalPiutangPenjualan() async {
    final result = await db.rawQuery('''
      SELECT harga_jual, cash_diterima, transfer_diterima FROM penjualan
      WHERE status_pembayaran = ?
    ''', [AppConstants.statusPembayaranBelumLunas]);
    double total = 0;
    for (final row in result) {
      final harga = (row['harga_jual'] as num).toDouble();
      final diterima = (row['cash_diterima'] as num).toDouble() +
          (row['transfer_diterima'] as num).toDouble();
      total += (harga - diterima).clamp(0, harga);
    }
    return total;
  }

  Future<List<PenjualanModel>> getAll({int? periodeId}) async {
    final result = await db.query(
      'penjualan',
      where: periodeId != null ? 'periode_id = ?' : null,
      whereArgs: periodeId != null ? [periodeId] : null,
      orderBy: 'tanggal_jual DESC',
    );
    return result.map((e) => PenjualanModel.fromMap(e)).toList();
  }

  Future<PenjualanModel?> getByMotorId(int motorId) async {
    final result = await db.query(
      'penjualan',
      where: 'motor_id = ?',
      whereArgs: [motorId],
      limit: 1,
    );
    if (result.isEmpty) return null;
    return PenjualanModel.fromMap(result.first);
  }

  /// Rekap total penjualan per penjual dalam suatu periode.
  /// Dipakai untuk laporan "Penjualan per Orang".
  Future<Map<String, int>> getJumlahUnitPerPenjual(int periodeId) async {
    final result = await db.rawQuery('''
      SELECT penjual, COUNT(*) as jumlah
      FROM penjualan
      WHERE periode_id = ?
      GROUP BY penjual
    ''', [periodeId]);

    final map = <String, int>{};
    for (final row in result) {
      map[row['penjual'] as String] = row['jumlah'] as int;
    }
    return map;
  }
}

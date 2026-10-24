import 'package:sqflite/sqflite.dart';
import 'dart:convert';
import '../core/constants/app_constants.dart';
import '../models/motor_model.dart';
import '../models/motor_cost_model.dart';
import '../models/penjualan_model.dart';
import 'audit_log_repository.dart';
import 'saldo_repository.dart';
import '../core/security/write_guard.dart';

/// Repository motor. Menangani logika pembelian unit (harga beli + biaya
/// = total modal), penambahan biaya susulan, edit, hapus (dengan
/// rollback saldo penuh), dan query stok/histori.
///
/// SEMUA operasi yang mengubah kas dibungkus dalam database transaction
/// agar konsisten: motor, motor_cost, saldo, dan cash_flow harus
/// berhasil bersamaan atau gagal bersamaan.
class MotorRepository {
  final Database db;

  MotorRepository(this.db);

  /// Generate kode motor berikutnya berdasarkan ANGKA TERTINGGI yang sudah
  /// pernah dipakai (bukan COUNT(*) baris) — supaya tidak tabrakan kalau
  /// ada motor yang pernah dihapus, atau nomor "meloncat" karena data
  /// masuk lewat sync (V5.1: push dari admin / pull dari server tidak
  /// selalu berurutan rapi seperti input manual satu-satu).
  Future<String> _generateKodeMotor(DatabaseExecutor txn) async {
    final result = await txn.rawQuery(
      "SELECT kode_motor FROM motor WHERE kode_motor LIKE 'MTR-%'",
    );
    int maxNomor = 0;
    for (final row in result) {
      final kode = row['kode_motor'] as String? ?? '';
      final numPart = kode.replaceFirst('MTR-', '');
      final n = int.tryParse(numPart);
      if (n != null && n > maxNomor) maxNomor = n;
    }

    // Coba angka berikutnya, dan kalau ternyata (sangat jarang, mis. race
    // condition antar-device sebelum sempat sync) masih tabrakan juga,
    // naikkan terus sampai benar-benar unik -- daripada gagal INSERT.
    int candidate = maxNomor + 1;
    while (true) {
      final kode = 'MTR-${candidate.toString().padLeft(4, '0')}';
      final exists = Sqflite.firstIntValue(await txn.rawQuery(
            'SELECT COUNT(*) FROM motor WHERE kode_motor = ?', [kode],
          )) ??
          0;
      if (exists == 0) return kode;
      candidate++;
    }
  }

  void _validasiSplitPembayaran(
      String metode, double cash, double transfer, double total) {
    if (metode == AppConstants.metodeCampuran) {
      final jumlah = cash + transfer;
      if ((jumlah - total).abs() > 0.5) {
        throw ArgumentError(
            'Cash + Transfer (Rp${jumlah.toStringAsFixed(0)}) harus sama dengan total (Rp${total.toStringAsFixed(0)})');
      }
    }
  }

  /// Menambahkan motor baru ke stok.
  ///
  /// [biayaAwal] adalah daftar biaya (kategori & nominal) yang langsung
  /// dikeluarkan saat pembelian, misal: Transportasi, Bensin, Service, dll.
  /// Total modal = hargaBeli + total semua biayaAwal. Biaya tambahan
  /// SELALU dibayar via metode yang sama dengan harga beli (disederhanakan
  /// agar satu transaksi = satu metode pembayaran utama).
  Future<MotorModel> tambahMotor({
    required String merk,
    required String tipe,
    int? tahun,
    String? warna,
    String? platNomor,
    required DateTime tanggalMasuk,
    required double hargaBeli,
    String metodePembayaran = AppConstants.metodeCash,
    double cashDibayar = 0,
    double transferDibayar = 0,
    String? jenisTransfer,
    String? catatan,
    int? periodeId,
    List<MotorCostModel> biayaAwal = const [],
  }) async {
    requireWriteAccess();
    return db.transaction<MotorModel>((txn) async {
      final auditLog = AuditLogRepository(txn);
      final saldoRepo = SaldoRepository(txn);

      final kodeMotor = await _generateKodeMotor(txn);
      final now = DateTime.now();

      final totalBiaya =
          biayaAwal.fold<double>(0, (sum, c) => sum + c.nominal);
      final totalModal = hargaBeli + totalBiaya;

      // Normalisasi nilai split sesuai metode pembayaran.
      double cash;
      double transfer;
      switch (metodePembayaran) {
        case AppConstants.metodeTransfer:
          cash = 0;
          transfer = totalModal;
          break;
        case AppConstants.metodeCampuran:
          _validasiSplitPembayaran(
              metodePembayaran, cashDibayar, transferDibayar, totalModal);
          cash = cashDibayar;
          transfer = transferDibayar;
          break;
        case AppConstants.metodeCash:
        default:
          cash = totalModal;
          transfer = 0;
      }

      final motor = MotorModel(
        kodeMotor: kodeMotor,
        merk: merk,
        tipe: tipe,
        tahun: tahun,
        warna: warna,
        platNomor: platNomor,
        tanggalMasuk: tanggalMasuk,
        hargaBeli: hargaBeli,
        totalModal: totalModal,
        status: AppConstants.statusMotorTersedia,
        metodePembayaran: metodePembayaran,
        cashDibayar: cash,
        transferDibayar: transfer,
        jenisTransfer: transfer > 0 ? jenisTransfer : null,
        catatan: catatan,
        periodeId: periodeId,
        createdAt: now,
        updatedAt: now,
      );

      final motorId = await txn.insert('motor', motor.toMap());
      var savedMotor = motor.copyWith(id: motorId);

      await auditLog.catatCreate(
        'motor',
        motorId,
        jsonEncode(savedMotor.toMap()),
        keterangan: 'Pembelian unit $kodeMotor ($metodePembayaran)',
      );

      // Simpan setiap biaya awal ke motor_cost. Biaya awal dibayar
      // BERSAMAAN dengan harga beli lewat satu transaksi (split cash di
      // atas), jadi split per-item di sini dihitung PROPORSIONAL
      // terhadap rasio cash:transfer motor supaya total tetap akurat
      // dan editBiaya/hapusBiaya nanti bisa rollback dengan benar.
      final rasioCash = totalModal > 0 ? cash / totalModal : 1.0;
      for (final biaya in biayaAwal) {
        final biayaCash = (biaya.nominal * rasioCash).roundToDouble();
        final biayaTransfer = biaya.nominal - biayaCash;
        final costToSave = biaya.copyWith(
          motorId: motorId,
          metodePembayaran: metodePembayaran,
          cashDibayar: biayaCash,
          transferDibayar: biayaTransfer,
          createdAt: now,
        );
        final costId = await txn.insert('motor_cost', costToSave.toMap());
        await auditLog.catatCreate(
          'motor_cost',
          costId,
          jsonEncode(costToSave.toMap()),
        );
      }

      // Kurangi cash/bank sejumlah total modal (harga beli + semua biaya)
      final biayaAdmin = await saldoRepo.bayarCampuran(
        cash: cash,
        transfer: transfer,
        tipe: AppConstants.cashFlowKeluar,
        referensi: AppConstants.cashFlowRefMotorBeli,
        referensiId: motorId,
        keterangan: 'Pembelian unit $kodeMotor ($merk $tipe)',
        tanggal: tanggalMasuk,
        jenisTransfer: jenisTransfer,
      );

      if (biayaAdmin > 0) {
        savedMotor = savedMotor.copyWith(biayaAdminTransfer: biayaAdmin);
        await txn.update('motor', savedMotor.toMap(),
            where: 'id = ?', whereArgs: [motorId]);
      }

      return savedMotor;
    });
  }

  /// Menambahkan biaya susulan ke motor yang sudah ada (misal service
  /// tambahan setelah unit masuk stok). Otomatis update total_modal
  /// motor. Biaya susulan punya metode pembayaran SENDIRI (tidak lagi
  /// otomatis ikut metode motor induk) — bisa Cash/Transfer/Campuran.
  Future<MotorModel> tambahBiaya({
    required int motorId,
    required String kategori,
    required double nominal,
    String metodePembayaran = AppConstants.metodeCash,
    double cashDibayar = 0,
    double transferDibayar = 0,
    String? jenisTransfer,
    String? keterangan,
    DateTime? tanggal,
  }) async {
    requireWriteAccess();
    return db.transaction<MotorModel>((txn) async {
      final auditLog = AuditLogRepository(txn);
      final saldoRepo = SaldoRepository(txn);

      final motorResult =
          await txn.query('motor', where: 'id = ?', whereArgs: [motorId]);
      if (motorResult.isEmpty) {
        throw ArgumentError('Motor tidak ditemukan');
      }
      final motorLama = MotorModel.fromMap(motorResult.first);

      double cash;
      double transfer;
      switch (metodePembayaran) {
        case AppConstants.metodeTransfer:
          cash = 0;
          transfer = nominal;
          break;
        case AppConstants.metodeCampuran:
          _validasiSplitPembayaran(
              metodePembayaran, cashDibayar, transferDibayar, nominal);
          cash = cashDibayar;
          transfer = transferDibayar;
          break;
        case AppConstants.metodeCash:
        default:
          cash = nominal;
          transfer = 0;
      }

      final now = DateTime.now();
      var cost = MotorCostModel(
        motorId: motorId,
        kategori: kategori,
        nominal: nominal,
        metodePembayaran: metodePembayaran,
        cashDibayar: cash,
        transferDibayar: transfer,
        jenisTransfer: transfer > 0 ? jenisTransfer : null,
        keterangan: keterangan,
        tanggal: tanggal ?? now,
        createdAt: now,
      );
      final costId = await txn.insert('motor_cost', cost.toMap());
      cost = cost.copyWith(id: costId);
      await auditLog.catatCreate(
          'motor_cost', costId, jsonEncode(cost.toMap()));

      // total_modal & split cash/transfer motor ikut terakumulasi
      // (dipakai untuk rollback saat hapus motor), TAPI metode_pembayaran
      // utama motor TIDAK diubah — itu tetap mencerminkan pembelian
      // awal saja.
      final motorBaru = motorLama.copyWith(
        totalModal: motorLama.totalModal + nominal,
        cashDibayar: motorLama.cashDibayar + cash,
        transferDibayar: motorLama.transferDibayar + transfer,
        updatedAt: now,
      );
      await txn.update('motor', motorBaru.toMap(),
          where: 'id = ?', whereArgs: [motorId]);
      await auditLog.catatUpdate(
        'motor',
        motorId,
        jsonEncode(motorLama.toMap()),
        jsonEncode(motorBaru.toMap()),
        keterangan: 'Tambah biaya $kategori: Rp$nominal ($metodePembayaran)',
      );

      final biayaAdmin = await saldoRepo.bayarCampuran(
        cash: cash,
        transfer: transfer,
        tipe: AppConstants.cashFlowKeluar,
        referensi: AppConstants.cashFlowRefMotorCost,
        referensiId: costId,
        keterangan: '$kategori - ${motorBaru.kodeMotor}',
        tanggal: tanggal,
        jenisTransfer: jenisTransfer,
      );

      if (biayaAdmin > 0) {
        cost = cost.copyWith(biayaAdminTransfer: biayaAdmin);
        await txn.update('motor_cost', cost.toMap(),
            where: 'id = ?', whereArgs: [costId]);
      }

      return motorBaru;
    });
  }

  /// Edit biaya tambahan/susulan motor. Efek kas lama dibalik, efek
  /// baru diterapkan, dan total_modal motor DIHITUNG ULANG otomatis
  /// (spesifikasi V3 #6).
  Future<MotorModel> editBiaya({
    required int biayaId,
    required String kategori,
    required double nominalBaru,
    String metodePembayaran = AppConstants.metodeCash,
    double cashDibayar = 0,
    double transferDibayar = 0,
    String? jenisTransfer,
    String? keterangan,
  }) async {
    requireWriteAccess();
    return db.transaction<MotorModel>((txn) async {
      final biayaResult = await txn
          .query('motor_cost', where: 'id = ?', whereArgs: [biayaId]);
      if (biayaResult.isEmpty) {
        throw ArgumentError('Biaya tidak ditemukan');
      }
      final biayaLama = MotorCostModel.fromMap(biayaResult.first);

      final motorResult = await txn
          .query('motor', where: 'id = ?', whereArgs: [biayaLama.motorId]);
      if (motorResult.isEmpty) throw ArgumentError('Motor tidak ditemukan');
      final motorLama = MotorModel.fromMap(motorResult.first);

      final saldoRepo = SaldoRepository(txn);
      final auditLog = AuditLogRepository(txn);

      // Balik efek kas biaya lama, termasuk biaya admin transfer lama.
      await saldoRepo.bayarCampuran(
        cash: biayaLama.cashDibayar,
        transfer: biayaLama.transferDibayar,
        tipe: AppConstants.cashFlowMasuk,
        referensi: AppConstants.cashFlowRefMotorCost,
        referensiId: biayaId,
        keterangan: 'Koreksi biaya ${biayaLama.kategori} (nilai lama dibatalkan)',
      );
      if (biayaLama.biayaAdminTransfer > 0) {
        await saldoRepo.mutasiBank(
          nominal: biayaLama.biayaAdminTransfer,
          tipe: AppConstants.cashFlowMasuk,
          referensi: AppConstants.cashFlowRefAdminTransfer,
          referensiId: biayaId,
          keterangan: 'Koreksi admin transfer biaya (nilai lama dibatalkan)',
        );
      }

      double cash;
      double transfer;
      switch (metodePembayaran) {
        case AppConstants.metodeTransfer:
          cash = 0;
          transfer = nominalBaru;
          break;
        case AppConstants.metodeCampuran:
          _validasiSplitPembayaran(
              metodePembayaran, cashDibayar, transferDibayar, nominalBaru);
          cash = cashDibayar;
          transfer = transferDibayar;
          break;
        case AppConstants.metodeCash:
        default:
          cash = nominalBaru;
          transfer = 0;
      }

      final biayaBaru = biayaLama.copyWith(
        kategori: kategori,
        nominal: nominalBaru,
        metodePembayaran: metodePembayaran,
        cashDibayar: cash,
        transferDibayar: transfer,
        jenisTransfer: transfer > 0 ? jenisTransfer : null,
        biayaAdminTransfer: 0,
        keterangan: keterangan,
      );
      await txn.update('motor_cost', biayaBaru.toMap(),
          where: 'id = ?', whereArgs: [biayaId]);
      await auditLog.catatUpdate(
        'motor_cost',
        biayaId,
        jsonEncode(biayaLama.toMap()),
        jsonEncode(biayaBaru.toMap()),
        keterangan: 'Edit biaya ${biayaLama.kategori}',
      );

      // Modal motor dihitung ulang: kurangi nominal lama, tambah baru.
      final motorBaru = motorLama.copyWith(
        totalModal: motorLama.totalModal - biayaLama.nominal + nominalBaru,
        cashDibayar: motorLama.cashDibayar - biayaLama.cashDibayar + cash,
        transferDibayar:
            motorLama.transferDibayar - biayaLama.transferDibayar + transfer,
        updatedAt: DateTime.now(),
      );
      await txn.update('motor', motorBaru.toMap(),
          where: 'id = ?', whereArgs: [motorLama.id]);
      await auditLog.catatUpdate(
        'motor',
        motorLama.id!,
        jsonEncode(motorLama.toMap()),
        jsonEncode(motorBaru.toMap()),
        keterangan: 'Modal dihitung ulang setelah edit biaya ${biayaBaru.kategori}',
      );

      final biayaAdminBaru = await saldoRepo.bayarCampuran(
        cash: cash,
        transfer: transfer,
        tipe: AppConstants.cashFlowKeluar,
        referensi: AppConstants.cashFlowRefMotorCost,
        referensiId: biayaId,
        keterangan: '${biayaBaru.kategori} - ${motorBaru.kodeMotor} (setelah edit)',
        jenisTransfer: jenisTransfer,
      );
      if (biayaAdminBaru > 0) {
        await txn.update(
            'motor_cost',
            biayaBaru.copyWith(biayaAdminTransfer: biayaAdminBaru).toMap(),
            where: 'id = ?',
            whereArgs: [biayaId]);
      }

      return motorBaru;
    });
  }

  /// Hapus biaya tambahan/susulan motor (Sistem Hapus Transaksi).
  /// Cash/Bank dikembalikan dan total_modal motor dihitung ulang
  /// otomatis (spesifikasi V3 #6).
  Future<MotorModel> hapusBiaya(int biayaId) async {
    requireWriteAccess();
    return db.transaction<MotorModel>((txn) async {
      final biayaResult = await txn
          .query('motor_cost', where: 'id = ?', whereArgs: [biayaId]);
      if (biayaResult.isEmpty) {
        throw ArgumentError('Biaya tidak ditemukan');
      }
      final biaya = MotorCostModel.fromMap(biayaResult.first);

      final motorResult = await txn
          .query('motor', where: 'id = ?', whereArgs: [biaya.motorId]);
      if (motorResult.isEmpty) throw ArgumentError('Motor tidak ditemukan');
      final motorLama = MotorModel.fromMap(motorResult.first);

      final saldoRepo = SaldoRepository(txn);
      final auditLog = AuditLogRepository(txn);

      await saldoRepo.bayarCampuran(
        cash: biaya.cashDibayar,
        transfer: biaya.transferDibayar,
        tipe: AppConstants.cashFlowMasuk,
        referensi: AppConstants.cashFlowRefMotorCost,
        referensiId: biayaId,
        keterangan: 'Rollback hapus biaya ${biaya.kategori}',
      );
      if (biaya.biayaAdminTransfer > 0) {
        await saldoRepo.mutasiBank(
          nominal: biaya.biayaAdminTransfer,
          tipe: AppConstants.cashFlowMasuk,
          referensi: AppConstants.cashFlowRefAdminTransfer,
          referensiId: biayaId,
          keterangan: 'Rollback hapus admin transfer biaya ${biaya.kategori}',
        );
      }

      await txn.delete('motor_cost', where: 'id = ?', whereArgs: [biayaId]);

      final motorBaru = motorLama.copyWith(
        totalModal: motorLama.totalModal - biaya.nominal,
        cashDibayar: motorLama.cashDibayar - biaya.cashDibayar,
        transferDibayar: motorLama.transferDibayar - biaya.transferDibayar,
        updatedAt: DateTime.now(),
      );
      await txn.update('motor', motorBaru.toMap(),
          where: 'id = ?', whereArgs: [motorLama.id]);

      await auditLog.catatDelete(
        'motor_cost',
        biayaId,
        jsonEncode(biaya.toMap()),
        keterangan:
            'Hapus biaya ${biaya.kategori} — saldo dikembalikan, modal ${motorBaru.kodeMotor} dihitung ulang',
      );

      return motorBaru;
    });
  }

  Future<MotorModel?> getById(int id) async {
    final result = await db.query('motor', where: 'id = ?', whereArgs: [id]);
    if (result.isEmpty) return null;
    return MotorModel.fromMap(result.first);
  }

  Future<List<MotorModel>> getAll({String? status, String? searchQuery}) async {
    final whereClauses = <String>[];
    final whereArgs = <Object?>[];

    if (status != null) {
      whereClauses.add('status = ?');
      whereArgs.add(status);
    }
    if (searchQuery != null && searchQuery.isNotEmpty) {
      whereClauses.add(
          '(kode_motor LIKE ? OR merk LIKE ? OR tipe LIKE ? OR plat_nomor LIKE ?)');
      final like = '%$searchQuery%';
      whereArgs.addAll([like, like, like, like]);
    }

    final result = await db.query(
      'motor',
      where: whereClauses.isEmpty ? null : whereClauses.join(' AND '),
      whereArgs: whereArgs.isEmpty ? null : whereArgs,
      orderBy: 'tanggal_masuk DESC',
    );
    return result.map((e) => MotorModel.fromMap(e)).toList();
  }

  Future<List<MotorModel>> getStokTersedia() =>
      getAll(status: AppConstants.statusMotorTersedia);

  Future<List<MotorCostModel>> getRiwayatBiaya(int motorId) async {
    final result = await db.query(
      'motor_cost',
      where: 'motor_id = ?',
      whereArgs: [motorId],
      orderBy: 'tanggal ASC',
    );
    return result.map((e) => MotorCostModel.fromMap(e)).toList();
  }

  /// Total nilai aset stok motor yang belum terjual (dipakai Dashboard).
  Future<double> getTotalNilaiStok() async {
    final result = await db.rawQuery(
      'SELECT COALESCE(SUM(total_modal), 0) as total FROM motor WHERE status = ?',
      [AppConstants.statusMotorTersedia],
    );
    return (result.first['total'] as num).toDouble();
  }

  /// Update data motor (Merk/Tipe/Tahun/Plat/Status/dll). TIDAK
  /// mengubah saldo — untuk koreksi harga beli/metode pembayaran pakai
  /// [editPembelian]. Status boleh diganti bebas (mis. salah input
  /// Tersedia<->Terjual) TANPA mengubah saldo dari sini; penjualan yang
  /// mempengaruhi saldo hanya lewat PenjualanRepository.
  Future<MotorModel> updateMotor(MotorModel motor) async {
    requireWriteAccess();
    final motorLama = await getById(motor.id!);
    final updated = motor.copyWith(updatedAt: DateTime.now());
    await db.update('motor', updated.toMap(),
        where: 'id = ?', whereArgs: [motor.id]);
    final auditLog = AuditLogRepository(db);
    await auditLog.catatUpdate(
      'motor',
      motor.id!,
      jsonEncode(motorLama?.toMap()),
      jsonEncode(updated.toMap()),
    );
    return updated;
  }

  /// Edit data PEMBELIAN motor (harga beli & metode pembayaran). Efek
  /// kas lama dibalik dulu, lalu efek baru diterapkan — total_modal ikut
  /// disesuaikan (total_modal lama - hargaBeli lama + hargaBeli baru).
  /// Hanya boleh untuk motor yang BELUM terjual.
  Future<MotorModel> editPembelian({
    required int motorId,
    required double hargaBeliBaru,
    required String metodePembayaranBaru,
    double cashDibayarBaru = 0,
    double transferDibayarBaru = 0,
    String? jenisTransferBaru,
  }) async {
    requireWriteAccess();
    return db.transaction<MotorModel>((txn) async {
      final motorResult =
          await txn.query('motor', where: 'id = ?', whereArgs: [motorId]);
      if (motorResult.isEmpty) {
        throw ArgumentError('Motor tidak ditemukan');
      }
      final motorLama = MotorModel.fromMap(motorResult.first);
      if (motorLama.isTerjual) {
        throw StateError(
            'Motor sudah terjual — batalkan penjualannya dulu sebelum edit pembelian.');
      }

      final saldoRepo = SaldoRepository(txn);
      final auditLog = AuditLogRepository(txn);

      // Balikkan efek kas pembelian lama sepenuhnya, termasuk biaya
      // admin transfer lama jika ada.
      await saldoRepo.bayarCampuran(
        cash: motorLama.cashDibayar,
        transfer: motorLama.transferDibayar,
        tipe: AppConstants.cashFlowMasuk,
        referensi: AppConstants.cashFlowRefMotorBeli,
        referensiId: motorId,
        keterangan: 'Koreksi pembelian ${motorLama.kodeMotor} (nilai lama dibatalkan)',
      );
      if (motorLama.biayaAdminTransfer > 0) {
        await saldoRepo.mutasiBank(
          nominal: motorLama.biayaAdminTransfer,
          tipe: AppConstants.cashFlowMasuk,
          referensi: AppConstants.cashFlowRefAdminTransfer,
          referensiId: motorId,
          keterangan: 'Koreksi admin transfer pembelian (nilai lama dibatalkan)',
        );
      }

      final totalModalBaru =
          motorLama.totalModal - motorLama.hargaBeli + hargaBeliBaru;

      double cash;
      double transfer;
      switch (metodePembayaranBaru) {
        case AppConstants.metodeTransfer:
          cash = 0;
          transfer = totalModalBaru;
          break;
        case AppConstants.metodeCampuran:
          _validasiSplitPembayaran(metodePembayaranBaru, cashDibayarBaru,
              transferDibayarBaru, totalModalBaru);
          cash = cashDibayarBaru;
          transfer = transferDibayarBaru;
          break;
        case AppConstants.metodeCash:
        default:
          cash = totalModalBaru;
          transfer = 0;
      }

      final motorBaru = motorLama.copyWith(
        hargaBeli: hargaBeliBaru,
        totalModal: totalModalBaru,
        metodePembayaran: metodePembayaranBaru,
        cashDibayar: cash,
        transferDibayar: transfer,
        jenisTransfer: transfer > 0 ? jenisTransferBaru : null,
        biayaAdminTransfer: 0,
        updatedAt: DateTime.now(),
      );
      await txn.update('motor', motorBaru.toMap(),
          where: 'id = ?', whereArgs: [motorId]);
      await auditLog.catatUpdate(
        'motor',
        motorId,
        jsonEncode(motorLama.toMap()),
        jsonEncode(motorBaru.toMap()),
        keterangan: 'Edit pembelian ${motorLama.kodeMotor}',
      );

      final biayaAdminBaru = await saldoRepo.bayarCampuran(
        cash: cash,
        transfer: transfer,
        tipe: AppConstants.cashFlowKeluar,
        referensi: AppConstants.cashFlowRefMotorBeli,
        referensiId: motorId,
        keterangan: 'Pembelian unit ${motorBaru.kodeMotor} (setelah edit)',
        jenisTransfer: jenisTransferBaru,
      );
      var hasilAkhir = motorBaru;
      if (biayaAdminBaru > 0) {
        hasilAkhir = motorBaru.copyWith(biayaAdminTransfer: biayaAdminBaru);
        await txn.update('motor', hasilAkhir.toMap(),
            where: 'id = ?', whereArgs: [motorId]);
      }

      return hasilAkhir;
    });
  }

  /// Edit HANYA tanggal masuk/pembelian motor (tanpa mengubah nominal/modal).
  /// Bagian dari V3.1 patch #3 — semua transaksi bisa dikoreksi tanggalnya.
  Future<void> editTanggalMasuk(int motorId, DateTime tanggalBaru) async {
    requireWriteAccess();
    return db.transaction<void>((txn) async {
      final motorResult =
          await txn.query('motor', where: 'id = ?', whereArgs: [motorId]);
      if (motorResult.isEmpty) throw ArgumentError('Motor tidak ditemukan');
      final lama = MotorModel.fromMap(motorResult.first);
      final auditLog = AuditLogRepository(txn);

      await txn.update(
        'motor',
        {
          'tanggal_masuk': tanggalBaru.toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [motorId],
      );
      await auditLog.catatUpdate(
        'motor',
        motorId,
        jsonEncode({'tanggal_masuk': lama.tanggalMasuk.toIso8601String()}),
        jsonEncode({'tanggal_masuk': tanggalBaru.toIso8601String()}),
        keterangan: 'Mengubah tanggal pembelian ${lama.kodeMotor}: dari '
            '${lama.tanggalMasuk.toIso8601String().split("T").first} menjadi '
            '${tanggalBaru.toIso8601String().split("T").first}',
      );
    });
  }

  /// Edit HANYA tanggal salah satu biaya tambahan motor (motor_cost).
  Future<void> editTanggalBiaya(int biayaId, DateTime tanggalBaru) async {
    requireWriteAccess();
    return db.transaction<void>((txn) async {
      final result = await txn
          .query('motor_cost', where: 'id = ?', whereArgs: [biayaId]);
      if (result.isEmpty) throw ArgumentError('Biaya tidak ditemukan');
      final lama = result.first;
      final auditLog = AuditLogRepository(txn);

      await txn.update(
        'motor_cost',
        {'tanggal': tanggalBaru.toIso8601String()},
        where: 'id = ?',
        whereArgs: [biayaId],
      );
      await auditLog.catatUpdate(
        'motor_cost',
        biayaId,
        jsonEncode({'tanggal': lama['tanggal']}),
        jsonEncode({'tanggal': tanggalBaru.toIso8601String()}),
        keterangan: 'Mengubah tanggal biaya tambahan motor',
      );
    });
  }

  /// HAPUS motor (Sistem Hapus Transaksi, poin #5). Rollback penuh:
  /// - Jika motor sudah TERJUAL, penjualannya ikut dihapus dulu
  ///   (rollback laba, cash/bank penjualan, dan pemasukan otomatis).
  /// - Seluruh motor_cost dihapus & cash/bank biayanya dikembalikan.
  /// - Cash/bank pembelian dikembalikan.
  /// - Baris motor dihapus permanen.
  Future<void> hapusMotor(int motorId) async {
    requireWriteAccess();
    return db.transaction<void>((txn) async {
      final motorResult =
          await txn.query('motor', where: 'id = ?', whereArgs: [motorId]);
      if (motorResult.isEmpty) return;
      final motor = MotorModel.fromMap(motorResult.first);

      final saldoRepo = SaldoRepository(txn);
      final auditLog = AuditLogRepository(txn);

      // 1) Jika sudah terjual, rollback penjualannya dulu.
      final penjualanResult = await txn
          .query('penjualan', where: 'motor_id = ?', whereArgs: [motorId]);
      if (penjualanResult.isNotEmpty) {
        final penjualan = PenjualanModel.fromMap(penjualanResult.first);
        await saldoRepo.bayarCampuran(
          cash: penjualan.cashDiterima,
          transfer: penjualan.transferDiterima,
          tipe: AppConstants.cashFlowKeluar,
          referensi: AppConstants.cashFlowRefPenjualan,
          referensiId: penjualan.id,
          keterangan:
              'Rollback hapus motor ${motor.kodeMotor} (penjualan ikut dihapus)',
        );
        // Hapus pemasukan otomatis dari penjualan tsb.
        await txn.delete('pemasukan',
            where: 'kategori = ? AND referensi_id = ?',
            whereArgs: ['Penjualan Motor', penjualan.id]);
        await txn.delete('penjualan', where: 'id = ?', whereArgs: [penjualan.id]);
        await auditLog.catatDelete(
          'penjualan',
          penjualan.id!,
          jsonEncode(penjualan.toMap()),
          keterangan: 'Ikut terhapus karena motor ${motor.kodeMotor} dihapus',
        );
      }

      // 2) Hapus semua baris motor_cost (biaya). TIDAK perlu rollback
      // NOMINAL kas terpisah di sini — motor.cashDibayar/transferDibayar
      // (yang di-rollback di langkah 3) sudah mencakup SELURUH biaya
      // secara kumulatif (setiap tambahBiaya/editBiaya selalu menambah
      // field ini), jadi rollback nominal terpisah di sini akan
      // mengembalikan saldo dua kali (bug lama yang diperbaiki di V3).
      //
      // TAPI biaya_admin_transfer TIDAK kumulatif di tabel motor (motor
      // hanya menyimpan fee dari tambahMotor/editPembelian) — fee dari
      // setiap tambahBiaya tersimpan terpisah per baris motor_cost. Jadi
      // WAJIB dijumlah dulu sebelum baris-barisnya dihapus, supaya ikut
      // dikembalikan ke saldo bank (V4.2.3 fix).
      final biayaCostRows = await txn.query('motor_cost',
          where: 'motor_id = ?', whereArgs: [motorId]);
      double totalFeeMotorCost = 0;
      for (final row in biayaCostRows) {
        totalFeeMotorCost +=
            (row['biaya_admin_transfer'] as num?)?.toDouble() ?? 0;
      }
      await txn.delete('motor_cost', where: 'motor_id = ?', whereArgs: [motorId]);

      // 3) Rollback TOTAL pembayaran motor (pembelian awal + seluruh
      // biaya kumulatif — motor.cashDibayar/transferDibayar selalu
      // sinkron dengan total_modal, lihat catatan langkah 2 di atas).
      await saldoRepo.bayarCampuran(
        cash: motor.cashDibayar,
        transfer: motor.transferDibayar,
        tipe: AppConstants.cashFlowMasuk,
        referensi: AppConstants.cashFlowRefMotorBeli,
        referensiId: motorId,
        keterangan: 'Rollback hapus motor ${motor.kodeMotor}',
      );

      final totalFeeDikembalikan = motor.biayaAdminTransfer + totalFeeMotorCost;
      if (totalFeeDikembalikan > 0) {
        await saldoRepo.mutasiBank(
          nominal: totalFeeDikembalikan,
          tipe: AppConstants.cashFlowMasuk,
          referensi: AppConstants.cashFlowRefAdminTransfer,
          referensiId: motorId,
          keterangan: 'Rollback hapus admin transfer motor ${motor.kodeMotor}',
        );
      }

      // 4) Hapus motor.
      await txn.delete('motor', where: 'id = ?', whereArgs: [motorId]);
      await auditLog.catatDelete(
        'motor',
        motorId,
        jsonEncode(motor.toMap()),
        keterangan:
            'Hapus motor ${motor.kodeMotor} — saldo & stok dikembalikan',
      );
    });
  }

  /// Update status motor jadi TERJUAL. Dipanggil oleh PenjualanRepository
  /// di dalam transaction yang sama, bukan dipanggil langsung dari UI.
  Future<void> tandaiTerjual(DatabaseExecutor txn, int motorId) async {
    requireWriteAccess();
    await txn.update(
      'motor',
      {
        'status': AppConstants.statusMotorTerjual,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [motorId],
    );
  }
}

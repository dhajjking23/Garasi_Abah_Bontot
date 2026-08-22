import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../core/constants/app_constants.dart';
import '../core/payment/transfer_fee_calculator.dart';
import '../models/saldo_model.dart';
import '../models/cash_flow_model.dart';
import '../models/modal_history_model.dart';
import '../models/mutasi_antar_saldo_model.dart';
import 'audit_log_repository.dart';
import '../core/security/write_guard.dart';

/// Mengelola saldo cash & bank (singleton row) beserta histori cash_flow,
/// dan Modal usaha (modal_cash & modal_bank) beserta modal_history.
///
/// Semua transaksi yang mempengaruhi kas HARUS lewat repository ini supaya
/// saldo selalu konsisten dan setiap mutasi tercatat di cash_flow /
/// modal_history. Operasi majemuk (deposit ke bank, tarik tunai) dibungkus
/// db.transaction agar atomik.
class SaldoRepository {
  final DatabaseExecutor db;

  SaldoRepository(this.db);

  /// Ambil saldo saat ini. Ini method BACA (read-only) — sengaja TIDAK
  /// memanggil requireWriteAccess() supaya akun VIEWER/Partner tetap bisa
  /// melihat Dashboard & laporan. Guard tulis tetap ada di setiap method
  /// yang benar-benar mengubah data (_updateSaldo, mutasiCash, mutasiBank,
  /// dll di bawah), jadi VIEWER tetap tidak bisa menulis apapun.
  Future<SaldoModel> getSaldo() async {
    final result = await db.query('saldo', where: 'id = 1', limit: 1);
    if (result.isEmpty) {
      // Fallback jika baris singleton belum ada (seharusnya sudah di-seed)
      final now = DateTime.now();
      final saldo = SaldoModel(
        cash: 0,
        saldoBank: 0,
        modalCash: 0,
        modalBank: 0,
        updatedAt: now,
      );
      await db.insert('saldo', saldo.toMap());
      return saldo;
    }
    return SaldoModel.fromMap(result.first);
  }

  Future<void> _updateSaldo(SaldoModel saldo) async {
    requireWriteAccess();
    await db.update(
      'saldo',
      saldo.toMap(),
      where: 'id = 1',
    );
  }

  /// Helper generik untuk transaksi dengan metode CASH/TRANSFER/CAMPURAN
  /// (dipakai oleh Motor, Penjualan, Dana Talang, Pengeluaran). Bagian
  /// cash & transfer masing-masing dimutasi lewat mutasiCash/mutasiBank
  /// sehingga tetap tercatat terpisah di riwayat Cash dan Saldo Bank.
  /// Bayar/terima memakai gabungan Cash + Transfer (PAYMENT GLOBAL,
  /// V4.2.1). Jika [tipe] KELUAR dan porsi transfer > 0 serta
  /// [jenisTransfer] diisi, biaya admin transfer OTOMATIS ikut memotong
  /// saldo bank (mutasi cash_flow terpisah, referensi ADMINISTRASI_BANK)
  /// — supaya SEMUA transaksi keluar via transfer (bukan cuma menu
  /// Pengeluaran) ikut kena potongan biaya transfer yang benar.
  ///
  /// Return nilai biaya admin yang dipotong (0 jika tidak ada), supaya
  /// caller bisa menyimpannya di tabel masing-masing untuk laporan &
  /// keperluan rollback (edit/hapus) yang akurat.
  Future<double> bayarCampuran({
    required double cash,
    required double transfer,
    required String tipe, // MASUK / KELUAR
    required String referensi,
    int? referensiId,
    String? keterangan,
    DateTime? tanggal,
    String? jenisTransfer,
  }) async {
    if (cash > 0) {
      await mutasiCash(
        nominal: cash,
        tipe: tipe,
        referensi: referensi,
        referensiId: referensiId,
        keterangan: keterangan,
        tanggal: tanggal,
      );
    }
    double biayaAdmin = 0;
    if (transfer > 0) {
      await mutasiBank(
        nominal: transfer,
        tipe: tipe,
        referensi: referensi,
        referensiId: referensiId,
        keterangan: keterangan,
        tanggal: tanggal,
      );
      if (tipe == AppConstants.cashFlowKeluar && jenisTransfer != null) {
        biayaAdmin = TransferFeeCalculator.hitung(jenisTransfer);
        if (biayaAdmin > 0) {
          await mutasiBank(
            nominal: biayaAdmin,
            tipe: AppConstants.cashFlowKeluar,
            referensi: AppConstants.cashFlowRefAdminTransfer,
            referensiId: referensiId,
            keterangan: 'Admin transfer - ${keterangan ?? referensi}',
            tanggal: tanggal,
          );
        }
      }
    }
    return biayaAdmin;
  }

  // ==========================================================
  // CASH & BANK (saldo operasional)
  // ==========================================================

  /// Menambah/mengurangi CASH, mencatat cash_flow (sumber=CASH), dan
  /// mengembalikan saldo terbaru. `nominal` selalu positif; arah
  /// ditentukan oleh `tipe`.
  Future<SaldoModel> mutasiCash({
    required double nominal,
    required String tipe, // MASUK / KELUAR
    required String referensi,
    int? referensiId,
    String? keterangan,
    DateTime? tanggal,
  }) async {
    requireWriteAccess();
    final saldoSekarang = await getSaldo();
    final delta = tipe == AppConstants.cashFlowMasuk ? nominal : -nominal;
    final saldoBaru = saldoSekarang.copyWith(
      cash: saldoSekarang.cash + delta,
      updatedAt: DateTime.now(),
    );
    await _updateSaldo(saldoBaru);

    final cashFlow = CashFlowModel(
      tanggal: tanggal ?? DateTime.now(),
      tipe: tipe,
      sumber: AppConstants.sumberCash,
      nominal: nominal,
      referensi: referensi,
      referensiId: referensiId,
      keterangan: keterangan,
      saldoSetelah: saldoBaru.cash,
      createdAt: DateTime.now(),
    );
    await db.insert('cash_flow', cashFlow.toMap());

    return saldoBaru;
  }

  /// Menambah/mengurangi SALDO BANK, mencatat cash_flow (sumber=BANK).
  Future<SaldoModel> mutasiBank({
    required double nominal,
    required String tipe, // MASUK / KELUAR
    required String referensi,
    int? referensiId,
    String? keterangan,
    DateTime? tanggal,
  }) async {
    requireWriteAccess();
    final saldoSekarang = await getSaldo();
    final delta = tipe == AppConstants.cashFlowMasuk ? nominal : -nominal;
    final saldoBaru = saldoSekarang.copyWith(
      saldoBank: saldoSekarang.saldoBank + delta,
      updatedAt: DateTime.now(),
    );
    await _updateSaldo(saldoBaru);

    final cashFlow = CashFlowModel(
      tanggal: tanggal ?? DateTime.now(),
      tipe: tipe,
      sumber: AppConstants.sumberBank,
      nominal: nominal,
      referensi: referensi,
      referensiId: referensiId,
      keterangan: keterangan,
      saldoSetelah: saldoBaru.saldoBank,
      createdAt: DateTime.now(),
    );
    await db.insert('cash_flow', cashFlow.toMap());

    return saldoBaru;
  }

  /// Set CASH langsung ke nilai baru (koreksi manual), dicatat sebagai
  /// PENYESUAIAN_SALDO di cash_flow + audit_log agar tetap terlacak.
  Future<SaldoModel> editCash(double nominalBaru, {String? keterangan}) async {
    final saldoSekarang = await getSaldo();
    final selisih = nominalBaru - saldoSekarang.cash;
    if (selisih == 0) return saldoSekarang;

    final auditLog = AuditLogRepository(db);
    final saldoBaru = await mutasiCash(
      nominal: selisih.abs(),
      tipe:
          selisih > 0 ? AppConstants.cashFlowMasuk : AppConstants.cashFlowKeluar,
      referensi: AppConstants.cashFlowRefAdjustment,
      keterangan: keterangan ?? 'Edit Cash manual',
    );
    await auditLog.catatUpdate(
      'saldo',
      1,
      jsonEncode({'cash': saldoSekarang.cash}),
      jsonEncode({'cash': saldoBaru.cash}),
      keterangan: keterangan ?? 'Edit Cash manual',
    );
    return saldoBaru;
  }

  /// Set SALDO BANK langsung ke nilai baru (koreksi manual).
  Future<SaldoModel> editSaldoBank(double nominalBaru,
      {String? keterangan}) async {
    final saldoSekarang = await getSaldo();
    final selisih = nominalBaru - saldoSekarang.saldoBank;
    if (selisih == 0) return saldoSekarang;

    final auditLog = AuditLogRepository(db);
    final saldoBaru = await mutasiBank(
      nominal: selisih.abs(),
      tipe:
          selisih > 0 ? AppConstants.cashFlowMasuk : AppConstants.cashFlowKeluar,
      referensi: AppConstants.cashFlowRefAdjustment,
      keterangan: keterangan ?? 'Edit Saldo Bank manual',
    );
    await auditLog.catatUpdate(
      'saldo',
      1,
      jsonEncode({'saldo_bank': saldoSekarang.saldoBank}),
      jsonEncode({'saldo_bank': saldoBaru.saldoBank}),
      keterangan: keterangan ?? 'Edit Saldo Bank manual',
    );
    return saldoBaru;
  }

  /// DEPOSIT CASH → BANK. Cash berkurang, Saldo Bank bertambah, tercatat
  /// sebagai satu baris di `mutasi_antar_saldo` (bisa diedit/dihapus).
  Future<SaldoModel> depositCashKeBank(double nominal,
      {String? keterangan, DateTime? tanggal}) async {
    if (nominal <= 0) {
      throw ArgumentError('Nominal deposit harus lebih dari 0');
    }
    final saldoSekarang = await getSaldo();
    if (nominal > saldoSekarang.cash) {
      throw StateError('Cash tidak mencukupi untuk deposit ini');
    }
    return _catatMutasiAntarSaldo(
      jenis: AppConstants.cashFlowRefDepositBank,
      nominal: nominal,
      keterangan: keterangan,
      tanggal: tanggal,
    );
  }

  /// TARIK TUNAI. Saldo Bank berkurang, Cash bertambah, tercatat sebagai
  /// satu baris di `mutasi_antar_saldo` (bisa diedit/dihapus).
  Future<SaldoModel> tarikTunai(double nominal,
      {String? keterangan, DateTime? tanggal}) async {
    if (nominal <= 0) {
      throw ArgumentError('Nominal tarik tunai harus lebih dari 0');
    }
    final saldoSekarang = await getSaldo();
    if (nominal > saldoSekarang.saldoBank) {
      throw StateError('Saldo Bank tidak mencukupi untuk penarikan ini');
    }
    return _catatMutasiAntarSaldo(
      jenis: AppConstants.cashFlowRefTarikTunai,
      nominal: nominal,
      keterangan: keterangan,
      tanggal: tanggal,
    );
  }

  Future<SaldoModel> _catatMutasiAntarSaldo({
    required String jenis, // DEPOSIT_KE_BANK / TARIK_TUNAI
    required double nominal,
    String? keterangan,
    DateTime? tanggal,
  }) async {
    requireWriteAccess();
    final now = DateTime.now();
    final row = MutasiAntarSaldoModel(
      tanggal: tanggal ?? now,
      jenis: jenis,
      nominal: nominal,
      keterangan: keterangan,
      createdAt: now,
      updatedAt: now,
    );
    final id = await db.insert('mutasi_antar_saldo', row.toMap());
    return _terapkanMutasiAntarSaldo(
      jenis: jenis,
      nominal: nominal,
      id: id,
      keterangan: keterangan ??
          (jenis == AppConstants.cashFlowRefDepositBank
              ? 'Deposit cash ke bank'
              : 'Tarik tunai dari bank'),
      tanggal: tanggal,
      balik: false,
    );
  }

  /// Menerapkan efek kas satu baris mutasi_antar_saldo. [balik]=true
  /// berarti membalikkan arah (dipakai saat rollback/hapus/edit).
  Future<SaldoModel> _terapkanMutasiAntarSaldo({
    required String jenis,
    required double nominal,
    required int id,
    String? keterangan,
    DateTime? tanggal,
    required bool balik,
  }) async {
    final isDeposit = jenis == AppConstants.cashFlowRefDepositBank;
    // Deposit (normal): Cash keluar, Bank masuk. Tarik (normal): Bank
    // keluar, Cash masuk. Saat balik=true, arahnya dibalik.
    final cashKeluar = isDeposit ? !balik : balik;
    await mutasiCash(
      nominal: nominal,
      tipe: cashKeluar ? AppConstants.cashFlowKeluar : AppConstants.cashFlowMasuk,
      referensi: jenis,
      referensiId: id,
      keterangan: keterangan,
      tanggal: tanggal,
    );
    final saldoBaru = await mutasiBank(
      nominal: nominal,
      tipe: cashKeluar ? AppConstants.cashFlowMasuk : AppConstants.cashFlowKeluar,
      referensi: jenis,
      referensiId: id,
      keterangan: keterangan,
      tanggal: tanggal,
    );
    return saldoBaru;
  }

  /// Edit nominal/keterangan Deposit atau Tarik Tunai. Efek kas lama
  /// dibalik dulu, lalu efek baru diterapkan (rollback otomatis).
  Future<SaldoModel> editMutasiAntarSaldo({
    required int id,
    required double nominalBaru,
    String? keteranganBaru,
  }) async {
    requireWriteAccess();
    final result = await db
        .query('mutasi_antar_saldo', where: 'id = ?', whereArgs: [id], limit: 1);
    if (result.isEmpty) {
      throw ArgumentError('Transaksi tidak ditemukan');
    }
    final lama = MutasiAntarSaldoModel.fromMap(result.first);

    // Validasi kecukupan saldo untuk nominal baru sebelum diterapkan
    final saldoSekarang = await getSaldo();
    final isDeposit = lama.jenis == AppConstants.cashFlowRefDepositBank;
    if (isDeposit) {
      final cashSetelahBalik = saldoSekarang.cash + lama.nominal;
      if (nominalBaru > cashSetelahBalik) {
        throw StateError('Cash tidak mencukupi untuk nominal deposit baru');
      }
    } else {
      final bankSetelahBalik = saldoSekarang.saldoBank + lama.nominal;
      if (nominalBaru > bankSetelahBalik) {
        throw StateError('Saldo Bank tidak mencukupi untuk nominal tarik baru');
      }
    }

    // Balikkan efek lama
    await _terapkanMutasiAntarSaldo(
      jenis: lama.jenis,
      nominal: lama.nominal,
      id: id,
      keterangan: 'Koreksi (nilai lama dibatalkan)',
      balik: true,
    );

    final baru = lama.copyWith(
      nominal: nominalBaru,
      keterangan: keteranganBaru ?? lama.keterangan,
      updatedAt: DateTime.now(),
    );
    await db.update('mutasi_antar_saldo', baru.toMap(),
        where: 'id = ?', whereArgs: [id]);

    final auditLog = AuditLogRepository(db);
    await auditLog.catatUpdate(
      'mutasi_antar_saldo',
      id,
      jsonEncode(lama.toMap()),
      jsonEncode(baru.toMap()),
      keterangan: 'Edit ${lama.jenis}',
    );

    return _terapkanMutasiAntarSaldo(
      jenis: baru.jenis,
      nominal: baru.nominal,
      id: id,
      keterangan: baru.keterangan,
      tanggal: baru.tanggal,
      balik: false,
    );
  }

  /// Hapus Deposit/Tarik Tunai — saldo Cash & Bank dikembalikan seperti
  /// sebelum transaksi terjadi (rollback penuh dua sisi).
  Future<void> hapusMutasiAntarSaldo(int id) async {
    requireWriteAccess();
    final result = await db
        .query('mutasi_antar_saldo', where: 'id = ?', whereArgs: [id], limit: 1);
    if (result.isEmpty) return;
    final row = MutasiAntarSaldoModel.fromMap(result.first);

    await _terapkanMutasiAntarSaldo(
      jenis: row.jenis,
      nominal: row.nominal,
      id: id,
      keterangan: 'Rollback hapus ${row.jenis}',
      balik: true,
    );
    await db.delete('mutasi_antar_saldo', where: 'id = ?', whereArgs: [id]);

    final auditLog = AuditLogRepository(db);
    await auditLog.catatDelete(
      'mutasi_antar_saldo',
      id,
      jsonEncode(row.toMap()),
      keterangan:
          'Hapus ${row.jenis == AppConstants.cashFlowRefDepositBank ? "Deposit ke Bank" : "Tarik Tunai"} '
          '- saldo dikembalikan',
    );
  }

  Future<List<MutasiAntarSaldoModel>> getRiwayatMutasiAntarSaldo() async {
    final result =
        await db.query('mutasi_antar_saldo', orderBy: 'tanggal DESC, id DESC');
    return result.map((e) => MutasiAntarSaldoModel.fromMap(e)).toList();
  }

  Future<List<CashFlowModel>> getHistoriCashFlow({
    String? sumber, // CASH / BANK / null (semua)
    DateTime? dari,
    DateTime? sampai,
  }) async {
    final whereClauses = <String>[];
    final whereArgs = <Object?>[];
    if (sumber != null) {
      whereClauses.add('sumber = ?');
      whereArgs.add(sumber);
    }
    if (dari != null && sampai != null) {
      whereClauses.add('tanggal BETWEEN ? AND ?');
      whereArgs.add(dari.toIso8601String());
      whereArgs.add(sampai.toIso8601String());
    }
    final result = await db.query(
      'cash_flow',
      where: whereClauses.isEmpty ? null : whereClauses.join(' AND '),
      whereArgs: whereArgs.isEmpty ? null : whereArgs,
      orderBy: 'tanggal DESC, id DESC',
    );
    return result.map((e) => CashFlowModel.fromMap(e)).toList();
  }

  // ==========================================================
  // MODAL (modal_cash & modal_bank) — capital record usaha,
  // terpisah dari saldo operasional Cash / Saldo Bank.
  // ==========================================================

  Future<void> _catatModalHistory({
    required String jenis,
    required String aksi,
    required double nominal,
    required double saldoSebelum,
    required double saldoSesudah,
    String? keterangan,
    DateTime? tanggal,
  }) async {
    requireWriteAccess();
    final history = ModalHistoryModel(
      tanggal: tanggal ?? DateTime.now(),
      jenis: jenis,
      aksi: aksi,
      nominal: nominal,
      saldoSebelum: saldoSebelum,
      saldoSesudah: saldoSesudah,
      keterangan: keterangan,
      createdAt: DateTime.now(),
    );
    await db.insert('modal_history', history.toMap());
  }

  /// Tambah Modal (dipakai juga dari PemasukanRepository kategori
  /// 'Tambah Modal'). Menambah Modal Cash SEKALIGUS Cash operasional,
  /// karena modal yang masuk secara fisik berupa uang cash.
  Future<SaldoModel> tambahModal(double nominal, {String? keterangan}) async {
    final saldoSekarang = await getSaldo();
    final saldoBaru = saldoSekarang.copyWith(
      modalCash: saldoSekarang.modalCash + nominal,
      updatedAt: DateTime.now(),
    );
    await _updateSaldo(saldoBaru);
    await _catatModalHistory(
      jenis: AppConstants.modalJenisCash,
      aksi: AppConstants.modalAksiTambah,
      nominal: nominal,
      saldoSebelum: saldoSekarang.modalCash,
      saldoSesudah: saldoBaru.modalCash,
      keterangan: keterangan ?? 'Tambah Modal',
    );
    return mutasiCash(
      nominal: nominal,
      tipe: AppConstants.cashFlowMasuk,
      referensi: AppConstants.cashFlowRefPemasukan,
      keterangan: keterangan ?? 'Tambah Modal',
    );
  }

  /// Tambah/kurangi Modal Cash atau Modal Bank secara mandiri (TIDAK
  /// mengubah saldo Cash/Bank operasional — murni catatan permodalan).
  Future<SaldoModel> ubahModal({
    required String jenis, // CASH / BANK
    required String aksi, // TAMBAH / KURANG
    required double nominal,
    String? keterangan,
  }) async {
    if (nominal <= 0) {
      throw ArgumentError('Nominal modal harus lebih dari 0');
    }
    final saldoSekarang = await getSaldo();
    final isCash = jenis == AppConstants.modalJenisCash;
    final saldoLama =
        isCash ? saldoSekarang.modalCash : saldoSekarang.modalBank;
    final delta = aksi == AppConstants.modalAksiTambah ? nominal : -nominal;
    final saldoBaruNilai = saldoLama + delta;
    if (saldoBaruNilai < 0) {
      throw StateError('Modal tidak boleh menjadi negatif');
    }

    final saldoBaru = saldoSekarang.copyWith(
      modalCash: isCash ? saldoBaruNilai : null,
      modalBank: !isCash ? saldoBaruNilai : null,
      updatedAt: DateTime.now(),
    );
    await _updateSaldo(saldoBaru);
    await _catatModalHistory(
      jenis: jenis,
      aksi: aksi,
      nominal: nominal,
      saldoSebelum: saldoLama,
      saldoSesudah: saldoBaruNilai,
      keterangan: keterangan,
    );
    return saldoBaru;
  }

  /// Edit Modal Cash/Bank langsung ke nilai baru (dicatat sebagai EDIT).
  Future<SaldoModel> editModal({
    required String jenis, // CASH / BANK
    required double nominalBaru,
    String? keterangan,
  }) async {
    if (nominalBaru < 0) {
      throw ArgumentError('Modal tidak boleh negatif');
    }
    final saldoSekarang = await getSaldo();
    final isCash = jenis == AppConstants.modalJenisCash;
    final saldoLama =
        isCash ? saldoSekarang.modalCash : saldoSekarang.modalBank;
    if (saldoLama == nominalBaru) return saldoSekarang;

    final saldoBaru = saldoSekarang.copyWith(
      modalCash: isCash ? nominalBaru : null,
      modalBank: !isCash ? nominalBaru : null,
      updatedAt: DateTime.now(),
    );
    await _updateSaldo(saldoBaru);
    await _catatModalHistory(
      jenis: jenis,
      aksi: AppConstants.modalAksiEdit,
      nominal: nominalBaru,
      saldoSebelum: saldoLama,
      saldoSesudah: nominalBaru,
      keterangan: keterangan ?? 'Edit Modal manual',
    );
    return saldoBaru;
  }

  /// Dipanggil PeriodeRepository saat periode baru dibuat dengan modal
  /// awal. Menambah Cash/Bank operasional SEKALIGUS Modal Cash/Bank
  /// (ledger permodalan) dengan nominal yang sama — karena modal awal
  /// pembukuan secara fisik berarti ada uang cash/saldo bank sejumlah
  /// itu di tangan saat periode dimulai. Ini yang menyambungkan input
  /// "Modal Awal" di form Buat Periode ke Dashboard (Cash/Saldo Bank
  /// tidak lagi tampil 0 padahal modal sudah diisi).
  Future<SaldoModel> suntikModalAwalPeriode({
    required double cash,
    required double bank,
    String? keterangan,
  }) async {
    if (cash > 0) {
      await mutasiCash(
        nominal: cash,
        tipe: AppConstants.cashFlowMasuk,
        referensi: AppConstants.cashFlowRefModalAwalPeriode,
        keterangan: keterangan ?? 'Modal awal periode (Cash)',
      );
      await ubahModal(
        jenis: AppConstants.modalJenisCash,
        aksi: AppConstants.modalAksiTambah,
        nominal: cash,
        keterangan: keterangan ?? 'Modal awal periode (Cash)',
      );
    }
    if (bank > 0) {
      await mutasiBank(
        nominal: bank,
        tipe: AppConstants.cashFlowMasuk,
        referensi: AppConstants.cashFlowRefModalAwalPeriode,
        keterangan: keterangan ?? 'Modal awal periode (Bank)',
      );
      await ubahModal(
        jenis: AppConstants.modalJenisBank,
        aksi: AppConstants.modalAksiTambah,
        nominal: bank,
        keterangan: keterangan ?? 'Modal awal periode (Bank)',
      );
    }
    return getSaldo();
  }

  Future<List<ModalHistoryModel>> getHistoriModal({String? jenis}) async {
    final result = await db.query(
      'modal_history',
      where: jenis != null ? 'jenis = ?' : null,
      whereArgs: jenis != null ? [jenis] : null,
      orderBy: 'tanggal DESC, id DESC',
    );
    return result.map((e) => ModalHistoryModel.fromMap(e)).toList();
  }
}

import 'package:sqflite/sqflite.dart';
import 'dart:convert';
import '../core/constants/app_constants.dart';
import '../models/dana_talang_model.dart';
import '../models/dana_talang_pembayaran_model.dart';
import 'audit_log_repository.dart';
import 'saldo_repository.dart';
import '../core/security/write_guard.dart';

/// Repository Dana Talang Partner.
///
/// KONSEP: Dana Talang BUKAN pengeluaran/pemasukan biasa.
/// - SAYA_MENALANGI (kita beri uang ke partner): cash/bank turun,
///   Piutang bertambah.
/// - SAYA_MENERIMA (partner beri uang ke kita): cash/bank naik,
///   Hutang bertambah.
/// Pembayaran kembali membalik arah kas dari transaksi awal dan
/// mengurangi piutang/hutang sampai status jadi LUNAS.
class DanaTalangRepository {
  final Database db;

  DanaTalangRepository(this.db);

  /// V5.9.1 — satu-satunya tempat status dana_talang dihitung, dipakai
  /// oleh [bayarKembali], [konversiKeModal], dan [editDanaTalang] supaya
  /// konsisten. Membedakan 3 hal (Spec Koreksi §7):
  ///   - lunas MURNI cash -> LUNAS
  ///   - lunas MURNI konversi -> DIKONVERSI_MODAL
  ///   - lunas CAMPURAN cash+konversi -> LUNAS (sudah selesai total;
  ///     rincian metode tetap terlihat di riwayat per baris)
  ///   - belum lunas tapi sudah ada konversi (belum ada cash sama
  ///     sekali) -> SEBAGIAN_DIKONVERSI
  ///   - belum lunas, ada cash (dengan/tanpa konversi) -> SEBAGIAN_LUNAS
  ///   - belum ada apa-apa -> BELUM_LUNAS
  String _hitungStatus({
    required double nominal,
    required double totalDibayarKembali,
    required double totalDikonversiModal,
  }) {
    final sisa = nominal - totalDibayarKembali - totalDikonversiModal;
    final adaCash = totalDibayarKembali > 0.5;
    final adaKonversi = totalDikonversiModal > 0.5;

    if (sisa <= 0.5) {
      if (adaKonversi && !adaCash) {
        return AppConstants.statusDanaTalangDikonversiModal;
      }
      return AppConstants.statusDanaTalangLunas;
    }
    if (adaKonversi && !adaCash) {
      return AppConstants.statusDanaTalangSebagianDikonversi;
    }
    if (adaCash || adaKonversi) {
      return AppConstants.statusDanaTalangSebagianLunas;
    }
    return AppConstants.statusDanaTalangBelumLunas;
  }

  void _validasiSplit(String metode, double cash, double transfer, double total) {
    if (metode == AppConstants.metodeCampuran) {
      final jumlah = cash + transfer;
      if ((jumlah - total).abs() > 0.5) {
        throw ArgumentError(
            'Cash + Transfer (Rp${jumlah.toStringAsFixed(0)}) harus sama dengan nominal (Rp${total.toStringAsFixed(0)})');
      }
    }
  }

  (double cash, double transfer) _hitungSplit(
      String metode, double cash, double transfer, double total) {
    switch (metode) {
      case AppConstants.metodeTransfer:
        return (0, total);
      case AppConstants.metodeCampuran:
        _validasiSplit(metode, cash, transfer, total);
        return (cash, transfer);
      case AppConstants.metodeCash:
      default:
        return (total, 0);
    }
  }

  /// Catat dana talang baru. [jenis] SAYA_MENALANGI atau SAYA_MENERIMA.
  /// [bentukTalangan] hanya relevan untuk SAYA_MENERIMA: TUNAI (partner
  /// benar-benar kasih cash/transfer -> Cash/Bank saya bertambah) atau
  /// NON_TUNAI (partner membayarkan sesuatu atas nama saya -> Cash/Bank
  /// saya TIDAK berubah, hanya hutang yang tercatat).
  Future<DanaTalangModel> tambahDanaTalang({
    required String namaPartner,
    required DateTime tanggal,
    required String jenis,
    required double nominal,
    String metodePembayaran = AppConstants.metodeCash,
    double cashDibayar = 0,
    double transferDibayar = 0,
    String? jenisTransfer,
    String bentukTalangan = AppConstants.bentukTalanganTunai,
    String? keterangan,
    int? periodeId,
  }) async {
    requireWriteAccess();
    return db.transaction<DanaTalangModel>((txn) async {
      final isMenalangi = jenis == AppConstants.danaTalangSayaMenalangi;
      // Non-tunai hanya berlaku untuk SAYA_MENERIMA. Untuk SAYA_MENALANGI
      // (atau jika bentuk TUNAI), tetap hitung split cash/transfer.
      final isNonTunai =
          !isMenalangi && bentukTalangan == AppConstants.bentukTalanganNonTunai;

      final (cash, transfer) = isNonTunai
          ? (0.0, 0.0)
          : _hitungSplit(metodePembayaran, cashDibayar, transferDibayar, nominal);

      final now = DateTime.now();
      var model = DanaTalangModel(
        namaPartner: namaPartner,
        tanggal: tanggal,
        jenis: jenis,
        nominal: nominal,
        metodePembayaran: isNonTunai ? AppConstants.metodeCash : metodePembayaran,
        cashTerpakai: cash,
        transferTerpakai: transfer,
        jenisTransfer: (isMenalangi && transfer > 0) ? jenisTransfer : null,
        bentukTalangan: isMenalangi ? AppConstants.bentukTalanganTunai : bentukTalangan,
        status: AppConstants.statusDanaTalangBelumLunas,
        totalDibayarKembali: 0,
        keterangan: keterangan,
        periodeId: periodeId,
        createdAt: now,
        updatedAt: now,
      );
      final id = await txn.insert('dana_talang', model.toMap());
      var saved = model.copyWith(id: id);

      final auditLog = AuditLogRepository(txn);
      await auditLog.catatCreate(
        'dana_talang',
        id,
        jsonEncode(saved.toMap()),
        keterangan:
            '${isMenalangi ? "Menalangi" : "Menerima talangan dari"} $namaPartner'
            '${isNonTunai ? " (non-tunai — dibayarkan atas nama saya)" : ""}',
      );

      // NON_TUNAI: tidak ada uang yang benar-benar masuk ke Cash/Bank
      // saya, jadi TIDAK dicatat sebagai mutasi kas — hanya hutangnya
      // yang tercatat di tabel dana_talang. Baru saat bayarKembali,
      // Cash/Bank saya akan berkurang seperti biasa.
      if (!isNonTunai) {
        final saldoRepo = SaldoRepository(txn);
        final biayaAdmin = await saldoRepo.bayarCampuran(
          cash: cash,
          transfer: transfer,
          tipe: isMenalangi ? AppConstants.cashFlowKeluar : AppConstants.cashFlowMasuk,
          referensi: isMenalangi
              ? AppConstants.cashFlowRefDanaTalangBeri
              : AppConstants.cashFlowRefDanaTalangTerima,
          referensiId: id,
          keterangan:
              '${isMenalangi ? "Dana talang ke" : "Dana talang dari"} $namaPartner',
          tanggal: tanggal,
          jenisTransfer: isMenalangi ? jenisTransfer : null,
        );
        if (biayaAdmin > 0) {
          saved = saved.copyWith(biayaAdminTransfer: biayaAdmin);
          await txn.update('dana_talang', saved.toMap(),
              where: 'id = ?', whereArgs: [id]);
        }
      }

      return saved;
    });
  }

  /// Edit dana talang. Nominal hanya boleh diubah jika BELUM ada
  /// pembayaran kembali (total_dibayar_kembali == 0) supaya rollback
  /// kas tetap sederhana & akurat.
  Future<DanaTalangModel> editDanaTalang({
    required int id,
    required String namaPartner,
    required DateTime tanggal,
    required double nominalBaru,
    String metodePembayaranBaru = AppConstants.metodeCash,
    double cashDibayarBaru = 0,
    double transferDibayarBaru = 0,
    String? jenisTransferBaru,
    String? keterangan,
  }) async {
    requireWriteAccess();
    return db.transaction<DanaTalangModel>((txn) async {
      final result =
          await txn.query('dana_talang', where: 'id = ?', whereArgs: [id]);
      if (result.isEmpty) throw ArgumentError('Dana talang tidak ditemukan');
      final lama = DanaTalangModel.fromMap(result.first);

      if (lama.status == AppConstants.statusDanaTalangBatal) {
        throw StateError('Dana talang yang sudah dibatalkan tidak bisa diedit.');
      }
      if ((lama.totalDibayarKembali > 0 || lama.totalDikonversiModal > 0) &&
          nominalBaru != lama.nominal) {
        throw StateError(
            'Nominal tidak bisa diubah karena sudah ada pembayaran kembali dan/atau konversi ke modal. Hapus riwayat pembayaran/konversi dulu.');
      }

      final saldoRepo = SaldoRepository(txn);
      final auditLog = AuditLogRepository(txn);
      final isMenalangi = lama.jenis == AppConstants.danaTalangSayaMenalangi;
      final isNonTunai = lama.isNonTunai;

      // Balik efek kas awal yang lama (no-op otomatis jika non-tunai,
      // karena cashTerpakai/transferTerpakai sudah 0 sejak awal), juga
      // balik biaya admin transfer lama jika ada.
      if (!isNonTunai) {
        await saldoRepo.bayarCampuran(
          cash: lama.cashTerpakai,
          transfer: lama.transferTerpakai,
          tipe: isMenalangi ? AppConstants.cashFlowMasuk : AppConstants.cashFlowKeluar,
          referensi: isMenalangi
              ? AppConstants.cashFlowRefDanaTalangBeri
              : AppConstants.cashFlowRefDanaTalangTerima,
          referensiId: id,
          keterangan: 'Koreksi dana talang $namaPartner (nilai lama dibatalkan)',
        );
        if (isMenalangi && lama.biayaAdminTransfer > 0) {
          await saldoRepo.mutasiBank(
            nominal: lama.biayaAdminTransfer,
            tipe: AppConstants.cashFlowMasuk,
            referensi: AppConstants.cashFlowRefAdminTransfer,
            referensiId: id,
            keterangan: 'Koreksi admin transfer dana talang (nilai lama dibatalkan)',
          );
        }
      }

      final (cash, transfer) = isNonTunai
          ? (0.0, 0.0)
          : _hitungSplit(
              metodePembayaranBaru, cashDibayarBaru, transferDibayarBaru, nominalBaru);

      var baru = lama.copyWith(
        namaPartner: namaPartner,
        tanggal: tanggal,
        nominal: nominalBaru,
        metodePembayaran: isNonTunai ? lama.metodePembayaran : metodePembayaranBaru,
        cashTerpakai: cash,
        transferTerpakai: transfer,
        jenisTransfer: (isMenalangi && transfer > 0) ? jenisTransferBaru : null,
        biayaAdminTransfer: 0,
        keterangan: keterangan,
        status: _hitungStatus(
          nominal: nominalBaru,
          totalDibayarKembali: lama.totalDibayarKembali,
          totalDikonversiModal: lama.totalDikonversiModal,
        ),
        updatedAt: DateTime.now(),
      );
      await txn.update('dana_talang', baru.toMap(),
          where: 'id = ?', whereArgs: [id]);
      await auditLog.catatUpdate(
        'dana_talang',
        id,
        jsonEncode(lama.toMap()),
        jsonEncode(baru.toMap()),
        keterangan: 'Edit dana talang $namaPartner',
      );

      if (!isNonTunai) {
        final biayaAdmin = await saldoRepo.bayarCampuran(
          cash: cash,
          transfer: transfer,
          tipe: isMenalangi ? AppConstants.cashFlowKeluar : AppConstants.cashFlowMasuk,
          referensi: isMenalangi
              ? AppConstants.cashFlowRefDanaTalangBeri
              : AppConstants.cashFlowRefDanaTalangTerima,
          referensiId: id,
          keterangan:
              '${isMenalangi ? "Dana talang ke" : "Dana talang dari"} $namaPartner (setelah edit)',
          tanggal: tanggal,
          jenisTransfer: isMenalangi ? jenisTransferBaru : null,
        );
        if (biayaAdmin > 0) {
          baru = baru.copyWith(biayaAdminTransfer: biayaAdmin);
          await txn.update('dana_talang', baru.toMap(),
              where: 'id = ?', whereArgs: [id]);
        }
      }

      return baru;
    });
  }

  /// Bayar kembali (cicilan/pelunasan). Untuk SAYA_MENALANGI, partner
  /// membayar kembali ke kita -> cash/bank kita bertambah. Untuk
  /// SAYA_MENERIMA, kita membayar kembali ke partner -> cash/bank kita
  /// berkurang.
  Future<DanaTalangModel> bayarKembali({
    required int danaTalangId,
    required DateTime tanggal,
    required double nominal,
    String metodePembayaran = AppConstants.metodeCash,
    double cashDibayar = 0,
    double transferDibayar = 0,
    String? jenisTransfer,
    String? keterangan,
  }) async {
    requireWriteAccess();
    return db.transaction<DanaTalangModel>((txn) => bayarKembaliInTxn(
          txn,
          danaTalangId: danaTalangId,
          tanggal: tanggal,
          nominal: nominal,
          metodePembayaran: metodePembayaran,
          cashDibayar: cashDibayar,
          transferDibayar: transferDibayar,
          jenisTransfer: jenisTransfer,
          keterangan: keterangan,
        ));
  }

  /// V5.9.2 — sama persis dengan [bayarKembali], TAPI menerima [txn] dari
  /// luar. Dipakai `GajihanRepository.prosesGajihan()` supaya pelunasan
  /// dana talang jadi bagian dari SATU transaction gabungan (all-or-nothing).
  Future<DanaTalangModel> bayarKembaliInTxn(
    DatabaseExecutor txn, {
    required int danaTalangId,
    required DateTime tanggal,
    required double nominal,
    String metodePembayaran = AppConstants.metodeCash,
    double cashDibayar = 0,
    double transferDibayar = 0,
    String? jenisTransfer,
    String? keterangan,
  }) async {
    requireWriteAccess();
    final result = await txn
        .query('dana_talang', where: 'id = ?', whereArgs: [danaTalangId]);
    if (result.isEmpty) throw ArgumentError('Dana talang tidak ditemukan');
    final talang = DanaTalangModel.fromMap(result.first);

    if (!talang.isAktif) {
      throw StateError('Dana talang ini sudah lunas/dibatalkan.');
    }
    if (nominal > talang.sisa) {
      throw ArgumentError(
          'Nominal pembayaran (Rp${nominal.toStringAsFixed(0)}) melebihi sisa (Rp${talang.sisa.toStringAsFixed(0)})');
    }

    final (cash, transfer) =
        _hitungSplit(metodePembayaran, cashDibayar, transferDibayar, nominal);

    final isMenalangi = talang.jenis == AppConstants.danaTalangSayaMenalangi;
    final now = DateTime.now();
    var pembayaran = DanaTalangPembayaranModel(
      danaTalangId: danaTalangId,
      tanggal: tanggal,
      nominal: nominal,
      metodePembayaran: metodePembayaran,
      cashTerpakai: cash,
      transferTerpakai: transfer,
      jenisTransfer: (!isMenalangi && transfer > 0) ? jenisTransfer : null,
      keterangan: keterangan,
      createdAt: now,
    );
    final pembayaranId =
        await txn.insert('dana_talang_pembayaran', pembayaran.toMap());
    pembayaran = pembayaran.copyWith(id: pembayaranId);

    final auditLog = AuditLogRepository(txn);
    await auditLog.catatCreate(
      'dana_talang_pembayaran',
      pembayaranId,
      jsonEncode(pembayaran.toMap()),
      keterangan: 'Pembayaran kembali dana talang ${talang.namaPartner}',
    );

    final totalBaru = talang.totalDibayarKembali + nominal;
    // V5.9.1 — pakai helper bersama supaya sisa yang sudah dikonversi
    // ke modal sebelumnya ikut diperhitungkan (dulu di sini cuma cek
    // `totalBaru >= talang.nominal`, yang jadi SALAH kalau sebagian
    // sudah dikonversi -- bisa menolak pelunasan cash yang harusnya
    // sudah cukup untuk melunasi SISA setelah dikurangi konversi).
    final statusBaru = _hitungStatus(
      nominal: talang.nominal,
      totalDibayarKembali: totalBaru,
      totalDikonversiModal: talang.totalDikonversiModal,
    );

    final talangBaru = talang.copyWith(
      totalDibayarKembali: totalBaru,
      status: statusBaru,
      updatedAt: now,
    );
    await txn.update('dana_talang', talangBaru.toMap(),
        where: 'id = ?', whereArgs: [danaTalangId]);
    await auditLog.catatUpdate(
      'dana_talang',
      danaTalangId,
      jsonEncode(talang.toMap()),
      jsonEncode(talangBaru.toMap()),
      keterangan: 'Status -> $statusBaru',
    );

    final saldoRepo = SaldoRepository(txn);
    // Menalangi: pembayaran kembali dari partner -> cash/bank kita naik.
    // Menerima: kita bayar balik ke partner -> cash/bank kita turun.
    final biayaAdmin = await saldoRepo.bayarCampuran(
      cash: cash,
      transfer: transfer,
      tipe: isMenalangi ? AppConstants.cashFlowMasuk : AppConstants.cashFlowKeluar,
      referensi: AppConstants.cashFlowRefDanaTalangBayar,
      referensiId: pembayaranId,
      keterangan: 'Pembayaran kembali dana talang ${talang.namaPartner}',
      tanggal: tanggal,
      jenisTransfer: !isMenalangi ? jenisTransfer : null,
    );
    if (biayaAdmin > 0) {
      pembayaran = pembayaran.copyWith(biayaAdminTransfer: biayaAdmin);
      await txn.update('dana_talang_pembayaran', pembayaran.toMap(),
          where: 'id = ?', whereArgs: [pembayaranId]);
    }

    return talangBaru;
  }

  /// V5.9.1 — CAPITAL CONVERSION (Spec §11/§12, Koreksi §1-§4).
  ///
  /// Konversi (sebagian atau seluruh) SISA hutang dana talang
  /// `SAYA_MENERIMA` menjadi Tambahan Modal. Ini **BUKAN pembayaran**:
  ///   Dana Talang / Liability   -> berkurang
  ///   Additional Capital / Equity -> bertambah, jumlah SAMA PERSIS
  ///   Cash / Bank                -> TIDAK BERUBAH SAMA SEKALI
  ///
  /// Method ini SENGAJA tidak pernah memanggil bayarCampuran/mutasiCash/
  /// mutasiBank — satu-satunya efek saldo yang boleh terjadi di sini
  /// adalah lewat `SaldoRepository.ubahModal()` (bukan `tambahModal()`,
  /// karena tambahModal() JUGA menambah Cash operasional — cocok untuk
  /// setoran modal fisik, tapi salah untuk konversi non-cash ini).
  ///
  /// Histori transaksi ASLI (baris dana_talang ini) TIDAK diubah/dihapus
  /// — "Abah memberikan dana talang" tetap tercatat apa adanya. Yang
  /// baru cuma 1 baris di `dana_talang_pembayaran` bertanda
  /// `metode_pembayaran = KONVERSI_MODAL` (cash/transfer_terpakai selalu
  /// 0) sebagai jejak "Konversi Dana Talang -> Tambahan Modal".
  ///
  /// Mendukung PARTIAL conversion: nominal boleh kurang dari sisa
  /// hutang, sisanya tetap outstanding sebagai liability
  /// (status SEBAGIAN_DIKONVERSI) dan masih bisa dibayar cash / dicicil
  /// / dikonversi lagi / dibawa ke periode berikutnya nanti.
  Future<DanaTalangModel> konversiKeModal({
    required int danaTalangId,
    required double nominal,
    DateTime? tanggal,
    String? keterangan,
  }) async {
    requireWriteAccess();
    return db.transaction<DanaTalangModel>((txn) => konversiKeModalInTxn(
          txn,
          danaTalangId: danaTalangId,
          nominal: nominal,
          tanggal: tanggal,
          keterangan: keterangan,
        ));
  }

  /// V5.9.3 — sama persis dengan [konversiKeModal], TAPI menerima [txn]
  /// dari luar. Dipakai [konversiSemuaAktifKeModal] (settlement massal
  /// per partner) supaya konversi banyak baris dana talang sekaligus
  /// tetap SATU transaction (all-or-nothing), bukan transaction terpisah
  /// per baris.
  Future<DanaTalangModel> konversiKeModalInTxn(
    DatabaseExecutor txn, {
    required int danaTalangId,
    required double nominal,
    DateTime? tanggal,
    String? keterangan,
  }) async {
    requireWriteAccess();
    final result = await txn
        .query('dana_talang', where: 'id = ?', whereArgs: [danaTalangId]);
    if (result.isEmpty) throw ArgumentError('Dana talang tidak ditemukan');
    final talang = DanaTalangModel.fromMap(result.first);

    // Validasi jenis: HANYA hutang perusahaan (partner pernah
    // menalangi KITA) yang bisa dikonversi jadi modal kita. Piutang
    // (SAYA_MENALANGI, kita yang menalangi partner) tidak relevan —
    // itu uang yang harus KITA terima, bukan kewajiban kita.
    if (talang.jenis != AppConstants.danaTalangSayaMenerima) {
      throw StateError(
          'Hanya dana talang SAYA_MENERIMA (hutang perusahaan ke partner) yang bisa dikonversi menjadi Tambahan Modal.');
    }
    if (!talang.isAktif) {
      throw StateError(
          'Dana talang ini sudah lunas/dikonversi penuh/dibatalkan — tidak ada sisa untuk dikonversi.');
    }
    if (nominal <= 0) {
      throw ArgumentError('Nominal konversi harus lebih dari 0');
    }
    // Toleransi Rp0.5 untuk pembulatan double, konsisten dengan
    // validasi nominal di bayarKembali().
    if (nominal > talang.sisa + 0.5) {
      throw ArgumentError(
          'Nominal konversi (Rp${nominal.toStringAsFixed(0)}) melebihi sisa hutang (Rp${talang.sisa.toStringAsFixed(0)})');
    }

    final now = DateTime.now();
    final auditLog = AuditLogRepository(txn);

    // 1) Catat peristiwa konversi sebagai baris BARU di riwayat
    //    (bukan menimpa/menghapus apa pun) — cash/transfer_terpakai
    //    SELALU 0 karena tidak ada uang yang berpindah.
    var konversi = DanaTalangPembayaranModel(
      danaTalangId: danaTalangId,
      tanggal: tanggal ?? now,
      nominal: nominal,
      metodePembayaran: AppConstants.metodeKonversiModal,
      cashTerpakai: 0,
      transferTerpakai: 0,
      keterangan: keterangan ??
          'Konversi Dana Talang ${talang.namaPartner} -> Tambahan Modal',
      createdAt: now,
    );
    final konversiId =
        await txn.insert('dana_talang_pembayaran', konversi.toMap());
    konversi = konversi.copyWith(id: konversiId);

    await auditLog.catatCreate(
      'dana_talang_pembayaran',
      konversiId,
      jsonEncode(konversi.toMap()),
      keterangan: 'KONVERSI MODAL -- FROM: Dana Talang/Partner Funding '
          'Liability (${talang.namaPartner}) TO: Additional Capital '
          '(Modal Cash). Amount: Rp${nominal.toStringAsFixed(0)}. '
          'Cash/Bank TIDAK berubah. Ref dana_talang #$danaTalangId.',
    );

    // 2) Kurangi outstanding liability di baris dana_talang.
    final totalDikonversiBaru = talang.totalDikonversiModal + nominal;
    final statusBaru = _hitungStatus(
      nominal: talang.nominal,
      totalDibayarKembali: talang.totalDibayarKembali,
      totalDikonversiModal: totalDikonversiBaru,
    );
    final talangBaru = talang.copyWith(
      totalDikonversiModal: totalDikonversiBaru,
      status: statusBaru,
      updatedAt: now,
    );
    await txn.update('dana_talang', talangBaru.toMap(),
        where: 'id = ?', whereArgs: [danaTalangId]);
    await auditLog.catatUpdate(
      'dana_talang',
      danaTalangId,
      jsonEncode(talang.toMap()),
      jsonEncode(talangBaru.toMap()),
      keterangan:
          'Konversi ke Modal Rp${nominal.toStringAsFixed(0)} -> status '
          '$statusBaru (liability berkurang, Cash/Bank tidak berubah)',
    );

    // 3) Tambah Equity. SENGAJA `ubahModal()`, BUKAN `tambahModal()` —
    //    ubahModal() murni catatan permodalan (modal_cash/modal_bank),
    //    TIDAK menyentuh saldo Cash/Bank operasional. Ini SATU-SATUNYA
    //    baris di seluruh fungsi ini yang menyentuh tabel `saldo`.
    final saldoRepo = SaldoRepository(txn);
    await saldoRepo.ubahModal(
      jenis: AppConstants.modalJenisCash,
      aksi: AppConstants.modalAksiTambah,
      nominal: nominal,
      keterangan: 'Konversi Dana Talang ${talang.namaPartner} -> '
          'Tambahan Modal (Cash/Bank tidak berubah), '
          'ref dana_talang #$danaTalangId',
    );

    return talangBaru;
  }

  /// V5.9.3 — SETTLEMENT MASSAL per partner, satu arah (SATU jenis
  /// saja: SAYA_MENALANGI *atau* SAYA_MENERIMA, tidak dicampur), dengan
  /// dukungan FULL LUNAS maupun CICIL (nominal boleh kurang dari total
  /// sisa gabungan).
  ///
  /// Dipakai untuk 2 aksi eksplisit di layar "Hubungan Partner":
  ///   - "Saya Menerima Pembayaran" -> jenis: SAYA_MENALANGI (piutang
  ///     kita ke partner, partner bayar balik ke kita, cash/bank KITA
  ///     bertambah).
  ///   - "Saya Membayar Hutang"     -> jenis: SAYA_MENERIMA (hutang
  ///     kita ke partner, kita bayar ke partner, cash/bank KITA
  ///     berkurang).
  ///
  /// [nominal] dialokasikan FIFO (transaksi TERTUA duluan) ke
  /// baris-baris dana_talang AKTIF milik partner & jenis tsb, memakai
  /// [bayarKembaliInTxn] per baris (jadi validasi/status/audit per
  /// baris tetap identik dengan pembayaran satuan). SATU
  /// `db.transaction` untuk semua baris -- kalau ada satu baris gagal
  /// (mis. data berubah di tengah jalan), SEMUA baris yang sudah
  /// diproses di panggilan ini ikut rollback (all-or-nothing), TIDAK
  /// ada partial state seperti implementasi lama (`_bayarSemuaSelisih`
  /// di UI yang loop manual dengan try-catch per baris).
  ///
  /// Melempar [ArgumentError] SEBELUM mengubah apa pun kalau [nominal]
  /// melebihi total sisa gabungan (tidak membuat saldo/liability jadi
  /// tidak masuk akal).
  Future<List<DanaTalangModel>> bayarSemuaAktif({
    required String namaPartner,
    required String jenis,
    required double nominal,
    String metodePembayaran = AppConstants.metodeCash,
    String? jenisTransfer,
    DateTime? tanggal,
    String? keterangan,
  }) async {
    requireWriteAccess();
    if (nominal <= 0) {
      throw ArgumentError('Nominal harus lebih dari 0');
    }
    return db.transaction<List<DanaTalangModel>>((txn) async {
      final rows = await txn.query(
        'dana_talang',
        where: 'nama_partner = ? AND jenis = ? AND status NOT IN (?, ?, ?)',
        whereArgs: [
          namaPartner,
          jenis,
          AppConstants.statusDanaTalangLunas,
          AppConstants.statusDanaTalangBatal,
          AppConstants.statusDanaTalangDikonversiModal,
        ],
        orderBy: 'tanggal ASC, id ASC',
      );
      final aktif = rows.map((r) => DanaTalangModel.fromMap(r)).toList();

      final totalSisa = aktif.fold<double>(0, (s, t) => s + t.sisa);
      if (nominal > totalSisa + 0.5) {
        throw ArgumentError(
            'Nominal (Rp${nominal.toStringAsFixed(0)}) melebihi total sisa '
            'aktif $namaPartner (Rp${totalSisa.toStringAsFixed(0)})');
      }

      double sisaAlokasi = nominal;
      final hasil = <DanaTalangModel>[];
      for (final t in aktif) {
        if (sisaAlokasi <= 0.5) break;
        final bayar = t.sisa <= sisaAlokasi ? t.sisa : sisaAlokasi;
        if (bayar <= 0) continue;
        final updated = await bayarKembaliInTxn(
          txn,
          danaTalangId: t.id!,
          tanggal: tanggal ?? DateTime.now(),
          nominal: bayar,
          metodePembayaran: metodePembayaran,
          cashDibayar: metodePembayaran == AppConstants.metodeCash ? bayar : 0,
          transferDibayar:
              metodePembayaran == AppConstants.metodeTransfer ? bayar : 0,
          jenisTransfer: jenisTransfer,
          keterangan: keterangan ?? 'Settlement massal $namaPartner',
        );
        hasil.add(updated);
        sisaAlokasi -= bayar;
      }
      return hasil;
    });
  }

  /// V5.9.3 — KONVERSI MASSAL per partner: alokasikan [nominal] (FIFO,
  /// tertua duluan) ke baris-baris dana talang `SAYA_MENERIMA` AKTIF
  /// milik partner, dikonversi jadi Tambahan Modal. SATU
  /// `db.transaction`, cash/bank TIDAK PERNAH tersentuh (pakai
  /// [konversiKeModalInTxn] per baris, sama seperti konversi satuan).
  Future<List<DanaTalangModel>> konversiSemuaAktifKeModal({
    required String namaPartner,
    required double nominal,
    DateTime? tanggal,
    String? keterangan,
  }) async {
    requireWriteAccess();
    if (nominal <= 0) {
      throw ArgumentError('Nominal harus lebih dari 0');
    }
    return db.transaction<List<DanaTalangModel>>((txn) async {
      final rows = await txn.query(
        'dana_talang',
        where: 'nama_partner = ? AND jenis = ? AND status NOT IN (?, ?, ?)',
        whereArgs: [
          namaPartner,
          AppConstants.danaTalangSayaMenerima,
          AppConstants.statusDanaTalangLunas,
          AppConstants.statusDanaTalangBatal,
          AppConstants.statusDanaTalangDikonversiModal,
        ],
        orderBy: 'tanggal ASC, id ASC',
      );
      final aktif = rows.map((r) => DanaTalangModel.fromMap(r)).toList();

      final totalSisa = aktif.fold<double>(0, (s, t) => s + t.sisa);
      if (nominal > totalSisa + 0.5) {
        throw ArgumentError(
            'Nominal (Rp${nominal.toStringAsFixed(0)}) melebihi total sisa '
            'hutang aktif $namaPartner (Rp${totalSisa.toStringAsFixed(0)})');
      }

      double sisaAlokasi = nominal;
      final hasil = <DanaTalangModel>[];
      for (final t in aktif) {
        if (sisaAlokasi <= 0.5) break;
        final konversi = t.sisa <= sisaAlokasi ? t.sisa : sisaAlokasi;
        if (konversi <= 0) continue;
        final updated = await konversiKeModalInTxn(
          txn,
          danaTalangId: t.id!,
          nominal: konversi,
          tanggal: tanggal,
          keterangan: keterangan ??
              'Konversi massal $namaPartner -> Tambahan Modal',
        );
        hasil.add(updated);
        sisaAlokasi -= konversi;
      }
      return hasil;
    });
  }

  /// Edit HANYA tanggal transaksi dana talang utama.
  Future<void> editTanggalDanaTalang(int id, DateTime tanggalBaru) async {
    requireWriteAccess();
    return db.transaction<void>((txn) async {
      final result =
          await txn.query('dana_talang', where: 'id = ?', whereArgs: [id]);
      if (result.isEmpty) throw ArgumentError('Dana talang tidak ditemukan');
      final lama = DanaTalangModel.fromMap(result.first);
      final auditLog = AuditLogRepository(txn);

      await txn.update(
        'dana_talang',
        {
          'tanggal': tanggalBaru.toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      await auditLog.catatUpdate(
        'dana_talang',
        id,
        jsonEncode({'tanggal': lama.tanggal.toIso8601String()}),
        jsonEncode({'tanggal': tanggalBaru.toIso8601String()}),
        keterangan: 'Mengubah tanggal dana talang ${lama.namaPartner}: dari '
            '${lama.tanggal.toIso8601String().split("T").first} menjadi '
            '${tanggalBaru.toIso8601String().split("T").first}',
      );
    });
  }

  /// Edit HANYA tanggal riwayat pembayaran kembali dana talang.
  Future<void> editTanggalPembayaran(int pembayaranId, DateTime tanggalBaru) async {
    requireWriteAccess();
    return db.transaction<void>((txn) async {
      final result = await txn.query('dana_talang_pembayaran',
          where: 'id = ?', whereArgs: [pembayaranId]);
      if (result.isEmpty) throw ArgumentError('Pembayaran tidak ditemukan');
      final lama = DanaTalangPembayaranModel.fromMap(result.first);
      final auditLog = AuditLogRepository(txn);

      await txn.update(
        'dana_talang_pembayaran',
        {'tanggal': tanggalBaru.toIso8601String()},
        where: 'id = ?',
        whereArgs: [pembayaranId],
      );
      await auditLog.catatUpdate(
        'dana_talang_pembayaran',
        pembayaranId,
        jsonEncode({'tanggal': lama.tanggal.toIso8601String()}),
        jsonEncode({'tanggal': tanggalBaru.toIso8601String()}),
        keterangan: 'Mengubah tanggal pembayaran dana talang #${lama.danaTalangId}: dari '
            '${lama.tanggal.toIso8601String().split("T").first} menjadi '
            '${tanggalBaru.toIso8601String().split("T").first}',
      );
    });
  }

  /// Batalkan dana talang (status -> BATAL). Hanya boleh jika BELUM ada
  /// pembayaran kembali sama sekali — membalik efek kas awal.
  Future<DanaTalangModel> batalkanDanaTalang(int id, {String? alasan}) async {
    requireWriteAccess();
    return db.transaction<DanaTalangModel>((txn) async {
      final result =
          await txn.query('dana_talang', where: 'id = ?', whereArgs: [id]);
      if (result.isEmpty) throw ArgumentError('Dana talang tidak ditemukan');
      final talang = DanaTalangModel.fromMap(result.first);

      if (talang.totalDibayarKembali > 0 || talang.totalDikonversiModal > 0) {
        throw StateError(
            'Tidak bisa dibatalkan karena sudah ada pembayaran kembali dan/atau konversi ke modal. Hapus saja transaksinya (akan rollback otomatis).');
      }
      if (!talang.isAktif) {
        throw StateError('Dana talang ini sudah lunas/dibatalkan.');
      }

      final saldoRepo = SaldoRepository(txn);
      final auditLog = AuditLogRepository(txn);
      final isMenalangi = talang.jenis == AppConstants.danaTalangSayaMenalangi;

      await saldoRepo.bayarCampuran(
        cash: talang.cashTerpakai,
        transfer: talang.transferTerpakai,
        tipe: isMenalangi ? AppConstants.cashFlowMasuk : AppConstants.cashFlowKeluar,
        referensi: isMenalangi
            ? AppConstants.cashFlowRefDanaTalangBeri
            : AppConstants.cashFlowRefDanaTalangTerima,
        referensiId: id,
        keterangan: 'Batal dana talang ${talang.namaPartner}',
      );
      if (isMenalangi && talang.biayaAdminTransfer > 0) {
        await saldoRepo.mutasiBank(
          nominal: talang.biayaAdminTransfer,
          tipe: AppConstants.cashFlowMasuk,
          referensi: AppConstants.cashFlowRefAdminTransfer,
          referensiId: id,
          keterangan: 'Batal admin transfer dana talang ${talang.namaPartner}',
        );
      }

      final baru = talang.copyWith(
        status: AppConstants.statusDanaTalangBatal,
        updatedAt: DateTime.now(),
      );
      await txn.update('dana_talang', baru.toMap(),
          where: 'id = ?', whereArgs: [id]);
      await auditLog.catatUpdate(
        'dana_talang',
        id,
        jsonEncode(talang.toMap()),
        jsonEncode(baru.toMap()),
        keterangan: alasan ?? 'Dibatalkan',
      );

      return baru;
    });
  }

  /// HAPUS dana talang beserta seluruh riwayat pembayarannya. Rollback
  /// penuh: semua pembayaran kembali dibalik, lalu transaksi awal
  /// dibalik, baru baris dihapus (cascade menghapus dana_talang_pembayaran).
  Future<void> hapusDanaTalang(int id) async {
    requireWriteAccess();
    return db.transaction<void>((txn) async {
      final result =
          await txn.query('dana_talang', where: 'id = ?', whereArgs: [id]);
      if (result.isEmpty) return;
      final talang = DanaTalangModel.fromMap(result.first);

      final saldoRepo = SaldoRepository(txn);
      final auditLog = AuditLogRepository(txn);
      final isMenalangi = talang.jenis == AppConstants.danaTalangSayaMenalangi;

      // 1) Balik semua pembayaran kembali.
      final pembayaranList = await txn.query('dana_talang_pembayaran',
          where: 'dana_talang_id = ?', whereArgs: [id]);
      for (final p in pembayaranList) {
        final bayar = DanaTalangPembayaranModel.fromMap(p);

        // V5.9.1 — baris KONVERSI MODAL tidak pernah menyentuh cash
        // (cash/transfer_terpakai selalu 0), jadi rollback-nya BUKAN
        // bayarCampuran (yang cuma memutasi cash/bank) melainkan balik
        // Tambahan Modal yang sempat ditambahkan lewat ubahModal().
        if (bayar.metodePembayaran == AppConstants.metodeKonversiModal) {
          await saldoRepo.ubahModal(
            jenis: AppConstants.modalJenisCash,
            aksi: AppConstants.modalAksiKurang,
            nominal: bayar.nominal,
            keterangan:
                'Rollback hapus dana talang ${talang.namaPartner} (batalkan konversi modal)',
          );
          continue;
        }

        await saldoRepo.bayarCampuran(
          cash: bayar.cashTerpakai,
          transfer: bayar.transferTerpakai,
          tipe:
              isMenalangi ? AppConstants.cashFlowKeluar : AppConstants.cashFlowMasuk,
          referensi: AppConstants.cashFlowRefDanaTalangBayar,
          referensiId: bayar.id,
          keterangan: 'Rollback hapus dana talang ${talang.namaPartner}',
        );
        if (!isMenalangi && bayar.biayaAdminTransfer > 0) {
          await saldoRepo.mutasiBank(
            nominal: bayar.biayaAdminTransfer,
            tipe: AppConstants.cashFlowMasuk,
            referensi: AppConstants.cashFlowRefAdminTransfer,
            referensiId: bayar.id,
            keterangan: 'Rollback hapus admin transfer pembayaran dana talang ${talang.namaPartner}',
          );
        }
      }

      // 2) Balik transaksi awal (jika belum dibatalkan sebelumnya).
      if (talang.status != AppConstants.statusDanaTalangBatal) {
        await saldoRepo.bayarCampuran(
          cash: talang.cashTerpakai,
          transfer: talang.transferTerpakai,
          tipe:
              isMenalangi ? AppConstants.cashFlowMasuk : AppConstants.cashFlowKeluar,
          referensi: isMenalangi
              ? AppConstants.cashFlowRefDanaTalangBeri
              : AppConstants.cashFlowRefDanaTalangTerima,
          referensiId: id,
          keterangan: 'Rollback hapus dana talang ${talang.namaPartner}',
        );
        if (isMenalangi && talang.biayaAdminTransfer > 0) {
          await saldoRepo.mutasiBank(
            nominal: talang.biayaAdminTransfer,
            tipe: AppConstants.cashFlowMasuk,
            referensi: AppConstants.cashFlowRefAdminTransfer,
            referensiId: id,
            keterangan: 'Rollback hapus admin transfer dana talang ${talang.namaPartner}',
          );
        }
      }

      // 3) Hapus (cascade menghapus dana_talang_pembayaran).
      await txn.delete('dana_talang', where: 'id = ?', whereArgs: [id]);
      await auditLog.catatDelete(
        'dana_talang',
        id,
        jsonEncode(talang.toMap()),
        keterangan: 'Hapus dana talang ${talang.namaPartner} — saldo dikembalikan',
      );
    });
  }

  /// V5.9.4 — [includeArchived] default false, lihat
  /// `KasbonRepository.getAll` untuk penjelasan arsip.
  Future<List<DanaTalangModel>> getAll({
    String? jenis,
    String? status,
    bool includeArchived = false,
  }) async {
    final whereClauses = <String>[];
    final whereArgs = <Object?>[];
    if (jenis != null) {
      whereClauses.add('jenis = ?');
      whereArgs.add(jenis);
    }
    if (status != null) {
      whereClauses.add('status = ?');
      whereArgs.add(status);
    }
    if (!includeArchived) {
      whereClauses.add('is_archived = 0');
    }
    final result = await db.query(
      'dana_talang',
      where: whereClauses.isEmpty ? null : whereClauses.join(' AND '),
      whereArgs: whereArgs.isEmpty ? null : whereArgs,
      orderBy: 'tanggal DESC',
    );
    return result.map((e) => DanaTalangModel.fromMap(e)).toList();
  }

  Future<List<DanaTalangPembayaranModel>> getRiwayatPembayaran(
      int danaTalangId) async {
    final result = await db.query(
      'dana_talang_pembayaran',
      where: 'dana_talang_id = ?',
      whereArgs: [danaTalangId],
      orderBy: 'tanggal DESC',
    );
    return result.map((e) => DanaTalangPembayaranModel.fromMap(e)).toList();
  }

  /// Total Piutang Partner (dana yang kita talangi & belum kembali).
  /// `total_dikonversi_modal` disertakan untuk konsistensi walau secara
  /// bisnis SAYA_MENALANGI tidak pernah dikonversi (konversi hanya
  /// berlaku untuk SAYA_MENERIMA, lihat konversiKeModal()) — nilainya
  /// akan selalu 0 di baris jenis ini.
  Future<double> getTotalPiutangPartner() async {
    final result = await db.rawQuery('''
      SELECT nominal, total_dibayar_kembali, total_dikonversi_modal FROM dana_talang
      WHERE jenis = ? AND status NOT IN (?, ?)
    ''', [
      AppConstants.danaTalangSayaMenalangi,
      AppConstants.statusDanaTalangLunas,
      AppConstants.statusDanaTalangBatal,
    ]);
    double total = 0;
    for (final row in result) {
      total += (row['nominal'] as num).toDouble() -
          (row['total_dibayar_kembali'] as num).toDouble() -
          ((row['total_dikonversi_modal'] as num?)?.toDouble() ?? 0);
    }
    return total;
  }

  /// Total Hutang Partner (talangan partner ke kita & belum kita
  /// bayar/konversi). V5.9.1: WAJIB kurangi `total_dikonversi_modal`
  /// juga & kecualikan status DIKONVERSI_MODAL — kalau tidak, hutang
  /// yang sudah dikonversi jadi Tambahan Modal akan tetap terhitung
  /// sebagai liability di Dashboard/Laporan/FinancialBalanceEngine
  /// padahal sudah pindah jadi Equity (balance jadi tidak Rp0).
  Future<double> getTotalHutangPartner() async {
    final result = await db.rawQuery('''
      SELECT nominal, total_dibayar_kembali, total_dikonversi_modal FROM dana_talang
      WHERE jenis = ? AND status NOT IN (?, ?, ?)
    ''', [
      AppConstants.danaTalangSayaMenerima,
      AppConstants.statusDanaTalangLunas,
      AppConstants.statusDanaTalangBatal,
      AppConstants.statusDanaTalangDikonversiModal,
    ]);
    double total = 0;
    for (final row in result) {
      total += (row['nominal'] as num).toDouble() -
          (row['total_dibayar_kembali'] as num).toDouble() -
          ((row['total_dikonversi_modal'] as num?)?.toDouble() ?? 0);
    }
    return total;
  }

  /// V5.5 — hubungan talangan per-partner: dikelompokkan dari data
  /// dana_talang yang SUDAH ADA (tidak ada tabel/kolom baru). Untuk tiap
  /// nama partner: total sisa yang kita talangi ke dia (piutang kita),
  /// total sisa dia talangi ke kita (hutang kita), dan selisihnya (net
  /// piutang kalau positif, net hutang kalau negatif).
  Future<List<HubunganPartnerSummary>> getHubunganPerPartner() async {
    final semua = await getAll();
    final aktif = semua.where((t) => t.isAktif).toList();
    final byNama = <String, List<DanaTalangModel>>{};
    for (final t in aktif) {
      byNama.putIfAbsent(t.namaPartner, () => []).add(t);
    }
    final result = <HubunganPartnerSummary>[];
    byNama.forEach((nama, list) {
      double piutang = 0; // kita menalangi dia, dia belum lunas bayar
      double hutang = 0; // dia menalangi kita, kita belum lunas bayar
      for (final t in list) {
        if (t.isMenalangi) {
          piutang += t.sisa;
        } else {
          hutang += t.sisa;
        }
      }
      result.add(HubunganPartnerSummary(
        namaPartner: nama,
        totalPiutang: piutang,
        totalHutang: hutang,
        riwayat: list..sort((a, b) => b.tanggal.compareTo(a.tanggal)),
      ));
    });
    // Urutkan berdasarkan |selisih| terbesar dulu -- yang paling perlu
    // diselesaikan tampil paling atas.
    result.sort((a, b) => b.selisih.abs().compareTo(a.selisih.abs()));
    return result;
  }
}

/// V5.5 — ringkasan hubungan talangan dengan 1 partner (dikelompokkan dari
/// dana_talang, bukan tabel baru).
class HubunganPartnerSummary {
  final String namaPartner;
  final double totalPiutang; // kita talangi dia, sisa belum dia bayar
  final double totalHutang; // dia talangi kita, sisa belum kita bayar
  final List<DanaTalangModel> riwayat;

  HubunganPartnerSummary({
    required this.namaPartner,
    required this.totalPiutang,
    required this.totalHutang,
    required this.riwayat,
  });

  /// Positif = net partner berhutang ke kita. Negatif = net kita
  /// berhutang ke partner.
  double get selisih => totalPiutang - totalHutang;
}

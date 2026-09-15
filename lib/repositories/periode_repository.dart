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

  /// V5.9.4 — Buka periode baru dengan CARRY-FORWARD dari closing
  /// sebelumnya (Mega Prompt Section M/§19-21, sesuai permintaan user).
  ///
  /// BEDA PENTING dengan [buatPeriode]: method itu MENYUNTIK cash/bank
  /// fisik sejumlah modal yang diinput (dipakai untuk periode PERTAMA
  /// kali / suntikan modal baru yang sungguhan). Method INI TIDAK
  /// menyuntik apa pun — karena Cash, Bank, Stok, Piutang semuanya
  /// SUDAH otomatis carry-forward (tidak pernah direset antar periode di
  /// aplikasi ini), jadi menyuntik lagi akan DOBEL menghitung aset yang
  /// sama. [totalAsetAkhirClosing] murni disimpan sebagai ANGKA
  /// REFERENSI (`modal_awal_total_aset`).
  ///
  /// CATATAN: method ini TIDAK memvalidasi ulang [totalAsetAkhirClosing]
  /// terhadap perhitungan live — validasi "OPENING BALANCE MISMATCH"
  /// (Spec §21) dilakukan SATU LAPIS DI ATAS, oleh
  /// `PeriodOpeningService.bukaPeriodeBaruDariClosing()` (lib/services),
  /// BUKAN di sini — supaya repository ini tidak perlu import
  /// `FinancialBalanceEngine` dari lib/services (circular
  /// repository<->service). Jangan panggil method ini langsung dari
  /// UI; selalu lewat `PeriodOpeningService`.
  Future<PeriodeModel> buatPeriodeCarryForward({
    required String namaPeriode,
    required DateTime tanggalMulai,
    required double totalAsetAkhirClosing,
    bool arsipkanTransaksiLunas = true,
  }) async {
    requireWriteAccess();
    final aktif = await getPeriodeAktif();
    if (aktif != null) {
      throw StateError(
        'Masih ada periode aktif ("${aktif.namaPeriode}"). '
        'Tutup buku periode tersebut terlebih dahulu sebelum membuka periode baru.',
      );
    }

    return db.transaction<PeriodeModel>((txn) async {
      final now = DateTime.now();
      final periode = PeriodeModel(
        namaPeriode: namaPeriode,
        tanggalMulai: tanggalMulai,
        status: AppConstants.statusPeriodeAktif,
        modalAwalCash: 0,
        modalAwalBank: 0,
        modalAwalTotalAset: totalAsetAkhirClosing,
        createdAt: now,
        updatedAt: now,
      );
      final id = await txn.insert('periode', periode.toMap());
      final saved = periode.copyWith(id: id);
      final auditLog = AuditLogRepository(txn);
      await auditLog.catatCreate(
        'periode',
        id,
        jsonEncode(saved.toMap()),
        keterangan: 'Buka periode baru (carry-forward). Modal Awal (Total '
            'Aset) = Rp${totalAsetAkhirClosing.toStringAsFixed(0)}, sama '
            'persis dengan total aset akhir closing sebelumnya (selisih '
            'Rp0, sudah divalidasi PeriodOpeningService sebelum method '
            'ini dipanggil). TIDAK ADA cash/bank baru disuntikkan — Cash, '
            'Bank, Stok, dan Piutang semuanya carry-forward otomatis dari '
            'sebelum periode ini dibuka.',
      );

      // Arsipkan (BUKAN hapus) transaksi kasbon & dana talang yang
      // sudah LUNAS/DIKONVERSI PENUH, supaya daftar tidak menumpuk.
      // Data TETAP ada di database (bisa diaudit/dilihat lagi lewat
      // includeArchived), cuma disembunyikan dari daftar aktif default.
      var arsipKasbon = 0;
      var arsipDanaTalang = 0;
      if (arsipkanTransaksiLunas) {
        arsipKasbon = await txn.update(
          'kasbon',
          {'is_archived': 1},
          where: 'status = ? AND is_archived = 0',
          whereArgs: [AppConstants.statusKasbonLunas],
        );
        arsipDanaTalang = await txn.update(
          'dana_talang',
          {'is_archived': 1},
          where: 'status IN (?, ?) AND is_archived = 0',
          whereArgs: [
            AppConstants.statusDanaTalangLunas,
            AppConstants.statusDanaTalangDikonversiModal,
          ],
        );
        if (arsipKasbon > 0 || arsipDanaTalang > 0) {
          await auditLog.catatCreate(
            'periode',
            id,
            jsonEncode({
              'arsip_kasbon': arsipKasbon,
              'arsip_dana_talang': arsipDanaTalang
            }),
            keterangan:
                'Arsip otomatis saat buka periode baru: $arsipKasbon kasbon '
                'lunas + $arsipDanaTalang dana talang lunas/dikonversi '
                'disembunyikan dari daftar aktif (DATA TIDAK DIHAPUS, '
                'tetap tersimpan penuh untuk audit).',
          );
        }
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

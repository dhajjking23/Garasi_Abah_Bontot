import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../core/constants/app_constants.dart';
import '../models/pembagian_laba_model.dart';
import '../models/penjualan_model.dart';
import '../models/kasbon_model.dart';
import '../models/dana_talang_model.dart';
import '../repositories/penjualan_repository.dart';
import '../repositories/pengeluaran_repository.dart';
import '../repositories/periode_repository.dart';
import '../repositories/saldo_repository.dart';
import '../repositories/audit_log_repository.dart';
import '../repositories/gajihan_repository.dart';
import '../repositories/kasbon_repository.dart';
import '../repositories/dana_talang_repository.dart';
import '../core/security/write_guard.dart';

/// Hasil preview perhitungan laba sebelum benar-benar disimpan/tutup buku.
/// Dipakai UI untuk menampilkan preview di layar "Pembukuan" / "Laporan"
/// sebelum user menekan tombol "Tutup Buku & Bagi Laba".
class PreviewPembagianLaba {
  final double totalLabaMotor;
  final double totalPengeluaranLain;
  final double labaBersih;
  final double bagianAbah;
  final double bagianIki;
  final double bagianAndri;
  final double bagianIlham;
  final double totalHadiahPenjualan;
  final int unitInternalTerjual;
  final double bonusPerUnit;
  final List<DetailBonusPenjual> detailBonus;

  PreviewPembagianLaba({
    required this.totalLabaMotor,
    required this.totalPengeluaranLain,
    required this.labaBersih,
    required this.bagianAbah,
    required this.bagianIki,
    required this.bagianAndri,
    required this.bagianIlham,
    required this.totalHadiahPenjualan,
    required this.unitInternalTerjual,
    required this.bonusPerUnit,
    required this.detailBonus,
  });
}

/// Service yang mengimplementasikan logika bisnis inti dari brief:
///
///   Laba motor        = harga_jual - modal_motor
///   Laba bersih periode = total_laba_motor - total_pengeluaran_lain
///   Pembagian 100% laba bersih:
///     Abah 25% | Iki 27.5% | Andri 22.5% | Ilham 15% | Hadiah Penjualan 10%
///   Hadiah penjualan (10% dari laba bersih) dibagi rata ke jumlah unit
///   INTERNAL yang terjual (Calo dikecualikan / bonus_eligible = false).
///   bonus/unit = total_hadiah / unit_internal_terjual
///   bonus milik seseorang = bonus/unit * jumlah unit yang dia jual
class PembagianLabaService {
  final Database db;
  final PenjualanRepository _penjualanRepo;
  final PengeluaranRepository _pengeluaranRepo;
  final PeriodeRepository _periodeRepo;

  PembagianLabaService(this.db)
      : _penjualanRepo = PenjualanRepository(db),
        _pengeluaranRepo = PengeluaranRepository(db),
        _periodeRepo = PeriodeRepository(db);

  /// Menghitung preview pembagian laba untuk sebuah periode TANPA
  /// menyimpan apapun ke database. Aman dipanggil berulang kali,
  /// misal untuk ditampilkan real-time di layar Laporan.
  Future<PreviewPembagianLaba> hitungPreview(int periodeId) async {
    final List<PenjualanModel> semuaPenjualan =
        await _penjualanRepo.getAll(periodeId: periodeId);

    final totalLabaMotor =
        semuaPenjualan.fold<double>(0, (sum, p) => sum + p.laba);

    final totalPengeluaranLain =
        await _pengeluaranRepo.getTotalPengeluaranLain(periodeId: periodeId);

    final labaBersih = totalLabaMotor - totalPengeluaranLain;

    // Pembagian 4 pemilik berdasarkan persentase tetap dari AppConstants
    final bagianAbah = labaBersih * AppConstants.persenAbah;
    final bagianIki = labaBersih * AppConstants.persenIki;
    final bagianAndri = labaBersih * AppConstants.persenAndri;
    final bagianIlham = labaBersih * AppConstants.persenIlham;
    final totalHadiahPenjualan = labaBersih * AppConstants.persenHadiahPenjualan;

    // Hitung unit internal terjual (bonus_eligible == true, Calo dikecualikan)
    final penjualanInternal =
        semuaPenjualan.where((p) => p.bonusEligible).toList();
    final unitInternalTerjual = penjualanInternal.length;

    final bonusPerUnit = unitInternalTerjual > 0
        ? totalHadiahPenjualan / unitInternalTerjual
        : 0.0;

    // Rekap jumlah unit per penjual internal
    final Map<String, int> unitPerPenjual = {};
    for (final p in penjualanInternal) {
      unitPerPenjual[p.penjual] = (unitPerPenjual[p.penjual] ?? 0) + 1;
    }

    final detailBonus = unitPerPenjual.entries
        .map((e) => DetailBonusPenjual(
              nama: e.key,
              jumlahUnit: e.value,
              totalBonus: bonusPerUnit * e.value,
            ))
        .toList()
      ..sort((a, b) => b.totalBonus.compareTo(a.totalBonus));

    return PreviewPembagianLaba(
      totalLabaMotor: totalLabaMotor,
      totalPengeluaranLain: totalPengeluaranLain,
      labaBersih: labaBersih,
      bagianAbah: bagianAbah,
      bagianIki: bagianIki,
      bagianAndri: bagianAndri,
      bagianIlham: bagianIlham,
      totalHadiahPenjualan: totalHadiahPenjualan,
      unitInternalTerjual: unitInternalTerjual,
      bonusPerUnit: bonusPerUnit,
      detailBonus: detailBonus,
    );
  }

  /// Ambil bagian (hak laba KOTOR, sebelum dikurangi yang sudah diambil
  /// lewat Gajihan) untuk SATU nama partner dari sebuah preview yang
  /// sudah dihitung. Mengembalikan 0 untuk nama yang bukan salah satu
  /// dari 4 partner (mis. karyawan lain jika suatu saat ditambahkan).
  double bagianPartner(PreviewPembagianLaba preview, String namaPartner) {
    switch (namaPartner) {
      case 'Abah':
        return preview.bagianAbah;
      case 'Iki':
        return preview.bagianIki;
      case 'Andri':
        return preview.bagianAndri;
      case 'Ilham':
        return preview.bagianIlham;
      default:
        return 0;
    }
  }

  /// V5.9.6 — SISA hak laba [namaPartner] untuk periode [periodeId] yang
  /// BELUM diambil lewat Gajihan (hak laba KOTOR dikurangi total yang
  /// sudah diambil, tidak pernah negatif). Dipakai GajihanScreen untuk
  /// auto-fill "Gaji Pokok" -- BUKAN gaji flat/manual, tapi benar-benar
  /// hak laba (persentase x laba bersih periode berjalan) dikurangi apa
  /// yang sudah pernah diambil partner ybs periode ini.
  Future<double> sisaHakLabaPartner(String namaPartner, int periodeId) async {
    final preview = await hitungPreview(periodeId);
    final hakKotor = bagianPartner(preview, namaPartner);
    final sudahDiambil = await GajihanRepository(db)
        .getTotalGajiDiambilPeriode(namaPartner, periodeId);
    return (hakKotor - sudahDiambil).clamp(0, double.infinity).toDouble();
  }

  /// Tutup buku periode: hitung ulang final, simpan hasil ke tabel
  /// pembagian_laba, EKSEKUSI PEMBAYARAN NYATA (Cash/Bank benar-benar
  /// berkurang) untuk distribusi laba 4 partner + bonus penjualan, lalu
  /// ubah status periode menjadi TUTUP. SEMUA dalam SATU
  /// `db.transaction` (all-or-nothing).
  ///
  /// V5.9.4 — sebelumnya method ini HANYA menyimpan baris laporan;
  /// PartnerSettlementService menghitung net settlement tapi tidak
  /// pernah dieksekusi, jadi Cash/Bank tidak pernah benar-benar
  /// berkurang saat closing (gap P0-1 yang diaudit sebelumnya). Sekarang
  /// diperbaiki: begitu tombol "Tutup Buku" ditekan, uang BENAR-BENAR
  /// keluar untuk bagian Abah/Iki/Andri/Ilham + bonus penjualan per
  /// penjual, dicatat sebagai `Pengeluaran` kategori
  /// [AppConstants.kategoriDistribusiLabaPartner]/[AppConstants.kategoriBonusPenjualan]
  /// (BUKAN 'Pengeluaran Lain' — supaya tidak dihitung ulang mengurangi
  /// laba bersih periode berikutnya, lihat dok kategori tsb).
  ///
  /// Kalau [preview.labaBersih] <= 0 (rugi/impas), TIDAK ADA pembayaran
  /// sama sekali (tidak masuk akal "membayar" bagian dari kerugian) —
  /// baris pembagian_laba tetap disimpan apa adanya untuk transparansi,
  /// tapi cash/bank tidak tersentuh.
  ///
  /// V5.9.7 — [metodePembayaran] sekarang CASH/TRANSFER/CAMPURAN (bukan
  /// cuma pilih satu sumber tunggal). Untuk CAMPURAN, [cashDibayar] +
  /// [transferDibayar] harus sama persis dengan total yang akan dibayar
  /// (divalidasi). Alokasi ke tiap partner/bonus dilakukan SEKUENSIAL:
  /// ambil dari pool Cash dulu sampai habis, sisanya dari pool Bank —
  /// jadi satu orang bisa saja dibayar sebagian cash sebagian transfer
  /// kalau pas di titik peralihan pool.
  Future<PembagianLabaModel> tutupBukuDanBagiLaba(
    int periodeId, {
    String metodePembayaran = AppConstants.metodeCash,
    double cashDibayar = 0,
    double transferDibayar = 0,
    String? jenisTransfer,
    bool settelKasbonDanTalang = false,
  }) async {
    requireWriteAccess();
    final periode = await _periodeRepo.getById(periodeId);
    if (periode == null) throw ArgumentError('Periode tidak ditemukan');
    if (!periode.isAktif) {
      throw StateError('Periode ini sudah ditutup sebelumnya.');
    }

    final preview = await hitungPreview(periodeId);
    final adaLabaUntukDibagi = preview.labaBersih > 0;

    // V5.9.4 — SAFETY GUARD: cegah DOBEL BAYAR kalau periode ini
    // sebelumnya SUDAH PERNAH ditutup (lalu dibuka lagi lewat
    // `bukaPeriode()` untuk koreksi, sesuai prinsip "Closing != Lock").
    // Menghitung ulang & membayar PENUH lagi di sini akan membayar dua
    // kali untuk bagian yang sudah dibayar di closing sebelumnya. Bukan
    // dicoba di-otomatisasi (rawan salah), TAPI diblokir dengan pesan
    // jelas supaya owner meninjau manual & tahu kenapa. Angka closing
    // SEBELUMNYA tidak hilang -- tetap ada sebagai histori permanen.
    final historiSebelumnya = await getHasilByPeriode(periodeId);
    if (historiSebelumnya != null) {
      throw StateError(
          'PERIODE INI SUDAH PERNAH DITUTUP SEBELUMNYA (${historiSebelumnya.createdAt}) '
          'dengan Laba Bersih Rp${historiSebelumnya.labaBersih.toStringAsFixed(0)}. '
          'Untuk mencegah pembayaran dobel, penutupan ulang otomatis '
          'dinonaktifkan. Bandingkan hasil closing lama vs preview baru '
          '(Rp${preview.labaBersih.toStringAsFixed(0)}) secara manual, lalu '
          'kalau memang ada selisih yang perlu dibayar/dikoreksi, catat lewat '
          'Pengeluaran/Modal secara manual dengan keterangan jelas.');
    }

    // V5.9.8 — BUG FIX KRITIS: baris-baris di bawah ini (hitung "sudah
    // diambil via Gajihan" per partner) SEBELUMNYA dipanggil DI DALAM
    // `db.transaction()` di bawah, lewat `GajihanRepository(db)` yang
    // internal-nya query pakai `this.db` (BUKAN `txn`). Memanggil
    // `db.query()` langsung pada `Database` yang sama SAAT SEDANG di
    // dalam `db.transaction()` miliknya sendiri membuat sqflite
    // DEADLOCK (transaksi menunggu lock yang justru dipegang oleh
    // dirinya sendiri) -- persis penyebab tombol "Tutup Buku & Bayar"
    // loading selamanya tanpa pernah selesai/gagal. Diperbaiki dengan
    // memindahkan SEMUA pembacaan read-only (sudah diambil, saldo
    // tersedia) ke SEBELUM transaction dibuka -- pola yang sama persis
    // sudah dipakai `GajihanRepository.prosesGajihan()` untuk alasan
    // yang sama.
    final gajihanRepo = GajihanRepository(db);
    final sudahDiambilAbah =
        await gajihanRepo.getTotalGajiDiambilPeriode('Abah', periodeId);
    final sudahDiambilIki =
        await gajihanRepo.getTotalGajiDiambilPeriode('Iki', periodeId);
    final sudahDiambilAndri =
        await gajihanRepo.getTotalGajiDiambilPeriode('Andri', periodeId);
    final sudahDiambilIlham =
        await gajihanRepo.getTotalGajiDiambilPeriode('Ilham', periodeId);

    final sisaAbah = !adaLabaUntukDibagi
        ? 0.0
        : (preview.bagianAbah - sudahDiambilAbah)
            .clamp(0, double.infinity)
            .toDouble();
    final sisaIki = !adaLabaUntukDibagi
        ? 0.0
        : (preview.bagianIki - sudahDiambilIki)
            .clamp(0, double.infinity)
            .toDouble();
    final sisaAndri = !adaLabaUntukDibagi
        ? 0.0
        : (preview.bagianAndri - sudahDiambilAndri)
            .clamp(0, double.infinity)
            .toDouble();
    final sisaIlham = !adaLabaUntukDibagi
        ? 0.0
        : (preview.bagianIlham - sudahDiambilIlham)
            .clamp(0, double.infinity)
            .toDouble();
    final totalAkanDibayar = !adaLabaUntukDibagi
        ? 0.0
        : sisaAbah +
            sisaIki +
            sisaAndri +
            sisaIlham +
            preview.totalHadiahPenjualan;

    // V5.9.10 — Settlement Kasbon & Dana Talang (opsional, per pilihan
    // user). SEBELUMNYA "Net Settlement" di layar Pembagian Laba
    // hanyalah PREVIEW -- tidak pernah benar-benar melunasi kasbon/dana
    // talang, jadi keduanya tetap outstanding & tetap muncul sebagai
    // Piutang di Modal Awal periode berikutnya walau closing sudah
    // "menghitungnya". Kalau [settelKasbonDanTalang] true, closing ini
    // JUGA benar-benar melunasi (bukan cuma menghitung):
    //   - Kasbon aktif tiap partner -> LUNAS (cash MASUK ke perusahaan)
    //   - Dana Talang SAYA_MENALANGI (piutang kita) -> LUNAS (cash MASUK)
    //   - Dana Talang SAYA_MENERIMA (hutang kita) -> LUNAS (cash KELUAR)
    // Kalau false (default), kasbon/dana talang TIDAK disentuh -- tetap
    // outstanding, bisa di-carry-forward atau diselesaikan manual lewat
    // layar Kasbon/Hubungan Partner (pilihan ini SENGAJA tidak dipaksa,
    // supaya carry-forward tetap jadi opsi yang valid).
    //
    // PENTING: SEMUA fetch di bawah ini terjadi SEBELUM transaction
    // dibuka. `KasbonRepository.getAll()`/
    // `DanaTalangRepository.getHubunganPerPartner()` keduanya query
    // pakai `this.db` (bukan `txn`) -- memanggilnya di dalam
    // `db.transaction()` sendiri akan DEADLOCK, PERSIS bug "sudah
    // diambil via Gajihan" (lihat komentar V5.9.8 di atas). EKSEKUSI
    // pembayarannya (bayarKasbonInTxn/bayarKembaliInTxn) baru terjadi
    // nanti DI DALAM transaction.
    final kasbonRepo = KasbonRepository(db);
    final danaTalangRepo = DanaTalangRepository(db);
    final kasbonAktifPerNama = <String, List<KasbonModel>>{};
    final danaTalangAktifPerNama = <String, List<DanaTalangModel>>{};
    double totalHutangSemuaPartner = 0; // dana talang SAYA_MENERIMA -> cash KELUAR
    double totalPiutangSemuaPartner = 0; // dana talang SAYA_MENALANGI -> cash MASUK
    double totalKasbonCashIn = 0; // kasbon sumber CASH -> cash MASUK
    double totalKasbonBankIn = 0; // kasbon sumber BANK -> bank MASUK
    if (settelKasbonDanTalang) {
      final hubunganSemua = await danaTalangRepo.getHubunganPerPartner();
      for (final nama in AppConstants.karyawanDefault) {
        final daftarKasbonPartner = (await kasbonRepo.getAll(namaKaryawan: nama))
            .where((k) => k.isAktif)
            .toList();
        kasbonAktifPerNama[nama] = daftarKasbonPartner;
        for (final k in daftarKasbonPartner) {
          if (k.sumber == AppConstants.sumberBank) {
            totalKasbonBankIn += k.sisa;
          } else {
            totalKasbonCashIn += k.sisa;
          }
        }

        final h = hubunganSemua.where((x) => x.namaPartner == nama);
        final riwayatAktif =
            h.isEmpty ? <DanaTalangModel>[] : h.first.riwayat.where((t) => t.isAktif && t.sisa > 0).toList();
        danaTalangAktifPerNama[nama] = riwayatAktif;
        totalHutangSemuaPartner += riwayatAktif
            .where((t) => t.jenis == AppConstants.danaTalangSayaMenerima)
            .fold<double>(0, (s, t) => s + t.sisa);
        totalPiutangSemuaPartner += riwayatAktif
            .where((t) => t.jenis == AppConstants.danaTalangSayaMenalangi)
            .fold<double>(0, (s, t) => s + t.sisa);
      }
    }

    double poolCash = 0;
    double poolBank = 0;
    if (totalAkanDibayar > 0) {
      if (metodePembayaran == AppConstants.metodeCampuran &&
          (cashDibayar + transferDibayar - totalAkanDibayar).abs() > 0.5) {
        throw ArgumentError(
            'Cash + Bank (Rp${(cashDibayar + transferDibayar).toStringAsFixed(0)}) '
            'harus sama dengan total yang akan dibayar '
            '(Rp${totalAkanDibayar.toStringAsFixed(0)})');
      }
      switch (metodePembayaran) {
        case AppConstants.metodeTransfer:
          poolCash = 0;
          poolBank = totalAkanDibayar;
          break;
        case AppConstants.metodeCampuran:
          poolCash = cashDibayar;
          poolBank = transferDibayar;
          break;
        case AppConstants.metodeCash:
        default:
          poolCash = totalAkanDibayar;
          poolBank = 0;
      }
    }

    if (totalAkanDibayar > 0 || totalHutangSemuaPartner > 0 || totalKasbonCashIn > 0) {
      // V5.9.11 — BUG FIX: sebelumnya hutang dana talang (cash KELUAR)
      // dihitung sebagai kebutuhan cash TAMBAHAN tanpa dikreditkan
      // dengan piutang dana talang (cash MASUK) & pelunasan kasbon
      // (cash/bank MASUK) yang terjadi DI TRANSAKSI YANG SAMA -- padahal
      // kalau piutang & hutang partner nilainya sama (netting sempurna,
      // efek cash bersih = 0), seharusnya TIDAK butuh cash ekstra sama
      // sekali. Diperbaiki: hitung saldo AKHIR (bersih, semua arus masuk
      // & keluar digabung), bukan cuma sisi keluarnya saja.
      final saldo = await SaldoRepository(db).getSaldo();
      final saldoCashAkhir = saldo.cash -
          poolCash -
          totalHutangSemuaPartner +
          totalPiutangSemuaPartner +
          totalKasbonCashIn;
      final saldoBankAkhir = saldo.saldoBank - poolBank + totalKasbonBankIn;
      if (saldoCashAkhir < -0.5) {
        throw StateError(
            'INSUFFICIENT_CASH: Setelah dinettokan (hak laba dibayar Rp${poolCash.toStringAsFixed(0)}, '
            'dana talang partner keluar Rp${totalHutangSemuaPartner.toStringAsFixed(0)}, '
            'dana talang partner masuk Rp${totalPiutangSemuaPartner.toStringAsFixed(0)}, '
            'kasbon masuk Rp${totalKasbonCashIn.toStringAsFixed(0)}), Cash akan MINUS '
            'Rp${(-saldoCashAkhir).toStringAsFixed(0)} (Cash tersedia sekarang '
            'Rp${saldo.cash.toStringAsFixed(0)}). Tutup buku DIBATALKAN, tidak ada '
            'perubahan yang tersimpan. Kurangi porsi Cash yang dibayar, matikan '
            '"Sekaligus Lunaskan", atau tambah Cash dulu.');
      }
      if (saldoBankAkhir < -0.5) {
        throw StateError(
            'INSUFFICIENT_CASH: Setelah dihitung (Bank dibayar Rp${poolBank.toStringAsFixed(0)}, '
            'kasbon Bank masuk Rp${totalKasbonBankIn.toStringAsFixed(0)}), Saldo Bank akan '
            'MINUS Rp${(-saldoBankAkhir).toStringAsFixed(0)} (Bank tersedia sekarang '
            'Rp${saldo.saldoBank.toStringAsFixed(0)}). Tutup buku DIBATALKAN, '
            'tidak ada perubahan yang tersimpan.');
      }
    }

    return db.transaction<PembagianLabaModel>((txn) async {
      final auditLog = AuditLogRepository(txn);
      final now = DateTime.now();

      final hasil = PembagianLabaModel(
        periodeId: periodeId,
        labaBersih: preview.labaBersih,
        bagianAbah: preview.bagianAbah,
        bagianIki: preview.bagianIki,
        bagianAndri: preview.bagianAndri,
        bagianIlham: preview.bagianIlham,
        totalHadiahPenjualan: preview.totalHadiahPenjualan,
        unitInternalTerjual: preview.unitInternalTerjual,
        bonusPerUnit: preview.bonusPerUnit,
        detailBonus: preview.detailBonus,
        createdAt: now,
      );

      final id = await txn.insert('pembagian_laba', hasil.toMap());
      final saved = PembagianLabaModel.fromMap({...hasil.toMap(), 'id': id});

      await auditLog.catatCreate(
        'pembagian_laba',
        id,
        jsonEncode(saved.toMap()),
        keterangan: 'Tutup buku periode "${periode.namaPeriode}"',
      );

      // ================================================================
      // EKSEKUSI PEMBAYARAN NYATA (Cash/Bank benar-benar berkurang)
      // Semua angka (sisaAbah..sisaIlham, totalAkanDibayar, poolCash,
      // poolBank) SUDAH dihitung & divalidasi SEBELUM transaction ini
      // dibuka (lihat komentar V5.9.8 di atas) -- di sini tinggal pakai.
      // ================================================================
      if (adaLabaUntukDibagi && totalAkanDibayar > 0) {
        double poolCashSisa = poolCash;
        double poolBankSisa = poolBank;

        // Alokasi SEKUENSIAL: ambil dari pool Cash dulu sampai habis,
        // sisanya dari pool Bank. Untuk CASH/TRANSFER murni, salah
        // satu pool selalu 0 jadi otomatis semua dari 1 sumber saja.
        (double cash, double bank) alokasikan(double nominal) {
          final dariCash =
              nominal <= poolCashSisa ? nominal : poolCashSisa;
          poolCashSisa -= dariCash;
          final sisaSetelahCash = nominal - dariCash;
          final dariBank =
              sisaSetelahCash <= poolBankSisa ? sisaSetelahCash : poolBankSisa;
          poolBankSisa -= dariBank;
          return (dariCash, dariBank);
        }

          final pengeluaranRepo = PengeluaranRepository(db);
          Future<void> bayar(String namaPartner, double sisaNominal,
              double sudahDiambil) async {
            if (sisaNominal <= 0) return;
            final (dariCash, dariBank) = alokasikan(sisaNominal);
            final keteranganDasar =
                'Distribusi laba periode "${periode.namaPeriode}" - '
                '$namaPartner (sisa setelah dikurangi Rp${sudahDiambil.toStringAsFixed(0)} '
                'yang sudah diambil via Gajihan periode ini)';
            if (dariCash > 0) {
              await pengeluaranRepo.tambahPengeluaranInTxn(
                txn,
                tanggal: now,
                kategori: AppConstants.kategoriDistribusiLabaPartner,
                nominal: dariCash,
                sumber: AppConstants.sumberCash,
                keterangan: dariBank > 0
                    ? '$keteranganDasar (porsi cash)'
                    : keteranganDasar,
                periodeId: periodeId,
                referensiId: id,
              );
            }
            if (dariBank > 0) {
              await pengeluaranRepo.tambahPengeluaranInTxn(
                txn,
                tanggal: now,
                kategori: AppConstants.kategoriDistribusiLabaPartner,
                nominal: dariBank,
                sumber: AppConstants.sumberBank,
                jenisTransfer: jenisTransfer,
                keterangan: dariCash > 0
                    ? '$keteranganDasar (porsi bank)'
                    : keteranganDasar,
                periodeId: periodeId,
                referensiId: id,
              );
            }
          }

          await bayar('Abah', sisaAbah, sudahDiambilAbah);
          await bayar('Iki', sisaIki, sudahDiambilIki);
          await bayar('Andri', sisaAndri, sudahDiambilAndri);
          await bayar('Ilham', sisaIlham, sudahDiambilIlham);

          for (final b in preview.detailBonus) {
            if (b.totalBonus <= 0) continue;
            final (dariCash, dariBank) = alokasikan(b.totalBonus);
            final keteranganDasar =
                'Bonus penjualan periode "${periode.namaPeriode}" - ${b.nama} '
                '(${b.jumlahUnit} unit)';
            if (dariCash > 0) {
              await pengeluaranRepo.tambahPengeluaranInTxn(
                txn,
                tanggal: now,
                kategori: AppConstants.kategoriBonusPenjualan,
                nominal: dariCash,
                sumber: AppConstants.sumberCash,
                keterangan: dariBank > 0
                    ? '$keteranganDasar (porsi cash)'
                    : keteranganDasar,
                periodeId: periodeId,
                referensiId: id,
              );
            }
            if (dariBank > 0) {
              await pengeluaranRepo.tambahPengeluaranInTxn(
                txn,
                tanggal: now,
                kategori: AppConstants.kategoriBonusPenjualan,
                nominal: dariBank,
                sumber: AppConstants.sumberBank,
                jenisTransfer: jenisTransfer,
                keterangan: dariCash > 0
                    ? '$keteranganDasar (porsi bank)'
                    : keteranganDasar,
                periodeId: periodeId,
                referensiId: id,
              );
            }
          }

          await auditLog.catatCreate(
            'pembagian_laba',
            id,
            jsonEncode(saved.toMap()),
            keterangan: 'PEMBAYARAN CLOSING: Total Rp${totalAkanDibayar.toStringAsFixed(0)} '
                'dibayar via $metodePembayaran (Abah/Iki/Andri/Ilham + bonus '
                'penjualan per penjual). Cash/Bank berkurang sejumlah ini.',
          );
      } else {
        await auditLog.catatCreate(
          'pembagian_laba',
          id,
          jsonEncode(saved.toMap()),
          keterangan: 'Laba bersih periode ini Rp${preview.labaBersih.toStringAsFixed(0)} '
              '(<= 0) — TIDAK ADA pembayaran distribusi/bonus.',
        );
      }

      // ================================================================
      // SETTLEMENT KASBON & DANA TALANG (opsional, `settelKasbonDanTalang`)
      // ================================================================
      if (settelKasbonDanTalang) {
        final kasbonRepoTxn = KasbonRepository(db);
        final danaTalangRepoTxn = DanaTalangRepository(db);
        for (final nama in AppConstants.karyawanDefault) {
          // Kasbon aktif -> lunaskan penuh (cash/bank MASUK sesuai
          // sumber asal kasbon masing-masing, ditangani otomatis oleh
          // bayarKasbonInTxn). Daftar SUDAH di-fetch sebelum transaction
          // (lihat komentar V5.9.10 di atas) -- di sini tinggal eksekusi.
          for (final k in kasbonAktifPerNama[nama] ?? const []) {
            await kasbonRepoTxn.bayarKasbonInTxn(txn, k.id!, tanggalLunas: now);
          }

          // Dana talang -- kedua arah, lunaskan penuh.
          for (final t in danaTalangAktifPerNama[nama] ?? const []) {
            await danaTalangRepoTxn.bayarKembaliInTxn(
              txn,
              danaTalangId: t.id!,
              tanggal: now,
              nominal: t.sisa,
              metodePembayaran: AppConstants.metodeCash,
              cashDibayar: t.sisa,
              keterangan:
                  'Settlement otomatis saat Tutup Buku periode "${periode.namaPeriode}"',
            );
          }
        }
        await auditLog.catatCreate(
          'pembagian_laba',
          id,
          jsonEncode(saved.toMap()),
          keterangan: 'SETTLEMENT KASBON & DANA TALANG: seluruh kasbon dan '
              'dana talang aktif tiap partner dilunaskan sebagai bagian dari '
              'closing ini (opsi "Sekaligus Lunaskan" aktif).',
        );
      }

      // Update status periode -> TUTUP
      final periodeLamaMap = periode.toMap();
      final periodeBaru = periode.copyWith(
        status: AppConstants.statusPeriodeTutup,
        tanggalSelesai: now,
        updatedAt: now,
      );
      await txn.update('periode', periodeBaru.toMap(),
          where: 'id = ?', whereArgs: [periodeId]);
      await auditLog.catatUpdate(
        'periode',
        periodeId,
        jsonEncode(periodeLamaMap),
        jsonEncode(periodeBaru.toMap()),
        keterangan: 'Tutup buku & pembagian laba',
      );

      return saved;
    });
  }

  Future<PembagianLabaModel?> getHasilByPeriode(int periodeId) async {
    final result = await db.query(
      'pembagian_laba',
      where: 'periode_id = ?',
      whereArgs: [periodeId],
      limit: 1,
    );
    if (result.isEmpty) return null;
    return PembagianLabaModel.fromMap(result.first);
  }

  Future<List<PembagianLabaModel>> getSemuaHistori() async {
    final result =
        await db.query('pembagian_laba', orderBy: 'created_at DESC');
    return result.map((e) => PembagianLabaModel.fromMap(e)).toList();
  }
}

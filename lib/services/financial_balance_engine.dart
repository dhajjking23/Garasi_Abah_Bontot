import 'package:sqflite/sqflite.dart';
import 'dashboard_service.dart';
import 'pembagian_laba_service.dart';
import '../repositories/periode_repository.dart';

/// V5.9.2 — FINANCIAL BALANCE ENGINE.
///
/// Read-only, murni kalkulasi — TIDAK MENULIS apa pun ke database, TIDAK
/// mengunci apa pun. Tujuannya cuma satu: pastikan
///
///     TOTAL ASET = TOTAL KEWAJIBAN + MODAL + LABA
///
/// dan kalau tidak balance, tunjukkan komponen apa saja yang membentuk
/// tiap sisi supaya selisihnya bisa ditelusuri — bukan cuma "Error".
///
/// SEMUA angka diambil dari service/repository yang SUDAH ADA (tidak ada
/// query baru yang menduplikasi logika sumber): DashboardService untuk
/// Aset & Kewajiban & Modal saat ini, plus histori `pembagian_laba`
/// (tabel yang sudah ada sejak PembagianLabaService) untuk akumulasi
/// Laba, dan PembagianLabaService.hitungPreview() (sumber kebenaran yang
/// SAMA dipakai tombol "Tutup Buku") untuk laba periode berjalan.
///
/// KOREKSI V5.9.2 (Audit Gate — Section C):
/// Versi sebelumnya menghitung laba periode berjalan dari
/// `labaPerubahanModal = totalAset - modalAwalPeriode` (LaporanService),
/// yaitu formula "TOTAL ASSET - MODAL = LABA" yang EKSPLISIT DILARANG
/// (Mega Prompt §4/§15, Invariant 2/3) — dan lebih parah lagi `totalAset`
/// di formula itu memakai SALDO GLOBAL SAAT INI (bukan "as of" tanggal
/// tertentu), dicampur dengan `modalAwalPeriode` yang PERIOD-SPECIFIC
/// (melanggar §3/Section D — global vs period tidak boleh campur). Efek
/// gabungannya: pengecekan balance jadi sebagian tautologis (karena
/// komponen laba itu sendiri didefinisikan dari totalAset yang sedang
/// diperiksa), bukan validasi independen.
///
/// Perbaikan: laba periode berjalan SEKARANG dihitung dari aktivitas
/// ekonomi sungguhan (Revenue motor - Cost motor - Biaya operasional),
/// persis rumus yang sama dipakai `PembagianLabaService.hitungPreview()`
/// (satu-satunya sumber kebenaran untuk "Tutup Buku & Bagi Laba" — kalau
/// dua tempat ini pernah beda angka, itu sendiri adalah bug yang harus
/// terlihat, bukan disembunyikan lewat formula lain).
/// `LaporanService.labaPerubahanModal` TIDAK dihapus (histori/diagnostik
/// tetap ada di layar Laporan sebagai info selisih), tapi TIDAK LAGI
/// dipakai sebagai komponen laba di sini.
///
/// CATATAN JUJUR soal selisih (WAJIB dibaca sebelum menganggap
/// "TIDAK BALANCE" = bug):
/// Aplikasi ini TIDAK mencatat "penarikan tunai laba oleh partner" sebagai
/// transaksi tersendiri — PartnerSettlementService (V5.8) SENGAJA hanya
/// menghitung, tidak memindahkan uang (P0-1, belum diimplementasikan).
/// Artinya laba yang sudah "dibagi" (tutup buku) tetap dianggap
/// "mengendap" di Cash/Bank sampai owner benar-benar mencatatnya (lewat
/// Pengeluaran atau pengurangan Modal). Kalau owner pernah membayar tunai
/// ke partner TANPA mencatatnya di aplikasi, Aset (Cash) akan lebih kecil
/// dari yang seharusnya dan selisih TIDAK akan nol — itu bukan bug engine
/// ini, itu justru tujuannya: mendeteksi uang yang "hilang" dari sistem.
class BalanceComponent {
  final String label;
  final double nilai;
  BalanceComponent(this.label, this.nilai);
}

class FinancialBalanceReport {
  final List<BalanceComponent> asetBreakdown;
  final List<BalanceComponent> kewajibanBreakdown;
  final double modal;
  final double labaAkumulasi;
  final double labaPeriodeBerjalan;

  FinancialBalanceReport({
    required this.asetBreakdown,
    required this.kewajibanBreakdown,
    required this.modal,
    required this.labaAkumulasi,
    required this.labaPeriodeBerjalan,
  });

  double get totalAset => asetBreakdown.fold(0, (s, c) => s + c.nilai);
  double get totalKewajiban => kewajibanBreakdown.fold(0, (s, c) => s + c.nilai);
  double get totalLaba => labaAkumulasi + labaPeriodeBerjalan;
  double get totalEquity => modal + totalLaba;
  double get expected => totalKewajiban + totalEquity;
  double get selisih => totalAset - expected;
  bool get isBalance => selisih.abs() < 1; // toleransi Rp1 pembulatan double
}

class FinancialBalanceEngine {
  final Database db;
  late final DashboardService _dashboardService;
  late final PembagianLabaService _pembagianLabaService;
  late final PeriodeRepository _periodeRepo;

  FinancialBalanceEngine(this.db) {
    _dashboardService = DashboardService(db);
    _pembagianLabaService = PembagianLabaService(db);
    _periodeRepo = PeriodeRepository(db);
  }

  /// LIABILITIES + EQUITY (Kewajiban + Modal + Laba Akumulasi + Laba
  /// Periode Berjalan) — dipisah dari `hitung()` supaya bisa dipanggil
  /// terpisah oleh service lain (mis. ClosingSnapshotService) tanpa
  /// menduplikasi rumus.
  Future<double> calculateAssets() async {
    final r = await hitung();
    return r.totalAset;
  }

  Future<double> calculateLiabilities() async {
    final r = await hitung();
    return r.totalKewajiban;
  }

  /// Retained earnings = akumulasi SEMUA laba periode yang pernah
  /// ditutup buku (histori permanen di tabel `pembagian_laba`, tidak
  /// pernah dihapus/di-overwrite).
  Future<double> calculateRetainedEarnings() async {
    final labaHistoris = await db.rawQuery(
      'SELECT COALESCE(SUM(laba_bersih), 0) as total FROM pembagian_laba',
    );
    return (labaHistoris.first['total'] as num).toDouble();
  }

  /// Laba periode AKTIF yang BELUM ditutup buku, dihitung dari aktivitas
  /// ekonomi sungguhan (Revenue motor - Cost motor - Biaya operasional)
  /// — BUKAN dari perubahan aset. Sumbernya SAMA PERSIS dengan yang
  /// dipakai tombol "Tutup Buku & Bagi Laba" (PembagianLabaService),
  /// supaya preview di Balance Engine tidak pernah berbeda dengan angka
  /// final saat closing sungguhan terjadi.
  Future<double> calculatePeriodProfit() async {
    final periodeAktif = await _periodeRepo.getPeriodeAktif();
    if (periodeAktif?.id == null) return 0;
    final preview = await _pembagianLabaService.hitungPreview(periodeAktif!.id!);
    return preview.labaBersih;
  }

  Future<double> calculateEquity() async {
    final r = await hitung();
    return r.totalEquity;
  }

  Future<FinancialBalanceReport> reconcileBalance() => hitung();

  Future<FinancialBalanceReport> hitung() async {
    final summary = await _dashboardService.getSummary();
    final labaAkumulasi = await calculateRetainedEarnings();
    final labaPeriodeBerjalan = await calculatePeriodProfit();

    return FinancialBalanceReport(
      asetBreakdown: [
        BalanceComponent('Cash', summary.cash),
        BalanceComponent('Bank', summary.saldoBank),
        BalanceComponent('Nilai Stok Motor', summary.nilaiStokMotor),
        BalanceComponent('Piutang Penjualan (DP)', summary.piutangPenjualan),
        BalanceComponent('Piutang Kasbon', summary.piutangKasbon),
        BalanceComponent('Piutang Partner (Dana Talang)', summary.piutangPartner),
      ],
      kewajibanBreakdown: [
        BalanceComponent('Hutang Partner (Dana Talang)', summary.hutangPartner),
      ],
      modal: summary.modal,
      labaAkumulasi: labaAkumulasi,
      labaPeriodeBerjalan: labaPeriodeBerjalan,
    );
  }
}

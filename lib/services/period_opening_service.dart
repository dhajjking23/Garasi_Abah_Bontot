import 'package:sqflite/sqflite.dart';
import '../core/constants/app_constants.dart';
import '../models/periode_model.dart';
import '../repositories/periode_repository.dart';
import 'financial_balance_engine.dart';

/// V5.9.4 — Orkestrasi "buka periode baru dengan carry-forward dari
/// closing sebelumnya" (Mega Prompt Section M/§19-21).
///
/// Sengaja jadi SERVICE terpisah (bukan method di [PeriodeRepository]
/// langsung) supaya bisa memakai [FinancialBalanceEngine] (lib/services)
/// untuk validasi live TANPA membuat circular import repository<->service
/// ([PeriodeRepository] tetap murni tidak tahu-menahu soal
/// FinancialBalanceEngine).
class PeriodOpeningService {
  final Database db;
  late final FinancialBalanceEngine _engine;
  late final PeriodeRepository _periodeRepo;

  PeriodOpeningService(this.db)
      : _engine = FinancialBalanceEngine(db),
        _periodeRepo = PeriodeRepository(db);

  /// Hitung total aset perusahaan SAAT INI — dipakai UI untuk
  /// menampilkan "Modal Awal Periode Baru" sebelum user konfirmasi.
  Future<double> hitungTotalAsetUntukOpening() => _engine.calculateAssets();

  /// Buka periode baru. [totalAsetOtomatis] adalah angka OTOMATIS
  /// (hasil [hitungTotalAsetUntukOpening]) yang ditampilkan & sudah
  /// dikonfirmasi user di UI. Method ini MENGHITUNG ULANG secara live
  /// dan membandingkan TERHADAP ANGKA OTOMATIS INI (bukan angka yang
  /// sudah diedit user) — kalau beda (mis. ada transaksi baru masuk
  /// sejak user melihat ringkasan), MELEMPAR [StateError]
  /// "OPENING BALANCE MISMATCH" dan TIDAK membuat periode apa pun.
  ///
  /// V5.9.9 — [modalAwalFinal] adalah nilai Modal Awal SETELAH user
  /// edit manual (kalau null atau sama dengan [totalAsetOtomatis],
  /// berarti tidak diedit). Selisihnya (`modalAwalFinal -
  /// totalAsetOtomatis`) BENAR-BENAR disuntik/ditarik dari Cash/Bank
  /// sungguhan via [metodePembayaranSelisih]/[cashSelisih]/[bankSelisih]
  /// (bukan cuma mengubah angka referensi) — lihat
  /// `SaldoRepository.sesuaikanModalAwalPeriode`.
  Future<PeriodeModel> bukaPeriodeBaruDariClosing({
    required String namaPeriode,
    required DateTime tanggalMulai,
    required double totalAsetOtomatis,
    double? modalAwalFinal,
    String metodePembayaranSelisih = AppConstants.metodeCash,
    double cashSelisih = 0,
    double bankSelisih = 0,
    bool arsipkanTransaksiLunas = true,
  }) async {
    final asetSekarang = await _engine.calculateAssets();
    if ((asetSekarang - totalAsetOtomatis).abs() > 1) {
      throw StateError(
          'OPENING BALANCE MISMATCH: Total aset perusahaan SAAT INI '
          '(Rp${asetSekarang.toStringAsFixed(0)}) berbeda dari yang '
          'dikonfirmasi sebelumnya (Rp${totalAsetOtomatis.toStringAsFixed(0)}), '
          'selisih Rp${(asetSekarang - totalAsetOtomatis).toStringAsFixed(0)}. '
          'Kemungkinan ada transaksi baru masuk sejak ringkasan closing '
          'ditampilkan. Muat ulang ringkasan dan coba lagi. Periode baru '
          'TIDAK dibuat.');
    }

    final modalFinal = modalAwalFinal ?? asetSekarang;
    final selisih = modalFinal - asetSekarang;

    return _periodeRepo.buatPeriodeCarryForward(
      namaPeriode: namaPeriode,
      tanggalMulai: tanggalMulai,
      totalAsetAkhirClosing: modalFinal,
      arsipkanTransaksiLunas: arsipkanTransaksiLunas,
      selisihModal: selisih,
      metodePembayaranSelisih: metodePembayaranSelisih,
      cashSelisih: cashSelisih,
      bankSelisih: bankSelisih,
    );
  }
}

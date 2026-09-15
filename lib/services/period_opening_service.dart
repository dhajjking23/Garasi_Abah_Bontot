import 'package:sqflite/sqflite.dart';
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

  /// Buka periode baru. [totalAsetAkhirClosing] adalah angka yang
  /// ditampilkan & dikonfirmasi user di UI (hasil pemanggilan
  /// [hitungTotalAsetUntukOpening] sebelumnya). Method ini MENGHITUNG
  /// ULANG secara live dan membandingkan — kalau beda (mis. ada transaksi
  /// baru masuk sejak user melihat ringkasan), MELEMPAR [StateError]
  /// "OPENING BALANCE MISMATCH" dan TIDAK membuat periode apa pun.
  Future<PeriodeModel> bukaPeriodeBaruDariClosing({
    required String namaPeriode,
    required DateTime tanggalMulai,
    required double totalAsetAkhirClosing,
    bool arsipkanTransaksiLunas = true,
  }) async {
    final asetSekarang = await _engine.calculateAssets();
    if ((asetSekarang - totalAsetAkhirClosing).abs() > 1) {
      throw StateError(
          'OPENING BALANCE MISMATCH: Total aset perusahaan SAAT INI '
          '(Rp${asetSekarang.toStringAsFixed(0)}) berbeda dari yang '
          'dikonfirmasi sebelumnya (Rp${totalAsetAkhirClosing.toStringAsFixed(0)}), '
          'selisih Rp${(asetSekarang - totalAsetAkhirClosing).toStringAsFixed(0)}. '
          'Kemungkinan ada transaksi baru masuk sejak ringkasan closing '
          'ditampilkan. Muat ulang ringkasan dan coba lagi. Periode baru '
          'TIDAK dibuat.');
    }

    return _periodeRepo.buatPeriodeCarryForward(
      namaPeriode: namaPeriode,
      tanggalMulai: tanggalMulai,
      totalAsetAkhirClosing: asetSekarang,
      arsipkanTransaksiLunas: arsipkanTransaksiLunas,
    );
  }
}

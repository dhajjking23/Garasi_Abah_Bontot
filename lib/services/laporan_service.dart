import 'package:sqflite/sqflite.dart';
import '../core/constants/app_constants.dart';
import '../repositories/motor_repository.dart';
import '../repositories/penjualan_repository.dart';
import '../repositories/pengeluaran_repository.dart';
import '../repositories/pemasukan_repository.dart';
import '../repositories/saldo_repository.dart';
import '../repositories/kasbon_repository.dart';
import '../repositories/dana_talang_repository.dart';
import '../repositories/periode_repository.dart';
import '../repositories/biaya_transfer_manual_repository.dart';
import '../models/penjualan_model.dart';
import '../models/motor_model.dart';

class LabaPerMotor {
  final MotorModel motor;
  final PenjualanModel penjualan;
  double get laba => penjualan.laba;
  LabaPerMotor(this.motor, this.penjualan);
}

class LaporanPeriodeData {
  // Motor & Penjualan (khusus periode aktif)
  final List<LabaPerMotor> labaPerMotor;
  final Map<String, double> pengeluaranPerKategori;
  final Map<String, int> penjualanPerOrang;
  final double totalLabaMotor;
  final double totalPengeluaran;
  final double totalPemasukan;
  final double totalPenjualan;
  final double labaPerUnitRataRata;

  /// Bagian "Pengeluaran per Kategori" TIDAK termasuk biaya admin bank —
  /// dipisah sendiri di sini sesuai spesifikasi poin #9.
  final double totalAdministrasiBank;

  /// Total biaya transfer yang dicatat manual lewat menu Biaya Transfer
  /// (V3.1 Patch #4) — terpisah dari totalAdministrasiBank yang otomatis
  /// dari pengeluaran, tapi digabung di totalBiayaTransferGabungan.
  final double totalBiayaTransferManual;
  final double totalBiayaTransferGabungan;

  /// V4.2.1 — breakdown biaya transfer per jenis (Gratis/BI_FAST/REALTIME),
  /// digabung dari SEMUA sumber (pengeluaran, motor, motor_cost,
  /// dana_talang, kasbon, biaya_transfer_manual). Key: AppConstants
  /// jenisTransferGratis/BiFast/Realtime.
  final Map<String, double> totalBiayaTransferPerJenis;

  // KEUANGAN (kondisi saat ini, bukan spesifik-periode)
  final double modal;
  final double cash;
  final double saldoBank;
  final double totalAset;

  /// Modal Awal periode aktif (snapshot immutable, BUKAN cashflow —
  /// lihat PeriodeModel.modalAwal). Dipakai untuk menghitung laba versi
  /// akuntansi "perubahan modal", terpisah dari totalLabaMotor yang
  /// dihitung per-transaksi penjualan.
  final double modalAwalPeriode;

  /// Laba berdasarkan perubahan modal = Total Aset saat ini - Modal
  /// Awal periode. Sesuai spesifikasi: "Modal tetap, laba dihitung dari
  /// perubahan nilai aset dibanding modal awal."
  final double labaPerubahanModal;

  // MOTOR (kondisi stok saat ini)
  final int jumlahStokTersedia;
  final int jumlahTerjualPeriode;
  final double nilaiStok;

  // DANA TALANG
  final double piutangPartner;
  final double hutangPartner;
  final double piutangKasbon;
  final double piutangPenjualan;

  LaporanPeriodeData({
    required this.labaPerMotor,
    required this.pengeluaranPerKategori,
    required this.penjualanPerOrang,
    required this.totalLabaMotor,
    required this.totalPengeluaran,
    required this.totalPemasukan,
    required this.totalPenjualan,
    required this.labaPerUnitRataRata,
    required this.totalAdministrasiBank,
    required this.totalBiayaTransferManual,
    required this.totalBiayaTransferGabungan,
    required this.totalBiayaTransferPerJenis,
    required this.modal,
    required this.cash,
    required this.saldoBank,
    required this.totalAset,
    required this.modalAwalPeriode,
    required this.labaPerubahanModal,
    required this.jumlahStokTersedia,
    required this.jumlahTerjualPeriode,
    required this.nilaiStok,
    required this.piutangPartner,
    required this.hutangPartner,
    required this.piutangKasbon,
    required this.piutangPenjualan,
  });
}

/// Service agregasi untuk halaman Laporan. Menggabungkan data dari
/// beberapa repository menjadi struktur siap-tampil dan siap-export,
/// sesuai spesifikasi "Laporan Realtime Terpusat" (poin #10): semua
/// angka diambil langsung dari database, bukan dihitung manual.
class LaporanService {
  final Database db;
  late final MotorRepository _motorRepo;
  late final PenjualanRepository _penjualanRepo;
  late final PengeluaranRepository _pengeluaranRepo;
  late final PemasukanRepository _pemasukanRepo;
  late final SaldoRepository _saldoRepo;
  late final KasbonRepository _kasbonRepo;
  late final DanaTalangRepository _danaTalangRepo;
  late final PeriodeRepository _periodeRepo;
  late final BiayaTransferManualRepository _biayaTransferManualRepo;

  LaporanService(this.db) {
    _motorRepo = MotorRepository(db);
    _penjualanRepo = PenjualanRepository(db);
    _pengeluaranRepo = PengeluaranRepository(db);
    _pemasukanRepo = PemasukanRepository(db);
    _saldoRepo = SaldoRepository(db);
    _kasbonRepo = KasbonRepository(db);
    _danaTalangRepo = DanaTalangRepository(db);
    _periodeRepo = PeriodeRepository(db);
    _biayaTransferManualRepo = BiayaTransferManualRepository(db);
  }

  Future<LaporanPeriodeData> getLaporanPeriode(int periodeId) async {
    final semuaPenjualan = await _penjualanRepo.getAll(periodeId: periodeId);

    final labaPerMotor = <LabaPerMotor>[];
    for (final p in semuaPenjualan) {
      final motor = await _motorRepo.getById(p.motorId);
      if (motor != null) {
        labaPerMotor.add(LabaPerMotor(motor, p));
      }
    }

    final semuaPengeluaran =
        await _pengeluaranRepo.getAll(periodeId: periodeId);
    // Pengeluaran per kategori HANYA nilai barang/jasa (nominal), biaya
    // admin bank dipisah ke totalAdministrasiBank supaya tidak tercampur.
    final pengeluaranPerKategori = <String, double>{};
    double totalAdministrasiBank = 0;
    for (final p in semuaPengeluaran) {
      pengeluaranPerKategori[p.kategori] =
          (pengeluaranPerKategori[p.kategori] ?? 0) + p.nominal;
      totalAdministrasiBank += p.biayaAdmin;
    }

    final penjualanPerOrang =
        await _penjualanRepo.getJumlahUnitPerPenjual(periodeId);

    final semuaPemasukan = await _pemasukanRepo.getAll(periodeId: periodeId);
    final totalPemasukan =
        semuaPemasukan.fold<double>(0, (sum, p) => sum + p.nominal);
    final totalPengeluaranBarang =
        semuaPengeluaran.fold<double>(0, (sum, p) => sum + p.nominal);
    final totalLabaMotor =
        semuaPenjualan.fold<double>(0, (sum, p) => sum + p.laba);
    final totalPenjualan =
        semuaPenjualan.fold<double>(0, (sum, p) => sum + p.hargaJual);
    final labaPerUnit = semuaPenjualan.isEmpty
        ? 0.0
        : totalLabaMotor / semuaPenjualan.length;

    final saldo = await _saldoRepo.getSaldo();
    final nilaiStok = await _motorRepo.getTotalNilaiStok();
    final stokTersedia = await _motorRepo.getStokTersedia();
    final piutangKasbon = await _kasbonRepo.getTotalPiutangBelumLunas();
    final piutangPenjualan = await _penjualanRepo.getTotalPiutangPenjualan();
    final piutangPartner = await _danaTalangRepo.getTotalPiutangPartner();
    final hutangPartner = await _danaTalangRepo.getTotalHutangPartner();

    final totalAset = saldo.cash +
        saldo.saldoBank +
        nilaiStok +
        piutangKasbon +
        piutangPenjualan +
        piutangPartner;

    final periode = await _periodeRepo.getById(periodeId);
    final modalAwalPeriode = periode?.modalAwal ?? 0;
    // Laba versi akuntansi "perubahan modal" (spesifikasi V3 #1): Modal
    // TIDAK berubah karena transaksi, laba = selisih Total Aset saat ini
    // dengan Modal Awal periode. Ini pelengkap, BUKAN pengganti
    // totalLabaMotor (laba per-transaksi penjualan) yang tetap dipakai
    // untuk pembagian hadiah per motor.
    final labaPerubahanModal = totalAset - modalAwalPeriode;

    final totalBiayaTransferManual =
        await _biayaTransferManualRepo.getTotal(periodeId: periodeId);

    // V4.2.1 — PAYMENT FLOW GLOBAL: biaya transfer sekarang tersebar di
    // banyak tabel (bukan cuma pengeluaran), jumlahkan semuanya untuk
    // laporan Total Biaya Transfer Periode.
    final motorFeeResult = await db.rawQuery(
      'SELECT COALESCE(SUM(biaya_admin_transfer),0) as total FROM motor WHERE periode_id = ?',
      [periodeId],
    );
    final totalBiayaTransferMotor =
        (motorFeeResult.first['total'] as num).toDouble();

    final motorCostFeeResult = await db.rawQuery('''
      SELECT COALESCE(SUM(mc.biaya_admin_transfer),0) as total
      FROM motor_cost mc
      JOIN motor m ON mc.motor_id = m.id
      WHERE m.periode_id = ?
    ''', [periodeId]);
    final totalBiayaTransferMotorCost =
        (motorCostFeeResult.first['total'] as num).toDouble();

    final danaTalangFeeResult = await db.rawQuery(
      'SELECT COALESCE(SUM(biaya_admin_transfer),0) as total FROM dana_talang WHERE periode_id = ?',
      [periodeId],
    );
    final totalBiayaTransferDanaTalang =
        (danaTalangFeeResult.first['total'] as num).toDouble();

    // Kasbon TIDAK punya periode_id (konsisten dengan desain existing —
    // piutang kasbon juga dihitung global, bukan per periode), jadi
    // biayanya dijumlahkan global juga, bukan per periode.
    final kasbonFeeResult = await db.rawQuery(
      'SELECT COALESCE(SUM(biaya_admin_transfer),0) as total FROM kasbon',
    );
    final totalBiayaTransferKasbon =
        (kasbonFeeResult.first['total'] as num).toDouble();

    final totalBiayaTransferLainnya = totalBiayaTransferMotor +
        totalBiayaTransferMotorCost +
        totalBiayaTransferDanaTalang +
        totalBiayaTransferKasbon;

    // Breakdown per jenis (Gratis/BI_FAST/Realtime) digabung dari SEMUA
    // sumber, sesuai spesifikasi laporan biaya transfer V4.2.1.
    final totalBiayaTransferPerJenis = <String, double>{
      AppConstants.jenisTransferGratis: 0,
      AppConstants.jenisTransferBiFast: 0,
      AppConstants.jenisTransferRealtime: 0,
    };

    Future<void> tambahBreakdown(String query, List<Object?> args) async {
      final rows = await db.rawQuery(query, args);
      for (final r in rows) {
        final jenis = r['jenis_transfer'] as String?;
        final total = (r['total'] as num?)?.toDouble() ?? 0;
        if (jenis == null || total <= 0) continue;
        totalBiayaTransferPerJenis[jenis] =
            (totalBiayaTransferPerJenis[jenis] ?? 0) + total;
      }
    }

    await tambahBreakdown(
      'SELECT jenis_transfer, SUM(biaya_admin) as total FROM pengeluaran WHERE periode_id = ? AND biaya_admin > 0 GROUP BY jenis_transfer',
      [periodeId],
    );
    await tambahBreakdown(
      'SELECT jenis_transfer, SUM(biaya_admin_transfer) as total FROM motor WHERE periode_id = ? AND biaya_admin_transfer > 0 GROUP BY jenis_transfer',
      [periodeId],
    );
    await tambahBreakdown('''
      SELECT mc.jenis_transfer, SUM(mc.biaya_admin_transfer) as total
      FROM motor_cost mc JOIN motor m ON mc.motor_id = m.id
      WHERE m.periode_id = ? AND mc.biaya_admin_transfer > 0
      GROUP BY mc.jenis_transfer
    ''', [periodeId]);
    await tambahBreakdown(
      'SELECT jenis_transfer, SUM(biaya_admin_transfer) as total FROM dana_talang WHERE periode_id = ? AND biaya_admin_transfer > 0 GROUP BY jenis_transfer',
      [periodeId],
    );
    await tambahBreakdown(
      'SELECT jenis_transfer, SUM(biaya_admin_transfer) as total FROM kasbon WHERE biaya_admin_transfer > 0 GROUP BY jenis_transfer',
      [],
    );
    // Catatan: biaya_transfer_manual TIDAK punya kolom jenis (Gratis/BI
    // FAST/Realtime) — sudah tercatat sebagai totalBiayaTransferManual
    // terpisah (lihat totalBiayaTransferGabungan), tidak ikut breakdown
    // per jenis di totalBiayaTransferPerJenis.

    return LaporanPeriodeData(
      labaPerMotor: labaPerMotor,
      pengeluaranPerKategori: pengeluaranPerKategori,
      penjualanPerOrang: penjualanPerOrang,
      totalLabaMotor: totalLabaMotor,
      totalPengeluaran: totalPengeluaranBarang + totalAdministrasiBank,
      totalPemasukan: totalPemasukan,
      totalPenjualan: totalPenjualan,
      labaPerUnitRataRata: labaPerUnit,
      totalAdministrasiBank: totalAdministrasiBank,
      totalBiayaTransferManual: totalBiayaTransferManual,
      totalBiayaTransferGabungan: totalAdministrasiBank +
          totalBiayaTransferManual +
          totalBiayaTransferLainnya,
      totalBiayaTransferPerJenis: totalBiayaTransferPerJenis,
      modal: saldo.modalTotal,
      cash: saldo.cash,
      saldoBank: saldo.saldoBank,
      totalAset: totalAset,
      modalAwalPeriode: modalAwalPeriode,
      labaPerubahanModal: labaPerubahanModal,
      jumlahStokTersedia: stokTersedia.length,
      jumlahTerjualPeriode: semuaPenjualan.length,
      nilaiStok: nilaiStok,
      piutangPartner: piutangPartner,
      hutangPartner: hutangPartner,
      piutangKasbon: piutangKasbon,
      piutangPenjualan: piutangPenjualan,
    );
  }
}

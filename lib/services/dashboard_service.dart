import 'package:sqflite/sqflite.dart';
import '../repositories/motor_repository.dart';
import '../repositories/saldo_repository.dart';
import '../repositories/kasbon_repository.dart';
import '../repositories/penjualan_repository.dart';
import '../repositories/periode_repository.dart';
import '../repositories/dana_talang_repository.dart';
import '../repositories/pengeluaran_repository.dart';
import '../repositories/biaya_transfer_manual_repository.dart';
import '../models/saldo_model.dart';

/// Ringkasan seluruh angka penting yang ditampilkan di layar Dashboard.
class DashboardSummary {
  final double modal;
  final double cash;
  final double saldoBank;
  final double nilaiStokMotor;
  final double piutangKasbon;
  final double piutangPenjualan;
  final double piutangPartner;
  final double hutangPartner;
  final double totalAset;
  final double totalBiayaTransferPeriode;
  final double totalPenjualanPeriodeAktif;
  final double totalLabaPeriodeAktif;
  final int jumlahUnitTersedia;
  final int jumlahUnitTerjualPeriodeAktif;
  final String? namaPeriodeAktif;

  DashboardSummary({
    required this.modal,
    required this.cash,
    required this.saldoBank,
    required this.nilaiStokMotor,
    required this.piutangKasbon,
    required this.piutangPenjualan,
    required this.piutangPartner,
    required this.hutangPartner,
    required this.totalAset,
    required this.totalBiayaTransferPeriode,
    required this.totalPenjualanPeriodeAktif,
    required this.totalLabaPeriodeAktif,
    required this.jumlahUnitTersedia,
    required this.jumlahUnitTerjualPeriodeAktif,
    required this.namaPeriodeAktif,
  });
}

class DashboardService {
  final Database db;
  late final MotorRepository _motorRepo;
  late final SaldoRepository _saldoRepo;
  late final KasbonRepository _kasbonRepo;
  late final PenjualanRepository _penjualanRepo;
  late final PeriodeRepository _periodeRepo;
  late final DanaTalangRepository _danaTalangRepo;
  late final PengeluaranRepository _pengeluaranRepo;
  late final BiayaTransferManualRepository _biayaTransferManualRepo;

  DashboardService(this.db) {
    _motorRepo = MotorRepository(db);
    _saldoRepo = SaldoRepository(db);
    _kasbonRepo = KasbonRepository(db);
    _penjualanRepo = PenjualanRepository(db);
    _periodeRepo = PeriodeRepository(db);
    _danaTalangRepo = DanaTalangRepository(db);
    _pengeluaranRepo = PengeluaranRepository(db);
    _biayaTransferManualRepo = BiayaTransferManualRepository(db);
  }

  Future<DashboardSummary> getSummary() async {
    final SaldoModel saldo = await _saldoRepo.getSaldo();
    final nilaiStok = await _motorRepo.getTotalNilaiStok();
    final piutangKasbon = await _kasbonRepo.getTotalPiutangBelumLunas();
    final piutangPenjualan = await _penjualanRepo.getTotalPiutangPenjualan();
    final piutangPartner = await _danaTalangRepo.getTotalPiutangPartner();
    final hutangPartner = await _danaTalangRepo.getTotalHutangPartner();
    final stokTersedia = await _motorRepo.getStokTersedia();
    final periodeAktif = await _periodeRepo.getPeriodeAktif();

    double totalPenjualan = 0;
    double totalLaba = 0;
    int jumlahTerjual = 0;
    double totalBiayaTransfer = 0;

    if (periodeAktif != null) {
      final penjualanPeriode =
          await _penjualanRepo.getAll(periodeId: periodeAktif.id);
      totalPenjualan =
          penjualanPeriode.fold<double>(0, (sum, p) => sum + p.hargaJual);
      totalLaba = penjualanPeriode.fold<double>(0, (sum, p) => sum + p.laba);
      jumlahTerjual = penjualanPeriode.length;
      totalBiayaTransfer = await _pengeluaranRepo
          .getTotalAdministrasiBank(periodeId: periodeAktif.id);
      totalBiayaTransfer +=
          await _biayaTransferManualRepo.getTotal(periodeId: periodeAktif.id);
    }

    // Total Aset = Cash + Saldo Bank + Nilai Stok + Piutang Kasbon +
    // Piutang Penjualan (DP) + Piutang Partner (Hutang Partner
    // ditampilkan terpisah sebagai kewajiban, tidak mengurangi Total
    // Aset agar konsisten dengan gaya laporan sederhana yang sudah ada).
    final totalAset = saldo.cash +
        saldo.saldoBank +
        nilaiStok +
        piutangKasbon +
        piutangPenjualan +
        piutangPartner;

    return DashboardSummary(
      modal: saldo.modalTotal,
      cash: saldo.cash,
      saldoBank: saldo.saldoBank,
      nilaiStokMotor: nilaiStok,
      piutangKasbon: piutangKasbon,
      piutangPenjualan: piutangPenjualan,
      piutangPartner: piutangPartner,
      hutangPartner: hutangPartner,
      totalAset: totalAset,
      totalBiayaTransferPeriode: totalBiayaTransfer,
      totalPenjualanPeriodeAktif: totalPenjualan,
      totalLabaPeriodeAktif: totalLaba,
      jumlahUnitTersedia: stokTersedia.length,
      jumlahUnitTerjualPeriodeAktif: jumlahTerjual,
      namaPeriodeAktif: periodeAktif?.namaPeriode,
    );
  }
}

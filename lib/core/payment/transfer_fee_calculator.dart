import '../constants/app_constants.dart';

/// GARASI ABAH BONTOT V4.2.1 — PAYMENT FLOW GLOBAL.
///
/// Sebelumnya algoritma biaya transfer hanya ada di PengeluaranRepository.
/// Ini SALAH — biaya transfer adalah bagian dari sistem PAYMENT GLOBAL dan
/// wajib berlaku di SEMUA transaksi yang mengurangi uang lewat TRANSFER:
/// pembelian motor, biaya tambahan/susulan motor, dana talang keluar,
/// kasbon, gaji (lewat pengeluaran), dan pengeluaran umum.
///
/// Single source of truth — semua repository WAJIB pakai kalkulator ini,
/// jangan duplikasi logika biaya transfer di masing-masing repository.
class TransferFeeCalculator {
  const TransferFeeCalculator._();

  static double hitung(String? jenisTransfer) {
    switch (jenisTransfer) {
      case AppConstants.jenisTransferBiFast:
        return AppConstants.adminTransferBiFast;
      case AppConstants.jenisTransferRealtime:
        return AppConstants.adminTransferRealtime;
      case AppConstants.jenisTransferGratis:
      default:
        return AppConstants.adminTransferGratis;
    }
  }
}

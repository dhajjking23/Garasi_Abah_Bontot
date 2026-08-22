# CHANGELOG — GARASI ABAH BONTOT V4.2.4 (Final Check)

Server, role, sync, login — tidak diubah.

## Audit Final TransferFeeCalculator

Dicek satu per satu, seluruh titik `bayarCampuran`/`mutasiBank`/`mutasiCash`
di semua repository transaksi uang keluar:

- **motor_repository.dart** (13 titik mutasi saldo): `tambahMotor`,
  `tambahBiaya`, `editBiaya`, `hapusBiaya`, `editPembelian`, `hapusMotor`
  — semua sudah pakai `jenisTransfer`/`TransferFeeCalculator` di jalur
  KELUAR, dan reversal fee benar di jalur rollback (termasuk fix
  `hapusMotor` dari V4.2.3). **Tidak ada perubahan.**
- **gajihan_repository.dart**: tidak ada mutasi saldo langsung — 100%
  lewat `pengeluaranRepo.tambahPengeluaran` yang sudah terintegrasi sejak
  V4.2.1. **Tidak ada perubahan.**
- **pembayaran supplier**: tidak ada entitas/tabel supplier terpisah di
  codebase ini. Pembayaran ke penjual motor tercakup dalam
  `tambahMotor`/`editPembelian` (sudah terintegrasi). **Tidak ada
  perubahan.**
- **pelunasan** (kasbon, dana_talang, pengeluaran): seluruh titik
  `mutasiBank`/`bayarCampuran` sudah memakai fee sesuai jenis transfer,
  termasuk `bayarKembali` dana talang yang diperbaiki di V4.2.2. **Tidak
  ada perubahan.**
- **biaya tambahan/susulan motor**: `tambahBiaya`/`editBiaya` sudah
  terintegrasi sejak V4.2.1, reversal fee benar sejak V4.2.3. **Tidak
  ada perubahan.**

## Hasil
Tidak ditemukan celah baru. Semua transaksi uang keluar via transfer
(Cash/Transfer/Campuran) sudah konsisten memakai satu sistem yang sama
(`TransferFeeCalculator` via `SaldoRepository.bayarCampuran`).

**Tidak ada file source yang diubah pada versi ini.**

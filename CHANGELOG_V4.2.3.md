# CHANGELOG — GARASI ABAH BONTOT V4.2.3 (Payment Audit Final)

Server, role, sync, login — tidak diubah.

## Audit Hasil
Semua alur uang keluar dicek ulang (pembelian motor, pembayaran motor,
pelunasan, dana talang keluar, kasbon, gaji, biaya tambahan/susulan motor,
pengeluaran lain). 9/9 kategori sudah pakai `TransferFeeCalculator`
(langsung atau lewat `bayarCampuran`) sejak V4.2.1/V4.2.2.

**1 celah ditemukan**: `MotorRepository.hapusMotor()`. `motor.biaya_admin_transfer`
hanya menyimpan fee dari pembelian awal (`tambahMotor`/`editPembelian`) —
TIDAK kumulatif. Fee dari tiap `tambahBiaya` (biaya susulan) tersimpan
terpisah di masing-masing baris `motor_cost`. Saat motor dihapus, baris
`motor_cost` langsung di-delete tanpa menjumlah fee-nya dulu → biaya admin
transfer dari biaya susulan hilang permanen dari saldo bank (tidak pernah
dikembalikan).

## File Diubah

- `lib/repositories/motor_repository.dart` — `hapusMotor()`: sebelum
  menghapus baris `motor_cost`, jumlahkan dulu `biaya_admin_transfer`
  semua baris tsb (`totalFeeMotorCost`). Total fee yang dikembalikan ke
  saldo bank = `motor.biayaAdminTransfer` (pembelian awal) +
  `totalFeeMotorCost` (akumulasi biaya susulan), dikembalikan lewat
  `mutasiBank` arah MASUK sebelum motor dihapus.

## Aturan Potong Saldo (tidak berubah, ditegakkan di `bayarCampuran`)
- **Cash**: kurangi cash saja.
- **Transfer**: kurangi saldo bank + biaya transfer.
- **Campuran**: kurangi cash sesuai porsi cash + kurangi saldo bank sesuai
  porsi transfer + biaya transfer.
- Total uang keluar = nominal transaksi + biaya transfer, tersimpan
  sebagai kolom terpisah (`biaya_admin`/`biaya_admin_transfer`) di setiap
  tabel transaksi.

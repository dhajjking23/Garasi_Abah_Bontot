# CHANGELOG — GARASI ABAH BONTOT V4.2.2 (Payment Integration Fix)

Server, role, login, sync — tidak diubah.

## Audit Hasil
Semua repository transaksi uang keluar dicek. 8 dari 9 kategori sudah pakai
`TransferFeeCalculator` (via `bayarCampuran`/`hitungBiayaAdmin`) sejak
V4.2.1: pembelian motor, biaya tambahan/susulan motor, dana talang keluar,
kasbon, gaji (lewat pengeluaran), pengeluaran lain.

**1 celah ditemukan**: `DanaTalangRepository.bayarKembali()` — jalur bayar
balik hutang ke partner (kasus `SAYA_MENERIMA`, uang KELUAR) sama sekali
belum pakai `TransferFeeCalculator`. UI-nya bahkan masih hardcode CASH,
tidak ada pilihan metode pembayaran sama sekali.

## File Diubah

- `lib/core/constants/app_constants.dart` — `dbVersion` 14 → 15.
- `lib/core/database/database_helper.dart` — kolom `jenis_transfer` +
  `biaya_admin_transfer` ditambahkan ke `dana_talang_pembayaran` (skema
  `_onCreate` + migration `oldVersion < 15`, `ADD COLUMN` aman, data lama
  tidak tersentuh).
- `lib/models/dana_talang_pembayaran_model.dart` — field baru +
  `copyWith` (sebelumnya tidak ada).
- `lib/repositories/dana_talang_repository.dart`:
  - `bayarKembali()`: parameter `jenisTransfer` baru. Fee dihitung &
    dipotong dari saldo bank HANYA saat arah KELUAR (`!isMenalangi`,
    kita bayar balik ke partner) via `bayarCampuran`. Arah MASUK
    (partner bayar balik ke kita) tidak kena fee — sesuai aturan
    (fee cuma untuk uang keluar).
  - `hapusDanaTalang()`: loop rollback pembayaran sekarang juga
    membalik `biaya_admin_transfer` per baris pembayaran (sebelumnya
    cuma balikin nominal, fee lama akan permanen hilang dari saldo jika
    dana talang dihapus setelah ada pembayaran kembali).
- `lib/screens/dana_talang/dana_talang_screen.dart` — `_bayarKembali()`
  ditulis ulang: dari dialog nominal sederhana (selalu CASH) jadi bottom
  sheet dengan `MetodePembayaranField` (Cash/Transfer/Campuran) +
  `JenisTransferField` (muncul kalau arah KELUAR & bukan Cash).

## Aturan Potong Saldo (ditegakkan di `bayarCampuran`, dipakai semua repo)
- **Cash**: potong cash saja.
- **Transfer**: potong saldo bank + biaya transfer (sesuai jenis: Gratis/BI FAST/Realtime).
- **Campuran**: potong cash sesuai porsi + potong saldo bank sesuai porsi transfer + biaya transfer.

Nominal transaksi, jenis_transfer, dan biaya_admin_transfer tersimpan
sebagai kolom terpisah di setiap tabel transaksi (bukan digabung), supaya
laporan bisa audit total uang keluar = nominal + biaya per baris.

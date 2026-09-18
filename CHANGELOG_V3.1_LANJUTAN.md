# GARASI ABAH BONTOT — V3.1 Patch (Lanjutan)

DB version: 10 -> 11 (migrasi additive, tidak reset data lama, tidak ubah applicationId).

## 1. Payment Transfer Fee
Sudah ada dari patch sebelumnya (kolom jenis_transfer/biaya_admin di pengeluaran,
GRATIS/BI_FAST/RP2.500/REALTIME Rp6.500), diverifikasi tetap konsisten.

## 2. Alur Uang Masuk (Cash / Saldo Bank / Campuran)
- DITEMUKAN BUG: repository pemasukan (tambah/edit/hapus) sebelumnya TIDAK
  benar-benar mendukung split CAMPURAN meski kolom DB sudah ada — diperbaiki
  penuh (validasi cash+bank harus sama dengan nominal, rollback via
  bayarCampuran).
- UI pemasukan_screen.dart ditulis ulang: SegmentedButton Cash/Saldo Bank/
  Campuran + 2 field nominal saat Campuran dipilih.
- DP/Pelunasan/Hutang Piutang/Dana Talang sudah pakai metodePembayaran
  CASH/TRANSFER/CAMPURAN (MetodePembayaranField) sejak sebelumnya — diverifikasi
  konsisten dengan aturan ini.

## 3. Edit Tanggal Transaksi
Ditambahkan method edit-tanggal ringan (audit-logged) + UI date-picker untuk:
- Pembelian motor (motor_repository.editTanggalMasuk) — tombol di Detail Motor
- Biaya tambahan motor (editTanggalBiaya) — dialog Edit Biaya
- Penjualan motor (editTanggalPenjualan) — ikon di baris Riwayat Penjualan
- DP/Pelunasan/cicilan (editTanggalPembayaran di penjualan_repository) — tersedia
  di repository, tanggal cicilan juga otomatis terisi via date-picker saat
  "Cicil/Lunasi Piutang"
- Dana Talang (editTanggalDanaTalang) — ikon di kartu Dana Talang + date-picker
  saat "Bayar Kembali"
- Pengeluaran — field tanggal ditambahkan ke dialog Tambah & Edit (repo sudah
  mendukung sejak sebelumnya, sekarang benar-benar terpasang di UI)
- Pemasukan — sama seperti Pengeluaran, plus perbaikan bug updated_at yang
  tidak ter-update saat edit
- Kasbon — field tanggal ditambahkan ke dialog Tambah & Edit
- Gajihan (gajihan_repository.editTanggalGajihan, method baru) — tap riwayat
  gajihan untuk ubah tanggal

Semua edit tanggal tercatat di audit_log dan otomatis tercermin di Laporan
karena laporan difilter berdasarkan periode_id (bukan rentang tanggal),
sehingga tidak perlu migrasi ulang data.

## 4. Menu Biaya Transfer
- Tabel baru: biaya_transfer_manual (migrasi v11)
- Model + Repository CRUD baru: BiayaTransferManualRepository
- Screen baru: lib/screens/biaya_transfer/biaya_transfer_screen.dart
  (riwayat, tambah, edit, hapus — field: tanggal, nama tujuan, keterangan,
  nominal)
- Kartu "Biaya Transfer (Periode)" di Dashboard sekarang bisa diklik dan
  membuka halaman ini
- Total Biaya Transfer Periode (Dashboard & Laporan) sekarang menggabungkan
  biaya admin otomatis (dari Pengeluaran via Transfer) + biaya transfer manual

## Catatan Build
- Sandbox pengembangan ini TIDAK memiliki Flutter SDK terpasang dan TIDAK
  ada akses jaringan keluar, sehingga `flutter analyze` dan `flutter test`
  TIDAK BISA dijalankan di sini. Source code sudah ditelaah manual (import,
  nama provider, signature method, balance tanda kurung/kurawal) tapi WAJIB
  dijalankan `flutter pub get && flutter analyze && flutter test` di
  environment Anda sebelum build APK rilis.
- package/applicationId Android tidak diubah: com.garasiabahbontot.garasi_abah_bontot
- pubspec version dinaikkan 1.0.1+2 -> 1.0.2+3 (versionCode naik agar APK bisa
  update dari versi sebelumnya, sesuai skema Android biasa — versionName ada
  di pubspec, pastikan build.gradle Anda membaca dari pubspec atau sesuaikan
  versionCode manual bila di-hardcode).

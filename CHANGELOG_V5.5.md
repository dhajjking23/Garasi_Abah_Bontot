# GARASI ABAH BONTOT V5.5 — FEATURE UPDATE

## 1. Dashboard
- Kartu "Total Aset" sekarang bisa diklik → `TotalAsetDetailScreen`
  (baru): komposisi aset, laba/rugi periode aktif, transaksi motor/
  pemasukan/pengeluaran terbaru, riwayat perubahan saldo. Semua dari data
  yang sudah ada (`DashboardSummary`, `LaporanPeriodeData`, cash_flow) —
  tidak ada perhitungan baru.

## 2. Dana Talang
- Form "Bayar Kembali": toggle **Cicil / Lunas**. Sebelumnya metode
  Cash/Transfer (non-Campuran) selalu memaksa bayar penuh sisa — sekarang
  Cicil membuka input nominal bebas (≤ sisa).
- Tombol **Edit Lengkap** (ikon pensil) di tiap entri yang belum ada
  pembayaran sama sekali — pakai `editDanaTalang()` yang sebelumnya sudah
  ada di repository tapi tidak pernah dipanggil dari UI. Jenis
  (Menalangi/Menerima) sengaja TIDAK bisa diubah di sini (ganti arah kas
  di luar cakupan edit — hapus & buat ulang kalau salah jenis).
- Tab baru **"Hubungan Partner"**: rekap per nama partner (Perusahaan↔
  Abah, dst) — total saling talang, selisih kewajiban, riwayat, tombol
  **"Bayar Semua Selisih"** (melunasi semua transaksi aktif partner itu
  sekaligus via `bayarKembali()` yang sudah teruji, bukan logika baru).

## 3. Jual Motor
- Dropdown pilih motor & kartu riwayat: **plat nomor** (bukan kode motor).
- Field baru **Biaya Calo** — laba otomatis `hargaJual - biayaCalo -
  modalMotor`. Migrasi DB aman: kolom `biaya_calo REAL DEFAULT 0`
  (`dbVersion` 16→17), data lama tidak berubah laba-nya.

## 4. Inventory Motor
- Plat nomor jadi identitas utama di kartu (judul), bukan nama/kode.
- Tab "Semua": motor **Tersedia** di atas, **Terjual** di bawah.

## 5. Export PDF & Excel
- Tabel "Laba per Motor": kolom Kode → **Tanggal** (dd/MM), tambah **Plat
  Nomor**.
- "Pengeluaran per Kategori" sekarang **detail per transaksi** (tanggal,
  nominal, catatan), bukan cuma total. Butuh `PengeluaranRepository`
  di-inject ke `ExportService` (fallback ke total lama kalau tidak ada).
- Tabel baru **"Detail Perjalanan Unit Motor"**: harga beli, semua biaya
  tambahan + catatannya (dari `motor_cost`), biaya calo, harga jual,
  laba/rugi.

## 6. Logo & Loading
- Icon launcher app diganti (semua ukuran mipmap).
- `SplashGate` baru di `main.dart`: splash image dari asset baru, tampil
  ~1.4 detik sebelum `AuthGate`.
- Logo layar login ikut ter-update.

## File berubah
`lib/main.dart`, `lib/core/constants/app_constants.dart` (dbVersion),
`lib/core/database/database_helper.dart` (migrasi V17),
`lib/models/penjualan_model.dart`, `lib/repositories/penjualan_repository.dart`,
`lib/screens/penjualan/penjualan_screen.dart`,
`lib/screens/motor/motor_list_screen.dart`,
`lib/screens/dashboard/dashboard_screen.dart`,
`lib/screens/auth/login_screen.dart`,
`lib/repositories/dana_talang_repository.dart`,
`lib/screens/dana_talang/dana_talang_screen.dart`,
`lib/providers/app_providers.dart`,
`lib/services/export_service.dart`,
`lib/screens/laporan/laporan_screen.dart`,
android launcher icons (`mipmap-*/ic_launcher.png`).

## File baru
`lib/screens/dashboard/total_aset_detail_screen.dart`,
`assets/images/logo.png`, `assets/images/splash.png`.

## Tidak diubah (sesuai instruksi)
- Role ADMIN/PARTNER (write guard, UI batasan Viewer) — nol perubahan.
- Sistem server/sync (V5.1–V5.4) — nol perubahan.
- Perhitungan saldo cash/bank, sistem sync_version/sync_log/audit_log.
- Skema tabel lain di luar kolom `biaya_calo` yang ditambahkan.

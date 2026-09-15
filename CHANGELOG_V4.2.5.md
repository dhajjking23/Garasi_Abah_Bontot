# CHANGELOG — GARASI ABAH BONTOT V4.2.5 (Critical Hotfix)

Server, role, sync, login (arsitektur) — tidak diubah. Ini perbaikan bug
kritis yang membuat aplikasi tidak bisa dipakai sama sekali di perangkat
Android nyata.

## Bug 1 — KRITIS: "no such function: json_object" saat INSERT apapun

**Akar masalah**: trigger sync (dibuat V12) memakai `json_object(...)`
SQLite untuk menyusun payload. Fungsi ini butuh ekstensi JSON1 yang
**tidak tersedia di SQLite bawaan banyak perangkat/versi Android**. Semua
INSERT ke 14 tabel yang disinkron (motor, penjualan, pemasukan,
pengeluaran, kasbon, saldo, dana_talang, gajihan, periode, users, dst)
gagal total — termasuk sekadar membuat periode pembukuan.

Tidak muncul di CI (`sqflite_common_ffi` di GitHub Actions pakai SQLite
desktop yang punya JSON1), makanya lolos semua testing sebelumnya.

**Fix**: `lib/core/database/database_helper.dart`
- `_createSyncTriggers()`: payload sync_log sekarang selalu `NULL`,
  tidak lagi pakai `json_object()`. Delta sync tetap jalan normal (masih
  ada `record_id`+`action`+`table_name`); Termux server tetap bisa ambil
  isi baris lengkap lewat endpoint fallback `GET /table/{name}` yang
  sudah ada sejak V4.
- `_dropOldSyncTriggers()` (baru): hapus trigger versi lama yang rusak.
- Migration V16: jalankan `_dropOldSyncTriggers` + `_createSyncTriggers`
  ulang untuk device yang sudah kena bug ini — tidak menyentuh data,
  hanya definisi trigger.
- `dbVersion` 15 → 16 (`app_constants.dart`).

## Bug 2 — KRITIS: Restore database corrupt ("duplicate column name")

**Akar masalah**: `restoreDatabase()` menutup koneksi lalu menimpa file
`.db` dengan file backup, TAPI tidak menghapus sidecar `-wal`/`-shm`
milik database LAMA. Saat file hasil restore dibuka lagi, SQLite
"memutar ulang" (WAL replay) sisa transaksi dari WAL lama yang sudah
tidak sinkron dengan file baru — skema versi lama & baru tercampur,
menyebabkan `ALTER TABLE ... ADD COLUMN` gagal karena kolom "sudah ada"
padahal sebenarnya konflik state.

**Fix**: `lib/core/database/database_helper.dart` — `restoreDatabase()`
sekarang menghapus `$path-wal` dan `$path-shm` SEBELUM menimpa file
utama dengan backup.

## Bug 3 — Login macet permanen (spinner tidak berhenti) setelah error DB

**Akar masalah**: `LoginScreen._submit()` memanggil `await ...login(...)`
tanpa try/catch. Kalau proses login melempar exception (mis. karena
koneksi database rusak akibat Bug 1/2 di atas), baris
`setState(() => _loading = false)` setelahnya tidak pernah tereksekusi
— tombol MASUK macet loading selamanya, aplikasi terlihat "tidak bisa
login" walau sebenarnya cuma exception yang tidak tertangkap.

**Fix**: `lib/screens/auth/login_screen.dart` — `_submit()` dibungkus
try/catch/finally: error ditampilkan ke user, `_loading` SELALU direset
di blok `finally` apa pun hasilnya.

## Dampak
Bug 1 & 2 adalah akar penyebab utama seluruh laporan "tidak bisa buat
periode" dan "tidak bisa restore". Bug 3 adalah gejala ikutan (login
macet) yang muncul setelah salah satu dari keduanya gagal — sekarang
error akan tertampil jelas alih-alih membuat tombol macet.

# CHANGELOG — GARASI ABAH BONTOT V4

## Prinsip
- Tidak ada aplikasi baru dibuat dari nol. Base: source V3.1 Patch Lanjutan.
- Tidak ada fitur lama dihapus. Tidak ada `DROP TABLE`.
- Semua perubahan skema lewat migration (`dbVersion` 11 → 12).

## Database (V11 → V12)
- Tabel baru: `users`, `devices`, `sync_version`, `sync_log`, `backup_log`.
- Seed default: `andri`/`andri123` (OWNER_ADMIN), `partner`/`partner123` (VIEWER) — **wajib diganti setelah instalasi**.
- Trigger otomatis (`AFTER INSERT/UPDATE/DELETE`) pada 12 tabel bisnis (motor, penjualan, pemasukan, pengeluaran, kasbon, cash_flow, saldo, dana_talang, gajihan, biaya_transfer_manual, audit_log) → mengisi `sync_version` + `sync_log` (payload JSON per baris) untuk delta sync ke Viewer.
- **Backup otomatis sebelum migration**: setiap buka app, jika versi DB lokal < versi target, file `.db` mentah dibackup ke `/storage/emulated/0/GarasiBackup/GARASI_PRE_MIGRATION_V{lama}_TO_V{baru}_{timestamp}.db` sebelum `onUpgrade` dijalankan.

## Multi User & Keamanan
- Role: `OWNER_ADMIN` (Andri, full access) dan `VIEWER` (Partner, read-only).
- Login wajib (`AuthGate`) sebelum masuk aplikasi.
- **Guard di layer data, bukan cuma UI**: `requireWriteAccess()` disisipkan di awal setiap method insert/update/delete di seluruh repository & service (motor, penjualan, pemasukan, pengeluaran, kasbon, saldo, dana_talang, gajihan, biaya_transfer, kategori, periode, audit_log, pembagian_laba). VIEWER yang mencoba menulis akan mendapat `PermissionDeniedException`, ditangkap UI lewat `showErrorSnackbar`.
- Menu **Pengaturan → Manajemen User**: ganti username/password Partner, aktif/nonaktifkan akun (khusus OWNER_ADMIN).
- Menu **Pengaturan → Perangkat Terhubung**: lihat & logout device.

## Local Server (Termux) — `garasi_server/`
- `server.py`: FastAPI, endpoint `/ping` (publik), `/status`, `/sync`, `/tables`, `/table/{name}` (semua wajib header `X-API-Token`).
- `sync_engine.py`: delta sync berbasis `sync_version` per tabel — hanya kirim perubahan (`sync_log`, action INSERT/UPDATE/DELETE + payload), bukan seluruh DB.
- `database_connector.py`: koneksi read-only ke SQLite master, server tidak pernah menulis langsung ke tabel transaksi.
- `config.json`: berisi `api_token` — **wajib diganti dari default**, harus sama dengan token yang dipakai app Partner.
- `start_server.sh` + `termux_boot/start-garasi-server`: auto-start via Termux:Boot + tmux saat HP restart.

## Android / Build
- `applicationId` **TIDAK DIUBAH**: tetap `com.garasiabahbontot.garasi_abah_bontot` (sama dengan V3.1 yang sudah terpasang) — mengubahnya akan membuat Android menganggap ini aplikasi berbeda dan memaksa uninstall.
- Signing release permanen via `android/key.properties` (lihat `android/KEYSTORE_SETUP.md`). Fallback ke debug signing HANYA jika `key.properties` belum ada (build tidak akan bisa update APK lama).
- `key.properties` & `*.jks` masuk `.gitignore`.

## Dependencies baru
- `crypto` (hash password), `http` (sync client).

## Belum/keterbatasan lingkungan build ini
- `flutter analyze` / `flutter test` / `flutter build apk` tidak bisa dijalankan di sandbox ini (tidak ada Flutter SDK & tidak ada akses jaringan). Sudah dilakukan verifikasi statis: brace/paren balance seluruh file `.dart`, `py_compile` untuk backend Python, review manual struktur migration & trigger.
- Keystore asli V3.1 tidak tersedia di sini — harus disuplai oleh pemilik project agar update APK in-place berfungsi (lihat `android/KEYSTORE_SETUP.md`).

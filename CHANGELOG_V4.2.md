# CHANGELOG — GARASI ABAH BONTOT V4.2 (Server + Role + Sync Final)

applicationId, namespace, package Kotlin, MainActivity, signing config —
**tidak diubah** (tetap `com.garasiabahbontot.garasi_abah_bontot`).

## File Baru
- `lib/services/server_config_service.dart` — penyimpanan permanen SERVER_HOST/PORT/TOKEN/MODE via SharedPreferences (bukan state sementara).
- `lib/services/server_discovery_service.dart` — Auto Discovery: coba host tersimpan dulu, jika gagal scan subnet WiFi lokal cari `/ping`. Viewer tidak pernah input IP manual.
- `lib/services/session_service.dart` — persistent login session (simpan username lokal, bukan password).
- `lib/providers/server_provider.dart` — provider Riverpod untuk config/discovery/status service.
- `lib/widgets/hidden_debug_trigger.dart` — widget hitung tap (5x/3 detik) generik, tidak tahu soal role.
- `lib/widgets/hidden_server_fallback_dialog.dart` — dialog input IP manual, hanya jalan jika `isOwnerAdminProvider == true`; Viewer yang tap 5x tidak mendapat apa pun (silent).
- `CHANGELOG_V4.2.md` — dokumen ini.

## File Diubah

**Database & Sync**
- `lib/core/constants/app_constants.dart` — `dbVersion` 12 → 13.
- `lib/core/database/database_helper.dart` — tabel `users` & `periode` ditambahkan ke `_syncedTables` (perubahan username/password Partner & pergantian periode sekarang ikut ke `sync_log`); migration block `oldVersion < 13` memanggil ulang `_createSyncTriggers` (idempotent, `CREATE TRIGGER IF NOT EXISTS`, tidak mengubah data lama).

**Login & Role (persistent, role-gated)**
- `lib/providers/auth_provider.dart` — ditulis ulang: `AuthState{user, restoring}`, `AuthNotifier` restore sesi dari `SessionService` saat start (baca ulang `users` dari DB — bukan cache statis — sehingga akun yang dinonaktifkan OWNER_ADMIN otomatis ter-logout saat sesi direstore). Provider lama (`authProvider`) tetap ada untuk kompatibilitas, ditambah `authNotifierProvider` & `authRestoringProvider`.
- `lib/services/auth_service.dart` — tambah `restoreSession(UserModel)`.
- `lib/main.dart` — `AuthGate` menampilkan loading selagi `authRestoringProvider` true, baru lompat ke Login/RootShell.
- `lib/screens/auth/login_screen.dart` — pakai `authNotifierProvider`.

**Server Config & Role Access (inti V4.2)**
- `lib/screens/server/server_screen.dart` — ditulis ulang total: OWNER_ADMIN dapat form Host/Port/Token/Mode (LOCAL/VPS) + tombol Simpan (permanen); VIEWER hanya lihat status ONLINE/OFFLINE + last sync, tanpa field IP/token/mode sama sekali, auto-discovery jalan sendiri saat layar dibuka.
- `lib/services/server_status_service.dart` — `ServerStatus` tambah field `mode`, `port`, getter `modeLabel`.
- `garasi_server/config.json` — token default diseragamkan jadi `garasi_abah_bontot` sesuai spesifikasi.
- `garasi_server/server.py` — perbaiki bug logic `verify_token` (sebelumnya token salah tetap lolos kecuali token kosong).

**Role Separation Total (UI + Backend)**
- `lib/screens/pengaturan/pengaturan_screen.dart` — menu Backup & Restore / Manajemen User / Perangkat Terhubung **dihilangkan total** dari daftar untuk VIEWER (bukan cuma di-disable); pakai `authNotifierProvider`.
- `lib/screens/dashboard/dashboard_screen.dart` — judul AppBar dibungkus `HiddenDebugTrigger` (tap 5x → fallback IP manual, hanya berefek untuk OWNER_ADMIN).
- `lib/screens/device/device_management_screen.dart` — guard akses OWNER_ADMIN di `build()`.
- `lib/screens/pembukuan/backup_restore_screen.dart` — guard akses OWNER_ADMIN di `build()` (method asli dipindah ke `_buildContent`).
- Tombol **Tambah** (FAB) di-gate `ref.watch(isOwnerAdminProvider)` — hilang total untuk VIEWER, bukan cuma disabled:
  - `lib/screens/penjualan/penjualan_screen.dart`
  - `lib/screens/biaya_transfer/biaya_transfer_screen.dart`
  - `lib/screens/motor/motor_list_screen.dart`
  - `lib/screens/kasbon/kasbon_screen.dart`
  - `lib/screens/pengeluaran/pengeluaran_screen.dart`
  - `lib/screens/dana_talang/dana_talang_screen.dart`
  - `lib/screens/pemasukan/pemasukan_screen.dart`
- Proteksi backend (`requireWriteAccess()` di repository/service, ditambahkan sesi sebelumnya) **tetap berlaku tanpa perubahan** — ini yang menolak INSERT/UPDATE/DELETE dari VIEWER di level data, terlepas dari UI.

**Belum di-gate UI (diketahui, prioritas rendah)**: tombol tambah/kurang cepat di `cash_screen.dart`, `modal_screen.dart`, `saldo_bank_screen.dart` masih terlihat untuk VIEWER — namun jika ditekan tetap **ditolak backend** (`PermissionDeniedException` via `requireWriteAccess()`) dan menampilkan snackbar error. Tidak ada risiko keamanan/data, hanya UX yang belum rapi. Rencana: gate di update berikutnya.

## Termux Server (11, 12) — Sudah Sesuai, Tidak Ada Perubahan
`garasi_server/start_server.sh`, `stop_server.sh`, `restart_server.sh` dari
update sebelumnya sudah memenuhi seluruh spesifikasi V4.2:
- 3 mode: Manual (`bash start_server.sh`), Background/tmux opsional (`--bg`), Auto Boot (`--boot`).
- tmux **tidak wajib** — Manual & Auto Boot tidak butuh tmux sama sekali.
- Cegah server ganda: `port_check.py` dicek sebelum start.
- Token sederhana lewat header `X-API-Token` (bukan sistem auth kompleks).

## Test Manual yang Perlu Dilakukan (sesuai TEST 1–9 di brief)
Tidak bisa dijalankan otomatis di lingkungan ini (tidak ada Flutter SDK/HP
fisik). Lakukan manual sesuai `INSTALLATION_V4.md` setelah APK ter-build.

# GARASI ABAH BONTOT V5.1 — SERVER MASTER SYNC ARCHITECTURE

## Ringkasan
Arsitektur sync diubah dari "server membaca file SQLite APK secara
langsung" menjadi "server sebagai database MASTER melalui API". Ini
menghilangkan akar masalah `unable to open database file` secara permanen
(server tidak lagi bergantung pada izin storage Android/MIUI sama sekali —
database server sekarang ada di storage privat Termux).

Tidak ada fitur lama yang dihapus. Tidak ada perubahan skema tabel bisnis,
migrasi Flutter, payment flow, atau role yang sudah stabil.

## Arsitektur Baru
```
OWNER_ADMIN                          VIEWER/PARTNER
   |                                       |
   | tulis lokal (spt biasa, tidak         | baca-saja, tidak berubah
   | berubah — semua repository/          |
   | trigger sync_log lokal tetap sama)   |
   v                                       |
 [outbox: sync_log lokal]                  |
   |                                       |
   | POST /push (baru)                     | POST /sync + GET /table/{name}
   v                                       v  (tidak berubah kontraknya)
        SERVER (Termux/FastAPI-Flask, DB privat sendiri)
        garasi_server/data/garasi_abah_bontot.db
```

## Server (garasi_server)
- **`config.json` / `config.py`**: `db_path` sekarang default ke
  `data/garasi_abah_bontot.db` (relatif ke folder `garasi_server`, di
  storage privat Termux — tidak butuh izin Android apa pun).
- **`database.py`**: tambah `ALLOWED_PUSH_TABLES` (whitelist tabel, sama
  persis dengan `kSyncedTables` di Flutter) dan `apply_push(changes,
  device_name)` — terapkan batch INSERT/UPDATE/DELETE dalam satu transaksi,
  filter nama kolom lewat `PRAGMA table_info` (proteksi injeksi), lalu
  otomatis menaikkan `sync_version` + catat `sync_log` + `audit_log`
  server sendiri.
- **`api/routes.py`**: endpoint baru `POST /push` (proteksi token sama
  seperti endpoint lain). `POST /sync`, `GET /table/{name}`, `GET /status`
  **tidak berubah kontraknya** — Partner tidak perlu tahu apa-apa soal
  perubahan ini.
- **`migrate_to_master_db.py`** (baru): migrasi satu kali, salin data admin
  yang sudah ada ke DB master server yang baru. Wajib dijalankan sekali
  sebelum server V5.1 pertama kali dipakai.

## Migration
Tidak ada perubahan skema tabel. Migrasi V5.1 murni **pemindahan lokasi
file** DB server (bootstrap satu kali via `migrate_to_master_db.py`), bukan
migrasi skema. Skema `sync_version`, `sync_log`, `audit_log` dipakai apa
adanya (sudah ada sejak V4).

## Flutter — Client
- **`lib/services/sync_push_service.dart`** (baru): outbox pusher untuk
  OWNER_ADMIN. Baca `sync_log` lokal (infrastruktur trigger yang sudah ada
  sejak V4, tidak diubah), ambil baris terkini dari tabel asal untuk
  INSERT/UPDATE, kirim batch ke `POST /push`, simpan high-water mark
  (`sync_last_pushed_log_id_v1` di SharedPreferences).
- **`lib/services/sync_client_service.dart`**: tambah method `pushChanges()`.
- **`lib/services/sync_version_store.dart`**: tambah
  `lastPushedLogId()` / `saveLastPushedLogId()`.
- **`lib/providers/sync_provider.dart`**: `syncNow()` sekarang bercabang
  sesuai role — VIEWER tetap **pull** (tidak berubah), OWNER_ADMIN sekarang
  **push** (sebelumnya no-op).
- **`lib/screens/server/server_screen.dart`**: tambah kartu "Kirim Data ke
  Server" (tombol "Kirim Sekarang") untuk OWNER_ADMIN, paralel dengan
  tombol "Sinkronkan Sekarang" milik Partner yang tidak diubah.

## Role
- **OWNER_ADMIN**: tetap satu-satunya yang bisa menulis. Enforcement ganda:
  (1) UI tidak berubah — tetap tanpa tombol edit/tambah/hapus untuk
  Partner; (2) endpoint `/push` memang ada di server, tapi hanya dipanggil
  dari kode admin (`SyncPushService`), Partner tidak pernah memanggilnya.
  Proyek ini sengaja **tidak** menambah token/role terpisah di server (LAN
  1 owner + beberapa viewer, sesuai instruksi "jangan bikin sistem
  enterprise") — kalau ke depan butuh proteksi server-side yang lebih
  ketat terhadap `/push`, itu langkah lanjutan terpisah, bukan bagian V5.1
  ini.
- **VIEWER/PARTNER**: read-only, tidak berubah sama sekali.

## Cara Deploy
1. Update kode server (`garasi_server/`) di HP Poco F3.
2. Jalankan migrasi satu kali:
   ```
   python migrate_to_master_db.py /storage/emulated/0/GarasiAbahBontot/garasi_abah_bontot.db
   ```
3. Restart server: `python stop_server.py && python start_server.py`
4. Build & pasang APK V5.1 baru di device ADMIN dan PARTNER.
5. Di device ADMIN: buka layar Server → tombol **"Kirim Sekarang"** sekali
   untuk push semua data existing ke server MASTER.
6. Di device PARTNER: tombol **"Sinkronkan Sekarang"** seperti biasa.

## Known Trade-off
- `/push` divalidasi lewat token API yang sama dengan Partner (bukan token
  terpisah khusus admin). Ini disengaja untuk tetap sederhana sesuai
  spesifikasi ("1 owner + beberapa viewer", "jangan bikin sistem
  enterprise/queue rumit"). Kalau token API pernah bocor ke Partner,
  Partner secara teknis bisa memanggil `/push` langsung lewat HTTP manual
  (di luar app) — risikonya kecil untuk pemakaian rumah tangga/LAN
  tertutup seperti ini, tapi dicatat di sini untuk transparansi.

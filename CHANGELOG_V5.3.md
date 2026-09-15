# GARASI ABAH BONTOT V5.3 — VPS PRODUCTION MIGRATION

## Analisa awal
Kode inti server (`config.py`, `database.py`, `services/*`, `utils/*`,
`main.py`, `api/*`) **sudah portable** — pakai path relatif berbasis
`BASE_DIR`, bukan hardcode path Android. Satu-satunya bagian yang benar-
benar Android-specific: `config.json` (`backup_dir` ke
`/storage/emulated/0/...`) dan skrip shell (shebang Termux,
`termux-setup-storage`, `pkg install`, `Termux:Boot`). Endpoint API,
format response JSON, dan mekanisme token **tidak pernah menyentuh path
storage** — jadi migrasi VPS ini murni soal konfigurasi & deployment,
bukan perubahan API.

## File berubah
- `garasi_server/config.py` — tambah `ENVIRONMENT`, `RATE_LIMIT_PER_MINUTE`;
  `BACKUP_DIR` default sekarang relatif ke `BASE_DIR` (setara perilaku
  lama, tapi generik OS). Config Termux existing (`backup_dir` absolut
  Android) tetap jalan apa adanya — tidak ada regresi.
- `garasi_server/utils/logger.py` — pisah jadi `server.log`, `error.log`,
  `access.log` (rotasi otomatis, sama seperti sebelumnya).
- `garasi_server/api/auth.py` — `hmac.compare_digest` (timing-safe token
  check) + rate limit sederhana per-IP (429 kalau kelebihan, default
  600/menit — longgar, tidak ganggu auto-sync normal). Response 401 tidak
  berubah formatnya.
- `garasi_server/main.py` — access-log hook (`after_request`), auto-buat
  folder DB saat startup, `MAX_CONTENT_LENGTH` 16MB (proteksi payload
  besar), docstring diperbarui (server yang sama untuk Termux & VPS).
- `garasi_server/database.py` — pesan `diagnose()` untuk "file belum ada"
  diperjelas (tidak lagi menyebut "HP" secara eksklusif).
- `garasi_server/migrate_to_master_db.py` — docstring diperbarui
  (mencakup contoh pemakaian VPS), logika tidak berubah.

## File baru
- `garasi_server/config.vps.example.json` — template config VPS (copy →
  `config.json` di server VPS).
- `garasi_server/install.sh` — **baru, VPS Ubuntu 22.04** (menggantikan
  default lama — venv, systemd, cek DB, dsb).
- `garasi_server/start_server.sh` / `stop_server.sh` / `restart_server.sh`
  — **baru, VPS** (wrapper `systemctl`).
- `garasi_server/garasi-abah.service` — unit systemd (`Restart=always`,
  auto-start saat boot).
- `garasi_server/install_termux.sh`, `start_server_termux.sh`,
  `stop_server_termux.sh`, `restart_server_termux.sh` — **salinan persis**
  dari versi lama (Termux/HP), namanya saja yang berubah supaya tidak
  bentrok dengan skrip VPS baru. Fungsi & isi 100% sama seperti sebelumnya.
- `garasi_server/README_VPS.md` — struktur folder, langkah instalasi,
  buka firewall Oracle Cloud, migrasi DB HP→VPS, command server, test API.

## TIDAK berubah (sesuai instruksi)
- Semua endpoint (`/status`, `/health`, `/sync`, `/push`, `/table/{name}`,
  `/tables`) — path, method, format request/response JSON persis sama.
- Skema database & migrasi Flutter.
- `server.py` (shim kompatibilitas), `port_check.py`,
  `services/sync_engine.py`, `services/backup_service.py` (logika backup
  tidak diubah, hanya `BACKUP_DIR` yang kini default relatif).
- Server tetap Waitress (WSGI production server) — bukan Flask dev server,
  ini sudah benar sejak sebelumnya, tidak perlu diubah.

## Langkah migrasi ringkas
1. `bash install.sh` di VPS (buat venv, systemd, folder).
2. Edit `config.json` → ganti `api_token`.
3. `scp` file `.db` dari HP ke VPS.
4. `./venv/bin/python migrate_to_master_db.py <path_db>`.
5. `sudo systemctl start garasi-abah`.
6. Buka port di Oracle Cloud Security List + `ufw`.
7. Update IP di menu Server tiap APK (admin & partner) ke IP VPS.

Detail lengkap tiap langkah: lihat `garasi_server/README_VPS.md`.

# GARASI ABAH BONTOT V4 — Server (Flask + Waitress, Struktur Modular)

Refactor server lama (`server.py` monolitik berbasis FastAPI) menjadi
struktur modular berbasis **Flask + Waitress**. **Tidak ada perubahan
kontrak API** — APK Flutter yang sudah ada tetap berjalan tanpa modifikasi
apa pun.

## ⚠️ Kenapa Flask, bukan FastAPI?

FastAPI menyeret `pydantic-core`, yang ditulis dalam **Rust**. PyPI tidak
menyediakan wheel siap-pakai untuk Termux ARM64 (Termux pakai Bionic libc
Android, bukan glibc, jadi wheel manylinux standar tidak kompatibel), jadi
`pip install` terpaksa compile dari source pakai toolchain Rust
(`cargo`/`maturin`) yang tidak tersedia di Termux secara default —
**install akan selalu gagal** kecuali Anda pasang toolchain Rust penuh
(berat, rumit, dan makan banyak storage di Android).

**Flask + Waitress 100% pure Python** — nol dependency yang perlu
dikompilasi. Install akan selalu berhasil di Termux ARM64 tanpa syarat
tambahan apapun. Ini prinsip yang sama seperti kenapa Anda sebelumnya
mengganti scikit-learn/pandas dengan implementasi NumPy/stdlib murni di
project lain — hindari apapun yang butuh toolchain compiler berat di Android.

## Struktur

```
garasi_server/
├── main.py                  # entry point baru
├── server.py                 # shim kompatibilitas (uvicorn server:app tetap jalan)
├── config.py / config.json    # konfigurasi
├── database.py                 # koneksi SQLite read-only
├── api/
│   ├── routes.py                # semua endpoint
│   └── auth.py                    # verifikasi X-API-Token
├── models/schemas.py               # skema Pydantic
├── services/
│   ├── sync_engine.py               # delta sync
│   └── backup_service.py              # backup otomatis (BARU)
├── utils/
│   ├── logger.py                       # logging + rotasi
│   ├── network.py                        # IP lokal, mode server
│   └── error_handler.py                   # global error handler (BARU)
├── install.sh                              # setup Termux (BARU)
├── start_server.py / stop_server.py / restart_server.py   # BARU — versi Python murni (tanpa bash)
├── start_server.sh / stop_server.sh / restart_server.sh   # tidak diubah — versi bash (opsional)
├── port_check.py                                            # tidak diubah
└── requirements.txt                                          # tidak diubah
```

## Cara Deploy ke Termux (HP yang sama seperti server lama)

1. Backup dulu folder `garasi_server/` lama Anda (jaga-jaga):
   ```bash
   cp -r ~/garasi_server ~/garasi_server.OLD_BACKUP
   ```

2. Salin isi folder `garasi_server/` baru ini ke lokasi yang sama
   (timpa file lama — **kecuali `config.json`**, lihat langkah 3).

3. **PENTING**: Salin `config.json` yang sudah pernah Anda isi/ubah
   (misal token yang diganti dari OWNER_ADMIN) dari `garasi_server.OLD_BACKUP/config.json`,
   jangan pakai `config.json` bawaan zip ini kalau Anda sudah pernah kustomisasi.

4. Install ulang dependency (aman dijalankan meski sudah pernah install):
   ```bash
   cd ~/garasi_server
   bash install.sh
   ```

5. Jalankan server — ada 2 cara, pakai yang paling kompatibel di HP Anda:

   **Cara A — Python murni (disarankan kalau bash Anda bermasalah):**
   ```bash
   python start_server.py          # manual
   python start_server.py --bg     # background (tanpa tmux)
   python start_server.py --boot   # dari Termux:Boot
   ```
   Hentikan dengan: `python stop_server.py`
   Restart dengan: `python restart_server.py`

   **Cara B — bash (kalau bash normal di HP Anda):**
   ```bash
   bash start_server.sh          # manual
   bash start_server.sh --bg     # tmux
   bash start_server.sh --boot   # dari Termux:Boot
   ```

   Kedua cara ini 100% setara — sama-sama menjalankan `uvicorn main:app`,
   sama-sama cek port ganda, sama-sama tulis `server.pid`/`server.mode`/log.
   Pilih salah satu, tidak perlu dua-duanya.

6. Tes cepat dari HP yang sama:
   ```bash
   curl http://127.0.0.1:8000/ping
   curl -H "X-API-Token: <token_anda>" http://127.0.0.1:8000/status
   ```

## Yang Baru Dibanding Server Lama

- **Backup otomatis harian** sesuai `auto_backup_time` di `config.json`
  (field ini sudah ada di config lama tapi belum pernah benar-benar jalan).
  Hasil backup masuk ke `backup_dir`, retensi 7 file terbaru
  (`backup_retention` bisa diubah di config.json).
- **Error handler global** — kalau ada bug tak terduga, server balas JSON
  rapi (500) alih-alih crash, dan dicatat ke `logs/server.log`.
- **`GET /health`** — endpoint tambahan opsional untuk monitoring manual
  (bukan pengganti `/ping`, APK tidak perlu tahu soal ini).
- **`install.sh`** — setup sekali jalan: cek Python, pip install, buat folder,
  validasi `config.json`.

## Yang TIDAK Berubah (dijamin)

- Semua endpoint, method, path, header `X-API-Token`.
- Semua field JSON request & response.
- Skema database & cara baca (read-only, tidak pernah menulis ke tabel transaksi).
- Port default 8000.
- Perilaku `start_server.sh` (mode Manual/tmux/AutoBoot) — file tidak diubah sama sekali.

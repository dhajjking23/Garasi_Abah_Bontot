# GARASI ABAH BONTOT — Deployment VPS Production (Oracle Cloud, Ubuntu 22.04)

Server yang sama (Flask + Waitress, kode 100% tidak berubah dari versi
Termux) sekarang bisa dijalankan sebagai layanan 24/7 di VPS. Endpoint,
format response JSON, dan header `X-API-Token` **identik** dengan versi
Termux — APK Android **tidak perlu diubah kodenya**, cukup diarahkan ke
alamat VPS di menu Server.

## 1. Struktur folder final

```
garasi_server/
├── api/
│   ├── auth.py              # token check + rate limit (V5.3)
│   └── routes.py            # endpoint (TIDAK berubah)
├── services/
│   ├── backup_service.py
│   └── sync_engine.py
├── utils/
│   ├── error_handler.py
│   ├── logger.py            # server.log + error.log + access.log (V5.3)
│   └── network.py
├── data/
│   ├── garasi_abah_bontot.db   # dibuat via migrate_to_master_db.py
│   └── backup/                 # backup otomatis harian
├── logs/
│   ├── server.log
│   ├── error.log
│   └── access.log
├── venv/                    # dibuat oleh install.sh
├── config.json              # aktif dipakai server (dari config.vps.example.json)
├── config.vps.example.json  # template VPS (V5.3, baru)
├── config.py
├── database.py
├── server.py                 # shim kompatibilitas (tidak berubah)
├── main.py
├── migrate_to_master_db.py
├── install.sh                # VPS Ubuntu (V5.3, baru — menggantikan default lama)
├── start_server.sh           # VPS, wrapper systemd (V5.3, baru)
├── stop_server.sh            # VPS, wrapper systemd (V5.3, baru)
├── restart_server.sh         # VPS, wrapper systemd (V5.3, baru)
├── garasi-abah.service        # systemd unit (V5.3, baru)
├── install_termux.sh         # versi LOKAL/HP lama (dipertahankan, tidak diubah)
├── start_server_termux.sh    # versi LOKAL/HP lama (dipertahankan, tidak diubah)
├── stop_server_termux.sh     # versi LOKAL/HP lama (dipertahankan, tidak diubah)
├── restart_server_termux.sh  # versi LOKAL/HP lama (dipertahankan, tidak diubah)
└── requirements.txt
```

## 2. Langkah instalasi VPS Ubuntu 22.04

```bash
# Di VPS, sebagai user biasa dengan akses sudo (bukan root langsung):
sudo apt-get update
sudo apt-get install -y git   # kalau belum ada

# Upload/clone folder garasi_server ke VPS, misalnya ke /opt/garasi-abah-bontot
sudo mkdir -p /opt/garasi-abah-bontot
sudo chown $(whoami):$(whoami) /opt/garasi-abah-bontot
# (scp folder garasi_server dari komputer Anda ke /opt/garasi-abah-bontot/garasi_server,
#  atau git clone kalau project ada di repo)

cd /opt/garasi-abah-bontot/garasi_server
bash install.sh
```

`install.sh` otomatis: install Python3/venv, install dependency, buat folder
`logs/`, `data/`, `data/backup/`, buat `config.json` dari template VPS
(kalau belum ada), dan **memasang systemd service** supaya server otomatis
hidup lagi kalau VPS reboot.

**WAJIB setelah instalasi:** edit `config.json`, ganti `api_token` ke token
acak yang kuat (server ini terekspos ke internet publik, beda dari LAN
Termux):
```bash
nano config.json   # ganti "api_token": "garasi_abah_bontot" ke token baru
sudo systemctl restart garasi-abah
```
Lalu samakan token itu di menu **Server** setiap aplikasi Android (admin &
partner).

### Buka firewall / Security List Oracle Cloud
Oracle Cloud VPS defaultnya memblokir port masuk. Buka port 8000 (atau
port pilihan Anda) di **dua tempat**:
1. Oracle Cloud Console → VCN → Security List → Ingress Rules → tambah
   `0.0.0.0/0` port `8000` (TCP).
2. Firewall OS (kalau `ufw` aktif):
   ```bash
   sudo ufw allow 8000/tcp
   ```

**Rekomendasi keamanan lebih lanjut** (opsional, di luar scope perubahan
ini): pasang Nginx sebagai reverse proxy + HTTPS (Let's Encrypt/certbot) di
depan port 8000, supaya trafik API terenkripsi TLS. Server Flask/Waitress
saat ini menerima HTTP polos di port 8000 — cukup untuk mulai, tapi
disarankan tambah HTTPS sebelum dipakai jangka panjang dengan data
finansial nyata.

## 3. Migrasi database dari HP ke VPS

Di HP admin (Termux, folder `garasi_server`), backup dulu database
terkini:
```bash
python3 -c "
import shutil, config
shutil.copy2(config.DB_PATH, '/storage/emulated/0/Download/garasi_backup_migrasi.db')
"
```
Atau pakai file backup manual yang sudah Anda simpan sebelumnya
(`garasi_abah_bontot_backup_v5.db`).

Pindahkan file itu ke VPS, misalnya lewat `scp` dari komputer:
```bash
scp garasi_backup_migrasi.db ubuntu@<IP_VPS>:/opt/garasi-abah-bontot/garasi_server/
```

Di VPS, jalankan migrasi (server harus dalam keadaan **berhenti** dulu):
```bash
cd /opt/garasi-abah-bontot/garasi_server
sudo systemctl stop garasi-abah
./venv/bin/python migrate_to_master_db.py garasi_backup_migrasi.db
sudo systemctl start garasi-abah
```

## 4. Command menjalankan server

```bash
sudo systemctl start garasi-abah      # start
sudo systemctl stop garasi-abah       # stop
sudo systemctl restart garasi-abah    # restart
sudo systemctl status garasi-abah     # status
sudo journalctl -u garasi-abah -f     # log realtime (stdout/stderr proses)
```
Atau pakai wrapper (sama persis, lebih pendek):
```bash
bash start_server.sh
bash stop_server.sh
bash restart_server.sh
```
Server **otomatis hidup lagi** kalau VPS di-reboot (`systemctl enable`
sudah dijalankan oleh `install.sh`) atau kalau proses crash
(`Restart=always` di `garasi-abah.service`).

## 5. Cara test API

```bash
# Ganti <TOKEN> dan <IP_VPS> sesuai config.json Anda
curl -H "X-API-Token: <TOKEN>" http://<IP_VPS>:8000/status
curl -H "X-API-Token: <TOKEN>" http://<IP_VPS>:8000/health
curl -H "X-API-Token: <TOKEN>" http://<IP_VPS>:8000/tables
```
Field `"sync_ready": true` di `/status` menandakan database & skema sudah
benar. Kalau `false`, field `"sync_problem"` menjelaskan penyebabnya
langsung (lihat `database.py diagnose()`).

## 6. Update aplikasi Android

Di menu **Server** tiap device (admin & partner):
1. Ganti field **IP** dari IP lokal (mis. `192.168.x.x`) ke IP publik VPS.
2. Pastikan **API Token** sama dengan `api_token` di `config.json` VPS.
3. Simpan Konfigurasi. Tidak ada perubahan kode APK yang diperlukan —
   kontrak endpoint (`/status`, `/sync`, `/push`, `/table/{name}`) persis
   sama seperti server Termux.

## Yang TIDAK berubah
- Format response JSON semua endpoint.
- Skema database & migrasi Flutter.
- Header `X-API-Token` dan mekanisme auth (hanya ditambah rate-limit +
  timing-safe compare, tidak mengubah kondisi sukses/gagal yang sudah ada).
- `install_termux.sh` / `start_server_termux.sh` / dst — versi lokal HP
  tetap ada & berfungsi kalau suatu saat masih dibutuhkan untuk testing.

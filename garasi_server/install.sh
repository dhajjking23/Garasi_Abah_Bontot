#!/usr/bin/env bash
# ==============================================================
# GARASI ABAH BONTOT — install.sh (VPS Ubuntu 22.04 Production)
#
# Setup awal server di Oracle Cloud VPS. Jalankan SEKALI saat pertama
# kali deploy. Aman dijalankan ulang (idempotent).
#
# Pemakaian (sebagai user biasa dengan akses sudo, BUKAN root langsung):
#   bash install.sh
#
# Versi untuk testing lokal di HP/Termux: install_termux.sh (TIDAK diubah,
# tetap berfungsi persis seperti sebelumnya).
# ==============================================================

set -e
cd "$(dirname "$0")"
APP_DIR="$(pwd)"

echo "=============================================="
echo " GARASI ABAH BONTOT — Setup VPS Ubuntu 22.04"
echo " Folder aplikasi: $APP_DIR"
echo "=============================================="

echo "[i] Update apt & pasang Python3/venv/pip..."
sudo apt-get update -y
sudo apt-get install -y python3 python3-venv python3-pip

echo "[OK] Python: $(python3 --version)"

if [ ! -d "venv" ]; then
  echo "[i] Membuat virtual environment di ./venv ..."
  python3 -m venv venv
else
  echo "[OK] venv sudah ada."
fi

echo "[i] Menginstall dependency dari requirements.txt..."
./venv/bin/pip install --upgrade pip --quiet
./venv/bin/pip install -r requirements.txt --quiet
echo "[OK] Dependency terpasang: $(./venv/bin/pip show flask 2>/dev/null | grep Version)"

mkdir -p logs data data/backup
echo "[OK] Folder logs/, data/, data/backup/ siap."

if [ ! -f "config.json" ]; then
  if [ -f "config.vps.example.json" ]; then
    cp config.vps.example.json config.json
    echo "[OK] config.json dibuat dari config.vps.example.json."
    echo "[!] PENTING: edit config.json, ganti api_token ke token acak yang kuat"
    echo "    (server ini akan terekspos ke internet publik)."
  else
    echo "[X] config.json TIDAK DITEMUKAN dan config.vps.example.json juga tidak ada."
    exit 1
  fi
else
  echo "[OK] config.json sudah ada, tidak ditimpa."
fi

python3 -c "
import json, sys
try:
    cfg = json.load(open('config.json'))
except Exception as e:
    print('[X] config.json tidak valid:', e)
    sys.exit(1)

required = ['server_id', 'port', 'db_path', 'backup_dir', 'api_token']
missing = [k for k in required if k not in cfg]
if missing:
    print('[!] Field config.json belum lengkap:', missing)
else:
    print('[OK] config.json valid.')

if cfg.get('api_token') in ('', 'GANTI_DENGAN_TOKEN_RAHASIA_ANDA', 'garasi_abah_bontot'):
    print('[!] PERINGATAN: api_token masih default. WAJIB diganti sebelum dipakai')
    print('    di internet publik -- lalu samakan juga di menu Server tiap APK.')
"

DB_PATH=$(python3 -c "import json,os; c=json.load(open('config.json')); p=c.get('db_path','data/garasi_abah_bontot.db'); print(p if os.path.isabs(p) else os.path.join('$APP_DIR', p))")
if [ ! -f "$DB_PATH" ]; then
  echo "[!] Database belum ada di: $DB_PATH"
  echo "    Ini NORMAL untuk instalasi baru. Migrasi data dari HP:"
  echo "      1. scp file .db dari HP admin ke VPS ini (lihat README_VPS.md)"
  echo "      2. jalankan: ./venv/bin/python migrate_to_master_db.py /path/ke/backup.db"
else
  echo "[OK] Database ditemukan: $DB_PATH"
fi

SERVICE_SRC="garasi-abah.service"
SERVICE_DST="/etc/systemd/system/garasi-abah.service"
if [ -f "$SERVICE_SRC" ]; then
  echo "[i] Memasang systemd service (butuh sudo)..."
  sed -e "s#__APP_DIR__#$APP_DIR#g" -e "s#__USER__#$(whoami)#g" "$SERVICE_SRC" \
    | sudo tee "$SERVICE_DST" > /dev/null
  sudo systemctl daemon-reload
  sudo systemctl enable garasi-abah.service
  echo "[OK] systemd service terpasang & di-enable (auto-start saat boot)."
else
  echo "[!] garasi-abah.service tidak ditemukan, lewati setup systemd."
fi

echo "=============================================="
echo " Instalasi selesai."
echo ""
echo " Jalankan server:"
echo "   sudo systemctl start garasi-abah      (via systemd, RECOMMENDED)"
echo "   bash start_server.sh                  (wrapper systemctl start + status)"
echo ""
echo " Cek status   : sudo systemctl status garasi-abah"
echo " Lihat log    : sudo journalctl -u garasi-abah -f"
echo "                tail -f logs/server.log logs/access.log logs/error.log"
echo " Stop         : bash stop_server.sh"
echo " Restart      : bash restart_server.sh"
echo "=============================================="

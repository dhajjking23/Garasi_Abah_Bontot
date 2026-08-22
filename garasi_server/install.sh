#!/data/data/com.termux/files/usr/bin/bash
# ==============================================================
# GARASI ABAH BONTOT V4 — install.sh
# Setup awal server Python di Termux. Jalankan SEKALI saat pertama
# kali deploy, atau ulang kalau pindah HP / install ulang Termux.
#
# Pemakaian:
#   bash install.sh
# ==============================================================

set -e
cd "$(dirname "$0")"

echo "=============================================="
echo " GARASI ABAH BONTOT V4 — Setup Server Termux"
echo "=============================================="

# --------------------------------------------------------------
# 1) Cek Python tersedia
# --------------------------------------------------------------
if ! command -v python3 >/dev/null 2>&1; then
  echo "[!] Python3 belum terpasang. Menginstall via pkg..."
  pkg update -y && pkg install python -y
else
  echo "[OK] Python3 ditemukan: $(python3 --version)"
fi

# --------------------------------------------------------------
# 2) Cek pip
# --------------------------------------------------------------
if ! python3 -m pip --version >/dev/null 2>&1; then
  echo "[!] pip belum tersedia. Menginstall..."
  pkg install python-pip -y
fi

# --------------------------------------------------------------
# 3) Izin penyimpanan (perlu untuk akses db_path & backup_dir di
#    /storage/emulated/0/...). Aman dipanggil berulang kali.
# --------------------------------------------------------------
if command -v termux-setup-storage >/dev/null 2>&1; then
  echo "[i] Meminta izin akses penyimpanan Android (approve di popup)..."
  termux-setup-storage
  sleep 1
fi

# --------------------------------------------------------------
# 4) Pastikan clang tersedia (jaga-jaga kalau ada dependency kecil yang
#    butuh compile — Flask & Waitress sendiri PURE PYTHON, tidak perlu
#    compiler, tapi ini pengaman kalau ada sub-dependency yang perlu).
# --------------------------------------------------------------
if ! command -v clang >/dev/null 2>&1; then
  echo "[i] clang belum terpasang, menginstall (jaga-jaga untuk build dependency kecil)..."
  pkg install clang -y || echo "[!] Gagal install clang, lanjut saja (biasanya tidak dibutuhkan)."
fi

# --------------------------------------------------------------
# 5) Install dependency Python (Flask + Waitress — pure Python,
#    TIDAK butuh Rust/compiler berat, selalu berhasil di Termux)
# --------------------------------------------------------------
echo "[i] Menginstall dependency dari requirements.txt (Flask + Waitress)..."
if ! pip install -r requirements.txt --quiet; then
  echo "[X] pip install GAGAL. Jalankan manual untuk lihat detail error:"
  echo "    pip install -r requirements.txt"
  exit 1
fi
echo "[OK] Dependency terpasang: $(pip show flask 2>/dev/null | grep Version)"

# --------------------------------------------------------------
# 6) Buat folder yang dibutuhkan
# --------------------------------------------------------------
mkdir -p logs data
echo "[OK] Folder logs/ dan data/ siap."

# --------------------------------------------------------------
# 7) Cek config.json ada & valid
# --------------------------------------------------------------
if [ ! -f "config.json" ]; then
  echo "[X] config.json TIDAK DITEMUKAN. Salin config.json ke folder ini dulu."
  exit 1
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

if cfg.get('api_token') in ('', 'GANTI_DENGAN_TOKEN_RAHASIA_ANDA'):
    print('[!] PERINGATAN: api_token masih default/kosong. Ganti sebelum dipakai di jaringan publik.')

import os
db_path = cfg.get('db_path', '')
if db_path and not os.path.exists(db_path):
    print('[!] PERINGATAN: db_path belum ditemukan (wajar jika aplikasi Flutter belum pernah dibuka):')
    print('   ', db_path)
"

# --------------------------------------------------------------
# 8) Buat folder backup_dir kalau belum ada
# --------------------------------------------------------------
BACKUP_DIR=$(python3 -c "import json;print(json.load(open('config.json')).get('backup_dir',''))")
if [ -n "$BACKUP_DIR" ]; then
  mkdir -p "$BACKUP_DIR" 2>/dev/null && echo "[OK] backup_dir siap: $BACKUP_DIR" \
    || echo "[!] Tidak bisa membuat backup_dir (cek izin storage): $BACKUP_DIR"
fi

echo "=============================================="
echo " Instalasi selesai."
echo ""
echo " Jalankan server dengan salah satu cara:"
echo "   bash start_server.sh            (manual, foreground)"
echo "   bash start_server.sh --bg       (background via tmux)"
echo "   bash start_server.sh --boot     (dipanggil Termux:Boot)"
echo ""
echo " Untuk auto-start saat HP nyala, install app Termux:Boot (F-Droid),"
echo " lalu jalankan:"
echo "   mkdir -p ~/.termux/boot"
echo "   cp termux_boot/start-garasi-server ~/.termux/boot/"
echo "=============================================="

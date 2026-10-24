#!/usr/bin/env bash
# ==============================================================
# GARASI ABAH BONTOT — stop_server.sh (VPS, wrapper systemd)
# Versi testing lokal HP/Termux: stop_server_termux.sh (tidak diubah).
# ==============================================================

cd "$(dirname "$0")"

if systemctl list-unit-files 2>/dev/null | grep -q "garasi-abah.service"; then
  sudo systemctl stop garasi-abah
  echo "Server (systemd garasi-abah) dihentikan."
else
  echo "[!] systemd service tidak terpasang. Mencoba hentikan proses manual..."
  if pkill -f "python.*main.py" 2>/dev/null; then
    echo "Proses main.py dihentikan (fallback pkill)."
  else
    echo "Tidak menemukan proses server yang berjalan."
  fi
fi

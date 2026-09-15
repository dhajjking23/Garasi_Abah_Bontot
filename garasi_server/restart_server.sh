#!/usr/bin/env bash
# ==============================================================
# GARASI ABAH BONTOT — restart_server.sh (VPS, wrapper systemd)
# Versi testing lokal HP/Termux: restart_server_termux.sh (tidak diubah).
# ==============================================================

cd "$(dirname "$0")"

if systemctl list-unit-files 2>/dev/null | grep -q "garasi-abah.service"; then
  sudo systemctl restart garasi-abah
  sleep 1
  sudo systemctl status garasi-abah --no-pager -l | head -n 12
else
  echo "[!] systemd service belum terpasang. Jalankan 'bash install.sh' dulu."
  bash stop_server.sh
  sleep 1
  bash start_server.sh
fi

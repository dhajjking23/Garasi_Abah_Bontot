#!/usr/bin/env bash
# ==============================================================
# GARASI ABAH BONTOT — start_server.sh (VPS, wrapper systemd)
# Server production dikelola systemd (garasi-abah.service) supaya
# otomatis hidup lagi kalau VPS restart / proses crash. Script ini
# cuma wrapper tipis: start via systemctl + tampilkan status.
#
# Kalau systemd belum terpasang (mis. belum sempat jalankan install.sh),
# fallback jalankan langsung pakai venv (foreground, sementara).
#
# Versi testing lokal HP/Termux: start_server_termux.sh (tidak diubah).
# ==============================================================

cd "$(dirname "$0")"

if systemctl list-unit-files 2>/dev/null | grep -q "garasi-abah.service"; then
  sudo systemctl start garasi-abah
  sleep 1
  sudo systemctl status garasi-abah --no-pager -l | head -n 12
  echo ""
  echo "Log realtime : sudo journalctl -u garasi-abah -f"
else
  echo "[!] systemd service belum terpasang. Jalankan 'bash install.sh' dulu,"
  echo "    atau jalankan langsung sementara (foreground, Ctrl+C untuk stop):"
  mkdir -p logs
  if [ -x "venv/bin/python" ]; then
    ./venv/bin/python main.py
  else
    python3 main.py
  fi
fi

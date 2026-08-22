#!/data/data/com.termux/files/usr/bin/bash
# ==============================================================
# GARASI ABAH BONTOT V4 — stop_server.sh
# Menghentikan server apapun modenya (Manual/Tmux/AutoBoot).
# ==============================================================

cd "$(dirname "$0")"

PID_FILE="server.pid"
MODE_FILE="server.mode"
STOPPED=false

# 1) Sesi tmux (mode Background)
if command -v tmux >/dev/null 2>&1 && tmux has-session -t garasi_server 2>/dev/null; then
  tmux kill-session -t garasi_server
  echo "Sesi tmux 'garasi_server' dihentikan."
  STOPPED=true
fi

# 2) PID tercatat (mode Manual / AutoBoot)
if [ -f "$PID_FILE" ]; then
  PID=$(cat "$PID_FILE")
  if kill -0 "$PID" 2>/dev/null; then
    kill "$PID" 2>/dev/null
    echo "Server (PID $PID) dihentikan."
    STOPPED=true
  fi
  rm -f "$PID_FILE"
fi
rm -f "$MODE_FILE"

# 3) Fallback: cari proses python3 main.py lewat pattern (jaga-jaga
#    kalau PID file hilang / server dijalankan manual dari terminal lain)
if [ "$STOPPED" = false ]; then
  if command -v pkill >/dev/null 2>&1; then
    if pkill -f "python3 main.py"; then
      echo "Proses python3 main.py dihentikan (fallback pkill)."
      STOPPED=true
    fi
  fi
fi

if [ "$STOPPED" = false ]; then
  echo "Tidak menemukan server yang sedang berjalan (PID file/tmux/pattern)."
  echo "Jika server masih berjalan manual di terminal lain, tekan CTRL+C di sana."
fi

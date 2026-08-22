#!/data/data/com.termux/files/usr/bin/bash
# ==============================================================
# GARASI ABAH BONTOT V4 — start_server.sh
# ==============================================================
# 3 mode menjalankan server, database & server.py yang dipakai SAMA
# persis di ketiga mode — hanya cara menjalankannya yang beda:
#
#   bash start_server.sh              -> MANUAL (foreground, Ctrl+C stop)
#   bash start_server.sh --bg         -> BACKGROUND pakai tmux (opsional)
#   bash start_server.sh --boot       -> dipanggil Termux:Boot saat HP nyala
#
# tmux TIDAK WAJIB. Kalau tidak mau pakai tmux, cukup jalankan MANUAL,
# atau AUTO START (--boot) yang juga tidak butuh tmux.
# ==============================================================

cd "$(dirname "$0")"
mkdir -p logs

PORT=$(python3 -c "import json;print(json.load(open('config.json'))['port'])" 2>/dev/null || echo 8000)
PID_FILE="server.pid"
MODE_FILE="server.mode"

MODE="MANUAL"
case "$1" in
  --bg|--tmux) MODE="TMUX" ;;
  --boot) MODE="AUTOBOOT" ;;
esac

# --------------------------------------------------------------
# Cegah server ganda: cek port sudah aktif atau belum
# --------------------------------------------------------------
if python3 port_check.py "$PORT"; then
  echo "Server GARASI ABAH BONTOT SUDAH BERJALAN di port $PORT."
  echo "Tidak menjalankan instance kedua. Pakai: bash restart_server.sh jika ingin memulai ulang."
  exit 0
fi

pip install -r requirements.txt --quiet

export GARASI_SERVER_MODE="$MODE"
echo "$MODE" > "$MODE_FILE"

case "$MODE" in
  TMUX)
    if ! command -v tmux >/dev/null 2>&1; then
      echo "tmux belum terpasang. Install dulu: pkg install tmux -y"
      echo "Atau jalankan tanpa tmux: bash start_server.sh"
      exit 1
    fi
    SESSION="garasi_server"
    if tmux has-session -t "$SESSION" 2>/dev/null; then
      echo "Sesi tmux '$SESSION' sudah ada. Cek: tmux attach -t $SESSION"
      exit 0
    fi
    tmux new-session -d -s "$SESSION" \
      "export GARASI_SERVER_MODE=TMUX; python3 main.py >> logs/server.log 2>&1"
    echo "Server dijalankan BACKGROUND via tmux (sesi: $SESSION), port $PORT."
    echo "Lihat log   : tmux attach -t $SESSION"
    echo "Hentikan    : bash stop_server.sh"
    ;;

  AUTOBOOT)
    nohup python3 main.py >> logs/server.log 2>&1 &
    echo $! > "$PID_FILE"
    echo "Server dijalankan AUTO START (Termux:Boot), PID $(cat "$PID_FILE"), port $PORT."
    ;;

  *)
    echo "Server MANUAL berjalan di port $PORT — tekan CTRL+C untuk berhenti."
    trap 'rm -f "$PID_FILE" "$MODE_FILE"; exit 0' INT TERM
    python3 main.py 2>&1 | tee -a logs/server.log &
    echo $! > "$PID_FILE"
    wait
    rm -f "$PID_FILE" "$MODE_FILE"
    ;;
esac

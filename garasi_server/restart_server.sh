#!/data/data/com.termux/files/usr/bin/bash
# GARASI ABAH BONTOT V4 — restart_server.sh
# Pemakaian sama seperti start_server.sh:
#   bash restart_server.sh          -> restart MANUAL
#   bash restart_server.sh --bg     -> restart BACKGROUND (tmux)
#   bash restart_server.sh --boot   -> restart mode AUTOBOOT

cd "$(dirname "$0")"
bash stop_server.sh
sleep 1
bash start_server.sh "$@"

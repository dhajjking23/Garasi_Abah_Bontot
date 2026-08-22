#!/usr/bin/env python3
"""
stop_server.py
Pengganti stop_server.sh (Python murni). Menghentikan server apapun
modenya (Manual/Background/AutoBoot). Baca PID dari server.pid dulu,
fallback ke pemindaian /proc kalau file PID hilang.

Pemakaian:
    python stop_server.py
"""

import os
import signal
import sys

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
os.chdir(BASE_DIR)

PID_FILE = os.path.join(BASE_DIR, "server.pid")
MODE_FILE = os.path.join(BASE_DIR, "server.mode")


def pid_running(pid: int) -> bool:
    try:
        os.kill(pid, 0)
        return True
    except OSError:
        return False


def find_server_pids():
    """Fallback: scan /proc untuk proses `python main.py` (jaga-jaga kalau
    server.pid hilang atau server dijalankan manual dari terminal lain)."""
    pids = []
    if not os.path.isdir("/proc"):
        return pids
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        cmdline_path = f"/proc/{entry}/cmdline"
        try:
            with open(cmdline_path, "rb") as f:
                cmdline = f.read().decode(errors="ignore").replace("\x00", " ")
        except Exception:
            continue
        if "main.py" in cmdline and "garasi" in cmdline.lower():
            pids.append(int(entry))
        elif "main.py" in cmdline and BASE_DIR in cmdline:
            pids.append(int(entry))
    return list(set(pids))


def main():
    stopped = False

    if os.path.exists(PID_FILE):
        try:
            with open(PID_FILE) as f:
                pid = int(f.read().strip())
            if pid_running(pid):
                os.kill(pid, signal.SIGTERM)
                print(f"Server (PID {pid}) dihentikan.")
                stopped = True
        except Exception as e:
            print(f"[!] Gagal membaca/menghentikan dari server.pid: {e}")
        try:
            os.remove(PID_FILE)
        except FileNotFoundError:
            pass

    if os.path.exists(MODE_FILE):
        os.remove(MODE_FILE)

    if not stopped:
        fallback_pids = find_server_pids()
        for pid in fallback_pids:
            try:
                os.kill(pid, signal.SIGTERM)
                print(f"Proses server (PID {pid}) dihentikan (fallback pemindaian /proc).")
                stopped = True
            except Exception:
                pass

    if not stopped:
        print("Tidak menemukan server yang sedang berjalan (PID file/proses tidak ketemu).")
        print("Jika server masih berjalan manual di terminal lain, tekan CTRL+C di sana.")
    else:
        print("Selesai.")


if __name__ == "__main__":
    main()

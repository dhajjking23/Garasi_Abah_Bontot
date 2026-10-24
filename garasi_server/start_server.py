#!/usr/bin/env python3
"""
start_server.py
Pengganti start_server.sh dalam bentuk PYTHON MURNI — dipakai kalau bash di
Termux Anda bermasalah/tidak kompatibel. Perilaku & kontrak SAMA PERSIS
dengan start_server.sh lama:

    python start_server.py              -> MANUAL   (foreground, Ctrl+C untuk stop)
    python start_server.py --bg         -> BACKGROUND (proses lepas dari terminal, tanpa tmux)
    python start_server.py --boot       -> AUTOBOOT  (dipanggil dari Termux:Boot)

Yang dilakukan (sama seperti versi bash):
    1. Cegah instance ganda (cek port sudah aktif via port_check.py).
    2. Install dependency dari requirements.txt (Flask + Waitress — pure
       Python, tidak perlu compiler apapun, selalu berhasil di Termux).
    3. Set env GARASI_SERVER_MODE & tulis file server.mode.
    4. Jalankan `python main.py` sebagai subprocess, log ke logs/server.log.
    5. Tulis server.pid supaya bisa dihentikan oleh stop_server.py.

Tidak butuh tmux, bash, atau uvicorn/ASGI sama sekali — semuanya
subprocess.Popen bawaan Python, jadi kompatibel di Termux versi apa pun
selama Python3 terpasang.
"""

import json
import os
import subprocess
import sys

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
os.chdir(BASE_DIR)
sys.path.insert(0, BASE_DIR)

import port_check  # reuse logic pengecekan port yang sudah ada

PID_FILE = os.path.join(BASE_DIR, "server.pid")
MODE_FILE = os.path.join(BASE_DIR, "server.mode")
LOG_DIR = os.path.join(BASE_DIR, "logs")
LOG_FILE = os.path.join(LOG_DIR, "server.log")


def get_port() -> int:
    cfg_path = os.path.join(BASE_DIR, "config.json")
    try:
        with open(cfg_path) as f:
            return int(json.load(f).get("port", 8000))
    except Exception:
        return 8000


def parse_mode() -> str:
    if "--bg" in sys.argv or "--tmux" in sys.argv:
        return "BACKGROUND"
    if "--boot" in sys.argv:
        return "AUTOBOOT"
    return "MANUAL"


def install_requirements() -> bool:
    """Install Flask + Waitress (pure Python, tidak perlu compiler).
    Return True kalau sukses, False kalau gagal — dipakai untuk memutuskan
    apakah aman melanjutkan ke tahap start server."""
    req = os.path.join(BASE_DIR, "requirements.txt")
    if not os.path.exists(req):
        return True
    print("[i] Memastikan dependency terpasang (pip install)...")
    result = subprocess.run(
        [sys.executable, "-m", "pip", "install", "-r", req, "--quiet"],
        capture_output=True, text=True,
    )
    if result.returncode != 0:
        print("[X] pip install GAGAL. Detail error:")
        print(result.stderr[-800:] if result.stderr else "(tidak ada detail error)")
        print()
        print("Coba jalankan manual untuk lihat error lengkap:")
        print(f"    pip install -r {req}")
        return False
    print("[OK] Dependency siap.")
    return True


def main():
    os.makedirs(LOG_DIR, exist_ok=True)
    port = get_port()
    mode = parse_mode()

    if port_check.is_port_active(port):
        print(f"Server GARASI ABAH BONTOT SUDAH BERJALAN di port {port}.")
        print("Tidak menjalankan instance kedua. Pakai: python restart_server.py")
        return

    if not install_requirements():
        print()
        print("[X] Server TIDAK dijalankan karena dependency belum terpasang.")
        sys.exit(1)

    env = os.environ.copy()
    env["GARASI_SERVER_MODE"] = mode
    with open(MODE_FILE, "w") as f:
        f.write(mode)

    server_cmd = [sys.executable, os.path.join(BASE_DIR, "main.py")]

    if mode == "MANUAL":
        print(f"Server MANUAL berjalan di port {port} — tekan CTRL+C untuk berhenti.")
        with open(LOG_FILE, "a") as logf:
            proc = subprocess.Popen(server_cmd, env=env, stdout=logf, stderr=subprocess.STDOUT)
            with open(PID_FILE, "w") as pf:
                pf.write(str(proc.pid))
            try:
                proc.wait()
            except KeyboardInterrupt:
                print("\nMenghentikan server...")
                proc.terminate()
                try:
                    proc.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    proc.kill()
            finally:
                for f_ in (PID_FILE, MODE_FILE):
                    if os.path.exists(f_):
                        os.remove(f_)
    else:
        # BACKGROUND / AUTOBOOT: proses dilepas dari terminal, tidak nge-block.
        with open(LOG_FILE, "a") as logf:
            popen_kwargs = {}
            if os.name != "nt":
                popen_kwargs["start_new_session"] = True  # setara nohup
            proc = subprocess.Popen(
                server_cmd, env=env, stdout=logf, stderr=subprocess.STDOUT, **popen_kwargs
            )
        with open(PID_FILE, "w") as pf:
            pf.write(str(proc.pid))
        label = "BACKGROUND" if mode == "BACKGROUND" else "AUTO START (Termux:Boot)"
        print(f"Server dijalankan {label}, PID {proc.pid}, port {port}.")
        print(f"Lihat log   : tail -f {LOG_FILE}")
        print("Hentikan    : python stop_server.py")


if __name__ == "__main__":
    main()

"""
utils/network.py
Helper jaringan — dipindah persis dari server.py lama (get_local_ip,
get_server_mode). Logic TIDAK diubah, hanya dipindah lokasi supaya
main.py & api/routes.py tetap ringkas.
"""

import os
import socket


def get_local_ip() -> str:
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
    except Exception:
        ip = "127.0.0.1"
    finally:
        s.close()
    return ip


def get_server_mode() -> str:
    """
    Mode dilaporkan ke aplikasi Flutter (ditampilkan di menu Server):
    MANUAL / TMUX / AUTOBOOT. Dibaca dari env var GARASI_SERVER_MODE
    (di-export oleh start_server.sh saat menjalankan uvicorn), dengan
    fallback ke file server.mode di folder yang sama dengan server ini.
    """
    mode = os.environ.get("GARASI_SERVER_MODE")
    if mode:
        return mode
    base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    mode_file = os.path.join(base_dir, "server.mode")
    try:
        with open(mode_file) as f:
            return f.read().strip() or "MANUAL"
    except Exception:
        return "MANUAL"

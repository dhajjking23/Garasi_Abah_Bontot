#!/usr/bin/env python3
"""
port_check.py — cek apakah port sudah ada yang memakai (server ganda).
Dipanggil dari start_server.sh / stop_server.sh via python3.
Exit code 0 = port AKTIF (ada proses dengar di situ).
Exit code 1 = port BEBAS.
"""
import socket
import sys
import json
import os


def get_port():
    if len(sys.argv) > 1:
        return int(sys.argv[1])
    cfg_path = os.path.join(os.path.dirname(__file__), "config.json")
    try:
        with open(cfg_path) as f:
            return json.load(f).get("port", 8000)
    except Exception:
        return 8000


def is_port_active(port: int, host: str = "127.0.0.1") -> bool:
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(1)
    try:
        result = s.connect_ex((host, port))
        return result == 0
    finally:
        s.close()


if __name__ == "__main__":
    port = get_port()
    sys.exit(0 if is_port_active(port) else 1)

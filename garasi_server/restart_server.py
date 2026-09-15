#!/usr/bin/env python3
"""
restart_server.py
Pengganti restart_server.sh (Python murni).

Pemakaian sama seperti start_server.py:
    python restart_server.py          -> restart MANUAL
    python restart_server.py --bg     -> restart BACKGROUND
    python restart_server.py --boot   -> restart mode AUTOBOOT
"""

import os
import subprocess
import sys
import time

BASE_DIR = os.path.dirname(os.path.abspath(__file__))


def main():
    subprocess.run([sys.executable, os.path.join(BASE_DIR, "stop_server.py")])
    time.sleep(1)
    subprocess.run([sys.executable, os.path.join(BASE_DIR, "start_server.py"), *sys.argv[1:]])


if __name__ == "__main__":
    main()

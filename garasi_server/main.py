"""
main.py — GARASI ABAH BONTOT V4 Local Server (Flask + Waitress)

KENAPA FLASK, BUKAN FASTAPI?
FastAPI menyeret pydantic v2, yang inti pemrosesannya (pydantic-core)
ditulis dalam Rust dan tidak punya wheel siap-pakai untuk Termux ARM64.
Akibatnya pip terpaksa compile dari source pakai toolchain Rust
(cargo/maturin) yang tidak tersedia di Termux secara default — install
SELALU gagal kecuali toolchain Rust lengkap dipasang (berat & rumit di
Android).

Flask + Waitress 100% PURE PYTHON — tidak ada satupun dependency yang
perlu dikompilasi. Install akan selalu berhasil di Termux ARM64 tanpa
syarat tambahan apapun.

KONTRAK API TIDAK BERUBAH — endpoint, method, field JSON, header
X-API-Token semuanya identik dengan versi FastAPI sebelumnya. APK tidak
akan melihat perbedaan apapun.

Jalankan:
    python main.py

Kompatibilitas mundur: server.py adalah shim 1-baris (`from main import
app`) — app di sini adalah Flask app yang sama.
"""

import os
import threading

from flask import Flask

from api.routes import bp as api_bp
from config import CONFIG, HOST, PORT
from services.backup_service import backup_scheduler_loop
from utils.error_handler import register_error_handlers
from utils.logger import log

app = Flask(__name__)
app.register_blueprint(api_bp)
register_error_handlers(app)

_backup_thread_started = False


def _start_backup_thread():
    global _backup_thread_started
    if _backup_thread_started:
        return
    t = threading.Thread(target=backup_scheduler_loop, daemon=True, name="backup-scheduler")
    t.start()
    _backup_thread_started = True


log.info("=" * 50)
log.info("GARASI ABAH BONTOT Server starting (PID=%s)", os.getpid())
log.info("Host=%s Port=%s DB=%s", HOST, PORT, CONFIG.get("db_path"))
log.info("=" * 50)
_start_backup_thread()


if __name__ == "__main__":
    from waitress import serve

    print(f"Server GARASI ABAH BONTOT berjalan di http://{HOST}:{PORT}")
    print("Tekan CTRL+C untuk berhenti (kalau dijalankan manual/foreground).")
    try:
        # single process, thread pool kecil - ringan untuk Android 24 jam
        serve(app, host=HOST, port=PORT, threads=4)
    except KeyboardInterrupt:
        log.info("GARASI ABAH BONTOT Server dihentikan (graceful, KeyboardInterrupt).")

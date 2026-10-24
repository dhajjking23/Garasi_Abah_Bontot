"""
main.py — GARASI ABAH BONTOT Server (Flask + Waitress)

KENAPA FLASK, BUKAN FASTAPI?
FastAPI menyeret pydantic v2, yang inti pemrosesannya (pydantic-core)
ditulis dalam Rust. Di Termux ARM64 ini sering gagal install tanpa
toolchain Rust lengkap. Flask + Waitress 100% PURE PYTHON — selalu
berhasil install di Termux MAUPUN di VPS Ubuntu biasa, tanpa syarat
tambahan apapun. Karena itu kode yang sama ini dipakai baik untuk server
lokal Termux (testing di HP) maupun deployment VPS production — tidak ada
percabangan kode antara keduanya, hanya config.json & cara menjalankannya
(systemd di VPS, tmux/manual di Termux) yang beda. Lihat README_VPS.md.

KONTRAK API TIDAK BERUBAH — endpoint, method, field JSON, header
X-API-Token semuanya identik dari V4 sampai V5.3 (VPS). APK Android tidak
perlu update apapun untuk pindah dari server Termux ke VPS, selama
host/port di menu Server aplikasi diarahkan ke alamat VPS.

Jalankan:
    python main.py

Kompatibilitas mundur: server.py adalah shim 1-baris (`from main import
app`) — app di sini adalah Flask app yang sama.
"""

import os
import threading
import time

from flask import Flask, g, request

from api.routes import bp as api_bp
from config import CONFIG, HOST, PORT, ENVIRONMENT, DB_PATH
from services.backup_service import backup_scheduler_loop
from utils.error_handler import register_error_handlers
from utils.logger import log, access_log

app = Flask(__name__)
app.register_blueprint(api_bp)
register_error_handlers(app)

# V5.3 — VPS PRODUCTION: batasi ukuran body request (proteksi ringan
# terhadap payload berlebihan/serangan) — endpoint yang ada (push/sync)
# tidak pernah butuh body sebesar ini untuk pemakaian normal 1 owner +
# beberapa viewer, jadi aman & tidak mengubah perilaku normal sama sekali.
app.config["MAX_CONTENT_LENGTH"] = 16 * 1024 * 1024  # 16 MB


@app.before_request
def _access_log_start():
    g._start_time = time.monotonic()


@app.after_request
def _access_log_write(response):
    # V5.3: access.log — 1 baris per request (method, path, status, IP,
    # durasi). Tidak mengubah response apapun, murni observability untuk
    # VPS production (item 6: logs/access.log).
    try:
        duration_ms = (time.monotonic() - getattr(g, "_start_time", time.monotonic())) * 1000
        ip = request.headers.get("X-Forwarded-For", request.remote_addr or "-").split(",")[0].strip()
        access_log.info(
            '%s "%s %s" %s %.1fms',
            ip, request.method, request.path, response.status_code, duration_ms,
        )
    except Exception:
        pass  # access log tidak boleh pernah menggagalkan response asli
    return response


_backup_thread_started = False


def _start_backup_thread():
    global _backup_thread_started
    if _backup_thread_started:
        return
    t = threading.Thread(target=backup_scheduler_loop, daemon=True, name="backup-scheduler")
    t.start()
    _backup_thread_started = True


# Pastikan folder DB ada sebelum request pertama masuk — penting untuk VPS
# baru yang belum pernah dijalankan sama sekali (item 1: "database
# otomatis dibuat jika belum ada"). File .db sendiri baru benar-benar ada
# setelah migrate_to_master_db.py dijalankan (lihat README_VPS.md) — kalau
# belum, /status akan melaporkan itu dengan jelas (lihat database.diagnose()),
# bukan error generik.
os.makedirs(os.path.dirname(DB_PATH), exist_ok=True)

log.info("=" * 50)
log.info("GARASI ABAH BONTOT Server starting (PID=%s, env=%s)", os.getpid(), ENVIRONMENT)
log.info("Host=%s Port=%s DB=%s", HOST, PORT, CONFIG.get("db_path"))
log.info("=" * 50)
_start_backup_thread()


if __name__ == "__main__":
    from waitress import serve

    print(f"Server GARASI ABAH BONTOT ({ENVIRONMENT}) berjalan di http://{HOST}:{PORT}")
    print("Tekan CTRL+C untuk berhenti (kalau dijalankan manual/foreground).")
    try:
        # single process, thread pool kecil - cukup untuk 1 owner + beberapa
        # viewer di VPS kecil (1-2 vCPU) maupun HP Android 24 jam.
        serve(app, host=HOST, port=PORT, threads=4)
    except KeyboardInterrupt:
        log.info("GARASI ABAH BONTOT Server dihentikan (graceful, KeyboardInterrupt).")

"""
api/auth.py
Verifikasi token — versi Flask (decorator), pengganti Depends(verify_token)
versi FastAPI. Perilaku & response error TIDAK berubah: request tanpa
header X-API-Token yang cocok tetap ditolak dengan status 401 dan body
JSON {"detail": "Token tidak valid"} — persis sama seperti sebelumnya,
supaya APK tidak melihat perbedaan apapun.
"""

from functools import wraps

from flask import jsonify, request

from config import API_TOKEN
from utils.logger import log


def verify_token(view_func):
    """Decorator: pasang di atas route yang butuh proteksi token, contoh:

        @bp.get("/status")
        @verify_token
        def status():
            ...
    """

    @wraps(view_func)
    def wrapper(*args, **kwargs):
        if not API_TOKEN or API_TOKEN == "GANTI_DENGAN_TOKEN_RAHASIA_ANDA":
            log.warning("API_TOKEN belum dikonfigurasi di config.json!")
        token = request.headers.get("X-API-Token", "")
        if token != API_TOKEN:
            log.warning("Sync ditolak: token tidak valid.")
            return jsonify({"detail": "Token tidak valid"}), 401
        return view_func(*args, **kwargs)

    return wrapper

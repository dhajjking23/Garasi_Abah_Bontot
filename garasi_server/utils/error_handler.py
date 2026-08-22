"""
utils/error_handler.py
Global exception handler — versi Flask.

Kalau ada error tak terduga di endpoint manapun (bug, DB terkunci, dll),
server tidak menampilkan halaman HTML error bawaan Werkzeug, melainkan
JSON yang rapi dengan status 500. Error tetap dicatat ke logs/server.log
untuk didiagnosis dari HP.

Error HTTP standar (404 Not Found, 405 Method Not Allowed, dan 401 yang
sudah ditangani manual oleh api/auth.py) DIBIARKAN LEWAT APA ADANYA —
handler ini hanya menangkap exception yang benar-benar tidak terduga.
"""

from flask import jsonify
from werkzeug.exceptions import HTTPException

from utils.logger import log


def register_error_handlers(app):
    @app.errorhandler(Exception)
    def handle_unexpected_error(exc):
        if isinstance(exc, HTTPException):
            # 404/405/dll bawaan Flask — biarkan format aslinya, tidak perlu diubah
            return exc

        log.exception("Unhandled error: %s", exc)
        return (
            jsonify({
                "ok": False,
                "error": "internal_server_error",
                "detail": "Terjadi kesalahan internal di server. Cek logs/server.log.",
            }),
            500,
        )

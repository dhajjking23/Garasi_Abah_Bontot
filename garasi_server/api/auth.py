"""
api/auth.py
Verifikasi token — versi Flask (decorator), pengganti Depends(verify_token)
versi FastAPI. Perilaku & response error TIDAK berubah: request tanpa
header X-API-Token yang cocok tetap ditolak dengan status 401 dan body
JSON {"detail": "Token tidak valid"} — persis sama seperti sebelumnya,
supaya APK tidak melihat perbedaan apapun.

V5.3 — VPS PRODUCTION: server sekarang terekspos ke internet publik (beda
dari LAN lokal Termux), jadi ditambah 2 lapis proteksi ringan yang TIDAK
mengubah kontrak sukses (200) sama sekali:
  1. Perbandingan token pakai hmac.compare_digest (timing-safe) —
     mencegah timing attack untuk menebak token karakter-per-karakter.
  2. Rate limit sederhana per-IP (in-memory, tanpa dependency tambahan) —
     menahan brute-force token / penyalahgunaan. Request yang kena limit
     dapat status 429 dengan body JSON {"detail": "..."}, format konsisten
     dengan error 401 yang sudah ada.
"""

import hmac
import time
from collections import defaultdict, deque
from functools import wraps
from threading import Lock

from flask import jsonify, request

from config import API_TOKEN, RATE_LIMIT_PER_MINUTE
from utils.logger import log

_WINDOW_SECONDS = 60
_hits: dict[str, deque] = defaultdict(deque)
_hits_lock = Lock()


def _client_ip() -> str:
    # Dukung reverse proxy (nginx) di depan server VPS: X-Forwarded-For
    # kalau ada, fallback ke remote_addr langsung (setup tanpa proxy).
    forwarded = request.headers.get("X-Forwarded-For", "")
    if forwarded:
        return forwarded.split(",")[0].strip()
    return request.remote_addr or "unknown"


def _rate_limited(ip: str) -> bool:
    if RATE_LIMIT_PER_MINUTE <= 0:
        return False  # 0/negatif = rate limit dimatikan
    now = time.monotonic()
    with _hits_lock:
        q = _hits[ip]
        while q and now - q[0] > _WINDOW_SECONDS:
            q.popleft()
        if len(q) >= RATE_LIMIT_PER_MINUTE:
            return True
        q.append(now)
    return False


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

        ip = _client_ip()
        if _rate_limited(ip):
            log.warning("Rate limit terlampaui dari IP %s (%s).", ip, request.path)
            return jsonify({"detail": "Terlalu banyak request, coba lagi sebentar."}), 429

        token = request.headers.get("X-API-Token", "")
        if not hmac.compare_digest(token, API_TOKEN):
            log.warning("Sync ditolak: token tidak valid (IP %s).", ip)
            return jsonify({"detail": "Token tidak valid"}), 401
        return view_func(*args, **kwargs)

    return wrapper

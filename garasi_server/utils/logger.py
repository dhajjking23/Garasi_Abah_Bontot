"""
utils/logger.py
Setup logging terpusat untuk seluruh server. Menulis ke 3 file terpisah di
LOG_DIR (V5.3):
  - server.log  : semua log INFO ke atas (perilaku lama, tidak berubah)
  - error.log   : HANYA level ERROR ke atas (subset dari server.log, biar
                  gampang cek cepat tanpa scroll log umum)
  - access.log  : 1 baris per HTTP request (method, path, status, IP,
                  durasi) -- ditulis oleh access_log() lewat after_request
                  hook di main.py, BUKAN oleh `log` biasa.

Semua file dirotasi otomatis (max 2MB, simpan 5 file lama) supaya tidak
memenuhi disk kalau server jalan 24/7 di VPS.
"""

import logging
import os
from logging.handlers import RotatingFileHandler

from config import LOG_DIR

_LOGGER_NAME = "garasi_server"
_ACCESS_LOGGER_NAME = "garasi_server.access"
_configured = False


def _rotating_handler(filename: str, level: int, formatter: logging.Formatter) -> RotatingFileHandler:
    handler = RotatingFileHandler(
        os.path.join(LOG_DIR, filename), maxBytes=2 * 1024 * 1024, backupCount=5, encoding="utf-8"
    )
    handler.setLevel(level)
    handler.setFormatter(formatter)
    return handler


def setup_logging() -> logging.Logger:
    global _configured
    logger = logging.getLogger(_LOGGER_NAME)

    if _configured:
        return logger

    os.makedirs(LOG_DIR, exist_ok=True)
    formatter = logging.Formatter("%(asctime)s %(levelname)s [%(name)s] %(message)s")

    logger.setLevel(logging.INFO)
    logger.addHandler(_rotating_handler("server.log", logging.INFO, formatter))
    logger.addHandler(_rotating_handler("error.log", logging.ERROR, formatter))
    logger.propagate = False

    access_logger = logging.getLogger(_ACCESS_LOGGER_NAME)
    access_logger.setLevel(logging.INFO)
    access_formatter = logging.Formatter("%(asctime)s %(message)s")
    access_logger.addHandler(_rotating_handler("access.log", logging.INFO, access_formatter))
    access_logger.propagate = False

    _configured = True
    return logger


# Logger siap pakai — import ini di modul lain: `from utils.logger import log`
log = setup_logging()
access_log = logging.getLogger(_ACCESS_LOGGER_NAME)

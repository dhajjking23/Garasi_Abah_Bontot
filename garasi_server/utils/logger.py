"""
utils/logger.py
Setup logging terpusat untuk seluruh server. Menulis ke logs/server.log
dengan rotasi otomatis (max 2MB per file, simpan 5 file lama) supaya tidak
memenuhi penyimpanan HP kalau server jalan 24 jam terus-menerus.
"""

import logging
import os
from logging.handlers import RotatingFileHandler

from config import LOG_DIR

_LOGGER_NAME = "garasi_server"
_configured = False


def setup_logging() -> logging.Logger:
    global _configured
    logger = logging.getLogger(_LOGGER_NAME)

    if _configured:
        return logger

    os.makedirs(LOG_DIR, exist_ok=True)
    log_file = os.path.join(LOG_DIR, "server.log")

    formatter = logging.Formatter("%(asctime)s %(levelname)s [%(name)s] %(message)s")

    file_handler = RotatingFileHandler(
        log_file, maxBytes=2 * 1024 * 1024, backupCount=5, encoding="utf-8"
    )
    file_handler.setFormatter(formatter)

    logger.setLevel(logging.INFO)
    logger.addHandler(file_handler)
    logger.propagate = False

    _configured = True
    return logger


# Logger siap pakai — import ini di modul lain: `from utils.logger import log`
log = setup_logging()

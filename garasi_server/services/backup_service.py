"""
services/backup_service.py
Backup database otomatis — FITUR BARU.

Di server lama, config.json sudah punya field "auto_backup_time" tapi tidak
ada kode yang benar-benar menjalankannya. Modul ini mengisi gap tersebut:

- Setiap menit, cek apakah jam:menit sekarang cocok dengan auto_backup_time.
- Kalau cocok (dan belum backup hari ini), salin database (pakai SQLite
  Online Backup API — aman dipakai walau DB sedang dibuka Flutter) ke
  BACKUP_DIR dengan nama file bertimestamp.
- Hapus backup lama, sisakan BACKUP_RETENTION file terbaru.

Berjalan sebagai background thread di dalam proses server yang sama (Flask
+ Waitress bersifat sinkron, jadi dipakai threading.Thread, bukan asyncio)
— TIDAK butuh cron, systemd, atau proses terpisah, supaya tetap ringan &
kompatibel Termux single-process.

Tidak ada endpoint baru yang wajib dipanggil APK — proses ini otomatis,
tidak mengubah kontrak API sama sekali.
"""

import os
import time
import sqlite3
from datetime import datetime

from config import DB_PATH, BACKUP_DIR, AUTO_BACKUP_TIME, BACKUP_RETENTION
from utils.logger import log

_last_backup_date = None  # cegah backup berulang kali di menit yang sama


def _do_backup() -> str | None:
    """Backup sinkron: copy DB pakai SQLite backup API (aman untuk DB yang
    sedang aktif dipakai), lalu rapikan file lama. Return path file backup
    kalau berhasil, None kalau gagal."""
    try:
        os.makedirs(BACKUP_DIR, exist_ok=True)
    except Exception as e:
        log.error("Gagal membuat folder backup_dir (%s): %s", BACKUP_DIR, e)
        return None

    if not DB_PATH or not os.path.exists(DB_PATH):
        log.warning("Backup dibatalkan: db_path tidak ditemukan (%s)", DB_PATH)
        return None

    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    dest_path = os.path.join(BACKUP_DIR, f"garasi_backup_{timestamp}.db")

    try:
        src_conn = sqlite3.connect(DB_PATH, timeout=5)
        dest_conn = sqlite3.connect(dest_path)
        with dest_conn:
            src_conn.backup(dest_conn)
        dest_conn.close()
        src_conn.close()
        log.info("Backup database berhasil: %s", dest_path)
    except Exception as e:
        log.error("Backup database gagal: %s", e)
        return None

    _cleanup_old_backups()
    return dest_path


def _cleanup_old_backups():
    try:
        files = sorted(
            (f for f in os.listdir(BACKUP_DIR) if f.startswith("garasi_backup_") and f.endswith(".db")),
            reverse=True,
        )
        for old_file in files[BACKUP_RETENTION:]:
            try:
                os.remove(os.path.join(BACKUP_DIR, old_file))
                log.info("Backup lama dihapus (retensi %d): %s", BACKUP_RETENTION, old_file)
            except Exception as e:
                log.warning("Gagal menghapus backup lama %s: %s", old_file, e)
    except FileNotFoundError:
        pass


def backup_now() -> str | None:
    """Trigger backup manual/on-demand — dipakai internal saat startup opsional."""
    return _do_backup()


def backup_scheduler_loop():
    """Loop background (dijalankan di thread terpisah oleh main.py): cek
    tiap 60 detik apakah waktunya backup harian."""
    global _last_backup_date
    log.info("Backup scheduler aktif. Jadwal harian: %s, retensi %d file.", AUTO_BACKUP_TIME, BACKUP_RETENTION)
    while True:
        try:
            now = datetime.now()
            current_hm = now.strftime("%H:%M")
            today = now.strftime("%Y-%m-%d")
            if current_hm == AUTO_BACKUP_TIME and _last_backup_date != today:
                _do_backup()
                _last_backup_date = today
        except Exception as e:
            log.error("Error di backup scheduler loop: %s", e)
        time.sleep(60)

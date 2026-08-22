"""
config.py
Loader konfigurasi terpusat untuk GARASI ABAH BONTOT Server.

Semua modul lain (database.py, api/routes.py, services/backup_service.py, dll)
mengambil konfigurasi dari sini — bukan dari file JSON langsung — supaya ada
satu sumber kebenaran (single source of truth) dan default value yang aman
kalau ada key yang belum diisi di config.json.

TIDAK ADA perubahan pada isi config.json dibanding versi lama. File ini
hanya membaca & menyediakan akses terstruktur ke konfigurasi tersebut.
"""

import json
import os

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
CONFIG_PATH = os.path.join(BASE_DIR, "config.json")


def _load_config() -> dict:
    try:
        with open(CONFIG_PATH, "r", encoding="utf-8") as f:
            return json.load(f)
    except FileNotFoundError:
        raise RuntimeError(
            f"config.json tidak ditemukan di {CONFIG_PATH}. "
            "Salin config.json ke folder ini sebelum menjalankan server."
        )
    except json.JSONDecodeError as e:
        raise RuntimeError(f"config.json tidak valid (format JSON rusak): {e}")


CONFIG = _load_config()

# ---- Akses terstruktur (dengan default aman) ----------------------------
SERVER_ID = CONFIG.get("server_id", "GAB-001")
SERVER_NAME = CONFIG.get("server_name", "GARASI ABAH BONTOT")
HOST = CONFIG.get("host", "0.0.0.0")
PORT = int(CONFIG.get("port", 8000))

# V5.1: db_path relatif diresolve ke dalam folder garasi_server sendiri
# (storage privat Termux, tidak butuh izin Android apapun). db_path absolut
# tetap didukung apa adanya untuk kompatibilitas siapa saja yang masih mau
# custom path.
_raw_db_path = CONFIG.get("db_path", "data/garasi_abah_bontot.db")
DB_PATH = _raw_db_path if os.path.isabs(_raw_db_path) else os.path.join(BASE_DIR, _raw_db_path)
BACKUP_DIR = CONFIG.get("backup_dir", os.path.join(BASE_DIR, "data", "backup"))
AUTO_BACKUP_TIME = CONFIG.get("auto_backup_time", "23:00")
BACKUP_RETENTION = int(CONFIG.get("backup_retention", 7))
LOG_DIR = CONFIG.get("log_dir", os.path.join(BASE_DIR, "logs"))
API_TOKEN = CONFIG.get("api_token", "")

# Direktori log selalu diresolve relatif terhadap BASE_DIR kalau path relatif
if not os.path.isabs(LOG_DIR):
    LOG_DIR = os.path.join(BASE_DIR, os.path.basename(LOG_DIR.rstrip("/")))


def reload_config():
    """Muat ulang config.json tanpa restart server (dipanggil manual bila perlu)."""
    global CONFIG
    CONFIG = _load_config()
    return CONFIG

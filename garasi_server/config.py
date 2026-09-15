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

# V5.3 — VPS PRODUCTION: "environment" menentukan perilaku non-fungsional
# (verbosity log, dsb) — TIDAK mempengaruhi endpoint/format API sama
# sekali. Default "development" supaya deploy Termux lama tanpa field ini
# tetap jalan apa adanya.
ENVIRONMENT = CONFIG.get("environment", "development")

# V5.1: db_path relatif diresolve ke dalam folder garasi_server sendiri
# (dulu: storage privat Termux; sekarang juga berlaku sama untuk VPS Linux
# biasa -- /opt/garasi-abah-bontot/garasi_server/data/...). db_path absolut
# tetap didukung apa adanya untuk kompatibilitas siapa saja yang masih mau
# custom path.
_raw_db_path = CONFIG.get("db_path", "data/garasi_abah_bontot.db")
DB_PATH = _raw_db_path if os.path.isabs(_raw_db_path) else os.path.join(BASE_DIR, _raw_db_path)

# V5.3: backup_dir default sekarang relatif ke BASE_DIR juga (dulu default
# Android /storage/emulated/0/... kalau field ini kosong di config.json).
# Kalau config.json lama (Termux) masih eksplisit isi path Android, itu
# tetap dipakai apa adanya (os.path lib Python tidak peduli path itu
# "valid" secara OS sampai benar-benar dipakai) -- tidak ada yang rusak
# untuk deployment Termux existing.
_raw_backup_dir = CONFIG.get("backup_dir", "data/backup")
BACKUP_DIR = _raw_backup_dir if os.path.isabs(_raw_backup_dir) else os.path.join(BASE_DIR, _raw_backup_dir)

AUTO_BACKUP_TIME = CONFIG.get("auto_backup_time", "23:00")
BACKUP_RETENTION = int(CONFIG.get("backup_retention", 7))
LOG_DIR = CONFIG.get("log_dir", os.path.join(BASE_DIR, "logs"))
API_TOKEN = CONFIG.get("api_token", "")

# V5.3 — rate limit sederhana (permintaan/menit per IP) untuk endpoint yang
# diproteksi token. Default longgar (600/menit = 10/detik) supaya tidak
# mengganggu pemakaian normal (auto-sync tiap 30 detik dari beberapa
# device) -- hanya menahan penyalahgunaan/brute-force token yang jelas.
RATE_LIMIT_PER_MINUTE = int(CONFIG.get("rate_limit_per_minute", 600))

# Direktori log selalu diresolve relatif terhadap BASE_DIR kalau path relatif
if not os.path.isabs(LOG_DIR):
    LOG_DIR = os.path.join(BASE_DIR, os.path.basename(LOG_DIR.rstrip("/")))


def reload_config():
    """Muat ulang config.json tanpa restart server (dipanggil manual bila perlu)."""
    global CONFIG
    CONFIG = _load_config()
    return CONFIG

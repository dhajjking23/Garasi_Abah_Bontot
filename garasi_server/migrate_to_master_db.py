"""
migrate_to_master_db.py
GARASI ABAH BONTOT — MIGRASI SATU KALI ke arsitektur Server Master
(dipakai sejak V5.1, tetap dipakai apa adanya untuk deploy VPS V5.3).

Server punya database SENDIRI (config.DB_PATH, default: garasi_server/data/
garasi_abah_bontot.db, relatif ke folder server -- baik itu storage privat
Termux MAUPUN /opt/garasi-abah-bontot/garasi_server/data/ di VPS Ubuntu).

Script ini HANYA dipakai SEKALI (per server baru): menyalin data yang
sudah ada (file .db dari HP admin) menjadi database awal server, supaya
data yang sudah diinput/direstore TIDAK HILANG.

Cara pakai:
    # Di Termux (HP):
    python migrate_to_master_db.py /storage/emulated/0/GarasiAbahBontot/garasi_abah_bontot.db

    # Di VPS Ubuntu (setelah file .db di-scp dari HP ke VPS):
    ./venv/bin/python migrate_to_master_db.py /path/ke/file/hasil_scp.db

Kalau argumen path tidak diisi, script akan coba tebak dari lokasi umum
yang pernah dipakai project ini di Termux (tidak relevan di VPS, aman
diabaikan -- selalu isi argumen path eksplisit di VPS).
"""

import os
import shutil
import sqlite3
import sys
from typing import Optional

from config import DB_PATH, BASE_DIR

CANDIDATE_LEGACY_PATHS = [
    "/storage/emulated/0/GarasiAbahBontot/garasi_abah_bontot.db",
    "/storage/emulated/0/Android/data/com.garasiabahbontot.garasi_abah_bontot/files/garasi_abah_bontot.db",
]


def _find_legacy_path(arg: Optional[str]) -> str:
    if arg:
        return arg
    for p in CANDIDATE_LEGACY_PATHS:
        if os.path.isfile(p):
            return p
    print("[GAGAL] Tidak menemukan file db lama otomatis. Jalankan dengan path eksplisit:")
    print("        python migrate_to_master_db.py /path/ke/garasi_abah_bontot.db")
    sys.exit(1)


def main():
    arg = sys.argv[1] if len(sys.argv) > 1 else None
    legacy_path = _find_legacy_path(arg)

    if not os.path.isfile(legacy_path):
        print(f"[GAGAL] File tidak ditemukan: {legacy_path}")
        sys.exit(1)

    if os.path.isfile(DB_PATH):
        # Kalau file yang sudah ada ternyata cuma stub kosong (auto-terbuat
        # oleh sqlite3.connect() waktu /status atau /health kepanggil
        # sebelum migrasi ini sempat jalan -- lihat catatan di
        # database.py get_connection()), aman ditimpa: tidak ada data asli
        # yang bisa hilang. Hanya tolak kalau file itu SUDAH punya skema
        # sync_version/sync_log (berarti sudah pernah jadi DB master yang
        # valid, mungkin sudah ada data baru masuk lewat push).
        try:
            conn = sqlite3.connect(DB_PATH)
            existing_tables = {r[0] for r in conn.execute(
                "SELECT name FROM sqlite_master WHERE type='table'"
            ).fetchall()}
            conn.close()
        except Exception:
            existing_tables = set()

        if {"sync_version", "sync_log"}.issubset(existing_tables):
            print(f"[STOP] DB master server SUDAH ADA & punya skema valid di {DB_PATH}.")
            print("       Migrasi ini hanya untuk sekali bootstrap awal, supaya data yang")
            print("       sudah ada tidak tertimpa tanpa sengaja. Hapus/pindahkan file itu")
            print("       manual dulu kalau memang ingin migrasi ulang dari nol.")
            sys.exit(1)
        else:
            print(f"[i] Ditemukan file kosong/stub (bukan DB master valid) di {DB_PATH} --")
            print("    kemungkinan ter-buat otomatis oleh percobaan koneksi sebelum migrasi")
            print("    ini sempat jalan. File ini AMAN ditimpa, tidak ada data di dalamnya.")
            os.remove(DB_PATH)

    # Validasi ringan: pastikan file lama benar db SQLite yang valid & ada
    # skema inti sebelum disalin.
    try:
        conn = sqlite3.connect(legacy_path)
        tables = {r[0] for r in conn.execute(
            "SELECT name FROM sqlite_master WHERE type='table'"
        ).fetchall()}
        conn.close()
    except Exception as e:
        print(f"[GAGAL] File di {legacy_path} bukan database SQLite yang valid: {e}")
        sys.exit(1)

    if "sync_version" not in tables or "sync_log" not in tables:
        print("[GAGAL] File ditemukan tapi tabel sync_version/sync_log tidak ada.")
        print("        Pastikan ini file db APK GARASI ABAH BONTOT versi V4+ yang benar.")
        sys.exit(1)

    os.makedirs(os.path.dirname(DB_PATH), exist_ok=True)
    shutil.copy2(legacy_path, DB_PATH)

    print(f"[OK] DB master server dibuat dari data admin di: {legacy_path}")
    print(f"[OK] Lokasi baru (dipakai server mulai sekarang): {DB_PATH}")
    print(f"[OK] {len(tables)} tabel tersalin, termasuk sync_version & sync_log.")
    print("")
    print("Langkah selanjutnya:")
    print("  1. Restart server: python stop_server.py && python start_server.py")
    print("  2. Cek: curl -H \"X-API-Token: <token>\" http://127.0.0.1:8000/status")
    print("  3. Update APK admin & partner ke build V5.1 (fitur push/pull baru).")


if __name__ == "__main__":
    main()

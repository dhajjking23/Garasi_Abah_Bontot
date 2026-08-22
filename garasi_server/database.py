"""
database.py
Konektor SQLite ke MASTER DB milik SERVER SENDIRI (garasi_abah_bontot.db,
lihat config.DB_PATH -- V5.1: sekarang di storage privat Termux, bukan lagi
file APK Flutter yang dibaca langsung).

V5.1 — SERVER MASTER SYNC ARCHITECTURE:
Server BUKAN lagi read-only mirror dari file Flutter. Server adalah sumber
data utama:
  - Admin (OWNER_ADMIN) PUSH perubahan lewat POST /push -> apply_push() di
    bawah menulis ke DB ini.
  - Partner (VIEWER) tetap PULL lewat POST /sync + GET /table/{name} seperti
    sebelumnya (tidak berubah kontraknya) -- lihat services/sync_engine.py.

Pengganti langsung (drop-in) dari database_connector.py lama. Nama fungsi
lama dipertahankan 100% (get_connection, is_connected, diagnose, fetch_all,
fetch_table_list, count_connected_devices) supaya sync_engine.py & routes.py
tidak perlu berubah untuk bagian PULL. Fungsi BARU untuk PUSH ditambah di
bagian bawah file.
"""

import json
import os
import sqlite3
from contextlib import contextmanager
from datetime import datetime

from config import DB_PATH

# Tabel yang WAJIB ada supaya sinkronisasi (services/sync_engine.py) bisa
# jalan. Kalau file db_path ada tapi tabel ini tidak ada, itu tandanya
# server membaca file SQLite yang SALAH/KOSONG (bukan DB asli aplikasi
# Flutter) — biasanya karena db_path di config.json tidak cocok dengan
# lokasi file DB yang sebenarnya dipakai APK di HP ini.
REQUIRED_SYNC_TABLES = ("sync_version", "sync_log")

# WHITELIST tabel bisnis yang boleh menerima PUSH dari admin. HARUS PERSIS
# SAMA dengan kSyncedTables di lib/services/sync_service.dart (Flutter) --
# kalau daftar berbeda, tabel yang hilang dari sini akan ditolak apply_push
# walau admin mengirimnya. Whitelist ini juga proteksi utama terhadap SQL
# injection lewat nama tabel (nama tabel dari JSON body TIDAK PERNAH
# dipakai langsung ke query tanpa dicek ada di set ini dulu).
ALLOWED_PUSH_TABLES = {
    "users",
    "motor",
    "motor_cost",
    "penjualan",
    "pemasukan",
    "pengeluaran",
    "kasbon",
    "cash_flow",
    "saldo",
    "dana_talang",
    "gajihan",
    "biaya_transfer_manual",
    "periode",
    "audit_log",
}


@contextmanager
def get_connection():
    # PENTING: jangan connect ke path yang folder induknya belum ada / file
    # belum pernah dibuat TANPA sadar -- sqlite3.connect() otomatis
    # membuat file kosong tanpa skema apa pun begitu path bisa dijangkau.
    # Ini pernah membuat file stub kosong ter-buat gara-gara /status atau
    # /health dipanggil SEBELUM migrate_to_master_db.py sempat jalan,
    # yang lalu membuat migrate_to_master_db.py menolak jalan (mengira DB
    # "sudah ada") padahal isinya kosong. Guard ini menutup celah itu:
    # kalau file belum ada, biarkan error eksplisit (ditangkap diagnose())
    # alih-alih diam-diam membuat file kosong baru.
    if not os.path.isfile(DB_PATH):
        raise sqlite3.OperationalError(f"unable to open database file: {DB_PATH} belum ada")
    conn = sqlite3.connect(DB_PATH, timeout=5)
    conn.row_factory = sqlite3.Row
    try:
        yield conn
    finally:
        conn.close()


def is_connected() -> bool:
    try:
        with get_connection() as conn:
            conn.execute("SELECT 1")
        return True
    except Exception:
        return False


def diagnose() -> dict:
    """Cek kesehatan db_path secara detail untuk endpoint /status, /health,
    dan sebagai pre-check sebelum /sync — supaya kalau ada masalah, pesannya
    jelas & actionable (bukan cuma '500 internal server error').
    """
    result = {
        "db_path": DB_PATH,
        "file_exists": False,
        "opened_ok": False,
        "missing_tables": list(REQUIRED_SYNC_TABLES),
        "problem": None,
    }

    if not DB_PATH:
        result["problem"] = (
            "db_path belum diisi di config.json."
        )
        return result

    result["file_exists"] = os.path.isfile(DB_PATH)
    if not result["file_exists"]:
        result["problem"] = (
            f"File database tidak ditemukan di '{DB_PATH}'. Pastikan: (1) aplikasi "
            "GARASI ABAH BONTOT sudah pernah dibuka minimal 1x di HP ini, dan "
            "(2) db_path di config.json sama persis dengan lokasi file DB yang "
            "dipakai APK (folder Android/data/<package>/files/)."
        )
        return result

    try:
        with get_connection() as conn:
            result["opened_ok"] = True
            cur = conn.execute(
                "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'"
            )
            existing = {r["name"] for r in cur.fetchall()}
            result["missing_tables"] = [t for t in REQUIRED_SYNC_TABLES if t not in existing]
    except Exception as e:
        result["problem"] = f"File ditemukan tapi gagal dibuka sebagai database SQLite: {e}"
        return result

    if result["missing_tables"]:
        result["problem"] = (
            "File database ditemukan & bisa dibuka, tapi tabel "
            f"{', '.join(result['missing_tables'])} tidak ada. Ini menandakan file yang "
            "dibaca server BUKAN database asli aplikasi (kemungkinan file kosong yang "
            "otomatis terbuat karena db_path salah), atau APK di HP ini versinya lebih "
            "lama dari V4 (belum punya tabel sync_version/sync_log)."
        )

    return result


def is_sync_ready() -> bool:
    return diagnose()["problem"] is None


def fetch_all(table_name: str, since_version: int = 0):
    """Ambil seluruh baris tabel (dipakai sync_engine untuk delta sync)."""
    with get_connection() as conn:
        cur = conn.execute(f"SELECT * FROM {table_name}")
        rows = [dict(r) for r in cur.fetchall()]
    return rows


def fetch_table_list():
    with get_connection() as conn:
        cur = conn.execute(
            "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'"
        )
        return [r["name"] for r in cur.fetchall()]


def count_connected_devices() -> int:
    try:
        with get_connection() as conn:
            cur = conn.execute("SELECT COUNT(*) c FROM devices WHERE status = 'ACTIVE'")
            return cur.fetchone()["c"]
    except Exception:
        return 0


# ==========================================================================
# V5.1 — PUSH (ADMIN -> SERVER)
# ==========================================================================

class PushError(Exception):
    """Error yang aman ditampilkan apa adanya ke client (pesan sudah dalam
    Bahasa Indonesia yang jelas, tidak bocorkan detail internal)."""


def _valid_columns(conn: sqlite3.Connection, table: str) -> set:
    cur = conn.execute(f"PRAGMA table_info({table})")
    return {r["name"] for r in cur.fetchall()}


def apply_push(changes: list, device_name: str) -> dict:
    """Terapkan sekumpulan perubahan (dari outbox lokal admin, berbasis
    sync_log lokal Flutter) ke DB MASTER milik server, dalam SATU transaksi.

    changes: list of {
        "table": str,        # harus ada di ALLOWED_PUSH_TABLES
        "action": "INSERT"|"UPDATE"|"DELETE",
        "record_id": int,
        "data": dict | None, # wajib untuk INSERT/UPDATE, None untuk DELETE
    }

    Kolom pada `data` DISARING dulu lewat PRAGMA table_info(table) sebelum
    dipakai membangun query — proteksi tambahan (di luar whitelist nama
    tabel) supaya key JSON sembarangan tidak bisa menyuntik nama kolom yang
    tidak valid ke SQL.

    Setelah apply, tiap tabel yang kena perubahan otomatis dinaikkan
    sync_version-nya + dicatat ke sync_log MILIK SERVER (bukan punya admin)
    supaya Partner tetap bisa delta-sync seperti biasa lewat /sync -
    /table/{name} yang sudah ada, tanpa perubahan kontrak apapun di sisi
    itu. Juga dicatat ke audit_log untuk jejak siapa mengubah apa.
    """
    if not changes:
        return {"applied": 0, "tables_affected": []}

    tables_affected: set[str] = set()
    applied = 0

    with get_connection() as conn:
        try:
            conn.execute("BEGIN")
            for change in changes:
                table = change.get("table")
                action = (change.get("action") or "").upper()
                record_id = change.get("record_id")
                data = change.get("data")

                if table not in ALLOWED_PUSH_TABLES:
                    raise PushError(f"Tabel '{table}' tidak diizinkan untuk push.")
                if action not in ("INSERT", "UPDATE", "DELETE"):
                    raise PushError(f"Action '{action}' tidak dikenal untuk tabel '{table}'.")
                if record_id is None:
                    raise PushError(f"record_id kosong untuk perubahan tabel '{table}'.")

                if action == "DELETE":
                    conn.execute(f"DELETE FROM {table} WHERE id = ?", (record_id,))
                else:
                    if not isinstance(data, dict) or not data:
                        raise PushError(
                            f"data kosong untuk {action} tabel '{table}' (record_id={record_id})."
                        )
                    valid_cols = _valid_columns(conn, table)
                    row = {k: v for k, v in data.items() if k in valid_cols}
                    row["id"] = record_id
                    cols = list(row.keys())
                    placeholders = ", ".join("?" for _ in cols)
                    updates = ", ".join(f"{c}=excluded.{c}" for c in cols if c != "id")
                    sql = (
                        f"INSERT INTO {table} ({', '.join(cols)}) VALUES ({placeholders}) "
                        f"ON CONFLICT(id) DO UPDATE SET {updates}"
                    )
                    conn.execute(sql, [row[c] for c in cols])

                tables_affected.add(table)
                applied += 1

            now = datetime.now().isoformat()
            for table in tables_affected:
                conn.execute(
                    "INSERT OR IGNORE INTO sync_version (table_name, version, last_update) "
                    "VALUES (?, 0, ?)",
                    (table, now),
                )
                conn.execute(
                    "UPDATE sync_version SET version = version + 1, last_update = ? "
                    "WHERE table_name = ?",
                    (now, table),
                )

            conn.execute(
                "INSERT INTO sync_log (table_name, record_id, action, payload, timestamp) "
                "VALUES (?, ?, ?, ?, ?)",
                ("_push_batch", 0, "PUSH", json.dumps({
                    "device": device_name, "tables": sorted(tables_affected), "count": applied,
                }), now),
            )

            try:
                conn.execute(
                    "INSERT INTO audit_log (tabel, record_id, aksi, keterangan, created_at) "
                    "VALUES (?, ?, ?, ?, ?)",
                    ("_sync", 0, "PUSH_SYNC",
                     f"{applied} perubahan dari {device_name} ({', '.join(sorted(tables_affected))})",
                     now),
                )
            except sqlite3.OperationalError:
                pass  # skema audit_log berbeda/tidak ada -- jangan gagalkan push karena ini

            conn.commit()
        except Exception:
            conn.rollback()
            raise

    return {"applied": applied, "tables_affected": sorted(tables_affected)}

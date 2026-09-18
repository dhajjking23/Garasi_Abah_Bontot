"""
services/sync_engine.py
Delta sync berbasis sync_version & sync_log. Viewer mengirim versi lokal
terakhir per tabel, server hanya mengembalikan perubahan (bukan seluruh DB).

Dipindah persis dari sync_engine.py lama (hanya lokasi & import path yang
berubah, karena database_connector.py sekarang bernama database.py).
"""

from database import get_connection


def get_server_versions():
    with get_connection() as conn:
        cur = conn.execute("SELECT table_name, version, last_update FROM sync_version")
        return {r["table_name"]: {"version": r["version"], "last_update": r["last_update"]} for r in cur.fetchall()}


def get_changes_since(table_name: str, since_version: int):
    """Ambil baris sync_log untuk table_name dengan id > since_version."""
    with get_connection() as conn:
        cur = conn.execute(
            "SELECT * FROM sync_log WHERE table_name = ? AND id > ? ORDER BY id ASC",
            (table_name, since_version),
        )
        return [dict(r) for r in cur.fetchall()]


def build_delta_payload(client_versions: dict):
    """
    client_versions: { "penjualan": 12, "motor": 5, ... }
    Return: { "penjualan": {"changes": [...], "version": 20}, ... }
    """
    result = {}
    server_versions = get_server_versions()
    for table_name, server_info in server_versions.items():
        client_last = client_versions.get(table_name, 0)
        server_version = server_info["version"]
        if server_version > client_last:
            changes = get_changes_since(table_name, client_last)
            result[table_name] = {
                "changes": changes,
                "version": server_version,
            }
    return result

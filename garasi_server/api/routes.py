"""
api/routes.py
Semua endpoint HTTP server GARASI ABAH BONTOT — versi Flask.

PENTING — KONTRAK API TIDAK BERUBAH dibanding server.py/FastAPI lama:
    GET  /ping                 -> publik, {"ok": true}
    GET  /status                -> perlu X-API-Token
    POST /sync                   -> perlu X-API-Token
    GET  /tables                  -> perlu X-API-Token
    GET  /table/{table_name}       -> perlu X-API-Token

Satu-satunya tambahan adalah GET /health (endpoint BARU, opsional untuk
monitoring manual, bukan pengganti /ping — APK tidak perlu tahu soal ini).
"""

import os
from datetime import datetime

from flask import Blueprint, jsonify, request

import database as db
import services.sync_engine as sync_engine
from api.auth import verify_token
from config import CONFIG
from utils.logger import log
from utils.network import get_local_ip, get_server_mode

bp = Blueprint("api", __name__)


@bp.get("/ping")
def ping():
    """Endpoint publik tanpa token, hanya untuk cek server hidup/mati.
    TIDAK DIUBAH — kontrak persis sama dengan server.py lama."""
    return jsonify({"ok": True})


@bp.get("/health")
def health():
    """BARU: health check yang sedikit lebih informatif untuk monitoring
    manual (bukan dipanggil APK). Tidak menggantikan /ping."""
    diag = db.diagnose()
    return jsonify({
        "ok": True,
        "database": "CONNECTED" if db.is_connected() else "DISCONNECTED",
        "sync_ready": diag["problem"] is None,
        "sync_problem": diag["problem"],
        "uptime_pid": os.getpid(),
        "timestamp": datetime.now().isoformat(),
    })


@bp.get("/status")
@verify_token
def status():
    diag = db.diagnose()
    log.info(
        "status check - db_connected=%s sync_ready=%s problem=%s",
        diag["opened_ok"], diag["problem"] is None, diag["problem"],
    )
    return jsonify({
        "server_id": CONFIG.get("server_id", "GAB-001"),
        "server_name": CONFIG.get("server_name", "GARASI ABAH BONTOT"),
        "ip": get_local_ip(),
        "port": CONFIG.get("port", 8000),
        "mode": get_server_mode(),
        "database": "CONNECTED" if diag["opened_ok"] else "DISCONNECTED",
        "sync_ready": diag["problem"] is None,
        "sync_problem": diag["problem"],
        "connected_devices": db.count_connected_devices(),
        "pid": os.getpid(),
        "timestamp": datetime.now().isoformat(),
    })


@bp.post("/sync")
@verify_token
def sync():
    body = request.get_json(silent=True) or {}
    client_versions = body.get("client_versions", {}) or {}
    device_name = body.get("device_name", "Unknown Device")
    log.info("sync request from %s | client_versions=%s", device_name, client_versions)

    # Pre-check eksplisit sebelum query sync_version/sync_log. Tanpa ini,
    # db_path yang salah/kosong/tabel belum ada akan lolos sampai ke query
    # SQL lalu meledak jadi exception generik yang ditangkap
    # utils/error_handler.py sebagai "internal_server_error" tanpa detail
    # yang berguna untuk didiagnosis dari layar APK.
    diag = db.diagnose()
    if diag["problem"]:
        log.error("sync ditolak (pre-check gagal) dari %s: %s", device_name, diag["problem"])
        return jsonify({
            "ok": False,
            "error": "sync_not_ready",
            "detail": diag["problem"],
            "db_path": diag["db_path"],
        }), 503

    try:
        payload = sync_engine.build_delta_payload(client_versions)
    except Exception:
        log.exception("sync gagal saat build_delta_payload untuk device=%s", device_name)
        raise  # tetap ditangani utils/error_handler.py -> 500 + log lengkap

    total_changes = sum(len(v.get("changes", [])) for v in payload.values())
    log.info(
        "sync sukses untuk %s | %d tabel berubah, %d baris perubahan",
        device_name, len(payload), total_changes,
    )
    return jsonify({
        "ok": True,
        "server_time": datetime.now().isoformat(),
        "data": payload,
    })


@bp.post("/push")
@verify_token
def push():
    """V5.1 — ADMIN -> SERVER. Terima batch perubahan (INSERT/UPDATE/DELETE)
    dari outbox lokal OWNER_ADMIN (lihat lib/services/sync_push_service.dart)
    dan terapkan ke DB MASTER milik server. Partner TIDAK memanggil endpoint
    ini -- Partner tetap read-only lewat /sync & /table/{name}.

    Body: {"device_name": str, "changes": [ {table, action, record_id, data}, ... ]}
    """
    body = request.get_json(silent=True) or {}
    device_name = body.get("device_name", "Unknown Admin Device")
    changes = body.get("changes", []) or []

    diag = db.diagnose()
    if diag["problem"]:
        log.error("push ditolak (pre-check gagal) dari %s: %s", device_name, diag["problem"])
        return jsonify({
            "ok": False,
            "error": "push_not_ready",
            "detail": diag["problem"],
            "db_path": diag["db_path"],
        }), 503

    try:
        result = db.apply_push(changes, device_name)
    except db.PushError as e:
        log.warning("push ditolak (data tidak valid) dari %s: %s", device_name, e)
        return jsonify({"ok": False, "error": "invalid_push", "detail": str(e)}), 400
    except Exception:
        log.exception("push gagal untuk device=%s", device_name)
        raise

    log.info(
        "push sukses dari %s | %d perubahan diterapkan, tabel: %s",
        device_name, result["applied"], ", ".join(result["tables_affected"]),
    )
    return jsonify({
        "ok": True,
        "server_time": datetime.now().isoformat(),
        "applied": result["applied"],
        "tables_affected": result["tables_affected"],
    })


@bp.get("/tables")
@verify_token
def tables():
    return jsonify({"tables": db.fetch_table_list()})


@bp.get("/table/<table_name>")
@verify_token
def table_full(table_name):
    """Fallback full fetch (dipakai saat first-sync device baru)."""
    rows = db.fetch_all(table_name)
    return jsonify({"table": table_name, "rows": rows})

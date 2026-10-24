"""
server.py — SHIM KOMPATIBILITAS MUNDUR

Logic asli sudah dipindah ke struktur modular:
    main.py, api/routes.py, api/auth.py, database.py,
    services/sync_engine.py, services/backup_service.py, utils/*

File ini sengaja DIPERTAHANKAN sebagai shim 1-baris untuk kompatibilitas
mundur (kalau ada tooling lama yang mengimpor `server.app`). "app" di sini
persis objek Flask yang sama dengan main.py.

Untuk menjalankan server, pakai salah satu:
    python main.py
    python start_server.py

Untuk pengembangan selanjutnya, edit main.py / api/routes.py — BUKAN file ini.
"""

from main import app  # noqa: F401

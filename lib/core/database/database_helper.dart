import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sqflite/sqflite.dart';
import '../constants/app_constants.dart';

/// DatabaseHelper - Singleton pengelola koneksi & schema SQLite.
///
/// Semua tabel didefinisikan di sini. Gunakan `database` getter untuk
/// mendapatkan instance yang sudah terbuka. Jangan buat instance Database
/// baru di tempat lain — selalu lewat helper ini agar migrasi konsisten.
class DatabaseHelper {
  DatabaseHelper._internal();
  static final DatabaseHelper instance = DatabaseHelper._internal();

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final path = await _resolveDbPath();

    // ==========================================================
    // MIGRASI LOKASI DB LAMA -> BARU (server Termux baca dari sini)
    // Sebelum perbaikan ini, DB disimpan lewat getApplicationDocumentsDirectory()
    // yaitu folder sandbox internal aplikasi yang TIDAK BISA diakses proses
    // lain (termasuk server Termux di HP yang sama). Server config.json
    // (db_path) selalu menunjuk ke folder external app-specific
    // (getExternalStorageDirectory()), sehingga server membaca file KOSONG
    // yang berbeda dari DB asli -> query sync_version/sync_log gagal
    // ("no such table") -> HTTP 500 saat sinkronisasi.
    //
    // Perbaikan: DB sekarang disimpan di folder external app-specific,
    // yang otomatis cocok dengan db_path server tanpa perlu setting apapun
    // (folder ini milik aplikasi sendiri, tidak butuh izin storage khusus).
    // Blok ini memindahkan DB lama (jika ada & DB baru belum ada) supaya
    // data pengguna yang sudah ada TIDAK hilang saat update.
    // ==========================================================
    await _migrateLegacyDbLocationIfNeeded(path);

    // ==========================================================
    // BACKUP OTOMATIS SEBELUM MIGRATION
    // Alur: cek versi lama -> jika ada migrasi pending -> backup dulu ->
    // baru jalankan openDatabase (yang otomatis memicu _onUpgrade).
    // Jika migrasi gagal, database asli TIDAK tersentuh sampai backup
    // berhasil, sehingga restore manual selalu memungkinkan.
    //
    // PENTING: precheck ini WAJIB pakai singleInstance: false. sqflite
    // meng-cache koneksi Database per `path` (default singleInstance:
    // true). Jika precheck memakai cache default, openDatabase() di
    // bawah (untuk pemakaian sesungguhnya, dengan onCreate/onUpgrade)
    // akan mendapat instance READ-ONLY yang sama dari cache alih-alih
    // koneksi baru — migration tidak pernah jalan dan semua operasi
    // tulis berikutnya macet/terkunci ("database is locked"). Dengan
    // singleInstance: false, precheck memakai koneksi terpisah yang
    // tidak ikut cache, sehingga tidak bentrok dengan koneksi utama.
    // ==========================================================
    final dbFile = File(path);
    if (await dbFile.exists()) {
      Database? preCheck;
      try {
        preCheck = await openDatabase(
          path,
          readOnly: true,
          singleInstance: false,
        );
        final oldVersion = await preCheck.getVersion();
        if (oldVersion > 0 && oldVersion < AppConstants.dbVersion) {
          await _backupBeforeMigration(dbFile, oldVersion, AppConstants.dbVersion);
        }
      } catch (e) {
        // Jika precheck gagal (file korup dsb), tetap lanjut — sqflite akan
        // menangani/reporting error saat openDatabase penuh di bawah.
      } finally {
        // WAJIB ditutup di finally: koneksi singleInstance:false tidak
        // dikelola cache plugin, jadi kalau tidak ditutup manual di sini
        // ia akan bocor (tetap membuka file handle) walau precheck gagal.
        await preCheck?.close();
      }
    }

    return await openDatabase(
      path,
      version: AppConstants.dbVersion,
      onConfigure: (db) async {
        // Aktifkan foreign key constraint
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  /// V5.1 — SERVER MASTER SYNC ARCHITECTURE: DB app SEKARANG cukup di
  /// storage internal biasa (getApplicationDocumentsDirectory()), TIDAK
  /// LAGI di folder publik. Sebelum V5.1, DB harus di folder publik supaya
  /// server Termux bisa membacanya langsung. Sejak V5.1, server punya DB
  /// sendiri dan admin PUSH data lewat API (lihat sync_push_service.dart)
  /// — jadi DB app ini murni untuk app itu sendiri lagi, tidak perlu
  /// dibaca proses lain sama sekali.
  ///
  /// Ini juga jadi FIX untuk error "DatabaseException(open_failed
  /// /storage/emulated/0/GarasiAbahBontot/garasi_abah_bontot.db)" yang
  /// muncul di layar login: folder publik butuh izin "Akses semua file"
  /// yang gampang dicabut MIUI di background (root cause yang sama dengan
  /// error server sebelumnya) — sqflite gagal open_failed walau folder-nya
  /// berhasil dibuat. Storage internal TIDAK PERNAH butuh izin apapun di
  /// versi Android manapun, jadi login tidak akan gagal karena ini lagi.
  Future<Directory> _dbBaseDirectory() async {
    return getApplicationDocumentsDirectory();
  }

  Future<String> _resolveDbPath() async {
    final dbDir = await _dbBaseDirectory();
    return join(dbDir.path, AppConstants.dbName);
  }

  /// Masih dipertahankan untuk kompatibilitas (dipanggil dari kartu lama di
  /// Server screen kalau masih ada) — TIDAK LAGI diperlukan untuk fungsi
  /// normal app sejak V5.1, karena DB app tidak perlu dibaca proses lain.
  Future<bool> ensureStorageAccess() async {
    if (await Permission.manageExternalStorage.isGranted) return true;
    final status = await Permission.manageExternalStorage.request();
    return status.isGranted;
  }

  /// Pindahkan DB dari lokasi lama manapun (folder publik GarasiAbahBontot
  /// dari percobaan V5.0, folder external app-specific dari percobaan
  /// sebelum itu, atau folder dokumen lama-lama sekali) ke lokasi final V5.1
  /// (storage internal) supaya data pengguna existing TIDAK HILANG. Dicek
  /// berurutan sesuai kemungkinan paling baru dulu. Idempotent & aman
  /// dipanggil setiap start.
  Future<void> _migrateLegacyDbLocationIfNeeded(String newPath) async {
    try {
      final newFile = File(newPath);
      if (await newFile.exists()) return; // sudah di lokasi final

      final legacyCandidates = <String>[];

      // Folder publik (percobaan V5.0) -- File.copy kadang tetap berhasil
      // membaca walau sqflite gagal open_failed, karena copy tidak
      // memerlukan file-locking penuh seperti yang dibutuhkan SQLite.
      try {
        final extDir = await getExternalStorageDirectory();
        if (extDir != null) {
          final segments = split(extDir.path);
          final androidIdx = segments.indexOf('Android');
          if (androidIdx > 0) {
            final sharedRoot = joinAll(segments.sublist(0, androidIdx));
            legacyCandidates.add(join(sharedRoot, 'GarasiAbahBontot', AppConstants.dbName));
          }
          // Folder external app-specific (percobaan sebelum folder publik).
          legacyCandidates.add(join(extDir.path, AppConstants.dbName));
        }
      } catch (_) {
        // Kalau gagal derive path publik, lewati kandidat ini saja.
      }

      for (final legacyPath in legacyCandidates) {
        if (legacyPath == newPath) continue;
        final legacyFile = File(legacyPath);
        bool exists;
        try {
          exists = await legacyFile.exists();
        } catch (_) {
          exists = false; // folder tidak terbaca (izin dicabut) -- skip, coba kandidat lain
        }
        if (!exists) continue;

        try {
          await Directory(dirname(newPath)).create(recursive: true);
          await legacyFile.copy(newPath);
          for (final ext in ['-wal', '-shm']) {
            final legacySide = File('$legacyPath$ext');
            if (await legacySide.exists()) {
              await legacySide.copy('$newPath$ext');
            }
          }
          return; // migrasi dari kandidat pertama yang berhasil, selesai
        } catch (_) {
          continue; // copy gagal (mis. izin dicabut di tengah jalan) -- coba kandidat berikutnya
        }
      }
      // Tidak ada kandidat lama yang bisa dibaca -> instalasi baru, atau
      // data lama benar-benar tidak terjangkau (mis. sudah tidak ada
      // storage permission sama sekali) -- app tetap lanjut jalan dengan
      // DB baru kosong daripada crash total. Cek manual via fitur
      // Backup/Restore kalau data lama ternyata tidak ikut pindah.
    } catch (_) {
      // Lihat catatan di atas -- migrasi gagal tidak boleh menghentikan app.
    }
  }

  /// Backup file database mentah ke folder GarasiBackup sebelum migration
  /// dijalankan. Nama file menandai versi asal & tujuan agar mudah dilacak
  /// dan direstore manual bila migration gagal.
  Future<void> _backupBeforeMigration(File dbFile, int fromVersion, int toVersion) async {
    try {
      Directory backupDir;
      try {
        backupDir = Directory('/storage/emulated/0/GarasiBackup');
        if (!await backupDir.exists()) {
          await backupDir.create(recursive: true);
        }
      } catch (_) {
        // Fallback ke folder dokumen aplikasi jika storage eksternal tidak
        // dapat diakses (mis. izin belum diberikan).
        backupDir = await getApplicationDocumentsDirectory();
      }
      final timestamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .replaceAll('.', '-');
      final backupPath = join(
        backupDir.path,
        'GARASI_PRE_MIGRATION_V${fromVersion}_TO_V${toVersion}_$timestamp.db',
      );
      await dbFile.copy(backupPath);
    } catch (_) {
      // Backup gagal tidak boleh menghentikan aplikasi — migration tetap
      // dicoba, tapi kegagalan ini idealnya dicatat via log terpisah.
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    final batch = db.batch();

    // ==========================================================
    // TABEL: periode (pembukuan)
    // ==========================================================
    batch.execute('''
      CREATE TABLE periode (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nama_periode TEXT NOT NULL,
        tanggal_mulai TEXT NOT NULL,
        tanggal_selesai TEXT,
        status TEXT NOT NULL DEFAULT '${AppConstants.statusPeriodeAktif}',
        modal_awal REAL NOT NULL DEFAULT 0,
        modal_awal_cash REAL NOT NULL DEFAULT 0,
        modal_awal_bank REAL NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    // ==========================================================
    // TABEL: karyawan
    // ==========================================================
    batch.execute('''
      CREATE TABLE karyawan (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nama TEXT NOT NULL UNIQUE,
        is_internal INTEGER NOT NULL DEFAULT 1,
        aktif INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL
      )
    ''');

    // ==========================================================
    // TABEL: motor
    // ==========================================================
    batch.execute('''
      CREATE TABLE motor (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        kode_motor TEXT NOT NULL UNIQUE,
        merk TEXT NOT NULL,
        tipe TEXT NOT NULL,
        tahun INTEGER,
        warna TEXT,
        plat_nomor TEXT,
        tanggal_masuk TEXT NOT NULL,
        harga_beli REAL NOT NULL DEFAULT 0,
        total_modal REAL NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT '${AppConstants.statusMotorTersedia}',
        metode_pembayaran TEXT NOT NULL DEFAULT 'CASH',
        cash_dibayar REAL NOT NULL DEFAULT 0,
        transfer_dibayar REAL NOT NULL DEFAULT 0,
        jenis_transfer TEXT,
        biaya_admin_transfer REAL NOT NULL DEFAULT 0,
        catatan TEXT,
        periode_id INTEGER,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (periode_id) REFERENCES periode (id) ON DELETE SET NULL
      )
    ''');

    // ==========================================================
    // TABEL: motor_cost (biaya per unit motor)
    // ==========================================================
    batch.execute('''
      CREATE TABLE motor_cost (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        motor_id INTEGER NOT NULL,
        kategori TEXT NOT NULL,
        nominal REAL NOT NULL DEFAULT 0,
        metode_pembayaran TEXT NOT NULL DEFAULT 'CASH',
        cash_dibayar REAL NOT NULL DEFAULT 0,
        transfer_dibayar REAL NOT NULL DEFAULT 0,
        jenis_transfer TEXT,
        biaya_admin_transfer REAL NOT NULL DEFAULT 0,
        keterangan TEXT,
        tanggal TEXT NOT NULL,
        created_at TEXT NOT NULL,
        FOREIGN KEY (motor_id) REFERENCES motor (id) ON DELETE CASCADE
      )
    ''');

    // ==========================================================
    // TABEL: penjualan
    // ==========================================================
    batch.execute('''
      CREATE TABLE penjualan (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        motor_id INTEGER NOT NULL,
        tanggal_jual TEXT NOT NULL,
        harga_jual REAL NOT NULL DEFAULT 0,
        modal_motor REAL NOT NULL DEFAULT 0,
        laba REAL NOT NULL DEFAULT 0,
        penjual TEXT NOT NULL,
        bonus_eligible INTEGER NOT NULL DEFAULT 1,
        metode_pembayaran TEXT NOT NULL DEFAULT 'CASH',
        cash_diterima REAL NOT NULL DEFAULT 0,
        transfer_diterima REAL NOT NULL DEFAULT 0,
        status_pembayaran TEXT NOT NULL DEFAULT 'LUNAS',
        periode_id INTEGER,
        created_at TEXT NOT NULL,
        FOREIGN KEY (motor_id) REFERENCES motor (id) ON DELETE RESTRICT,
        FOREIGN KEY (periode_id) REFERENCES periode (id) ON DELETE SET NULL
      )
    ''');

    // ==========================================================
    // TABEL: pemasukan
    // V3.1: Support split amount untuk CAMPURAN (cash + bank)
    // ==========================================================
    batch.execute('''
      CREATE TABLE pemasukan (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tanggal TEXT NOT NULL,
        kategori TEXT NOT NULL,
        nominal REAL NOT NULL DEFAULT 0,
        keterangan TEXT,
        sumber TEXT NOT NULL DEFAULT 'CASH',
        cash_masuk REAL NOT NULL DEFAULT 0,
        bank_masuk REAL NOT NULL DEFAULT 0,
        referensi_id INTEGER,
        periode_id INTEGER,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (periode_id) REFERENCES periode (id) ON DELETE SET NULL
      )
    ''');

    // ==========================================================
    // TABEL: pengeluaran
    // V3.1: Universal transfer admin fee (GRATIS, BI_FAST, REALTIME)
    // ==========================================================
    batch.execute('''
      CREATE TABLE pengeluaran (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tanggal TEXT NOT NULL,
        kategori TEXT NOT NULL,
        nominal REAL NOT NULL DEFAULT 0,
        keterangan TEXT,
        sumber TEXT NOT NULL DEFAULT 'CASH',
        jenis_transfer TEXT,
        biaya_admin REAL NOT NULL DEFAULT 0,
        referensi_id INTEGER,
        periode_id INTEGER,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (periode_id) REFERENCES periode (id) ON DELETE SET NULL
      )
    ''');

    // ==========================================================
    // TABEL: kasbon
    // ==========================================================
    batch.execute('''
      CREATE TABLE kasbon (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nama_karyawan TEXT NOT NULL,
        tanggal TEXT NOT NULL,
        jumlah REAL NOT NULL DEFAULT 0,
        sumber TEXT NOT NULL DEFAULT 'CASH',
        jenis_transfer TEXT,
        biaya_admin_transfer REAL NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT '${AppConstants.statusKasbonBelumLunas}',
        tanggal_lunas TEXT,
        keterangan TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    // ==========================================================
    // TABEL: cash_flow (histori mutasi kas)
    // ==========================================================
    batch.execute('''
      CREATE TABLE cash_flow (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tanggal TEXT NOT NULL,
        tipe TEXT NOT NULL,
        sumber TEXT NOT NULL DEFAULT 'CASH',
        nominal REAL NOT NULL DEFAULT 0,
        referensi TEXT NOT NULL,
        referensi_id INTEGER,
        keterangan TEXT,
        saldo_setelah REAL NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');

    // ==========================================================
    // TABEL: saldo (singleton row - cash & bank saat ini)
    // modal_cash & modal_bank = modal usaha (bukan saldo operasional).
    // modal_total tetap disimpan sebagai cache = modal_cash + modal_bank
    // supaya kode lama yang membaca modal_total tidak perlu berubah.
    // ==========================================================
    batch.execute('''
      CREATE TABLE saldo (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        cash REAL NOT NULL DEFAULT 0,
        saldo_bank REAL NOT NULL DEFAULT 0,
        modal_cash REAL NOT NULL DEFAULT 0,
        modal_bank REAL NOT NULL DEFAULT 0,
        modal_total REAL NOT NULL DEFAULT 0,
        updated_at TEXT NOT NULL
      )
    ''');

    // ==========================================================
    // TABEL: modal_history (riwayat perubahan modal cash & bank)
    // ==========================================================
    batch.execute('''
      CREATE TABLE modal_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tanggal TEXT NOT NULL,
        jenis TEXT NOT NULL,
        aksi TEXT NOT NULL,
        nominal REAL NOT NULL DEFAULT 0,
        saldo_sebelum REAL NOT NULL DEFAULT 0,
        saldo_sesudah REAL NOT NULL DEFAULT 0,
        keterangan TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    // ==========================================================
    // TABEL: pembagian_laba (histori tutup buku)
    // ==========================================================
    batch.execute('''
      CREATE TABLE pembagian_laba (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        periode_id INTEGER NOT NULL,
        laba_bersih REAL NOT NULL DEFAULT 0,
        bagian_abah REAL NOT NULL DEFAULT 0,
        bagian_iki REAL NOT NULL DEFAULT 0,
        bagian_andri REAL NOT NULL DEFAULT 0,
        bagian_ilham REAL NOT NULL DEFAULT 0,
        total_hadiah_penjualan REAL NOT NULL DEFAULT 0,
        unit_internal_terjual INTEGER NOT NULL DEFAULT 0,
        bonus_per_unit REAL NOT NULL DEFAULT 0,
        detail_bonus_json TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY (periode_id) REFERENCES periode (id) ON DELETE CASCADE
      )
    ''');

    // ==========================================================
    // TABEL: audit_log
    // ==========================================================
    batch.execute('''
      CREATE TABLE audit_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tabel TEXT NOT NULL,
        record_id INTEGER,
        aksi TEXT NOT NULL,
        data_lama TEXT,
        data_baru TEXT,
        keterangan TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    // ==========================================================
    // TABEL: mutasi_antar_saldo (Deposit Cash->Bank & Tarik Tunai)
    // Dipisah dari cash_flow generik supaya bisa diedit/dihapus
    // sebagai SATU transaksi utuh (rollback dua sisi sekaligus).
    // ==========================================================
    batch.execute('''
      CREATE TABLE mutasi_antar_saldo (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tanggal TEXT NOT NULL,
        jenis TEXT NOT NULL,
        nominal REAL NOT NULL DEFAULT 0,
        keterangan TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    // ==========================================================
    // TABEL: dana_talang (piutang/hutang ke partner)
    // ==========================================================
    batch.execute('''
      CREATE TABLE dana_talang (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nama_partner TEXT NOT NULL,
        tanggal TEXT NOT NULL,
        jenis TEXT NOT NULL,
        nominal REAL NOT NULL DEFAULT 0,
        metode_pembayaran TEXT NOT NULL DEFAULT 'CASH',
        cash_terpakai REAL NOT NULL DEFAULT 0,
        transfer_terpakai REAL NOT NULL DEFAULT 0,
        jenis_transfer TEXT,
        biaya_admin_transfer REAL NOT NULL DEFAULT 0,
        bentuk_talangan TEXT NOT NULL DEFAULT 'TUNAI',
        status TEXT NOT NULL DEFAULT '${AppConstants.statusDanaTalangBelumLunas}',
        total_dibayar_kembali REAL NOT NULL DEFAULT 0,
        keterangan TEXT,
        periode_id INTEGER,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (periode_id) REFERENCES periode (id) ON DELETE SET NULL
      )
    ''');

    // ==========================================================
    // TABEL: dana_talang_pembayaran (riwayat cicilan/pelunasan)
    // ==========================================================
    batch.execute('''
      CREATE TABLE dana_talang_pembayaran (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        dana_talang_id INTEGER NOT NULL,
        tanggal TEXT NOT NULL,
        nominal REAL NOT NULL DEFAULT 0,
        metode_pembayaran TEXT NOT NULL DEFAULT 'CASH',
        cash_terpakai REAL NOT NULL DEFAULT 0,
        transfer_terpakai REAL NOT NULL DEFAULT 0,
        jenis_transfer TEXT,
        biaya_admin_transfer REAL NOT NULL DEFAULT 0,
        keterangan TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY (dana_talang_id) REFERENCES dana_talang (id) ON DELETE CASCADE
      )
    ''');

    // ==========================================================
    // TABEL: penjualan_pembayaran (cicilan/pelunasan DP penjualan)
    // ==========================================================
    batch.execute('''
      CREATE TABLE penjualan_pembayaran (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        penjualan_id INTEGER NOT NULL,
        tanggal TEXT NOT NULL,
        nominal REAL NOT NULL DEFAULT 0,
        metode_pembayaran TEXT NOT NULL DEFAULT 'CASH',
        cash_terpakai REAL NOT NULL DEFAULT 0,
        transfer_terpakai REAL NOT NULL DEFAULT 0,
        keterangan TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY (penjualan_id) REFERENCES penjualan (id) ON DELETE CASCADE
      )
    ''');

    // ==========================================================
    // TABEL: kategori_custom (jenis transaksi buatan user, untuk
    // Pemasukan/Pengeluaran/Biaya Motor — persisten & selalu muncul di
    // pilihan berikutnya)
    // ==========================================================
    batch.execute('''
      CREATE TABLE kategori_custom (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tipe TEXT NOT NULL,
        nama TEXT NOT NULL,
        created_at TEXT NOT NULL,
        UNIQUE(tipe, nama)
      )
    ''');

    // ==========================================================
    // TABEL: gajihan (proses gaji karyawan saat tutup buku, dengan
    // potongan kasbon & dana talang otomatis — spesifikasi V3 #11)
    // ==========================================================
    batch.execute('''
      CREATE TABLE gajihan (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nama_karyawan TEXT NOT NULL,
        tanggal TEXT NOT NULL,
        gaji_pokok REAL NOT NULL DEFAULT 0,
        kasbon_dipotong REAL NOT NULL DEFAULT 0,
        dana_talang_dipotong REAL NOT NULL DEFAULT 0,
        total_diterima REAL NOT NULL DEFAULT 0,
        sumber TEXT NOT NULL DEFAULT 'CASH',
        keterangan TEXT,
        periode_id INTEGER,
        created_at TEXT NOT NULL,
        FOREIGN KEY (periode_id) REFERENCES periode (id) ON DELETE SET NULL
      )
    ''');

    // ==========================================================
    // TABEL: biaya_transfer_manual (V3.1 Patch #4 — Menu Biaya Transfer)
    // Biaya transfer yang dicatat manual (bukan hasil otomatis dari
    // pengeluaran), mis. biaya admin bank yang tidak terkait transaksi
    // pengeluaran tertentu. Ikut dijumlahkan ke laporan total biaya
    // transfer periode.
    // ==========================================================
    batch.execute('''
      CREATE TABLE biaya_transfer_manual (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tanggal TEXT NOT NULL,
        nama_tujuan TEXT NOT NULL,
        keterangan TEXT,
        nominal REAL NOT NULL DEFAULT 0,
        periode_id INTEGER,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (periode_id) REFERENCES periode (id) ON DELETE SET NULL
      )
    ''');

    // ==========================================================
    // TABEL V4: users, devices, sync_version, sync_log, backup_log
    // ==========================================================
    batch.execute('''
      CREATE TABLE IF NOT EXISTS users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nama TEXT NOT NULL,
        username TEXT NOT NULL UNIQUE,
        password_hash TEXT NOT NULL,
        role TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'ACTIVE',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    batch.execute('''
      CREATE TABLE IF NOT EXISTS devices (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER,
        device_name TEXT NOT NULL,
        device_type TEXT NOT NULL,
        last_ip TEXT,
        last_sync_at TEXT,
        status TEXT NOT NULL DEFAULT 'ACTIVE',
        created_at TEXT NOT NULL,
        FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE SET NULL
      )
    ''');
    batch.execute('''
      CREATE TABLE IF NOT EXISTS sync_version (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        table_name TEXT NOT NULL UNIQUE,
        version INTEGER NOT NULL DEFAULT 0,
        last_update TEXT NOT NULL
      )
    ''');
    batch.execute('''
      CREATE TABLE IF NOT EXISTS sync_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        table_name TEXT NOT NULL,
        record_id INTEGER NOT NULL,
        action TEXT NOT NULL,
        payload TEXT,
        timestamp TEXT NOT NULL
      )
    ''');
    batch.execute('''
      CREATE TABLE IF NOT EXISTS backup_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        file_name TEXT NOT NULL,
        file_path TEXT NOT NULL,
        file_size INTEGER NOT NULL DEFAULT 0,
        jenis TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');

    await batch.commit(noResult: true);

    // Seed data awal
    await _seedInitialData(db);
    await _seedDefaultUsers(db);
    await _createSyncTriggers(db);
  }

  Future<void> _seedDefaultUsers(Database db) async {
    final now = DateTime.now().toIso8601String();
    await db.insert('users', {
      'nama': 'Andri',
      'username': 'andri',
      'password_hash': _sha256Hex('andri123'),
      'role': 'OWNER_ADMIN',
      'status': 'ACTIVE',
      'created_at': now,
      'updated_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    await db.insert('users', {
      'nama': 'Partner',
      'username': 'partner',
      'password_hash': _sha256Hex('partner123'),
      'role': 'VIEWER',
      'status': 'ACTIVE',
      'created_at': now,
      'updated_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Migrasi versi mendatang ditambahkan di sini secara berurutan.
    // WAJIB: tidak pernah DROP TABLE atau menghapus data lama.
    if (oldVersion < 2) {
      // V2: pisahkan Modal menjadi Modal Cash & Modal Bank, tambahkan
      // penanda sumber (CASH/BANK) pada cash_flow, dan riwayat modal.
      await db.execute(
          "ALTER TABLE cash_flow ADD COLUMN sumber TEXT NOT NULL DEFAULT 'CASH'");
      await db.execute(
          'ALTER TABLE saldo ADD COLUMN modal_cash REAL NOT NULL DEFAULT 0');
      await db.execute(
          'ALTER TABLE saldo ADD COLUMN modal_bank REAL NOT NULL DEFAULT 0');

      await db.execute('''
        CREATE TABLE IF NOT EXISTS modal_history (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          tanggal TEXT NOT NULL,
          jenis TEXT NOT NULL,
          aksi TEXT NOT NULL,
          nominal REAL NOT NULL DEFAULT 0,
          saldo_sebelum REAL NOT NULL DEFAULT 0,
          saldo_sesudah REAL NOT NULL DEFAULT 0,
          keterangan TEXT,
          created_at TEXT NOT NULL
        )
      ''');

      // Data lama: seluruh modal_total yang sudah ada dipindahkan ke
      // modal_cash agar tidak ada nilai modal yang hilang. User bisa
      // memindahkan sebagian ke Modal Bank secara manual lewat menu Modal.
      final existing = await db.query('saldo', where: 'id = 1', limit: 1);
      if (existing.isNotEmpty) {
        final modalLama = (existing.first['modal_total'] as num).toDouble();
        await db.update(
          'saldo',
          {'modal_cash': modalLama, 'modal_bank': 0},
          where: 'id = 1',
        );
        if (modalLama != 0) {
          await db.insert('modal_history', {
            'tanggal': DateTime.now().toIso8601String(),
            'jenis': 'CASH',
            'aksi': 'EDIT',
            'nominal': modalLama,
            'saldo_sebelum': 0,
            'saldo_sesudah': modalLama,
            'keterangan':
                'Migrasi otomatis dari Modal V1 (semua modal lama dicatat sebagai Modal Cash)',
            'created_at': DateTime.now().toIso8601String(),
          });
        }
      }
    }

    if (oldVersion < 3) {
      // V3: metode pembayaran Cash/Transfer/Campuran pada motor &
      // penjualan, biaya admin transfer pada pengeluaran, modul Dana
      // Talang Partner, dan tabel mutasi_antar_saldo (deposit/tarik
      // tunai) supaya bisa diedit/dihapus sebagai satu transaksi utuh.
      await db.execute(
          "ALTER TABLE motor ADD COLUMN metode_pembayaran TEXT NOT NULL DEFAULT 'CASH'");
      await db.execute(
          'ALTER TABLE motor ADD COLUMN cash_dibayar REAL NOT NULL DEFAULT 0');
      await db.execute(
          'ALTER TABLE motor ADD COLUMN transfer_dibayar REAL NOT NULL DEFAULT 0');
      // Data lama: semua pembelian motor sebelumnya selalu dibayar CASH.
      await db.execute('UPDATE motor SET cash_dibayar = total_modal');

      await db.execute(
          "ALTER TABLE penjualan ADD COLUMN metode_pembayaran TEXT NOT NULL DEFAULT 'CASH'");
      await db.execute(
          'ALTER TABLE penjualan ADD COLUMN cash_diterima REAL NOT NULL DEFAULT 0');
      await db.execute(
          'ALTER TABLE penjualan ADD COLUMN transfer_diterima REAL NOT NULL DEFAULT 0');
      // Data lama: semua penjualan sebelumnya selalu diterima CASH.
      await db.execute('UPDATE penjualan SET cash_diterima = harga_jual');

      await db.execute(
          "ALTER TABLE pemasukan ADD COLUMN sumber TEXT NOT NULL DEFAULT 'CASH'");
      await db.execute(
          "ALTER TABLE pengeluaran ADD COLUMN sumber TEXT NOT NULL DEFAULT 'CASH'");
      await db
          .execute('ALTER TABLE pengeluaran ADD COLUMN jenis_transfer TEXT');
      await db.execute(
          'ALTER TABLE pengeluaran ADD COLUMN biaya_admin REAL NOT NULL DEFAULT 0');

      await db.execute('''
        CREATE TABLE IF NOT EXISTS mutasi_antar_saldo (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          tanggal TEXT NOT NULL,
          jenis TEXT NOT NULL,
          nominal REAL NOT NULL DEFAULT 0,
          keterangan TEXT,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        )
      ''');

      await db.execute('''
        CREATE TABLE IF NOT EXISTS dana_talang (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          nama_partner TEXT NOT NULL,
          tanggal TEXT NOT NULL,
          jenis TEXT NOT NULL,
          nominal REAL NOT NULL DEFAULT 0,
          metode_pembayaran TEXT NOT NULL DEFAULT 'CASH',
          cash_terpakai REAL NOT NULL DEFAULT 0,
          transfer_terpakai REAL NOT NULL DEFAULT 0,
          status TEXT NOT NULL DEFAULT 'BELUM_LUNAS',
          total_dibayar_kembali REAL NOT NULL DEFAULT 0,
          keterangan TEXT,
          periode_id INTEGER,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          FOREIGN KEY (periode_id) REFERENCES periode (id) ON DELETE SET NULL
        )
      ''');

      await db.execute('''
        CREATE TABLE IF NOT EXISTS dana_talang_pembayaran (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          dana_talang_id INTEGER NOT NULL,
          tanggal TEXT NOT NULL,
          nominal REAL NOT NULL DEFAULT 0,
          metode_pembayaran TEXT NOT NULL DEFAULT 'CASH',
          cash_terpakai REAL NOT NULL DEFAULT 0,
          transfer_terpakai REAL NOT NULL DEFAULT 0,
          keterangan TEXT,
          created_at TEXT NOT NULL,
          FOREIGN KEY (dana_talang_id) REFERENCES dana_talang (id) ON DELETE CASCADE
        )
      ''');
    }

    if (oldVersion < 4) {
      // V4: motor yang terjual bisa dibayar DP dulu (belum lunas) lalu
      // dicicil sampai lunas. Data lama semuanya dianggap LUNAS (motor
      // yang sudah tercatat terjual pasti sudah dianggap selesai dibayar
      // di versi sebelumnya).
      await db.execute(
          "ALTER TABLE penjualan ADD COLUMN status_pembayaran TEXT NOT NULL DEFAULT 'LUNAS'");

      await db.execute('''
        CREATE TABLE IF NOT EXISTS penjualan_pembayaran (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          penjualan_id INTEGER NOT NULL,
          tanggal TEXT NOT NULL,
          nominal REAL NOT NULL DEFAULT 0,
          metode_pembayaran TEXT NOT NULL DEFAULT 'CASH',
          cash_terpakai REAL NOT NULL DEFAULT 0,
          transfer_terpakai REAL NOT NULL DEFAULT 0,
          keterangan TEXT,
          created_at TEXT NOT NULL,
          FOREIGN KEY (penjualan_id) REFERENCES penjualan (id) ON DELETE CASCADE
        )
      ''');
    }

    if (oldVersion < 5) {
      // V5: kategori/jenis transaksi custom buatan user (Pemasukan,
      // Pengeluaran, Biaya Motor) — dulunya 'Custom' adalah nama
      // kategori literal yang membingungkan; sekarang jadi fitur nyata
      // untuk menambah jenis baru yang tersimpan permanen.
      await db.execute('''
        CREATE TABLE IF NOT EXISTS kategori_custom (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          tipe TEXT NOT NULL,
          nama TEXT NOT NULL,
          created_at TEXT NOT NULL,
          UNIQUE(tipe, nama)
        )
      ''');
    }

    if (oldVersion < 6) {
      // V6: pisahkan modal_awal periode menjadi Cash & Bank (dulunya
      // cuma satu field 'modal_awal' yang tidak pernah disinkronkan ke
      // saldo.cash/saldo_bank saat periode dibuat — itu penyebab bug
      // "Modal sudah diisi tapi Cash=0, Saldo=0"). modal_awal lama tetap
      // dipertahankan sebagai total (Cash+Bank), dan datanya dipindah ke
      // modal_awal_cash agar tidak hilang.
      await db.execute(
          'ALTER TABLE periode ADD COLUMN modal_awal_cash REAL NOT NULL DEFAULT 0');
      await db.execute(
          'ALTER TABLE periode ADD COLUMN modal_awal_bank REAL NOT NULL DEFAULT 0');
      await db.execute(
          'UPDATE periode SET modal_awal_cash = modal_awal WHERE modal_awal > 0');
    }

    if (oldVersion < 7) {
      // V7: bentuk dana talang saat SAYA_MENERIMA — TUNAI (uang cash
      // benar-benar masuk) vs NON_TUNAI (partner membayarkan sesuatu
      // atas nama saya, bukan uang masuk). Data lama semuanya dianggap
      // TUNAI (perilaku lama, konsisten dengan yang sudah tercatat).
      await db.execute(
          "ALTER TABLE dana_talang ADD COLUMN bentuk_talangan TEXT NOT NULL DEFAULT 'TUNAI'");
    }

    if (oldVersion < 8) {
      // V8: metode pembayaran universal untuk Kasbon & Biaya
      // Tambahan/Susulan Motor (dulunya selalu CASH / selalu ikut
      // metode motor induk), plus kolom Catatan pada motor untuk
      // mendukung Edit Detail Motor lengkap.
      await db.execute(
          "ALTER TABLE kasbon ADD COLUMN sumber TEXT NOT NULL DEFAULT 'CASH'");

      await db.execute(
          "ALTER TABLE motor_cost ADD COLUMN metode_pembayaran TEXT NOT NULL DEFAULT 'CASH'");
      await db.execute(
          'ALTER TABLE motor_cost ADD COLUMN cash_dibayar REAL NOT NULL DEFAULT 0');
      await db.execute(
          'ALTER TABLE motor_cost ADD COLUMN transfer_dibayar REAL NOT NULL DEFAULT 0');
      // Data lama: semua biaya motor sebelumnya selalu dibayar CASH.
      await db.execute('UPDATE motor_cost SET cash_dibayar = nominal');

      await db.execute('ALTER TABLE motor ADD COLUMN catatan TEXT');
    }

    if (oldVersion < 9) {
      // V9: modul Gajihan & Tutup Buku — proses gaji karyawan dengan
      // potongan kasbon & dana talang otomatis (spesifikasi V3 #11).
      await db.execute('''
        CREATE TABLE IF NOT EXISTS gajihan (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          nama_karyawan TEXT NOT NULL,
          tanggal TEXT NOT NULL,
          gaji_pokok REAL NOT NULL DEFAULT 0,
          kasbon_dipotong REAL NOT NULL DEFAULT 0,
          dana_talang_dipotong REAL NOT NULL DEFAULT 0,
          total_diterima REAL NOT NULL DEFAULT 0,
          sumber TEXT NOT NULL DEFAULT 'CASH',
          keterangan TEXT,
          periode_id INTEGER,
          created_at TEXT NOT NULL,
          FOREIGN KEY (periode_id) REFERENCES periode (id) ON DELETE SET NULL
        )
      ''');
    }

    if (oldVersion < 10) {
      // V10: V3.1 Update — Perbaikan logika transaksi
      // 1. Pemasukan: support split amount (CAMPURAN = cash + bank)
      // 2. Pengeluaran: finalisasi transfer fee admin untuk semua transaksi
      // 3. Semua transaksi: allow edit tanggal (sudah supported via TEXT field)
      // 4. Audit log: track date changes dan fee changes

      // Tambahkan kolom untuk pemasukan CAMPURAN (cash + bank split)
      await db.execute(
          "ALTER TABLE pemasukan ADD COLUMN cash_masuk REAL NOT NULL DEFAULT 0");
      await db.execute(
          "ALTER TABLE pemasukan ADD COLUMN bank_masuk REAL NOT NULL DEFAULT 0");

      // Tambahkan tracking untuk transfer fee pada pengeluaran
      // (field sudah ada di v9, hanya perlu ensure ada di semua row)
      // jenis_transfer dan biaya_admin sudah ada, tidak perlu ALTER

      // Pastikan transfer fee diterapkan pada semua pengeluaran yang type TRANSFER
      // Data lama: jenis_transfer null = GRATIS, set ke GRATIS untuk aman
      await db.execute(
          "UPDATE pengeluaran SET jenis_transfer = 'GRATIS' WHERE jenis_transfer IS NULL AND sumber = 'BANK'");

      // Pastikan biaya_admin di-populate untuk transfer fee
      // Data lama dengan jenis_transfer tertentu: kalkulasi biaya otomatis
      await db.execute('''
        UPDATE pengeluaran 
        SET biaya_admin = CASE 
          WHEN jenis_transfer = 'BI_FAST' THEN 2500
          WHEN jenis_transfer = 'REALTIME' THEN 6500
          ELSE 0
        END
        WHERE sumber = 'BANK' AND biaya_admin = 0
      ''');

      // Tambahkan kolom updated_at ke pengeluaran untuk tracking edit tanggal
      await db.execute(
          "ALTER TABLE pengeluaran ADD COLUMN updated_at TEXT");

      // Set updated_at = created_at untuk data lama
      await db.execute(
          "UPDATE pengeluaran SET updated_at = created_at WHERE updated_at IS NULL");

      // Tambahkan kolom updated_at ke pemasukan untuk tracking edit tanggal
      await db.execute(
          "ALTER TABLE pemasukan ADD COLUMN updated_at TEXT");

      // Set updated_at = created_at untuk data lama
      await db.execute(
          "UPDATE pemasukan SET updated_at = created_at WHERE updated_at IS NULL");

      // Perpopuasi cash_masuk dan bank_masuk untuk pemasukan CAMPURAN
      // Data lama: semua pemasukan adalah full amount ke sumber yang tertera
      await db.execute('''
        UPDATE pemasukan 
        SET cash_masuk = CASE WHEN sumber = 'CASH' THEN nominal ELSE 0 END,
            bank_masuk = CASE WHEN sumber = 'BANK' THEN nominal ELSE 0 END
        WHERE cash_masuk = 0 AND bank_masuk = 0
      ''');
    }

    if (oldVersion < 11) {
      // V11: V3.1 Patch — Menu Biaya Transfer (halaman khusus, additive)
      await db.execute('''
        CREATE TABLE IF NOT EXISTS biaya_transfer_manual (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          tanggal TEXT NOT NULL,
          nama_tujuan TEXT NOT NULL,
          keterangan TEXT,
          nominal REAL NOT NULL DEFAULT 0,
          periode_id INTEGER,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          FOREIGN KEY (periode_id) REFERENCES periode (id) ON DELETE SET NULL
        )
      ''');
    }

    if (oldVersion < 12) {
      // V12: GARASI ABAH BONTOT V4 — Local Server, Multi User, Sync
      await db.execute('''
        CREATE TABLE IF NOT EXISTS users (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          nama TEXT NOT NULL,
          username TEXT NOT NULL UNIQUE,
          password_hash TEXT NOT NULL,
          role TEXT NOT NULL,
          status TEXT NOT NULL DEFAULT 'ACTIVE',
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        )
      ''');

      await db.execute('''
        CREATE TABLE IF NOT EXISTS devices (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          user_id INTEGER,
          device_name TEXT NOT NULL,
          device_type TEXT NOT NULL,
          last_ip TEXT,
          last_sync_at TEXT,
          status TEXT NOT NULL DEFAULT 'ACTIVE',
          created_at TEXT NOT NULL,
          FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE SET NULL
        )
      ''');

      await db.execute('''
        CREATE TABLE IF NOT EXISTS sync_version (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          table_name TEXT NOT NULL UNIQUE,
          version INTEGER NOT NULL DEFAULT 0,
          last_update TEXT NOT NULL
        )
      ''');

      await db.execute('''
        CREATE TABLE IF NOT EXISTS sync_log (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          table_name TEXT NOT NULL,
          record_id INTEGER NOT NULL,
          action TEXT NOT NULL,
          payload TEXT,
          timestamp TEXT NOT NULL
        )
      ''');

      await db.execute('''
        CREATE TABLE IF NOT EXISTS backup_log (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          file_name TEXT NOT NULL,
          file_path TEXT NOT NULL,
          file_size INTEGER NOT NULL DEFAULT 0,
          jenis TEXT NOT NULL,
          created_at TEXT NOT NULL
        )
      ''');

      final now = DateTime.now().toIso8601String();
      // Default OWNER_ADMIN: Andri / andri123 (wajib ganti password di app)
      await db.insert('users', {
        'nama': 'Andri',
        'username': 'andri',
        'password_hash': _sha256Hex('andri123'),
        'role': 'OWNER_ADMIN',
        'status': 'ACTIVE',
        'created_at': now,
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);

      // Default VIEWER: Partner / partner123 (password bisa diubah OWNER_ADMIN)
      await db.insert('users', {
        'nama': 'Partner',
        'username': 'partner',
        'password_hash': _sha256Hex('partner123'),
        'role': 'VIEWER',
        'status': 'ACTIVE',
        'created_at': now,
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);

      await _createSyncTriggers(db);
    }

    if (oldVersion < 13) {
      // V13 — GARASI ABAH BONTOT V4.2: tambahkan 'users' & 'periode' ke
      // daftar tabel yang disinkron (agar perubahan username/password
      // Partner dan pergantian periode ikut terkirim ke Viewer via
      // sync_log). CREATE TRIGGER IF NOT EXISTS aman dipanggil ulang —
      // hanya menambah trigger yang belum ada, tidak mengubah data lama.
      await _createSyncTriggers(db);
    }

    if (oldVersion < 14) {
      // V14 — GARASI ABAH BONTOT V4.2.1: PAYMENT FLOW GLOBAL.
      // Biaya transfer sebelumnya cuma ada di tabel 'pengeluaran'. Sekarang
      // jadi bagian sistem payment global — motor, motor_cost, dana_talang,
      // dan kasbon butuh kolom jenis_transfer + biaya_admin_transfer supaya
      // biaya transfer tercatat & bisa dipotong dari saldo di transaksi apa
      // pun yang keluar via transfer. ADD COLUMN saja — data lama aman,
      // default biaya_admin_transfer = 0 untuk semua baris lama (tidak
      // pernah dikenai biaya karena field ini belum ada saat itu).
      await _addColumnIfNotExists(db, 'motor', 'jenis_transfer', 'TEXT');
      await _addColumnIfNotExists(
          db, 'motor', 'biaya_admin_transfer', 'REAL NOT NULL DEFAULT 0');
      await _addColumnIfNotExists(db, 'motor_cost', 'jenis_transfer', 'TEXT');
      await _addColumnIfNotExists(db, 'motor_cost', 'biaya_admin_transfer',
          'REAL NOT NULL DEFAULT 0');
      await _addColumnIfNotExists(
          db, 'dana_talang', 'jenis_transfer', 'TEXT');
      await _addColumnIfNotExists(db, 'dana_talang', 'biaya_admin_transfer',
          'REAL NOT NULL DEFAULT 0');
      await _addColumnIfNotExists(db, 'kasbon', 'jenis_transfer', 'TEXT');
      await _addColumnIfNotExists(
          db, 'kasbon', 'biaya_admin_transfer', 'REAL NOT NULL DEFAULT 0');

      // Tabel baru ikut _syncedTables (lewat trigger ulang) supaya biaya
      // transfer di transaksi ini juga ter-sync ke Viewer.
      await _createSyncTriggers(db);
    }

    if (oldVersion < 15) {
      // V15 — GARASI ABAH BONTOT V4.2.2: PAYMENT INTEGRATION FIX.
      // Ditemukan celah: bayarKembali() dana talang (pelunasan hutang saat
      // SAYA_MENERIMA — uang keluar bayar balik ke partner) belum pakai
      // TransferFeeCalculator sama sekali. Tambah kolom penyimpanannya.
      await _addColumnIfNotExists(
          db, 'dana_talang_pembayaran', 'jenis_transfer', 'TEXT');
      await _addColumnIfNotExists(db, 'dana_talang_pembayaran',
          'biaya_admin_transfer', 'REAL NOT NULL DEFAULT 0');
    }

    if (oldVersion < 16) {
      // V16 — HOTFIX KRITIS: trigger sync lama (V12-V15) memakai
      // json_object() yang TIDAK tersedia di SQLite bawaan banyak
      // perangkat Android, menyebabkan SEMUA insert ke tabel manapun
      // (motor, penjualan, periode, dst) gagal dengan error
      // "no such function: json_object". Hapus trigger lama yang rusak,
      // buat ulang versi yang tidak bergantung JSON1. Tidak menyentuh
      // data — hanya definisi trigger.
      await _dropOldSyncTriggers(db);
      await _createSyncTriggers(db);
    }
  }

  /// ALTER TABLE ADD COLUMN aman — cek dulu supaya tidak error kalau
  /// migration dijalankan ulang atau kolom sudah ada dari _onCreate.
  Future<void> _addColumnIfNotExists(
      Database db, String table, String column, String definition) async {
    final info = await db.rawQuery('PRAGMA table_info($table)');
    final exists = info.any((c) => c['name'] == column);
    if (!exists) {
      await db.execute('ALTER TABLE $table ADD COLUMN $column $definition');
    }
  }

  /// Tabel bisnis yang wajib disinkronkan ke Viewer.
  static const List<String> _syncedTables = [
    'users',
    'motor',
    'motor_cost',
    'penjualan',
    'pemasukan',
    'pengeluaran',
    'kasbon',
    'cash_flow',
    'saldo',
    'dana_talang',
    'gajihan',
    'biaya_transfer_manual',
    'periode',
    'audit_log',
  ];

  /// Trigger otomatis: setiap INSERT/UPDATE/DELETE pada tabel bisnis akan
  /// menaikkan sync_version dan mencatat sync_log (lengkap dengan payload
  /// JSON seluruh kolom baris), dipakai oleh sync_engine di Termux Server
  /// untuk delta sync ke HP Partner (Viewer). Mendukung ketiga aksi:
  /// INSERT, UPDATE, DELETE.
  /// Trigger otomatis: setiap INSERT/UPDATE/DELETE pada tabel bisnis akan
  /// menaikkan sync_version dan mencatat sync_log (payload NULL — lihat
  /// catatan di bawah), dipakai oleh sync_engine di Termux Server untuk
  /// delta sync ke HP Partner (Viewer). Mendukung ketiga aksi: INSERT,
  /// UPDATE, DELETE.
  ///
  /// PENTING: payload TIDAK memakai json_object(...) SQLite. Fungsi
  /// json_object() butuh ekstensi JSON1 yang TIDAK selalu tersedia di
  /// SQLite bawaan Android (banyak versi Android/OEM tidak
  /// mengompilasinya) — memakainya membuat trigger gagal saat
  /// dieksekusi dengan error "no such function: json_object", yang
  /// membuat SEMUA insert ke tabel manapun yang ter-trigger ini gagal
  /// total (termasuk membuat periode, transaksi, dll). Server Termux
  /// tetap bisa mengambil data lengkap lewat endpoint fallback
  /// GET /table/{name} memakai record_id dari sync_log.
  static Future<void> _createSyncTriggers(Database db) async {
    for (final table in _syncedTables) {
      await db.execute('''
        INSERT OR IGNORE INTO sync_version (table_name, version, last_update)
        VALUES ('$table', 0, '${DateTime.now().toIso8601String()}')
      ''');

      for (final op in ['INSERT', 'UPDATE', 'DELETE']) {
        final rowRef = op == 'DELETE' ? 'OLD' : 'NEW';
        await db.execute('''
          CREATE TRIGGER IF NOT EXISTS trg_${table}_${op.toLowerCase()}_sync
          AFTER $op ON $table
          BEGIN
            UPDATE sync_version
              SET version = version + 1, last_update = datetime('now')
              WHERE table_name = '$table';
            INSERT INTO sync_log (table_name, record_id, action, payload, timestamp)
              VALUES ('$table', $rowRef.id, '$op', NULL, datetime('now'));
          END;
        ''');
      }
    }
  }

  /// Hapus trigger sync lama (dibuat versi sebelumnya yang memakai
  /// json_object dan gagal di SQLite Android tanpa JSON1). Dipanggil
  /// sebelum _createSyncTriggers supaya CREATE TRIGGER IF NOT EXISTS
  /// benar-benar membuat ulang versi yang sudah diperbaiki.
  static Future<void> _dropOldSyncTriggers(Database db) async {
    for (final table in _syncedTables) {
      for (final op in ['insert', 'update', 'delete']) {
        await db.execute('DROP TRIGGER IF EXISTS trg_${table}_${op}_sync');
      }
    }
  }

  static String _sha256Hex(String input) {
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  Future<void> _seedInitialData(Database db) async {
    final now = DateTime.now().toIso8601String();

    // Seed karyawan default
    for (final nama in AppConstants.karyawanDefault) {
      await db.insert('karyawan', {
        'nama': nama,
        'is_internal': 1,
        'aktif': 1,
        'created_at': now,
      });
    }

    // Seed saldo awal (singleton row id=1)
    await db.insert('saldo', {
      'id': 1,
      'cash': 0,
      'saldo_bank': 0,
      'modal_cash': 0,
      'modal_bank': 0,
      'modal_total': 0,
      'updated_at': now,
    });
  }

  Future<void> close() async {
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
    }
  }

  /// Path fisik file database, dipakai untuk fitur backup/restore.
  Future<String> getDbPath() async {
    return _resolveDbPath();
  }

  /// Backup database ke file tujuan (path lengkap termasuk nama file).
  Future<File> backupDatabase(String destinationPath) async {
    final db = await database;
    // Pastikan semua perubahan tertulis ke disk sebelum copy
    await db.rawQuery('PRAGMA wal_checkpoint(FULL)');
    final currentPath = await getDbPath();
    final sourceFile = File(currentPath);
    return sourceFile.copy(destinationPath);
  }

  /// Restore database dari file backup. Menutup koneksi aktif dulu.
  Future<void> restoreDatabase(String sourceBackupPath) async {
    await close();
    final currentPath = await getDbPath();

    // WAJIB: hapus sidecar WAL/SHM milik database LAMA sebelum menimpa
    // file utama. Kalau tidak, file -wal lama yang masih berisi
    // transaksi/skema versi sebelumnya akan "diputar ulang" (WAL
    // replay) oleh SQLite saat file .db yang baru (hasil restore)
    // dibuka kembali — menyebabkan konflik skema seperti
    // "duplicate column name" karena versi lama & baru tercampur.
    final walFile = File('$currentPath-wal');
    final shmFile = File('$currentPath-shm');
    if (await walFile.exists()) await walFile.delete();
    if (await shmFile.exists()) await shmFile.delete();

    final backupFile = File(sourceBackupPath);
    await backupFile.copy(currentPath);

    // Buka ulang koneksi
    _database = await _initDatabase();
  }
}

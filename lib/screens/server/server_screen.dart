import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/utils/app_formatter.dart';
import '../../providers/auth_provider.dart';
import '../../providers/server_provider.dart';
import '../../providers/sync_provider.dart';
import '../../services/server_config_service.dart';
import '../../services/server_status_service.dart';

/// Menu Server — V4.2:
/// - OWNER_ADMIN: atur SERVER_HOST/PORT/TOKEN/MODE sekali, tersimpan
///   permanen (SharedPreferences), aplikasi baca otomatis setelahnya.
/// - VIEWER: TIDAK bisa lihat/ubah IP/token/mode sama sekali — hanya
///   baca konfigurasi otomatis + cek status ONLINE/OFFLINE (auto
///   discovery, tanpa input manual).
class ServerScreen extends ConsumerStatefulWidget {
  const ServerScreen({super.key});

  @override
  ConsumerState<ServerScreen> createState() => _ServerScreenState();
}

class _ServerScreenState extends ConsumerState<ServerScreen> {
  ServerStatus? _status;
  bool _checking = false;
  DateTime? _lastSyncLocal;

  @override
  void initState() {
    super.initState();
    // Viewer & Owner sama-sama auto-check status saat layar dibuka —
    // Viewer tidak perlu tap apa pun / input apa pun.
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoCheck());
  }

  Future<void> _autoCheck() async {
    final config = await ref.read(serverConfigServiceProvider).load();
    await _checkStatus(config);
  }

  Future<void> _checkStatus(ServerConfig config) async {
    if (!mounted) return;
    setState(() => _checking = true);
    final discovery = ref.read(serverDiscoveryServiceProvider);
    final statusService = ref.read(serverStatusServiceProvider);

    final foundHost = await discovery.discover(config);
    ServerStatus status = ServerStatus.offline();
    if (foundHost != null) {
      status = await statusService.checkStatus(
        foundHost,
        port: config.port,
        apiToken: config.token,
      );
    }
    if (!mounted) return;
    setState(() {
      _status = status;
      _checking = false;
      if (status.online) _lastSyncLocal = DateTime.now();
    });

    // Status ONLINE cuma berarti server bisa di-ping — belum tentu data
    // sudah tersinkron. Trigger sync sungguhan di sini: untuk VIEWER ini
    // menarik (pull) perubahan terbaru; untuk OWNER_ADMIN (V5.1) ini
    // mendorong (push) outbox lokal ke server MASTER. syncNow() sendiri
    // yang menentukan arahnya sesuai role, jadi aman dipanggil apa adanya
    // dari kedua sisi.
    if (status.online) {
      await ref.read(syncNotifierProvider.notifier).syncNow();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isOwner = ref.watch(isOwnerAdminProvider);
    final configAsync = ref.watch(serverConfigProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Server'),
        actions: [
          IconButton(
            onPressed: _checking
                ? null
                : () async {
                    final config = await ref.read(serverConfigServiceProvider).load();
                    await _checkStatus(config);
                  },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: configAsync.when(
        data: (config) => isOwner ? _OwnerView(config: config, screen: this) : _ViewerView(screen: this),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }

  Widget statusCard() {
    final online = _status?.online ?? false;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  online ? Icons.cloud_done : Icons.cloud_off,
                  color: online ? Colors.green : Colors.red,
                  size: 32,
                ),
                const SizedBox(width: 12),
                Text(
                  _checking ? 'MENGECEK...' : (online ? 'ONLINE' : 'OFFLINE'),
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: _checking ? Colors.orange : (online ? Colors.green : Colors.red),
                  ),
                ),
              ],
            ),
            if (!online && !_checking) ...[
              const SizedBox(height: 8),
              Text(
                _lastSyncLocal != null
                    ? 'Mode Offline — data terakhir: ${AppFormatter.tanggalWaktu(_lastSyncLocal!)}'
                    : 'Mode Offline — belum pernah sync. Buka cache terakhir.',
                style: const TextStyle(color: Colors.grey),
              ),
            ],
            const Divider(height: 24),
            _row('Mode Server', online ? _status!.modeLabel : '-'),
            _row('IP', _status?.ip ?? '-'),
            _row('Port', '${_status?.port ?? '-'}'),
            _row('Database', _status?.dbConnected == true ? 'CONNECTED' : '-'),
            _row('Perangkat Terhubung (Client)', '${_status?.connectedDevices ?? 0}'),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// Tampilan OWNER_ADMIN — full config, tersimpan permanen.
class _OwnerView extends ConsumerStatefulWidget {
  final ServerConfig config;
  final _ServerScreenState screen;
  const _OwnerView({required this.config, required this.screen});

  @override
  ConsumerState<_OwnerView> createState() => _OwnerViewState();
}

class _OwnerViewState extends ConsumerState<_OwnerView> {
  late TextEditingController _hostCtrl;
  late TextEditingController _portCtrl;
  late TextEditingController _tokenCtrl;
  late ServerMode _mode;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _hostCtrl = TextEditingController(text: widget.config.host);
    _portCtrl = TextEditingController(text: widget.config.port.toString());
    _tokenCtrl = TextEditingController(text: widget.config.token);
    _mode = widget.config.mode;
  }

  @override
  void dispose() {
    _hostCtrl.dispose();
    _portCtrl.dispose();
    _tokenCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final newConfig = ServerConfig(
      host: _hostCtrl.text.trim(),
      port: int.tryParse(_portCtrl.text.trim()) ?? ServerConfig.defaultPort,
      token: _tokenCtrl.text.trim().isEmpty ? ServerConfig.defaultToken : _tokenCtrl.text.trim(),
      mode: _mode,
    );
    await ref.read(serverConfigServiceProvider).save(newConfig);
    ref.invalidate(serverConfigProvider);
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Konfigurasi server disimpan permanen.')),
    );
    await widget.screen._checkStatus(newConfig);
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        widget.screen.statusCard(),
        const SizedBox(height: 16),
        const _AdminPushCard(),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Konfigurasi Server (OWNER_ADMIN)',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                const Text(
                  'Diatur sekali, tersimpan permanen. Partner otomatis membaca '
                  'konfigurasi ini — tidak perlu input IP manual.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<ServerMode>(
                  value: _mode,
                  decoration: const InputDecoration(
                    labelText: 'Mode Server',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: ServerMode.local, child: Text('LOCAL (Poco F3 + Termux)')),
                    DropdownMenuItem(value: ServerMode.vps, child: Text('VPS (server jarak jauh)')),
                  ],
                  onChanged: (v) => setState(() => _mode = v ?? ServerMode.local),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _hostCtrl,
                  decoration: InputDecoration(
                    labelText: _mode == ServerMode.local ? 'IP Terakhir (opsional, auto-discovery aktif)' : 'Host / Domain VPS',
                    helperText: _mode == ServerMode.local
                        ? 'Boleh dikosongkan — sistem akan cari otomatis di jaringan WiFi lokal.'
                        : 'Contoh: garasi.namadomain.com atau 203.0.113.10',
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _portCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Port',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _tokenCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'API Token',
                    helperText: 'Default: garasi_abah_bontot — samakan dengan garasi_server/config.json',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.save),
                    label: const Text('Simpan Konfigurasi'),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Kontrol proses server (start/stop/restart, 3 mode: Manual/'
              'Background tmux/Auto Boot) dilakukan langsung di HP Poco F3 '
              'lewat Termux — lihat garasi_server/start_server.sh, '
              'stop_server.sh, restart_server.sh.',
            ),
          ),
        ),
      ],
    );
  }
}

/// Tampilan VIEWER — read-only total, tidak ada field IP/token/mode sama
/// sekali. Auto-discovery jalan sendiri di background (lihat initState
/// _ServerScreenState di atas).
///
/// (Kartu izin "Akses semua file" DIHAPUS sejak V5.1 — server sekarang
/// punya DB sendiri via arsitektur push/pull API, jadi DB app tidak lagi
/// perlu berada di folder publik yang butuh izin itu. Lihat
/// database_helper.dart & CHANGELOG_V5.1.md.)

/// V5.1 — kartu push manual untuk OWNER_ADMIN. Push otomatis sudah jalan
/// tiap kali status server dicek ONLINE (lihat _checkStatus), tapi tombol
/// manual tetap dipertahankan sesuai spesifikasi V5.1 ("tetap pertahankan
/// tombol Sinkronkan Sekarang").
class _AdminPushCard extends ConsumerWidget {
  const _AdminPushCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final syncState = ref.watch(syncNotifierProvider);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.cloud_upload_outlined),
                SizedBox(width: 8),
                Text('Kirim Data ke Server', style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              syncState.lastSyncAt != null
                  ? 'Terakhir dikirim: ${AppFormatter.tanggalWaktu(syncState.lastSyncAt!)}'
                  : 'Terakhir dikirim: Belum pernah',
            ),
            if (syncState.lastError != null) ...[
              const SizedBox(height: 8),
              Text('Gagal: ${syncState.lastError}', style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: syncState.isSyncing
                    ? null
                    : () => ref.read(syncNotifierProvider.notifier).syncNow(),
                icon: syncState.isSyncing
                    ? const SizedBox(
                        width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.cloud_upload_outlined),
                label: const Text('Kirim Sekarang'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ViewerView extends ConsumerWidget {
  final _ServerScreenState screen;
  const _ViewerView({required this.screen});

  String _formatWaktu(DateTime? dt) {
    if (dt == null) return 'Belum pernah';
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inSeconds < 60) return 'Baru saja';
    if (diff.inMinutes < 60) return '${diff.inMinutes} menit lalu';
    if (diff.inHours < 24) return '${diff.inHours} jam lalu';
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final syncState = ref.watch(syncNotifierProvider);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        screen.statusCard(),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      syncState.isSyncing
                          ? Icons.sync
                          : (syncState.lastError != null ? Icons.sync_problem : Icons.sync_alt),
                      color: syncState.isSyncing
                          ? Colors.orange
                          : (syncState.lastError != null ? Colors.red : Colors.green),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      syncState.isSyncing ? 'Sedang menyinkronkan data...' : 'Sinkronisasi Data',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text('Terakhir data disinkronkan: ${_formatWaktu(syncState.lastSyncAt)}'),
                if (syncState.lastError != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Sync terakhir gagal: ${syncState.lastError}',
                    style: const TextStyle(color: Colors.red),
                  ),
                ],
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: syncState.isSyncing
                        ? null
                        : () => ref.read(syncNotifierProvider.notifier).syncNow(),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Sinkronkan Sekarang'),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Koneksi ke server dicari & disambungkan otomatis. Jika '
              'OFFLINE, aplikasi tetap bisa dipakai memakai data terakhir '
              'yang tersimpan di HP ini.',
            ),
          ),
        ),
      ],
    );
  }
}

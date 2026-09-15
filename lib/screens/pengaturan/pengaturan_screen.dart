import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/auth_provider.dart';
import '../../providers/sync_provider.dart';
import '../pembukuan/backup_restore_screen.dart';
import 'manajemen_user_screen.dart';
import '../server/server_screen.dart';
import '../device/device_management_screen.dart';

class PengaturanScreen extends ConsumerWidget {
  const PengaturanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider);
    final isOwner = ref.watch(isOwnerAdminProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Pengaturan')),
      body: ListView(
        children: [
          ListTile(
            leading: const CircleAvatar(child: Icon(Icons.person)),
            title: Text(user?.nama ?? '-'),
            subtitle: Text(user?.role ?? '-'),
          ),
          const Divider(),
          // Menu admin (Backup, Manajemen User, Perangkat) HANYA muncul
          // untuk OWNER_ADMIN — bukan sekadar di-nonaktifkan, tapi
          // dihilangkan total dari daftar untuk VIEWER.
          if (isOwner) ...[
            ListTile(
              leading: const Icon(Icons.backup_outlined),
              title: const Text('Backup & Restore'),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const BackupRestoreScreen()),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.people_alt_outlined),
              title: const Text('Manajemen User'),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ManajemenUserScreen()),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.devices_other_outlined),
              title: const Text('Perangkat Terhubung'),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const DeviceManagementScreen()),
              ),
            ),
          ],
          ListTile(
            leading: const Icon(Icons.dns_outlined),
            title: const Text('Server'),
            subtitle: Text(isOwner ? 'Atur koneksi server' : 'Status koneksi (read-only)'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ServerScreen()),
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text('Keluar', style: TextStyle(color: Colors.red)),
            onTap: () async {
              // Reset penanda versi sync SEBELUM logout — supaya kalau
              // akun VIEWER lain login di device yang sama, sync mulai
              // dari nol (bukan lanjut dari titik akun sebelumnya, yang
              // bisa bikin data tercampur antar sesi/akun).
              await ref.read(syncServiceProvider).resetLocalSyncState();
              ref.read(authNotifierProvider).logout();
            },
          ),
        ],
      ),
    );
  }
}

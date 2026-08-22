import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/database/database_helper.dart';
import '../../providers/auth_provider.dart';

final daftarDeviceProvider = FutureProvider.autoDispose<List<Map<String, Object?>>>((ref) async {
  final db = await DatabaseHelper.instance.database;
  return db.query('devices', orderBy: 'id DESC');
});

class DeviceManagementScreen extends ConsumerWidget {
  const DeviceManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOwner = ref.watch(isOwnerAdminProvider);
    if (!isOwner) {
      return Scaffold(
        appBar: AppBar(title: const Text('Perangkat Terhubung')),
        body: const Center(child: Text('Hanya OWNER_ADMIN yang dapat mengakses halaman ini.')),
      );
    }
    final devicesAsync = ref.watch(daftarDeviceProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Perangkat Terhubung')),
      body: devicesAsync.when(
        data: (devices) {
          if (devices.isEmpty) {
            return const Center(child: Text('Belum ada perangkat terdaftar.'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: devices.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final d = devices[i];
              final status = d['status'] as String? ?? 'ACTIVE';
              return Card(
                child: ListTile(
                  leading: Icon(
                    d['device_type'] == 'OWNER' ? Icons.phone_android : Icons.smartphone,
                  ),
                  title: Text(d['device_name'] as String? ?? '-'),
                  subtitle: Text(
                    '${d['device_type']} • IP: ${d['last_ip'] ?? '-'}\n'
                    'Sync terakhir: ${d['last_sync_at'] ?? '-'}',
                  ),
                  isThreeLine: true,
                  trailing: TextButton(
                    onPressed: () async {
                      final db = await DatabaseHelper.instance.database;
                      await db.update(
                        'devices',
                        {'status': status == 'ACTIVE' ? 'LOGGED_OUT' : 'ACTIVE'},
                        where: 'id = ?',
                        whereArgs: [d['id']],
                      );
                      ref.invalidate(daftarDeviceProvider);
                    },
                    child: Text(status == 'ACTIVE' ? 'Logout' : 'Aktifkan'),
                  ),
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }
}

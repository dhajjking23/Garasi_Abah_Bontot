import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../providers/server_provider.dart';

/// Fallback debug: dipanggil saat logo aplikasi di-tap 5x. HANYA
/// OWNER_ADMIN yang bisa memakainya — Viewer yang tap 5x tidak
/// mendapat apa-apa (silent, tidak ada indikasi fitur ini ada).
Future<void> showHiddenServerFallback(BuildContext context, WidgetRef ref) async {
  final isOwner = ref.read(isOwnerAdminProvider);
  if (!isOwner) {
    // Viewer: sengaja tidak menampilkan apa pun, termasuk pesan error,
    // supaya keberadaan fitur ini tidak bocor ke Viewer.
    return;
  }

  final config = await ref.read(serverConfigServiceProvider).load();
  final hostCtrl = TextEditingController(text: config.host);
  final portCtrl = TextEditingController(text: config.port.toString());

  if (!context.mounted) return;
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Fallback: IP Server Manual'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Dipakai HANYA jika Auto Discovery gagal menemukan server.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: hostCtrl,
            decoration: const InputDecoration(labelText: 'IP Server', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: portCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Port', border: OutlineInputBorder()),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Simpan')),
      ],
    ),
  );

  if (result == true) {
    final newConfig = config.copyWith(
      host: hostCtrl.text.trim(),
      port: int.tryParse(portCtrl.text.trim()) ?? config.port,
    );
    await ref.read(serverConfigServiceProvider).save(newConfig);
    ref.invalidate(serverConfigProvider);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('IP server fallback disimpan.')),
      );
    }
  }
}

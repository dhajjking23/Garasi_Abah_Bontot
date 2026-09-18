import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';

class ManajemenUserScreen extends ConsumerWidget {
  const ManajemenUserScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOwner = ref.watch(isOwnerAdminProvider);
    if (!isOwner) {
      return Scaffold(
        appBar: AppBar(title: const Text('Manajemen User')),
        body: const Center(child: Text('Hanya OWNER_ADMIN yang dapat mengakses halaman ini.')),
      );
    }

    final usersAsync = ref.watch(daftarUserProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Manajemen User')),
      body: usersAsync.when(
        data: (users) => ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: users.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, i) => _UserCard(user: users[i], ref: ref),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }
}

class _UserCard extends StatelessWidget {
  final UserModel user;
  final WidgetRef ref;
  const _UserCard({required this.user, required this.ref});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          child: Icon(user.isOwnerAdmin ? Icons.admin_panel_settings : Icons.visibility),
        ),
        title: Text('${user.nama} (@${user.username})'),
        subtitle: Text('${user.role} • ${user.status}'),
        trailing: PopupMenuButton<String>(
          onSelected: (value) => _onAction(context, value),
          itemBuilder: (context) => [
            const PopupMenuItem(value: 'username', child: Text('Ganti Username')),
            const PopupMenuItem(value: 'password', child: Text('Ganti Password')),
            PopupMenuItem(
              value: 'status',
              child: Text(user.isActive ? 'Nonaktifkan Akun' : 'Aktifkan Akun'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _onAction(BuildContext context, String action) async {
    final repo = ref.read(userRepositoryProvider);
    if (action == 'username') {
      final ctrl = TextEditingController(text: user.username);
      final newVal = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Ganti Username'),
          content: TextField(controller: ctrl, decoration: const InputDecoration(labelText: 'Username baru')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
            FilledButton(onPressed: () => Navigator.pop(context, ctrl.text.trim()), child: const Text('Simpan')),
          ],
        ),
      );
      if (newVal != null && newVal.isNotEmpty) {
        await repo.updateUsername(user.id!, newVal);
        ref.invalidate(daftarUserProvider);
      }
    } else if (action == 'password') {
      final ctrl = TextEditingController();
      final newVal = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Ganti Password'),
          content: TextField(
            controller: ctrl,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Password baru'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
            FilledButton(onPressed: () => Navigator.pop(context, ctrl.text), child: const Text('Simpan')),
          ],
        ),
      );
      if (newVal != null && newVal.length >= 4) {
        await repo.updatePassword(user.id!, newVal);
        ref.invalidate(daftarUserProvider);
      }
    } else if (action == 'status') {
      await repo.setStatus(user.id!, user.isActive ? 'NONAKTIF' : 'ACTIVE');
      ref.invalidate(daftarUserProvider);
    }
  }
}

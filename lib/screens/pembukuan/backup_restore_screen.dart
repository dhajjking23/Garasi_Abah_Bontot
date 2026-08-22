import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import '../../core/database/database_helper.dart';
import '../../core/theme/app_theme.dart';
import '../../services/auth_service.dart';

class BackupRestoreScreen extends StatefulWidget {
  const BackupRestoreScreen({super.key});

  @override
  State<BackupRestoreScreen> createState() => _BackupRestoreScreenState();
}

class _BackupRestoreScreenState extends State<BackupRestoreScreen> {
  bool _loading = false;
  String? _statusMessage;

  @override
  Widget build(BuildContext context) {
    if (!AuthService.instance.isOwnerAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('Backup & Restore')),
        body: const Center(child: Text('Hanya OWNER_ADMIN yang dapat mengakses halaman ini.')),
      );
    }
    return _buildContent(context);
  }

  Future<void> _backup() async {
    setState(() {
      _loading = true;
      _statusMessage = null;
    });
    try {
      final dir = await getTemporaryDirectory();
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final backupPath =
          '${dir.path}/garasi_abah_bontot_backup_$timestamp.db';

      final file =
          await DatabaseHelper.instance.backupDatabase(backupPath);

      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Backup database Garasi Abah Bontot - $timestamp',
      );

      setState(() => _statusMessage = 'Backup berhasil dibuat & siap dibagikan.');
    } catch (e) {
      setState(() => _statusMessage = 'Gagal backup: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _restore() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore Database?'),
        content: const Text(
          'Semua data saat ini akan DIGANTI dengan data dari file backup '
          'yang dipilih. Tindakan ini tidak dapat dibatalkan. Lanjutkan?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Ya, Restore'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _loading = true;
      _statusMessage = null;
    });

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
      );
      if (result == null || result.files.single.path == null) {
        setState(() => _loading = false);
        return;
      }

      await DatabaseHelper.instance
          .restoreDatabase(result.files.single.path!);

      setState(() => _statusMessage =
          'Restore berhasil. Silakan restart aplikasi agar seluruh data termuat ulang.');
    } catch (e) {
      setState(() => _statusMessage = 'Gagal restore: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  Widget _buildContent(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Backup & Restore')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_statusMessage != null)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(_statusMessage!),
              ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.backup_outlined, color: AppTheme.primary),
                    const SizedBox(height: 8),
                    const Text('Backup Database',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    const Text(
                      'Simpan salinan database saat ini ke file yang bisa '
                      'dibagikan atau disimpan di Google Drive/penyimpanan lain.',
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: _loading ? null : _backup,
                      child: const Text('Backup Sekarang'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.restore_outlined, color: AppTheme.danger),
                    const SizedBox(height: 8),
                    const Text('Restore Database',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    const Text(
                      'Pulihkan data dari file backup (.db). Data saat ini '
                      'akan tergantikan sepenuhnya.',
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.danger),
                      onPressed: _loading ? null : _restore,
                      child: const Text('Pilih File & Restore'),
                    ),
                  ],
                ),
              ),
            ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.only(top: 20),
                child: Center(child: CircularProgressIndicator()),
              ),
          ],
        ),
      ),
    );
  }
}

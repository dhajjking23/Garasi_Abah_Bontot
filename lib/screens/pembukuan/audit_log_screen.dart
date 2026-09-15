import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/app_formatter.dart';
import '../../providers/app_providers.dart';
import '../../widgets/common_widgets.dart';

class AuditLogScreen extends ConsumerStatefulWidget {
  const AuditLogScreen({super.key});

  @override
  ConsumerState<AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends ConsumerState<AuditLogScreen> {
  String? _filterTabel;

  final _daftarTabel = const [
    'motor',
    'motor_cost',
    'penjualan',
    'pemasukan',
    'pengeluaran',
    'kasbon',
    'periode',
    'pembagian_laba',
  ];

  Color _warnaAksi(String aksi) {
    switch (aksi) {
      case AppConstants.auditCreate:
        return AppTheme.success;
      case AppConstants.auditUpdate:
        return AppTheme.accent;
      case AppConstants.auditDelete:
        return AppTheme.danger;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final logAsync = ref.watch(auditLogProvider(_filterTabel));

    return Scaffold(
      appBar: AppBar(title: const Text('Audit Log')),
      body: Column(
        children: [
          SizedBox(
            height: 50,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              children: [
                ChoiceChip(
                  label: const Text('Semua'),
                  selected: _filterTabel == null,
                  onSelected: (_) => setState(() => _filterTabel = null),
                ),
                const SizedBox(width: 8),
                ..._daftarTabel.map((t) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(t),
                        selected: _filterTabel == t,
                        onSelected: (_) => setState(() => _filterTabel = t),
                      ),
                    )),
              ],
            ),
          ),
          Expanded(
            child: logAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, st) => Center(child: Text('Error: $e')),
              data: (logs) {
                if (logs.isEmpty) {
                  return const EmptyState(message: 'Belum ada aktivitas tercatat');
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: logs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final log = logs[i];
                    return Card(
                      child: ListTile(
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: _warnaAksi(log.aksi).withOpacity(0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            log.aksi.substring(0, 1),
                            style: TextStyle(
                              color: _warnaAksi(log.aksi),
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        title: Text(
                          '${log.aksi} - ${log.tabel}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          log.keterangan ??
                              'Record ID: ${log.recordId ?? "-"}',
                        ),
                        trailing: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              AppFormatter.tanggalWaktu(log.createdAt),
                              style: const TextStyle(fontSize: 10),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline,
                                  size: 18, color: AppTheme.danger),
                              visualDensity: VisualDensity.compact,
                              onPressed: () => _hapusLog(context, log.id!),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _hapusLog(BuildContext context, int logId) async {
    final konfirmasi = await showConfirmDialog(
      context,
      title: 'Hapus Log Ini?',
      message:
          'Jika log ini masih terkait transaksi yang belum dihapus, transaksi tersebut '
          'akan IKUT terhapus dan saldo (Cash/Saldo Bank/Modal) akan dikembalikan otomatis. '
          'Tindakan ini tidak bisa dibatalkan. Lanjutkan?',
      confirmLabel: 'Ya, Hapus',
      confirmColor: AppTheme.danger,
    );
    if (!konfirmasi) return;
    try {
      final service = await ref.read(auditRollbackServiceProvider.future);
      await service.hapusLogDanRollback(logId);
      refreshSemuaData(ref);
      ref.invalidate(auditLogProvider);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }
}

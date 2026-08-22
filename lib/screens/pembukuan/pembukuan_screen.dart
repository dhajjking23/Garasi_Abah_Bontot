import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/app_providers.dart';
import '../pemasukan/pemasukan_screen.dart';
import '../pengeluaran/pengeluaran_screen.dart';
import '../kasbon/kasbon_screen.dart';
import '../dana_talang/dana_talang_screen.dart';
import '../gajihan/gajihan_screen.dart';
import '../pembagian_laba/pembagian_laba_screen.dart';
import 'buat_periode_screen.dart';
import 'riwayat_periode_screen.dart';
import 'backup_restore_screen.dart';
import 'audit_log_screen.dart';

class PembukuanScreen extends ConsumerWidget {
  const PembukuanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final periodeAktifAsync = ref.watch(periodeAktifProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Pembukuan')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          periodeAktifAsync.when(
            data: (periode) => Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.primary,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Periode Aktif',
                      style: TextStyle(color: Colors.white70, fontSize: 12)),
                  const SizedBox(height: 4),
                  Text(
                    periode?.namaPeriode ?? 'Belum ada periode aktif',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 16),
                  ),
                  const SizedBox(height: 12),
                  if (periode == null)
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white),
                      ),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const BuatPeriodeScreen()),
                        ).then((_) => refreshSemuaData(ref));
                      },
                      child: const Text('Buat Periode Baru'),
                    )
                  else
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white),
                      ),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => PembagianLabaScreen(
                              periodeId: periode.id!,
                              namaPeriode: periode.namaPeriode,
                            ),
                          ),
                        ).then((_) => refreshSemuaData(ref));
                      },
                      child: const Text('Lihat Pembagian Laba'),
                    ),
                ],
              ),
            ),
            loading: () => const SizedBox(
              height: 100,
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, st) => Text('Error: $e'),
          ),
          const SizedBox(height: 20),
          _MenuTile(
            icon: Icons.add_card_outlined,
            label: 'Pemasukan',
            subtitle: 'Catat modal & pemasukan lain',
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const PemasukanScreen())),
          ),
          _MenuTile(
            icon: Icons.remove_circle_outline,
            label: 'Pengeluaran',
            subtitle: 'Catat pengeluaran operasional',
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const PengeluaranScreen())),
          ),
          _MenuTile(
            icon: Icons.receipt_long_outlined,
            label: 'Kasbon Karyawan',
            subtitle: 'Piutang & pelunasan kasbon',
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const KasbonScreen())),
          ),
          _MenuTile(
            icon: Icons.handshake_outlined,
            label: 'Dana Talang Partner',
            subtitle: 'Piutang & hutang antar partner',
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const DanaTalangScreen()))
                .then((_) => refreshSemuaData(ref)),
          ),
          _MenuTile(
            icon: Icons.payments_outlined,
            label: 'Gajihan & Tutup Buku',
            subtitle: 'Proses gaji dengan potongan kasbon/dana talang',
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const GajihanScreen()))
                .then((_) => refreshSemuaData(ref)),
          ),
          _MenuTile(
            icon: Icons.history_outlined,
            label: 'Riwayat Periode',
            subtitle: 'Semua periode pembukuan sebelumnya',
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const RiwayatPeriodeScreen())),
          ),
          _MenuTile(
            icon: Icons.backup_outlined,
            label: 'Backup & Restore',
            subtitle: 'Amankan atau pulihkan data',
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const BackupRestoreScreen())),
          ),
          _MenuTile(
            icon: Icons.fact_check_outlined,
            label: 'Audit Log',
            subtitle: 'Riwayat semua perubahan data',
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const AuditLogScreen())),
          ),
        ],
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  const _MenuTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppTheme.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: AppTheme.primary),
        ),
        title: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

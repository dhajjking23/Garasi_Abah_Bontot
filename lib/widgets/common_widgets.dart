import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';
import '../core/utils/app_formatter.dart';
import '../core/utils/rupiah_input_formatter.dart';
import '../core/security/write_guard.dart';

/// Buka date picker standar aplikasi (rentang 2015 - 5 tahun ke depan).
Future<DateTime?> pickTanggal(BuildContext context, DateTime initial) {
  return showDatePicker(
    context: context,
    initialDate: initial,
    firstDate: DateTime(2015),
    lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
  );
}

/// Baris field tanggal yang bisa ditekan untuk mengubah tanggal transaksi.
/// Dipakai di dialog edit transaksi (pengeluaran, pemasukan, kasbon, dst)
/// agar tanggal transaksi bisa dikoreksi — bagian dari V3.1 patch #3.
class TanggalEditField extends StatelessWidget {
  final DateTime tanggal;
  final ValueChanged<DateTime> onChanged;
  final String label;

  const TanggalEditField({
    super.key,
    required this.tanggal,
    required this.onChanged,
    this.label = 'Tanggal Transaksi',
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        final picked = await pickTanggal(context, tanggal);
        if (picked != null) onChanged(picked);
      },
      borderRadius: BorderRadius.circular(8),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: const Icon(Icons.edit_calendar_outlined),
        ),
        child: Text(AppFormatter.tanggal(tanggal)),
      ),
    );
  }
}

class SummaryCard extends StatelessWidget {
  final String label;
  final double value;
  final IconData icon;
  final Color color;
  final bool isHighlight;
  final VoidCallback? onTap;

  const SummaryCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.color = AppTheme.primary,
    this.isHighlight = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final card = Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isHighlight ? color : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isHighlight
                      ? Colors.white.withOpacity(0.2)
                      : color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon,
                    size: 18, color: isHighlight ? Colors.white : color),
              ),
              if (onTap != null)
                Icon(Icons.chevron_right,
                    size: 18,
                    color: isHighlight ? Colors.white70 : Colors.black26),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: isHighlight ? Colors.white70 : Colors.black54,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            AppFormatter.rupiah(value),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: isHighlight ? Colors.white : Colors.black87,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );

    if (onTap == null) return card;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: card,
    );
  }
}

class SectionTitle extends StatelessWidget {
  final String title;
  final Widget? trailing;

  const SectionTitle({super.key, required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Colors.black87,
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  final String message;
  final IconData icon;

  const EmptyState({
    super.key,
    required this.message,
    this.icon = Icons.inbox_outlined,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          Icon(icon, size: 48, color: Colors.black26),
          const SizedBox(height: 12),
          Text(
            message,
            style: const TextStyle(color: Colors.black45),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// Hasil dialog input nominal: nominal wajib, keterangan opsional.
typedef NominalInputResult = ({double nominal, String? keterangan});

/// Dialog input nominal + keterangan yang dipakai berulang di banyak
/// layar (Tambah/Kurangi/Edit Cash, Saldo Bank, Modal, Deposit, Tarik
/// Tunai, dsb). Mengembalikan null jika dibatalkan.
Future<NominalInputResult?> showNominalInputDialog(
  BuildContext context, {
  required String title,
  String confirmLabel = 'Simpan',
  double? initialNominal,
  String? initialKeterangan,
  String keteranganLabel = 'Keterangan (opsional)',
  String? helperText,
}) async {
  final nominalController = TextEditingController(
    text: (initialNominal != null && initialNominal != 0)
        ? RupiahInputFormatter.format(initialNominal.round())
        : '',
  );
  final keteranganController =
      TextEditingController(text: initialKeterangan ?? '');
  final formKey = GlobalKey<FormState>();

  return showDialog<NominalInputResult>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: Text(title),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (helperText != null) ...[
                Text(helperText,
                    style: const TextStyle(fontSize: 12, color: Colors.black54)),
                const SizedBox(height: 12),
              ],
              TextFormField(
                controller: nominalController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: false),
                inputFormatters: [RupiahInputFormatter()],
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Nominal',
                  prefixText: 'Rp ',
                ),
                validator: (v) {
                  final cleaned = (v ?? '').replaceAll(RegExp(r'[^0-9]'), '');
                  final n = double.tryParse(cleaned);
                  if (n == null || n <= 0) return 'Nominal harus lebih dari 0';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: keteranganController,
                decoration: InputDecoration(labelText: keteranganLabel),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                final cleaned = nominalController.text
                    .replaceAll(RegExp(r'[^0-9]'), '');
                Navigator.pop(
                  dialogContext,
                  (
                    nominal: double.parse(cleaned),
                    keterangan: keteranganController.text.trim().isEmpty
                        ? null
                        : keteranganController.text.trim(),
                  ),
                );
              }
            },
            child: Text(confirmLabel),
          ),
        ],
      );
    },
  );
}

/// Dialog konfirmasi generik (dipakai untuk konfirmasi hapus transaksi
/// sesuai aturan "Sistem Hapus Transaksi").
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Ya, Lanjutkan',
  Color? confirmColor,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Batal'),
        ),
        ElevatedButton(
          style: confirmColor != null
              ? ElevatedButton.styleFrom(backgroundColor: confirmColor)
              : null,
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Baris riwayat mutasi kas/bank/modal — dipakai di layar Cash, Saldo
/// Bank, dan Modal.
class RiwayatMutasiTile extends StatelessWidget {
  final DateTime tanggal;
  final String label;
  final String? keterangan;
  final double nominal;
  final bool isMasuk;
  final double? saldoSetelah;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  const RiwayatMutasiTile({
    super.key,
    required this.tanggal,
    required this.label,
    this.keterangan,
    required this.nominal,
    required this.isMasuk,
    this.saldoSetelah,
    this.onTap,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final warna = isMasuk ? AppTheme.success : AppTheme.danger;
    return Card(
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: warna.withOpacity(0.12),
          child: Icon(
            isMasuk ? Icons.arrow_downward : Icons.arrow_upward,
            color: warna,
            size: 18,
          ),
        ),
        title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          '${AppFormatter.tanggalWaktu(tanggal)}${keterangan != null && keterangan!.isNotEmpty ? " • $keterangan" : ""}'
          '${saldoSetelah != null ? "\nSaldo: ${AppFormatter.rupiah(saldoSetelah!)}" : ""}',
        ),
        isThreeLine: saldoSetelah != null,
        trailing: onDelete == null
            ? Text(
                '${isMasuk ? "+" : "-"}${AppFormatter.rupiah(nominal)}',
                style: TextStyle(color: warna, fontWeight: FontWeight.w700),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${isMasuk ? "+" : "-"}${AppFormatter.rupiah(nominal)}',
                    style: TextStyle(color: warna, fontWeight: FontWeight.w700),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline,
                        size: 18, color: AppTheme.danger),
                    onPressed: onDelete,
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
      ),
    );
  }
}

/// Helper global: tampilkan snackbar merah untuk PermissionDeniedException
/// (VIEWER mencoba menulis data) atau error umum lainnya.
void showErrorSnackbar(BuildContext context, Object error) {
  final message = error is PermissionDeniedException
      ? error.message
      : 'Terjadi kesalahan: $error';
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), backgroundColor: AppTheme.danger),
  );
}

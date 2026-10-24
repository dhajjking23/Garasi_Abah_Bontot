import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants/app_constants.dart';
import '../providers/app_providers.dart';

/// Dropdown kategori/jenis transaksi yang otomatis menggabungkan daftar
/// bawaan aplikasi dengan kategori custom yang sudah pernah dibuat user
/// (tabel kategori_custom), plus opsi paling bawah "+ Tambah Jenis
/// Baru" untuk membuat kategori baru yang tersimpan permanen dan akan
/// selalu muncul di transaksi berikutnya.
class KategoriDropdownField extends ConsumerWidget {
  final String tipe; // AppConstants.kategoriTipe*
  final String? value;
  final String label;
  final ValueChanged<String> onChanged;
  final List<String> exclude;

  const KategoriDropdownField({
    super.key,
    required this.tipe,
    required this.value,
    required this.onChanged,
    this.label = 'Jenis Transaksi',
    this.exclude = const [],
  });

  Future<void> _tambahJenisBaru(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final namaBaru = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Tambah Jenis Transaksi Baru'),
          content: Form(
            key: formKey,
            child: TextFormField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Nama jenis transaksi',
                hintText: 'Contoh: Cuci Motor, Sewa Gudang, dll',
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Wajib diisi' : null,
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
                  Navigator.pop(dialogContext, controller.text.trim());
                }
              },
              child: const Text('Simpan'),
            ),
          ],
        );
      },
    );

    if (namaBaru == null || namaBaru.isEmpty) return;

    try {
      final repo = await ref.read(kategoriRepositoryProvider.future);
      final tersimpan = await repo.tambahKategori(tipe, namaBaru);
      ref.invalidate(daftarKategoriProvider);
      onChanged(tersimpan);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final daftarAsync = ref.watch(daftarKategoriProvider(tipe));

    return daftarAsync.when(
      loading: () => const LinearProgressIndicator(),
      error: (e, st) => Text('Gagal memuat kategori: $e'),
      data: (daftarMentah) {
        final daftar =
            daftarMentah.where((k) => !exclude.contains(k)).toList();
        final selected = (value != null && daftar.contains(value))
            ? value
            : (daftar.isNotEmpty ? daftar.first : null);
        return DropdownButtonFormField<String>(
          value: selected,
          decoration: InputDecoration(labelText: label),
          items: [
            ...daftar.map((k) => DropdownMenuItem(value: k, child: Text(k))),
            const DropdownMenuItem(
              value: AppConstants.kategoriTambahBaruSentinel,
              child: Row(
                children: [
                  Icon(Icons.add, size: 16),
                  SizedBox(width: 6),
                  Text('Tambah Jenis Baru'),
                ],
              ),
            ),
          ],
          onChanged: (v) {
            if (v == AppConstants.kategoriTambahBaruSentinel) {
              _tambahJenisBaru(context, ref);
              return;
            }
            if (v != null) onChanged(v);
          },
        );
      },
    );
  }
}

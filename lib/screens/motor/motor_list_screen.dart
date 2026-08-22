import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/app_formatter.dart';
import '../../models/motor_model.dart';
import '../../providers/app_providers.dart';
import '../../widgets/common_widgets.dart';
import 'tambah_motor_screen.dart';
import 'motor_detail_screen.dart';
import '../../providers/auth_provider.dart';

class MotorListScreen extends ConsumerStatefulWidget {
  const MotorListScreen({super.key});

  @override
  ConsumerState<MotorListScreen> createState() => _MotorListScreenState();
}

class _MotorListScreenState extends ConsumerState<MotorListScreen> {
  String? _filterStatus;
  String _searchQuery = '';
  final _searchController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final motorAsync = ref.watch(daftarMotorProvider(_filterStatus));

    return Scaffold(
      appBar: AppBar(title: const Text('Inventory Motor')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Cari kode, merk, tipe, plat nomor...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                  ),
                  onChanged: (v) => setState(() => _searchQuery = v),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 36,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      _FilterChip(
                        label: 'Semua',
                        selected: _filterStatus == null,
                        onTap: () => setState(() => _filterStatus = null),
                      ),
                      const SizedBox(width: 8),
                      _FilterChip(
                        label: 'Tersedia',
                        selected: _filterStatus ==
                            AppConstants.statusMotorTersedia,
                        onTap: () => setState(() =>
                            _filterStatus = AppConstants.statusMotorTersedia),
                      ),
                      const SizedBox(width: 8),
                      _FilterChip(
                        label: 'Terjual',
                        selected:
                            _filterStatus == AppConstants.statusMotorTerjual,
                        onTap: () => setState(() =>
                            _filterStatus = AppConstants.statusMotorTerjual),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: motorAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, st) => Center(child: Text('Error: $e')),
              data: (motorList) {
                final filtered = _searchQuery.isEmpty
                    ? motorList
                    : motorList.where((m) {
                        final q = _searchQuery.toLowerCase();
                        return m.kodeMotor.toLowerCase().contains(q) ||
                            m.merk.toLowerCase().contains(q) ||
                            m.tipe.toLowerCase().contains(q) ||
                            (m.platNomor?.toLowerCase().contains(q) ?? false);
                      }).toList();

                if (filtered.isEmpty) {
                  return const EmptyState(
                    message: 'Belum ada data motor',
                    icon: Icons.motorcycle_outlined,
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 90),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final motor = filtered[index];
                    return _MotorCard(motor: motor);
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: ref.watch(isOwnerAdminProvider)
          ? FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const TambahMotorScreen()),
          ).then((_) => refreshSemuaData(ref));
        },
        icon: const Icon(Icons.add),
        label: const Text('Tambah Motor'),
      )
          : null,
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: AppTheme.primary,
      labelStyle: TextStyle(
        color: selected ? Colors.white : Colors.black87,
        fontWeight: FontWeight.w600,
      ),
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: Colors.black.withOpacity(0.1)),
      ),
    );
  }
}

class _MotorCard extends StatelessWidget {
  final MotorModel motor;

  const _MotorCard({required this.motor});

  @override
  Widget build(BuildContext context) {
    final isTerjual = motor.isTerjual;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => MotorDetailScreen(motorId: motor.id!),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.motorcycle, color: AppTheme.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      motor.namaLengkap,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${motor.kodeMotor}${motor.platNomor != null ? " • ${motor.platNomor}" : ""}',
                      style:
                          const TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      AppFormatter.rupiah(motor.totalModal),
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppTheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: isTerjual
                      ? Colors.grey.withOpacity(0.15)
                      : AppTheme.success.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  isTerjual ? 'Terjual' : 'Tersedia',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: isTerjual ? Colors.grey.shade700 : AppTheme.success,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

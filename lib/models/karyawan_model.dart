import 'package:equatable/equatable.dart';

class KaryawanModel extends Equatable {
  final int? id;
  final String nama;
  final bool isInternal;
  final bool aktif;
  /// V5.9.5 — gaji pokok STANDAR karyawan ini, dipakai untuk auto-fill
  /// field "Gaji Pokok" di GajihanScreen (supaya tidak input manual tiap
  /// kali), tetap bisa diedit per-transaksi tanpa mengubah nilai standar
  /// ini kecuali user pilih "jadikan standar baru".
  final double gajiPokok;
  final DateTime createdAt;

  const KaryawanModel({
    this.id,
    required this.nama,
    this.isInternal = true,
    this.aktif = true,
    this.gajiPokok = 0,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'nama': nama,
      'is_internal': isInternal ? 1 : 0,
      'aktif': aktif ? 1 : 0,
      'gaji_pokok': gajiPokok,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory KaryawanModel.fromMap(Map<String, dynamic> map) {
    return KaryawanModel(
      id: map['id'] as int?,
      nama: map['nama'] as String,
      isInternal: (map['is_internal'] as int) == 1,
      aktif: (map['aktif'] as int) == 1,
      gajiPokok: (map['gaji_pokok'] as num?)?.toDouble() ?? 0,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  KaryawanModel copyWith({
    int? id,
    String? nama,
    bool? isInternal,
    bool? aktif,
    double? gajiPokok,
    DateTime? createdAt,
  }) {
    return KaryawanModel(
      id: id ?? this.id,
      nama: nama ?? this.nama,
      isInternal: isInternal ?? this.isInternal,
      aktif: aktif ?? this.aktif,
      gajiPokok: gajiPokok ?? this.gajiPokok,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  List<Object?> get props =>
      [id, nama, isInternal, aktif, gajiPokok, createdAt];
}

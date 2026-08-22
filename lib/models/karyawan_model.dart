import 'package:equatable/equatable.dart';

class KaryawanModel extends Equatable {
  final int? id;
  final String nama;
  final bool isInternal;
  final bool aktif;
  final DateTime createdAt;

  const KaryawanModel({
    this.id,
    required this.nama,
    this.isInternal = true,
    this.aktif = true,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'nama': nama,
      'is_internal': isInternal ? 1 : 0,
      'aktif': aktif ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory KaryawanModel.fromMap(Map<String, dynamic> map) {
    return KaryawanModel(
      id: map['id'] as int?,
      nama: map['nama'] as String,
      isInternal: (map['is_internal'] as int) == 1,
      aktif: (map['aktif'] as int) == 1,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  @override
  List<Object?> get props => [id, nama, isInternal, aktif, createdAt];
}

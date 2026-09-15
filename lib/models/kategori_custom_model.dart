import 'package:equatable/equatable.dart';

class KategoriCustomModel extends Equatable {
  final int? id;
  final String tipe; // PEMASUKAN / PENGELUARAN / MOTOR_COST
  final String nama;
  final DateTime createdAt;

  const KategoriCustomModel({
    this.id,
    required this.tipe,
    required this.nama,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'tipe': tipe,
      'nama': nama,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory KategoriCustomModel.fromMap(Map<String, dynamic> map) {
    return KategoriCustomModel(
      id: map['id'] as int?,
      tipe: map['tipe'] as String,
      nama: map['nama'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  @override
  List<Object?> get props => [id, tipe, nama, createdAt];
}

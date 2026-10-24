import 'package:equatable/equatable.dart';

class MutasiAntarSaldoModel extends Equatable {
  final int? id;
  final DateTime tanggal;
  final String jenis; // DEPOSIT_KE_BANK / TARIK_TUNAI
  final double nominal;
  final String? keterangan;
  final DateTime createdAt;
  final DateTime updatedAt;

  const MutasiAntarSaldoModel({
    this.id,
    required this.tanggal,
    required this.jenis,
    required this.nominal,
    this.keterangan,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'tanggal': tanggal.toIso8601String(),
      'jenis': jenis,
      'nominal': nominal,
      'keterangan': keterangan,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory MutasiAntarSaldoModel.fromMap(Map<String, dynamic> map) {
    return MutasiAntarSaldoModel(
      id: map['id'] as int?,
      tanggal: DateTime.parse(map['tanggal'] as String),
      jenis: map['jenis'] as String,
      nominal: (map['nominal'] as num).toDouble(),
      keterangan: map['keterangan'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  MutasiAntarSaldoModel copyWith({
    int? id,
    DateTime? tanggal,
    String? jenis,
    double? nominal,
    String? keterangan,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return MutasiAntarSaldoModel(
      id: id ?? this.id,
      tanggal: tanggal ?? this.tanggal,
      jenis: jenis ?? this.jenis,
      nominal: nominal ?? this.nominal,
      keterangan: keterangan ?? this.keterangan,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  @override
  List<Object?> get props =>
      [id, tanggal, jenis, nominal, keterangan, createdAt, updatedAt];
}

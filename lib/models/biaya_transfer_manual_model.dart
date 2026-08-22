import 'package:equatable/equatable.dart';

/// Model untuk biaya transfer yang dicatat MANUAL lewat menu Biaya Transfer
/// (V3.1 Patch #4). Terpisah dari biaya_admin otomatis di tabel pengeluaran,
/// tapi keduanya digabung saat menghitung Total Biaya Transfer Periode.
class BiayaTransferManualModel extends Equatable {
  final int? id;
  final DateTime tanggal;
  final String namaTujuan;
  final String? keterangan;
  final double nominal;
  final int? periodeId;
  final DateTime createdAt;
  final DateTime updatedAt;

  const BiayaTransferManualModel({
    this.id,
    required this.tanggal,
    required this.namaTujuan,
    this.keterangan,
    required this.nominal,
    this.periodeId,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'tanggal': tanggal.toIso8601String(),
      'nama_tujuan': namaTujuan,
      'keterangan': keterangan,
      'nominal': nominal,
      'periode_id': periodeId,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory BiayaTransferManualModel.fromMap(Map<String, dynamic> map) {
    return BiayaTransferManualModel(
      id: map['id'] as int?,
      tanggal: DateTime.parse(map['tanggal'] as String),
      namaTujuan: map['nama_tujuan'] as String,
      keterangan: map['keterangan'] as String?,
      nominal: (map['nominal'] as num).toDouble(),
      periodeId: map['periode_id'] as int?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  BiayaTransferManualModel copyWith({
    int? id,
    DateTime? tanggal,
    String? namaTujuan,
    String? keterangan,
    double? nominal,
    int? periodeId,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return BiayaTransferManualModel(
      id: id ?? this.id,
      tanggal: tanggal ?? this.tanggal,
      namaTujuan: namaTujuan ?? this.namaTujuan,
      keterangan: keterangan ?? this.keterangan,
      nominal: nominal ?? this.nominal,
      periodeId: periodeId ?? this.periodeId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  @override
  List<Object?> get props => [
        id,
        tanggal,
        namaTujuan,
        keterangan,
        nominal,
        periodeId,
        createdAt,
        updatedAt,
      ];
}

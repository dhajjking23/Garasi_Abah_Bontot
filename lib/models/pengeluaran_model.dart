import 'package:equatable/equatable.dart';
import '../core/constants/app_constants.dart';

class PengeluaranModel extends Equatable {
  final int? id;
  final DateTime tanggal;
  final String kategori;
  final double nominal;
  final String? keterangan;
  final String sumber; // CASH / BANK
  final String? jenisTransfer; // GRATIS / BI_FAST / REALTIME (V3.1)
  final double biayaAdmin; // V3.1: universal transfer admin fee
  final int? referensiId;
  final int? periodeId;
  final DateTime createdAt;
  final DateTime updatedAt; // V3.1 untuk tracking edit tanggal

  const PengeluaranModel({
    this.id,
    required this.tanggal,
    required this.kategori,
    required this.nominal,
    this.keterangan,
    this.sumber = AppConstants.sumberCash,
    this.jenisTransfer,
    this.biayaAdmin = 0,
    this.referensiId,
    this.periodeId,
    required this.createdAt,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? createdAt;

  double get totalKeluar => nominal + biayaAdmin;

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'tanggal': tanggal.toIso8601String(),
      'kategori': kategori,
      'nominal': nominal,
      'keterangan': keterangan,
      'sumber': sumber,
      'jenis_transfer': jenisTransfer,
      'biaya_admin': biayaAdmin,
      'referensi_id': referensiId,
      'periode_id': periodeId,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory PengeluaranModel.fromMap(Map<String, dynamic> map) {
    return PengeluaranModel(
      id: map['id'] as int?,
      tanggal: DateTime.parse(map['tanggal'] as String),
      kategori: map['kategori'] as String,
      nominal: (map['nominal'] as num).toDouble(),
      keterangan: map['keterangan'] as String?,
      sumber: (map['sumber'] as String?) ?? AppConstants.sumberCash,
      jenisTransfer: map['jenis_transfer'] as String?,
      biayaAdmin: (map['biaya_admin'] as num?)?.toDouble() ?? 0,
      referensiId: map['referensi_id'] as int?,
      periodeId: map['periode_id'] as int?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: map['updated_at'] != null
          ? DateTime.parse(map['updated_at'] as String)
          : DateTime.parse(map['created_at'] as String),
    );
  }

  @override
  List<Object?> get props => [
        id,
        tanggal,
        kategori,
        nominal,
        keterangan,
        sumber,
        jenisTransfer,
        biayaAdmin,
        referensiId,
        periodeId,
        createdAt,
        updatedAt,
      ];
}

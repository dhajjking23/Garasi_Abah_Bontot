import 'package:equatable/equatable.dart';
import '../core/constants/app_constants.dart';

class GajihanModel extends Equatable {
  final int? id;
  final String namaKaryawan;
  final DateTime tanggal;
  final double gajiPokok;
  final double kasbonDipotong;
  final double danaTalangDipotong;
  final double totalDiterima;
  final String sumber; // CASH / BANK
  final String? keterangan;
  final int? periodeId;
  final DateTime createdAt;

  const GajihanModel({
    this.id,
    required this.namaKaryawan,
    required this.tanggal,
    required this.gajiPokok,
    this.kasbonDipotong = 0,
    this.danaTalangDipotong = 0,
    required this.totalDiterima,
    this.sumber = AppConstants.sumberCash,
    this.keterangan,
    this.periodeId,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'nama_karyawan': namaKaryawan,
      'tanggal': tanggal.toIso8601String(),
      'gaji_pokok': gajiPokok,
      'kasbon_dipotong': kasbonDipotong,
      'dana_talang_dipotong': danaTalangDipotong,
      'total_diterima': totalDiterima,
      'sumber': sumber,
      'keterangan': keterangan,
      'periode_id': periodeId,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory GajihanModel.fromMap(Map<String, dynamic> map) {
    return GajihanModel(
      id: map['id'] as int?,
      namaKaryawan: map['nama_karyawan'] as String,
      tanggal: DateTime.parse(map['tanggal'] as String),
      gajiPokok: (map['gaji_pokok'] as num).toDouble(),
      kasbonDipotong: (map['kasbon_dipotong'] as num?)?.toDouble() ?? 0,
      danaTalangDipotong:
          (map['dana_talang_dipotong'] as num?)?.toDouble() ?? 0,
      totalDiterima: (map['total_diterima'] as num).toDouble(),
      sumber: (map['sumber'] as String?) ?? AppConstants.sumberCash,
      keterangan: map['keterangan'] as String?,
      periodeId: map['periode_id'] as int?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  @override
  List<Object?> get props => [
        id,
        namaKaryawan,
        tanggal,
        gajiPokok,
        kasbonDipotong,
        danaTalangDipotong,
        totalDiterima,
        sumber,
        keterangan,
        periodeId,
        createdAt,
      ];
}

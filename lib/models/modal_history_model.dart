import 'package:equatable/equatable.dart';

class ModalHistoryModel extends Equatable {
  final int? id;
  final DateTime tanggal;
  final String jenis; // CASH / BANK, lihat AppConstants.modalJenis*
  final String aksi; // TAMBAH / KURANG / EDIT, lihat AppConstants.modalAksi*
  final double nominal;
  final double saldoSebelum;
  final double saldoSesudah;
  final String? keterangan;
  final DateTime createdAt;

  const ModalHistoryModel({
    this.id,
    required this.tanggal,
    required this.jenis,
    required this.aksi,
    required this.nominal,
    required this.saldoSebelum,
    required this.saldoSesudah,
    this.keterangan,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'tanggal': tanggal.toIso8601String(),
      'jenis': jenis,
      'aksi': aksi,
      'nominal': nominal,
      'saldo_sebelum': saldoSebelum,
      'saldo_sesudah': saldoSesudah,
      'keterangan': keterangan,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory ModalHistoryModel.fromMap(Map<String, dynamic> map) {
    return ModalHistoryModel(
      id: map['id'] as int?,
      tanggal: DateTime.parse(map['tanggal'] as String),
      jenis: map['jenis'] as String,
      aksi: map['aksi'] as String,
      nominal: (map['nominal'] as num).toDouble(),
      saldoSebelum: (map['saldo_sebelum'] as num).toDouble(),
      saldoSesudah: (map['saldo_sesudah'] as num).toDouble(),
      keterangan: map['keterangan'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  @override
  List<Object?> get props => [
        id,
        tanggal,
        jenis,
        aksi,
        nominal,
        saldoSebelum,
        saldoSesudah,
        keterangan,
        createdAt,
      ];
}

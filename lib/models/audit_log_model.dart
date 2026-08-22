import 'package:equatable/equatable.dart';

class AuditLogModel extends Equatable {
  final int? id;
  final String tabel;
  final int? recordId;
  final String aksi; // CREATE / UPDATE / DELETE
  final String? dataLama;
  final String? dataBaru;
  final String? keterangan;
  final DateTime createdAt;

  const AuditLogModel({
    this.id,
    required this.tabel,
    this.recordId,
    required this.aksi,
    this.dataLama,
    this.dataBaru,
    this.keterangan,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'tabel': tabel,
      'record_id': recordId,
      'aksi': aksi,
      'data_lama': dataLama,
      'data_baru': dataBaru,
      'keterangan': keterangan,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory AuditLogModel.fromMap(Map<String, dynamic> map) {
    return AuditLogModel(
      id: map['id'] as int?,
      tabel: map['tabel'] as String,
      recordId: map['record_id'] as int?,
      aksi: map['aksi'] as String,
      dataLama: map['data_lama'] as String?,
      dataBaru: map['data_baru'] as String?,
      keterangan: map['keterangan'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  @override
  List<Object?> get props => [
        id,
        tabel,
        recordId,
        aksi,
        dataLama,
        dataBaru,
        keterangan,
        createdAt,
      ];
}

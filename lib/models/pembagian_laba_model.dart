import 'dart:convert';
import 'package:equatable/equatable.dart';

/// Detail bonus per penjual internal, disimpan sebagai JSON di kolom
/// detail_bonus_json pada tabel pembagian_laba.
class DetailBonusPenjual extends Equatable {
  final String nama;
  final int jumlahUnit;
  final double totalBonus;

  const DetailBonusPenjual({
    required this.nama,
    required this.jumlahUnit,
    required this.totalBonus,
  });

  Map<String, dynamic> toJson() => {
        'nama': nama,
        'jumlah_unit': jumlahUnit,
        'total_bonus': totalBonus,
      };

  factory DetailBonusPenjual.fromJson(Map<String, dynamic> json) {
    return DetailBonusPenjual(
      nama: json['nama'] as String,
      jumlahUnit: json['jumlah_unit'] as int,
      totalBonus: (json['total_bonus'] as num).toDouble(),
    );
  }

  @override
  List<Object?> get props => [nama, jumlahUnit, totalBonus];
}

class PembagianLabaModel extends Equatable {
  final int? id;
  final int periodeId;
  final double labaBersih;
  final double bagianAbah;
  final double bagianIki;
  final double bagianAndri;
  final double bagianIlham;
  final double totalHadiahPenjualan;
  final int unitInternalTerjual;
  final double bonusPerUnit;
  final List<DetailBonusPenjual> detailBonus;
  final DateTime createdAt;

  const PembagianLabaModel({
    this.id,
    required this.periodeId,
    required this.labaBersih,
    required this.bagianAbah,
    required this.bagianIki,
    required this.bagianAndri,
    required this.bagianIlham,
    required this.totalHadiahPenjualan,
    required this.unitInternalTerjual,
    required this.bonusPerUnit,
    required this.detailBonus,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'periode_id': periodeId,
      'laba_bersih': labaBersih,
      'bagian_abah': bagianAbah,
      'bagian_iki': bagianIki,
      'bagian_andri': bagianAndri,
      'bagian_ilham': bagianIlham,
      'total_hadiah_penjualan': totalHadiahPenjualan,
      'unit_internal_terjual': unitInternalTerjual,
      'bonus_per_unit': bonusPerUnit,
      'detail_bonus_json':
          jsonEncode(detailBonus.map((e) => e.toJson()).toList()),
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory PembagianLabaModel.fromMap(Map<String, dynamic> map) {
    final rawJson = map['detail_bonus_json'] as String?;
    final List<DetailBonusPenjual> detail = [];
    if (rawJson != null && rawJson.isNotEmpty) {
      final List<dynamic> decoded = jsonDecode(rawJson) as List<dynamic>;
      detail.addAll(
        decoded.map(
          (e) => DetailBonusPenjual.fromJson(e as Map<String, dynamic>),
        ),
      );
    }

    return PembagianLabaModel(
      id: map['id'] as int?,
      periodeId: map['periode_id'] as int,
      labaBersih: (map['laba_bersih'] as num).toDouble(),
      bagianAbah: (map['bagian_abah'] as num).toDouble(),
      bagianIki: (map['bagian_iki'] as num).toDouble(),
      bagianAndri: (map['bagian_andri'] as num).toDouble(),
      bagianIlham: (map['bagian_ilham'] as num).toDouble(),
      totalHadiahPenjualan: (map['total_hadiah_penjualan'] as num).toDouble(),
      unitInternalTerjual: map['unit_internal_terjual'] as int,
      bonusPerUnit: (map['bonus_per_unit'] as num).toDouble(),
      detailBonus: detail,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  @override
  List<Object?> get props => [
        id,
        periodeId,
        labaBersih,
        bagianAbah,
        bagianIki,
        bagianAndri,
        bagianIlham,
        totalHadiahPenjualan,
        unitInternalTerjual,
        bonusPerUnit,
        detailBonus,
        createdAt,
      ];
}

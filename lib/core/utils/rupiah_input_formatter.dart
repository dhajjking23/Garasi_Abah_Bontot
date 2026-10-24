import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

/// TextInputFormatter yang otomatis menambahkan pemisah ribuan saat
/// user mengetik nominal (mis. "12300000" -> "12.300.000"), sesuai
/// spesifikasi "Format Nominal Uang". Nilai murni (tanpa titik) selalu
/// bisa didapat lewat [RupiahInputFormatter.parse].
class RupiahInputFormatter extends TextInputFormatter {
  static final NumberFormat _formatter = NumberFormat.decimalPattern('id_ID');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digitsOnly = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digitsOnly.isEmpty) {
      return const TextEditingValue(text: '');
    }

    final number = int.parse(digitsOnly);
    final newText = _formatter.format(number);

    return TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newText.length),
    );
  }

  /// Format angka murni menjadi teks dengan pemisah ribuan (dipakai
  /// untuk mengisi nilai awal field yang sudah ada isinya).
  static String format(num value) => _formatter.format(value);

  /// Ambil nilai numerik murni dari teks yang sudah diformat (buang
  /// semua pemisah ribuan).
  static double parse(String formatted) {
    final digitsOnly = formatted.replaceAll(RegExp(r'[^0-9]'), '');
    if (digitsOnly.isEmpty) return 0;
    return double.parse(digitsOnly);
  }
}

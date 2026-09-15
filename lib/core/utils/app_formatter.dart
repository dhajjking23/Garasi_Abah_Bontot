import 'package:intl/intl.dart';

class AppFormatter {
  AppFormatter._();

  static final NumberFormat _currencyFormat = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp ',
    decimalDigits: 0,
  );

  static final DateFormat _dateFormat = DateFormat('d MMM yyyy', 'id_ID');
  static final DateFormat _dateTimeFormat =
      DateFormat('d MMM yyyy, HH:mm', 'id_ID');

  static String rupiah(num value) => _currencyFormat.format(value);

  static String tanggal(DateTime date) => _dateFormat.format(date);

  static String tanggalWaktu(DateTime date) => _dateTimeFormat.format(date);

  static String persen(double value) =>
      '${(value * 100).toStringAsFixed(1)}%';
}

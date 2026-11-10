import 'package:intl/intl.dart';

String formatKc(double value) => '${NumberFormat.decimalPattern('cs').format(value.round())} Kč';

String formatMonths(double months) => '${NumberFormat('0.0', 'cs').format(months)} měs.';

/// „do února 2028“ – formátovací (genitivní) tvar měsíce.
String formatUntil(DateTime date) => 'do ${DateFormat('MMMM yyyy', 'cs').format(date)}';

import '../data/entries_document.dart';

enum Scenario { asUsual, withoutDiscretionary, essentialOnly }

const _scenarioNeeds = {
  Scenario.asUsual: {'nezbytné', 'vhodné', 'zbytné'},
  Scenario.withoutDiscretionary: {'nezbytné', 'vhodné'},
  Scenario.essentialOnly: {'nezbytné'},
};

const unexpectedNeed = 'nečekané';
const _essentialNeed = 'nezbytné';
const uncategorizedType = 'nezařazeno';

/// Delší runway (100 let) už je prakticky „vystačí“ a datum by bylo nesmyslné.
const maxRunwayMonths = 1200;

class RunwayInput {
  const RunwayInput({
    required this.savings,
    required this.newMonthlyIncome,
    required this.windowMonths,
    required this.includeUnexpected,
    required this.today,
  });

  final double savings;
  final double newMonthlyIncome;
  final int windowMonths;
  final bool includeUnexpected;
  final DateTime today;
}

class ScenarioResult {
  const ScenarioResult({
    required this.scenario,
    required this.monthlySpend,
    required this.runwayMonths,
    required this.depletionDate,
    required this.monthlyByType,
  });

  final Scenario scenario;
  final double monthlySpend;

  /// `null` = úspory nedojdou (nový příjem pokryje výdaje), nebo nejsou data.
  final double? runwayMonths;
  final DateTime? depletionDate;
  final Map<String, double> monthlyByType;
}

class RunwayResult {
  const RunwayResult({
    required this.scenarios,
    required this.monthsWithData,
    required this.windowMonths,
    required this.regularMonthlyIncome,
    required this.uncategorizedCount,
    required this.nonCzkCount,
    required this.hasData,
  });

  /// V pořadí [Scenario.values].
  final List<ScenarioResult> scenarios;
  final int monthsWithData;
  final int windowMonths;
  final double regularMonthlyIncome;
  final int uncategorizedCount;
  final int nonCzkCount;
  final bool hasData;
}

int _monthKey(DateTime d) => d.year * 12 + d.month - 1;

/// Poslední měsíc okna: měsíc posledního záznamu, pokud je den ≥ 25, jinak předchozí.
int _windowEnd(DateTime lastEntry) =>
    lastEntry.day >= 25 ? _monthKey(lastEntry) : _monthKey(lastEntry) - 1;

DateTime _addMonths(DateTime today, double months) {
  final whole = months.floor();
  final days = ((months - whole) * 30).round();
  // Den oříznout na délku cílového měsíce (31. 1. + 1 měsíc = 28. 2., ne 3. 3.).
  final lastDay = DateTime(today.year, today.month + whole + 1, 0).day;
  final day = today.day > lastDay ? lastDay : today.day;
  return DateTime(today.year, today.month + whole, day + days);
}

RunwayResult calculateRunway(EntriesDocument doc, RunwayInput input) {
  final czk = doc.entries.where((e) => e.currency == 'CZK').toList();
  final nonCzkCount = doc.entries.length - czk.length;
  final uncategorizedCount = czk.where((e) => e.amountCents < 0 && e.categoryKind == null).length;

  var inWindow = <AppEntry>[];
  if (czk.isNotEmpty) {
    final last = czk.map((e) => e.date).reduce((a, b) => a.isAfter(b) ? a : b);
    final end = _windowEnd(last);
    final start = end - input.windowMonths + 1;
    inWindow = czk.where((e) {
      final key = _monthKey(e.date);
      return key >= start && key <= end;
    }).toList();
  }
  final monthsWithData = inWindow.map((e) => _monthKey(e.date)).toSet().length;
  final hasData = monthsWithData > 0;
  final divisor = hasData ? monthsWithData : 1;

  final regularIncomeCents = inWindow
      .where((e) => e.amountCents > 0 && e.incomeType == 'pravidelný')
      .fold<int>(0, (sum, e) => sum + e.amountCents);

  final expenses = inWindow
      .where((e) => e.amountCents < 0 && !doc.excludedTypes.contains(e.expenseType))
      .toList();

  final scenarios = [
    for (final scenario in Scenario.values)
      _scenario(scenario, expenses, input, divisor, hasData),
  ];

  return RunwayResult(
    scenarios: scenarios,
    monthsWithData: monthsWithData,
    windowMonths: input.windowMonths,
    regularMonthlyIncome: regularIncomeCents / 100 / divisor,
    uncategorizedCount: uncategorizedCount,
    nonCzkCount: nonCzkCount,
    hasData: hasData,
  );
}

ScenarioResult _scenario(
  Scenario scenario,
  List<AppEntry> expenses,
  RunwayInput input,
  int divisor,
  bool hasData,
) {
  final needs = {..._scenarioNeeds[scenario]!, if (input.includeUnexpected) unexpectedNeed};
  final byTypeCents = <String, int>{};
  for (final e in expenses) {
    final uncategorized = e.categoryKind == null;
    final need = uncategorized ? _essentialNeed : e.need;
    if (!needs.contains(need)) continue;
    final type = uncategorized ? uncategorizedType : (e.expenseType ?? uncategorizedType);
    byTypeCents[type] = (byTypeCents[type] ?? 0) - e.amountCents;
  }
  final monthlyByType = {
    for (final entry in byTypeCents.entries) entry.key: entry.value / 100 / divisor,
  };
  final monthlySpend = monthlyByType.values.fold<double>(0, (a, b) => a + b);

  double? months;
  if (hasData && monthlySpend - input.newMonthlyIncome > 0) {
    months = input.savings <= 0 ? 0 : input.savings / (monthlySpend - input.newMonthlyIncome);
    if (months > maxRunwayMonths) months = null;
  }
  return ScenarioResult(
    scenario: scenario,
    monthlySpend: monthlySpend,
    runwayMonths: months,
    depletionDate: months == null ? null : _addMonths(input.today, months),
    monthlyByType: monthlyByType,
  );
}

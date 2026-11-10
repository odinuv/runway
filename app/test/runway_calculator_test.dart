import 'package:flutter_test/flutter_test.dart';
import 'package:runway_app/data/entries_document.dart';
import 'package:runway_app/domain/runway_calculator.dart';

AppEntry e(
  DateTime date,
  double kc, {
  String? need,
  String type = 'ostatní',
  String? incomeType,
  String currency = 'CZK',
}) {
  final uncategorized = need == null && incomeType == null;
  return AppEntry(
    date: date,
    amountCents: (kc * 100).round(),
    currency: currency,
    categoryKind: uncategorized ? null : (kc < 0 ? 'expense' : 'income'),
    expenseType: kc < 0 && !uncategorized ? type : null,
    need: need,
    incomeType: incomeType,
  );
}

EntriesDocument doc(List<AppEntry> entries, {Set<String> excluded = const {}}) =>
    EntriesDocument(initialBalance: 0, updatedAt: null, entries: entries, excludedTypes: excluded);

RunwayInput input({
  double savings = 300000,
  double income = 0,
  int window = 12,
  bool unexpected = false,
}) =>
    RunwayInput(
      savings: savings,
      newMonthlyIncome: income,
      windowMonths: window,
      includeUnexpected: unexpected,
      today: DateTime(2026, 11, 9),
    );

ScenarioResult scenario(RunwayResult r, Scenario s) => r.scenarios[s.index];

void main() {
  test('window ends in last month when last entry day >= 25', () {
    final r = calculateRunway(
      doc([
        e(DateTime(2026, 7, 15), -1000, need: 'nezbytné'),
        e(DateTime(2026, 8, 15), -2000, need: 'nezbytné'),
        e(DateTime(2026, 10, 27), -4000, need: 'nezbytné'),
      ]),
      input(window: 3),
    );
    expect(r.monthsWithData, 2);
    expect(scenario(r, Scenario.essentialOnly).monthlySpend, 3000);
  });

  test('window ends previous month when last entry day < 25', () {
    final r = calculateRunway(
      doc([
        e(DateTime(2026, 6, 15), -1000, need: 'nezbytné'),
        e(DateTime(2026, 7, 15), -2000, need: 'nezbytné'),
        e(DateTime(2026, 10, 10), -4000, need: 'nezbytné'),
      ]),
      input(window: 3),
    );
    expect(r.monthsWithData, 1);
    expect(scenario(r, Scenario.essentialOnly).monthlySpend, 2000);
  });

  test('divides by months with data', () {
    final r = calculateRunway(
      doc([
        e(DateTime(2026, 3, 5), -20000, need: 'nezbytné'),
        e(DateTime(2026, 9, 26), -10000, need: 'nezbytné'),
      ]),
      input(window: 12),
    );
    expect(r.monthsWithData, 2);
    expect(r.windowMonths, 12);
    expect(scenario(r, Scenario.essentialOnly).monthlySpend, 15000);
  });

  group('scenario sums', () {
    final entries = [
      e(DateTime(2026, 10, 1), -10000, need: 'nezbytné', type: 'bydlení'),
      e(DateTime(2026, 10, 2), -5000, need: 'vhodné', type: 'pojištění'),
      e(DateTime(2026, 10, 3), -3000, need: 'zbytné', type: 'volný čas'),
      e(DateTime(2026, 10, 28), -2000, need: 'nečekané', type: 'doprava'),
    ];

    test('without unexpected', () {
      final r = calculateRunway(doc(entries), input());
      expect(r.scenarios.map((s) => s.monthlySpend), [18000, 15000, 10000]);
      expect(scenario(r, Scenario.withoutDiscretionary).monthlyByType, {'bydlení': 10000, 'pojištění': 5000});
    });

    test('with unexpected', () {
      final r = calculateRunway(doc(entries), input(unexpected: true));
      expect(r.scenarios.map((s) => s.monthlySpend), [20000, 17000, 12000]);
      expect(scenario(r, Scenario.essentialOnly).monthlyByType['doprava'], 2000);
    });
  });

  test('runway months and depletion date', () {
    final r = calculateRunway(
      doc([e(DateTime(2026, 10, 26), -25000, need: 'nezbytné')]),
      input(savings: 300000, income: 10000),
    );
    final s = scenario(r, Scenario.essentialOnly);
    expect(s.runwayMonths, 20);
    expect(s.depletionDate, DateTime(2028, 7, 9));
  });

  test('fractional runway adds days', () {
    final r = calculateRunway(
      doc([e(DateTime(2026, 10, 26), -10000, need: 'nezbytné')]),
      input(savings: 15000),
    );
    final s = scenario(r, Scenario.essentialOnly);
    expect(s.runwayMonths, 1.5);
    expect(s.depletionDate, DateTime(2026, 12, 24));
  });

  test('infinite when income covers spend', () {
    final r = calculateRunway(
      doc([e(DateTime(2026, 10, 26), -25000, need: 'nezbytné')]),
      input(income: 25000),
    );
    expect(scenario(r, Scenario.essentialOnly).runwayMonths, isNull);
    expect(scenario(r, Scenario.essentialOnly).depletionDate, isNull);
  });

  test('zero savings gives zero months', () {
    final r = calculateRunway(
      doc([e(DateTime(2026, 10, 26), -25000, need: 'nezbytné')]),
      input(savings: 0),
    );
    expect(scenario(r, Scenario.essentialOnly).runwayMonths, 0);
    expect(scenario(r, Scenario.essentialOnly).depletionDate, DateTime(2026, 11, 9));
  });

  test('excluded types and non-CZK ignored, counted', () {
    final r = calculateRunway(
      doc(
        [
          e(DateTime(2026, 10, 26), -10000, need: 'nezbytné'),
          e(DateTime(2026, 10, 5), -50000, need: 'vhodné', type: 'spoření a investice'),
          e(DateTime(2026, 10, 6), -100, need: 'nezbytné', currency: 'EUR'),
        ],
        excluded: {'spoření a investice'},
      ),
      input(),
    );
    expect(scenario(r, Scenario.asUsual).monthlySpend, 10000);
    expect(r.nonCzkCount, 1);
  });

  test('uncategorized counted as essential', () {
    final r = calculateRunway(
      doc([
        e(DateTime(2026, 10, 26), -10000, need: 'nezbytné', type: 'bydlení'),
        e(DateTime(2026, 10, 5), -700),
      ]),
      input(),
    );
    expect(scenario(r, Scenario.essentialOnly).monthlySpend, 10700);
    expect(scenario(r, Scenario.essentialOnly).monthlyByType['nezařazeno'], 700);
    expect(r.uncategorizedCount, 1);
  });

  test('regular income only', () {
    final r = calculateRunway(
      doc([
        e(DateTime(2026, 10, 10), 60000, incomeType: 'pravidelný'),
        e(DateTime(2026, 10, 26), 3000, incomeType: 'nepravidelný'),
      ]),
      input(),
    );
    expect(r.regularMonthlyIncome, 60000);
    expect(scenario(r, Scenario.asUsual).monthlySpend, 0);
  });

  test('no data in window', () {
    final r = calculateRunway(doc([]), input(window: 3));
    expect(r.hasData, isFalse);
    expect(r.scenarios, hasLength(3));
    expect(r.scenarios.every((s) => s.runwayMonths == null), isTrue);
  });

  test('absurdly long runway shown as infinite', () {
    final r = calculateRunway(
      doc([e(DateTime(2026, 10, 26), -10000.40, need: 'nezbytné')]),
      input(savings: 1500000, income: 10000),
    );
    expect(scenario(r, Scenario.essentialOnly).runwayMonths, isNull);
  });

  test('depletion date clamps day to month length', () {
    final r = calculateRunway(
      doc([e(DateTime(2026, 10, 26), -10000, need: 'nezbytné')]),
      RunwayInput(
        savings: 10000,
        newMonthlyIncome: 0,
        windowMonths: 12,
        includeUnexpected: false,
        today: DateTime(2027, 1, 31),
      ),
    );
    expect(scenario(r, Scenario.essentialOnly).depletionDate, DateTime(2027, 2, 28));
  });
}

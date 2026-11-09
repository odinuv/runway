import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:runway_app/data/entries_document.dart';
import 'package:runway_app/data/repository.dart';
import 'package:runway_app/state/app_state.dart';
import 'package:runway_app/ui/home_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

AppEntry expense(DateTime d, double kc, String need, String type) => AppEntry(
      date: d,
      amountCents: (kc * 100).round(),
      categoryKind: 'expense',
      expenseType: type,
      need: need,
    );

final twoMonths = EntriesDocument(
  initialBalance: 300000,
  updatedAt: '2026-11-09T10:00:00Z',
  entries: [
    expense(DateTime(2026, 9, 5), -20000, 'nezbytné', 'bydlení'),
    expense(DateTime(2026, 9, 6), -5000, 'zbytné', 'volný čas'),
    expense(DateTime(2026, 10, 26), -20000, 'nezbytné', 'bydlení'),
    expense(DateTime(2026, 10, 27), -5000, 'zbytné', 'volný čas'),
  ],
  excludedTypes: const {},
);

Future<AppState> pumpHome(WidgetTester tester, EntriesDocument doc) async {
  final state = AppState(
    prefs: await SharedPreferences.getInstance(),
    loader: () async => Loaded(doc, fromCache: false),
    salt: '',
    hash: '',
    now: () => DateTime(2026, 11, 9),
  );
  await state.refresh();
  tester.view.physicalSize = const Size(1080, 4000);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: HomeScreen(state: state)));
  return state;
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('cs');
    Intl.defaultLocale = 'cs';
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('shows three scenario cards with runway', (tester) async {
    await pumpHome(tester, twoMonths);
    expect(find.text('Utrácíme jako dosud'), findsOneWidget);
    expect(find.text('Bez zbytných'), findsOneWidget);
    expect(find.text('Jen nezbytné'), findsOneWidget);
    // jako dosud 300 000 / 25 000 = 12 měsíců, bez zbytných i jen nezbytné 300 000 / 20 000 = 15 měsíců
    expect(find.text('12,0 měs.'), findsOneWidget);
    expect(find.text('15,0 měs.'), findsNWidgets(2));
    expect(find.text('do listopadu 2027'), findsOneWidget);
    expect(find.text('do února 2028'), findsNWidgets(2));
  });

  testWidgets('income above limit is clamped and covers spend', (tester) async {
    final state = await pumpHome(tester, twoMonths);
    await tester.enterText(find.byKey(const Key('incomeField')), '200000');
    await tester.pump();
    expect(state.newIncome, 100000);
    expect(find.text('∞ – vystačí'), findsNWidgets(3));
  });

  testWidgets('cleared income field stays empty while typing', (tester) async {
    final state = await pumpHome(tester, twoMonths);
    final field = find.byKey(const Key('incomeField'));
    await tester.enterText(field, '5000');
    await tester.pump();
    await tester.enterText(field, '');
    await tester.pump();
    expect(state.newIncome, 0);
    expect(tester.widget<TextField>(field).controller!.text, '');
  });

  testWidgets('tapping card shows breakdown', (tester) async {
    await pumpHome(tester, twoMonths);
    expect(find.text('volný čas'), findsNothing);
    await tester.tap(find.text('Utrácíme jako dosud'));
    await tester.pump();
    expect(find.text('volný čas'), findsOneWidget);
  });

  testWidgets('no data in window', (tester) async {
    await pumpHome(
      tester,
      const EntriesDocument(initialBalance: 0, updatedAt: null, entries: [], excludedTypes: {}),
    );
    expect(find.text('Žádná data v období'), findsOneWidget);
    expect(find.text('Utrácíme jako dosud'), findsNothing);
  });
}

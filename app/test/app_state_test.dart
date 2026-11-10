import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runway_app/data/entries_document.dart';
import 'package:runway_app/data/repository.dart';
import 'package:runway_app/state/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

final hash = sha256.convert(utf8.encode('saltheslo')).toString();

const doc = EntriesDocument(
  initialBalance: 420000,
  updatedAt: '2026-11-09T10:00:00Z',
  entries: [],
  excludedTypes: {},
);

Future<AppState> newState({Future<LoadResult> Function()? loader}) async => AppState(
      prefs: await SharedPreferences.getInstance(),
      loader: loader ?? () async => const Loaded(doc, fromCache: false),
      salt: 'salt',
      hash: hash,
      now: () => DateTime(2026, 11, 9),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('defaults', () async {
    final s = await newState();
    expect(s.loggedIn, isFalse);
    expect(s.newIncome, 0);
    expect(s.windowMonths, 12);
    expect(s.includeUnexpected, isFalse);
    expect(s.result, isNull);
  });

  test('income is clamped', () async {
    final s = await newState();
    s.setNewIncome(-5);
    expect(s.newIncome, 0);
    s.setNewIncome(250000);
    expect(s.newIncome, 100000);
  });

  test('settings survive restart', () async {
    final s = await newState();
    s.setNewIncome(15000);
    s.setWindow(6);
    s.setIncludeUnexpected(true);
    s.setSavings(300000);
    final again = await newState();
    expect(again.newIncome, 15000);
    expect(again.windowMonths, 6);
    expect(again.includeUnexpected, isTrue);
    expect(again.savingsOverride, 300000);
  });

  test('invalid window ignored', () async {
    final s = await newState();
    s.setWindow(5);
    expect(s.windowMonths, 12);
  });

  test('savings default to initialBalance, override can be reset', () async {
    final s = await newState();
    await s.refresh();
    expect(s.savings, 420000);
    s.setSavings(100000);
    expect(s.savings, 100000);
    s.setSavings(null);
    expect(s.savings, 420000);
    s.setSavings(-1);
    expect(s.savings, 0);
  });

  test('login checks password and persists', () async {
    final s = await newState();
    expect(s.login('spatne'), isFalse);
    expect(s.loggedIn, isFalse);
    expect(s.login('heslo'), isTrue);
    expect((await newState()).loggedIn, isTrue);
    s.logout();
    expect((await newState()).loggedIn, isFalse);
  });

  test('result computed after refresh', () async {
    final s = await newState();
    await s.refresh();
    expect(s.load, isA<Loaded>());
    expect(s.result, isNotNull);
    expect(s.result!.hasData, isFalse);
  });
}

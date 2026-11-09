import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:runway_app/data/entries_document.dart';

Map<String, dynamic> specExample() => jsonDecode('''
{
  "version": 1,
  "initialBalance": 420000,
  "initialBalanceCurrency": "CZK",
  "updatedAt": "2026-11-09T10:00:00Z",
  "modelConfig": {"excludedTypes": ["spoření a investice"]},
  "entries": [
    {
      "id": "abc",
      "date": "2024-01-04",
      "amount": -1535.00,
      "currency": "CZK",
      "ownAccount": "1234567890",
      "counterAccount": "107-2000145399",
      "counterBankCode": "0100",
      "message": "",
      "note": "Elektřina doplatek",
      "type": "Okamžitá odchozí platba",
      "source": {"format": "fio-csv", "file": "pohyby.csv"},
      "category": {"kind": "expense", "type": "energie", "need": "nezbytné", "model": "m", "categorizedAt": "t"}
    },
    {
      "id": "def",
      "date": "2024-01-10",
      "amount": 60000.5,
      "category": {"kind": "income", "incomeType": "pravidelný"}
    }
  ]
}
''') as Map<String, dynamic>;

void main() {
  test('parses spec example', () {
    final doc = EntriesDocument.fromJson(specExample());
    expect(doc.initialBalance, 420000);
    expect(doc.updatedAt, '2026-11-09T10:00:00Z');
    expect(doc.entries, hasLength(2));
    final e = doc.entries.first;
    expect(e.date, DateTime(2024, 1, 4));
    expect(e.amountCents, -153500);
    expect(e.currency, 'CZK');
    expect(e.categoryKind, 'expense');
    expect(e.expenseType, 'energie');
    expect(e.need, 'nezbytné');
    final income = doc.entries.last;
    expect(income.amountCents, 6000050);
    expect(income.incomeType, 'pravidelný');
    expect(income.currency, 'CZK');
  });

  test('tolerates null category and missing modelConfig', () {
    final raw = specExample()
      ..remove('modelConfig')
      ..remove('updatedAt');
    (raw['entries'] as List).first['category'] = null;
    final doc = EntriesDocument.fromJson(raw);
    expect(doc.excludedTypes, isEmpty);
    expect(doc.updatedAt, isNull);
    expect(doc.entries.first.categoryKind, isNull);
    expect(doc.entries.first.need, isNull);
  });

  test('reads excludedTypes', () {
    expect(EntriesDocument.fromJson(specExample()).excludedTypes, {'spoření a investice'});
  });

  test('missing initialBalance and entries default to empty', () {
    final doc = EntriesDocument.fromJson({'version': 1});
    expect(doc.initialBalance, 0);
    expect(doc.entries, isEmpty);
  });
}

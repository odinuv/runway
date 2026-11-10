/// Záznam z `entries.json` – jen pole, která appka potřebuje k výpočtu.
class AppEntry {
  const AppEntry({
    required this.date,
    required this.amountCents,
    this.currency = 'CZK',
    this.categoryKind,
    this.expenseType,
    this.need,
    this.incomeType,
  });

  factory AppEntry.fromJson(Map<String, dynamic> json) {
    final category = json['category'] as Map<String, dynamic>?;
    return AppEntry(
      date: DateTime.parse(json['date'] as String),
      amountCents: ((json['amount'] as num) * 100).round(),
      currency: json['currency'] as String? ?? 'CZK',
      categoryKind: category?['kind'] as String?,
      expenseType: category?['type'] as String?,
      need: category?['need'] as String?,
      incomeType: category?['incomeType'] as String?,
    );
  }

  final DateTime date;
  final int amountCents;
  final String currency;
  final String? categoryKind;
  final String? expenseType;
  final String? need;
  final String? incomeType;
}

/// Obsah `entries.json` z kontejneru `app`.
class EntriesDocument {
  const EntriesDocument({
    required this.initialBalance,
    required this.updatedAt,
    required this.entries,
    required this.excludedTypes,
  });

  factory EntriesDocument.fromJson(Map<String, dynamic> json) {
    final modelConfig = json['modelConfig'] as Map<String, dynamic>?;
    return EntriesDocument(
      initialBalance: (json['initialBalance'] as num? ?? 0).toDouble(),
      updatedAt: json['updatedAt'] as String?,
      entries: [
        for (final e in json['entries'] as List? ?? const [])
          AppEntry.fromJson(e as Map<String, dynamic>),
      ],
      excludedTypes: {
        for (final t in modelConfig?['excludedTypes'] as List? ?? const []) t as String,
      },
    );
  }

  final double initialBalance;
  final String? updatedAt;
  final List<AppEntry> entries;
  final Set<String> excludedTypes;
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/repository.dart';
import '../domain/runway_calculator.dart';
import '../state/app_state.dart';
import 'format.dart';
import 'scenario_card.dart';

/// Hlavní obrazovka podle mockupu A: vstupy nahoře, pod nimi tři karty scénářů.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.state});

  final AppState state;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _income = TextEditingController();
  final _savings = TextEditingController();

  AppState get state => widget.state;

  @override
  void initState() {
    super.initState();
    state.addListener(_syncFields);
    _syncFields();
  }

  @override
  void dispose() {
    state.removeListener(_syncFields);
    _income.dispose();
    _savings.dispose();
    super.dispose();
  }

  /// Přepíše pole jen tehdy, když jejich hodnota neodpovídá stavu (posuvník, oříznutí, reset).
  void _syncFields() {
    _sync(_income, state.newIncome);
    _sync(_savings, state.savings);
  }

  void _sync(TextEditingController controller, double value) {
    if (double.tryParse(controller.text) != value) {
      controller.text = value.round().toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: const Text('Runway'),
          actions: [
            IconButton(
              tooltip: 'Obnovit data',
              icon: const Icon(Icons.refresh),
              onPressed: state.loading ? null : state.refresh,
            ),
            IconButton(tooltip: 'Odhlásit', icon: const Icon(Icons.logout), onPressed: state.logout),
          ],
        ),
        body: RefreshIndicator(onRefresh: state.refresh, child: _body(context)),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final load = state.load;
    if (load == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (load is LoadFailed) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 80),
          Text(load.message, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          Center(child: FilledButton(onPressed: state.refresh, child: const Text('Zkusit znovu'))),
        ],
      );
    }
    final loaded = load as Loaded;
    final result = state.result!;
    final numbers = [FilteringTextInputFormatter.digitsOnly];

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (loaded.warning != null || loaded.doc.updatedAt != null)
            _Banner(warning: loaded.warning, updatedAt: loaded.doc.updatedAt),
          Row(
            children: [
              const Expanded(child: Text('Nový příjem / měs.')),
              SizedBox(
                width: 130,
                child: TextField(
                  key: const Key('incomeField'),
                  controller: _income,
                  keyboardType: TextInputType.number,
                  inputFormatters: numbers,
                  textAlign: TextAlign.end,
                  decoration: const InputDecoration(suffixText: 'Kč', isDense: true),
                  onChanged: (v) => state.setNewIncome(double.tryParse(v) ?? 0),
                ),
              ),
            ],
          ),
          Slider(
            value: state.newIncome,
            max: maxIncome,
            divisions: 100,
            label: formatKc(state.newIncome),
            onChanged: state.setNewIncome,
          ),
          Row(
            children: [
              const Expanded(child: Text('Úspory')),
              SizedBox(
                width: 130,
                child: TextField(
                  key: const Key('savingsField'),
                  controller: _savings,
                  keyboardType: TextInputType.number,
                  inputFormatters: numbers,
                  textAlign: TextAlign.end,
                  decoration: const InputDecoration(suffixText: 'Kč', isDense: true),
                  onChanged: (v) => state.setSavings(double.tryParse(v) ?? 0),
                ),
              ),
              IconButton(
                tooltip: 'Výchozí úspory z dat',
                icon: const Icon(Icons.restart_alt),
                onPressed: state.savingsOverride == null ? null : () => state.setSavings(null),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text('Průměr výdajů za'),
          const SizedBox(height: 6),
          SegmentedButton<int>(
            segments: [
              for (final m in windowOptions) ButtonSegment(value: m, label: Text('$m m')),
            ],
            selected: {state.windowMonths},
            showSelectedIcon: false,
            onSelectionChanged: (s) => state.setWindow(s.first),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Započítat nečekané výdaje'),
            value: state.includeUnexpected,
            onChanged: state.setIncludeUnexpected,
          ),
          if (result.hasData)
            Text('Dosavadní pravidelný příjem: ${formatKc(result.regularMonthlyIncome)}/měs.'),
          const SizedBox(height: 8),
          if (!result.hasData)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Text('Žádná data v období', textAlign: TextAlign.center),
            )
          else
            for (final s in result.scenarios) ScenarioCard(result: s),
          const SizedBox(height: 8),
          ..._notes(result).map((n) => Text(n, style: Theme.of(context).textTheme.bodySmall)),
        ],
      ),
    );
  }

  List<String> _notes(RunwayResult r) => [
        if (r.hasData)
          'Průměr z ${r.monthsWithData} měsíců s daty'
              '${r.monthsWithData < r.windowMonths ? ' (méně než zvolených ${r.windowMonths})' : ''}.',
        if (r.uncategorizedCount > 0) 'Nezařazených výdajů: ${r.uncategorizedCount} (počítají se jako nezbytné).',
        if (r.nonCzkCount > 0) 'Záznamů v jiné měně než CZK (nezapočítány): ${r.nonCzkCount}.',
      ];
}

class _Banner extends StatelessWidget {
  const _Banner({required this.warning, required this.updatedAt});

  final String? warning;
  final String? updatedAt;

  @override
  Widget build(BuildContext context) {
    final updated = updatedAt == null ? null : DateTime.tryParse(updatedAt!)?.toLocal();
    final parts = [
      ?warning,
      if (updated != null) 'Data k ${updated.day}. ${updated.month}. ${updated.year}',
    ];
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: warning == null
            ? Theme.of(context).colorScheme.surfaceContainerHighest
            : Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(parts.join(' · ')),
    );
  }
}

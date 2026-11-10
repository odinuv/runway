import 'package:flutter/material.dart';

import '../domain/runway_calculator.dart';
import 'format.dart';

const scenarioLabels = {
  Scenario.asUsual: 'Utrácíme jako dosud',
  Scenario.withoutDiscretionary: 'Bez zbytných',
  Scenario.essentialOnly: 'Jen nezbytné',
};

const scenarioColors = {
  Scenario.asUsual: Color(0xFFC0504D),
  Scenario.withoutDiscretionary: Color(0xFFD89A2B),
  Scenario.essentialOnly: Color(0xFF4A9A5A),
};

/// Barevná karta scénáře; klepnutím se rozbalí měsíční výdaje podle typu.
class ScenarioCard extends StatefulWidget {
  const ScenarioCard({super.key, required this.result});

  final ScenarioResult result;

  @override
  State<ScenarioCard> createState() => _ScenarioCardState();
}

class _ScenarioCardState extends State<ScenarioCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final r = widget.result;
    const white = TextStyle(color: Colors.white);
    final dimmed = TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13);
    final months = r.runwayMonths;
    final byType = r.monthlyByType.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    return Card(
      color: scenarioColors[r.scenario],
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => _expanded = !_expanded),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(scenarioLabels[r.scenario]!, style: dimmed)),
                  Text('${formatKc(r.monthlySpend)}/měs.', style: dimmed),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                months == null ? '∞ – vystačí' : formatMonths(months),
                style: white.copyWith(fontSize: 28, fontWeight: FontWeight.w700),
              ),
              if (r.depletionDate != null) Text(formatUntil(r.depletionDate!), style: dimmed),
              if (_expanded) ...[
                const Divider(color: Colors.white54),
                for (final item in byType)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 1),
                    child: Row(
                      children: [
                        Expanded(child: Text(item.key, style: white)),
                        Text(formatKc(item.value), style: white),
                      ],
                    ),
                  ),
                if (byType.isEmpty) Text('Žádné výdaje', style: dimmed),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../analysis.dart';
import '../../app_state.dart';
import '../../calc.dart';
import '../../models.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// Repetibilidade e estatísticas (tela 8): média, desvio padrão e
/// coeficiente de variação de mA, tempo e mAs.
class StatsTab extends StatefulWidget {
  final AppState state;
  const StatsTab({super.key, required this.state});

  @override
  State<StatsTab> createState() => _StatsTabState();
}

class _StatsTabState extends State<StatsTab> {
  bool includeSimulated = false;
  bool allSessions = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    var list = allSessions ? s.readings : s.sessionReadings;
    if (!includeSimulated) list = list.where((r) => !r.isDemo).toList();
    // Repetibilidade só faz sentido no mesmo SET: agrupa pelo SET mais recente.
    final ref = list.isEmpty ? null : list.first;
    final sameSet = ref == null ? <Reading>[] : list.where((r) => r.setMa == ref.setMa && r.setMs == ref.setMs).toList();
    final ma = stats(sameSet.map((r) => r.readMa));
    final ms = stats(sameSet.map((r) => r.readMs));
    final mas = stats(sameSet.map((r) => r.readMas));
    final err = stats(sameSet.map((r) => s.evalOf(r).errMas ?? double.nan));
    final limit = s.settings.cvLimitPct;

    Widget row(String name, String unit, Stats? st) {
      final cv = st?.cvPct;
      final ok = cv == null ? null : cv <= limit;
      final color = ok == null ? XColors.gray : (ok ? XColors.ok : XColors.fail);
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Expanded(
              flex: 3,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Colors.white)),
                Text('n = ${st?.n ?? 0}', style: const TextStyle(color: XColors.gray)),
              ]),
            ),
            Expanded(
              flex: 4,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Média ${fmt(st?.mean, 2)} $unit', style: const TextStyle(fontSize: 15)),
                Text('DP ${fmt(st?.sd, 3)} • mín ${fmt(st?.min, 2)} • máx ${fmt(st?.max, 2)}',
                    style: const TextStyle(color: XColors.gray, fontSize: 12)),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              const Text('CV', style: TextStyle(color: XColors.gray)),
              Text(cv == null ? '—' : '${fmt(cv, 2)} %',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: color)),
            ]),
          ]),
        ),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(spacing: 8, runSpacing: 8, children: [
        FilterChip(
          label: const Text('Todas as sessões'),
          selected: allSessions,
          onSelected: (v) => setState(() => allSessions = v),
        ),
        FilterChip(
          label: const Text('Incluir simuladas'),
          selected: includeSimulated,
          selectedColor: XColors.demo.withValues(alpha: 0.3),
          onSelected: (v) => setState(() => includeSimulated = v),
        ),
      ]),
      const SizedBox(height: 10),
      if (ref == null)
        const Card(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Text('Sem medições para calcular a repetibilidade. Faça pelo menos 2 disparos com o mesmo SET.'),
          ),
        )
      else ...[
        Text(
          'SET ${fmtTrim(ref.setMa)} mA × ${fmtTrim(ref.setMs)} ms = ${fmt(ref.setMas)} mAs • '
          '${sameSet.length} disparo(s) com este SET'
          '${includeSimulated && sameSet.any((r) => r.isDemo) ? ' • INCLUI SIMULADOS' : ''}',
          style: const TextStyle(color: XColors.gray),
        ),
        const SizedBox(height: 8),
        row('Corrente (mA)', 'mA', ma),
        const SizedBox(height: 8),
        row('Tempo (ms)', 'ms', ms),
        const SizedBox(height: 8),
        row('mAs', 'mAs', mas),
        const SizedBox(height: 10),
        Text(
          'Erro médio do mAs em relação ao SET: ${fmtSigned(err?.mean)} % '
          '(DP ${fmt(err?.sd, 2)} %). Limite de CV configurado: ${fmt(limit, 1)} % (Configurações).',
          style: const TextStyle(color: XColors.gray),
        ),
        if (sameSet.length < 2)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('O coeficiente de variação exige pelo menos 2 disparos.', style: TextStyle(color: XColors.warn)),
          ),
        const SizedBox(height: 10),
        const SectionTitle('Disparos usados'),
        for (final r in sameSet.take(30))
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              '${r.isDemo ? '[${r.sourceLabel}] ' : ''}${fmtDateTime(r.when)} • ${fmt(r.readMa, 1)} mA • '
              '${fmt(r.readMs, 2)} ms • ${fmt(r.readMas, 3)} mAs',
              style: const TextStyle(fontSize: 13),
            ),
          ),
      ],
    ]);
  }
}

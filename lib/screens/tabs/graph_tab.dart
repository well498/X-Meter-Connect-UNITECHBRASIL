import 'dart:math';

import 'package:flutter/material.dart';

import '../../analysis.dart';
import '../../app_state.dart';
import '../../calc.dart';
import '../../models.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/wave_chart.dart';
import 'measure_tab.dart';

/// Gráficos das exposições (tela 6): ampliação, navegação e comparação de
/// até 4 disparos sobrepostos, com análise do início e do fim da exposição.
class GraphTab extends StatefulWidget {
  final AppState state;
  const GraphTab({super.key, required this.state});

  @override
  State<GraphTab> createState() => _GraphTabState();
}

class _GraphTabState extends State<GraphTab> {
  final selected = <String>[];

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final withWave = s.readings.where((r) => r.waveform != null).take(30).toList();
    if (withWave.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Text('Nenhuma forma de onda registrada para este equipamento. Ela aparece quando o instrumento '
              '(ou o modo demonstração) envia as amostras de corrente.'),
        ),
      );
    }
    selected.removeWhere((uid) => !withWave.any((r) => r.uid == uid));
    if (selected.isEmpty) selected.add(withWave.first.uid);
    final chosen = [for (final uid in selected) withWave.firstWhere((r) => r.uid == uid)];
    final series = [
      for (var i = 0; i < chosen.length; i++)
        WaveSeries(chosen[i].waveform!, XColors.series[i % XColors.series.length], '#${i + 1} ${fmt(chosen[i].readMas)} mAs'),
    ];
    final h = MediaQuery.sizeOf(context).height;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 10, 10, 6),
          child: SizedBox(
            height: max(300.0, h * 0.42),
            child: () {
              final w = chosen.first.waveform!;
              final d = chosen.length == 1
                  ? diagnoseWave(uniformTimes(w.ma.length, w.samplePeriodUs), w.ma,
                      cfg: s.detection, setMa: chosen.first.setMa)
                  : null;
              return WaveChart(
                series: series,
                referenceMa: chosen.first.setMa,
                markers: diagMarkers(d),
                plateauMa: d?.plateauMa,
              );
            }(),
          ),
        ),
      ),
      const SizedBox(height: 6),
      const Text('Pinça ou botões ampliam o tempo • arraste para navegar • toque duplo volta à visão completa. '
          'Tracejado cinza: mA SET • linha verde: patamar • marcas: início, fim e picos (com 1 disparo selecionado).',
          style: TextStyle(color: XColors.gray, fontSize: 12)),
      const SizedBox(height: 12),
      for (var i = 0; i < chosen.length; i++) _analysis(chosen[i], XColors.series[i % XColors.series.length], s),
      const SectionTitle('Comparar disparos (até 4)'),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final r in withWave)
          FilterChip(
            label: Text(shotLabel(r), style: const TextStyle(fontSize: 12)),
            selected: selected.contains(r.uid),
            onSelected: (v) => setState(() {
              if (v) {
                if (selected.length >= 4) selected.removeAt(0);
                selected.add(r.uid);
              } else if (selected.length > 1) {
                selected.remove(r.uid);
              }
            }),
          ),
      ]),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: () async {
          try {
            final path = await s.exportWaveformCsv(chosen.first);
            await s.shareFile(path, 'Forma de onda ${chosen.first.shotId}');
          } catch (e) {
            if (context.mounted) showSnack(context, 'Falha ao exportar: $e');
          }
        },
        icon: const Icon(Icons.ios_share),
        label: const Text('Exportar forma de onda (CSV)'),
      ),
    ]);
  }

  /// Comportamento inicial/final e oscilação do disparo, calculados pelo
  /// mesmo algoritmo do firmware.
  Widget _analysis(Reading r, Color color, AppState s) {
    final w = r.waveform!;
    final t = uniformTimes(w.ma.length, w.samplePeriodUs);
    final ex = detectExposure(t, w.ma, cfg: s.detection);
    String txt;
    if (!ex.valid && ex.timeMs == 0) {
      txt = 'Exposição não detectada na forma de onda armazenada.';
    } else {
      // Subida/descida 10–90 % e ondulação no platô (desvio padrão / média).
      final peak = ex.peakMa - ex.baselineMa;
      double? edge(bool rising) {
        final lo = ex.baselineMa + 0.1 * peak, hi = ex.baselineMa + 0.9 * peak;
        int? a, b;
        if (rising) {
          for (var i = 0; i < w.ma.length; i++) {
            if (a == null && w.ma[i] >= lo) a = i;
            if (w.ma[i] >= hi) {
              b = i;
              break;
            }
          }
        } else {
          for (var i = w.ma.length - 1; i >= 0; i--) {
            if (a == null && w.ma[i] >= lo) a = i;
            if (w.ma[i] >= hi) {
              b = i;
              break;
            }
          }
        }
        if (a == null || b == null) return null;
        return (t[b] - t[a]).abs();
      }

      final i0 = ex.startIndex + (ex.endIndex - ex.startIndex) ~/ 10;
      final i1 = ex.endIndex - (ex.endIndex - ex.startIndex) ~/ 10;
      final plateau = i1 > i0 ? stats(w.ma.sublist(i0, i1)) : null;
      txt = 'Tempo ${fmt(ex.timeMs, 2)} ms • mAs ${fmt(ex.mas, 3)} • média ${fmt(ex.meanMa, 1)} mA • '
          'máx. ${fmt(ex.peakMa, 1)} mA\n'
          'Subida 10–90 %: ${fmt(edge(true), 2)} ms • descida: ${fmt(edge(false), 2)} ms • '
          'ondulação no platô: ${fmt(plateau?.cvPct, 1)} %'
          '${ex.flags.isEmpty ? '' : '\nAtenção: ${ex.flags.map((f) => f.label).join(', ')}'}';
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(width: 6, height: 44, color: color, margin: const EdgeInsets.only(right: 10, top: 2)),
        Expanded(child: Text('${shotLabel(r)}\n$txt', style: const TextStyle(fontSize: 13))),
      ]),
    );
  }
}

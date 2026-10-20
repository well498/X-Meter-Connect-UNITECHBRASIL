import 'package:flutter/material.dart';

import '../../analysis.dart';
import '../../app_state.dart';
import '../../calc.dart';
import '../../models.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/wave_chart.dart';

String qualityLabel(String code) {
  for (final f in ExposureFlag.values) {
    if (f.code == code) return f.label;
  }
  return switch (code) {
    'verificacao_mas_divergente' => 'mAs do instrumento difere > 2 % da integração da forma de onda',
    'fora_da_faixa' => 'FORA DA FAIXA do instrumento (valor registrado sem truncar; medição inválida)',
    _ => code.replaceAll('_', ' '),
  };
}

/// Resultados READ (tela 5) com a forma de onda do último disparo.
class MeasureTab extends StatelessWidget {
  final AppState state;
  const MeasureTab({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final s = state;
    final r = s.displayed;
    if (r == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(children: [
            Icon(s.connected ? Icons.hourglass_top : Icons.sensors_off, size: 44, color: XColors.gray),
            const SizedBox(height: 10),
            Text(
              s.settings.demoMode
                  ? 'MODO DEMONSTRAÇÃO: toque em "Simular medição" para gerar um disparo simulado.'
                  : s.connected
                      ? 'Toque em "Iniciar Medição" e faça a exposição no comando do gerador.'
                      : 'Instrumento desconectado. Nenhum valor READ é exibido sem medição real.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 14),
            const Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
              _Empty('mAs READ'),
              _Empty('Tempo'),
              _Empty('Corrente'),
            ]),
          ]),
        ),
      );
    }
    final ev = s.evalOf(r);
    final w = r.waveform;
    final diag = w == null
        ? null
        : diagnoseWave(uniformTimes(w.ma.length, w.samplePeriodUs), w.ma, cfg: s.detection, setMa: r.setMa);
    final tol = r.tolerances ?? s.tol;
    final color = r.isDemo ? XColors.demo : XColors.status(ev.status);
    final statusText = switch (ev.status) {
      MeasureStatus.approved => 'Dentro da tolerância',
      MeasureStatus.alert => 'Alerta',
      MeasureStatus.failed => 'Fora da tolerância',
      MeasureStatus.invalid => 'Medição inválida',
      MeasureStatus.unknown => 'Sem dados',
    };
    final readColor = r.isDemo ? XColors.demo : (ev.status == MeasureStatus.approved ? XColors.okText : color);

    final left = Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
      Text('mAs medido (READ)', style: TextStyle(color: readColor, fontSize: 16, fontWeight: FontWeight.w600)),
      FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(fmt(r.readMas),
            style: TextStyle(
                fontSize: 64,
                height: 1.1,
                fontWeight: FontWeight.w900,
                color: readColor,
                fontFeatures: const [FontFeature.tabularFigures()])),
      ),
      const Text('mAs', style: TextStyle(fontSize: 20, color: XColors.blueDark)),
    ]);

    final middle = Column(children: [
      const Text('Desvio', style: TextStyle(fontSize: 16, color: XColors.blueDark)),
      FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
          Text(fmtSigned(ev.errMas),
              style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: readColor)),
          const Text(' %', style: TextStyle(fontSize: 18, color: XColors.blueDark)),
        ]),
      ),
      const SizedBox(height: 6),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          border: Border.all(color: color),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(
              r.isDemo
                  ? Icons.science_outlined
                  : ev.status == MeasureStatus.approved
                      ? Icons.check_circle
                      : ev.status == MeasureStatus.alert
                          ? Icons.warning_amber_rounded
                          : Icons.cancel,
              color: color,
              size: 20),
          const SizedBox(width: 6),
          Flexible(
            child: Text(r.isDemo ? '${r.sourceLabel}\n$statusText' : statusText,
                textAlign: TextAlign.center,
                style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13)),
          ),
        ]),
      ),
    ]);

    Widget kv(String k, String v, String unit, double? err, double tolPct) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(k, style: const TextStyle(color: XColors.blueDark, fontSize: 14)),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                Text(v,
                    style: const TextStyle(
                        fontSize: 30, fontWeight: FontWeight.w800, color: Colors.white, fontFeatures: [FontFeature.tabularFigures()])),
                Text(' $unit', style: const TextStyle(fontSize: 15, color: XColors.blueDark)),
              ]),
            ),
            if (err != null)
              Text('${fmtSigned(err)} %',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: XColors.status(classifyError(err, tolPct, tol.alertFraction)))),
          ],
        );

    final right = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      kv('Tempo medido', fmtTime(r.readMs, seconds: s.settings.timeInSeconds),
          s.settings.timeInSeconds ? 's' : 'ms', ev.errMs, tol.msPct),
      const Divider(height: 18),
      kv('Corrente média', fmt(r.readMa, 1), 'mA', ev.errMa, tol.maPct),
      if (r.maPeak != null) ...[
        const Divider(height: 18),
        kv('Corrente máxima', fmt(r.maPeak, 1), 'mA', null, 0),
      ],
    ]);

    return Column(children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: LayoutBuilder(builder: (context, c) {
            if (c.maxWidth < 420) {
              return Column(children: [
                left,
                const SizedBox(height: 10),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: middle),
                  const SizedBox(width: 12),
                  Expanded(child: right),
                ]),
              ]);
            }
            return IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(flex: 4, child: left),
                const VerticalDivider(width: 20),
                Expanded(flex: 3, child: middle),
                const VerticalDivider(width: 20),
                Expanded(flex: 3, child: right),
              ]),
            );
          }),
        ),
      ),
      const SizedBox(height: 12),
      if (r.waveform != null)
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Expanded(
                  child: Text('Forma de onda da corrente',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
                ),
                Text('${r.waveform!.ma.length} pontos • ${fmt(r.waveform!.durationMs, 1)} ms',
                    style: const TextStyle(color: XColors.gray, fontSize: 12)),
              ]),
              SizedBox(
                height: 230,
                child: WaveChart(
                  markers: diagMarkers(diag),
                  plateauMa: diag?.plateauMa,
                  series: [WaveSeries(r.waveform!, r.isDemo ? XColors.demo : XColors.cyan, 'Disparo')],
                  referenceMa: r.setMa,
                ),
              ),
            ]),
          ),
        ),
      if (diag != null) ...[
        const SizedBox(height: 12),
        DiagnosticsCard(diag: diag, sawae: r.profileId == BuiltinProfiles.sawaeAltusId || s.profile?.id == BuiltinProfiles.sawaeAltusId),
      ],
      const SizedBox(height: 10),
      Builder(builder: (context) {
        final (lo, hi) = tol.masInterval(r.setMas);
        return Text(
          'Critério: ${tol.description}${tol.originText.isEmpty ? '' : ' — ${tol.originText}'}\n'
          'Aceitação do mAs para ${fmt(r.setMas)} mAs: ${fmt(lo)} a ${fmt(hi)} mAs'
          '${tol.maPct <= 0 || tol.msPct <= 0 ? '\nmA/tempo sem critério documentado: exibidos sem classificação.' : ''}',
          style: const TextStyle(color: XColors.gray, fontSize: 13),
        );
      }),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 6, children: [
        if (r.isDemo) DemoTag(label: r.sourceLabel),
        _chip(Icons.tag, 'Disparo ${r.shotId}'),
        _chip(Icons.access_time, fmtDateTime(r.when)),
        _chip(Icons.memory, r.isDemo ? r.deviceId : 'Instrumento ${r.deviceId}'),
        if (r.probeId != null) _chip(Icons.sensors, 'Sonda ${r.probeId}'),
        if (r.calStatus != null) _chip(Icons.verified_outlined, 'Calibração: ${r.calStatus}'),
        _chip(Icons.rule, 'mAs ${tol.masRule}'),
        for (final q in r.quality) _chip(Icons.warning_amber_rounded, qualityLabel(q), color: XColors.warn),
      ]),
      for (final n in s.notes.where((n) => n.readingUid == r.uid))
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(children: [
            const Icon(Icons.sticky_note_2_outlined, size: 18, color: XColors.gray),
            const SizedBox(width: 6),
            Expanded(child: Text('${fmtDateTime(n.at)} — ${n.text}', style: const TextStyle(color: XColors.gray))),
          ]),
        ),
    ]);
  }

  Widget _chip(IconData i, String t, {Color color = XColors.gray}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          border: Border.all(color: XColors.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(i, size: 14, color: color),
          const SizedBox(width: 4),
          Flexible(child: Text(t, style: TextStyle(fontSize: 12, color: color))),
        ]),
      );
}

class _Empty extends StatelessWidget {
  final String label;
  const _Empty(this.label);
  @override
  Widget build(BuildContext context) => Column(children: [
        Text(label, style: const TextStyle(color: XColors.gray)),
        const Text('—', style: TextStyle(fontSize: 36, fontWeight: FontWeight.w800, color: XColors.gray)),
      ]);
}

/// Reaproveitado por outras abas.
String shotLabel(Reading r) => '${r.isDemo ? '[${r.sourceLabel}] ' : ''}${fmtDateTime(r.when)} • ${fmt(r.readMas)} mAs';


/// Marcas de início, fim, pico inicial e pico máximo para o gráfico.
List<ChartMarker> diagMarkers(WaveDiagnostics? d) => d == null
    ? const []
    : [
        ChartMarker(d.startMs, 'início', XColors.okText),
        ChartMarker(d.endMs, 'fim', XColors.fail),
        ChartMarker(d.initialPeakTimeMs, 'pico inicial', XColors.warn, ma: d.initialPeakMa),
        if ((d.peakTimeMs - d.initialPeakTimeMs).abs() > 0.001)
          ChartMarker(d.peakTimeMs, 'máx.', XColors.cyan, ma: d.peakMa),
      ];

/// Indicadores da forma de onda — observações, nunca comandos de ajuste.
class DiagnosticsCard extends StatelessWidget {
  final WaveDiagnostics diag;
  final bool sawae;
  const DiagnosticsCard({super.key, required this.diag, this.sawae = false});

  @override
  Widget build(BuildContext context) {
    Widget item(String k, String v) => SizedBox(
          width: 150,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(k, style: const TextStyle(color: XColors.gray, fontSize: 12)),
            Text(v, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
          ]),
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Diagnóstico da forma de onda',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
          const SizedBox(height: 8),
          Wrap(spacing: 12, runSpacing: 10, children: [
            item('Pico inicial', '${fmt(diag.initialPeakMa, 1)} mA (${fmtSigned(diag.overshootPct, 1)} %)'),
            item('Corrente no patamar', '${fmt(diag.plateauMa, 1)} mA'),
            item('Oscilação (CV)', '${fmt(diag.rippleCvPct, 2)} %'),
            item('Estabilidade', '${fmtSigned(diag.driftPct, 2)} %'),
            item('Tempo efetivo', '${fmt(diag.timeMs, 2)} ms'),
            item('mAs integrado', fmt(diag.mas, 3)),
          ]),
          if (diag.observations.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (final o in diag.observations)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.info_outline, size: 16, color: XColors.warn),
                  const SizedBox(width: 6),
                  Expanded(child: Text(o, style: const TextStyle(fontSize: 13))),
                ]),
              ),
          ],
          if (sawae) ...[
            const SizedBox(height: 6),
            const Text(
              'Referência do manual SAWAE ALTUS: a referência de PREPARO influencia o comportamento inicial e '
              'o pico de partida; a referência de DISPARO influencia a amplitude da corrente durante a exposição e o mAs.',
              style: TextStyle(color: XColors.gray, fontSize: 12),
            ),
          ],
          const SizedBox(height: 6),
          const Text('Indicadores para avaliação técnica. O aplicativo não envia ajustes ao gerador.',
              style: TextStyle(color: XColors.gray, fontSize: 11, fontStyle: FontStyle.italic)),
        ]),
      ),
    );
  }
}

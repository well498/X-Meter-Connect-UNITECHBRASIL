import 'package:flutter/material.dart';

import '../app_state.dart';
import '../calc.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'waveform_page.dart';

/// Painel principal de leitura (READ), priorizando números grandes.
class ReadPage extends StatelessWidget {
  final AppState state;
  final void Function(int) goTo;
  const ReadPage({super.key, required this.state, required this.goTo});

  @override
  Widget build(BuildContext context) {
    final s = state;
    final ses = s.session;
    final r = s.latest;
    final ev = r == null ? null : s.evalOf(r);
    final tol = s.tol;

    Color accentFor(double? err, double tolPct) =>
        XColors.status(classifyError(err, tolPct, tol.alertFraction));

    return PageBody(children: [
      SectionTitle('Painel de medições — ${s.selected?.title ?? ''}',
          trailing: Text('${s.sessionReadings.length} disparo(s)',
              style: const TextStyle(color: XColors.gray, fontWeight: FontWeight.w600))),
      if (r == null)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(children: [
              Icon(s.connected ? Icons.hourglass_top : Icons.wifi_off, size: 48, color: XColors.gray),
              const SizedBox(height: 10),
              Text(
                s.connected
                    ? 'Aguardando medição do instrumento ${s.deviceId}…'
                    : 'Instrumento desconectado. Nenhum valor READ é exibido sem medição real.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18),
              ),
              const SizedBox(height: 14),
              ResponsiveGrid(minTileWidth: 200, children: [
                BigValueTile(label: 'mA READ', value: '—', unit: 'mA', footer: 'SET ${fmt(ses?.setMa, 0)} mA'),
                BigValueTile(label: 'Tempo READ', value: '—', unit: 'ms', footer: 'SET ${fmt(ses?.setMs, 0)} ms'),
                BigValueTile(label: 'mAs READ', value: '—', unit: 'mAs', footer: 'SET ${fmt(ses?.setMas)} mAs'),
              ]),
            ]),
          ),
        )
      else ...[
        Row(children: [
          Expanded(child: StatusBadge(ev!.status, large: true)),
          if (r.isDemo) ...[const SizedBox(width: 10), DemoTag(label: r.sourceLabel)],
        ]),
        const SizedBox(height: 12),
        ResponsiveGrid(minTileWidth: 220, children: [
          BigValueTile(
            label: 'mA READ',
            value: fmt(r.readMa, 1),
            unit: 'mA',
            footer: 'SET ${fmt(r.setMa, 0)} • erro ${fmtSigned(ev.errMa)} %',
            accent: accentFor(ev.errMa, tol.maPct),
          ),
          BigValueTile(
            label: 'Tempo READ',
            value: fmt(r.readMs, 1),
            unit: 'ms',
            footer: 'SET ${fmt(r.setMs, 0)} • erro ${fmtSigned(ev.errMs)} %',
            accent: accentFor(ev.errMs, tol.msPct),
          ),
          BigValueTile(
            label: 'mAs READ (integrado)',
            value: fmt(r.readMas),
            unit: 'mAs',
            footer: 'SET ${fmt(r.setMas)} • erro ${fmtSigned(ev.errMas)} %',
            accent: accentFor(ev.errMas, tol.masPct),
          ),
        ]),
        const SizedBox(height: 10),
        Text(
          '${r.isDemo ? '${r.sourceLabel} (não é medição real)' : 'Instrumento ${r.deviceId}'} • disparo ${r.shotId} • '
          '${fmtDateTime(r.when)}',
          style: const TextStyle(color: XColors.gray),
        ),
        if (r.waveform != null) ...[
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: SizedBox(height: 180, child: WaveformChart(reading: r)),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(onPressed: () => goTo(4), child: const Text('Ver forma de onda ampliada')),
          ),
        ],
      ],
      const SizedBox(height: 16),
      Wrap(spacing: 10, runSpacing: 10, children: [
        FilledButton.icon(
          onPressed: s.connected ? s.syncNow : s.connect,
          icon: Icon(s.connected ? Icons.sync : Icons.wifi),
          label: Text(s.connected ? 'Sincronizar agora' : 'Conectar ao instrumento'),
        ),
        if (s.settings.demoMode)
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: XColors.demo),
            onPressed: s.generateDemoShot,
            icon: const Icon(Icons.science_outlined),
            label: const Text('Simular disparo (DEMONSTRAÇÃO)'),
          ),
      ]),
      const SizedBox(height: 10),
      Text(
        'Tolerâncias: mA ±${fmt(tol.maPct, 1)} % • tempo ±${fmt(tol.msPct, 1)} % • '
        'mAs ±${fmt(tol.masPct, 1)} % • alerta a partir de ${fmt(tol.alertFraction * 100, 0)} % da tolerância',
        style: const TextStyle(color: XColors.gray),
      ),
    ]);
  }
}

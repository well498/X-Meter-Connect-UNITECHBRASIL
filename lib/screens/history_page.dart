import 'package:flutter/material.dart';

import '../app_state.dart';
import '../calc.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';

enum _Filter { all, real, demo }

class HistoryPage extends StatefulWidget {
  final AppState state;
  const HistoryPage({super.key, required this.state});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  _Filter filter = _Filter.all;
  bool onlySession = false;

  void _details(Reading r) {
    final ev = widget.state.evalOf(r);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(children: [
          const Expanded(child: Text('Detalhes da medição')),
          if (r.isDemo) DemoTag(label: r.sourceLabel),
        ]),
        content: SingleChildScrollView(
          child: SelectableText([
            'ID único: ${r.uid}',
            'Origem: ${r.isDemo ? '${r.sourceLabel} (simulado, não é medição real)' : 'Instrumento ${r.deviceId}'}',
            'Disparo: ${r.shotId}',
            'Sessão: ${r.sessionId}',
            'Data/hora da medição: ${fmtDateTime(r.recordedAt)}',
            'Recebida no aparelho: ${fmtDateTime(r.receivedAt)}',
            '',
            'mA: SET ${fmt(r.setMa)} • READ ${fmt(r.readMa)} • erro ${fmtSigned(ev.errMa)} %',
            'ms: SET ${fmt(r.setMs)} • READ ${fmt(r.readMs)} • erro ${fmtSigned(ev.errMs)} %',
            'mAs: SET ${fmt(r.setMas)} • READ ${fmt(r.readMas)} • erro ${fmtSigned(ev.errMas)} %',
            'Resultado: ${r.isDemo ? 'SIMULADO' : ev.status.label}',
            'Forma de onda: ${r.waveform == null ? 'não recebida' : '${r.waveform!.ma.length} amostras'}',
          ].join('\n')),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fechar'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    var list = s.readings;
    if (onlySession) list = list.where((r) => r.sessionId == s.session?.id).toList();
    if (filter == _Filter.real) list = list.where((r) => !r.isDemo).toList();
    if (filter == _Filter.demo) list = list.where((r) => r.isDemo).toList();
    final sessions = s.readings.map((r) => r.sessionId).toSet().length;

    return PageBody(children: [
      SectionTitle('Histórico — ${s.selected?.title ?? ''}'),
      Text('${s.readings.length} medição(ões) em $sessions sessão(ões) gravadas neste aparelho.',
          style: const TextStyle(color: XColors.gray)),
      const SizedBox(height: 10),
      Wrap(spacing: 8, runSpacing: 8, children: [
        SegmentedButton<_Filter>(
          segments: const [
            ButtonSegment(value: _Filter.all, label: Text('Todas')),
            ButtonSegment(value: _Filter.real, label: Text('Reais')),
            ButtonSegment(value: _Filter.demo, label: Text('Simuladas')),
          ],
          selected: {filter},
          onSelectionChanged: (v) => setState(() => filter = v.first),
        ),
        FilterChip(
          label: const Text('Só sessão atual'),
          selected: onlySession,
          onSelected: (v) => setState(() => onlySession = v),
        ),
      ]),
      const SizedBox(height: 12),
      if (list.isEmpty)
        const Card(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Text('Nenhuma medição para este filtro.'),
          ),
        ),
      for (final r in list)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Card(
            child: ListTile(
              onTap: () => _details(r),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              title: Row(children: [
                Expanded(
                  child: Text('${fmt(r.readMas)} mAs  (SET ${fmt(r.setMas)})',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                ),
                if (r.isDemo) DemoTag(label: r.sourceLabel) else StatusBadge(s.evalOf(r).status),
              ]),
              subtitle: Text(
                '${fmtDateTime(r.when)} • erro mAs ${fmtSigned(s.evalOf(r).errMas)} % • '
                'mA ${fmt(r.readMa, 1)} • ms ${fmt(r.readMs, 1)}\n'
                '${r.isDemo ? '${r.sourceLabel} ${r.deviceId}' : r.deviceId} • disparo ${r.shotId}'
                '${r.sessionId == s.session?.id ? ' • sessão atual' : ''}',
              ),
              isThreeLine: true,
            ),
          ),
        ),
      if (s.readings.any((r) => r.isDemo))
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: OutlinedButton.icon(
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Apagar simulações?'),
                  content: const Text('Remove os registros do modo demonstração e do simulador de bancada. '
                      'Medições reais não são afetadas.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
                    FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Apagar')),
                  ],
                ),
              );
              if (ok == true) await s.clearDemo();
            },
            icon: const Icon(Icons.delete_sweep_outlined),
            label: const Text('Apagar registros simulados'),
          ),
        ),
    ]);
  }
}

import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../calc.dart';
import '../../models.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import 'measure_tab.dart';

enum _Filter { all, real, demo }

/// Histórico e comparação de disparos (tela 7).
class HistoryTab extends StatefulWidget {
  final AppState state;
  const HistoryTab({super.key, required this.state});

  @override
  State<HistoryTab> createState() => _HistoryTabState();
}

enum _Period { all, today, week, month }

class _HistoryTabState extends State<HistoryTab> {
  _Filter filter = _Filter.all;
  bool onlySession = false;
  bool allEquipment = false;
  _Period period = _Period.all;
  String? sessionId;
  List<Reading>? _all;
  List<MeasureSession> _sessions = [];

  Future<void> _loadAll() async {
    final r = await widget.state.db.readings();
    if (mounted) setState(() => _all = r);
  }

  Future<void> _loadSessions() async {
    final eq = widget.state.selected;
    if (eq == null) return;
    final ss = await widget.state.db.sessions(eq.id);
    if (mounted) setState(() => _sessions = ss);
  }

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  String _equipmentName(String id) =>
      firstOrNull(widget.state.equipments.followedBy(widget.state.archivedEquipments).where((e) => e.id == id))
          ?.title ??
      id;

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
            if (r.maPeak != null) 'Corrente máxima: ${fmt(r.maPeak, 1)} mA',
            if (r.tolerances != null)
              'Tolerância aplicada: mA ±${fmt(r.tolerances!.maPct, 1)} % • ms ±${fmt(r.tolerances!.msPct, 1)} % • '
                  'mAs ±${fmt(r.tolerances!.masPct, 1)} %',
            if (r.probeId != null) 'Sonda: ${r.probeId}',
            if (r.calStatus != null) 'Calibração: ${r.calStatus}',
            for (final q in r.quality) 'Qualidade: ${qualityLabel(q)}',
            for (final n in widget.state.notes.where((n) => n.readingUid == r.uid))
              'Observação (${fmtDateTime(n.at)}): ${n.text}',
          ].join('\n')),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fechar'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    var list = allEquipment ? (_all ?? s.readings) : s.readings;
    if (onlySession) list = list.where((r) => r.sessionId == s.session?.id).toList();
    if (sessionId != null && !allEquipment) list = list.where((r) => r.sessionId == sessionId).toList();
    final now = DateTime.now();
    final from = switch (period) {
      _Period.today => DateTime(now.year, now.month, now.day),
      _Period.week => now.subtract(const Duration(days: 7)),
      _Period.month => now.subtract(const Duration(days: 30)),
      _Period.all => null,
    };
    if (from != null) list = list.where((r) => r.when.isAfter(from)).toList();
    if (filter == _Filter.real) list = list.where((r) => !r.isDemo).toList();
    if (filter == _Filter.demo) list = list.where((r) => r.isDemo).toList();
    final sessions = s.readings.map((r) => r.sessionId).toSet().length;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
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
        FilterChip(
          label: const Text('Todos os equipamentos'),
          selected: allEquipment,
          onSelected: (v) {
            setState(() => allEquipment = v);
            if (v) _loadAll();
          },
        ),
      ]),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        const Text('Período:', style: TextStyle(color: XColors.gray)),
        for (final p in _Period.values)
          ChoiceChip(
            label: Text(switch (p) {
              _Period.all => 'Tudo',
              _Period.today => 'Hoje',
              _Period.week => '7 dias',
              _Period.month => '30 dias',
            }),
            selected: period == p,
            onSelected: (_) => setState(() => period = p),
          ),
      ]),
      if (!allEquipment && _sessions.length > 1) ...[
        const SizedBox(height: 8),
        InputDecorator(
          decoration: const InputDecoration(
              labelText: 'Sessão', contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 2)),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String?>(
              value: _sessions.any((x) => x.id == sessionId) ? sessionId : null,
              isExpanded: true,
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('Todas as sessões')),
                for (final ss in _sessions)
                  DropdownMenuItem<String?>(
                    value: ss.id,
                    child: Text(
                      '${fmtDateTime(ss.startedAt)} • ${ss.label ?? '${fmtTrim(ss.setMa)} mA × ${fmtTrim(ss.setMs)} ms'}'
                      '${ss.setOrigin == 'instrumento' ? ' (instrumento)' : ''}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (v) => setState(() => sessionId = v),
            ),
          ),
        ),
      ],
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
                '${allEquipment ? '${_equipmentName(r.equipmentId)} • ' : ''}'
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

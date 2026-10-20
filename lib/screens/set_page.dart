import 'package:flutter/material.dart';

import '../app_state.dart';
import '../calc.dart';
import '../theme.dart';
import '../widgets/common.dart';

class SetPage extends StatefulWidget {
  final AppState state;
  const SetPage({super.key, required this.state});

  @override
  State<SetPage> createState() => _SetPageState();
}

class _SetPageState extends State<SetPage> {
  final ma = TextEditingController();
  final ms = TextEditingController();
  String? _loadedSession;
  String? error;

  void _syncFields() {
    final ses = widget.state.session;
    final key = ses == null ? null : '${ses.id}|${ses.setMa}|${ses.setMs}';
    if (key != _loadedSession) {
      _loadedSession = key;
      ma.text = ses == null ? '' : fmt(ses.setMa, ses.setMa % 1 == 0 ? 0 : 2);
      ms.text = ses == null ? '' : fmt(ses.setMs, ses.setMs % 1 == 0 ? 0 : 2);
    }
  }

  @override
  void initState() {
    super.initState();
    _syncFields();
  }

  @override
  void didUpdateWidget(covariant SetPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncFields();
  }

  @override
  void dispose() {
    ma.dispose();
    ms.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    final err = await widget.state.saveSet(parseNum(ma.text), parseNum(ms.text));
    if (mounted) setState(() => error = err);
  }

  Widget _input(String label, String unit, TextEditingController c) => TextField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textAlign: TextAlign.right,
        onChanged: (_) => setState(() {}),
        style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: XColors.blueDark),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(fontSize: 18),
          suffixText: unit,
          suffixStyle: const TextStyle(fontSize: 20, color: XColors.gray),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final ses = s.session;
    final a = parseNum(ma.text);
    final t = parseNum(ms.text);
    final mas = (a != null && t != null) ? masFrom(a, t) : null;
    final dirty = ses != null && (a != ses.setMa || t != ses.setMs);

    if (ses == null) {
      return const PageBody(children: [
        Card(
            child: Padding(
                padding: EdgeInsets.all(20),
                child: Text('Cadastre ou selecione um equipamento primeiro.'))),
      ]);
    }

    return PageBody(children: [
      SectionTitle('SET — ${s.selected?.title ?? ''}'),
      const Text('Informe apenas a corrente e o tempo programados no gerador. '
          'O mAs é calculado automaticamente: mAs = mA × ms ÷ 1000.'),
      if (s.sessionReadings.isNotEmpty) ...[
        const SizedBox(height: 10),
        Card(
          color: const Color(0xFFFFF8E1),
          child: ListTile(
            leading: const Icon(Icons.lock_outline, color: XColors.warn),
            title: const Text('SET desta sessão travado',
                style: TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text('A sessão já tem ${s.sessionReadings.length} medição(ões). '
                'Ao salvar um SET diferente, uma nova sessão é aberta automaticamente.'),
          ),
        ),
      ],
      const SizedBox(height: 14),
      ResponsiveGrid(minTileWidth: 260, children: [
        _input('Corrente programada', 'mA', ma),
        _input('Tempo programado', 'ms', ms),
      ]),
      const SizedBox(height: 12),
      BigValueTile(
        label: 'mAs SET calculado automaticamente',
        value: fmt(mas),
        unit: 'mAs',
        footer: a != null && t != null ? '${fmt(a, 2)} mA × ${fmt(t, 2)} ms ÷ 1000' : 'Valores inválidos',
        accent: XColors.blue,
      ),
      if (error != null)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(error!, style: const TextStyle(color: XColors.fail, fontWeight: FontWeight.w700)),
        ),
      const SizedBox(height: 14),
      FilledButton.icon(
        onPressed: _save,
        icon: const Icon(Icons.save),
        label: Text(dirty ? 'Salvar SET (alterado)' : 'Salvar SET'),
      ),
      const SizedBox(height: 18),
      Card(
        child: ListTile(
          leading: Icon(
            ses.setPending ? Icons.schedule_send : Icons.verified,
            color: ses.setPending ? XColors.warn : XColors.ok,
            size: 32,
          ),
          title: Text(ses.setPending ? 'SET salvo, pendente de envio' : 'SET confirmado pelo instrumento',
              style: const TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Text(ses.setPending
              ? 'Será enviado automaticamente quando o instrumento estiver conectado.'
              : 'Confirmado por ${ses.deviceId ?? '—'} em ${fmtDateTime(ses.setConfirmedAt)}'),
        ),
      ),
      const SizedBox(height: 12),
      Wrap(spacing: 10, runSpacing: 10, children: [
        OutlinedButton.icon(
          onPressed: s.connected ? s.sendSetNow : null,
          icon: const Icon(Icons.send),
          label: const Text('Enviar SET agora'),
        ),
        OutlinedButton.icon(
          onPressed: () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Iniciar nova sessão?'),
                content: const Text('As medições já gravadas continuam no histórico. '
                    'A nova sessão começa com o SET atual.'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
                  FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Iniciar')),
                ],
              ),
            );
            if (ok == true) await s.newSession();
          },
          icon: const Icon(Icons.playlist_add),
          label: const Text('Nova sessão de medição'),
        ),
      ]),
      const SizedBox(height: 12),
      Text('Sessão atual iniciada em ${fmtDateTime(ses.startedAt)} • '
          '${s.sessionReadings.length} medição(ões)', style: const TextStyle(color: XColors.gray)),
      const SizedBox(height: 8),
      const Text('O SET é apenas a referência de comparação enviada ao medidor. O aplicativo '
          'não altera parâmetros do gerador.', style: TextStyle(color: XColors.gray)),
    ]);
  }
}

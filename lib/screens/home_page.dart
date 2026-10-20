import 'package:flutter/material.dart';

import '../app_state.dart';
import '../calc.dart';
import '../theme.dart';
import '../widgets/common.dart';

class HomePage extends StatelessWidget {
  final AppState state;
  final void Function(int) goTo;
  final String version;
  const HomePage({super.key, required this.state, required this.goTo, required this.version});

  @override
  Widget build(BuildContext context) {
    final s = state;
    final eq = s.selected;
    final ses = s.session;
    final last = s.latest;
    final link = linkInfo(s);
    final ev = last == null ? null : s.evalOf(last);

    return PageBody(children: [
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: const LinearGradient(
            colors: [XColors.blueDark, XColors.blue],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('UNITECH BRASIL',
              style: TextStyle(color: XColors.silver, fontWeight: FontWeight.w700, letterSpacing: 2)),
          const SizedBox(height: 4),
          const FittedBox(
            fit: BoxFit.scaleDown,
            child: Text('X-METER CONNECT',
                style: TextStyle(
                    color: Colors.white, fontSize: 34, fontWeight: FontWeight.w900, letterSpacing: 1)),
          ),
          const SizedBox(height: 4),
          Text('Medidor de mA, tempo e mAs para raios X • versão $version',
              style: const TextStyle(color: Colors.white70)),
        ]),
      ),
      const SizedBox(height: 14),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            CircleAvatar(
                radius: 26,
                backgroundColor: link.color,
                child: Icon(link.icon, color: Colors.white, size: 28)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(link.text, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                Text(
                  s.link == LinkState.connected
                      ? 'Instrumento em ${s.settings.host}:${s.settings.port}'
                          '${s.lastSync != null ? ' • última sincronização ${fmtDateTime(s.lastSync)}' : ''}'
                      : (s.linkError ?? 'Conecte o celular ao Wi-Fi do X-METER e toque em Conectar'),
                  style: const TextStyle(color: XColors.gray),
                ),
              ]),
            ),
            const SizedBox(width: 8),
            if (s.link == LinkState.disconnected)
              FilledButton(onPressed: s.connect, child: const Text('Conectar'))
            else
              OutlinedButton(onPressed: s.disconnect, child: const Text('Desconectar')),
          ]),
        ),
      ),
      const SectionTitle('Equipamento em aferição'),
      Card(
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: const Icon(Icons.medical_services, color: XColors.blue, size: 36),
          title: Text(eq?.title ?? 'Nenhum equipamento cadastrado',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          subtitle: eq == null
              ? null
              : Text([
                  if (eq.client != null) eq.client!,
                  if (eq.site != null) eq.site!,
                  eq.generatorType.label,
                  'Série: ${eq.serialLabel}',
                  if (eq.internalId != null) 'ID: ${eq.internalId}',
                ].join(' • ')),
          trailing: TextButton(onPressed: () => goTo(1), child: const Text('Trocar')),
        ),
      ),
      SectionTitle('Parâmetros programados (SET)',
          trailing: TextButton.icon(
              onPressed: () => goTo(2), icon: const Icon(Icons.edit), label: const Text('Alterar'))),
      if (ses != null)
        ResponsiveGrid(minTileWidth: 200, children: [
          BigValueTile(label: 'mA SET', value: fmt(ses.setMa, 0), unit: 'mA'),
          BigValueTile(label: 'Tempo SET', value: fmt(ses.setMs, 0), unit: 'ms'),
          BigValueTile(
            label: 'mAs SET (calculado)',
            value: fmt(ses.setMas),
            unit: 'mAs',
            footer: ses.setPending ? 'Pendente de envio ao instrumento' : 'Confirmado pelo instrumento',
            accent: ses.setPending ? XColors.warn : XColors.ok,
          ),
        ]),
      SectionTitle('Última medição da sessão',
          trailing: TextButton.icon(
              onPressed: () => goTo(3), icon: const Icon(Icons.speed), label: const Text('Painel'))),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: last == null
              ? const Text('Nenhuma medição recebida nesta sessão. Os valores READ aparecem '
                  'aqui somente quando enviados pelo instrumento.',
                  style: TextStyle(fontSize: 16, color: XColors.gray))
              : Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      if (last.isDemo) DemoTag(label: last.sourceLabel),
                      Text('${fmt(last.readMas)} mAs',
                          style: const TextStyle(
                              fontSize: 36, fontWeight: FontWeight.w900, color: XColors.blueDark)),
                      Text('Erro mAs ${fmtSigned(ev!.errMas)} % • ${fmtDateTime(last.when)}'),
                    ]),
                  ),
                  StatusBadge(ev.status, large: true),
                ]),
        ),
      ),
      const SizedBox(height: 18),
      const Text(
        'O X-METER CONNECT apenas registra e compara medições. Ele não comanda o gerador '
        'nem dispara exposições de raios X.',
        style: TextStyle(color: XColors.gray),
      ),
    ]);
  }
}

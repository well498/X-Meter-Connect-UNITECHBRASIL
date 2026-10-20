import 'package:flutter/material.dart';

import '../app_state.dart';
import '../calc.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Conectividade (tela 8): Wi-Fi/BLE, sincronização, estado do instrumento,
/// bateria, modo local/conectado e versão do firmware.
class ConnectivityPage extends StatefulWidget {
  final AppState state;
  const ConnectivityPage({super.key, required this.state});

  @override
  State<ConnectivityPage> createState() => _ConnectivityPageState();
}

class _ConnectivityPageState extends State<ConnectivityPage> {
  late final st = widget.state.settings;
  late final host = TextEditingController(text: st.host);
  late final port = TextEditingController(text: st.port.toString());
  late final token = TextEditingController(text: st.token);
  late bool autoReconnect = st.autoReconnect;
  bool showToken = false;
  String? error;

  @override
  void dispose() {
    for (final c in [host, port, token]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<bool> _save() async {
    final p = int.tryParse(port.text.trim());
    String? err;
    if (host.text.trim().isEmpty) err = 'Informe o IP do instrumento';
    if (p == null || p < 1 || p > 65535) err = 'Porta inválida (1–65535)';
    setState(() => error = err);
    if (err != null) return false;
    await widget.state.saveSettings(widget.state.settings
        .copyWith(host: host.text.trim(), port: p, token: token.text.trim(), autoReconnect: autoReconnect));
    return true;
  }

  Widget _info(String k, String v, {Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 150, child: Text(k, style: const TextStyle(color: XColors.gray))),
          Expanded(child: Text(v, style: TextStyle(fontWeight: FontWeight.w600, color: color))),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final info = s.deviceInfo;
    final link = linkInfo(s);
    final battery = info?.batteryPct;
    return PageBody(children: [
      const SectionTitle('Estado do instrumento'),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(link.icon, color: link.color, size: 30),
              const SizedBox(width: 10),
              Expanded(
                child: Text(link.text,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: link.color)),
              ),
              if (s.connected)
                IconButton(
                  tooltip: 'Atualizar estado',
                  onPressed: s.refreshInstrument,
                  icon: const Icon(Icons.refresh),
                ),
            ]),
            const Divider(height: 18),
            _info('Instrumento', s.deviceId ?? '—'),
            _info('Modelo', info?.model ?? '—'),
            _info('Firmware', info?.firmware ?? s.firmware ?? '—'),
            _info('Modo de operação', switch (info?.mode) {
              'local' => 'LOCAL — configurado no display do instrumento',
              'connected' => 'CONECTADO — configurado pelo aplicativo',
              _ => '—',
            }),
            _info(
              'Bateria',
              battery == null ? '—' : '${fmt(battery, 0)} %${info?.charging == true ? ' (carregando por USB-C)' : ''}',
              color: battery == null ? null : (battery < 20 ? XColors.fail : battery < 40 ? XColors.warn : XColors.okText),
            ),
            _info('Transporte', switch (info?.transport) {
              'ble' => 'Bluetooth LE',
              'wifi' => 'Wi-Fi (Access Point do instrumento)',
              _ => s.connected ? 'Wi-Fi' : '—',
            }),
            _info('Calibração', info?.calibration ?? '—'),
            _info('Sonda', info?.probeId ?? '—'),
            _info('Última sincronização', fmtDateTime(s.lastSync)),
            if (info?.simulated == true) _info('Origem', 'SIMULADOR de bancada', color: XColors.demo),
            if (info != null && info.alerts.isNotEmpty)
              _info('Alertas', info.alerts.join('; '), color: XColors.warn),
            if (s.linkError != null) _info('Último erro', s.linkError!, color: XColors.fail),
          ]),
        ),
      ),
      const SizedBox(height: 8),
      const Text(
        'O instrumento funciona sozinho no MODO LOCAL (SET no display e medições guardadas na memória). '
        'Ao conectar, o aplicativo recebe as medições pendentes sem duplicar e adota o SET alterado no '
        'instrumento, registrando a origem da alteração.',
        style: TextStyle(color: XColors.gray),
      ),
      const SectionTitle('Transporte'),
      Card(
        child: Column(children: [
          const ListTile(
            leading: Icon(Icons.wifi, color: XColors.blue),
            title: Text('Wi-Fi próprio do X-METER (Access Point)'),
            subtitle: Text('Não usa internet nem a rede do hospital. Conecte o celular à rede do instrumento.'),
            trailing: Icon(Icons.check_circle, color: XColors.ok),
          ),
          const Divider(height: 1),
          ListTile(
            enabled: false,
            leading: const Icon(Icons.bluetooth),
            title: const Text('Bluetooth Low Energy'),
            subtitle: const Text('Previsto no protocolo; aguardando implementação no ESP32-S3.'),
            trailing: Chip(label: const Text('Indisponível'), backgroundColor: XColors.silver.withValues(alpha: 0.2)),
          ),
        ]),
      ),
      const SizedBox(height: 12),
      ResponsiveGrid(minTileWidth: 240, children: [
        TextField(
          controller: host,
          keyboardType: TextInputType.url,
          style: const TextStyle(fontSize: 18),
          decoration: const InputDecoration(labelText: 'IP do instrumento', hintText: '192.168.4.1'),
        ),
        TextField(
          controller: port,
          keyboardType: TextInputType.number,
          style: const TextStyle(fontSize: 18),
          decoration: const InputDecoration(labelText: 'Porta', hintText: '8080'),
        ),
        TextField(
          controller: token,
          obscureText: !showToken,
          style: const TextStyle(fontSize: 18),
          decoration: InputDecoration(
            labelText: 'Token de pareamento',
            suffixIcon: IconButton(
              onPressed: () => setState(() => showToken = !showToken),
              icon: Icon(showToken ? Icons.visibility_off : Icons.visibility),
            ),
          ),
        ),
      ]),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Reconectar automaticamente'),
        subtitle: const Text('Após queda do Wi-Fi, tenta de novo e sincroniza sem duplicar medições.'),
        value: autoReconnect,
        onChanged: (v) => setState(() => autoReconnect = v),
      ),
      if (error != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(error!, style: const TextStyle(color: XColors.fail, fontWeight: FontWeight.w700)),
        ),
      Wrap(spacing: 10, runSpacing: 10, children: [
        FilledButton.icon(
          onPressed: () async {
            if (await _save()) await s.connect();
          },
          icon: const Icon(Icons.link),
          label: const Text('Salvar e conectar'),
        ),
        OutlinedButton.icon(
          onPressed: s.connected ? s.syncNow : null,
          icon: const Icon(Icons.sync),
          label: const Text('Sincronizar agora'),
        ),
        OutlinedButton.icon(
          onPressed: s.link == LinkState.disconnected ? null : s.disconnect,
          icon: const Icon(Icons.link_off),
          label: const Text('Desconectar'),
        ),
      ]),
      const SizedBox(height: 12),
      const Text(
        'Teste sem hardware: rode tools/xmeter_simulador.py no computador e use o IP do computador '
        '(APK de teste). A comunicação HTTP local sem criptografia é apenas para bancada.',
        style: TextStyle(color: XColors.gray),
      ),
    ]);
  }
}

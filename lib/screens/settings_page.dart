import 'package:flutter/material.dart';

import '../app_state.dart';
import '../calc.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'audit_page.dart';

class SettingsPage extends StatefulWidget {
  final AppState state;
  final String version;
  const SettingsPage({super.key, required this.state, required this.version});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final st = widget.state.settings;
  late final host = TextEditingController(text: st.host);
  late final port = TextEditingController(text: st.port.toString());
  late final token = TextEditingController(text: st.token);
  late final tolMa = TextEditingController(text: fmt(st.tolerances.maPct, 1));
  late final tolMs = TextEditingController(text: fmt(st.tolerances.msPct, 1));
  late final tolMas = TextEditingController(text: fmt(st.tolerances.masPct, 1));
  late final alert = TextEditingController(text: fmt(st.tolerances.alertFraction * 100, 0));
  late final cTolMa = TextEditingController(text: fmt(st.tolerancesConv.maPct, 1));
  late final cTolMs = TextEditingController(text: fmt(st.tolerancesConv.msPct, 1));
  late final cTolMas = TextEditingController(text: fmt(st.tolerancesConv.masPct, 1));
  late final cAlert = TextEditingController(text: fmt(st.tolerancesConv.alertFraction * 100, 0));
  late bool autoReconnect = st.autoReconnect;
  late bool demoMode = st.demoMode;
  late final detStart = TextEditingController(text: fmtTrim(st.detStartPct));
  late final detEnd = TextEditingController(text: fmtTrim(st.detEndPct));
  late final detMin = TextEditingController(text: fmtTrim(st.detMinMs));
  late final cvLimit = TextEditingController(text: fmtTrim(st.cvLimitPct));
  bool showToken = false;
  String? error;

  @override
  void dispose() {
    for (final c in [
      host, port, token, tolMa, tolMs, tolMas, alert, cTolMa, cTolMs, cTolMas, cAlert, //
      detStart, detEnd, detMin, cvLimit,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<bool> _save() async {
    final p = int.tryParse(port.text.trim());
    Tolerances? read(TextEditingController ma, TextEditingController ms, TextEditingController mas,
        TextEditingController al) {
      final a = parseNum(ma.text), b = parseNum(ms.text), c = parseNum(mas.text), f = parseNum(al.text);
      if ([a, b, c].any((v) => v == null || v <= 0 || v > 100)) return null;
      if (f == null || f <= 0 || f > 100) return null;
      return Tolerances(maPct: a!, msPct: b!, masPct: c!, alertFraction: f / 100);
    }

    final hf = read(tolMa, tolMs, tolMas, alert);
    final conv = read(cTolMa, cTolMs, cTolMas, cAlert);
    String? err;
    if (host.text.trim().isEmpty) err = 'Informe o IP do instrumento';
    if (p == null || p < 1 || p > 65535) err = 'Porta inválida (1–65535)';
    if (hf == null || conv == null) {
      err = 'Tolerâncias e início do alerta devem estar entre 0 e 100 %';
    }
    final ds = parseNum(detStart.text), de = parseNum(detEnd.text), dm = parseNum(detMin.text);
    final cv = parseNum(cvLimit.text);
    if (ds == null || de == null || ds <= 0 || ds >= 100 || de <= 0 || de > ds) {
      err = 'Limiares de detecção: início entre 1 e 99 % e fim (histerese) menor ou igual ao início';
    }
    if (dm == null || dm <= 0 || dm > 1000) err = 'Duração mínima da exposição inválida';
    if (cv == null || cv <= 0 || cv > 100) err = 'Limite de CV inválido';
    setState(() => error = err);
    if (err != null) return false;
    await widget.state.saveSettings(widget.state.settings.copyWith(
      host: host.text.trim(),
      port: p,
      token: token.text.trim(),
      autoReconnect: autoReconnect,
      demoMode: demoMode,
      tolerances: hf,
      tolerancesConv: conv,
      detStartPct: ds,
      detEndPct: de,
      detMinMs: dm,
      cvLimitPct: cv,
    ));
    return true;
  }

  Future<void> _exportBackup() async {
    try {
      final path = await widget.state.exportBackup(widget.version);
      if (!mounted) return;
      await widget.state.shareFile(path, 'Backup X-METER CONNECT');
    } catch (e) {
      if (mounted) showSnack(context, 'Falha no backup: $e');
    }
  }

  Future<void> _restoreBackup() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restaurar backup?'),
        content: const Text('TODOS os dados deste aparelho serão substituídos pelos do arquivo '
            'escolhido. Antes disso, o app salva automaticamente uma cópia dos dados atuais '
            'na pasta de exportações.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Escolher arquivo')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final path = await widget.state.pickBackupFile();
      if (path == null) return;
      final msg = await widget.state.importBackupFile(path, widget.version);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Backup restaurado'),
          content: Text(msg),
          actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
        ),
      );
    } catch (e) {
      if (mounted) showSnack(context, 'Backup não restaurado: $e');
    }
  }

  Widget _num(String label, TextEditingController c, String suffix) => TextField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        style: const TextStyle(fontSize: 18),
        decoration: InputDecoration(labelText: label, suffixText: suffix),
      );

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    return PageBody(children: [
      const SectionTitle('Conexão com o instrumento'),
      Card(
        child: Column(children: [
          const ListTile(
            leading: Icon(Icons.wifi, color: XColors.blue),
            title: Text('Wi-Fi próprio do X-METER (Access Point)'),
            subtitle: Text('Transporte ativo. Conecte o celular à rede do instrumento antes.'),
            trailing: Icon(Icons.check_circle, color: XColors.ok),
          ),
          const Divider(height: 1),
          ListTile(
            enabled: false,
            leading: const Icon(Icons.bluetooth),
            title: const Text('Bluetooth Low Energy'),
            subtitle: const Text('Aguardando implementação no hardware (ver protocolo proposto).'),
            trailing: Chip(
              label: const Text('Indisponível'),
              backgroundColor: XColors.silver.withValues(alpha: 0.4),
            ),
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
      Wrap(spacing: 10, runSpacing: 10, children: [
        FilledButton.icon(
          onPressed: () async {
            if (await _save()) await s.connect();
          },
          icon: const Icon(Icons.link),
          label: const Text('Salvar e conectar'),
        ),
        OutlinedButton.icon(
          onPressed: s.link == LinkState.disconnected ? null : s.disconnect,
          icon: const Icon(Icons.link_off),
          label: const Text('Desconectar'),
        ),
      ]),
      if (s.linkError != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text('Último erro: ${s.linkError}', style: const TextStyle(color: XColors.fail)),
        ),
      if (s.deviceId != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text('Instrumento: ${s.deviceId}${s.firmware != null ? ' • firmware ${s.firmware}' : ''}'),
        ),
      const SizedBox(height: 10),
      const SectionTitle('Tolerâncias — alta frequência e "a identificar" (±)'),
      ResponsiveGrid(minTileWidth: 200, children: [
        _num('Corrente (mA)', tolMa, '%'),
        _num('Tempo (ms)', tolMs, '%'),
        _num('mAs', tolMas, '%'),
        _num('Alerta a partir de', alert, '% da tol.'),
      ]),
      const SizedBox(height: 10),
      const SectionTitle('Tolerâncias — convencionais 2, 6 e 12 pulsos (±)'),
      ResponsiveGrid(minTileWidth: 200, children: [
        _num('Corrente (mA)', cTolMa, '%'),
        _num('Tempo (ms)', cTolMs, '%'),
        _num('mAs', cTolMas, '%'),
        _num('Alerta a partir de', cAlert, '% da tol.'),
      ]),
      const SizedBox(height: 6),
      const Text(
        'Verde: dentro da faixa de alerta • Amarelo: entre o início do alerta e a tolerância • '
        'Vermelho: fora da tolerância. Ajuste conforme o procedimento e a norma aplicáveis.',
        style: TextStyle(color: XColors.gray),
      ),
      const SizedBox(height: 10),
      const SectionTitle('Detecção da exposição e repetibilidade'),
      ResponsiveGrid(minTileWidth: 200, children: [
        _num('Início / medição do tempo', detStart, '% do pico'),
        _num('Fim (histerese)', detEnd, '% do pico'),
        _num('Duração mínima', detMin, 'ms'),
        _num('Limite do CV', cvLimit, '%'),
      ]),
      const SizedBox(height: 6),
      const Text(
        'O tempo é medido entre as passagens pelo limiar de início na subida e na descida. O limiar de fim, '
        'menor, evita que ruído encerre a exposição. Pulsos mais curtos que a duração mínima são descartados. '
        'Estes parâmetros valem para o modo demonstração e para a conferência das formas de onda; o firmware '
        'usará os mesmos (docs/PROTOCOLO_PROPOSTO.md).',
        style: TextStyle(color: XColors.gray),
      ),
      const SizedBox(height: 10),
      const SectionTitle('Modo demonstração'),
      Card(
        color: demoMode ? XColors.demo.withValues(alpha: 0.08) : null,
        child: SwitchListTile(
          title: const Text('Ativar MODO DEMONSTRAÇÃO'),
          subtitle: const Text('Permite gerar disparos simulados para treinar e testar telas. '
              'Ficam marcados como DEMONSTRAÇÃO e fora dos relatórios por padrão.'),
          value: demoMode,
          onChanged: (v) => setState(() => demoMode = v),
        ),
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
        label: const Text('Salvar configurações'),
      ),
      const SizedBox(height: 20),
      const SectionTitle('Dados e backup'),
      const Text(
        'Os dados ficam só neste aparelho. Faça backup com frequência e guarde o arquivo '
        'fora do celular (Google Drive, e-mail ou computador).',
        style: TextStyle(color: XColors.gray),
      ),
      const SizedBox(height: 10),
      Wrap(spacing: 10, runSpacing: 10, children: [
        FilledButton.icon(
          onPressed: _exportBackup,
          icon: const Icon(Icons.backup_outlined),
          label: const Text('Fazer backup e compartilhar'),
        ),
        OutlinedButton.icon(
          onPressed: _restoreBackup,
          icon: const Icon(Icons.settings_backup_restore),
          label: const Text('Restaurar backup'),
        ),
        OutlinedButton.icon(
          onPressed: () => Navigator.of(context)
              .push(MaterialPageRoute<void>(builder: (_) => AuditPage(state: s))),
          icon: const Icon(Icons.history_edu),
          label: const Text('Registro de alterações'),
        ),
      ]),
      const SizedBox(height: 20),
      const SectionTitle('Sobre'),
      Text('UNITECH X-METER CONNECT ${widget.version}\nBanco local: ${s.dbPath}',
          style: const TextStyle(color: XColors.gray)),
      const SizedBox(height: 6),
      const Text(
        'Protótipo de engenharia. Não comanda exposições nem altera parâmetros do gerador. '
        'A comunicação HTTP local sem criptografia é apenas para bancada.',
        style: TextStyle(color: XColors.gray),
      ),
    ]);
  }
}

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../calc.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'audit_page.dart';
import 'profiles_page.dart';

class SettingsPage extends StatefulWidget {
  final AppState state;
  final String version;
  const SettingsPage({super.key, required this.state, required this.version});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final st = widget.state.settings;
  late bool demoMode = st.demoMode;
  late bool timeInSeconds = st.timeInSeconds;
  late final detStart = TextEditingController(text: fmtTrim(st.detStartPct));
  late final detEnd = TextEditingController(text: fmtTrim(st.detEndPct));
  late final detMin = TextEditingController(text: fmtTrim(st.detMinMs));
  late final cvLimit = TextEditingController(text: fmtTrim(st.cvLimitPct));
  String? error;

  @override
  void dispose() {
    for (final c in [detStart, detEnd, detMin, cvLimit]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<bool> _save() async {
    String? err;
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
      demoMode: demoMode,
      timeInSeconds: timeInSeconds,
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
      const SectionTitle('Unidades'),
      SegmentedButton<bool>(
        segments: const [
          ButtonSegment(value: false, label: Text('Tempo em ms')),
          ButtonSegment(value: true, label: Text('Tempo em s')),
        ],
        selected: {timeInSeconds},
        onSelectionChanged: (v) => setState(() => timeInSeconds = v.first),
      ),
      const SizedBox(height: 6),
      const Text('Corrente em mA e carga em mAs. O SET continua sendo calculado com o tempo em ms.',
          style: TextStyle(color: XColors.gray)),
      const SectionTitle('Perfis de geradores e tolerâncias'),
      Card(
        child: ListTile(
          leading: const Icon(Icons.electric_bolt, color: XColors.cyan),
          title: Text('${s.profiles.length} perfil(is) cadastrado(s)'),
          subtitle: const Text('Cada perfil tem faixas, estações de mA e critério de aceitação próprios, '
              'com origem e versão (ex.: SAWAE ALTUS — manual rev. 19).'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ProfilesPage(state: s))),
        ),
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

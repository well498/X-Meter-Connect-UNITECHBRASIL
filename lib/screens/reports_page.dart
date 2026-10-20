import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../calc.dart';
import '../reports.dart';
import '../reports_pdf.dart';
import '../theme.dart';
import '../widgets/common.dart';

class ReportsPage extends StatefulWidget {
  final AppState state;
  final String version;
  const ReportsPage({super.key, required this.state, this.version = ''});

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  bool includeDemo = false;
  bool onlySession = false;
  String? lastFile;

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final eq = s.selected;
    if (eq == null) {
      return const PageBody(children: [Text('Selecione um equipamento.')]);
    }
    var list = s.readings;
    if (onlySession) list = list.where((r) => r.sessionId == s.session?.id).toList();
    if (!includeDemo) list = list.where((r) => !r.isDemo).toList();
    final sum = summarize(list, s.tol);
    final report = buildTextReport(eq, s.session, list, s.tol, includesDemo: list.any((r) => r.isDemo));
    final stamp = DateTime.now();
    final base = 'xmeter_${eq.model.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')}_'
        '${stamp.year}${two(stamp.month)}${two(stamp.day)}_${two(stamp.hour)}${two(stamp.minute)}';

    Future<void> exportPdf() async {
      try {
        Uint8List? logo;
        try {
          logo = (await rootBundle.load('assets/logo_unitech.png')).buffer.asUint8List();
        } catch (_) {}
        final bytes = await buildPdfReport(
          eq: eq,
          session: s.session,
          readings: list,
          notes: s.notes,
          tol: s.tol,
          includesSimulated: list.any((r) => r.isDemo),
          appVersion: widget.version,
          profile: s.profile,
          limits: s.limits,
          logoPng: logo,
        );
        final path = await s.saveExportBytes('$base.pdf', bytes);
        if (!mounted) return;
        setState(() => lastFile = path);
        await s.shareFile(path, 'Relatório X-METER — ${eq.title}');
      } catch (e) {
        if (mounted) showSnack(this.context, 'Falha ao gerar PDF: $e');
      }
    }

    Future<void> export(String name, String content, {bool share = false}) async {
      try {
        final path = await s.saveExport(name, content);
        if (!mounted) return;
        setState(() => lastFile = path);
        if (share) {
          await s.shareFile(path, 'X-METER CONNECT — ${eq.title}');
        } else {
          showSnack(this.context, 'Arquivo salvo: $path');
        }
      } catch (e) {
        if (mounted) showSnack(this.context, 'Falha ao salvar: $e');
      }
    }

    Future<void> copy(String content, String what) async {
      await Clipboard.setData(ClipboardData(text: content));
      if (mounted) showSnack(this.context, '$what copiado. Cole no e-mail, WhatsApp ou planilha.');
    }

    return PageBody(children: [
      SectionTitle('Relatórios — ${eq.title}'),
      Wrap(spacing: 8, runSpacing: 8, children: [
        FilterChip(
          label: const Text('Só sessão atual'),
          selected: onlySession,
          onSelected: (v) => setState(() => onlySession = v),
        ),
        FilterChip(
          label: const Text('Incluir simuladas'),
          selected: includeDemo,
          selectedColor: XColors.demo.withValues(alpha: 0.25),
          onSelected: (v) => setState(() => includeDemo = v),
        ),
      ]),
      const SizedBox(height: 12),
      ResponsiveGrid(minTileWidth: 160, children: [
        BigValueTile(label: 'Medições', value: '${sum.total}', unit: ''),
        BigValueTile(label: 'Aprovadas', value: '${sum.approved}', unit: '', accent: XColors.ok),
        BigValueTile(label: 'Alerta', value: '${sum.alert}', unit: '', accent: XColors.warn),
        BigValueTile(label: 'Reprovadas', value: '${sum.failed}', unit: '', accent: XColors.fail),
      ]),
      const SizedBox(height: 14),
      Wrap(spacing: 10, runSpacing: 10, children: [
        FilledButton.icon(
          onPressed: exportPdf,
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFF16A34A), foregroundColor: Colors.white),
          icon: const Icon(Icons.picture_as_pdf),
          label: const Text('Relatório PDF'),
        ),
        FilledButton.icon(
          onPressed: () => export('$base.csv', buildCsv(eq, list, s.tol), share: true),
          icon: const Icon(Icons.table_view),
          label: const Text('Compartilhar CSV (Excel)'),
        ),
        FilledButton.icon(
          onPressed: () => export('$base.txt', report, share: true),
          icon: const Icon(Icons.share),
          label: const Text('Compartilhar relatório'),
        ),
        OutlinedButton.icon(
          onPressed: () => copy(report, 'Relatório'),
          icon: const Icon(Icons.copy),
          label: const Text('Copiar relatório'),
        ),
        OutlinedButton.icon(
          onPressed: () => copy(buildCsv(eq, list, s.tol), 'CSV'),
          icon: const Icon(Icons.copy_all),
          label: const Text('Copiar CSV'),
        ),
      ]),
      if (lastFile != null)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: SelectableText('Último arquivo: $lastFile',
              style: const TextStyle(color: XColors.gray)),
        ),
      const SizedBox(height: 14),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: SelectableText(report,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13, height: 1.35)),
        ),
      ),
      const SizedBox(height: 8),
      const Text(
        'No Android os arquivos ficam em Android/data/br.com.unitech.unitech_xmeter_connect/files/exportacoes '
        '(acessível pelo cabo USB no computador).',
        style: TextStyle(color: XColors.gray),
      ),
    ]);
  }
}

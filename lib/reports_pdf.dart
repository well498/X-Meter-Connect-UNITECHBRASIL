import 'dart:math';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'analysis.dart';
import 'calc.dart';
import 'models.dart';
import 'reports.dart';

/// Fonte padrão do PDF (Helvetica) cobre Latin-1: troca símbolos fora dela.
String _t(String s) => s
    .replaceAll('—', '-')
    .replaceAll('–', '-')
    .replaceAll('−', '-')
    .replaceAll('≤', '<=')
    .replaceAll('≥', '>=')
    .replaceAll('•', '|')
    .replaceAll('Σ', 'Soma');

const _blue = PdfColor.fromInt(0xFF0B3D7A);
const _gray = PdfColor.fromInt(0xFF5F6B76);
const _ok = PdfColor.fromInt(0xFF2E7D32);
const _warn = PdfColor.fromInt(0xFFB7860B);
const _fail = PdfColor.fromInt(0xFFC62828);
const _demo = PdfColor.fromInt(0xFF7B1FA2);

/// Relatório técnico em PDF (tela 9).
Future<Uint8List> buildPdfReport({
  required Equipment eq,
  required MeasureSession? session,
  required List<Reading> readings,
  required List<Note> notes,
  required Tolerances tol,
  required bool includesSimulated,
  required String appVersion,
  Uint8List? logoPng,
  String? reportId,
}) async {
  final doc = pw.Document(title: 'Relatório X-METER CONNECT', author: 'UNITECH BRASIL');
  final sum = summarize(readings, tol);
  final id = reportId ?? 'XM-${DateTime.now().millisecondsSinceEpoch.toRadixString(36).toUpperCase()}';
  final logo = logoPng == null ? null : pw.MemoryImage(logoPng);
  final latestWave = readings.where((r) => r.waveform != null).cast<Reading?>().firstWhere((_) => true, orElse: () => null);

  pw.Widget kv(String k, String v) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
        child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.SizedBox(width: 130, child: pw.Text(_t(k), style: const pw.TextStyle(color: _gray, fontSize: 9))),
          pw.Expanded(child: pw.Text(_t(v), style: const pw.TextStyle(fontSize: 9.5))),
        ]),
      );

  pw.Widget section(String title) => pw.Container(
        margin: const pw.EdgeInsets.only(top: 12, bottom: 5),
        padding: const pw.EdgeInsets.only(bottom: 2),
        decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: _blue, width: 1))),
        child: pw.Text(_t(title), style: pw.TextStyle(fontSize: 11.5, fontWeight: pw.FontWeight.bold, color: _blue)),
      );

  final repeat = stats(readings.where((r) => !r.isDemo || includesSimulated).map((r) => r.readMas));

  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(36, 30, 36, 36),
    header: (ctx) => pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 6),
      decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: _gray, width: 0.5))),
      child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
        if (logo != null)
          pw.Container(
            height: 30,
            padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            color: const PdfColor.fromInt(0xFF061430),
            child: pw.Image(logo, height: 24),
          )
        else
          pw.Text('UNITECH BRASIL', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: _blue)),
        pw.SizedBox(width: 10),
        pw.Expanded(
          child: pw.Text(_t('Relatório técnico — aferição de mA, tempo e mAs'),
              style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
        ),
        pw.Text('Nº $id', style: const pw.TextStyle(fontSize: 9, color: _gray)),
      ]),
    ),
    footer: (ctx) => pw.Row(children: [
      pw.Expanded(
        child: pw.Text(
            _t('X-METER CONNECT $appVersion — o aplicativo registra medições e não comanda o gerador de raios X.'),
            style: const pw.TextStyle(fontSize: 7.5, color: _gray)),
      ),
      pw.Text('Página ${ctx.pageNumber}/${ctx.pagesCount}', style: const pw.TextStyle(fontSize: 8, color: _gray)),
    ]),
    build: (ctx) => [
      if (includesSimulated)
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(6),
          margin: const pw.EdgeInsets.only(bottom: 6),
          color: _demo,
          child: pw.Text(_t('ATENÇÃO: este relatório inclui registros SIMULADOS (demonstração/simulador). Não são medições reais.'),
              style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 9)),
        ),
      kv('Emitido em', fmtDateTime(DateTime.now())),
      section('Cliente e equipamento'),
      kv('Cliente', eq.client ?? '—'),
      kv('Estabelecimento', eq.site ?? '—'),
      kv('Aparelho', eq.title),
      kv('Nº de série', eq.serialLabel),
      kv('Identificação interna', eq.internalId ?? '—'),
      kv('Data da aferição', fmtDate(eq.calibrationDate)),
      kv('Responsável técnico', eq.technician ?? '—'),
      section('Gerador'),
      kv('Tecnologia', eq.generatorType.label),
      kv('Fabricante / modelo', [eq.generatorMaker, eq.generatorModel].whereType<String>().join(' ').ifEmpty('—')),
      kv('Potência nominal', eq.powerKw == null ? '—' : '${fmtTrim(eq.powerKw!)} kW'),
      kv(eq.hasCustomLimits ? 'Limites (manual)' : 'Limites (referência)',
          '${fmtTrim(eq.limits.minMa)}–${fmtTrim(eq.limits.maxMa)} mA | ${fmtTrim(eq.limits.minMs)}–${fmtTrim(eq.limits.maxMs)} ms | até ${fmtTrim(eq.limits.maxMas)} mAs'),
      if (session != null) ...[
        section('Sessão e SET'),
        kv('Sessão', session.label ?? session.id),
        kv('Início', fmtDateTime(session.startedAt)),
        kv('SET', '${fmtTrim(session.setMa)} mA x ${fmtTrim(session.setMs)} ms = ${fmt(session.setMas)} mAs'),
      ],
      section('Critérios'),
      kv('Tolerâncias atuais',
          'mA ±${fmt(tol.maPct, 1)} % | tempo ±${fmt(tol.msPct, 1)} % | mAs ±${fmt(tol.masPct, 1)} % | alerta a partir de ${fmt(tol.alertFraction * 100, 0)} % da tolerância'),
      kv('Observação', 'cada medição é avaliada com a tolerância gravada no momento em que foi recebida'),
      section('Resumo'),
      pw.Row(children: [
        for (final e in [
          ('Medições', '${sum.total}', _blue),
          ('Aprovadas', '${sum.approved}', _ok),
          ('Alerta', '${sum.alert}', _warn),
          ('Reprovadas', '${sum.failed}', _fail),
        ])
          pw.Expanded(
            child: pw.Container(
              margin: const pw.EdgeInsets.only(right: 6),
              padding: const pw.EdgeInsets.all(6),
              decoration: pw.BoxDecoration(border: pw.Border.all(color: e.$3, width: 1)),
              child: pw.Column(children: [
                pw.Text(e.$2, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: e.$3)),
                pw.Text(e.$1, style: const pw.TextStyle(fontSize: 8, color: _gray)),
              ]),
            ),
          ),
      ]),
      pw.SizedBox(height: 4),
      kv('Erro do mAs', 'médio ${fmtSigned(sum.meanErrMas)} % | maior absoluto ${fmt(sum.maxAbsErrMas)} %'),
      if (repeat != null)
        kv('Repetibilidade do mAs',
            'n = ${repeat.n} | média ${fmt(repeat.mean, 3)} mAs | DP ${fmt(repeat.sd, 4)} | CV ${fmt(repeat.cvPct, 2)} %'),
      section('Medições'),
      if (readings.isEmpty)
        pw.Text('Nenhuma medição registrada.', style: const pw.TextStyle(fontSize: 9))
      else
        pw.TableHelper.fromTextArray(
          headerStyle: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
          headerDecoration: const pw.BoxDecoration(color: _blue),
          cellStyle: const pw.TextStyle(fontSize: 7.5),
          cellAlignment: pw.Alignment.centerRight,
          headerAlignment: pw.Alignment.center,
          columnWidths: {0: const pw.FlexColumnWidth(2.2), 1: const pw.FlexColumnWidth(1.2), 9: const pw.FlexColumnWidth(1.4)},
          headers: ['Data/hora', 'Disparo', 'mA', 'erro', 'ms', 'erro', 'mAs', 'erro', 'mA máx', 'Resultado'],
          data: [
            for (final r in readings.take(200))
              () {
                final ev = evaluateReading(r, tol);
                return [
                  fmtDateTime(r.when),
                  _t('${r.isDemo ? '[SIM] ' : ''}${r.shotId.length > 10 ? r.shotId.substring(r.shotId.length - 10) : r.shotId}'),
                  fmt(r.readMa, 1),
                  '${fmtSigned(ev.errMa, 1)}%',
                  fmt(r.readMs, 2),
                  '${fmtSigned(ev.errMs, 1)}%',
                  fmt(r.readMas, 3),
                  '${fmtSigned(ev.errMas, 1)}%',
                  fmt(r.maPeak, 1),
                  r.isDemo ? 'SIMULADO' : ev.status.label,
                ];
              }(),
          ],
        ),
      if (latestWave != null) ...[
        section('Forma de onda — disparo ${_t(latestWave.shotId)}'),
        pw.Container(
          height: 150,
          decoration: pw.BoxDecoration(border: pw.Border.all(color: _gray, width: 0.5)),
          child: pw.CustomPaint(
            size: const PdfPoint(523, 150),
            painter: (canvas, size) {
              final w = latestWave.waveform!;
              final maxY = max(w.ma.reduce(max), latestWave.setMa) * 1.15;
              final n = w.ma.length;
              if (n < 2 || maxY <= 0) return;
              // Referência mA SET.
              final yRef = latestWave.setMa / maxY * size.y;
              canvas
                ..setStrokeColor(PdfColors.grey500)
                ..setLineWidth(0.5)
                ..moveTo(0, yRef)
                ..lineTo(size.x, yRef)
                ..strokePath();
              canvas
                ..setStrokeColor(latestWave.isDemo ? _demo : _blue)
                ..setLineWidth(1);
              final step = max(1, n ~/ 1000);
              for (var i = 0; i < n; i += step) {
                final x = i / (n - 1) * size.x;
                final y = w.ma[i] / maxY * size.y;
                if (i == 0) {
                  canvas.moveTo(x, y);
                } else {
                  canvas.lineTo(x, y);
                }
              }
              canvas.strokePath();
            },
          ),
        ),
        pw.Text(
            _t('Janela ${fmt(latestWave.waveform!.durationMs, 1)} ms | escala vertical até '
                '${fmt(max(latestWave.waveform!.ma.reduce(max), latestWave.setMa) * 1.15, 0)} mA | linha cinza: mA SET'),
            style: const pw.TextStyle(fontSize: 8, color: _gray)),
      ],
      if (notes.isNotEmpty) ...[
        section('Observações do técnico'),
        for (final n in notes.take(50))
          pw.Bullet(text: _t('${fmtDateTime(n.at)} — ${n.text}'), style: const pw.TextStyle(fontSize: 9)),
      ],
      section('Conclusão e assinatura'),
      pw.Text(
          _t(sum.total == 0
              ? 'Sem medições para conclusão.'
              : sum.failed > 0
                  ? 'Há medições fora da tolerância. Recomenda-se ajuste/manutenção e nova aferição.'
                  : sum.alert > 0
                      ? 'Medições dentro da tolerância, com valores em faixa de alerta. Recomenda-se acompanhamento.'
                      : 'Todas as medições dentro da tolerância configurada.'),
          style: const pw.TextStyle(fontSize: 10)),
      pw.SizedBox(height: 36),
      pw.Row(children: [
        pw.Expanded(
          child: pw.Column(children: [
            pw.Container(height: 0.6, color: PdfColors.black),
            pw.Text(_t(eq.technician ?? 'Responsável técnico'), style: const pw.TextStyle(fontSize: 9)),
          ]),
        ),
        pw.SizedBox(width: 40),
        pw.Expanded(
          child: pw.Column(children: [
            pw.Container(height: 0.6, color: PdfColors.black),
            pw.Text('Data', style: const pw.TextStyle(fontSize: 9)),
          ]),
        ),
      ]),
    ],
  ));
  return doc.save();
}

extension _IfEmpty on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}

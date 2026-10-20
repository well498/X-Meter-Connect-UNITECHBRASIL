import 'calc.dart';
import 'models.dart';

String _csvCell(String v) {
  if (v.contains(';') || v.contains('"') || v.contains('\n')) {
    return '"${v.replaceAll('"', '""')}"';
  }
  return v;
}

/// CSV no padrão brasileiro (separador ';' e vírgula decimal) para Excel.
String buildCsv(Equipment eq, List<Reading> readings, Tolerances tol) {
  final b = StringBuffer();
  b.writeln([
    'id_medicao', 'origem', 'equipamento', 'serie', 'id_interno', 'sessao', 'instrumento',
    'disparo', 'data_hora', 'mA_SET', 'ms_SET', 'mAs_SET', 'mA_READ', 'ms_READ', 'mAs_READ',
    'erro_mA_%', 'erro_ms_%', 'erro_mAs_%', 'status'
  ].join(';'));
  for (final r in readings) {
    final ev = evaluate(
        setMa: r.setMa,
        setMs: r.setMs,
        readMa: r.readMa,
        readMs: r.readMs,
        readMas: r.readMas,
        tol: tol);
    b.writeln([
      r.uid,
      r.sourceLabel,
      eq.title,
      eq.serialLabel,
      eq.internalId ?? '',
      r.sessionId,
      r.deviceId,
      r.shotId,
      fmtDateTime(r.when),
      fmt(r.setMa),
      fmt(r.setMs),
      fmt(r.setMas),
      fmt(r.readMa),
      fmt(r.readMs),
      fmt(r.readMas),
      fmt(ev.errMa),
      fmt(ev.errMs),
      fmt(ev.errMas),
      r.isDemo ? 'SIMULADO' : ev.status.label,
    ].map(_csvCell).join(';'));
  }
  return b.toString();
}

class Summary {
  final int total;
  final int approved;
  final int alert;
  final int failed;
  final double? meanErrMas;
  final double? maxAbsErrMas;
  const Summary(this.total, this.approved, this.alert, this.failed, this.meanErrMas, this.maxAbsErrMas);
}

Summary summarize(List<Reading> readings, Tolerances tol) {
  var a = 0, w = 0, f = 0;
  final errs = <double>[];
  for (final r in readings) {
    final ev = evaluate(
        setMa: r.setMa,
        setMs: r.setMs,
        readMa: r.readMa,
        readMs: r.readMs,
        readMas: r.readMas,
        tol: tol);
    switch (ev.status) {
      case MeasureStatus.approved:
        a++;
      case MeasureStatus.alert:
        w++;
      case MeasureStatus.failed:
        f++;
      case MeasureStatus.unknown:
        break;
    }
    if (ev.errMas != null) errs.add(ev.errMas!);
  }
  final mean = errs.isEmpty ? null : errs.reduce((x, y) => x + y) / errs.length;
  final maxAbs = errs.isEmpty ? null : errs.map((e) => e.abs()).reduce((x, y) => x > y ? x : y);
  return Summary(readings.length, a, w, f, mean, maxAbs);
}

/// Relatório em texto simples (pode ser copiado para e-mail ou WhatsApp).
String buildTextReport(Equipment eq, MeasureSession? session, List<Reading> readings,
    Tolerances tol, {required bool includesDemo}) {
  final s = summarize(readings, tol);
  final b = StringBuffer()
    ..writeln('UNITECH BRASIL — RELATÓRIO X-METER CONNECT')
    ..writeln('Gerado em: ${fmtDateTime(DateTime.now())}')
    ..writeln('')
    ..writeln('EQUIPAMENTO')
    ..writeln('Cliente: ${eq.client ?? '—'}')
    ..writeln('Estabelecimento: ${eq.site ?? '—'}')
    ..writeln('Fabricante/Modelo: ${eq.title}')
    ..writeln('Nº de série: ${eq.serialLabel}')
    ..writeln('Identificação interna: ${eq.internalId ?? '—'}')
    ..writeln('Data da aferição: ${fmtDate(eq.calibrationDate)}')
    ..writeln('Responsável técnico: ${eq.technician ?? '—'}')
    ..writeln('');
  if (session != null) {
    b
      ..writeln('SET DA SESSÃO ATUAL')
      ..writeln('mA SET: ${fmt(session.setMa)} mA | Tempo SET: ${fmt(session.setMs)} ms | '
          'mAs SET: ${fmt(session.setMas)} mAs')
      ..writeln('');
  }
  b
    ..writeln('TOLERÂNCIAS (±): mA ${fmt(tol.maPct, 1)} % | tempo ${fmt(tol.msPct, 1)} % | '
        'mAs ${fmt(tol.masPct, 1)} % | alerta a partir de ${fmt(tol.alertFraction * 100, 0)} % da tolerância')
    ..writeln('')
    ..writeln('RESUMO: ${s.total} medição(ões) | aprovadas ${s.approved} | alerta ${s.alert} | '
        'reprovadas ${s.failed}')
    ..writeln('Erro médio mAs: ${fmtSigned(s.meanErrMas)} % | maior erro absoluto mAs: '
        '${fmt(s.maxAbsErrMas)} %')
    ..writeln('');
  if (includesDemo) {
    b.writeln('ATENÇÃO: este relatório inclui registros SIMULADOS (modo demonstração ou '
        'simulador de bancada). Eles não são medições reais.');
    b.writeln('');
  }
  b.writeln('MEDIÇÕES');
  if (readings.isEmpty) b.writeln('Nenhuma medição registrada.');
  for (final r in readings) {
    final ev = evaluate(
        setMa: r.setMa,
        setMs: r.setMs,
        readMa: r.readMa,
        readMs: r.readMs,
        readMas: r.readMas,
        tol: tol);
    b.writeln('${fmtDateTime(r.when)} | ${r.isDemo ? '[${r.sourceLabel}] ' : ''}disparo ${r.shotId} | '
        'mA ${fmt(r.readMa)} (${fmtSigned(ev.errMa)} %) | ms ${fmt(r.readMs)} (${fmtSigned(ev.errMs)} %) | '
        'mAs ${fmt(r.readMas)} (${fmtSigned(ev.errMas)} %) | ${r.isDemo ? 'SIMULADO' : ev.status.label}');
  }
  b
    ..writeln('')
    ..writeln('O X-METER CONNECT apenas registra medições; não comanda o gerador de raios X.');
  return b.toString();
}

// Cálculos puros do X-METER CONNECT (sem dependência de Flutter),
// testados em test/calc_test.dart.

/// mAs SET = mA SET × tempo SET / 1000
double masFrom(double ma, double ms) => ma * ms / 1000.0;

/// Erro percentual do valor lido em relação ao programado.
/// Retorna null quando o valor programado é zero ou inválido.
double? errorPercent(double set, double read) {
  if (!set.isFinite || !read.isFinite || set == 0) return null;
  return (read - set) / set * 100.0;
}

enum MeasureStatus { approved, alert, failed, unknown }

extension MeasureStatusText on MeasureStatus {
  String get code => switch (this) {
        MeasureStatus.approved => 'approved',
        MeasureStatus.alert => 'alert',
        MeasureStatus.failed => 'failed',
        MeasureStatus.unknown => 'unknown',
      };

  String get label => switch (this) {
        MeasureStatus.approved => 'APROVADO',
        MeasureStatus.alert => 'ALERTA',
        MeasureStatus.failed => 'REPROVADO',
        MeasureStatus.unknown => 'SEM DADOS',
      };

  static MeasureStatus fromCode(String? code) => switch (code) {
        'approved' => MeasureStatus.approved,
        'alert' => MeasureStatus.alert,
        'failed' => MeasureStatus.failed,
        _ => MeasureStatus.unknown,
      };
}

/// Tolerâncias em % (±) para cada grandeza.
/// [alertFraction] define a faixa amarela: a partir dessa fração da
/// tolerância o resultado é ALERTA; acima da tolerância é REPROVADO.
class Tolerances {
  final double maPct;
  final double msPct;
  final double masPct;
  final double alertFraction;

  const Tolerances({
    this.maPct = 10,
    this.msPct = 10,
    this.masPct = 10,
    this.alertFraction = 0.8,
  });
}

MeasureStatus classifyError(double? errPct, double tolPct, double alertFraction) {
  if (errPct == null || !errPct.isFinite || tolPct <= 0) return MeasureStatus.unknown;
  final e = errPct.abs();
  // Pequena margem para evitar que arredondamento de ponto flutuante
  // reprove um valor exatamente no limite (ex.: 10,000000001 %).
  const eps = 1e-9;
  if (e > tolPct + eps) return MeasureStatus.failed;
  if (e > tolPct * alertFraction + eps) return MeasureStatus.alert;
  return MeasureStatus.approved;
}

MeasureStatus worst(Iterable<MeasureStatus> all) {
  var result = MeasureStatus.approved;
  var any = false;
  for (final s in all) {
    if (s == MeasureStatus.unknown) continue;
    any = true;
    if (s == MeasureStatus.failed) return MeasureStatus.failed;
    if (s == MeasureStatus.alert) result = MeasureStatus.alert;
  }
  return any ? result : MeasureStatus.unknown;
}

class Evaluation {
  final double? errMa;
  final double? errMs;
  final double? errMas;
  final MeasureStatus status;
  const Evaluation(this.errMa, this.errMs, this.errMas, this.status);
}

Evaluation evaluate({
  required double setMa,
  required double setMs,
  required double readMa,
  required double readMs,
  required double readMas,
  required Tolerances tol,
}) {
  final eMa = errorPercent(setMa, readMa);
  final eMs = errorPercent(setMs, readMs);
  final eMas = errorPercent(masFrom(setMa, setMs), readMas);
  final status = worst([
    classifyError(eMa, tol.maPct, tol.alertFraction),
    classifyError(eMs, tol.msPct, tol.alertFraction),
    classifyError(eMas, tol.masPct, tol.alertFraction),
  ]);
  return Evaluation(eMa, eMs, eMas, status);
}

/// Aceita "200", "200,5" ou "200.5". Retorna null para entradas inválidas.
double? parseNum(String text) {
  final v = double.tryParse(text.trim().replaceAll(',', '.'));
  if (v == null || !v.isFinite) return null;
  return v;
}

/// Formata no padrão brasileiro: 20.0 -> "20,00".
String fmt(double? v, [int decimals = 2]) {
  if (v == null || !v.isFinite) return '—';
  return v.toStringAsFixed(decimals).replaceAll('.', ',');
}

String fmtSigned(double? v, [int decimals = 2]) {
  if (v == null || !v.isFinite) return '—';
  final s = fmt(v, decimals);
  return v > 0 ? '+$s' : s;
}

String two(int n) => n.toString().padLeft(2, '0');

String fmtDateTime(DateTime? d) {
  if (d == null) return '—';
  final l = d.toLocal();
  return '${two(l.day)}/${two(l.month)}/${l.year} ${two(l.hour)}:${two(l.minute)}:${two(l.second)}';
}

String fmtDate(DateTime? d) {
  if (d == null) return '—';
  final l = d.toLocal();
  return '${two(l.day)}/${two(l.month)}/${l.year}';
}

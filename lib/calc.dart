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

/// Formata sem zeros desnecessários: 200 -> "200", 12.5 -> "12,5", 1.25 -> "1,25".
String fmtTrim(double v) {
  if (v % 1 == 0) return v.toStringAsFixed(0);
  var t = v.toStringAsFixed(2);
  while (t.endsWith('0')) {
    t = t.substring(0, t.length - 1);
  }
  return t.replaceAll('.', ',');
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

// ---------------------------------------------------------------------------
// Tipos de gerador, faixas de referência e estações de mA / tempo (setas ▲▼)
// ---------------------------------------------------------------------------

/// Faixa-alvo do instrumento UNITECH X-METER (requisito de projeto,
/// ainda não comprovado metrologicamente).
class InstrumentRange {
  static const minMa = 1.0;
  static const maxMa = 1500.0;
  static const minMs = 1.0;
  static const maxMs = 10000.0;
  static const minMas = 0.01;
  static const maxMas = 2000.0;
}

/// Limites de um gerador. Vêm do manual técnico do aparelho; quando não
/// informados, usam-se as faixas de referência do tipo de gerador.
class GeneratorLimits {
  final double minMa;
  final double maxMa;
  final double minMs;
  final double maxMs;
  final double maxMas;
  const GeneratorLimits(this.minMa, this.maxMa, this.minMs, this.maxMs, this.maxMas);

  /// Mensagem de erro se o SET estiver fora dos limites, ou null.
  String? check(double ma, double ms) {
    if (ma < minMa || ma > maxMa) return 'mA SET fora da faixa do gerador (${fmtTrim(minMa)} a ${fmtTrim(maxMa)} mA)';
    if (ms < minMs || ms > maxMs) return 'Tempo SET fora da faixa do gerador (${fmtTrim(minMs)} a ${fmtTrim(maxMs)} ms)';
    final mas = masFrom(ma, ms);
    if (mas > maxMas) return 'mAs SET ${fmt(mas)} excede o limite do gerador (${fmtTrim(maxMas)} mAs)';
    if (mas < InstrumentRange.minMas) return 'mAs SET abaixo da faixa do instrumento';
    return null;
  }
}

enum GeneratorType { highFrequency, singlePhase2p, threePhase6p, threePhase12p, unknown }

extension GeneratorTypeInfo on GeneratorType {
  String get code => switch (this) {
        GeneratorType.highFrequency => 'hf',
        GeneratorType.singlePhase2p => 'mono2p',
        GeneratorType.threePhase6p => 'tri6p',
        GeneratorType.threePhase12p => 'tri12p',
        GeneratorType.unknown => 'unknown',
      };

  String get label => switch (this) {
        GeneratorType.highFrequency => 'Alta frequência (HF)',
        GeneratorType.singlePhase2p => 'Convencional monofásico 2 pulsos',
        GeneratorType.threePhase6p => 'Convencional trifásico 6 pulsos',
        GeneratorType.threePhase12p => 'Convencional trifásico 12 pulsos',
        GeneratorType.unknown => 'A identificar / outro',
      };

  String get shortLabel => switch (this) {
        GeneratorType.highFrequency => 'HF',
        GeneratorType.singlePhase2p => 'Mono 2P',
        GeneratorType.threePhase6p => 'Tri 6P',
        GeneratorType.threePhase12p => 'Tri 12P',
        GeneratorType.unknown => 'A identificar',
      };

  bool get isConventional => switch (this) {
        GeneratorType.singlePhase2p || GeneratorType.threePhase6p || GeneratorType.threePhase12p => true,
        _ => false,
      };

  /// 'conv' (V1.7) não dizia o número de pulsos: vira "A identificar",
  /// para não presumir a tecnologia instalada.
  static GeneratorType fromCode(String? code) => switch (code) {
        'hf' => GeneratorType.highFrequency,
        'mono2p' => GeneratorType.singlePhase2p,
        'tri6p' => GeneratorType.threePhase6p,
        'tri12p' => GeneratorType.threePhase12p,
        _ => GeneratorType.unknown,
      };

  /// Faixas comerciais de referência (não são limites universais).
  GeneratorLimits get referenceLimits => switch (this) {
        GeneratorType.highFrequency => const GeneratorLimits(10, 1000, 1, 6300, 1000),
        GeneratorType.unknown => const GeneratorLimits(
            InstrumentRange.minMa, InstrumentRange.maxMa, InstrumentRange.minMs, InstrumentRange.maxMs,
            InstrumentRange.maxMas),
        _ => const GeneratorLimits(25, 800, 10, 10000, 500),
      };

  /// Estações de corrente (mA).
  List<double> get maSteps => switch (this) {
        // Série R10 (Renard), comum em geradores de alta frequência.
        GeneratorType.highFrequency || GeneratorType.unknown => const <double>[
            1, 2, 5, 10, 12.5, 16, 20, 25, 32, 40, 50, 63, 80, 100, 125, 160, //
            200, 250, 320, 400, 500, 630, 800, 1000, 1250, 1500,
          ],
        // Estações comuns em comandos convencionais microprocessados.
        _ => const <double>[25, 50, 75, 100, 150, 200, 250, 300, 400, 500, 600, 700, 800],
      };

  /// Estações de tempo (ms).
  List<double> get msSteps => switch (this) {
        GeneratorType.highFrequency || GeneratorType.unknown => const <double>[
            1, 1.25, 1.6, 2, 2.5, 3.2, 4, 5, 6.3, 8, 10, 12.5, 16, 20, 25, 32, 40, 50, //
            63, 80, 100, 125, 160, 200, 250, 320, 400, 500, 630, 800, 1000, 1250, 1600,
            2000, 2500, 3200, 4000, 5000, 6300, 8000, 10000,
          ],
        _ => const <double>[
            10, 20, 30, 40, 50, 60, 80, 100, 120, 150, 200, 250, 300, 400, 500, //
            600, 800, 1000, 1200, 1500, 2000, 2500, 3000, 4000, 5000, 6000, 8000, 10000,
          ],
      };
}

/// Estações dentro dos limites do equipamento (sempre inclui os extremos).
List<double> stepsWithin(List<double> steps, double min, double max) {
  final inside = steps.where((v) => v >= min - 1e-9 && v <= max + 1e-9).toList();
  if (inside.isEmpty || inside.first > min + 1e-9) inside.insert(0, min);
  if (inside.last < max - 1e-9) inside.add(max);
  return inside;
}

/// Próxima estação da tabela acima (up = true) ou abaixo do valor atual.
/// Funciona mesmo quando o valor digitado não está na tabela.
double stepValue(List<double> steps, double current, {required bool up}) {
  const eps = 1e-9;
  if (up) {
    for (final s in steps) {
      if (s > current + eps) return s;
    }
    return steps.last;
  }
  for (final s in steps.reversed) {
    if (s < current - eps) return s;
  }
  return steps.first;
}

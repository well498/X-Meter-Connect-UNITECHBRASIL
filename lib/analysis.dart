// Processamento da forma de onda da corrente do tubo.
//
// Este arquivo é a REFERÊNCIA dos algoritmos que o firmware do STM32 deverá
// implementar. O aplicativo usa o mesmo código para:
//  - gerar as medições do MODO DEMONSTRAÇÃO;
//  - conferir as medições recebidas do instrumento a partir da forma de onda;
//  - calcular estatísticas de repetibilidade.
// Tudo em Dart puro, coberto por test/analysis_test.dart.

import 'dart:math';

/// Integral pela regra dos trapézios usando os instantes REAIS de cada amostra.
/// [tMs] em milissegundos, [ma] em mA. Resultado em mAs.
double trapezoidMas(List<double> tMs, List<double> ma, [int from = 0, int? to]) {
  final end = to ?? ma.length - 1;
  var acc = 0.0;
  for (var i = from + 1; i <= end; i++) {
    final dt = tMs[i] - tMs[i - 1];
    if (dt <= 0) continue; // amostra fora de ordem: ignorada
    acc += (ma[i] + ma[i - 1]) / 2 * dt;
  }
  return acc / 1000.0; // mA·ms -> mAs
}

/// Parâmetros da detecção de exposição (configuráveis).
class DetectionConfig {
  /// Início quando a corrente passa desta fração do pico (sobre a linha de base).
  final double startFraction;

  /// Fim do pulso (estado) quando a corrente cai abaixo desta fração —
  /// histerese, menor que o início. O TEMPO é medido sempre em [startFraction].
  final double endFraction;

  /// Exposições mais curtas que isso são tratadas como ruído/disparo inválido.
  final double minDurationMs;

  /// Corrente mínima de pico para considerar que houve exposição.
  final double minPeakMa;

  /// Quedas mais curtas que isso dentro da exposição não encerram a exposição
  /// (ondulação de geradores de 2 pulsos, por exemplo).
  final double gapToleranceMs;

  const DetectionConfig({
    this.startFraction = 0.50,
    this.endFraction = 0.40,
    this.minDurationMs = 0.5,
    this.minPeakMa = 0.5,
    this.gapToleranceMs = 9.0,
  });
}

enum ExposureFlag { noExposure, tooShort, startedBeforeWindow, endedAfterWindow, multiplePulses, noisyBaseline, saturated }

extension ExposureFlagText on ExposureFlag {
  String get code => name;
  String get label => switch (this) {
        ExposureFlag.noExposure => 'sem exposição detectada',
        ExposureFlag.tooShort => 'pulso curto demais (ruído)',
        ExposureFlag.startedBeforeWindow => 'exposição já em curso no início da janela',
        ExposureFlag.endedAfterWindow => 'exposição cortada no fim da janela',
        ExposureFlag.multiplePulses => 'mais de um pulso na janela',
        ExposureFlag.noisyBaseline => 'linha de base ruidosa',
        ExposureFlag.saturated => 'sinal saturado',
      };
}

class ExposureResult {
  final bool valid;
  final int startIndex;
  final int endIndex;

  /// Tempo de exposição (ms), medido entre os cruzamentos interpolados.
  final double timeMs;

  /// mAs integrado (trapézios) dentro da janela de exposição.
  final double mas;

  /// Corrente média = mAs / tempo (não é arredondamento de média × tempo).
  final double meanMa;
  final double peakMa;
  final double baselineMa;
  final List<ExposureFlag> flags;

  const ExposureResult({
    required this.valid,
    required this.startIndex,
    required this.endIndex,
    required this.timeMs,
    required this.mas,
    required this.meanMa,
    required this.peakMa,
    required this.baselineMa,
    required this.flags,
  });

  static const invalid = ExposureResult(
      valid: false,
      startIndex: 0,
      endIndex: 0,
      timeMs: 0,
      mas: 0,
      meanMa: 0,
      peakMa: 0,
      baselineMa: 0,
      flags: [ExposureFlag.noExposure]);
}

/// Maior valor mantido durante pelo menos [windowMs] (mínimo deslizante
/// seguido de máximo — "abertura" morfológica). O(n).
double sustainedPeak(List<double> tMs, List<double> v, double windowMs) {
  final n = v.length;
  if (n == 0) return 0;
  final dt = n > 1 ? (tMs[n - 1] - tMs[0]) / (n - 1) : 1.0;
  final w = dt > 0 ? max(1, (windowMs / dt).round()) : 1;
  final dq = List<int>.filled(n, 0);
  var head = 0, tail = 0;
  var best = double.negativeInfinity;
  for (var i = 0; i < n; i++) {
    while (tail > head && v[dq[tail - 1]] >= v[i]) {
      tail--;
    }
    dq[tail++] = i;
    if (dq[head] <= i - w) head++;
    if (i >= w - 1 && v[dq[head]] > best) best = v[dq[head]];
  }
  return best == double.negativeInfinity ? v.reduce(max) : best;
}

double _median(List<double> v) {
  if (v.isEmpty) return 0;
  final s = [...v]..sort();
  final m = s.length ~/ 2;
  return s.length.isOdd ? s[m] : (s[m - 1] + s[m]) / 2;
}

/// Detecta início e fim da exposição com limiares e histerese, rejeita
/// pulsos curtos e integra a corrente pelos trapézios.
ExposureResult detectExposure(List<double> tMs, List<double> ma,
    {DetectionConfig cfg = const DetectionConfig(), double? saturationMa}) {
  final n = ma.length;
  if (n < 3 || tMs.length != n) return ExposureResult.invalid;
  final flags = <ExposureFlag>[];

  // Linha de base: mediana dos primeiros 5 % das amostras (mín. 3).
  final nb = max(3, n ~/ 20);
  final baseline = _median(ma.sublist(0, nb));
  final corr = [for (final v in ma) v - baseline];
  // Nível de pico ROBUSTO: maior corrente mantida por pelo menos
  // minDurationMs. Picos isolados (ruído) não deslocam os limiares.
  final peak = sustainedPeak(tMs, corr, cfg.minDurationMs);
  if (peak < cfg.minPeakMa) return ExposureResult.invalid;
  if (saturationMa != null && ma.any((v) => v >= saturationMa)) flags.add(ExposureFlag.saturated);

  final noise = corr.sublist(0, nb).map((v) => v.abs()).reduce(max);
  if (noise > peak * 0.05) flags.add(ExposureFlag.noisyBaseline);

  final on = peak * cfg.startFraction;
  final off = peak * cfg.endFraction;

  // Máquina de estados com histerese; quedas curtas não encerram o pulso.
  final pulses = <List<int>>[];
  var inPulse = false;
  var start = 0;
  int? belowSince;
  for (var i = 0; i < n; i++) {
    final v = corr[i];
    if (!inPulse) {
      if (v >= on) {
        inPulse = true;
        start = i;
        belowSince = null;
      }
    } else {
      if (v < off) {
        belowSince ??= i;
        if (tMs[i] - tMs[belowSince] > cfg.gapToleranceMs) {
          pulses.add([start, belowSince]);
          inPulse = false;
          belowSince = null;
        }
      } else {
        belowSince = null;
      }
    }
  }
  if (inPulse) {
    pulses.add([start, belowSince ?? n - 1]);
    if (belowSince == null) flags.add(ExposureFlag.endedAfterWindow);
  }

  // Descarta pulsos curtos (ruído) e escolhe o de maior carga.
  double dur(List<int> p) => tMs[p[1]] - tMs[p[0]];
  final validPulses = pulses.where((p) => dur(p) >= cfg.minDurationMs).toList();
  if (validPulses.isEmpty) {
    return ExposureResult(
        valid: false,
        startIndex: 0,
        endIndex: 0,
        timeMs: 0,
        mas: 0,
        meanMa: 0,
        peakMa: peak + baseline,
        baselineMa: baseline,
        flags: [...flags, pulses.isEmpty ? ExposureFlag.noExposure : ExposureFlag.tooShort]);
  }
  if (validPulses.length > 1) flags.add(ExposureFlag.multiplePulses);
  validPulses.sort((a, b) => trapezoidMas(tMs, corr, b[0], b[1]).compareTo(trapezoidMas(tMs, corr, a[0], a[1])));
  final p = validPulses.first;
  if (corr[0] >= on) flags.add(ExposureFlag.startedBeforeWindow);

  // Cruzamentos interpolados linearmente (resolução abaixo do período de amostragem).
  double crossing(int i, double level) {
    if (i <= 0) return tMs[0];
    final v0 = corr[i - 1], v1 = corr[i];
    if (v1 == v0) return tMs[i];
    final f = ((level - v0) / (v1 - v0)).clamp(0.0, 1.0);
    return tMs[i - 1] + f * (tMs[i] - tMs[i - 1]);
  }

  // O tempo é medido no MESMO nível (startFraction) na subida e na descida;
  // a histerese (endFraction) serve só para não encerrar o pulso por ruído.
  final tStart = crossing(p[0], on);
  var last = p[0];
  for (var i = p[0]; i <= p[1]; i++) {
    if (corr[i] >= on) last = i;
  }
  final double tEnd;
  if (last >= n - 1) {
    tEnd = tMs[n - 1];
  } else {
    final v0 = corr[last], v1 = corr[last + 1];
    final f = v0 == v1 ? 0.0 : ((v0 - on) / (v0 - v1)).clamp(0.0, 1.0);
    tEnd = tMs[last] + f * (tMs[last + 1] - tMs[last]);
  }
  final timeMs = max(0.0, tEnd - tStart);

  // Integra a carga da exposição inteira (inclui subida e descida) entre os
  // pontos em que a corrente sai e volta à linha de base.
  var a = p[0];
  while (a > 0 && corr[a - 1] > off * 0.1) {
    a--;
  }
  var b = p[1];
  while (b < n - 1 && corr[b + 1] > off * 0.1) {
    b++;
  }
  final mas = trapezoidMas(tMs, corr, max(0, a - 1), min(n - 1, b + 1));
  final peakIn = corr.sublist(p[0], p[1] + 1).reduce(max) + baseline;

  return ExposureResult(
    valid: !flags.contains(ExposureFlag.saturated),
    startIndex: p[0],
    endIndex: p[1],
    timeMs: timeMs,
    mas: mas,
    meanMa: timeMs > 0 ? mas * 1000 / timeMs : 0,
    peakMa: peakIn,
    baselineMa: baseline,
    flags: flags,
  );
}

/// Instantes (ms) de amostras com período fixo.
List<double> uniformTimes(int count, double periodUs) =>
    [for (var i = 0; i < count; i++) i * periodUs / 1000.0];

// ---------------- Estatística de repetibilidade ----------------

class Stats {
  final int n;
  final double mean;

  /// Desvio padrão amostral (n − 1).
  final double sd;
  final double min;
  final double max;
  const Stats(this.n, this.mean, this.sd, this.min, this.max);

  /// Coeficiente de variação em %.
  double? get cvPct => n < 2 || mean == 0 ? null : sd / mean.abs() * 100;
}

Stats? stats(Iterable<double> values) {
  final v = values.where((x) => x.isFinite).toList();
  if (v.isEmpty) return null;
  final mean = v.reduce((a, b) => a + b) / v.length;
  final sd = v.length < 2
      ? 0.0
      : sqrt(v.map((x) => (x - mean) * (x - mean)).reduce((a, b) => a + b) / (v.length - 1));
  return Stats(v.length, mean, sd, v.reduce(min), v.reduce(max));
}

// ---------------- Diagnóstico da forma de onda ----------------

/// Indicadores da forma de onda de UMA exposição. São observações para o
/// técnico — o aplicativo nunca comanda ajustes no gerador.
class WaveDiagnostics {
  final double startMs;
  final double endMs;
  final double timeMs;
  final double mas;

  /// Pico na partida (primeiros 10 % da exposição) e quanto passa do patamar.
  final double initialPeakMa;
  final double initialPeakTimeMs;
  final double overshootPct;

  /// Corrente média no patamar (região estável, sem a partida e o fim).
  final double plateauMa;
  final double plateauStartMs;
  final double plateauEndMs;

  /// Oscilação: coeficiente de variação das amostras do patamar (%).
  final double rippleCvPct;

  /// Estabilidade: variação da média entre a 2ª e a 1ª metade do patamar (%).
  final double driftPct;

  final double peakMa;
  final double peakTimeMs;
  final List<String> observations;

  const WaveDiagnostics({
    required this.startMs,
    required this.endMs,
    required this.timeMs,
    required this.mas,
    required this.initialPeakMa,
    required this.initialPeakTimeMs,
    required this.overshootPct,
    required this.plateauMa,
    required this.plateauStartMs,
    required this.plateauEndMs,
    required this.rippleCvPct,
    required this.driftPct,
    required this.peakMa,
    required this.peakTimeMs,
    required this.observations,
  });
}

WaveDiagnostics? diagnoseWave(List<double> tMs, List<double> ma,
    {DetectionConfig cfg = const DetectionConfig(), double? setMa}) {
  final ex = detectExposure(tMs, ma, cfg: cfg);
  if (ex.timeMs <= 0 || ex.endIndex <= ex.startIndex) return null;
  final i0 = ex.startIndex, i1 = ex.endIndex;
  final n = i1 - i0;
  final startMs = tMs[i0];
  final endMs = startMs + ex.timeMs;
  // Partida: primeiros 10 % (mín. 1 amostra). Patamar: de 10 % a 95 %.
  final iPlat0 = i0 + max(1, (n * 0.10).round());
  final iPlat1 = max(iPlat0 + 1, i0 + (n * 0.95).round());
  var ip = i0;
  for (var i = i0; i <= min(iPlat0, ma.length - 1); i++) {
    if (ma[i] > ma[ip]) ip = i;
  }
  var pk = i0;
  for (var i = i0; i <= i1; i++) {
    if (ma[i] > ma[pk]) pk = i;
  }
  final plat = ma.sublist(iPlat0, min(iPlat1, ma.length));
  final st = stats(plat);
  final plateau = st?.mean ?? ex.meanMa;
  final half = plat.length ~/ 2;
  final a = half > 0 ? stats(plat.sublist(0, half))?.mean : null;
  final b = half > 0 ? stats(plat.sublist(half))?.mean : null;
  final drift = (a != null && b != null && a != 0) ? (b - a) / a * 100 : 0.0;
  final overshoot = plateau == 0 ? 0.0 : (ma[ip] - plateau) / plateau * 100;
  final ripple = st?.cvPct ?? 0.0;

  final obs = <String>[];
  if (overshoot > 10) {
    obs.add('Pico inicial ${overshoot.toStringAsFixed(1)} % acima do patamar (comportamento de partida da corrente).');
  }
  if (setMa != null && setMa > 0) {
    final dev = (plateau - setMa) / setMa * 100;
    if (dev.abs() > 5) {
      obs.add('Corrente do patamar ${dev > 0 ? '+' : ''}${dev.toStringAsFixed(1)} % em relação ao mA SET.');
    }
  }
  if (ripple > 5) obs.add('Oscilação no patamar: CV ${ripple.toStringAsFixed(1)} % (compare com a tecnologia do gerador).');
  if (drift.abs() > 3) {
    obs.add('Corrente ${drift > 0 ? 'sobe' : 'cai'} ${drift.abs().toStringAsFixed(1)} % ao longo da exposição (estabilidade).');
  }
  if (ex.flags.isNotEmpty) obs.add('Qualidade da aquisição: ${ex.flags.map((f) => f.label).join(', ')}.');

  return WaveDiagnostics(
    startMs: startMs,
    endMs: endMs,
    timeMs: ex.timeMs,
    mas: ex.mas,
    initialPeakMa: ma[ip],
    initialPeakTimeMs: tMs[ip],
    overshootPct: overshoot,
    plateauMa: plateau,
    plateauStartMs: tMs[iPlat0],
    plateauEndMs: tMs[min(iPlat1, tMs.length - 1)],
    rippleCvPct: ripple,
    driftPct: drift,
    peakMa: ma[pk],
    peakTimeMs: tMs[pk],
    observations: obs,
  );
}

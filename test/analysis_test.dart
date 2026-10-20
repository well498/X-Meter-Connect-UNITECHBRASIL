import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:unitech_xmeter_connect/analysis.dart';

/// Pulso trapezoidal com rampas centradas nas bordas: cruza 50 % do pico
/// exatamente em [pre] e [pre + timeMs].
({List<double> t, List<double> ma}) pulse({
  double ma = 200,
  double timeMs = 100,
  double rise = 1,
  double pre = 10,
  double post = 10,
  double dtMs = 0.01,
  double base = 0,
  double noise = 0,
  double Function(double t)? shape,
  int seed = 1,
}) {
  final rnd = Random(seed);
  final t = <double>[];
  final y = <double>[];
  final total = pre + timeMs + post;
  final n = (total / dtMs).round();
  for (var i = 0; i <= n; i++) {
    final tt = i * dtMs;
    final x = tt - pre;
    double env;
    if (x < -rise / 2 || x > timeMs + rise / 2) {
      env = 0;
    } else if (x < rise / 2) {
      env = (x + rise / 2) / rise;
    } else if (x > timeMs - rise / 2) {
      env = (timeMs + rise / 2 - x) / rise;
    } else {
      env = 1;
    }
    final g = noise == 0 ? 0.0 : noise * (rnd.nextDouble() * 2 - 1);
    t.add(tt);
    y.add(base + ma * env * (shape?.call(tt) ?? 1) + g);
  }
  return (t: t, ma: y);
}

void main() {
  group('integração pela regra dos trapézios', () {
    test('retângulo e triângulo exatos', () {
      expect(trapezoidMas([0, 50, 100], [200, 200, 200]), closeTo(20, 1e-12));
      expect(trapezoidMas([0, 10], [0, 100]), closeTo(0.5, 1e-12));
    });

    test('usa os intervalos reais entre amostras (não uniformes)', () {
      // 200 mA constante, amostras irregulares: 0, 1, 5, 20, 100 ms.
      expect(trapezoidMas([0, 1, 5, 20, 100], [200, 200, 200, 200, 200]), closeTo(20, 1e-12));
    });

    test('ignora o trecho com instante fora de ordem', () {
      // 0→50 ms (5 mAs) + 40→100 ms (6 mAs); o trecho 50→40 é descartado.
      expect(trapezoidMas([0, 50, 40, 100], [100, 100, 100, 100]), closeTo(11, 1e-9));
    });
  });

  group('detecção da exposição', () {
    test('200 mA × 100 ms a 100 kS/s = 20,00 mAs', () {
      final p = pulse();
      final ex = detectExposure(p.t, p.ma);
      expect(ex.valid, isTrue);
      expect(ex.timeMs, closeTo(100, 0.02));
      expect(ex.mas, closeTo(20, 0.01));
      expect(ex.meanMa, closeTo(200, 0.2));
      expect(ex.peakMa, closeTo(200, 0.01));
      expect(ex.flags, isEmpty);
    });

    test('exposição curta de 5 ms', () {
      final p = pulse(ma: 100, timeMs: 5, rise: 0.2, pre: 2, post: 2);
      final ex = detectExposure(p.t, p.ma);
      expect(ex.timeMs, closeTo(5, 0.02));
      expect(ex.mas, closeTo(0.5, 0.002));
    });

    test('amostragem grossa (2 kS/s) ainda interpola o tempo', () {
      final p = pulse(dtMs: 0.5);
      final ex = detectExposure(p.t, p.ma);
      expect(ex.timeMs, closeTo(100, 0.3));
      expect(ex.mas, closeTo(20, 0.05));
    });

    test('linha de base é descontada', () {
      final p = pulse(base: 3);
      final ex = detectExposure(p.t, p.ma);
      expect(ex.baselineMa, closeTo(3, 1e-9));
      expect(ex.mas, closeTo(20, 0.01));
    });

    test('pico isolado de ruído não altera o limiar nem o tempo', () {
      final p = pulse();
      for (var i = 5000; i < 5010; i++) {
        p.ma[i] += 300; // 0,1 ms de interferência no meio da exposição
      }
      final ex = detectExposure(p.t, p.ma);
      expect(ex.timeMs, closeTo(100, 0.05));
      expect(ex.peakMa, greaterThan(400), reason: 'a corrente máxima registra o pico real');
    });

    test('pulso curto demais é rejeitado como ruído', () {
      final p = pulse(timeMs: 0.2, rise: 0.02, pre: 5, post: 5);
      final ex = detectExposure(p.t, p.ma, cfg: const DetectionConfig(minDurationMs: 0.5));
      expect(ex.valid, isFalse);
      expect(ex.flags, anyOf(contains(ExposureFlag.tooShort), contains(ExposureFlag.noExposure)));
    });

    test('sem exposição', () {
      final t = [for (var i = 0; i < 1000; i++) i * 0.1];
      final ex = detectExposure(t, List.filled(1000, 0.1));
      expect(ex.valid, isFalse);
      expect(ex.flags, contains(ExposureFlag.noExposure));
    });

    test('gerador monofásico de 2 pulsos (vai a zero a cada semiciclo) é UMA exposição', () {
      final p = pulse(
        ma: 200,
        timeMs: 100,
        shape: (t) => (sin(2 * pi * 60 * t / 1000)).abs() * pi / 2,
      );
      final ex = detectExposure(p.t, p.ma);
      expect(ex.valid, isTrue);
      expect(ex.flags, isNot(contains(ExposureFlag.multiplePulses)));
      expect(ex.mas, closeTo(20, 0.6), reason: 'média da retificação de onda completa preservada');
      expect(ex.timeMs, greaterThan(90));
    });

    test('dois disparos na mesma janela são sinalizados', () {
      final a = pulse(timeMs: 20, post: 40);
      final y = [...a.ma];
      // Segundo pulso de 20 ms começando em 50 ms.
      for (var i = 0; i < a.t.length; i++) {
        if (a.t[i] >= 50 && a.t[i] <= 65) y[i] = 200;
      }
      final ex = detectExposure(a.t, y);
      expect(ex.flags, contains(ExposureFlag.multiplePulses));
      expect(ex.timeMs, closeTo(20, 0.05), reason: 'mede o pulso de maior carga');
    });

    test('exposição cortada no fim da janela', () {
      final p = pulse(post: 0, timeMs: 50, rise: 0.4);
      final cut = p.ma.sublist(0, p.ma.length - 2000);
      final ex = detectExposure(p.t.sublist(0, cut.length), cut);
      expect(ex.flags, contains(ExposureFlag.endedAfterWindow));
    });

    test('saturação invalida a medição', () {
      final p = pulse();
      final ex = detectExposure(p.t, p.ma, saturationMa: 199);
      expect(ex.flags, contains(ExposureFlag.saturated));
      expect(ex.valid, isFalse);
    });
  });

  group('estatística de repetibilidade', () {
    test('média, desvio padrão amostral e CV', () {
      final s = stats([20.0, 20.2, 19.8, 20.0])!;
      expect(s.n, 4);
      expect(s.mean, closeTo(20, 1e-12));
      expect(s.sd, closeTo(sqrt(0.08 / 3), 1e-12));
      expect(s.cvPct, closeTo(sqrt(0.08 / 3) / 20 * 100, 1e-9));
      expect(s.min, 19.8);
      expect(s.max, 20.2);
    });

    test('um só valor não tem CV; lista vazia não tem estatística', () {
      expect(stats([5])!.cvPct, isNull);
      expect(stats([]), isNull);
      expect(stats([double.nan]), isNull);
    });
  });

  group('diagnóstico da forma de onda', () {
    test('pico inicial, patamar, tempo e mAs', () {
      final p = pulse(ma: 200, timeMs: 100, rise: 0.5);
      // Pico de partida: +30 % nos primeiros 3 ms da exposição.
      for (var i = 0; i < p.t.length; i++) {
        if (p.t[i] >= 10.3 && p.t[i] < 13) p.ma[i] = 260;
      }
      final d = diagnoseWave(p.t, p.ma, setMa: 200)!;
      expect(d.initialPeakMa, closeTo(260, 0.01));
      expect(d.overshootPct, closeTo(30, 1));
      expect(d.plateauMa, closeTo(200, 0.5));
      expect(d.timeMs, closeTo(100, 0.2), reason: 'limiar a 50 % do pico inicial');
      expect(d.startMs, closeTo(10, 0.1));
      expect(d.observations.any((o) => o.contains('Pico inicial')), isTrue);
    });

    test('corrente que sobe durante a exposição é indicada (estabilidade)', () {
      final p = pulse(ma: 200, timeMs: 100, shape: (t) => t < 10 ? 1.0 : 1 + 0.12 * (t - 10) / 100);
      final d = diagnoseWave(p.t, p.ma, setMa: 200)!;
      expect(d.driftPct, greaterThan(3));
      expect(d.observations.any((o) => o.contains('estabilidade')), isTrue);
    });

    test('patamar fora do mA SET gera observação, sem comando de ajuste', () {
      final p = pulse(ma: 230, timeMs: 50);
      final d = diagnoseWave(p.t, p.ma, setMa: 200)!;
      expect(d.observations.any((o) => o.contains('mA SET')), isTrue);
      expect(d.observations.join(' ').toLowerCase(), isNot(contains('ajuste o')));
    });

    test('pulso limpo de alta frequência não gera observações', () {
      final p = pulse();
      final d = diagnoseWave(p.t, p.ma, setMa: 200)!;
      expect(d.observations, isEmpty);
      expect(d.rippleCvPct, lessThan(0.5));
    });

    test('sem exposição não há diagnóstico', () {
      final t = [for (var i = 0; i < 500; i++) i * 0.1];
      expect(diagnoseWave(t, List.filled(500, 0.0)), isNull);
    });
  });
}

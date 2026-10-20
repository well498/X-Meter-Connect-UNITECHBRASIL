import 'package:flutter_test/flutter_test.dart';
import 'package:unitech_xmeter_connect/calc.dart';

void main() {
  group('mAs SET', () {
    test('200 mA × 100 ms = 20,00 mAs', () {
      expect(masFrom(200, 100), closeTo(20.0, 1e-12));
      expect(fmt(masFrom(200, 100)), '20,00');
    });

    test('outros valores', () {
      expect(masFrom(100, 50), closeTo(5.0, 1e-12));
      expect(masFrom(320, 6.3), closeTo(2.016, 1e-12));
      expect(fmt(masFrom(320, 6.3)), '2,02');
    });
  });

  group('entrada numérica', () {
    test('aceita vírgula e ponto', () {
      expect(parseNum('200'), 200);
      expect(parseNum('12,5'), 12.5);
      expect(parseNum(' 12.5 '), 12.5);
    });
    test('rejeita texto inválido', () {
      expect(parseNum(''), isNull);
      expect(parseNum('abc'), isNull);
      expect(parseNum('NaN'), isNull);
      expect(parseNum('Infinity'), isNull);
    });
  });

  group('erro e classificação', () {
    test('erro percentual', () {
      expect(errorPercent(20, 21), closeTo(5.0, 1e-9));
      expect(errorPercent(20, 19), closeTo(-5.0, 1e-9));
      expect(errorPercent(0, 5), isNull);
    });

    test('faixas verde / amarelo / vermelho (tol 10 %, alerta 80 %)', () {
      expect(classifyError(0, 10, 0.8), MeasureStatus.approved);
      expect(classifyError(-8, 10, 0.8), MeasureStatus.approved);
      expect(classifyError(8.5, 10, 0.8), MeasureStatus.alert);
      expect(classifyError(-10, 10, 0.8), MeasureStatus.alert);
      expect(classifyError(10.01, 10, 0.8), MeasureStatus.failed);
      expect(classifyError(null, 10, 0.8), MeasureStatus.unknown);
    });

    test('resultado geral é o pior entre mA, ms e mAs', () {
      final ok = evaluate(
          setMa: 200, setMs: 100, readMa: 201, readMs: 100, readMas: 20.1, tol: const Tolerances());
      expect(ok.status, MeasureStatus.approved);
      expect(ok.errMas, closeTo(0.5, 1e-9));

      final failMs = evaluate(
          setMa: 200, setMs: 100, readMa: 200, readMs: 115, readMas: 20.2, tol: const Tolerances());
      expect(failMs.status, MeasureStatus.failed);
    });
  });

  test('formatação brasileira', () {
    expect(fmt(1234.5), '1234,50');
    expect(fmtSigned(2.5), '+2,50');
    expect(fmtSigned(-2.5), '-2,50');
    expect(fmt(null), '—');
  });

  group('setas ▲▼ e estações padrão', () {
    test('alta frequência: série R10 até 800 mA', () {
      final t = GeneratorType.highFrequency;
      expect(t.maxMa, 800);
      expect(stepValue(t.maSteps, 200, up: true), 250);
      expect(stepValue(t.maSteps, 200, up: false), 160);
      expect(stepValue(t.msSteps, 100, up: true), 125);
      expect(stepValue(t.msSteps, 100, up: false), 80);
      expect(stepValue(t.maSteps, 800, up: true), 800, reason: 'não passa do máximo');
      expect(stepValue(t.maSteps, 10, up: false), 10, reason: 'não passa do mínimo');
    });

    test('convencional microprocessado', () {
      final t = GeneratorType.conventional;
      expect(t.maxMa, 800);
      expect(t.msSteps.first, 10);
      expect(stepValue(t.maSteps, 200, up: true), 250);
      expect(stepValue(t.maSteps, 200, up: false), 150);
      expect(stepValue(t.msSteps, 100, up: true), 120);
    });

    test('valor digitado fora da tabela vai para a estação vizinha', () {
      final steps = GeneratorType.highFrequency.maSteps;
      expect(stepValue(steps, 210, up: true), 250);
      expect(stepValue(steps, 210, up: false), 200);
    });

    test('todas as tabelas em ordem crescente e mA ≤ 800', () {
      for (final t in GeneratorType.values) {
        for (final list in [t.maSteps, t.msSteps]) {
          for (var i = 1; i < list.length; i++) {
            expect(list[i] > list[i - 1], isTrue);
          }
        }
        expect(t.maSteps.every((v) => v <= 800), isTrue);
      }
    });

    test('formatação das estações', () {
      expect(fmtTrim(200), '200');
      expect(fmtTrim(12.5), '12,5');
      expect(fmtTrim(1.25), '1,25');
      expect(fmtTrim(6.3), '6,3');
    });
  });
}

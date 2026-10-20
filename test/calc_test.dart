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

  group('tipos de gerador, limites e setas ▲▼', () {
    test('5 tipos e códigos; "conv" antigo vira "a identificar"', () {
      expect(GeneratorType.values, hasLength(5));
      for (final t in GeneratorType.values) {
        expect(GeneratorTypeInfo.fromCode(t.code), t);
      }
      expect(GeneratorTypeInfo.fromCode('conv'), GeneratorType.unknown);
      expect(GeneratorTypeInfo.fromCode(null), GeneratorType.unknown);
      expect(GeneratorType.threePhase6p.isConventional, isTrue);
      expect(GeneratorType.highFrequency.isConventional, isFalse);
      expect(GeneratorType.unknown.isConventional, isFalse);
    });

    test('faixas de referência', () {
      final hf = GeneratorType.highFrequency.referenceLimits;
      expect([hf.minMa, hf.maxMa, hf.minMs, hf.maxMs, hf.maxMas], [10, 1000, 1, 6300, 1000]);
      final conv = GeneratorType.singlePhase2p.referenceLimits;
      expect(conv.maxMa, 800);
      expect(conv.maxMas, 500);
      final unk = GeneratorType.unknown.referenceLimits;
      expect([unk.maxMa, unk.maxMs, unk.maxMas], [InstrumentRange.maxMa, InstrumentRange.maxMs, InstrumentRange.maxMas]);
    });

    test('setas seguem as estações R10 em HF', () {
      final st = GeneratorType.highFrequency.maSteps;
      expect(stepValue(st, 200, up: true), 250);
      expect(stepValue(st, 200, up: false), 160);
      expect(stepValue(GeneratorType.highFrequency.msSteps, 100, up: true), 125);
      expect(stepValue(GeneratorType.highFrequency.msSteps, 100, up: false), 80);
      expect(stepValue(st, 210, up: true), 250);
      expect(stepValue(st, 210, up: false), 200);
    });

    test('setas em convencional', () {
      final st = GeneratorType.threePhase12p.maSteps;
      expect(stepValue(st, 200, up: true), 250);
      expect(stepValue(st, 200, up: false), 150);
      expect(stepValue(GeneratorType.threePhase12p.msSteps, 100, up: true), 120);
    });

    test('estações limitadas pelos limites do manual', () {
      final st = stepsWithin(GeneratorType.highFrequency.maSteps, 25, 500);
      expect(st.first, 25);
      expect(st.last, 500);
      expect(stepValue(st, 500, up: true), 500, reason: 'não passa do máximo do aparelho');
      final odd = stepsWithin(GeneratorType.highFrequency.maSteps, 30, 450);
      expect(odd.first, 30);
      expect(odd.last, 450);
    });

    test('tabelas em ordem crescente', () {
      for (final t in GeneratorType.values) {
        for (final list in [t.maSteps, t.msSteps]) {
          for (var i = 1; i < list.length; i++) {
            expect(list[i] > list[i - 1], isTrue);
          }
        }
      }
    });

    test('verificação do SET contra os limites', () {
      const lim = GeneratorLimits(25, 500, 10, 5000, 400);
      expect(lim.check(200, 100), isNull);
      expect(lim.check(600, 100), contains('mA'));
      expect(lim.check(200, 6000), contains('Tempo'));
      expect(lim.check(500, 1000), contains('mAs'), reason: '500 mA × 1 s = 500 mAs > 400');
    });

    test('formatação das estações', () {
      expect(fmtTrim(200), '200');
      expect(fmtTrim(12.5), '12,5');
      expect(fmtTrim(1.25), '1,25');
      expect(fmtTrim(6.3), '6,3');
    });
  });

  group('critério de aceitação com parcela absoluta (perfil SAWAE ALTUS)', () {
    const sawae = Tolerances(maPct: 0, msPct: 0, masPct: 10, masAbs: 0.2, origin: 'Manual ALTUS', version: 'rev. 19');

    test('20 mAs: tolerância 2,2 mAs e aceitação de 17,8 a 22,2 mAs', () {
      expect(sawae.masTolerance(20), closeTo(2.2, 1e-12));
      final (lo, hi) = sawae.masInterval(20);
      expect(lo, closeTo(17.8, 1e-12));
      expect(hi, closeTo(22.2, 1e-12));
      expect(fmt(lo), '17,80');
      expect(fmt(hi), '22,20');
      expect(sawae.masRule, '±(10 % + 0,2 mAs)');
      expect(sawae.originText, 'Manual ALTUS, versão rev. 19');
    });

    Evaluation ev(double readMas) =>
        evaluate(setMa: 200, setMs: 100, readMa: 200, readMs: 100, readMas: readMas, tol: sawae);

    test('classificação nos limites do intervalo', () {
      expect(ev(20).status, MeasureStatus.approved);
      expect(ev(22.2).status, isNot(MeasureStatus.failed), reason: 'limite superior aceito');
      expect(ev(17.8).status, isNot(MeasureStatus.failed), reason: 'limite inferior aceito');
      expect(ev(22.25).status, MeasureStatus.failed);
      expect(ev(17.7).status, MeasureStatus.failed);
    });

    test('mA e tempo sem critério documentado não reprovam', () {
      final e = evaluate(setMa: 200, setMs: 100, readMa: 260, readMs: 77, readMas: 20.0, tol: sawae);
      expect(e.status, MeasureStatus.approved);
      expect(e.errMa, closeTo(30, 1e-9), reason: 'erro de mA continua sendo calculado e exibido');
    });

    test('parcela absoluta pesa mais em mAs baixos', () {
      expect(sawae.masTolerance(0.4), closeTo(0.24, 1e-12));
      expect(sawae.masEffectivePct(0.4), closeTo(60, 1e-9));
    });
  });

  group('faixa do instrumento', () {
    test('valores dentro e fora da faixa', () {
      expect(InstrumentRange.check(200, 100, 20), isNull);
      expect(InstrumentRange.check(200, 100, 2500), contains('mAs'));
      expect(InstrumentRange.check(1600, 100, 160), contains('corrente'));
      expect(InstrumentRange.check(200, 12000, 1500), contains('tempo'));
      expect(InstrumentRange.check(10, 0.5, 0.005), isNotNull);
    });

    test('limite mínimo de mAs do gerador', () {
      const lim = GeneratorLimits(80, 630, 1, 6300, 500, minMas: 0.4);
      expect(lim.check(80, 3), contains('mínimo'), reason: '80 mA × 3 ms = 0,24 mAs < 0,4');
      expect(lim.check(80, 5), isNull);
    });

    test('status inválido prevalece', () {
      expect(worst([MeasureStatus.approved, MeasureStatus.invalid]), MeasureStatus.invalid);
      expect(MeasureStatusText.fromCode('invalid'), MeasureStatus.invalid);
    });

    test('tempo em ms ou s', () {
      expect(fmtTime(100), '100,0');
      expect(fmtTime(100, seconds: true), '0,100');
      expect(fmtTime(2.5), '2,50');
    });
  });
}

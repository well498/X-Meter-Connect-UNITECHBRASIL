import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:unitech_xmeter_connect/calc.dart';
import 'package:unitech_xmeter_connect/models.dart';
import 'package:unitech_xmeter_connect/reports.dart';
import 'package:unitech_xmeter_connect/reports_pdf.dart';

Reading reading(String shot, double mas, {String source = 'device', List<String> quality = const []}) =>
    Reading.fromMap({
      'uid': 'rd-$shot',
      'device_id': source == 'device' ? 'XM-1' : 'DEMO',
      'shot_id': shot,
      'session_id': 'ses-1',
      'equipment_id': 'eq-1',
      'source': source,
      'set_ma': 200.0,
      'set_ms': 100.0,
      'read_ma': 200.0,
      'read_ms': 100.0,
      'read_mas': mas,
      'status': 'approved',
      'tol_ma': 0.0,
      'tol_ms': 0.0,
      'tol_mas': 10.0,
      'tol_mas_abs': 0.2,
      'alert_fraction': 0.8,
      'tol_origin': 'Manual ALTUS, versão rev. 19',
      'quality': quality.isEmpty ? null : jsonEncode(quality),
      'waveform': jsonEncode({
        'sample_period_us': 100,
        'ma': [for (var i = 0; i < 1200; i++) (i >= 100 && i < 1100) ? 200.0 : 0.0],
      }),
      'recorded_at': '2026-10-20T13:00:00Z',
      'received_at': '2026-10-20T13:00:01Z',
    });

void main() {
  final eq = Equipment(
    id: 'eq-1',
    client: 'Hospital Teste',
    manufacturer: 'SAWAE',
    model: 'ALTUS',
    generatorType: GeneratorType.highFrequency,
    profileId: BuiltinProfiles.sawaeAltusId,
    tubeMaker: 'Toshiba',
    tubeModel: 'E7242FX',
    technician: 'Técnico UNITECH',
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
  final session = MeasureSession(
    id: 'ses-1',
    equipmentId: 'eq-1',
    setMa: 200,
    setMs: 100,
    setPending: false,
    startedAt: DateTime(2026, 10, 20, 10),
    tubeModel: 'Toshiba E7242FX',
    kvInfo: '70 kV',
  );

  test('relatório técnico em PDF é gerado com SAWAE, inválidas e simuladas', () async {
    final readings = [
      reading('1', 20.1),
      reading('2', 22.5),
      reading('3', 2500, quality: ['fora_da_faixa']),
      reading('4', 19.9, source: 'demo'),
    ];
    final bytes = await buildPdfReport(
      eq: eq,
      session: session,
      readings: readings,
      notes: [Note(1, 'ses-1', 'rd-1', 'Colimador conferido — ok', DateTime(2026, 10, 20, 10, 5))],
      tol: BuiltinProfiles.sawaeAltus.tolerances,
      includesSimulated: true,
      appVersion: 'teste',
      profile: BuiltinProfiles.sawaeAltus,
      limits: BuiltinProfiles.sawaeAltus.limits,
    );
    expect(bytes.length, greaterThan(2000));
    expect(ascii.decode(bytes.sublist(0, 5)), '%PDF-');
  });

  test('resumo conta aprovadas, reprovadas e inválidas pelo critério gravado', () {
    final s = summarize([reading('1', 20.1), reading('2', 22.5), reading('3', 2500, quality: ['fora_da_faixa'])],
        const Tolerances());
    expect(s.total, 3);
    expect(s.approved, 1);
    expect(s.failed, 1, reason: '22,5 mAs passa de 22,2 (±(10 % + 0,2))');
    expect(s.invalid, 1);
  });

  test('CSV traz a tolerância aplicada e a origem do critério', () {
    final csv = buildCsv(eq, [reading('1', 20.1)], const Tolerances());
    expect(csv, contains('±(10 % + 0,2 mAs)'));
    expect(csv, contains('ALTUS'));
  });
}

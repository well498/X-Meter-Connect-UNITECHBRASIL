import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:unitech_xmeter_connect/calc.dart';
import 'package:unitech_xmeter_connect/database.dart';
import 'package:unitech_xmeter_connect/models.dart';

Map<String, Object?> shot(String id, {String session = seedSessionId, double mas = 20.1}) => {
      'shot_id': id,
      'session_id': session,
      'quality': 'valid',
      'set_ma': 200,
      'set_ms': 100,
      'read_ma': 201.0,
      'read_ms': 100.0,
      'read_mas': mas,
      'recorded_at': '2026-10-20T13:00:00Z',
    };

void main() {
  late Directory tmp;
  late String path;

  setUpAll(sqfliteFfiInit);

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('xmeter_test_');
    path = p.join(tmp.path, 'x.sqlite');
  });

  tearDown(() {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<XDatabase> open() => XDatabase.open(path, factory: databaseFactoryFfi);

  test('cadastro inicial Siemens Multix B com SET 200 mA / 100 ms = 20,00 mAs', () async {
    final db = await open();
    final eqs = await db.equipments();
    expect(eqs, hasLength(1));
    expect(eqs.single.manufacturer, 'Siemens');
    expect(eqs.single.model, 'Multix B');
    expect(eqs.single.serialNumber, isNull);
    expect(eqs.single.serialLabel, 'Não informado');
    final s = (await db.currentSession(seedEquipmentId))!;
    expect(s.setMa, 200);
    expect(s.setMs, 100);
    expect(fmt(s.setMas), '20,00');
    expect(s.setPending, isTrue);
    expect(await db.readings(), isEmpty, reason: 'nenhuma leitura fictícia na criação');
    await db.db.close();
  });

  test('edição de cadastro e SET persiste após fechar e reabrir', () async {
    var db = await open();
    final e = (await db.equipment(seedEquipmentId))!;
    await db.saveEquipment(Equipment(
      id: e.id,
      client: 'Hospital Teste',
      site: 'Sala 2',
      manufacturer: e.manufacturer,
      model: e.model,
      serialNumber: 'SN-123',
      internalId: 'RX-02',
      calibrationDate: DateTime(2026, 10, 20),
      technician: 'Técnico UNITECH',
      createdAt: e.createdAt,
      updatedAt: DateTime.now(),
    ));
    final ch = await db.changeSet(seedEquipmentId, 320, 6.3);
    expect(ch.newSession, isFalse, reason: 'sessão sem medições é só atualizada');
    await db.saveSettings(const AppSettings(host: '192.168.4.1', token: 'abc', demoMode: true));
    await db.db.close();

    db = await open();
    final again = (await db.equipment(seedEquipmentId))!;
    expect(again.client, 'Hospital Teste');
    expect(again.serialNumber, 'SN-123');
    expect(again.internalId, 'RX-02');
    expect(again.technician, 'Técnico UNITECH');
    expect(again.calibrationDate, DateTime(2026, 10, 20));
    final s = (await db.currentSession(seedEquipmentId))!;
    expect(s.setMa, 320);
    expect(s.setMs, 6.3);
    final st = await db.loadSettings();
    expect(st.token, 'abc');
    expect(st.demoMode, isTrue);
    expect((await db.equipments()), hasLength(1), reason: 'seed não deve duplicar');
    await db.db.close();
  });

  test('novo equipamento recebe sessão própria', () async {
    final db = await open();
    final now = DateTime.now();
    await db.saveEquipment(Equipment(
        id: 'eq-2', manufacturer: 'Philips', model: 'Digital Diagnost', createdAt: now, updatedAt: now));
    expect(await db.equipments(), hasLength(2));
    expect(await db.currentSession('eq-2'), isNotNull);
    await db.db.close();
  });

  test('sincronização não duplica medições e o cursor só avança', () async {
    final db = await open();
    const tol = Tolerances();
    var m = await db.mergeDeviceReadings('XM-1', 2, [shot('1'), shot('2', mas: 23)], tol);
    expect(m.inserted, 2);
    m = await db.mergeDeviceReadings('XM-1', 2, [shot('1'), shot('2', mas: 23)], tol);
    expect(m.inserted, 0);
    expect(m.duplicates, 2);
    m = await db.mergeDeviceReadings('XM-1', 1, [], tol);
    expect(await db.cursor('XM-1'), 2, reason: 'cursor não retrocede');

    final rs = await db.readings(equipmentId: seedEquipmentId);
    expect(rs, hasLength(2));
    expect(rs.map((r) => r.uid).toSet(), hasLength(2), reason: 'cada medição tem ID único');
    expect(rs.every((r) => r.source == 'device' && !r.isDemo), isTrue);
    final bad = rs.firstWhere((r) => r.shotId == '2');
    expect(bad.errMas, closeTo(15, 1e-9));
    expect(bad.status, MeasureStatus.failed);
    await db.db.close();
  });

  test('itens inválidos ou de sessão desconhecida são rejeitados', () async {
    final db = await open();
    final m = await db.mergeDeviceReadings('XM-1', 5, [
      {...shot('a'), 'quality': 'saturated'},
      {...shot('b'), 'read_mas': -1},
      {...shot('c'), 'read_ma': 'x'},
      shot('d', session: 'sessao-inexistente'),
      'lixo',
    ], const Tolerances());
    expect(m.inserted, 0);
    expect(m.rejected, 5);
    expect(await db.readings(), isEmpty);
    await db.db.close();
  });

  test('simulações ficam separadas das medições reais', () async {
    final db = await open();
    await db.mergeDeviceReadings('XM-1', 1, [shot('1')], const Tolerances());
    await db.mergeDeviceReadings('SIM', 1, [shot('1')], const Tolerances(), deviceSimulated: true);
    final s = (await db.session(seedSessionId))!;
    await db.insertDemoReading(
        session: s,
        readMa: 200,
        readMs: 100,
        readMas: 20,
        waveform: const Waveform(500, [0, 200, 200, 0]),
        tol: const Tolerances());
    final all = await db.readings();
    expect(all.where((r) => r.source == 'device'), hasLength(1));
    expect(all.where((r) => r.source == 'simulator'), hasLength(1));
    expect(all.where((r) => r.source == 'demo'), hasLength(1));
    expect(all.where((r) => r.isDemo), hasLength(2));
    expect(await db.deleteDemoReadings(), 2);
    final left = await db.readings();
    expect(left, hasLength(1));
    expect(left.single.source, 'device');
    await db.db.close();
  });

  test('migração automática do banco da V1.5', () async {
    final v1 = await databaseFactoryFfi.openDatabase(path,
        options: OpenDatabaseOptions(
            version: 1,
            onCreate: (d, _) async {
              await d.execute('''CREATE TABLE equipment (id TEXT PRIMARY KEY, manufacturer TEXT NOT NULL,
                model TEXT NOT NULL, serial_number TEXT, created_at TEXT NOT NULL)''');
              await d.execute('''CREATE TABLE sessions (id TEXT PRIMARY KEY, equipment_id TEXT NOT NULL,
                set_ma REAL NOT NULL, set_ms REAL NOT NULL, created_at TEXT NOT NULL,
                FOREIGN KEY(equipment_id) REFERENCES equipment(id))''');
              await d.execute('''CREATE TABLE readings (device_id TEXT NOT NULL, shot_id TEXT NOT NULL,
                session_id TEXT NOT NULL, set_ma REAL NOT NULL, set_ms REAL NOT NULL,
                read_ma REAL NOT NULL, read_ms REAL NOT NULL, read_mas REAL NOT NULL,
                quality TEXT NOT NULL, recorded_at TEXT NOT NULL, PRIMARY KEY(device_id, shot_id))''');
              await d.execute('''CREATE TABLE sync_state (device_id TEXT PRIMARY KEY,
                last_cursor INTEGER NOT NULL DEFAULT 0)''');
              await d.insert('equipment', {
                'id': seedEquipmentId,
                'manufacturer': 'Siemens',
                'model': 'Multix B',
                'serial_number': 'ANTIGO-1',
                'created_at': '2026-01-01T00:00:00Z'
              });
              await d.insert('sessions', {
                'id': seedSessionId,
                'equipment_id': seedEquipmentId,
                'set_ma': 250.0,
                'set_ms': 80.0,
                'created_at': '2026-01-01T00:00:00Z'
              });
              await d.insert('readings', {
                'device_id': 'XM-1',
                'shot_id': '7',
                'session_id': seedSessionId,
                'set_ma': 250.0,
                'set_ms': 80.0,
                'read_ma': 251.0,
                'read_ms': 80.0,
                'read_mas': 20.08,
                'quality': 'valid',
                'recorded_at': '2026-01-02T10:00:00Z'
              });
              await d.insert('sync_state', {'device_id': 'XM-1', 'last_cursor': 7});
            }));
    await v1.close();

    final db = await open();
    final eq = (await db.equipment(seedEquipmentId))!;
    expect(eq.serialNumber, 'ANTIGO-1');
    final s = (await db.currentSession(seedEquipmentId))!;
    expect(s.setMa, 250);
    final rs = await db.readings();
    expect(rs, hasLength(1));
    expect(rs.single.shotId, '7');
    expect(rs.single.equipmentId, seedEquipmentId);
    expect(await db.cursor('XM-1'), 7);
    expect(await db.equipments(), hasLength(1));
    expect(rs.single.tolerances, isNotNull, reason: 'v3 grava tolerância nas medições antigas');
    expect(rs.single.tolerances!.masPct, 10);
    expect(eq.archived, isFalse);
    await db.db.close();
  });

  test('tolerância fica gravada em cada medição', () async {
    final db = await open();
    await db.mergeDeviceReadings('XM-1', 1, [shot('1', mas: 20.9)], const Tolerances(masPct: 10));
    final r = (await db.readings()).single;
    expect(r.tolerances!.masPct, 10);
    // Mesmo com tolerância atual mais rígida (2 %), a medição mantém o resultado original.
    expect(evaluateReading(r, const Tolerances(masPct: 2, maPct: 2, msPct: 2)).status,
        MeasureStatus.approved);
    expect(evaluate(setMa: 200, setMs: 100, readMa: 201, readMs: 100, readMas: 20.9,
            tol: const Tolerances(masPct: 2, maPct: 2, msPct: 2)).status,
        MeasureStatus.failed);
    await db.db.close();
  });

  test('medições reais não podem ser apagadas nem alteradas', () async {
    final db = await open();
    await db.mergeDeviceReadings('XM-1', 1, [shot('1')], const Tolerances());
    await expectLater(db.db.delete('readings'), throwsA(anything));
    await expectLater(db.db.update('readings', {'read_mas': 1.0}), throwsA(anything));
    await expectLater(db.db.delete('audit_log'), throwsA(anything));
    expect(await db.readings(), hasLength(1));
    await db.db.close();
  });

  test('arquivar equipamento preserva medições e pode restaurar', () async {
    final db = await open();
    await db.mergeDeviceReadings('XM-1', 1, [shot('1')], const Tolerances());
    await db.setArchived(seedEquipmentId, true);
    expect(await db.equipments(), isEmpty);
    expect(await db.equipments(archived: true), hasLength(1));
    expect(await db.readings(equipmentId: seedEquipmentId), hasLength(1));
    await db.setArchived(seedEquipmentId, false);
    expect(await db.equipments(), hasLength(1));
    await db.db.close();
  });

  test('SET travado: sessão com medições abre nova sessão ao mudar SET', () async {
    final db = await open();
    await db.mergeDeviceReadings('XM-1', 1, [shot('1')], const Tolerances());
    final ch = await db.changeSet(seedEquipmentId, 100, 50);
    expect(ch.newSession, isTrue);
    expect(ch.sessionId, isNot(seedSessionId));
    final old = (await db.session(seedSessionId))!;
    expect(old.setMa, 200, reason: 'SET da sessão antiga não muda');
    final cur = (await db.currentSession(seedEquipmentId))!;
    expect(cur.id, ch.sessionId);
    expect(cur.setMas, closeTo(5, 1e-9));
    await db.db.close();
  });

  test('registro de alterações guarda as operações', () async {
    final db = await open();
    await db.changeSet(seedEquipmentId, 150, 80);
    await db.mergeDeviceReadings('XM-1', 1, [shot('1')], const Tolerances());
    final log = await db.auditLog();
    final actions = log.map((e) => e.action).toList();
    expect(actions, containsAll(['criado', 'SET alterado', 'medicoes recebidas']));
    await db.db.close();
  });

  test('backup exporta e restaura tudo, com medições protegidas', () async {
    var db = await open();
    await db.saveSettings(const AppSettings(token: 'segredo', demoMode: true));
    await db.mergeDeviceReadings('XM-1', 1, [shot('1'), shot('2')], const Tolerances());
    final backup = await db.exportBackup(appVersion: 'teste');
    final settingsRows = ((backup['tables'] as Map)['settings'] as List).cast<Map>();
    expect(settingsRows.any((r) => r['key'] == 'token'), isFalse, reason: 'token não vai no backup');
    await db.db.close();

    // Outro aparelho (banco novo) recebe o backup.
    path = p.join(tmp.path, 'outro.sqlite');
    db = await open();
    await db.saveSettings(const AppSettings(token: 'token-local'));
    final counts = await db.importBackup(backup);
    expect(counts['readings'], 2);
    expect(await db.readings(), hasLength(2));
    expect((await db.loadSettings()).demoMode, isTrue);
    expect((await db.loadSettings()).token, 'token-local', reason: 'token local é mantido');
    await expectLater(db.db.delete('readings'), throwsA(anything),
        reason: 'proteção recriada após restaurar');
    expect((await db.auditLog()).first.action, 'backup restaurado');
    await expectLater(db.importBackup({'format': 'outro'}), throwsA(isA<BackupException>()));
    expect(await db.readings(), hasLength(2), reason: 'backup inválido não altera nada');
    await db.db.close();
  });

  test('tipo de gerador é salvo e define a tolerância aplicada', () async {
    final db = await open();
    final e = (await db.equipment(seedEquipmentId))!;
    expect(e.generatorType, GeneratorType.highFrequency);
    await db.saveEquipment(Equipment(
      id: e.id,
      manufacturer: e.manufacturer,
      model: e.model,
      generatorType: GeneratorType.conventional,
      createdAt: e.createdAt,
      updatedAt: DateTime.now(),
    ));
    expect((await db.equipment(e.id))!.generatorType, GeneratorType.conventional);
    await db.mergeDeviceReadings('XM-1', 1, [shot('1')], const Tolerances(masPct: 10),
        convTol: const Tolerances(masPct: 5));
    final r = (await db.readings()).single;
    expect(r.tolerances!.masPct, 5, reason: 'convencional usa a tolerância própria');
    await db.db.close();
  });

  test('configurações guardam tolerâncias separadas por tipo', () async {
    final db = await open();
    await db.saveSettings(const AppSettings(
        tolerances: Tolerances(maPct: 10), tolerancesConv: Tolerances(maPct: 15, alertFraction: 0.7)));
    final st = await db.loadSettings();
    expect(st.tolFor(GeneratorType.highFrequency).maPct, 10);
    expect(st.tolFor(GeneratorType.conventional).maPct, 15);
    expect(st.tolFor(GeneratorType.conventional).alertFraction, 0.7);
    await db.db.close();
  });
}

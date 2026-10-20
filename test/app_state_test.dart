import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:unitech_xmeter_connect/app_state.dart';
import 'package:unitech_xmeter_connect/database.dart';
import 'package:unitech_xmeter_connect/meter_api.dart';

/// Instrumento falso que segue o protocolo proposto v1 (docs/PROTOCOLO_PROPOSTO.md).
class FakeInstrument {
  late HttpServer server;
  bool offline = false;
  String? sessionId;
  final readings = <Map<String, Object?>>[];
  int setCalls = 0;

  int get port => server.port;

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen(_handle);
  }

  void addShot(String id, double mas) {
    readings.add({
      'cursor': readings.length + 1,
      'shot_id': id,
      'session_id': sessionId,
      'quality': 'valid',
      'set_ma': 200,
      'set_ms': 100,
      'read_ma': 200.0,
      'read_ms': 100.0,
      'read_mas': mas,
      'recorded_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<void> _handle(HttpRequest req) async {
    final res = req.response..headers.contentType = ContentType.json;
    Future<void> send(int code, Object body) async {
      res.statusCode = code;
      res.write(jsonEncode(body));
      await res.close();
    }

    if (offline) return send(503, {'error': 'offline'});
    if (req.headers.value('authorization') != 'Bearer tok') return send(401, {'error': 'auth'});
    final path = req.uri.path;
    if (req.method == 'GET' && path == '/v1/device') {
      return send(200, {'device_id': 'XM-TEST', 'protocol_version': 1});
    }
    if (req.method == 'PUT' && path == '/v1/session/set') {
      final body = jsonDecode(await utf8.decoder.bind(req).join()) as Map;
      sessionId = body['session_id'] as String;
      setCalls++;
      return send(200, {'accepted': true, 'session_id': sessionId});
    }
    if (req.method == 'GET' && path == '/v1/readings') {
      final after = int.parse(req.uri.queryParameters['after'] ?? '0');
      final items = readings.where((r) => (r['cursor'] as int) > after).toList();
      return send(200, {
        'device_id': 'XM-TEST',
        'next_cursor': items.isEmpty ? after : items.last['cursor'],
        'more': false,
        'items': [for (final i in items) Map.of(i)..remove('cursor')],
      });
    }
    return send(404, {'error': 'not found'});
  }
}

void main() {
  late Directory tmp;
  late AppState state;
  late FakeInstrument inst;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('xmeter_state_');
    final path = p.join(tmp.path, 'x.sqlite');
    final db = await XDatabase.open(path, factory: databaseFactoryFfi);
    inst = FakeInstrument();
    await inst.start();
    state = AppState(db, path, apiFactory: (h, port, t) => MeterApi(h, port, t, timeout: const Duration(seconds: 2)));
    await state.init();
    await state.saveSettings(state.settings.copyWith(host: '127.0.0.1', port: inst.port, token: 'tok'));
  });

  tearDown(() async {
    state.dispose();
    await inst.server.close(force: true);
    await state.db.db.close();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('sem instrumento: conexão falha e nenhuma leitura READ é criada', () async {
    await state.saveSettings(state.settings.copyWith(port: 1));
    await state.connect();
    expect(state.link, LinkState.disconnected);
    expect(state.linkError, isNotNull);
    expect(state.readings, isEmpty);
    expect(state.session!.setPending, isTrue, reason: 'SET continua salvo e pendente');
  });

  test('conecta, envia SET pendente e sincroniza sem duplicar', () async {
    await state.connect();
    expect(state.link, LinkState.connected);
    expect(state.deviceId, 'XM-TEST');
    expect(inst.setCalls, 1);
    expect(state.session!.setPending, isFalse);

    inst.addShot('1', 20.1);
    inst.addShot('2', 19.8);
    await state.syncNow();
    expect(state.readings, hasLength(2));

    // Instrumento reenvia o mesmo disparo (ex.: após reinício): ignorado.
    inst.readings.add({...inst.readings.first, 'cursor': 3});
    await state.syncNow();
    expect(state.readings, hasLength(2));
  });

  test('queda de conexão: reconecta e recupera leituras pelo cursor', () async {
    await state.connect();
    inst.addShot('1', 20.0);
    await state.syncNow();
    expect(state.readings, hasLength(1));

    inst.offline = true;
    await state.syncNow();
    expect(state.link, LinkState.reconnecting);

    inst.addShot('2', 20.2); // medido enquanto o app estava sem rede
    inst.offline = false;
    for (var i = 0; i < 40 && state.link != LinkState.connected; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    expect(state.link, LinkState.connected);
    for (var i = 0; i < 20 && state.readings.length < 2; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    expect(state.readings, hasLength(2));
    expect(state.readings.map((r) => r.shotId).toSet(), {'1', '2'});
  });

  test('alteração de SET fica pendente e é reenviada ao instrumento', () async {
    await state.connect();
    expect(inst.setCalls, 1);
    final err = await state.saveSet(320, 6.3);
    expect(err, isNull);
    expect(inst.setCalls, 2);
    expect(state.session!.setMa, 320);
    expect(state.session!.setPending, isFalse);
    expect(await state.saveSet(-1, 100), isNotNull);
    expect(await state.saveSet(null, 100), isNotNull);
  });

  test('MODO DEMONSTRAÇÃO só gera dados quando ativo e sempre marcados', () async {
    await state.generateDemoShot();
    expect(state.readings, isEmpty);
    await state.saveSettings(state.settings.copyWith(demoMode: true));
    await state.generateDemoShot();
    expect(state.readings, hasLength(1));
    expect(state.readings.single.isDemo, isTrue);
    expect(state.readings.single.source, 'demo');
    expect(state.readings.single.waveform, isNotNull);
  });
}

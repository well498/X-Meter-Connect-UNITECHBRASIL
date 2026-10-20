import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'calc.dart';
import 'database.dart';
import 'meter_api.dart';
import 'models.dart';

enum LinkState { disconnected, connecting, connected, reconnecting }

T? firstOrNull<T>(Iterable<T> items) {
  for (final i in items) {
    return i;
  }
  return null;
}

/// Estado central do aplicativo: cadastro, SET, leituras e conexão.
class AppState extends ChangeNotifier {
  final XDatabase db;
  final String dbPath;

  /// Permite substituir o transporte nos testes.
  final MeterApi Function(String host, int port, String token) apiFactory;

  AppState(this.db, this.dbPath, {MeterApi Function(String, int, String)? apiFactory})
      : apiFactory = apiFactory ?? ((h, port, t) => MeterApi(h, port, t));

  AppSettings settings = const AppSettings();
  List<Equipment> equipments = [];
  Equipment? selected;
  MeasureSession? session;
  List<Reading> readings = [];
  String message = '';

  /// Incrementa a cada nova mensagem (para exibir SnackBar mesmo se repetida).
  int messageSeq = 0;

  LinkState link = LinkState.disconnected;
  String? deviceId;
  String? firmware;
  bool deviceSimulated = false;
  String? linkError;
  DateTime? lastSync;
  int reconnectAttempts = 0;

  MeterApi? _api;
  Timer? _poll;
  Timer? _retry;
  bool _io = false;
  bool _disposed = false;

  Tolerances get tol => settings.tolerances;
  bool get connected => link == LinkState.connected;

  List<Reading> get sessionReadings =>
      readings.where((r) => r.sessionId == session?.id).toList(growable: false);

  Reading? get latest => firstOrNull(sessionReadings);

  /// Reavalia o resultado com as tolerâncias configuradas no momento.
  Evaluation evalOf(Reading r) => evaluate(
      setMa: r.setMa,
      setMs: r.setMs,
      readMa: r.readMa,
      readMs: r.readMs,
      readMas: r.readMas,
      tol: tol);

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _say(String m) {
    message = m;
    messageSeq++;
    _notify();
  }

  Future<void> init() async {
    settings = await db.loadSettings();
    await reload();
  }

  Future<void> reload() async {
    equipments = await db.equipments();
    selected = firstOrNull(equipments.where((e) => e.id == settings.selectedEquipmentId)) ??
        firstOrNull(equipments);
    if (selected != null) {
      session = await db.currentSession(selected!.id);
      readings = await db.readings(equipmentId: selected!.id);
    } else {
      session = null;
      readings = [];
    }
    _notify();
  }

  // ---------------- Equipamentos ----------------

  Future<void> selectEquipment(String id) async {
    settings = settings.copyWith(selectedEquipmentId: id);
    await db.saveSettings(settings);
    await reload();
    _say('Equipamento selecionado: ${selected?.title ?? ''}');
  }

  Future<void> saveEquipment(Equipment e) async {
    await db.saveEquipment(e);
    if (selected == null) {
      settings = settings.copyWith(selectedEquipmentId: e.id);
      await db.saveSettings(settings);
    }
    await reload();
    _say('Cadastro salvo: ${e.title}');
  }

  Future<void> deleteEquipment(String id) async {
    await db.deleteEquipment(id);
    if (settings.selectedEquipmentId == id) {
      final rest = equipments.where((e) => e.id != id);
      settings = AppSettings.fromMap({
        ...settings.toMap()..remove('selected_equipment'),
        if (rest.isNotEmpty) 'selected_equipment': rest.first.id,
      });
      await db.saveSettings(settings);
    }
    await reload();
    _say('Equipamento excluído');
  }

  // ---------------- SET ----------------

  /// Valida e grava o SET. Retorna mensagem de erro ou null.
  Future<String?> saveSet(double? ma, double? ms) async {
    final s = session;
    if (s == null) return 'Selecione um equipamento';
    if (ma == null || ms == null) return 'Informe mA e tempo numéricos';
    if (ma <= 0 || ma > 2000) return 'mA SET deve estar entre 0 e 2000 mA';
    if (ms <= 0 || ms > 10000) return 'Tempo SET deve estar entre 0 e 10000 ms';
    await db.updateSet(s.id, ma, ms);
    await reload();
    if (connected) {
      await _guarded(_sendPendingSet);
    } else {
      _say('SET salvo no aparelho. Será enviado ao instrumento quando conectar.');
    }
    return null;
  }

  Future<void> newSession() async {
    final eq = selected;
    if (eq == null) return;
    await db.newSession(eq.id);
    await reload();
    if (connected) await _guarded(_sendPendingSet);
    _say('Nova sessão de medição iniciada');
  }

  // ---------------- Conexão ----------------

  Future<void> connect() async {
    if (link == LinkState.connecting) return;
    _stopTimers();
    final api = apiFactory(settings.host, settings.port, settings.token);
    link = LinkState.connecting;
    linkError = null;
    _say('Conectando a ${settings.host}:${settings.port}...');
    try {
      final info = await api.identity();
      _api = api;
      _onConnected(info);
      await _guarded(() async {
        await _sendPendingSet();
        await _syncAll();
      });
    } catch (e) {
      _api = null;
      link = LinkState.disconnected;
      linkError = e.toString();
      _say('Falha ao conectar: $e');
    }
  }

  void _onConnected(DeviceInfo info) {
    deviceId = info.deviceId;
    firmware = info.firmware;
    deviceSimulated = info.simulated;
    link = LinkState.connected;
    linkError = null;
    reconnectAttempts = 0;
    _poll = Timer.periodic(const Duration(seconds: 4), (_) => _tick());
    _say('Conectado ao instrumento ${info.deviceId}');
  }

  void disconnect() {
    _stopTimers();
    _api = null;
    link = LinkState.disconnected;
    _say('Desconectado pelo usuário');
  }

  void _stopTimers() {
    _poll?.cancel();
    _retry?.cancel();
    _poll = null;
    _retry = null;
  }

  Future<void> _tick() async {
    if (_io || link != LinkState.connected) return;
    try {
      await _guarded(() async {
        await _sendPendingSet();
        await _syncAll();
      });
    } catch (_) {
      // Tratado em _guarded.
    }
  }

  /// Serializa as operações de rede e trata perda de conexão.
  Future<void> _guarded(Future<void> Function() action) async {
    var waited = 0;
    while (_io && waited < 100) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      waited++;
    }
    if (_io) return;
    _io = true;
    try {
      await action();
    } on MeterException catch (e) {
      _onLinkLost(e.toString());
    } on SocketException catch (e) {
      _onLinkLost(e.message);
    } catch (e) {
      _say('Erro: $e');
    } finally {
      _io = false;
    }
  }

  void _onLinkLost(String reason) {
    _poll?.cancel();
    _poll = null;
    linkError = reason;
    if (settings.autoReconnect && _api != null) {
      link = LinkState.reconnecting;
      _say('Conexão perdida: $reason. Tentando reconectar...');
      _scheduleRetry();
    } else {
      link = LinkState.disconnected;
      _say('Conexão perdida: $reason');
    }
  }

  void _scheduleRetry() {
    _retry?.cancel();
    final seconds = min(30, 2 << min(reconnectAttempts, 4));
    _retry = Timer(Duration(seconds: seconds), () async {
      final api = _api;
      if (api == null || link != LinkState.reconnecting) return;
      reconnectAttempts++;
      _notify();
      try {
        final info = await api.identity();
        final previous = deviceId;
        _onConnected(info);
        if (previous != null && previous != info.deviceId) {
          _say('Atenção: reconectado a outro instrumento (${info.deviceId})');
        }
        await _guarded(() async {
          await _sendPendingSet();
          await _syncAll();
        });
      } catch (e) {
        linkError = e.toString();
        _notify();
        if (link == LinkState.reconnecting) _scheduleRetry();
      }
    });
  }

  Future<void> _sendPendingSet() async {
    final s = session;
    final api = _api;
    final dev = deviceId;
    if (s == null || api == null || dev == null || !s.setPending) return;
    await api.sendSet(s.id, s.setMa, s.setMs);
    await db.markSetConfirmed(s.id, dev);
    await reload();
    _say('SET ${fmt(s.setMa, 0)} mA / ${fmt(s.setMs, 0)} ms confirmado pelo instrumento $dev');
  }

  Future<void> _syncAll() async {
    final api = _api;
    final dev = deviceId;
    if (api == null || dev == null) return;
    var total = 0, dup = 0, rej = 0;
    for (var page = 0; page < 50; page++) {
      final cursor = await db.cursor(dev);
      final res = await api.readings(cursor);
      if (res.deviceId != dev) throw const MeterException('Instrumento trocado durante a sincronização');
      final m = await db.mergeDeviceReadings(dev, res.nextCursor, res.items, tol,
          deviceSimulated: deviceSimulated);
      total += m.inserted;
      dup += m.duplicates;
      rej += m.rejected;
      if (!res.more) break;
    }
    lastSync = DateTime.now();
    if (total > 0) {
      await reload();
      _say('Recebidas $total nova(s) medição(ões) do instrumento'
          '${dup > 0 ? '; $dup repetida(s) ignorada(s)' : ''}'
          '${rej > 0 ? '; $rej rejeitada(s)' : ''}');
    } else {
      _notify();
    }
  }

  Future<void> sendSetNow() async {
    if (!connected) {
      _say('Instrumento desconectado. O SET fica salvo e pendente de envio.');
      return;
    }
    await _guarded(_sendPendingSet);
  }

  Future<void> syncNow() async {
    if (!connected) {
      _say('Conecte-se ao instrumento para sincronizar');
      return;
    }
    await _guarded(_syncAll);
    if (connected) _say('Sincronização concluída');
  }

  // ---------------- Configurações ----------------

  Future<void> saveSettings(AppSettings s) async {
    final linkChanged =
        s.host != settings.host || s.port != settings.port || s.token != settings.token;
    settings = s.copyWith(selectedEquipmentId: settings.selectedEquipmentId);
    await db.saveSettings(settings);
    if (linkChanged && link != LinkState.disconnected) disconnect();
    await reload();
    _say('Configurações salvas');
  }

  Future<void> clearDemo() async {
    final n = await db.deleteDemoReadings();
    await reload();
    _say('$n registro(s) simulado(s) apagado(s)');
  }

  // ---------------- MODO DEMONSTRAÇÃO ----------------

  final _rnd = Random();

  double _gauss() {
    final u1 = max(_rnd.nextDouble(), 1e-12);
    final u2 = _rnd.nextDouble();
    return sqrt(-2 * log(u1)) * cos(2 * pi * u2);
  }

  /// Gera um disparo SIMULADO, gravado com source='demo'. Só funciona com
  /// o modo demonstração ativo e nunca é apresentado como medição real.
  Future<void> generateDemoShot() async {
    final s = session;
    if (!settings.demoMode || s == null) return;
    final readMs = max(1.0, s.setMs * (1 + 0.02 * _gauss()));
    final plateau = max(1.0, s.setMa * (1 + 0.03 * _gauss()));
    // Janela com 15 % de margem antes e depois da exposição.
    const samples = 240;
    final window = readMs * 1.3;
    final periodUs = window * 1000 / samples;
    final start = readMs * 0.15;
    final rise = max(0.4, readMs * 0.03);
    final values = <double>[];
    var masAcc = 0.0;
    for (var i = 0; i < samples; i++) {
      final t = i * periodUs / 1000;
      double v;
      if (t < start || t > start + readMs) {
        v = 0;
      } else if (t < start + rise) {
        v = plateau * (t - start) / rise;
      } else if (t > start + readMs - rise) {
        v = plateau * (start + readMs - t) / rise;
      } else {
        v = plateau * (1 + 0.015 * sin(t * 2 * pi / 3.33)) + 0.4 * _gauss();
      }
      v = max(0, v);
      values.add(v);
      masAcc += v * periodUs / 1e6;
    }
    await db.insertDemoReading(
      session: s,
      readMa: plateau,
      readMs: readMs,
      readMas: masAcc,
      waveform: Waveform(periodUs, values),
      tol: tol,
    );
    await reload();
    _say('MODO DEMONSTRAÇÃO: disparo simulado gerado (não é medição real)');
  }

  // ---------------- Exportação ----------------

  Future<String> saveExport(String fileName, String content) async {
    Directory? dir;
    if (Platform.isAndroid) {
      dir = await getExternalStorageDirectory();
    }
    dir ??= await getApplicationDocumentsDirectory();
    final folder = Directory(p.join(dir.path, 'exportacoes'));
    await folder.create(recursive: true);
    final file = File(p.join(folder.path, fileName));
    // BOM UTF-8 para o Excel abrir acentos corretamente.
    await file.writeAsString('﻿$content');
    return file.path;
  }

  @override
  void dispose() {
    _disposed = true;
    _stopTimers();
    super.dispose();
  }
}

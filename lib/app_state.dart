import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'analysis.dart';
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
  List<Equipment> archivedEquipments = [];

  /// Perfis de gerador e o perfil do equipamento selecionado.
  List<GeneratorProfile> profiles = [];
  GeneratorProfile? profile;

  /// Último estado informado pelo instrumento (bateria, modo, alertas…).
  DeviceInfo? deviceInfo;
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

  GeneratorType get generatorType => selected?.generatorType ?? GeneratorType.unknown;

  /// Tolerância do tipo de gerador do equipamento selecionado.
  Tolerances get tol => profile?.tolerances ?? settings.tolFor(generatorType);

  GeneratorProfile? profileOf(Equipment e) =>
      firstOrNull(profiles.where((p) => p.id == e.profileId)) ??
      firstOrNull(profiles.where((p) => p.id == BuiltinProfiles.genericId(e.generatorType)));

  /// Limites efetivos: manual do equipamento > perfil > referência do tipo.
  GeneratorLimits limitsOf(Equipment e) {
    final base = profileOf(e)?.limits ?? e.generatorType.referenceLimits;
    return GeneratorLimits(e.minMa ?? base.minMa, e.maxMa ?? base.maxMa, e.minMs ?? base.minMs,
        e.maxMs ?? base.maxMs, e.maxMas ?? base.maxMas,
        minMas: base.minMas);
  }

  /// Estações das setas ▲▼ (do perfil, quando definidas) dentro dos limites.
  List<double> maStationsOf(Equipment e) {
    final l = limitsOf(e);
    return stepsWithin(profileOf(e)?.maStations ?? e.generatorType.maSteps, l.minMa, l.maxMa);
  }

  List<double> msStationsOf(Equipment e) {
    final l = limitsOf(e);
    return stepsWithin(e.generatorType.msSteps, l.minMs, l.maxMs);
  }
  bool get connected => link == LinkState.connected;

  List<Reading> get sessionReadings =>
      readings.where((r) => r.sessionId == session?.id).toList(growable: false);

  Reading? get latest => firstOrNull(sessionReadings);

  /// Limites efetivos do equipamento selecionado.
  GeneratorLimits get limits => selected == null ? generatorType.referenceLimits : limitsOf(selected!);

  /// Avalia com a tolerância gravada na própria medição (rastreabilidade).
  Evaluation evalOf(Reading r) => evaluateReading(r, tol);

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
    profiles = await db.profiles();
    equipments = await db.equipments();
    archivedEquipments = await db.equipments(archived: true);
    selected = firstOrNull(equipments.where((e) => e.id == settings.selectedEquipmentId)) ??
        firstOrNull(equipments);
    profile = selected == null ? null : profileOf(selected!);
    if (selected != null) {
      session = await db.currentSession(selected!.id);
      readings = await db.readings(equipmentId: selected!.id);
      notes = await db.notes(equipmentId: selected!.id);
    } else {
      session = null;
      readings = [];
      notes = [];
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

  /// Arquiva (nunca apaga) o equipamento e todas as suas medições.
  Future<void> archiveEquipment(String id) async {
    await db.setArchived(id, true);
    if (settings.selectedEquipmentId == id) {
      final rest = equipments.where((e) => e.id != id);
      settings = AppSettings.fromMap({
        ...settings.toMap()..remove('selected_equipment'),
        if (rest.isNotEmpty) 'selected_equipment': rest.first.id,
      });
      await db.saveSettings(settings);
    }
    await reload();
    _say('Equipamento arquivado. As medições continuam guardadas.');
  }

  Future<void> restoreEquipment(String id) async {
    await db.setArchived(id, false);
    await reload();
    _say('Equipamento restaurado');
  }

  // ---------------- SET ----------------

  /// Valida e grava o SET. Retorna mensagem de erro ou null.
  Future<String?> saveSet(double? ma, double? ms) async {
    final s = session;
    if (s == null) return 'Selecione um equipamento';
    if (ma == null || ms == null) return 'Informe mA e tempo numéricos';
    if (ma <= 0 || ms <= 0) return 'mA e tempo devem ser maiores que zero';
    final limitError = selected == null ? null : limitsOf(selected!).check(ma, ms);
    if (limitError != null) return limitError;
    if (ma == s.setMa && ms == s.setMs) {
      _say('SET sem alteração');
      return null;
    }
    final change = await db.changeSet(s.equipmentId, ma, ms);
    await reload();
    final prefix = change.newSession
        ? 'A sessão anterior já tinha medições e ficou travada. Nova sessão aberta com o novo SET. '
        : '';
    if (connected) {
      await _guarded(_sendPendingSet);
      if (change.newSession) _say('${prefix}SET enviado ao instrumento.');
    } else {
      _say('${prefix}SET salvo no aparelho. Será enviado ao instrumento quando conectar.');
    }
    return null;
  }

  Future<void> newSession({String? label}) async {
    final eq = selected;
    if (eq == null) return;
    await db.newSession(eq.id, label: label);
    hiddenReadingUid = null;
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
        await _refreshStatus();
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
    deviceInfo = info;
    db.upsertInstrument(info.toDbMap());
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
        await _refreshStatus();
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

  /// Estado do instrumento (bateria, modo, alertas) e SET configurado nele.
  /// Se o técnico mudou o SET no display (MODO LOCAL), o aplicativo adota
  /// esse SET e registra a origem "instrumento".
  Future<void> _refreshStatus() async {
    final api = _api;
    final dev = deviceId;
    final eq = selected;
    if (api == null || dev == null) return;
    final info = await api.identity();
    final alertsChanged = info.alerts.join('|') != (deviceInfo?.alerts.join('|') ?? '');
    deviceInfo = info;
    await db.upsertInstrument(info.toDbMap());
    if (alertsChanged && info.alerts.isNotEmpty) _say('Alerta do instrumento: ${info.alerts.join('; ')}');
    final ds = await api.deviceSet();
    final ses = session;
    if (ds == null || eq == null || ses == null || ds.origin != 'instrumento') return;
    final same = ds.ma == ses.setMa && ds.ms == ses.setMs && (ds.sessionId == null || ds.sessionId == ses.id);
    if (same) return;
    final known = ses.setChangedAt;
    if (known != null && ds.changedAt != null && !ds.changedAt!.isAfter(known)) return;
    await db.adoptInstrumentSet(eq.id, dev, ds.ma, ds.ms, deviceSessionId: ds.sessionId, changedAt: ds.changedAt);
    await reload();
    _say('SET alterado no instrumento (modo local): ${fmtTrim(ds.ma)} mA × ${fmtTrim(ds.ms)} ms');
  }

  /// Atualiza o estado do instrumento sob demanda (tela Conectividade).
  Future<void> refreshInstrument() async {
    if (!connected) return;
    await _guarded(_refreshStatus);
    _notify();
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
          deviceSimulated: deviceSimulated, fallbackEquipmentId: selected?.id);
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

  DetectionConfig get detection => DetectionConfig(
        startFraction: settings.detStartPct / 100,
        endFraction: settings.detEndPct / 100,
        minDurationMs: settings.detMinMs,
      );

  /// Forma de onda sintética conforme a tecnologia do gerador, amostrada a
  /// até 100 kS/s (MODO DEMONSTRAÇÃO). Devolve instantes (ms) e corrente (mA).
  ({List<double> t, List<double> ma}) _synthWave(double setMa, double setMs, GeneratorType type) {
    final realMa = max(0.5, setMa * (1 + 0.025 * _gauss()));
    final realMs = max(0.5, setMs * (1 + 0.015 * _gauss()));
    final pre = max(2.0, realMs * 0.12);
    final total = pre * 2 + realMs;
    final dt = max(0.01, total / 50000); // 100 kS/s, limitado a 50 mil amostras
    final rise = switch (type) {
      GeneratorType.highFrequency => max(0.3, min(1.5, realMs * 0.01)),
      _ => max(0.8, min(3.0, realMs * 0.02)),
    };
    const mains = 60.0; // Hz
    final t = <double>[];
    final y = <double>[];
    for (var tt = 0.0; tt <= total; tt += dt) {
      final x = tt - pre;
      double env;
      if (x < 0 || x > realMs + rise) {
        env = 0;
      } else if (x < rise) {
        env = x / rise;
      } else if (x > realMs) {
        env = 1 - (x - realMs) / rise;
      } else {
        env = 1;
      }
      final w = 2 * pi * mains * tt / 1000;
      final shape = switch (type) {
        // Monofásico 2 pulsos: retificação de onda completa (vai a ~0 a cada semiciclo).
        GeneratorType.singlePhase2p => (sin(w)).abs() * pi / 2,
        GeneratorType.threePhase6p => 1 + 0.06 * cos(6 * w),
        GeneratorType.threePhase12p => 1 + 0.02 * cos(12 * w),
        _ => 1 + 0.01 * sin(2 * pi * tt / 0.05), // HF: ondulação de ~20 kHz, pequena
      };
      t.add(tt);
      y.add(max(0.0, realMa * env * shape + 0.003 * setMa * _gauss()));
    }
    return (t: t, ma: y);
  }

  /// Gera um disparo SIMULADO, gravado com source='demo'. Só funciona com
  /// o modo demonstração ativo e nunca é apresentado como medição real.
  /// mAs, tempo, corrente média e máxima saem do MESMO algoritmo do
  /// firmware (lib/analysis.dart): detecção com histerese + trapézios.
  Future<void> generateDemoShot() async {
    final s = session;
    if (!settings.demoMode || s == null) return;
    final wave = _synthWave(s.setMa, s.setMs, generatorType);
    final ex = detectExposure(wave.t, wave.ma, cfg: detection);
    if (!ex.valid) {
      _say('MODO DEMONSTRAÇÃO: exposição simulada rejeitada (${ex.flags.map((f) => f.label).join(', ')})');
      return;
    }
    // Guarda até 2.000 pontos para o gráfico (a medição usou todas as amostras).
    final step = max(1, (wave.ma.length / 2000).ceil());
    final stored = <double>[for (var i = 0; i < wave.ma.length; i += step) wave.ma[i]];
    final periodUs = (wave.t[1] - wave.t[0]) * 1000 * step;
    await db.insertDemoReading(
      session: s,
      readMa: ex.meanMa,
      readMs: ex.timeMs,
      readMas: ex.mas,
      waveform: Waveform(periodUs, stored),
      tol: tol,
      maPeak: ex.peakMa,
      quality: ex.flags.map((f) => f.code).toList(),
      profileId: profile?.id,
    );
    hiddenReadingUid = null;
    await reload();
    _say('MODO DEMONSTRAÇÃO: disparo simulado gerado (não é medição real)');
  }

  /// "Iniciar Medição": arma o instrumento para registrar a PRÓXIMA exposição
  /// feita pelo operador no comando do gerador. O app não dispara raios X.
  Future<void> startMeasurement() async {
    if (settings.demoMode) {
      await generateDemoShot();
      return;
    }
    final s = session;
    final api = _api;
    if (!connected || api == null || s == null) {
      _say('Conecte-se ao instrumento para iniciar a medição (ou ative o modo demonstração)');
      return;
    }
    await _guarded(() async {
      await _sendPendingSet();
      await api.arm(s.id);
      _say('Instrumento pronto: faça a exposição no comando do gerador');
    });
  }

  /// "Limpar": esconde o último resultado do painel até chegar uma nova
  /// medição. Nada é apagado.
  String? hiddenReadingUid;

  void clearPanel() {
    hiddenReadingUid = latest?.uid;
    _say('Painel limpo. Aguardando nova medição.');
  }

  Reading? get displayed {
    final r = latest;
    return (r == null || r.uid == hiddenReadingUid) ? null : r;
  }

  // ---------------- Perfis e metadados ----------------

  Future<void> saveProfile(GeneratorProfile p) async {
    await db.saveProfile(p);
    await reload();
    _say('Perfil salvo: ${p.name}');
  }

  Future<bool> deleteProfile(String id) async {
    final ok = await db.deleteProfile(id);
    await reload();
    _say(ok ? 'Perfil excluído' : 'Perfil em uso ou do aplicativo: não pode ser excluído');
    return ok;
  }

  Future<void> updateSessionMeta({String? tubeModel, String? kvInfo}) async {
    final s = session;
    if (s == null) return;
    await db.updateSessionMeta(s.id, tubeModel: tubeModel, kvInfo: kvInfo);
    await reload();
    _say('Dados do teste salvos');
  }

  // ---------------- Observações e foto ----------------

  List<Note> notes = [];

  Future<void> addNote(String text, {String? readingUid}) async {
    final s = session;
    if (s == null || text.trim().isEmpty) return;
    await db.addNote(s.id, text, readingUid: readingUid);
    await reload();
    _say('Observação registrada');
  }

  Future<void> pickEquipmentPhoto(String equipmentId) async {
    final res = await FilePicker.platform.pickFiles(type: FileType.image);
    final src = res?.files.single.path;
    if (src == null) return;
    final dir = await getApplicationSupportDirectory();
    final folder = Directory(p.join(dir.path, 'fotos'));
    await folder.create(recursive: true);
    final dest = p.join(folder.path, '${equipmentId}_${DateTime.now().millisecondsSinceEpoch}${p.extension(src)}');
    await File(src).copy(dest);
    await db.setPhoto(equipmentId, dest);
    await reload();
    _say('Foto do equipamento atualizada');
  }

  /// Exporta a forma de onda em CSV (tempo_ms;corrente_mA) para análise externa.
  Future<String> exportWaveformCsv(Reading r) async {
    final w = r.waveform;
    if (w == null) throw StateError('Medição sem forma de onda');
    final b = StringBuffer('tempo_ms;corrente_mA\n');
    for (var i = 0; i < w.ma.length; i++) {
      b.writeln('${fmt(i * w.samplePeriodUs / 1000, 3)};${fmt(w.ma[i], 3)}');
    }
    return saveExport('forma_onda_${r.shotId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}.csv', b.toString());
  }

  Future<String> saveExportBytes(String fileName, List<int> bytes) async {
    final path = await saveExport(fileName, '', bom: false);
    await File(path).writeAsBytes(bytes);
    return path;
  }

  // ---------------- Exportação ----------------

  /// Abre o menu de compartilhamento do Android (WhatsApp, e-mail, Drive…).
  Future<void> shareFile(String path, String subject) async {
    await SharePlus.instance.share(ShareParams(files: [XFile(path)], subject: subject, text: subject));
  }

  // ---------------- Backup ----------------

  Future<String> _writeBackup(String prefix, String appVersion) async {
    final data = await db.exportBackup(appVersion: appVersion);
    final n = DateTime.now();
    final name = '${prefix}_${n.year}${two(n.month)}${two(n.day)}_${two(n.hour)}${two(n.minute)}${two(n.second)}.json';
    return saveExport(name, const JsonEncoder.withIndent(' ').convert(data), bom: false);
  }

  /// Gera o arquivo de backup completo e devolve o caminho.
  Future<String> exportBackup(String appVersion) async {
    final path = await _writeBackup('xmeter_backup', appVersion);
    _say('Backup salvo: $path');
    return path;
  }

  /// Restaura um backup. Antes, salva automaticamente uma cópia dos dados
  /// atuais (xmeter_antes_restauracao_*.json) para poder desfazer.
  Future<String> importBackupFile(String path, String appVersion) async {
    Object? json;
    try {
      json = jsonDecode(await File(path).readAsString());
    } catch (_) {
      throw const BackupException('Não foi possível ler o arquivo. Escolha um backup .json do X-METER.');
    }
    if (json is! Map) throw const BackupException('Arquivo de backup inválido');
    final safety = await _writeBackup('xmeter_antes_restauracao', appVersion);
    disconnect();
    final counts = await db.importBackup(Map<String, Object?>.from(json));
    settings = await db.loadSettings();
    await reload();
    final msg = 'Backup restaurado: ${counts['equipment'] ?? 0} equipamento(s), '
        '${counts['readings'] ?? 0} medição(ões). Cópia dos dados anteriores: $safety';
    _say(msg);
    return msg;
  }

  /// Abre o seletor de arquivos do Android para escolher o backup.
  Future<String?> pickBackupFile() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.any);
    return res?.files.single.path;
  }

  Future<List<AuditEntry>> auditLog() => db.auditLog();

  Future<String> saveExport(String fileName, String content, {bool bom = true}) async {
    Directory? dir;
    if (Platform.isAndroid) {
      dir = await getExternalStorageDirectory();
    }
    dir ??= await getApplicationDocumentsDirectory();
    final folder = Directory(p.join(dir.path, 'exportacoes'));
    await folder.create(recursive: true);
    final file = File(p.join(folder.path, fileName));
    // BOM UTF-8 para o Excel abrir acentos corretamente.
    await file.writeAsString(bom ? '\uFEFF$content' : content);
    return file.path;
  }

  @override
  void dispose() {
    _disposed = true;
    _stopTimers();
    super.dispose();
  }
}

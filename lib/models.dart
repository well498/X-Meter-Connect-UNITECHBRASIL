import 'dart:convert';
import 'dart:math';

import 'calc.dart';

final _rand = Random.secure();

/// Identificador único (128 bits aleatórios em hexadecimal) com prefixo.
String newId(String prefix) {
  final b = List<int>.generate(16, (_) => _rand.nextInt(256));
  return '$prefix-${b.map((x) => x.toRadixString(16).padLeft(2, '0')).join()}';
}

String? _str(Object? v) {
  if (v == null) return null;
  final s = v.toString().trim();
  return s.isEmpty ? null : s;
}

double _dbl(Object? v, [double def = 0]) => v is num ? v.toDouble() : def;

class Equipment {
  final String id;
  final String? client;
  final String? site;
  final String manufacturer;
  final String model;
  final String? serialNumber;
  final String? internalId;
  final DateTime? calibrationDate;
  final String? technician;
  final GeneratorType generatorType;
  final bool archived;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Equipment({
    required this.id,
    this.client,
    this.site,
    required this.manufacturer,
    required this.model,
    this.serialNumber,
    this.internalId,
    this.calibrationDate,
    this.technician,
    this.generatorType = GeneratorType.highFrequency,
    this.archived = false,
    required this.createdAt,
    required this.updatedAt,
  });

  String get title => '$manufacturer $model';
  String get serialLabel => serialNumber ?? 'Não informado';

  Map<String, Object?> toMap() => {
        'id': id,
        'client': client,
        'site': site,
        'manufacturer': manufacturer,
        'model': model,
        'serial_number': serialNumber,
        'internal_id': internalId,
        'calibration_date': calibrationDate?.toIso8601String(),
        'technician': technician,
        'generator_type': generatorType.code,
        'archived': archived ? 1 : 0,
        'created_at': createdAt.toUtc().toIso8601String(),
        'updated_at': updatedAt.toUtc().toIso8601String(),
      };

  factory Equipment.fromMap(Map<String, Object?> m) => Equipment(
        id: m['id'].toString(),
        client: _str(m['client']),
        site: _str(m['site']),
        manufacturer: m['manufacturer'].toString(),
        model: m['model'].toString(),
        serialNumber: _str(m['serial_number']),
        internalId: _str(m['internal_id']),
        calibrationDate: DateTime.tryParse(m['calibration_date']?.toString() ?? ''),
        technician: _str(m['technician']),
        generatorType: GeneratorTypeInfo.fromCode(m['generator_type']?.toString()),
        archived: (m['archived'] as int? ?? 0) == 1,
        createdAt: DateTime.tryParse(m['created_at']?.toString() ?? '') ?? DateTime.now(),
        updatedAt: DateTime.tryParse(m['updated_at']?.toString() ?? '') ?? DateTime.now(),
      );
}

class MeasureSession {
  final String id;
  final String equipmentId;
  final double setMa;
  final double setMs;
  final bool setPending;
  final DateTime? setConfirmedAt;
  final String? deviceId;
  final DateTime startedAt;

  const MeasureSession({
    required this.id,
    required this.equipmentId,
    required this.setMa,
    required this.setMs,
    required this.setPending,
    this.setConfirmedAt,
    this.deviceId,
    required this.startedAt,
  });

  double get setMas => masFrom(setMa, setMs);

  factory MeasureSession.fromMap(Map<String, Object?> m) => MeasureSession(
        id: m['id'].toString(),
        equipmentId: m['equipment_id'].toString(),
        setMa: _dbl(m['set_ma']),
        setMs: _dbl(m['set_ms']),
        setPending: (m['set_pending'] as int? ?? 0) == 1,
        setConfirmedAt: DateTime.tryParse(m['set_confirmed_at']?.toString() ?? ''),
        deviceId: _str(m['device_id']),
        startedAt: DateTime.tryParse(m['started_at']?.toString() ?? '') ?? DateTime.now(),
      );
}

class Waveform {
  /// Período de amostragem em microssegundos.
  final double samplePeriodUs;

  /// Amostras de corrente do tubo em mA.
  final List<double> ma;

  const Waveform(this.samplePeriodUs, this.ma);

  double get durationMs => ma.length * samplePeriodUs / 1000.0;

  static Waveform? tryParse(Object? raw) {
    try {
      final Object? data = raw is String ? jsonDecode(raw) : raw;
      if (data is! Map) return null;
      final period = data['sample_period_us'];
      final samples = data['ma'];
      if (period is! num || period <= 0 || samples is! List || samples.isEmpty) return null;
      final values = <double>[];
      for (final s in samples) {
        if (s is! num || !s.toDouble().isFinite) return null;
        values.add(s.toDouble());
      }
      return Waveform(period.toDouble(), values);
    } catch (_) {
      return null;
    }
  }

  String toJson() => jsonEncode({'sample_period_us': samplePeriodUs, 'ma': ma});
}

class Reading {
  final String uid;
  final String deviceId;
  final String shotId;
  final String sessionId;
  final String equipmentId;

  /// 'device' = medição real recebida do instrumento;
  /// 'demo' = MODO DEMONSTRAÇÃO do aplicativo;
  /// 'simulator' = simulador de bancada (tools/xmeter_simulador.py).
  final String source;
  final double setMa;
  final double setMs;
  final double readMa;
  final double readMs;
  final double readMas;
  final double? errMa;
  final double? errMs;
  final double? errMas;
  final MeasureStatus status;
  final Waveform? waveform;
  final DateTime? recordedAt;
  final DateTime receivedAt;

  /// Tolerância vigente quando a medição foi gravada (rastreabilidade).
  final Tolerances? tolerances;

  const Reading({
    required this.uid,
    required this.deviceId,
    required this.shotId,
    required this.sessionId,
    required this.equipmentId,
    required this.source,
    required this.setMa,
    required this.setMs,
    required this.readMa,
    required this.readMs,
    required this.readMas,
    required this.errMa,
    required this.errMs,
    required this.errMas,
    required this.status,
    required this.waveform,
    required this.recordedAt,
    required this.receivedAt,
    this.tolerances,
  });

  /// Verdadeiro para QUALQUER dado não real (demonstração ou simulador).
  bool get isDemo => source != 'device';

  String get sourceLabel => switch (source) {
        'device' => 'INSTRUMENTO',
        'simulator' => 'SIMULADOR',
        _ => 'DEMONSTRAÇÃO',
      };
  double get setMas => masFrom(setMa, setMs);
  DateTime get when => recordedAt ?? receivedAt;

  factory Reading.fromMap(Map<String, Object?> m) {
    double? opt(Object? v) => v is num ? v.toDouble() : null;
    return Reading(
      uid: m['uid'].toString(),
      deviceId: m['device_id'].toString(),
      shotId: m['shot_id'].toString(),
      sessionId: m['session_id'].toString(),
      equipmentId: m['equipment_id'].toString(),
      source: m['source']?.toString() ?? 'device',
      setMa: _dbl(m['set_ma']),
      setMs: _dbl(m['set_ms']),
      readMa: _dbl(m['read_ma']),
      readMs: _dbl(m['read_ms']),
      readMas: _dbl(m['read_mas']),
      errMa: opt(m['err_ma']),
      errMs: opt(m['err_ms']),
      errMas: opt(m['err_mas']),
      status: MeasureStatusText.fromCode(m['status']?.toString()),
      waveform: Waveform.tryParse(m['waveform']),
      recordedAt: DateTime.tryParse(m['recorded_at']?.toString() ?? ''),
      receivedAt: DateTime.tryParse(m['received_at']?.toString() ?? '') ?? DateTime.now(),
      tolerances: m['tol_ma'] is num
          ? Tolerances(
              maPct: (m['tol_ma'] as num).toDouble(),
              msPct: _dbl(m['tol_ms'], 10),
              masPct: _dbl(m['tol_mas'], 10),
              alertFraction: _dbl(m['alert_fraction'], 0.8),
            )
          : null,
    );
  }
}

/// Avalia a medição com a tolerância GRAVADA nela; [fallback] só é usado em
/// registros sem tolerância gravada.
Evaluation evaluateReading(Reading r, Tolerances fallback) => evaluate(
      setMa: r.setMa,
      setMs: r.setMs,
      readMa: r.readMa,
      readMs: r.readMs,
      readMas: r.readMas,
      tol: r.tolerances ?? fallback,
    );

/// Entrada do registro de alterações (somente leitura).
class AuditEntry {
  final int id;
  final DateTime at;
  final String action;
  final String entity;
  final String? entityId;
  final Map<String, Object?> details;

  const AuditEntry(this.id, this.at, this.action, this.entity, this.entityId, this.details);

  factory AuditEntry.fromMap(Map<String, Object?> m) {
    Map<String, Object?> details = const {};
    final raw = m['details'];
    if (raw is String && raw.isNotEmpty) {
      try {
        final d = jsonDecode(raw);
        if (d is Map) details = Map<String, Object?>.from(d);
      } catch (_) {}
    }
    return AuditEntry(
      m['id'] as int,
      DateTime.tryParse(m['at']?.toString() ?? '') ?? DateTime.now(),
      m['action'].toString(),
      m['entity'].toString(),
      m['entity_id']?.toString(),
      details,
    );
  }
}

class AppSettings {
  final String host;
  final int port;
  final String token;
  final bool autoReconnect;
  /// Tolerâncias para geradores de alta frequência.
  final Tolerances tolerances;

  /// Tolerâncias para geradores convencionais microprocessados.
  final Tolerances tolerancesConv;
  final bool demoMode;
  final String? selectedEquipmentId;

  const AppSettings({
    this.host = '192.168.4.1',
    this.port = 8080,
    this.token = '',
    this.autoReconnect = true,
    this.tolerances = const Tolerances(),
    this.tolerancesConv = const Tolerances(),
    this.demoMode = false,
    this.selectedEquipmentId,
  });

  AppSettings copyWith({
    String? host,
    int? port,
    String? token,
    bool? autoReconnect,
    Tolerances? tolerances,
    Tolerances? tolerancesConv,
    bool? demoMode,
    String? selectedEquipmentId,
  }) =>
      AppSettings(
        host: host ?? this.host,
        port: port ?? this.port,
        token: token ?? this.token,
        autoReconnect: autoReconnect ?? this.autoReconnect,
        tolerances: tolerances ?? this.tolerances,
        tolerancesConv: tolerancesConv ?? this.tolerancesConv,
        demoMode: demoMode ?? this.demoMode,
        selectedEquipmentId: selectedEquipmentId ?? this.selectedEquipmentId,
      );

  Map<String, String> toMap() => {
        'host': host,
        'port': port.toString(),
        'token': token,
        'auto_reconnect': autoReconnect ? '1' : '0',
        'tol_ma': tolerances.maPct.toString(),
        'tol_ms': tolerances.msPct.toString(),
        'tol_mas': tolerances.masPct.toString(),
        'alert_fraction': tolerances.alertFraction.toString(),
        'conv_tol_ma': tolerancesConv.maPct.toString(),
        'conv_tol_ms': tolerancesConv.msPct.toString(),
        'conv_tol_mas': tolerancesConv.masPct.toString(),
        'conv_alert_fraction': tolerancesConv.alertFraction.toString(),
        'demo_mode': demoMode ? '1' : '0',
        if (selectedEquipmentId != null) 'selected_equipment': selectedEquipmentId!,
      };

  Tolerances tolFor(GeneratorType t) =>
      t == GeneratorType.conventional ? tolerancesConv : tolerances;

  factory AppSettings.fromMap(Map<String, String> m) {
    const d = AppSettings();
    double n(String k, double def) => double.tryParse(m[k] ?? '') ?? def;
    return AppSettings(
      host: m['host'] ?? d.host,
      port: int.tryParse(m['port'] ?? '') ?? d.port,
      token: m['token'] ?? d.token,
      autoReconnect: (m['auto_reconnect'] ?? '1') == '1',
      tolerances: Tolerances(
        maPct: n('tol_ma', d.tolerances.maPct),
        msPct: n('tol_ms', d.tolerances.msPct),
        masPct: n('tol_mas', d.tolerances.masPct),
        alertFraction: n('alert_fraction', d.tolerances.alertFraction),
      ),
      tolerancesConv: Tolerances(
        maPct: n('conv_tol_ma', d.tolerancesConv.maPct),
        msPct: n('conv_tol_ms', d.tolerancesConv.msPct),
        masPct: n('conv_tol_mas', d.tolerancesConv.masPct),
        alertFraction: n('conv_alert_fraction', d.tolerancesConv.alertFraction),
      ),
      demoMode: (m['demo_mode'] ?? '0') == '1',
      selectedEquipmentId: m['selected_equipment'],
    );
  }
}

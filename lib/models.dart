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

double? _optDbl(Object? v) => v is num && v.toDouble().isFinite ? v.toDouble() : null;

class Equipment {
  final String id;
  final String? client;
  final String? site;

  /// Fabricante e modelo do APARELHO de raios X.
  final String manufacturer;
  final String model;
  final String? serialNumber;
  final String? internalId;
  final DateTime? calibrationDate;
  final String? technician;

  /// Gerador: tecnologia, fabricante, modelo e potência nominal.
  final GeneratorType generatorType;
  final String? generatorMaker;
  final String? generatorModel;
  final double? powerKw;

  /// Limites REAIS do manual técnico (null = faixa de referência do tipo).
  final double? minMa;
  final double? maxMa;
  final double? minMs;
  final double? maxMs;
  final double? maxMas;

  /// Perfil de gerador (faixas, estações e critério de aceitação).
  final String? profileId;

  /// Tubo de raios X instalado.
  final String? tubeMaker;
  final String? tubeModel;

  /// Observações gerais do equipamento.
  final String? notes;

  /// Foto do equipamento (arquivo no aparelho).
  final String? photoPath;
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
    this.generatorType = GeneratorType.unknown,
    this.generatorMaker,
    this.generatorModel,
    this.powerKw,
    this.minMa,
    this.maxMa,
    this.minMs,
    this.maxMs,
    this.maxMas,
    this.profileId,
    this.tubeMaker,
    this.tubeModel,
    this.notes,
    this.photoPath,
    this.archived = false,
    required this.createdAt,
    required this.updatedAt,
  });

  String get title => '$manufacturer $model';
  String get serialLabel => serialNumber ?? 'Não informado';

  /// true quando algum limite veio do manual (e não da referência do tipo).
  bool get hasCustomLimits =>
      minMa != null || maxMa != null || minMs != null || maxMs != null || maxMas != null;

  /// Limites efetivos: os do manual quando informados; senão os de referência.
  GeneratorLimits get limits {
    final r = generatorType.referenceLimits;
    return GeneratorLimits(
        minMa ?? r.minMa, maxMa ?? r.maxMa, minMs ?? r.minMs, maxMs ?? r.maxMs, maxMas ?? r.maxMas);
  }

  List<double> get maStations => stepsWithin(generatorType.maSteps, limits.minMa, limits.maxMa);
  List<double> get msStations => stepsWithin(generatorType.msSteps, limits.minMs, limits.maxMs);

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
        'generator_maker': generatorMaker,
        'generator_model': generatorModel,
        'power_kw': powerKw,
        'min_ma': minMa,
        'max_ma': maxMa,
        'min_ms': minMs,
        'max_ms': maxMs,
        'max_mas': maxMas,
        'profile_id': profileId,
        'tube_maker': tubeMaker,
        'tube_model': tubeModel,
        'notes': notes,
        'photo_path': photoPath,
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
        generatorMaker: _str(m['generator_maker']),
        generatorModel: _str(m['generator_model']),
        powerKw: _optDbl(m['power_kw']),
        minMa: _optDbl(m['min_ma']),
        maxMa: _optDbl(m['max_ma']),
        minMs: _optDbl(m['min_ms']),
        maxMs: _optDbl(m['max_ms']),
        maxMas: _optDbl(m['max_mas']),
        profileId: _str(m['profile_id']),
        tubeMaker: _str(m['tube_maker']),
        tubeModel: _str(m['tube_model']),
        notes: _str(m['notes']),
        photoPath: _str(m['photo_path']),
        archived: (m['archived'] as int? ?? 0) == 1,
        createdAt: DateTime.tryParse(m['created_at']?.toString() ?? '') ?? DateTime.now(),
        updatedAt: DateTime.tryParse(m['updated_at']?.toString() ?? '') ?? DateTime.now(),
      );

  Equipment copyWith({String? photoPath, GeneratorType? generatorType}) => Equipment.fromMap({
        ...toMap(),
        if (photoPath != null) 'photo_path': photoPath,
        if (generatorType != null) 'generator_type': generatorType.code,
      });
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

  /// Identificação da sessão dada pelo técnico (opcional).
  final String? label;

  /// Origem da última alteração do SET: 'app' ou 'instrumento'.
  final String setOrigin;
  final DateTime? setChangedAt;

  /// Metadados do teste informados pelo técnico (o X-METER não mede kV).
  final String? tubeModel;
  final String? kvInfo;

  const MeasureSession({
    required this.id,
    required this.equipmentId,
    required this.setMa,
    required this.setMs,
    required this.setPending,
    this.setConfirmedAt,
    this.deviceId,
    required this.startedAt,
    this.label,
    this.setOrigin = 'app',
    this.setChangedAt,
    this.tubeModel,
    this.kvInfo,
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
        label: _str(m['label']),
        setOrigin: _str(m['set_origin']) ?? 'app',
        setChangedAt: DateTime.tryParse(m['set_changed_at']?.toString() ?? ''),
        tubeModel: _str(m['tube_model']),
        kvInfo: _str(m['kv_info']),
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

  /// Corrente máxima durante a exposição (mA). [readMa] é a corrente média.
  final double? maPeak;

  /// Indicadores de qualidade da aquisição (códigos).
  final List<String> quality;

  /// Identificação da sonda e estado de calibração informados pelo instrumento.
  final String? probeId;
  final String? calStatus;

  /// Perfil de gerador usado na avaliação.
  final String? profileId;

  /// Indicadores que tornam a medição INVÁLIDA (nunca aprovada).
  static const invalidFlags = {'fora_da_faixa', 'saturated', 'noExposure', 'tooShort'};
  bool get isInvalid => status == MeasureStatus.invalid || quality.any(invalidFlags.contains);

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
    this.maPeak,
    this.quality = const [],
    this.probeId,
    this.calStatus,
    this.profileId,
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
              masAbs: _dbl(m['tol_mas_abs'], 0),
              alertFraction: _dbl(m['alert_fraction'], 0.8),
              origin: _str(m['tol_origin']),
            )
          : null,
      profileId: _str(m['profile_id']),
      maPeak: opt(m['ma_peak']),
      quality: _strList(m['quality']),
      probeId: _str(m['probe_id']),
      calStatus: _str(m['cal_status']),
    );
  }
}

List<String> _strList(Object? raw) {
  if (raw is List) return raw.map((e) => e.toString()).toList();
  if (raw is String && raw.isNotEmpty) {
    try {
      final d = jsonDecode(raw);
      if (d is List) return d.map((e) => e.toString()).toList();
    } catch (_) {}
  }
  return const [];
}

/// Observação do técnico (registro somente de inclusão; não é editável).
class Note {
  final int id;
  final String sessionId;
  final String? readingUid;
  final String text;
  final DateTime at;
  const Note(this.id, this.sessionId, this.readingUid, this.text, this.at);

  factory Note.fromMap(Map<String, Object?> m) => Note(
        m['id'] as int,
        m['session_id'].toString(),
        _str(m['reading_uid']),
        m['text'].toString(),
        DateTime.tryParse(m['at']?.toString() ?? '') ?? DateTime.now(),
      );
}

/// Avalia a medição com a tolerância GRAVADA nela; [fallback] só é usado em
/// registros sem tolerância gravada.
Evaluation evaluateReading(Reading r, Tolerances fallback) {
  final ev = evaluate(
    setMa: r.setMa,
    setMs: r.setMs,
    readMa: r.readMa,
    readMs: r.readMs,
    readMas: r.readMas,
    tol: r.tolerances ?? fallback,
  );
  return r.isInvalid ? Evaluation(ev.errMa, ev.errMs, ev.errMas, MeasureStatus.invalid) : ev;
}

/// Perfil de gerador: faixas, estações de mA/tempo, tubos e critério de
/// aceitação com origem e versão. Perfis "builtin" vêm com o aplicativo.
class GeneratorProfile {
  final String id;
  final String name;
  final String? maker;
  final String? model;
  final GeneratorType type;
  final double? powerKw;
  final double? inverterKhz;

  /// Estações de corrente específicas (null = tabela do tipo).
  final List<double>? maStations;
  final double? minMa;
  final double? maxMa;
  final double? minMs;
  final double? maxMs;
  final double? minMas;
  final double? maxMas;
  final Tolerances tolerances;
  final List<String> tubes;
  final bool builtin;
  final String? notes;

  const GeneratorProfile({
    required this.id,
    required this.name,
    this.maker,
    this.model,
    required this.type,
    this.powerKw,
    this.inverterKhz,
    this.maStations,
    this.minMa,
    this.maxMa,
    this.minMs,
    this.maxMs,
    this.minMas,
    this.maxMas,
    required this.tolerances,
    this.tubes = const [],
    this.builtin = false,
    this.notes,
  });

  GeneratorLimits get limits {
    final r = type.referenceLimits;
    final st = maStations;
    return GeneratorLimits(
      minMa ?? (st != null && st.isNotEmpty ? st.first : r.minMa),
      maxMa ?? (st != null && st.isNotEmpty ? st.last : r.maxMa),
      minMs ?? r.minMs,
      maxMs ?? r.maxMs,
      maxMas ?? r.maxMas,
      minMas: minMas ?? r.minMas,
    );
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'maker': maker,
        'model': model,
        'generator_type': type.code,
        'power_kw': powerKw,
        'inverter_khz': inverterKhz,
        'ma_stations': maStations == null ? null : jsonEncode(maStations),
        'min_ma': minMa,
        'max_ma': maxMa,
        'min_ms': minMs,
        'max_ms': maxMs,
        'min_mas': minMas,
        'max_mas': maxMas,
        'tol_ma_pct': tolerances.maPct,
        'tol_ms_pct': tolerances.msPct,
        'tol_mas_pct': tolerances.masPct,
        'tol_mas_abs': tolerances.masAbs,
        'alert_fraction': tolerances.alertFraction,
        'tol_origin': tolerances.origin,
        'tol_version': tolerances.version,
        'tubes': jsonEncode(tubes),
        'builtin': builtin ? 1 : 0,
        'notes': notes,
      };

  factory GeneratorProfile.fromMap(Map<String, Object?> m) {
    List<double>? st;
    final raw = m['ma_stations'];
    if (raw is String && raw.isNotEmpty) {
      try {
        final d = jsonDecode(raw);
        if (d is List) st = d.whereType<num>().map((e) => e.toDouble()).toList();
      } catch (_) {}
    }
    return GeneratorProfile(
      id: m['id'].toString(),
      name: m['name'].toString(),
      maker: _str(m['maker']),
      model: _str(m['model']),
      type: GeneratorTypeInfo.fromCode(m['generator_type']?.toString()),
      powerKw: _optDbl(m['power_kw']),
      inverterKhz: _optDbl(m['inverter_khz']),
      maStations: (st == null || st.isEmpty) ? null : st,
      minMa: _optDbl(m['min_ma']),
      maxMa: _optDbl(m['max_ma']),
      minMs: _optDbl(m['min_ms']),
      maxMs: _optDbl(m['max_ms']),
      minMas: _optDbl(m['min_mas']),
      maxMas: _optDbl(m['max_mas']),
      tolerances: Tolerances(
        maPct: _dbl(m['tol_ma_pct'], 10),
        msPct: _dbl(m['tol_ms_pct'], 10),
        masPct: _dbl(m['tol_mas_pct'], 10),
        masAbs: _dbl(m['tol_mas_abs'], 0),
        alertFraction: _dbl(m['alert_fraction'], 0.8),
        origin: _str(m['tol_origin']),
        version: _str(m['tol_version']),
      ),
      tubes: _strList(m['tubes']),
      builtin: (m['builtin'] as int? ?? 0) == 1,
      notes: _str(m['notes']),
    );
  }
}

/// Perfis que acompanham o aplicativo.
class BuiltinProfiles {
  static const sawaeAltusId = 'perfil-sawae-altus-st543hf';

  /// Perfil genérico (editável) de cada tipo de gerador.
  static String genericId(GeneratorType t) => 'perfil-generico-${t.code}';

  static const userOrigin = 'Configuração do usuário (perfil genérico)';

  static GeneratorProfile generic(GeneratorType t, Tolerances tol) => GeneratorProfile(
        id: genericId(t),
        name: 'Genérico — ${t.label}',
        type: t,
        tolerances: Tolerances(
          maPct: tol.maPct,
          msPct: tol.msPct,
          masPct: tol.masPct,
          masAbs: tol.masAbs,
          alertFraction: tol.alertFraction,
          origin: tol.origin ?? userOrigin,
          version: tol.version ?? '1',
        ),
        builtin: true,
      );

  /// SAWAE ALTUS ST 543-HF — Manual Técnico do Conjunto Radiológico ALTUS,
  /// revisão 19 (20/02/2015). Critério do manual apenas para o mAs.
  static const sawaeAltus = GeneratorProfile(
    id: sawaeAltusId,
    name: 'SAWAE ALTUS ST 543-HF',
    maker: 'SAWAE',
    model: 'ALTUS ST 543-HF',
    type: GeneratorType.highFrequency,
    powerKw: 54,
    inverterKhz: 36,
    maStations: [80, 100, 125, 160, 200, 250, 320, 400, 500, 630],
    minMas: 0.4,
    maxMas: 500,
    tolerances: Tolerances(
      maPct: 0,
      msPct: 0,
      masPct: 10,
      masAbs: 0.2,
      alertFraction: 0.8,
      origin: 'Manual Técnico do Conjunto Radiológico ALTUS, rev. 19 (20/02/2015)',
      version: 'rev. 19',
    ),
    tubes: ['Toshiba E7242FX', 'Toshiba E7252FX', 'Siemens Ray8', 'Siemens Ray12'],
    builtin: true,
    notes: 'Aferição pelo manual: medidor de mAs externo e observação da forma de onda da corrente. '
        'Referência de preparo influencia o pico inicial; referência de disparo influencia a amplitude '
        'durante a exposição e o mAs. O critério do manual é só para o mAs; mA e tempo são exibidos sem '
        'classificação.',
  );
}

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

  /// Tolerâncias para geradores de alta frequência (e "a identificar").
  final Tolerances tolerances;

  /// Tolerâncias para geradores convencionais (2, 6 e 12 pulsos).
  final Tolerances tolerancesConv;
  final bool demoMode;
  final String? selectedEquipmentId;

  /// Detecção da exposição: limiar de início/medição do tempo (% do pico),
  /// limiar de fim (histerese, % do pico) e duração mínima (ms).
  final double detStartPct;
  final double detEndPct;
  final double detMinMs;

  /// Limite do coeficiente de variação (%) na repetibilidade.
  final double cvLimitPct;

  /// Exibir o tempo em segundos (true) ou milissegundos (false).
  final bool timeInSeconds;

  const AppSettings({
    this.host = '192.168.4.1',
    this.port = 8080,
    this.token = '',
    this.autoReconnect = true,
    this.tolerances = const Tolerances(),
    this.tolerancesConv = const Tolerances(),
    this.demoMode = false,
    this.selectedEquipmentId,
    this.detStartPct = 50,
    this.detEndPct = 40,
    this.detMinMs = 0.5,
    this.cvLimitPct = 5,
    this.timeInSeconds = false,
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
    double? detStartPct,
    double? detEndPct,
    double? detMinMs,
    double? cvLimitPct,
    bool? timeInSeconds,
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
        detStartPct: detStartPct ?? this.detStartPct,
        detEndPct: detEndPct ?? this.detEndPct,
        detMinMs: detMinMs ?? this.detMinMs,
        cvLimitPct: cvLimitPct ?? this.cvLimitPct,
        timeInSeconds: timeInSeconds ?? this.timeInSeconds,
      );

  /// Convencionais (2, 6 e 12 pulsos) usam [tolerancesConv]; HF e
  /// "a identificar" usam [tolerances].
  Tolerances tolFor(GeneratorType t) => t.isConventional ? tolerancesConv : tolerances;

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
        'det_start_pct': detStartPct.toString(),
        'det_end_pct': detEndPct.toString(),
        'det_min_ms': detMinMs.toString(),
        'cv_limit_pct': cvLimitPct.toString(),
        'time_unit': timeInSeconds ? 's' : 'ms',
        if (selectedEquipmentId != null) 'selected_equipment': selectedEquipmentId!,
      };

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
      detStartPct: n('det_start_pct', d.detStartPct),
      detEndPct: n('det_end_pct', d.detEndPct),
      detMinMs: n('det_min_ms', d.detMinMs),
      cvLimitPct: n('cv_limit_pct', d.cvLimitPct),
      timeInSeconds: m['time_unit'] == 's',
    );
  }
}

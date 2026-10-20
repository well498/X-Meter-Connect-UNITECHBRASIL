import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import 'analysis.dart';

import 'calc.dart';
import 'models.dart';

/// Equipamento e SET iniciais exigidos na especificação.
const seedEquipmentId = 'equip-siemens-multix-b-initial';
const seedSessionId = 'session-multix-b-initial';
const seedSetMa = 200.0;
const seedSetMs = 100.0;

/// Identificação do formato de backup (arquivo .json).
const backupFormat = 'unitech-xmeter-backup';

class MergeResult {
  final int inserted;
  final int duplicates;
  final int rejected;
  const MergeResult(this.inserted, this.duplicates, this.rejected);
}

/// Resultado de uma alteração de SET.
class SetChange {
  final String sessionId;

  /// true quando a sessão anterior já tinha medições e outra foi aberta.
  final bool newSession;
  const SetChange(this.sessionId, this.newSession);
}

class BackupException implements Exception {
  final String message;
  const BackupException(this.message);
  @override
  String toString() => message;
}

/// Persistência local (SQLite). Funciona 100% offline.
///
/// Versão 1 = esquema do pacote V1.5 original.
/// Versão 2 = cadastro completo, sessões, leituras com status e forma de onda.
/// Versão 3 = tolerância gravada por medição, equipamentos arquivados,
///            registro de alterações e proteção das medições reais.
/// Versão 4 = gerador (tecnologia, fabricante, modelo, potência, limites),
///            foto, identificação da sessão, corrente máxima, indicadores de
///            qualidade, sonda/calibração e observações do técnico.
/// Versão 5 = perfis de gerador (faixas, estações, critério com origem e
///            versão — inclui SAWAE ALTUS), tubo, observações do equipamento,
///            origem do SET (app/instrumento), kV como metadado e cadastro
///            de instrumentos (firmware, bateria, modo, calibração).
class XDatabase {
  static const schemaVersion = 5;

  /// Tabelas na ordem segura para inserir (respeita as chaves estrangeiras).
  static const tables = [
    'generator_profiles', 'equipment', 'sessions', 'readings', 'notes', //
    'sync_state', 'instruments', 'settings', 'audit_log',
  ];

  final Database db;
  XDatabase(this.db);

  static Future<XDatabase> open(String path, {DatabaseFactory? factory}) async {
    final f = factory ?? databaseFactory;
    final db = await f.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onConfigure: (d) => d.execute('PRAGMA foreign_keys = ON'),
        onCreate: (d, _) async {
          await _createV2(d);
          await _upgradeV2toV3(d);
          await _upgradeV3toV4(d);
          await _upgradeV4toV5(d);
        },
        onUpgrade: (d, oldV, newV) async {
          if (oldV < 2) await _migrateV1toV2(d);
          if (oldV < 3) await _upgradeV2toV3(d);
          if (oldV < 4) await _upgradeV3toV4(d);
          if (oldV < 5) await _upgradeV4toV5(d);
        },
      ),
    );
    final store = XDatabase(db);
    await store.seedIfEmpty();
    return store;
  }

  static Future<void> _createV2(DatabaseExecutor d) async {
    await d.execute('''CREATE TABLE equipment (
      id TEXT PRIMARY KEY,
      client TEXT, site TEXT,
      manufacturer TEXT NOT NULL, model TEXT NOT NULL,
      serial_number TEXT, internal_id TEXT,
      calibration_date TEXT, technician TEXT,
      created_at TEXT NOT NULL, updated_at TEXT NOT NULL)''');
    await d.execute('''CREATE TABLE sessions (
      id TEXT PRIMARY KEY,
      equipment_id TEXT NOT NULL REFERENCES equipment(id) ON DELETE CASCADE,
      set_ma REAL NOT NULL, set_ms REAL NOT NULL,
      set_pending INTEGER NOT NULL DEFAULT 1,
      set_confirmed_at TEXT, device_id TEXT,
      started_at TEXT NOT NULL)''');
    await d.execute('''CREATE TABLE readings (
      uid TEXT PRIMARY KEY,
      device_id TEXT NOT NULL, shot_id TEXT NOT NULL,
      session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
      equipment_id TEXT NOT NULL REFERENCES equipment(id) ON DELETE CASCADE,
      source TEXT NOT NULL CHECK (source IN ('device','demo','simulator')),
      set_ma REAL NOT NULL, set_ms REAL NOT NULL,
      read_ma REAL NOT NULL, read_ms REAL NOT NULL, read_mas REAL NOT NULL,
      err_ma REAL, err_ms REAL, err_mas REAL,
      status TEXT NOT NULL,
      waveform TEXT,
      recorded_at TEXT, received_at TEXT NOT NULL,
      UNIQUE(device_id, shot_id))''');
    await d.execute('CREATE INDEX idx_readings_equipment ON readings(equipment_id, received_at)');
    await d.execute('''CREATE TABLE sync_state (
      device_id TEXT PRIMARY KEY, last_cursor INTEGER NOT NULL DEFAULT 0)''');
    await d.execute('CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)');
  }

  /// Converte um banco criado pela V1.5 sem perder cadastro, SET ou leituras.
  /// Executado pelo sqflite dentro da transação de upgrade (não abrir outra).
  static Future<void> _migrateV1toV2(Database txn) async {
    for (final t in ['equipment', 'sessions', 'readings', 'sync_state']) {
      await txn.execute('ALTER TABLE $t RENAME TO ${t}_v1');
    }
    await _createV2(txn);
    final now = DateTime.now().toUtc().toIso8601String();
    await txn.execute('''INSERT INTO equipment
      (id, manufacturer, model, serial_number, created_at, updated_at)
      SELECT id, manufacturer, model, serial_number, created_at, '$now' FROM equipment_v1''');
    await txn.execute('''INSERT INTO sessions
      (id, equipment_id, set_ma, set_ms, set_pending, started_at)
      SELECT id, equipment_id, set_ma, set_ms, 1, created_at FROM sessions_v1''');
    final old = await txn.rawQuery('''SELECT r.*, s.equipment_id AS eq
      FROM readings_v1 r JOIN sessions_v1 s ON s.id = r.session_id''');
    for (final r in old) {
      final setMa = (r['set_ma'] as num).toDouble();
      final setMs = (r['set_ms'] as num).toDouble();
      final ev = evaluate(
        setMa: setMa,
        setMs: setMs,
        readMa: (r['read_ma'] as num).toDouble(),
        readMs: (r['read_ms'] as num).toDouble(),
        readMas: (r['read_mas'] as num).toDouble(),
        tol: const Tolerances(),
      );
      await txn.insert('readings', {
        'uid': newId('rd'),
        'device_id': r['device_id'],
        'shot_id': r['shot_id'],
        'session_id': r['session_id'],
        'equipment_id': r['eq'],
        'source': 'device',
        'set_ma': setMa,
        'set_ms': setMs,
        'read_ma': r['read_ma'],
        'read_ms': r['read_ms'],
        'read_mas': r['read_mas'],
        'err_ma': ev.errMa,
        'err_ms': ev.errMs,
        'err_mas': ev.errMas,
        'status': ev.status.code,
        'recorded_at': r['recorded_at'],
        'received_at': r['recorded_at'] ?? now,
      });
    }
    await txn.execute('INSERT INTO sync_state SELECT device_id, last_cursor FROM sync_state_v1');
    for (final t in ['readings', 'sessions', 'equipment', 'sync_state']) {
      await txn.execute('DROP TABLE ${t}_v1');
    }
  }

  /// V3: tolerância por medição, arquivamento, auditoria e proteção.
  static Future<void> _upgradeV2toV3(DatabaseExecutor d) async {
    await d.execute('ALTER TABLE equipment ADD COLUMN archived INTEGER NOT NULL DEFAULT 0');
    await d.execute("ALTER TABLE equipment ADD COLUMN generator_type TEXT NOT NULL DEFAULT 'hf'");
    for (final c in ['tol_ma', 'tol_ms', 'tol_mas', 'alert_fraction']) {
      await d.execute('ALTER TABLE readings ADD COLUMN $c REAL');
    }
    // Medições antigas recebem a tolerância padrão vigente até a V1.6.
    const t = Tolerances();
    await d.execute('UPDATE readings SET tol_ma = ?, tol_ms = ?, tol_mas = ?, alert_fraction = ? '
        'WHERE tol_ma IS NULL', [t.maPct, t.msPct, t.masPct, t.alertFraction]);
    await d.execute('''CREATE TABLE audit_log (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      at TEXT NOT NULL, action TEXT NOT NULL,
      entity TEXT NOT NULL, entity_id TEXT, details TEXT)''');
    await _createProtection(d);
  }

  /// V4: dados do gerador, limites do manual, foto, sessão, pico, qualidade,
  /// sonda e observações.
  static Future<void> _upgradeV3toV4(DatabaseExecutor d) async {
    for (final c in [
      'generator_maker TEXT',
      'generator_model TEXT',
      'power_kw REAL',
      'min_ma REAL',
      'max_ma REAL',
      'min_ms REAL',
      'max_ms REAL',
      'max_mas REAL',
      'photo_path TEXT',
    ]) {
      await d.execute('ALTER TABLE equipment ADD COLUMN $c');
    }
    await d.execute('ALTER TABLE sessions ADD COLUMN label TEXT');
    for (final c in ['ma_peak REAL', 'quality TEXT', 'probe_id TEXT', 'cal_status TEXT']) {
      await d.execute('ALTER TABLE readings ADD COLUMN $c');
    }
    await d.execute('''CREATE TABLE notes (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      session_id TEXT NOT NULL REFERENCES sessions(id),
      reading_uid TEXT,
      text TEXT NOT NULL,
      at TEXT NOT NULL)''');
    // Não presumir a tecnologia do gerador do cadastro inicial: se o técnico
    // nunca a alterou, passa para "A identificar".
    await d.execute('''UPDATE equipment SET generator_type = 'unknown'
      WHERE id = '$seedEquipmentId' AND NOT EXISTS (
        SELECT 1 FROM audit_log WHERE entity_id = '$seedEquipmentId' AND details LIKE '%generator_type%')''');
    await _createProtection(d);
  }

  /// V5: perfis de gerador, tubo, origem do SET, kV (metadado), instrumentos.
  static Future<void> _upgradeV4toV5(DatabaseExecutor d) async {
    await d.execute('''CREATE TABLE generator_profiles (
      id TEXT PRIMARY KEY, name TEXT NOT NULL, maker TEXT, model TEXT,
      generator_type TEXT NOT NULL, power_kw REAL, inverter_khz REAL,
      ma_stations TEXT, min_ma REAL, max_ma REAL, min_ms REAL, max_ms REAL,
      min_mas REAL, max_mas REAL,
      tol_ma_pct REAL NOT NULL, tol_ms_pct REAL NOT NULL, tol_mas_pct REAL NOT NULL,
      tol_mas_abs REAL NOT NULL DEFAULT 0, alert_fraction REAL NOT NULL,
      tol_origin TEXT, tol_version TEXT, tubes TEXT,
      builtin INTEGER NOT NULL DEFAULT 0, notes TEXT,
      created_at TEXT, updated_at TEXT)''');
    for (final c in ['profile_id TEXT', 'tube_maker TEXT', 'tube_model TEXT', 'notes TEXT']) {
      await d.execute('ALTER TABLE equipment ADD COLUMN $c');
    }
    for (final c in ["set_origin TEXT NOT NULL DEFAULT 'app'", 'set_changed_at TEXT', 'tube_model TEXT', 'kv_info TEXT']) {
      await d.execute('ALTER TABLE sessions ADD COLUMN $c');
    }
    for (final c in ['tol_mas_abs REAL', 'tol_origin TEXT', 'profile_id TEXT']) {
      await d.execute('ALTER TABLE readings ADD COLUMN $c');
    }
    await d.execute('''CREATE TABLE instruments (
      device_id TEXT PRIMARY KEY, firmware TEXT, model TEXT, protocol INTEGER,
      battery_pct REAL, charging INTEGER, mode TEXT, transport TEXT,
      calibration TEXT, alerts TEXT, simulated INTEGER, last_seen TEXT NOT NULL)''');

    // Perfis genéricos herdam as tolerâncias configuradas na V1.7/1.8:
    // HF e "a identificar" ← tolerância HF; convencionais ← tolerância conv.
    final rows = await d.query('settings');
    final st = AppSettings.fromMap({for (final r in rows) r['key'].toString(): r['value'].toString()});
    final now = DateTime.now().toUtc().toIso8601String();
    for (final t in GeneratorType.values) {
      final p = BuiltinProfiles.generic(t, st.tolFor(t));
      await d.insert('generator_profiles', {...p.toMap(), 'created_at': now, 'updated_at': now},
          conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    await d.insert('generator_profiles',
        {...BuiltinProfiles.sawaeAltus.toMap(), 'created_at': now, 'updated_at': now},
        conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  /// Gatilhos do banco: medições reais e o registro de alterações não podem
  /// ser apagados nem modificados (só o backup completo as substitui).
  static Future<void> _createProtection(DatabaseExecutor d) async {
    await d.execute('''CREATE TRIGGER IF NOT EXISTS protect_readings_delete
      BEFORE DELETE ON readings WHEN OLD.source = 'device'
      BEGIN SELECT RAISE(ABORT, 'Medicao real nao pode ser apagada'); END''');
    await d.execute('''CREATE TRIGGER IF NOT EXISTS protect_readings_update
      BEFORE UPDATE ON readings WHEN OLD.source = 'device'
      BEGIN SELECT RAISE(ABORT, 'Medicao real nao pode ser alterada'); END''');
    await d.execute('''CREATE TRIGGER IF NOT EXISTS protect_audit_delete
      BEFORE DELETE ON audit_log
      BEGIN SELECT RAISE(ABORT, 'Registro de alteracoes nao pode ser apagado'); END''');
    await d.execute('''CREATE TRIGGER IF NOT EXISTS protect_audit_update
      BEFORE UPDATE ON audit_log
      BEGIN SELECT RAISE(ABORT, 'Registro de alteracoes nao pode ser alterado'); END''');
    final hasNotes = (await d.rawQuery("SELECT name FROM sqlite_master WHERE type='table' AND name='notes'")).isNotEmpty;
    if (hasNotes) {
      await d.execute('''CREATE TRIGGER IF NOT EXISTS protect_notes_delete
        BEFORE DELETE ON notes
        BEGIN SELECT RAISE(ABORT, 'Observacao nao pode ser apagada'); END''');
      await d.execute('''CREATE TRIGGER IF NOT EXISTS protect_notes_update
        BEFORE UPDATE ON notes
        BEGIN SELECT RAISE(ABORT, 'Observacao nao pode ser alterada'); END''');
    }
  }

  static Future<void> _dropProtection(DatabaseExecutor d) async {
    for (final t in [
      'protect_readings_delete',
      'protect_readings_update',
      'protect_audit_delete',
      'protect_audit_update',
      'protect_notes_delete',
      'protect_notes_update',
    ]) {
      await d.execute('DROP TRIGGER IF EXISTS $t');
    }
  }

  // ---------------- Registro de alterações ----------------

  static Future<void> _audit(DatabaseExecutor d, String action, String entity, String? entityId,
      [Map<String, Object?> details = const {}]) async {
    await d.insert('audit_log', {
      'at': DateTime.now().toUtc().toIso8601String(),
      'action': action,
      'entity': entity,
      'entity_id': entityId,
      'details': details.isEmpty ? null : jsonEncode(details),
    });
  }

  Future<void> audit(String action, String entity, String? entityId,
          [Map<String, Object?> details = const {}]) =>
      _audit(db, action, entity, entityId, details);

  Future<List<AuditEntry>> auditLog({int limit = 300}) async {
    final rows = await db.query('audit_log', orderBy: 'id DESC', limit: limit);
    return rows.map(AuditEntry.fromMap).toList();
  }

  Future<void> seedIfEmpty() async {
    final count = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM equipment')) ?? 0;
    if (count > 0) return;
    final now = DateTime.now();
    await db.transaction((txn) async {
      await txn.insert(
          'equipment',
          Equipment(
            id: seedEquipmentId,
            manufacturer: 'Siemens',
            model: 'Multix B',
            serialNumber: null,
            calibrationDate: DateTime(now.year, now.month, now.day),
            createdAt: now,
            updatedAt: now,
          ).toMap());
      await txn.insert('sessions', {
        'id': seedSessionId,
        'equipment_id': seedEquipmentId,
        'set_ma': seedSetMa,
        'set_ms': seedSetMs,
        'set_pending': 1,
        'started_at': now.toUtc().toIso8601String(),
      });
      await _audit(txn, 'criado', 'equipamento', seedEquipmentId,
          {'cadastro': 'inicial', 'equipamento': 'Siemens Multix B', 'set': '200 mA / 100 ms'});
    });
  }

  // ---------------- Configurações ----------------

  Future<AppSettings> loadSettings() async {
    final rows = await db.query('settings');
    return AppSettings.fromMap({for (final r in rows) r['key'].toString(): r['value'].toString()});
  }

  Future<void> saveSettings(AppSettings s) async {
    await db.transaction((txn) async {
      final rows = await txn.query('settings');
      final old = {for (final r in rows) r['key'].toString(): r['value'].toString()};
      final changes = <String, Object?>{};
      for (final e in s.toMap().entries) {
        if (old[e.key] != e.value && e.key != 'selected_equipment') {
          changes[e.key] = e.key == 'token' ? '(alterado)' : '${old[e.key] ?? '—'} → ${e.value}';
        }
        await txn.insert('settings', {'key': e.key, 'value': e.value},
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
      if (changes.isNotEmpty) await _audit(txn, 'alterado', 'configuracoes', null, changes);
    });
  }

  // ---------------- Equipamentos ----------------

  Future<List<Equipment>> equipments({bool archived = false}) async {
    final rows = await db.query('equipment',
        where: 'archived = ?', whereArgs: [archived ? 1 : 0], orderBy: 'manufacturer, model, created_at');
    return rows.map(Equipment.fromMap).toList();
  }

  Future<Equipment?> equipment(String id) async {
    final rows = await db.query('equipment', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Equipment.fromMap(rows.single);
  }

  /// Insere ou atualiza o equipamento. Um equipamento novo recebe uma
  /// sessão com SET padrão (200 mA / 100 ms) para ser ajustada pelo técnico.
  Future<void> saveEquipment(Equipment e) async {
    await db.transaction((txn) async {
      final prev = await txn.query('equipment', where: 'id = ?', whereArgs: [e.id]);
      if (prev.isNotEmpty) {
        final map = e.toMap()
          ..remove('created_at')
          ..remove('archived')
          ..remove('photo_path');
        final changes = <String, Object?>{};
        for (final k in map.keys) {
          if (k == 'updated_at') continue;
          final before = prev.single[k];
          if ((before ?? '').toString() != (map[k] ?? '').toString()) {
            changes[k] = '${before ?? '—'} → ${map[k] ?? '—'}';
          }
        }
        await txn.update('equipment', map, where: 'id = ?', whereArgs: [e.id]);
        if (changes.isNotEmpty) await _audit(txn, 'alterado', 'equipamento', e.id, changes);
      } else {
        await txn.insert('equipment', e.toMap());
        await txn.insert('sessions', {
          'id': newId('ses'),
          'equipment_id': e.id,
          'set_ma': seedSetMa,
          'set_ms': seedSetMs,
          'set_pending': 1,
          'started_at': DateTime.now().toUtc().toIso8601String(),
        });
        await _audit(txn, 'criado', 'equipamento', e.id, {'equipamento': e.title});
      }
    });
  }

  /// Equipamentos nunca são apagados: são arquivados com todas as medições.
  Future<void> setArchived(String id, bool archived) async {
    await db.transaction((txn) async {
      await txn.update('equipment',
          {'archived': archived ? 1 : 0, 'updated_at': DateTime.now().toUtc().toIso8601String()},
          where: 'id = ?', whereArgs: [id]);
      await _audit(txn, archived ? 'arquivado' : 'restaurado', 'equipamento', id);
    });
  }

  // ---------------- Sessões / SET ----------------

  Future<MeasureSession?> currentSession(String equipmentId) async {
    final rows = await db.query('sessions',
        where: 'equipment_id = ?', whereArgs: [equipmentId], orderBy: 'started_at DESC, rowid DESC', limit: 1);
    return rows.isEmpty ? null : MeasureSession.fromMap(rows.single);
  }

  Future<MeasureSession?> session(String id) async {
    final rows = await db.query('sessions', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : MeasureSession.fromMap(rows.single);
  }

  Future<int> readingCount(String sessionId) async =>
      Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM readings WHERE session_id = ?', [sessionId])) ??
      0;

  /// Altera o SET do equipamento. Se a sessão atual já tem medições, o SET
  /// dela fica TRAVADO e uma nova sessão é aberta com o novo SET — assim cada
  /// sessão tem um único SET de referência. Fica pendente de envio até o
  /// instrumento confirmar.
  Future<SetChange> changeSet(String equipmentId, double ma, double ms) async {
    late SetChange result;
    await db.transaction((txn) async {
      final rows = await txn.query('sessions',
          where: 'equipment_id = ?', whereArgs: [equipmentId], orderBy: 'started_at DESC, rowid DESC', limit: 1);
      final now = DateTime.now().toUtc().toIso8601String();
      final current = rows.isEmpty ? null : MeasureSession.fromMap(rows.single);
      final used = current == null
          ? 0
          : Sqflite.firstIntValue(await txn
                  .rawQuery('SELECT COUNT(*) FROM readings WHERE session_id = ?', [current.id])) ??
              0;
      if (current == null || used > 0) {
        final id = newId('ses');
        await txn.insert('sessions', {
          'id': id,
          'equipment_id': equipmentId,
          'set_ma': ma,
          'set_ms': ms,
          'set_pending': 1,
          'started_at': now,
          'set_origin': 'app',
          'set_changed_at': now,
        });
        await _audit(txn, 'nova sessao', 'sessao', id, {
          'motivo': 'SET alterado após medições',
          'sessao_anterior': current?.id,
          'set': '${fmt(ma)} mA / ${fmt(ms)} ms',
        });
        result = SetChange(id, true);
      } else {
        await txn.update(
            'sessions',
            {
              'set_ma': ma,
              'set_ms': ms,
              'set_pending': 1,
              'set_confirmed_at': null,
              'set_origin': 'app',
              'set_changed_at': now,
            },
            where: 'id = ?',
            whereArgs: [current.id]);
        await _audit(txn, 'SET alterado', 'sessao', current.id, {
          'antes': '${fmt(current.setMa)} mA / ${fmt(current.setMs)} ms',
          'depois': '${fmt(ma)} mA / ${fmt(ms)} ms',
        });
        result = SetChange(current.id, false);
      }
    });
    return result;
  }

  Future<void> markSetConfirmed(String sessionId, String deviceId) async {
    await db.transaction((txn) async {
      await txn.update(
          'sessions',
          {
            'set_pending': 0,
            'set_confirmed_at': DateTime.now().toUtc().toIso8601String(),
            'device_id': deviceId,
          },
          where: 'id = ?',
          whereArgs: [sessionId]);
      await _audit(txn, 'SET confirmado', 'sessao', sessionId, {'instrumento': deviceId});
    });
  }

  /// Abre uma nova sessão copiando o SET da anterior.
  Future<String> newSession(String equipmentId, {String? label}) async {
    final prev = await currentSession(equipmentId);
    final id = newId('ses');
    await db.transaction((txn) async {
      await txn.insert('sessions', {
        'id': id,
        'equipment_id': equipmentId,
        'set_ma': prev?.setMa ?? seedSetMa,
        'set_ms': prev?.setMs ?? seedSetMs,
        'set_pending': 1,
        'started_at': DateTime.now().toUtc().toIso8601String(),
        'label': (label == null || label.trim().isEmpty) ? null : label.trim(),
      });
      await _audit(txn, 'nova sessao', 'sessao', id,
          {'motivo': 'iniciada pelo técnico', if (label != null && label.trim().isNotEmpty) 'identificacao': label.trim()});
    });
    return id;
  }

  Future<void> setPhoto(String equipmentId, String? path) async {
    await db.transaction((txn) async {
      await txn.update('equipment', {'photo_path': path}, where: 'id = ?', whereArgs: [equipmentId]);
      await _audit(txn, 'foto alterada', 'equipamento', equipmentId);
    });
  }

  // ---------------- Perfis de gerador ----------------

  Future<List<GeneratorProfile>> profiles() async {
    final rows = await db.query('generator_profiles', orderBy: 'builtin DESC, name');
    return rows.map(GeneratorProfile.fromMap).toList();
  }

  Future<GeneratorProfile?> profile(String id) async {
    final rows = await db.query('generator_profiles', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : GeneratorProfile.fromMap(rows.single);
  }

  /// Perfil do equipamento: o escolhido no cadastro ou o genérico do tipo.
  static Future<GeneratorProfile?> _profileForEquipment(DatabaseExecutor d, String equipmentId) async {
    final eq = await d.query('equipment',
        columns: ['profile_id', 'generator_type'], where: 'id = ?', whereArgs: [equipmentId]);
    if (eq.isEmpty) return null;
    final pid = eq.single['profile_id']?.toString();
    final type = GeneratorTypeInfo.fromCode(eq.single['generator_type']?.toString());
    for (final id in [if (pid != null && pid.isNotEmpty) pid, BuiltinProfiles.genericId(type)]) {
      final rows = await d.query('generator_profiles', where: 'id = ?', whereArgs: [id]);
      if (rows.isNotEmpty) return GeneratorProfile.fromMap(rows.single);
    }
    return null;
  }

  Future<GeneratorProfile?> profileForEquipment(String equipmentId) => _profileForEquipment(db, equipmentId);

  Future<void> saveProfile(GeneratorProfile p) async {
    await db.transaction((txn) async {
      final now = DateTime.now().toUtc().toIso8601String();
      final prev = await txn.query('generator_profiles', where: 'id = ?', whereArgs: [p.id]);
      if (prev.isEmpty) {
        await txn.insert('generator_profiles', {...p.toMap(), 'created_at': now, 'updated_at': now});
        await _audit(txn, 'criado', 'perfil', p.id, {'perfil': p.name, 'criterio': p.tolerances.description});
      } else {
        await txn.update('generator_profiles', {...p.toMap(), 'updated_at': now}, where: 'id = ?', whereArgs: [p.id]);
        await _audit(txn, 'alterado', 'perfil', p.id, {
          'perfil': p.name,
          'criterio': p.tolerances.description,
          'origem': p.tolerances.originText,
        });
      }
    });
  }

  /// Exclui um perfil criado pelo usuário que não esteja em uso.
  Future<bool> deleteProfile(String id) async {
    final p = await profile(id);
    if (p == null || p.builtin) return false;
    final used = Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM equipment WHERE profile_id = ?', [id])) ??
        0;
    if (used > 0) return false;
    await db.transaction((txn) async {
      await txn.delete('generator_profiles', where: 'id = ?', whereArgs: [id]);
      await _audit(txn, 'excluido', 'perfil', id, {'perfil': p.name});
    });
    return true;
  }

  // ---------------- Sessões: metadados e SET do instrumento ----------------

  Future<List<MeasureSession>> sessions(String equipmentId) async {
    final rows = await db.query('sessions',
        where: 'equipment_id = ?', whereArgs: [equipmentId], orderBy: 'started_at DESC, rowid DESC');
    return rows.map(MeasureSession.fromMap).toList();
  }

  /// Tubo e kV usados no teste (kV é só metadado informado pelo técnico).
  Future<void> updateSessionMeta(String sessionId, {String? tubeModel, String? kvInfo}) async {
    String? clean(String? v) => (v == null || v.trim().isEmpty) ? null : v.trim();
    await db.transaction((txn) async {
      await txn.update('sessions', {'tube_model': clean(tubeModel), 'kv_info': clean(kvInfo)},
          where: 'id = ?', whereArgs: [sessionId]);
      await _audit(txn, 'metadados da sessao', 'sessao', sessionId,
          {'tubo': clean(tubeModel) ?? '—', 'kV (informado)': clean(kvInfo) ?? '—'});
    });
  }

  /// O técnico alterou o SET no display do instrumento (MODO LOCAL).
  /// Abre/atualiza a sessão com origem "instrumento". Devolve o id da sessão.
  Future<String> adoptInstrumentSet(String equipmentId, String deviceId, double ma, double ms,
      {String? deviceSessionId, DateTime? changedAt}) async {
    late String id;
    await db.transaction((txn) async {
      final when = (changedAt ?? DateTime.now()).toUtc().toIso8601String();
      final existing = deviceSessionId == null
          ? <Map<String, Object?>>[]
          : await txn.query('sessions', where: 'id = ?', whereArgs: [deviceSessionId]);
      if (existing.isNotEmpty) {
        id = deviceSessionId!;
        final used = Sqflite.firstIntValue(
                await txn.rawQuery('SELECT COUNT(*) FROM readings WHERE session_id = ?', [id])) ??
            0;
        if (used == 0) {
          await txn.update(
              'sessions',
              {'set_ma': ma, 'set_ms': ms, 'set_pending': 0, 'set_origin': 'instrumento', 'set_changed_at': when},
              where: 'id = ?',
              whereArgs: [id]);
        }
      } else {
        id = deviceSessionId ?? newId('ses');
        await txn.insert('sessions', {
          'id': id,
          'equipment_id': equipmentId,
          'set_ma': ma,
          'set_ms': ms,
          'set_pending': 0,
          'device_id': deviceId,
          'started_at': DateTime.now().toUtc().toIso8601String(),
          'label': 'SET alterado no instrumento',
          'set_origin': 'instrumento',
          'set_changed_at': when,
        });
      }
      await _audit(txn, 'SET do instrumento', 'sessao', id,
          {'instrumento': deviceId, 'set': '${fmt(ma)} mA / ${fmt(ms)} ms', 'origem': 'display do instrumento'});
    });
    return id;
  }

  Future<void> upsertInstrument(Map<String, Object?> info) async {
    await db.insert('instruments', {...info, 'last_seen': DateTime.now().toUtc().toIso8601String()},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, Object?>>> instruments() => db.query('instruments', orderBy: 'last_seen DESC');

  // ---------------- Observações ----------------

  Future<void> addNote(String sessionId, String text, {String? readingUid}) async {
    final t = text.trim();
    if (t.isEmpty) return;
    await db.transaction((txn) async {
      final id = await txn.insert('notes', {
        'session_id': sessionId,
        'reading_uid': readingUid,
        'text': t,
        'at': DateTime.now().toUtc().toIso8601String(),
      });
      await _audit(txn, 'observacao', 'sessao', sessionId, {'nota': id, if (readingUid != null) 'medicao': readingUid});
    });
  }

  Future<List<Note>> notes({String? sessionId, String? equipmentId}) async {
    final rows = await db.rawQuery(
        'SELECT n.* FROM notes n JOIN sessions s ON s.id = n.session_id '
        'WHERE (? IS NULL OR n.session_id = ?) AND (? IS NULL OR s.equipment_id = ?) ORDER BY n.id DESC',
        [sessionId, sessionId, equipmentId, equipmentId]);
    return rows.map(Note.fromMap).toList();
  }

  // ---------------- Leituras ----------------

  Future<List<Reading>> readings({String? equipmentId, String? sessionId}) async {
    final where = <String>[];
    final args = <Object?>[];
    if (equipmentId != null) {
      where.add('equipment_id = ?');
      args.add(equipmentId);
    }
    if (sessionId != null) {
      where.add('session_id = ?');
      args.add(sessionId);
    }
    final rows = await db.query('readings',
        where: where.isEmpty ? null : where.join(' AND '),
        whereArgs: args.isEmpty ? null : args,
        orderBy: 'received_at DESC, rowid DESC');
    return rows.map(Reading.fromMap).toList();
  }

  Future<int> cursor(String deviceId) async {
    final rows = await db.query('sync_state', where: 'device_id = ?', whereArgs: [deviceId]);
    return rows.isEmpty ? 0 : rows.single['last_cursor'] as int;
  }

  static Map<String, Object?> _tolColumns(Tolerances t) => {
        'tol_ma': t.maPct,
        'tol_ms': t.msPct,
        'tol_mas': t.masPct,
        'tol_mas_abs': t.masAbs,
        'alert_fraction': t.alertFraction,
        'tol_origin': t.originText.isEmpty ? null : t.originText,
      };

  /// Grava as leituras recebidas do instrumento numa única transação.
  /// Leituras repetidas (mesmo device_id + shot_id) são ignoradas, então
  /// reconexões e re-sincronizações nunca duplicam medições.
  ///
  /// A tolerância vigente é gravada junto com cada medição: mudar a
  /// tolerância depois não altera o resultado de medições anteriores.
  ///
  /// Itens marcados com "simulated": true (ou vindos de um instrumento que se
  /// identifica como simulador) são gravados como source='simulator' e
  /// aparecem sempre como SIMULADOR, nunca como medição real.
  Future<MergeResult> mergeDeviceReadings(
      String deviceId, int nextCursor, List<dynamic> items, Tolerances fallbackTol,
      {bool deviceSimulated = false, String? fallbackEquipmentId}) async {
    var inserted = 0, duplicates = 0, rejected = 0;
    await db.transaction((txn) async {
      for (final raw in items) {
        if (raw is! Map) {
          rejected++;
          continue;
        }
        final r = Map<String, dynamic>.from(raw);
        final shotId = r['shot_id']?.toString();
        final sessionId = r['session_id']?.toString();
        final q = r['quality']?.toString();
        // 'out_of_range' e 'saturated' são REGISTRADOS (como inválidos);
        // qualquer outra qualidade desconhecida é rejeitada.
        if (shotId == null || shotId.isEmpty || sessionId == null || !const {'valid', 'out_of_range', 'saturated'}.contains(q)) {
          rejected++;
          continue;
        }
        double? val(String k) {
          final v = r[k];
          if (v is! num) return null;
          final d = v.toDouble();
          return d.isFinite && d >= 0 ? d : null;
        }

        var ses = await txn.query('sessions', where: 'id = ?', whereArgs: [sessionId]);
        if (ses.isEmpty) {
          // MODO LOCAL: o técnico configurou o SET no display do instrumento.
          // A sessão do instrumento é criada no equipamento selecionado.
          final sm = val('set_ma'), ss = val('set_ms');
          if (fallbackEquipmentId == null || sm == null || ss == null || sm <= 0 || ss <= 0) {
            rejected++;
            continue;
          }
          await txn.insert('sessions', {
            'id': sessionId,
            'equipment_id': fallbackEquipmentId,
            'set_ma': sm,
            'set_ms': ss,
            'set_pending': 0,
            'device_id': deviceId,
            'started_at': DateTime.tryParse(r['recorded_at']?.toString() ?? '')?.toUtc().toIso8601String() ??
                DateTime.now().toUtc().toIso8601String(),
            'label': 'Modo local do instrumento $deviceId',
            'set_origin': 'instrumento',
            'set_changed_at': DateTime.now().toUtc().toIso8601String(),
          });
          await _audit(txn, 'sessao do modo local', 'sessao', sessionId,
              {'instrumento': deviceId, 'set': '${fmt(sm)} mA / ${fmt(ss)} ms'});
          ses = await txn.query('sessions', where: 'id = ?', whereArgs: [sessionId]);
        }

        final setMa = val('set_ma') ?? (ses.single['set_ma'] as num).toDouble();
        final setMs = val('set_ms') ?? (ses.single['set_ms'] as num).toDouble();
        final readMa = val('read_ma');
        final readMs = val('read_ms');
        final readMas = val('read_mas');
        if (readMa == null || readMs == null || readMas == null) {
          rejected++;
          continue;
        }
        final existing = await txn.query('readings',
            columns: ['uid'], where: 'device_id = ? AND shot_id = ?', whereArgs: [deviceId, shotId]);
        if (existing.isNotEmpty) {
          duplicates++;
          continue;
        }
        final equipmentId = ses.single['equipment_id'].toString();
        final profile = await _profileForEquipment(txn, equipmentId);
        final applied = profile?.tolerances ?? fallbackTol;
        final wf = Waveform.tryParse(r['waveform']);
        final quality = <String>[
          if (r['flags'] is List) ...(r['flags'] as List).map((e) => e.toString()),
          if (q == 'saturated') 'saturated',
        ];
        // Fora da faixa do instrumento: registrado SEM truncar, como inválido.
        if (q == 'out_of_range' || InstrumentRange.check(readMa, readMs, readMas) != null) {
          quality.add('fora_da_faixa');
        }
        // Conferência independente: o app integra a forma de onda recebida
        // (trapézios) e sinaliza divergência maior que 2 % no mAs.
        if (wf != null) {
          final ex = detectExposure(uniformTimes(wf.ma.length, wf.samplePeriodUs), wf.ma);
          if (ex.valid && readMas > 0 && ((ex.mas - readMas).abs() / readMas) > 0.02) {
            quality.add('verificacao_mas_divergente');
          }
        }
        var ev = evaluate(
            setMa: setMa, setMs: setMs, readMa: readMa, readMs: readMs, readMas: readMas, tol: applied);
        if (quality.any(Reading.invalidFlags.contains)) {
          ev = Evaluation(ev.errMa, ev.errMs, ev.errMas, MeasureStatus.invalid);
        }
        await txn.insert('readings', {
          'uid': newId('rd'),
          'device_id': deviceId,
          'shot_id': shotId,
          'session_id': sessionId,
          'equipment_id': equipmentId,
          'source': (deviceSimulated || r['simulated'] == true) ? 'simulator' : 'device',
          'set_ma': setMa,
          'set_ms': setMs,
          'read_ma': readMa,
          'read_ms': readMs,
          'read_mas': readMas,
          'err_ma': ev.errMa,
          'err_ms': ev.errMs,
          'err_mas': ev.errMas,
          'status': ev.status.code,
          'waveform': wf?.toJson(),
          'recorded_at': DateTime.tryParse(r['recorded_at']?.toString() ?? '')?.toUtc().toIso8601String(),
          'received_at': DateTime.now().toUtc().toIso8601String(),
          ..._tolColumns(applied),
          'profile_id': profile?.id,
          'ma_peak': val('ma_peak'),
          'quality': quality.isEmpty ? null : jsonEncode(quality),
          'probe_id': r['probe_id']?.toString(),
          'cal_status': r['cal_status']?.toString(),
        });
        inserted++;
      }
      final prev = await txn.query('sync_state', where: 'device_id = ?', whereArgs: [deviceId]);
      final oldCursor = prev.isEmpty ? 0 : prev.single['last_cursor'] as int;
      await txn.insert('sync_state',
          {'device_id': deviceId, 'last_cursor': nextCursor > oldCursor ? nextCursor : oldCursor},
          conflictAlgorithm: ConflictAlgorithm.replace);
      if (inserted > 0) {
        await _audit(txn, 'medicoes recebidas', 'instrumento', deviceId, {
          'novas': inserted,
          if (duplicates > 0) 'repetidas_ignoradas': duplicates,
          if (rejected > 0) 'rejeitadas': rejected,
          'cursor': nextCursor,
        });
      }
    });
    return MergeResult(inserted, duplicates, rejected);
  }

  /// MODO DEMONSTRAÇÃO: grava um disparo simulado, sempre marcado como
  /// source='demo' e device_id='DEMO'. Nunca se mistura às medições reais.
  Future<Reading> insertDemoReading({
    required MeasureSession session,
    required double readMa,
    required double readMs,
    required double readMas,
    required Waveform waveform,
    required Tolerances tol,
    double? maPeak,
    List<String> quality = const [],
    String? profileId,
  }) async {
    final ev = evaluate(
        setMa: session.setMa,
        setMs: session.setMs,
        readMa: readMa,
        readMs: readMs,
        readMas: readMas,
        tol: tol);
    final now = DateTime.now().toUtc().toIso8601String();
    final uid = newId('demo');
    final map = <String, Object?>{
      'uid': uid,
      'device_id': 'DEMO',
      'shot_id': uid,
      'session_id': session.id,
      'equipment_id': session.equipmentId,
      'source': 'demo',
      'set_ma': session.setMa,
      'set_ms': session.setMs,
      'read_ma': readMa,
      'read_ms': readMs,
      'read_mas': readMas,
      'err_ma': ev.errMa,
      'err_ms': ev.errMs,
      'err_mas': ev.errMas,
      'status': ev.status.code,
      'waveform': waveform.toJson(),
      'recorded_at': now,
      'received_at': now,
      ..._tolColumns(tol),
      'ma_peak': maPeak,
      'quality': quality.isEmpty ? null : jsonEncode(quality),
      'probe_id': 'DEMO',
      'cal_status': 'simulado',
      'profile_id': profileId,
    };
    await db.insert('readings', map);
    return Reading.fromMap(map);
  }

  /// Apaga SOMENTE registros simulados (modo demonstração e simulador).
  /// Medições reais são protegidas por gatilho no banco.
  Future<int> deleteDemoReadings() async {
    late int n;
    await db.transaction((txn) async {
      n = await txn.delete('readings', where: "source <> 'device'");
      if (n > 0) await _audit(txn, 'simulacoes apagadas', 'medicoes', null, {'quantidade': n});
    });
    return n;
  }

  // ---------------- Backup ----------------

  /// Exporta todos os dados para um mapa JSON. O token de pareamento não é
  /// incluído por segurança.
  Future<Map<String, Object?>> exportBackup({required String appVersion}) async {
    final data = <String, Object?>{};
    for (final t in tables) {
      var rows = await db.query(t);
      if (t == 'settings') rows = rows.where((r) => r['key'] != 'token').toList();
      data[t] = rows;
    }
    final counts = {for (final t in tables) t: (data[t] as List).length};
    await audit('backup exportado', 'banco', null, {'registros': counts});
    return {
      'format': backupFormat,
      'schema': schemaVersion,
      'app_version': appVersion,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'tables': data,
    };
  }

  /// Substitui TODOS os dados pelo conteúdo do backup, numa única transação.
  /// Se qualquer linha for inválida, nada é alterado.
  Future<Map<String, int>> importBackup(Map<String, Object?> backup) async {
    if (backup['format'] != backupFormat) {
      throw const BackupException('Arquivo não é um backup do X-METER CONNECT');
    }
    final schema = backup['schema'];
    if (schema is! int || schema > schemaVersion) {
      throw const BackupException('Backup de versão mais nova do aplicativo. Atualize o app.');
    }
    if (schema < 3) throw const BackupException('Versão de backup não suportada');
    // Backups da versão 3 não têm as colunas novas: ficam vazias.
    final tablesData = backup['tables'];
    if (tablesData is! Map) throw const BackupException('Backup sem dados');
    final counts = <String, int>{};
    final keepToken = await db.query('settings', where: "key = 'token'");
    await db.transaction((txn) async {
      await _dropProtection(txn);
      for (final t in tables.reversed) {
        await txn.delete(t);
      }
      for (final t in tables) {
        final cols = (await txn.rawQuery('PRAGMA table_info($t)')).map((c) => c['name'].toString()).toSet();
        final rows = tablesData[t];
        if (rows == null) continue;
        if (rows is! List) throw BackupException('Tabela $t inválida no backup');
        for (final row in rows) {
          if (row is! Map) throw BackupException('Registro inválido em $t');
          final clean = <String, Object?>{
            for (final e in row.entries)
              if (cols.contains(e.key.toString())) e.key.toString(): e.value,
          };
          await txn.insert(t, clean);
        }
        counts[t] = rows.length;
      }
      for (final r in keepToken) {
        await txn.insert('settings', r, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      // Backups anteriores à V5 não têm perfis: recria os do aplicativo.
      final st = AppSettings.fromMap({
        for (final r in await txn.query('settings')) r['key'].toString(): r['value'].toString(),
      });
      final now = DateTime.now().toUtc().toIso8601String();
      for (final p in [
        for (final t in GeneratorType.values) BuiltinProfiles.generic(t, st.tolFor(t)),
        BuiltinProfiles.sawaeAltus,
      ]) {
        await txn.insert('generator_profiles', {...p.toMap(), 'created_at': now, 'updated_at': now},
            conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      await _createProtection(txn);
      await _audit(txn, 'backup restaurado', 'banco', null, {
        'criado_em': backup['created_at'],
        'versao_app': backup['app_version'],
        'registros': counts,
      });
    });
    return counts;
  }
}

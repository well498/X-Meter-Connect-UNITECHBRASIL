import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Erro de comunicação com o instrumento (rede, HTTP ou protocolo).
class MeterException implements Exception {
  final String message;
  const MeterException(this.message);
  @override
  String toString() => message;
}

/// Identificação devolvida por GET /v1/device.
class DeviceInfo {
  final String deviceId;
  final int protocolVersion;
  final String? firmware;

  /// true quando o equipamento do outro lado é o simulador de bancada.
  final bool simulated;
  const DeviceInfo(this.deviceId, this.protocolVersion, this.firmware, {this.simulated = false});
}

/// Página de leituras devolvida por GET /v1/readings.
class ReadingsPage {
  final String deviceId;
  final int nextCursor;
  final List<dynamic> items;
  final bool more;
  const ReadingsPage(this.deviceId, this.nextCursor, this.items, this.more);
}

/// Transporte Wi-Fi (Access Point do ESP32-S3) do PROTOCOLO PROPOSTO v1.
/// Ver docs/PROTOCOLO_PROPOSTO.md. Nenhum endpoint existe no hardware
/// ainda: use tools/xmeter_simulador.py para testes de bancada.
class MeterApi {
  static const protocolVersion = 1;
  final String host;
  final int port;
  final String token;
  final Duration timeout;

  MeterApi(this.host, this.port, this.token, {this.timeout = const Duration(seconds: 5)});

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri(scheme: 'http', host: host, port: port, path: path, queryParameters: query);

  Future<Map<String, dynamic>> _request(String method, Uri url, [Object? payload]) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final req = await client.openUrl(method, url).timeout(timeout);
      if (token.isNotEmpty) {
        req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      }
      req.headers.contentType = ContentType.json;
      if (payload != null) req.write(jsonEncode(payload));
      final response = await req.close().timeout(timeout);
      final body = await utf8.decoder.bind(response).join().timeout(timeout);
      if (response.statusCode == 401 || response.statusCode == 403) {
        throw const MeterException('Token de pareamento recusado pelo instrumento');
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw MeterException('Instrumento respondeu HTTP ${response.statusCode}');
      }
      final json = _decode(body);
      if (json is! Map) throw const MeterException('Resposta do instrumento em formato inesperado');
      return Map<String, dynamic>.from(json);
    } on MeterException {
      rethrow;
    } on TimeoutException {
      throw const MeterException('Tempo esgotado: instrumento não respondeu');
    } on SocketException catch (e) {
      throw MeterException('Sem comunicação com $host:$port (${e.osError?.message ?? e.message})');
    } on HttpException catch (e) {
      throw MeterException('Falha HTTP: ${e.message}');
    } finally {
      client.close(force: true);
    }
  }

  static Object? _decode(String body) {
    try {
      return jsonDecode(body);
    } on FormatException {
      throw const MeterException('Resposta do instrumento não é JSON válido');
    }
  }

  Future<DeviceInfo> identity() async {
    final j = await _request('GET', _uri('/v1/device'));
    final id = j['device_id'];
    final v = j['protocol_version'];
    if (id is! String || id.isEmpty) throw const MeterException('Identificação do instrumento ausente');
    if (v != protocolVersion) {
      throw MeterException('Protocolo incompatível (instrumento v$v, aplicativo v$protocolVersion)');
    }
    return DeviceInfo(id, v as int, j['firmware']?.toString(), simulated: j['simulated'] == true);
  }

  /// Envia apenas os parâmetros SET de referência para o medidor.
  /// O X-METER NÃO comanda o gerador nem dispara exposições.
  Future<void> sendSet(String sessionId, double ma, double ms) async {
    final j = await _request('PUT', _uri('/v1/session/set'), {
      'session_id': sessionId,
      'set_ma': ma,
      'set_ms': ms,
      'set_mas': ma * ms / 1000.0,
    });
    if (j['accepted'] != true || j['session_id'] != sessionId) {
      throw const MeterException('SET não confirmado pelo instrumento');
    }
  }

  /// Arma a aquisição para registrar a próxima exposição (protocolo v1.1).
  /// O instrumento apenas MEDE; quem dispara é o operador no comando.
  Future<void> arm(String sessionId) async {
    final j = await _request('POST', _uri('/v1/acquisition/arm'), {'session_id': sessionId});
    if (j['armed'] != true) throw const MeterException('Instrumento não confirmou o início da medição');
  }

  Future<ReadingsPage> readings(int after, {int limit = 100}) async {
    final j = await _request(
        'GET', _uri('/v1/readings', {'after': after.toString(), 'limit': limit.toString()}));
    final id = j['device_id'];
    final next = j['next_cursor'];
    final items = j['items'];
    if (id is! String || next is! int || items is! List) {
      throw const MeterException('Resposta de sincronização inválida');
    }
    if (next < after) throw const MeterException('Cursor do instrumento retrocedeu');
    return ReadingsPage(id, next, items, j['more'] == true);
  }
}

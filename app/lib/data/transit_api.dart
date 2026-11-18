import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'models.dart';

class ApiException implements Exception {
  const ApiException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Cliente del backend de Smart Transport.
class TransitApi {
  TransitApi({required String baseUrl, http.Client? client})
      : _baseUrl = baseUrl.replaceFirst(RegExp(r'/+$'), ''),
        _client = client ?? http.Client();

  final String _baseUrl;
  final http.Client _client;

  final _demoPaths = <String>{};

  /// Capas que el backend está sirviendo con datos simulados (p. ej. colectivos y subte sin
  /// credenciales del GCBA, mientras Ecobici es real). Vacío = todo es real.
  List<String> get demoLayers => [
        if (_demoPaths.any((p) => p.startsWith('/v1/buses'))) 'colectivos',
        if (_demoPaths.any((p) => p.startsWith('/v1/subway'))) 'subte',
        if (_demoPaths.contains('/v1/ecobici/stations')) 'Ecobici',
      ];

  /// Los colectivos en vivo de esas Líneas de Colectivo (todos sus Ramales), en toda la ciudad
  /// y en un solo pedido.
  Future<BusesResult> buses({required List<String> lines}) async =>
      BusesResult.fromJson(await _get('/v1/buses', {'line': lines.join(',')}));

  /// El catálogo de Líneas de Colectivo, con sus Ramales y Terminales pero sin los Recorridos.
  Future<List<BusLine>> busLines() async {
    final j = await _get('/v1/buses/lines');
    return [for (final l in j['lines'] as List) BusLine.fromJson(l as Map<String, dynamic>)];
  }

  /// Una Línea de Colectivo con los Recorridos de todos sus Ramales.
  Future<BusLine> busPaths(String line) async {
    final j = await _get('/v1/buses/paths', {'line': line});
    return BusLine.fromJson(j['line'] as Map<String, dynamic>);
  }

  Future<List<SubwayLine>> subwayLines() async {
    final j = await _get('/v1/subway/lines');
    return [for (final l in j['lines'] as List) SubwayLine.fromJson(l as Map<String, dynamic>)];
  }

  Future<List<SubwayArrival>> subwayArrivals(String stationId) async {
    final j = await _get('/v1/subway/arrivals', {'station': stationId});
    return [for (final a in j['arrivals'] as List) SubwayArrival.fromJson(a as Map<String, dynamic>)];
  }

  Future<List<ServiceAlert>> subwayAlerts() async {
    final j = await _get('/v1/subway/alerts');
    return [for (final a in j['alerts'] as List) ServiceAlert.fromJson(a as Map<String, dynamic>)];
  }

  Future<List<BikeStation>> bikeStations() async {
    final j = await _get('/v1/ecobici/stations');
    return [for (final s in j['stations'] as List) BikeStation.fromJson(s as Map<String, dynamic>)];
  }

  Future<Map<String, dynamic>> _get(String path, [Map<String, String>? query]) async {
    final uri = Uri.parse('$_baseUrl$path').replace(queryParameters: query);
    final http.Response res;
    try {
      res = await _client.get(uri).timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw const ApiException('El servidor tardó demasiado en responder');
    } on Exception {
      throw const ApiException('No se pudo conectar con el servidor');
    }

    final Object? body;
    try {
      body = jsonDecode(utf8.decode(res.bodyBytes));
    } on FormatException {
      throw ApiException('Respuesta inválida del servidor (${res.statusCode})');
    }
    if (body is! Map<String, dynamic>) throw const ApiException('Respuesta inválida del servidor');
    if (res.statusCode != 200) {
      throw ApiException(body['error'] as String? ?? 'Error ${res.statusCode}');
    }
    body['mode'] == 'demo' ? _demoPaths.add(path) : _demoPaths.remove(path);
    return body;
  }

  void close() => _client.close();
}

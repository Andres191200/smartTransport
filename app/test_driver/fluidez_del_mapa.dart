// Lado de la PC de la medición de fluidez (integration_test/fluidez_del_mapa_test.dart): recibe
// los cuadros del teléfono, guarda los resultados crudos en mediciones/ e imprime el resumen.
// Se corre con `tool/fluidez.sh`.

import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver(
      responseDataCallback: (data) async {
        final ahora = DateTime.now();
        final archivo = 'fluidez-${ahora.toIso8601String().substring(0, 19).replaceAll(':', '-')}';
        await writeResponseData(data, testOutputFilename: archivo, destinationDirectory: 'mediciones');
        stdout
          ..writeln()
          ..writeln(resumenDeCuadros(data!['mapa'] as Map<String, dynamic>))
          ..writeln('Resultados crudos: mediciones/$archivo.json');
      },
    );

/// Una tabla con el promedio, p90, p99 y peor tiempo de cuadro, y los cuadros fuera de
/// presupuesto, de build y de raster por separado. [cuadros] es el resumen que arma
/// `watchPerformance` (`FrameTimingSummarizer.summary`).
String resumenDeCuadros(Map<String, dynamic> cuadros) {
  String ms(String clave) => '${(cuadros[clave] as num).toStringAsFixed(1)} ms'.padLeft(10);
  String fila(String nombre, String clave, String fuera) => [
        nombre.padRight(8),
        ms('average_frame_${clave}_time_millis'),
        ms('90th_percentile_frame_${clave}_time_millis'),
        ms('99th_percentile_frame_${clave}_time_millis'),
        ms('worst_frame_${clave}_time_millis'),
        '${cuadros[fuera]}'.padLeft(18),
      ].join();
  return [
    'Fluidez del mapa: ${cuadros['frame_count']} cuadros',
    '${''.padRight(8)}${'promedio'.padLeft(10)}${'p90'.padLeft(10)}${'p99'.padLeft(10)}${'peor'.padLeft(10)}'
        '${'cuadros > 16 ms'.padLeft(18)}',
    fila('build', 'build', 'missed_frame_build_budget_count'),
    fila('raster', 'rasterizer', 'missed_frame_rasterizer_budget_count'),
  ].join('\n');
}

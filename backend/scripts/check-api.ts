// Verifica las fuentes de datos reales y que los adaptadores entienden sus respuestas.
// Uso: npm run check-api
//   - Ecobici (feed GBFS público): siempre.
//   - Colectivos y subte (API Transporte del GCBA): solo si hay credenciales en el .env.

import { parseBusPositions } from '../src/adapters/buses.ts';
import { readGtfsZip } from '../src/adapters/gtfs.ts';
import { buildSubwayLines, parseServiceAlerts, parseSubwayForecast } from '../src/adapters/subway.ts';
import { loadConfig } from '../src/config.ts';
import { GbfsClient } from '../src/gbfs.ts';
import { EcobiciSource } from '../src/sources.ts';
import { TransporteClient } from '../src/upstream.ts';

const config = loadConfig();

/** Muestra un pedacito de la respuesta cruda: si un parser da 0, esto dice cómo viene el JSON. */
const preview = (raw: unknown) => JSON.stringify(Array.isArray(raw) ? raw.slice(0, 1) : raw).slice(0, 600);

let failures = 0;
async function check(name: string, run: () => Promise<{ count: number; raw?: unknown }>) {
  try {
    const { count, raw } = await run();
    const ok = count > 0;
    if (!ok) failures++;
    console.log(`${ok ? '✔' : '✘'} ${name}: ${count} elementos`);
    if (!ok && raw !== undefined) console.log(`    respuesta cruda: ${preview(raw)}`);
  } catch (error) {
    failures++;
    console.log(`✘ ${name}: ${(error as Error).message}`);
  }
}

// ------------------------------------------------------------------ Ecobici (GBFS público)

await check(`Ecobici (${config.ecobici.discoveryUrl})`, async () => {
  const stations = await new EcobiciSource(new GbfsClient({ discoveryUrl: config.ecobici.discoveryUrl })).bikeStations();
  const sum = (f: (s: (typeof stations)[number]) => number) => stations.reduce((n, s) => n + f(s), 0);
  console.log(
    `    ${sum((s) => s.bikes)} bicis (${sum((s) => s.ebikes)} eléctricas), ` +
      `${stations.filter((s) => !s.operational).length} estaciones sin préstamo, ` +
      `${stations.filter((s) => !s.acceptsReturns).length} sin devoluciones`,
  );
  return { count: stations.length };
});

// ------------------------------------------------------------------ API Transporte (GCBA)

if (!config.credentials) {
  console.log('– Colectivos y subte: sin TRANSPORTE_CLIENT_ID / TRANSPORTE_CLIENT_SECRET en el .env, se omiten.');
} else {
  const api = new TransporteClient({ baseUrl: config.upstreamBaseUrl, ...config.credentials });

  await check('Colectivos (vehiclePositionsSimple)', async () => {
    const raw = await api.json('/colectivos/vehiclePositionsSimple');
    return { count: parseBusPositions(raw).length, raw };
  });

  await check('Subte: líneas (feed-gtfs)', async () => {
    const zip = await api.bytes('/subtes/feed-gtfs');
    const files = readGtfsZip(zip, ['routes.txt', 'stops.txt', 'trips.txt', 'stop_times.txt', 'shapes.txt']);
    const lines = buildSubwayLines(files);
    for (const l of lines) console.log(`    Línea ${l.name}: ${l.stations.length} estaciones, recorrido de ${l.path.length} puntos`);
    return { count: lines.length, raw: Object.keys(files) };
  });

  await check('Subte: próximos trenes (forecastGTFS)', async () => {
    const raw = await api.json('/subtes/forecastGTFS', { json: '1' });
    return { count: parseSubwayForecast(raw).arrivals.length, raw };
  });

  // Que no haya alertas es normal, así que se informa sin contarlo como falla.
  try {
    const alerts = parseServiceAlerts(await api.json('/subtes/serviceAlerts', { json: '1' }));
    console.log(`✔ Subte: alertas: ${alerts.length}${alerts.length ? ` (p. ej. "${alerts[0]!.title}")` : ''}`);
  } catch (error) {
    failures++;
    console.log(`✘ Subte: alertas: ${(error as Error).message}`);
  }
}

console.log(failures ? `\n${failures} verificación(es) fallaron.` : '\nTodo OK.');
process.exit(failures ? 1 : 0);

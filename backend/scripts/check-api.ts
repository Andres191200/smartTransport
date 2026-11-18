// Verifica las fuentes de datos reales y que los adaptadores entienden sus respuestas.
// Uso: npm run check-api
//   - Ecobici (feed GBFS público): siempre.
//   - Colectivos y subte (API Transporte del GCBA): solo si hay credenciales en el .env.

import { unzipSync } from 'fflate';
import { BUS_GTFS_FILES, buildBusLines } from '../src/adapters/bus-lines.ts';
import { parseBusPositions, type Bus } from '../src/adapters/buses.ts';
import { readGtfsZip } from '../src/adapters/gtfs.ts';
import { buildSubwayLines, parseServiceAlerts, parseSubwayForecast } from '../src/adapters/subway.ts';
import { loadConfig } from '../src/config.ts';
import { GbfsClient } from '../src/gbfs.ts';
import { BUS_GTFS_PATH, BUS_GTFS_TIMEOUT_MS, EcobiciSource } from '../src/sources.ts';
import { TransporteClient } from '../src/upstream.ts';

const config = loadConfig();

/** Muestra un pedacito de la respuesta cruda: si un parser da 0, esto dice cómo viene el JSON. */
const preview = (raw: unknown) => JSON.stringify(Array.isArray(raw) ? raw.slice(0, 1) : raw).slice(0, 600);

const mb = (bytes: number) => `${(bytes / 1024 / 1024).toFixed(1)} MB`;
const since = (start: number) => `${((Date.now() - start) / 1000).toFixed(1)} s`;

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

  let liveBuses: Bus[] = [];
  await check('Colectivos (vehiclePositionsSimple)', async () => {
    const raw = await api.json('/colectivos/vehiclePositionsSimple');
    liveBuses = parseBusPositions(raw);
    return { count: liveBuses.length, raw };
  });

  // El catálogo de Líneas sale de acá. Se informa la ruta, el tamaño, los archivos y sus columnas
  // para confirmar lo que buildBusLines supone del feed (y si conviene separar los Recorridos).
  await check(`Colectivos: catálogo de Líneas (GTFS estático, ${BUS_GTFS_PATH})`, async () => {
    const start = Date.now();
    const zip = await api.bytes(BUS_GTFS_PATH, {}, { timeoutMs: BUS_GTFS_TIMEOUT_MS });
    console.log(`    zip de ${mb(zip.length)}, bajado en ${since(start)}`);

    const entries: string[] = [];
    unzipSync(zip, {
      filter: (file) => {
        entries.push(file.name);
        console.log(`    ${file.name}: ${mb(file.originalSize)} sin comprimir`);
        return false;
      },
    });
    const missing = BUS_GTFS_FILES.filter((name) => !entries.some((e) => e === name || e.endsWith(`/${name}`)));
    if (missing.length) console.log(`    faltan: ${missing.join(', ')}`);

    const files = readGtfsZip(zip, BUS_GTFS_FILES);
    for (const [name, text] of Object.entries(files)) {
      // Encabezado y primera fila: muestran los nombres de campos y cómo vienen los valores.
      const [header, first] = text.split(/\r?\n/, 2);
      console.log(`    ${name}: ${header}\n      p. ej. ${first}`);
    }

    const processing = Date.now();
    const lines = buildBusLines(files);
    const branches = lines.flatMap((l) => l.branches);
    console.log(
      `    procesado en ${since(processing)}, memoria del proceso: ${mb(process.memoryUsage().rss)}\n` +
        `    ${lines.length} Líneas, ${branches.length} Ramales, ` +
        `${branches.filter((b) => !b.terminals).length} sin Terminales, ` +
        `${branches.filter((b) => b.path.length < 2).length} sin Recorrido`,
    );
    const catalog = lines.map((l) => ({ id: l.id, branches: l.branches.map(({ path: _path, ...b }) => b) }));
    const heaviest = lines.reduce<{ id: string; size: number }>((max, l) => {
      const size = JSON.stringify(l).length;
      return size > max.size ? { id: l.id, size } : max;
    }, { id: '-', size: 0 });
    console.log(
      `    /v1/buses/lines pesa ${mb(JSON.stringify(catalog).length)}; ` +
        `la Línea con Recorridos más pesados (${heaviest.id}) pesa ${mb(heaviest.size)} en /v1/buses/paths`,
    );
    for (const line of lines.filter((l) => ['60', '152'].includes(l.id))) {
      const detail = line.branches.map((b) => `${b.id} (${b.terminals?.join(' – ') ?? 'sin Terminales'}, ${b.path.length} puntos)`);
      console.log(`    Línea ${line.id}: ${detail.join(', ')}`);
    }

    // Los colectivos en vivo tienen que poder ubicarse en el catálogo por su Ramal.
    if (liveBuses.length) {
      const known = new Set(branches.map((b) => b.id));
      const unknown = [...new Set(liveBuses.map((b) => b.line.toUpperCase()).filter((line) => !known.has(line)))];
      console.log(
        `    Ramales en vivo que no están en el catálogo: ${unknown.length}` +
          (unknown.length ? ` (p. ej. ${unknown.slice(0, 10).join(', ')})` : ''),
      );
    }
    return { count: missing.length ? 0 : lines.length, raw: entries };
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

import type { IncomingMessage, ServerResponse } from 'node:http';
import { filterBuses, type BoundingBox } from './adapters/buses.ts';
import { arrivalsForStation } from './adapters/subway.ts';
import type { BikeSource, SourceMode, TransitSource } from './sources.ts';
import { UpstreamError } from './upstream.ts';

class BadRequest extends Error {}
class NotFound extends Error {}

interface Route {
  /** De qué fuente salen los datos: cada respuesta informa si son reales o simulados. */
  source?: { mode: SourceMode };
  run: (query: URLSearchParams) => Promise<object>;
}

const MAX_BUSES = 600;

export function createHandler(sources: { transit: TransitSource; bikes: BikeSource }) {
  const { transit, bikes } = sources;
  const routes: Record<string, Route> = {
    '/health': { run: async () => ({ modes: { transit: transit.mode, bikes: bikes.mode } }) },

    '/v1/buses': {
      source: transit,
      run: async (q) => {
        const box = parseBox(q.get('bbox'));
        const lines = parseLines(q.getAll('line'));
        if (!box && !lines) {
          // Sin filtro serían miles de colectivos: obligamos a pedir una zona o alguna Línea.
          throw new BadRequest('Indicá bbox=minLat,minLon,maxLat,maxLon y/o line=<línea>[,<línea>...]');
        }
        const limit = clampInt(q.get('limit'), 1, MAX_BUSES, MAX_BUSES);
        return filterBuses(await transit.buses(), { ...(box && { box }), ...(lines && { lines }), limit });
      },
    },

    // Catálogo liviano para el buscador: los Recorridos se piden por Línea en /v1/buses/paths.
    '/v1/buses/lines': {
      source: transit,
      run: async () => ({
        lines: (await transit.busLines()).map((line) => ({
          id: line.id,
          branches: line.branches.map(({ path: _path, ...branch }) => branch),
        })),
      }),
    },

    '/v1/buses/paths': {
      source: transit,
      run: async (q) => {
        const id = q.get('line')?.trim().toUpperCase();
        if (!id) throw new BadRequest('Falta el parámetro line');
        const line = (await transit.busLines()).find((l) => l.id === id);
        if (!line) throw new NotFound(`No existe la Línea ${id}`);
        return { line };
      },
    },

    '/v1/subway/lines': { source: transit, run: async () => ({ lines: await transit.subwayLines() }) },

    '/v1/subway/arrivals': {
      source: transit,
      run: async (q) => {
        const station = q.get('station');
        if (!station) throw new BadRequest('Falta el parámetro station');
        const nowSec = Math.floor(Date.now() / 1000);
        return { station, arrivals: arrivalsForStation(await transit.subwayArrivals(), station, nowSec) };
      },
    },

    '/v1/subway/alerts': { source: transit, run: async () => ({ alerts: await transit.subwayAlerts() }) },

    '/v1/ecobici/stations': { source: bikes, run: async () => ({ stations: await bikes.bikeStations() }) },
  };

  return async function handle(req: IncomingMessage, res: ServerResponse): Promise<void> {
    const url = new URL(req.url ?? '/', 'http://localhost');
    res.setHeader('Access-Control-Allow-Origin', '*');

    if (req.method === 'OPTIONS') return send(res, 204);
    if (req.method !== 'GET') return send(res, 405, { error: 'Método no permitido' });

    const route = routes[url.pathname.replace(/\/+$/, '') || '/'];
    if (!route) return send(res, 404, { error: 'No encontrado' });

    try {
      const body = await route.run(url.searchParams);
      const mode = route.source ? { mode: route.source.mode } : { ok: true };
      send(res, 200, { ...mode, generatedAt: new Date().toISOString(), ...body });
    } catch (error) {
      if (error instanceof BadRequest) return send(res, 400, { error: error.message });
      if (error instanceof NotFound) return send(res, 404, { error: error.message });
      console.error(`[${url.pathname}]`, error instanceof Error ? error.message : error);
      const status = error instanceof UpstreamError ? 502 : 500;
      send(res, status, { error: status === 502 ? 'La API Transporte no respondió' : 'Error interno' });
    }
  };
}

function send(res: ServerResponse, status: number, body?: object) {
  res.statusCode = status;
  if (body === undefined) return void res.end();
  res.setHeader('Content-Type', 'application/json; charset=utf-8');
  res.setHeader('Cache-Control', 'no-store');
  res.end(JSON.stringify(body));
}

export function parseBox(value: string | null): BoundingBox | undefined {
  if (!value) return undefined;
  const parts = value.split(',').map(Number);
  if (parts.length !== 4 || parts.some((n) => !Number.isFinite(n))) {
    throw new BadRequest('bbox debe ser minLat,minLon,maxLat,maxLon');
  }
  const [minLat, minLon, maxLat, maxLon] = parts as [number, number, number, number];
  if (minLat > maxLat || minLon > maxLon) throw new BadRequest('bbox: el mínimo supera al máximo');
  return { minLat, minLon, maxLat, maxLon };
}

/** `line=60,152` o `line=60&line=152` → ["60", "152"]; sin Líneas, undefined. */
function parseLines(values: string[]): string[] | undefined {
  const lines = [...new Set(values.flatMap((v) => v.split(',')).map((l) => l.trim()).filter(Boolean))];
  return lines.length ? lines : undefined;
}

function clampInt(value: string | null, min: number, max: number, fallback: number): number {
  const n = Number.parseInt(value ?? '', 10);
  return Number.isFinite(n) ? Math.min(max, Math.max(min, n)) : fallback;
}

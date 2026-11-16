import type { IncomingMessage, ServerResponse } from 'node:http';
import { filterBuses, type BoundingBox } from './adapters/buses.ts';
import { arrivalsForStation } from './adapters/subway.ts';
import type { BikeSource, SourceMode, TransitSource } from './sources.ts';
import { UpstreamError } from './upstream.ts';

class BadRequest extends Error {}

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
        const line = q.get('line')?.trim() || undefined;
        if (!box && !line) {
          // Sin filtro serían miles de colectivos: obligamos a pedir una zona o una línea.
          throw new BadRequest('Indicá bbox=minLat,minLon,maxLat,maxLon y/o line=<línea>');
        }
        const limit = clampInt(q.get('limit'), 1, MAX_BUSES, MAX_BUSES);
        return filterBuses(await transit.buses(), { ...(box && { box }), ...(line && { line }), limit });
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

function clampInt(value: string | null, min: number, max: number, fallback: number): number {
  const n = Number.parseInt(value ?? '', 10);
  return Number.isFinite(n) ? Math.min(max, Math.max(min, n)) : fallback;
}

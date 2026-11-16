import { parseCsv, type CsvRow } from './gtfs.ts';
import { isObj, list, num, pick, str } from './read.ts';

export type LatLon = [lat: number, lon: number];

export interface SubwayStation {
  /** Clave estable línea + nombre; es la que se usa para pedir próximos trenes. */
  id: string;
  name: string;
  lat: number;
  lon: number;
}

export interface SubwayLine {
  id: string;
  name: string;
  /** Color en hex sin "#", p. ej. "18CCF5". */
  color: string;
  textColor: string;
  path: LatLon[];
  stations: SubwayStation[];
}

export interface SubwayArrival {
  stationId: string;
  lineId: string;
  tripId: string;
  directionId: number;
  /** Nombre de la estación terminal hacia la que va el tren. */
  destination: string;
  /** Llegada estimada, segundos POSIX. */
  arrivalTime: number;
  delaySeconds: number;
}

export interface ServiceAlert {
  id: string;
  title: string;
  description?: string;
  lineIds: string[];
  activeFrom?: number;
  activeUntil?: number;
}

export function normalizeName(name: string): string {
  return name
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-|-$/g, '');
}

export const stationKey = (lineId: string, stationName: string) => `${lineId}:${normalizeName(stationName)}`;

/**
 * Arma las líneas de subte (recorrido + estaciones en orden) a partir del GTFS estático.
 * Por cada línea toma el viaje con más paradas como recorrido representativo.
 * Si el feed tiene shapes.txt usa esa geometría; si no, une las estaciones en orden.
 */
export function buildSubwayLines(files: Record<string, string>): SubwayLine[] {
  const routes = parseCsv(files['routes.txt'] ?? '');
  const stops = new Map(parseCsv(files['stops.txt'] ?? '').map((s) => [s.stop_id ?? '', s]));
  const trips = parseCsv(files['trips.txt'] ?? '');
  const shapes = groupShapes(parseCsv(files['shapes.txt'] ?? ''));

  const stopsByTrip = new Map<string, { seq: number; stopId: string }[]>();
  for (const st of parseCsv(files['stop_times.txt'] ?? '')) {
    const tripId = st.trip_id ?? '';
    let arr = stopsByTrip.get(tripId);
    if (!arr) stopsByTrip.set(tripId, (arr = []));
    arr.push({ seq: Number(st.stop_sequence), stopId: st.stop_id ?? '' });
  }

  const lines: SubwayLine[] = [];
  for (const route of routes) {
    const lineId = route.route_id ?? '';
    const representative = pickRepresentativeTrip(
      trips.filter((t) => t.route_id === lineId),
      stopsByTrip,
    );
    if (!representative) continue;

    const stations: SubwayStation[] = [];
    const seen = new Set<string>();
    const ordered = [...(stopsByTrip.get(representative.trip_id ?? '') ?? [])].sort((a, b) => a.seq - b.seq);
    for (const { stopId } of ordered) {
      const stop = resolveStation(stops, stopId);
      if (!stop) continue;
      const id = stationKey(lineId, stop.name);
      if (seen.has(id)) continue;
      seen.add(id);
      stations.push({ id, name: stop.name, lat: stop.lat, lon: stop.lon });
    }
    if (stations.length === 0) continue;

    const shape = shapes.get(representative.shape_id ?? '');
    lines.push({
      id: lineId,
      name: route.route_short_name || route.route_long_name || lineId,
      color: cleanColor(route.route_color, '888888'),
      textColor: cleanColor(route.route_text_color, 'FFFFFF'),
      path: shape && shape.length > 1 ? shape : stations.map((s) => [s.lat, s.lon] as LatLon),
      stations,
    });
  }
  return lines.sort((a, b) => a.name.localeCompare(b.name, 'es'));
}

function pickRepresentativeTrip(trips: CsvRow[], stopsByTrip: Map<string, unknown[]>): CsvRow | undefined {
  let best: CsvRow | undefined;
  let bestScore = -1;
  for (const t of trips) {
    // Más paradas gana; ante empate, preferir sentido 0 para que el orden sea estable.
    const score = (stopsByTrip.get(t.trip_id ?? '')?.length ?? 0) * 2 + (t.direction_id === '0' ? 1 : 0);
    if (score > bestScore) {
      best = t;
      bestScore = score;
    }
  }
  return best;
}

/** Si la parada es un andén con estación padre, devuelve la estación. */
function resolveStation(stops: Map<string, CsvRow>, stopId: string) {
  const stop = stops.get(stopId);
  if (!stop) return undefined;
  const parent = stop.parent_station ? stops.get(stop.parent_station) : undefined;
  const source = parent && parent.stop_lat ? parent : stop;
  const lat = Number(source.stop_lat);
  const lon = Number(source.stop_lon);
  const name = source.stop_name || stop.stop_name;
  if (!name || !Number.isFinite(lat) || !Number.isFinite(lon)) return undefined;
  return { name, lat, lon };
}

function groupShapes(rows: CsvRow[]): Map<string, LatLon[]> {
  const byId = new Map<string, { seq: number; pt: LatLon }[]>();
  for (const r of rows) {
    const id = r.shape_id ?? '';
    let arr = byId.get(id);
    if (!arr) byId.set(id, (arr = []));
    arr.push({ seq: Number(r.shape_pt_sequence), pt: [Number(r.shape_pt_lat), Number(r.shape_pt_lon)] });
  }
  const out = new Map<string, LatLon[]>();
  for (const [id, pts] of byId) out.set(id, pts.sort((a, b) => a.seq - b.seq).map((p) => p.pt));
  return out;
}

function cleanColor(value: string | undefined, fallback: string): string {
  const hex = (value ?? '').replace(/^#/, '').toUpperCase();
  return /^[0-9A-F]{6}$/.test(hex) ? hex : fallback;
}

/**
 * Convierte /subtes/forecastGTFS. Forma esperada (JSON propio del GCBA, no GTFS-RT estándar):
 *   { Header: {timestamp}, Entity: [{ ID, Linea: { Trip_Id, Route_Id, Direction_ID,
 *       Estaciones: [{ stop_id, stop_name, arrival: {time, delay}, departure: {...} }] } }] }
 */
export function parseSubwayForecast(raw: unknown): { updatedAt?: number; arrivals: SubwayArrival[] } {
  const arrivals: SubwayArrival[] = [];
  for (const entity of list(pick(raw, 'Entity', 'entity'))) {
    const linea = pick(entity, 'Linea', 'trip_update', 'tripUpdate');
    const lineId = str(pick(linea, 'Route_Id', 'route_id'));
    if (!lineId) continue;
    const tripId = str(pick(linea, 'Trip_Id', 'trip_id')) ?? str(pick(entity, 'ID', 'id')) ?? '';
    const directionId = num(pick(linea, 'Direction_ID', 'direction_id')) ?? 0;

    const stations = list(pick(linea, 'Estaciones', 'stop_time_update'));
    const last = stations.at(-1);
    const destination = str(pick(last, 'stop_name')) ?? '';

    for (const est of stations) {
      const name = str(pick(est, 'stop_name'));
      const event = pick(est, 'arrival');
      const fallback = pick(est, 'departure');
      const time = num(pick(event, 'time')) || num(pick(fallback, 'time'));
      if (!name || !time) continue;
      arrivals.push({
        stationId: stationKey(lineId, name),
        lineId,
        tripId,
        directionId,
        destination,
        arrivalTime: time,
        delaySeconds: num(pick(event, 'delay')) ?? 0,
      });
    }
  }
  const updatedAt = num(pick(pick(raw, 'Header', 'header'), 'timestamp'));
  return updatedAt === undefined ? { arrivals } : { updatedAt, arrivals };
}

/** Próximas llegadas a una estación: hasta `perDirection` trenes por sentido, ya ordenados. */
export function arrivalsForStation(
  all: SubwayArrival[],
  stationId: string,
  nowSec: number,
  perDirection = 3,
): SubwayArrival[] {
  const upcoming = all
    .filter((a) => a.stationId === stationId && a.arrivalTime >= nowSec - 30)
    .sort((a, b) => a.arrivalTime - b.arrivalTime);
  const count = new Map<string, number>();
  return upcoming.filter((a) => {
    const n = count.get(a.destination) ?? 0;
    count.set(a.destination, n + 1);
    return n < perDirection;
  });
}

/** Convierte /subtes/serviceAlerts?json=1 (GTFS-Realtime en JSON). */
export function parseServiceAlerts(raw: unknown): ServiceAlert[] {
  const alerts: ServiceAlert[] = [];
  list(pick(raw, 'entity', 'Entity')).forEach((entity, idx) => {
    const alert = pick(entity, 'alert') ?? entity;
    const title = translated(pick(alert, 'header_text', 'headerText'));
    if (!title) return;
    const description = translated(pick(alert, 'description_text', 'descriptionText'));
    const lineIds = [
      ...new Set(
        list(pick(alert, 'informed_entity', 'informedEntity'))
          .map((e) => str(pick(e, 'route_id', 'routeId')))
          .filter((id): id is string => Boolean(id)),
      ),
    ];
    const period = list(pick(alert, 'active_period', 'activePeriod'))[0];
    const result: ServiceAlert = { id: str(pick(entity, 'id')) ?? `alert-${idx}`, title, lineIds };
    if (description && description !== title) result.description = description;
    const start = num(pick(period, 'start'));
    const end = num(pick(period, 'end'));
    if (start) result.activeFrom = start;
    if (end) result.activeUntil = end;
    alerts.push(result);
  });
  return alerts;
}

/** Texto traducido GTFS-RT: {translation:[{text, language}]} o directamente [{text, language}]. */
function translated(value: unknown): string | undefined {
  if (typeof value === 'string') return str(value);
  const items = isObj(value) ? list(pick(value, 'translation')) : list(value);
  const es = items.find((t) => /^es/i.test(str(pick(t, 'language')) ?? ''));
  return str(pick(es ?? items[0], 'text'));
}

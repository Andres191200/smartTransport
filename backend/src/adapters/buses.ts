import { isValidCoord, list, num, pick, str } from './read.ts';

export interface Bus {
  id: string;
  lat: number;
  lon: number;
  /** Línea visible al público, p. ej. "60" o "152A". */
  line: string;
  headsign?: string;
  agency?: string;
  directionId?: number;
  speedMps?: number;
  /** Momento de la posición, en segundos POSIX. */
  timestamp?: number;
}

export interface BoundingBox {
  minLat: number;
  minLon: number;
  maxLat: number;
  maxLon: number;
}

/**
 * Convierte la respuesta de /colectivos/vehiclePositionsSimple.
 * Se espera un array de objetos planos (id, latitude, longitude, route_short_name, ...);
 * también se acepta el array envuelto en { data: [...] }.
 */
export function parseBusPositions(raw: unknown): Bus[] {
  const rows = Array.isArray(raw) ? raw : list(pick(raw, 'data', 'vehicles', 'entity'));
  const buses: Bus[] = [];

  for (const row of rows) {
    const lat = num(pick(row, 'latitude', 'lat'));
    const lon = num(pick(row, 'longitude', 'lon', 'lng'));
    if (!isValidCoord(lat, lon)) continue;

    const id = str(pick(row, 'id', 'vehicle_id'));
    const line = str(pick(row, 'route_short_name', 'linea', 'route_id'));
    if (!id || !line) continue;

    const bus: Bus = { id, lat: lat!, lon: lon!, line };
    const headsign = str(pick(row, 'trip_headsign', 'headsign'));
    const agency = str(pick(row, 'agency_name'));
    const directionId = num(pick(row, 'direction', 'direction_id'));
    const speedMps = num(pick(row, 'speed'));
    const timestamp = num(pick(row, 'timestamp'));
    if (headsign) bus.headsign = headsign;
    if (agency) bus.agency = agency;
    if (directionId !== undefined) bus.directionId = directionId;
    if (speedMps !== undefined) bus.speedMps = speedMps;
    if (timestamp !== undefined) bus.timestamp = timestamp;
    buses.push(bus);
  }
  return buses;
}

/**
 * Línea a la que pertenece un Ramal: su número sin el sufijo de letras ("60A" → "60").
 * Es la misma regla que `matchesLine`; un nombre sin número queda igual.
 */
export function branchLine(branch: string): string {
  const name = branch.trim().toUpperCase();
  return /^(.*\d)[A-Z]*$/.exec(name)?.[1] ?? name;
}

/** "60" coincide con "60", "60A", "60B"... pero no con "160" ni "600". */
export function matchesLine(busLine: string, query: string): boolean {
  const line = busLine.toUpperCase();
  const q = query.trim().toUpperCase();
  if (!q) return true;
  return line === q || (line.startsWith(q) && /^[A-Z]+$/.test(line.slice(q.length)));
}

export function inBox(bus: { lat: number; lon: number }, box: BoundingBox): boolean {
  return bus.lat >= box.minLat && bus.lat <= box.maxLat && bus.lon >= box.minLon && bus.lon <= box.maxLon;
}

/** Con `lines`, cada Línea incluye todos sus Ramales. */
export function filterBuses(
  buses: Bus[],
  opts: { box?: BoundingBox; lines?: string[]; limit: number },
): { vehicles: Bus[]; truncated: boolean } {
  const { box, lines } = opts;
  const matched = buses.filter(
    (b) => (!box || inBox(b, box)) && (!lines || lines.some((line) => matchesLine(b.line, line))),
  );
  return { vehicles: matched.slice(0, opts.limit), truncated: matched.length > opts.limit };
}

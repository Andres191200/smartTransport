import { branchLine } from './buses.ts';
import { csvRows, parseCsv, readShapes, type LatLon } from './gtfs.ts';

export interface BusBranch {
  /** Nombre del Ramal, p. ej. "60A" (o "152" si la Línea tiene uno solo). */
  id: string;
  /** Las dos Terminales, en el sentido del Recorrido. Falta si el feed no permite deducirlas. */
  terminals?: [string, string];
  /** Recorrido de una Terminal a la otra; vacío si el feed no trae el shape. */
  path: LatLon[];
}

export interface BusLine {
  /** Número de la Línea, p. ej. "60". */
  id: string;
  branches: BusBranch[];
}

/** Archivos del GTFS estático que usa `buildBusLines` (stop_times.txt no: es enorme y no hace falta). */
export const BUS_GTFS_FILES = ['routes.txt', 'trips.txt', 'shapes.txt', 'stops.txt'];

/** Cuántas veces aparece cada valor; sirve para elegir el más usado. */
class Tally {
  #counts = new Map<string, number>();

  add(value: string | undefined) {
    if (value) this.#counts.set(value, (this.#counts.get(value) ?? 0) + 1);
  }

  /** El más frecuente; ante empate, el primero que apareció. */
  top(): string | undefined {
    let best: string | undefined;
    let bestCount = 0;
    for (const [value, count] of this.#counts) {
      if (count > bestCount) {
        best = value;
        bestCount = count;
      }
    }
    return best;
  }
}

interface Direction {
  trips: number;
  shapes: Tally;
  headsigns: Tally;
}

/**
 * Arma el catálogo de Líneas de Colectivo a partir del GTFS estático.
 *
 * - Cada `route_short_name` es un Ramal (varios `route_id` con el mismo nombre se juntan) y los
 *   Ramales se agrupan en Líneas con la regla de `branchLine` ("60A" → Línea 60).
 * - El Recorrido es el shape más usado por los viajes de ida (`direction_id` 0, o el sentido con
 *   más viajes si no hay ida).
 * - Las Terminales salen de los `trip_headsign`: el de la vuelta es donde empieza el Recorrido y el
 *   de la ida, donde termina. Si falta alguno, se usa la parada más cercana a esa punta del Recorrido.
 */
export function buildBusLines(files: Record<string, string>): BusLine[] {
  const branchOfRoute = new Map<string, string>();
  for (const route of parseCsv(files['routes.txt'] ?? '')) {
    const name = (route.route_short_name ?? '').replace(/\s+/g, '').toUpperCase();
    if (route.route_id && name) branchOfRoute.set(route.route_id, name);
  }

  const directions = new Map<string, Map<string, Direction>>();
  for (const trip of csvRows(files['trips.txt'] ?? '')) {
    const branch = branchOfRoute.get(trip.route_id ?? '');
    if (!branch) continue;
    let byDirection = directions.get(branch);
    if (!byDirection) directions.set(branch, (byDirection = new Map()));
    const key = trip.direction_id ?? '';
    let dir = byDirection.get(key);
    if (!dir) byDirection.set(key, (dir = { trips: 0, shapes: new Tally(), headsigns: new Tally() }));
    dir.trips++;
    dir.shapes.add(trip.shape_id);
    dir.headsigns.add(trip.trip_headsign);
  }

  const chosen = new Map<string, { shapeId?: string; from?: string; to?: string }>();
  for (const [branch, byDirection] of directions) {
    const [outbound, inbound] = pickDirections(byDirection);
    chosen.set(branch, {
      shapeId: outbound.shapes.top(),
      to: outbound.headsigns.top(),
      from: inbound?.headsigns.top(),
    });
  }

  const wanted = new Set([...chosen.values()].map((c) => c.shapeId).filter((id): id is string => Boolean(id)));
  const shapes = readShapes(files['shapes.txt'] ?? '', wanted);
  const nearestStop = stopFinder(files['stops.txt'] ?? '');

  const lines = new Map<string, BusBranch[]>();
  for (const [id, { shapeId, from, to }] of chosen) {
    const path = (shapeId && shapes.get(shapeId)) || [];
    const start = from ?? nearestStop(path[0]);
    const end = to ?? nearestStop(path.at(-1));
    const branch: BusBranch = { id, path };
    if (start && end) branch.terminals = [start, end];

    const lineId = branchLine(id);
    let branches = lines.get(lineId);
    if (!branches) lines.set(lineId, (branches = []));
    branches.push(branch);
  }

  return [...lines]
    .map(([id, branches]) => ({ id, branches: branches.sort((a, b) => compareNames(a.id, b.id)) }))
    .sort((a, b) => compareNames(a.id, b.id));
}

/** [ida, vuelta]: la ida es el sentido 0 (o el que tiene más viajes); la vuelta, el 1 si hay ida. */
function pickDirections(byDirection: Map<string, Direction>): [Direction, Direction | undefined] {
  const outbound =
    byDirection.get('0') ?? [...byDirection.values()].reduce((a, b) => (b.trips > a.trips ? b : a));
  const inbound = byDirection.has('0') ? byDirection.get('1') : undefined;
  return [outbound, inbound];
}

/** Ordena "8" antes que "60" y "60A" antes que "60B". */
const compareNames = (a: string, b: string) => a.localeCompare(b, 'es', { numeric: true });

/** Devuelve el nombre de la parada más cercana a un punto. Lee stops.txt solo si hace falta. */
function stopFinder(text: string): (point: LatLon | undefined) => string | undefined {
  let stops: { name: string; lat: number; lon: number }[] | undefined;
  return (point) => {
    if (!point) return undefined;
    stops ??= parseCsv(text)
      .map((s) => ({ name: s.stop_name ?? '', lat: Number(s.stop_lat), lon: Number(s.stop_lon) }))
      .filter((s) => s.name && Number.isFinite(s.lat) && Number.isFinite(s.lon));
    let best: string | undefined;
    let bestDistance = Infinity;
    const [lat, lon] = point;
    // Distancia plana: en el AMBA un grado de longitud mide cos(lat) ≈ 0,82 de uno de latitud.
    const lonScale = Math.cos((lat * Math.PI) / 180);
    for (const s of stops) {
      const d = (s.lat - lat) ** 2 + ((s.lon - lon) * lonScale) ** 2;
      if (d < bestDistance) {
        best = s.name;
        bestDistance = d;
      }
    }
    return best;
  };
}

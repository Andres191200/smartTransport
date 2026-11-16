// Ecobici vía GBFS (General Bikeshare Feed Specification).
// Referencia: https://github.com/MobilityData/gbfs/blob/v2.3/gbfs.md
// Se aceptan también los formatos 1.x (enteros 0/1 en vez de booleanos) que usa la API del GCBA.

import { isValidCoord, list, num, pick, str } from './read.ts';

export interface BikeStation {
  id: string;
  name: string;
  address?: string;
  lat: number;
  lon: number;
  /** Total de anclajes instalados (disponibles o no). */
  capacity?: number;
  /** Bicis disponibles para alquilar (sin contar monopatines u otros vehículos). */
  bikes: number;
  /** De esas, cuántas son eléctricas. */
  ebikes: number;
  /** Anclajes libres para devolver una bici. */
  docks: number;
  /** La estación está instalada y prestando bicis (`is_installed` && `is_renting`). */
  operational: boolean;
  /** La estación acepta devoluciones (`is_returning`). */
  acceptsReturns: boolean;
}

interface VehicleType {
  isBicycle: boolean;
  isElectric: boolean;
}

const stationsOf = (raw: unknown) => list(pick(pick(raw, 'data'), 'stations'));

/** GBFS 2.x usa booleanos; 1.x (y la API del GCBA) usa 0/1. */
function flag(value: unknown): boolean | undefined {
  if (typeof value === 'boolean') return value;
  const n = num(value);
  return n === undefined ? undefined : n === 1;
}

/** "002 - Retiro I" → "Retiro I" */
export function cleanStationName(name: string): string {
  return name.replace(/^\s*\d+\s*-\s*/, '').trim() || name;
}

/**
 * vehicle_types.json → tipos por id. Eléctrico = `propulsion_type` distinto de "human";
 * bici = `form_factor` "bicycle" o "cargo_bicycle" (Ecobici también publica monopatines).
 */
export function parseVehicleTypes(raw: unknown): Map<string, VehicleType> {
  const types = new Map<string, VehicleType>();
  for (const t of list(pick(pick(raw, 'data'), 'vehicle_types'))) {
    const id = str(pick(t, 'vehicle_type_id'));
    if (!id) continue;
    const formFactor = str(pick(t, 'form_factor')) ?? 'bicycle';
    const propulsion = str(pick(t, 'propulsion_type')) ?? 'human';
    types.set(id, {
      isBicycle: formFactor === 'bicycle' || formFactor === 'cargo_bicycle',
      isElectric: propulsion !== 'human',
    });
  }
  return types;
}

function countBikes(status: unknown, types: Map<string, VehicleType>): { bikes: number; ebikes: number } {
  const total = num(pick(status, 'num_bikes_available')) ?? 0;
  const available = pick(status, 'vehicle_types_available');

  // GBFS 2.1+: desglose por tipo de vehículo. Sin vehicle_types.json no se puede interpretar.
  if (Array.isArray(available) && types.size > 0) {
    let bikes = 0;
    let ebikes = 0;
    for (const entry of available) {
      const type = types.get(str(pick(entry, 'vehicle_type_id')) ?? '');
      const count = num(pick(entry, 'count')) ?? 0;
      // Un tipo que no figura en vehicle_types.json se asume bici mecánica (default de la spec).
      if (type && !type.isBicycle) continue;
      bikes += count;
      if (type?.isElectric) ebikes += count;
    }
    return { bikes, ebikes };
  }

  // GBFS 1.x de la API del GCBA: { mechanical: n, ebike: n }
  const ebikes = num(pick(pick(status, 'num_bikes_available_types'), 'ebike')) ?? 0;
  return { bikes: total, ebikes: Math.min(ebikes, total) };
}

/**
 * Une station_information (estático) con station_status (tiempo real).
 * `vehicleTypes` es opcional: según la spec, si no existe todos los vehículos son bicis mecánicas.
 */
export function mergeBikeStations(information: unknown, status: unknown, vehicleTypes?: unknown): BikeStation[] {
  const types = parseVehicleTypes(vehicleTypes);
  const statusById = new Map<string, unknown>();
  for (const s of stationsOf(status)) {
    const id = str(pick(s, 'station_id'));
    if (id) statusById.set(id, s);
  }

  const result: BikeStation[] = [];
  for (const info of stationsOf(information)) {
    const id = str(pick(info, 'station_id'));
    const lat = num(pick(info, 'lat'));
    const lon = num(pick(info, 'lon'));
    if (!id || !isValidCoord(lat, lon)) continue;

    // La spec exige que toda estación tenga estado; si falta, se muestra como no operativa.
    const st = statusById.get(id);
    const { bikes, ebikes } = countBikes(st, types);
    const installed = flag(pick(st, 'is_installed')) ?? false;

    const station: BikeStation = {
      id,
      name: cleanStationName(str(pick(info, 'name')) ?? id),
      lat: lat!,
      lon: lon!,
      bikes,
      ebikes,
      docks: num(pick(st, 'num_docks_available')) ?? 0,
      operational: installed && (flag(pick(st, 'is_renting')) ?? false),
      acceptsReturns: installed && (flag(pick(st, 'is_returning')) ?? false),
    };
    const address = str(pick(info, 'address'));
    const capacity = num(pick(info, 'capacity'));
    if (address) station.address = address;
    if (capacity !== undefined) station.capacity = capacity;
    result.push(station);
  }
  return result;
}

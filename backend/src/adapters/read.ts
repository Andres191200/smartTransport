// Lectores tolerantes para JSON de forma no garantizada.
// La API del GCBA mezcla mayúsculas (p. ej. "Entity"/"entity", "Route_Id"/"route_id"),
// así que la búsqueda de claves ignora mayúsculas y guiones bajos.

type Obj = Record<string, unknown>;

export function isObj(value: unknown): value is Obj {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

const normKey = (k: string) => k.toLowerCase().replace(/_/g, '');

/** Devuelve el valor de la primera clave que exista (sin distinguir mayúsculas ni "_"). */
export function pick(obj: unknown, ...keys: string[]): unknown {
  if (!isObj(obj)) return undefined;
  for (const key of keys) {
    if (key in obj) return obj[key];
  }
  const wanted = new Set(keys.map(normKey));
  for (const [k, v] of Object.entries(obj)) {
    if (wanted.has(normKey(k))) return v;
  }
  return undefined;
}

export function str(value: unknown): string | undefined {
  if (typeof value === 'string') return value.trim() || undefined;
  if (typeof value === 'number' && Number.isFinite(value)) return String(value);
  return undefined;
}

export function num(value: unknown): number | undefined {
  if (typeof value === 'number') return Number.isFinite(value) ? value : undefined;
  if (typeof value === 'string' && value.trim() !== '') {
    const n = Number(value);
    return Number.isFinite(n) ? n : undefined;
  }
  return undefined;
}

/** Acepta un array, un objeto suelto (lo envuelve) o nada. */
export function list(value: unknown): unknown[] {
  if (Array.isArray(value)) return value;
  if (value === undefined || value === null) return [];
  return [value];
}

export function isValidCoord(lat: number | undefined, lon: number | undefined): boolean {
  return (
    lat !== undefined && lon !== undefined &&
    lat >= -90 && lat <= 90 && lon >= -180 && lon <= 180 &&
    !(lat === 0 && lon === 0)
  );
}

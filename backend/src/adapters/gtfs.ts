import { strFromU8, unzipSync } from 'fflate';

export type CsvRow = Record<string, string>;

/** Extrae del zip GTFS solo los archivos pedidos (p. ej. "stops.txt"). */
export function readGtfsZip(zip: Uint8Array, wanted: string[]): Record<string, string> {
  const wantedSet = new Set(wanted);
  const files = unzipSync(zip, {
    // Algunos feeds traen los .txt dentro de una carpeta: comparar por nombre base.
    filter: (file) => wantedSet.has(baseName(file.name)),
  });
  const out: Record<string, string> = {};
  for (const [name, data] of Object.entries(files)) out[baseName(name)] = strFromU8(data);
  return out;
}

const baseName = (path: string) => path.slice(path.lastIndexOf('/') + 1);

/** Parser CSV (RFC 4180): comillas, comas y saltos de línea dentro de comillas, BOM y CRLF. */
export function parseCsv(text: string): CsvRow[] {
  return [...csvRows(text)];
}

/**
 * Como `parseCsv`, pero entrega las filas de a una: para archivos grandes (el `shapes.txt` de
 * colectivos) se puede quedar solo con lo que hace falta sin armar todas las filas juntas.
 */
export function* csvRows(text: string): Generator<CsvRow> {
  let keys: string[] | undefined;
  for (const record of csvRecords(text)) {
    if (record.length === 1 && record[0] === '') continue;
    if (!keys) {
      keys = record.map((h) => h.trim());
      continue;
    }
    const obj: CsvRow = {};
    keys.forEach((k, idx) => {
      obj[k] = (record[idx] ?? '').trim();
    });
    yield obj;
  }
}

function* csvRecords(text: string): Generator<string[]> {
  let row: string[] = [];
  let field = '';
  let inQuotes = false;
  const src = text.charCodeAt(0) === 0xfeff ? text.slice(1) : text;

  for (let i = 0; i < src.length; i++) {
    const c = src[i];
    if (inQuotes) {
      if (c === '"') {
        if (src[i + 1] === '"') {
          field += '"';
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        field += c;
      }
    } else if (c === '"') {
      inQuotes = true;
    } else if (c === ',') {
      row.push(field);
      field = '';
    } else if (c === '\n' || c === '\r') {
      if (c === '\r' && src[i + 1] === '\n') i++;
      row.push(field);
      yield row;
      row = [];
      field = '';
    } else {
      field += c;
    }
  }
  if (field !== '' || row.length > 0) {
    row.push(field);
    yield row;
  }
}

export type LatLon = [lat: number, lon: number];

/**
 * shapes.txt → { shape_id → puntos en orden de secuencia }.
 * Con `only`, guarda solo esos shapes (el feed de colectivos trae miles y se usan pocos).
 */
export function readShapes(text: string, only?: ReadonlySet<string>): Map<string, LatLon[]> {
  const byId = new Map<string, { seq: number; pt: LatLon }[]>();
  for (const r of csvRows(text)) {
    const id = r.shape_id ?? '';
    if (only && !only.has(id)) continue;
    let arr = byId.get(id);
    if (!arr) byId.set(id, (arr = []));
    arr.push({ seq: Number(r.shape_pt_sequence), pt: [Number(r.shape_pt_lat), Number(r.shape_pt_lon)] });
  }
  const out = new Map<string, LatLon[]>();
  for (const [id, pts] of byId) out.set(id, pts.sort((a, b) => a.seq - b.seq).map((p) => p.pt));
  return out;
}

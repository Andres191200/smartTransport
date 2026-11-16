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
  const rows: string[][] = [];
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
      rows.push(row);
      row = [];
      field = '';
    } else {
      field += c;
    }
  }
  if (field !== '' || row.length > 0) {
    row.push(field);
    rows.push(row);
  }

  const [header, ...body] = rows.filter((r) => !(r.length === 1 && r[0] === ''));
  if (!header) return [];
  const keys = header.map((h) => h.trim());
  return body.map((r) => {
    const obj: CsvRow = {};
    keys.forEach((k, idx) => {
      obj[k] = (r[idx] ?? '').trim();
    });
    return obj;
  });
}

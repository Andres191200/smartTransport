// Cliente genérico de feeds GBFS 2.x (sin credenciales).
// Spec: https://github.com/MobilityData/gbfs/blob/v2.3/gbfs.md

import { isObj, list, num, pick, str } from './adapters/read.ts';
import { TtlCache } from './cache.ts';
import { UpstreamError } from './upstream.ts';

/** Límites para el `ttl` que informa el feed. ttl=0 ("siempre refrescar") pediría el feed en cada
 * request de cada usuario; con un piso de 10 s el backend hace como mucho 6 pedidos por minuto. */
const MIN_TTL_MS = 10_000;
const MAX_TTL_MS = 60 * 60_000;

export function ttlFromResponse(raw: unknown): number {
  const ttlSeconds = num(pick(raw, 'ttl')) ?? 0;
  return Math.min(MAX_TTL_MS, Math.max(MIN_TTL_MS, ttlSeconds * 1000));
}

/**
 * gbfs.json → { nombre de feed → URL }. En 2.x los feeds van agrupados por idioma
 * (`data.es.feeds`, `data.en.feeds`...); se usa el idioma pedido o, si no está, el primero.
 */
export function parseDiscovery(raw: unknown, language: string): Map<string, string> {
  const data = pick(raw, 'data');
  if (!isObj(data)) throw new UpstreamError('gbfs.json sin campo data');
  const byLanguage = isObj(data[language]) ? data[language] : Object.values(data).find(isObj);
  // Algunos feeds 1.0 ponen `feeds` directo en `data`.
  const feeds = list(pick(byLanguage, 'feeds') ?? pick(data, 'feeds'));

  const urls = new Map<string, string>();
  for (const feed of feeds) {
    const name = str(pick(feed, 'name'));
    const url = str(pick(feed, 'url'));
    if (name && url) urls.set(name, url);
  }
  if (urls.size === 0) throw new UpstreamError('gbfs.json no lista ningún feed');
  return urls;
}

export class GbfsClient {
  #discoveryUrl: string;
  #language: string;
  #timeoutMs: number;
  #fetch: typeof fetch;
  #cache = new TtlCache();

  constructor(opts: { discoveryUrl: string; language?: string; timeoutMs?: number; fetch?: typeof fetch }) {
    this.#discoveryUrl = opts.discoveryUrl;
    this.#language = opts.language ?? 'es';
    this.#timeoutMs = opts.timeoutMs ?? 15_000;
    this.#fetch = opts.fetch ?? fetch;
  }

  /** Devuelve un feed por su nombre de la spec (p. ej. "station_status"), cacheado según su `ttl`. */
  async feed(name: string): Promise<unknown> {
    const urls = await this.#cache.get('gbfs.json', ttlFromResponse, () => this.#getJson(this.#discoveryUrl))
      .then((raw) => parseDiscovery(raw, this.#language));
    const url = urls.get(name);
    if (!url) throw new UpstreamError(`El feed GBFS no publica "${name}"`);
    return this.#cache.get(name, ttlFromResponse, () => this.#getJson(url));
  }

  /** Igual que feed(), pero `undefined` si el sistema no publica ese archivo (los opcionales de la spec). */
  async optionalFeed(name: string): Promise<unknown> {
    try {
      return await this.feed(name);
    } catch (error) {
      if (error instanceof UpstreamError) return undefined;
      throw error;
    }
  }

  async #getJson(url: string): Promise<unknown> {
    let res: Response;
    try {
      res = await this.#fetch(url, { signal: AbortSignal.timeout(this.#timeoutMs) });
    } catch (error) {
      throw new UpstreamError(`No se pudo conectar con ${url}: ${(error as Error).message}`);
    }
    if (!res.ok) throw new UpstreamError(`${url} respondió ${res.status}`, res.status);
    try {
      return await res.json();
    } catch {
      throw new UpstreamError(`Respuesta no-JSON de ${url}`, res.status);
    }
  }
}

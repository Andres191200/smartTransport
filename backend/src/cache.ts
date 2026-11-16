interface Entry {
  value: unknown;
  expiresAt: number;
}

/**
 * Caché en memoria con vencimiento por clave.
 *
 * - Pedidos simultáneos a la misma clave comparten una sola llamada a la API.
 * - Si la recarga falla y hay un valor vencido, se devuelve ese valor (mejor un dato
 *   de hace un minuto que una pantalla vacía).
 */
export class TtlCache {
  #entries = new Map<string, Entry>();
  #inflight = new Map<string, Promise<unknown>>();
  #now: () => number;

  constructor(now: () => number = Date.now) {
    this.#now = now;
  }

  /** `ttlMs` puede depender del valor cargado (p. ej. el campo `ttl` de una respuesta GBFS). */
  async get<T>(key: string, ttlMs: number | ((value: T) => number), load: () => Promise<T>): Promise<T> {
    const cached = this.#entries.get(key);
    if (cached && cached.expiresAt > this.#now()) return cached.value as T;

    const pending = this.#inflight.get(key);
    if (pending) return pending as Promise<T>;

    const promise = load()
      .then((value) => {
        const ttl = typeof ttlMs === 'function' ? ttlMs(value) : ttlMs;
        this.#entries.set(key, { value, expiresAt: this.#now() + ttl });
        return value;
      })
      .catch((error: unknown) => {
        if (cached) return cached.value as T;
        throw error;
      })
      .finally(() => this.#inflight.delete(key));

    this.#inflight.set(key, promise);
    return promise;
  }
}

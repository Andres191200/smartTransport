export class UpstreamError extends Error {
  readonly status: number | undefined;

  constructor(message: string, status?: number) {
    super(message);
    this.name = 'UpstreamError';
    this.status = status;
  }
}

/** Cliente HTTP mínimo para https://apitransporte.buenosaires.gob.ar */
export class TransporteClient {
  #baseUrl: string;
  #clientId: string;
  #clientSecret: string;
  #timeoutMs: number;

  constructor(opts: { baseUrl: string; clientId: string; clientSecret: string; timeoutMs?: number }) {
    this.#baseUrl = opts.baseUrl.replace(/\/+$/, '');
    this.#clientId = opts.clientId;
    this.#clientSecret = opts.clientSecret;
    this.#timeoutMs = opts.timeoutMs ?? 20_000;
  }

  async json(path: string, params: Record<string, string> = {}): Promise<unknown> {
    const res = await this.#fetch(path, params);
    try {
      return await res.json();
    } catch {
      throw new UpstreamError(`Respuesta no-JSON de ${path}`, res.status);
    }
  }

  async bytes(path: string, params: Record<string, string> = {}): Promise<Uint8Array> {
    const res = await this.#fetch(path, params);
    return new Uint8Array(await res.arrayBuffer());
  }

  async #fetch(path: string, params: Record<string, string>): Promise<Response> {
    const url = new URL(this.#baseUrl + path);
    for (const [k, v] of Object.entries(params)) url.searchParams.set(k, v);
    url.searchParams.set('client_id', this.#clientId);
    url.searchParams.set('client_secret', this.#clientSecret);

    let res: Response;
    try {
      res = await fetch(url, { signal: AbortSignal.timeout(this.#timeoutMs) });
    } catch (error) {
      // Nunca incluir la URL completa en el error: lleva las credenciales.
      throw new UpstreamError(`No se pudo conectar con ${path}: ${(error as Error).message}`);
    }
    if (!res.ok) {
      const hint = res.status === 401 || res.status === 403 ? ' (¿credenciales inválidas?)' : '';
      throw new UpstreamError(`${path} respondió ${res.status}${hint}`, res.status);
    }
    return res;
  }
}

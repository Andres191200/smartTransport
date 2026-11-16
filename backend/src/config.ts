export interface Config {
  port: number;
  /** Credenciales de la API Transporte. Si falta alguna, colectivos y subte corren en modo demo. */
  credentials: { clientId: string; clientSecret: string } | null;
  upstreamBaseUrl: string;
  ecobici: {
    /** 'live' = feed GBFS público (default); 'demo' = datos simulados, para trabajar sin internet. */
    source: 'live' | 'demo';
    /** URL del gbfs.json (archivo índice de GBFS). */
    discoveryUrl: string;
  };
}

export const ECOBICI_GBFS_URL = 'https://buenosaires.publicbikesystem.net/customer/gbfs/v2/gbfs.json';

export function loadConfig(env: NodeJS.ProcessEnv = process.env): Config {
  const clientId = env.TRANSPORTE_CLIENT_ID?.trim();
  const clientSecret = env.TRANSPORTE_CLIENT_SECRET?.trim();
  const port = Number(env.PORT ?? 8080);

  if (!Number.isInteger(port) || port < 0 || port > 65535) {
    throw new Error(`PORT inválido: ${env.PORT}`);
  }

  const ecobiciSource = env.ECOBICI_SOURCE?.trim() || 'live';
  if (ecobiciSource !== 'live' && ecobiciSource !== 'demo') {
    throw new Error(`ECOBICI_SOURCE debe ser "live" o "demo", no "${ecobiciSource}"`);
  }

  return {
    port,
    credentials: clientId && clientSecret ? { clientId, clientSecret } : null,
    upstreamBaseUrl: env.TRANSPORTE_BASE_URL?.trim() || 'https://apitransporte.buenosaires.gob.ar',
    ecobici: {
      source: ecobiciSource,
      discoveryUrl: env.ECOBICI_GBFS_URL?.trim() || ECOBICI_GBFS_URL,
    },
  };
}

import { BUS_GTFS_FILES, buildBusLines, type BusLine } from './adapters/bus-lines.ts';
import { parseBusPositions, type Bus } from './adapters/buses.ts';
import { mergeBikeStations, type BikeStation } from './adapters/ecobici.ts';
import { readGtfsZip } from './adapters/gtfs.ts';
import {
  buildSubwayLines,
  parseServiceAlerts,
  parseSubwayForecast,
  type ServiceAlert,
  type SubwayArrival,
  type SubwayLine,
} from './adapters/subway.ts';
import { TtlCache } from './cache.ts';
import type { GbfsClient } from './gbfs.ts';
import type { TransporteClient } from './upstream.ts';

export type SourceMode = 'live' | 'demo';

/** Colectivos y subte: API Transporte del GCBA (requiere credenciales). */
export interface TransitSource {
  readonly mode: SourceMode;
  buses(): Promise<Bus[]>;
  /** Catálogo de Líneas de Colectivo con sus Ramales, Terminales y Recorridos. */
  busLines(): Promise<BusLine[]>;
  subwayLines(): Promise<SubwayLine[]>;
  subwayArrivals(): Promise<SubwayArrival[]>;
  subwayAlerts(): Promise<ServiceAlert[]>;
}

/** Ecobici: feed GBFS público del operador (sin credenciales). */
export interface BikeSource {
  readonly mode: SourceMode;
  bikeStations(): Promise<BikeStation[]>;
}

const SECOND = 1000;
const MINUTE = 60 * SECOND;

/** GTFS estático de colectivos (zip). Sin verificar contra la API real: ver `npm run check-api`. */
export const BUS_GTFS_PATH = '/colectivos/feed-gtfs';
/** Se espera que el zip de colectivos sea mucho más grande que el del subte: más margen para bajarlo. */
export const BUS_GTFS_TIMEOUT_MS = 3 * MINUTE;

/** Datos reales de la API Transporte, con caché para no superar la cuota ni sobrecargarla. */
export class LiveSource implements TransitSource {
  readonly mode = 'live' as const;
  #api: TransporteClient;
  #cache = new TtlCache();

  constructor(api: TransporteClient) {
    this.#api = api;
  }

  buses() {
    // La API actualiza posiciones cada 30 s; pedir más seguido no aporta nada.
    return this.#cache.get('buses', 25 * SECOND, async () =>
      parseBusPositions(await this.#api.json('/colectivos/vehiclePositionsSimple')),
    );
  }

  busLines() {
    // Cambia poco y es pesado de bajar y procesar: se arma una vez cada 24 h.
    return this.#cache.get('bus-lines', 24 * 60 * MINUTE, async () => {
      const zip = await this.#api.bytes(BUS_GTFS_PATH, {}, { timeoutMs: BUS_GTFS_TIMEOUT_MS });
      return buildBusLines(readGtfsZip(zip, BUS_GTFS_FILES));
    });
  }

  subwayLines() {
    return this.#cache.get('subway-lines', 24 * 60 * MINUTE, async () => {
      const zip = await this.#api.bytes('/subtes/feed-gtfs');
      const files = readGtfsZip(zip, ['routes.txt', 'stops.txt', 'trips.txt', 'stop_times.txt', 'shapes.txt']);
      return buildSubwayLines(files);
    });
  }

  subwayArrivals() {
    return this.#cache.get('subway-arrivals', 20 * SECOND, async () =>
      parseSubwayForecast(await this.#api.json('/subtes/forecastGTFS', { json: '1' })).arrivals,
    );
  }

  subwayAlerts() {
    return this.#cache.get('subway-alerts', 60 * SECOND, async () =>
      parseServiceAlerts(await this.#api.json('/subtes/serviceAlerts', { json: '1' })),
    );
  }
}

/** Ecobici en vivo desde su feed GBFS. La caché por `ttl` la maneja GbfsClient. */
export class EcobiciSource implements BikeSource {
  readonly mode = 'live' as const;
  #gbfs: GbfsClient;

  constructor(gbfs: GbfsClient) {
    this.#gbfs = gbfs;
  }

  async bikeStations() {
    const [information, status, vehicleTypes] = await Promise.all([
      this.#gbfs.feed('station_information'),
      this.#gbfs.feed('station_status'),
      this.#gbfs.optionalFeed('vehicle_types'),
    ]);
    return mergeBikeStations(information, status, vehicleTypes);
  }
}

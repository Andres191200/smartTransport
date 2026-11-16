// Datos SIMULADOS para desarrollar sin credenciales.
// Las coordenadas son aproximadas y hay pocas líneas/estaciones: alcanza para probar la app,
// no para usarla de referencia. Con credenciales, el servidor usa LiveSource y esto no se carga.

import type { Bus } from './adapters/buses.ts';
import type { BikeStation } from './adapters/ecobici.ts';
import { stationKey, type ServiceAlert, type SubwayArrival, type SubwayLine } from './adapters/subway.ts';
import type { BikeSource, TransitSource } from './sources.ts';

type DemoStation = [name: string, lat: number, lon: number];

const DEMO_LINES: { id: string; name: string; color: string; stations: DemoStation[] }[] = [
  {
    id: 'LineaA',
    name: 'A',
    color: '18CCF5',
    stations: [
      ['Plaza de Mayo', -34.6088, -58.3709],
      ['Perú', -34.6086, -58.3742],
      ['Piedras', -34.6089, -58.3792],
      ['Lima', -34.6091, -58.3826],
      ['Sáenz Peña', -34.6094, -58.3868],
      ['Congreso', -34.6092, -58.3926],
    ],
  },
  {
    id: 'LineaD',
    name: 'D',
    color: '00A975',
    stations: [
      ['Catedral', -34.6074, -58.3741],
      ['9 de Julio', -34.6045, -58.3805],
      ['Tribunales', -34.6018, -58.3846],
      ['Callao', -34.5996, -58.3924],
      ['Facultad de Medicina', -34.5993, -58.3976],
    ],
  },
];

const DEMO_BUS_LINES = ['60', '152', '29', '39', '64', '17'];
const CENTER = { lat: -34.6037, lon: -58.3816 }; // Obelisco

const DEMO_BIKES: DemoStation[] = [
  ['Obelisco', -34.6033, -58.3812],
  ['Plaza de Mayo', -34.6083, -58.3721],
  ['Congreso', -34.6095, -58.3915],
  ['Tribunales', -34.6022, -58.3852],
  ['Plaza San Martín', -34.5953, -58.3755],
  ['Puerto Madero', -34.6077, -58.3646],
  ['Facultad de Derecho', -34.5832, -58.3919],
  ['Retiro', -34.5924, -58.3747],
];

/** Pseudo-aleatorio determinístico: mismo seed → mismo número. */
function rand(seed: number): number {
  const x = Math.sin(seed * 9301 + 49297) * 233280;
  return x - Math.floor(x);
}

export class DemoSource implements TransitSource, BikeSource {
  readonly mode = 'demo' as const;
  #now: () => number;

  constructor(now: () => number = Date.now) {
    this.#now = now;
  }

  async buses(): Promise<Bus[]> {
    const t = this.#now() / 1000;
    const buses: Bus[] = [];
    for (let i = 0; i < 40; i++) {
      const line = DEMO_BUS_LINES[i % DEMO_BUS_LINES.length]!;
      // Cada colectivo da vueltas sobre una elipse alrededor del centro, a distinta velocidad.
      const radius = 0.004 + rand(i) * 0.018;
      const speed = (0.6 + rand(i + 100)) / 600;
      const angle = rand(i + 200) * Math.PI * 2 + t * speed;
      buses.push({
        id: `demo-${i}`,
        lat: CENTER.lat + Math.sin(angle) * radius * 0.82,
        lon: CENTER.lon + Math.cos(angle) * radius,
        line,
        headsign: i % 2 === 0 ? 'Ida (demo)' : 'Vuelta (demo)',
        agency: 'Empresa demo',
        directionId: i % 2,
        speedMps: 4 + rand(i + 300) * 8,
        timestamp: Math.floor(t),
      });
    }
    return buses;
  }

  async subwayLines(): Promise<SubwayLine[]> {
    return DEMO_LINES.map((l) => ({
      id: l.id,
      name: l.name,
      color: l.color,
      textColor: 'FFFFFF',
      path: l.stations.map(([, lat, lon]) => [lat, lon]),
      stations: l.stations.map(([name, lat, lon]) => ({ id: stationKey(l.id, name), name, lat, lon })),
    }));
  }

  async subwayArrivals(): Promise<SubwayArrival[]> {
    const now = Math.floor(this.#now() / 1000);
    const headway = 4 * 60; // un tren cada 4 minutos
    const hop = 90; // 1,5 minutos entre estaciones
    const arrivals: SubwayArrival[] = [];

    for (const line of DEMO_LINES) {
      const names = line.stations.map(([n]) => n);
      for (const directionId of [0, 1]) {
        const order = directionId === 0 ? names : [...names].reverse();
        const destination = order.at(-1)!;
        const firstDeparture = Math.floor(now / headway) * headway;
        for (let train = -1; train < 3; train++) {
          const departure = firstDeparture + train * headway;
          order.forEach((name, idx) => {
            const time = departure + idx * hop;
            if (time < now) return;
            arrivals.push({
              stationId: stationKey(line.id, name),
              lineId: line.id,
              tripId: `${line.id}-${directionId}-${departure}`,
              directionId,
              destination,
              arrivalTime: time,
              delaySeconds: 0,
            });
          });
        }
      }
    }
    return arrivals;
  }

  async subwayAlerts(): Promise<ServiceAlert[]> {
    return [
      {
        id: 'demo-1',
        title: 'Datos de demostración',
        description: 'El servidor no tiene credenciales de la API Transporte. Configurá el .env para ver datos reales.',
        lineIds: [],
      },
    ];
  }

  async bikeStations(): Promise<BikeStation[]> {
    const minute = Math.floor(this.#now() / 60_000);
    return DEMO_BIKES.map(([name, lat, lon], i) => {
      const capacity = 16 + (i % 3) * 4;
      const bikes = Math.floor(rand(minute * 31 + i) * (capacity + 1));
      return {
        id: `demo-${i}`,
        name,
        lat,
        lon,
        capacity,
        bikes,
        ebikes: Math.min(bikes, Math.floor(rand(minute + i * 7) * 4)),
        docks: capacity - bikes,
        operational: i !== 5,
        acceptsReturns: i !== 5,
      };
    });
  }
}

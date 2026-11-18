// Datos SIMULADOS para desarrollar sin credenciales.
// Las coordenadas son aproximadas y hay pocas líneas/estaciones: alcanza para probar la app,
// no para usarla de referencia. Con credenciales, el servidor usa LiveSource y esto no se carga.

import type { BusLine } from './adapters/bus-lines.ts';
import { branchLine, type Bus } from './adapters/buses.ts';
import type { LatLon } from './adapters/gtfs.ts';
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

// Ramales de colectivo con Terminales y Recorridos inventados pero plausibles. Los colectivos
// simulados circulan por estos Recorridos, así que catálogo y vehículos son coherentes.
type DemoBranch = { id: string; terminals: [string, string]; path: LatLon[] };

const CONSTITUCION: LatLon = [-34.6277, -58.3815];
const LA_BOCA: LatLon = [-34.6345, -58.3631];
const PLAZA_DE_MAYO: LatLon = [-34.6083, -58.3712];
const PLAZA_ITALIA: LatLon = [-34.5813, -58.421];
const CHACARITA: LatLon = [-34.587, -58.4545];
const BARRACAS: LatLon = [-34.645, -58.382];

const DEMO_BUS_BRANCHES: DemoBranch[] = [
  {
    id: '60A',
    terminals: ['Constitución', 'Escobar'],
    path: [CONSTITUCION, [-34.6045, -58.3925], PLAZA_ITALIA, [-34.5617, -58.45], [-34.4708, -58.5286], [-34.3484, -58.7957]],
  },
  {
    id: '60B',
    terminals: ['Constitución', 'Tigre'],
    path: [CONSTITUCION, [-34.6045, -58.3925], PLAZA_ITALIA, [-34.5617, -58.45], [-34.426, -58.5796]],
  },
  {
    id: '152',
    terminals: ['La Boca', 'Olivos'],
    path: [LA_BOCA, PLAZA_DE_MAYO, [-34.5915, -58.3745], [-34.578, -58.413], [-34.51, -58.489]],
  },
  {
    id: '29',
    terminals: ['La Boca', 'Belgrano'],
    path: [[-34.638, -58.362], PLAZA_DE_MAYO, [-34.5953, -58.3755], [-34.58, -58.4], [-34.56, -58.456]],
  },
  {
    id: '39A',
    terminals: ['Barracas', 'Chacarita'],
    path: [BARRACAS, CONSTITUCION, [-34.6092, -58.3926], [-34.6035, -58.411], CHACARITA],
  },
  {
    id: '39B',
    terminals: ['Barracas', 'Belgrano'],
    path: [BARRACAS, CONSTITUCION, [-34.6092, -58.3926], PLAZA_ITALIA, [-34.5627, -58.4565]],
  },
  {
    id: '64',
    terminals: ['La Boca', 'Chacarita'],
    path: [LA_BOCA, PLAZA_DE_MAYO, [-34.609, -58.406], CHACARITA],
  },
  {
    id: '17',
    terminals: ['Barrio Mitre', 'Constitución'],
    path: [[-34.556, -58.498], PLAZA_ITALIA, [-34.609, -58.406], CONSTITUCION],
  },
];

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

/** Punto a una fracción (0 a 1) del largo de un Recorrido. */
function pointAlong(path: LatLon[], fraction: number): LatLon {
  const lengths = path.slice(1).map((p, i) => Math.hypot(p[0] - path[i]![0], p[1] - path[i]![1]));
  let remaining = fraction * lengths.reduce((a, b) => a + b, 0);
  for (const [i, length] of lengths.entries()) {
    if (remaining <= length) {
      const [a, b] = [path[i]!, path[i + 1]!];
      const k = length ? remaining / length : 0;
      return [a[0] + (b[0] - a[0]) * k, a[1] + (b[1] - a[1]) * k];
    }
    remaining -= length;
  }
  return path.at(-1)!;
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
      const branch = DEMO_BUS_BRANCHES[i % DEMO_BUS_BRANCHES.length]!;
      // Cada colectivo va y vuelve por el Recorrido de su Ramal, a distinta velocidad.
      const lap = (rand(i) * 2 + t / (1800 + rand(i + 100) * 1800)) % 2;
      const directionId = lap < 1 ? 0 : 1;
      const [lat, lon] = pointAlong(branch.path, directionId === 0 ? lap : 2 - lap);
      buses.push({
        id: `demo-${i}`,
        lat,
        lon,
        line: branch.id,
        headsign: branch.terminals[directionId === 0 ? 1 : 0],
        agency: 'Empresa demo',
        directionId,
        speedMps: 4 + rand(i + 300) * 8,
        timestamp: Math.floor(t),
      });
    }
    return buses;
  }

  async busLines(): Promise<BusLine[]> {
    const lines = new Map<string, BusLine>();
    for (const { id, terminals, path } of DEMO_BUS_BRANCHES) {
      const lineId = branchLine(id);
      let line = lines.get(lineId);
      if (!line) lines.set(lineId, (line = { id: lineId, branches: [] }));
      line.branches.push({ id, terminals, path });
    }
    return [...lines.values()].sort((a, b) => a.id.localeCompare(b.id, 'es', { numeric: true }));
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

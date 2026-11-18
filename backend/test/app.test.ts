import assert from 'node:assert/strict';
import { createServer, type Server } from 'node:http';
import type { AddressInfo } from 'node:net';
import { after, before, describe, it } from 'node:test';
import { createHandler } from '../src/app.ts';
import { TtlCache } from '../src/cache.ts';
import { loadConfig } from '../src/config.ts';
import { DemoSource } from '../src/demo.ts';
import type { BikeSource, TransitSource } from '../src/sources.ts';
import { UpstreamError } from '../src/upstream.ts';

async function withServer(source: TransitSource & BikeSource) {
  const server = createServer(createHandler({ transit: source, bikes: source }));
  await new Promise<void>((resolve) => server.listen(0, resolve));
  const { port } = server.address() as AddressInfo;
  const get = async (path: string) => {
    const res = await fetch(`http://127.0.0.1:${port}${path}`);
    return { status: res.status, body: (await res.json()) as Record<string, any> };
  };
  return { server, get };
}

describe('API HTTP en modo demo', () => {
  let server: Server;
  let get: Awaited<ReturnType<typeof withServer>>['get'];

  before(async () => ({ server, get } = await withServer(new DemoSource())));
  after(() => server.close());

  it('/health informa el modo de cada fuente', async () => {
    const { status, body } = await get('/health');
    assert.equal(status, 200);
    assert.deepEqual(body.modes, { transit: 'demo', bikes: 'demo' });
  });

  it('cada endpoint informa el modo de su fuente', async () => {
    assert.equal((await get('/v1/ecobici/stations')).body.mode, 'demo');
    assert.equal((await get('/v1/subway/lines')).body.mode, 'demo');
  });

  it('/v1/buses exige zona o línea', async () => {
    assert.equal((await get('/v1/buses')).status, 400);
    assert.equal((await get('/v1/buses?line=,')).status, 400);
    assert.equal((await get('/v1/buses?bbox=1,2,3')).status, 400);
  });

  it('/v1/buses filtra por zona', async () => {
    const { status, body } = await get('/v1/buses?bbox=-34.7,-58.5,-34.5,-58.3');
    assert.equal(status, 200);
    assert.ok(body.vehicles.length > 0);
    for (const v of body.vehicles) assert.ok(v.lat >= -34.7 && v.lat <= -34.5);
  });

  it('/v1/buses filtra por línea', async () => {
    const { body } = await get('/v1/buses?line=60');
    assert.ok(body.vehicles.length > 0);
    assert.ok(body.vehicles.every((v: { line: string }) => /^60[A-Z]*$/.test(v.line)));
  });

  it('/v1/buses con varias Líneas trae todos sus Ramales y nada de otras Líneas', async () => {
    const { status, body } = await get('/v1/buses?line=60,152');
    assert.equal(status, 200);
    const lines = new Set(body.vehicles.map((v: { line: string }) => v.line));
    assert.deepEqual([...lines].sort(), ['152', '60A', '60B']);
    // También repitiendo el parámetro.
    const repeated = (await get('/v1/buses?line=60&line=152')).body;
    assert.equal(repeated.vehicles.length, body.vehicles.length);
  });

  it('/v1/buses con varias Líneas respeta el límite', async () => {
    const { body } = await get('/v1/buses?line=60,152&limit=2');
    assert.equal(body.vehicles.length, 2);
    assert.equal(body.truncated, true);
  });

  it('/v1/buses/lines: catálogo de Líneas con sus Ramales y Terminales, sin Recorridos', async () => {
    const { status, body } = await get('/v1/buses/lines');
    assert.equal(status, 200);
    assert.equal(body.mode, 'demo');
    const sixty = body.lines.find((l: { id: string }) => l.id === '60');
    assert.deepEqual(sixty, {
      id: '60',
      branches: [
        { id: '60A', terminals: ['Constitución', 'Escobar'] },
        { id: '60B', terminals: ['Constitución', 'Tigre'] },
      ],
    });
    for (const line of body.lines) {
      assert.ok(line.branches.length > 0);
      for (const branch of line.branches) {
        assert.equal(branch.terminals.length, 2);
        assert.equal(branch.path, undefined);
      }
    }
  });

  it('el catálogo es coherente con los colectivos simulados', async () => {
    const branches = new Set<string>(
      (await get('/v1/buses/lines')).body.lines.flatMap((l: { branches: { id: string }[] }) => l.branches.map((b) => b.id)),
    );
    const buses = (await get('/v1/buses?bbox=-90,-180,90,180')).body.vehicles;
    assert.ok(buses.length > 0);
    for (const bus of buses) assert.ok(branches.has(bus.line), `${bus.line} no está en el catálogo`);
  });

  it('/v1/buses/paths: Recorridos de cada Ramal de una Línea', async () => {
    const { status, body } = await get('/v1/buses/paths?line=60');
    assert.equal(status, 200);
    assert.equal(body.mode, 'demo');
    assert.equal(body.line.id, '60');
    assert.deepEqual(body.line.branches.map((b: { id: string }) => b.id), ['60A', '60B']);
    for (const branch of body.line.branches) {
      assert.equal(branch.terminals.length, 2);
      assert.ok(branch.path.length > 1);
      for (const [lat, lon] of branch.path) assert.ok(lat < -34 && lat > -35 && lon < -58 && lon > -59);
    }
  });

  it('/v1/buses/paths sin line es 400 y con una Línea desconocida es 404', async () => {
    assert.equal((await get('/v1/buses/paths')).status, 400);
    assert.equal((await get('/v1/buses/paths?line=9999')).status, 404);
  });

  it('/v1/subway/lines y /v1/subway/arrivals usan las mismas claves de estación', async () => {
    const lines = (await get('/v1/subway/lines')).body.lines;
    const station = lines[0].stations[1].id;
    const { status, body } = await get(`/v1/subway/arrivals?station=${encodeURIComponent(station)}`);
    assert.equal(status, 200);
    assert.ok(body.arrivals.length > 0);
    assert.ok(body.arrivals.every((a: { stationId: string }) => a.stationId === station));
  });

  it('/v1/subway/arrivals sin station es 400', async () => {
    assert.equal((await get('/v1/subway/arrivals')).status, 400);
  });

  it('/v1/ecobici/stations y /v1/subway/alerts', async () => {
    assert.ok((await get('/v1/ecobici/stations')).body.stations.length > 0);
    assert.ok(Array.isArray((await get('/v1/subway/alerts')).body.alerts));
  });

  it('404 en rutas desconocidas', async () => {
    assert.equal((await get('/nada')).status, 404);
  });
});

describe('errores de la API de origen', () => {
  it('se responden como 502 sin filtrar detalles', async () => {
    const failing = new DemoSource();
    failing.bikeStations = () => Promise.reject(new UpstreamError('/ecobici respondió 401', 401));
    const { server, get } = await withServer(failing);
    try {
      const { status, body } = await get('/v1/ecobici/stations');
      assert.equal(status, 502);
      assert.equal(body.error, 'La API Transporte no respondió');
    } finally {
      server.close();
    }
  });
});

describe('TtlCache', () => {
  it('reutiliza el valor hasta que vence', async () => {
    let now = 0;
    let calls = 0;
    const cache = new TtlCache(() => now);
    const load = async () => ++calls;
    assert.equal(await cache.get('k', 100, load), 1);
    assert.equal(await cache.get('k', 100, load), 1);
    now = 101;
    assert.equal(await cache.get('k', 100, load), 2);
  });

  it('comparte pedidos simultáneos', async () => {
    let calls = 0;
    const cache = new TtlCache();
    const load = () => new Promise<number>((r) => setTimeout(() => r(++calls), 10));
    const results = await Promise.all([cache.get('k', 1000, load), cache.get('k', 1000, load)]);
    assert.deepEqual(results, [1, 1]);
  });

  it('si falla la recarga devuelve el valor vencido', async () => {
    let now = 0;
    const cache = new TtlCache(() => now);
    await cache.get('k', 10, async () => 'viejo');
    now = 20;
    assert.equal(await cache.get('k', 10, () => Promise.reject(new Error('caída'))), 'viejo');
  });

  it('sin valor previo propaga el error', async () => {
    const cache = new TtlCache();
    await assert.rejects(cache.get('k', 10, () => Promise.reject(new Error('caída'))));
  });
});

describe('loadConfig', () => {
  it('sin credenciales queda en demo', () => {
    assert.equal(loadConfig({}).credentials, null);
    assert.equal(loadConfig({ TRANSPORTE_CLIENT_ID: 'x', TRANSPORTE_CLIENT_SECRET: '  ' }).credentials, null);
  });

  it('con credenciales las toma', () => {
    const c = loadConfig({ TRANSPORTE_CLIENT_ID: ' id ', TRANSPORTE_CLIENT_SECRET: 'sec', PORT: '3000' });
    assert.deepEqual(c.credentials, { clientId: 'id', clientSecret: 'sec' });
    assert.equal(c.port, 3000);
  });
});

describe('fuentes mixtas', () => {
  it('Ecobici en vivo y colectivos/subte en demo', async () => {
    const demo = new DemoSource();
    const liveBikes = { mode: 'live' as const, bikeStations: () => demo.bikeStations() };
    const server = createServer(createHandler({ transit: demo, bikes: liveBikes }));
    await new Promise<void>((resolve) => server.listen(0, resolve));
    const { port } = server.address() as AddressInfo;
    try {
      const get = (p: string) => fetch(`http://127.0.0.1:${port}${p}`).then((r) => r.json() as Promise<Record<string, any>>);
      assert.equal((await get('/v1/ecobici/stations')).mode, 'live');
      assert.equal((await get('/v1/buses?line=60')).mode, 'demo');
      assert.deepEqual((await get('/health')).modes, { transit: 'demo', bikes: 'live' });
    } finally {
      server.close();
    }
  });
});

describe('loadConfig: Ecobici', () => {
  it('por defecto usa el feed GBFS público', () => {
    const c = loadConfig({});
    assert.equal(c.ecobici.source, 'live');
    assert.match(c.ecobici.discoveryUrl, /publicbikesystem\.net\/.*gbfs\.json$/);
  });

  it('ECOBICI_SOURCE=demo y valores inválidos', () => {
    assert.equal(loadConfig({ ECOBICI_SOURCE: 'demo' }).ecobici.source, 'demo');
    assert.throws(() => loadConfig({ ECOBICI_SOURCE: 'otro' }));
  });
});

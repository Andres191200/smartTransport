import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { describe, it } from 'node:test';
import { cleanStationName, mergeBikeStations, parseVehicleTypes } from '../src/adapters/ecobici.ts';
import { GbfsClient, parseDiscovery, ttlFromResponse } from '../src/gbfs.ts';
import { EcobiciSource } from '../src/sources.ts';
import { UpstreamError } from '../src/upstream.ts';

// Respuestas reales del feed de Ecobici (GBFS 2.3), recortadas a una estación.
const fixture = (name: string): unknown =>
  JSON.parse(readFileSync(new URL(`fixtures/ecobici/${name}.json`, import.meta.url), 'utf8'));

const realInfo = fixture('station_information');
const realStatus = fixture('station_status');
const realTypes = fixture('vehicle_types');
const realDiscovery = fixture('gbfs');

/** Arma un station_status GBFS 2.3 de una estación, con el formato del feed real. */
function statusOf(station: Record<string, unknown>) {
  return {
    ttl: 10,
    version: '2.3',
    data: {
      stations: [{
        station_id: '2', num_bikes_available: 0, num_docks_available: 0,
        is_installed: true, is_renting: true, is_returning: true, last_reported: 1794765200,
        ...station,
      }],
    },
  };
}

describe('Ecobici: adaptador GBFS', () => {
  it('lee la respuesta real del feed', () => {
    assert.deepEqual(mergeBikeStations(realInfo, realStatus, realTypes), [{
      id: '2',
      name: 'Retiro I',
      address: 'AV. Dr. José María Ramos Mejía 1300',
      lat: -34.59242413,
      lon: -58.37470988999999,
      capacity: 40,
      bikes: 3,
      ebikes: 0,
      docks: 34,
      operational: true,
      acceptsReturns: true,
    }]);
  });

  it('vehicle_types: eléctrico = propulsión no humana; bici = bicycle/cargo_bicycle', () => {
    const types = parseVehicleTypes(realTypes);
    assert.deepEqual(types.get('FIT'), { isBicycle: true, isElectric: false });
    assert.deepEqual(types.get('EFIT'), { isBicycle: true, isElectric: true });
    assert.deepEqual(types.get('BOOST'), { isBicycle: true, isElectric: true });
    assert.deepEqual(types.get('CHLOE'), { isBicycle: false, isElectric: true }); // monopatín
  });

  it('cuenta eléctricas y excluye monopatines', () => {
    const status = statusOf({
      num_bikes_available: 9,
      vehicle_types_available: [
        { vehicle_type_id: 'FIT', count: 3 },
        { vehicle_type_id: 'EFIT', count: 2 },
        { vehicle_type_id: 'BOOST', count: 1 },
        { vehicle_type_id: 'CHLOE', count: 3 },
      ],
    });
    const [s] = mergeBikeStations(realInfo, status, realTypes);
    assert.equal(s?.bikes, 6);
    assert.equal(s?.ebikes, 3);
  });

  it('sin vehicle_types.json todas son bicis mecánicas (regla de la spec)', () => {
    const status = statusOf({ num_bikes_available: 5, vehicle_types_available: [{ vehicle_type_id: 'EFIT', count: 5 }] });
    const [s] = mergeBikeStations(realInfo, status);
    assert.equal(s?.bikes, 5);
    assert.equal(s?.ebikes, 0);
  });

  it('un tipo que no figura en vehicle_types.json cuenta como bici mecánica', () => {
    const status = statusOf({ num_bikes_available: 2, vehicle_types_available: [{ vehicle_type_id: 'NUEVO', count: 2 }] });
    const [s] = mergeBikeStations(realInfo, status, realTypes);
    assert.equal(s?.bikes, 2);
    assert.equal(s?.ebikes, 0);
  });

  it('operativa = instalada y prestando; devoluciones = is_returning', () => {
    const notRenting = mergeBikeStations(realInfo, statusOf({ is_renting: false }), realTypes)[0];
    assert.equal(notRenting?.operational, false);
    assert.equal(notRenting?.acceptsReturns, true);

    const notReturning = mergeBikeStations(realInfo, statusOf({ is_returning: false }), realTypes)[0];
    assert.equal(notReturning?.operational, true);
    assert.equal(notReturning?.acceptsReturns, false);

    const uninstalled = mergeBikeStations(realInfo, statusOf({ is_installed: false }), realTypes)[0];
    assert.equal(uninstalled?.operational, false);
    assert.equal(uninstalled?.acceptsReturns, false);
  });

  it('el campo "status" (extensión del operador, fuera de la spec) no decide nada', () => {
    const [s] = mergeBikeStations(realInfo, statusOf({ status: 'END_OF_LIFE' }), realTypes);
    assert.equal(s?.operational, true);
  });

  it('estación sin estado: se muestra como no operativa', () => {
    const [s] = mergeBikeStations(realInfo, { data: { stations: [] } }, realTypes);
    assert.equal(s?.operational, false);
    assert.equal(s?.bikes, 0);
  });

  it('acepta el formato 1.x de la API del GCBA (0/1 y num_bikes_available_types)', () => {
    const status = { data: { stations: [{
      station_id: '2', num_bikes_available: 5, num_bikes_available_types: { mechanical: 3, ebike: 2 },
      num_docks_available: 15, is_installed: 1, is_renting: 1, is_returning: 0,
    }] } };
    const [s] = mergeBikeStations(realInfo, status);
    assert.equal(s?.bikes, 5);
    assert.equal(s?.ebikes, 2);
    assert.equal(s?.operational, true);
    assert.equal(s?.acceptsReturns, false);
  });

  it('limpia el número del nombre', () => {
    assert.equal(cleanStationName('002 - Retiro I'), 'Retiro I');
    assert.equal(cleanStationName('Retiro'), 'Retiro');
  });
});

describe('GBFS: gbfs.json y ttl', () => {
  it('toma los feeds del idioma pedido', () => {
    const urls = parseDiscovery(realDiscovery, 'es');
    assert.equal(urls.get('station_status'), 'https://buenosaires.publicbikesystem.net/customer/gbfs/v2/es/station_status');
    assert.ok(urls.has('vehicle_types'));
  });

  it('si el idioma no existe usa el primero', () => {
    const urls = parseDiscovery({ data: { en: { feeds: [{ name: 'station_status', url: 'u-en' }] } } }, 'es');
    assert.equal(urls.get('station_status'), 'u-en');
  });

  it('acepta feeds directo en data (GBFS 1.0)', () => {
    assert.equal(parseDiscovery({ data: { feeds: [{ name: 'a', url: 'u' }] } }, 'es').get('a'), 'u');
  });

  it('gbfs.json inválido es UpstreamError', () => {
    assert.throws(() => parseDiscovery({}, 'es'), UpstreamError);
    assert.throws(() => parseDiscovery({ data: { es: { feeds: [] } } }, 'es'), UpstreamError);
  });

  it('ttl: respeta el valor del feed dentro de 10 s y 1 h', () => {
    assert.equal(ttlFromResponse({ ttl: 30 }), 30_000);
    assert.equal(ttlFromResponse({ ttl: 0 }), 10_000);
    assert.equal(ttlFromResponse({}), 10_000);
    assert.equal(ttlFromResponse({ ttl: 86_400 }), 3_600_000);
  });
});

describe('GbfsClient + EcobiciSource', () => {
  /** fetch falso: sirve las respuestas reales y registra qué URLs se pidieron. */
  function fakeFetch(overrides: Record<string, unknown> = {}) {
    const calls: string[] = [];
    const base = 'https://buenosaires.publicbikesystem.net/customer/gbfs/v2';
    const responses: Record<string, unknown> = {
      [`${base}/gbfs.json`]: realDiscovery,
      [`${base}/es/station_information`]: realInfo,
      [`${base}/es/station_status`]: realStatus,
      [`${base}/es/vehicle_types`]: realTypes,
      ...overrides,
    };
    const impl = (async (input: string | URL | Request) => {
      const url = String(input);
      calls.push(url);
      const body = responses[url];
      return body === undefined ? new Response('not found', { status: 404 }) : Response.json(body);
    }) as typeof fetch;
    return { impl, calls, discoveryUrl: `${base}/gbfs.json`, base };
  }

  it('descubre los feeds, los une y cachea según el ttl', async () => {
    const f = fakeFetch();
    const source = new EcobiciSource(new GbfsClient({ discoveryUrl: f.discoveryUrl, fetch: f.impl }));

    const stations = await source.bikeStations();
    assert.equal(stations.length, 1);
    assert.equal(stations[0]?.name, 'Retiro I');
    assert.equal(f.calls.length, 4); // gbfs.json + 3 feeds

    await source.bikeStations();
    assert.equal(f.calls.length, 4, 'la segunda llamada sale de la caché');
  });

  it('si vehicle_types no existe, sigue funcionando', async () => {
    const f = fakeFetch();
    const discovery = structuredClone(realDiscovery) as { data: { es: { feeds: { name: string }[] } } };
    discovery.data.es.feeds = discovery.data.es.feeds.filter((x) => x.name !== 'vehicle_types');
    const g = fakeFetch({ [f.discoveryUrl]: discovery });
    const source = new EcobiciSource(new GbfsClient({ discoveryUrl: g.discoveryUrl, fetch: g.impl }));
    const [s] = await source.bikeStations();
    assert.equal(s?.bikes, 3);
  });

  it('un error del feed obligatorio se propaga como UpstreamError', async () => {
    const f = fakeFetch();
    const g = fakeFetch({ [`${f.base}/es/station_status`]: undefined });
    const source = new EcobiciSource(new GbfsClient({ discoveryUrl: g.discoveryUrl, fetch: g.impl }));
    await assert.rejects(source.bikeStations(), UpstreamError);
  });
});

import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { strToU8, zipSync } from 'fflate';
import { buildBusLines } from '../src/adapters/bus-lines.ts';
import { branchLine, filterBuses, matchesLine, parseBusPositions } from '../src/adapters/buses.ts';
import { parseCsv, readGtfsZip } from '../src/adapters/gtfs.ts';
import {
  arrivalsForStation,
  buildSubwayLines,
  parseServiceAlerts,
  parseSubwayForecast,
  stationKey,
} from '../src/adapters/subway.ts';

describe('parseCsv', () => {
  it('maneja BOM, CRLF, comillas y comas dentro de campos', () => {
    const rows = parseCsv('﻿stop_id,stop_name\r\n1,"Perú, Av. de Mayo"\r\n2,"Dice ""hola"""\r\n');
    assert.deepEqual(rows, [
      { stop_id: '1', stop_name: 'Perú, Av. de Mayo' },
      { stop_id: '2', stop_name: 'Dice "hola"' },
    ]);
  });

  it('completa con vacío las columnas faltantes', () => {
    assert.deepEqual(parseCsv('a,b,c\n1,2'), [{ a: '1', b: '2', c: '' }]);
  });
});

describe('colectivos', () => {
  const raw = [
    { id: '8217', latitude: -34.6, longitude: -58.4, route_short_name: '60A', trip_headsign: 'Escobar', speed: 5.5, timestamp: 1700000000, direction: 1, agency_name: 'MONSA' },
    { id: '9', latitude: '-34.61', longitude: '-58.41', route_short_name: 152 },
    { id: 'sin-coords', latitude: 0, longitude: 0, route_short_name: '29' },
    { id: 'sin-linea', latitude: -34.6, longitude: -58.4 },
  ];

  it('normaliza filas y descarta las inválidas', () => {
    const buses = parseBusPositions(raw);
    assert.equal(buses.length, 2);
    assert.deepEqual(buses[0], {
      id: '8217', lat: -34.6, lon: -58.4, line: '60A', headsign: 'Escobar', agency: 'MONSA',
      directionId: 1, speedMps: 5.5, timestamp: 1700000000,
    });
    assert.deepEqual(buses[1], { id: '9', lat: -34.61, lon: -58.41, line: '152' });
  });

  it('acepta el array envuelto en { data }', () => {
    assert.equal(parseBusPositions({ data: raw }).length, 2);
  });

  it('matchesLine: "60" incluye ramales con letra pero no otras líneas', () => {
    assert.ok(matchesLine('60', '60'));
    assert.ok(matchesLine('60A', '60'));
    assert.ok(matchesLine('60a', '60A'));
    assert.ok(!matchesLine('160', '60'));
    assert.ok(!matchesLine('600', '60'));
  });

  it('filterBuses aplica zona, línea y límite', () => {
    const buses = parseBusPositions(raw);
    const box = { minLat: -34.605, minLon: -58.405, maxLat: -34.595, maxLon: -58.395 };
    assert.deepEqual(filterBuses(buses, { box, limit: 10 }).vehicles.map((b) => b.id), ['8217']);
    assert.deepEqual(filterBuses(buses, { lines: ['152'], limit: 10 }).vehicles.map((b) => b.id), ['9']);
    assert.deepEqual(filterBuses(buses, { limit: 1 }), { vehicles: [buses[0]], truncated: true });
  });

  it('filterBuses con varias Líneas incluye todos sus Ramales', () => {
    const buses = parseBusPositions([
      { id: 'a', latitude: -34.6, longitude: -58.4, route_short_name: '60A' },
      { id: 'b', latitude: -34.6, longitude: -58.4, route_short_name: '60B' },
      { id: 'c', latitude: -34.6, longitude: -58.4, route_short_name: '152' },
      { id: 'd', latitude: -34.6, longitude: -58.4, route_short_name: '160' },
      { id: 'e', latitude: -34.6, longitude: -58.4, route_short_name: '29' },
    ]);
    const ids = filterBuses(buses, { lines: ['60', '152'], limit: 10 }).vehicles.map((b) => b.id);
    assert.deepEqual(ids, ['a', 'b', 'c']);
  });

  it('branchLine: la Línea de un Ramal es su número sin el sufijo de letras', () => {
    assert.equal(branchLine('60A'), '60');
    assert.equal(branchLine('60'), '60');
    assert.equal(branchLine('152ab'), '152');
    // Sin número no hay sufijo que sacar.
    assert.equal(branchLine('MB'), 'MB');
    // Misma regla que el filtro: todo Ramal coincide con su Línea.
    for (const branch of ['60A', '152', '39B', 'MB']) assert.ok(matchesLine(branch, branchLine(branch)));
  });
});

describe('colectivos: GTFS estático (catálogo de Líneas)', () => {
  const files = {
    'routes.txt': [
      'route_id,agency_id,route_short_name,route_long_name,route_type',
      'r60a,1,60A,,3',
      'r60b,1,60B,,3',
      'r160,2,160,,3',
      'r152,3,152,,3',
      // Mismo Ramal con otro route_id (p. ej. otra empresa o variante): se junta con el 60A.
      'r60a2,1,60A,,3',
      'sin-nombre,4,,Algo,3',
    ].join('\n'),
    'trips.txt': [
      'route_id,service_id,trip_id,trip_headsign,direction_id,shape_id',
      // 60A: ida (0) hacia Escobar por sh60a, vuelta (1) hacia Constitución.
      'r60a,S,t1,Escobar,0,sh60a',
      'r60a,S,t2,Escobar,0,sh60a',
      'r60a2,S,t3,Escobar,0,sh60a-corto',
      'r60a,S,t4,Constitución,1,sh60a-vuelta',
      // 60B: sin headsign ni vuelta; las Terminales salen de la parada más cercana a cada punta.
      'r60b,S,t5,,0,sh60b',
      'r160,S,t6,Pompeya,0,sh160',
      'r160,S,t7,Retiro,1,sh160-vuelta',
      // 152: sin recorrido en shapes.txt.
      'r152,S,t8,Olivos,0,',
      'r152,S,t9,La Boca,1,',
    ].join('\n'),
    'shapes.txt': [
      'shape_id,shape_pt_lat,shape_pt_lon,shape_pt_sequence',
      'sh60a,-34.50,-58.60,3',
      'sh60a,-34.62,-58.38,1',
      'sh60a,-34.58,-58.42,2',
      'sh60a-corto,-34.62,-58.38,1',
      'sh60a-corto,-34.60,-58.40,2',
      'sh60a-vuelta,-34.50,-58.60,1',
      'sh60a-vuelta,-34.62,-58.38,2',
      'sh60b,-34.6201,-58.3801,1',
      'sh60b,-34.4301,-58.5701,2',
      'sh160,-34.64,-58.41,1',
      'sh160,-34.59,-58.37,2',
    ].join('\n'),
    'stops.txt': [
      'stop_id,stop_name,stop_lat,stop_lon',
      's1,Constitución,-34.6200,-58.3800',
      's2,Tigre,-34.4300,-58.5700',
      's3,Palermo,-34.5800,-58.4200',
    ].join('\n'),
  };

  it('agrupa los Ramales en Líneas con la regla del filtro y ordena por número', () => {
    const lines = buildBusLines(files);
    assert.deepEqual(lines.map((l) => l.id), ['60', '152', '160']);
    assert.deepEqual(lines[0]?.branches.map((b) => b.id), ['60A', '60B']);
  });

  it('las Terminales salen de los trip_headsign: de la vuelta a la ida', () => {
    const [sixty] = buildBusLines(files);
    assert.deepEqual(sixty?.branches[0]?.terminals, ['Constitución', 'Escobar']);
  });

  it('sin trip_headsign, las Terminales son las paradas más cercanas a las puntas del Recorrido', () => {
    const [sixty] = buildBusLines(files);
    assert.deepEqual(sixty?.branches[1]?.terminals, ['Constitución', 'Tigre']);
  });

  it('el Recorrido es el shape más usado por la ida, en orden de secuencia', () => {
    const [sixty] = buildBusLines(files);
    assert.deepEqual(sixty?.branches[0]?.path, [[-34.62, -58.38], [-34.58, -58.42], [-34.5, -58.6]]);
  });

  it('un Ramal sin shapes queda sin Recorrido pero con sus Terminales', () => {
    const line152 = buildBusLines(files).find((l) => l.id === '152');
    assert.deepEqual(line152?.branches, [{ id: '152', terminals: ['La Boca', 'Olivos'], path: [] }]);
  });

  it('se arma igual leyendo el zip del feed', () => {
    const zip = zipSync(Object.fromEntries(Object.entries(files).map(([name, text]) => [`gtfs/${name}`, strToU8(text)])));
    const lines = buildBusLines(readGtfsZip(zip, Object.keys(files)));
    assert.deepEqual(lines.map((l) => l.id), ['60', '152', '160']);
  });
});

describe('subte: GTFS estático', () => {
  const files = {
    'routes.txt': 'route_id,agency_id,route_short_name,route_long_name,route_type,route_color,route_text_color\nLineaA,1,A,Línea A,1,18CCF5,FFFFFF\n',
    'stops.txt': [
      'stop_id,stop_name,stop_lat,stop_lon,location_type,parent_station',
      '1076,Plaza de Mayo,-34.6088,-58.3709,1,',
      '1076N,Plaza de Mayo,-34.60881,-58.37091,0,1076',
      '1077N,Perú,-34.6086,-58.3742,0,',
      '1078N,Piedras,-34.6089,-58.3792,0,',
    ].join('\n'),
    'trips.txt': 'route_id,service_id,trip_id,direction_id,shape_id\nLineaA,S,corto,0,\nLineaA,S,largo,1,\n',
    'stop_times.txt': [
      'trip_id,arrival_time,departure_time,stop_id,stop_sequence',
      'corto,10:00:00,10:00:00,1076N,1',
      'largo,10:00:00,10:00:00,1078N,1',
      'largo,10:01:00,10:01:00,1077N,2',
      'largo,10:02:00,10:02:00,1076N,3',
    ].join('\n'),
  };

  it('usa el viaje con más paradas y resuelve andenes a su estación', () => {
    const [line] = buildSubwayLines(files);
    assert.equal(line?.name, 'A');
    assert.equal(line?.color, '18CCF5');
    assert.deepEqual(line?.stations.map((s) => s.name), ['Piedras', 'Perú', 'Plaza de Mayo']);
    assert.deepEqual(line?.stations[2], { id: 'LineaA:plaza-de-mayo', name: 'Plaza de Mayo', lat: -34.6088, lon: -58.3709 });
    // Sin shapes.txt, el recorrido une las estaciones.
    assert.equal(line?.path.length, 3);
  });

  it('prefiere shapes.txt si existe', () => {
    const withShape = {
      ...files,
      'trips.txt': 'route_id,service_id,trip_id,direction_id,shape_id\nLineaA,S,largo,1,sh1\n',
      'shapes.txt': 'shape_id,shape_pt_lat,shape_pt_lon,shape_pt_sequence\nsh1,-34.2,-58.2,2\nsh1,-34.1,-58.1,1\n',
    };
    assert.deepEqual(buildSubwayLines(withShape)[0]?.path, [[-34.1, -58.1], [-34.2, -58.2]]);
  });

  it('lee el zip aunque los .txt estén dentro de una carpeta', () => {
    const zip = zipSync({ 'feed/routes.txt': strToU8('a\n1'), 'feed/otro.txt': strToU8('x') });
    assert.deepEqual(readGtfsZip(zip, ['routes.txt']), { 'routes.txt': 'a\n1' });
  });
});

describe('subte: tiempo real', () => {
  const forecast = {
    Header: { timestamp: 1700000000 },
    Entity: [{
      ID: 'LineaA_A01',
      Linea: {
        Trip_Id: 'A01', Route_Id: 'LineaA', Direction_ID: 1,
        Estaciones: [
          { stop_id: '1078N', stop_name: 'Piedras', arrival: { time: 1700000060, delay: 0 }, departure: { time: 1700000080, delay: 0 } },
          { stop_id: '1077N', stop_name: 'Perú', arrival: { time: 1700000150, delay: 30 } },
          { stop_id: '1076N', stop_name: 'Plaza de Mayo', arrival: { time: 0 }, departure: { time: 1700000250 } },
        ],
      },
    }],
  };

  it('convierte el formato propio del GCBA', () => {
    const { updatedAt, arrivals } = parseSubwayForecast(forecast);
    assert.equal(updatedAt, 1700000000);
    assert.equal(arrivals.length, 3);
    assert.deepEqual(arrivals[1], {
      stationId: 'LineaA:peru', lineId: 'LineaA', tripId: 'A01', directionId: 1,
      destination: 'Plaza de Mayo', arrivalTime: 1700000150, delaySeconds: 30,
    });
    // Sin hora de llegada usa la de salida.
    assert.equal(arrivals[2]?.arrivalTime, 1700000250);
  });

  it('la clave de estación coincide entre GTFS estático y tiempo real', () => {
    assert.equal(stationKey('LineaA', 'Perú'), 'LineaA:peru');
    assert.equal(stationKey('LineaA', 'Sáenz Peña'), 'LineaA:saenz-pena');
  });

  it('arrivalsForStation filtra, ordena y limita por sentido', () => {
    const mk = (time: number, destination: string) => ({
      stationId: 's', lineId: 'L', tripId: String(time), directionId: 0, destination, arrivalTime: time, delaySeconds: 0,
    });
    const all = [mk(500, 'X'), mk(100, 'X'), mk(50, 'X'), mk(300, 'X'), mk(400, 'X'), mk(200, 'Y'), { ...mk(150, 'X'), stationId: 'otra' }];
    const result = arrivalsForStation(all, 's', 120, 3);
    assert.deepEqual(result.map((a) => a.arrivalTime), [100, 200, 300, 400]);
  });

  it('convierte alertas GTFS-RT (con y sin "translation")', () => {
    const alerts = parseServiceAlerts({
      header: { timestamp: 1 },
      entity: [
        { id: 'a1', alert: {
          active_period: [{ start: 10, end: 20 }],
          informed_entity: [{ route_id: 'LineaA' }, { route_id: 'LineaA' }, { route_id: 'LineaB' }],
          header_text: { translation: [{ text: 'Linea A: demoras', language: 'es' }] },
          description_text: { translation: [{ text: 'Por obras', language: 'es' }] },
        } },
        // Forma del ejemplo de la documentación: la alerta va directo en la entidad.
        { header_text: [{ text: 'Servicio con demoras - 60', language: 'es' }] },
        { id: 'vacía', alert: {} },
      ],
    });
    assert.deepEqual(alerts, [
      { id: 'a1', title: 'Linea A: demoras', description: 'Por obras', lineIds: ['LineaA', 'LineaB'], activeFrom: 10, activeUntil: 20 },
      { id: 'alert-1', title: 'Servicio con demoras - 60', lineIds: [] },
    ]);
  });
});

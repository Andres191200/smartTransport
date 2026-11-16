import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { strToU8, zipSync } from 'fflate';
import { filterBuses, matchesLine, parseBusPositions } from '../src/adapters/buses.ts';
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
    assert.deepEqual(filterBuses(buses, { line: '152', limit: 10 }).vehicles.map((b) => b.id), ['9']);
    assert.deepEqual(filterBuses(buses, { limit: 1 }), { vehicles: [buses[0]], truncated: true });
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

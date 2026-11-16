import { createServer } from 'node:http';
import { createHandler } from './app.ts';
import { loadConfig } from './config.ts';
import { DemoSource } from './demo.ts';
import { GbfsClient } from './gbfs.ts';
import { EcobiciSource, LiveSource, type BikeSource, type TransitSource } from './sources.ts';
import { TransporteClient } from './upstream.ts';

const config = loadConfig();
const demo = new DemoSource();

const transit: TransitSource = config.credentials
  ? new LiveSource(new TransporteClient({ baseUrl: config.upstreamBaseUrl, ...config.credentials }))
  : demo;

const bikes: BikeSource =
  config.ecobici.source === 'live'
    ? new EcobiciSource(new GbfsClient({ discoveryUrl: config.ecobici.discoveryUrl }))
    : demo;

const server = createServer(createHandler({ transit, bikes }));

server.listen(config.port, () => {
  console.log(`Smart Transport backend escuchando en http://localhost:${config.port}`);
  console.log(
    transit.mode === 'live'
      ? '  Colectivos y subte: API Transporte del GCBA.'
      : '  Colectivos y subte: MODO DEMO (faltan TRANSPORTE_CLIENT_ID / TRANSPORTE_CLIENT_SECRET en el .env).',
  );
  console.log(
    bikes.mode === 'live'
      ? `  Ecobici: feed GBFS público (${config.ecobici.discoveryUrl}).`
      : '  Ecobici: MODO DEMO (ECOBICI_SOURCE=demo).',
  );
});

for (const signal of ['SIGINT', 'SIGTERM'] as const) {
  process.on(signal, () => server.close(() => process.exit(0)));
}

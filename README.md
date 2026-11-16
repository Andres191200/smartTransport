# Smart Transport

Mapa en tiempo real de colectivos, subte y Ecobici de la Ciudad de Buenos Aires.

| Capa | Fuente | ¿Credenciales? |
|---|---|---|
| Colectivos y subte | [API Transporte del GCBA](https://api-transporte.buenosaires.gob.ar/) | Sí (`client_id` / `client_secret`) |
| Ecobici | [Feed GBFS público](https://buenosaires.publicbikesystem.net/customer/gbfs/v2/gbfs.json) del operador ([spec GBFS 2.3](https://github.com/MobilityData/gbfs/blob/v2.3/gbfs.md)) | No |

```
App Flutter (app/)  ──►  Backend Node (backend/)  ──►  apitransporte.buenosaires.gob.ar
   sin credenciales        guarda client_id/secret,   └► buenosaires.publicbikesystem.net (GBFS)
                           cachea y simplifica
```

La app nunca ve las credenciales: solo habla con el backend.

## Backend

Requiere Node 22.18 o superior (corre TypeScript directo, sin paso de compilación).

```bash
cd backend
npm install
cp .env.example .env      # completar TRANSPORTE_CLIENT_ID y TRANSPORTE_CLIENT_SECRET
npm run check-api         # verifica credenciales y que los datos reales se entienden
npm run dev               # http://localhost:8080
```

**Sin credenciales, colectivos y subte arrancan en modo demo** (datos simulados), así que se
puede desarrollar la app antes de tenerlas. **Ecobici siempre usa datos reales** del feed GBFS
(cacheado según el `ttl` que informa el feed); con `ECOBICI_SOURCE=demo` se simula, para
trabajar sin internet. `npm run check-api` verifica Ecobici aunque no haya credenciales.

| Endpoint | Devuelve |
|---|---|
| `GET /v1/buses?bbox=minLat,minLon,maxLat,maxLon` | Colectivos en la zona (máx. 600) |
| `GET /v1/buses?line=60` | Todos los colectivos de una línea (incluye ramales 60A, 60B…) |
| `GET /v1/subway/lines` | Líneas de subte con color, recorrido y estaciones |
| `GET /v1/subway/arrivals?station=<id>` | Próximos trenes en una estación (id de `/lines`) |
| `GET /v1/subway/alerts` | Avisos de servicio del subte |
| `GET /v1/ecobici/stations` | Estaciones con bicis (y cuántas eléctricas), anclajes libres, si presta y si recibe devoluciones |

Cada respuesta trae `"mode": "live"` o `"demo"` según su fuente; `GET /health` informa ambas.

Tests: `npm test` · Tipos: `npm run typecheck`

## App (Flutter)

Requiere el [SDK de Flutter](https://docs.flutter.dev/get-started/install/linux/android)
y Android Studio (para el SDK de Android y el emulador).

```bash
cd app
flutter pub get
flutter run                                              # emulador: usa http://10.0.2.2:8080
flutter run --dart-define=API_BASE_URL=http://192.168.0.10:8080   # celular real en tu red
```

Tests: `flutter test` · Análisis: `flutter analyze`

## Antes de publicar en Play Store

- **Alojar el backend con HTTPS** (Render, Fly.io, Railway…) y compilar con
  `--dart-define=API_BASE_URL=https://tu-backend`. En release, Android bloquea `http://`.
- **Cambiar el proveedor de mapas.** Los tiles de openstreetmap.org no se pueden usar en apps
  con mucho tráfico. Usá uno con plan para apps y pasalo con
  `--dart-define=TILE_URL=...` y `--dart-define=TILE_ATTRIBUTION=...`.
- **Elegir el `applicationId` definitivo** (`com.smarttransport.smart_transport` en
  `app/android/app/build.gradle.kts`): no se puede cambiar después de publicar.
- Ícono, firma de la app y política de privacidad (la app usa la ubicación).
- **Licencia del feed de Ecobici:** su `system_information` no declara `license_id` ni
  `license_url` (la spec GBFS lo recomienda). Antes de publicar, confirmar con el GCBA u operador
  las condiciones de uso.

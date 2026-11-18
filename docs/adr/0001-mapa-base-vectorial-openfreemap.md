# 0001. Mapa base vectorial de OpenFreeMap con vector_map_tiles

- Estado: aceptada
- Fecha: 2026-11-16

## Contexto

El mapa es el fondo de toda la app y tiene que ser simple: calles y manzanas, sin comercios ni
íconos que compitan con los colectivos, el subte y las estaciones de Ecobici.

La app usaba los tiles raster de openstreetmap.org, que tienen dos problemas:

- Son muy cargados visualmente.
- Su [política de uso](https://operations.osmfoundation.org/policies/tiles/) no permite apps con
  mucho tráfico, así que no sirven para publicar en Play Store.

Alternativas evaluadas:

- **Tiles raster minimalistas** (CARTO Positron, Stadia Alidade Smooth, MapTiler). CARTO ahora
  exige clave: sin ella, cada tile es una imagen que dice "API KEY REQUIRED". Los demás piden
  clave, y sus planes gratis no cubren uso comercial o tienen límites bajos.
- **Tiles vectoriales de [OpenFreeMap](https://openfreemap.org/) con `vector_map_tiles`**,
  sobre el `flutter_map` que ya usa la app.
- **Cambiar a MapLibre (`maplibre_gl`)**: es más maduro con tiles vectoriales, pero obliga a
  rehacer la pantalla del mapa y los marcadores.

## Decisión

Usar los tiles vectoriales de OpenFreeMap con `vector_map_tiles`:

- Estilo **Positron** en tema claro y **Dark** en tema oscuro.
- Las URLs de los estilos y la atribución se pueden cambiar con `--dart-define`, sin tocar código:
  `MAP_STYLE_LIGHT`, `MAP_STYLE_DARK` y `MAP_ATTRIBUTION`.

Se eligió con un prototipo de cuatro variantes probado en un celular real: OSM raster, Positron,
"minimal" (solo calles y manzanas) y minimal con nombres de calles. Ganó Positron tal como viene.
El prototipo quedó en la rama `prototype/mapa-vectorial`.

## Consecuencias

- **Sin costo ni clave.** OpenFreeMap permite uso comercial, sin límites de vistas ni registro.
- **Atribución obligatoria:** "OpenFreeMap © OpenMapTiles © OpenStreetMap contributors". Se
  muestra en el mapa.
- **No tiene SLA.** Si OpenFreeMap se cae o cambia sus condiciones, se puede autoalojar (es open
  source) o apuntar los estilos a otro proveedor compatible, por ejemplo MapTiler o Stadia con
  clave, sin cambiar código.
- **Dependencia beta.** La única versión de `vector_map_tiles` compatible con `flutter_map` 8 es
  `9.0.0-beta.13`; la última estable (8.0.0) requiere `flutter_map` 7. Queda fijada a esa versión
  exacta. Si la beta da problemas de rendimiento o de memoria en producción, el plan B es
  `maplibre_gl` con los mismos estilos de OpenFreeMap.
- **Más trabajo para el celular** que con raster: los tiles se dibujan en el dispositivo. La
  librería los convierte en imágenes y los cachea.

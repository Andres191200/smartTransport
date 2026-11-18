# 0002. El mapa muestra solo Mis líneas

- Estado: aceptada
- Fecha: 2026-11-17

Para Colectivo y Subte, el mapa muestra únicamente las Líneas que el usuario agregó a Mis líneas,
en cualquier parte de la ciudad, y no todo el transporte que pasa por la zona visible. Un usuario
sin Líneas ve el mapa vacío, con una invitación a agregarlas. Ecobici es aparte: se prende o se
apaga y, prendida, muestra todas las estaciones.

La única excepción es la vista previa: al buscar una Línea que no está en Mis líneas, mientras su
ficha está abierta el mapa dibuja su Recorrido y sus Terminales, sin los vehículos en vivo. Al
cerrar la ficha, el Recorrido desaparece. Sirve para decidir si agregarla, sin que el mapa muestre
en vivo nada que el usuario no eligió.

Así la app es personal y el mapa queda limpio, en línea con el mapa base minimalista
([ADR 0001](0001-mapa-base-vectorial-openfreemap.md)). Tampoco hay que cortar los colectivos por
zoom ni por cantidad, como pasaba al mostrar todos los de la zona.

## Considered Options

- **Todo el transporte de la zona, con Mis líneas como filtros rápidos.** Es lo habitual en apps
  de transporte, y era lo que hacía la app hasta ahora. Se descartó porque el usuario quiere ver
  solo lo que usa, y porque el mapa se llena de marcadores.
- **Mostrar en vivo una Línea buscada sin agregarla** (con sus vehículos, como si estuviera en Mis
  líneas). Se descartó: en el mapa no aparece en vivo nada que el usuario no haya elegido. Se
  adoptó en su lugar la vista previa del Recorrido.
- **Ocultar Líneas de Mis líneas sin eliminarlas.** Se descartó: las Líneas de Mis líneas se ven
  siempre; el botón de cada Línea abre su ficha, y quien no quiere verla la elimina.

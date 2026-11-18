# Smart Transport

App de mapa en tiempo real del transporte público de la Ciudad de Buenos Aires: colectivos, subte y Ecobici.

## Language

### Transporte

**Medio**:
Cada tipo de transporte que muestra la app: Colectivo, Subte o Ecobici.
_Avoid_: Modo, tipo de transporte, servicio

**Línea**:
Un servicio de Colectivo (p. ej. el 60) o de Subte (p. ej. la D, o el Premetro). Una Línea de Colectivo incluye todos sus Ramales. Ecobici no tiene líneas: tiene estaciones fijas.
_Avoid_: Ruta

**Recorrido**:
El trazado de una Línea sobre el mapa, de una Terminal a la otra. Cada Ramal tiene su propio Recorrido.
_Avoid_: Ruta, trayecto, traza

**Terminal**:
Cada uno de los dos extremos de un Recorrido, donde empieza y termina el servicio (p. ej. Plaza de Mayo y San Pedrito en la línea A).
_Avoid_: Cabecera, punta de línea

**Ramal**:
Variante de Recorrido de una Línea de Colectivo, identificada con una letra (60A, 60B). El usuario elige Líneas, no Ramales.
_Avoid_: Sublínea, variante

### Usuario

**Mis líneas**:
Las Líneas que el usuario eligió seguir; son las únicas de Colectivo y Subte que el mapa muestra. Se guardan en su dispositivo y se agrupan por Medio: un Medio que el usuario eligió, o al que le agregó una Línea, mantiene su grupo aunque se quede sin Líneas.
_Avoid_: Favoritas, líneas guardadas, suscripciones

**Onboarding**:
Las pantallas que se muestran solo la primera vez que se abre la app, donde el usuario elige sus Medios y sus Mis líneas.
_Avoid_: Tutorial, bienvenida, setup

#!/usr/bin/env bash
# Mide qué tan fluido se mueve el mapa en el celular conectado por USB: abre el mapa con el mapa
# base real y datos fijos (sin backend), arrastra y hace zoom siempre igual, e imprime el resumen
# de cuadros. Los resultados crudos quedan en app/mediciones/ (ignorada por git).
#
#   app/tool/fluidez.sh
#
# Siempre en modo profile y en un teléfono real: en debug o en el emulador los números no dicen
# nada. El teléfono necesita internet (para el mapa base) y la pantalla encendida y desbloqueada.
set -euo pipefail

adb=$(command -v adb || echo "${ANDROID_HOME:-$HOME/Android/Sdk}/platform-tools/adb")
serial=$("$adb" devices | awk 'NR > 1 && $2 == "device" { print $1; exit }')
if [[ -z "$serial" ]]; then
  echo "No hay ningún teléfono conectado por USB (adb devices no muestra ninguno)." >&2
  exit 1
fi
echo "Midiendo en $("$adb" -s "$serial" shell getprop ro.product.model | tr -d '\r') ($serial)"

cd "$(dirname "$0")/.."
exec flutter drive --profile -d "$serial" \
  --driver=test_driver/fluidez_del_mapa.dart \
  --target=integration_test/fluidez_del_mapa_test.dart "$@"

#!/usr/bin/env bash
# Corre la app en un celular conectado por USB, apuntando al backend de esta PC (puerto 8080).
#
#   app/tool/telefono.sh            # debug, con hot reload
#   app/tool/telefono.sh --profile  # para juzgar la velocidad real (el mapa dibuja mucho más rápido)
#
# El "adb reverse" se pierde al desconectar el cable o reiniciar adb: por eso lo hace siempre.
# Después de cambiar la URL hay que relanzar con este script: un hot restart no la cambia.
set -euo pipefail

adb=$(command -v adb || echo "${ANDROID_HOME:-$HOME/Android/Sdk}/platform-tools/adb")
"$adb" reverse tcp:8080 tcp:8080

cd "$(dirname "$0")/.."
exec flutter run --dart-define=API_BASE_URL=http://localhost:8080 "$@"

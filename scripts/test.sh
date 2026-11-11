#!/bin/bash
# Corre las pruebas del núcleo (Swift Testing).
# Uso: ./scripts/test.sh [argumentos extra para `swift test`]
#
# Con solo las herramientas de línea de comandos (sin Xcode), SwiftPM no siempre
# encuentra el plugin de macros de Swift Testing (`@Test`, `#expect`) y falla con
# "plugin for module 'TestingMacros' not found". Si es el caso, se le indica la ruta.
set -euo pipefail
cd "$(dirname "$0")/.."

EXTRA=()
DEV_DIR="$(xcode-select -p 2>/dev/null || true)"
PLUGINS="${DEV_DIR}/usr/lib/swift/host/plugins/testing"
if [[ "${DEV_DIR}" == */CommandLineTools ]] && [ -d "${PLUGINS}" ]; then
    EXTRA=(-Xswiftc -plugin-path -Xswiftc "${PLUGINS}")
fi

swift test ${EXTRA[@]+"${EXTRA[@]}"} "$@"

#!/bin/bash
# Compila Aura y arma build/Aura.app (con el comando `aura` dentro).
# Uso: ./scripts/build.sh            → arquitectura de este Mac
#      ARCH=universal ./scripts/build.sh → Apple Silicon + Intel (requiere Xcode completo)
# Variables opcionales:
#      AURA_SWIFT_FLAGS="--disable-sandbox"  → la usa la fórmula de Homebrew
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v swift >/dev/null 2>&1; then
    echo "✗ No se encontró Swift. Instala las herramientas de línea de comandos:"
    echo "    xcode-select --install"
    exit 1
fi

ARCH="${ARCH:-$(uname -m)}"
ARCH_ARGS=()
if [ "${ARCH}" = "universal" ]; then
    ARCH_ARGS=(--arch arm64 --arch x86_64)
fi
# Homebrew compila dentro de su propio sandbox, donde el de SwiftPM no puede anidarse.
if [ -n "${AURA_SWIFT_FLAGS:-}" ]; then
    # shellcheck disable=SC2206
    ARCH_ARGS+=(${AURA_SWIFT_FLAGS})
fi

echo "→ Compilando (release, ${ARCH})…"
swift build -c release ${ARCH_ARGS[@]+"${ARCH_ARGS[@]}"}
BIN_DIR="$(swift build -c release ${ARCH_ARGS[@]+"${ARCH_ARGS[@]}"} --show-bin-path)"

APP="build/Aura.app"
echo "→ Armando ${APP}…"
rm -rf "${APP}"
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources" "${APP}/Contents/Helpers"
cp "${BIN_DIR}/Aura" "${APP}/Contents/MacOS/Aura"
cp "${BIN_DIR}/aura-cli" "${APP}/Contents/Helpers/aura"
cp Resources/Info.plist "${APP}/Contents/Info.plist"
iconutil -c icns Resources/AppIcon.iconset -o "${APP}/Contents/Resources/AppIcon.icns"
cp LICENSE "${APP}/Contents/Resources/LICENSE"

# Firma ad-hoc: obligatoria en Apple Silicon para ejecutar binarios.
echo "→ Firmando (ad-hoc)…"
codesign --force --sign - "${APP}/Contents/Helpers/aura"
codesign --force --sign - "${APP}"

echo "✓ Listo: $(pwd)/${APP}"
echo "  Instálala con ./scripts/install.sh o ábrela con: open ${APP}"

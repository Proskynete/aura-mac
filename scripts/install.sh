#!/bin/bash
# Compila (si hace falta) e instala Aura en ~/Applications y el comando `aura` en tu PATH.
# Uso: ./scripts/install.sh [--system]   (--system instala en /Applications)
set -euo pipefail
cd "$(dirname "$0")/.."

DEST_DIR="${HOME}/Applications"
if [ "${1:-}" = "--system" ]; then DEST_DIR="/Applications"; fi

if [ ! -d build/Aura.app ] || [ -n "$(find Sources Package.swift Resources -newer build/Aura.app/Contents/MacOS/Aura -print -quit 2>/dev/null)" ]; then
    ./scripts/build.sh
fi

# Cierra la versión anterior si está abierta.
if pgrep -x Aura >/dev/null; then
    echo "→ Cerrando Aura…"
    osascript -e 'tell application id "io.github.aura.macos" to quit' >/dev/null 2>&1 || pkill -x Aura || true
    sleep 1
fi

mkdir -p "${DEST_DIR}"
echo "→ Copiando a ${DEST_DIR}/Aura.app…"
rm -rf "${DEST_DIR}/Aura.app"
cp -R build/Aura.app "${DEST_DIR}/Aura.app"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "${DEST_DIR}/Aura.app" >/dev/null 2>&1 || true

# Comando `aura`: Homebrew si su carpeta es escribible; si no, ~/.local/bin.
CLI_SRC="${DEST_DIR}/Aura.app/Contents/Helpers/aura"
if [ -d /opt/homebrew/bin ] && [ -w /opt/homebrew/bin ]; then
    BIN_DIR=/opt/homebrew/bin
elif [ -d /usr/local/bin ] && [ -w /usr/local/bin ]; then
    BIN_DIR=/usr/local/bin
else
    BIN_DIR="${HOME}/.local/bin"
    mkdir -p "${BIN_DIR}"
fi
ln -sf "${CLI_SRC}" "${BIN_DIR}/aura"
echo "→ Comando instalado: ${BIN_DIR}/aura"
case ":${PATH}:" in
    *":${BIN_DIR}:"*) ;;
    *) echo "  ⚠︎ ${BIN_DIR} no está en tu PATH. Agrega a ~/.zshrc:"
       echo "      export PATH=\"${BIN_DIR}:\${PATH}\"" ;;
esac

echo "→ Abriendo Aura…"
open "${DEST_DIR}/Aura.app"
echo "✓ Aura instalada. Prueba: aura status"

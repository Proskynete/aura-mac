#!/bin/bash
# Genera el cask (Casks/aura.rb) y la fórmula (Formula/aura-macos.rb) del tap
# para una versión publicada. El workflow de release lo ejecuta solo; a mano:
#
#   ./scripts/render-homebrew.sh VERSION ZIP_SHA256 SRC_SHA256 DIRECTORIO_DEL_TAP
#
#   ZIP_SHA256  checksum de Aura-VERSION.zip (el que sube el release)
#   SRC_SHA256  checksum de archive/refs/tags/vVERSION.tar.gz (para la fórmula)
#
# Usuario y repo por defecto: los de GITHUB_REPOSITORY o Proskynete/aura-mac.
set -euo pipefail
cd "$(dirname "$0")/.."

if [ $# -ne 4 ]; then
    sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'
    exit 2
fi
VERSION="$1"; ZIP_SHA="$2"; SRC_SHA="$3"; OUT="$4"

REPO_FULL="${GITHUB_REPOSITORY:-Proskynete/aura-mac}"
USER_NAME="${REPO_FULL%%/*}"
REPO_NAME="${REPO_FULL#*/}"
# Nombre corto del tap: Proskynete/homebrew-aura → proskynete/aura
TAP="$(echo "${USER_NAME}" | tr '[:upper:]' '[:lower:]')/aura"

for sha in "${ZIP_SHA}" "${SRC_SHA}"; do
    [[ "${sha}" =~ ^[0-9a-f]{64}$ ]] || { echo "✗ Checksum inválido: ${sha}" >&2; exit 1; }
done

render() {
    sed -e "s|__USER__|${USER_NAME}|g" \
        -e "s|__REPO__|${REPO_NAME}|g" \
        -e "s|__TAP__|${TAP}|g" \
        -e "s|__VERSION__|${VERSION}|g" \
        -e "s|__ZIP_SHA256__|${ZIP_SHA}|g" \
        -e "s|__SRC_SHA256__|${SRC_SHA}|g" \
        "$1" > "$2"
}

mkdir -p "${OUT}/Casks" "${OUT}/Formula"
render homebrew/aura.rb.template "${OUT}/Casks/aura.rb"
render homebrew/aura-macos.rb.template "${OUT}/Formula/aura-macos.rb"
echo "✓ ${OUT}/Casks/aura.rb y ${OUT}/Formula/aura-macos.rb (versión ${VERSION})"

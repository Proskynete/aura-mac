#!/bin/bash
# Genera homebrew/Formula/aura-macos.rb para una versión publicada.
#
# Uso:  ./scripts/make-formula.sh 1.0.0
#       (usuario y repo por defecto: Proskynete/aura-mac; cámbialos con GH_USER y GH_REPO)
#
# Antes, en tu fork, crea y sube el tag de la versión:
#   git tag macos-v1.0.0 && git push origin macos-v1.0.0
set -euo pipefail
cd "$(dirname "$0")/.."

USER_NAME="${GH_USER:-Proskynete}"
REPO_NAME="${GH_REPO:-aura-mac}"
VERSION="${1:-}"
if [ -z "${VERSION}" ]; then
    echo "Uso: ./scripts/make-formula.sh VERSION   (ej.: ./scripts/make-formula.sh 1.0.0)"
    exit 1
fi

TAG="macos-v${VERSION}"
URL="https://github.com/${USER_NAME}/${REPO_NAME}/archive/refs/tags/${TAG}.tar.gz"

# Avisa si la versión de la app no coincide con la del tag.
PLIST_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist 2>/dev/null || echo '?')"
if [ "${PLIST_VERSION}" != "${VERSION}" ]; then
    echo "⚠︎ Resources/Info.plist dice ${PLIST_VERSION} y el tag es ${VERSION}."
    echo "  Actualiza CFBundleShortVersionString (y AuraConfig.currentVersion) si corresponde."
fi

echo "→ Calculando el checksum de ${URL}…"
if ! SHA="$(curl -fsSL "${URL}" | shasum -a 256 | awk '{print $1}')"; then
    echo "✗ No se pudo descargar. ¿Subiste el tag?"
    echo "    git tag ${TAG} && git push origin ${TAG}"
    exit 1
fi

mkdir -p homebrew/Formula
sed -e "s|__USER__|${USER_NAME}|g" \
    -e "s|__REPO__|${REPO_NAME}|g" \
    -e "s|__TAG__|${TAG}|g" \
    -e "s|__SHA256__|${SHA}|g" \
    homebrew/aura-macos.rb.template > homebrew/Formula/aura-macos.rb

echo "✓ Fórmula lista: homebrew/Formula/aura-macos.rb (sha256 ${SHA})"
echo ""
echo "Siguiente paso: cópiala a tu tap (un repo llamado homebrew-aura):"
echo "    cp homebrew/Formula/aura-macos.rb ~/Developer/homebrew-aura/Formula/"
echo "Y luego se instala con:"
echo "    brew install ${USER_NAME}/aura/aura-macos"

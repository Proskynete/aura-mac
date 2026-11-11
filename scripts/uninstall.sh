#!/bin/bash
# Desinstala Aura.
# Uso: ./scripts/uninstall.sh            → pregunta si borrar configuración y caché
#      ./scripts/uninstall.sh --purge    → las borra sin preguntar
#      ./scripts/uninstall.sh --keep     → las conserva sin preguntar
#
# Nunca se tocan los fondos descargados en ~/Pictures/Wallpapers/Aura ni
# ~/Pictures/Wallpapers/Aura/.system-frames: ahí está la imagen que macOS usa
# como fondo, así que el escritorio queda igual después de desinstalar.
set -uo pipefail

PURGE=""
case "${1:-}" in
    --purge) PURGE=yes ;;
    --keep) PURGE=no ;;
    "") ;;
    *) echo "Uso: $0 [--purge | --keep]" >&2; exit 2 ;;
esac

if [ -z "${PURGE}" ]; then
    if [ -t 0 ]; then
        echo "¿Borrar también la configuración y la caché de Aura?"
        echo "  (ajustes, favoritos, historial y miniaturas; tus fondos no se tocan)"
        read -r -p "  [s/N] " answer
        case "${answer}" in
            [sSyY]*) PURGE=yes ;;
            *) PURGE=no ;;
        esac
    else
        # Sin terminal (otro script, CI): lo seguro es conservar.
        PURGE=no
    fi
fi

osascript -e 'tell application id "io.github.aura.macos" to quit' >/dev/null 2>&1 || pkill -x Aura
sleep 1

for app in "${HOME}/Applications/Aura.app" "/Applications/Aura.app"; do
    [ -d "${app}" ] && rm -rf "${app}" && echo "→ Eliminado ${app}"
done
for bin in /opt/homebrew/bin/aura /usr/local/bin/aura "${HOME}/.local/bin/aura"; do
    [ -L "${bin}" ] && rm -f "${bin}" && echo "→ Eliminado ${bin}"
done

if [ "${PURGE}" = "yes" ]; then
    rm -rf "${HOME}/Library/Application Support/Aura" "${HOME}/Library/Caches/Aura"
    echo "→ Configuración y caché eliminadas"
else
    echo "→ Configuración conservada en ~/Library/Application Support/Aura"
fi
echo "✓ Aura desinstalada. Tus fondos siguen en ~/Pictures/Wallpapers/Aura"
echo "  El fondo de macOS queda con el último fotograma de Aura."
echo "  Para cambiarlo: Ajustes del Sistema → Fondo de pantalla."

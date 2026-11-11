# Aura para macOS

> **Fork no oficial de [antwny/aura](https://github.com/antwny/aura).** Aura fue creada por **Antwny** para Linux (COSMIC); este repositorio nació como su versión para macOS y reemplaza aquel código por una implementación nativa en Swift. El historial de git conserva el proyecto original. Todo el mérito del diseño es de su autor: si usas Linux, usa el [proyecto original](https://github.com/antwny/aura). En [`NOTICE.md`](NOTICE.md) está el detalle de qué cambió.

Port nativo para macOS de Aura, el gestor de fondos animados para el escritorio COSMIC de Pop!_OS. Está reescrito en Swift con AVFoundation, AppKit y SwiftUI. No usa Wayland, mpv ni D-Bus: cada pieza se reemplazó por su equivalente de Apple.

Las herramientas de línea de comandos de Xcode bastan para compilarlo: no necesitas Xcode completo.

## Requisitos

- macOS 14 Sonoma o superior (Apple Silicon o Intel).
- Herramientas de línea de comandos de Xcode: `xcode-select --install`. Xcode completo no es necesario.
- Opcional: `brew install ffmpeg`, solo para reproducir videos WebM, MKV o AVI.

## Instalar

### Con Homebrew

```bash
brew install Proskynete/aura/aura-macos
```

Homebrew compila la app en tu Mac, así que no hay avisos de Gatekeeper. Al terminar te muestra cómo agregarla a Launchpad y cómo hacer que se abra al iniciar sesión (`brew services start aura-macos`). Para actualizar, usa `brew upgrade aura-macos`.

### Desde el código

```bash
git clone https://github.com/Proskynete/aura-mac.git
cd aura-mac
./scripts/install.sh
```

El script compila, copia `Aura.app` a `~/Applications`, instala el comando `aura` en tu PATH y abre la app. Para instalar en `/Applications` usa `./scripts/install.sh --system`. Si solo quieres compilar, usa `./scripts/build.sh`; el resultado queda en `build/Aura.app`.

El tema automático (cambiar el modo claro/oscuro de macOS según el fondo) viene apagado. Si lo activas en Ajustes → Apariencia, macOS te pedirá una vez permiso para que Aura controle "Eventos del Sistema".

## Uso

Aura vive en la **barra de menú**. Al cerrar la ventana el fondo sigue animado y el ícono del Dock desaparece. Desde ahí tienes pausa, siguiente, anterior, volumen, rotación y el selector rápido.

- **Biblioteca:** tus fondos locales. Puedes arrastrar videos o imágenes a la ventana para importarlos. Clic para aplicar, clic derecho para elegir pantalla, favoritos o mandarlo a la papelera.
- **Explorar:** Bing UHD (con archivo histórico), Wallhaven, Minimalistic, MotionBGS y LiveWallpapers4Free, con búsqueda, categorías y resolución. Las descargas van a `~/Pictures/Wallpapers/Aura`.
- **Pantallas:** el lienzo a escala de tus monitores. Ahí eliges el fondo de cada uno y el ajuste (Ajustar, Rellenar o Estirar).
- **Selector rápido:** se abre con `⌃⌥Espacio` desde cualquier app, o con `aura switcher`. Tiene tres estilos (panal, cinemático y clásico) y se maneja con las flechas, Enter y Esc.

### Terminal

```text
aura                      Abre la ventana
aura next | prev          Siguiente / anterior
aura toggle-pause         Pausa o reanuda
aura apply <archivo> [pantalla]
aura stop
aura switcher
aura volume 0-100 | aura mute
aura mode auto|dark|light|manual
aura status [--json]
aura displays
aura quit
```

Para asignar `aura next` a una combinación de teclas, crea un atajo en la app **Atajos** con la acción "Ejecutar script de shell".

## Qué cambia respecto al original

| Original (Linux / COSMIC) | En macOS |
|---|---|
| `mpvpaper` sobre Wayland layer-shell | Ventana a nivel de escritorio con `AVPlayerLayer`, una por pantalla |
| VA-API / NVDEC | VideoToolbox (decodificación por hardware automática) |
| Pausa con `SIGSTOP` al jugar | Pausa del reproductor con apps a pantalla completa o ventanas encima (por pantalla) |
| UPower por D-Bus | IOKit (batería) + modo de bajo consumo |
| Feral GameMode | No existe en macOS; lo cubre la pausa a pantalla completa |
| Bandeja StatusNotifierItem | Ícono en la barra de menú |
| Instancia única por D-Bus | Notificaciones distribuidas de macOS |
| Acento y modo de COSMIC | Modo claro/oscuro de macOS; el acento es aproximado (macOS solo tiene 8 colores) |
| — | Fotograma del fondo como fondo de macOS (Mission Control, pantalla de bloqueo) |
| WebM / MKV con mpv | Conversión única a HEVC con ffmpeg (AVFoundation no lee esos formatos) |
| Actualización desde GitHub Releases | No incluida: este port se compila localmente |

Los fondos animados se ven en todos los escritorios (Spaces). En los espacios de apps a pantalla completa no se dibujan, así que ahí el video queda en pausa y no gasta GPU.

## Solución de problemas

- **"Aura" no se puede abrir porque es de un desarrollador no identificado:** no debería pasar si la compilaste tú. Si copiaste la app desde otro Mac, haz clic derecho → Abrir.
- **El fondo no se mueve:** revisa en el menú si dice "En pausa" y por qué (batería, bajo consumo, ventanas encima). Puedes ajustar la sensibilidad en Ajustes → Rendimiento.
- **Un video .webm no se reproduce:** instala ffmpeg (`brew install ffmpeg`) y vuelve a aplicarlo. La primera vez tarda un poco porque lo convierte.
- **Recuperar tu fondo de antes:** Ajustes → Apariencia → "Restaurar el fondo original de macOS".

## Desinstalar

```bash
brew uninstall aura-macos       # si la instalaste con Homebrew
./scripts/uninstall.sh          # si la instalaste desde el código (pregunta si borrar la configuración)
./scripts/uninstall.sh --purge  # borra configuración y caché sin preguntar
./scripts/uninstall.sh --keep   # las conserva sin preguntar
```

Tus fondos descargados en `~/Pictures/Wallpapers/Aura` no se tocan. El fondo de macOS tampoco cambia: queda con el último fotograma que puso Aura, guardado en `~/Pictures/Wallpapers/Aura/.system-frames`.

## Estructura

```text
Sources/AuraCore   Lógica sin interfaz: configuración, catálogos, paleta, IPC
Sources/Aura       App: motor de fondos, pausa, barra de menú, selector, SwiftUI
Sources/aura-cli   Comando `aura`
Tests              Pruebas del núcleo con Swift Testing (./scripts/test.sh; no requiere Xcode)
scripts            build.sh, test.sh, install.sh, uninstall.sh, make-formula.sh
homebrew           Plantilla de la fórmula de Homebrew
```

La configuración se guarda en `~/Library/Application Support/Aura/config.json` y la caché en `~/Library/Caches/Aura`.

## Publicar una versión en Homebrew

Esto es para quien mantiene el fork. Homebrew instala desde un *tap*, que es un repositorio de GitHub llamado `homebrew-aura` con la fórmula adentro.

1. Crea el tap una sola vez: un repositorio público `homebrew-aura` en tu cuenta, con una carpeta `Formula/`.
2. Sube la versión al fork con un tag:
   ```bash
   git tag macos-v1.0.0 && git push origin macos-v1.0.0
   ```
3. Genera la fórmula con el checksum de ese tag:
   ```bash
   ./scripts/make-formula.sh 1.0.0
   ```
4. Copia `homebrew/Formula/aura-macos.rb` al tap, haz commit y súbelo.

Para cada versión nueva, sube `CFBundleShortVersionString` en `Resources/Info.plist` y `AuraConfig.currentVersion`, y repite los pasos 2 a 4.

## Créditos y licencia

Basado en [Aura](https://github.com/antwny/aura) de **Antwny** ([YouTube](https://www.youtube.com/@antwny)): diseño, catálogos, lógica de paleta y comandos. El ícono es el del proyecto original.

Se distribuye bajo **GPL-3.0-or-later**, igual que el original (ver `LICENSE`).

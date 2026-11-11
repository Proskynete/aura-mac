# Aura para macOS

> **Fork no oficial de [antwny/aura](https://github.com/antwny/aura).** Aura fue creada por **Antwny** para Linux (COSMIC); este repositorio nació como su versión para macOS y reemplaza aquel código por una implementación nativa en Swift. El historial de git conserva el proyecto original. Todo el mérito del diseño es de su autor: si usas Linux, usa el [proyecto original](https://github.com/antwny/aura). En [`NOTICE.md`](NOTICE.md) está el detalle de qué cambió.

Port nativo para macOS de Aura, el gestor de fondos animados para el escritorio COSMIC de Pop!_OS. Está reescrito en Swift con AVFoundation, AppKit y SwiftUI. No usa Wayland, mpv ni D-Bus: cada pieza se reemplazó por su equivalente de Apple.

Las herramientas de línea de comandos de Xcode bastan para compilarlo: no necesitas Xcode completo.

## Requisitos

- macOS 14 Sonoma o superior (Apple Silicon o Intel).
- Herramientas de línea de comandos de Xcode: `xcode-select --install`. Xcode completo no es necesario.
- Opcional: `brew install ffmpeg`, solo para reproducir videos WebM, MKV o AVI.

## Instalar

### Con Homebrew (recomendado)

```bash
brew install --cask proskynete/aura/aura
```

Instala `Aura.app` en `/Applications` y el comando `aura`. Para actualizar, usa `brew upgrade --cask aura`.

Aura todavía no está firmada con un certificado de Apple, así que la primera vez que la abras macOS la bloqueará. Para permitirla, ve a **Ajustes del Sistema → Privacidad y seguridad → "Abrir igualmente"**. También puedes hacerlo desde la terminal:

```bash
xattr -dr com.apple.quarantine /Applications/Aura.app
```

### Con Homebrew, compilando en tu Mac

```bash
brew install proskynete/aura/aura-macos
```

Homebrew compila la app en tu Mac, así que no hay avisos de Gatekeeper, pero tarda unos minutos y necesita las herramientas de línea de comandos de Xcode. Al terminar te muestra cómo agregarla a Launchpad y cómo hacer que se abra al iniciar sesión (`brew services start aura-macos`). Para actualizar, usa `brew upgrade aura-macos`. No se puede tener a la vez con el cask.

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
brew uninstall --cask aura      # si la instalaste con el cask
brew uninstall --zap --cask aura  # además borra configuración y caché
brew uninstall aura-macos       # si la compilaste con Homebrew
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
scripts            build.sh, test.sh, install.sh, uninstall.sh, render-homebrew.sh
homebrew           Plantillas del cask y de la fórmula de Homebrew
```

La configuración se guarda en `~/Library/Application Support/Aura/config.json` y la caché en `~/Library/Caches/Aura`.

## Publicar una versión en Homebrew

Esto es para quien mantiene el proyecto. Homebrew instala desde un *tap*: el repositorio público [`Proskynete/homebrew-aura`](https://github.com/Proskynete/homebrew-aura), que contiene el cask (`Casks/aura.rb`) y la fórmula (`Formula/aura-macos.rb`). No hace falta ninguna cuenta en Homebrew.

Para publicar una versión:

1. Sube la versión en `Resources/Info.plist` (`CFBundleShortVersionString` y `CFBundleVersion`) y en `AuraConfig.currentVersion`, y agrega la entrada en `CHANGELOG.md`. Haz merge a `main`.
2. Crea y sube el tag desde `main`:
   ```bash
   git tag v1.1.0 && git push origin v1.1.0
   ```

El workflow `Release (macOS)` hace el resto:
- comprueba que el tag coincida con la versión de la app;
- corre las pruebas;
- compila la app universal (Apple Silicon e Intel);
- publica `Aura-1.1.0.zip` en un GitHub Release;
- actualiza el cask y la fórmula en el tap.

Para escribir en el tap, el workflow usa una deploy key guardada en el secret `HOMEBREW_TAP_DEPLOY_KEY`.

Si algún día se firma con un certificado de Apple (Apple Developer Program), basta con agregar estos secrets y el workflow firma y notariza solo:
- `MACOS_CERTIFICATE_P12`: el certificado *Developer ID Application* en base64;
- `MACOS_CERTIFICATE_PASSWORD`;
- `MACOS_SIGNING_IDENTITY`;
- `APPLE_ID`;
- `APPLE_TEAM_ID`;
- `APPLE_APP_PASSWORD`: una contraseña de app.

Con la app firmada se puede quitar el aviso de Gatekeeper del cask y del README.

## Créditos y licencia

Basado en [Aura](https://github.com/antwny/aura) de **Antwny** ([YouTube](https://www.youtube.com/@antwny)): diseño, catálogos, lógica de paleta y comandos. El ícono es el del proyecto original.

Se distribuye bajo **GPL-3.0-or-later**, igual que el original (ver `LICENSE`).
